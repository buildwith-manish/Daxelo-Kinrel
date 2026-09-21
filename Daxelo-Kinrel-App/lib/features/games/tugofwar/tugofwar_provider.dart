// lib/features/games/tugofwar/tugofwar_provider.dart
//
// Tug of War — Riverpod state + Supabase Realtime + host-authoritative rope.
//
// Architecture (perf/smoothness-pass-2 Step 1 — migrated from per-batch
// DB-pull RPC to Realtime Broadcast, mirroring the stickman_heist
// pattern from commit aa46b5a9):
//
//   • Supabase stores the game row (roster, winner, endReason) and the
//     per-player row (team, validated pullCount, ready state). These
//     rows are written ONLY on lifecycle events (create/join/start/
//     leave/complete) — NOT on every tap batch.
//
//   • HOT PATH (active play, pure websocket — NO DB):
//       NON-HOST clients:
//         • Tap batches accumulate locally; every 400 ms the local
//           batch is sent via `channel.sendBroadcastMessage(event:
//           'tap_batch', payload: {userId, taps})` — pure websocket.
//         • Receive authoritative rope state via
//           `onBroadcast(event: 'rope_state')` every 150 ms.
//         • On subscribe, send `request_state` to get an instant
//           snapshot from the host (no waiting up to 150 ms for the
//           next periodic broadcast).
//       HOST client:
//         • Receives non-host tap batches via
//           `onBroadcast(event: 'tap_batch')` and accumulates per-
//           player pullCount locally.
//         • Every 150 ms (matching the SQL's previous 6 Hz cadence),
//           computes the authoritative rope position using the SAME
//           fairness formula (avgA - avgB) / 30 and broadcasts it via
//           `sendBroadcastMessage(event: 'rope_state', payload:
//           {rope, teamATaps, teamBTaps, players: [...]})`.
//         • Host's own taps are applied directly to the local
//           accumulator (no network round-trip).
//         • Responds to `request_state` handshake with a one-time
//           snapshot for spectators / reconnecting players.
//
//   • DURABLE DB calls (event-driven, one per match):
//       • createGame / joinGame / leaveGame (one-time per player).
//       • startMatch / fn_tugofwar_start (one-time per match).
//       • MATCH COMPLETION: ONE call to fn_tugofwar_persist_match
//         (host only) — persists per-player pullCount + final rope +
//         winner + endReason. The ONLY DB write in the hot path; one
//         call per match, not 10/sec.
//
//   • Watchdog: the 2s _watchdogTimer is left alone per the user's
//     instruction ("local sanity-check timer — leave it alone"). It
//     still calls fn_tugofwar_tick every 2s during a timed match so
//     an expired match ends even if the host disconnects. Edge case:
//     under the new architecture, tugofwar_players.pullCount is only
//     updated by fn_tugofwar_persist_match at match end — so if the
//     host disconnects BEFORE persisting, the watchdog will compute
//     a 0-0 draw. This is the same trade-off stickman_heist made
//     (host disconnect → match can't complete authoritatively).
//
//   • Anti-cheat: the previous fn_tugofwar_pull RPC enforced a
//     15 taps/sec cap per player server-side. The new architecture
//     trusts the host as the authority (host is elected by the
//     family). Each client could in theory inflate its own broadcast
//     count, but the host applies a local 15 taps/sec cap per
//     player before accumulating — same effective cap, just enforced
//     by the host instead of the DB. The fn_tugofwar_pull RPC is
//     retained for backward compatibility but is no longer called
//     in the hot path.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../game_motion_tokens.dart';
import '../shared/data/game_invite_chat_sync.dart';
import '../shared/services/temporary_room_service.dart';
import 'tugofwar_models.dart';

/// How often the local tap buffer is broadcast to the host via Realtime
/// Broadcast (pure websocket, no DB). Was 400ms for the DB-pull path;
/// kept the same for the Broadcast path — tap responsiveness unchanged.
const Duration kPullBatchWindow = Duration(milliseconds: 400);

/// How often the HOST recomputes the authoritative rope position and
/// broadcasts it to all clients. Matches the SQL's previous 6 Hz
/// throttle (every 150ms inside fn_tugofwar_pull).
const Duration kRopeBroadcastInterval = Duration(milliseconds: 150);

/// Local anti-cheat cap: each client enforces 15 taps/sec + 10 burst
/// budget on its OWN count before broadcasting (mirrors the server-side
/// cap previously enforced by fn_tugofwar_pull). The host additionally
/// re-checks received counts against this cap before accumulating.
const int _kTapsPerSecCap = 15;
const int _kTapsBurstBudget = 10;

class TugOfWarState {
  const TugOfWarState({
    this.game,
    this.players = const [],
    this.isLoading = false,
    this.isStarting = false,
    this.isLeaving = false,
    this.error,
    this.amSpectator = false,
    this.myLocalTaps = 0,
    this.rateLimitedUntil,
    /// Broadcast-authoritative rope position (live, host-broadcast).
    /// This is the value the rope controller should render. It mirrors
    /// game.ropePosition once a match completes (the durable final value).
    this.broadcastRope,
    this.broadcastTeamATaps = 0,
    this.broadcastTeamBTaps = 0,
  });

  final TugOfWarGame? game;
  final List<TugOfWarPlayer> players;
  final bool isLoading;
  final bool isStarting;
  final bool isLeaving;
  final String? error;
  final bool amSpectator;

  /// Optimistic local tap counter (instant PULL feedback). The host's
  /// authoritative count for me arrives via Broadcast (as part of the
  /// rope_state payload) and is mirrored into the matching player row.
  final int myLocalTaps;

  /// While set, the host is rejecting part of our taps (15/sec cap).
  final DateTime? rateLimitedUntil;

  /// Latest broadcast rope position from the host (-1 .. +1). Updated
  /// every 150 ms during active play (pure websocket). Null before the
  /// first rope_state event arrives (or for spectators before they send
  /// `request_state`). The `game.ropePosition` field is still updated
  /// via Postgres Changes for the durable final value at match end.
  final double? broadcastRope;

  /// Latest broadcast team-A tap total (sum of all Team A players'
  /// pullCounts). Mirrors `game.teamATaps` once the match completes.
  final int broadcastTeamATaps;

  /// Latest broadcast team-B tap total.
  final int broadcastTeamBTaps;

  bool get isWaiting => game?.isWaiting ?? false;
  bool get isInProgress => game?.isInProgress ?? false;
  bool get isCompleted => game?.isCompleted ?? false;
  bool get hasGame => game != null;

  bool get isRateLimited =>
      rateLimitedUntil != null && DateTime.now().isBefore(rateLimitedUntil!);

  TugOfWarPlayer? playerFor(String? userId) {
    if (userId == null) return null;
    for (final p in players) {
      if (p.userId == userId) return p;
    }
    return null;
  }

  TugTeam? teamFor(String? userId) => playerFor(userId)?.team;

  List<TugOfWarPlayer> teamRoster(TugTeam team) =>
      players.where((p) => p.team == team).toList();

  TugTeamStats teamStats(TugTeam team) {
    final roster = teamRoster(team);
    return TugTeamStats(
      players: roster,
      totalTaps: roster.fold<int>(0, (sum, p) => sum + p.pullCount),
    );
  }

  bool get teamsUneven {
    final a = teamRoster(TugTeam.a).length;
    final b = teamRoster(TugTeam.b).length;
    return a != b;
  }

  bool get canStart {
    if (game == null) return false;
    return teamRoster(TugTeam.a).isNotEmpty &&
        teamRoster(TugTeam.b).isNotEmpty;
  }

  /// Effective rope position: prefer the live broadcast value during
  /// active play (low-latency), fall back to the durable game.ropePosition
  /// for the final value after match completion.
  double get effectiveRope => broadcastRope ?? game?.ropePosition ?? 0.0;

  /// Effective team A taps: prefer the live broadcast total during
  /// active play, fall back to game.teamATaps.
  int get effectiveTeamATaps =>
      broadcastTeamATaps > 0 ? broadcastTeamATaps : (game?.teamATaps ?? 0);

  /// Effective team B taps.
  int get effectiveTeamBTaps =>
      broadcastTeamBTaps > 0 ? broadcastTeamBTaps : (game?.teamBTaps ?? 0);

  TugOfWarState copyWith({
    TugOfWarGame? game,
    List<TugOfWarPlayer>? players,
    bool? isLoading,
    bool? isStarting,
    bool? isLeaving,
    bool clearError = false,
    String? error,
    bool? amSpectator,
    int? myLocalTaps,
    bool resetLocalTaps = false,
    DateTime? rateLimitedUntil,
    bool clearRateLimit = false,
    double? broadcastRope,
    int? broadcastTeamATaps,
    int? broadcastTeamBTaps,
  }) =>
      TugOfWarState(
        game: game ?? this.game,
        players: players ?? this.players,
        isLoading: isLoading ?? this.isLoading,
        isStarting: isStarting ?? this.isStarting,
        isLeaving: isLeaving ?? this.isLeaving,
        error: clearError ? null : (error ?? this.error),
        amSpectator: amSpectator ?? this.amSpectator,
        myLocalTaps: resetLocalTaps ? 0 : (myLocalTaps ?? this.myLocalTaps),
        rateLimitedUntil:
            clearRateLimit ? null : (rateLimitedUntil ?? this.rateLimitedUntil),
        broadcastRope: broadcastRope ?? this.broadcastRope,
        broadcastTeamATaps: broadcastTeamATaps ?? this.broadcastTeamATaps,
        broadcastTeamBTaps: broadcastTeamBTaps ?? this.broadcastTeamBTaps,
      );
}

class TugOfWarNotifier extends StateNotifier<TugOfWarState> {
  TugOfWarNotifier(this._ref, this.familyId) : super(const TugOfWarState()) {
    _batchTimer = Timer.periodic(kPullBatchWindow, (_) => _broadcastTaps());
    _ropeBroadcastTimer =
        Timer.periodic(kRopeBroadcastInterval, (_) => _broadcastRopeState());
  }

  final Ref _ref;
  final String familyId;

  SupabaseClient? get _client => _ref.read(supabaseProvider);
  String? get _myId => _client?.auth.currentUser?.id;
  String get _myName =>
      _client?.auth.currentUser?.userMetadata?['name'] as String? ?? 'Player';

  RealtimeChannel? _channel;
  String? _gameId;
  Timer? _watchdogTimer;
  Timer? _cleanupTimer;
  late final Timer _batchTimer;
  late final Timer _ropeBroadcastTimer;

  /// Local tap buffer for THIS client (the host's own taps if I'm the
  /// host, my own taps if I'm a non-host). Flushed every 400 ms via
  /// `sendBroadcastMessage(event: 'tap_batch', ...)`.
  int _pendingTaps = 0;

  /// True while a tap-batch broadcast is in-flight (prevents overlapping
  /// sends if the 400 ms tick fires faster than the network can deliver).
  bool _broadcastInFlight = false;

  /// Host-only: per-player authoritative pullCount accumulator. Updated
  /// from received `tap_batch` broadcasts AND from the host's own local
  /// `_pendingTaps` flush.
  /// Keyed by userId. Only players on a team (A or B) are tracked.
  final Map<String, int> _authoritativePullCounts = {};

  /// Host-only: timestamp the match started (for the 15 taps/sec cap).
  DateTime? _matchStartTime;

  /// Host-only: latest computed rope position. Broadcast every 150 ms.
  double _currentRope = 0.0;

  /// Cold-start retries (kept from the original — same purpose).
  int _loadRetries = 0;

  /// True iff this client is the host of the current game. Set in
  /// `_applyGameRow` from `game.hostUserId == _myId`.
  bool get _isHost {
    final game = state.game;
    if (game == null) return false;
    return game.hostUserId == _myId;
  }

  // ── Public API ───────────────────────────────────────────────────

  /// Host: create a new room with the chosen settings.
  Future<String?> createGame({
    required int matchDurationSec,
    required int maxPlayers,
    required TugOfWarTeamMode teamMode,
    String? roomName,
    bool spectatorsEnabled = true,
  }) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) {
      state = state.copyWith(error: 'Not signed in');
      return null;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final body = <String, dynamic>{
        'familyId': familyId,
        'hostUserId': myId,
        'hostUserName': _myName,
        'status': 'waiting',
        'teamMode': teamMode.wire,
        'matchDurationSec': matchDurationSec,
        'maxPlayers': maxPlayers,
        'spectatorsEnabled': spectatorsEnabled,
        'autoCloseDeadline':
            DateTime.now().add(const Duration(minutes: 5)).toIso8601String(),
        if (roomName != null && roomName.trim().isNotEmpty)
          'roomName': roomName.trim(),
      };
      final resp =
          await client.from('tugofwar_games').insert(body).select().single();
      final game = TugOfWarGame.fromJson(resp);
      _gameId = game.id;

      await client.from('tugofwar_players').insert({
        'gameId': game.id,
        'userId': myId,
        'userName': _myName,
      });

      // Register in the shared room bookkeeping so the ecosystem archive
      // sees this participant (same path RoomController uses).
      await client.rpc('fn_record_room_join', params: {
        'p_game_table': 'tugofwar_games',
        'p_game_id': game.id,
        'p_family_id': familyId,
        'p_user_id': myId,
        'p_user_name': _myName,
        'p_role': 'host',
      });

      state = state.copyWith(game: game, isLoading: false);
      _subscribeToRealtime(game.id);
      await _refreshPlayers(game.id);
      return game.id;
    } catch (e) {
      debugPrint('[TugOfWar] createGame error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
      return null;
    }
  }

  /// Join an existing room. Falls back to spectating once the match is
  /// already running (spectator mode is part of the game's design).
  Future<bool> joinGame(String gameId) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) {
      state = state.copyWith(error: 'Not signed in');
      return false;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final gameResp = await client
          .from('tugofwar_games')
          .select()
          .eq('id', gameId)
          .maybeSingle();
      if (isRoomRowClosed(gameResp)) {
        state = state.copyWith(isLoading: false, error: kRoomClosedMessage);
        return false;
      }
      final game = TugOfWarGame.fromJson(gameResp as Map<String, dynamic>);
      _gameId = game.id;

      final playersResp = await client
          .from('tugofwar_players')
          .select()
          .eq('gameId', gameId)
          .order('joinedAt', ascending: true);
      final existing = playersResp
          .map((p) => TugOfWarPlayer.fromJson(p))
          .toList();
      final alreadyJoined = existing.any((p) => p.userId == myId);

      if (!alreadyJoined && game.isWaiting) {
        if (existing.length >= game.maxPlayers) {
          state = state.copyWith(isLoading: false, error: 'Game is full');
          return false;
        }
        await client.from('tugofwar_players').upsert({
          'gameId': gameId,
          'userId': myId,
          'userName': _myName,
        }, onConflict: 'gameId,userId');
        await client.rpc('fn_record_room_join', params: {
          'p_game_table': 'tugofwar_games',
          'p_game_id': gameId,
          'p_family_id': familyId,
          'p_user_id': myId,
          'p_user_name': _myName,
          'p_role': 'player',
        });
        await _ref.read(temporaryRoomServiceProvider).touchActivity(
              gameTable: 'tugofwar_games',
              gameId: gameId,
            );
        // Teams are assigned automatically by the database trigger
        // trg_tugofwar_assign_team_on_join (alternate A/B in join order) —
        // no client-side RPC needed, and the assignment is visible the
        // moment the player lands in the lobby.
      } else if (!alreadyJoined) {
        // Match already running — watch from the sidelines.
        await _spectate(gameId);
      }

      state = state.copyWith(game: game, isLoading: false);
      _subscribeToRealtime(gameId);
      await _refreshPlayers(gameId);
      unawaited(
        syncGameInviteChatCards(
          client: client,
          gameId: gameId,
          currentPlayers: state.players.length,
        ),
      );
      return true;
    } catch (e) {
      debugPrint('[TugOfWar] joinGame error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
      return false;
    }
  }

  /// Spectate a room (read-only + emoji reactions).
  Future<void> spectate(String gameId) async {
    await _spectate(gameId);
    await _loadGame(gameId);
    await _refreshPlayers(gameId);
    _subscribeToRealtime(gameId);
  }

  Future<void> _spectate(String gameId) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) return;
    _gameId = gameId;
    state = state.copyWith(amSpectator: true);
    try {
      await client.rpc('fn_spectate_game', params: {
        'p_game_table': 'tugofwar_games',
        'p_game_id': gameId,
        'p_family_id': familyId,
        'p_user_id': myId,
        'p_user_name': _myName,
      });
    } catch (e) {
      debugPrint('[TugOfWar] spectate error: $e');
    }
  }

  // NOTE: setTeam()/assignTeams() were removed — teams are now assigned
  // automatically by the trg_tugofwar_assign_team_on_join database
  // trigger (alternating A/B in join order) the moment a player joins.

  /// Toggle the ready flag in the waiting lobby.
  Future<void> toggleReady(bool isReady) async {
    final gameId = _gameId;
    if (gameId == null) return;
    await _ref.read(temporaryRoomServiceProvider).toggleReady(
          gameTable: 'tugofwar_games',
          gameId: gameId,
          isReady: isReady,
        );
    final myId = _myId;
    if (myId != null) {
      final next = state.players
          .map((p) => p.userId == myId ? p.copyWith(isReady: isReady) : p)
          .toList();
      state = state.copyWith(players: next);
    }
  }

  /// Host: start the match. The RPC validates both teams are non-empty;
  /// [force] lets the host push through an "uneven teams" warning.
  Future<String?> startMatch({bool force = false}) async {
    final gameId = _gameId;
    if (gameId == null) return null;
    if (!state.canStart) return 'Each team needs at least one player';
    if (!force && state.game?.teamMode == TugOfWarTeamMode.manual &&
        state.teamsUneven) {
      return 'uneven';
    }
    state = state.copyWith(isStarting: true, clearError: true);
    try {
      final client = _client;
      if (client == null) return null;
      final result = await client.rpc('fn_tugofwar_start', params: {
        'p_game_id': gameId,
      });
      final map = (result is Map<String, dynamic>)
          ? result
          : Map<String, dynamic>.from(result as Map);
      state = state.copyWith(isStarting: false);
      if (map['ok'] == true) {
        GameMotionTokens.celebrate();
        // Host initializes the authoritative accumulator when the match
        // starts. Non-hosts will receive the rope_state broadcasts.
        if (_isHost) {
          _matchStartTime = DateTime.now();
          _authoritativePullCounts.clear();
          _currentRope = 0.0;
          for (final p in state.players) {
            if (p.team != null) {
              _authoritativePullCounts[p.userId] = 0;
            }
          }
        }
        return null;
      }
      return switch (map['reason']) {
        'empty_team' => 'Each team needs at least one player',
        'not_host' => 'Only the host can start',
        'already_started' => null,
        _ => 'Could not start the match',
      };
    } catch (e) {
      debugPrint('[TugOfWar] startMatch error: $e');
      state = state.copyWith(isStarting: false, error: '$e');
      return 'Could not start the match';
    }
  }

  /// PULL! Called on every tap of the big button. Registers locally at
  /// once (instant haptics + rope impulse) and batches for broadcast.
  ///
  /// Step 1 (broadcast migration): the local cap is now enforced here
  /// (15 taps/sec + 10 burst budget, mirroring the previous server-side
  /// cap in fn_tugofwar_pull). If the local cap rejects the tap, we
  /// set rateLimitedUntil to show the "steady!" hint.
  void pull() {
    if (!state.isInProgress || state.amSpectator) return;
    final myId = _myId;
    if (myId == null) return;
    if (state.playerFor(myId)?.team == null) return;

    // Local anti-cheat: 15 taps/sec + 10 burst budget since match start.
    // Same formula as fn_tugofwar_pull (line 381-383 of the migration).
    if (_matchStartTime != null) {
      final elapsed = DateTime.now().difference(_matchStartTime!).inMilliseconds /
          1000.0;
      final cap = (elapsed * _kTapsPerSecCap).floor() + _kTapsBurstBudget;
      final myCurrentAuthoritative =
          _isHost ? (_authoritativePullCounts[myId] ?? 0) : state.myLocalTaps;
      if (myCurrentAuthoritative >= cap) {
        // Rate-limited — show "steady!" hint for 900 ms.
        state = state.copyWith(
          rateLimitedUntil:
              DateTime.now().add(const Duration(milliseconds: 900)),
        );
        return;
      }
    }

    _pendingTaps += 1;
    state = state.copyWith(myLocalTaps: state.myLocalTaps + 1);

    // If I'm the host, apply my own taps directly to the authoritative
    // accumulator (no network round-trip). The 400 ms _broadcastTaps
    // timer will also broadcast my taps to spectators / late-joiners,
    // but the rope state is computed from the live accumulator.
    if (_isHost) {
      _authoritativePullCounts[myId] =
          (_authoritativePullCounts[myId] ?? 0) + 1;
    }
  }

  /// Non-host: send my local tap batch to the host via Realtime Broadcast
  /// (pure websocket, NO DB). Host: also broadcasts own taps so spectators
  /// can see them. Called every kPullBatchWindow (400 ms) by _batchTimer.
  ///
  /// If the match has ended (game == null or game.isCompleted or
  /// game.isWaiting), the pending taps are silently dropped — the host
  /// won't accept them and we don't want to leak them when the next match
  /// starts.
  void _broadcastTaps() {
    if (_broadcastInFlight) return;
    final gameId = _gameId;
    final channel = _channel;
    final myId = _myId;
    if (gameId == null || channel == null || myId == null) {
      _pendingTaps = 0;
      return;
    }
    // Only broadcast during active play.
    if (!state.isInProgress) {
      _pendingTaps = 0;
      return;
    }
    final taps = _pendingTaps;
    if (taps <= 0) return;
    _pendingTaps = 0;
    _broadcastInFlight = true;
    try {
      unawaited(channel.sendBroadcastMessage(
        event: 'tap_batch',
        payload: {
          'userId': myId,
          'taps': taps,
          'ts': DateTime.now().toIso8601String(),
        },
      ));
    } catch (e) {
      debugPrint('[TugOfWar] broadcastTaps error: $e');
    } finally {
      _broadcastInFlight = false;
    }
  }

  /// Host-only: recompute the authoritative rope position from the
  /// per-player accumulator and broadcast it to all clients (including
  /// spectators) every kRopeBroadcastInterval (150 ms). Called by
  /// _ropeBroadcastTimer.
  ///
  /// On match completion (rope crosses ±1.0 OR host detects time-up),
  /// makes ONE durable RPC to fn_tugofwar_persist_match to persist
  /// the final result.
  Future<void> _broadcastRopeState() async {
    if (!_isHost) return;
    final gameId = _gameId;
    final channel = _channel;
    final client = _client;
    if (gameId == null || channel == null || client == null) return;
    if (!state.isInProgress) return;

    // 1. Compute team totals + averages from the authoritative accumulator.
    int sumA = 0, sumB = 0, nA = 0, nB = 0;
    for (final p in state.players) {
      if (p.team == null) continue;
      final count = _authoritativePullCounts[p.userId] ?? p.pullCount;
      if (p.team == TugTeam.a) {
        sumA += count;
        nA++;
      } else {
        sumB += count;
        nB++;
      }
    }
    final avgA = nA == 0 ? 0.0 : sumA / nA;
    final avgB = nB == 0 ? 0.0 : sumB / nB;

    // 2. FAIRNESS: normalized per-player averages, not raw team totals.
    // Same formula as fn_tugofwar_pull (line 404 of the migration).
    final rope = ((avgA - avgB) / 30.0).clamp(-1.0, 1.0);
    _currentRope = rope;

    // 3. Update the broadcast state (live, for the rope controller + UI).
    state = state.copyWith(
      broadcastRope: rope,
      broadcastTeamATaps: sumA,
      broadcastTeamBTaps: sumB,
      // Mirror the authoritative pullCounts back into the player rows so
      // team stats / leaderboards render the live counts during play.
      players: state.players.map((p) {
        if (p.team == null) return p;
        final live = _authoritativePullCounts[p.userId];
        if (live == null || live == p.pullCount) return p;
        return p.copyWith(pullCount: live);
      }).toList(),
    );

    // 4. Broadcast the rope state to all clients (pure websocket).
    try {
      unawaited(channel.sendBroadcastMessage(
        event: 'rope_state',
        payload: {
          'rope': rope,
          'teamATaps': sumA,
          'teamBTaps': sumB,
          'players': state.players
              .where((p) => p.team != null)
              .map((p) => {
                    'userId': p.userId,
                    'pullCount': _authoritativePullCounts[p.userId] ?? p.pullCount,
                  })
              .toList(),
          'ts': DateTime.now().toIso8601String(),
        },
      ));
    } catch (e) {
      debugPrint('[TugOfWar] broadcastRopeState (ws) error: $e');
    }

    // 5. Check match-completion conditions:
    //    a) rope crossed ±1.0 → victory_line
    //    b) timed match + time expired → time_up
    String? endReason;
    String? winnerTeam;
    if (rope >= 1.0 && nA > 0 && nB > 0) {
      endReason = 'victory_line';
      winnerTeam = 'A';
    } else if (rope <= -1.0 && nA > 0 && nB > 0) {
      endReason = 'victory_line';
      winnerTeam = 'B';
    } else {
      final game = state.game;
      if (game != null && game.hasTimer && game.endsAt != null) {
        if (DateTime.now().isAfter(game.endsAt!)) {
          endReason = 'time_up';
          if (avgA > avgB) {
            winnerTeam = 'A';
          } else if (avgB > avgA) {
            winnerTeam = 'B';
          } else {
            winnerTeam = null; // draw
          }
        }
      }
    }

    if (endReason == null) return;

    // 6. ONE durable RPC to persist the final result. This is the ONLY
    //    DB write in the hot path — one call per match, not 10/sec.
    await _persistMatchFinal(
      gameId: gameId,
      client: client,
      rope: rope,
      endReason: endReason,
      winnerTeam: winnerTeam,
    );
  }

  /// Host-only: ONE durable RPC to persist the match final result.
  /// Calls fn_tugofwar_persist_match (added in migration
  /// 20260922100000_tugofwar_broadcast_persist.sql).
  Future<void> _persistMatchFinal({
    required String gameId,
    required SupabaseClient client,
    required double rope,
    required String endReason,
    required String? winnerTeam,
  }) async {
    try {
      final pullCountsJson = <String, dynamic>{};
      for (final entry in _authoritativePullCounts.entries) {
        pullCountsJson[entry.key] = entry.value;
      }
      await client.rpc('fn_tugofwar_persist_match', params: {
        'p_game_id': gameId,
        'p_pull_counts': pullCountsJson,
        'p_final_rope': rope,
        'p_end_reason': endReason,
        'p_winner_team': winnerTeam ?? '',
      });
    } catch (e) {
      debugPrint('[TugOfWar] persistMatchFinal error: $e');
    }
  }

  /// Leave the game. Host in the waiting room closes the whole room
  /// (shared temporary-room semantics, same as Ludo).
  Future<void> leaveGame() async {
    final client = _client;
    final gameId = _gameId;
    final myId = _myId;
    final game = state.game;
    if (client == null || gameId == null || myId == null) {
      _cleanup();
      return;
    }
    state = state.copyWith(isLeaving: true);
    try {
      if (game != null && game.isWaiting && game.hostUserId == myId) {
        await _ref.read(temporaryRoomServiceProvider).cancelWaitingRoom(
              gameTable: 'tugofwar_games',
              gameId: gameId,
            );
      } else if (state.amSpectator) {
        await client.rpc('fn_leave_spectator', params: {
          'p_game_table': 'tugofwar_games',
          'p_game_id': gameId,
          'p_user_id': myId,
        });
      } else {
        await _tryRpc('fn_tugofwar_leave', {'p_game_id': gameId});
      }
    } catch (_) {}
    _cleanup();
  }

  /// Host: one-tap rematch. Creates a fresh room with the same settings,
  /// carries the roster over (same teams or reshuffled) and invites
  /// everyone back.
  Future<String?> rematch({required bool keepTeams}) async {
    final client = _client;
    final game = state.game;
    final myId = _myId;
    if (client == null || game == null || myId == null) return null;

    final roster = List<TugOfWarPlayer>.from(state.players);
    if (!keepTeams) {
      // Shuffle everyone, then deal alternate teams.
      roster.shuffle();
      for (var i = 0; i < roster.length; i++) {
        roster[i] =
            roster[i].copyWith(team: i.isEven ? TugTeam.a : TugTeam.b);
      }
    }

    final newGameId = await createGame(
      matchDurationSec: game.matchDurationSec,
      maxPlayers: game.maxPlayers,
      teamMode: game.teamMode,
      roomName: game.roomName,
      spectatorsEnabled: game.spectatorsEnabled,
    );
    if (newGameId == null) return null;

    try {
      // createGame inserts the host WITHOUT a team — restore the host's own
      // side from the previous match so "same teams" is truly the same.
      final myEntry = roster.where((p) => p.userId == myId).firstOrNull;
      if (myEntry?.team != null) {
        await client.from('tugofwar_players').update({
          'team': myEntry!.team!.wire,
        }).eq('gameId', newGameId).eq('userId', myId);
      }
      final others = roster.where((p) => p.userId != myId).toList();
      if (others.isNotEmpty) {
        await client.from('tugofwar_players').upsert(
          others
              .map((p) => {
                    'gameId': newGameId,
                    'userId': p.userId,
                    'userName': p.userName,
                    if (p.team != null) 'team': p.team!.wire,
                  })
              .toList(),
          onConflict: 'gameId,userId',
        );
        // Record them in the shared room bookkeeping too — joinGame skips
        // fn_record_room_join for players whose rows already exist, so
        // without this the ecosystem archive would miss rematch players.
        for (final p in others) {
          if (p.userId.isEmpty) continue;
          try {
            await client.rpc('fn_record_room_join', params: {
              'p_game_table': 'tugofwar_games',
              'p_game_id': newGameId,
              'p_family_id': familyId,
              'p_user_id': p.userId,
              'p_user_name': p.userName,
              'p_role': 'player',
            });
          } catch (_) {}
        }
      }
      // Fresh ids for the rematch invites.
      final roomCode =
          newGameId.replaceAll('-', '').substring(0, 6).toUpperCase();
      final invites = roster
          .where((p) => p.userId != myId && p.userId.isNotEmpty)
          .map((p) => {
                'gameTable': 'tugofwar_games',
                'gameId': newGameId,
                'gameType': 'tug-of-war',
                'familyId': familyId,
                'roomCode': roomCode,
                'invitedUserId': p.userId,
                'invitedByUserId': myId,
                'invitedByName': _myName,
                'maxPlayers': game.maxPlayers,
                'currentPlayers': 1,
                'message':
                    '$_myName wants a Tug of War rematch${keepTeams ? ' — same teams!' : ' — new teams!'}',
                'status': 'pending',
                'sourceGameId': game.id,
              })
          .toList();
      if (invites.isNotEmpty) {
        try {
          await client.from('game_invites').insert(invites);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[TugOfWar] rematch error: $e');
    }
    return newGameId;
  }

  // ── Data loading ─────────────────────────────────────────────────

  Future<void> loadGame(String gameId) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) {
      // Supabase/session not wired yet — retry with backoff instead of
      // silently bailing (reconnecting players depend on this path).
      if (_loadRetries < 6) {
        _loadRetries++;
        Future.delayed(const Duration(milliseconds: 900), () {
          if (mounted && state.game == null) loadGame(gameId);
        });
      }
      return;
    }
    _loadRetries = 0;
    await _loadGame(gameId);
    await _refreshPlayers(gameId);
    _subscribeToRealtime(gameId);
  }

  Future<void> _loadGame(String gameId) async {
    final client = _client;
    if (client == null) return;
    try {
      final resp = await client
          .from('tugofwar_games')
          .select()
          .eq('id', gameId)
          .maybeSingle();
      if (resp == null) return;
      _gameId = gameId;
      _applyGameRow(TugOfWarGame.fromJson(resp));
    } catch (e) {
      debugPrint('[TugOfWar] loadGame error: $e');
    }
  }

  void _applyGameRow(TugOfWarGame game) {
    final wasInProgress = state.game?.isInProgress ?? false;
    state = state.copyWith(game: game);

    // Watchdog: while a timed match runs, ping the server every 2 s so an
    // expired match ends even if both teams stop pulling. LEFT ALONE per
    // user instruction — local sanity-check timer, not a hot-path DB hit.
    if (game.isInProgress && game.hasTimer && _watchdogTimer == null) {
      _watchdogTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        _tryRpc('fn_tugofwar_tick', {'p_game_id': game.id});
      });
    } else if (!game.isInProgress && _watchdogTimer != null) {
      _watchdogTimer?.cancel();
      _watchdogTimer = null;
    }
    if (game.isInProgress && !wasInProgress) {
      state = state.copyWith(resetLocalTaps: true);
      // Host initializes the authoritative accumulator when the match
      // starts (also done in startMatch, but this path covers the case
      // where the host was already in the lobby and another client
      // triggered the start, OR the host is reconnecting mid-match).
      if (_isHost) {
        _matchStartTime = game.startedAt ?? DateTime.now();
        if (_authoritativePullCounts.isEmpty) {
          _currentRope = game.ropePosition;
          for (final p in state.players) {
            if (p.team != null) {
              _authoritativePullCounts[p.userId] = p.pullCount;
            }
          }
        }
      }
    }
    if (game.isCompleted && wasInProgress) {
      GameMotionTokens.celebrate();
      _scheduleRoomCleanup(game.id);
    }
  }

  Future<void> _refreshPlayers(String gameId) async {
    final client = _client;
    if (client == null) return;
    try {
      final resp = await client
          .from('tugofwar_players')
          .select()
          .eq('gameId', gameId)
          .order('joinedAt', ascending: true);
      final players = resp
          .map((p) => TugOfWarPlayer.fromJson(p))
          .toList();
      state = state.copyWith(players: players);
      // If I'm the host and the match is in progress, sync the
      // authoritative accumulator with the freshly-loaded roster.
      if (_isHost && state.isInProgress && _authoritativePullCounts.isEmpty) {
        for (final p in players) {
          if (p.team != null) {
            _authoritativePullCounts[p.userId] ??= p.pullCount;
          }
        }
      }
    } catch (e) {
      debugPrint('[TugOfWar] refreshPlayers error: $e');
    }
  }

  Future<bool> _tryRpc(String fn, Map<String, dynamic> params) async {
    final client = _client;
    if (client == null) return false;
    try {
      await client.rpc(fn, params: params);
      return true;
    } catch (e) {
      debugPrint('[TugOfWar] $fn error: $e');
      return false;
    }
  }

  void _scheduleRoomCleanup(String gameId) {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer(const Duration(seconds: 30), () {
      _ref.read(temporaryRoomServiceProvider).endGame(
            gameTable: 'tugofwar_games',
            gameId: gameId,
          );
    });
  }

  // ── Realtime subscription ────────────────────────────────────────

  void _subscribeToRealtime(String gameId) {
    _channel?.unsubscribe();
    final client = _client;
    if (client == null) return;

    _channel = client
        .channel('tugofwar_game:$gameId')
        // ── HOT-PATH BROADCAST LISTENERS (pure websocket, no DB) ──
        // These replace the previous 400 ms `fn_tugofwar_pull` RPC.
        .onBroadcast(
          event: 'tap_batch',
          callback: (payload) {
            // Host receives a non-host's tap batch. Accumulate locally.
            if (!_isHost) return;
            try {
              final map = Map<String, dynamic>.from(payload as Map);
              final userId = map['userId'] as String?;
              final taps = (map['taps'] as num?)?.toInt() ?? 0;
              if (userId == null || userId.isEmpty || taps <= 0) return;
              if (userId == _myId) return; // host's own taps already applied

              // Local anti-cheat: enforce the 15 taps/sec + 10 burst
              // cap per player before accumulating. Same formula as
              // fn_tugofwar_pull.
              final player = state.playerFor(userId);
              if (player?.team == null) return;
              if (_matchStartTime != null) {
                final elapsed = DateTime.now()
                        .difference(_matchStartTime!)
                        .inMilliseconds /
                    1000.0;
                final cap = (elapsed * _kTapsPerSecCap).floor() +
                    _kTapsBurstBudget;
                final current = _authoritativePullCounts[userId] ?? 0;
                final accepted = (taps).clamp(0, (cap - current).clamp(0, 1 << 30));
                if (accepted <= 0) return;
                _authoritativePullCounts[userId] = current + accepted;
              } else {
                _authoritativePullCounts[userId] =
                    (_authoritativePullCounts[userId] ?? 0) + taps;
              }
            } catch (e) {
              debugPrint('[TugOfWar] onBroadcast(tap_batch) parse error: $e');
            }
          },
        )
        .onBroadcast(
          event: 'rope_state',
          callback: (payload) {
            // Non-hosts + spectators receive the authoritative rope
            // state from the host. Host ignores — host owns the
            // canonical state.
            if (_isHost) return;
            try {
              final map = Map<String, dynamic>.from(payload as Map);
              final rope = (map['rope'] as num?)?.toDouble() ?? 0.0;
              final teamATaps = (map['teamATaps'] as num?)?.toInt() ?? 0;
              final teamBTaps = (map['teamBTaps'] as num?)?.toInt() ?? 0;
              final playersList = map['players'];
              // Mirror per-player pullCounts into state.players so the
              // team-stats / leaderboard UIs render live during play.
              List<TugOfWarPlayer>? updatedPlayers;
              if (playersList is List) {
                final byId = <String, int>{};
                for (final item in playersList) {
                  if (item is Map) {
                    final uid = item['userId'] as String?;
                    final cnt = (item['pullCount'] as num?)?.toInt();
                    if (uid != null && cnt != null) {
                      byId[uid] = cnt;
                    }
                  }
                }
                if (byId.isNotEmpty) {
                  updatedPlayers = state.players.map((p) {
                    final live = byId[p.userId];
                    if (live == null || live == p.pullCount) return p;
                    return p.copyWith(pullCount: live);
                  }).toList();
                }
              }
              state = state.copyWith(
                broadcastRope: rope.clamp(-1.0, 1.0),
                broadcastTeamATaps: teamATaps,
                broadcastTeamBTaps: teamBTaps,
                players: updatedPlayers ?? state.players,
              );
            } catch (e) {
              debugPrint('[TugOfWar] onBroadcast(rope_state) parse error: $e');
            }
          },
        )
        .onBroadcast(
          event: 'request_state',
          callback: (_) {
            // A spectator (or reconnecting player) joined and is asking
            // for a one-time snapshot of the current rope state so they
            // can render immediately instead of waiting up to 150 ms for
            // the next periodic broadcast. Only host responds.
            if (!_isHost) return;
            final channel = _channel;
            if (channel == null) return;
            try {
              // Reuse the same payload shape as _broadcastRopeState.
              int sumA = 0, sumB = 0;
              for (final p in state.players) {
                if (p.team == null) continue;
                final count = _authoritativePullCounts[p.userId] ?? p.pullCount;
                if (p.team == TugTeam.a) {
                  sumA += count;
                } else {
                  sumB += count;
                }
              }
              channel.sendBroadcastMessage(
                event: 'rope_state',
                payload: {
                  'rope': _currentRope,
                  'teamATaps': sumA,
                  'teamBTaps': sumB,
                  'players': state.players
                      .where((p) => p.team != null)
                      .map((p) => {
                            'userId': p.userId,
                            'pullCount':
                                _authoritativePullCounts[p.userId] ?? p.pullCount,
                          })
                      .toList(),
                  'ts': DateTime.now().toIso8601String(),
                },
              );
            } catch (e) {
              debugPrint('[TugOfWar] request_state response error: $e');
            }
          },
        )
        // ── DURABLE POSTGRES CHANGES LISTENERS ──
        // These remain on Postgres Changes because they describe
        // durable state changes that must survive disconnect/reload:
        //   • tugofwar_games UPDATE → status flip (waiting →
        //     in_progress → completed), winnerTeam, endReason
        //   • tugofwar_players INSERT/UPDATE/DELETE → lobby
        //     roster + ready state
        // These fire ~once per actual lifecycle event, not per frame.
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'tugofwar_games',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: gameId,
          ),
          callback: (payload) {
            final updated =
                TugOfWarGame.fromJson(payload.newRecord);
            _applyGameRow(updated);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'tugofwar_players',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: gameId,
          ),
          callback: (payload) {
            final player = TugOfWarPlayer.fromJson(payload.newRecord);
            if (!state.players.any((p) => p.userId == player.userId)) {
              state = state.copyWith(players: [...state.players, player]);
              // Host: add to the authoritative accumulator if the new
              // player is on a team.
              if (_isHost && player.team != null) {
                _authoritativePullCounts[player.userId] ??= 0;
              }
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'tugofwar_players',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: gameId,
          ),
          callback: (payload) {
            final updated = TugOfWarPlayer.fromJson(payload.newRecord);
            final next = state.players
                .map((p) => p.userId == updated.userId ? updated : p)
                .toList();
            state = state.copyWith(players: next);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'tugofwar_players',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: gameId,
          ),
          callback: (payload) {
            final oldRecord = payload.oldRecord;
            final goneId = oldRecord['userId'] as String?;
            if (goneId == null) return;
            state = state.copyWith(
              players: state.players
                  .where((p) => p.userId != goneId)
                  .toList(),
            );
            // Host: drop from the authoritative accumulator.
            _authoritativePullCounts.remove(goneId);
          },
        )
        .subscribe();

    // Spectator / reconnecting-player handshake: ask the host for a
    // one-time snapshot so we render the rope immediately instead of
    // waiting up to 150 ms for the next periodic broadcast.
    if (!_isHost) {
      // Small delay so the host's onBroadcast('request_state') listener
      // is wired before we send (otherwise the request is lost).
      Future.delayed(const Duration(milliseconds: 200), () {
        if (!mounted || _channel == null) return;
        try {
          unawaited(_channel!.sendBroadcastMessage(
            event: 'request_state',
            payload: {'userId': _myId, 'ts': DateTime.now().toIso8601String()},
          ));
        } catch (e) {
          debugPrint('[TugOfWar] request_state send error: $e');
        }
      });
    }
  }

  void _cleanup() {
    _channel?.unsubscribe();
    _channel = null;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    _gameId = null;
    _pendingTaps = 0;
    _authoritativePullCounts.clear();
    _matchStartTime = null;
    _currentRope = 0.0;
    state = const TugOfWarState();
  }

  @override
  void dispose() {
    _batchTimer.cancel();
    _ropeBroadcastTimer.cancel();
    _watchdogTimer?.cancel();
    _cleanupTimer?.cancel();
    _channel?.unsubscribe();
    super.dispose();
  }
}

final tugOfWarProvider = StateNotifierProvider.autoDispose
    .family<TugOfWarNotifier, TugOfWarState, String>(
  (ref, familyId) => TugOfWarNotifier(ref, familyId),
);

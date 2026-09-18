// lib/features/games/tugofwar/tugofwar_provider.dart
//
// Tug of War — Riverpod state + Supabase Realtime + server-authoritative pulls.
//
// Architecture:
//   • Supabase stores the game row (rope position, team taps, winner) and
//     the player roster (validated pull counts, teams).
//   • The fn_tugofwar_pull RPC is the ONLY place taps are counted — it
//     enforces the 15 taps/sec anti-cheat cap server-side and recomputes
//     the rope from per-player averages (fairness formula).
//   • Clients batch taps every 400 ms (~2.5 RPCs/sec/player) and animate
//     locally at 60 fps; the game row updates arrive via Realtime at up to
//     ~6 Hz (server-throttled) and are interpolated by the rope controller.
//   • fn_tugofwar_tick is a watchdog any client runs every 2 s so timed
//     matches end the moment they expire.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../game_motion_tokens.dart';
import '../shared/data/game_invite_chat_sync.dart';
import '../shared/services/temporary_room_service.dart';
import 'tugofwar_models.dart';

/// How often the local tap buffer is flushed to fn_tugofwar_pull.
const Duration kPullBatchWindow = Duration(milliseconds: 400);

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
  });

  final TugOfWarGame? game;
  final List<TugOfWarPlayer> players;
  final bool isLoading;
  final bool isStarting;
  final bool isLeaving;
  final String? error;
  final bool amSpectator;

  /// Optimistic local tap counter (instant PULL feedback). The server's
  /// count for me lives on my player row and arrives via Realtime.
  final int myLocalTaps;

  /// While set, the server is rejecting part of our taps (15/sec cap).
  final DateTime? rateLimitedUntil;

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
      );
}

class TugOfWarNotifier extends StateNotifier<TugOfWarState> {
  TugOfWarNotifier(this._ref, this.familyId) : super(const TugOfWarState()) {
    _batchTimer = Timer.periodic(kPullBatchWindow, (_) => _flushTaps());
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

  int _pendingTaps = 0;
  bool _flushInFlight = false;

  /// Cold-start retries: deep-linking or RELOADING straight onto the game
  /// screen can create this notifier BEFORE the Supabase client/session is
  /// wired into Riverpod. Without a retry the load bails once and a
  /// reconnecting player is stranded on the loading spinner forever even
  /// though the match is live (same class of bug as Ghost Painter f28fb88).
  int _loadRetries = 0;

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
  /// once (instant haptics + rope impulse) and batches to the server.
  void pull() {
    if (!state.isInProgress || state.amSpectator) return;
    final myId = _myId;
    if (state.playerFor(myId)?.team == null) return;
    _pendingTaps += 1;
    state = state.copyWith(myLocalTaps: state.myLocalTaps + 1);
  }

  Future<void> _flushTaps() async {
    if (_flushInFlight || _pendingTaps <= 0) return;
    final gameId = _gameId;
    if (gameId == null) {
      _pendingTaps = 0;
      return;
    }
    final taps = _pendingTaps;
    _pendingTaps = 0;
    _flushInFlight = true;
    final client = _client;
    try {
      if (client != null) {
        final result = await client.rpc('fn_tugofwar_pull', params: {
          'p_game_id': gameId,
          'p_taps': taps,
        });
        final map = result is Map<String, dynamic>
            ? result
            : (result is Map ? Map<String, dynamic>.from(result) : null);
        if (map != null) {
          final accepted = (map['accepted'] as num?)?.toInt() ?? 0;
          if (accepted < taps) {
            // Server clipped us (anti-cheat). Ease off the local counter and
            // briefly show the "steady!" hint.
            state = state.copyWith(
              myLocalTaps:
                  (state.myLocalTaps - (taps - accepted)).clamp(0, 1 << 30),
              rateLimitedUntil:
                  DateTime.now().add(const Duration(milliseconds: 900)),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[TugOfWar] pull flush error: $e');
    } finally {
      _flushInFlight = false;
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
    // expired match ends even if both teams stop pulling.
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
          },
        )
        .subscribe();
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
    state = const TugOfWarState();
  }

  @override
  void dispose() {
    _batchTimer.cancel();
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

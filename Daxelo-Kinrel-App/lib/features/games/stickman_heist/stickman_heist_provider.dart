// lib/features/games/stickman_heist/stickman_heist_provider.dart
//
// Stickman Heist — Riverpod state + Supabase Realtime Broadcast + Forge2D
// physics orchestration.
//
// Architecture (HOST-AUTHORITATIVE, Broadcast-based):
//   • Supabase Postgres stores ONLY durable state: games, players,
//     and the FINAL match result (winnerUserIds, endReason,
//     completedAt). Per-frame inputs and per-frame board state NEVER
//     touch Postgres — they go over Realtime Broadcast (pure websocket
//     pub/sub, no DB).
//   • The host's client runs the Forge2D physics simulation at 60fps:
//       1. step() the physics + checkCollisions() (treasure pickup,
//          escape zone, weapon/powerup pickups, respawns, kills).
//       2. Non-host inputs arrive via Realtime Broadcast
//          `onBroadcast(event: 'input')` — applied to the physics
//          sim on the next 16ms tick. Previously the host polled the
//          `stickman_heist_inputs` table at 20Hz (DB READ) — removed.
//       3. Every 100ms, broadcast the latest boardState JSON via
//          `channel.sendBroadcastMessage(event: 'state', ...)` — pure
//          websocket, no DB. Previously this called
//          `fn_stickmanheist_broadcast_state` RPC at 10Hz (DB WRITE)
//          — eliminated.
//       4. On match completion (status='completed'), make ONE final
//          durable RPC call to `fn_stickmanheist_broadcast_state` to
//          persist winnerUserIds + endReason + completedAt. This is
//          the ONLY DB write in the hot path — one call per match.
//   • Non-host clients:
//       1. Receive boardState via `onBroadcast(event: 'state')` and
//          render it.
//       2. Send their input frame via
//          `channel.sendBroadcastMessage(event: 'input', ...)` at 20Hz
//          — pure websocket, no DB. Previously this upserted a row in
//          `stickman_heist_inputs` at 20Hz (DB WRITE) — eliminated.
//   • Spectators (joined after start): read-only like non-host, but
//     don't send inputs. On subscribe they send a one-time
//     `request_state` broadcast so the host immediately pushes a
//     state snapshot (no waiting up to 100ms for the next periodic
//     broadcast).
//   • Reconnect mid-match: a non-host who closed and reopens the app
//     calls `joinGame` → `_subscribeToRealtime` → sends
//     `request_state` → host responds with one state snapshot.
//     Subsequent updates flow via the periodic 10Hz broadcast. No DB
//     needed.
//   • Durable state still flows through Postgres Changes listeners
//     (status flip to in_progress / completed, lobby roster changes,
//     room deletion) — these fire ~once per lifecycle event, not per
//     frame.
//
// The provider is a StateNotifier keyed by familyId (per-family game
// session). All timers and subscriptions are cleaned up in dispose().
//
// See worklog Task 2-stickman-heist for the before/after Supabase-call
// table that drives the manual-playtest checklist.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/socket_service.dart';
import '../../../core/services/supabase_service.dart';
import '../game_motion_tokens.dart';
import '../shared/data/game_invite_chat_sync.dart';
import '../shared/models/game_invite.dart';
import '../shared/services/room_presence_heartbeat.dart';
import '../shared/services/temporary_room_service.dart';
import 'stickman_heist_models.dart';
import 'stickman_heist_physics.dart';

/// Local UI state for the Stickman Heist notifier.
class StickmanHeistState_ {
  const StickmanHeistState_({
    this.game,
    this.players = const [],
    this.isLoading = false,
    this.isStarting = false,
    this.error,
    this.amSpectator = false,
    this.myInput = const StickmanHeistInputWire(
      gameId: '',
      userId: '',
      moveX: 0,
      moveY: 0,
      aimAngle: 0,
      shooting: false,
      reloadRequested: false,
      swapWeaponRequested: false,
    ),
    this.liveState,
    this.lastEventSeen = 0,
  });

  final StickmanHeistGame? game;
  final List<StickmanHeistPlayerWire> players;
  final bool isLoading;
  final bool isStarting;
  final String? error;

  /// True if the local user joined after the match started.
  final bool amSpectator;

  /// The local user's current input frame. Mirrored here so the UI can
  /// reflect hold-to-shoot etc. without a round-trip.
  final StickmanHeistInputWire myInput;

  /// The latest board state received from Supabase Realtime (non-host)
  /// or produced locally by the host's sim loop. The game screen paints
  /// this.
  final StickmanHeistBoardState? liveState;

  /// Highest event.atMs we've already surfaced — used by the UI to
  /// trigger event banners only for new events.
  final int lastEventSeen;

  bool get isWaiting => game?.isWaiting ?? false;
  bool get isInProgress => game?.isInProgress ?? false;
  bool get isCompleted => game?.isCompleted ?? false;
  bool get hasGame => game != null;

  StickmanHeistState_ copyWith({
    StickmanHeistGame? game,
    List<StickmanHeistPlayerWire>? players,
    bool? isLoading,
    bool? isStarting,
    String? error,
    bool clearError = false,
    bool? amSpectator,
    StickmanHeistInputWire? myInput,
    StickmanHeistBoardState? liveState,
    int? lastEventSeen,
  }) =>
      StickmanHeistState_(
        game: game ?? this.game,
        players: players ?? this.players,
        isLoading: isLoading ?? this.isLoading,
        isStarting: isStarting ?? this.isStarting,
        error: clearError ? null : (error ?? this.error),
        amSpectator: amSpectator ?? this.amSpectator,
        myInput: myInput ?? this.myInput,
        liveState: liveState ?? this.liveState,
        lastEventSeen: lastEventSeen ?? this.lastEventSeen,
      );
}

class StickmanHeistNotifier extends StateNotifier<StickmanHeistState_> {
  StickmanHeistNotifier(this._ref, this.familyId)
      : super(const StickmanHeistState_());

  final Ref _ref;
  final String familyId;

  SupabaseClient? get _client => _ref.read(supabaseProvider);
  String? get _myId => _client?.auth.currentUser?.id;
  String get _myName =>
      _client?.auth.currentUser?.userMetadata?['name'] as String? ??
      'Player';

  // ── Subscriptions / timers ──────────────────────────────────────────
  RealtimeChannel? _channel;
  RoomPresenceHeartbeat? _heartbeat;
  String? _gameId;

  StickmanHeistPhysicsEngine? _physics;

  /// Host sim loop — 60fps physics tick.
  Timer? _simTimer;

  /// Host broadcast loop — 10Hz state broadcast via Realtime Broadcast
  /// (pure websocket pub/sub, no DB). Replaces the previous 10Hz
  /// `fn_stickmanheist_broadcast_state` DB RPC.
  Timer? _broadcastTimer;

  /// Non-host input broadcast loop — 20Hz send my input frame via
  /// Realtime Broadcast (pure websocket, no DB). Replaces the previous
  /// 20Hz `stickman_heist_inputs` upsert.
  Timer? _inputBroadcastTimer;

  /// Cleanup safety timer — end the room 30s after the match completes.
  Timer? _cleanupTimer;

  // ── Receive-side throttle for state broadcasts ──────────────────
  // Multiple state broadcasts arriving in the same frame are coalesced
  // into a single state emission. The host sends at 10Hz (100ms) but
  // network jitter can bunch them; without this throttle, two
  // back-to-back state events would queue two full-screen rebuilds in
  // the same frame — one wasted.
  Map<String, dynamic>? _pendingState;
  Timer? _stateFlush;
  bool _disposed = false;

  /// Latest snapshot of all player inputs. Updated by the Broadcast
  /// `onBroadcast(event: 'input')` callback — no DB polling.
  final Map<String, StickmanHeistInputWire> _latestInputs = {};

  bool get _isHost {
    final myId = _myId;
    final game = state.game;
    if (myId == null || game == null) return false;
    return game.hostUserId == myId;
  }

  // ── Public API ──────────────────────────────────────────────────────

  /// Host: create a new game room.
  Future<String?> createGame({
    required String mapId,
    required bool respawnsEnabled,
    required int matchSeconds,
    String? roomName,
    bool spectatorsEnabled = true,
    int maxPlayers = kStickmanHeistMaxPlayers,
  }) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) {
      state = state.copyWith(error: 'Not signed in');
      return null;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final deadline =
          DateTime.now().add(const Duration(minutes: 10));
      final body = <String, dynamic>{
        'familyId': familyId,
        'hostUserId': myId,
        'hostUserName': _myName,
        if (roomName != null && roomName.trim().isNotEmpty)
          'roomName': roomName.trim(),
        'status': 'waiting',
        'maxPlayers': maxPlayers,
        'playerOrder': [],
        'winnerUserIds': [],
        'spectatorsEnabled': spectatorsEnabled,
        'hostReady': true,
        'mapId': mapId,
        'respawnsEnabled': respawnsEnabled,
        'matchSeconds': matchSeconds,
        'autoCloseDeadline': deadline.toIso8601String(),
      };
      final resp = await client
          .from('stickman_heist_games')
          .insert(body)
          .select()
          .single();
      final game = StickmanHeistGame.fromJson(resp);
      _gameId = game.id;

      // Insert the host as the first player.
      await client.from('stickman_heist_players').insert({
        'gameId': game.id,
        'userId': myId,
        'userName': _myName,
        'isReady': true,
      });
      await client.rpc('fn_record_room_join', params: {
        'p_game_table': 'stickman_heist_games',
        'p_game_id': game.id,
        'p_family_id': familyId,
        'p_user_id': myId,
        'p_user_name': _myName,
        'p_role': 'host',
      });

      final players = await _fetchPlayers(game.id);
      state = state.copyWith(
        game: game,
        players: players,
        isLoading: false,
      );
      _subscribeToRealtime(game.id);
      return game.id;
    } catch (e) {
      debugPrint('[StickmanHeist] createGame error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
      return null;
    }
  }

  /// Non-host: join an existing waiting room (or spectate an in-progress
  /// match).
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
          .from('stickman_heist_games')
          .select()
          .eq('id', gameId)
          .maybeSingle();
      if (isRoomRowClosed(gameResp)) {
        state = state.copyWith(
            isLoading: false, error: kRoomClosedMessage);
        return false;
      }
      final game = StickmanHeistGame.fromJson(
          gameResp as Map<String, dynamic>);
      _gameId = game.id;

      final existing = await client
          .from('stickman_heist_players')
          .select()
          .eq('gameId', gameId)
          .eq('userId', myId)
          .maybeSingle();

      final alreadyInGame = existing != null;

      if (!alreadyInGame) {
        if (game.isWaiting) {
          if (game.playerOrder.length >= game.maxPlayers) {
            state = state.copyWith(
              isLoading: false,
              error: 'Game is full',
            );
            return false;
          }
          await client.from('stickman_heist_players').insert({
            'gameId': gameId,
            'userId': myId,
            'userName': _myName,
            'isReady': false,
          });
          await client.rpc('fn_record_room_join', params: {
            'p_game_table': 'stickman_heist_games',
            'p_game_id': gameId,
            'p_family_id': familyId,
            'p_user_id': myId,
            'p_user_name': _myName,
            'p_role': 'player',
          });
          await _ref.read(temporaryRoomServiceProvider).touchActivity(
                gameTable: 'stickman_heist_games',
                gameId: gameId,
              );
        } else if (game.isInProgress) {
          await client.rpc('fn_spectate_game', params: {
            'p_game_table': 'stickman_heist_games',
            'p_game_id': gameId,
            'p_family_id': familyId,
            'p_user_id': myId,
            'p_user_name': _myName,
          });
          state = state.copyWith(amSpectator: true);
        }
      }

      final players = await _fetchPlayers(game.id);
      state = state.copyWith(
        game: game,
        players: players,
        isLoading: false,
        liveState: game.boardState,
      );
      _subscribeToRealtime(gameId);

      // If the match is in progress and we're the host, kick off the
      // sim loop (e.g. after a hot restart).
      if (game.isInProgress && _isHost) {
        _startHostLoops(game);
      } else if (game.isInProgress && !_isHost && !state.amSpectator) {
        _startInputBroadcastLoop(gameId);
      }

      // Keep the persistent game-invite chat card in sync (best-effort).
      unawaited(
        syncGameInviteChatCards(
          client: client,
          gameId: gameId,
          currentPlayers: players.length,
        ),
      );
      return true;
    } catch (e) {
      debugPrint('[StickmanHeist] joinGame error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
      return false;
    }
  }

  /// Toggle my ready state in the lobby.
  Future<void> toggleReady(bool isReady) async {
    final client = _client;
    final myId = _myId;
    final gameId = _gameId;
    if (client == null || myId == null || gameId == null) return;
    try {
      await client
          .from('stickman_heist_players')
          .update({
            'isReady': isReady,
            'lastActivityAt': DateTime.now().toIso8601String(),
          })
          .eq('gameId', gameId)
          .eq('userId', myId);
      await _ref.read(temporaryRoomServiceProvider).touchActivity(
            gameTable: 'stickman_heist_games',
            gameId: gameId,
          );
    } catch (e) {
      debugPrint('[StickmanHeist] toggleReady error: $e');
    }
  }

  /// Host: start the match. Calls fn_stickmanheist_start which sets
  /// status=in_progress, generates the initial board state, and
  /// populates playerOrder. Then we kick off the host sim loop locally.
  Future<String?> startGame() async {
    final client = _client;
    final gameId = _gameId;
    final game = state.game;
    final myId = _myId;
    if (client == null || gameId == null || game == null) {
      return 'No active room';
    }
    if (game.hostUserId != myId) {
      return 'Only the host can start';
    }
    if (state.players.where((p) => p.isActive).length <
        kStickmanHeistMinPlayers) {
      return 'Waiting for more players to join';
    }
    state = state.copyWith(isStarting: true, clearError: true);
    try {
      final result = await client.rpc(
        'fn_stickmanheist_start',
        params: {'p_game_id': gameId},
      );
      final ok = (result is Map)
          ? (result['ok'] as bool? ?? false)
          : false;
      if (!ok) {
        final reason = (result is Map)
            ? (result['reason'] as String? ?? 'unknown')
            : 'unknown';
        state = state.copyWith(isStarting: false);
        return 'Could not start: $reason';
      }
      // Re-fetch the game row to get the populated boardState.
      final gameResp = await client
          .from('stickman_heist_games')
          .select()
          .eq('id', gameId)
          .single();
      final updated = StickmanHeistGame.fromJson(gameResp);
      state = state.copyWith(
        game: updated,
        liveState: updated.boardState,
        isStarting: false,
      );
      GameMotionTokens.celebrate();
      _startHostLoops(updated);
      return null;
    } catch (e) {
      debugPrint('[StickmanHeist] startGame error: $e');
      state = state.copyWith(isStarting: false, error: '$e');
      return 'Could not start the match';
    }
  }

  /// Update my input frame.
  ///
  /// - HOST: applies directly to the local physics engine (immediate
  ///   response, no network round-trip).
  /// - NON-HOST: stashes into `state.myInput`; the 20Hz
  ///   `_inputBroadcastTimer` (started in `_startInputBroadcastLoop`)
  ///   sends it via Realtime Broadcast `event: 'input'` — pure websocket,
  ///   no DB.
  ///
  /// Previously this upserted a row in `stickman_heist_inputs` at 20Hz
  /// (DB WRITE); the host polled that table at 20Hz (DB READ). Both hit
  /// Postgres in the hot path. See worklog Task 2-stickman-heist.
  void updateInput({
    required double moveX,
    required double moveY,
    required double aimAngle,
    required bool shooting,
    required bool reloadRequested,
    required bool swapWeaponRequested,
  }) {
    final gameId = _gameId;
    final myId = _myId;
    if (gameId == null || myId == null) return;
    final input = StickmanHeistInputWire(
      gameId: gameId,
      userId: myId,
      moveX: moveX,
      moveY: moveY,
      aimAngle: aimAngle,
      shooting: shooting,
      reloadRequested: reloadRequested,
      swapWeaponRequested: swapWeaponRequested,
    );
    state = state.copyWith(myInput: input);
    if (_isHost) {
      // Apply directly to the host's physics engine (immediate response).
      final idx = state.game?.idxForUserId(myId);
      if (idx != null && _physics != null) {
        _physics!.applyInput(
          idx,
          moveX: moveX,
          moveY: moveY,
          aimAngle: aimAngle,
          shooting: shooting,
          reloadRequested: reloadRequested,
          swapWeaponRequested: swapWeaponRequested,
        );
      }
    }
    // Non-host: the 20Hz `_inputBroadcastTimer` sends `state.myInput`
    // via Realtime Broadcast. No fire-and-forget write here — keep the
    // hot path 100% off Postgres.
  }

  /// Non-host: send my current input frame via Realtime Broadcast.
  /// Called every 50ms by `_inputBroadcastTimer`.
  void _broadcastMyInput() {
    final channel = _channel;
    final gameId = _gameId;
    if (channel == null || gameId == null) return;
    try {
      channel.sendBroadcastMessage(
        event: 'input',
        payload: state.myInput.toJson(),
      );
    } catch (e) {
      debugPrint('[StickmanHeist] broadcastInput error: $e');
    }
  }

  /// Host: broadcast the current physics state via Realtime Broadcast
  /// (pure websocket pub/sub, no DB). Called every 100ms by the
  /// broadcast timer.
  ///
  /// On match completion (`phase == completed`), this ALSO makes one
  /// final durable RPC call to `fn_stickmanheist_broadcast_state` to
  /// persist the final result (winnerUserIds, endReason, completedAt,
  /// status='completed') — that single durable write is the ONLY DB
  /// write in the entire hot path.
  Future<void> broadcastState({bool isFinal = false}) async {
    final channel = _channel;
    final physics = _physics;
    final gameId = _gameId;
    if (channel == null || physics == null) return;
    final stateJson = physics.readState().toJson();

    // 1. Broadcast live state over websocket (no DB).
    try {
      unawaited(channel.sendBroadcastMessage(
        event: 'state',
        payload: stateJson,
      ));
    } catch (e) {
      debugPrint('[StickmanHeist] broadcastState (ws) error: $e');
    }

    // 2. On match end, persist the final result durably to Postgres
    //    so it survives disconnect / app reload. This is the ONLY DB
    //    write in the hot path — one call per match, not 10/sec.
    if (isFinal) {
      final client = _client;
      if (client == null || gameId == null) return;
      try {
        await client.rpc(
          'fn_stickmanheist_broadcast_state',
          params: {
            'p_game_id': gameId,
            'p_state': stateJson,
          },
        );
      } catch (e) {
        debugPrint(
            '[StickmanHeist] broadcastState (final RPC) error: $e');
      }
    }
  }

  /// Leave the game (waiting room or in-progress). Routes to
  /// fn_stickmanheist_leave for in-progress matches so the server can
  /// detect walkover wins.
  Future<void> leaveGame() async {
    final client = _client;
    final gameId = _gameId;
    final game = state.game;
    if (client == null || gameId == null) {
      _reset();
      return;
    }
    try {
      if (game != null && game.isWaiting) {
        if (_isHost) {
          await _ref.read(temporaryRoomServiceProvider).cancelWaitingRoom(
                gameTable: 'stickman_heist_games',
                gameId: gameId,
              );
        } else {
          await client
              .from('stickman_heist_players')
              .update({
                'leftAt': DateTime.now().toIso8601String(),
              })
              .eq('gameId', gameId)
              .eq('userId', _myId ?? '');
        }
      } else if (game != null && game.isInProgress) {
        await client.rpc('fn_stickmanheist_leave',
            params: {'p_game_id': gameId});
      }
    } catch (_) {}
    _reset();
  }

  /// Rematch — create a new game with the same settings + invite all
  /// prior participants.
  Future<String?> rematch() async {
    final client = _client;
    final game = state.game;
    final myId = _myId;
    if (client == null || game == null || myId == null) return null;
    // QA fix 2026-09-19: capture the previous participants BEFORE
    // createGame() — it overwrites state.players with the NEW game's
    // roster (host only), so by the time the old code computed `others`
    // the list was always empty: rematch invites were never inserted,
    // the opponent never got a dialog, and both players tapping Rematch
    // created divergent rooms.
    final others = state.players
        .where((p) => p.isActive && p.userId != myId)
        .map((p) => (userId: p.userId, name: p.userName))
        .toList();
    final newGameId = await createGame(
      mapId: game.mapId,
      respawnsEnabled: game.respawnsEnabled,
      matchSeconds: game.matchSeconds,
      roomName: game.roomName,
      spectatorsEnabled: game.spectatorsEnabled,
      maxPlayers: game.maxPlayers,
    );
    if (newGameId == null) return null;
    final roomCode =
        newGameId.replaceAll('-', '').substring(0, 6).toUpperCase();
    for (final other in others) {
      // 1. Durable invite row (source of truth; drives the Supabase
      //    Realtime leg of GameInviteListener + FCM push).
      try {
        await client.from('game_invites').insert({
          'gameTable': 'stickman_heist_games',
          'gameId': newGameId,
          'gameType': 'stickman-heist',
          'familyId': familyId,
          'roomCode': roomCode,
          'invitedUserId': other.userId,
          'invitedByUserId': myId,
          'invitedByName': _myName,
          'maxPlayers': game.maxPlayers,
          'currentPlayers': 1,
          'message': '$_myName wants a Stickman Heist rematch!',
          'status': 'pending',
          'sourceGameId': game.id,
        });
      } catch (_) {}
      // 2. Socket.IO realtime leg — best-effort acceleration so the
      //    Accept/Decline dialog pops instantly for online opponents
      //    (same 2-leg design as the lobby one-tap invite).
      try {
        await _ref.read(socketServiceProvider).sendGameInvite(
          toUserId: other.userId,
          invite: GameInvite(
            inviteId:
                'inv_${DateTime.now().millisecondsSinceEpoch}_${other.userId.substring(0, 8)}',
            gameType: GameType.stickmanHeist,
            gameId: newGameId,
            roomCode: roomCode,
            familyId: familyId,
            fromUserId: myId,
            fromName: _myName,
            maxPlayers: game.maxPlayers,
            currentPlayers: 1,
            message: '$_myName wants a Stickman Heist rematch!',
            timestamp: DateTime.now().toUtc(),
          ),
        );
      } catch (_) {
        // The durable row above already guarantees delivery.
      }
    }
    return newGameId;
  }

  /// Load an existing game (e.g. via deep link or invite accept).
  Future<bool> loadGame(String gameId) async {
    final client = _client;
    if (client == null) {
      state = state.copyWith(error: 'Not signed in');
      return false;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final gameResp = await client
          .from('stickman_heist_games')
          .select()
          .eq('id', gameId)
          .maybeSingle();
      if (isRoomRowClosed(gameResp)) {
        state = const StickmanHeistState_(
            error: kRoomClosedMessage);
        return false;
      }
      final game = StickmanHeistGame.fromJson(
          gameResp as Map<String, dynamic>);
      _gameId = game.id;
      final players = await _fetchPlayers(game.id);
      state = state.copyWith(
        game: game,
        players: players,
        liveState: game.boardState,
        isLoading: false,
      );
      _subscribeToRealtime(gameId);
      if (game.isInProgress && _isHost) {
        _startHostLoops(game);
      } else if (game.isInProgress && !_isHost) {
        // Determine if I'm already a player or spectating.
        final isPlayer =
            state.players.any((p) => p.userId == _myId && p.isActive);
        state = state.copyWith(amSpectator: !isPlayer);
        if (isPlayer) _startInputBroadcastLoop(gameId);
      }
      return true;
    } catch (e) {
      debugPrint('[StickmanHeist] loadGame error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
      return false;
    }
  }

  // ── Host game loop ──────────────────────────────────────────────────

  void _startHostLoops(StickmanHeistGame game) {
    _cancelHostLoops();
    final board = game.boardState;
    if (board == null) {
      debugPrint('[StickmanHeist] no boardState — cannot start sim');
      return;
    }
    _physics = StickmanHeistPhysicsEngine()..setup(board);

    // Physics + collision check at 60fps.
    // State EMISSION is throttled to every other tick (~30fps) so the
    // host's UI rebuilds at 30fps instead of 60fps — visually
    // indistinguishable for the HUD/arena but halves the rebuild cost
    // (the _TopHud + _ArenaView + _ControlsBar + _EventBanner subtree
    // is heavy: BoxShadow + gradients + TextPainter calls per frame).
    // The physics engine itself still steps at 60fps for accuracy;
    // only the state.copyWith() + notifyListeners is throttled.
    int _simTickNum = 0;
    _simTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) {
        if (_physics == null) return;
        // Apply latest known inputs to the engine (host's own input
        // is already applied directly via updateInput; we only need to
        // apply non-host inputs here).
        for (final entry in _latestInputs.entries) {
          final idx = game.idxForUserId(entry.key);
          if (idx == null) continue;
          if (idx == game.idxForUserId(_myId)) continue; // already applied
          _physics!.applyInput(
            idx,
            moveX: entry.value.moveX,
            moveY: entry.value.moveY,
            aimAngle: entry.value.aimAngle,
            shooting: entry.value.shooting,
            reloadRequested: entry.value.reloadRequested,
            swapWeaponRequested: entry.value.swapWeaponRequested,
          );
        }
        _physics!.step();
        _physics!.checkCollisions();
        // Update local live state for the host's own rendering.
        final live = _physics!.readState();
        // Throttle: emit state every other sim tick (~30fps). Phase
        // transitions / completion always emit immediately regardless
        // of tick parity so the post-match flow doesn't lag.
        final shouldEmit = (_simTickNum & 1) == 0 ||
            live.phase == StickmanHeistPhase.completed ||
            live.phase != state.liveState?.phase;
        if (shouldEmit) {
          state = state.copyWith(liveState: live);
        }
        _simTickNum++;
        // If the sim says the match is over, stop the loops and let
        // the broadcast timer push the final state once (durably).
        if (live.phase == StickmanHeistPhase.completed) {
          _cancelHostLoops();
          unawaited(broadcastState(isFinal: true));
          _scheduleRoomCleanup(game.id);
        }
      },
    );

    // NOTE: No more _inputPollTimer. Non-host inputs now arrive via
    // Realtime Broadcast `onBroadcast(event: 'input')` callback (set
    // up in `_subscribeToRealtime`). Previously the host polled the
    // `stickman_heist_inputs` table at 20Hz (DB READ) — eliminated.

    // Broadcast — push the current state at 10Hz via Realtime Broadcast
    // (pure websocket, no DB). Previously this called
    // `fn_stickmanheist_broadcast_state` RPC (DB WRITE) at 10Hz.
    _broadcastTimer = Timer.periodic(
      const Duration(
          milliseconds: kStickmanHeistBroadcastIntervalMs),
      (_) => broadcastState(),
    );
  }

  void _cancelHostLoops() {
    _simTimer?.cancel();
    _simTimer = null;
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
  }

  // NOTE: `_pollInputs()` removed. Previously the host polled the
  // `stickman_heist_inputs` table at 20Hz (DB READ). Now inputs arrive
  // via Realtime Broadcast `onBroadcast(event: 'input')` callback —
  // see `_subscribeToRealtime`. Zero DB reads in the input hot path.

  // ── Non-host input broadcast loop ───────────────────────────────────

  void _startInputBroadcastLoop(String gameId) {
    _inputBroadcastTimer?.cancel();
    _inputBroadcastTimer = Timer.periodic(
      const Duration(
          milliseconds: kStickmanHeistInputPollIntervalMs),
      (_) {
        if (state.amSpectator) return;
        _broadcastMyInput();
      },
    );
  }

  // ── Realtime subscription ───────────────────────────────────────────

  void _subscribeToRealtime(String gameId) {
    _channel?.unsubscribe();
    final client = _client;
    if (client == null) return;

    final myId = _myId;
    if (myId != null) {
      _heartbeat?.stop();
      _heartbeat = RoomPresenceHeartbeat('stickman_heist_games')
        ..start(client, gameId, myId);
    }

    _channel = client
        .channel('stickmanheist_game:$gameId')
        // ── HOT-PATH BROADCAST LISTENERS (pure websocket, no DB) ──
        // These replace the old DB-polling + DB-RPC-broadcast pattern.
        // See worklog Task 2-stickman-heist for the before/after table.
        .onBroadcast(
          event: 'input',
          callback: (payload) {
            // Non-host input frame received. Host applies it to the
            // physics sim via the next _simTimer tick (16ms).
            // Spectators + non-hosts ignore — they only render state.
            if (!_isHost) return;
            try {
              final input = StickmanHeistInputWire.fromJson(
                  Map<String, dynamic>.from(payload as Map));
              if (input.userId.isEmpty ||
                  input.userId == _myId) {
                return;
              }
              _latestInputs[input.userId] = input;
            } catch (e) {
              debugPrint(
                  '[StickmanHeist] onBroadcast(input) parse error: $e');
            }
          },
        )
        .onBroadcast(
          event: 'state',
          callback: (payload) {
            // Host broadcasted a new board state. Non-hosts + spectators
            // render this. Host ignores — host owns the canonical state.
            if (_isHost) return;
            try {
              final map = Map<String, dynamic>.from(payload as Map);
              // Coalesce: buffer the latest payload and flush on the
              // next event-loop turn. Multiple same-frame state broadcasts
              // collapse into one state emission + one rebuild.
              // Note: Timer.run returns void — use Timer(Duration.zero,
              // ...) which returns a Timer so we can cancel/track it.
              _pendingState = map;
              _stateFlush ??= Timer(Duration.zero, _flushState);
            } catch (e) {
              debugPrint(
                  '[StickmanHeist] onBroadcast(state) parse error: $e');
            }
          },
        )
        .onBroadcast(
          event: 'request_state',
          callback: (_) {
            // A spectator (or reconnecting player) joined and is asking
            // for a one-time snapshot of the current sim state so they
            // can render immediately instead of waiting up to 100ms for
            // the next periodic broadcast. Only host responds.
            if (!_isHost) return;
            final physics = _physics;
            final channel = _channel;
            if (physics == null || channel == null) return;
            try {
              channel.sendBroadcastMessage(
                event: 'state',
                payload: physics.readState().toJson(),
              );
            } catch (e) {
              debugPrint(
                  '[StickmanHeist] request_state response error: $e');
            }
          },
        )
        // ── DURABLE POSTGRES CHANGES LISTENERS ──
        // These remain on Postgres Changes because they describe
        // durable state changes that must survive disconnect/reload:
        //   • stickman_heist_games UPDATE → status flip (waiting →
        //     in_progress → completed), winnerUserIds, endReason
        //   • stickman_heist_players INSERT/UPDATE/DELETE → lobby
        //     roster + ready state + leftAt
        //   • stickman_heist_games DELETE → room closed
        // These fire ~once per actual lifecycle event, not per frame.
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'stickman_heist_games',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: gameId,
          ),
          callback: (payload) {
            final updated = StickmanHeistGame.fromJson(
                payload.newRecord);
            if (updated.isCompleted && state.liveState?.phase !=
                StickmanHeistPhase.completed) {
              GameMotionTokens.celebrate();
            }
            state = state.copyWith(
              game: updated,
              liveState: updated.boardState ?? state.liveState,
            );
            if (updated.isInProgress &&
                _isHost &&
                _physics == null) {
              _startHostLoops(updated);
            }
            if (updated.isInProgress &&
                !_isHost &&
                _inputBroadcastTimer == null &&
                !state.amSpectator) {
              _startInputBroadcastLoop(updated.id);
            }
            if (updated.isCompleted) {
              _cancelHostLoops();
              _inputBroadcastTimer?.cancel();
              _inputBroadcastTimer = null;
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'stickman_heist_players',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: gameId,
          ),
          callback: (_) async {
            final players = await _fetchPlayers(gameId);
            state = state.copyWith(players: players);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'stickman_heist_players',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: gameId,
          ),
          callback: (_) async {
            final players = await _fetchPlayers(gameId);
            state = state.copyWith(players: players);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'stickman_heist_games',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: gameId,
          ),
          callback: (_) {
            debugPrint(
                '[StickmanHeist] game row deleted — room closed');
            _channel?.unsubscribe();
            _channel = null;
            _gameId = null;
            if (state.game?.isCompleted ?? false) return;
            state =
                const StickmanHeistState_(error: kRoomClosedMessage);
          },
        )
        .subscribe();

    // Spectator / late-joiner handshake: ask the host for a one-time
    // state snapshot so we can render immediately instead of waiting
    // up to 100ms for the next periodic broadcast. Host ignores
    // `request_state` from itself (it owns the canonical state).
    // This is a single Broadcast message — zero DB cost.
    if (!_isHost) {
      try {
        _channel?.sendBroadcastMessage(
          event: 'request_state',
          payload: {'from': _myId ?? ''},
        );
      } catch (_) {
        // Best-effort — next periodic broadcast will arrive within
        // 100ms anyway. Don't crash the subscribe flow.
      }
    }
  }

  Future<List<StickmanHeistPlayerWire>> _fetchPlayers(
      String gameId) async {
    final client = _client;
    if (client == null) return const [];
    try {
      final resp = await client
          .from('stickman_heist_players')
          .select()
          .eq('gameId', gameId)
          .order('joinedAt', ascending: true);
      return resp
          .map((p) => StickmanHeistPlayerWire.fromJson(p))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  // ── Teardown ────────────────────────────────────────────────────────

  void _scheduleRoomCleanup(String gameId) {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer(const Duration(seconds: 30), () {
      _ref.read(temporaryRoomServiceProvider).endGame(
            gameTable: 'stickman_heist_games',
            gameId: gameId,
          );
    });
  }

  void _reset() {
    _cancelHostLoops();
    _inputBroadcastTimer?.cancel();
    _inputBroadcastTimer = null;
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    _channel?.unsubscribe();
    _channel = null;
    _heartbeat?.stop();
    _heartbeat = null;
    _physics?.dispose();
    _physics = null;
    _latestInputs.clear();
    _gameId = null;
    state = const StickmanHeistState_();
  }

  /// Flush the latest buffered state payload as a single state
  /// emission. Called via `Timer.run` from the state listener — by
  /// the time this fires, any same-frame state broadcasts have
  /// already been collapsed into the latest `_pendingState`.
  void _flushState() {
    _stateFlush = null;
    final map = _pendingState;
    _pendingState = null;
    if (map == null || _disposed) return;
    try {
      final board = StickmanHeistBoardState.fromJson(map);
      if (board.phase == StickmanHeistPhase.completed &&
          state.liveState?.phase != StickmanHeistPhase.completed) {
        GameMotionTokens.celebrate();
      }
      state = state.copyWith(liveState: board);
    } catch (e) {
      debugPrint('[StickmanHeist] _flushState parse error: $e');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelHostLoops();
    _inputBroadcastTimer?.cancel();
    _cleanupTimer?.cancel();
    _stateFlush?.cancel();
    _physics?.dispose();
    _channel?.unsubscribe();
    _heartbeat?.stop();
    super.dispose();
  }
}

final stickmanHeistProvider = StateNotifierProvider.autoDispose
    .family<StickmanHeistNotifier, StickmanHeistState_, String>(
  (ref, familyId) => StickmanHeistNotifier(ref, familyId),
);

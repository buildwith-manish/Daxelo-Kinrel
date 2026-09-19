// lib/features/games/stickman_heist/stickman_heist_provider.dart
//
// Stickman Heist — Riverpod state + Supabase Realtime + Forge2D physics
// orchestration.
//
// Architecture (HOST-AUTHORITATIVE):
//   • Supabase stores games, players, and per-frame inputs.
//   • The host's client runs the Forge2D physics simulation at 60fps:
//       1. Every 50ms, read all input rows from stickman_heist_inputs
//          for the active game.
//       2. Apply each input to the corresponding player body.
//       3. step() the physics + checkCollisions() (treasure pickup,
//          escape zone, weapon/powerup pickups, respawns, kills).
//       4. Every 100ms, call fn_stickmanheist_broadcast_state with the
//          latest boardState JSON — Supabase Realtime delivers it to
//          every other client.
//   • Non-host clients:
//       1. Render the boardState they receive via Realtime.
//       2. Upsert their input row at ~20Hz (joystick + shoot button).
//   • Spectators (joined after start): read-only, like non-host but
//     without writing inputs.
//
// The provider is a StateNotifier keyed by familyId (per-family game
// session). All timers and subscriptions are cleaned up in dispose().

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../game_motion_tokens.dart';
import '../shared/data/game_invite_chat_sync.dart';
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

  /// Host broadcast loop — 10Hz state broadcast.
  Timer? _broadcastTimer;

  /// Host input-poll loop — 20Hz read inputs from stickman_heist_inputs.
  Timer? _inputPollTimer;

  /// Non-host input-write loop — 20Hz upsert my input row.
  Timer? _inputWriteTimer;

  /// Cleanup safety timer — end the room 30s after the match completes.
  Timer? _cleanupTimer;

  /// Latest snapshot of all player inputs (read by host poll loop).
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
        _startInputWriteLoop(gameId);
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

  /// Update my input frame. Non-host: upserts my row in
  /// stickman_heist_inputs (the host's poll loop picks it up). Host:
  /// applies directly to the physics engine and also upserts the row
  /// (so spectators / late-join hosts see consistent state).
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
    } else if (state.game?.isInProgress == true && !state.amSpectator) {
      // Non-host: fire-and-forget upsert; the 20Hz loop also writes.
      _upsertInputRow(input);
    }
  }

  Future<void> _upsertInputRow(StickmanHeistInputWire input) async {
    final client = _client;
    if (client == null) return;
    try {
      await client
          .from('stickman_heist_inputs')
          .upsert({
            ...input.toJson(),
            'updatedAt': DateTime.now().toIso8601String(),
          }, onConflict: '"gameId","userId"');
    } catch (e) {
      debugPrint('[StickmanHeist] upsertInput error: $e');
    }
  }

  /// Host: broadcast the current physics state via RPC. Called every
  /// 100ms by the broadcast timer.
  Future<void> broadcastState() async {
    final client = _client;
    final gameId = _gameId;
    final physics = _physics;
    if (client == null || gameId == null || physics == null) return;
    try {
      final stateJson = physics.readState().toJson();
      await client.rpc(
        'fn_stickmanheist_broadcast_state',
        params: {
          'p_game_id': gameId,
          'p_state': stateJson,
        },
      );
    } catch (e) {
      debugPrint('[StickmanHeist] broadcastState error: $e');
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
    final newGameId = await createGame(
      mapId: game.mapId,
      respawnsEnabled: game.respawnsEnabled,
      matchSeconds: game.matchSeconds,
      roomName: game.roomName,
      spectatorsEnabled: game.spectatorsEnabled,
      maxPlayers: game.maxPlayers,
    );
    if (newGameId == null) return null;
    try {
      final others = state.players
          .where((p) => p.isActive && p.userId != myId)
          .toList();
      for (final other in others) {
        try {
          await client.from('game_invites').insert({
            'gameTable': 'stickman_heist_games',
            'gameId': newGameId,
            'gameType': 'stickman-heist',
            'familyId': familyId,
            'roomCode': newGameId
                .replaceAll('-', '')
                .substring(0, 6)
                .toUpperCase(),
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
      }
    } catch (e) {
      debugPrint('[StickmanHeist] rematch error: $e');
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
        if (isPlayer) _startInputWriteLoop(gameId);
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
        state = state.copyWith(liveState: live);
        // If the sim says the match is over, stop the loops and let
        // the broadcast timer push the final state once.
        if (live.phase == StickmanHeistPhase.completed) {
          _cancelHostLoops();
          unawaited(broadcastState());
          _scheduleRoomCleanup(game.id);
        }
      },
    );

    // Input poll — read non-host inputs at 20Hz.
    _inputPollTimer = Timer.periodic(
      const Duration(
          milliseconds: kStickmanHeistInputPollIntervalMs),
      (_) => _pollInputs(game.id),
    );

    // Broadcast — push the current state at 10Hz.
    _broadcastTimer = Timer.periodic(
      const Duration(
          milliseconds: kStickmanHeistBroadcastIntervalMs),
      (_) => broadcastState(),
    );
  }

  void _cancelHostLoops() {
    _simTimer?.cancel();
    _simTimer = null;
    _inputPollTimer?.cancel();
    _inputPollTimer = null;
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
  }

  Future<void> _pollInputs(String gameId) async {
    final client = _client;
    if (client == null) return;
    try {
      final resp = await client
          .from('stickman_heist_inputs')
          .select()
          .eq('gameId', gameId);
      for (final row in resp) {
        final input =
            StickmanHeistInputWire.fromJson(row as Map<String, dynamic>);
        _latestInputs[input.userId] = input;
      }
    } catch (e) {
      debugPrint('[StickmanHeist] pollInputs error: $e');
    }
  }

  // ── Non-host input write loop ───────────────────────────────────────

  void _startInputWriteLoop(String gameId) {
    _inputWriteTimer?.cancel();
    _inputWriteTimer = Timer.periodic(
      const Duration(
          milliseconds: kStickmanHeistInputPollIntervalMs),
      (_) {
        if (state.amSpectator) return;
        _upsertInputRow(state.myInput);
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
                _inputWriteTimer == null &&
                !state.amSpectator) {
              _startInputWriteLoop(updated.id);
            }
            if (updated.isCompleted) {
              _cancelHostLoops();
              _inputWriteTimer?.cancel();
              _inputWriteTimer = null;
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
          .map((p) => StickmanHeistPlayerWire.fromJson(
              p as Map<String, dynamic>))
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
    _inputWriteTimer?.cancel();
    _inputWriteTimer = null;
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

  @override
  void dispose() {
    _cancelHostLoops();
    _inputWriteTimer?.cancel();
    _cleanupTimer?.cancel();
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

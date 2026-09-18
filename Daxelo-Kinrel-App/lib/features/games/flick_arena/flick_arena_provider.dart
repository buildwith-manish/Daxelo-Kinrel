// lib/features/games/flick_arena/flick_arena_provider.dart
//
// Flick Arena — Riverpod state + Supabase Realtime + Forge2D physics
// orchestration.
//
// Architecture:
//   • Supabase stores games + turns
//   • Supabase Realtime broadcasts board state changes
//   • The active player runs the Forge2D physics simulation locally
//   • When pieces settle, the final state is evaluated and broadcast
//   • A pg_cron-driven watchdog enforces the 15-second turn timer
//     (via fn_flickarena_tick, called by this provider's _watchdog timer)

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../game_motion_tokens.dart';
import '../shared/data/game_invite_chat_sync.dart';
import '../shared/services/room_presence_heartbeat.dart';
import '../shared/services/temporary_room_service.dart';
import 'flick_arena_constants.dart';
import 'flick_arena_engine.dart';
import 'flick_arena_models.dart';
import 'flick_arena_physics.dart';

class FlickArenaState_ {
  const FlickArenaState_({
    this.game,
    this.turns = const [],
    this.isLoading = false,
    this.isSimulating = false,
    this.isSubmitting = false,
    this.error,
    this.aimAngle,
    this.aimPower,
    this.selectedDiscId,
    this.liveDiscPositions = const {},
    this.liveBallPosition,
    this.lastTurnResult,
    this.amSpectator = false,
  });

  final FlickArenaGame? game;
  final List<FlickArenaTurnRecord> turns;
  final bool isLoading;
  final bool isSimulating;
  final bool isSubmitting;
  final String? error;

  // Aim state (local UI only) — set by drag gesture on the board.
  final double? aimAngle;
  final double? aimPower;
  final String? selectedDiscId;

  // Live physics positions (during simulation, for rendering).
  final Map<String, (double, double)> liveDiscPositions;
  final (double, double)? liveBallPosition;

  // Last turn result (for showing goal / no-goal feedback).
  final FlickTurnResult? lastTurnResult;

  final bool amSpectator;

  bool get isWaiting => game?.isWaiting ?? false;
  bool get isInProgress => game?.isInProgress ?? false;
  bool get isCompleted => game?.isCompleted ?? false;
  bool get hasGame => game != null;

  FlickArenaState_ copyWith({
    FlickArenaGame? game,
    List<FlickArenaTurnRecord>? turns,
    bool? isLoading,
    bool? isSimulating,
    bool? isSubmitting,
    String? error,
    bool clearError = false,
    double? aimAngle,
    double? aimPower,
    String? selectedDiscId,
    bool clearAim = false,
    bool clearSelectedDisc = false,
    Map<String, (double, double)>? liveDiscPositions,
    (double, double)? liveBallPosition,
    FlickTurnResult? lastTurnResult,
    bool clearTurnResult = false,
    bool? amSpectator,
  }) =>
      FlickArenaState_(
        game: game ?? this.game,
        turns: turns ?? this.turns,
        isLoading: isLoading ?? this.isLoading,
        isSimulating: isSimulating ?? this.isSimulating,
        isSubmitting: isSubmitting ?? this.isSubmitting,
        error: clearError ? null : (error ?? this.error),
        aimAngle: clearAim ? null : (aimAngle ?? this.aimAngle),
        aimPower: clearAim ? null : (aimPower ?? this.aimPower),
        selectedDiscId: clearSelectedDisc
            ? null
            : (selectedDiscId ?? this.selectedDiscId),
        liveDiscPositions: liveDiscPositions ?? this.liveDiscPositions,
        liveBallPosition: liveBallPosition ?? this.liveBallPosition,
        lastTurnResult:
            clearTurnResult ? null : (lastTurnResult ?? this.lastTurnResult),
        amSpectator: amSpectator ?? this.amSpectator,
      );
}

class FlickArenaNotifier extends StateNotifier<FlickArenaState_> {
  FlickArenaNotifier(this._ref, this.familyId) : super(const FlickArenaState_());

  final Ref _ref;
  final String familyId;

  SupabaseClient? get _client => _ref.read(supabaseProvider);
  String? get _myId => _client?.auth.currentUser?.id;
  String get _myName =>
      _client?.auth.currentUser?.userMetadata?['name'] as String? ?? 'Player';

  RealtimeChannel? _channel;
  RoomPresenceHeartbeat? _heartbeat;
  String? _gameId;
  FlickArenaPhysicsEngine? _physics;
  Timer? _simTimer;
  Timer? _watchdogTimer;
  Timer? _cleanupTimer;
  int _simStepCount = 0;
  double _simAccumulatedShotDistance = 0;
  String? _activeSimDiscId;
  (double, double)? _activeSimDiscStart;

  // ── Public API ───────────────────────────────────────────────────

  /// Host: create a new room.
  ///
  /// [matchType] determines maxPlayers (solo_duel = 2, team_battle = 4)
  /// and goals-to-win (solo_duel = 3, team_battle = 5).
  Future<String?> createRoom({
    required FlickArenaMatchType matchType,
    required bool spectatorsEnabled,
    String? roomName,
  }) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) {
      state = state.copyWith(error: 'Not signed in');
      return null;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final initialBoard = createInitialBoard(matchType);
      final turnOrder = defaultTurnOrder(matchType);
      final teamAssignment = defaultTeamAssignment(matchType);
      final maxPlayers = matchType.maxPlayers;
      final deadline = DateTime.now().add(const Duration(minutes: 5));

      final body = <String, dynamic>{
        'familyId': familyId,
        'hostUserId': myId,
        'hostUserName': _myName,
        if (roomName != null && roomName.trim().isNotEmpty)
          'roomName': roomName.trim(),
        'matchType': matchType.wire,
        'maxPlayers': maxPlayers,
        'playerOneId': myId,
        'playerOneName': _myName,
        'currentTurnSlot': 1,
        'currentTurnPlayerId': myId,
        'currentTurnPlayerName': _myName,
        'status': 'waiting',
        'teamOneScore': 0,
        'teamTwoScore': 0,
        'boardState': initialBoard.toJson(),
        'turnOrder': turnOrder,
        'teamAssignment': teamAssignment
            .map((k, v) => MapEntry(k.toString(), v)),
        'spectatorsEnabled': spectatorsEnabled,
        'hostReady': true,
        'autoCloseDeadline': deadline.toIso8601String(),
      };

      final resp = await client
          .from('flick_arena_games')
          .insert(body)
          .select()
          .single();
      final game = FlickArenaGame.fromJson(resp);
      _gameId = game.id;

      await client.rpc('fn_record_room_join', params: {
        'p_game_table': 'flick_arena_games',
        'p_game_id': game.id,
        'p_family_id': familyId,
        'p_user_id': myId,
        'p_user_name': _myName,
        'p_role': 'host',
      });

      state = state.copyWith(game: game, isLoading: false);
      _subscribeToRealtime(game.id);
      return game.id;
    } catch (e) {
      debugPrint('[FlickArena] createRoom error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
      return null;
    }
  }

  /// Non-host: join an existing room.
  ///
  /// • Room closed / deleted → friendly error (create a new room).
  /// • Waiting + free slot → take it (first member to join wins the slot).
  /// • Waiting + all slots filled → 'Game is full'.
  /// • Match already running → spectate read-only.
  Future<bool> joinRoom(String gameId) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) {
      state = state.copyWith(error: 'Not signed in');
      return false;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      var gameResp = await client
          .from('flick_arena_games')
          .select()
          .eq('id', gameId)
          .maybeSingle();
      if (isRoomRowClosed(gameResp)) {
        state = state.copyWith(isLoading: false, error: kRoomClosedMessage);
        return false;
      }
      var game = FlickArenaGame.fromJson(gameResp as Map<String, dynamic>);
      _gameId = game.id;

      final alreadyInGame = game.slotForUserId(myId) != null;

      if (!alreadyInGame) {
        if (game.isWaiting) {
          // Find first empty slot and take it.
          final updateBody = <String, dynamic>{};
          String? slotField;
          if (game.playerOneId.isEmpty) {
            updateBody['playerOneId'] = myId;
            updateBody['playerOneName'] = _myName;
            slotField = 'playerOneId';
          } else if (game.playerTwoId.isEmpty) {
            updateBody['playerTwoId'] = myId;
            updateBody['playerTwoName'] = _myName;
            slotField = 'playerTwoId';
          } else if (game.matchType == FlickArenaMatchType.teamBattle) {
            if (game.playerThreeId.isEmpty) {
              updateBody['playerThreeId'] = myId;
              updateBody['playerThreeName'] = _myName;
              slotField = 'playerThreeId';
            } else if (game.playerFourId.isEmpty) {
              updateBody['playerFourId'] = myId;
              updateBody['playerFourName'] = _myName;
              slotField = 'playerFourId';
            }
          }
          if (slotField == null) {
            state = state.copyWith(
              isLoading: false,
              error: 'Game is full',
            );
            return false;
          }
          await client
              .from('flick_arena_games')
              .update(updateBody)
              .eq('id', gameId);
          await client.rpc('fn_record_room_join', params: {
            'p_game_table': 'flick_arena_games',
            'p_game_id': gameId,
            'p_family_id': familyId,
            'p_user_id': myId,
            'p_user_name': _myName,
            'p_role': 'player',
          });
          await _ref.read(temporaryRoomServiceProvider).touchActivity(
                gameTable: 'flick_arena_games',
                gameId: gameId,
              );
          // Re-fetch.
          gameResp = await client
              .from('flick_arena_games')
              .select()
              .eq('id', gameId)
              .maybeSingle();
          if (gameResp != null) {
            game = FlickArenaGame.fromJson(gameResp);
          }
        } else if (game.isInProgress) {
          await client.rpc('fn_spectate_game', params: {
            'p_game_table': 'flick_arena_games',
            'p_game_id': gameId,
            'p_family_id': familyId,
            'p_user_id': myId,
            'p_user_name': _myName,
          });
          state = state.copyWith(amSpectator: true);
        }
      }

      state = state.copyWith(game: game, isLoading: false);
      _subscribeToRealtime(gameId);
      // Keep the persistent game-invite chat card in sync (best-effort).
      unawaited(
        syncGameInviteChatCards(
          client: client,
          gameId: gameId,
          currentPlayers: game.filledSlots,
        ),
      );
      return true;
    } catch (e) {
      debugPrint('[FlickArena] joinRoom error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
      return false;
    }
  }

  /// Host: start the match from the waiting room.
  Future<String?> startMatch() async {
    final client = _client;
    final gameId = _gameId;
    final game = state.game;
    final myId = _myId;
    if (client == null || gameId == null || game == null) {
      return 'No active room';
    }
    if (game.hostUserId != null && game.hostUserId != myId) {
      return 'Only the host can start';
    }
    if (game.filledSlots < 2) {
      return 'Waiting for more players to join';
    }
    try {
      // Set status in_progress, set startedAt, set first turnEndsAt.
      await client.from('flick_arena_games').update({
        'status': 'in_progress',
        'startedAt': DateTime.now().toIso8601String(),
        'turnEndsAt':
            DateTime.now().add(kFlickArenaTurnDuration).toIso8601String(),
        'lastActivityAt': DateTime.now().toIso8601String(),
      }).eq('id', gameId);
      try {
        await client.from('game_room_events').insert({
          'gameTable': 'flick_arena_games',
          'gameId': gameId,
          'familyId': familyId,
          'userId': myId,
          'userName': _myName,
          'eventType': 'match_start',
          'payload': {},
        });
      } catch (_) {}
      return null;
    } catch (e) {
      debugPrint('[FlickArena] startMatch error: $e');
      return 'Could not start the match';
    }
  }

  /// Leave the waiting room. Host → the room is closed and deleted for
  /// everyone; guest → their slot is freed for another family member.
  Future<void> leaveRoom() async {
    final client = _client;
    final gameId = _gameId;
    final myId = _myId;
    final game = state.game;
    if (client == null || gameId == null || myId == null) {
      _reset();
      return;
    }
    try {
      if (game != null && game.isWaiting) {
        if (game.hostUserId == myId) {
          await _ref.read(temporaryRoomServiceProvider).cancelWaitingRoom(
                gameTable: 'flick_arena_games',
                gameId: gameId,
              );
        } else {
          // Clear my slot
          final slot = game.slotForUserId(myId);
          if (slot != null) {
            final updateBody = <String, dynamic>{};
            switch (slot) {
              case 1:
                updateBody['playerOneId'] = '';
                updateBody['playerOneName'] = 'Player 1';
                break;
              case 2:
                updateBody['playerTwoId'] = '';
                updateBody['playerTwoName'] = 'Player 2';
                break;
              case 3:
                updateBody['playerThreeId'] = '';
                updateBody['playerThreeName'] = 'Player 3';
                break;
              case 4:
                updateBody['playerFourId'] = '';
                updateBody['playerFourName'] = 'Player 4';
                break;
            }
            await client
                .from('flick_arena_games')
                .update(updateBody)
                .eq('id', gameId);
          }
        }
      }
    } catch (_) {}
    _reset();
  }

  /// Leave an in-progress match. Delegates to fn_flickarena_leave which
  /// handles walkover scoring.
  Future<void> leaveInProgressMatch() async {
    final client = _client;
    final gameId = _gameId;
    if (client == null || gameId == null) {
      _reset();
      return;
    }
    try {
      await client.rpc('fn_flickarena_leave', params: {
        'p_game_id': gameId,
      });
    } catch (_) {}
    _reset();
  }

  void _reset() {
    _simTimer?.cancel();
    _simTimer = null;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _channel?.unsubscribe();
    _channel = null;
    _heartbeat?.stop();
    _heartbeat = null;
    _gameId = null;
    state = const FlickArenaState_();
  }

  /// Load an existing game (for the board screen).
  Future<bool> loadGame(String gameId) async {
    final client = _client;
    if (client == null) {
      state = state.copyWith(error: 'Not signed in');
      return false;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final gameResp = await client
          .from('flick_arena_games')
          .select()
          .eq('id', gameId)
          .maybeSingle();
      if (isRoomRowClosed(gameResp)) {
        state = const FlickArenaState_(error: kRoomClosedMessage);
        return false;
      }
      final game = FlickArenaGame.fromJson(gameResp as Map<String, dynamic>);
      _gameId = game.id;

      final turnsResp = await client
          .from('flick_arena_turns')
          .select()
          .eq('gameId', gameId)
          .order('turnNumber', ascending: true);
      final turns = turnsResp
          .map((t) => FlickArenaTurnRecord.fromJson(t))
          .toList();

      state = state.copyWith(game: game, turns: turns, isLoading: false);
      _subscribeToRealtime(gameId);
      return true;
    } catch (e) {
      debugPrint('[FlickArena] loadGame error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
      return false;
    }
  }

  // ── Aim / disc selection ─────────────────────────────────────────

  /// Mark a disc as the user's current selection (tapped on the board).
  /// Only the current player can select their own discs.
  void selectDisc(String discId) {
    final game = state.game;
    final myId = _myId;
    if (game == null || myId == null) return;
    if (game.currentTurnPlayerId != myId) return;
    final disc = game.boardState.discs
        .where((d) => d.id == discId && !d.isPotted)
        .firstOrNull;
    if (disc == null) return;
    if (disc.ownerSlot != game.slotForUserId(myId)) return;
    state = state.copyWith(selectedDiscId: discId);
  }

  void clearSelection() {
    state = state.copyWith(clearSelectedDisc: true, clearAim: true);
  }

  /// Set the aim angle and power (from drag gesture).
  void setAim(double angle, double power) {
    state = state.copyWith(aimAngle: angle, aimPower: power);
  }

  void clearAim() {
    state = state.copyWith(clearAim: true);
  }

  // ── Execute a flick ──────────────────────────────────────────────

  /// Execute a flick — runs the full physics simulation locally, then
  /// broadcasts the settled state to Supabase.
  ///
  /// [discId] — which of the current player's discs to flick.
  /// [angle]  — radians, the direction of the flick.
  /// [power]  — normalized 0.0 to 1.0.
  Future<bool> executeFlick({
    required String discId,
    required double angle,
    required double power,
  }) async {
    final game = state.game;
    final client = _client;
    final myId = _myId;
    if (game == null || client == null || myId == null) return false;
    if (game.currentTurnPlayerId != myId) return false;
    if (state.isSimulating) return false;

    // Validate disc ownership.
    final disc = game.boardState.discs
        .where((d) => d.id == discId && !d.isPotted)
        .firstOrNull;
    if (disc == null) return false;
    final mySlot = game.slotForUserId(myId);
    if (mySlot == null || disc.ownerSlot != mySlot) return false;

    // Setup physics with current board state.
    _physics = FlickArenaPhysicsEngine();
    _physics!.setup(
      discs: game.boardState.discs,
      ball: game.boardState.ball,
    );

    final applied = _physics!.flickDisc(
      discId: discId,
      angle: angle,
      power: power,
    );
    if (!applied) {
      _physics!.dispose();
      _physics = null;
      return false;
    }
    GameMotionTokens.tap();

    state = state.copyWith(
      isSimulating: true,
      aimAngle: angle,
      aimPower: power,
      selectedDiscId: discId,
      clearError: true,
    );

    _simStepCount = 0;
    _simAccumulatedShotDistance = 0;
    _activeSimDiscId = discId;
    _activeSimDiscStart = (disc.x, disc.y);

    // Run the simulation at 60fps.
    _simTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _simulationTick(angle, power, discId, mySlot),
    );

    return true;
  }

  void _simulationTick(
    double angle,
    double power,
    String discId,
    int shooterSlot,
  ) {
    if (_physics == null || !state.isSimulating) return;

    _physics!.step();
    _simStepCount++;

    // Read live positions for rendering.
    final discPositions = _physics!.readDiscPositions();
    final ballPos = _physics!.readBallPosition();
    state = state.copyWith(
      liveDiscPositions: discPositions,
      liveBallPosition: ballPos,
    );

    // Accumulate shot distance: integral of speed * dt over the steps.
    if (_activeSimDiscId != null) {
      final speed = _physics!.readDiscSpeed(_activeSimDiscId!);
      _simAccumulatedShotDistance +=
          speed * FlickArenaPhysics.timeStep;
    }

    final atRest = _physics!.isAtRest();
    final maxSteps = FlickArenaPhysics.maxSteps;

    if (atRest || _simStepCount >= maxSteps) {
      _simTimer?.cancel();
      _simTimer = null;
      _finalizeTurn(angle, power, discId, shooterSlot);
    }
  }

  Future<void> _finalizeTurn(
    double angle,
    double power,
    String discId,
    int shooterSlot,
  ) async {
    final game = state.game;
    final client = _client;
    final myId = _myId;
    if (game == null || client == null || myId == null) return;

    final physics = _physics;
    if (physics == null) return;

    // Read final positions.
    final finalDiscPositions = physics.readDiscPositions();
    final finalBallPos = physics.readBallPosition();

    // Build the updated board state (post-flick).
    final updatedDiscs = game.boardState.discs.map((d) {
      final pos = finalDiscPositions[d.id];
      if (pos == null) return d;
      return d.copyWith(x: pos.$1, y: pos.$2);
    }).toList();
    final updatedBall = finalBallPos != null
        ? FlickBall(x: finalBallPos.$1, y: finalBallPos.$2)
        : game.boardState.ball;

    final stateAfter = FlickArenaState(
      discs: updatedDiscs,
      ball: updatedBall,
      lastShooterSlot: shooterSlot,
    );

    // Evaluate the turn.
    final result = evaluateTurn(
      stateBefore: game.boardState,
      stateAfter: stateAfter,
      shooterSlot: shooterSlot,
      shooterUserId: myId,
      currentSlot: game.currentTurnSlot,
      turnOrder: game.turnOrder,
      teamOneScore: game.teamOneScore,
      teamTwoScore: game.teamTwoScore,
      matchType: game.matchType,
      shotDistance: _simAccumulatedShotDistance,
    );

    // Determine next player.
    final nextSlot = result.nextSlot;
    final (nextPlayerId, nextPlayerName) = result.gameOver
        ? ('', '')
        : game.playerForSlot(nextSlot);

    final updateBody = <String, dynamic>{
      'boardState': result.updatedState.toJson(),
      'currentTurnSlot': nextSlot,
      'currentTurnPlayerId': nextPlayerId,
      'currentTurnPlayerName': nextPlayerName,
      'teamOneScore':
          game.teamOneScore + result.teamOneScoreDelta,
      'teamTwoScore':
          game.teamTwoScore + result.teamTwoScoreDelta,
      'turnEndsAt': result.gameOver
          ? null
          : DateTime.now().add(kFlickArenaTurnDuration).toIso8601String(),
      'lastTurnSummary': {
        'shooterSlot': shooterSlot,
        'shooterUserId': myId,
        'discId': discId,
        'angle': angle,
        'force': power,
        'shotDistance': result.shotDistance,
        'goalScored': result.goalScored,
        'goalForTeam': result.goalForTeam,
      },
      'lastActivityAt': DateTime.now().toIso8601String(),
    };

    if (result.gameOver) {
      updateBody['status'] = 'completed';
      updateBody['completedAt'] = DateTime.now().toIso8601String();
      updateBody['winningTeam'] = result.winningTeam;
      // Winner user ids — collect from the winning team's slots.
      final winnerIds = <String>[];
      if (result.winningTeam != null) {
        for (final slot in game.turnOrder) {
          if (game.teamForSlot(slot) == result.winningTeam) {
            final (uid, _) = game.playerForSlot(slot);
            if (uid.isNotEmpty) winnerIds.add(uid);
          }
        }
      }
      updateBody['winnerUserIds'] = winnerIds;
      updateBody['endReason'] = 'goals_reached';
    }

    try {
      await client
          .from('flick_arena_games')
          .update(updateBody)
          .eq('id', game.id);

      // Insert turn record.
      final turnNumber = state.turns.length + 1;
      await client.from('flick_arena_turns').insert({
        'gameId': game.id,
        'playerId': myId,
        'playerName': _myName,
        'slotNumber': shooterSlot,
        'teamNumber': game.teamForSlot(shooterSlot),
        'discId': discId,
        'discStartX': _activeSimDiscStart?.$1 ?? 0,
        'discStartY': _activeSimDiscStart?.$1 ?? 0,
        'angle': angle,
        'force': power,
        'shotDistance': result.shotDistance,
        'scoredGoal': result.goalScored,
        'goalForTeam': result.goalForTeam,
        'wasAutoSkipped': false,
        'turnNumber': turnNumber,
      });

      // Haptics
      if (result.gameOver) {
        GameMotionTokens.celebrate();
      } else if (result.goalScored) {
        GameMotionTokens.success();
      }

      if (result.gameOver) {
        _scheduleRoomCleanup(game.id);
      }

      state = state.copyWith(
        isSimulating: false,
        isSubmitting: false,
        clearAim: true,
        clearSelectedDisc: true,
        lastTurnResult: result,
        liveDiscPositions: const {},
        liveBallPosition: null,
      );
    } catch (e) {
      debugPrint('[FlickArena] finalizeTurn error: $e');
      state = state.copyWith(
        isSimulating: false,
        error: '$e',
      );
    }

    physics.dispose();
    _physics = null;
    _activeSimDiscId = null;
    _activeSimDiscStart = null;
  }

  /// Schedule the temporary room (and all temporary player associations)
  /// for deletion 30s after the game ends. The hourly pg_cron job is the
  /// safety net if the user closes the app before this fires.
  void _scheduleRoomCleanup(String gameId) {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer(const Duration(seconds: 30), () {
      _ref.read(temporaryRoomServiceProvider).endGame(
            gameTable: 'flick_arena_games',
            gameId: gameId,
          );
    });
  }

  /// Rematch — create a new room with the same players + settings.
  Future<String?> rematch() async {
    final client = _client;
    final game = state.game;
    final myId = _myId;
    if (client == null || game == null || myId == null) return null;

    final newGameId = await createRoom(
      matchType: game.matchType,
      spectatorsEnabled: game.spectatorsEnabled,
      roomName: game.roomName,
    );
    if (newGameId == null) return null;

    try {
      // Re-add the other players to the new game (best-effort — we
      // only have their names, not their auth ids in some cases, but
      // we always have their userIds from the game row).
      final others = <int>[];
      for (final slot in game.turnOrder) {
        if (slot == 1 && game.playerOneId.isNotEmpty && game.playerOneId != myId) {
          others.add(1);
        } else if (slot == 2 && game.playerTwoId.isNotEmpty && game.playerTwoId != myId) {
          others.add(2);
        } else if (slot == 3 && game.playerThreeId.isNotEmpty && game.playerThreeId != myId) {
          others.add(3);
        } else if (slot == 4 && game.playerFourId.isNotEmpty && game.playerFourId != myId) {
          others.add(4);
        }
      }
      for (final slot in others) {
        final (uid, uname) = game.playerForSlot(slot);
        if (uid.isEmpty) continue;
        final slotUpdate = <String, dynamic>{};
        switch (slot) {
          case 1:
            slotUpdate['playerOneId'] = uid;
            slotUpdate['playerOneName'] = uname;
            break;
          case 2:
            slotUpdate['playerTwoId'] = uid;
            slotUpdate['playerTwoName'] = uname;
            break;
          case 3:
            slotUpdate['playerThreeId'] = uid;
            slotUpdate['playerThreeName'] = uname;
            break;
          case 4:
            slotUpdate['playerFourId'] = uid;
            slotUpdate['playerFourName'] = uname;
            break;
        }
        await client
            .from('flick_arena_games')
            .update(slotUpdate)
            .eq('id', newGameId);
        try {
          await client.rpc('fn_record_room_join', params: {
            'p_game_table': 'flick_arena_games',
            'p_game_id': newGameId,
            'p_family_id': familyId,
            'p_user_id': uid,
            'p_user_name': uname,
            'p_role': 'player',
          });
        } catch (_) {}

        // Send a rematch invite so they see it in their invite dialog.
        final roomCode =
            newGameId.replaceAll('-', '').substring(0, 6).toUpperCase();
        try {
          await client.from('game_invites').insert({
            'gameTable': 'flick_arena_games',
            'gameId': newGameId,
            'gameType': 'flick-arena',
            'familyId': familyId,
            'roomCode': roomCode,
            'invitedUserId': uid,
            'invitedByUserId': myId,
            'invitedByName': _myName,
            'maxPlayers': game.maxPlayers,
            'currentPlayers': 1,
            'message': '$_myName wants a Flick Arena rematch!',
            'status': 'pending',
            'sourceGameId': game.id,
          });
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[FlickArena] rematch error: $e');
    }
    return newGameId;
  }

  /// Leave the game (called when the user backs out of the screen).
  void leaveGame() {
    _simTimer?.cancel();
    _simTimer = null;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _physics?.dispose();
    _physics = null;
    _channel?.unsubscribe();
    _channel = null;
    _heartbeat?.stop();
    _heartbeat = null;
    _gameId = null;
  }

  // ── Realtime subscription ────────────────────────────────────────

  void _subscribeToRealtime(String gameId) {
    _channel?.unsubscribe();
    final client = _client;
    if (client == null) return;

    final myId = _myId;
    if (myId != null) {
      _heartbeat?.stop();
      _heartbeat = RoomPresenceHeartbeat('flick_arena_games')
        ..start(client, gameId, myId);
    }

    _channel = client
        .channel('flickarena_game:$gameId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'flick_arena_games',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: gameId,
          ),
          callback: (payload) {
            final updated =
                FlickArenaGame.fromJson(payload.newRecord);
            if (updated.isCompleted) {
              GameMotionTokens.celebrate();
            }
            state = state.copyWith(game: updated);
            // Restart the watchdog timer when a new turn begins.
            _ensureWatchdog(updated);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'flick_arena_turns',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: gameId,
          ),
          callback: (payload) {
            final turn =
                FlickArenaTurnRecord.fromJson(payload.newRecord);
            if (!state.turns.any((t) => t.id == turn.id)) {
              state = state.copyWith(turns: [...state.turns, turn]);
            }
          },
        )
        // Game row DELETE = the room was closed by the host (or the
        // opponent left) → fn_end_game hard-deleted it. Show a friendly
        // "room closed" state instead of hanging on a dead board.
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'flick_arena_games',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: gameId,
          ),
          callback: (payload) {
            debugPrint('[FlickArena] game row deleted — room closed');
            _channel?.unsubscribe();
            _channel = null;
            _gameId = null;
            // Completed games are archived + deleted server-side right
            // after the results screen renders — keep the in-memory
            // state so the results view survives the cleanup delete.
            if (state.game?.isCompleted ?? false) return;
            state = const FlickArenaState_(error: kRoomClosedMessage);
          },
        )
        .subscribe();

    // Kick off the watchdog timer for an in-progress match.
    if (state.game != null) {
      _ensureWatchdog(state.game!);
    }
  }

  /// Ensure the pg_cron-driven turn-timer watchdog is running while the
  /// match is in progress. It calls fn_flickarena_tick every 2 seconds,
  /// which advances the turn (auto-skip) when the 15-second timer
  /// expires.
  void _ensureWatchdog(FlickArenaGame game) {
    if (game.isInProgress) {
      _watchdogTimer ??= Timer.periodic(
        const Duration(seconds: 2),
        (_) {
          final id = _gameId;
          final client = _client;
          if (id == null || client == null) return;
          client.rpc('fn_flickarena_tick', params: {'p_game_id': id}).catchError(
            (e) {
              debugPrint('[FlickArena] tick error: $e');
              return null;
            },
          );
        },
      );
    } else {
      _watchdogTimer?.cancel();
      _watchdogTimer = null;
    }
  }

  @override
  void dispose() {
    _simTimer?.cancel();
    _watchdogTimer?.cancel();
    _cleanupTimer?.cancel();
    _physics?.dispose();
    _channel?.unsubscribe();
    _heartbeat?.stop();
    super.dispose();
  }
}

final flickArenaProvider = StateNotifierProvider.autoDispose
    .family<FlickArenaNotifier, FlickArenaState_, String>(
  (ref, familyId) => FlickArenaNotifier(ref, familyId),
);

// lib/features/games/carrom/carrom_provider.dart
//
// Carrom — Riverpod state + Supabase Realtime + Forge2D physics orchestration.
//
// Architecture:
//   • Supabase stores games + turns
//   • Supabase Realtime broadcasts board state changes
//   • The active player runs the Forge2D physics simulation locally
//   • When pieces settle, the final state is evaluated and broadcast
//   • The opponent sees the updated board state

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../game_motion_tokens.dart';
import 'carrom_constants.dart';
import 'carrom_game_logic.dart';
import 'carrom_models.dart';
import 'carrom_physics.dart';

class CarromState {
  const CarromState({
    this.game,
    this.turns = const [],
    this.isLoading = false,
    this.isSimulating = false,
    this.isSubmitting = false,
    this.error,
    this.aimAngle,
    this.aimPower,
    this.liveCoinPositions = const {},
    this.liveStrikerPosition,
    this.lastTurnResult,
  });

  final CarromGame? game;
  final List<CarromTurnRecord> turns;
  final bool isLoading;
  final bool isSimulating;
  final bool isSubmitting;
  final String? error;

  // Aim state (local UI only)
  final double? aimAngle;
  final double? aimPower;

  // Live physics positions (during simulation, for rendering)
  final Map<int, (double, double)> liveCoinPositions;
  final (double, double)? liveStrikerPosition;

  // Last turn result (for showing feedback)
  final TurnResult? lastTurnResult;

  bool get isWaiting => game?.isWaiting ?? false;
  bool get isInProgress => game?.isInProgress ?? false;
  bool get isCompleted => game?.isCompleted ?? false;
  bool get hasGame => game != null;

  CarromState copyWith({
    CarromGame? game,
    List<CarromTurnRecord>? turns,
    bool? isLoading,
    bool? isSimulating,
    bool? isSubmitting,
    String? error,
    bool clearError = false,
    double? aimAngle,
    double? aimPower,
    bool clearAim = false,
    Map<int, (double, double)>? liveCoinPositions,
    (double, double)? liveStrikerPosition,
    TurnResult? lastTurnResult,
    bool clearTurnResult = false,
  }) =>
      CarromState(
        game: game ?? this.game,
        turns: turns ?? this.turns,
        isLoading: isLoading ?? this.isLoading,
        isSimulating: isSimulating ?? this.isSimulating,
        isSubmitting: isSubmitting ?? this.isSubmitting,
        error: clearError ? null : (error ?? this.error),
        aimAngle: clearAim ? null : (aimAngle ?? this.aimAngle),
        aimPower: clearAim ? null : (aimPower ?? this.aimPower),
        liveCoinPositions: liveCoinPositions ?? this.liveCoinPositions,
        liveStrikerPosition:
            liveStrikerPosition ?? this.liveStrikerPosition,
        lastTurnResult:
            clearTurnResult ? null : (lastTurnResult ?? this.lastTurnResult),
      );
}

class CarromNotifier extends StateNotifier<CarromState> {
  CarromNotifier(this._ref, this.familyId) : super(const CarromState());

  final Ref _ref;
  final String familyId;

  SupabaseClient? get _client => _ref.read(supabaseProvider);
  String? get _myId => _client?.auth.currentUser?.id;
  String get _myName =>
      _client?.auth.currentUser?.userMetadata?['name'] as String? ?? 'Player';

  RealtimeChannel? _channel;
  String? _gameId;
  CarromPhysicsEngine? _physics;
  Timer? _simTimer;
  int _simStepCount = 0;

  // ── Public API ───────────────────────────────────────────────────

  /// Create a new game challenging [opponentId].
  Future<String?> createGame({
    required String opponentId,
    required String opponentName,
  }) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) {
      state = state.copyWith(error: 'Not signed in');
      return null;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final initialBoard = createInitialBoard();
      final strikerPos = defaultStrikerPosition(1);

      final body = {
        'familyId': familyId,
        'playerOneId': myId,
        'playerOneName': _myName,
        'playerTwoId': opponentId,
        'playerTwoName': opponentName,
        'currentTurnPlayerId': myId,
        'status': 'in_progress',
        'playerOneColor': CarromCoinType.white.name,
        'playerTwoColor': CarromCoinType.black.name,
        'boardState': initialBoard.map((c) => c.toJson()).toList(),
        'strikerX': strikerPos.x,
        'strikerY': strikerPos.y,
        'queenStatus': CarromQueenStatus.onBoard.name,
      };
      final resp = await client
          .from('carrom_games')
          .insert(body)
          .select()
          .single();
      final game = CarromGame.fromJson(resp as Map<String, dynamic>);
      _gameId = game.id;

      state = state.copyWith(game: game, isLoading: false);
      _subscribeToRealtime(game.id);
      return game.id;
    } catch (e) {
      debugPrint('[Carrom] createGame error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
      return null;
    }
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
          .from('carrom_games')
          .select()
          .eq('id', gameId)
          .single();
      final game = CarromGame.fromJson(gameResp as Map<String, dynamic>);
      _gameId = game.id;

      final turnsResp = await client
          .from('carrom_turns')
          .select()
          .eq('gameId', gameId)
          .order('turnNumber', ascending: true);
      final turns = turnsResp
          .map((t) => CarromTurnRecord.fromJson(t as Map<String, dynamic>))
          .toList();

      state = state.copyWith(game: game, turns: turns, isLoading: false);
      _subscribeToRealtime(gameId);
      return true;
    } catch (e) {
      debugPrint('[Carrom] loadGame error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
      return false;
    }
  }

  /// Set the aim angle and power (from drag gesture).
  void setAim(double angle, double power) {
    state = state.copyWith(aimAngle: angle, aimPower: power);
  }

  void clearAim() {
    state = state.copyWith(clearAim: true);
  }

  /// Execute a flick — runs the full physics simulation locally,
  /// then broadcasts the settled state to Supabase.
  Future<bool> executeFlick(double angle, double power) async {
    final game = state.game;
    final client = _client;
    final myId = _myId;
    if (game == null || client == null || myId == null) return false;
    if (game.currentTurnPlayerId != myId) return false;
    if (state.isSimulating) return false;

    // Set up the physics engine with the current board state
    _physics = CarromPhysicsEngine();
    _physics!.setup(
      coins: game.boardState,
      strikerX: game.strikerX,
      strikerY: game.strikerY,
    );

    // Apply the flick impulse
    _physics!.flickStriker(angle, power);
    GameMotionTokens.tap();

    state = state.copyWith(
      isSimulating: true,
      aimAngle: angle,
      aimPower: power,
      clearError: true,
    );

    _simStepCount = 0;

    // Run the simulation in a timer at 60fps
    _simTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _simulationTick(angle, power),
    );

    return true;
  }

  void _simulationTick(double angle, double power) {
    if (_physics == null || !state.isSimulating) return;

    // Step the physics
    _physics!.step();
    _simStepCount++;

    // Read live positions for rendering
    final coinPositions = _physics!.readCoinPositions();
    final strikerPos = _physics!.readStrikerPosition();
    state = state.copyWith(
      liveCoinPositions: coinPositions,
      liveStrikerPosition: strikerPos,
    );

    // Check for potted coins mid-simulation and remove them
    final pottedMidSim = _physics!.checkPottedCoins();
    if (pottedMidSim.isNotEmpty) {
      _physics!.removePottedCoins(pottedMidSim);
    }

    // Check for potted striker
    if (_physics!.isStrikerPotted()) {
      _physics!.removeStriker();
    }

    // Check if simulation should stop
    final atRest = _physics!.isAtRest();
    final maxSteps = CarromPhysics.maxSteps;

    if (atRest || _simStepCount >= maxSteps) {
      _simTimer?.cancel();
      _simTimer = null;
      _finalizeTurn(angle, power);
    }
  }

  Future<void> _finalizeTurn(double angle, double power) async {
    final game = state.game;
    final client = _client;
    final myId = _myId;
    if (game == null || client == null || myId == null) return;

    final physics = _physics;
    if (physics == null) return;

    // Read final positions
    final finalCoinPositions = physics.readCoinPositions();
    final strikerPotted = physics.isStrikerPotted() ||
        (physics.readStrikerPosition() == null);

    // Build the updated board state
    final updatedCoins = List<CarromCoin>.from(game.boardState);
    for (int i = 0; i < updatedCoins.length; i++) {
      if (finalCoinPositions.containsKey(i)) {
        final (x, y) = finalCoinPositions[i]!;
        // Check if this coin was potted during the simulation
        final wasPotted = !updatedCoins[i].isPotted &&
            _wasCoinPotted(i, physics);
        updatedCoins[i] = updatedCoins[i].copyWith(
          x: x,
          y: y,
          isPotted: updatedCoins[i].isPotted || wasPotted,
        );
      }
    }

    // Determine player colors
    final myColor = game.colorFor(myId) ?? CarromCoinType.white;
    final opponentId = myId == game.playerOneId
        ? game.playerTwoId
        : game.playerOneId;
    final opponentColor = game.colorFor(opponentId) ?? CarromCoinType.black;

    // Evaluate the turn
    final result = evaluateTurn(
      coinsBefore: game.boardState,
      coinsAfter: updatedCoins,
      playerId: myId,
      playerColor: myColor,
      opponentId: opponentId,
      opponentColor: opponentColor,
      queenStatusBefore: game.queenStatus,
      queenPottedByBefore: game.queenPottedBy,
      strikerPotted: strikerPotted,
      playerOneScore: game.playerOneScore,
      playerTwoScore: game.playerTwoScore,
      playerOneId: game.playerOneId,
      playerTwoId: game.playerTwoId,
    );

    // Determine new striker position for next turn
    final nextPlayerNumber = game.playerNumberFor(result.nextPlayerId) ?? 1;
    final newStrikerPos = defaultStrikerPosition(nextPlayerNumber);

    // Update the game in Supabase
    final updateBody = <String, dynamic>{
      'boardState': result.updatedCoins.map((c) => c.toJson()).toList(),
      'currentTurnPlayerId': result.nextPlayerId,
      'playerOneScore': game.playerOneScore + result.playerOneScoreDelta,
      'playerTwoScore': game.playerTwoScore + result.playerTwoScoreDelta,
      'queenStatus': result.updatedQueenStatus.name,
      'queenPottedBy': result.queenPotted
          ? myId
          : (result.queenCovered ? myId : game.queenPottedBy),
      'strikerX': newStrikerPos.x,
      'strikerY': newStrikerPos.y,
      'lastTurnSummary': {
        'potted': result.pottedCoins.map((t) => t.name).toList(),
        'foul': result.wasFoul,
        'foulReason': result.foulReason,
        'extraTurn': result.extraTurn,
        'queenPotted': result.queenPotted,
        'queenCovered': result.queenCovered,
      },
    };

    if (result.gameOver) {
      updateBody['status'] = 'completed';
      updateBody['completedAt'] = DateTime.now().toIso8601String();
      updateBody['winnerId'] = result.winnerId;
      updateBody['winnerName'] = result.winnerId == game.playerOneId
          ? game.playerOneName
          : game.playerTwoName;
    }

    try {
      await client.from('carrom_games').update(updateBody).eq('id', game.id);

      // Insert turn record
      final turnNumber = state.turns.length + 1;
      await client.from('carrom_turns').insert({
        'gameId': game.id,
        'playerId': myId,
        'playerName': _myName,
        'strikerStartX': game.strikerX,
        'strikerStartY': game.strikerY,
        'angle': angle,
        'force': power,
        'pottedCoins': result.pottedCoins.map((t) => t.name).toList(),
        'wasFoul': result.wasFoul,
        'foulReason': result.foulReason,
        'extraTurn': result.extraTurn,
        'queenPotted': result.queenPotted,
        'queenCovered': result.queenCovered,
        'turnNumber': turnNumber,
      });

      // Haptics
      if (result.gameOver) {
        GameMotionTokens.celebrate();
      } else if (result.wasFoul) {
        GameMotionTokens.error();
      } else if (result.extraTurn) {
        GameMotionTokens.success();
      }

      state = state.copyWith(
        isSimulating: false,
        isSubmitting: false,
        clearAim: true,
        lastTurnResult: result,
        liveCoinPositions: const {},
        liveStrikerPosition: null,
      );
    } catch (e) {
      debugPrint('[Carrom] finalizeTurn error: $e');
      state = state.copyWith(
        isSimulating: false,
        error: '$e',
      );
    }

    // Clean up physics
    physics.dispose();
    _physics = null;
  }

  /// Check if a coin at the given index was potted during the simulation.
  /// We track this by checking if the coin body was removed.
  bool _wasCoinPotted(int coinIndex, CarromPhysicsEngine physics) {
    // The coin body was removed if it's no longer in the physics engine.
    // We check by trying to find it in the remaining bodies.
    // Since removePottedCoins removes them, if the coin's index is not
    // in the current coinIndices list, it was potted.
    // But we already updated the positions map, so we need a different approach.
    // Simplest: check if the coin's final position is inside a pocket.
    final positions = physics.readCoinPositions();
    if (!positions.containsKey(coinIndex)) return true; // body was removed
    final (x, y) = positions[coinIndex]!;
    final pos = math.Point(x, y);
    for (final pocket in CarromBoard.pocketPositions) {
      if (pos.distanceTo(math.Point(pocket.x, pocket.y)) <
          CarromBoard.pocketRadius) {
        return true;
      }
    }
    return false;
  }

  /// Leave the game.
  void leaveGame() {
    _simTimer?.cancel();
    _simTimer = null;
    _physics?.dispose();
    _physics = null;
    _channel?.unsubscribe();
    _channel = null;
    _gameId = null;
  }

  // ── Realtime subscription ────────────────────────────────────────

  void _subscribeToRealtime(String gameId) {
    _channel?.unsubscribe();
    final client = _client;
    if (client == null) return;

    _channel = client
        .channel('carrom_game:$gameId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'carrom_games',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: gameId,
          ),
          callback: (payload) {
            final updated = CarromGame.fromJson(payload.newRecord);
            if (updated.isCompleted) {
              GameMotionTokens.celebrate();
            }
            state = state.copyWith(game: updated);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'carrom_turns',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: gameId,
          ),
          callback: (payload) {
            final turn = CarromTurnRecord.fromJson(payload.newRecord);
            if (!state.turns.any((t) => t.id == turn.id)) {
              state = state.copyWith(turns: [...state.turns, turn]);
            }
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _simTimer?.cancel();
    _physics?.dispose();
    _channel?.unsubscribe();
    super.dispose();
  }
}

final carromProvider = StateNotifierProvider.autoDispose
    .family<CarromNotifier, CarromState, String>(
  (ref, familyId) => CarromNotifier(ref, familyId),
);

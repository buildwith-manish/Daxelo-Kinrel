// lib/features/games/checkers/checkers_provider.dart
//
// Checkers — Riverpod state + Supabase Realtime for live move sync.
//
// Architecture:
//   • Supabase stores games + moves
//   • Game logic (validation, captures, multi-jump, king promotion) runs
//     client-side via checkers_game_logic.dart — same logic runs on both
//     players' devices, ensuring consistency
//   • Supabase Realtime broadcasts board state updates + new moves
//   • The current player applies a move locally (validation + state update),
//     then persists the new board state + move record to Supabase

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../game_motion_tokens.dart';
import 'checkers_game_logic.dart';
import 'checkers_models.dart';

class CheckersState {
  const CheckersState({
    this.game,
    this.moves = const [],
    this.isLoading = false,
    this.isSubmitting = false,
    this.error,
    this.selectedRow,
    this.selectedCol,
    this.legalMoves = const [],
    this.lastMove,
    this.lastCapture,
    this.lastKingPromotion,
  });

  final CheckersGame? game;
  final List<CheckersMoveRecord> moves;
  final bool isLoading;
  final bool isSubmitting;
  final String? error;

  // Selection state (UI-only, not persisted)
  final int? selectedRow;
  final int? selectedCol;
  final List<CheckersMove> legalMoves;

  // Animation triggers (UI-only)
  final CheckersMove? lastMove;
  final CheckersMove? lastCapture;
  final (int, int)? lastKingPromotion; // (row, col) of the promoted piece

  bool get isWaiting => game?.isWaiting ?? false;
  bool get isInProgress => game?.isInProgress ?? false;
  bool get isCompleted => game?.isCompleted ?? false;
  bool get hasGame => game != null;

  CheckersState copyWith({
    CheckersGame? game,
    List<CheckersMoveRecord>? moves,
    bool? isLoading,
    bool? isSubmitting,
    String? error,
    bool clearError = false,
    int? selectedRow,
    int? selectedCol,
    bool clearSelection = false,
    List<CheckersMove>? legalMoves,
    CheckersMove? lastMove,
    CheckersMove? lastCapture,
    (int, int)? lastKingPromotion,
    bool clearAnimTriggers = false,
  }) =>
      CheckersState(
        game: game ?? this.game,
        moves: moves ?? this.moves,
        isLoading: isLoading ?? this.isLoading,
        isSubmitting: isSubmitting ?? this.isSubmitting,
        error: clearError ? null : (error ?? this.error),
        selectedRow: clearSelection ? null : (selectedRow ?? this.selectedRow),
        selectedCol: clearSelection ? null : (selectedCol ?? this.selectedCol),
        legalMoves: legalMoves ?? this.legalMoves,
        lastMove: clearAnimTriggers ? null : (lastMove ?? this.lastMove),
        lastCapture:
            clearAnimTriggers ? null : (lastCapture ?? this.lastCapture),
        lastKingPromotion: clearAnimTriggers
            ? null
            : (lastKingPromotion ?? this.lastKingPromotion),
      );
}

class CheckersNotifier extends StateNotifier<CheckersState> {
  CheckersNotifier(this._ref, this.familyId) : super(const CheckersState());

  final Ref _ref;
  final String familyId;

  SupabaseClient? get _client => _ref.read(supabaseProvider);
  String? get _myId => _client?.auth.currentUser?.id;
  String get _myName =>
      _client?.auth.currentUser?.userMetadata?['name'] as String? ?? 'Player';

  RealtimeChannel? _channel;
  String? _gameId;

  // ── Public API ───────────────────────────────────────────────────

  /// Create a new game challenging [opponentId].
  /// Player One (red) is the creator; Player Two (black) is the opponent.
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
      final body = {
        'familyId': familyId,
        'playerOneId': myId,
        'playerOneName': _myName,
        'playerTwoId': opponentId,
        'playerTwoName': opponentName,
        'currentTurnPlayerId': myId, // red moves first
        'boardState': boardToJson(initialBoard),
        'status': 'in_progress',
        'mandatoryCapturePending': false,
        'playerOneCaptured': 0,
        'playerTwoCaptured': 0,
        'startedAt': DateTime.now().toIso8601String(),
      };
      final resp = await client
          .from('checkers_games')
          .insert(body)
          .select()
          .single();
      final game = CheckersGame.fromJson(resp as Map<String, dynamic>);
      _gameId = game.id;

      state = state.copyWith(game: game, isLoading: false);
      _subscribeToRealtime(game.id);
      return game.id;
    } catch (e) {
      debugPrint('[Checkers] createGame error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
      return null;
    }
  }

  /// Join an existing game (load state for the board screen).
  Future<bool> loadGame(String gameId) async {
    final client = _client;
    if (client == null) {
      state = state.copyWith(error: 'Not signed in');
      return false;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final gameResp = await client
          .from('checkers_games')
          .select()
          .eq('id', gameId)
          .single();
      final game = CheckersGame.fromJson(gameResp as Map<String, dynamic>);
      _gameId = game.id;

      final movesResp = await client
          .from('checkers_moves')
          .select()
          .eq('gameId', gameId)
          .order('moveNumber', ascending: true);
      final moves = movesResp
          .map((m) => CheckersMoveRecord.fromJson(m as Map<String, dynamic>))
          .toList();

      state = state.copyWith(game: game, moves: moves, isLoading: false);
      _subscribeToRealtime(gameId);
      return true;
    } catch (e) {
      debugPrint('[Checkers] loadGame error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
      return false;
    }
  }

  /// Select a piece at (row, col). Updates legal moves for that piece.
  void selectPiece(int row, int col) {
    final game = state.game;
    if (game == null || !game.isInProgress) return;
    final myId = _myId;
    if (myId == null) return;

    // Can only select your own pieces on your turn
    final piece = game.boardState[row][col];
    if (piece == null) return;
    if (piece.player != game.playerNumberFor(myId)) return;
    if (game.currentTurnPlayerId != myId) return;

    final legalMoves = getLegalMovesForPiece(
      game.boardState,
      row,
      col,
      forcedPieceRow: game.multiJumpPieceRow,
      forcedPieceCol: game.multiJumpPieceCol,
    );

    state = state.copyWith(
      selectedRow: row,
      selectedCol: col,
      legalMoves: legalMoves,
    );
    GameMotionTokens.tap();
  }

  /// Clear the current selection.
  void clearSelection() {
    state = state.copyWith(clearSelection: true, legalMoves: const []);
  }

  /// Attempt to move the selected piece to (toRow, toCol).
  Future<bool> makeMove(int toRow, int toCol) async {
    final game = state.game;
    final client = _client;
    final myId = _myId;
    if (game == null || client == null || myId == null) return false;
    if (state.selectedRow == null || state.selectedCol == null) return false;

    final fromRow = state.selectedRow!;
    final fromCol = state.selectedCol!;

    // Find the matching legal move
    final move = state.legalMoves
        .where((m) => m.toRow == toRow && m.toCol == toCol)
        .firstOrNull;
    if (move == null) {
      GameMotionTokens.error();
      return false;
    }

    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      // Apply the move locally
      final result = applyMove(game.boardState, move);
      final myPlayerNumber = game.playerNumberFor(myId)!;
      final opponentPlayerNumber = myPlayerNumber == 1 ? 2 : 1;

      // Update captured count
      int newPlayerOneCaptured = game.playerOneCaptured;
      int newPlayerTwoCaptured = game.playerTwoCaptured;
      if (move.isCapture) {
        if (myPlayerNumber == 1) {
          newPlayerOneCaptured++;
        } else {
          newPlayerTwoCaptured++;
        }
      }

      // Determine if multi-jump continues
      final continuesCapture = result.canContinueCapture;

      // Determine next turn player
      String nextTurnPlayerId;
      bool newMandatoryCapturePending = false;
      int? newMultiJumpRow;
      int? newMultiJumpCol;

      if (continuesCapture) {
        // Same player continues
        nextTurnPlayerId = myId;
        newMandatoryCapturePending = true;
        newMultiJumpRow = move.toRow;
        newMultiJumpCol = move.toCol;
      } else {
        // Switch turns
        nextTurnPlayerId = game.idForPlayer(opponentPlayerNumber)!;
        newMandatoryCapturePending = false;
        newMultiJumpRow = null;
        newMultiJumpCol = null;
      }

      // Check game over
      final nextPlayerNumber = continuesCapture
          ? myPlayerNumber
          : opponentPlayerNumber;
      final winner = checkGameOver(result.board, nextPlayerNumber);

      // Build update
      final updateBody = <String, dynamic>{
        'boardState': boardToJson(result.board),
        'currentTurnPlayerId': nextTurnPlayerId,
        'mandatoryCapturePending': newMandatoryCapturePending,
        'multiJumpPieceRow': newMultiJumpRow,
        'multiJumpPieceCol': newMultiJumpCol,
        'playerOneCaptured': newPlayerOneCaptured,
        'playerTwoCaptured': newPlayerTwoCaptured,
      };

      if (winner != null) {
        updateBody['status'] = 'completed';
        updateBody['completedAt'] = DateTime.now().toIso8601String();
        updateBody['winnerId'] = game.idForPlayer(winner);
        updateBody['winnerName'] = game.nameForPlayer(winner);
      }

      // Insert move record
      final moveNumber = state.moves.length + 1;
      await client.from('checkers_moves').insert({
        'gameId': game.id,
        'playerId': myId,
        'playerName': _myName,
        'fromRow': fromRow,
        'fromCol': fromCol,
        'toRow': toRow,
        'toCol': toCol,
        'wasCapture': move.isCapture,
        'capturedRow': move.capturedRow,
        'capturedCol': move.capturedCol,
        'becameKing': result.becameKing,
        'moveNumber': moveNumber,
      });

      // Update game state
      await client
          .from('checkers_games')
          .update(updateBody)
          .eq('id', game.id);

      // Update local state immediately for responsive UI
      final updatedGame = CheckersGame(
        id: game.id,
        familyId: game.familyId,
        playerOneId: game.playerOneId,
        playerOneName: game.playerOneName,
        playerTwoId: game.playerTwoId,
        playerTwoName: game.playerTwoName,
        currentTurnPlayerId: nextTurnPlayerId,
        boardState: result.board,
        status: winner != null
            ? CheckersStatus.completed
            : CheckersStatus.inProgress,
        winnerId: winner != null ? game.idForPlayer(winner) : null,
        winnerName: winner != null ? game.nameForPlayer(winner) : null,
        mandatoryCapturePending: newMandatoryCapturePending,
        multiJumpPieceRow: newMultiJumpRow,
        multiJumpPieceCol: newMultiJumpCol,
        playerOneCaptured: newPlayerOneCaptured,
        playerTwoCaptured: newPlayerTwoCaptured,
        startedAt: game.startedAt,
        completedAt: winner != null ? DateTime.now() : null,
        createdAt: game.createdAt,
      );

      // Haptics
      if (winner != null) {
        GameMotionTokens.celebrate();
      } else if (move.isCapture) {
        GameMotionTokens.success();
      } else {
        GameMotionTokens.tap();
      }

      state = state.copyWith(
        game: updatedGame,
        isSubmitting: false,
        clearSelection: true,
        legalMoves: const [],
        lastMove: move,
        lastCapture: move.isCapture ? move : null,
        lastKingPromotion:
            result.becameKing ? (move.toRow, move.toCol) : null,
      );

      return true;
    } catch (e) {
      debugPrint('[Checkers] makeMove error: $e');
      state = state.copyWith(isSubmitting: false, error: '$e');
      return false;
    }
  }

  /// Leave the game (manual exit).
  void leaveGame() {
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
        .channel('checkers_game:$gameId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'checkers_games',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: gameId,
          ),
          callback: (payload) {
            final updated = CheckersGame.fromJson(payload.newRecord);
            state = state.copyWith(game: updated);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'checkers_moves',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: gameId,
          ),
          callback: (payload) {
            final move = CheckersMoveRecord.fromJson(payload.newRecord);
            if (!state.moves.any((m) => m.id == move.id)) {
              state = state.copyWith(moves: [...state.moves, move]);
            }
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }
}

final checkersProvider = StateNotifierProvider.autoDispose
    .family<CheckersNotifier, CheckersState, String>(
  (ref, familyId) => CheckersNotifier(ref, familyId),
);

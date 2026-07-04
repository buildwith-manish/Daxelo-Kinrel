// lib/features/games/chess/chess_provider.dart
//
// Chess — Riverpod state + Supabase Realtime + chess.dart logic engine.
//
// Architecture:
//   • Supabase stores games + moves
//   • Supabase Realtime broadcasts board state + new moves
//   • The chess.dart package (MIT+BSD) handles all rules: move validation,
//     check/checkmate/stalemate, castling, en passant, promotion, FEN, SAN
//   • The current player applies a move locally (validated by chess.dart),
//     then persists the new FEN + move record to Supabase
//
// License attribution: chess.dart is MIT licensed (David Kopec) + BSD-2
// (Jeff Hlywa's chess.js). All UI is original to Kinrel.

import 'dart:async';

import 'package:chess/chess.dart' as chess;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../game_motion_tokens.dart';
import 'chess_models.dart';

class ChessState {
  const ChessState({
    this.game,
    this.moves = const [],
    this.isLoading = false,
    this.isSubmitting = false,
    this.error,
    this.selectedSquare,
    this.legalDestinations = const [],
    this.lastMove,
    this.inCheck = false,
    this.isCheckmate = false,
    this.isStalemate = false,
  });

  final ChessGame? game;
  final List<ChessMoveRecord> moves;
  final bool isLoading;
  final bool isSubmitting;
  final String? error;

  // Selection state (UI-only)
  final String? selectedSquare; // e.g. 'e2'
  final List<String> legalDestinations; // e.g. ['e3', 'e4']

  // Animation trigger
  final (String, String)? lastMove; // (from, to)

  // Game state flags (derived from chess.dart)
  final bool inCheck;
  final bool isCheckmate;
  final bool isStalemate;

  bool get isWaiting => game?.isWaiting ?? false;
  bool get isInProgress => game?.isInProgress ?? false;
  bool get isCompleted => game?.isCompleted ?? false;
  bool get hasGame => game != null;

  ChessState copyWith({
    ChessGame? game,
    List<ChessMoveRecord>? moves,
    bool? isLoading,
    bool? isSubmitting,
    String? error,
    bool clearError = false,
    String? selectedSquare,
    bool clearSelection = false,
    List<String>? legalDestinations,
    (String, String)? lastMove,
    bool? inCheck,
    bool? isCheckmate,
    bool? isStalemate,
  }) =>
      ChessState(
        game: game ?? this.game,
        moves: moves ?? this.moves,
        isLoading: isLoading ?? this.isLoading,
        isSubmitting: isSubmitting ?? this.isSubmitting,
        error: clearError ? null : (error ?? this.error),
        selectedSquare:
            clearSelection ? null : (selectedSquare ?? this.selectedSquare),
        legalDestinations: legalDestinations ?? this.legalDestinations,
        lastMove: lastMove ?? this.lastMove,
        inCheck: inCheck ?? this.inCheck,
        isCheckmate: isCheckmate ?? this.isCheckmate,
        isStalemate: isStalemate ?? this.isStalemate,
      );
}

class ChessNotifier extends StateNotifier<ChessState> {
  ChessNotifier(this._ref, this.familyId) : super(const ChessState());

  final Ref _ref;
  final String familyId;

  SupabaseClient? get _client => _ref.read(supabaseProvider);
  String? get _myId => _client?.auth.currentUser?.id;
  String get _myName =>
      _client?.auth.currentUser?.userMetadata?['name'] as String? ?? 'Player';

  RealtimeChannel? _channel;
  String? _gameId;
  chess.Chess? _logic;

  // ── Public API ───────────────────────────────────────────────────

  /// Create a new game challenging [opponentId].
  /// Creator plays White (moves first); opponent plays Black.
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
      final body = {
        'familyId': familyId,
        'playerWhiteId': myId,
        'playerWhiteName': _myName,
        'playerBlackId': opponentId,
        'playerBlackName': opponentName,
        'currentTurnColor': 'white',
        'boardState': initialFen,
        'status': 'in_progress',
        'startedAt': DateTime.now().toIso8601String(),
      };
      final resp = await client
          .from('chess_games')
          .insert(body)
          .select()
          .single();
      final game = ChessGame.fromJson(resp as Map<String, dynamic>);
      _gameId = game.id;
      _logic = chess.Chess.fromFEN(game.boardState);

      state = state.copyWith(
        game: game,
        isLoading: false,
        inCheck: _logic!.in_check,
        isCheckmate: _logic!.in_checkmate,
        isStalemate: _logic!.in_stalemate,
      );
      _subscribeToRealtime(game.id);
      return game.id;
    } catch (e) {
      debugPrint('[Chess] createGame error: $e');
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
          .from('chess_games')
          .select()
          .eq('id', gameId)
          .single();
      final game = ChessGame.fromJson(gameResp as Map<String, dynamic>);
      _gameId = game.id;
      _logic = chess.Chess.fromFEN(game.boardState);

      final movesResp = await client
          .from('chess_moves')
          .select()
          .eq('gameId', gameId)
          .order('moveNumber', ascending: true);
      final moves = movesResp
          .map((m) => ChessMoveRecord.fromJson(m as Map<String, dynamic>))
          .toList();

      state = state.copyWith(
        game: game,
        moves: moves,
        isLoading: false,
        inCheck: _logic!.in_check,
        isCheckmate: _logic!.in_checkmate,
        isStalemate: _logic!.in_stalemate,
      );
      _subscribeToRealtime(gameId);
      return true;
    } catch (e) {
      debugPrint('[Chess] loadGame error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
      return false;
    }
  }

  /// Select a piece at the given square (e.g. 'e2').
  /// Updates legal destinations for that piece.
  void selectSquare(String square) {
    final game = state.game;
    if (game == null || !game.isInProgress) return;
    final myId = _myId;
    if (myId == null) return;
    if (!game.isMyTurn(myId)) return;

    final logic = _logic;
    if (logic == null) return;

    // Check there's a piece at this square and it's the current player's
    final piece = logic.get(square);
    if (piece == null) return;

    // chess.dart uses 'w'/'b' for color; our ChessColor uses white/black
    final pieceColor = piece.color == chess.Color.WHITE
        ? ChessColor.white
        : ChessColor.black;
    if (pieceColor != game.currentTurnColor) return;

    // Get legal moves FROM this square
    final legalMoves = logic.generate_moves({
      'from': square,
    });
    final destinations = legalMoves.map((m) => m.toAlgebraic).toList();

    state = state.copyWith(
      selectedSquare: square,
      legalDestinations: destinations,
    );
    GameMotionTokens.tap();
  }

  /// Clear the current selection.
  void clearSelection() {
    state = state.copyWith(clearSelection: true, legalDestinations: const []);
  }

  /// Attempt to move from [from] to [to].
  /// Handles promotion (defaults to Queen).
  Future<bool> makeMove(String from, String to, {String? promotion}) async {
    final game = state.game;
    final client = _client;
    final myId = _myId;
    final logic = _logic;
    if (game == null || client == null || myId == null || logic == null) {
      return false;
    }
    if (!game.isMyTurn(myId)) return false;

    // Build the move
    final moveObj = <String, dynamic>{
      'from': from,
      'to': to,
    };

    // Check if promotion is needed
    final piece = logic.get(from);
    if (piece != null && piece.type == chess.PieceType.PAWN) {
      // Check if this is a promotion move (pawn reaching last rank)
      final toRank = to[1];
      if ((piece.color == chess.Color.WHITE && toRank == '8') ||
          (piece.color == chess.Color.BLACK && toRank == '1')) {
        moveObj['promotion'] = promotion ?? 'q'; // default to queen
      }
    }

    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      // In chess.dart 0.8.1, move() returns bool, not a Move object.
      // Find the matching Move from generate_moves() first to get details.
      final candidates = logic.generate_moves({
        'from': from,
        'to': to,
      });

      // Find the matching move (handle promotion)
      chess.Move? matchedMove;
      for (final m in candidates) {
        if (m.toAlgebraic == to && m.fromAlgebraic == from) {
          // If promotion, match the promotion piece; otherwise take first match
          if (moveObj.containsKey('promotion')) {
            final promoStr = moveObj['promotion'] as String;
            final promoPiece = promoStr == 'q'
                ? chess.PieceType.QUEEN
                : promoStr == 'r'
                    ? chess.PieceType.ROOK
                    : promoStr == 'b'
                        ? chess.PieceType.BISHOP
                        : chess.PieceType.KNIGHT;
            if (m.promotion == promoPiece) {
              matchedMove = m;
              break;
            }
          } else {
            matchedMove = m;
            break;
          }
        }
      }

      if (matchedMove == null) {
        GameMotionTokens.error();
        state = state.copyWith(
          isSubmitting: false,
          error: 'Illegal move',
          clearSelection: true,
          legalDestinations: const [],
        );
        return false;
      }

      // Get SAN BEFORE making the move (san() requires the move to not yet be applied)
      final notation = logic.san(matchedMove);

      // Extract move details from the Move object
      final fromSquare = matchedMove.fromAlgebraic;
      final toSquare = matchedMove.toAlgebraic;
      final pieceMoved = matchedMove.piece.toString().toUpperCase();
      final capturedPiece = matchedMove.captured != null
          ? matchedMove.captured.toString()
          : null;
      final promotedTo = matchedMove.promotion != null
          ? matchedMove.promotion.toString().toUpperCase()
          : null;

      // Determine special move type (chess.dart uses string flags: 'k','q','e','p')
      String? specialMove;
      if (matchedMove.flag == 'k') {
        specialMove = 'castle_kingside';
      } else if (matchedMove.flag == 'q') {
        specialMove = 'castle_queenside';
      } else if (matchedMove.flag == 'e') {
        specialMove = 'en_passant';
      } else if (matchedMove.flag == 'p') {
        specialMove = 'promotion';
      }

      // Apply the move (returns bool in chess.dart 0.8.1)
      final success = logic.move(moveObj);
      if (!success) {
        GameMotionTokens.error();
        state = state.copyWith(
          isSubmitting: false,
          error: 'Move failed',
          clearSelection: true,
          legalDestinations: const [],
        );
        return false;
      }

      // Get the new FEN
      final newFen = logic.fen;

      // Determine game result
      String? result;
      String? winnerId;
      String? winnerName;
      bool gameEnded = false;

      if (logic.in_checkmate) {
        // Checkmate — current player's opponent wins
        final winnerColor = game.currentTurnColor == ChessColor.white
            ? ChessColor.black
            : ChessColor.white;
        result = winnerColor == ChessColor.white
            ? 'white_win'
            : 'black_win';
        winnerId = game.playerIdForColor(winnerColor);
        winnerName = winnerColor == ChessColor.white
            ? game.playerWhiteName
            : game.playerBlackName;
        gameEnded = true;
        GameMotionTokens.celebrate();
      } else if (logic.in_stalemate) {
        result = 'stalemate';
        gameEnded = true;
        GameMotionTokens.error();
      } else if (logic.in_draw) {
        result = 'draw';
        gameEnded = true;
        GameMotionTokens.tap();
      } else {
        // Normal move — haptic
        if (capturedPiece != null) {
          GameMotionTokens.success();
        } else {
          GameMotionTokens.tap();
        }
      }

      // Build update
      final updateBody = <String, dynamic>{
        'boardState': newFen,
        'currentTurnColor':
            game.currentTurnColor == ChessColor.white ? 'black' : 'white',
        'lastMoveAt': DateTime.now().toIso8601String(),
      };

      if (gameEnded) {
        updateBody['status'] = 'completed';
        updateBody['completedAt'] = DateTime.now().toIso8601String();
        updateBody['result'] = result;
        updateBody['winnerId'] = winnerId;
        updateBody['winnerName'] = winnerName;
      }

      // Update game
      await client.from('chess_games').update(updateBody).eq('id', game.id);

      // Insert move record
      final moveNumber = state.moves.length + 1;
      await client.from('chess_moves').insert({
        'gameId': game.id,
        'playerId': myId,
        'playerName': _myName,
        'fromSquare': fromSquare,
        'toSquare': toSquare,
        'pieceMoved': pieceMoved,
        'capturedPiece': capturedPiece,
        'specialMove': specialMove,
        'promotedTo': promotedTo,
        'moveNumber': moveNumber,
        'notation': notation,
      });

      // Update local state
      final updatedGame = ChessGame(
        id: game.id,
        familyId: game.familyId,
        playerWhiteId: game.playerWhiteId,
        playerWhiteName: game.playerWhiteName,
        playerBlackId: game.playerBlackId,
        playerBlackName: game.playerBlackName,
        currentTurnColor: game.currentTurnColor == ChessColor.white
            ? ChessColor.black
            : ChessColor.white,
        boardState: newFen,
        status: gameEnded ? ChessStatus.completed : ChessStatus.inProgress,
        result: ChessResultX.fromString(result),
        winnerId: winnerId,
        winnerName: winnerName,
        lastMoveAt: DateTime.now(),
        startedAt: game.startedAt,
        completedAt: gameEnded ? DateTime.now() : null,
        createdAt: game.createdAt,
      );

      state = state.copyWith(
        game: updatedGame,
        isSubmitting: false,
        clearSelection: true,
        legalDestinations: const [],
        lastMove: (fromSquare, toSquare),
        inCheck: logic.in_check,
        isCheckmate: logic.in_checkmate,
        isStalemate: logic.in_stalemate,
      );

      return true;
    } catch (e) {
      debugPrint('[Chess] makeMove error: $e');
      state = state.copyWith(isSubmitting: false, error: '$e');
      return false;
    }
  }

  /// Leave the game.
  void leaveGame() {
    _channel?.unsubscribe();
    _channel = null;
    _gameId = null;
    _logic = null;
  }

  // ── Realtime subscription ────────────────────────────────────────

  void _subscribeToRealtime(String gameId) {
    _channel?.unsubscribe();
    final client = _client;
    if (client == null) return;

    _channel = client
        .channel('chess_game:$gameId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'chess_games',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: gameId,
          ),
          callback: (payload) {
            final updated = ChessGame.fromJson(payload.newRecord);
            // Rebuild the logic engine from the new FEN
            _logic = chess.Chess.fromFEN(updated.boardState);
            if (updated.isCompleted) {
              GameMotionTokens.celebrate();
            }
            state = state.copyWith(
              game: updated,
              inCheck: _logic!.in_check,
              isCheckmate: _logic!.in_checkmate,
              isStalemate: _logic!.in_stalemate,
            );
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chess_moves',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: gameId,
          ),
          callback: (payload) {
            final move = ChessMoveRecord.fromJson(payload.newRecord);
            if (!state.moves.any((m) => m.id == move.id)) {
              state = state.copyWith(
                moves: [...state.moves, move],
                lastMove: (move.fromSquare, move.toSquare),
              );
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

final chessProvider = StateNotifierProvider.autoDispose
    .family<ChessNotifier, ChessState, String>(
  (ref, familyId) => ChessNotifier(ref, familyId),
);

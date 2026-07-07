// lib/features/games/chess/chess_board_screen.dart
//
// Chess — main board screen with:
//   • 8x8 board using original Kinrel color palette
//   • Original piece design (Unicode chess glyphs styled with Kinrel colors)
//   • Tap to select, legal destination highlights
//   • Check indicator (king glows when in check)
//   • Captured pieces display + move history
//   • Smooth piece-slide animation
//   • Inline results view with confetti
// Route: /family/$familyId/chess/board/:gameId

import 'package:chess/chess.dart' as chess;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/dk_components.dart';
import '../game_motion_tokens.dart';
import 'chess_models.dart';
import 'chess_provider.dart';

class ChessBoardScreen extends ConsumerStatefulWidget {
  const ChessBoardScreen({
    super.key,
    required this.familyId,
    required this.gameId,
  });
  final String familyId;
  final String gameId;

  @override
  ConsumerState<ChessBoardScreen> createState() => _ChessBoardScreenState();
}

class _ChessBoardScreenState extends ConsumerState<ChessBoardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(chessProvider(widget.familyId));
      if (state.game == null) {
        ref.read(chessProvider(widget.familyId).notifier).loadGame(widget.gameId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chessProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;

    if (state.isCompleted) {
      return _resultsView(state, myId);
    }

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () {
            ref.read(chessProvider(widget.familyId).notifier).leaveGame();
            Navigator.of(context).pop();
          },
        ),
        title: Text(
          'Chess',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontWeight: FontWeight.w600,
            color: KinrelColors.textWhite,
          ),
        ),
        backgroundColor: KinrelColors.darkCard,
        foregroundColor: KinrelColors.textWhite,
        elevation: 0,
      ),
      body: state.isLoading && state.game == null
          ? const Center(
              child: CircularProgressIndicator(color: KinrelColors.orange),
            )
          : state.error != null && state.game == null
          ? DKErrorState(
              message: state.error!,
              onRetry: () => ref
                  .read(chessProvider(widget.familyId).notifier)
                  .loadGame(widget.gameId),
            )
          : state.game == null
          ? const Center(
              child: CircularProgressIndicator(color: KinrelColors.orange),
            )
          : _gameView(state, myId),
    );
  }

  Widget _gameView(ChessState state, String? myId) {
    final game = state.game!;
    final isMyTurn = game.isMyTurn(myId);
    final myColor = game.colorForPlayerId(myId);
    final opponentName = myColor == ChessColor.white
        ? game.playerBlackName
        : game.playerWhiteName;

    // Parse the FEN to get the board
    final logic = chess.Chess.fromFEN(game.boardState);
    // chess.dart 0.8.1 returns a flat List<Piece?> (64 elements)
    // Convert to 2D List<List<Piece?>> for easier rendering
    final flatBoard = logic.board as List;
    final board = List<List<chess.Piece?>>.generate(
      8,
      (row) => List<chess.Piece?>.generate(
        8,
        (col) => flatBoard[row * 8 + col] as chess.Piece?,
      ),
    );

    // Flip the board if I'm playing black
    final flipBoard = myColor == ChessColor.black;

    return SafeArea(
      child: Column(
        children: [
          // Turn indicator + check warning
          _turnIndicator(game, state, isMyTurn, opponentName, myColor),
          // Captured pieces bar
          _capturedPiecesBar(state, game, myColor),
          const SizedBox(height: KinrelSpacing.sm),
          // Board
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(KinrelSpacing.sm),
                child: AspectRatio(
                  aspectRatio: 1.0,
                  child: _boardWidget(state, game, board, flipBoard, myId),
                ),
              ),
            ),
          ),
          // Move history (last 5 moves)
          if (state.moves.isNotEmpty)
            _moveHistory(state, myColor),
          const SizedBox(height: KinrelSpacing.base),
        ],
      ),
    );
  }

  Widget _turnIndicator(
    ChessGame game,
    ChessState state,
    bool isMyTurn,
    String opponentName,
    ChessColor? myColor,
  ) {
    final turnColor = game.currentTurnColor;
    final turnColorValue = turnColor == ChessColor.white
        ? Colors.white
        : const Color(0xFF1F2937);

    return Container(
      margin: const EdgeInsets.all(KinrelSpacing.base),
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.md,
        vertical: KinrelSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: (isMyTurn ? KinrelColors.orange : KinrelColors.darkElevated)
            .withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(
          color: isMyTurn
              ? KinrelColors.orange
              : (state.inCheck ? KinrelColors.error : KinrelColors.border),
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: turnColorValue,
              border: Border.all(color: KinrelColors.border, width: 1),
            ),
          ),
          const SizedBox(width: KinrelSpacing.sm),
          Text(
            isMyTurn
                ? 'Your turn (${turnColor.name})'
                : '$opponentName\'s turn (${turnColor.name})',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              color: isMyTurn ? Colors.white : KinrelColors.textDim,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (state.inCheck && !state.isCheckmate) ...[
            const SizedBox(width: KinrelSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: KinrelColors.error,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'CHECK!',
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 9,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _capturedPiecesBar(
    ChessState state,
    ChessGame game,
    ChessColor? myColor,
  ) {
    // Parse captured pieces from move history
    final whiteCaptured = <String>[]; // pieces captured BY white (black pieces)
    final blackCaptured = <String>[]; // pieces captured BY black (white pieces)

    for (final move in state.moves) {
      if (move.capturedPiece != null) {
        final isUpperCase = move.capturedPiece!.toUpperCase() ==
            move.capturedPiece;
        if (isUpperCase) {
          // White piece captured → black captured it
          blackCaptured.add(move.capturedPiece!);
        } else {
          // Black piece captured → white captured it
          whiteCaptured.add(move.capturedPiece!);
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _capturedRow(
            'You',
            myColor == ChessColor.white ? whiteCaptured : blackCaptured,
            true,
          ),
          _capturedRow(
            myColor == ChessColor.white ? game.playerBlackName : game.playerWhiteName,
            myColor == ChessColor.white ? blackCaptured : whiteCaptured,
            false,
          ),
        ],
      ),
    );
  }

  Widget _capturedRow(String label, List<String> pieces, bool isMe) {
    return Column(
      crossAxisAlignment: isMe ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 10,
            color: KinrelColors.textDim,
          ),
        ),
        const SizedBox(height: 2),
        SizedBox(
          height: 20,
          child: pieces.isEmpty
              ? Text(
                  '—',
                  style: TextStyle(
                    fontSize: 14,
                    color: KinrelColors.textDim,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: pieces.map((p) {
                    final isWhite = p.toUpperCase() == p;
                    return Text(
                      _pieceGlyph(p, isWhite),
                      style: TextStyle(
                        fontSize: 16,
                        color: isWhite
                            ? Colors.white
                            : const Color(0xFF1F2937),
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  Widget _boardWidget(
    ChessState state,
    ChessGame game,
    List<List<chess.Piece?>> board,
    bool flipBoard,
    String? myId,
  ) {
    final selectedSquare = state.selectedSquare;
    final legalDests = state.legalDestinations;
    final lastMove = state.lastMove;
    final inCheck = state.inCheck;
    final currentTurnColor = game.currentTurnColor;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(color: KinrelColors.orange, width: 2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(KinrelRadius.lg - 2),
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 8,
          ),
          itemCount: 64,
          itemBuilder: (context, index) {
            // Default orientation: white at bottom (rank 8 at top, rank 1 at bottom)
            int row = index ~/ 8;
            int col = index % 8;

            // Flip for black player
            if (flipBoard) {
              row = 7 - row;
              col = 7 - col;
            }

            // chess.dart board[row][col] — row 0 = rank 8, row 7 = rank 1
            final piece = board[row][col];

            // Square name (e.g. 'e2')
            final file = 'abcdefgh'[col];
            final rank = '${8 - row}';
            final squareName = '$file$rank';

            final isSelected = squareName == selectedSquare;
            final isLegalDest = legalDests.contains(squareName);
            final isLastMoveFrom =
                lastMove != null && lastMove.$1 == squareName;
            final isLastMoveTo =
                lastMove != null && lastMove.$2 == squareName;

            // Check if this is the king in check
            final isKingInCheck = inCheck &&
                piece != null &&
                piece.type == chess.PieceType.KING &&
                ((piece.color == chess.Color.WHITE &&
                      currentTurnColor == ChessColor.white) ||
                    (piece.color == chess.Color.BLACK &&
                      currentTurnColor == ChessColor.black));

            return _cell(
              row: row,
              col: col,
              piece: piece,
              isSelected: isSelected,
              isLegalDest: isLegalDest,
              isLastMoveFrom: isLastMoveFrom,
              isLastMoveTo: isLastMoveTo,
              isKingInCheck: isKingInCheck,
              squareName: squareName,
              isMyTurn: game.isMyTurn(myId),
            );
          },
        ),
      ),
    );
  }

  Widget _cell({
    required int row,
    required int col,
    required chess.Piece? piece,
    required bool isSelected,
    required bool isLegalDest,
    required bool isLastMoveFrom,
    required bool isLastMoveTo,
    required bool isKingInCheck,
    required String squareName,
    required bool isMyTurn,
  }) {
    // Original Kinrel board colors — not standard white/brown
    final isLightSquare = (row + col) % 2 == 0;
    Color bgColor;
    if (isLightSquare) {
      bgColor = const Color(0xFF2A2A3D); // dark elevated
    } else {
      bgColor = const Color(0xFF13141E); // dark surface
    }

    // Highlight selected
    if (isSelected) {
      bgColor = KinrelColors.orange.withValues(alpha: 0.4);
    }
    // Highlight last move
    else if (isLastMoveTo) {
      bgColor = KinrelColors.success.withValues(alpha: 0.2);
    } else if (isLastMoveFrom) {
      bgColor = KinrelColors.success.withValues(alpha: 0.1);
    }

    return GestureDetector(
      onTap: () => _onCellTap(squareName, isMyTurn),
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(
            color: isSelected
                ? KinrelColors.orange
                : (isLegalDest
                      ? KinrelColors.orange.withValues(alpha: 0.5)
                      : Colors.transparent),
            width: isSelected ? 2.5 : (isLegalDest ? 2 : 0),
          ),
        ),
        child: Stack(
          children: [
            // Legal destination dot
            if (isLegalDest && piece == null)
              Center(
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: KinrelColors.orange.withValues(alpha: 0.6),
                  ),
                ),
              ),
            // Legal destination ring (for captures)
            if (isLegalDest && piece != null)
              Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: KinrelColors.orange,
                    width: 3,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            // Piece
            if (piece != null)
              Center(
                child: _pieceWidget(piece, isKingInCheck),
              ),
          ],
        ),
      ),
    )
        .animate(target: isLastMoveTo ? 1 : 0)
        .fadeIn(duration: 200.ms);
  }

  /// Original piece rendering — Unicode chess glyphs styled with
  /// Kinrel's brand colors. White pieces use amber/gold, black pieces
  /// use a dark slate. This is distinct from traditional black/white.
  Widget _pieceWidget(chess.Piece piece, bool isInCheck) {
    final isWhite = piece.color == chess.Color.WHITE;
    final glyph = _pieceUnicode(piece);

    // King in check gets a red glow
    final checkGlow = isInCheck
        ? [
            BoxShadow(
              color: KinrelColors.error.withValues(alpha: 0.8),
              blurRadius: 8,
              spreadRadius: 2,
            ),
          ]
        : null;

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: checkGlow,
      ),
      child: Text(
        glyph,
        style: TextStyle(
          fontSize: 28,
          color: isWhite ? KinrelColors.amber : const Color(0xFF94A3B8),
          shadows: [
            Shadow(
              color: Colors.black.withValues(alpha: 0.5),
              offset: const Offset(1, 1),
              blurRadius: 2,
            ),
          ],
        ),
      ),
    );
  }

  /// Unicode chess piece glyphs.
  String _pieceUnicode(chess.Piece piece) {
    // White pieces (uppercase): ♔♕♖♗♘♙
    // Black pieces (lowercase): ♚♛♜♝♞♟
    switch (piece.type) {
      case chess.PieceType.KING:
        return piece.color == chess.Color.WHITE ? '♔' : '♚';
      case chess.PieceType.QUEEN:
        return piece.color == chess.Color.WHITE ? '♕' : '♛';
      case chess.PieceType.ROOK:
        return piece.color == chess.Color.WHITE ? '♖' : '♜';
      case chess.PieceType.BISHOP:
        return piece.color == chess.Color.WHITE ? '♗' : '♝';
      case chess.PieceType.KNIGHT:
        return piece.color == chess.Color.WHITE ? '♘' : '♞';
      case chess.PieceType.PAWN:
        return piece.color == chess.Color.WHITE ? '♙' : '♟';
      default:
        return '?';
    }
  }

  /// Get the glyph for a piece letter (for captured pieces display).
  String _pieceGlyph(String letter, bool isWhite) {
    switch (letter.toUpperCase()) {
      case 'K':
        return isWhite ? '♔' : '♚';
      case 'Q':
        return isWhite ? '♕' : '♛';
      case 'R':
        return isWhite ? '♖' : '♜';
      case 'B':
        return isWhite ? '♗' : '♝';
      case 'N':
        return isWhite ? '♘' : '♞';
      case 'P':
        return isWhite ? '♙' : '♟';
      default:
        return '?';
    }
  }

  void _onCellTap(String squareName, bool isMyTurn) {
    final state = ref.read(chessProvider(widget.familyId));
    final notifier = ref.read(chessProvider(widget.familyId).notifier);

    // If a square is already selected and this is a legal destination → move
    if (state.selectedSquare != null &&
        state.legalDestinations.contains(squareName)) {
      notifier.makeMove(state.selectedSquare!, squareName);
      return;
    }

    // If it's my turn and I tap a square → try to select
    if (isMyTurn) {
      notifier.selectSquare(squareName);
      return;
    }

    // Otherwise clear selection
    notifier.clearSelection();
  }

  Widget _moveHistory(ChessState state, ChessColor? myColor) {
    final recentMoves = state.moves.reversed.take(5).toList().reversed;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.md,
        vertical: KinrelSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(color: KinrelColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MOVES',
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 9,
              color: KinrelColors.textDim,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 2,
            children: recentMoves.map((m) {
              return Text(
                '${m.moveNumber}. ${m.notation}',
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 11,
                  color: KinrelColors.textWhite,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── Results view ──────────────────────────────────────────────────

  Widget _resultsView(ChessState state, String? myId) {
    final game = state.game!;
    final isWinner = game.winnerId == myId;
    final winnerName = game.winnerName ?? 'Player';
    final isDraw = game.result == ChessResult.draw ||
        game.result == ChessResult.stalemate;

    return DKScaffold(
      gradient: isWinner ? KinrelGradients.deepFireGradient : null,
      backgroundColor: isWinner ? null : KinrelColors.darkSurface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text('Results',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontWeight: FontWeight.w600,
            color: KinrelColors.textWhite,
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: KinrelColors.textWhite,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(KinrelSpacing.base),
        children: [
          const SizedBox(height: KinrelSpacing.lg),
          Column(
            children: [
              Text(
                isDraw ? '🤝' : '🏆',
                style: TextStyle(fontSize: 64),
              )
                  .animate(onPlay: (c) => c.forward())
                  .fadeIn(duration: 500.ms)
                  .scale(
                    begin: const Offset(0.5, 0.5),
                    end: const Offset(1.0, 1.0),
                    duration: 500.ms,
                    curve: Curves.elasticOut,
                  ),
              const SizedBox(height: KinrelSpacing.sm),
              Text(
                isDraw
                    ? (game.result == ChessResult.stalemate
                          ? 'Stalemate — Draw!'
                          : 'Draw!')
                    : (isWinner ? 'Checkmate — You Won!' : 'Checkmate!'),
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: KinrelColors.textWhite,
                  letterSpacing: 2,
                ),
              ),
              if (!isDraw) ...[
                const SizedBox(height: 4),
                Text(
                  isWinner ? '$winnerName (You)' : winnerName,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.orange,
                  ),
                ),
              ],
            ],
          )
              .animate()
              .fadeIn(duration: 400.ms)
              .scale(
                begin: const Offset(0.92, 0.92),
                end: const Offset(1.0, 1.0),
                duration: 400.ms,
                curve: Curves.easeOutBack,
              ),
          const SizedBox(height: KinrelSpacing.xxl),
          DKButton(
            label: 'Play Again',
            variant: DKButtonVariant.gradient,
            fullWidth: true,
            icon: Icons.refresh_rounded,
            onPressed: () {
              ref.read(chessProvider(widget.familyId).notifier).leaveGame();
              if (context.mounted) {
                context.pushReplacement(
                  '/family/${widget.familyId}/chess/lobby',
                );
              }
            },
          ),
          const SizedBox(height: KinrelSpacing.sm),
          DKButton(
            label: 'Back to Hub',
            variant: DKButtonVariant.secondary,
            fullWidth: true,
            onPressed: () {
              ref.read(chessProvider(widget.familyId).notifier).leaveGame();
              if (context.mounted) {
                context.go('/games?familyId=${widget.familyId}');
              }
            },
          ),
        ],
      ),
    );
  }
}

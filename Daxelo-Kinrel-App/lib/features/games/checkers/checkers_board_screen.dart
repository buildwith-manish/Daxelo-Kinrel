// lib/features/games/checkers/checkers_board_screen.dart
//
// Checkers — main board screen with:
//   • 8x8 board rendering with light/dark squares
//   • Pieces as circles (red/black, kings with crown glow)
//   • Tap to select, legal moves highlighted (regular vs forced capture)
//   • Smooth move animation between squares
//   • King promotion glow animation
//   • Capture fade-out animation
//   • Captured piece counts + turn indicator
//   • Inline results view with confetti
// Premium finish: wooden GameBoardShell table frame, directionally-lit
// tan/brown squares, 3D ivory & charcoal-brown chips (kings glow), and a
// physics GameConfetti volley when a winner is crowned.
// Route: /family/$familyId/checkers/board/:gameId

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/dk_components.dart';
import '../shared/multiplayer/multiplayer.dart';
import '../shared/services/temporary_room_service.dart';
import '../shared/widgets/game_board_shell.dart';
import '../shared/widgets/game_confetti.dart';
import 'checkers_game_logic.dart';
import 'checkers_models.dart';
import 'checkers_provider.dart';
import '../../gaming_ecosystem/presentation/match_ecosystem_summary.dart';

/// Checkers brand accent — the family-hub game card orange.
const Color _checkersAccent = KinrelColors.orange;

/// Directionally-lit wooden squares (warm tan light / deep brown dark),
/// lit from the top-left so the board reads as a physical table.
final List<BoxDecoration> _checkersSquareShades = boardSquareShades(
  lightSquare: const Color(0xFFB08968),
  darkSquare: const Color(0xFF5C3A21),
);

/// Piece chip colours — warm ivory vs deep charcoal-brown.
const Color _checkersLightPiece = Color(0xFFE8DCC8);
const Color _checkersDarkPiece = Color(0xFF3A2A1E);

class CheckersBoardScreen extends ConsumerStatefulWidget {
  const CheckersBoardScreen({
    super.key,
    required this.familyId,
    required this.gameId,
  });
  final String familyId;
  final String gameId;

  @override
  ConsumerState<CheckersBoardScreen> createState() =>
      _CheckersBoardScreenState();
}

class _CheckersBoardScreenState extends ConsumerState<CheckersBoardScreen>
    with TickerProviderStateMixin {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(checkersProvider(widget.familyId).notifier).loadGame(widget.gameId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(checkersProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;

    // Show results inline when game completes
    //
    // RoomKeepAlive: keep the room framework (host heartbeat + room
    // realtime) alive for the whole lifetime of this screen — the
    // challenge lobby that attached the RoomController is replaced by
    // this route; without a watch the autoDispose controller dies and
    // the server-side reaper auto-closes the room ~60-75s in.
    final Widget view = RoomKeepAlive(
      roomKey: RoomControllerKey(RoomConfig.checkers, widget.familyId),
      child: DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          // Plain pop — the route-level onExit guard (app_router.dart)
          // intercepts this while a game room is active and shows the
          // confirmation dialog first.
          onPressed: () { if (context.canPop()) { context.pop(); } else { context.go('/family/${widget.familyId}'); } },
        ),
        title: Text(
          'Checkers',
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
              // Room closed by the host → terminal state, offer a clean
              // exit back to the games hub instead of a pointless retry.
              actionLabel:
                  state.error == kRoomClosedMessage ? 'Back to Games' : null,
              icon: state.error == kRoomClosedMessage
                  ? Icons.meeting_room_rounded
                  : null,
              onRetry: state.error == kRoomClosedMessage
                  ? () => context.go('/games?familyId=${widget.familyId}')
                  : () => ref
                      .read(checkersProvider(widget.familyId).notifier)
                      .loadGame(widget.gameId),
            )
          : state.game == null
          ? const Center(
              child: CircularProgressIndicator(color: KinrelColors.orange),
            )
          : _gameView(state, myId),
      ),
    );

    if (state.isCompleted) {
      return _resultsView(state, myId);
    }
    return view;
  }

  Widget _gameView(CheckersState state, String? myId) {
    final game = state.game!;
    final myPlayerNumber = game.playerNumberFor(myId);
    final isMyTurn = game.currentTurnPlayerId == myId;
    final opponentName = myPlayerNumber == 1
        ? game.playerTwoName
        : game.playerOneName;

    return SafeArea(
      child: Column(
        children: [
          // Turn indicator
          _turnIndicator(game, isMyTurn, opponentName, myPlayerNumber),
          // Captured pieces bar
          _capturedBar(game, myPlayerNumber),
          const SizedBox(height: KinrelSpacing.sm),
          // Board
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(KinrelSpacing.base),
                child: AspectRatio(
                  aspectRatio: 1.0,
                  child: _board(state, game, myId, myPlayerNumber),
                ),
              ),
            ),
          ),
          // Status / error message
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: KinrelSpacing.base,
                vertical: KinrelSpacing.sm,
              ),
              child: Text(
                state.error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  color: KinrelColors.warning,
                ),
              ),
            ),
          if (game.mandatoryCapturePending)
            Padding(
              padding: const EdgeInsets.only(bottom: KinrelSpacing.sm),
              child: Text(
                'Multi-jump in progress — continue capturing!',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  color: KinrelColors.warning,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(height: KinrelSpacing.base),
        ],
      ),
    );
  }

  Widget _turnIndicator(
    CheckersGame game,
    bool isMyTurn,
    String opponentName,
    int? myPlayerNumber,
  ) {
    final turnPlayerName = game.currentTurnPlayerId == game.playerOneId
        ? game.playerOneName
        : game.playerTwoName;
    final turnPlayerNumber = game.currentTurnPlayerId == game.playerOneId
        ? 1
        : 2;
    final turnColor = turnPlayerNumber == 1
        ? _checkersLightPiece // ivory
        : _checkersDarkPiece; // charcoal-brown

    return Container(
      margin: const EdgeInsets.all(KinrelSpacing.base),
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.md,
        vertical: KinrelSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: turnColor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(color: turnColor, width: 1.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (isMyTurn)
            const Icon(Icons.pan_tool_rounded, size: 16, color: Colors.white)
          else
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: turnColor,
              ),
            ),
          const SizedBox(width: KinrelSpacing.sm),
          Text(
            isMyTurn
                ? 'Your turn (Player ${myPlayerNumber == 1 ? "Ivory" : "Black"})'
                : '$turnPlayerName\'s turn (${turnPlayerNumber == 1 ? "Ivory" : "Black"})',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _capturedBar(CheckersGame game, int? myPlayerNumber) {
    final myCaptured = myPlayerNumber == 1
        ? game.playerOneCaptured
        : game.playerTwoCaptured;
    final opponentCaptured = myPlayerNumber == 1
        ? game.playerTwoCaptured
        : game.playerOneCaptured;

    // Chips carry the physical piece colours, flipped to whichever side
    // "you" are playing.
    final myPieceColor = myPlayerNumber == 2
        ? _checkersDarkPiece
        : _checkersLightPiece;
    final opponentPieceColor = myPlayerNumber == 2
        ? _checkersLightPiece
        : _checkersDarkPiece;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _capturedChip('You captured', myCaptured, myPieceColor),
          _capturedChip(
            'Opponent captured',
            opponentCaptured,
            opponentPieceColor,
          ),
        ],
      ),
    );
  }

  Widget _capturedChip(String label, int count, Color color) {
    return Column(
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
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GamePiece3D(color: color, size: 13),
            const SizedBox(width: 4),
            Text(
              '$count',
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _board(
    CheckersState state,
    CheckersGame game,
    String? myId,
    int? myPlayerNumber,
  ) {
    final board = game.boardState;
    final selectedRow = state.selectedRow;
    final selectedCol = state.selectedCol;
    final legalMoves = state.legalMoves;
    final lastMove = state.lastMove;
    final lastKingPromo = state.lastKingPromotion;

    // Check if any captures are available (for the "forced capture" hint)
    final allCaptures = myPlayerNumber != null && game.currentTurnPlayerId == myId
        ? getAllCapturesForPlayer(board, myPlayerNumber)
        : <CheckersMove>[];
    final hasForcedCaptures = allCaptures.isNotEmpty;

    // Premium wooden table frame — bevelled rim, grain, accent under-glow.
    return GameBoardShell(
      accent: _checkersAccent,
      surface: BoardSurface.wood,
      radius: 22,
      padding: 8,
      child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 8,
          ),
          itemCount: 64,
          itemBuilder: (context, index) {
            final row = index ~/ 8;
            final col = index % 8;
            final isDarkSquare = (row + col) % 2 == 1;
            final piece = board[row][col];
            final isSelected = row == selectedRow && col == selectedCol;
            final legalMove = legalMoves
                .where((m) => m.toRow == row && m.toCol == col)
                .firstOrNull;
            final isLegalDestination = legalMove != null;
            final isForcedCapture = isLegalDestination && legalMove.isCapture;
            final isLastMoveFrom =
                lastMove != null &&
                lastMove.fromRow == row &&
                lastMove.fromCol == col;
            final isLastMoveTo =
                lastMove != null &&
                lastMove.toRow == row &&
                lastMove.toCol == col;
            final isKingPromo =
                lastKingPromo != null &&
                lastKingPromo.$1 == row &&
                lastKingPromo.$2 == col;
            final isCapturedSquare =
                lastMove != null &&
                lastMove.isCapture &&
                lastMove.capturedRow == row &&
                lastMove.capturedCol == col;

            return _cell(
              row: row,
              col: col,
              isDarkSquare: isDarkSquare,
              piece: piece,
              isSelected: isSelected,
              isLegalDestination: isLegalDestination,
              isForcedCapture: isForcedCapture,
              isLastMoveFrom: isLastMoveFrom,
              isLastMoveTo: isLastMoveTo,
              isKingPromo: isKingPromo,
              isCapturedSquare: isCapturedSquare,
              hasForcedCaptures: hasForcedCaptures,
              myId: myId,
              game: game,
              state: state,
            );
          },
        ),
    );
  }

  Widget _cell({
    required int row,
    required int col,
    required bool isDarkSquare,
    required CheckersPiece? piece,
    required bool isSelected,
    required bool isLegalDestination,
    required bool isForcedCapture,
    required bool isLastMoveFrom,
    required bool isLastMoveTo,
    required bool isKingPromo,
    required bool isCapturedSquare,
    required bool hasForcedCaptures,
    required String? myId,
    required CheckersGame game,
    required CheckersState state,
  }) {
    // Directionally-lit wooden square (tan light / brown dark). Selection
    // and last-move tints render as translucent overlays on top so the
    // top-left lighting stays visible through them.
    final squareShade = _checkersSquareShades[isDarkSquare ? 1 : 0];

    // Forced capture highlight (red glow on the source piece's legal captures)
    final forcedCaptureSourceHighlight = hasForcedCaptures &&
        piece != null &&
        piece.player == game.playerNumberFor(myId) &&
        game.currentTurnPlayerId == myId;

    return GestureDetector(
      onTap: () => _onCellTap(row, col, state, game, myId),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: squareShade.copyWith(
          border: Border.all(
            color: isSelected
                ? KinrelColors.orange
                : (isLegalDestination
                      ? (isForcedCapture
                            ? KinrelColors.error
                            : KinrelColors.success)
                      : Colors.transparent),
            width: isSelected ? 3 : (isLegalDestination ? 2 : 0),
          ),
        ),
        child: Stack(
          children: [
            // Selection tint over the lit wood (dark squares, as before).
            if (isDarkSquare && isSelected)
              Positioned.fill(
                child: ColoredBox(
                  color: KinrelColors.orange.withValues(alpha: 0.4),
                ),
              ),
            // Last-move destination tint.
            if (isDarkSquare && isLastMoveTo)
              Positioned.fill(
                child: ColoredBox(
                  color: KinrelColors.success.withValues(alpha: 0.2),
                ),
              ),
            // Legal destination dot
            if (isLegalDestination && piece == null)
              Center(
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isForcedCapture
                        ? KinrelColors.error
                        : KinrelColors.success,
                  ),
                ),
              ),
            // Piece
            if (piece != null && !isCapturedSquare)
              Center(
                child: _pieceWidget(
                  piece,
                  isSelected: isSelected,
                  isKingPromo: isKingPromo,
                  forcedHighlight: forcedCaptureSourceHighlight && !isSelected,
                ),
              ),
            // Captured piece (fade out animation)
            if (isCapturedSquare)
              Center(
                child: _pieceWidget(
                  piece ?? const CheckersPiece(player: 0, isKing: false),
                  isSelected: false,
                  isKingPromo: false,
                  forcedHighlight: false,
                  fadingOut: true,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _pieceWidget(
    CheckersPiece piece, {
    required bool isSelected,
    required bool isKingPromo,
    required bool forcedHighlight,
    bool fadingOut = false,
  }) {
    if (piece.player == 0) {
      // Placeholder for fading-out captured piece — use a neutral color
      return const SizedBox.shrink();
    }

    // Physical chips: warm ivory vs deep charcoal-brown, radially lit
    // with a specular highlight and a grounded drop shadow.
    final pieceColor = piece.player == 1
        ? _checkersLightPiece
        : _checkersDarkPiece;

    return Opacity(
      opacity: fadingOut ? 0.3 : 1.0,
      child: GamePiece3D(
        color: pieceColor,
        size: 36,
        // Kings (and fresh promotions) glow.
        glow: piece.isKing || isKingPromo,
        ring: piece.isKing
            ? KinrelColors.warning
            : (isSelected
                  ? Colors.white
                  : (forcedHighlight ? KinrelColors.error : null)),
        child: piece.isKing
            ? const Text(
                '♛',
                style: TextStyle(fontSize: 20, color: KinrelColors.warning),
              )
            : null,
      )
          .animate(target: isKingPromo ? 1 : 0)
          .scale(
            begin: const Offset(0.8, 0.8),
            end: const Offset(1.0, 1.0),
            duration: 400.ms,
            curve: Curves.elasticOut,
          ),
    );
  }

  void _onCellTap(
    int row,
    int col,
    CheckersState state,
    CheckersGame game,
    String? myId,
  ) {
    final piece = game.boardState[row][col];

    // If it's my turn and I tap my own piece → select it
    if (piece != null &&
        piece.player == game.playerNumberFor(myId) &&
        game.currentTurnPlayerId == myId) {
      ref.read(checkersProvider(widget.familyId).notifier).selectPiece(row, col);
      return;
    }

    // If I have a piece selected and tap a legal destination → move
    if (state.selectedRow != null &&
        state.selectedCol != null &&
        state.legalMoves.any((m) => m.toRow == row && m.toCol == col)) {
      ref.read(checkersProvider(widget.familyId).notifier).makeMove(row, col);
      return;
    }

    // Otherwise, clear selection
    ref.read(checkersProvider(widget.familyId).notifier).clearSelection();
  }

  // ── Results view ──────────────────────────────────────────────────

  Widget _resultsView(CheckersState state, String? myId) {
    final game = state.game!;
    final isWinner = game.winnerId == myId;
    final winnerName = game.winnerName ?? 'Player';

    return DKScaffold(
      gradient: isWinner ? KinrelGradients.deepFireGradient : null,
      backgroundColor: isWinner ? null : KinrelColors.darkSurface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          'Results',
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
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(KinrelSpacing.base),
            children: [
              const SizedBox(height: KinrelSpacing.lg),
              // Winner banner
              Column(
                children: [
                  const Text('🏆', style: TextStyle(fontSize: 64))
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
                    isWinner ? 'You Won!' : 'Winner!',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: KinrelColors.textWhite,
                      letterSpacing: 2,
                    ),
                  ),
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
              )
                  .animate()
                  .fadeIn(duration: 400.ms)
                  .scale(
                    begin: const Offset(0.92, 0.92),
                    end: const Offset(1.0, 1.0),
                    duration: 400.ms,
                    curve: Curves.easeOutBack,
                  ),
              const SizedBox(height: KinrelSpacing.xl),
              // Stats
              _statsCard(game),
              const SizedBox(height: KinrelSpacing.xl),
              // Move history (last 10 moves)
              if (state.moves.isNotEmpty) ...[
                Text(
                  'Move History',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.textDim,
                  ),
                ),
                const SizedBox(height: KinrelSpacing.sm),
                ...state.moves.reversed.take(10).map((m) => _moveHistoryRow(m)),
              MatchEcosystemSummary(
                gameTable: 'checkers_games',
                gameId: game.id,
                familyId: widget.familyId,
              ),
                const SizedBox(height: KinrelSpacing.xl),
              ],
              DKButton(
                label: 'Play Again',
                variant: DKButtonVariant.gradient,
                fullWidth: true,
                icon: Icons.refresh_rounded,
                onPressed: () {
                  final gameId = ref.read(checkersProvider(widget.familyId)).game?.id;
                  ref.read(checkersProvider(widget.familyId).notifier).leaveGame();
                  if (gameId != null) {
                    ref.read(temporaryRoomServiceProvider).endGame(
                          gameTable: 'checkers_games',
                          gameId: gameId,
                        );
                  }
                  if (context.mounted) {
                    context.pushReplacement(
                      '/family/${widget.familyId}/checkers/lobby',
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
                  final gameId = ref.read(checkersProvider(widget.familyId)).game?.id;
                  ref.read(checkersProvider(widget.familyId).notifier).leaveGame();
                  if (gameId != null) {
                    ref.read(temporaryRoomServiceProvider).endGame(
                          gameTable: 'checkers_games',
                          gameId: gameId,
                        );
                  }
                  if (context.mounted) {
                    context.go('/games?familyId=${widget.familyId}');
                  }
                },
              ),
            ],
          ),
          // Physics confetti volley for the winner — draws stay calm.
          if (game.winnerId != null)
            const Positioned.fill(
              child: IgnorePointer(
                child: GameConfetti(burstCount: 2, density: 2),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statsCard(CheckersGame game) {
    return Container(
      padding: const EdgeInsets.all(KinrelSpacing.lg),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(color: KinrelColors.border),
      ),
      child: Column(
        children: [
          _statRow('Total Moves', '${game.playerOneCaptured + game.playerTwoCaptured}'),
          const Divider(height: 24),
          _statRow(
            'Ivory Captured',
            '${game.playerOneCaptured}',
            color: _checkersLightPiece,
          ),
          const Divider(height: 24),
          _statRow(
            'Black Captured',
            '${game.playerTwoCaptured}',
            color: const Color(0xFFA08363),
          ),
        ],
      ),
    );
  }

  Widget _statRow(String label, String value, {Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 13,
            color: KinrelColors.textDim,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: KinrelTypography.monoFont,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color ?? KinrelColors.textWhite,
          ),
        ),
      ],
    );
  }

  Widget _moveHistoryRow(CheckersMoveRecord move) {
    return Container(
      margin: const EdgeInsets.only(bottom: KinrelSpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.md,
        vertical: KinrelSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(color: KinrelColors.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              '${move.moveNumber}.',
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 12,
                color: KinrelColors.textDim,
              ),
            ),
          ),
          Expanded(
            child: Text(
              move.playerName,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: KinrelColors.textWhite,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            '(${move.fromRow},${move.fromCol})→(${move.toRow},${move.toCol})'
            '${move.wasCapture ? ' x' : ''}'
            '${move.becameKing ? ' ♛' : ''}',
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 11,
              color: move.wasCapture
                  ? KinrelColors.error
                  : (move.becameKing
                        ? KinrelColors.warning
                        : KinrelColors.textDim),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

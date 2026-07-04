// lib/features/games/carrom/carrom_board_screen.dart
//
// Carrom — main board screen with:
//   • CustomPainter rendering the board, coins, striker, aim line
//   • Drag-to-aim gesture handling
//   • Live physics rendering during simulation
//   • Turn indicator, scores, queen status
//   • Inline results view with confetti
// Route: /family/$familyId/carrom/board/:gameId

import 'dart:math' as math;

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
import 'carrom_constants.dart';
import 'carrom_game_logic.dart';
import 'carrom_models.dart';
import 'carrom_provider.dart';

class CarromBoardScreen extends ConsumerStatefulWidget {
  const CarromBoardScreen({
    super.key,
    required this.familyId,
    required this.gameId,
  });
  final String familyId;
  final String gameId;

  @override
  ConsumerState<CarromBoardScreen> createState() => _CarromBoardScreenState();
}

class _CarromBoardScreenState extends ConsumerState<CarromBoardScreen> {
  Offset? _dragStart;
  Offset? _dragCurrent;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(carromProvider(widget.familyId));
      if (state.game == null) {
        ref.read(carromProvider(widget.familyId).notifier).loadGame(widget.gameId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(carromProvider(widget.familyId));
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
            ref.read(carromProvider(widget.familyId).notifier).leaveGame();
            Navigator.of(context).pop();
          },
        ),
        title: Text(
          'Carrom',
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
                  .read(carromProvider(widget.familyId).notifier)
                  .loadGame(widget.gameId),
            )
          : state.game == null
          ? const Center(
              child: CircularProgressIndicator(color: KinrelColors.orange),
            )
          : _gameView(state, myId),
    );
  }

  Widget _gameView(CarromState state, String? myId) {
    final game = state.game!;
    final isMyTurn = game.currentTurnPlayerId == myId;
    final myColor = game.colorFor(myId);
    final myPlayerNumber = game.playerNumberFor(myId);
    final opponentName = myPlayerNumber == 1
        ? game.playerTwoName
        : game.playerOneName;
    final myScore = myPlayerNumber == 1
        ? game.playerOneScore
        : game.playerTwoScore;
    final opponentScore = myPlayerNumber == 1
        ? game.playerTwoScore
        : game.playerOneScore;

    return SafeArea(
      child: Column(
        children: [
          // Score bar
          _scoreBar(
            myColor: myColor,
            myScore: myScore,
            opponentScore: opponentScore,
            opponentName: opponentName,
            queenStatus: game.queenStatus,
            isMyTurn: isMyTurn,
          ),
          // Turn indicator
          _turnIndicator(game, isMyTurn, opponentName),
          // Board
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(KinrelSpacing.sm),
                child: AspectRatio(
                  aspectRatio: 1.0,
                  child: _boardWidget(state, game, myId, isMyTurn),
                ),
              ),
            ),
          ),
          // Status / instructions
          _statusBar(state, isMyTurn, myColor),
          const SizedBox(height: KinrelSpacing.base),
        ],
      ),
    );
  }

  Widget _scoreBar({
    required CarromCoinType? myColor,
    required int myScore,
    required int opponentScore,
    required String opponentName,
    required CarromQueenStatus queenStatus,
    required bool isMyTurn,
  }) {
    return Container(
      margin: const EdgeInsets.all(KinrelSpacing.base),
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.md,
        vertical: KinrelSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(color: KinrelColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _scoreChip('You', myScore, myColor, isMyTurn),
          if (queenStatus != CarromQueenStatus.onBoard)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: KinrelColors.error.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                queenStatus == CarromQueenStatus.pottedCovered
                    ? 'Queen ✓'
                    : 'Queen!',
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 10,
                  color: KinrelColors.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          _scoreChip(opponentName, opponentScore, null, !isMyTurn),
        ],
      ),
    );
  }

  Widget _scoreChip(
    String name,
    int score,
    CarromCoinType? color,
    bool isActive,
  ) {
    final chipColor = color == CarromCoinType.white
        ? Colors.white
        : color == CarromCoinType.black
        ? const Color(0xFF1F2937)
        : KinrelColors.orange;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (color != null)
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: chipColor,
                  border: Border.all(
                    color: isActive ? KinrelColors.orange : Colors.transparent,
                    width: 2,
                  ),
                ),
              )
            else
              Icon(
                Icons.person,
                size: 12,
                color: isActive ? KinrelColors.orange : KinrelColors.textDim,
              ),
            const SizedBox(width: 4),
            Text(
              name,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 11,
                color: isActive ? KinrelColors.textWhite : KinrelColors.textDim,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '$score/9',
          style: TextStyle(
            fontFamily: KinrelTypography.monoFont,
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: isActive ? KinrelColors.orange : KinrelColors.textWhite,
          ),
        ),
      ],
    );
  }

  Widget _turnIndicator(
    CarromGame game,
    bool isMyTurn,
    String opponentName,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.md,
        vertical: KinrelSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: (isMyTurn ? KinrelColors.orange : KinrelColors.darkElevated)
            .withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(
          color: isMyTurn ? KinrelColors.orange : KinrelColors.border,
          width: 1,
        ),
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
                color: KinrelColors.textDim,
              ),
            ),
          const SizedBox(width: KinrelSpacing.sm),
          Text(
            isMyTurn ? 'Your turn — drag to aim!' : '$opponentName\'s turn…',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              color: isMyTurn ? Colors.white : KinrelColors.textDim,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _boardWidget(
    CarromState state,
    CarromGame game,
    String? myId,
    bool isMyTurn,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.maxWidth;
        return GestureDetector(
          onPanStart: (details) {
            if (!isMyTurn || state.isSimulating) return;
            _dragStart = details.localPosition;
            _dragCurrent = details.localPosition;
          },
          onPanUpdate: (details) {
            if (!isMyTurn || state.isSimulating) return;
            _dragCurrent = details.localPosition;
            _updateAim(state, game, size);
          },
          onPanEnd: (details) {
            if (!isMyTurn || state.isSimulating) return;
            _executeFlick(state, game, size);
            _dragStart = null;
            _dragCurrent = null;
          },
          child: CustomPaint(
            size: Size(size, size),
            painter: CarromBoardPainter(
              coins: game.boardState,
              liveCoinPositions: state.liveCoinPositions,
              strikerBasePos: (
                game.strikerX,
                game.strikerY,
              ),
              liveStrikerPos: state.liveStrikerPosition,
              aimAngle: state.aimAngle,
              aimPower: state.aimPower,
              isSimulating: state.isSimulating,
              myColor: game.colorFor(myId),
              isMyTurn: isMyTurn,
              boardSize: size,
            ),
          ),
        );
      },
    );
  }

  void _updateAim(CarromState state, CarromGame game, double boardSize) {
    if (_dragStart == null || _dragCurrent == null) return;

    // Convert striker position from physics coords to screen coords
    final strikerScreenX = ((game.strikerX + 1) / 2) * boardSize;
    final strikerScreenY = ((game.strikerY + 1) / 2) * boardSize;
    final strikerScreen = Offset(strikerScreenX, strikerScreenY);

    // Direction from striker to drag current position
    final delta = _dragCurrent! - strikerScreen;
    final angle = math.atan2(delta.dy, delta.dx);
    final distance = delta.distance;

    // Power: 0 to 1, based on drag distance (max = boardSize/3)
    final maxDrag = boardSize / 3;
    final power = (distance / maxDrag).clamp(0.1, 1.0);

    ref.read(carromProvider(widget.familyId).notifier).setAim(angle, power);
  }

  void _executeFlick(CarromState state, CarromGame game, double boardSize) {
    final angle = state.aimAngle;
    final power = state.aimPower;
    if (angle == null || power == null) return;

    ref.read(carromProvider(widget.familyId).notifier).executeFlick(angle, power);
    ref.read(carromProvider(widget.familyId).notifier).clearAim();
  }

  Widget _statusBar(
    CarromState state,
    bool isMyTurn,
    CarromCoinType? myColor,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: Column(
        children: [
          if (state.error != null)
            Text(
              state.error!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: KinrelColors.warning,
              ),
            ),
          if (state.lastTurnResult != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _turnResultMessage(state.lastTurnResult!),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  color: state.lastTurnResult!.wasFoul
                      ? KinrelColors.error
                      : KinrelColors.success,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (state.isSimulating)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: KinrelColors.orange,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Simulating…',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      color: KinrelColors.textDim,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _turnResultMessage(TurnResult result) {
    if (result.gameOver) return 'Game Over!';
    if (result.wasFoul) return 'Foul: ${result.foulReason}';
    if (result.queenCovered) return 'Queen covered! Extra turn!';
    if (result.queenPotted) return 'Queen potted — cover it next turn!';
    if (result.extraTurn) return 'Nice shot! Extra turn!';
    if (result.pottedCoins.isEmpty) return 'No coins potted — turn passes';
    return 'Turn passes';
  }

  // ── Results view ──────────────────────────────────────────────────

  Widget _resultsView(CarromState state, String? myId) {
    final game = state.game!;
    final isWinner = game.winnerId == myId;
    final winnerName = game.winnerName ?? 'Player';

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
          const SizedBox(height: KinrelSpacing.xxl),
          DKButton(
            label: 'Play Again',
            variant: DKButtonVariant.gradient,
            fullWidth: true,
            icon: Icons.refresh_rounded,
            onPressed: () {
              ref.read(carromProvider(widget.familyId).notifier).leaveGame();
              if (context.mounted) {
                context.pushReplacement(
                  '/family/${widget.familyId}/carrom/lobby',
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
              ref.read(carromProvider(widget.familyId).notifier).leaveGame();
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

// ── CustomPainter for the Carrom board ─────────────────────────────

class CarromBoardPainter extends CustomPainter {
  CarromBoardPainter({
    required this.coins,
    required this.liveCoinPositions,
    required this.strikerBasePos,
    required this.liveStrikerPos,
    required this.aimAngle,
    required this.aimPower,
    required this.isSimulating,
    required this.myColor,
    required this.isMyTurn,
    required this.boardSize,
  });

  final List<CarromCoin> coins;
  final Map<int, (double, double)> liveCoinPositions;
  final (double, double) strikerBasePos;
  final (double, double)? liveStrikerPos;
  final double? aimAngle;
  final double? aimPower;
  final bool isSimulating;
  final CarromCoinType? myColor;
  final bool isMyTurn;
  final double boardSize;

  /// Convert physics coordinates (-1 to +1) to screen coordinates.
  Offset _toScreen(double x, double y) {
    return Offset(
      ((x + 1) / 2) * boardSize,
      ((y + 1) / 2) * boardSize,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;

    // ── Board background ────────────────────────────────────────────
    final boardPaint = Paint()
      ..color = const Color(0xFF1A1410) // dark warm wood
      ..style = PaintingStyle.fill;
    canvas.drawRect(Offset.zero & size, boardPaint);

    // Board border (amber accent)
    final borderPaint = Paint()
      ..color = KinrelColors.amber
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawRect(
      Rect.fromCenter(center: Offset(s / 2, s / 2), width: s - 4, height: s - 4),
      borderPaint,
    );

    // Inner border line
    final innerBorderPaint = Paint()
      ..color = KinrelColors.amber.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final inset = s * 0.05;
    canvas.drawRect(
      Rect.fromLTWH(inset, inset, s - 2 * inset, s - 2 * inset),
      innerBorderPaint,
    );

    // ── Center circle ───────────────────────────────────────────────
    final centerPaint = Paint()
      ..color = KinrelColors.amber.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;
    final centerRadius = s * 0.12;
    canvas.drawCircle(Offset(s / 2, s / 2), centerRadius, centerPaint);
    final centerStrokePaint = Paint()
      ..color = KinrelColors.amber.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(Offset(s / 2, s / 2), centerRadius, centerStrokePaint);

    // ── Baselines ──────────────────────────────────────────────────
    final baselinePaint = Paint()
      ..color = KinrelColors.amber.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    // Player 1 baseline (bottom)
    final y1 = ((CarromBoard.baselineY1 + 1) / 2) * s;
    final xMin = ((CarromBoard.baselineMinX + 1) / 2) * s;
    final xMax = ((CarromBoard.baselineMaxX + 1) / 2) * s;
    canvas.drawLine(Offset(xMin, y1), Offset(xMax, y1), baselinePaint);
    // Player 2 baseline (top)
    final y2 = ((CarromBoard.baselineY2 + 1) / 2) * s;
    canvas.drawLine(Offset(xMin, y2), Offset(xMax, y2), baselinePaint);

    // ── Pockets ─────────────────────────────────────────────────────
    for (final pocket in CarromBoard.pocketPositions) {
      final pos = _toScreen(pocket.x, pocket.y);
      final pocketPaint = Paint()
        ..color = const Color(0xFF0A0A0A)
        ..style = PaintingStyle.fill;
      final pocketScreenRadius = (CarromBoard.pocketRadius / 2) * s;
      canvas.drawCircle(pos, pocketScreenRadius, pocketPaint);
      // Pocket rim
      final rimPaint = Paint()
        ..color = KinrelColors.amber.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(pos, pocketScreenRadius, rimPaint);
    }

    // ── Coins ──────────────────────────────────────────────────────
    for (int i = 0; i < coins.length; i++) {
      if (coins[i].isPotted) continue;

      // Use live position if available, otherwise use stored position
      double x, y;
      if (liveCoinPositions.containsKey(i) && isSimulating) {
        x = liveCoinPositions[i]!.$1;
        y = liveCoinPositions[i]!.$2;
      } else {
        x = coins[i].x;
        y = coins[i].y;
      }

      final pos = _toScreen(x, y);
      final coinScreenRadius = (CarromPhysics.coinRadius / 2) * s;

      // Coin color
      Color coinColor;
      Color coinBorderColor;
      switch (coins[i].type) {
        case CarromCoinType.white:
          coinColor = Colors.white;
          coinBorderColor = const Color(0xFFCCCCCC);
          break;
        case CarromCoinType.black:
          coinColor = const Color(0xFF1F2937);
          coinBorderColor = const Color(0xFF374151);
          break;
        case CarromCoinType.queen:
          coinColor = const Color(0xFFEF4444); // red queen
          coinBorderColor = const Color(0xFFDC2626);
          break;
      }

      // Highlight own-color coins
      final isOwnColor = coins[i].type == myColor;
      final coinPaint = Paint()..color = coinColor;
      canvas.drawCircle(pos, coinScreenRadius, coinPaint);

      // Border
      final borderPaint = Paint()
        ..color = isOwnColor ? KinrelColors.orange : coinBorderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = isOwnColor ? 2 : 1;
      canvas.drawCircle(pos, coinScreenRadius, borderPaint);
    }

    // ── Striker ─────────────────────────────────────────────────────
    double strikerX, strikerY;
    if (liveStrikerPos != null && isSimulating) {
      strikerX = liveStrikerPos!.$1;
      strikerY = liveStrikerPos!.$2;
    } else {
      strikerX = strikerBasePos.$1;
      strikerY = strikerBasePos.$2;
    }
    final strikerPos = _toScreen(strikerX, strikerY);
    final strikerScreenRadius = (CarromPhysics.strikerRadius / 2) * s;

    // Striker glow if it's my turn
    if (isMyTurn && !isSimulating) {
      final glowPaint = Paint()
        ..color = KinrelColors.orange.withValues(alpha: 0.3)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        strikerPos,
        strikerScreenRadius * 1.5,
        glowPaint,
      );
    }

    final strikerPaint = Paint()
      ..color = isMyTurn && !isSimulating
          ? KinrelColors.orange
          : KinrelColors.amber;
    canvas.drawCircle(strikerPos, strikerScreenRadius, strikerPaint);

    final strikerBorderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(strikerPos, strikerScreenRadius, strikerBorderPaint);

    // ── Aim line ────────────────────────────────────────────────────
    if (aimAngle != null && aimPower != null && isMyTurn && !isSimulating) {
      final lineLength = aimPower! * s * 0.3;
      final endX = strikerPos.dx + lineLength * math.cos(aimAngle!);
      final endY = strikerPos.dy + lineLength * math.sin(aimAngle!);
      final aimPaint = Paint()
        ..color = KinrelColors.orange.withValues(alpha: 0.6 + aimPower! * 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(strikerPos, Offset(endX, endY), aimPaint);

      // Arrowhead
      final arrowSize = 8.0;
      final arrowAngle1 = aimAngle! + math.pi - 0.4;
      final arrowAngle2 = aimAngle! + math.pi + 0.4;
      final arrowPaint = Paint()
        ..color = KinrelColors.orange
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(endX, endY),
        Offset(
          endX + arrowSize * math.cos(arrowAngle1),
          endY + arrowSize * math.sin(arrowAngle1),
        ),
        arrowPaint,
      );
      canvas.drawLine(
        Offset(endX, endY),
        Offset(
          endX + arrowSize * math.cos(arrowAngle2),
          endY + arrowSize * math.sin(arrowAngle2),
        ),
        arrowPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CarromBoardPainter oldDelegate) => true;
}

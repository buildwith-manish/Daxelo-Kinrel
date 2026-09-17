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
import '../shared/icons/kinrel_icons.dart';
import '../shared/multiplayer/multiplayer.dart';
import '../shared/services/temporary_room_service.dart';
import '../shared/widgets/game_board_shell.dart';
import '../shared/widgets/game_confetti.dart';
import 'carrom_constants.dart';
import 'carrom_game_logic.dart';
import 'carrom_models.dart';
import 'carrom_provider.dart';
import '../../gaming_ecosystem/presentation/match_ecosystem_summary.dart';

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

class _CarromBoardScreenState extends ConsumerState<CarromBoardScreen>
    with SingleTickerProviderStateMixin {
  Offset? _dragStart;
  Offset? _dragCurrent;

  /// Breathing glow on the striker while the player aims — premium
  /// "your move" affordance without re-running the physics painter.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(carromProvider(widget.familyId));
      if (state.game == null) {
        ref
            .read(carromProvider(widget.familyId).notifier)
            .loadGame(widget.gameId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(carromProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;

    // RoomKeepAlive: keep the room framework (host heartbeat + room
    // realtime) alive for the whole lifetime of this screen — the
    // challenge lobby that attached the RoomController is replaced by
    // this route; without a watch the autoDispose controller dies and
    // the server-side reaper auto-closes the room ~60-75s in.
    Widget view = RoomKeepAlive(
      roomKey: RoomControllerKey(RoomConfig.carrom, widget.familyId),
      child: DKScaffold(
        backgroundColor: KinrelColors.darkSurface,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            // Plain pop — the route-level onExit guard (app_router.dart)
            // intercepts this while a game room is active and shows the
            // confirmation dialog first.
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/family/${widget.familyId}');
              }
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
                // Room closed by the host → terminal state, offer a clean
                // exit back to the games hub instead of a pointless retry.
                actionLabel: state.error == kRoomClosedMessage
                    ? 'Back to Games'
                    : null,
                icon: state.error == kRoomClosedMessage
                    ? Icons.meeting_room_rounded
                    : null,
                onRetry: state.error == kRoomClosedMessage
                    ? () => context.go('/games?familyId=${widget.familyId}')
                    : () => ref
                          .read(carromProvider(widget.familyId).notifier)
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
          const SizedBox(height: KinrelSpacing.sm),
          // Turn indicator
          _turnIndicator(game, isMyTurn, opponentName),
          const SizedBox(height: KinrelSpacing.sm),
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
      margin: const EdgeInsets.fromLTRB(
        KinrelSpacing.base,
        KinrelSpacing.base,
        KinrelSpacing.base,
        0,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.md,
        vertical: KinrelSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1C1824), Color(0xFF141119)],
        ),
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(
          color: isMyTurn
              ? KinrelColors.amber.withValues(alpha: 0.45)
              : KinrelColors.border,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _scoreChip('You', myScore, myColor, isMyTurn),
          if (queenStatus != CarromQueenStatus.onBoard)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.3, -0.4),
                  colors: [
                    KinrelColors.error.withValues(alpha: 0.35),
                    KinrelColors.error.withValues(alpha: 0.08),
                  ],
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: KinrelColors.error.withValues(alpha: 0.7),
                ),
                boxShadow: [
                  BoxShadow(
                    color: KinrelColors.error.withValues(alpha: 0.35),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    queenStatus == CarromQueenStatus.pottedCovered ? '♛' : '♕',
                    style: TextStyle(
                      fontSize: 15,
                      color: queenStatus == CarromQueenStatus.pottedCovered
                          ? KinrelColors.brightGold
                          : KinrelColors.error,
                    ),
                  ),
                  Text(
                    queenStatus == CarromQueenStatus.pottedCovered
                        ? 'COVERED'
                        : 'QUEEN',
                    style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 7.5,
                      letterSpacing: 1.1,
                      color: queenStatus == CarromQueenStatus.pottedCovered
                          ? KinrelColors.brightGold
                          : KinrelColors.error,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
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
        ? const Color(0xFFEFE6D2)
        : color == CarromCoinType.black
        ? const Color(0xFF2A1F16)
        : KinrelColors.orange;
    final lead = score >= 9;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (color != null)
              GamePiece3D(
                color: chipColor,
                size: 16,
                ring: isActive ? KinrelColors.orange : null,
                glow: isActive,
              )
            else
              Icon(
                Icons.person_rounded,
                size: 14,
                color: isActive ? KinrelColors.orange : KinrelColors.textDim,
              ),
            const SizedBox(width: 6),
            Text(
              name,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 11.5,
                color: isActive ? KinrelColors.textWhite : KinrelColors.textDim,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '$score/9',
          style: TextStyle(
            fontFamily: KinrelTypography.monoFont,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: isActive
                ? (lead ? KinrelColors.brightGold : KinrelColors.orange)
                : KinrelColors.textWhite,
          ),
        ),
        const SizedBox(height: 4),
        // Coin collection progress — goal-gradient cue.
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            width: 64,
            height: 4,
            child: LinearProgressIndicator(
              value: (score / 9).clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation(
                lead ? KinrelColors.brightGold : chipColor,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _turnIndicator(CarromGame game, bool isMyTurn, String opponentName) {
    return Center(
      child: GameTurnPill(
        label: isMyTurn ? 'Your turn — drag to aim!' : '$opponentName\'s turn…',
        color: KinrelColors.amber,
        active: isMyTurn,
        icon: isMyTurn ? Icons.pan_tool_rounded : Icons.hourglass_top_rounded,
      ),
    );
  }

  Widget _boardWidget(
    CarromState state,
    CarromGame game,
    String? myId,
    bool isMyTurn,
  ) {
    // Breathing striker glow only while this player may act.
    final wantPulse = isMyTurn && !state.isSimulating;
    if (wantPulse && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!wantPulse && _pulse.isAnimating) {
      _pulse.stop();
    }

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
          child: GameBoardShell(
            accent: KinrelColors.amber,
            surface: BoardSurface.wood,
            radius: 24,
            padding: 12,
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) => CustomPaint(
                size: Size(size, size),
                painter: CarromBoardPainter(
                  coins: game.boardState,
                  liveCoinPositions: state.liveCoinPositions,
                  strikerBasePos: (game.strikerX, game.strikerY),
                  liveStrikerPos: state.liveStrikerPosition,
                  aimAngle: state.aimAngle,
                  aimPower: state.aimPower,
                  isSimulating: state.isSimulating,
                  myColor: game.colorFor(myId),
                  isMyTurn: isMyTurn,
                  boardSize: size,
                  pulse: wantPulse ? _pulse.value : 0,
                ),
              ),
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

    ref
        .read(carromProvider(widget.familyId).notifier)
        .executeFlick(angle, power);
    ref.read(carromProvider(widget.familyId).notifier).clearAim();
  }

  Widget _statusBar(CarromState state, bool isMyTurn, CarromCoinType? myColor) {
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
              Column(
                    children: [
                      const KinrelIcon(KinrelIconData.trophy,
                        size: 64, color: KinrelColors.brightGold)
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
              const SizedBox(height: KinrelSpacing.md),
              _resultsScoreCard(game, myId),
              MatchEcosystemSummary(
                gameTable: 'carrom_games',
                gameId: game.id,
                familyId: widget.familyId,
              ),
              const SizedBox(height: KinrelSpacing.xxl),
              DKButton(
                label: 'Play Again',
                variant: DKButtonVariant.gradient,
                fullWidth: true,
                icon: Icons.refresh_rounded,
                onPressed: () {
                  final gameId = ref
                      .read(carromProvider(widget.familyId))
                      .game
                      ?.id;
                  ref
                      .read(carromProvider(widget.familyId).notifier)
                      .leaveGame();
                  if (gameId != null) {
                    ref
                        .read(temporaryRoomServiceProvider)
                        .endGame(gameTable: 'carrom_games', gameId: gameId);
                  }
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
                  final gameId = ref
                      .read(carromProvider(widget.familyId))
                      .game
                      ?.id;
                  ref
                      .read(carromProvider(widget.familyId).notifier)
                      .leaveGame();
                  if (gameId != null) {
                    ref
                        .read(temporaryRoomServiceProvider)
                        .endGame(gameTable: 'carrom_games', gameId: gameId);
                  }
                  if (context.mounted) {
                    context.go('/games?familyId=${widget.familyId}');
                  }
                },
              ),
            ],
          ),
          if (isWinner)
            const GameConfetti(
              colors: [
                KinrelColors.brightGold,
                KinrelColors.orange,
                KinrelColors.amber,
                Color(0xFFF6E7C8),
              ],
            ),
        ],
      ),
    );
  }

  /// Final coin count card — the data epilogue under the trophy.
  Widget _resultsScoreCard(CarromGame game, String? myId) {
    final myNumber = game.playerNumberFor(myId);
    final myScore = myNumber == 1 ? game.playerOneScore : game.playerTwoScore;
    final oppScore = myNumber == 1 ? game.playerTwoScore : game.playerOneScore;
    final oppName = myNumber == 1 ? game.playerTwoName : game.playerOneName;
    final queenMine = game.queenStatus == CarromQueenStatus.pottedCovered;

    return Container(
      padding: const EdgeInsets.all(KinrelSpacing.md),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: KinrelColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _finalScoreColumn('You', myScore, KinrelColors.orange, true),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'COINS',
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 9,
                  letterSpacing: 1.6,
                  color: KinrelColors.textDim,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              if (queenMine)
                const Text(
                  '♛',
                  style: TextStyle(
                    fontSize: 16,
                    color: KinrelColors.brightGold,
                  ),
                )
              else
                Text(
                  myScore > oppScore ? '▲' : (myScore < oppScore ? '▼' : '—'),
                  style: TextStyle(
                    fontSize: 14,
                    color: myScore > oppScore
                        ? KinrelColors.success
                        : (myScore < oppScore
                              ? KinrelColors.error
                              : KinrelColors.textDim),
                  ),
                ),
            ],
          ),
          _finalScoreColumn(oppName, oppScore, KinrelColors.blue, false),
        ],
      ),
    );
  }

  Widget _finalScoreColumn(String name, int score, Color accent, bool mine) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name.isEmpty ? 'Family' : name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 11.5,
            color: mine ? KinrelColors.textWhite : KinrelColors.textDim,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$score',
          style: TextStyle(
            fontFamily: KinrelTypography.monoFont,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: mine ? accent : KinrelColors.textWhite,
          ),
        ),
      ],
    );
  }
}

// ── CustomPainter for the Carrom board ─────────────────────────────
//
// Premium carrom table:
//   • Plywood playing surface — warm maple gradient lit from the
//     top-left, deterministic wood-grain streaks.
//   • Classic carrom markings — double frame, baselines with end
//     circles, center sun medallion, deep red lacquer.
//   • Pockets machined into the wood — dark bores with rim highlight.
//   • Coins & striker as radial-lit 3D discs with grounded shadows.
//   • Aim system — power-tinted dashed guide, arrowhead and charge
//     ring around the striker.

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
    this.pulse = 0,
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

  /// Breathing striker glow while the player aims (0..1).
  final double pulse;

  /// Convert physics coordinates (-1 to +1) to screen coordinates.
  Offset _toScreen(double x, double y) {
    return Offset(((x + 1) / 2) * boardSize, ((y + 1) / 2) * boardSize);
  }

  @override
  void paint(Canvas canvas, Size size) {
    _paintSurface(canvas, size);
    _paintMarkings(canvas, size);
    _paintPockets(canvas, size);
    _paintCoins(canvas, size);
    _paintStriker(canvas, size);
    _paintAim(canvas, size);
  }

  // ── Plywood surface ─────────────────────────────────────────────

  void _paintSurface(Canvas canvas, Size size) {
    final s = size.width;

    // Warm maple plywood, lit from the top-left.
    final surface = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFE5C58C), Color(0xFFD6AF74), Color(0xFFC69A5D)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, surface);

    // Soft directional sheen.
    final sheen = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.55, -0.6),
        radius: 1.5,
        colors: [
          Colors.white.withValues(alpha: 0.16),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, sheen);

    // Deterministic wood grain — stable across repaints.
    final rng = math.Random(11);
    final grain = Paint()
      ..color = const Color(0xFF8A6435).withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke;
    for (var y = 3.0; y < s; y += 5 + rng.nextDouble() * 6) {
      final path = Path()..moveTo(0, y);
      for (var x = 0.0; x <= s; x += s / 6) {
        path.lineTo(x, y + math.sin(x * 0.045 + y * 0.7) * 1.6);
      }
      canvas.drawPath(path, grain..strokeWidth = 0.7 + rng.nextDouble() * 0.9);
    }
  }

  // ── Classic lacquer markings ────────────────────────────────────

  void _paintMarkings(Canvas canvas, Size size) {
    final s = size.width;
    final lacquer = const Color(0xFF9C3B22);

    // Double frame.
    final frame = Paint()
      ..color = lacquer.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.6, s * 0.006);
    final outer = Rect.fromLTWH(s * 0.035, s * 0.035, s * 0.93, s * 0.93);
    final inner = Rect.fromLTWH(s * 0.055, s * 0.055, s * 0.89, s * 0.89);
    canvas.drawRRect(
      RRect.fromRectAndRadius(outer, Radius.circular(s * 0.02)),
      frame,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(inner, Radius.circular(s * 0.015)),
      frame..strokeWidth = math.max(1.0, s * 0.004),
    );

    // Baselines — two parallel lines with end circles per player.
    final linePaint = Paint()
      ..color = lacquer.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.4, s * 0.005)
      ..strokeCap = StrokeCap.round;
    final gap = s * 0.018;
    final circleR = s * 0.028;
    final xMin = ((CarromBoard.baselineMinX + 1) / 2) * s;
    final xMax = ((CarromBoard.baselineMaxX + 1) / 2) * s;
    for (final by in <double>[CarromBoard.baselineY1, CarromBoard.baselineY2]) {
      final y = ((by + 1) / 2) * s;
      canvas.drawLine(Offset(xMin, y - gap), Offset(xMax, y - gap), linePaint);
      canvas.drawLine(Offset(xMin, y + gap), Offset(xMax, y + gap), linePaint);
      canvas.drawCircle(Offset(xMin, y), circleR, linePaint);
      canvas.drawCircle(Offset(xMax, y), circleR, linePaint);
    }

    // Center sun medallion.
    final center = Offset(s / 2, s / 2);
    final medOuter = s * 0.13;
    final medInner = s * 0.075;
    canvas.drawCircle(center, medOuter, linePaint);
    canvas.drawCircle(center, medInner, linePaint);
    // Petal spokes between the circles.
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      canvas.drawLine(
        center + Offset(math.cos(a) * medInner, math.sin(a) * medInner),
        center + Offset(math.cos(a) * medOuter, math.sin(a) * medOuter),
        linePaint..strokeWidth = math.max(1.0, s * 0.004),
      );
    }
    // Amber core dot.
    canvas.drawCircle(
      center,
      s * 0.018,
      Paint()..color = KinrelColors.amber.withValues(alpha: 0.8),
    );

    // Corner arrows pointing into the pockets.
    final arrowPaint = Paint()
      ..color = lacquer.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, s * 0.0045)
      ..strokeCap = StrokeCap.round;
    final inset = s * 0.09;
    final len = s * 0.10;
    void cornerArrow(double cx, double cy, double dx, double dy) {
      final start = Offset(cx + dx * inset, cy + dy * inset);
      final end = Offset(cx + dx * (inset + len), cy + dy * (inset + len));
      canvas.drawLine(start, end, arrowPaint);
      // Small arrowhead.
      final a = math.atan2(dy, dx);
      for (final side in <double>[0.5, -0.5]) {
        canvas.drawLine(
          end,
          Offset(
            end.dx - math.cos(a + side) * s * 0.018,
            end.dy - math.sin(a + side) * s * 0.018,
          ),
          arrowPaint,
        );
      }
    }

    cornerArrow(0, 0, 1, 1);
    cornerArrow(s, 0, -1, 1);
    cornerArrow(0, s, 1, -1);
    cornerArrow(s, s, -1, -1);
  }

  // ── Pockets machined into the wood ──────────────────────────────

  void _paintPockets(Canvas canvas, Size size) {
    final s = size.width;
    for (final pocket in CarromBoard.pocketPositions) {
      final pos = _toScreen(pocket.x, pocket.y);
      final r = (CarromBoard.pocketRadius / 2) * s;

      // Dark bore with depth.
      final bore = Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.1, 0.15),
          radius: 1.1,
          colors: [
            const Color(0xFF040302),
            const Color(0xFF1C1108),
            const Color(0xFF33200F),
          ],
          stops: const [0.0, 0.65, 1.0],
        ).createShader(Rect.fromCircle(center: pos, radius: r));
      canvas.drawCircle(pos, r, bore);

      // Machined rim — lit on the top-left, shaded bottom-right.
      final rim = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFC79A5C).withValues(alpha: 0.75),
            const Color(0xFF6B4A26).withValues(alpha: 0.6),
          ],
        ).createShader(Rect.fromCircle(center: pos, radius: r));
      canvas.drawCircle(pos, r, rim);

      // Inner shadow ring.
      canvas.drawCircle(
        pos,
        r * 0.78,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Colors.black.withValues(alpha: 0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
      );
    }
  }

  // ── Coins — radial-lit 3D discs ─────────────────────────────────

  void _paintCoins(Canvas canvas, Size size) {
    final s = size.width;
    for (int i = 0; i < coins.length; i++) {
      if (coins[i].isPotted) continue;

      double x, y;
      if (liveCoinPositions.containsKey(i) && isSimulating) {
        x = liveCoinPositions[i]!.$1;
        y = liveCoinPositions[i]!.$2;
      } else {
        x = coins[i].x;
        y = coins[i].y;
      }

      final pos = _toScreen(x, y);
      final r = (CarromPhysics.coinRadius / 2) * s;
      final isOwnColor = coins[i].type == myColor;

      switch (coins[i].type) {
        case CarromCoinType.white:
          _drawDisc(
            canvas,
            pos,
            r,
            light: const Color(0xFFFFFAF0),
            base: const Color(0xFFEEE2C6),
            dark: const Color(0xFFB3A06F),
            ring: isOwnColor ? KinrelColors.orange : null,
          );
          break;
        case CarromCoinType.black:
          _drawDisc(
            canvas,
            pos,
            r,
            light: const Color(0xFF5E4934),
            base: const Color(0xFF2E2115),
            dark: const Color(0xFF0D0803),
            ring: isOwnColor ? KinrelColors.orange : null,
          );
          break;
        case CarromCoinType.queen:
          _drawDisc(
            canvas,
            pos,
            r,
            light: const Color(0xFFFF8E97),
            base: const Color(0xFFE0404E),
            dark: const Color(0xFF7C101E),
            ring: KinrelColors.brightGold.withValues(alpha: 0.9),
          );
          // Queen crown dot.
          canvas.drawCircle(
            pos,
            r * 0.28,
            Paint()..color = const Color(0xFFFFE9B8).withValues(alpha: 0.95),
          );
          break;
      }
    }
  }

  /// A radial-lit disc with grounded shadow, dark rim, optional ring
  /// and specular highlight — the shared "physical piece" language.
  void _drawDisc(
    Canvas canvas,
    Offset c,
    double radius, {
    required Color light,
    required Color base,
    required Color dark,
    Color? ring,
  }) {
    // Grounded shadow.
    canvas.drawCircle(
      c + Offset(0, radius * 0.2),
      radius * 0.95,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.30)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.38),
    );

    // Body — lit from the top-left.
    final body = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.45, -0.5),
        radius: 1.3,
        colors: [light, base, dark],
        stops: const [0.05, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: c, radius: radius));
    canvas.drawCircle(c, radius, body);

    // Dark rim.
    canvas.drawCircle(
      c,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, radius * 0.09)
        ..color = dark.withValues(alpha: 0.85),
    );

    // Optional contrasting ring inset.
    if (ring != null) {
      canvas.drawCircle(
        c,
        radius * 0.72,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.8, radius * 0.07)
          ..color = ring,
      );
    }

    // Specular highlight.
    final spec = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.4, -0.45),
        radius: 0.55,
        colors: [
          Colors.white.withValues(alpha: 0.55),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: c, radius: radius));
    canvas.drawCircle(c, radius * 0.85, spec);
  }

  // ── Striker — ivory disc with breathing glow ────────────────────

  void _paintStriker(Canvas canvas, Size size) {
    final s = size.width;
    double strikerX, strikerY;
    if (liveStrikerPos != null && isSimulating) {
      strikerX = liveStrikerPos!.$1;
      strikerY = liveStrikerPos!.$2;
    } else {
      strikerX = strikerBasePos.$1;
      strikerY = strikerBasePos.$2;
    }
    final pos = _toScreen(strikerX, strikerY);
    final r = (CarromPhysics.strikerRadius / 2) * s;

    if (isMyTurn && !isSimulating) {
      // Breathing halo while the player aims.
      final glow = Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 1.0,
          colors: [
            KinrelColors.orange.withValues(alpha: 0.34 + 0.22 * pulse),
            KinrelColors.orange.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: pos, radius: r * 2.6));
      canvas.drawCircle(pos, r * 2.6, glow);
    }

    _drawDisc(
      canvas,
      pos,
      r,
      light: const Color(0xFFFFFCF4),
      base: const Color(0xFFF2E8D4),
      dark: const Color(0xFFBFA87E),
      ring: isMyTurn && !isSimulating
          ? KinrelColors.orange
          : KinrelColors.amber.withValues(alpha: 0.8),
    );
  }

  // ── Aim system — dashed guide + charge ring ──────────────────────

  void _paintAim(Canvas canvas, Size size) {
    final s = size.width;
    if (aimAngle == null || aimPower == null || !isMyTurn || isSimulating) {
      return;
    }

    double strikerX, strikerY;
    if (liveStrikerPos != null && isSimulating) {
      strikerX = liveStrikerPos!.$1;
      strikerY = liveStrikerPos!.$2;
    } else {
      strikerX = strikerBasePos.$1;
      strikerY = strikerBasePos.$2;
    }
    final strikerPos = _toScreen(strikerX, strikerY);
    final strikerR = (CarromPhysics.strikerRadius / 2) * s;

    // Power-tinted guide color — gentle → firm → fierce.
    final p = aimPower!.clamp(0.0, 1.0);
    final Color powerColor;
    if (p < 0.45) {
      powerColor = const Color(0xFF7BC96F);
    } else if (p < 0.8) {
      powerColor = const Color(0xFFF5B93E);
    } else {
      powerColor = const Color(0xFFF2704B);
    }

    // Dashed guide from the striker outward.
    final dir = Offset(math.cos(aimAngle!), math.sin(aimAngle!));
    final len = p * s * 0.32;
    final aimPaint = Paint()
      ..color = powerColor.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const dash = 7.0;
    const gap = 5.0;
    var d = strikerR + 5.0;
    Offset? lastDashEnd;
    while (d < len) {
      final from = strikerPos + dir * d;
      final to = strikerPos + dir * math.min(d + dash, len);
      canvas.drawLine(from, to, aimPaint);
      lastDashEnd = to;
      d += dash + gap;
    }

    // Filled arrowhead at the tip.
    final tip = strikerPos + dir * math.max(len, strikerR + 8);
    if (lastDashEnd != null || len > strikerR + 8) {
      final a = aimAngle!;
      final head = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(
          tip.dx - math.cos(a - 0.42) * s * 0.028,
          tip.dy - math.sin(a - 0.42) * s * 0.028,
        )
        ..lineTo(
          tip.dx - math.cos(a + 0.42) * s * 0.028,
          tip.dy - math.sin(a + 0.42) * s * 0.028,
        )
        ..close();
      canvas.drawPath(head, Paint()..color = powerColor);
    }

    // Charge ring around the striker.
    canvas.drawArc(
      Rect.fromCircle(center: strikerPos, radius: strikerR * 1.45),
      -math.pi / 2,
      p * math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..color = powerColor.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(covariant CarromBoardPainter oldDelegate) => true;
}

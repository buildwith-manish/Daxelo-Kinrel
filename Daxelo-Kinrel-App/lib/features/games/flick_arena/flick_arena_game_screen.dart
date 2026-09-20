// lib/features/games/flick_arena/flick_arena_game_screen.dart
//
// Flick Arena — main match screen.
//
// Layout:
//   ┌──────────────────────────────────────┐
//   │  [Team 1 score]  Current Turn  [Team 2]│  ← Match HUD (top)
//   │  [Timer 0:12]                          │
//   ├──────────────────────────────────────┤
//   │                                        │
//   │       ┌──── goal ────┐                │  ← Arena (CustomPainter,
//   │       │               │                │     top-down view)
//   │   ○          ○                          │
//   │       ●                                │
//   │   ○          ○                          │
//   │       └──── goal ────┐                │
//   │                                        │
//   ├──────────────────────────────────────┤
//   │  Drag back from your disc to aim.     │  ← Aim help / status
//   │  Power ▰▰▰▰▱▱  ·  Release to flick    │
//   └──────────────────────────────────────┘
//
// Drag gesture: tap one of your discs to select it, then drag back to
// aim. The painter overlays a power line + aim direction + predicted
// path similar to premium pool games.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../gaming_ecosystem/presentation/match_ecosystem_summary.dart';
import '../../gaming_ecosystem/presentation/widgets/gaming_kit.dart';
import '../shared/icons/kinrel_icons.dart';
import '../shared/widgets/game_confetti.dart';
import '../shared/widgets/leave_game_dialog.dart';
import '../shared/widgets/reactions_bar.dart';
import '../shared/models/game_invite.dart';
import '../shared/widgets/rematch_button.dart';
import 'flick_arena_models.dart';
import 'flick_arena_provider.dart';

class FlickArenaGameScreen extends ConsumerStatefulWidget {
  const FlickArenaGameScreen({
    super.key,
    required this.familyId,
    required this.gameId,
  });
  final String familyId;
  final String gameId;

  @override
  ConsumerState<FlickArenaGameScreen> createState() =>
      _FlickArenaGameScreenState();
}

class _FlickArenaGameScreenState extends ConsumerState<FlickArenaGameScreen>
    with SingleTickerProviderStateMixin {
  /// Drag state — set when the user is currently aiming.
  /// _dragStart is in arena physics coordinates (-1..1 x, -1.5..1.5 y).
  Offset? _dragStartArena;
  Offset? _dragCurrentArena;

  /// The disc that the current drag is flicking (already validated as
  /// owned by the current player).
  String? _aimDiscId;

  /// One-time guard for the waiting-room redirect.
  bool _didWaitingRedirect = false;

  /// Breathing glow on the active player's discs while they aim.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  @override
  void initState() {
    super.initState();
    _pulse.repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(flickArenaProvider(widget.familyId));
      if (state.game == null) {
        ref
            .read(flickArenaProvider(widget.familyId).notifier)
            .loadGame(widget.gameId);
      }
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _confirmLeave() async {
    final state = ref.read(flickArenaProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final shouldLeave = await LeaveGameDialog.show(
      context,
      isHost: state.game?.hostUserId == myId &&
          state.game?.isWaiting == true,
      gameName: 'Flick Arena',
    );
    if (shouldLeave == true) {
      await ref
          .read(flickArenaProvider(widget.familyId).notifier)
          .leaveInProgressMatch();
      if (mounted) {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/family/${widget.familyId}');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(flickArenaProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final game = state.game;

    // Waiting-room redirect — the lobby owns the pre-match phase.
    final waitingGameId = state.isWaiting && game?.id != null
        ? game!.id
        : null;
    if (waitingGameId != null && !_didWaitingRedirect) {
      _didWaitingRedirect = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.pushReplacement(
          '/family/${widget.familyId}/flick-arena/lobby?join=$waitingGameId',
        );
      });
    }

    if (state.isLoading && game == null) {
      return DKScaffold(
        backgroundColor: KinrelColors.darkSurface,
        appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back), onPressed: _confirmLeave),
          title: const Text('Flick Arena'),
          backgroundColor: KinrelColors.darkCard,
          foregroundColor: KinrelColors.textWhite,
        ),
        body: const Center(
          child: CircularProgressIndicator(color: KinrelColors.orange),
        ),
      );
    }

    if (game == null) {
      return DKScaffold(
        backgroundColor: KinrelColors.darkSurface,
        appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/family/${widget.familyId}')),
          title: const Text('Flick Arena'),
          backgroundColor: KinrelColors.darkCard,
          foregroundColor: KinrelColors.textWhite,
        ),
        body: Center(
          child: GamingEmptyCard(
            emoji: '🎯',
            title: 'Game not found',
            message: 'This match may have ended.',
          ),
        ),
      );
    }

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.arrow_back), onPressed: _confirmLeave),
        title: Text(
          game.roomName?.isNotEmpty == true
              ? game.roomName!
              : 'Flick Arena',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontWeight: FontWeight.w600,
            color: KinrelColors.textWhite,
          ),
        ),
        backgroundColor: KinrelColors.darkCard,
        foregroundColor: KinrelColors.textWhite,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(
              child: _MatchTypeChip(game: game),
            ),
          ),
          if (game.hostUserId == myId && game.isInProgress)
            IconButton(
              tooltip: 'Leave',
              icon: const Icon(Icons.logout, size: 20),
              onPressed: _confirmLeave,
            ),
        ],
      ),
      body: game.isCompleted
          ? _ResultsView(
              game: game,
              familyId: widget.familyId,
              isHost: game.hostUserId == myId,
              onRematch: () => ref
                  .read(flickArenaProvider(widget.familyId).notifier)
                  .rematch(),
              onExit: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/family/${widget.familyId}');
                }
              },
            )
          : _MatchView(
              state: state,
              game: game,
              myUserId: myId,
              pulse: _pulse,
              dragStartArena: _dragStartArena,
              dragCurrentArena: _dragCurrentArena,
              aimDiscId: _aimDiscId,
              onAimStart: (discId, startPos) {
                setState(() {
                  _aimDiscId = discId;
                  _dragStartArena = startPos;
                  _dragCurrentArena = startPos;
                });
              },
              onAimUpdate: (pos) {
                setState(() {
                  _dragCurrentArena = pos;
                });
              },
              onAimCancel: () {
                setState(() {
                  _aimDiscId = null;
                  _dragStartArena = null;
                  _dragCurrentArena = null;
                });
                ref
                    .read(flickArenaProvider(widget.familyId).notifier)
                    .clearAim();
              },
              onAimRelease: (angle, power) {
                final discId = _aimDiscId;
                setState(() {
                  _aimDiscId = null;
                  _dragStartArena = null;
                  _dragCurrentArena = null;
                });
                if (discId != null) {
                  ref
                      .read(
                          flickArenaProvider(widget.familyId).notifier)
                      .executeFlick(
                        discId: discId,
                        angle: angle,
                        power: power,
                      );
                }
              },
            ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Match HUD
// ═════════════════════════════════════════════════════════════════════

class _MatchTypeChip extends StatelessWidget {
  const _MatchTypeChip({required this.game});
  final FlickArenaGame game;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: KinrelColors.amber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        game.matchType == FlickArenaMatchType.soloDuel
            ? '1v1 · 3'
            : '2v2 · 5',
        style: TextStyle(
          fontFamily: KinrelTypography.monoFont,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: KinrelColors.amber,
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Match view — HUD + arena + aim status
// ═════════════════════════════════════════════════════════════════════

class _MatchView extends ConsumerWidget {
  const _MatchView({
    required this.state,
    required this.game,
    required this.myUserId,
    required this.pulse,
    required this.dragStartArena,
    required this.dragCurrentArena,
    required this.aimDiscId,
    required this.onAimStart,
    required this.onAimUpdate,
    required this.onAimCancel,
    required this.onAimRelease,
  });

  final FlickArenaState_ state;
  final FlickArenaGame game;
  final String? myUserId;
  final AnimationController pulse;
  final Offset? dragStartArena;
  final Offset? dragCurrentArena;
  final String? aimDiscId;
  final void Function(String discId, Offset startPos) onAimStart;
  final void Function(Offset pos) onAimUpdate;
  final VoidCallback onAimCancel;
  final void Function(double angle, double power) onAimRelease;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMyTurn = game.currentTurnPlayerId == myUserId;
    final mySlot = game.slotForUserId(myUserId);
    final goalsToWin = game.matchType.goalsToWin;

    // Compute aim angle + power from drag.
    double? aimAngle;
    double? aimPower;
    if (dragStartArena != null && dragCurrentArena != null) {
      final delta = dragStartArena! - dragCurrentArena!;
      final dragDist = delta.distance;
      aimAngle = math.atan2(delta.dy, delta.dx);
      // Map drag distance (0..0.6 arena units) to power (0..1).
      aimPower = (dragDist / 0.6).clamp(0.0, 1.0);
    }

    return Column(
      children: [
        // ── Top HUD: Team 1 score | turn + timer | Team 2 score ──
        _TopHud(
          game: game,
          isMyTurn: isMyTurn,
          mySlot: mySlot,
          goalsToWin: goalsToWin,
        ),

        // ── Arena (CustomPainter with drag-to-aim gesture) ──
        Expanded(
          child: _ArenaGestureDetector(
            game: game,
            state: state,
            myUserId: myUserId,
            pulse: pulse,
            aimDiscId: aimDiscId,
            dragStartArena: dragStartArena,
            dragCurrentArena: dragCurrentArena,
            aimAngle: aimAngle,
            aimPower: aimPower,
            onAimStart: onAimStart,
            onAimUpdate: onAimUpdate,
            onAimCancel: onAimCancel,
            onAimRelease: onAimRelease,
          ),
        ),

        // ── Bottom aim status strip ──
        _AimStatusBar(
          isMyTurn: isMyTurn,
          isSimulating: state.isSimulating,
          aimPower: aimPower,
          lastResult: state.lastTurnResult,
          matchType: game.matchType,
        ),
        if (state.amSpectator)
          ReactionsBar(
            gameTable: 'flick_arena_games',
            gameId: game.id,
            familyId: game.familyId,
          ),
      ],
    );
  }
}

class _TopHud extends StatelessWidget {
  const _TopHud({
    required this.game,
    required this.isMyTurn,
    required this.mySlot,
    required this.goalsToWin,
  });
  final FlickArenaGame game;
  final bool isMyTurn;
  final int? mySlot;
  final int goalsToWin;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        border: Border(
          bottom: BorderSide(color: KinrelColors.border),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _TeamScoreBadge(
                label: game.matchType == FlickArenaMatchType.soloDuel
                    ? game.playerOneName
                    : 'Team 1',
                score: game.teamOneScore,
                goalsToWin: goalsToWin,
                color: KinrelColors.orange,
                isMine: mySlot != null && game.teamForSlot(mySlot!) == 1,
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      isMyTurn ? 'YOUR TURN' : '${game.currentTurnPlayerName}\'s turn',
                      style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                        color: isMyTurn
                            ? KinrelColors.amber
                            : KinrelColors.textDim,
                      ),
                    ),
                    const SizedBox(height: 2),
                    TimerText(turnEndsAt: game.turnEndsAt),
                  ],
                ),
              ),
              _TeamScoreBadge(
                label: game.matchType == FlickArenaMatchType.soloDuel
                    ? game.playerTwoName
                    : 'Team 2',
                score: game.teamTwoScore,
                goalsToWin: goalsToWin,
                color: const Color(0xFF22D3EE),
                isMine: mySlot != null && game.teamForSlot(mySlot!) == 2,
                alignEnd: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TeamScoreBadge extends StatelessWidget {
  const _TeamScoreBadge({
    required this.label,
    required this.score,
    required this.goalsToWin,
    required this.color,
    required this.isMine,
    this.alignEnd = false,
  });
  final String label;
  final int score;
  final int goalsToWin;
  final Color color;
  final bool isMine;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final labelWidget = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: KinrelTypography.bodyFont,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: isMine ? color : KinrelColors.textDim,
      ),
    );
    final scoreWidget = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          '$score',
          style: TextStyle(
            fontFamily: KinrelTypography.monoFont,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        Text(
          '/$goalsToWin',
          style: TextStyle(
            fontFamily: KinrelTypography.monoFont,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textDim,
          ),
        ),
      ],
    );
    return SizedBox(
      width: 100,
      child: Column(
        crossAxisAlignment:
            alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [labelWidget, const SizedBox(height: 2), scoreWidget],
      ),
    );
  }
}

/// Live-updating countdown timer.
class TimerText extends StatefulWidget {
  const TimerText({super.key, required this.turnEndsAt});
  final DateTime? turnEndsAt;

  @override
  State<TimerText> createState() => _TimerTextState();
}

class _TimerTextState extends State<TimerText> {
  late final Stream<int> _stream;
  StreamSubscription<int>? _sub;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    _stream = Stream<int>.periodic(const Duration(milliseconds: 250), (_) {
      if (widget.turnEndsAt == null) return 0;
      final left = widget.turnEndsAt!.difference(DateTime.now()).inSeconds;
      return left < 0 ? 0 : left;
    });
    _sub = _stream.listen((s) {
      if (mounted && s != _seconds) setState(() => _seconds = s);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _seconds <= 3
        ? KinrelColors.error
        : _seconds <= 7
            ? KinrelColors.amber
            : KinrelColors.textWhite;
    return Text(
      '$_seconds s',
      style: TextStyle(
        fontFamily: KinrelTypography.monoFont,
        fontSize: 16,
        fontWeight: FontWeight.w800,
        color: color,
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Arena — CustomPainter + drag gesture
// ═════════════════════════════════════════════════════════════════════

class _ArenaGestureDetector extends StatelessWidget {
  const _ArenaGestureDetector({
    required this.game,
    required this.state,
    required this.myUserId,
    required this.pulse,
    required this.aimDiscId,
    required this.dragStartArena,
    required this.dragCurrentArena,
    required this.aimAngle,
    required this.aimPower,
    required this.onAimStart,
    required this.onAimUpdate,
    required this.onAimCancel,
    required this.onAimRelease,
  });

  final FlickArenaGame game;
  final FlickArenaState_ state;
  final String? myUserId;
  final AnimationController pulse;
  final String? aimDiscId;
  final Offset? dragStartArena;
  final Offset? dragCurrentArena;
  final double? aimAngle;
  final double? aimPower;
  final void Function(String discId, Offset startPos) onAimStart;
  final void Function(Offset pos) onAimUpdate;
  final VoidCallback onAimCancel;
  final void Function(double angle, double power) onAimRelease;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // The arena is taller than wide. We compute the largest arena
        // rect that fits inside the available space, preserving the
        // 2.0 x 3.0 aspect ratio (width x height in physics units).
        const arenaAspect =
            FlickArenaBoard.fullWidth / FlickArenaBoard.fullHeight;
        final availAspect = constraints.maxWidth / constraints.maxHeight;
        double arenaWidth;
        double arenaHeight;
        if (availAspect > arenaAspect) {
          // available space is wider than arena — fit to height
          arenaHeight = constraints.maxHeight;
          arenaWidth = arenaHeight * arenaAspect;
        } else {
          // available space is taller than arena — fit to width
          arenaWidth = constraints.maxWidth;
          arenaHeight = arenaWidth / arenaAspect;
        }
        final arenaRect = Rect.fromCenter(
          center: Offset(constraints.maxWidth / 2,
              constraints.maxHeight / 2),
          width: arenaWidth,
          height: arenaHeight,
        );

        // Convert local pixels inside the arena rect to physics coords
        // (x ∈ [-1,1], y ∈ [-1.5,1.5]).
        Offset localToPhysics(Offset local) {
          return Offset(
            ((local.dx - arenaRect.center.dx) /
                (arenaRect.width / 2)) *
                FlickArenaBoard.halfWidth,
            ((local.dy - arenaRect.center.dy) /
                (arenaRect.height / 2)) *
                FlickArenaBoard.halfHeight,
          );
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) {
            final localPos = details.localPosition;
            // Only the current player can start an aim.
            if (game.currentTurnPlayerId != myUserId) return;
            if (state.isSimulating) return;

            final physPos = localToPhysics(localPos);
            final mySlot = game.slotForUserId(myUserId);
            if (mySlot == null) return;

            // Find the closest disc owned by my slot within reach.
            FlickDisc? closest;
            double closestDist = double.infinity;
            for (final d in game.boardState.discs) {
              if (d.ownerSlot != mySlot || d.isPotted) continue;
              final dist = (Offset(d.x, d.y) - physPos).distance;
              // Allow tap within 1.5x disc radius for forgiveness.
              if (dist < FlickArenaPhysics.discRadius * 2.5 &&
                  dist < closestDist) {
                closestDist = dist;
                closest = d;
              }
            }
            if (closest != null) {
              onAimStart(closest.id, Offset(closest.x, closest.y));
            }
          },
          onPanUpdate: (details) {
            if (aimDiscId == null) return;
            final physPos = localToPhysics(details.localPosition);
            onAimUpdate(physPos);
          },
          onPanEnd: (details) {
            if (aimDiscId == null) return;
            if (dragStartArena == null || dragCurrentArena == null) {
              onAimCancel();
              return;
            }
            final delta = dragStartArena! - dragCurrentArena!;
            final dragDist = delta.distance;
            // If the drag was tiny, treat it as a tap-cancel.
            if (dragDist < 0.05) {
              onAimCancel();
              return;
            }
            final angle = math.atan2(delta.dy, delta.dx);
            final power = (dragDist / 0.6).clamp(0.0, 1.0);
            onAimRelease(angle, power);
          },
          onPanCancel: onAimCancel,
          child: SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: CustomPaint(
              painter: _ArenaPainter(
                game: game,
                state: state,
                myUserId: myUserId,
                arenaRect: arenaRect,
                pulseValue: pulse.value,
                aimDiscId: aimDiscId,
                dragStartArena: dragStartArena,
                dragCurrentArena: dragCurrentArena,
                aimAngle: aimAngle,
                aimPower: aimPower,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ArenaPainter extends CustomPainter {
  _ArenaPainter({
    required this.game,
    required this.state,
    required this.myUserId,
    required this.arenaRect,
    required this.pulseValue,
    required this.aimDiscId,
    required this.dragStartArena,
    required this.dragCurrentArena,
    required this.aimAngle,
    required this.aimPower,
  });

  final FlickArenaGame game;
  final FlickArenaState_ state;
  final String? myUserId;
  final Rect arenaRect;
  final double pulseValue;
  final String? aimDiscId;
  final Offset? dragStartArena;
  final Offset? dragCurrentArena;
  final double? aimAngle;
  final double? aimPower;

  Offset _physicsToLocal(double px, double py) {
    return Offset(
      arenaRect.center.dx +
          (px / FlickArenaBoard.halfWidth) * (arenaRect.width / 2),
      arenaRect.center.dy +
          (py / FlickArenaBoard.halfHeight) * (arenaRect.height / 2),
    );
  }

  double _scaleRadius(double physicsRadius) {
    // We want circles to look circular, so use the average scale.
    return (physicsRadius / FlickArenaBoard.halfWidth) *
        (arenaRect.width / 2);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // ── Arena background (dark with subtle vignette) ──────────────
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [
          Color(0xFF0F1424),
          Color(0xFF16182B),
        ],
      ).createShader(arenaRect);
    canvas.drawRect(arenaRect, bgPaint);

    // Subtle center line (dashed)
    final centerLinePaint = Paint()
      ..color = const Color(0xFF3B3F5C)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final centerY = arenaRect.center.dy;
    _drawDashedLine(
      canvas,
      Offset(arenaRect.left, centerY),
      Offset(arenaRect.right, centerY),
      centerLinePaint,
      dashWidth: 5,
      gapWidth: 8,
    );

    // Center circle
    final centerCircleRadius = _scaleRadius(0.35);
    final centerCirclePaint = Paint()
      ..color = const Color(0xFF2A2F4A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawCircle(arenaRect.center, centerCircleRadius,
        centerCirclePaint);

    // ── Goal mouths (top + bottom) ────────────────────────────────
    final goalHalfWidthLocal =
        (FlickArenaBoard.goalHalfWidth / FlickArenaBoard.halfWidth) *
            (arenaRect.width / 2);
    final goalTopRect = Rect.fromCenter(
      center: Offset(arenaRect.center.dx, arenaRect.top),
      width: goalHalfWidthLocal * 2,
      height: 12,
    );
    final goalBottomRect = Rect.fromCenter(
      center: Offset(arenaRect.center.dx, arenaRect.bottom),
      width: goalHalfWidthLocal * 2,
      height: 12,
    );
    // Top goal — team 2 defends (cyan), team 1 scores into
    final goalTopPaint = Paint()
      ..color = const Color(0xFF22D3EE).withValues(alpha: 0.45);
    canvas.drawRRect(
      RRect.fromRectAndRadius(goalTopRect, const Radius.circular(6)),
      goalTopPaint,
    );
    // Bottom goal — team 1 defends (orange), team 2 scores into
    final goalBottomPaint = Paint()
      ..color = KinrelColors.orange.withValues(alpha: 0.45);
    canvas.drawRRect(
      RRect.fromRectAndRadius(goalBottomRect, const Radius.circular(6)),
      goalBottomPaint,
    );

    // ── Arena border ──────────────────────────────────────────────
    final borderPaint = Paint()
      ..color = const Color(0xFF3B3F5C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawRect(arenaRect, borderPaint);

    // ── Draw discs (use live positions during simulation, otherwise
    //    the persisted board state) ───────────────────────────────
    final isMyTurn = game.currentTurnPlayerId == myUserId;
    final mySlot = game.slotForUserId(myUserId);

    for (final disc in game.boardState.discs) {
      if (disc.isPotted) continue;

      // Use live position during simulation if available.
      final livePos = state.liveDiscPositions[disc.id];
      final pos = livePos != null
          ? Offset(livePos.$1, livePos.$2)
          : Offset(disc.x, disc.y);
      final localPos = _physicsToLocal(pos.dx, pos.dy);
      final radius = _scaleRadius(FlickArenaPhysics.discRadius);

      final team = game.teamForSlot(disc.ownerSlot);
      final isOwner = isMyTurn && mySlot == disc.ownerSlot;
      final discColor = team == 1
          ? KinrelColors.orange
          : const Color(0xFF22D3EE);

      // Soft shadow under the disc.
      final shadowPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.35);
      canvas.drawCircle(
          Offset(localPos.dx, localPos.dy + 3), radius, shadowPaint);

      // Disc body — gradient fill.
      final discPaint = Paint()
        ..shader = RadialGradient(
          center: Alignment(-0.4, -0.4),
          colors: [
            discColor.withValues(alpha: 0.95),
            discColor.withValues(alpha: 0.65),
          ],
        ).createShader(
            Rect.fromCircle(center: localPos, radius: radius));
      canvas.drawCircle(localPos, radius, discPaint);

      // Disc rim.
      final rimPaint = Paint()
        ..color = discColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(localPos, radius, rimPaint);

      // Highlight if it's the current player's disc and not currently
      // being aimed.
      if (isOwner && aimDiscId != disc.id) {
        final glowPaint = Paint()
          ..color = discColor
            .withValues(alpha: 0.15 + 0.15 * pulseValue)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 + 1.5 * pulseValue;
        canvas.drawCircle(localPos, radius + 4 + 2 * pulseValue,
            glowPaint);
      }

      // Slot number etched in the center.
      final slotTextPainter = TextPainter(
        text: TextSpan(
          text: '${disc.ownerSlot}',
          style: TextStyle(
            color: Colors.white,
            fontSize: radius * 0.85,
            fontWeight: FontWeight.w800,
            fontFamily: 'RobotoMono',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      slotTextPainter.paint(
        canvas,
        Offset(
          localPos.dx - slotTextPainter.width / 2,
          localPos.dy - slotTextPainter.height / 2,
        ),
      );
    }

    // ── Draw the ball ─────────────────────────────────────────────
    final liveBallPos = state.liveBallPosition;
    final ballPos = liveBallPos != null
        ? Offset(liveBallPos.$1, liveBallPos.$2)
        : Offset(game.boardState.ball.x, game.boardState.ball.y);
    final ballLocal = _physicsToLocal(ballPos.dx, ballPos.dy);
    final ballRadius = _scaleRadius(FlickArenaPhysics.ballRadius);

    // Ball shadow.
    final ballShadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.4);
    canvas.drawCircle(
        Offset(ballLocal.dx, ballLocal.dy + 2), ballRadius,
        ballShadowPaint);

    // Ball body — bright white with subtle gradient.
    final ballPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.4, -0.4),
        colors: const [
          Color(0xFFFFFFFF),
          Color(0xFFCBD5E1),
        ],
      ).createShader(
          Rect.fromCircle(center: ballLocal, radius: ballRadius));
    canvas.drawCircle(ballLocal, ballRadius, ballPaint);

    // ── Draw aim line + power meter ───────────────────────────────
    if (aimDiscId != null &&
        dragStartArena != null &&
        dragCurrentArena != null &&
        aimAngle != null &&
        aimPower != null) {
      // Find the disc being aimed.
      final aimedDisc = game.boardState.discs
          .where((d) => d.id == aimDiscId)
          .firstOrNull;
      if (aimedDisc != null) {
        final liveAimPos = state.liveDiscPositions[aimedDisc.id];
        final discPos = liveAimPos != null
            ? Offset(liveAimPos.$1, liveAimPos.$2)
            : Offset(aimedDisc.x, aimedDisc.y);
        final discLocal = _physicsToLocal(discPos.dx, discPos.dy);

        // Aim line — from the disc in the direction of the flick.
        // Length scales with power.
        final lineLength = 80 + (aimPower! * 180);
        final aimEnd = Offset(
          discLocal.dx + math.cos(aimAngle!) * lineLength,
          discLocal.dy + math.sin(aimAngle!) * lineLength,
        );

        // Dashed aim line.
        final aimLinePaint = Paint()
          ..color = KinrelColors.amber.withValues(alpha: 0.85)
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke;
        _drawDashedLine(
          canvas,
          discLocal,
          aimEnd,
          aimLinePaint,
          dashWidth: 6,
          gapWidth: 6,
        );

        // Arrowhead.
        final arrowPaint = Paint()
          ..color = KinrelColors.amber
          ..style = PaintingStyle.fill;
        final arrowAngle = aimAngle!;
        const arrowSize = 10.0;
        final arrowPath = Path()
          ..moveTo(aimEnd.dx, aimEnd.dy)
          ..lineTo(
            aimEnd.dx -
                arrowSize * math.cos(arrowAngle - 0.4),
            aimEnd.dy -
                arrowSize * math.sin(arrowAngle - 0.4),
          )
          ..lineTo(
            aimEnd.dx -
                arrowSize * math.cos(arrowAngle + 0.4),
            aimEnd.dy -
                arrowSize * math.sin(arrowAngle + 0.4),
          )
          ..close();
        canvas.drawPath(arrowPath, arrowPaint);

        // Predicted path — a faint line extending further in the aim
        // direction to suggest the shot trajectory.
        final predictedEnd = Offset(
          discLocal.dx +
              math.cos(aimAngle!) * (lineLength + 80),
          discLocal.dy +
              math.sin(aimAngle!) * (lineLength + 80),
        );
        final predictedPaint = Paint()
          ..color = KinrelColors.amber.withValues(alpha: 0.18)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke;
        _drawDashedLine(
          canvas,
          aimEnd,
          predictedEnd,
          predictedPaint,
          dashWidth: 3,
          gapWidth: 6,
        );

        // Power meter — small arc above the disc.
        final powerColor = aimPower! < 0.4
            ? const Color(0xFF10B981)
            : aimPower! < 0.75
                ? KinrelColors.amber
                : KinrelColors.error;
        final powerBarWidth = 60.0;
        final powerBarRect = Rect.fromCenter(
          center: Offset(discLocal.dx, discLocal.dy - 35),
          width: powerBarWidth,
          height: 6,
        );
        // Track background.
        canvas.drawRRect(
          RRect.fromRectAndRadius(powerBarRect,
              const Radius.circular(3)),
          Paint()..color = Colors.black.withValues(alpha: 0.4),
        );
        // Filled portion.
        final filledRect = Rect.fromLTWH(
          powerBarRect.left,
          powerBarRect.top,
          powerBarRect.width * aimPower!,
          powerBarRect.height,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(filledRect,
              const Radius.circular(3)),
          Paint()..color = powerColor,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ArenaPainter oldDelegate) {
    // Repaint on any change — game state, live positions, pulse, drag.
    return true;
  }
}

// ═════════════════════════════════════════════════════════════════════
// Aim status bar (bottom)
// ═════════════════════════════════════════════════════════════════════

class _AimStatusBar extends StatelessWidget {
  const _AimStatusBar({
    required this.isMyTurn,
    required this.isSimulating,
    required this.aimPower,
    required this.lastResult,
    required this.matchType,
  });
  final bool isMyTurn;
  final bool isSimulating;
  final double? aimPower;
  final FlickTurnResult? lastResult;
  final FlickArenaMatchType matchType;

  @override
  Widget build(BuildContext context) {
    String message;
    Color color;
    if (isSimulating) {
      message = 'Physics simulating...';
      color = KinrelColors.textDim;
    } else if (lastResult != null && lastResult!.goalScored) {
      final team = lastResult!.goalForTeam;
      message = team == 1
          ? '⚽ GOAL — Team 1 scores!'
          : '⚽ GOAL — Team 2 scores!';
      color = KinrelColors.amber;
    } else if (!isMyTurn) {
      message = 'Waiting for opponent to flick...';
      color = KinrelColors.textDim;
    } else if (aimPower != null) {
      final pct = (aimPower! * 100).round();
      message = 'Power $pct% — release to flick!';
      color = KinrelColors.amber;
    } else {
      message =
          'Drag back from one of your discs to aim and shoot.';
      color = KinrelColors.textSilver;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        border: Border(
          top: BorderSide(color: KinrelColors.border),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: color, blurRadius: 5)],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Results view
// ═════════════════════════════════════════════════════════════════════

class _ResultsView extends StatelessWidget {
  const _ResultsView({
    required this.game,
    required this.familyId,
    required this.isHost,
    required this.onRematch,
    required this.onExit,
  });
  final FlickArenaGame game;
  final String familyId;
  final bool isHost;
  final Future<String?> Function() onRematch;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final winnerTeam = game.winningTeam;
    final winnerLabel = winnerTeam == 1 ? 'Team 1' : 'Team 2';
    final isTeam1 = winnerTeam == 1;
    final winnerColor =
        isTeam1 ? KinrelColors.orange : const Color(0xFF22D3EE);

    // Best shot — scan turn history for the longest shotDistance.
    // (Turns are loaded async by the provider; we read them off the
    // match_ecosystem_summary downstream if needed. For v1 we show a
    // simple stats panel.)

    return SingleChildScrollView(
      padding: const EdgeInsets.all(KinrelSpacing.lg),
      child: Column(
        children: [
          if (winnerTeam != null) const GameConfetti(),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  winnerColor.withValues(alpha: 0.18),
                  const Color(0xFF1C1410),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: winnerColor.withValues(alpha: 0.45)),
            ),
            child: Column(
              children: [
                const KinrelIcon(KinrelIconData.trophy,
                    size: 40, color: KinrelColors.brightGold),
                const SizedBox(height: 8),
                Text(
                  '$winnerLabel wins!',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: KinrelColors.brightGold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Final score: ${game.teamOneScore} — ${game.teamTwoScore}',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    color: KinrelColors.textSilver,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // ── Match stats summary ─────────────────────────────────
          GamingSectionHeader(
              title: 'Match Summary', icon: Icons.insights_outlined),
          _StatRow(
              label: 'Final score',
              value: '${game.teamOneScore} — ${game.teamTwoScore}'),
          _StatRow(
              label: 'Match type',
              value: game.matchType.label),
          _StatRow(
              label: 'Goals to win',
              value: '${game.matchType.goalsToWin}'),
          if (game.startedAt != null && game.completedAt != null)
            _StatRow(
              label: 'Duration',
              value: _formatDuration(
                game.completedAt!.difference(game.startedAt!),
              ),
            ),
          const SizedBox(height: 18),

          // ── Ecosystem summary (Family Cup, achievements, etc.) ─
          MatchEcosystemSummary(
            gameTable: 'flick_arena_games',
            gameId: game.id,
            familyId: familyId,
          ),
          const SizedBox(height: 18),

          // ── Action buttons ─────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: DKButton(
                  label: 'Exit',
                  variant: DKButtonVariant.secondary,
                  fullWidth: true,
                  onPressed: onExit,
                ),
              ),
              // Host-gated shared rematch — provider rematch() restores the
              // slot players and writes invites itself (insertInvites:
              // false). Participants come from the game row's four slots.
              if (isHost) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: RematchButton(
                    familyId: familyId,
                    gameType: GameType.flickArena,
                    previousGameId: game.id,
                    participantUserIds: [
                      game.playerOneId,
                      game.playerTwoId,
                      game.playerThreeId,
                      game.playerFourId,
                    ].where((id) => id.isNotEmpty).toList(),
                    maxPlayers: game.maxPlayers,
                    insertInvites: false,
                    onCreateNewGame: onRematch,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m}m ${s}s';
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  color: KinrelColors.textDim,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Draw a dashed line between [start] and [end] using alternating
/// dash/gap segments. Pure-Flutter replacement for the Skia
/// `DashPathEffect` we'd use in native code.
void _drawDashedLine(
  Canvas canvas,
  Offset start,
  Offset end,
  Paint paint, {
  double dashWidth = 6,
  double gapWidth = 6,
}) {
  final total = (start - end).distance;
  if (total <= 0) return;
  final dx = (end.dx - start.dx) / total;
  final dy = (end.dy - start.dy) / total;
  var drawn = 0.0;
  bool drawing = true;
  while (drawn < total) {
    final step = drawing ? dashWidth : gapWidth;
    final next = (drawn + step).clamp(0.0, total);
    if (drawing) {
      canvas.drawLine(
        Offset(start.dx + dx * drawn, start.dy + dy * drawn),
        Offset(start.dx + dx * next, start.dy + dy * next),
        paint,
      );
    }
    drawn = next;
    drawing = !drawing;
  }
}

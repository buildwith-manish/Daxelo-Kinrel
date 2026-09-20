// lib/features/prediction_battle/prediction_card.dart
//
// ┌─────────────────────────────────────────────────────────────────────┐
// │  PREDICTION BATTLE — Premium Feature Card (redesigned)              │
// └─────────────────────────────────────────────────────────────────────┘
//
// Design goals (per spec):
//   • Replace emoji (🔮) with a custom branded visual asset — the
//     "Prediction Target" mark: concentric rings painted with a radial
//     gradient + an animated outer pulse halo. This becomes the unique
//     Prediction Battle identity, distinct from any other card.
//   • Strong visual hierarchy — bold hero typography, clear status
//     badges, scannable stat row.
//   • Modern gamification — live countdown with progress bar,
//     participation count, win-streak indicator, reward/points cue.
//   • Premium feel — layered gradient backgrounds, glow shadows,
//     shimmer sweep on legendary rounds, gold accents.
//   • Curiosity + anticipation triggers — "LIVE NOW" / "REVEALS SOON"
//     pills, large countdown digits, progress bar that drains.
//   • Reward & achievement cues — points/multiplier chip, "submitted ✓"
//     confirmation, streak flame.
//   • Reduced cognitive load — single primary CTA, clear secondary
//     action, all info above the fold.
//
// The card still uses the existing predictionProvider for state and
// routes to /family/<id>/prediction-battle on tap.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../games/shared/icons/kinrel_icons.dart';
import 'prediction_models.dart';
import 'prediction_provider.dart';

class PredictionBattleCard extends ConsumerStatefulWidget {
  const PredictionBattleCard({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<PredictionBattleCard> createState() =>
      _PredictionBattleCardState();
}

class _PredictionBattleCardState extends ConsumerState<PredictionBattleCard>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _shimmerController;
  late final Animation<double> _pulseAnimation;
  late final Animation<double> _shimmerAnimation;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    Future.microtask(
        () => ref.read(predictionProvider(widget.familyId).notifier).load());

    // Outer halo pulse — slow breathe to feel "alive".
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.92, end: 1.08)
        .animate(CurvedAnimation(
            parent: _pulseController, curve: Curves.easeInOut));

    // Legendary shimmer sweep — only animates when isLegendary.
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
    _shimmerAnimation = Tween<double>(begin: -1.0, end: 2.0)
        .animate(CurvedAnimation(
            parent: _shimmerController, curve: Curves.easeInOutSine));

    // 1s tick so the countdown text re-renders smoothly.
    _countdownTimer =
        Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _shimmerController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(predictionProvider(widget.familyId));
    final round = state.activeRound;
    final question = state.activeQuestion;

    if (state.isLoading) return const _SkeletonCard();

    if (round == null || question == null) {
      return _EmptyCard(familyId: widget.familyId);
    }

    final isLegendary = round.isLegendary;
    final accent = isLegendary ? KinrelColors.brightGold : KinrelColors.orange;
    final accent2 = isLegendary ? KinrelColors.amber : KinrelColors.amber;

    return GestureDetector(
      onTap: () =>
          context.push('/family/${widget.familyId}/prediction-battle'),
      behavior: HitTestBehavior.opaque,
      child: _PremiumCard(
        isLegendary: isLegendary,
        accent: accent,
        accent2: accent2,
        shimmerAnimation: _shimmerAnimation,
        pulseAnimation: _pulseAnimation,
        round: round,
        question: question,
        state: state,
        familyId: widget.familyId,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Premium card shell — gradient + glow + optional shimmer sweep.
// ═══════════════════════════════════════════════════════════════════════

class _PremiumCard extends StatelessWidget {
  const _PremiumCard({
    required this.isLegendary,
    required this.accent,
    required this.accent2,
    required this.shimmerAnimation,
    required this.pulseAnimation,
    required this.round,
    required this.question,
    required this.state,
    required this.familyId,
  });

  final bool isLegendary;
  final Color accent;
  final Color accent2;
  final Animation<double> shimmerAnimation;
  final Animation<double> pulseAnimation;
  final PredictionRound round;
  final PredictionQuestion question;
  final PredictionState state;
  final String familyId;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          // Deep elevation shadow
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          // Brand-tinted outer glow
          BoxShadow(
            color: accent.withValues(alpha: 0.28),
            blurRadius: 28,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Base gradient + clipped shimmer sweep (legendary only)
          ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isLegendary
                      ? [
                          const Color(0xFF2A1F08),
                          const Color(0xFF1B1505),
                          const Color(0xFF13141E),
                        ]
                      : [
                          const Color(0xFF241208),
                          const Color(0xFF1A0E05),
                          KinrelColors.darkCard,
                        ],
                ),
              ),
              child: Stack(
                children: [
                  if (isLegendary)
                    AnimatedBuilder(
                      animation: shimmerAnimation,
                      builder: (context, _) {
                        return Positioned.fill(
                          child: CustomPaint(
                            painter: _ShimmerSweepPainter(
                              progress: shimmerAnimation.value,
                              color: KinrelColors.brightGold
                                  .withValues(alpha: 0.22),
                            ),
                          ),
                        );
                      },
                    ),
                  Positioned(
                    right: -60,
                    top: -40,
                    child: Opacity(
                      opacity: 0.10,
                      child: SizedBox(
                        width: 180,
                        height: 180,
                        child: CustomPaint(
                          painter: _WatermarkTargetPainter(color: accent),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _HeaderRow(
                          accent: accent,
                          accent2: accent2,
                          pulseAnimation: pulseAnimation,
                          isLegendary: isLegendary,
                          status: round.status,
                        ),
                        const SizedBox(height: 16),
                        _QuestionBlock(
                          question: question,
                          isLegendary: isLegendary,
                        ),
                        const SizedBox(height: 16),
                        _StatRow(
                          round: round,
                          state: state,
                          accent: accent,
                          accent2: accent2,
                        ),
                        const SizedBox(height: 14),
                        _CountdownProgress(
                          round: round,
                          accent: accent,
                        ),
                        const SizedBox(height: 16),
                        _ActionRow(
                          round: round,
                          state: state,
                          familyId: familyId,
                          accent: accent,
                          accent2: accent2,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Top accent border — premium stroke that ties the card to the
          // brand accent. Painted as an overlay so the gradient fill below
          // stays clipped to the rounded corners.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color:
                        accent.withValues(alpha: isLegendary ? 0.55 : 0.40),
                    width: 1.2,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 450.ms)
        .slideY(begin: -0.04, end: 0, duration: 450.ms)
        .shimmer(
          duration: 1200.ms,
          color: isLegendary
              ? KinrelColors.brightGold.withValues(alpha: 0.18)
              : KinrelColors.orange.withValues(alpha: 0.14),
        );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Header row — branded target mark + title block + live status pill.
// ═══════════════════════════════════════════════════════════════════════

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.accent,
    required this.accent2,
    required this.pulseAnimation,
    required this.isLegendary,
    required this.status,
  });

  final Color accent;
  final Color accent2;
  final Animation<double> pulseAnimation;
  final bool isLegendary;
  final PredictionStatus status;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // ── Prediction Target mark (replaces 🔮 emoji) ──
        // Concentric rings painted with a radial gradient, wrapped in
        // a pulsing halo. This is the unique Prediction Battle identity.
        SizedBox(
          width: 52,
          height: 52,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer pulse halo
              AnimatedBuilder(
                animation: pulseAnimation,
                builder: (context, _) {
                  return Transform.scale(
                    scale: pulseAnimation.value,
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            accent.withValues(alpha: 0.32),
                            accent.withValues(alpha: 0.0),
                          ],
                          stops: const [0.35, 1.0],
                        ),
                      ),
                    ),
                  );
                },
              ),
              // Target mark
              SizedBox(
                width: 38,
                height: 38,
                child: CustomPaint(
                  painter: _PredictionTargetPainter(
                    color: accent,
                    innerColor: accent2,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // ── Title block ──
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    'PREDICTION BATTLE',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (isLegendary)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFFFFD700),
                            Color(0xFFF59240),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'LEGENDARY',
                        style: TextStyle(
                          fontFamily: KinrelTypography.monoFont,
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: Colors.black,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                _tagline(status),
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: accent.withValues(alpha: 0.95),
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
        // ── Live status pill ──
        _LiveStatusPill(status: status, accent: accent),
      ],
    );
  }

  String _tagline(PredictionStatus s) {
    switch (s) {
      case PredictionStatus.open:
        return 'Live now · Predict to win';
      case PredictionStatus.locked:
        return 'Locked · Awaiting reveal';
      case PredictionStatus.pending:
        return 'Revealing soon · Stay tuned';
      case PredictionStatus.resolved:
        return 'Resolved · See the results';
      case PredictionStatus.archived:
        return 'Archived battle';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Live status pill — colored dot + uppercase label.
// Pulses when OPEN to draw the eye.
// ═══════════════════════════════════════════════════════════════════════

class _LiveStatusPill extends StatefulWidget {
  const _LiveStatusPill({required this.status, required this.accent});
  final PredictionStatus status;
  final Color accent;

  @override
  State<_LiveStatusPill> createState() => _LiveStatusPillState();
}

class _LiveStatusPillState extends State<_LiveStatusPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _dot;

  @override
  void initState() {
    super.initState();
    _dot = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    if (widget.status == PredictionStatus.open) _dot.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _LiveStatusPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.status != oldWidget.status) {
      if (widget.status == PredictionStatus.open) {
        _dot.repeat(reverse: true);
      } else {
        _dot.stop();
      }
    }
  }

  @override
  void dispose() {
    _dot.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(widget.status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.40), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.status == PredictionStatus.open)
            AnimatedBuilder(
              animation: _dot,
              builder: (context, _) {
                return Opacity(
                  opacity: 0.45 + (_dot.value * 0.55),
                  child: _Dot(color: color, size: 6),
                );
              },
            )
          else
            _Dot(color: color, size: 6),
          const SizedBox(width: 5),
          Text(
            widget.status.label,
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Color _colorFor(PredictionStatus s) {
    switch (s) {
      case PredictionStatus.open:
        return KinrelColors.success;
      case PredictionStatus.locked:
        return KinrelColors.textSilver;
      case PredictionStatus.pending:
        return KinrelColors.amber;
      case PredictionStatus.resolved:
        return KinrelColors.orange;
      case PredictionStatus.archived:
        return KinrelColors.textSilver;
    }
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.size});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.6),
            blurRadius: 4,
            spreadRadius: 0.5,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Question block — large bold hero typography.
// ═══════════════════════════════════════════════════════════════════════

class _QuestionBlock extends StatelessWidget {
  const _QuestionBlock({required this.question, required this.isLegendary});
  final PredictionQuestion question;
  final bool isLegendary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Type chip — Closest Wins / Outcome Prediction
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
          decoration: BoxDecoration(
            color: KinrelColors.darkElevated.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: (isLegendary ? KinrelColors.brightGold : KinrelColors.orange)
                  .withValues(alpha: 0.35),
              width: 0.6,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              KinrelIcon(
                KinrelIconData.target,
                size: 10,
                color: isLegendary
                    ? KinrelColors.brightGold
                    : KinrelColors.orange,
              ),
              const SizedBox(width: 4),
              Text(
                question.type.label.toUpperCase(),
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: isLegendary
                      ? KinrelColors.brightGold
                      : KinrelColors.orange,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          question.question,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textWhite,
            height: 1.32,
            letterSpacing: -0.1,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Stat row — three KPIs: countdown, participants, streak/reward.
// ═══════════════════════════════════════════════════════════════════════

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.round,
    required this.state,
    required this.accent,
    required this.accent2,
  });
  final PredictionRound round;
  final PredictionState state;
  final Color accent;
  final Color accent2;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatChip(
            icon: _statusIcon(round.status),
            label: _statusLabel(round.status),
            value: _statusValue(round),
            color: _statusColor(round.status),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatChip(
            icon: KinrelIconData.users,
            label: 'PLAYERS',
            value: '${state.participationCount} joined',
            color: KinrelColors.amber,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatChip(
            icon: KinrelIconData.flame,
            label: state.myStats != null && state.myStats!.currentStreak > 0
                ? 'YOUR STREAK'
                : 'REWARD',
            value: state.myStats != null && state.myStats!.currentStreak > 0
                ? '${state.myStats!.currentStreak} in a row'
                : 'up to 15 pts',
            color: KinrelColors.orange,
          ),
        ),
      ],
    );
  }

  IconData _statusIcon(PredictionStatus s) {
    switch (s) {
      case PredictionStatus.open:
        return Icons.timer_outlined;
      case PredictionStatus.locked:
        return Icons.lock_outline;
      case PredictionStatus.pending:
        return Icons.hourglass_top_outlined;
      case PredictionStatus.resolved:
        return Icons.emoji_events_outlined;
      case PredictionStatus.archived:
        return Icons.archive_outlined;
    }
  }

  String _statusLabel(PredictionStatus s) {
    switch (s) {
      case PredictionStatus.open:
        return 'CLOSES IN';
      case PredictionStatus.locked:
        return 'STATUS';
      case PredictionStatus.pending:
        return 'REVEALS IN';
      case PredictionStatus.resolved:
        return 'STATUS';
      case PredictionStatus.archived:
        return 'STATUS';
    }
  }

  String _statusValue(PredictionRound r) {
    switch (r.status) {
      case PredictionStatus.open:
        return _countdown(r.lockAt);
      case PredictionStatus.locked:
        return 'Locked';
      case PredictionStatus.pending:
        return _countdown(r.revealAt);
      case PredictionStatus.resolved:
        return 'Resolved';
      case PredictionStatus.archived:
        return 'Archived';
    }
  }

  Color _statusColor(PredictionStatus s) {
    switch (s) {
      case PredictionStatus.open:
        return KinrelColors.orange;
      case PredictionStatus.locked:
        return KinrelColors.textSilver;
      case PredictionStatus.pending:
        return KinrelColors.amber;
      case PredictionStatus.resolved:
        return KinrelColors.success;
      case PredictionStatus.archived:
        return KinrelColors.textSilver;
    }
  }

  String _countdown(DateTime target) {
    final diff = target.difference(DateTime.now());
    if (diff.isNegative) return 'soon';
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    if (h > 0) return '${h}h ${m}m';
    final s = diff.inSeconds % 60;
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: BoxDecoration(
        color: KinrelColors.darkElevated.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: color.withValues(alpha: 0.18), width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 11, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: color.withValues(alpha: 0.85),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: KinrelColors.textWhite,
              height: 1.1,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Countdown progress bar — visualizes time remaining as a draining bar.
// Only shown for OPEN / PENDING statuses (where a target future time exists).
// ═══════════════════════════════════════════════════════════════════════

class _CountdownProgress extends StatelessWidget {
  const _CountdownProgress({required this.round, required this.accent});
  final PredictionRound round;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final target = round.status == PredictionStatus.open
        ? round.lockAt
        : round.status == PredictionStatus.pending
            ? round.revealAt
            : null;
    if (target == null) return const SizedBox.shrink();

    final createdAt = round.createdAt ?? target.subtract(const Duration(hours: 24));
    final total = target.difference(createdAt).inSeconds;
    final remaining = target.difference(DateTime.now()).inSeconds;
    final progress = total <= 0
        ? 0.0
        : (remaining / total).clamp(0.0, 1.0);

    // Color shifts to amber/red as time runs out.
    final color = progress > 0.5
        ? accent
        : progress > 0.2
            ? KinrelColors.amber
            : KinrelColors.coral;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            children: [
              // Track
              Container(
                height: 5,
                width: double.infinity,
                color: KinrelColors.darkElevated.withValues(alpha: 0.7),
              ),
              // Fill
              FractionallySizedBox(
                widthFactor: progress,
                child: Container(
                  height: 5,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [color, color.withValues(alpha: 0.6)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.6),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 5),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              progress > 0.5
                  ? 'Plenty of time'
                  : progress > 0.2
                      ? 'Getting closer'
                      : 'Almost up — predict now',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                color: color.withValues(alpha: 0.95),
                letterSpacing: 0.2,
              ),
            ),
            Text(
              '${(progress * 100).round()}% left',
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Action row — primary CTA + secondary "view details".
// ═══════════════════════════════════════════════════════════════════════

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.round,
    required this.state,
    required this.familyId,
    required this.accent,
    required this.accent2,
  });
  final PredictionRound round;
  final PredictionState state;
  final String familyId;
  final Color accent;
  final Color accent2;

  @override
  Widget build(BuildContext context) {
    final canSubmit =
        round.status == PredictionStatus.open && !state.hasSubmitted;

    return Row(
      children: [
        Expanded(
          child: _PrimaryCta(
            label: canSubmit
                ? 'Submit Prediction'
                : state.hasSubmitted
                    ? 'Prediction Submitted'
                    : 'View Battle',
            icon: canSubmit
                ? Icons.bolt_rounded
                : state.hasSubmitted
                    ? Icons.check_circle_rounded
                    : Icons.arrow_forward_rounded,
            accent: accent,
            accent2: accent2,
            enabled: canSubmit || !state.hasSubmitted,
            emphasized: canSubmit,
            onTap: () =>
                context.push('/family/$familyId/prediction-battle'),
          ),
        ),
        if (state.hasSubmitted || round.status != PredictionStatus.open) ...[
          const SizedBox(width: 8),
          _SecondaryCta(
            label: 'Details',
            accent: accent,
            onTap: () =>
                context.push('/family/$familyId/prediction-battle'),
          ),
        ],
      ],
    );
  }
}

class _PrimaryCta extends StatelessWidget {
  const _PrimaryCta({
    required this.label,
    required this.icon,
    required this.accent,
    required this.accent2,
    required this.enabled,
    required this.emphasized,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final Color accent;
  final Color accent2;
  final bool enabled;
  final bool emphasized;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final submittedSuccess = label == 'Prediction Submitted';
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          gradient: submittedSuccess
              ? LinearGradient(
                  colors: [
                    KinrelColors.success.withValues(alpha: 0.18),
                    KinrelColors.success.withValues(alpha: 0.10),
                  ],
                )
              : LinearGradient(
                  colors: emphasized
                      ? [accent, accent2]
                      : [accent.withValues(alpha: 0.85), accent2.withValues(alpha: 0.7)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: submittedSuccess
                ? KinrelColors.success.withValues(alpha: 0.45)
                : accent.withValues(alpha: 0.6),
            width: 0.8,
          ),
          boxShadow: emphasized
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.45),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 15,
              color: submittedSuccess
                  ? KinrelColors.success
                  : (emphasized ? Colors.white : KinrelColors.textWhite),
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
                color: submittedSuccess
                    ? KinrelColors.success
                    : (emphasized ? Colors.white : KinrelColors.textWhite),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecondaryCta extends StatelessWidget {
  const _SecondaryCta({required this.label, required this.accent, required this.onTap});
  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: KinrelColors.darkElevated.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: accent.withValues(alpha: 0.30),
            width: 0.8,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: accent,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Custom painters — the Prediction Battle brand mark.
// ═══════════════════════════════════════════════════════════════════════

/// Concentric-ring target — the unique Prediction Battle identity.
/// Paints an outer ring, a middle ring, and a center bullseye dot
/// with a subtle radial gradient so it feels dimensional, not flat.
class _PredictionTargetPainter extends CustomPainter {
  _PredictionTargetPainter({required this.color, required this.innerColor});
  final Color color;
  final Color innerColor;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 38.0;
    final center = Offset(size.width / 2, size.height / 2);

    // Outer ring
    final outerPaint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * s
      ..isAntiAlias = true;
    canvas.drawCircle(center, 16 * s, outerPaint);

    // Middle ring (thicker)
    final midPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4 * s
      ..isAntiAlias = true;
    canvas.drawCircle(center, 10.5 * s, midPaint);

    // Inner bullseye — radial gradient fill
    final bullPaint = Paint()
      ..shader = RadialGradient(
        colors: [innerColor, color],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: 5 * s));
    canvas.drawCircle(center, 4.6 * s, bullPaint);

    // Center highlight dot
    final dotPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.75)
      ..isAntiAlias = true;
    canvas.drawCircle(
        Offset(center.dx - 0.8 * s, center.dy - 0.8 * s), 1.2 * s, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _PredictionTargetPainter oldDelegate) =>
      color != oldDelegate.color || innerColor != oldDelegate.innerColor;
}

/// Large watermark target — painted behind the card for depth.
class _WatermarkTargetPainter extends CustomPainter {
  _WatermarkTargetPainter({required this.color});
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..isAntiAlias = true;
    canvas.drawCircle(center, size.width * 0.42, paint);
    canvas.drawCircle(center, size.width * 0.28, paint);
    canvas.drawCircle(center, size.width * 0.14, paint);
  }

  @override
  bool shouldRepaint(covariant _WatermarkTargetPainter oldDelegate) =>
      color != oldDelegate.color;
}

/// Diagonal shimmer sweep — only used for Legendary rounds.
class _ShimmerSweepPainter extends CustomPainter {
  _ShimmerSweepPainter({required this.progress, required this.color});
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final sweepWidth = w * 0.5;
    final x = -sweepWidth + (progress * (w + sweepWidth));

    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          color.withValues(alpha: 0.0),
          color.withValues(alpha: 0.6),
          color.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(x, 0, sweepWidth, h));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), paint);
  }

  @override
  bool shouldRepaint(covariant _ShimmerSweepPainter oldDelegate) =>
      progress != oldDelegate.progress || color != oldDelegate.color;
}

// Unused import guard removed — dart:math is no longer needed since
// the shimmer sweep uses a linear gradient, not a sweep angle.

// ═══════════════════════════════════════════════════════════════════════
// Skeleton + Empty states — redesigned to match the new premium feel.
// ═══════════════════════════════════════════════════════════════════════

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      height: 220,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [KinrelColors.darkCard, KinrelColors.darkElevated],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
            color: KinrelColors.orange.withValues(alpha: 0.18), width: 1),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: KinrelColors.orange.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Loading Prediction Battle…',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 11,
                color: KinrelColors.textSilver,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.familyId});
  final String familyId;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/family/$familyId/prediction-battle'),
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF241208),
              KinrelColors.darkCard,
            ],
          ),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: KinrelColors.orange.withValues(alpha: 0.35),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: KinrelColors.orange.withValues(alpha: 0.18),
              blurRadius: 24,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: CustomPaint(
                painter: _PredictionTargetPainter(
                  color: KinrelColors.orange,
                  innerColor: KinrelColors.amber,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PREDICTION BATTLE',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.3,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Your family\'s next prediction is being prepared. Tap to check the arena.',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      height: 1.4,
                      color: KinrelColors.textSilver,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.arrow_forward_rounded,
              color: KinrelColors.orange,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

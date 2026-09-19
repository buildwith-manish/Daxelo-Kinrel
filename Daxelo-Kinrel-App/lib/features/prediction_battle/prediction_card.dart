// lib/features/prediction_battle/prediction_card.dart
//
// Prediction Battle Card — the Family Space "moment" card.
// Replaces TruthStreakCard in the same location.

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
  ConsumerState<PredictionBattleCard> createState() => _PredictionBattleCardState();
}

class _PredictionBattleCardState extends ConsumerState<PredictionBattleCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(predictionProvider(widget.familyId).notifier).load());
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.15).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() {}); });
  }

  @override
  void dispose() { _pulseController.dispose(); _countdownTimer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(predictionProvider(widget.familyId));
    final round = state.activeRound;
    final question = state.activeQuestion;

    if (state.isLoading) {
      return _SkeletonCard();
    }

    if (round == null || question == null) {
      return _EmptyCard(familyId: widget.familyId);
    }

    return GestureDetector(
      onTap: () => context.push('/family/${widget.familyId}/prediction-battle'),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: round.isLegendary
                ? [const Color(0xFF2B1A0E), const Color(0xFF1D1409)]
                : [KinrelColors.purple.withValues(alpha: 0.15), KinrelColors.darkCard],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: round.isLegendary
                ? KinrelColors.brightGold.withValues(alpha: 0.45)
                : KinrelColors.purple.withValues(alpha: 0.35),
          ),
          boxShadow: [
            BoxShadow(
              color: (round.isLegendary ? KinrelColors.brightGold : KinrelColors.purple).withValues(alpha: 0.15),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                ScaleTransition(
                  scale: _pulseAnimation,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          (round.isLegendary ? KinrelColors.brightGold : KinrelColors.purple).withValues(alpha: 0.5),
                          (round.isLegendary ? KinrelColors.brightGold : KinrelColors.purple).withValues(alpha: 0.1),
                        ],
                      ),
                    ),
                    child: Center(
                      child: KinrelIcon(
                        KinrelIconData.sparkle,
                        size: 20,
                        color: round.isLegendary ? KinrelColors.brightGold : KinrelColors.purple,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        round.isLegendary ? '🔮 Legendary Prediction Battle' : '🔮 Prediction Battle',
                        style: TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: KinrelColors.textWhite,
                        ),
                      ),
                      Text(
                        'Today\'s Prediction · ${question.type.label}',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 11,
                          color: KinrelColors.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusBadge(status: round.status),
              ],
            ),
            const SizedBox(height: 14),
            // Question
            Text(
              question.question,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 12),
            // Countdown + participation
            Row(
              children: [
                if (round.status == PredictionStatus.open) ...[
                  Icon(Icons.timer_outlined, size: 14, color: KinrelColors.orange),
                  const SizedBox(width: 4),
                  Text(
                    'Closes in ${_countdown(round.lockAt)}',
                    style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: KinrelColors.orange,
                    ),
                  ),
                ] else if (round.status == PredictionStatus.locked) ...[
                  Icon(Icons.lock_outline, size: 14, color: KinrelColors.textDim),
                  const SizedBox(width: 4),
                  Text('Predictions Locked', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 11, color: KinrelColors.textDim)),
                ] else if (round.status == PredictionStatus.pending) ...[
                  Icon(Icons.hourglass_top_outlined, size: 14, color: KinrelColors.amber),
                  const SizedBox(width: 4),
                  Text(
                    'Reveals in ${_countdown(round.revealAt)}',
                    style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 11, fontWeight: FontWeight.w700, color: KinrelColors.amber),
                  ),
                ] else ...[
                  Icon(Icons.check_circle_outline, size: 14, color: KinrelColors.success),
                  const SizedBox(width: 4),
                  Text('Resolved', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 11, color: KinrelColors.success)),
                ],
                const Spacer(),
                Text(
                  '${state.participationCount} participated',
                  style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 11, color: KinrelColors.textDim),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Actions
            Row(
              children: [
                if (round.status == PredictionStatus.open && !state.hasSubmitted)
                  Expanded(
                    child: DKPredictionButton(
                      label: 'Submit Prediction',
                      onPressed: () => context.push('/family/${widget.familyId}/prediction-battle'),
                    ),
                  )
                else if (state.hasSubmitted)
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: KinrelColors.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: KinrelColors.success.withValues(alpha: 0.3)),
                      ),
                      child: Center(
                        child: Text('✓ Prediction Submitted', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, fontWeight: FontWeight.w700, color: KinrelColors.success)),
                      ),
                    ),
                  ),
                if (round.status != PredictionStatus.open || state.hasSubmitted) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => context.push('/family/${widget.familyId}/prediction-battle'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: KinrelColors.darkElevated,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('View Details →', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, fontWeight: FontWeight.w700, color: KinrelColors.purple)),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      )
          .animate()
          .fadeIn(duration: 400.ms)
          .slideY(begin: -0.03, end: 0, duration: 400.ms),
    );
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

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final PredictionStatus status;
  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      PredictionStatus.open => KinrelColors.orange,
      PredictionStatus.locked => KinrelColors.textDim,
      PredictionStatus.pending => KinrelColors.amber,
      PredictionStatus.resolved => KinrelColors.success,
      PredictionStatus.archived => KinrelColors.textDim,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
      child: Text(status.label, style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 9, fontWeight: FontWeight.w800, color: color)),
    );
  }
}

class DKPredictionButton extends StatelessWidget {
  const DKPredictionButton({super.key, required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [KinrelColors.purple, KinrelColors.purple.withValues(alpha: 0.7)]),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(child: Text(label, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white))),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      height: 160,
      decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(22)),
      child: const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: KinrelColors.purple))),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.familyId});
  final String familyId;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(22), border: Border.all(color: KinrelColors.purple.withValues(alpha: 0.2))),
      child: Column(children: [
        const Text('🔮', style: TextStyle(fontSize: 32)),
        const SizedBox(height: 8),
        Text('Prediction Battle', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 15, fontWeight: FontWeight.w800, color: KinrelColors.textWhite)),
        const SizedBox(height: 4),
        Text('Loading your family\'s next prediction...', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim)),
      ]),
    );
  }
}

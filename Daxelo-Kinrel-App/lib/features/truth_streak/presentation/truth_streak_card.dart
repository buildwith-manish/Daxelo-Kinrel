// lib/features/truth_streak/presentation/truth_streak_card.dart
//
// DAXELO KINREL — Truth Streak Hero Card
//
// The visual hero of the Family Space home feed. Uses brand orange/amber
// (NOT purple — that's the graph's extendedPurple for uncles/aunts).
// Features an animated pulsing flame icon, large display-weight question
// text, and a prominent streak counter.

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../providers/truth_streak_provider.dart';

class TruthStreakCard extends ConsumerStatefulWidget {
  const TruthStreakCard({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<TruthStreakCard> createState() => _TruthStreakCardState();
}

class _TruthStreakCardState extends ConsumerState<TruthStreakCard>
    with SingleTickerProviderStateMixin {
  final _answerController = TextEditingController();
  late final AnimationController _flameController;
  late final Animation<double> _flamePulse;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(truthStreakProvider(widget.familyId).notifier).load();
    });
    // Flame pulse animation — loops every 2 seconds
    _flameController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _flamePulse = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _flameController, curve: Curves.easeInOut),
    );
    _flameController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _answerController.dispose();
    _flameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(truthStreakProvider(widget.familyId));

    if (state.isLoading) return _buildLoadingCard();
    if (state.error != null || state.assignment == null) {
      return const SizedBox.shrink();
    }

    final assignment = state.assignment!;
    final hasAnswered = state.hasAnswered;
    final streak = state.stats?.currentStreak ?? 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            KinrelColors.orange.withValues(alpha: 0.18),
            KinrelColors.darkCard,
          ],
        ),
        border: Border.all(
          color: KinrelColors.orange.withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: KinrelColors.orange.withValues(alpha: 0.12),
            blurRadius: 24,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: hasAnswered
              ? () {
                  HapticFeedback.lightImpact();
                  context.push('/family/${widget.familyId}/truth-streak');
                }
              : null,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: animated flame + title + streak badge
                Row(
                  children: [
                    // Animated pulsing flame icon
                    AnimatedBuilder(
                      animation: _flamePulse,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _flamePulse.value,
                          child: child,
                        );
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              KinrelColors.orange.withValues(alpha: 0.25),
                              KinrelColors.amber.withValues(alpha: 0.15),
                            ],
                          ),
                        ),
                        child: Icon(
                          Icons.local_fire_department_rounded,
                          color: KinrelColors.orange,
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Truth Streak',
                        style: TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: KinrelColors.textWhite,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    // Streak badge — prominent
                    if (streak > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              KinrelColors.orange,
                              KinrelColors.amber,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: KinrelColors.orange.withValues(alpha: 0.3),
                              blurRadius: 8,
                              spreadRadius: 0,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.local_fire_department,
                              color: Colors.white,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$streak day${streak == 1 ? "" : "s"}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                // Today's question — large, display-weight
                Text(
                  assignment.question?.question ?? 'Loading question...',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.textWhite,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                // State-dependent bottom section
                if (hasAnswered)
                  _buildAnsweredState(state)
                else
                  _buildAnswerInput(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      height: 140,
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: KinrelColors.orange,
          ),
        ),
      ),
    );
  }

  Widget _buildAnswerInput() {
    final state = ref.watch(truthStreakProvider(widget.familyId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _answerController,
          maxLines: 2,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 14,
            color: KinrelColors.textWhite,
          ),
          decoration: InputDecoration(
            hintText: 'Share your answer...',
            hintStyle: TextStyle(
              color: KinrelColors.textDim,
              fontSize: 14,
            ),
            filled: true,
            fillColor: KinrelColors.darkElevated,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.all(14),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: state.isSubmitting
                ? null
                : () async {
                    final text = _answerController.text.trim();
                    if (text.isEmpty) return;
                    HapticFeedback.mediumImpact();
                    final success = await ref
                        .read(truthStreakProvider(widget.familyId).notifier)
                        .submitAnswer(text);
                    if (success && mounted) {
                      _answerController.clear();
                    }
                  },
            style: FilledButton.styleFrom(
              backgroundColor: KinrelColors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: state.isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Submit Answer',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildAnsweredState(state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: KinrelColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: KinrelColors.success.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_rounded,
            color: KinrelColors.success,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              state.answerCount == 0
                  ? 'Your answer is in! Waiting for others...'
                  : '${state.answerCount} ${state.answerCount == 1 ? "person has" : "people have"} answered — tap to reveal',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: KinrelColors.textSilver,
              ),
            ),
          ),
          Icon(
            Icons.arrow_forward_ios,
            size: 14,
            color: KinrelColors.orange,
          ),
        ],
      ),
    );
  }
}

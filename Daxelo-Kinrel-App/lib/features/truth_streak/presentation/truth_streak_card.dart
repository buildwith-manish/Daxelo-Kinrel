// lib/features/truth_streak/presentation/truth_streak_card.dart
//
// Compact card for the Family Space home feed.
// Shows today's question, streak count, and either an answer input
// (if not yet answered) or a "waiting for others" state (if answered).

import 'package:flutter/material.dart';
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

class _TruthStreakCardState extends ConsumerState<TruthStreakCard> {
  final _answerController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Load the truth streak state when the card mounts
    Future.microtask(() {
      ref
          .read(truthStreakProvider(widget.familyId).notifier)
          .load();
    });
  }

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(truthStreakProvider(widget.familyId));

    if (state.isLoading) {
      return _buildLoadingCard();
    }

    if (state.error != null || state.assignment == null) {
      return const SizedBox.shrink();
    }

    final assignment = state.assignment!;
    final hasAnswered = state.hasAnswered;
    final streak = state.stats?.currentStreak ?? 0;

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.base,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF8B5CF6).withValues(alpha: 0.15),
            const Color(0xFF191B2C),
          ],
        ),
        border: Border.all(
          color: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: hasAnswered
              ? () => context.push(
                  '/family/${widget.familyId}/truth-streak')
              : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row: icon + title + streak badge
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF8B5CF6)
                            .withValues(alpha: 0.2),
                      ),
                      child: const Icon(
                        Icons.local_fire_department_rounded,
                        color: Color(0xFF8B5CF6),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Truth Streak',
                        style: TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: KinrelColors.textWhite,
                        ),
                      ),
                    ),
                    if (streak > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8B5CF6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.local_fire_department,
                              color: Colors.white,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$streak',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                // Today's question
                Text(
                  assignment.question?.question ?? 'Loading question...',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: KinrelColors.textWhite,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
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
      height: 120,
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: const Color(0xFF8B5CF6),
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
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.all(12),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: state.isSubmitting
                ? null
                : () async {
                    final text = _answerController.text.trim();
                    if (text.isEmpty) return;
                    final success = await ref
                        .read(truthStreakProvider(widget.familyId)
                            .notifier)
                        .submitAnswer(text);
                    if (success && mounted) {
                      _answerController.clear();
                    }
                  },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF8B5CF6),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: state.isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Submit Answer'),
          ),
        ),
      ],
    );
  }

  Widget _buildAnsweredState(state) {
    return Row(
      children: [
        Icon(
          Icons.check_circle_rounded,
          color: KinrelColors.success,
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${state.answerCount} ${state.answerCount == 1 ? "person has" : "people have"} answered — tap to reveal',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              color: KinrelColors.textDim,
            ),
          ),
        ),
        Icon(
          Icons.arrow_forward_ios,
          size: 14,
          color: KinrelColors.textDim,
        ),
      ],
    );
  }
}

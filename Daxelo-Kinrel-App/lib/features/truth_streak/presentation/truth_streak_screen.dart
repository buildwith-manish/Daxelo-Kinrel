// lib/features/truth_streak/presentation/truth_streak_screen.dart
//
// Full-screen Truth Streak reveal — shows all answers attributed to
// each family member, once the current user has answered.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../shared/widgets/dk_components.dart';
import '../providers/truth_streak_provider.dart';

class TruthStreakScreen extends ConsumerStatefulWidget {
  const TruthStreakScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<TruthStreakScreen> createState() =>
      _TruthStreakScreenState();
}

class _TruthStreakScreenState extends ConsumerState<TruthStreakScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(truthStreakProvider(widget.familyId).notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(truthStreakProvider(widget.familyId));

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Truth Streak',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: KinrelColors.darkCard,
        foregroundColor: KinrelColors.textWhite,
        elevation: 0,
      ),
      body: state.isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: const Color(0xFF8B5CF6),
              ),
            )
          : state.error != null
              ? DKErrorState(
                  message: state.error!,
                  onRetry: () => ref
                      .read(truthStreakProvider(widget.familyId).notifier)
                      .load(),
                )
              : _buildContent(state),
    );
  }

  Widget _buildContent(state) {
    final assignment = state.assignment;
    if (assignment == null) {
      return Center(
        child: Text(
          'No question available today.',
          style: TextStyle(color: KinrelColors.textDim),
        ),
      );
    }

    // If the user hasn't answered yet, show a locked state
    if (!state.hasAnswered) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 56,
                color: KinrelColors.textDim,
              ),
              const SizedBox(height: 16),
              Text(
                'Answer first to reveal',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textWhite,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Share your answer to today\'s question\nto see what your family said.',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  color: KinrelColors.textDim,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // User has answered — show the full reveal
    return ListView(
      padding: const EdgeInsets.all(KinrelSpacing.base),
      children: [
        // Question card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                KinrelColors.darkCard,
              ],
            ),
            border: Border.all(
              color: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.local_fire_department_rounded,
                    color: Color(0xFF8B5CF6),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Today\'s Question',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF8B5CF6),
                    ),
                  ),
                  const Spacer(),
                  if (state.stats != null && state.stats!.currentStreak > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Color(0xFF8B5CF6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.local_fire_department,
                              color: Colors.white, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            '${state.stats!.currentStreak} day streak',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                assignment.question?.question ?? '',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textWhite,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // Answers header
        Row(
          children: [
            Text(
              'Family Answers',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: KinrelColors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${state.answerCount}',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.orange,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Answers list
        ...state.allAnswers.map((answer) => _buildAnswerTile(answer)),
        // Stats footer
        if (state.stats != null) ...[
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: KinrelColors.darkCard,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  'Current Streak',
                  '${state.stats!.currentStreak}',
                  Icons.local_fire_department_outlined,
                  const Color(0xFF8B5CF6),
                ),
                _buildStatItem(
                  'Longest Streak',
                  '${state.stats!.longestStreak}',
                  Icons.emoji_events_outlined,
                  KinrelColors.gold,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAnswerTile(answer) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: KinrelColors.orange.withValues(alpha: 0.15),
            child: Text(
              answer.userName.isNotEmpty
                  ? answer.userName[0].toUpperCase()
                  : '?',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: KinrelColors.orange,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  answer.userName,
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.textWhite,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  answer.answer,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    color: KinrelColors.textSilver,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
      String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textWhite,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 11,
            color: KinrelColors.textDim,
          ),
        ),
      ],
    );
  }
}

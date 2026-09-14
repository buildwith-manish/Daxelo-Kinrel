// lib/features/gaming_ecosystem/presentation/gaming_challenges_screen.dart
//
// Family Challenges — weekly and monthly missions with live progress.
//
// Reward loop design:
//   • Progress is recomputed from real match history after every game,
//     so finishing a match visibly moves these bars (instant feedback).
//   • Completed challenges show a satisfying gold "complete" state with
//     the earned reward points.
//   • Family-wide challenges (e.g. "family plays 25 matches this month")
//     turn individual play into a shared goal.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../shared/widgets/dk_components.dart';
import '../data/gaming_models.dart';
import '../data/gaming_providers.dart';
import 'widgets/gaming_kit.dart';
import 'package:flutter_animate/flutter_animate.dart';

class GamingChallengesScreen extends ConsumerWidget {
  const GamingChallengesScreen({super.key, required this.familyId});
  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final challengesAsync = ref.watch(gamingChallengesProvider(familyId));

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.canPop() ? context.pop() : context.go('/home')),
        title: Text('Challenges',
            style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontWeight: FontWeight.w700)),
        backgroundColor: KinrelColors.darkCard,
        foregroundColor: KinrelColors.textWhite,
        elevation: 0,
      ),
      body: challengesAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: KinrelColors.orange)),
        error: (e, _) => Center(
          child: GamingEmptyCard(
            emoji: '🔌',
            title: 'Couldn\'t load challenges',
            message: 'Pull down to try again.',
          ),
        ),
        data: (challenges) => RefreshIndicator(
          color: KinrelColors.orange,
          backgroundColor: KinrelColors.darkCard,
          onRefresh: () async {
            ref.invalidate(gamingChallengesProvider(familyId));
            await ref.read(gamingChallengesProvider(familyId).future);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            children: [
              _IntroCard(challenges: challenges),
              const SizedBox(height: 16),
              ..._grouped(challenges, 'weekly'),
              const SizedBox(height: 8),
              ..._grouped(challenges, 'monthly'),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _grouped(List<ChallengeInfo> challenges, String cadence) {
    final list = challenges.where((c) => c.cadence == cadence).toList();
    if (list.isEmpty) return const [];
    return [
      GamingSectionHeader(
        title: cadence == 'weekly' ? 'This Week' : 'This Month',
        subtitle: cadence == 'weekly'
            ? 'Refreshes every Monday'
            : 'Refreshes on the 1st of each month',
        icon: cadence == 'weekly' ? Icons.date_range : Icons.calendar_month,
      ),
      for (final c in list) ...[
        _ChallengeCard(challenge: c, familyId: familyId),
        const SizedBox(height: 10),
      ],
    ];
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.challenges});
  final List<ChallengeInfo> challenges;

  @override
  Widget build(BuildContext context) {
    final completed = challenges.where((c) => c.isCompleted).length;
    final totalPoints = challenges
        .where((c) => c.isCompleted)
        .fold<int>(0, (sum, c) => sum + c.rewardPoints);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF241610), Color(0xFF191420)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border:
            Border.all(color: KinrelColors.orange.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Text('🎯', style: TextStyle(fontSize: 30)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$completed of ${challenges.length} complete',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: KinrelColors.textWhite,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  totalPoints > 0
                      ? 'You\'ve earned $totalPoints bonus points playing together'
                      : 'Finish games as a family to complete challenges and earn bonus points',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    height: 1.35,
                    color: KinrelColors.textSilver,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChallengeCard extends StatelessWidget {
  const _ChallengeCard({required this.challenge, required this.familyId});
  final ChallengeInfo challenge;
  final String familyId;

  @override
  Widget build(BuildContext context) {
    final done = challenge.isCompleted;
    final color = challenge.cadence == 'monthly'
        ? const Color(0xFF8B5CF6)
        : KinrelColors.orange;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: done
              ? KinrelColors.gold.withValues(alpha: 0.5)
              : color.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GamingProgressRing(
                progress: challenge.progressFraction,
                size: 52,
                color: done ? KinrelColors.gold : color,
                child: done
                    ? const Icon(Icons.check_rounded,
                        color: KinrelColors.brightGold, size: 24)
                    : Text(
                        '${challenge.progress}/${challenge.target}',
                        style: TextStyle(
                          fontFamily: KinrelTypography.monoFont,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: KinrelColors.textWhite,
                        ),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${challenge.icon} ${challenge.title}'
                            '${challenge.familyWide ? ' · 👨‍👩‍👧‍👦' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: KinrelColors.textWhite,
                            ),
                          ),
                        ),
                        if (done)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              gradient: KinrelGradients.achievementGradient,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '+${challenge.rewardPoints} pts',
                              style: TextStyle(
                                fontFamily: KinrelTypography.monoFont,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: KinrelColors.textDark,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      challenge.description,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        height: 1.35,
                        color: KinrelColors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GamingProgressBar(
            progress: challenge.progressFraction,
            color: done ? KinrelColors.gold : color,
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 300.ms)
        .slideY(begin: 0.03, end: 0, duration: 300.ms);
  }
}

// lib/features/gaming_ecosystem/presentation/gaming_milestones_screen.dart
//
// Family Milestones — the family's shared gaming journey: 1, 10, 25, 50,
// 100, 250, 500 games played together, plus game-variety milestones.
// Each shows progress toward the next unlock — a long-term bonding goal
// rather than an individual stat.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../shared/widgets/dk_components.dart';
import '../data/gaming_providers.dart';
import 'widgets/gaming_kit.dart';

class GamingMilestonesScreen extends ConsumerWidget {
  const GamingMilestonesScreen({super.key, required this.familyId});
  final String familyId;

  static const _togetherTargets = [1, 10, 25, 50, 100, 250, 500];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final milestonesAsync = ref.watch(gamingMilestonesProvider(familyId));

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.canPop() ? context.pop() : context.go('/home')),
        title: Text('Family Milestones',
            style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontWeight: FontWeight.w700)),
        backgroundColor: KinrelColors.darkCard,
        foregroundColor: KinrelColors.textWhite,
        elevation: 0,
      ),
      body: milestonesAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: KinrelColors.orange)),
        error: (e, _) => Center(
          child: GamingEmptyCard(
            emoji: '🔌',
            title: 'Couldn\'t load milestones',
            message: 'Pull down to try again.',
          ),
        ),
        data: (data) => RefreshIndicator(
          color: KinrelColors.orange,
          backgroundColor: KinrelColors.darkCard,
          onRefresh: () async {
            ref.invalidate(gamingMilestonesProvider(familyId));
            await ref.read(gamingMilestonesProvider(familyId).future);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            children: [
              _JourneyHero(
                  total: data.totalMatches,
                  distinct: data.distinctGames,
                  unlocked: data.milestones.length),
              const SizedBox(height: 18),
              GamingSectionHeader(
                title: 'Games Played Together',
                subtitle: 'Every match — win, lose or just-for-fun — counts',
                icon: Icons.favorite_outline,
              ),
              for (final t in _togetherTargets)
                _MilestoneRow(
                  emoji: _togetherEmoji(t),
                  title: _togetherTitle(t),
                  current: data.totalMatches,
                  target: t,
                ),
              const SizedBox(height: 14),
              GamingSectionHeader(
                title: 'Game Variety',
                subtitle: 'Explore the whole playground as a family',
                icon: Icons.explore_outlined,
              ),
              for (final t in const [5, 10])
                _MilestoneRow(
                  emoji: t == 5 ? '🧭' : '🗺️',
                  title: 'Try $t different games together',
                  current: data.distinctGames,
                  target: t,
                  unit: 'games',
                ),
              const SizedBox(height: 14),
              if (data.lastMatchAt != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Last family match ${gamingTimeAgo(data.lastMatchAt)} — the journey continues 💛',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      color: KinrelColors.textDim,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _togetherEmoji(int t) {
    switch (t) {
      case 1:
        return '🌱';
      case 10:
        return '💛';
      case 25:
        return '🔥';
      case 50:
        return '🎯';
      case 100:
        return '🏆';
      case 250:
        return '👑';
      default:
        return '🌟';
    }
  }

  String _togetherTitle(int t) {
    switch (t) {
      case 1:
        return 'First family match';
      default:
        return '$t games played together';
    }
  }
}

class _JourneyHero extends StatelessWidget {
  const _JourneyHero(
      {required this.total, required this.distinct, required this.unlocked});
  final int total;
  final int distinct;
  final int unlocked;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E2029), Color(0xFF141821)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: KinrelColors.amber.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Text('🎯', style: TextStyle(fontSize: 34)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'The Family Journey',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: KinrelColors.textWhite,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '$total matches played · $distinct different games · $unlocked milestones unlocked',
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
        ],
      ),
    );
  }
}

class _MilestoneRow extends StatelessWidget {
  const _MilestoneRow({
    required this.emoji,
    required this.title,
    required this.current,
    required this.target,
    this.unit = 'games',
  });

  final String emoji;
  final String title;
  final int current;
  final int target;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final reached = current >= target;
    final fraction = current >= target ? 1.0 : current / target;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: reached
              ? KinrelColors.gold.withValues(alpha: 0.45)
              : Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: reached ? KinrelGradients.achievementGradient : null,
              color: reached ? null : KinrelColors.darkElevated,
              border: Border.all(
                color: reached
                    ? KinrelColors.brightGold
                    : KinrelColors.textDim.withValues(alpha: 0.3),
              ),
            ),
            child: Center(
              child: reached
                  ? const Icon(Icons.check_rounded,
                      color: KinrelColors.textDark, size: 22)
                  : Text(emoji, style: const TextStyle(fontSize: 19)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                  ),
                ),
                const SizedBox(height: 7),
                GamingProgressBar(
                  progress: fraction,
                  height: 6,
                  color: reached ? KinrelColors.gold : KinrelColors.amber,
                ),
                const SizedBox(height: 5),
                Text(
                  reached
                      ? 'Unlocked · $current+ $unit played'
                      : '$current of $target $unit · ${target - current} to go',
                  style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 10,
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
}

// lib/features/gaming_ecosystem/presentation/gaming_achievements_screen.dart
//
// Family Achievements & Badges — the trophy room.
//
// Recognition-system design:
//   • Tier-colored rings (bronze → platinum) with a gold glow for earned.
//   • Locked badges show their unlock condition — always visible progress.
//   • Grouped by tier with an earned-count hero at the top.

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

class GamingAchievementsScreen extends ConsumerWidget {
  const GamingAchievementsScreen({super.key, required this.familyId});
  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashAsync = ref.watch(gamingDashboardProvider(familyId));

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.canPop() ? context.pop() : context.go('/home')),
        title: Text('Achievements',
            style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontWeight: FontWeight.w700)),
        backgroundColor: KinrelColors.darkCard,
        foregroundColor: KinrelColors.textWhite,
        elevation: 0,
      ),
      body: dashAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: KinrelColors.orange)),
        error: (e, _) => Center(
          child: GamingEmptyCard(
            emoji: '🔌',
            title: 'Couldn\'t load achievements',
            message: 'Pull down to try again.',
          ),
        ),
        data: (dash) {
          final earned = dash.allGameBadges.where((b) => b.earned).toList();
          final locked = dash.allGameBadges.where((b) => !b.earned).toList();
          return RefreshIndicator(
            color: KinrelColors.orange,
            backgroundColor: KinrelColors.darkCard,
            onRefresh: () async {
              ref.invalidate(gamingDashboardProvider(familyId));
              await ref.read(gamingDashboardProvider(familyId).future);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              children: [
                _TrophyRoomHero(earned: earned, total: dash.allGameBadges.length),
                const SizedBox(height: 18),
                GamingSectionHeader(
                  title: 'Latest Badges',
                  subtitle: 'Your most recent family gaming moments',
                  icon: Icons.emoji_events_outlined,
                ),
                if (dash.myBadges.isEmpty)
                  GamingEmptyCard(
                    emoji: '🌱',
                    title: 'Your trophy room awaits',
                    message:
                        'Play your first family game to unlock the First Victory badge.',
                  )
                else
                  SizedBox(
                    height: 108,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: dash.myBadges.take(10).length,
                      separatorBuilder: (_, __) => const SizedBox(width: 14),
                      itemBuilder: (context, i) {
                        final b = dash.myBadges[i];
                        return SizedBox(
                          width: 82,
                          child: GamingBadgeChip(
                            icon: b.icon,
                            name: b.name,
                            tier: b.tier,
                            earned: true,
                          ),
                        )
                            .animate()
                            .fadeIn(delay: (60 * i).ms, duration: 300.ms)
                            .scale(
                                begin: const Offset(0.85, 0.85),
                                end: const Offset(1, 1),
                                duration: 300.ms,
                                curve: Curves.easeOutBack);
                      },
                    ),
                  ),
                const SizedBox(height: 18),
                GamingSectionHeader(
                  title: 'Earned · ${earned.length}',
                  icon: Icons.workspace_premium_outlined,
                ),
                _BadgeGrid(badges: earned),
                const SizedBox(height: 12),
                GamingSectionHeader(
                  title: 'Still to Unlock · ${locked.length}',
                  subtitle: 'Each badge shows how to earn it',
                  icon: Icons.lock_outline,
                ),
                _BadgeGrid(badges: locked),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TrophyRoomHero extends StatelessWidget {
  const _TrophyRoomHero({required this.earned, required this.total});
  final List<BadgeInfo> earned;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2A1F0C), Color(0xFF1A1608)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: KinrelColors.gold.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: KinrelColors.gold.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          GamingProgressRing(
            progress: total == 0 ? 0 : earned.length / total,
            size: 72,
            strokeWidth: 6,
            color: KinrelColors.brightGold,
            child: Text(
              '${earned.length}/$total',
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: KinrelColors.textWhite,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Trophy Room',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: KinrelColors.brightGold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  earned.isEmpty
                      ? 'Every game you play together brings a badge closer.'
                      : 'You\'ve unlocked ${earned.length} badges playing with your family. Keep the streak alive!',
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

class _BadgeGrid extends StatelessWidget {
  const _BadgeGrid({required this.badges});
  final List<BadgeInfo> badges;

  @override
  Widget build(BuildContext context) {
    if (badges.isEmpty) {
      return const SizedBox.shrink();
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: badges.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 14,
        crossAxisSpacing: 8,
        childAspectRatio: 0.72,
      ),
      itemBuilder: (context, i) {
        final b = badges[i];
        return Tooltip(
          message: '${b.name} — ${b.description}',
          triggerMode: TooltipTriggerMode.longPress,
          child: GamingBadgeChip(
            icon: b.icon,
            name: b.name,
            tier: b.tier,
            earned: b.earned,
            size: 58,
          ),
        );
      },
    );
  }
}

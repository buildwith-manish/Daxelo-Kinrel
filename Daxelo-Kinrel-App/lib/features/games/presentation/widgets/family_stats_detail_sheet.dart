// lib/features/games/presentation/widgets/family_stats_detail_sheet.dart
//
// FamilyStatsDetailSheet — the destination for tap-on-hero-card.
//
// Holds the content that used to clutter the home surface as separate
// stat-chip rows + challenge rings:
//   • Full rank + win-streak + games + badges stat grid (4 chips)
//   • Family Cup standing detail
//   • Weekly challenges carousel (the ring widgets that used to be on home)
//   • Quick links: Full leaderboard, Full challenges screen, Achievements
//
// Privacy contract (unchanged from the prior reframe):
//   • The signed-in viewer's own wins / win% are visible here (it's their
//     own data). Other family members' wins/losses/win% are NEVER shown —
//     they remain behind the participant gate from the privacy migration.
//   • Streak shown here is the viewer's own current win streak (self-only).
//
// Rendered as a draggable modal bottom sheet (~85% viewport height).

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../gaming_ecosystem/data/gaming_models.dart';
import '../../../gaming_ecosystem/presentation/widgets/gaming_kit.dart';
import '../../shared/icons/kinrel_icons.dart';

class FamilyStatsDetailSheet extends ConsumerWidget {
  const FamilyStatsDetailSheet({
    super.key,
    required this.familyId,
    required this.dashboard,
    required this.streak,
  });

  final String familyId;
  final GamingDashboard? dashboard;
  final FamilyPlayStreak? streak;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dash = dashboard;
    final topPad = MediaQuery.of(context).padding.top;
    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
        color: KinrelColors.darkSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Padding(
            padding: EdgeInsets.only(top: 10 + topPad * 0.0),
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Your family gaming at a glance',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: KinrelColors.textDim),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
          // Body
          Expanded(
            child: dash == null
                ? const Center(
                    child: CircularProgressIndicator(color: KinrelColors.orange),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 36),
                    children: [
                      _StatGrid(dashboard: dash, streak: streak),
                      const SizedBox(height: 18),
                      if (dash.season != null) ...[
                        _CupStandingCard(familyId: familyId, dashboard: dash),
                        const SizedBox(height: 18),
                      ],
                      if (dash.challenges.isNotEmpty) ...[
                        GamingSectionHeader(
                          title: 'This Week\'s Challenges',
                          subtitle: 'Small goals that bring the family together',
                          icon: Icons.flag_outlined,
                          actionLabel: 'View all',
                          onAction: () {
                            Navigator.of(context).maybePop();
                            context.push('/family/$familyId/gaming/challenges');
                          },
                        ),
                        _ChallengeCarousel(familyId: familyId, dashboard: dash),
                        const SizedBox(height: 18),
                      ],
                      _QuickLinksRow(familyId: familyId),
                    ],
                  ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 220.ms)
        .slideY(begin: 0.08, end: 0, duration: 280.ms, curve: Curves.easeOutCubic);
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Stat grid — 4 chips (rank, win streak, games, badges). Self-only data.
// ─────────────────────────────────────────────────────────────────────────

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.dashboard, required this.streak});
  final GamingDashboard dashboard;
  final FamilyPlayStreak? streak;

  @override
  Widget build(BuildContext context) {
    final me = dashboard.me;
    final badgeCount = dashboard.myBadges.length;
    final winStreak = me.streakCurrent; // self-only — always safe to show
    return Row(
      children: [
        Expanded(
          child: GamingStatChip(
            emoji: '🥇',
            value: me.rank > 0 ? '#${me.rank}' : '—',
            label: 'FAMILY RANK',
            color: KinrelColors.brightGold,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GamingStatChip(
            emoji: '🔥',
            value: '$winStreak',
            label: 'WIN STREAK',
            color: KinrelColors.error,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GamingStatChip(
            emoji: '🎮',
            value: '${me.matches}',
            label: 'GAMES',
            color: KinrelColors.orange,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GamingStatChip(
            emoji: '🏅',
            value: '$badgeCount',
            label: 'BADGES',
            color: const Color(0xFFD97706),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Cup standing card — expands the subtext on the hero card.
// ─────────────────────────────────────────────────────────────────────────

class _CupStandingCard extends StatelessWidget {
  const _CupStandingCard({required this.familyId, required this.dashboard});
  final String familyId;
  final GamingDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final season = dashboard.season!;
    final me = dashboard.me;
    final myStanding = dashboard.seasonStandings
        .where((s) => s.userId == me.userId)
        .toList();
    final myPoints = myStanding.isNotEmpty ? myStanding.first.points : me.points;
    final myRank = myStanding.isNotEmpty
        ? dashboard.seasonStandings.indexOf(myStanding.first) + 1
        : me.rank;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2A1A0E), Color(0xFF1C1410)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: KinrelColors.gold.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const KinrelIcon(KinrelIconData.trophy,
              size: 28, color: KinrelColors.brightGold),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  season.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: KinrelColors.brightGold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  myPoints > 0
                      ? '${season.daysRemaining}d left · you\'re #${myRank > 0 ? myRank : '—'} with $myPoints pts'
                      : '${season.daysRemaining}d left · play a match to earn Cup points',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 11.5,
                    color: KinrelColors.textSilver,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, color: KinrelColors.gold, size: 22),
            onPressed: () {
              Navigator.of(context).maybePop();
              context.push('/family/$familyId/gaming/season');
            },
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Challenge carousel — the ring widgets that used to live on the home
// surface. Now they live here, one tap away.
// ─────────────────────────────────────────────────────────────────────────

class _ChallengeCarousel extends StatelessWidget {
  const _ChallengeCarousel({required this.familyId, required this.dashboard});
  final String familyId;
  final GamingDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final challenges =
        dashboard.challenges.where((c) => !c.isCompleted).take(6).toList();
    if (challenges.isEmpty) {
      return GamingEmptyCard(
        emoji: '✅',
        title: 'All challenges complete!',
        message:
            'You\'re a family gaming legend this week. New ones land Monday.',
      );
    }
    return SizedBox(
      height: 118,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: challenges.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final c = challenges[i];
          final color = c.cadence == 'monthly'
              ? const Color(0xFF8B5CF6)
              : KinrelColors.orange;
          return GestureDetector(
            onTap: () => context.push('/family/$familyId/gaming/challenges'),
            child: Container(
              width: 230,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: KinrelColors.darkCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  GamingProgressRing(
                    progress: c.progressFraction,
                    size: 52,
                    color: color,
                    child: Text(
                      '${c.progress}/${c.target}',
                      style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: KinrelColors.textWhite,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            if (kinrelIconFromEmoji(c.icon) != null) ...[
                              KinrelIcon(kinrelIconFromEmoji(c.icon)!,
                                  size: 13, color: color),
                              const SizedBox(width: 5),
                            ],
                            Expanded(
                              child: Text(
                                c.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: KinrelTypography.bodyFont,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: KinrelColors.textWhite,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          c.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 10.5,
                            height: 1.3,
                            color: KinrelColors.textDim,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
              .animate()
              .fadeIn(delay: (60 * i).ms, duration: 250.ms);
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Quick links row — jump to full leaderboard / achievements / match history.
// ─────────────────────────────────────────────────────────────────────────

class _QuickLinksRow extends StatelessWidget {
  const _QuickLinksRow({required this.familyId});
  final String familyId;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _QuickLinkChip(
          icon: Icons.leaderboard_outlined,
          label: 'Leaderboard',
          onTap: () {
            Navigator.of(context).maybePop();
            context.push('/family/$familyId/gaming/leaderboard');
          },
        ),
        _QuickLinkChip(
          icon: Icons.emoji_events_outlined,
          label: 'Achievements',
          onTap: () {
            Navigator.of(context).maybePop();
            context.push('/family/$familyId/gaming/achievements');
          },
        ),
        _QuickLinkChip(
          icon: Icons.history,
          label: 'Match History',
          onTap: () {
            Navigator.of(context).maybePop();
            context.push('/family/$familyId/gaming/match-history');
          },
        ),
        _QuickLinkChip(
          icon: Icons.military_tech_outlined,
          label: 'Milestones',
          onTap: () {
            Navigator.of(context).maybePop();
            context.push('/family/$familyId/gaming/milestones');
          },
        ),
      ],
    );
  }
}

class _QuickLinkChip extends StatelessWidget {
  const _QuickLinkChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      onPressed: onTap,
      avatar: Icon(icon, size: 16, color: KinrelColors.orange),
      label: Text(
        label,
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: KinrelColors.textWhite,
        ),
      ),
      backgroundColor: KinrelColors.darkCard,
      side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  }
}

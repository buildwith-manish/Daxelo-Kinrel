// lib/features/gaming_ecosystem/presentation/gaming_season_screen.dart
//
// Seasonal Events & The Family Cup — the current month's cup with live
// standings, days remaining, and how points work. Seasons are lazy: the
// first game of a month starts the cup; at month end the top 3 are
// immortalised as season winners (with the Family Cup Champion badge).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../shared/widgets/dk_components.dart';
import '../data/gaming_providers.dart';
import '../../games/shared/icons/kinrel_icons.dart';
import 'widgets/gaming_kit.dart';
import 'package:flutter_animate/flutter_animate.dart';

class GamingSeasonScreen extends ConsumerWidget {
  const GamingSeasonScreen({super.key, required this.familyId});
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
        title: Text('Family Cup',
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
            title: 'Couldn\'t load the Family Cup',
            message: 'Pull down to try again.',
          ),
        ),
        data: (dash) => RefreshIndicator(
          color: KinrelColors.orange,
          backgroundColor: KinrelColors.darkCard,
          onRefresh: () async {
            ref.invalidate(gamingDashboardProvider(familyId));
            await ref.read(gamingDashboardProvider(familyId).future);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            children: [
              _CupHero(
                seasonName: dash.season?.name ?? 'The Family Cup',
                daysRemaining: dash.season?.daysRemaining ?? 0,
              ),
              const SizedBox(height: 16),
              GamingSectionHeader(
                title: 'How the Cup Works',
                subtitle: 'Everyone contributes — showing up matters most',
                icon: Icons.help_outline,
              ),
              const _PointsExplainer(),
              const SizedBox(height: 16),
              GamingSectionHeader(
                title: 'Standings',
                subtitle: 'Top 3 at month-end are crowned family champions',
                icon: Icons.leaderboard_outlined,
              ),
              if (dash.seasonStandings.isEmpty)
                GamingEmptyCard(
                  emoji: '🏁',
                  title: 'The cup is wide open',
                  message:
                      'No points yet this month. Play a game together — the '
                      'whole family\'s points count toward the cup.',
                )
              else ...[
                GamingPodium(
                  entries: dash.seasonStandings,
                  myUserId: dash.me.userId,
                  onTap: (e) => context.push(
                      '/family/$familyId/gaming/player/${e.userId}'),
                ),
                const SizedBox(height: 10),
                ...dash.seasonStandings.asMap().entries.map((entry) {
                  final i = entry.key;
                  final s = entry.value;
                  return GamingRankRow(
                    rank: i + 1,
                    userName: s.userName,
                    points: s.points,
                    matches: s.gamesPlayed,
                    wins: s.wins,
                    isMe: s.userId == dash.me.userId,
                    onTap: () => context
                        .push('/family/$familyId/gaming/player/${s.userId}'),
                  );
                }),
              ],
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: KinrelColors.darkCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: KinrelColors.gold.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    const KinrelIcon(KinrelIconData.crown,
                        size: 24, color: KinrelColors.brightGold),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'The monthly champion earns the Family Cup Champion badge — a permanent crown in the trophy room.',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 12,
                          height: 1.45,
                          color: KinrelColors.textSilver,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CupHero extends StatelessWidget {
  const _CupHero({required this.seasonName, required this.daysRemaining});
  final String seasonName;
  final int daysRemaining;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2A1F0C), Color(0xFF191308)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: KinrelColors.gold.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(
            color: KinrelColors.gold.withValues(alpha: 0.18),
            blurRadius: 26,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          const KinrelIcon(KinrelIconData.trophy,
              size: 46, color: KinrelColors.brightGold),
          const SizedBox(height: 10),
          Text(
            seasonName,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
              color: KinrelColors.brightGold,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: KinrelColors.gold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: KinrelColors.gold.withValues(alpha: 0.4)),
            ),
            child: Text(
              daysRemaining > 0
                  ? '$daysRemaining days remaining'
                  : 'Final results coming',
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: KinrelColors.gold,
              ),
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 400.ms)
        .scale(
            begin: const Offset(0.95, 0.95),
            end: const Offset(1, 1),
            duration: 400.ms,
            curve: Curves.easeOutBack);
  }
}

class _PointsExplainer extends StatelessWidget {
  const _PointsExplainer();

  @override
  Widget build(BuildContext context) {
    Widget pointRow(KinrelIconData icon, String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              KinrelIcon(icon, size: 16, color: KinrelColors.orange),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12.5,
                    color: KinrelColors.textSilver,
                  ),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: KinrelColors.orange,
                ),
              ),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          pointRow(KinrelIconData.trophy, 'Win a match', '+3 pts'),
          pointRow(KinrelIconData.handshake, 'Draw a match', '+1 pt'),
          pointRow(KinrelIconData.controller, 'Play a match (any result)', '+1 pt'),
          pointRow(KinrelIconData.heart, 'Earn sportsmanship cheers', 'badge progress'),
        ],
      ),
    );
  }
}

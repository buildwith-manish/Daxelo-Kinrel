// lib/features/gaming_ecosystem/presentation/gaming_leaderboard_screen.dart
//
// Family Leaderboards — weekly · monthly · all-time · per-game.
//
// Non-toxic design rules:
//   • Primary ordering is POINTS (participation-weighted: win 3, draw 1,
//     played 1) so showing up for the family always matters.
//   • Losses are never displayed. Streaks, wins and games played are.
//   • The podium celebrates the top 3; every row is tappable to view the
//     player's gaming profile (recognition system).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../games/presentation/widgets/not_yet_played_prompt.dart';
import '../data/game_registry.dart';
import '../data/gaming_providers.dart';
import '../../games/shared/icons/kinrel_icons.dart';
import 'widgets/gaming_kit.dart';
import 'package:flutter_animate/flutter_animate.dart';

class GamingLeaderboardScreen extends ConsumerStatefulWidget {
  const GamingLeaderboardScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<GamingLeaderboardScreen> createState() =>
      _GamingLeaderboardScreenState();
}

class _GamingLeaderboardScreenState
    extends ConsumerState<GamingLeaderboardScreen> {
  String _period = 'weekly'; // weekly | monthly | all_time
  String? _gameTable; // null = all games

  @override
  Widget build(BuildContext context) {
    final key = LeaderboardKey(
      familyId: widget.familyId,
      period: _period,
      gameTable: _gameTable,
    );
    // Use the v3 participation-based leaderboard directly (ranked by
    // games_played DESC, with a separate notYetPlayed section).
    final lbAsync = ref.watch(participationLeaderboardProvider(key));
    final dashAsync = ref.watch(gamingDashboardProvider(widget.familyId));
    final myUserId =
        dashAsync.asData?.value.me.userId ?? '';

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.canPop() ? context.pop() : context.go('/home')),
        title: const Text('Leaderboard',
            style: const TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontWeight: FontWeight.w700)),
        backgroundColor: KinrelColors.darkCard,
        foregroundColor: KinrelColors.textWhite,
        elevation: 0,
      ),
      body: Column(
        children: [
          // ── Period tabs ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                _PeriodTab(
                    label: 'Weekly',
                    selected: _period == 'weekly',
                    onTap: () => setState(() => _period = 'weekly')),
                const SizedBox(width: 8),
                _PeriodTab(
                    label: 'Monthly',
                    selected: _period == 'monthly',
                    onTap: () => setState(() => _period = 'monthly')),
                const SizedBox(width: 8),
                _PeriodTab(
                    label: 'All-Time',
                    selected: _period == 'all_time',
                    onTap: () => setState(() => _period = 'all_time')),
              ],
            ),
          ),

          // ── Per-game filter chips ──────────────────────────────────
          // v114 — Step 4 perf: use ListView.builder so chip widgets
          // are built lazily (only the visible ~5 of ~30 are built
          // at any time during horizontal scroll).
          SizedBox(
            height: 44,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 1 + kGameCatalog.length,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _GameFilterChip(
                    label: 'All Games',
                    icon: '🎮',
                    selected: _gameTable == null,
                    onTap: () => setState(() => _gameTable = null),
                  );
                }
                final g = kGameCatalog[index - 1];
                return _GameFilterChip(
                  label: g.name,
                  icon: '🏆',
                  selected: _gameTable == g.gameTable,
                  onTap: () => setState(() => _gameTable = g.gameTable),
                );
              },
            ),
          ),
          const SizedBox(height: 6),

          // ── Entries ────────────────────────────────────────────────
          Expanded(
            child: lbAsync.when(
              loading: () => const Center(
                  child: CircularProgressIndicator(color: KinrelColors.orange)),
              error: (e, _) => const Center(
                child: const GamingEmptyCard(
                  emoji: '🔌',
                  title: 'Couldn\'t load the leaderboard',
                  message: 'Pull down to try again.',
                ),
              ),
              data: (lb) {
                final ranked = lb.ranked;
                final notPlayed = lb.notYetPlayed;
                if (ranked.isEmpty && notPlayed.isEmpty) {
                  return ListView(children: [
                    const SizedBox(height: 80),
                    GamingEmptyCard(
                      emoji: '🏁',
                      title: _period == 'weekly'
                          ? 'No games this week yet'
                          : _period == 'monthly'
                              ? 'No games this month yet'
                              : 'Your family hasn\'t played yet',
                      message: 'Play a game together — every match counts '
                          'for everyone who shows up.',
                    ),
                  ]);
                }
                return RefreshIndicator(
                  color: KinrelColors.orange,
                  backgroundColor: KinrelColors.darkCard,
                  onRefresh: () async {
                    ref.invalidate(participationLeaderboardProvider(key));
                    await ref.read(
                        participationLeaderboardProvider(key).future);
                  },
                  // v114 — Step 4 perf: build a flat list of rows then
                  // use ListView.builder so leaderboard rows + "not
                  // playing yet" prompts are built lazily.
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                    itemCount: () {
                      int count = 0;
                      if (ranked.length >= 2) count += 1; // podium
                      count += ranked.length; // rank rows
                      if (notPlayed.isNotEmpty) {
                        count += 1; // spacer (SizedBox(height: 20))
                        count += 1; // section header
                        count += notPlayed.length; // not-played prompts
                      }
                      return count;
                    }(),
                    itemBuilder: (context, index) {
                      var i = index;
                      if (ranked.length >= 2) {
                        if (i == 0) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: GamingPodium(
                              entries: ranked,
                              myUserId: myUserId,
                              onTap: (e) => context.push(
                                  '/family/${widget.familyId}/gaming/player/${e.userId}'),
                            ),
                          );
                        }
                        i -= 1;
                      }
                      if (i < ranked.length) {
                        final rankIndex = i;
                        return GamingRankRow(
                          rank: rankIndex + 1,
                          userName: ranked[rankIndex].userName,
                          points: ranked[rankIndex].points,
                          matches: ranked[rankIndex].matches,
                          streak: ranked[rankIndex].userId == myUserId &&
                                  _period == 'all_time'
                              ? ranked[rankIndex].streakCurrent
                              : 0,
                          isMe: ranked[rankIndex].userId == myUserId,
                          hideScoreChip: true,
                          onTap: () => context.push(
                              '/family/${widget.familyId}/gaming/player/${ranked[rankIndex].userId}'),
                        )
                            .animate()
                            .fadeIn(delay: (30 * rankIndex).ms, duration: 250.ms);
                      }
                      i -= ranked.length;
                      // "Not playing yet" section header + prompts.
                      if (i == 0) {
                        return const SizedBox(height: 20);
                      }
                      if (i == 1) {
                        return const Padding(
                          padding: EdgeInsets.only(bottom: 8, left: 2),
                          child: const Text(
                            'Not playing yet',
                            style: const TextStyle(
                              fontFamily: KinrelTypography.displayFont,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                              color: KinrelColors.amber,
                            ),
                          ),
                        );
                      }
                      final npIndex = i - 2;
                      final m = notPlayed[npIndex];
                      return NotYetPlayedPrompt(
                        member: NotYetPlayedMemberData(
                          userId: m.userId,
                          userName: m.userName,
                          avatarUrl: m.avatarUrl,
                        ),
                        familyId: widget.familyId,
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PeriodTab extends StatelessWidget {
  const _PeriodTab(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: selected ? KinrelGradients.ignite : null,
            color: selected ? null : KinrelColors.darkCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? KinrelColors.orange
                  : Colors.white.withValues(alpha: 0.07),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
              color: selected ? Colors.white : KinrelColors.textDim,
            ),
          ),
        ),
      ),
    );
  }
}

class _GameFilterChip extends StatelessWidget {
  const _GameFilterChip(
      {required this.label,
      required this.icon,
      required this.selected,
      required this.onTap});
  final String label;
  final String icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final chipColor = selected ? KinrelColors.orange : KinrelColors.textDim;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? KinrelColors.orange.withValues(alpha: 0.16)
                : KinrelColors.darkCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? KinrelColors.orange
                  : Colors.white.withValues(alpha: 0.07),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              KinrelIcon(
                  kinrelIconFromEmoji(icon) ?? KinrelIconData.controller,
                  size: 13,
                  color: chipColor),
              const SizedBox(width: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? KinrelColors.orange : KinrelColors.textDim,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

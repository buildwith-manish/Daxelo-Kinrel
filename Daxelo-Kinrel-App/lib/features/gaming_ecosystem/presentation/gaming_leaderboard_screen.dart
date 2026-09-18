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
    final entriesAsync = ref.watch(gamingLeaderboardProvider(key));
    final dashAsync = ref.watch(gamingDashboardProvider(widget.familyId));
    final myUserId =
        dashAsync.asData?.value.me.userId ?? '';

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.canPop() ? context.pop() : context.go('/home')),
        title: Text('Leaderboard',
            style: TextStyle(
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
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _GameFilterChip(
                  label: 'All Games',
                  icon: '🎮',
                  selected: _gameTable == null,
                  onTap: () => setState(() => _gameTable = null),
                ),
                for (final g in kGameCatalog)
                  _GameFilterChip(
                    label: g.name,
                    icon: '🏆',
                    selected: _gameTable == g.gameTable,
                    onTap: () => setState(() => _gameTable = g.gameTable),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),

          // ── Entries ────────────────────────────────────────────────
          Expanded(
            child: entriesAsync.when(
              loading: () => const Center(
                  child: CircularProgressIndicator(color: KinrelColors.orange)),
              error: (e, _) => Center(
                child: GamingEmptyCard(
                  emoji: '🔌',
                  title: 'Couldn\'t load the leaderboard',
                  message: 'Pull down to try again.',
                ),
              ),
              data: (entries) => RefreshIndicator(
                color: KinrelColors.orange,
                backgroundColor: KinrelColors.darkCard,
                onRefresh: () async {
                  ref.invalidate(gamingLeaderboardProvider(key));
                  await ref.read(gamingLeaderboardProvider(key).future);
                },
                child: entries.isEmpty
                    ? ListView(children: [
                        const SizedBox(height: 80),
                        GamingEmptyCard(
                          emoji: '🏁',
                          title: _period == 'weekly'
                              ? 'No games this week yet'
                              : _period == 'monthly'
                                  ? 'No games this month yet'
                                  : 'Your family hasn\'t played yet',
                          message:
                              'Play a game together — every match earns points '
                              'for everyone who shows up.',
                        ),
                      ])
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                        itemCount: entries.length + 1,
                        itemBuilder: (context, i) {
                          if (i == 0) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: GamingPodium(
                                entries: entries,
                                myUserId: myUserId,
                                onTap: (e) => context.push(
                                    '/family/${widget.familyId}/gaming/player/${e.userId}'),
                              ),
                            );
                          }
                          final e = entries[i - 1];
                          return GamingRankRow(
                            rank: i,
                            userName: e.userName,
                            points: e.points,
                            matches: e.matches,
                            // Streak only renders for the viewer's own row
                            // (the row widget gates the chip on isMe; the
                            // backend also returns 0 for everyone else).
                            streak: e.userId == myUserId &&
                                    _period == 'all_time'
                                ? e.streakCurrent
                                : 0,
                            isMe: e.userId == myUserId,
                            onTap: () => context.push(
                                '/family/${widget.familyId}/gaming/player/${e.userId}'),
                          )
                              .animate()
                              .fadeIn(delay: (30 * i).ms, duration: 250.ms);
                        },
                      ),
              ),
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

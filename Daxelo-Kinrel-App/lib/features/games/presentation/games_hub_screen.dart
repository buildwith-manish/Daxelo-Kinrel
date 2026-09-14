// lib/features/games/presentation/games_hub_screen.dart
//
// ┌─────────────────────────────────────────────────────────────────────┐
// │  FAMILY ARENA — the redesigned Games hub (Gaming Dashboard)         │
// └─────────────────────────────────────────────────────────────────────┘
//
// The hub is no longer a flat catalog — it is the family's gaming home:
//
//   1. Family Cup banner            (seasonal event, days left, your rank)
//   2. Quick stats row               (rank · streak · games · badges)
//   3. Weekly challenges carousel    (progress rings, tap for detail)
//   4. Smart match suggestions       (online members + shared favorites)
//   5. Family leaderboard preview    (podium + your position)
//   6. Categorised game grid         (Hick's Law: 4 scannable groups)
//   7. Activity feed preview         (social proof)
//   8. Milestones progress strip     (long-term shared goals)
//
// UX principles applied:
//   • Hick's Law      — 15 games are grouped into 4 categories with
//                       progressive disclosure (collapse/expand).
//   • Fitts's Law     — whole game cards are tap targets (≥ 96dp tall).
//   • Social proof    — activity feed, presence, playmate counts.
//   • Reward loops    — challenges/season points update after each match.
//   • Non-toxic       — losses never shown; streaks + participation are.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../family/presentation/family_space_floating_nav.dart';
import '../../gaming_ecosystem/data/game_registry.dart';
import '../../gaming_ecosystem/data/gaming_models.dart';
import '../../gaming_ecosystem/data/gaming_providers.dart';
import '../../gaming_ecosystem/presentation/widgets/gaming_kit.dart';
import '../services/game_asset_manager.dart';
import '../shared/icons/game_icons.dart';
import '../shared/widgets/family_presence_strip.dart';

class GamesHubScreen extends ConsumerStatefulWidget {
  const GamesHubScreen({super.key, this.familyId});
  final String? familyId;

  @override
  ConsumerState<GamesHubScreen> createState() => _GamesHubScreenState();
}

class _GamesHubScreenState extends ConsumerState<GamesHubScreen> {
  String? _resolvedFamilyId;
  bool _resolving = true;
  final Set<GameCategory> _expandedCategories = {GameCategory.quickDuels};

  @override
  void initState() {
    super.initState();
    _resolveFamilyId();
  }

  /// Resolves the family to use: the explicit query param, or the user's
  /// first family (so the dashboard always has a family context).
  Future<void> _resolveFamilyId() async {
    if (widget.familyId != null) {
      setState(() {
        _resolvedFamilyId = widget.familyId;
        _resolving = false;
      });
      return;
    }
    final client = ref.read(supabaseProvider);
    if (client?.auth.currentUser == null) {
      setState(() => _resolving = false);
      return;
    }
    try {
      final fams = await client!
          .rpc('get_user_families',
              params: {'p_user_id': client.auth.currentUser!.id})
          .timeout(const Duration(seconds: 8));
      String? first;
      if (fams is List && fams.isNotEmpty) {
        final row = Map<String, dynamic>.from(fams.first as Map);
        first = row['id']?.toString();
      }
      setState(() {
        _resolvedFamilyId = first;
        _resolving = false;
      });
    } catch (_) {
      setState(() => _resolving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final familyId = _resolvedFamilyId;
    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
        ),
        title: Text(
          'Family Arena',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
        backgroundColor: KinrelColors.darkCard,
        foregroundColor: KinrelColors.textWhite,
        elevation: 0,
      ),
      bottomNavigationBar: familyId != null
          ? FamilySpaceFloatingNav(familyId: familyId)
          : null,
      body: _resolving
          ? const Center(
              child: CircularProgressIndicator(color: KinrelColors.orange))
          : familyId == null
              ? _NoFamilyState()
              : _GamingDashboardBody(
                  familyId: familyId,
                  expandedCategories: _expandedCategories,
                  onToggleCategory: _toggleCategory,
                ),
    );
  }

  void _toggleCategory(GameCategory category) {
    setState(() {
      if (_expandedCategories.contains(category)) {
        _expandedCategories.remove(category);
      } else {
        _expandedCategories.add(category);
      }
    });
  }
}

class _NoFamilyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('👨‍👩‍👧‍👦', style: TextStyle(fontSize: 44)),
            const SizedBox(height: 12),
            Text(
              'Create your family to unlock the Arena',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Games, challenges, leaderboards and cups live inside your family space.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                height: 1.4,
                color: KinrelColors.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GamingDashboardBody extends ConsumerWidget {
  const _GamingDashboardBody({
    required this.familyId,
    required this.expandedCategories,
    required this.onToggleCategory,
  });

  final String familyId;
  final Set<GameCategory> expandedCategories;
  final void Function(GameCategory) onToggleCategory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashAsync = ref.watch(gamingDashboardProvider(familyId));

    return RefreshIndicator(
      color: KinrelColors.orange,
      backgroundColor: KinrelColors.darkCard,
      onRefresh: () async {
        ref.invalidate(gamingDashboardProvider(familyId));
        await ref.read(gamingDashboardProvider(familyId).future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            KinrelSpacing.base, KinrelSpacing.base, KinrelSpacing.base, 120),
        children: [
          // ── Family presence (who's around right now) ────────────────
          FamilyPresenceStrip(familyId: familyId),
          const SizedBox(height: 14),

          dashAsync.when(
            loading: () => const _DashboardSkeleton(),
            error: (e, _) => GamingEmptyCard(
              emoji: '🔌',
              title: 'Could not load your Arena',
              message: 'Check your connection and pull to refresh.',
            ),
            data: (dash) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── 1. Family Cup banner ─────────────────────────────
                if (dash.season != null) ...[
                  _SeasonBanner(familyId: familyId, dashboard: dash),
                  const SizedBox(height: 14),
                ],

                // ── 2. Quick stats row ───────────────────────────────
                _QuickStatsRow(familyId: familyId, dashboard: dash),
                const SizedBox(height: 18),

                // ── 3. Challenges ────────────────────────────────────
                if (dash.challenges.isNotEmpty) ...[
                  GamingSectionHeader(
                    title: 'This Week\'s Challenges',
                    subtitle: 'Small goals that bring the family together',
                    icon: Icons.flag_outlined,
                    actionLabel: 'View all',
                    onAction: () => context.push(
                        '/family/$familyId/gaming/challenges'),
                  ),
                  _ChallengeCarousel(familyId: familyId, dashboard: dash),
                  const SizedBox(height: 18),
                ],

                // ── 4. Smart match suggestions ───────────────────────
                if (dash.suggestions.isNotEmpty) ...[
                  GamingSectionHeader(
                    title: 'Play Now',
                    subtitle: 'Family online — start a match together',
                    icon: Icons.bolt_rounded,
                  ),
                  _SmartSuggestions(familyId: familyId, dashboard: dash),
                  const SizedBox(height: 18),
                ],

                // ── 5. Leaderboard preview ───────────────────────────
                if (dash.leaderboard.isNotEmpty) ...[
                  GamingSectionHeader(
                    title: 'Family Leaderboard',
                    subtitle: 'Friendly competition — everyone earns points',
                    icon: Icons.leaderboard_outlined,
                    actionLabel: 'View all',
                    onAction: () => context.push(
                        '/family/$familyId/gaming/leaderboard'),
                  ),
                  _LeaderboardPreview(familyId: familyId, dashboard: dash),
                  const SizedBox(height: 18),
                ],

                // ── 6. Games grid (categorised) ──────────────────────
                GamingSectionHeader(
                  title: 'Family Games',
                  subtitle:
                      '${kGameCatalog.length} games · ${dash.familyDistinctGames} explored together',
                  icon: Icons.sports_esports_outlined,
                ),
                _CategorizedGameGrid(
                  familyId: familyId,
                  expandedCategories: expandedCategories,
                  onToggleCategory: onToggleCategory,
                ),
                const SizedBox(height: 18),

                // ── 7. Activity preview ──────────────────────────────
                if (dash.activity.isNotEmpty) ...[
                  GamingSectionHeader(
                    title: 'Family Moments',
                    subtitle: 'Every game becomes a memory',
                    icon: Icons.favorite_outline,
                    actionLabel: 'View all',
                    onAction: () =>
                        context.push('/family/$familyId/gaming/activity'),
                  ),
                  _ActivityPreview(dashboard: dash),
                  const SizedBox(height: 18),
                ],

                // ── 8. Milestones strip ──────────────────────────────
                _MilestoneStrip(familyId: familyId, dashboard: dash),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 1. Season banner
// ═══════════════════════════════════════════════════════════════════════

class _SeasonBanner extends StatelessWidget {
  const _SeasonBanner({required this.familyId, required this.dashboard});
  final String familyId;
  final GamingDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final season = dashboard.season!;
    final standings = dashboard.seasonStandings;
    final me = dashboard.me;
    final myStanding = standings.where((s) => s.userId == me.userId).toList();
    final myPoints = myStanding.isNotEmpty ? myStanding.first.points : 0;
    final myRank = myStanding.isNotEmpty
        ? standings.indexOf(myStanding.first) + 1
        : null;

    return GestureDetector(
      onTap: () => context.push('/family/$familyId/gaming/season'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF2A1A0E), Color(0xFF1C1410)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: KinrelColors.gold.withValues(alpha: 0.4)),
          boxShadow: [
            BoxShadow(
              color: KinrelColors.gold.withValues(alpha: 0.15),
              blurRadius: 18,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const Text('🏆', style: TextStyle(fontSize: 30)),
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
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: KinrelColors.brightGold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${season.daysRemaining} days left · '
                    '${myRank != null ? "you're #$myRank with" : "earn your first"} '
                    '$myPoints pts',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      color: KinrelColors.textSilver,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: KinrelColors.gold, size: 22),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 350.ms)
        .shimmer(delay: 600.ms, duration: 1200.ms, color: KinrelColors.gold.withValues(alpha: 0.08));
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 2. Quick stats row
// ═══════════════════════════════════════════════════════════════════════

class _QuickStatsRow extends StatelessWidget {
  const _QuickStatsRow({required this.familyId, required this.dashboard});
  final String familyId;
  final GamingDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final me = dashboard.me;
    final badgeCount = dashboard.myBadges.length;
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
            value: '${me.streakCurrent}',
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
          child: GestureDetector(
            onTap: () =>
                context.push('/family/$familyId/gaming/achievements'),
            child: GamingStatChip(
              emoji: '🏅',
              value: '$badgeCount',
              label: 'BADGES',
              color: const Color(0xFFD97706),
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 3. Challenge carousel
// ═══════════════════════════════════════════════════════════════════════

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
        message: 'You\'re a family gaming legend this week. New ones land Monday.',
      );
    }
    return SizedBox(
      height: 128,
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
            onTap: () =>
                context.push('/family/$familyId/gaming/challenges'),
            child: Container(
              width: 210,
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
                    size: 54,
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
                        Text(
                          '${c.icon} ${c.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: KinrelColors.textWhite,
                          ),
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
              .fadeIn(delay: (80 * i).ms, duration: 300.ms)
              .slideX(begin: 0.06, end: 0, duration: 300.ms);
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 4. Smart suggestions
// ═══════════════════════════════════════════════════════════════════════

class _SmartSuggestions extends StatelessWidget {
  const _SmartSuggestions({required this.familyId, required this.dashboard});
  final String familyId;
  final GamingDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final suggestions = dashboard.suggestions.take(3).toList();
    return Column(
      children: suggestions.map((s) {
        final game = gameByTable(s.gameTable);
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                if (game == null) return;
                context.push(gameRoute(game, familyId));
              },
              child: Ink(
                decoration: BoxDecoration(
                  color: KinrelColors.darkCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: game != null
                          ? Color(game.accent).withValues(alpha: 0.35)
                          : KinrelColors.orange.withValues(alpha: 0.35)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: game != null
                              ? GameIcon(gameId: game.gameId, size: 48)
                              : const Center(child: Text('🎮', style: TextStyle(fontSize: 22))),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${s.gameIcon} Play ${s.gameName} with ${s.userName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: KinrelColors.textWhite,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              s.reason,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 11,
                                color: KinrelColors.textDim,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: KinrelGradients.ignite,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Play',
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 5. Leaderboard preview
// ═══════════════════════════════════════════════════════════════════════

class _LeaderboardPreview extends StatelessWidget {
  const _LeaderboardPreview({required this.familyId, required this.dashboard});
  final String familyId;
  final GamingDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final entries = dashboard.leaderboard;
    final myUserId = dashboard.me.userId;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          if (entries.length >= 2) GamingPodium(entries: entries, myUserId: myUserId),
          const SizedBox(height: 6),
          ...entries.asMap().entries.take(4).map((e) {
            final i = e.key;
            final row = e.value;
            return GamingRankRow(
              rank: i + 1,
              userName: row.userName,
              points: row.points,
              matches: row.matches,
              wins: row.wins,
              streak: row.streakCurrent,
              winRateLabel: row.matches > 0 ? row.winRateLabel : null,
              isMe: row.userId == myUserId,
              onTap: () => context
                  .push('/family/$familyId/gaming/player/${row.userId}'),
            );
          }),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 6. Categorised game grid
// ═══════════════════════════════════════════════════════════════════════

class _CategorizedGameGrid extends ConsumerWidget {
  const _CategorizedGameGrid({
    required this.familyId,
    required this.expandedCategories,
    required this.onToggleCategory,
  });

  final String familyId;
  final Set<GameCategory> expandedCategories;
  final void Function(GameCategory) onToggleCategory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Kick off download-status checks for every game (once per hub visit).
    for (final g in kGameCatalog) {
      Future.microtask(() =>
          ref.read(gameDownloadStatusProvider(g.gameId).notifier).checkStatus());
    }

    return Column(
      children: [
        for (final category in GameCategory.values)
          _CategorySection(
            familyId: familyId,
            category: category,
            expanded: expandedCategories.contains(category),
            onToggle: () => onToggleCategory(category),
          ),
      ],
    );
  }
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.familyId,
    required this.category,
    required this.expanded,
    required this.onToggle,
  });

  final String familyId;
  final GameCategory category;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final games = gamesByCategory(category);
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Row(
                children: [
                  Text(category.emoji,
                      style: const TextStyle(fontSize: 15)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      category.label,
                      style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                        color: KinrelColors.textSilver,
                      ),
                    ),
                  ),
                  Text(
                    '${games.length}',
                    style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 11,
                      color: KinrelColors.textDim,
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: KinrelColors.textDim,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 240),
          crossFadeState: expanded
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          firstChild: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: games.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.12,
              ),
              itemBuilder: (context, i) => _GameGridCard(
                game: games[i],
                familyId: familyId,
              ),
            ),
          ),
          secondChild: const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// A single game card in the hub grid. The whole card is the tap target
/// (Fitts's Law) once downloaded; otherwise it downloads on tap.
class _GameGridCard extends ConsumerWidget {
  const _GameGridCard({required this.game, required this.familyId});
  final GameCatalogEntry game;
  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dlState = ref.watch(gameDownloadStatusProvider(game.gameId));
    final accent = Color(game.accent);
    final isDownloaded = dlState.status == GameDownloadStatus.downloaded;

    return GestureDetector(
      onTap: () {
        switch (dlState.status) {
          case GameDownloadStatus.downloaded:
            context.push(gameRoute(game, familyId));
            break;
          case GameDownloadStatus.notDownloaded:
          case GameDownloadStatus.failed:
            ref
                .read(gameDownloadStatusProvider(game.gameId).notifier)
                .download();
            break;
          default:
            break;
        }
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDownloaded
                ? accent.withValues(alpha: 0.45)
                : Colors.white.withValues(alpha: 0.06),
            width: isDownloaded ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: GameIcon(gameId: game.gameId, size: 44),
                  ),
                ),
                const Spacer(),
                _downloadIndicator(dlState, accent),
              ],
            ),
            const Spacer(),
            Text(
              game.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              game.playersLabel,
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 10,
                letterSpacing: 0.4,
                color: accent.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 250.ms)
        .scale(begin: const Offset(0.96, 0.96), end: const Offset(1, 1), duration: 250.ms);
  }

  Widget _downloadIndicator(GameDownloadState dlState, Color accent) {
    switch (dlState.status) {
      case GameDownloadStatus.notDownloaded:
        return Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.download_rounded, size: 15, color: accent),
        );
      case GameDownloadStatus.downloading:
        return SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: accent),
        );
      case GameDownloadStatus.downloaded:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            gradient: KinrelGradients.ignite,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            'PLAY',
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: Colors.white,
            ),
          ),
        );
      case GameDownloadStatus.failed:
        return Icon(Icons.refresh_rounded, size: 18, color: KinrelColors.error);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 7. Activity preview
// ═══════════════════════════════════════════════════════════════════════

class _ActivityPreview extends StatelessWidget {
  const _ActivityPreview({required this.dashboard});
  final GamingDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final activity = dashboard.activity.take(4).toList();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          for (final a in activity)
            GamingActivityTile(
              icon: a.icon,
              description: a.description,
              timeLabel: gamingTimeAgo(a.createdAt),
              accent: _accentFor(a.action),
            ),
        ],
      ),
    );
  }

  Color _accentFor(String action) {
    switch (action) {
      case 'game_badge_earned':
        return KinrelColors.brightGold;
      case 'game_challenge_completed':
        return const Color(0xFF8B5CF6);
      case 'game_milestone_reached':
        return KinrelColors.gold;
      case 'game_cup_won':
        return KinrelColors.brightGold;
      case 'game_sportsmanship':
        return KinrelColors.success;
      default:
        return KinrelColors.orange;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 8. Milestone strip
// ═══════════════════════════════════════════════════════════════════════

class _MilestoneStrip extends StatelessWidget {
  const _MilestoneStrip({required this.familyId, required this.dashboard});
  final String familyId;
  final GamingDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final total = dashboard.familyTotalMatches;
    final reached = dashboard.milestones.where((m) => m.isReached).length;

    // Next "games together" milestone target
    const thresholds = [1, 10, 25, 50, 100, 250, 500];
    final next = thresholds.where((t) => t > total).toList();
    final nextTarget = next.isNotEmpty ? next.first : 500;
    final prevTarget = thresholds.where((t) => t <= total).toList();
    final inRange = total - (prevTarget.isNotEmpty ? prevTarget.last : 0);
    final range = nextTarget - (prevTarget.isNotEmpty ? prevTarget.last : 0);

    return GestureDetector(
      onTap: () => context.push('/family/$familyId/gaming/milestones'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1E2029), Color(0xFF16181F)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: KinrelColors.amber.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('🎯', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Family Milestones',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                ),
                Text(
                  '$reached unlocked',
                  style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 11,
                    color: KinrelColors.amber,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Next: $nextTarget games played together',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: KinrelColors.textSilver,
              ),
            ),
            const SizedBox(height: 8),
            GamingProgressBar(
              progress: range <= 0 ? 1 : inRange / range,
              color: KinrelColors.amber,
            ),
            const SizedBox(height: 6),
            Text(
              '$total of $nextTarget games · keep playing as a family',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 10.5,
                color: KinrelColors.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Loading skeleton
// ═══════════════════════════════════════════════════════════════════════

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget block(double h) => Container(
          height: h,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: KinrelColors.darkCard,
            borderRadius: BorderRadius.circular(16),
          ),
        );
    return Column(
      children: [
        block(64),
        block(56),
        block(128),
        block(70),
        block(180),
      ],
    );
  }
}

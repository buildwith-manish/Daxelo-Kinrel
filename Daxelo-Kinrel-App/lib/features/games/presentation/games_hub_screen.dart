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
import '../shared/icons/kinrel_icons.dart';
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
            const KinrelIcon(KinrelIconData.users,
                size: 44, color: KinrelColors.orange),
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
                // ── Above-the-fold: 3 PRIMARY cards only ─────────────
                // Per the participation-over-competition reframe, the
                // home screen leads with exactly 3 cards so nobody is
                // overwhelmed by 7 simultaneous competing metrics:
                //   (1) Streak + Cup countdown combined
                //   (2) One CTA to play now
                //   (3) Collapsed leaderboard preview (rank + points)

                // (1) Streak + Cup countdown — combined card.
                _StreakAndCupCard(familyId: familyId, dashboard: dash),
                const SizedBox(height: 14),

                // (2) Play Now CTA.
                if (dash.suggestions.isNotEmpty) ...[
                  _PlayNowCta(familyId: familyId, dashboard: dash),
                  const SizedBox(height: 14),
                ],

                // (3) Collapsed leaderboard preview — rank + points only,
                //     expandable via the "View all" action.
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

                // ── Below the fold: secondary surfaces ───────────────
                // The full Quick Stats row (rank · streak · games · badges)
                // is intentionally NOT rendered above the fold anymore —
                // those four metrics are already represented inside the
                // streak/cup card and the leaderboard preview. Keeping
                // them below the fold keeps the above-the-fold surface to
                // exactly 3 primary cards.

                // Full Family Game Night streak card (with breathing flame
                // + best-streak facts) — secondary surface below the fold.
                _PlayStreakBanner(familyId: familyId),
                const SizedBox(height: 18),

                _QuickStatsRow(familyId: familyId, dashboard: dash),
                const SizedBox(height: 18),

                // ── Challenges (below the fold) ──────────────────────
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

                // Full Play Now list (more suggestions) — below the fold.
                if (dash.suggestions.length > 1) ...[
                  GamingSectionHeader(
                    title: 'More to Play',
                    subtitle: 'Family online — start a match together',
                    icon: Icons.bolt_rounded,
                  ),
                  _SmartSuggestions(familyId: familyId, dashboard: dash),
                  const SizedBox(height: 18),
                ],

                // ── Games grid (categorised) ──────────────────────────
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

                // ── Activity preview ──────────────────────────────────
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

                // ── Milestones strip ──────────────────────────────────
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
// 0. Family Game Night streak banner
//
//    Goal-Setting Theory as ritual: the streak rewards SHOWING UP
//    TOGETHER, never winning — so nobody dreads playing. Loss
//    aversion is deliberately soft-pedalled: a missed day never
//    scolds, the card simply waits for the next family game night.
// ═══════════════════════════════════════════════════════════════════════

class _PlayStreakBanner extends ConsumerWidget {
  const _PlayStreakBanner({required this.familyId});
  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streakAsync = ref.watch(familyPlayStreakProvider(familyId));
    return streakAsync.maybeWhen(
      data: (s) {
        if (!s.isVisible) return const SizedBox.shrink();
        return _StreakCard(streak: s);
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _StreakCard extends StatefulWidget {
  const _StreakCard({required this.streak});
  final FamilyPlayStreak streak;

  @override
  State<_StreakCard> createState() => _StreakCardState();
}

class _StreakCardState extends State<_StreakCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flame = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _flame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.streak;
    final alive = s.currentStreakDays > 0;

    // Copy — celebration when protected, gentle invite when not.
    String title;
    if (s.currentStreakDays >= 2) {
      title = s.playedToday
          ? '${s.currentStreakDays}-day streak — flame burning bright!'
          : '${s.currentStreakDays}-day Family Game Night streak!';
    } else if (s.currentStreakDays == 1) {
      title = s.playedToday
          ? 'Streak started today — keep it alive tomorrow!'
          : 'Your streak from last time is waiting for tonight';
    } else {
      title = 'Start a Family Game Night streak';
    }
    final String subtitle = s.playedToday
        ? 'Come back tomorrow and make it ${s.currentStreakDays + 1} — every night counts'
        : 'Play any game together today to ${alive ? 'make it ${s.currentStreakDays + 1} in a row' : 'light the first flame'}';

    final facts = <String>[
      if (s.bestStreakDays > 0) 'Best ${s.bestStreakDays} days',
      if (s.matchesThisWeek > 0)
        '${s.matchesThisWeek} ${s.matchesThisWeek == 1 ? 'game' : 'games'} this week',
      if (s.playersThisWeek > 0)
        '${s.playersThisWeek} ${s.playersThisWeek == 1 ? 'player' : 'players'} joined in',
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: s.playedToday
              ? const [Color(0xFF2B1A0E), Color(0xFF1D1409)]
              : const [Color(0xFF3B1D0A), Color(0xFF241207)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: s.playedToday
              ? KinrelColors.amber.withValues(alpha: 0.35)
              : KinrelColors.orange.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: (s.playedToday ? KinrelColors.amber : KinrelColors.orange)
                .withValues(alpha: 0.18),
            blurRadius: 26,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          // Flame medallion — breathing glow.
          ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.08).animate(
              CurvedAnimation(parent: _flame, curve: Curves.easeInOut),
            ),
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(-0.2, -0.3),
                  colors: [
                    (s.playedToday ? KinrelColors.amber : KinrelColors.orange)
                        .withValues(alpha: 0.55),
                    (s.playedToday ? KinrelColors.amber : KinrelColors.orange)
                        .withValues(alpha: 0.12),
                  ],
                ),
                border: Border.all(
                  color: (s.playedToday
                          ? KinrelColors.amber
                          : KinrelColors.orange)
                      .withValues(alpha: 0.6),
                ),
              ),
              child: const Center(
                child: KinrelIcon(KinrelIconData.flame,
                    size: 24, color: KinrelColors.brightGold),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: KinrelColors.textWhite,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 11.5,
                    color: KinrelColors.textSilver,
                    height: 1.25,
                  ),
                ),
                if (facts.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final f in facts)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            f,
                            style: TextStyle(
                              fontFamily: KinrelTypography.monoFont,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                              color: KinrelColors.amber.withValues(alpha: 0.9),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 450.ms)
        .slideY(begin: -0.04, end: 0, duration: 450.ms);
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 0b. Combined Streak + Cup card — the #1 above-the-fold surface.
//
//     Folds the previous two separate cards (Family Game Night streak
//     + Family Cup season banner) into a single above-the-fold card so
//     the home screen presents exactly 3 primary cards (streak/cup,
//     play-now CTA, leaderboard preview) instead of 7 competing metrics.
//
//     The card is collaborative by design: "Family Game Night streak"
//     means anyone playing keeps it alive — never a personal loss record.
// ═══════════════════════════════════════════════════════════════════════

class _StreakAndCupCard extends ConsumerWidget {
  const _StreakAndCupCard({required this.familyId, required this.dashboard});
  final String familyId;
  final GamingDashboard dashboard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streakAsync = ref.watch(familyPlayStreakProvider(familyId));
    return streakAsync.maybeWhen(
      data: (s) {
        final season = dashboard.season;
        final me = dashboard.me;
        // Compose the headline.
        String streakLine;
        if (s.currentStreakDays >= 2) {
          streakLine = s.playedToday
              ? '${s.currentStreakDays}-day Family Game Night streak — flame burning bright!'
              : '${s.currentStreakDays}-day Family Game Night streak — play tonight to keep it alive';
        } else if (s.currentStreakDays == 1) {
          streakLine = 'Streak started — play tonight to make it 2 in a row';
        } else if (s.matchesThisWeek > 0) {
          streakLine = 'Your family played this week — start a streak tonight';
        } else {
          streakLine = 'Start a Family Game Night streak tonight';
        }
        final cupLine = season != null
            ? (me.points > 0
                ? '${season.daysRemaining}d left in ${season.name} · you\'re #${me.rank > 0 ? me.rank : '—'} with ${me.points} pts'
                : '${season.daysRemaining}d left in ${season.name} · play to earn Cup points')
            : null;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: s.playedToday
                  ? const [Color(0xFF2B1A0E), Color(0xFF1D1409)]
                  : const [Color(0xFF3B1D0A), Color(0xFF241207)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: s.playedToday
                  ? KinrelColors.amber.withValues(alpha: 0.35)
                  : KinrelColors.orange.withValues(alpha: 0.5),
            ),
            boxShadow: [
              BoxShadow(
                color: (s.playedToday
                        ? KinrelColors.amber
                        : KinrelColors.orange)
                    .withValues(alpha: 0.18),
                blurRadius: 26,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              // Flame medallion (no animation here — the dedicated streak
              // banner below the fold still has the breathing flame).
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: const Alignment(-0.2, -0.3),
                    colors: [
                      (s.playedToday
                              ? KinrelColors.amber
                              : KinrelColors.orange)
                          .withValues(alpha: 0.55),
                      (s.playedToday
                              ? KinrelColors.amber
                              : KinrelColors.orange)
                          .withValues(alpha: 0.12),
                    ],
                  ),
                  border: Border.all(
                    color: (s.playedToday
                            ? KinrelColors.amber
                            : KinrelColors.orange)
                        .withValues(alpha: 0.6),
                  ),
                ),
                child: const Center(
                  child: KinrelIcon(KinrelIconData.flame,
                      size: 22, color: KinrelColors.brightGold),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      streakLine,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: KinrelColors.textWhite,
                        height: 1.25,
                      ),
                    ),
                    if (cupLine != null) ...[
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: () =>
                            context.push('/family/$familyId/gaming/season'),
                        child: Row(
                          children: [
                            const KinrelIcon(KinrelIconData.trophy,
                                size: 13, color: KinrelColors.brightGold),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                cupLine,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: KinrelTypography.bodyFont,
                                  fontSize: 11.5,
                                  color: KinrelColors.textSilver,
                                ),
                              ),
                            ),
                            const Icon(Icons.chevron_right,
                                size: 16, color: KinrelColors.gold),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        )
            .animate()
            .fadeIn(duration: 350.ms)
            .slideY(begin: -0.03, end: 0, duration: 350.ms);
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 0c. Play Now CTA — the #2 above-the-fold surface.
//
//     A single primary CTA that takes the viewer straight into a match
//     with a family member who's online. Replaces the longer "Play Now"
//     suggestions list as the above-the-fold version (the full list is
//     still rendered below the fold via _SmartSuggestions when expanded).
// ═══════════════════════════════════════════════════════════════════════

class _PlayNowCta extends StatelessWidget {
  const _PlayNowCta({required this.familyId, required this.dashboard});
  final String familyId;
  final GamingDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final s = dashboard.suggestions.first;
    final game = gameByTable(s.gameTable);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          if (game == null) return;
          context.push(gameRoute(game, familyId));
        },
        child: Ink(
          decoration: BoxDecoration(
            gradient: KinrelGradients.ignite,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: KinrelColors.orange.withValues(alpha: 0.35),
                blurRadius: 22,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: game != null
                        ? GameIcon(gameId: game.gameId, size: 44)
                        : const Center(
                            child: KinrelIcon(KinrelIconData.controller,
                                size: 20, color: Colors.white),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Play ${s.gameName} with ${s.userName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        s.reason,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 11.5,
                          color: Colors.white.withValues(alpha: 0.88),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Play',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: KinrelColors.orange,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(delay: 100.ms, duration: 350.ms)
        .slideY(begin: 0.04, end: 0, duration: 350.ms);
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 1. Season banner  (kept for the season screen; no longer rendered on hub)
// ═══════════════════════════════════════════════════════════════════════

// ignore: unused_element
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
            const KinrelIcon(KinrelIconData.trophy,
                size: 30, color: KinrelColors.brightGold),
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
                    myPoints > 0
                        ? '${season.daysRemaining} days left · '
                          '${myRank != null ? "you're #$myRank with" : "you have"} '
                          '$myPoints pts'
                        : '${season.daysRemaining} days left · '
                          'play a match to earn Cup points',
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
                              : const Center(
                                  child: KinrelIcon(
                                      KinrelIconData.controller,
                                      size: 22,
                                      color: KinrelColors.orange),
                                ),
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
              // Streak is only surfaced for the viewer's own row. The row
              // widget also double-gates this on isMe.
              streak: row.userId == myUserId ? row.streakCurrent : 0,
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
                  KinrelIcon(
                    kinrelIconFromEmoji(category.emoji) ??
                        KinrelIconData.controller,
                    size: 15,
                    color: KinrelColors.orange,
                  ),
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
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent.withValues(alpha: isDownloaded ? 0.14 : 0.05),
              KinrelColors.darkCard,
              KinrelColors.darkCard,
            ],
            stops: const [0.0, 0.45, 1.0],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDownloaded
                ? accent.withValues(alpha: 0.45)
                : Colors.white.withValues(alpha: 0.06),
            width: isDownloaded ? 1.5 : 1,
          ),
          boxShadow: isDownloaded
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.16),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Icon plate — accent halo behind the glossy game icon.
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: RadialGradient(
                      center: const Alignment(-0.4, -0.4),
                      radius: 1.1,
                      colors: [
                        accent.withValues(alpha: 0.34),
                        accent.withValues(alpha: 0.05),
                      ],
                    ),
                    border: Border.all(
                      color: accent.withValues(alpha: 0.22),
                      width: 1,
                    ),
                  ),
                  padding: const EdgeInsets.all(3),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: GameIcon(gameId: game.gameId, size: 44),
                    ),
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
            Row(
              children: [
                Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(alpha: 0.9),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.6),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    game.playersLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 10,
                      letterSpacing: 0.4,
                      color: accent.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ],
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
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            value: (dlState.progress >= 0 && dlState.progress <= 1)
                ? dlState.progress
                : null,
            strokeCap: StrokeCap.round,
            color: accent,
          ),
        );
      case GameDownloadStatus.downloaded:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            gradient: KinrelGradients.ignite,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: KinrelColors.orange.withValues(alpha: 0.4),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
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
                const KinrelIcon(KinrelIconData.flag,
                    size: 18, color: KinrelColors.amber),
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

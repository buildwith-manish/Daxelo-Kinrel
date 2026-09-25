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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../family/presentation/add_member_options_sheet.dart';
import '../../family/presentation/family_space_floating_nav.dart';
import '../../family/presentation/premium/family_hub_sections.dart';
import '../../gaming_ecosystem/data/gaming_models.dart';
import '../../gaming_ecosystem/data/gaming_providers.dart';
import '../../gaming_ecosystem/presentation/widgets/gaming_kit.dart';
import '../shared/icons/kinrel_icons.dart';
import '../retention/coin_balance_chip.dart';
import '../retention/live_presence_strip.dart';
import 'widgets/family_streak_hero_card.dart';
import 'widgets/family_moment_card.dart';
import 'widgets/play_with_row.dart';
import 'widgets/quick_picks_row.dart';
import 'widgets/not_yet_played_prompt.dart';

class GamesHubScreen extends ConsumerStatefulWidget {
  const GamesHubScreen({super.key, this.familyId});
  final String? familyId;

  @override
  ConsumerState<GamesHubScreen> createState() => _GamesHubScreenState();
}

class _GamesHubScreenState extends ConsumerState<GamesHubScreen> {
  String? _resolvedFamilyId;
  bool _resolving = true;

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

  /// Navigate back to Family Space (the parent). Family Arena is a
  /// child of Family Space, so back must NEVER land on Home — even if
  /// the route was opened via a deep-link / cold start (where there's
  /// nothing to pop to). When the stack has a parent, pop; otherwise
  /// explicitly go to /family/<id> (Family Space overview). Only fall
  /// back to /home when no family context is available at all.
  void _backToFamilySpace() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    final fid = widget.familyId ?? _resolvedFamilyId;
    if (fid != null && fid.isNotEmpty) {
      context.go('/family/$fid');
    } else {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final familyId = _resolvedFamilyId;
    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      // PopScope ties the Android hardware-back button to the same
      // logic as the AppBar back arrow — both must return to Family
      // Space, never to Home. canPop=true means a parent is on the
      // stack → Framework pops automatically; canPop=false triggers
      // our onPopInvokedWithResult callback where we route to
      // /family/<id> explicitly.
      body: PopScope(
        canPop: context.canPop(),
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _backToFamilySpace();
        },
        child: _resolving
            ? const Center(
                child: CircularProgressIndicator(color: KinrelColors.orange))
            : familyId == null
                ? _NoFamilyState()
                : _GamingDashboardBody(familyId: familyId),
      ),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _backToFamilySpace,
        ),
        title: const Text(
          'Family Arena',
          style: const TextStyle(
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
    );
  }
}

class _NoFamilyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            KinrelIcon(KinrelIconData.users,
                size: 44, color: KinrelColors.orange),
            SizedBox(height: 12),
            const Text(
              'Create your family to unlock the Arena',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
            SizedBox(height: 8),
            const Text(
              'Games, challenges, leaderboards and cups live inside your family space.',
              textAlign: TextAlign.center,
              style: const TextStyle(
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
  const _GamingDashboardBody({required this.familyId});

  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashAsync = ref.watch(gamingDashboardProvider(familyId));

    return RefreshIndicator(
      color: KinrelColors.orange,
      backgroundColor: KinrelColors.darkCard,
      onRefresh: () async {
        ref.invalidate(gamingDashboardProvider(familyId));
        await ref.read(gamingDashboardProvider(familyId).future);
        ref.invalidate(playWithSuggestionsProvider(familyId));
        ref.invalidate(familyMomentsProvider(familyId));
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            KinrelSpacing.base, KinrelSpacing.base, KinrelSpacing.base, 120),
        children: [
          // ── Live presence + coin balance ──────────────────────────
          // Replaces the old static presence strip with a live avatar
          // row + coin balance chip. The coin chip is also tappable to
          // open the Rewards Shop.
          Row(
            children: [
              Expanded(child: LivePresenceStrip(familyId: familyId)),
              CoinBalanceChip(familyId: familyId),
            ],
          ),
          const SizedBox(height: 14),

          // ═══════════════════════════════════════════════════════════════
          // ZONE 1: HERO CARD — single source of truth for streak + cup
          // ═══════════════════════════════════════════════════════════════
          // Replaces the previous duplicate streak banners + the standalone
          // #1 FAMILY RANK / WIN STREAK / GAMES / BADGES stat-chip row +
          // the "This Week's Challenges" ring widgets from the home surface.
          // All of that content now lives one tap away in the
          // FamilyStatsDetailSheet (opened by tapping the hero card).
          FamilyStreakHeroCard(familyId: familyId),
          const SizedBox(height: 18),

          // ═══════════════════════════════════════════════════════════════
          // ZONE 2: PLAY WITH — people-first suggestions
          // ═══════════════════════════════════════════════════════════════
          // Replaces the flat game-icon grid as the primary above-the-fold
          // content. People motivate more than icons.
          PlayWithRow(familyId: familyId),
          const SizedBox(height: 18),

          // ═══════════════════════════════════════════════════════════════
          // ZONE 2b: INVITE FAMILY (Reciprocity)
          // ═══════════════════════════════════════════════════════════════
          // A prominent, one-tap "Invite family member" banner right below
          // the people-first Play With row. Giving an invite FIRST (before
          // asking for anything) triggers reciprocity — invited family
          // members are far more likely to join and play.
          _InviteFamilyBanner(familyId: familyId),
          const SizedBox(height: 18),

          // ═══════════════════════════════════════════════════════════════
          // ZONE 2c: QUICK PICKS — game discovery row
          // ═══════════════════════════════════════════════════════════════
          // Curated horizontal-scroll row of games the family has played
          // most in the last 30 days, with a default backfill. Excludes
          // any game already suggested in the Play With row above.
          QuickPicksRow(familyId: familyId),
          const SizedBox(height: 8),

          // "Browse all games →" link to the secondary All Games screen.
          _BrowseAllGamesLink(familyId: familyId),
          const SizedBox(height: 18),

          // ═══════════════════════════════════════════════════════════════
          // ZONE 2d: GAMES SECTION — Play/Leaderboard toggle
          // ═══════════════════════════════════════════════════════════════
          // Moved here from the Family Space hub per user request. All
          // game-related content (active games, categorized game catalog,
          // leaderboard) now lives exclusively on this dedicated Games
          // screen — not on the Family home page.
          //   • ActiveGamesList — live rooms with Zeigarnik "Your turn"
          //     pulse badge.
          //   • Hick's-Law grouped games row (Quick Play / Classic Board /
          //     Family Fun) with duration + complexity labels + social
          //     proof micro-labels.
          //   • Play/Leaders toggle — leaderboard with loss-aversion gap
          //     notices.
          GamesSection(familyId: familyId),
          const SizedBox(height: 18),

          // ═══════════════════════════════════════════════════════════════
          // ZONE 3: FAMILY MOMENTS — promoted to second position, restyled
          // ═══════════════════════════════════════════════════════════════
          // Moved up from the bottom of the scroll. Restyled as a feed
          // with avatar + reactions + date group headers. Tapping "View
          // all" opens the full activity feed screen.
          GamingSectionHeader(
            title: 'Family Moments',
            subtitle: 'Every game becomes a memory',
            icon: Icons.favorite_outline,
            actionLabel: 'View all',
            onAction: () =>
                context.push('/family/$familyId/gaming/activity'),
          ),
          _FamilyMomentsPreview(familyId: familyId),
          const SizedBox(height: 22),

          // ═══════════════════════════════════════════════════════════════
          // ZONE 4 (below fold): participation-based leaderboard + milestones
          // ═══════════════════════════════════════════════════════════════
          dashAsync.when(
            loading: () => const _DashboardSkeleton(),
            error: (e, _) => const GamingEmptyCard(
              emoji: '🔌',
              title: 'Could not load your Arena',
              message: 'Check your connection and pull to refresh.',
            ),
            data: (dash) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (dash.leaderboard.isNotEmpty) ...[
                  GamingSectionHeader(
                    title: 'Family Leaderboard',
                    // Updated subtitle: participation-framed (no more
                    // "earns points" language since we removed the points
                    // chip from the leaderboard UI).
                    subtitle: 'Every game counts — see who\'s playing the most',
                    icon: Icons.leaderboard_outlined,
                    actionLabel: 'View all',
                    onAction: () => context.push(
                        '/family/$familyId/gaming/leaderboard'),
                  ),
                  _LeaderboardPreview(familyId: familyId, dashboard: dash),
                  const SizedBox(height: 18),
                ],
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
// Zone 2b helper: Invite Family banner (Reciprocity principle)
// ═══════════════════════════════════════════════════════════════════════

/// Prominent one-tap invite CTA. The whole banner opens the standard
/// add-member flow (Find on Kinrel / Add manually), so inviting a family
/// member to the Arena is a single tap from the games hub.
class _InviteFamilyBanner extends StatelessWidget {
  const _InviteFamilyBanner({required this.familyId});
  final String familyId;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showAddMemberOptions(context, familyId: familyId),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFE8612A), Color(0xFFF59240)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFE8612A).withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.35),
                  width: 1.2,
                ),
              ),
              child: const Icon(
                Icons.card_giftcard_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Invite family member',
                    style: const TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    'The Arena is better with everyone — one tap to invite',
                    style: const TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 11.5,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person_add_alt_1_rounded,
                      size: 15, color: Color(0xFFE8612A)),
                  SizedBox(width: 5),
                  Text(
                    'Invite',
                    style: const TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFE8612A),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Zone 2 helper: "Browse all games →" link to the secondary All Games screen.
// ═══════════════════════════════════════════════════════════════════════

class _BrowseAllGamesLink extends StatelessWidget {
  const _BrowseAllGamesLink({required this.familyId});
  final String familyId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: GestureDetector(
          onTap: () => context.push('/family/$familyId/gaming/all-games'),
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: KinrelColors.darkCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: KinrelColors.orange.withValues(alpha: 0.25)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                KinrelIcon(KinrelIconData.controller,
                    size: 13, color: KinrelColors.orange),
                SizedBox(width: 6),
                const Text(
                  'Browse all games',
                  style: const TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.orange,
                  ),
                ),
                SizedBox(width: 4),
                Icon(Icons.chevron_right,
                    size: 16, color: KinrelColors.orange),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Zone 3 helper: Family Moments preview — top 3 moments with reactions,
// grouped by date via MomentDateGroupWidget.
//
// Fetches via familyMomentsProvider (fn_get_family_gaming_activity_v2),
// which returns reaction counts + the viewer's own reactions per moment.
// Each moment is rendered with the FamilyMomentCard widget, wrapped in
// MomentDateGroupWidget so the date header (Today / Yesterday / Sep 15)
// renders once per group — not repeated per-entry as "1d ago".
// ═══════════════════════════════════════════════════════════════════════

class _FamilyMomentsPreview extends ConsumerWidget {
  const _FamilyMomentsPreview({required this.familyId});
  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(familyMomentsProvider(familyId));
    return async.when(
      loading: () => const SizedBox(
        height: 100,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: KinrelColors.orange,
            ),
          ),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (moments) {
        if (moments.isEmpty) {
          return const GamingEmptyCard(
            emoji: '✨',
            title: 'No family moments yet',
            message: 'Wins, badges, milestones and cheers from your family\'s '
                'games will appear here.',
          );
        }
        // Take top 3 — the home surface shows a preview; the full feed is
        // one tap away via "View all". Then group by date so the header
        // renders once per group.
        final previewMoments = moments.take(3).toList();
        final groups = groupMomentsByDate(previewMoments);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final g in groups)
              MomentDateGroupWidget(group: g, familyId: familyId),
          ],
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Zone 4 helper: Leaderboard preview (kept from the prior reframe, with
// zero-state fix — members with 0 games show "Just joined" instead of
// "0 pts" so the home surface never shows a bare zero).
// ═══════════════════════════════════════════════════════════════════════

class _LeaderboardPreview extends ConsumerWidget {
  const _LeaderboardPreview({required this.familyId, required this.dashboard});
  final String familyId;
  final GamingDashboard dashboard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Use the v3 participation-based leaderboard: ranked rows sorted by
    // games_played DESC (NOT points), plus a separate notYetPlayed list
    // for members who haven't played any games. The points chip is
    // hidden entirely on ranked rows — the spec removes it.
    final key = LeaderboardKey(familyId: familyId, period: 'all_time');
    final async = ref.watch(participationLeaderboardProvider(key));

    return async.when(
      loading: () => Container(
        height: 120,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: KinrelColors.orange,
            ),
          ),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (lb) {
        final myUserId = dashboard.me.userId;
        final ranked = lb.ranked.take(4).toList();
        if (ranked.isEmpty && lb.notYetPlayed.isEmpty) {
          return const SizedBox.shrink();
        }
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: KinrelColors.darkCard,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (ranked.length >= 2)
                GamingPodium(entries: ranked, myUserId: myUserId),
              if (ranked.length >= 2) const SizedBox(height: 6),
              for (var i = 0; i < ranked.length; i++)
                GamingRankRow(
                  rank: i + 1,
                  userName: ranked[i].userName,
                  points: ranked[i].points,
                  matches: ranked[i].matches,
                  // Streak is only surfaced for the viewer's own row.
                  streak: ranked[i].userId == myUserId
                      ? ranked[i].streakCurrent
                      : 0,
                  isMe: ranked[i].userId == myUserId,
                  // Participation-based leaderboard: hide the points chip
                  // entirely. The row shows "Played N games together" via
                  // the participation line.
                  hideScoreChip: true,
                  onTap: () => context.push(
                      '/family/$familyId/gaming/player/${ranked[i].userId}'),
                ),
              if (lb.notYetPlayed.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Padding(
                  padding: EdgeInsets.only(bottom: 6, left: 2),
                  child: const Text(
                    'Not playing yet',
                    style: const TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: KinrelColors.amber,
                    ),
                  ),
                ),
                for (final m in lb.notYetPlayed.take(3))
                  NotYetPlayedPrompt(
                    member: NotYetPlayedMemberData(
                      userId: m.userId,
                      userName: m.userName,
                      avatarUrl: m.avatarUrl,
                    ),
                    familyId: familyId,
                  ),
              ],
            ],
          ),
        );
      },
    );
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
                const Expanded(
                  child: const Text(
                    'Family Milestones',
                    style: const TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                ),
                Text(
                  '$reached unlocked',
                  style: const TextStyle(
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
              style: const TextStyle(
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
              style: const TextStyle(
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

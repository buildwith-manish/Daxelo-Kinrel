// lib/features/home/presentation/home_screen.dart
//
// DAXELO KINREL — Home Dashboard Screen (The Command Center)
//
// Orange K-Graph DNA redesign:
//   • Sticky Header: K-graph mini icon + time-based greeting + @username + avatar
//   • Family Switcher: horizontal scroll with + Add + family avatars (Ignite gradient)
//   • Hero Family Card: radial gradient bg, orange glow, dotted K-graph pattern
//   • Family Feed: Instagram-style vertical feed (replaces Recent Activity + Family at a Glance)
//
// Uses KinrelColors (orange #E8612A / amber #F59240 / ember #C44A18),
// KinrelTypography, KinrelSpacing, KinrelGradients, flutter_animate.
// Dark mode is the primary experience.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../notifications/providers/notifications_provider.dart';
import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/family/family_provider.dart';
// v5.215 (unified add-member entry-point fix): the Home screen's two
// "Add Member" / "Add family member" entry points (more-menu item +
// quick-action chip) now skip straight to Find on Kinrel search,
// matching the other non-Graph entry points. "Add Manually" remains
// reachable only from the Family Graph screen.
import '../../../features/family/presentation/find_on_kinrel_flow.dart'
    show openFindOnKinrelFlow;
import '../../../shared/widgets/kinrel_icon.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../../shared/widgets/kinrel_skeleton.dart';
import '../../../shared/widgets/kinrel_empty_state.dart';
import 'widgets/compact_family_switcher.dart';
import 'widgets/continue_with_family_card.dart';
import 'widgets/kinship_ring_row.dart';
import 'widgets/streak_badge.dart';
// Phase B — Today's Question card inserts into the Phase B slot in
// _buildUnifiedHomeView. Surfaces one curated prompt per cycle with
// a tap-to-start/stop mic button + preview + Save/Discard.
import '../../todays_question/presentation/todays_question_card.dart';
// Phase A — Home, the Instagram-level idea:
// The leading "You / Add yours" item in the kinship ring row opens
// /sparq/create (the existing Sparq composer) — per the user's
// Phase A decision, we do NOT revive the legacy add_story_sheet /
// stories system. The Sparq feature is the existing story-like
// surface and is what the ring row should launch.
import '../../family/presentation/join_family_screen.dart';
import '../../feed/presentation/widgets/feed_post_card.dart';
import '../../feed/providers/feed_provider.dart';
import '../../occasions/providers/occasion_reminders_provider.dart';
import '../../occasions/widgets/upcoming_occasions_row.dart';
import '../../social/data/providers/sparq_provider.dart' show sparqProvider;
import '../../../core/utils/accessibility_utils.dart';
import '../../../core/theme/kinrel_fx.dart';

// ── Color shortcuts for the Command Center ──────────────────────
const _cOrange = KinrelColors.orange; // #E8612A
const _cBg = KinrelColors.darkBackground; // #131416
const _cCard = KinrelColors.darkCard; // #191B2C
const _cElevated = KinrelColors.darkElevated; // #202338
const _cTextPrimary = KinrelColors.textWhite; // #F5F0EE
const _cTextSecondary = KinrelColors.textSilver; // #C9B4A8
const _cTextDim = KinrelColors.textDim; // #8A7A72

class HomeScreen extends ConsumerStatefulWidget {
  HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _feedScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _feedScrollController.addListener(_onFeedScroll);
    // Load home feed on init
    Future.microtask(() {
      if (mounted) {
        ref.read(homeFeedProvider.notifier).loadHomeFeed().catchError((_) {});
      }
    });
  }

  @override
  void dispose() {
    _feedScrollController.removeListener(_onFeedScroll);
    _feedScrollController.dispose();
    super.dispose();
  }

  void _onFeedScroll() {
    if (_feedScrollController.position.pixels >=
        _feedScrollController.position.maxScrollExtent - 200) {
      ref.read(homeFeedProvider.notifier).loadMoreHome();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required by AutomaticKeepAliveClientMixin
    final familiesAsync = ref.watch(familyListProvider);
    final user = ref.watch(currentUserProvider);
    // Extract families for the FAB's quick-add sheet (available even
    // during loading — the sheet handles the empty case gracefully).
    final families = familiesAsync.valueOrNull ?? [];

    return DKScaffold(
      backgroundColor: _cBg,
      body: familiesAsync.when(
        loading: () => _buildLoadingState(),
        error: (error, _) => DKErrorState(
          message: error.toString(),
          onRetry: () => ref.invalidate(familyListProvider),
        ),
        data: (families) {
          if (families.isEmpty) {
            return _buildNoFamiliesView(user);
          }
          return _buildUnifiedHomeView(user, families);
        },
      ),
      floatingActionButton: FloatingActionButton(
        // KIN-03 FIX: FAB now opens a quick-add bottom sheet with
        // kinship-mapping actions in priority order, instead of
        // jumping directly to /post/create (social post composer).
        // The audit identified the post-create FAB as a Critical
        // misdirection of the app's most prominent control away
        // from its core value proposition.
        onPressed: () {
          // ── Haptic on FAB — primary CTA gets the standard tap haptic.
          HapticService.tap();
          _showQuickAddSheet(context, families);
        },
        backgroundColor: _cOrange,
        elevation: (KinrelFx.rich ? 4 : 0),
        shape: const CircleBorder(),
        child: const Icon(Icons.add, size: 28, color: Colors.white),
      ),
    );
  }

  // ── Loading state — shimmer placeholders ──────────────────────
  Widget _buildLoadingState() {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          // Header shimmer
          const Row(
            children: [
              KinrelIcon(size: 20),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KinrelSkeletonBox(width: 80, height: 12),
                    SizedBox(height: 6),
                    KinrelSkeletonBox(width: 140, height: 18),
                  ],
                ),
              ),
              KinrelSkeletonBox(width: 36, height: 36, radius: 18),
            ],
          ),
          const SizedBox(height: 24),
          // Family switcher shimmer
          SizedBox(
            height: 76,
            child: Row(
              children: List.generate(
                5,
                (_) => const Padding(
                  padding: EdgeInsets.only(right: 14),
                  child: KinrelSkeletonBox(width: 52, height: 52, radius: 26),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Hero card shimmer
          const KinrelSkeletonBox(width: double.infinity, height: 160, radius: 18),
          const SizedBox(height: 20),
          // Feed shimmer
          const KinrelSkeletonBox(width: 120, height: 18),
          const SizedBox(height: 12),
          ...List.generate(
            2,
            (_) => const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: KinrelSkeletonBox(
                width: double.infinity,
                height: 280,
                radius: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── No families — empty state ─────────────────────────────────
  Widget _buildNoFamiliesView(dynamic user) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: Column(
        children: [
          const SizedBox(height: 24),
          // Phase A: pass an empty families list — CompactFamilySwitcher
          // renders a "Create family" affordance in this state.
          const _StickyHeader(user: null, families: const <Family>[]),
          const SizedBox(height: 48),
          // ── Migrated to KinrelEmptyState ──
          // Adds BounceButton + haptic + teaching subtitle. The secondary
          // CTA ('Join by Code') replaces the separate TextButton below.
          KinrelEmptyState(
            icon: Icons.family_restroom_outlined,
            title: 'No Families Yet',
            subtitle:
                'Create your first family to start building your kinship graph',
            actionLabel: 'Create Family',
            onAction: () => context.push('/families/create'),
            secondaryLabel: 'Join by Code',
            onSecondary: () => _showJoinFamilyDialog(context),
          ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0),
          const SizedBox(height: 16),
          semanticLink(
            label: 'Join an existing family with a code',
            child: TextButton(
              onPressed: () => _showJoinFamilyDialog(context),
              child: const Text(
                'Or join an existing family with a code',
                style: TextStyle(
                  color: _cOrange,
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  decoration: TextDecoration.underline,
                  decorationColor: _cOrange,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Has families — show Unified Home Feed ────────────────────────
  // Phase A — Home, the Instagram-level idea:
  //   Reorder to match the mockup. From top to bottom:
  //     1. Sticky header (K-icon wordmark + CompactFamilySwitcher
  //        pill + Streak badge + Notification bell).
  //     2. Compact greeting secondary line (greeting + @username —
  //        moved out of the sticky header to free header real
  //        estate for the family switcher).
  //     3. KinshipRingRow (the Instagram-level idea): leading
  //        "You / Add yours" + one item per relative, with the
  //        kinship TERM as the bold primary label and first name
  //        as the secondary line.
  //     4. [Phase B slot — TodaysQuestionCard will be inserted
  //         here. Left as a clearly-marked TODO so Phase B can drop
  //         it in without touching the surrounding order.]
  //     5. ContinueWithFamilyCard (kept — the WhatsApp/Telegram
  //        "open to last chat" pattern).
  //     6. UpcomingOccasionsRow (kept — birthday strip).
  //     7. Home Feed section header + SliverList of FeedPostCard.
  //
  // Removed from Home (Phase A):
  //   • _HeroFamilyCard — the family name, member/link/generation
  //     stats, and the 3 quick-action chips (Graph / Add Member /
  //     Wall). All three actions remain reachable from the Family
  //     tab → family_detail_screen.dart:
  //       - Graph:        family_detail_screen hero's flanking Graph
  //                       icon (line 292 of that file).
  //       - Add Member:   family_detail_screen's "Add Member" entry
  //                       (line 533 — uses Find on Kinrel flow).
  //       - Wall:         family_detail_screen's "Post to family
  //                       wall" action in the family activity hub.
  //     The widget class _HeroFamilyCard is preserved in this file
  //     for future reuse (e.g. inside family_detail_screen as a
  //     "Family summary" header); it's simply not rendered on Home
  //     anymore.
  //   • Inline _FamilySwitcherRow / FamilySparqTray — replaced by
  //     CompactFamilySwitcher in the sticky header. The widget
  //     classes are kept; only Home's rendering of them is removed.
  Widget _buildUnifiedHomeView(dynamic user, List<Family> families) {
    final primaryFamily = families.first;
    final feedState = ref.watch(homeFeedProvider);

    return RefreshIndicator(
      color: _cOrange,
      backgroundColor: _cCard,
      onRefresh: () async {
        ref.invalidate(familyListProvider);
        ref.invalidate(homeFeedProvider);
        // Spec section 5: Home pull-to-refresh should call
        // refreshFeed() in place of the stories invalidate. The tray
        // rebuilds off sparqProvider's feed list identity.
        await ref.read(sparqProvider.notifier).refreshFeed();
      },
      child: CustomScrollView(
        controller: _feedScrollController,
        physics: const BouncingScrollPhysics(),
        slivers: [
          // Sticky Header — K-icon wordmark + CompactFamilySwitcher
          // + Streak + Notification bell.
          SliverPersistentHeader(
            pinned: true,
            delegate: _StickyHeaderDelegate(user: user, families: families),
          ),

          // Main content
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Compact greeting secondary line — moved out of the
                // sticky header so the header can fit the family
                // switcher pill. Scrolls away with the content (not
                // sticky) which matches the mockup.
                _CompactGreeting(user: user)
                    .animate()
                    .fadeIn(duration: 300.ms, delay: 50.ms),

                const SizedBox(height: 8),

                // ── Kinship Ring Row (Instagram-level idea) ──────────
                // Leading "You / Add yours" + one item per relative,
                // with the kinship TERM as the bold primary label
                // (e.g. "Mausi") and the person's first name as the
                // small secondary line (e.g. "Priya"). Ring gradient
                // when unseen, dim when seen. Birthday badge "3d"
                // when occasionRemindersProvider says their birthday
                // is within 7 days.
                //
                // The row watches the precomputed
                // kinshipTermsForFamilyProvider(familyId) — terms are
                // resolved off the UI thread (compute() isolate) and
                // cached. No per-avatar kinship lookups in build().
                //
                // When the viewer has no relatives yet (graph has
                // only the viewer's own node), the row returns a
                // zero-height SizedBox — and we render the "Next
                // step" invite card in its place. The invite card
                // reuses the existing KinrelEmptyState widget
                // (same component Home's no-families view uses) so
                // the visual language stays consistent.
                KinshipRingRow(
                  familyId: primaryFamily.id,
                  onAddYours: () {
                    HapticService.tap();
                    // Phase A decision: open the Sparq composer, not
                    // the legacy add_story_sheet. The Sparq feature
                    // is the existing story-like surface.
                    context.push('/sparq/create');
                  },
                )
                    .animate()
                    .fadeIn(duration: 350.ms, delay: 80.ms)
                    .slideY(begin: -0.03, end: 0),

                // ── Today's Question card (Phase B) ──────────────────────
                // Phase B — surfaces one curated prompt + a one-tap mic
                // button. Tap-to-start/stop (NOT press-and-hold —
                // elders struggle with it). Max 3 min. Preview with
                // Play/Save/Discard. First-time consent notice per
                // (familyId, elderPersonId). Reuses the existing
                // OralHistoryNotifier recorder + upload path (no
                // third recorder). After Save or Skip, hides until
                // the next cycle (kQuestionCadenceDays = 7).
                TodaysQuestionCard(familyId: primaryFamily.id)
                    .animate()
                    .fadeIn(duration: 350.ms, delay: 100.ms)
                    .slideY(begin: 0.04, end: 0),

                const SizedBox(height: 12),

                // ── Continue with {Family} card ──────────────────────────
                // Returning-user shortcut. Reads SmartDefaultsService to
                // show the last-viewed family. Hidden on first launch
                // (no saved family) and when the saved family no longer
                // exists. This is the WhatsApp/Telegram "open to last
                // chat" pattern.
                ContinueWithFamilyCard(families: families),

                const SizedBox(height: 20),

                // Upcoming Occasions row (only when there are occasions within 7 days)
                Builder(builder: (context) {
                  final occasionsAsync = ref.watch(occasionRemindersProvider);
                  return occasionsAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (occasionsState) {
                      final upcomingOccasions = occasionsState.withinSevenDays;
                      if (upcomingOccasions.isEmpty) return const SizedBox.shrink();
                      return UpcomingOccasionsRow(
                        occasions: upcomingOccasions,
                      )
                          .animate()
                          .fadeIn(duration: 350.ms, delay: 120.ms)
                          .slideY(begin: -0.05, end: 0);
                    },
                  );
                }),

                const SizedBox(height: 20),

                // Feed section header
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KinrelSpacing.base,
                  ),
                  child: semanticHeader(
                    label: 'Home Feed',
                    child: const Row(
                      children: [
                        Icon(
                          Icons.auto_awesome_rounded,
                          size: 18,
                          color: _cOrange,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Home Feed',
                          style: TextStyle(
                            fontFamily: KinrelTypography.displayFont,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: _cTextPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ).animate().fadeIn(duration: 350.ms, delay: 200.ms),

                const SizedBox(height: 12),
              ],
            ),
          ),

          // Unified Home Feed (using homeFeedProvider)
          if (feedState.isLoading)
            const SliverFillRemaining(
              child: Center(
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: _cOrange,
                  ),
                ),
              ),
            )
          else if (feedState.error != null && feedState.posts.isEmpty)
            SliverFillRemaining(
              child: DKErrorState(
                message: feedState.error ?? 'Failed to load feed',
                onRetry: () => ref.read(homeFeedProvider.notifier).loadHomeFeed(),
              ),
            )
          else if (feedState.posts.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: KinrelGradients.igniteGradient.colors
                                .map((c) => c.withValues(alpha: 0.12))
                                .toList(),
                            begin: KinrelGradients.igniteGradient.begin,
                            end: KinrelGradients.igniteGradient.end,
                          ),
                        ),
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          size: 36,
                          color: _cOrange,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'No family moments yet',
                        style: TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: _cTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Share your first post to start the conversation!',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 14,
                          color: _cTextSecondary,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index == feedState.posts.length) {
                    // Loading more indicator
                    if (feedState.isLoadingMore) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: _cOrange,
                            ),
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  }

                  final post = feedState.posts[index];
                  return FeedPostCard(
                    post: post,
                    onHeart: () => ref
                        .read(homeFeedProvider.notifier)
                        .toggleHeart(post.id),
                    onReact: (emoji) => ref
                        .read(homeFeedProvider.notifier)
                        .addReaction(post.id, emoji),
                  );
                },
                childCount: feedState.posts.length +
                    (feedState.isLoadingMore ? 1 : 0),
              ),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // QUICK-ADD SHEET (KIN-03 FIX)
  // ═══════════════════════════════════════════════════════════════════════

  void _showQuickAddSheet(BuildContext context, List<Family> families) {
    final hasFamily = families.isNotEmpty;
    final primaryFamilyId = hasFamily ? families.first.id : null;

    showModalBottomSheet(
      context: context,
      backgroundColor: _cCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Quick Add',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: _cTextPrimary,
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: _cOrange.withValues(alpha: 0.15),
                  child: const Icon(Icons.person_add_alt_1_rounded,
                      color: _cOrange, size: 22),
                ),
                title: const Text('Add Family Member',
                  style: TextStyle(fontFamily: KinrelTypography.bodyFont,
                    fontWeight: FontWeight.w600, color: _cTextPrimary)),
                subtitle: Text(
                  hasFamily
                      ? 'Add a relative to ${families.first.name}'
                      : 'Create a family first',
                  style: const TextStyle(fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12, color: _cTextDim)),
                enabled: hasFamily,
                onTap: () {
                  Navigator.pop(ctx);
                  if (primaryFamilyId != null) {
                    // v5.215 (unified add-member entry-point fix):
                    // skip straight to Find on Kinrel search
                    // (matching the Family Space / Family Profile /
                    // Members / Games Hub / Relationship Builder
                    // entry points). Previously this pushed the
                    // `/family/$familyId/add-person` route which
                    // opened `AddPersonSheet` (the manual-entry
                    // form) directly. "Add Manually" remains
                    // reachable only from the Family Graph screen.
                    openFindOnKinrelFlow(
                      context,
                      familyId: primaryFamilyId,
                    );
                  }
                },
              ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: KinrelColors.gold.withValues(alpha: 0.15),
                  child: const Icon(Icons.photo_library_outlined,
                      color: KinrelColors.gold, size: 22),
                ),
                title: const Text('Add Memory',
                  style: TextStyle(fontFamily: KinrelTypography.bodyFont,
                    fontWeight: FontWeight.w600, color: _cTextPrimary)),
                subtitle: const Text('Save a photo to Family Vault',
                  style: TextStyle(fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12, color: _cTextDim)),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/memory-vault');
                },
              ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: KinrelColors.purple.withValues(alpha: 0.15),
                  child: const Icon(Icons.edit_note_rounded,
                      color: KinrelColors.purple, size: 22),
                ),
                title: const Text('Post to Family Wall',
                  style: TextStyle(fontFamily: KinrelTypography.bodyFont,
                    fontWeight: FontWeight.w600, color: _cTextPrimary)),
                subtitle: const Text('Share an update with your family',
                  style: TextStyle(fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12, color: _cTextDim)),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/post/create');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showJoinFamilyDialog(BuildContext context) {
    final codeController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.dialog),
          side: BorderSide(color: _cOrange.withValues(alpha: 0.15)),
        ),
        title: const Text(
          'Join Family',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            color: _cTextPrimary,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter the family code shared with you',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                color: _cTextSecondary,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: codeController,
              style: const TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                color: _cTextPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'e.g., sharma-family-2a3b',
                hintStyle: const TextStyle(color: _cTextDim),
                filled: true,
                fillColor: _cElevated,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(KinrelRadius.input),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: _cTextSecondary)),
          ),
          FilledButton(
            onPressed: () {
              final id = codeController.text.trim();
              Navigator.pop(ctx);
              if (id.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a Family ID')),
                );
                return;
              }
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => JoinFamilyScreen(kinFamilyId: id),
                ),
              );
            },
            style: FilledButton.styleFrom(backgroundColor: _cOrange),
            child: const Text('Join'),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Sticky Header (60px)
// ═══════════════════════════════════════════════════════════════════════

/// Time-of-day contextual emoji.
String _greetingEmoji() {
  final hour = DateTime.now().hour;
  if (hour >= 5 && hour < 12) return '☀️';
  if (hour >= 12 && hour < 17) return '🌤️';
  if (hour >= 17 && hour < 21) return '🌅';
  return '🌙';
}

/// Time-of-day greeting prefix.
String _greetingPrefix() {
  final hour = DateTime.now().hour;
  if (hour >= 5 && hour < 12) return 'Good morning';
  if (hour >= 12 && hour < 17) return 'Good afternoon';
  if (hour >= 17 && hour < 21) return 'Good evening';
  return 'Good night';
}

class _StickyHeader extends StatelessWidget {
  const _StickyHeader({required this.user, required this.families});

  final dynamic user;

  /// The list of families the viewer belongs to. Used by the
  /// CompactFamilySwitcher pill in the header. When empty (Home's
  /// no-families view), the switcher renders a "Create family"
  /// affordance instead.
  final List<Family> families;

  @override
  Widget build(BuildContext context) {
    // The active family is the first one in the list — Home has
    // always used `families.first` as the primary family. The
    // CompactFamilySwitcher marks this id as "active" in the sheet.
    final activeFamilyId = families.isNotEmpty ? families.first.id : null;

    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      decoration: BoxDecoration(
        color: _cBg,
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          // K-graph mini icon (20px) — the Kinrel wordmark.
          const KinrelIcon(size: 20),
          const SizedBox(width: 10),
          // Compact family switcher pill — Phase A. The legacy
          // greeting block that used to live here is moved into
          // _CompactGreeting below the header so the header can fit
          // the switcher + wordmark + bell on a single 60px line,
          // matching the mockup.
          if (families.isNotEmpty)
            CompactFamilySwitcher(
              families: families,
              activeFamilyId: activeFamilyId,
            )
          else
            // No families — render a tiny "Create" pill so the
            // header still has a primary affordance. (Home's
            // empty-state view shows the full empty-state card
            // below, but the header still renders.)
            const CompactFamilySwitcher(
              families: const <Family>[],
              activeFamilyId: null,
            ),
          const Spacer(),
          // ── Streak badge: "🔥 N days". Hidden for new users (streak < 1).
          // This is the #1 retention lever — the user opens the app daily
          // to "not lose their streak" (Loss Aversion).
          //
          // PERF (Part C5): wrapped in a RepaintBoundary so the milestone
          // pulse animation (1200ms repeat) doesn't bleed repaints into the
          // rest of the home header / scroll view. The pulse only fires for
          // milestone streaks (and respects reduce-motion), but when it does
          // fire it ticks every ~16ms — isolate it.
          const RepaintBoundary(child: StreakBadge()),
          const SizedBox(width: 8),
          // v138: Replaced the circular user-avatar icon with a single
          // notification bell. The bell is now part of the Home header
          // itself (naturally Home-only — no floating overlay needed).
          // Tapping it opens /notifications. Shows a red badge with the
          // unread count when > 0.
          _HomeNotificationBell(),
        ],
      ),
    );
  }
}

/// Compact secondary line below the sticky header that shows the
/// greeting + @username. Phase A — moved out of the sticky header
/// so the header can fit the family-switcher pill on a single line.
///
/// This line scrolls with the content (not sticky) which matches
/// the mockup (the mockup doesn't show the greeting at all, but the
/// task says "keep greeting and streak if they fit, or move them
/// into a compact secondary line" — so we keep the greeting here
/// and the streak in the header).
class _CompactGreeting extends StatelessWidget {
  const _CompactGreeting({required this.user});

  final dynamic user;

  @override
  Widget build(BuildContext context) {
    // v2.2: Real authenticated user only — no mock fallback.
    final userName = user?.email?.split('@').first ?? 'Welcome';
    final userUsername = user?.userMetadata?['username'] as String?;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KinrelSpacing.base,
        12,
        KinrelSpacing.base,
        4,
      ),
      child: semanticHeader(
        label: '${_greetingPrefix()} $userName',
        child: Row(
          children: [
            Text(
              '${_greetingPrefix()} ${_greetingEmoji()}',
              style: const TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: _cTextDim,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                userName,
                style: const TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _cTextPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (userUsername != null) ...[
              const SizedBox(width: 6),
              Text(
                '@$userUsername',
                style: const TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  color: _cOrange,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Home-only notification bell — sits in the sticky header where the
/// user avatar circle used to be. Single clean icon, no circular profile
/// background. Red badge appears when there are unread notifications.
class _HomeNotificationBell extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCount = ref.watch(unreadCountProvider);

    return Semantics(
      button: true,
      label: unreadCount > 0
          ? 'Notifications, $unreadCount unread'
          : 'Notifications',
      hint: 'Double tap to view notifications',
      child: minimumTapTarget(
        child: GestureDetector(
          onTap: () {
                // ── Haptic on notification bell — selection click for
                // a navigation action (not a primary CTA).
                HapticService.selection();
                context.push('/notifications');
              },
          child: Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: _cElevated,
            ),
            alignment: Alignment.center,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  unreadCount > 0
                      ? Icons.notifications_rounded
                      : Icons.notifications_outlined,
                  color: const Color(0xFFC9B4A8),
                  size: 20,
                ),
                if (unreadCount > 0)
                  Positioned(
                    top: -2,
                    right: -4,
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 14,
                        minHeight: 14,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF4444),
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: _cBg,
                          width: 1.5,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          unreadCount > 99 ? '99+' : '$unreadCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// SliverPersistentHeaderDelegate for a sticky 60px header.
class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  _StickyHeaderDelegate({required this.user, required this.families});

  final dynamic user;

  /// The families list — passed through to _StickyHeader so the
  /// CompactFamilySwitcher pill can render in the header.
  final List<Family> families;

  @override
  double get minExtent => 60;

  @override
  double get maxExtent => 60;

  @override
  bool shouldRebuild(covariant _StickyHeaderDelegate oldDelegate) =>
      oldDelegate.user != user || oldDelegate.families != families;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return _StickyHeader(user: user, families: families);
  }
}


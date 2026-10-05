// lib/features/memories/presentation/memories_screen.dart
//
// DAXELO KINREL — Memories & Timeline Screen
//
// Family Timeline: Vertical timeline with orange gradient line,
// glow nodes, event cards (#191B2C, radius 14px).
// "On This Day" horizontal scroll cards with date overlay.
// Filter chips: Year, Event Type, Family Member.
// FAB: Add memory (orange gradient).
//
// Orange K-Graph DNA: #13141E bg, #191B2C cards, #E8612A accent,
// timeline gradient (#E8612A → #F59240), glow nodes.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_tokens.dart' show AppMotion;
import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../shared/widgets/animated_preview_card.dart';
import '../../../shared/widgets/app_scroll_safe_area.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../../shared/widgets/kinrel_empty_state.dart';
import '../providers/memories_provider.dart';
import '../../memory_vault/providers/memory_vault_provider.dart';

// ═══════════════════════════════════════════════════════════════════════
// Memories & Timeline Screen
// ═══════════════════════════════════════════════════════════════════════

class MemoriesScreen extends ConsumerStatefulWidget {
  const MemoriesScreen({super.key, this.familyId = ''});

  /// v96: the familyId for the current family context, passed via
  /// the route's query parameter (`/memories?familyId=...`). Used by
  /// the back button to navigate to `/family/$familyId` (Family
  /// Space). Empty string if no familyId was passed (the back button
  /// falls back to `context.pop()` in that case).
  final String familyId;

  @override
  ConsumerState<MemoriesScreen> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends ConsumerState<MemoriesScreen>
    with TickerProviderStateMixin {
  late AnimationController _fabController;

  @override
  void initState() {
    super.initState();
    _fabController = AnimationController(
      vsync: this,
      duration: KinrelMotion.slow,
    )..forward();
  }

  @override
  void dispose() {
    _fabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watch the display provider — reads REAL memories from
    // memoryVaultProvider (Supabase-backed) + filter state from
    // memoriesProvider. Pre-fix this watched memoriesProvider directly
    // (local-only, always empty in production) — the root cause of the
    // "save not persisting" regression.
    final state = ref.watch(displayMemoriesProvider);

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      body: Stack(
        children: [
          CustomScrollView(
            scrollCacheExtent: const ScrollCacheExtent.pixels(500),
            physics: const BouncingScrollPhysics(),
            slivers: [
              // ── Header ────────────────────────────────────────────
              SliverToBoxAdapter(child: _buildHeader(state)),

              // ── On This Day (if any) ──────────────────────────────
              // HIDDEN entirely when there are zero "On This Day"
              // matches — never shown empty or with placeholder content.
              // (On This Day reflects a calendar-date filter independent
              // of the user's Year/Type/Member pills, so its visibility
              // is decided purely by [state.hasOnThisDay].)
              if (state.hasOnThisDay)
                SliverToBoxAdapter(
                  child: _buildOnThisDaySection(state.onThisDayMemories),
                ),

              // ── Filter Chips ──────────────────────────────────────
              // Filter pills are ONLY rendered when there's something to
              // filter — for a brand-new family with zero memories the
              // empty state invites the user to add the first moment
              // instead of presenting unpopulated filter UI.
              if (state.hasMemories)
                SliverToBoxAdapter(child: _buildFilterChips(state)),

              // ── Timeline ──────────────────────────────────────────
              // Two distinct empty states:
              //   • Zero memories TOTAL → invitation to act ("add your
              //     family's first moment")
              //   • Has memories but filteredEvents is empty → "no
              //     memories match your filters — adjust or clear"
              if (!state.hasMemories)
                SliverToBoxAdapter(child: _buildEmptyStateZeroMemories())
              else if (state.filteredEvents.isEmpty)
                SliverToBoxAdapter(child: _buildEmptyStateFiltered(state))
              else
                _buildTimeline(state.filteredEvents),

              // ── Scroll safe-area padding ──────────────────────────
              // Shared widget — encodes the ADR-007 pattern so the last
              // card never clips under the FAB or the gesture-nav inset.
              // chromeHeight 56 = FAB only (no floating nav on this
              // screen). See lib/shared/widgets/app_scroll_safe_area.dart
              // for the full pattern. Other scroll screens with the
              // same layout shape should adopt this widget instead of
              // re-implementing the math inline.
              AppScrollSafeArea.sliver(chromeHeight: 56),
            ],
          ),

          // ── FAB: Add Memory ────────────────────────────────────────
          // Per ADR-007: positioned using MediaQuery padding bottom +
          // visual margin. The FAB floats above the scrollable content
          // (and the safe-area sliver above guarantees the last card
          // never clips under it).
          //
          // v96: HIDE the FAB when the family has ZERO memories (true
          // empty state) — the empty-state block's own "Add First
          // Memory" CTA is the only add action shown in that case,
          // avoiding redundancy. Once at least one memory exists
          // (populated list OR filtered-empty), the FAB reappears so
          // the user can add more from anywhere on the screen.
          if (state.hasMemories)
            Positioned(
              right: KinrelSpacing.base,
              bottom: MediaQuery.of(context).padding.bottom + 24,
              child: _buildFAB(),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Header
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildHeader(MemoriesState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            KinrelSpacing.base,
            KinrelSpacing.xl,
            KinrelSpacing.base,
            KinrelSpacing.sm,
          ),
          child: Row(
            children: [
              // v96: Back button — navigates to the Family Space screen
              // for the current family context. Uses context.go (not
              // context.pop) so it always lands on the correct Family
              // Space screen regardless of navigation history. Falls
              // back to context.pop() if no familyId was passed.
              GestureDetector(
                onTap: () {
                  if (widget.familyId.isNotEmpty) {
                    context.go('/family/${widget.familyId}');
                  } else if (context.canPop()) {
                    context.pop();
                  }
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: KinrelColors.darkCard,
                  ),
                  child: const Icon(
                    Icons.arrow_back_rounded,
                    color: KinrelColors.textWhite,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: KinrelSpacing.sm),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: KinrelColors.orange.withValues(alpha: 0.15),
                ),
                child: const Icon(
                  Icons.access_time_rounded,
                  color: KinrelColors.orange,
                  size: 22,
                ),
              ),
              const SizedBox(width: KinrelSpacing.md),
              Expanded(
                child: Text(
                  'Memories & Timeline',
                  style: KinrelTypography.headlineLarge.copyWith(
                    color: KinrelColors.textWhite,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              // ── Pin-count badge (TAPPABLE) ───────────────────────
              // Tapping the badge toggles the `showPinnedOnly` filter,
              // filtering the timeline to pinned memories only. The
              // badge is hidden when there are zero pinned memories
              // (because there's nothing to filter to). When the
              // pinned-only filter is active, the badge shows a
              // distinct "active" style (filled orange) so the user
              // knows the timeline is currently filtered.
              if (state.hasPinnedMemories)
                _PinCountBadge(
                  count: state.pinnedCount,
                  isActive: state.filter.showPinnedOnly,
                  onTap: () =>
                      ref.read(memoriesProvider.notifier).togglePinnedOnly(),
                ),
            ],
          ),
        ),
        // ── "Showing pinned only — view all" indicator ─────────────
        // Renders below the header when `showPinnedOnly` is active so
        // the user always has a clear path back to the unfiltered
        // timeline. Tapping it clears the pinned-only filter (keeps the
        // user's prior year/type/member pills intact).
        if (state.filter.showPinnedOnly)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              KinrelSpacing.base,
              0,
              KinrelSpacing.base,
              KinrelSpacing.sm,
            ),
            child: _ShowingPinnedOnlyBanner(
              onTap: () =>
                  ref.read(memoriesProvider.notifier).togglePinnedOnly(),
            ),
          ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // On This Day Section
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildOnThisDaySection(List<OnThisDayMemory> memories) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            KinrelSpacing.base,
            KinrelSpacing.md,
            KinrelSpacing.base,
            KinrelSpacing.sm,
          ),
          child: Row(
            children: [
              const Icon(
                Icons.today_rounded,
                color: KinrelColors.orange,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                'On This Day',
                style: KinrelTypography.headlineSmall.copyWith(
                  color: KinrelColors.textWhite,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: KinrelColors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(KinrelRadius.full),
                ),
                child: Text(
                  '${memories.length}',
                  style: KinrelTypography.labelSmall.copyWith(
                    color: KinrelColors.orange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 180,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
            itemCount: memories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              return _OnThisDayCard(memory: memories[index]);
            },
          ),
        ),
        const SizedBox(height: KinrelSpacing.md),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Filter Chips
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildFilterChips(MemoriesState state) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KinrelSpacing.base,
        KinrelSpacing.sm,
        KinrelSpacing.base,
        KinrelSpacing.md,
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Year filter
              Expanded(
                child: _FilterChipButton(
                  label: state.filter.selectedYear != null
                      ? '${state.filter.selectedYear}'
                      : 'Year',
                  icon: Icons.calendar_today_rounded,
                  isActive: state.filter.selectedYear != null,
                  onClear: state.filter.selectedYear != null
                      ? () => ref
                          .read(memoriesProvider.notifier)
                          .setYearFilter(null)
                      : null,
                  onTap: () => _showYearFilterSheet(state),
                ),
              ),
              const SizedBox(width: 8),
              // Event type filter
              Expanded(
                child: _FilterChipButton(
                  label: state.filter.selectedType != null
                      ? state.filter.selectedType!.typeLabel
                      : 'Event Type',
                  icon: Icons.filter_list_rounded,
                  isActive: state.filter.selectedType != null,
                  onClear: state.filter.selectedType != null
                      ? () => ref
                          .read(memoriesProvider.notifier)
                          .setTypeFilter(null)
                      : null,
                  onTap: () => _showTypeFilterSheet(state),
                ),
              ),
              const SizedBox(width: 8),
              // Member filter
              Expanded(
                child: _FilterChipButton(
                  label: state.filter.selectedMember != null
                      ? state.filter.selectedMember!.split(' ').first
                      : 'Member',
                  icon: Icons.person_rounded,
                  isActive: state.filter.selectedMember != null,
                  onClear: state.filter.selectedMember != null
                      ? () => ref
                          .read(memoriesProvider.notifier)
                          .setMemberFilter(null)
                      : null,
                  onTap: () => _showMemberFilterSheet(state),
                ),
              ),
            ],
          ),
          // Clear filters — only when at least one pill filter is active.
          // `showPinnedOnly` is excluded because it has its own banner
          // under the header.
          if (state.filter.pillsActive)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () =>
                      ref.read(memoriesProvider.notifier).clearFilters(),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.close_rounded,
                        size: 14,
                        color: KinrelColors.orange,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Clear filters',
                        style: KinrelTypography.labelSmall.copyWith(
                          color: KinrelColors.orange,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Filter Sheets
  // ═══════════════════════════════════════════════════════════════════

  void _showYearFilterSheet(MemoriesState state) {
    final years = state.availableYears;
    showModalBottomSheet(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.xxl),
        ),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(KinrelSpacing.base),
                child: Row(
                  children: [
                    Text(
                      'Filter by Year',
                      style: KinrelTypography.headlineMedium.copyWith(
                        color: KinrelColors.textWhite,
                      ),
                    ),
                    const Spacer(),
                    if (state.filter.selectedYear != null)
                      TextButton(
                        onPressed: () {
                          ref
                              .read(memoriesProvider.notifier)
                              .setYearFilter(null);
                          Navigator.pop(context);
                        },
                        child: Text(
                          'Clear',
                          style: KinrelTypography.labelMedium.copyWith(
                            color: KinrelColors.orange,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(color: Color(0xFF2A2A3D), height: 1),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.4,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: years.length,
                  itemBuilder: (context, index) {
                    final year = years[index];
                    final isSelected = state.filter.selectedYear == year;
                    return ListTile(
                      title: Text(
                        '$year',
                        style: KinrelTypography.bodyLarge.copyWith(
                          color: isSelected
                              ? KinrelColors.orange
                              : KinrelColors.textWhite,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(
                              Icons.check_rounded,
                              color: KinrelColors.orange,
                              size: 20,
                            )
                          : null,
                      onTap: () {
                        ref.read(memoriesProvider.notifier).setYearFilter(year);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showTypeFilterSheet(MemoriesState state) {
    final types = MemoryEventType.values;
    showModalBottomSheet(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.xxl),
        ),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(KinrelSpacing.base),
                child: Row(
                  children: [
                    Text(
                      'Filter by Event Type',
                      style: KinrelTypography.headlineMedium.copyWith(
                        color: KinrelColors.textWhite,
                      ),
                    ),
                    const Spacer(),
                    if (state.filter.selectedType != null)
                      TextButton(
                        onPressed: () {
                          ref
                              .read(memoriesProvider.notifier)
                              .setTypeFilter(null);
                          Navigator.pop(context);
                        },
                        child: Text(
                          'Clear',
                          style: KinrelTypography.labelMedium.copyWith(
                            color: KinrelColors.orange,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(color: Color(0xFF2A2A3D), height: 1),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: types.length,
                  itemBuilder: (context, index) {
                    final type = types[index];
                    final isSelected = state.filter.selectedType == type;
                    return ListTile(
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: type.accentColor.withValues(alpha: 0.15),
                        ),
                        child: Icon(
                          type.icon,
                          size: 18,
                          color: type.accentColor,
                        ),
                      ),
                      title: Text(
                        type.typeLabel,
                        style: KinrelTypography.bodyLarge.copyWith(
                          color: isSelected
                              ? type.accentColor
                              : KinrelColors.textWhite,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                      trailing: isSelected
                          ? Icon(
                              Icons.check_rounded,
                              color: type.accentColor,
                              size: 20,
                            )
                          : null,
                      onTap: () {
                        ref.read(memoriesProvider.notifier).setTypeFilter(type);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showMemberFilterSheet(MemoriesState state) {
    final members = state.availableMembers;
    showModalBottomSheet(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.xxl),
        ),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(KinrelSpacing.base),
                child: Row(
                  children: [
                    Text(
                      'Filter by Family Member',
                      style: KinrelTypography.headlineMedium.copyWith(
                        color: KinrelColors.textWhite,
                      ),
                    ),
                    const Spacer(),
                    if (state.filter.selectedMember != null)
                      TextButton(
                        onPressed: () {
                          ref
                              .read(memoriesProvider.notifier)
                              .setMemberFilter(null);
                          Navigator.pop(context);
                        },
                        child: Text(
                          'Clear',
                          style: KinrelTypography.labelMedium.copyWith(
                            color: KinrelColors.orange,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(color: Color(0xFF2A2A3D), height: 1),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.4,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: members.length,
                  itemBuilder: (context, index) {
                    final member = members[index];
                    final isSelected = state.filter.selectedMember == member;
                    final initials = member
                        .split(' ')
                        .where((s) => s.isNotEmpty)
                        .take(2)
                        .map((s) => s[0].toUpperCase())
                        .join();
                    return ListTile(
                      leading: DKAvatar(
                        initials: initials,
                        size: DKAvatarSize.sm,
                        backgroundColor: isSelected
                            ? KinrelColors.orange.withValues(alpha: 0.3)
                            : null,
                      ),
                      title: Text(
                        member,
                        style: KinrelTypography.bodyLarge.copyWith(
                          color: isSelected
                              ? KinrelColors.orange
                              : KinrelColors.textWhite,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(
                              Icons.check_rounded,
                              color: KinrelColors.orange,
                              size: 20,
                            )
                          : null,
                      onTap: () {
                        ref
                            .read(memoriesProvider.notifier)
                            .setMemberFilter(member);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Timeline
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildTimeline(List<MemoryEvent> events) {
    // NOTE: Bottom scroll padding is now provided by AppScrollSafeArea.sliver
    // (added after this sliver in the build method). The previous inline
    // SizedBox(height: 100) footer was insufficient on devices with large
    // gesture-nav insets — see the ADR-007 safe-area policy and the
    // shared widget's doc comment for details.
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final event = events[index];
          final isFirst = index == 0;
          final isLast = index == events.length - 1;
          return _TimelineEventCard(
            event: event,
            isFirst: isFirst,
            isLast: isLast,
            // Pin toggle goes to the vault (Supabase DB write) — NOT to
            // the local memoriesProvider (which only updated an in-memory
            // list and never persisted). The displayMemoriesProvider will
            // re-emit when the vault state changes, so the card's pin
            // badge updates immediately via optimistic update.
            onPin: () => ref
                .read(memoryVaultProvider.notifier)
                .togglePinToVault(event.id),
          );
        },
        childCount: events.length,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Empty State — Zero Memories Total
  // ═══════════════════════════════════════════════════════════════════
  //
  // Renders when the family has NO memories at all (the production
  // default for a brand-new family — see `MemoriesNotifier` doc).
  // Uses the shared [KinrelEmptyState] widget which follows the
  // app-wide "invitation to act" pattern (matching the family list,
  // presence strip, and leaderboard empty states).
  //
  // v94 (animated preview card): the static icon is replaced with
  // a small, animated live preview of what a memory card looks like.
  // The preview cycles through 3-4 illustrative placeholder scenes
  // with a slow crossfade (3.5s hold + 700ms transition), so the
  // user sees the feature in action rather than just an icon. The
  // animation respects the platform reduced-motion accessibility
  // setting (AppMotion.reducedMotion) by showing a single static
  // frame instead of cycling. The preview card is wrapped in a
  // RepaintBoundary so the continuous crossfade doesn't cause frame
  // drops elsewhere on the screen (per the jank-audit principles
  // already established in this app).

  Widget _buildEmptyStateZeroMemories() {
    // Returns a BOX widget (not a sliver) — the caller wraps it in
    // SliverToBoxAdapter(child: ...) in the build method's slivers
    // list. The previous version returned SliverToBoxAdapter(...) here,
    // which produced SliverToBoxAdapter(child: SliverToBoxAdapter(...))
    // — a sliver-in-a-box-slot that renders nothing (the inner sliver
    // gets zero size). This is the root cause of the blank-screen bug.
    return KinrelEmptyState(
        // v94: pass an animated preview card as the illustration
        // instead of a static icon. The KinrelEmptyState widget
        // renders the illustration in place of the default icon
        // circle (it replaces the 96×96 icon container — the
        // illustration is sized larger via its own constrained
        // width, so it reads as a real timeline card preview,
        // not a tiny icon-sized chip).
        illustration: RepaintBoundary(
          child: _AnimatedMemoryPreviewCard(
            reducedMotion: AppMotion.reducedMotion(context),
          ),
        ),
        // `icon` is still required by KinrelEmptyState (used as a
        // fallback if illustration is null). We pass a sensible
        // default that matches the previous static state.
        icon: Icons.auto_stories_rounded,
        title: 'No Memories Yet',
        subtitle:
            "Capture your family's first moment — a birth, a wedding, "
            'a festival, a milestone — to start building your timeline '
            'together.',
        actionLabel: 'Add First Memory',
        onAction: () => _showAddMemorySheet(),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Empty State — Filtered (Has Memories, No Filter Match)
  // ═══════════════════════════════════════════════════════════════════
  //
  // Distinct from the zero-memories state: the family HAS memories but
  // the current filter combination produces zero results. The CTA
  // offers a clear path back (clear filters / clear pinned-only) so
  // the user isn't stuck on a dead-end screen.

  Widget _buildEmptyStateFiltered(MemoriesState state) {
    final isPinnedOnly = state.filter.showPinnedOnly;
    final hasPillFilters = state.filter.pillsActive;
    void onClear() {
      if (hasPillFilters) {
        ref.read(memoriesProvider.notifier).clearFilters();
      }
      if (isPinnedOnly) {
        ref.read(memoriesProvider.notifier).togglePinnedOnly();
      }
    }
    // Returns a BOX widget (not a sliver) — see the note in
    // _buildEmptyStateZeroMemories above for the root-cause explanation
    // of the previous SliverToBoxAdapter(child: SliverToBoxAdapter(...))
    // double-wrap that rendered nothing.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: KinrelColors.orange.withValues(alpha: 0.1),
            ),
            child: const Icon(
              Icons.filter_alt_off_rounded,
              size: 40,
              color: KinrelColors.orange,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            isPinnedOnly && !hasPillFilters
                ? 'No Pinned Memories'
                : 'No Memories Match Your Filters',
            style: KinrelTypography.headlineMedium.copyWith(
              color: KinrelColors.textWhite,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isPinnedOnly && !hasPillFilters
                ? 'Pin a memory to keep it at the top of your timeline — '
                    'tap the pin icon on any card.'
                : 'Try adjusting or clearing your filters to see more '
                    'of your family timeline.',
            textAlign: TextAlign.center,
            style: KinrelTypography.bodyMedium.copyWith(
              color: KinrelColors.textSilver,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          DKButton(
            label: isPinnedOnly && !hasPillFilters
                ? 'View All Memories'
                : 'Clear Filters',
            variant: DKButtonVariant.secondary,
            icon: Icons.close_rounded,
            size: DKButtonSize.md,
            onPressed: onClear,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // FAB
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildFAB() {
    return ScaleTransition(
      scale: CurvedAnimation(
        parent: _fabController,
        curve: KinrelMotion.spring,
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(KinrelRadius.full),
          gradient: KinrelGradients.igniteGradient,
          boxShadow: [
            const BoxShadow(
              color: KinrelColors.orangeGlowIntense,
              blurRadius: 16,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(KinrelRadius.full),
            onTap: () => _showAddMemorySheet(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add_rounded, color: Colors.white, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Add Memory',
                    style: KinrelTypography.labelLarge.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Add Memory Sheet
  // ═══════════════════════════════════════════════════════════════════

  void _showAddMemorySheet() {
    // Route to the new MemoryCreateScreen (the Supabase-backed memory
    // composer with image picker, crop editor, compression, and the
    // shared-quota gate — see lib/features/memory_vault/presentation/
    // memory_create_screen.dart).
    //
    // Per the user spec, this is the "Timeline entry creation flow":
    // "Add an optional single-image field to the Timeline entry creation
    // flow — when adding a memory (birth, wedding, festival, custom,
    // etc.), allow attaching exactly ONE photo as that entry's hero
    // image."
    //
    // The new screen handles the optional photo attachment (subject to
    // the shared monthly quota with Memory Vault), the structured fields
    // (title/description/location/memory_type/members/date), and writes
    // to the Supabase `family_memories` table via MemoryVaultNotifier.
    context.push('/memory/create');
  }
}

// ═══════════════════════════════════════════════════════════════════════
// On This Day Card
// ═══════════════════════════════════════════════════════════════════════

class _OnThisDayCard extends StatelessWidget {
  const _OnThisDayCard({required this.memory});

  final OnThisDayMemory memory;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(
          color: KinrelColors.orange.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Photo placeholder with date overlay
          Stack(
            children: [
              Container(
                height: 100,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      memory.members.isNotEmpty
                          ? KinrelColors.orange.withValues(alpha: 0.2)
                          : KinrelColors.darkElevated,
                      KinrelColors.darkCard,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(KinrelRadius.lg),
                  ),
                ),
                child: const Center(
                  child: Icon(
                    Icons.photo_camera_rounded,
                    size: 32,
                    color: KinrelColors.textDim,
                  ),
                ),
              ),
              // Date overlay (bottom-left)
              Positioned(
                bottom: 8,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: KinrelColors.darkSurface.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(KinrelRadius.sm),
                  ),
                  child: Text(
                    memory.formattedDate,
                    style: KinrelTypography.micro.copyWith(
                      color: KinrelColors.textSilver,
                    ),
                  ),
                ),
              ),
              // Years ago badge (top-right)
              Positioned(
                top: 8,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    gradient: KinrelGradients.igniteGradient,
                    borderRadius: BorderRadius.circular(KinrelRadius.full),
                  ),
                  child: Text(
                    memory.yearsAgoLabel,
                    style: KinrelTypography.micro.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  memory.title,
                  style: KinrelTypography.labelLarge.copyWith(
                    color: KinrelColors.textWhite,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (memory.description != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    memory.description!,
                    style: KinrelTypography.bodySmall.copyWith(
                      color: KinrelColors.textSilver,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (memory.members.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _AvatarRow(members: memory.members, maxSize: 22),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Filter Chip Button
// ═══════════════════════════════════════════════════════════════════════
//
// Three interaction states (all visually distinct):
//   • Default  — outlined, dim icon/label.
//   • Active   — filled accent background (orange at 15% alpha),
//                accent border, accent icon/label, plus a small "×"
//                affordance so the user can clear this filter without
//                re-opening the bottom sheet.
//   • Pressed  — handled by AnimatedContainer + Material InkWell.
//
// Tapping the pill body opens the bottom sheet to change the selection.
// Tapping the "×" clears this filter in one tap (does not open the sheet).

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  /// Optional quick-clear callback. When non-null AND `isActive` is
  /// true, a small "×" appears at the trailing edge of the pill.
  /// Tapping the "×" calls this callback (does NOT trigger `onTap`).
  /// Set to null to hide the "×" affordance entirely.
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: KinrelMotion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          // Active state uses a FILLED background (not just a tinted
          // outline) so it's immediately obvious at a glance which
          // filters are applied. Matches the pattern used by other
          // active filter chips in the app.
          color: isActive
              ? KinrelColors.orange.withValues(alpha: 0.18)
              : KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(KinrelRadius.full),
          border: Border.all(
            color: isActive
                ? KinrelColors.orange.withValues(alpha: 0.55)
                : const Color(0xFF3A3A4A),
            width: isActive ? 1.5 : 1,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: KinrelColors.orange.withValues(alpha: 0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isActive ? KinrelColors.orange : KinrelColors.textDim,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                style: KinrelTypography.labelSmall.copyWith(
                  color: isActive
                      ? KinrelColors.orange
                      : KinrelColors.textSilver,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // ── Quick-clear "×" — only on active pills ────────────
            // Tap area is intentionally larger than the visual icon
            // (44×44 minimum) for accessibility.
            if (isActive && onClear != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onClear,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: KinrelColors.orange.withValues(alpha: 0.25),
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 11,
                      color: KinrelColors.orange,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Pin Count Badge (header)
// ═══════════════════════════════════════════════════════════════════════
//
// Tappable badge that shows the count of pinned memories. Tapping it
// toggles the `showPinnedOnly` filter (filtering the timeline to pinned
// memories only). When the filter is active, the badge shows a distinct
// "active" style — bright filled orange + glow — so the user knows the
// timeline is currently filtered. When inactive, the badge shows a
// softer outlined style to invite tapping.

class _PinCountBadge extends StatelessWidget {
  const _PinCountBadge({
    required this.count,
    required this.isActive,
    required this.onTap,
  });

  final int count;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Tooltip(
        message: isActive ? 'Showing pinned only — tap to view all' : 'Tap to show pinned only',
        child: AnimatedContainer(
          duration: KinrelMotion.fast,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            // Active: solid orange gradient + glow.
            // Inactive: soft orange-tinted outline (still discoverable).
            gradient: isActive ? KinrelGradients.igniteGradient : null,
            color: isActive
                ? null
                : KinrelColors.orange.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(KinrelRadius.full),
            border: isActive
                ? null
                : Border.all(
                    color: KinrelColors.orange.withValues(alpha: 0.45),
                    width: 1.2,
                  ),
            boxShadow: isActive
                ? [
                    const BoxShadow(
                      color: KinrelColors.orangeGlowIntense,
                      blurRadius: 12,
                      offset: Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isActive
                    ? Icons.push_pin_rounded
                    : Icons.push_pin_outlined,
                size: 14,
                color: isActive ? Colors.white : KinrelColors.orange,
              ),
              const SizedBox(width: 4),
              Text(
                '$count',
                style: KinrelTypography.labelSmall.copyWith(
                  color: isActive ? Colors.white : KinrelColors.orange,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// "Showing Pinned Only — View All" Banner
// ═══════════════════════════════════════════════════════════════════════
//
// Renders below the header when the `showPinnedOnly` filter is active.
// Provides a clear path back to the unfiltered timeline — tapping it
// toggles the pinned-only filter off (the user's prior year/type/member
// pills are preserved).

class _ShowingPinnedOnlyBanner extends StatelessWidget {
  const _ShowingPinnedOnlyBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KinrelColors.orange.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(KinrelRadius.full),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KinrelRadius.full),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.push_pin_rounded,
                size: 12,
                color: KinrelColors.orange,
              ),
              const SizedBox(width: 6),
              Text(
                'Showing pinned only',
                style: KinrelTypography.labelSmall.copyWith(
                  color: KinrelColors.orange,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '— View all',
                style: KinrelTypography.labelSmall.copyWith(
                  color: KinrelColors.orange.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.underline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Timeline Event Card
// ═══════════════════════════════════════════════════════════════════════

class _TimelineEventCard extends StatelessWidget {
  const _TimelineEventCard({
    required this.event,
    required this.isFirst,
    required this.isLast,
    required this.onPin,
  });

  final MemoryEvent event;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onPin;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Timeline Column (line + node) ──────────────────────────
          SizedBox(
            width: 56,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Gradient line
                if (!isLast)
                  Positioned(
                    top: isFirst ? 28 : 0,
                    bottom: 0,
                    left: 27,
                    child: Container(
                      width: 2,
                      decoration: const BoxDecoration(
                        gradient: KinrelGradients.timelineGradient,
                      ),
                    ),
                  ),
                // Top cap for first item
                if (isFirst)
                  Positioned(
                    top: 0,
                    left: 27,
                    child: Container(
                      width: 2,
                      height: 28,
                      decoration: const BoxDecoration(
                        gradient: KinrelGradients.timelineGradient,
                      ),
                    ),
                  ),
                // Glow node
                Positioned(
                  top: 20,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: event.accentColor,
                      boxShadow: [
                        BoxShadow(
                          color: event.accentColor.withValues(alpha: 0.5),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                        BoxShadow(
                          color: event.accentColor.withValues(alpha: 0.25),
                          blurRadius: 16,
                          spreadRadius: 3,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ── Event Card ─────────────────────────────────────────────
          Expanded(
            child: Container(
              margin: EdgeInsets.only(
                top: isFirst ? 10 : 8,
                bottom: isLast ? 8 : 12,
                right: KinrelSpacing.base,
              ),
              padding: const EdgeInsets.all(KinrelSpacing.base),
              decoration: BoxDecoration(
                color: KinrelColors.darkCard,
                borderRadius: BorderRadius.circular(KinrelRadius.lg),
                border: event.isPinned
                    ? Border.all(
                        color: KinrelColors.orange.withValues(alpha: 0.4),
                        width: 1.5,
                      )
                    : null,
                boxShadow: event.isPinned
                    ? [
                        const BoxShadow(
                          color: KinrelColors.orangeGlowSubtle,
                          blurRadius: 12,
                          offset: Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Top row: type badge + pin + date ──────────────────
                  Row(
                    children: [
                      // Type badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: event.accentColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(KinrelRadius.xs),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              event.icon,
                              size: 12,
                              color: event.accentColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              event.typeLabel,
                              style: KinrelTypography.micro.copyWith(
                                color: event.accentColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Pin icon
                      if (event.isPinned) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.push_pin_rounded,
                          size: 14,
                          color: KinrelColors.orange,
                        ),
                      ],
                      const Spacer(),
                      // Date
                      Text(
                        event.formattedDate,
                        style: KinrelTypography.labelSmall.copyWith(
                          color: KinrelColors.textDim,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // ── Title ────────────────────────────────────────────
                  Text(
                    event.title,
                    style: KinrelTypography.headlineSmall.copyWith(
                      color: KinrelColors.textWhite,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  // ── Description ──────────────────────────────────────
                  if (event.description != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      event.description!,
                      style: KinrelTypography.bodySmall.copyWith(
                        color: KinrelColors.textSilver,
                        height: 1.5,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  // ── Location ─────────────────────────────────────────
                  if (event.location != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_rounded,
                          size: 13,
                          color: KinrelColors.textDim,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            event.location!,
                            style: KinrelTypography.labelSmall.copyWith(
                              color: KinrelColors.textDim,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  // ── Photo placeholder ────────────────────────────────
                  if (event.photoUrl != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      height: 80,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            event.accentColor.withValues(alpha: 0.1),
                            KinrelColors.darkElevated,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(KinrelRadius.md),
                      ),
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.image_rounded,
                              size: 20,
                              color: KinrelColors.textDim,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'View Photo',
                              style: KinrelTypography.labelSmall.copyWith(
                                color: KinrelColors.textDim,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  // ── Member avatars + Pin action ──────────────────────
                  if (event.members.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: _AvatarRow(members: event.members)),
                        // Pin toggle
                        GestureDetector(
                          onTap: onPin,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: event.isPinned
                                  ? KinrelColors.orange.withValues(alpha: 0.15)
                                  : KinrelColors.darkElevated,
                            ),
                            child: Icon(
                              event.isPinned
                                  ? Icons.push_pin_rounded
                                  : Icons.push_pin_outlined,
                              size: 16,
                              color: event.isPinned
                                  ? KinrelColors.orange
                                  : KinrelColors.textDim,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    // Pin button even without members
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: onPin,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: event.isPinned
                                ? KinrelColors.orange.withValues(alpha: 0.15)
                                : KinrelColors.darkElevated,
                          ),
                          child: Icon(
                            event.isPinned
                                ? Icons.push_pin_rounded
                                : Icons.push_pin_outlined,
                            size: 16,
                            color: event.isPinned
                                ? KinrelColors.orange
                                : KinrelColors.textDim,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Avatar Row (overlapping circles)
// ═══════════════════════════════════════════════════════════════════════

class _AvatarRow extends StatelessWidget {
  const _AvatarRow({required this.members, this.maxSize = 28});

  final List<MemoryMember> members;
  final double maxSize;

  @override
  Widget build(BuildContext context) {
    const maxDisplay = 4;
    final displayMembers = members.take(maxDisplay).toList();
    final extraCount = members.length - maxDisplay;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...displayMembers.asMap().entries.map((entry) {
          final index = entry.key;
          final member = entry.value;
          return Padding(
            padding: EdgeInsets.only(left: index > 0 ? -8.0 : 0),
            child: Container(
              width: maxSize,
              height: maxSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KinrelColors.darkElevated,
                border: Border.all(color: KinrelColors.darkCard, width: 2),
              ),
              child: Center(
                child: Text(
                  member.displayInitials,
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: maxSize * 0.35,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                    height: 1,
                  ),
                ),
              ),
            ),
          );
        }),
        if (extraCount > 0)
          Padding(
            padding: const EdgeInsets.only(left: -8.0),
            child: Container(
              width: maxSize,
              height: maxSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KinrelColors.darkElevated,
                border: Border.all(color: KinrelColors.darkCard, width: 2),
              ),
              child: Center(
                child: Text(
                  '+$extraCount',
                  style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: maxSize * 0.3,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.orange,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Add Memory Sheet
// ═══════════════════════════════════════════════════════════════════════

class _AddMemorySheet extends ConsumerStatefulWidget {
  @override
  ConsumerState<_AddMemorySheet> createState() => _AddMemorySheetState();
}

class _AddMemorySheetState extends ConsumerState<_AddMemorySheet> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _locationController = TextEditingController();
  MemoryEventType _selectedType = MemoryEventType.custom;
  DateTime _selectedDate = DateTime.now();

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: KinrelSpacing.base,
        right: KinrelSpacing.base,
        top: KinrelSpacing.xl,
        bottom: MediaQuery.of(context).viewInsets.bottom + KinrelSpacing.xl,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF3A3A4A),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Title
            Text(
              'Add a Memory',
              style: KinrelTypography.headlineLarge.copyWith(
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: 20),
            // Event type selector
            Text(
              'Event Type',
              style: KinrelTypography.labelMedium.copyWith(
                color: KinrelColors.textSilver,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: MemoryEventType.values.map((type) {
                final isSelected = _selectedType == type;
                return GestureDetector(
                  onTap: () => setState(() => _selectedType = type),
                  child: AnimatedContainer(
                    duration: KinrelMotion.fast,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? type.accentColor.withValues(alpha: 0.2)
                          : KinrelColors.darkElevated,
                      borderRadius: BorderRadius.circular(KinrelRadius.full),
                      border: Border.all(
                        color: isSelected
                            ? type.accentColor.withValues(alpha: 0.5)
                            : Colors.transparent,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          type.icon,
                          size: 14,
                          color: isSelected
                              ? type.accentColor
                              : KinrelColors.textDim,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          type.typeLabel,
                          style: KinrelTypography.labelSmall.copyWith(
                            color: isSelected
                                ? type.accentColor
                                : KinrelColors.textSilver,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            // Title input
            _buildInputField(
              controller: _titleController,
              hint: 'Memory title',
              icon: Icons.title_rounded,
            ),
            const SizedBox(height: 10),
            // Description input
            _buildInputField(
              controller: _descController,
              hint: 'Description (optional)',
              icon: Icons.notes_rounded,
              maxLines: 3,
            ),
            const SizedBox(height: 10),
            // Location input
            _buildInputField(
              controller: _locationController,
              hint: 'Location (optional)',
              icon: Icons.location_on_rounded,
            ),
            const SizedBox(height: 10),
            // Date picker
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: KinrelColors.darkElevated,
                  borderRadius: BorderRadius.circular(KinrelRadius.md),
                  border: Border.all(color: const Color(0xFF3A3A4A)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_rounded,
                      size: 18,
                      color: KinrelColors.textDim,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _formatDate(_selectedDate),
                      style: KinrelTypography.bodyMedium.copyWith(
                        color: KinrelColors.textWhite,
                      ),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: KinrelColors.textDim,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Create button
            SizedBox(
              width: double.infinity,
              child: DKButton(
                label: 'Create Memory',
                variant: DKButtonVariant.gradient,
                icon: Icons.add_rounded,
                size: DKButtonSize.lg,
                fullWidth: true,
                onPressed: _createMemory,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: KinrelTypography.bodyMedium.copyWith(
        color: KinrelColors.textWhite,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: KinrelTypography.bodyMedium.copyWith(
          color: KinrelColors.textDim,
        ),
        prefixIcon: Icon(icon, size: 20, color: KinrelColors.textDim),
        filled: true,
        fillColor: KinrelColors.darkElevated,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          borderSide: const BorderSide(color: KinrelColors.orange, width: 1.5),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month]} ${date.year}';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: KinrelColors.orange,
              surface: KinrelColors.darkCard,
              onSurface: KinrelColors.textWhite,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  void _createMemory() {
    if (_titleController.text.trim().isEmpty) return;

    final event = MemoryEvent(
      id: 'memory-${DateTime.now().millisecondsSinceEpoch}',
      title: _titleController.text.trim(),
      type: _selectedType,
      date: _selectedDate,
      description: _descController.text.trim().isNotEmpty
          ? _descController.text.trim()
          : null,
      location: _locationController.text.trim().isNotEmpty
          ? _locationController.text.trim()
          : null,
    );

    ref.read(memoriesProvider.notifier).addEvent(event);
    Navigator.pop(context);
  }
}

// ═══════════════════════════════════════════════════════════════════════
// NOTE: SliverChildBuilderWithFooter removed — replaced by
// AppScrollSafeArea.sliver (lib/shared/widgets/app_scroll_safe_area.dart)
// which encodes the ADR-007 bottom safe-area pattern as a reusable
// widget. Other scroll screens with the same layout shape should adopt
// the same widget instead of re-implementing the bottom-padding math.
// ═══════════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════
// Animated Memory Preview Card (v94)
// ═══════════════════════════════════════════════════════════════════════
//
// A small, animated live preview of what a memory timeline card looks
// like — used in the Memories & Timeline empty state to demonstrate
// the feature in action rather than showing a static icon.
//
// DESIGN
// ──────
// The preview card is styled identically to a real memory timeline
// card (matching KinrelColors.darkCard + KinrelRadius.lg, category
// color-coding, type badge, date, title/description layout already
// established in the populated timeline view). The photo area uses
// an AnimatedSwitcher with a crossfade to cycle through 3-4
// illustrative placeholder "scenes" every 3.5 seconds, with a 700ms
// crossfade transition between them (per the brief: 3-4 second hold
// + 600-800ms transition).
//
// The placeholder scenes are deliberately generic and abstract — NOT
// photos of real or AI-generated people — to avoid any implication
// that these are real family photos or someone else's actual
// memories. Each scene is a warm gradient + a simple Material icon
// (cake, hearts, photo frame, star) that hints at the kind of memory
// the user might add. The captions are neutral and non-specific
// ("A family celebration", "A treasured milestone", "A special
// moment", "A captured memory").
//
// REDUCED MOTION
// ──────────────
// When `reducedMotion` is true (the platform accessibility setting
// is on, per AppMotion.reducedMotion), the card shows a SINGLE static
// frame instead of cycling. The card is still visible (the user
// still sees what a memory card looks like) — only the crossfade
// animation is suppressed.
//
// PERFORMANCE
// ───────────
// The parent wraps this widget in a RepaintBoundary so the
// continuous crossfade doesn't cause Flutter to repaint the entire
// empty state on every animation tick. The AnimatedSwitcher itself
// is lightweight (only the photo area animates; the rest of the
// card is static). The Timer is cancelled on dispose so the widget
// doesn't keep ticking when the empty state is scrolled off-screen
// or the screen is popped.
//
// The animation is intentionally SLOW and SUBTLE — a 3.5s hold per
// scene + 700ms crossfade means a full cycle takes ~16 seconds. This
// reads as a gentle, ambient demonstration, not an attention-
// grabbing loop. Per the brief: "this should read as a gentle,
// ambient demonstration, not an attention-grabbing or distracting
// loop."

class _AnimatedMemoryPreviewCard extends StatefulWidget {
  const _AnimatedMemoryPreviewCard({
    this.reducedMotion = false,
  });

  /// Whether the user has requested reduced motion. When true, the
  /// card shows a single static frame instead of cycling through
  /// placeholder scenes. Defaults to false — the parent should pass
  /// `AppMotion.reducedMotion(context)`.
  final bool reducedMotion;

  @override
  State<_AnimatedMemoryPreviewCard> createState() =>
      _AnimatedMemoryPreviewCardState();
}

class _AnimatedMemoryPreviewCardState
    extends State<_AnimatedMemoryPreviewCard> {
  /// Index of the currently-shown placeholder scene.
  /// Cycles 0 → 1 → 2 → 3 → 0 → ...
  int _currentSceneIndex = 0;

  /// Drives the crossfade cycle. Restarts when the user toggles
  /// reduced-motion off (so the cycle resumes from the current
  /// frame, not from the beginning).
  Timer? _cycleTimer;

  /// The 3-4 illustrative placeholder scenes. Each scene is a tuple
  /// of (gradient colors, icon, accent color, type label, title,
  /// date label, description).
  ///
  /// v95 (demo-style content): these are full, complete illustrative
  /// examples matching the spirit of the original demo data — specific
  /// titles, real category types, and plausible dates — so the preview
  /// reads as a real timeline card, not generic placeholder text. The
  /// scenes are clearly illustrative (they cycle, and the empty-state
  /// headline/subtitle makes it clear this is a preview), not real
  /// data presented as the user's own.
  static const _placeholderScenes = <_PlaceholderScene>[
    _PlaceholderScene(
      gradientColors: [Color(0xFFE8612A), Color(0xFF1A1C2E)],
      icon: Icons.cake_rounded,
      accentColor: KinrelColors.orange,
      typeLabel: 'BIRTH',
      title: 'Aarav was born',
      dateLabel: '12 Aug 2023',
      description: 'Welcome to the family, Aarav! Born at 3:42 AM, 3.2 kg.',
    ),
    _PlaceholderScene(
      gradientColors: [Color(0xFFF59240), Color(0xFF1A1C2E)],
      icon: Icons.favorite_rounded,
      accentColor: KinrelColors.amber,
      typeLabel: 'MARRIAGE',
      title: "Rajesh & Meera's Wedding",
      dateLabel: '14 Feb 2023',
      description: 'A grand Gujarati-Rajasthani fusion wedding.',
    ),
    _PlaceholderScene(
      gradientColors: [Color(0xFF60A5FA), Color(0xFF1A1C2E)],
      icon: Icons.emoji_events_rounded,
      accentColor: KinrelColors.info,
      typeLabel: 'ACHIEVEMENT',
      title: 'Ravi received Padma Shri Award',
      dateLabel: '26 Jan 2024',
      description: 'Honored for contributions to rural education.',
    ),
    _PlaceholderScene(
      gradientColors: [Color(0xFFFFD700), Color(0xFF1A1C2E)],
      icon: Icons.festival_rounded,
      accentColor: KinrelColors.brightGold,
      typeLabel: 'FESTIVAL',
      title: 'Diwali at the family home',
      dateLabel: '1 Nov 2024',
      description: 'The whole family gathered for Diwali puja and fireworks.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _startCycleIfNeeded();
  }

  @override
  void didUpdateWidget(_AnimatedMemoryPreviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If reduced-motion toggled, start/stop the cycle accordingly.
    if (widget.reducedMotion != oldWidget.reducedMotion) {
      if (widget.reducedMotion) {
        _stopCycle();
      } else {
        _startCycleIfNeeded();
      }
    }
  }

  void _startCycleIfNeeded() {
    if (widget.reducedMotion) return;
    _stopCycle();
    // 3.5 second hold per scene + 700ms crossfade ≈ 4.2s per cycle.
    // Total cycle (4 scenes) ≈ 16.8s — slow and ambient, per the
    // brief's "gentle, ambient demonstration, not an attention-
    // grabbing loop" requirement.
    _cycleTimer = Timer.periodic(
      const Duration(milliseconds: 4200),
      (_) {
        if (!mounted) return;
        setState(() {
          _currentSceneIndex =
              (_currentSceneIndex + 1) % _placeholderScenes.length;
        });
      },
    );
  }

  void _stopCycle() {
    _cycleTimer?.cancel();
    _cycleTimer = null;
  }

  @override
  void dispose() {
    _stopCycle();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scene = _placeholderScenes[_currentSceneIndex];

    // v95: delegate the card container + title/description layout to
    // the shared AnimatedPreviewCard shell. This widget now owns only
    // the scene data + the crossfade media widget — the card chrome
    // (darkCard container, KinrelRadius.lg, accent border/shadow,
    // title/description typography) lives in the shared shell so the
    // Oral History preview card can reuse the exact same chrome.
    return AnimatedPreviewCard(
      reducedMotion: widget.reducedMotion,
      accentColor: scene.accentColor,
      header: _SceneHeader(scene: scene),
      mediaArea: _MemoryPhotoCrossfade(
        scene: scene,
        sceneIndex: _currentSceneIndex,
      ),
      title: scene.title,
      description: scene.description,
    );
  }
}

/// The header row for the Memories preview card — a type badge (icon
/// + uppercase label) on the left, a date label on the right. Matches
/// the real `_TimelineEventCard`'s top-row layout so the preview
/// reads as a real timeline card.
class _SceneHeader extends StatelessWidget {
  const _SceneHeader({required this.scene});

  final _PlaceholderScene scene;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: scene.accentColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(KinrelRadius.xs),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(scene.icon, size: 12, color: scene.accentColor),
              const SizedBox(width: 4),
              Text(
                scene.typeLabel,
                style: KinrelTypography.micro.copyWith(
                  color: scene.accentColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        Text(
          scene.dateLabel,
          style: KinrelTypography.labelSmall.copyWith(
            color: KinrelColors.textDim,
          ),
        ),
      ],
    );
  }
}

/// The animated photo area for the Memories preview card — a soft
/// gradient + centered icon that crossfades between scenes via
/// [AnimatedSwitcher]. When reduced-motion is on, the parent stops
/// cycling the scene index so this widget renders a single static
/// frame (the AnimatedSwitcher still exists but never switches).
class _MemoryPhotoCrossfade extends StatelessWidget {
  const _MemoryPhotoCrossfade({
    required this.scene,
    required this.sceneIndex,
  });

  final _PlaceholderScene scene;
  final int sceneIndex;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(KinrelRadius.md),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 700),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: child,
        ),
        child: _PlaceholderPhoto(
          key: ValueKey('scene_$sceneIndex'),
          scene: scene,
        ),
      ),
    );
  }
}

/// A single illustrative placeholder scene for the animated preview
/// card. Kept simple (gradient + icon + accent + text) — deliberately
/// NOT a photo of real people, to avoid any implication that these
/// are real family photos or someone else's actual memories.
@immutable
class _PlaceholderScene {
  const _PlaceholderScene({
    required this.gradientColors,
    required this.icon,
    required this.accentColor,
    required this.typeLabel,
    required this.title,
    required this.dateLabel,
    required this.description,
  });

  /// The two-color gradient for the photo area. The first color is
  /// warm (the scene's accent), the second is dark (the card
  /// background) — produces a soft "spotlight" effect that reads as
  /// an illustrative placeholder rather than a real photo.
  final List<Color> gradientColors;

  /// A simple Material icon that hints at the scene's category
  /// (cake for celebration, hearts for marriage, etc.).
  final IconData icon;

  /// The accent color used for the type badge and the gradient.
  final Color accentColor;

  /// The uppercase type label (matches the real timeline card's
  /// `event.typeLabel` convention).
  final String typeLabel;

  /// A neutral, non-specific title (e.g., "A family celebration").
  final String title;

  /// A neutral, non-specific date label.
  final String dateLabel;

  /// A neutral, non-specific description (1 sentence).
  final String description;
}

/// The placeholder "photo" area inside the preview card — a soft
/// gradient with a centered icon. Used by AnimatedSwitcher to
/// crossfade between scenes.
class _PlaceholderPhoto extends StatelessWidget {
  const _PlaceholderPhoto({super.key, required this.scene});

  final _PlaceholderScene scene;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 110,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: scene.gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Icon(
            scene.icon,
            size: 44,
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
      ),
    );
  }
}

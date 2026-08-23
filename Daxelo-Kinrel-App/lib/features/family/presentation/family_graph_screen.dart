// lib/features/family/presentation/family_graph_screen.dart
//
// DAXELO KINREL — Family Graph Screen (v7.0 — Graph Overhaul)
//
// Full-screen graph viewer for visualizing family relationships.
//
// v7 changes (2026-06-18, responding to user feedback):
//   - Removed Zoom In / Zoom Out buttons from AppBar
//   - Pinch-to-zoom is now the only zoom method (handled by GraphPanZoom v4)
//   - Double-tap-to-zoom (toggle 1x ↔ 2.5x) also available
//   - Graph can be freely moved across the entire canvas (no clamping)
//   - Removed "No relationships in database" warning banner
//   - Removed debug overlay (P:2 E:1 L:2 C:500x250 V:284x693 Z:0.64 A:Y)
//   - Kinship dataset (5,359 relationships × 15 languages) preloaded
//     at app startup so the Add Member flow has it ready
//
// Features:
//   - AppBar: [Back] [Family Name] --- [Add Member]
//   - Bottom toolbar: Center, Add Member (primary), Filter, Help
//   - Passes graph data directly to FamilyGraphWidget (no double-fetch)
//   - Custom GraphPanZoom (v4) — pinch, pan, double-tap, no clamping
//   - Graph state persistence (zoom/position) via SharedPreferences
//   - Responsive, safe-area aware, no overflow issues
//   - Real-time updates via Supabase Realtime
//   - Immediate graph refresh after adding members
//   - Direct Supabase query as primary source (always fetches ALL members)

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/services/supabase_service.dart';
import '../../../graph/graph.dart';
import '../../../graph/interaction/graph_focus_state.dart'
    show graphFocusProvider, PathSelectPhase;
import '../../../graph/widgets/family_graph_engine_view.dart';
import '../../../graph/widgets/graph_tutorial_overlay.dart';
import '../../../graph/widgets/search_bar.dart';
import '../../../graph/widgets/unlinked_members_sheet.dart'; // v5.9
import '../../../graph/widgets/relationship_picker_flow.dart'; // v5.10
import '../../../graph/widgets/graph_relationship_labels.dart' show GraphPersonData; // v5.10
// v5.41: Pending Invitations sheet (graph-originated invites).
import '../../../graph/widgets/pending_invitations_sheet.dart';
import '../../family/presentation/providers/graph_pending_invitations_provider.dart';
// v5.22: Rearrange-mode toggle (personal layout overrides + edge midpoint bow).
// v5.34: also imports saveAllOverridesTriggerProvider + resetUnsavedOverridesTriggerProvider.
// v5.38: also imports hasUnsavedChangesProvider + saveCompletedTriggerProvider.
import '../../../graph/rearrange/layout_overrides_service.dart'
    show
        LayoutOverridesService,
        PersonalLayoutOverrides,
        personalLayoutOverridesProvider,
        rearrangeModeProvider,
        saveAllOverridesTriggerProvider,
        resetUnsavedOverridesTriggerProvider,
        hasUnsavedChangesProvider,
        saveCompletedTriggerProvider;
import 'add_member_options_sheet.dart';
import 'providers/family_graph_provider.dart'
    show
        FamilyGraphNotifier,
        FlatGraphResult,
        familyGraphProvider,
        graphRealtimeProvider,
        selectedNodeProvider,
        unlinkedPersonIdsProvider; // v5.9
import 'widgets/relationship_legend.dart';
import 'widgets/stats_panel.dart';

// ═══════════════════════════════════════════════════════════════════════
// FAMILY GRAPH SCREEN
// ═══════════════════════════════════════════════════════════════════════

class FamilyGraphScreen extends ConsumerStatefulWidget {
  const FamilyGraphScreen({
    super.key,
    required this.familyId,
    this.familyName,
  });

  final String familyId;
  final String? familyName;

  @override
  ConsumerState<FamilyGraphScreen> createState() => _FamilyGraphScreenState();
}

class _FamilyGraphScreenState extends ConsumerState<FamilyGraphScreen> {
  /// External TransformationController to drive FamilyGraphWidget zoom/pan.
  final TransformationController _graphTransformController =
      TransformationController();

  /// Currently hovered relationship key for legend filtering.
  String? _hoveredRelationshipKey;

  /// Whether the relationship legend is visible.
  bool _showLegend = false;

  /// Whether the filter panel is visible in the bottom toolbar context.
  bool _filterVisible = false;

  /// Whether the search overlay is visible.
  bool _showSearch = false;

  /// v62: Multi-select state. When non-empty, the graph is in
  /// multi-select mode — tapping a node adds/removes it from the
  /// selection. Long-pressing empty canvas exits multi-select.
  Set<String> _selectedNodeIds = <String>{};

  /// v62: Returns true if the graph is in multi-select mode.
  bool get _isMultiSelect => _selectedNodeIds.isNotEmpty;

  /// v60: Incremented to trigger re-centering in FamilyGraphWidget.
  int _recenterKey = 0;

  // v5.26 (Task 1b): Auto-hide the Rearrange-mode instructional banner
  // after 4 seconds. The banner appears when rearrangeModeProvider
  // flips true->ON, then auto-hides (no interaction needed). The
  // exit-X toggle stays visible separately so the user can still exit.
  // To re-summon the banner later, a small "?" icon next to the exit
  // button could be added (deferred — not needed today).
  bool _showRearrangeBanner = false;
  Timer? _rearrangeBannerTimer;

  // v60: Removed _transformPrefsPrefix — no longer saving transform state.

  @override
  void initState() {
    super.initState();
    _restoreTransformState();
    // v5.26 (Task 1b): listen for rearrangeModeProvider true->ON
    // transitions to (re)show the banner + arm the 4s auto-hide timer.
    // We do this in initState via ref.listenToSelf so the listener
    // is wired once and survives rebuilds. The listener callback runs
    // AFTER the provider changes — `previous` is the prior value.
    //
    // NOTE: Riverpod's listenManual callback types the state as `bool?`
    // (nullable) to support providers that may be in a loading/error
    // state. StateProvider<bool> never actually emits null — but the
    // static type is still bool?, so we use `next == true` /
    // `previous == true` instead of the bare bool operators.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.listenManual(rearrangeModeProvider, (previous, next) {
        final turnedOn = next == true && previous != true;
        final turnedOff = next != true;
        if (turnedOn) {
          // Just turned ON — show banner + arm auto-hide.
          _showRearrangeBanner = true;
          _rearrangeBannerTimer?.cancel();
          _rearrangeBannerTimer = Timer(
            const Duration(seconds: 4),
            () {
              if (mounted) {
                setState(() => _showRearrangeBanner = false);
              }
            },
          );
          // Trigger a rebuild so the banner appears immediately.
          setState(() {});
        } else if (turnedOff) {
          // Turned OFF — cancel any pending auto-hide + hide banner
          // immediately (so it doesn't linger if the user exits
          // before the 4s timer fires).
          _rearrangeBannerTimer?.cancel();
          _rearrangeBannerTimer = null;
          _showRearrangeBanner = false;
        }
      });
      // v5.38: Listen for save completion to show the success snackbar.
      ref.listenManual(saveCompletedTriggerProvider, (previous, next) {
        if (next != null && next > (previous ?? 0)) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(
              content: Text('Layout saved successfully'),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 2),
            ),
          );
        }
      });
    });
  }

  @override
  void dispose() {
    // v60: Removed _saveTransformState() — it was a dead write since
    // _restoreTransformState() never reads the saved values (it always
    // resets to identity). Wasted I/O on every screen exit.
    _graphTransformController.dispose();
    _rearrangeBannerTimer?.cancel();
    super.dispose();
  }

  /// v60: Reset transform to identity on screen load. The
  /// FamilyGraphWidget's auto-center logic will compute the correct
  /// matrix for the current family's canvas dimensions.
  Future<void> _restoreTransformState() async {
    _graphTransformController.value = Matrix4.identity();
  }

  // ── Zoom helpers ───────────────────────────────────────────────────
  //
  // v4 (2026-06-18): _zoomIn() and _zoomOut() removed. Zoom is now
  // exclusively via pinch gestures handled by GraphPanZoom.
  // Double-tap-to-zoom (toggle 1x ↔ 2.5x) is also handled by
  // GraphPanZoom, so users have a one-finger zoom option too.

  /// Centers the graph on the root/anchor user by triggering re-centering
  /// in the FamilyGraphWidget via recenterKey.
  void _centerOnRootUser() {
    setState(() {
      _recenterKey++;
      _hoveredRelationshipKey = null;
    });
  }

  /// Opens the Add Member sheet and refreshes graph data when it closes.
  /// v5.41: Passes `fromGraph: true` so that graph-originated invites
  /// (with phone/email) are routed to the pending invitations system
  /// instead of creating an unlinked Person node immediately.
  Future<void> _openAddMember() async {
    await showAddMemberOptions(
      context,
      familyId: widget.familyId,
      fromGraph: true,
    );

    if (mounted) {
      // v60: Single cache clear + invalidation. Removed the 1500ms
      // double-refresh — it caused a visible double-reload flicker and
      // wasted bandwidth. Supabase Realtime (graphRealtimeProvider)
      // handles delayed propagation automatically.
      FamilyGraphNotifier.clearCache(widget.familyId);
      ref.invalidate(familyGraphProvider(widget.familyId));
      // v5.41: Also refresh pending invitations in case an invite was sent.
      ref.invalidate(graphPendingInvitationsProvider(widget.familyId));
    }
  }

  /// Manual refresh — forces a complete re-fetch of graph data.
  void _refreshGraph() {
    ref.invalidate(familyGraphProvider(widget.familyId));
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Guard: ensure familyId is valid before proceeding
    if (widget.familyId.isEmpty) {
      return Scaffold(
        backgroundColor: KinrelColors.darkBackground,
        appBar: _buildAppBar(),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.family_restroom,
                  color: KinrelColors.textDim, size: 48),
              const SizedBox(height: 16),
              const Text('No family selected',
                  style: TextStyle(
                      color: KinrelColors.textSecondaryDark,
                      fontFamily: 'DMSans',
                      fontSize: 14)),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () { if (context.canPop()) { context.pop(); } else { context.go('/family/${widget.familyId}'); } },
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Go back'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: KinrelColors.orange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Watch the realtime provider to auto-invalidate graph data on changes
    ref.watch(graphRealtimeProvider(widget.familyId));
    final graphAsync = ref.watch(familyGraphProvider(widget.familyId));

    return Scaffold(
      // FIX (keyboard-resize): Prevent the keyboard from shrinking the
      // graph body. The graph manages its own layout and camera — a body
      // resize would cause the LayoutBuilder to fire with smaller
      // constraints, corrupting the camera viewport rect and making
      // nodes/edges disappear + background turn white. Bottom sheets
      // handle their own viewInsets.bottom padding via isScrollControlled.
      resizeToAvoidBottomInset: false,
      backgroundColor: KinrelColors.darkBackground,
      appBar: _buildAppBar(),
      body: GraphTutorialOverlay(
        child: Stack(
          children: [
            graphAsync.when(
              loading: _buildLoadingState,
              error: _buildErrorState,
              data: _buildDataState,
            ),
            // Search overlay — shown when _showSearch is true.
            if (_showSearch)
              GraphSearchBar(
                familyId: widget.familyId,
                persons: graphAsync.valueOrNull?.persons ?? const [],
                onResultTap: (memberId) {
                  setState(() => _showSearch = false);
                  _focusOnMember(memberId, graphAsync.valueOrNull);
                },
                onClose: () => setState(() => _showSearch = false),
              ),
          ],
        ),
      ),
    );
  }

  /// Centers the camera on the member with [memberId] by bumping the
  /// recenter key. The actual transform is applied by FamilyGraphWidget's
  /// auto-center logic when it sees the recenterKey change.
  ///
  /// Note: this is a simplified jump-to-person — it triggers a full
  /// re-center on the anchor. A more precise "center on this specific
  /// node" would require access to the layout positions, which live
  /// inside FamilyGraphWidget. For now, the search result tap selects
  /// the node (via selectedNodeProvider) so the user can see it
  /// highlighted.
  void _focusOnMember(String memberId, FlatGraphResult? graphData) {
    // Select the node so it's visually highlighted.
    ref.read(selectedNodeProvider.notifier).state = memberId;
    // Trigger re-centering so the graph fits in view.
    setState(() {
      _recenterKey++;
    });
  }

  // ── AppBar ────────────────────────────────────────────────────────
  //
  // v4 (2026-06-18): Removed Zoom In / Zoom Out buttons per user request.
  // Users now zoom naturally with two-finger pinch gestures. The custom
  // GraphPanZoom widget handles pinch-to-zoom, two-finger panning, and
  // double-tap-to-zoom — no on-screen zoom buttons needed.
  //
  // Layout: [Back] [Family Name] --- [Add Member]

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: KinrelColors.darkCard,
      foregroundColor: KinrelColors.textWhite,
      elevation: 0,
      // BackButton is RTL-aware — it renders an arrow_back in LTR and an
      // arrow_forward in RTL automatically, and pops via Navigator.
      leading: const BackButton(),
      title: Text(
        widget.familyName ?? 'Family Graph',
        style: TextStyle(
          fontFamily: KinrelTypography.displayFont,
          fontWeight: FontWeight.w600,
          fontSize: 18,
        ),
      ),
      // v5.25 (distraction-free Rearrange): Hide AppBar actions during
      // Rearrange mode. Only the back arrow + family name title stay
      // visible for orientation. The map/search/Add actions clutter
      // the screen mid-drag and risk accidental taps.
      actions: ref.watch(rearrangeModeProvider)
          ? const []
          : [
              // Map toggle — opens the family map view (MapLibre).
              IconButton(
                icon: const Icon(Icons.map_outlined, size: 22),
                tooltip: 'Family map',
                onPressed: () => context.push('/family/${widget.familyId}/map'),
              ),
              // Search button — opens the graph search overlay.
              IconButton(
                icon: const Icon(Icons.search_rounded, size: 22),
                tooltip: 'Search family',
                onPressed: () => setState(() => _showSearch = true),
              ),
              // Add Member button — primary action, always visible
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: TextButton.icon(
                  onPressed: _openAddMember,
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: const Text('Add'),
                  style: TextButton.styleFrom(
                    foregroundColor: KinrelColors.orange,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  // ── Loading State ─────────────────────────────────────────────────

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(
              color: KinrelColors.orange, strokeWidth: 3),
          const SizedBox(height: 16),
          const Text('Loading family graph...',
              style: TextStyle(
                  color: KinrelColors.textSecondaryDark,
                  fontFamily: 'DMSans',
                  fontSize: 14)),
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: _refreshGraph,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Refresh'),
            style: TextButton.styleFrom(
              foregroundColor: KinrelColors.orange,
            ),
          ),
        ],
      ),
    );
  }

  // ── Error State ───────────────────────────────────────────────────

  Widget _buildErrorState(Object error, StackTrace stackTrace) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                color: KinrelColors.orange, size: 48),
            const SizedBox(height: 16),
            const Text('Something went wrong',
                style: TextStyle(
                    color: KinrelColors.textWhite,
                    fontFamily: 'Outfit',
                    fontWeight: FontWeight.w600,
                    fontSize: 18)),
            const SizedBox(height: 8),
            Text(error.toString(),
                style: const TextStyle(
                    color: KinrelColors.textSecondaryDark,
                    fontFamily: 'DMSans',
                    fontSize: 13),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _refreshGraph,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Tap to retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: KinrelColors.orange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                  ),
                ),
                const SizedBox(width: 12),
                // Direct DB query fallback button
                OutlinedButton.icon(
                  onPressed: _directDBRefresh,
                  icon: const Icon(Icons.storage_outlined, size: 18),
                  label: const Text('Direct query'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: KinrelColors.orange,
                    side: const BorderSide(color: KinrelColors.orange),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Direct DB Refresh ─────────────────────────────────────────────
  //
  // Bypasses the RPC and queries Person + Relationship tables directly.
  // This is a fallback for when the `get_family_graph` RPC fails or
  // returns incomplete data.

  Future<void> _directDBRefresh() async {
    try {
      final client = ref.read(supabaseProvider);
      if (client == null) {
        debugPrint('[DirectDBRefresh] Supabase client not available');
        return;
      }

      // Query all non-deleted persons in this family
      final persons = await client
          .from('Person')
          .select('id, name, gender, "generationIndex", "isAnchor", "photoUrl", "isDeceased", visibility, username, "familyId"')
          .eq('familyId', widget.familyId)
          .isFilter('deletedAt', null);

      // Query all relationships in this family
      // Use resilient column selection with fallback to select(*)
      List<Map<String, dynamic>> relationships;
      try {
        relationships = await client
            .from('Relationship')
            .select('id, "fromPersonId", "toPersonId", "relationshipKey", is_private, "familyId"')
            .eq('familyId', widget.familyId);
      } catch (e) {
        debugPrint('[DirectDBRefresh] Specific column select failed, trying select(*): $e');
        relationships = await client
            .from('Relationship')
            .select('*')
            .eq('familyId', widget.familyId);
      }

      debugPrint(
        '[DirectDBRefresh] Found ${persons.length} persons, '
        '${relationships.length} relationships for ${widget.familyId}',
      );

      // Force invalidate to trigger a full re-fetch
      ref.invalidate(familyGraphProvider(widget.familyId));
    } catch (e) {
      debugPrint('[DirectDBRefresh] Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Direct query failed: $e'),
            backgroundColor: KinrelColors.error,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // ── Data State ────────────────────────────────────────────────────

  Widget _buildDataState(FlatGraphResult graph) {
    final persons = graph.toPersonDataList();

    // If no persons at all, show the empty state with add member FAB
    if (persons.isEmpty) return _buildEmptyState();

    // Determine which generations are present (used by the stats panel
    // for the "totalGenerations" count).
    final presentGenerations = <int>{};
    for (final p in persons) {
      presentGenerations.add(p.generationIndex);
    }

    final bottomPadding = MediaQuery.of(context).padding.bottom;

    // NOTE: We do NOT add topPadding here because the Scaffold already has
    // an AppBar, which consumes the status bar height. The body coordinate
    // system starts at y=0 below the AppBar. Using topPadding would
    // double-count the safe area.

    // Calculate safe bottom offset for FAB above toolbar
    // Toolbar height = 48px + 8px bottom margin
    final fabBottomOffset = bottomPadding + 72;

    // v4.10: Compute the REAL bottom chrome height for the camera.
    // The bottom overlay stack (from screen bottom upward) is:
    //   1. OS safe area: bottomPadding
    //   2. Toolbar bottom margin: 24px (Positioned bottom: bottomPadding + 24)
    //   3. Toolbar height: 48px (each button is height: 48)
    //   4. Gap between toolbar top and stats panel bottom: 0 (stats sit at fabBottomOffset = bottomPadding + 72)
    //   5. StatsPanel height: ~124px (padding 12 all sides + 4 stat rows ~20px each + gaps 6+6+8 = ~100 content + 24 padding)
    //
    // Total bottom chrome = bottomPadding + 72 (toolbar bottom + height) + 124 (stats panel) = bottomPadding + 196
    // The StatsPanel is the HIGHEST element, so its top edge defines the true reserved bottom space.
    //
    // The AppBar is already excluded from the Scaffold body (body starts below AppBar),
    // so topChromeHeight = 0 (NOT 56 as previously assumed).
    const statsPanelEstimatedHeight = 124.0;
    final bottomChromeHeight = bottomPadding + 72 + statsPanelEstimatedHeight;

    return Stack(
      children: [
        // Main graph content
        // v106: The generation filter bar ("All" / "Self" / "Parents" /
        // ... chips) has been REMOVED per user request — the graph now
        // starts directly below the AppBar, reclaiming the 56px the
        // filter bar occupied. The graph expands to fill the space.
        Column(
          children: [
            if (graph.isTruncated) _buildTruncationBanner(graph),

            // P3.7: "On this day" banner — shows when any persons have
            // a birthday or anniversary today.
            if (_onThisDayCount(graph) > 0) _buildOnThisDayBanner(graph),

            Expanded(
              // v4.18: Removed the Padding wrapper (v4.17) that created a
              // visible dark rectangle at the bottom. The graph canvas now
              // extends to the full height. The stats panel + toolbar are
              // drawn as Positioned overlays on top with semi-transparent
              // backgrounds, so they remain visible. The graph's gradient
              // background fills the entire area — no visible rectangle.
              child: FamilyGraphEngineView(
                familyId: widget.familyId,
                recenterKey: _recenterKey,
                bottomChromeHeight: bottomChromeHeight,
                topChromeHeight: 0, // AppBar already excluded by Scaffold
              ),
            ),
          ],
        ),

        // P2.1: "How We're Connected" FAB — visible when family has ≥2 members
        // AND NOT in Rearrange mode (v5.25 distraction-free gate).
        // Premium: neutral dark (NOT orange — orange is reserved for the
        // single primary action). Positioned bottom-left to balance the
        // orange Share FAB on bottom-right.
        if (graph.persons.length >= 2 && !ref.watch(rearrangeModeProvider))
          Positioned(
            right: Directionality.of(context) == TextDirection.rtl ? null : 20,
            left: Directionality.of(context) == TextDirection.rtl ? 20 : null,
            bottom: MediaQuery.of(context).padding.bottom + 80,
            child: _buildHowConnectedFab(),
          ),

        // v5.22: Rearrange-mode toggle FAB + (when active) status banner.
        // Positioned TOP-LEFT (away from the bottom Share/HowConnected FABs).
        // While Rearrange mode is ON, long-press on a node repositions it
        // (PART 1), long-press on a midpoint dot bows the curve (PART 2),
        // and the existing long-press → info-sheet gesture is suspended.
        // Outside Rearrange mode, all existing gestures work unchanged.
        //
        // v5.26 (Task 1b): The banner now auto-hides 4 seconds after
        // Rearrange mode is toggled ON (uses _showRearrangeBanner state
        // driven by a Timer in initState, NOT directly tied to
        // rearrangeModeProvider). The exit toggle stays visible the
        // whole time — only the instructional banner disappears.
        // v5.26 (Task 2b): When Rearrange is ON AND the viewer has
        // saved overrides, also show a "Reset all my custom positions"
        // button next to the toggle (Row wraps both buttons + resets).
        // v5.29 Fix 3: Moved up from top+60 to top+8 so the buttons sit
        // just below the AppBar (right under the Add button area).
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 16,
          child: _buildRearrangeControlsCluster(),
        ),
        if (_showRearrangeBanner)
          Positioned(
            top: MediaQuery.of(context).padding.top + 58,
            left: 16,
            right: 16,
            child: _buildRearrangeBanner(),
          ),

        // v5.84: COMBINED "Link & Invites" button — replaces the two
        // separate pills with a single button showing the combined count
        // of unlinked members + pending invitations. Tapping opens a
        // single bottom sheet with two sections.
        if (!ref.watch(rearrangeModeProvider))
          Builder(builder: (context) {
            final unlinkedCount =
                ref.watch(unlinkedPersonIdsProvider(widget.familyId)).length;
            final inviteCount = ref.watch(
                pendingGraphInvitationCountProvider(widget.familyId));
            final totalCount = unlinkedCount + inviteCount;
            if (totalCount == 0) return const SizedBox.shrink();
            return Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 16,
              child: _buildCombinedLinkInvitesButton(
                unlinkedCount: unlinkedCount,
                inviteCount: inviteCount,
              ),
            );
          }),

        // REMOVED: Floating legend button (top-right).
        // The legend is now triggered from the bottom dock's Help/Legend
        // button — one entry point, not two. The legend card still appears
        // below the bottom dock when toggled.

        // V2.1 Stats panel (bottom-start, above bottom toolbar)
        // Directional positioning: bottom-left in LTR, bottom-right in RTL
        // so the stats panel mirrors to the leading edge of the layout.
        // v5.25 (distraction-free Rearrange): hide during Rearrange mode.
        if (!ref.watch(rearrangeModeProvider))
          Positioned(
            right: Directionality.of(context) == TextDirection.rtl ? 16 : null,
            left: Directionality.of(context) == TextDirection.rtl ? null : 16,
            bottom: fabBottomOffset,
            child: StatsPanel(
              totalMembers: graph.persons.length,
              totalConnections: graph.relationships.length,
              totalGenerations: presentGenerations.length,
              isTruncated: graph.isTruncated,
            ),
          ),

        // Bottom toolbar — Center, Add Member, Filter, Help
        // v42 FIX: Removed PhysicalModel(transparent) and IgnorePointer
        // which caused the toolbar to be invisible/untappable on Android.
        // _buildBottomToolbar() already returns a Container with its own
        // BoxShadow, so no wrapper is needed.
        // v62: Show multi-select bar instead when in multi-select mode.
        // v5.25 (distraction-free Rearrange): hide during Rearrange mode.
        if (!ref.watch(rearrangeModeProvider))
          Positioned(
            bottom: bottomPadding + 24,
            left: 0,
            right: 0,
            child: Center(
              child: _isMultiSelect
                  ? _buildMultiSelectBar()
                  : _buildBottomToolbar(),
            ),
          ),
      ],
    );
  }

  /// v62: Multi-select action bar shown when one or more nodes are
  /// selected. Shows the count + actions: Add Relationship, Hide, Cancel.
  Widget _buildMultiSelectBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${_selectedNodeIds.length} selected',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: KinrelColors.orange,
            ),
          ),
          const SizedBox(width: 16),
          // Add Relationship between selected nodes.
          if (_selectedNodeIds.length == 2)
            _multiSelectAction(
              icon: Icons.link_rounded,
              label: 'Add Rel',
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Open the Relationship Builder from the family '
                      'detail screen to connect these two people.',
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                setState(() => _selectedNodeIds = {});
              },
            ),
          // Clear selection.
          _multiSelectAction(
            icon: Icons.close_rounded,
            label: 'Cancel',
            onTap: () => setState(() => _selectedNodeIds = {}),
          ),
        ],
      ),
    );
  }

  Widget _multiSelectAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return IconButton(
      onPressed: onTap,
      icon: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: KinrelColors.textWhite),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: KinrelColors.textSilver,
            ),
          ),
        ],
      ),
    );
  }

  // ── Empty State ───────────────────────────────────────────────────

  // ── P2.1: "How We're Connected" FAB + path-select flow ───────────────

  Widget _buildHowConnectedFab() {
    final focusState = ref.watch(graphFocusProvider);
    final inPathSelectMode = focusState.pathSelectPhase != PathSelectPhase.idle;

    return Semantics(
      label: inPathSelectMode
          ? 'Cancel path selection'
          : 'How are we connected? Tap to start, then tap any two people.',
      button: true,
      child: FloatingActionButton(
        heroTag: 'how_connected_fab',
        // Premium: neutral dark card color — NOT orange.
        // Orange is reserved for the single primary action (Share FAB).
        backgroundColor: KinrelColors.darkCard,
        foregroundColor: KinrelColors.textWhite,
        elevation: 4,
        onPressed: () {
          if (inPathSelectMode) {
            ref.read(graphFocusProvider.notifier).exitPathSelectMode();
          } else {
            ref.read(graphFocusProvider.notifier).enterPathSelectMode();
            SemanticsService.announce(
                'Path select mode. Tap the first person.', TextDirection.ltr);
          }
        },
        child: Icon(
          inPathSelectMode ? Icons.close : Icons.timeline,
          size: 24,
        ),
      ),
    );
  }

  // v5.22: Rearrange-mode toggle FAB. While ON, long-press on a node
  // repositions it (PART 1) and long-press on a midpoint dot bows the
  // curve (PART 2). The existing long-press → info-sheet gesture is
  // suspended while active. Tap the FAB again (or long-press empty
  // canvas) to exit.
  //
  // v5.26 (Task 1a): Changed the active-state icon from Icons.check
  // (which read as "Save" and got confused with the per-drag
  // SaveLockPill) to Icons.close (X) — unambiguously means "exit
  // Rearrange mode", distinct from the per-drag Save/Cancel pill which
  // commits one specific change. Both are needed: the X exits the
  // whole Rearrange MODE (session scope), the SaveLockPill commits a
  // single EDIT (per-drag scope).
  Widget _buildRearrangeToggleButton() {
    final isOn = ref.watch(rearrangeModeProvider);
    return Semantics(
      label: isOn
          ? 'Exit rearrange mode'
          : 'Enter rearrange mode — drag nodes and curve dots',
      button: true,
      child: FloatingActionButton.small(
        heroTag: 'rearrange_toggle',
        backgroundColor:
            isOn ? KinrelColors.tealAccent : KinrelColors.darkCard,
        foregroundColor: isOn ? Colors.black : KinrelColors.textWhite,
        elevation: 4,
        onPressed: () {
          ref.read(rearrangeModeProvider.notifier).state = !isOn;
        },
        child: Icon(isOn ? Icons.close : Icons.open_with, size: 20),
      ),
    );
  }

  // v5.26 (Task 2b): Cluster that wraps the Rearrange toggle + (when
  // the viewer has at least one saved override) a "Reset all" button
  // next to it. Both buttons live in a Row so they share the same
  // top-left Positioned slot.
  Widget _buildRearrangeControlsCluster() {
    final isOn = ref.watch(rearrangeModeProvider);
    if (!isOn) {
      // Outside Rearrange mode: just the toggle (no Save/Reset buttons).
      return _buildRearrangeToggleButton();
    }
    // v5.34: New workflow — persistent Save + Reset buttons in the
    // top toolbar. Users move multiple nodes freely (no per-drag
    // SaveLockPill), then click Save once to commit ALL changes.
    // Reset discards all unsaved moves (restores to the last saved
    // layout). Both buttons are ALWAYS visible while Rearrange mode
    // is active — they never hide.
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildRearrangeToggleButton(),
        const SizedBox(width: 8),
        _buildSaveAllButton(),
        const SizedBox(width: 8),
        _buildResetAllButton(),
      ],
    );
  }

  // v5.34: Persistent Save button — commits ALL unsaved node positions
  // + edge waypoints in one operation. Increments
  // saveAllOverridesTriggerProvider; the engine view watches this and
  // iterates over _rearrangeLiveNodeOverrides + _rearrangeLiveEdgeWaypoints,
  // saving each entry via LayoutOverridesService.
  // v5.38: Save button — enabled ONLY when there are unsaved changes
  // (hasUnsavedChangesProvider is true). Disabled/dimmed when there
  // are no changes. Shows "Saving layout..." on tap, then the engine
  // view's _onSaveAllTrigger runs async and increments
  // saveCompletedTriggerProvider — the screen listens for that and
  // shows "Layout saved successfully".
  Widget _buildSaveAllButton() {
    final hasChanges = ref.watch(hasUnsavedChangesProvider);
    return Semantics(
      label: 'Save all rearranged positions',
      button: true,
      enabled: hasChanges,
      child: FloatingActionButton.small(
        heroTag: 'rearrange_save_all',
        backgroundColor: hasChanges
            ? KinrelColors.tealAccent
            : KinrelColors.darkCard.withValues(alpha: 0.5),
        foregroundColor: hasChanges ? Colors.black : KinrelColors.textDim,
        elevation: hasChanges ? 4 : 0,
        // v5.38: onPressed is null when disabled (no unsaved changes).
        // This makes the button non-clickable + Flutter applies the
        // disabled visual style automatically.
        onPressed: hasChanges
            ? () {
                ref.read(saveAllOverridesTriggerProvider.notifier).state++;
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  const SnackBar(
                    content: Text('Saving layout...'),
                    behavior: SnackBarBehavior.floating,
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            : null,
        child: const Icon(Icons.check_rounded, size: 20),
      ),
    );
  }

  // v5.34: Reset button — discards ALL unsaved moves made during the
  // current Rearrange session. Restores to the LAST SAVED layout (whatever
  // was in the DB when Rearrange mode was entered). Does NOT wipe the DB
  // — saved overrides are preserved, only unsaved live changes are
  // discarded.
  Widget _buildResetAllButton() {
    return Semantics(
      label: 'Discard unsaved rearrangements',
      button: true,
      child: FloatingActionButton.small(
        heroTag: 'rearrange_reset_all',
        backgroundColor: KinrelColors.darkCard,
        foregroundColor: KinrelColors.orange,
        elevation: 4,
        onPressed: () {
          // v5.34: Increment the reset-unsaved trigger. The engine
          // view watches this and clears _rearrangeLiveNodeOverrides +
          // _rearrangeLiveEdgeWaypoints (the unsaved changes). The
          // graph snaps back to the saved layout.
          ref.read(resetUnsavedOverridesTriggerProvider.notifier).state++;
          // v5.37: Show snackbar feedback so the user knows the Reset
          // button was tapped.
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(
              content: Text('Resetting to saved layout...'),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 1),
            ),
          );
        },
        child: const Icon(Icons.restart_alt_outlined, size: 20),
      ),
    );
  }

  Widget _buildRearrangeBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: KinrelColors.tealAccent.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: KinrelColors.tealAccent.withValues(alpha: 0.6),
            width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.open_with,
              size: 16, color: KinrelColors.tealAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Rearrange mode — drag nodes / curve dots. '
              'Tap the X button to exit.',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: KinrelColors.textWhite,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // v5.84: Combined Link & Invites button — single entry point with
  // combined count badge. Opens a bottom sheet with two sections.
  Widget _buildCombinedLinkInvitesButton({
    required int unlinkedCount,
    required int inviteCount,
  }) {
    final totalCount = unlinkedCount + inviteCount;

    return Semantics(
      label: '$totalCount items need attention: $unlinkedCount unlinked members, '
          '$inviteCount pending invitations. Tap to see the list.',
      button: true,
      child: GestureDetector(
        onTap: () => _showCombinedLinkInvitesSheet(
          unlinkedCount: unlinkedCount,
          inviteCount: inviteCount,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: KinrelColors.darkCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: KinrelColors.orange.withValues(alpha: 0.4),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.notifications_active_rounded,
                size: 16,
                color: KinrelColors.orange,
              ),
              const SizedBox(width: 6),
              Text(
                'Inbox',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textWhite,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: KinrelColors.orange,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$totalCount',
                  style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.darkCard,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // v5.84: Combined bottom sheet with two sections.
  void _showCombinedLinkInvitesSheet({
    required int unlinkedCount,
    required int inviteCount,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: KinrelColors.textDim,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Title
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  'Link & Invites',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                  ),
                ),
              ),
              const Divider(color: Color(0x1AFFFFFF), height: 1),
              // Content
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    // Section 1: Unlinked members
                    _buildSectionHeader(
                      'Unlinked members',
                      unlinkedCount,
                      KinrelColors.amber,
                    ),
                    if (unlinkedCount > 0)
                      _buildUnlinkedMembersList()
                    else
                      _buildEmptySection('All members are linked'),
                    const SizedBox(height: 12),
                    // Section 2: Pending invitations
                    _buildSectionHeader(
                      'Pending invitations',
                      inviteCount,
                      KinrelColors.tealAccent,
                    ),
                    if (inviteCount > 0)
                      _buildPendingInvitesList()
                    else
                      _buildEmptySection('No pending invitations'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Row(
        children: [
          Text(
            '$title ($count)',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptySection(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Text(
        message,
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 13,
          color: KinrelColors.textDim,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  Widget _buildUnlinkedMembersList() {
    final unlinkedIds = ref.watch(unlinkedPersonIdsProvider(widget.familyId));
    final graph = ref.watch(familyGraphProvider(widget.familyId)).valueOrNull;
    if (graph == null) return _buildEmptySection('Loading...');

    final personsById = <String, Map<String, dynamic>>{};
    for (final p in graph.persons) {
      final id = p['id'] as String?;
      if (id != null) personsById[id] = p;
    }

    return Column(
      children: unlinkedIds.map((id) {
        final person = personsById[id];
        final name = (person?['name'] as String?) ?? 'Unknown';
        return ListTile(
          leading: Icon(Icons.link_off, color: KinrelColors.amber, size: 20),
          title: Text(name, style: TextStyle(
            color: KinrelColors.textWhite,
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 14,
          )),
          subtitle: Text('No relationships defined', style: TextStyle(
            color: KinrelColors.textDim, fontSize: 12,
          )),
          trailing: Icon(Icons.chevron_right, color: KinrelColors.textDim),
          onTap: () {
            Navigator.pop(context);
            showRelationshipPickerFlow(
              context: context,
              ref: ref,
              familyId: widget.familyId,
              sourcePerson: GraphPersonData(id: id, name: name),
            );
          },
        );
      }).toList(),
    );
  }

  Widget _buildPendingInvitesList() {
    return Consumer(builder: (context, ref, _) {
      final invitationsAsync =
          ref.watch(graphPendingInvitationsProvider(widget.familyId));
      final invitations = invitationsAsync.valueOrNull ?? [];

      if (invitations.isEmpty) {
        return _buildEmptySection('No pending invitations');
      }

      return Column(
        children: invitations.map((inv) {
          return ListTile(
            leading: Icon(Icons.mail_outline, color: KinrelColors.tealAccent, size: 20),
            title: Text(inv.recipientName ?? 'Unknown', style: TextStyle(
              color: KinrelColors.textWhite,
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
            )),
            subtitle: Text(
              '${inv.specificLabelAtoB ?? inv.relationshipKey} • ${inv.status}',
              style: TextStyle(color: KinrelColors.textDim, fontSize: 12),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () async {
                    final notifier = ref.read(
                      graphPendingInvitationsProvider(widget.familyId).notifier,
                    );
                    await notifier.cancelInvitation(inv.id);
                  },
                  child: Text('Cancel', style: TextStyle(
                    color: Colors.red.shade300, fontSize: 12,
                  )),
                ),
              ],
            ),
          );
        }).toList(),
      );
    });
  }

  // v5.9: Unlinked Members button — shows count badge, opens bottom sheet.
  Widget _buildUnlinkedMembersButton() {
    final unlinkedIds = ref.watch(unlinkedPersonIdsProvider(widget.familyId));
    final count = unlinkedIds.length;

    return Semantics(
      label: '$count members need linking. Tap to see the list.',
      button: true,
      child: GestureDetector(
        onTap: () {
          showUnlinkedMembersSheet(
            context,
            ref,
            widget.familyId,
            onPersonSelected: (personId, personName) {
              // v5.10: Open the shared relationship picker flow directly
              // (instead of the old focus+snackbar dead-end). The user
              // picks ANY other person to connect this unlinked member to.
              showRelationshipPickerFlow(
                context: context,
                ref: ref,
                familyId: widget.familyId,
                sourcePerson: GraphPersonData(
                  id: personId,
                  name: personName,
                ),
                onComplete: (created) {
                  if (created) {
                    // Relationship was created — unlinkedPersonIdsProvider
                    // will reactively update (it watches familyGraphProvider
                    // which is invalidated by createRelationship).
                    // If there are still unlinked members, the user can
                    // tap the button again to see the updated list.
                  }
                },
              );
            },
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: KinrelColors.darkCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: KinrelColors.amber.withValues(alpha: 0.4),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.link_off,
                size: 16,
                color: KinrelColors.amber,
              ),
              const SizedBox(width: 6),
              Text(
                'Link',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textWhite,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: KinrelColors.amber,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.darkCard,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // v5.41: Pending Invitations button — shows count badge, opens bottom sheet
  // that lists graph-originated invitations (people invited from the graph
  // who haven't accepted yet). The graph itself does NOT show these as
  // nodes — only confirmed members appear in the graph.
  Widget _buildPendingInvitationsButton() {
    final count = ref.watch(pendingGraphInvitationCountProvider(widget.familyId));

    return Semantics(
      label: '$count pending invitations. Tap to see the list.',
      button: true,
      child: GestureDetector(
        onTap: () {
          showPendingInvitationsSheet(
            context,
            ref,
            widget.familyId,
            onInvitationCancelled: () {
              // The provider auto-refreshes via realtime, but we
              // invalidate to force an immediate refresh.
              ref.invalidate(graphPendingInvitationsProvider(widget.familyId));
            },
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: KinrelColors.darkCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: KinrelColors.tealAccent.withValues(alpha: 0.4),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.mail_outline,
                size: 16,
                color: KinrelColors.tealAccent,
              ),
              const SizedBox(width: 6),
              Text(
                'Invites',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textWhite,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: KinrelColors.tealAccent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.darkCard,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Empty state ──────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Stack(
      children: [
        EmptyState(
          memberCount: 0,
          familyId: widget.familyId,
          onAddMember: _openAddMember,
        ),
        // Add Member FAB — visible even in empty state
        // Directional positioning: bottom-end (bottom-right in LTR,
        // bottom-left in RTL).
        Positioned(
          right: Directionality.of(context) == TextDirection.rtl ? null : 20,
          left: Directionality.of(context) == TextDirection.rtl ? 20 : null,
          bottom: bottomPadding + 20,
          child: FloatingActionButton(
            heroTag: 'empty_add_member_fab',
            backgroundColor: KinrelColors.orange,
            foregroundColor: Colors.white,
            elevation: 6,
            onPressed: _openAddMember,
            child: const Icon(Icons.person_add_alt_1_rounded, size: 24),
          ),
        ),
      ],
    );
  }

  // ── Bottom Toolbar ─────────────────────────────────────────────────
  //
  // Per reference design: Center, Add Member, Filter, Help at bottom center.
  // Zoom In/Out are in the AppBar. Add Member is prominently placed
  // in the toolbar for guaranteed visibility and one-tap access.

  Widget _buildBottomToolbar() {
    return Container(
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Recenter/fit-to-screen
          _toolbarButton(
            icon: Icons.center_focus_strong_outlined,
            tooltip: 'Center on Root',
            onPressed: _centerOnRootUser,
          ),
          // Divider
          _divider(),
          // Filter
          _toolbarButton(
            icon: Icons.filter_list_rounded,
            tooltip: 'Filter',
            onPressed: () {
              setState(() => _filterVisible = !_filterVisible);
            },
            highlighted: _filterVisible,
          ),
          // Divider
          _divider(),
          // Help / Legend
          _toolbarButton(
            icon: Icons.help_outline_rounded,
            tooltip: 'Legend',
            onPressed: () => setState(() => _showLegend = !_showLegend),
            highlighted: _showLegend,
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    return Container(
      width: 1,
      height: 24,
      color: Colors.white.withValues(alpha: 0.1),
      margin: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  Widget _toolbarButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    bool highlighted = false,
    bool isPrimary = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(24),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: isPrimary
                ? KinrelColors.orange.withValues(alpha: 0.2)
                : highlighted
                    ? KinrelColors.orange.withValues(alpha: 0.15)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Icon(
            icon,
            size: 22,
            color: isPrimary
                ? KinrelColors.orange
                : highlighted
                    ? KinrelColors.orange
                    : KinrelColors.textDim,
          ),
        ),
      ),
    );
  }

  // ── Truncation Banner ─────────────────────────────────────────────

  Widget _buildTruncationBanner(FlatGraphResult graph) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: KinrelColors.darkElevated,
        border: Border(bottom: BorderSide(color: KinrelColors.amber, width: 1)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: KinrelColors.amber, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              graph.totalCount != null
                  ? 'Showing first ${graph.persons.length} of ${graph.totalCount} persons.'
                  : 'Showing first ${graph.persons.length} persons.',
              style: const TextStyle(
                  color: KinrelColors.textSecondaryDark,
                  fontFamily: 'DMSans',
                  fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  // ── P3.7: "On this day" banner ──────────────────────────────────

  /// Counts how many persons in [graph] have an "on this day" event
  /// (birthday today or anniversary today).
  int _onThisDayCount(FlatGraphResult graph) {
    final now = DateTime.now();
    var count = 0;
    for (final p in graph.persons) {
      final dobStr = p['dateOfBirth'] as String?;
      if (dobStr != null && dobStr.isNotEmpty) {
        final dob = DateTime.tryParse(dobStr);
        if (dob != null && dob.month == now.month && dob.day == now.day) {
          count++;
          continue;
        }
      }
      final annivStr = p['anniversaryDate'] as String?;
      if (annivStr != null && annivStr.isNotEmpty) {
        final anniv = DateTime.tryParse(annivStr);
        if (anniv != null &&
            anniv.month == now.month &&
            anniv.day == now.day) {
          count++;
        }
      }
    }
    return count;
  }

  /// Builds the "On this day" banner shown above the graph when any
  /// persons have a birthday or anniversary today.
  Widget _buildOnThisDayBanner(FlatGraphResult graph) {
    final count = _onThisDayCount(graph);
    return Semantics(
      liveRegion: true,
      label: '$count events on this day. Tap a badge to view.',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: const BoxDecoration(
          color: KinrelColors.darkElevated,
          border: Border(
            bottom: BorderSide(color: KinrelColors.orange, width: 1),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.today, color: KinrelColors.orange, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$count event${count == 1 ? '' : 's'} on this day. '
                'Tap a badge to view.',
                style: const TextStyle(
                  color: KinrelColors.textWhite,
                  fontFamily: 'DMSans',
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

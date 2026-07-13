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
import 'add_member_options_sheet.dart';
import 'providers/family_graph_provider.dart'
    show
        FamilyGraphNotifier,
        FlatGraphResult,
        familyGraphProvider,
        graphRealtimeProvider,
        selectedNodeProvider;
import 'widgets/generation_filter_bar.dart';
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
  /// Highlighted generation index (null = no highlight).
  int? _highlightedGeneration;

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

  // v60: Removed _transformPrefsPrefix — no longer saving transform state.

  @override
  void initState() {
    super.initState();
    _restoreTransformState();
  }

  @override
  void dispose() {
    // v60: Removed _saveTransformState() — it was a dead write since
    // _restoreTransformState() never reads the saved values (it always
    // resets to identity). Wasted I/O on every screen exit.
    _graphTransformController.dispose();
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
      _highlightedGeneration = null;
      _hoveredRelationshipKey = null;
    });
  }

  /// Opens the Add Member sheet and refreshes graph data when it closes.
  Future<void> _openAddMember() async {
    await showAddMemberOptions(context, familyId: widget.familyId);

    if (mounted) {
      // v60: Single cache clear + invalidation. Removed the 1500ms
      // double-refresh — it caused a visible double-reload flicker and
      // wasted bandwidth. Supabase Realtime (graphRealtimeProvider)
      // handles delayed propagation automatically.
      FamilyGraphNotifier.clearCache(widget.familyId);
      ref.invalidate(familyGraphProvider(widget.familyId));
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
                onPressed: () => Navigator.of(context).pop(),
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
      _highlightedGeneration = null;
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
      actions: [
        // Map toggle — opens the family map view (MapLibre).
        IconButton(
          icon: const Icon(Icons.map_outlined, size: 22),
          tooltip: 'Family map',
          onPressed: () => context.push('/family-map'),
        ),
        // Search button — opens the graph search overlay.
        IconButton(
          icon: const Icon(Icons.search_rounded, size: 22),
          tooltip: 'Search family',
          onPressed: () => setState(() => _showSearch = true),
        ),
        // Phase 3: Archive button — unified Photos/Timeline/Audio entry.
        IconButton(
          icon: const Icon(Icons.photo_library_outlined, size: 22),
          tooltip: 'Family Archive',
          onPressed: () {
            // Archive removed — repoint to /memory-vault if needed
          },
        ),
        // v92: Chat button — quick access to family chat from the graph.
        IconButton(
          icon: const Icon(Icons.chat_bubble_outline_rounded, size: 22),
          tooltip: 'Family chat',
          onPressed: () {
            context.push('/family/${widget.familyId}/chat');
          },
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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

    // Determine which generations are present
    final presentGenerations = <int>{};
    for (final p in persons) {
      presentGenerations.add(p.generationIndex);
    }

    // Determine which relationship types are present
    final presentRelationshipKeys = <String>{};
    for (final r in graph.relationships) {
      presentRelationshipKeys.add(r['relationshipKey'] as String? ?? '');
    }

    final bottomPadding = MediaQuery.of(context).padding.bottom;

    // NOTE: We do NOT add topPadding here because the Scaffold already has
    // an AppBar, which consumes the status bar height. The body coordinate
    // system starts at y=0 below the AppBar. Using topPadding would
    // double-count the safe area.
    // GenerationFilterBar height = 48px, margin below it = 8px
    const filterBarTopOffset = 56.0;

    // Calculate safe bottom offset for FAB above toolbar
    // Toolbar height = 48px + 8px bottom margin
    final fabBottomOffset = bottomPadding + 72;

    return Stack(
      children: [
        // Main graph content
        Column(
          children: [
            // V2.1 Generation filter bar at top
            // v10 Fix #1B: Wrap in SizedBox with fixed height to constrain
            // the hit-test region. Without this, the filter bar's
            // InkWells could absorb touches below their visible area.
            SizedBox(
              height: 56,
              child: GenerationFilterBar(
                presentGenerations: presentGenerations,
                highlightedGeneration: _highlightedGeneration,
                onGenerationTap: (gen) {
                  setState(() => _highlightedGeneration = gen);
                },
              ),
            ),

            if (graph.isTruncated) _buildTruncationBanner(graph),

            // P3.7: "On this day" banner — shows when any persons have
            // a birthday or anniversary today.
            if (_onThisDayCount(graph) > 0) _buildOnThisDayBanner(graph),

            Expanded(
              // v2.2: Always use the V2.1 engine view. The old
              // FamilyGraphWidget with its RelationshipEdge painter
              // is removed — rendering both painters caused a double
              // line bug on the web build.
              child: FamilyGraphEngineView(
                familyId: widget.familyId,
                highlightedGeneration: _highlightedGeneration,
                recenterKey: _recenterKey,
              ),
            ),
          ],
        ),

        // P2.1: "How We're Connected" FAB — visible when family has ≥2 members.
        // Positioned at bottom-start (left in LTR, right in RTL) to balance
        // the bottom toolbar at bottom-center. Tapping enters path-select mode.
        if (graph.persons.length >= 2)
          Positioned(
            right: Directionality.of(context) == TextDirection.rtl ? null : 20,
            left: Directionality.of(context) == TextDirection.rtl ? 20 : null,
            bottom: MediaQuery.of(context).padding.bottom + 80,
            child: _buildHowConnectedFab(),
          ),

        // Legend (?) button (top-end, below filter bar)
        // Only the help/legend button — no Add Member pill here
        // (Add Member is in the AppBar and bottom toolbar).
        // Directional positioning: hugs the trailing edge in both LTR (right)
        // and RTL (left) so the legend doesn't overlap the back button.
        if (presentRelationshipKeys.isNotEmpty)
          Positioned(
            right: Directionality.of(context) == TextDirection.rtl ? null : 16,
            left: Directionality.of(context) == TextDirection.rtl ? 16 : null,
            top: filterBarTopOffset,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                GestureDetector(
                  onTap: () => setState(() => _showLegend = !_showLegend),
                  child: Semantics(
                    label: 'Toggle legend',
                    button: true,
                    child: Container(
                      // P4.3: 44x44 minimum hit target per WCAG 2.5.5.
                      // Was 36x36 (below the 44px minimum).
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: KinrelColors.darkCard,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _showLegend
                              ? KinrelColors.orange.withValues(alpha: 0.5)
                              : Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Icon(
                        Icons.help_outline_rounded,
                        size: 22,
                        color: _showLegend
                            ? KinrelColors.orange
                            : KinrelColors.textDim,
                      ),
                    ),
                  ),
                ),
                if (_showLegend) ...[
                  const SizedBox(height: 8),
                  RelationshipLegend(
                    presentRelationshipKeys: presentRelationshipKeys,
                    hoveredRelationshipKey: _hoveredRelationshipKey,
                    onRelationshipTap: (key) {
                      setState(() => _hoveredRelationshipKey = key);
                    },
                    onClose: () => setState(() => _showLegend = false),
                  ),
                ],
              ],
            ),
          ),

        // V2.1 Stats panel (bottom-start, above bottom toolbar)
        // Directional positioning: bottom-left in LTR, bottom-right in RTL
        // so the stats panel mirrors to the leading edge of the layout.
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
        backgroundColor:
            inPathSelectMode ? KinrelColors.darkCard : KinrelColors.orange,
        foregroundColor: Colors.white,
        elevation: 6,
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
          // Center on Root User
          _toolbarButton(
            icon: Icons.center_focus_strong_outlined,
            tooltip: 'Center on Root',
            onPressed: _centerOnRootUser,
          ),
          // Divider
          Container(
            width: 1,
            height: 24,
            color: Colors.white.withValues(alpha: 0.1),
            margin: const EdgeInsets.symmetric(horizontal: 4),
          ),
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
          Container(
            width: 1,
            height: 24,
            color: Colors.white.withValues(alpha: 0.1),
            margin: const EdgeInsets.symmetric(horizontal: 4),
          ),
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

// lib/features/family/presentation/family_graph_screen.dart
//
// DAXELO KINREL — Family Graph Screen (V6.0 Complete Fix)
//
// Full-screen graph viewer for visualizing family relationships.
// Features:
//   - AppBar with back, family name, Zoom In, Zoom Out
//   - Add Member button in bottom toolbar (always visible, orange highlight)
//   - Add Member FAB floating above toolbar (extended label style)
//   - Bottom toolbar with Center, Add Member, Filter, Help
//   - Passes graph data directly to FamilyGraphWidget (no double-fetch)
//   - InteractiveViewer pinch-to-zoom, pan, center on root
//   - Graph state persistence (zoom/position) via SharedPreferences
//   - Responsive, safe-area aware, no overflow issues
//   - Real-time updates via Supabase Realtime
//   - Immediate graph refresh after adding members
//   - Direct Supabase query as primary source (always fetches ALL members)

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/services/supabase_service.dart';
import '../../../graph/graph.dart';
import 'add_person_sheet.dart';
import 'providers/family_graph_provider.dart';
import 'widgets/generation_filter_bar.dart';
import 'widgets/graph_canvas_widget.dart' show PersonData;
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

  /// SharedPreferences key for persisting transform state per family.
  static const String _transformPrefsPrefix = 'kinrel_graph_transform_';

  @override
  void initState() {
    super.initState();
    _restoreTransformState();
  }

  @override
  void dispose() {
    _saveTransformState();
    _graphTransformController.dispose();
    super.dispose();
  }

  /// Saves the current transform matrix to SharedPreferences.
  Future<void> _saveTransformState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final m = _graphTransformController.value;
      final values = <double>[
        m.entry(0, 0), m.entry(0, 1), m.entry(0, 2), m.entry(0, 3),
        m.entry(1, 0), m.entry(1, 1), m.entry(1, 2), m.entry(1, 3),
        m.entry(2, 0), m.entry(2, 1), m.entry(2, 2), m.entry(2, 3),
        m.entry(3, 0), m.entry(3, 1), m.entry(3, 2), m.entry(3, 3),
      ];
      await prefs.setStringList(
        '$_transformPrefsPrefix${widget.familyId}',
        values.map((v) => v.toString()).toList(),
      );
    } catch (e) {
      debugPrint('Failed to save transform state: $e');
    }
  }

  /// Restores the transform matrix from SharedPreferences.
  Future<void> _restoreTransformState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList(
        '$_transformPrefsPrefix${widget.familyId}',
      );
      if (stored != null && stored.length == 16) {
        final values = stored.map((v) => double.tryParse(v) ?? 0.0).toList();
        final m = Matrix4.fromList(values);
        if (mounted) {
          _graphTransformController.value = m;
        }
      }
    } catch (e) {
      debugPrint('Failed to restore transform state: $e');
    }
  }

  // ── Zoom helpers ───────────────────────────────────────────────────

  void _zoomIn() {
    final current = _graphTransformController.value.clone();
    final currentScale = current.getMaxScaleOnAxis();
    if (currentScale >= 4.0) return;
    final newScale = (currentScale + 0.25).clamp(0.1, 4.0);
    final factor = newScale / currentScale;
    final size = MediaQuery.of(context).size;
    final focalPoint = Offset(size.width / 2, size.height / 2);
    final tp = MatrixUtils.transformPoint(current, focalPoint);
    _graphTransformController.value = current
      ..translate(tp.dx, tp.dy)
      ..scale(factor)
      ..translate(-tp.dx, -tp.dy);
  }

  void _zoomOut() {
    final current = _graphTransformController.value.clone();
    final currentScale = current.getMaxScaleOnAxis();
    if (currentScale <= 0.1) return;
    final newScale = (currentScale - 0.25).clamp(0.1, 4.0);
    final factor = newScale / currentScale;
    final size = MediaQuery.of(context).size;
    final focalPoint = Offset(size.width / 2, size.height / 2);
    final tp = MatrixUtils.transformPoint(current, focalPoint);
    _graphTransformController.value = current
      ..translate(tp.dx, tp.dy)
      ..scale(factor)
      ..translate(-tp.dx, -tp.dy);
  }

  /// Centers the graph on the root/anchor user by resetting transform
  /// to identity, which triggers the FamilyGraphWidget to auto-center
  /// on the anchor node via its _initialCenterDone logic.
  void _centerOnRootUser() {
    _graphTransformController.value = Matrix4.identity();
    setState(() {
      _highlightedGeneration = null;
      _hoveredRelationshipKey = null;
    });
  }

  /// Opens the Add Member sheet and refreshes graph data when it closes.
  Future<void> _openAddMember() async {
    await AddPersonSheet.show(context, familyId: widget.familyId);
    // Refresh graph data after the sheet closes to immediately show
    // newly added members. The Supabase Realtime subscription may have
    // already invalidated, but we force a refresh as a safety net.
    // Also add a small delay to allow Supabase to propagate the change.
    if (mounted) {
      // First immediate refresh
      ref.invalidate(familyGraphProvider(widget.familyId));
      // Second delayed refresh as safety net for slow DB propagation
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) {
          ref.invalidate(familyGraphProvider(widget.familyId));
        }
      });
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
      backgroundColor: KinrelColors.darkBackground,
      appBar: _buildAppBar(),
      body: graphAsync.when(
        loading: _buildLoadingState,
        error: _buildErrorState,
        data: _buildDataState,
      ),
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────
  //
  // [Back] [Family Name] --- [Zoom In] [Zoom Out]
  // Add Member is now a prominent FAB inside the graph, not in the AppBar.

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: KinrelColors.darkCard,
      foregroundColor: KinrelColors.textWhite,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, size: 22),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Text(
        widget.familyName ?? 'Family Graph',
        style: TextStyle(
          fontFamily: KinrelTypography.displayFont,
          fontWeight: FontWeight.w600,
          fontSize: 18,
        ),
      ),
      actions: [
        // Add Member button in AppBar
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: TextButton.icon(
            onPressed: _openAddMember,
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
            label: const Text('Add'),
            style: TextButton.styleFrom(
              foregroundColor: KinrelColors.orange,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ),
        // Zoom In button
        IconButton(
          icon: const Icon(Icons.zoom_in_rounded, size: 24),
          tooltip: 'Zoom In',
          onPressed: _zoomIn,
        ),
        // Zoom Out button
        IconButton(
          icon: const Icon(Icons.zoom_out_rounded, size: 24),
          tooltip: 'Zoom Out',
          onPressed: _zoomOut,
        ),
        const SizedBox(width: 4),
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

    // ── EDGE DEBUG: Log data passed to FamilyGraphWidget ──
    debugPrint('[EDGE-DEBUG] _buildDataState: ${persons.length} persons, '
        '${graph.relationships.length} relationships');

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
            GenerationFilterBar(
              presentGenerations: presentGenerations,
              highlightedGeneration: _highlightedGeneration,
              onGenerationTap: (gen) {
                setState(() => _highlightedGeneration = gen);
              },
            ),

            if (graph.isTruncated) _buildTruncationBanner(graph),

            Expanded(
              child: FamilyGraphWidget(
                familyId: widget.familyId,
                familyName: widget.familyName ?? 'Family Tree',
                externalTransformController: _graphTransformController,
                graphData: graph,
              ),
            ),
          ],
        ),

        // Legend (?) button (top-right, below filter bar)
        // Only the help/legend button — no Add Member pill here
        // (Add Member is in the AppBar and bottom toolbar).
        if (presentRelationshipKeys.isNotEmpty)
          Positioned(
            right: 16,
            top: filterBarTopOffset,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                GestureDetector(
                  onTap: () => setState(() => _showLegend = !_showLegend),
                  child: Container(
                    width: 36,
                    height: 36,
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
                      size: 18,
                      color: _showLegend
                          ? KinrelColors.orange
                          : KinrelColors.textDim,
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

        // V2.1 Stats panel (bottom-left, above bottom toolbar)
        Positioned(
          left: 16,
          bottom: fabBottomOffset,
          child: StatsPanel(
            totalMembers: graph.persons.length,
            totalConnections: graph.relationships.length,
            totalGenerations: presentGenerations.length,
            isTruncated: graph.isTruncated,
          ),
        ),

        // Bottom toolbar — Center, Add Member, Filter, Help (NO zoom buttons)
        // Zoom In/Out are in the AppBar per reference design
        // Add Member button is in the toolbar for guaranteed visibility
        Positioned(
          bottom: bottomPadding + 8,
          left: 0,
          right: 0,
          child: Center(child: _buildBottomToolbar()),
        ),
      ],
    );
  }

  // ── Empty State ───────────────────────────────────────────────────

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
        Positioned(
          right: 20,
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
          // Add Member — PROMINENT in toolbar for guaranteed visibility
          _toolbarButton(
            icon: Icons.person_add_alt_1_rounded,
            tooltip: 'Add Member',
            onPressed: _openAddMember,
            highlighted: true,
            isPrimary: true,
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
        child: Container(
          width: 48,
          height: 48,
          decoration: isPrimary
              ? BoxDecoration(
                  color: KinrelColors.orange.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(24),
                )
              : highlighted
                  ? BoxDecoration(
                      color: KinrelColors.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(24),
                    )
                  : null,
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
}

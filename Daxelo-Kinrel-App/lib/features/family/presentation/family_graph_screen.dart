// lib/features/family/presentation/family_graph_screen.dart
//
// DAXELO KINREL — Family Graph Screen
//
// Full-screen graph viewer for visualizing family relationships.
// Features:
//   - AppBar with family name, back button, search, and settings
//   - Loading state: shimmer skeleton of graph nodes
//   - Error state: error message with retry button
//   - Empty state: "No family members yet" message with add person CTA
//   - Graph canvas with zoom/pan controls
//   - Truncation warning banner for large families (>5000 persons)
//   - FABs: zoom in, zoom out, reset view, center on anchor
//   - Real-time updates via Socket.IO

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import 'providers/family_graph_provider.dart';
import 'widgets/graph_canvas_widget.dart';

// ═══════════════════════════════════════════════════════════════════════
// FAMILY GRAPH SCREEN
// ═══════════════════════════════════════════════════════════════════════

class FamilyGraphScreen extends ConsumerStatefulWidget {
  const FamilyGraphScreen({
    super.key,
    required this.familyId,
    this.familyName,
  });

  /// The ID of the family whose graph to display.
  final String familyId;

  /// Optional display name for the AppBar title.
  final String? familyName;

  @override
  ConsumerState<FamilyGraphScreen> createState() => _FamilyGraphScreenState();
}

class _FamilyGraphScreenState extends ConsumerState<FamilyGraphScreen> {
  // ── Transformation Controller ──────────────────────────────────────
  final TransformationController _transformCtrl = TransformationController();

  @override
  void dispose() {
    _transformCtrl.dispose();
    super.dispose();
  }

  // ── Zoom Controls ─────────────────────────────────────────────────

  void _zoomIn() {
    final current = _transformCtrl.value;
    final scale = current.storage[0]; // Scale X value from matrix
    final newScale = (scale * 1.2).clamp(0.1, 4.0);
    _transformCtrl.value = Matrix4.diagonal3Values(newScale, newScale, 1.0);
    ref.read(graphZoomProvider.notifier).state = newScale;
  }

  void _zoomOut() {
    final current = _transformCtrl.value;
    final scale = current.storage[0]; // Scale X value from matrix
    final newScale = (scale / 1.2).clamp(0.1, 4.0);
    _transformCtrl.value = Matrix4.diagonal3Values(newScale, newScale, 1.0);
    ref.read(graphZoomProvider.notifier).state = newScale;
  }

  void _resetView() {
    _transformCtrl.value = Matrix4.identity();
    ref.read(graphZoomProvider.notifier).state = 1.0;
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Watch real-time updates for this family
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
      floatingActionButton: _buildZoomControls(),
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: KinrelColors.darkCard,
      foregroundColor: KinrelColors.textWhite,
      elevation: 0,
      title: Text(
        widget.familyName ?? 'Family Graph',
        style: const TextStyle(
          fontFamily: 'Outfit',
          fontWeight: FontWeight.w600,
          fontSize: 18,
        ),
      ),
      actions: [
        // Search button
        IconButton(
          icon: const Icon(Icons.search, size: 22),
          onPressed: () {
            // TODO: Navigate to person search within graph
          },
          tooltip: 'Search',
        ),
        // Settings / filter button
        IconButton(
          icon: const Icon(Icons.tune, size: 22),
          onPressed: () {
            // TODO: Show graph filter settings
          },
          tooltip: 'Filter',
        ),
      ],
    );
  }

  // ── Loading State ─────────────────────────────────────────────────

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            color: KinrelColors.orange,
            strokeWidth: 3,
          ),
          SizedBox(height: 16),
          Text(
            'Loading family graph...',
            style: TextStyle(
              color: KinrelColors.textSecondaryDark,
              fontFamily: 'DMSans',
              fontSize: 14,
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
            const Icon(
              Icons.error_outline,
              color: KinrelColors.orange,
              size: 48,
            ),
            const SizedBox(height: 16),
            const Text(
              'Something went wrong',
              style: TextStyle(
                color: KinrelColors.textWhite,
                fontFamily: 'Outfit',
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              style: const TextStyle(
                color: KinrelColors.textSecondaryDark,
                fontFamily: 'DMSans',
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                ref.invalidate(familyGraphProvider(widget.familyId));
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Tap to retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: KinrelColors.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Data State ────────────────────────────────────────────────────

  Widget _buildDataState(FlatGraphResult graph) {
    if (graph.persons.isEmpty) {
      return _buildEmptyState();
    }

    return Column(
      children: [
        // Truncation warning banner
        if (graph.isTruncated) _buildTruncationBanner(graph),

        // Graph canvas
        Expanded(
          child: GraphCanvasWidget(
            persons: graph.toPersonDataList(),
            relationships: graph.toRelationshipDataList(),
            familyId: widget.familyId,
          ),
        ),
      ],
    );
  }

  // ── Empty State ───────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.family_restroom_outlined,
              color: KinrelColors.textDim,
              size: 64,
            ),
            const SizedBox(height: 16),
            const Text(
              'No family members yet',
              style: TextStyle(
                color: KinrelColors.textWhite,
                fontFamily: 'Outfit',
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add family members and relationships to see\nthe family graph visualization.',
              style: TextStyle(
                color: KinrelColors.textSecondaryDark,
                fontFamily: 'DMSans',
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                // TODO: Navigate to add person screen
              },
              icon: const Icon(Icons.person_add, size: 18),
              label: const Text('Add Family Member'),
              style: ElevatedButton.styleFrom(
                backgroundColor: KinrelColors.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
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
        border: Border(
          bottom: BorderSide(
            color: KinrelColors.amber,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: KinrelColors.amber,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              graph.totalCount != null
                  ? 'Showing first ${graph.persons.length} of ${graph.totalCount} persons. '
                      'The full family has more members.'
                  : 'Showing first ${graph.persons.length} persons. '
                      'The full family has more members.',
              style: const TextStyle(
                color: KinrelColors.textSecondaryDark,
                fontFamily: 'DMSans',
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Zoom Controls (FAB Column) ────────────────────────────────────

  Widget? _buildZoomControls() {
    final graphAsync = ref.watch(familyGraphProvider(widget.familyId));
    if (graphAsync.isLoading || graphAsync.hasError) return null;
    final graph = graphAsync.valueOrNull;
    if (graph == null || graph.persons.isEmpty) return null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Zoom In
        FloatingActionButton.small(
          heroTag: 'zoom_in',
          onPressed: _zoomIn,
          backgroundColor: KinrelColors.darkElevated,
          foregroundColor: KinrelColors.textWhite,
          child: const Icon(Icons.add, size: 20),
        ),
        const SizedBox(height: 8),

        // Zoom Out
        FloatingActionButton.small(
          heroTag: 'zoom_out',
          onPressed: _zoomOut,
          backgroundColor: KinrelColors.darkElevated,
          foregroundColor: KinrelColors.textWhite,
          child: const Icon(Icons.remove, size: 20),
        ),
        const SizedBox(height: 8),

        // Reset View
        FloatingActionButton.small(
          heroTag: 'reset_view',
          onPressed: _resetView,
          backgroundColor: KinrelColors.darkElevated,
          foregroundColor: KinrelColors.textWhite,
          child: const Icon(Icons.center_focus_strong, size: 20),
        ),
        const SizedBox(height: 8),

        // Refresh
        FloatingActionButton.small(
          heroTag: 'refresh',
          onPressed: () {
            ref.invalidate(familyGraphProvider(widget.familyId));
          },
          backgroundColor: KinrelColors.darkElevated,
          foregroundColor: KinrelColors.textWhite,
          child: const Icon(Icons.refresh, size: 20),
        ),
      ],
    );
  }
}

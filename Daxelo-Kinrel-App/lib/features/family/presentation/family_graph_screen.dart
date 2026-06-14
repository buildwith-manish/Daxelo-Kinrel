// lib/features/family/presentation/family_graph_screen.dart
//
// DAXELO KINREL — Family Graph Screen (V2.1 Blueprint Integration)
//
// Full-screen graph viewer for visualizing family relationships.
// Features:
//   - AppBar with family name, back button, stacked avatar previews
//   - Loading/error/empty states
//   - New FamilyGraphWidget from lib/graph/ architecture
//   - Generation legend chips (top-left floating)
//   - Bottom legend bar with dynamic categories
//   - Truncation warning banner for large families
//   - Real-time updates via Socket.IO

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../graph/graph.dart';
import 'add_person_sheet.dart';
import 'providers/family_graph_provider.dart';
import 'widgets/generation_filter_bar.dart';
import 'widgets/generation_legend_widget.dart';
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
      debugPrint('⚠️ Failed to save transform state: $e');
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
      debugPrint('⚠️ Failed to restore transform state: $e');
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

  void _resetZoom() {
    _graphTransformController.value = Matrix4.identity();
  }

  /// Centers the graph on the root/anchor user by resetting transform.
  /// This is called from the "center" button in the bottom action bar.
  void _centerOnRootUser() {
    _resetZoom();
    setState(() {
      _highlightedGeneration = null;
      _hoveredRelationshipKey = null;
    });
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    ref.watch(graphRealtimeProvider(widget.familyId));
    final graphAsync = ref.watch(familyGraphProvider(widget.familyId));

    return Scaffold(
      backgroundColor: KinrelColors.darkBackground,
      appBar: _buildAppBar(graphAsync.valueOrNull),
      body: graphAsync.when(
        loading: _buildLoadingState,
        error: _buildErrorState,
        data: _buildDataState,
      ),
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(FlatGraphResult? graph) {
    // Build up to 3 overlapping avatar circles for the top-right
    final persons = graph?.toPersonDataList() ?? [];
    final avatarPersons = persons.take(3).toList();

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
        // 3 stacked circular avatar previews
        if (avatarPersons.isNotEmpty)
          GestureDetector(
            onTap: () => _showFamilyMembersSheet(persons),
            child: Padding(
              padding: const EdgeInsets.only(right: 12.0),
              child: SizedBox(
                width: 28.0 * avatarPersons.length.toDouble() + 12.0,
                height: 36.0,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: List.generate(avatarPersons.length, (i) {
                    final p = avatarPersons[i];
                    final initials = p.name.trim().split(RegExp(r'\s+'));
                    final letter = initials.length >= 2
                        ? '${initials[0][0]}${initials[1][0]}'.toUpperCase()
                        : p.name.substring(0, p.name.length > 1 ? 2 : 1).toUpperCase();

                    return Positioned(
                      left: i * 16.0,
                      child: Container(
                        width: 28.0,
                        height: 28.0,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: KinrelColors.darkElevated,
                          border: Border.all(color: KinrelColors.textWhite, width: 1.5),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          letter,
                          style: TextStyle(
                            fontFamily: KinrelTypography.displayFont,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: KinrelColors.textWhite,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _showFamilyMembersSheet(List<PersonData> persons) {
    showModalBottomSheet(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        minChildSize: 0.25,
        maxChildSize: 0.8,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Family Members',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textWhite,
                ),
              ),
            ),
            const Divider(color: Color(0x1AFFFFFF), height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: persons.length,
                itemBuilder: (context, index) {
                  final p = persons[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: KinrelColors.darkElevated,
                      child: Text(
                        p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                        style: TextStyle(color: KinrelColors.textWhite, fontSize: 14),
                      ),
                    ),
                    title: Text(p.name, style: TextStyle(color: KinrelColors.textWhite, fontFamily: KinrelTypography.displayFont)),
                    subtitle: Text('Generation ${p.generationIndex}', style: TextStyle(color: KinrelColors.textDim, fontSize: 12)),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Loading State ─────────────────────────────────────────────────

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: KinrelColors.orange, strokeWidth: 3),
          SizedBox(height: 16),
          Text('Loading family graph...', style: TextStyle(color: KinrelColors.textSecondaryDark, fontFamily: 'DMSans', fontSize: 14)),
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
            const Icon(Icons.error_outline, color: KinrelColors.orange, size: 48),
            const SizedBox(height: 16),
            const Text('Something went wrong', style: TextStyle(color: KinrelColors.textWhite, fontFamily: 'Outfit', fontWeight: FontWeight.w600, fontSize: 18)),
            const SizedBox(height: 8),
            Text(error.toString(), style: const TextStyle(color: KinrelColors.textSecondaryDark, fontFamily: 'DMSans', fontSize: 13), textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => ref.invalidate(familyGraphProvider(widget.familyId)),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Tap to retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: KinrelColors.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Data State ────────────────────────────────────────────────────

  Widget _buildDataState(FlatGraphResult graph) {
    if (graph.persons.isEmpty) return _buildEmptyState();

    final persons = graph.toPersonDataList();

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
              ),
            ),
          ],
        ),

        // Generation legend chips (top-left floating, below filter bar)
        Positioned(
          left: 16,
          top: graph.isTruncated ? 96 : 56,
          child: GenerationLegendWidget(
            presentGenerations: presentGenerations,
            highlightedGeneration: _highlightedGeneration,
            onGenerationTap: (gen) {
              setState(() => _highlightedGeneration = gen);
            },
          ),
        ),

        // Relationship legend — hidden by default, tap icon to show
        if (presentRelationshipKeys.isNotEmpty)
          Positioned(
            right: 16,
            top: 80,
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
                      Icons.account_tree_outlined,
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

        // V2.1 Stats panel (bottom-left, above action bar)
        Positioned(
          left: 16,
          bottom: MediaQuery.of(context).padding.bottom + 72,
          child: StatsPanel(
            totalMembers: graph.persons.length,
            totalConnections: graph.relationships.length,
            totalGenerations: presentGenerations.length,
            isTruncated: graph.isTruncated,
          ),
        ),

        // Bottom action bar — single consolidated toolbar
        // Contains: zoom out, reset view, zoom in, divider, add member
        Positioned(
          bottom: MediaQuery.of(context).padding.bottom + 8,
          left: 0,
          right: 0,
          child: Center(child: _buildBottomActionBar()),
        ),
      ],
    );
  }

  // ── Empty State ───────────────────────────────────────────────────

  Widget _buildEmptyState() {
    // Delegate to V2.1 EmptyState widget with illustrated welcome + onboarding
    return Stack(
      children: [
        EmptyState(
          memberCount: 0,
          familyId: widget.familyId,
          onAddMember: () {
            AddPersonSheet.show(context, familyId: widget.familyId);
          },
        ),
        // Add Member FAB — visible even in empty state
        Positioned(
          right: 20,
          bottom: MediaQuery.of(context).padding.bottom + 20,
          child: FloatingActionButton(
            heroTag: 'empty_add_member_fab',
            backgroundColor: KinrelColors.orange,
            foregroundColor: Colors.white,
            elevation: 6,
            onPressed: () =>
                AddPersonSheet.show(context, familyId: widget.familyId),
            child: const Icon(Icons.person_add_alt_1_rounded, size: 24),
          ),
        ),
      ],
    );
  }

  // ── Bottom Action Bar ──────────────────────────────────────────────

  Widget _buildBottomActionBar() {
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
          // Zoom Out
          _actionBarButton(
            icon: Icons.zoom_out_rounded,
            tooltip: 'Zoom Out',
            onPressed: _zoomOut,
          ),
          // Center / Reset — centers on root user
          _actionBarButton(
            icon: Icons.center_focus_strong_outlined,
            tooltip: 'Center on Root',
            onPressed: _centerOnRootUser,
          ),
          // Zoom In
          _actionBarButton(
            icon: Icons.zoom_in_rounded,
            tooltip: 'Zoom In',
            onPressed: _zoomIn,
          ),
          // Divider
          Container(
            width: 1,
            height: 24,
            color: Colors.white.withValues(alpha: 0.1),
            margin: const EdgeInsets.symmetric(horizontal: 4),
          ),
          // Add Member (highlighted)
          _actionBarButton(
            icon: Icons.person_add_alt_1_rounded,
            tooltip: 'Add Member',
            onPressed: () => AddPersonSheet.show(context, familyId: widget.familyId),
            highlighted: true,
          ),
        ],
      ),
    );
  }

  Widget _actionBarButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    bool highlighted = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: 48,
          height: 48,
          decoration: highlighted
              ? BoxDecoration(
                  color: KinrelColors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(24),
                )
              : null,
          child: Icon(
            icon,
            size: 22,
            color: highlighted ? KinrelColors.orange : KinrelColors.textDim,
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
          const Icon(Icons.warning_amber_rounded, color: KinrelColors.amber, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              graph.totalCount != null
                  ? 'Showing first ${graph.persons.length} of ${graph.totalCount} persons.'
                  : 'Showing first ${graph.persons.length} persons.',
              style: const TextStyle(color: KinrelColors.textSecondaryDark, fontFamily: 'DMSans', fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

}

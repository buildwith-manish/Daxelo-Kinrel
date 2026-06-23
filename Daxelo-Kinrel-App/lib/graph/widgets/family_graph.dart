// lib/graph/widgets/family_graph.dart
//
// DAXELO KINREL — Family Graph Widget (v40 COMPLETE REWRITE)
//
// Previous versions (v1-v39) used complex custom gesture handling,
// viewport culling, camera controllers, and transform math that
// caused persistent blank-screen bugs due to setState-during-build,
// stale transforms, and culling issues.
//
// v40 SIMPLIFIES everything:
//   - Uses Flutter's built-in InteractiveViewer for pan/zoom
//   - No viewport culling (families are small, <500 nodes)
//   - No custom gesture handlers
//   - No camera controller
//   - No transform fingerprinting
//   - No _initialCenterDone flags
//   - Just: compute layout → position nodes → draw edges → InteractiveViewer
//
// This is deliberately simple. Every line here is easy to debug.

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/brand_colors.dart';
import '../../core/constants/brand_typography.dart';
import '../../core/services/graph_layout_service.dart';
import '../../features/family/presentation/add_person_sheet.dart';
import '../../features/family/presentation/providers/family_graph_provider.dart';
import '../data/family_graph_repository.dart' show GraphEdgeData;
import 'empty_state.dart';
import 'graph_error_state.dart';
import 'graph_node.dart';
import 'graph_node_state.dart';
import 'graph_pan_zoom.dart';
import 'graph_quick_actions.dart';
import 'graph_relationship_labels.dart';
import 'onboarding_flow.dart';
import 'relationship_edge.dart';
import 'relationship_info_sheet.dart';

// ═══════════════════════════════════════════════════════════════════════
// FAMILY GRAPH WIDGET
// ═══════════════════════════════════════════════════════════════════════

class FamilyGraphWidget extends ConsumerStatefulWidget {
  const FamilyGraphWidget({
    super.key,
    required this.familyId,
    required this.familyName,
    this.externalTransformController,
    this.graphData,
    this.highlightedGeneration,
  });

  final String familyId;
  final String familyName;
  final TransformationController? externalTransformController;
  final FlatGraphResult? graphData;
  final int? highlightedGeneration;

  @override
  ConsumerState<FamilyGraphWidget> createState() => _FamilyGraphWidgetState();
}

class _FamilyGraphWidgetState extends ConsumerState<FamilyGraphWidget> {
  late TransformationController _transformationController;
  bool _ownsController = false;

  // Selected node/edge for highlighting
  String? _selectedNodeId;
  String? _selectedEdgeId;
  String? _focusedNodeId;

  // Onboarding
  bool _onboardingLocallyDismissed = false;

  // v52.4: Auto-center flag — only center once per family to avoid
  // fighting the user's manual pan/zoom after the first centering.
  bool _autoCenterDone = false;

  @override
  void initState() {
    super.initState();
    if (widget.externalTransformController != null) {
      _transformationController = widget.externalTransformController!;
      _ownsController = false;
    } else {
      _transformationController = TransformationController();
      _ownsController = true;
    }
    _autoDismissOnboarding();
  }

  @override
  void dispose() {
    if (_ownsController) {
      _transformationController.dispose();
    }
    super.dispose();
  }

  Future<void> _autoDismissOnboarding() async {
    try {
      final dismissed = await OnboardingPrefs.load();
      if (dismissed.contains(widget.familyId) && mounted) {
        setState(() => _onboardingLocallyDismissed = true);
      }
    } catch (_) {}
  }

  void _openAddMemberSheet() {
    AddPersonSheet.show(context, familyId: widget.familyId);
  }

  // ═══════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final FlatGraphResult? effectiveGraphData = widget.graphData;

    if (effectiveGraphData != null) {
      return _buildFromGraphData(effectiveGraphData, reduceMotion);
    }

    final graphAsync = ref.watch(familyGraphProvider(widget.familyId));
    return graphAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: KinrelColors.orange),
      ),
      error: (error, stack) => GraphErrorState(
        familyId: widget.familyId,
        error: error,
      ),
      data: (graphData) => _buildFromGraphData(graphData, reduceMotion),
    );
  }

  Widget _buildFromGraphData(FlatGraphResult graphData, bool reduceMotion) {
    final persons = graphData.toPersonDataList();

    debugPrint('[FamilyGraph] persons=${persons.length} '
        'relationships=${graphData.relationships.length}');

    if (persons.isEmpty) {
      final dismissedAsync = ref.watch(onboardingDismissedProvider);
      final isDismissed =
          dismissedAsync.valueOrNull?.contains(widget.familyId) ?? true;

      if (!isDismissed && !_onboardingLocallyDismissed) {
        return Stack(
          children: [
            EmptyState(
              familyId: widget.familyId,
              memberCount: 0,
              onAddMember: _openAddMemberSheet,
            ),
            OnboardingFlow(familyId: widget.familyId, memberCount: 0),
          ],
        );
      }

      return GraphEmptyStack(
        child: EmptyState(
          familyId: widget.familyId,
          memberCount: 0,
          onAddMember: _openAddMemberSheet,
        ),
      );
    }

    // Auto-dismiss onboarding for families with members
    if (persons.isNotEmpty && !_onboardingLocallyDismissed) {
      final dismissedAsync = ref.watch(onboardingDismissedProvider);
      final isDismissed =
          dismissedAsync.valueOrNull?.contains(widget.familyId) ?? true;
      if (!isDismissed) {
        ref.read(onboardingDismissedProvider.notifier).dismiss(widget.familyId);
      }
      _onboardingLocallyDismissed = true;
    }

    // Build person map
    final personMap = <String, GraphPersonData>{};
    for (final p in persons) {
      personMap[p.id] = GraphPersonData(
        id: p.id,
        name: p.name,
        gender: p.gender,
        generationIndex: p.generationIndex,
        isAnchor: p.isAnchor,
        photoUrl: p.photoUrl,
        isDeceased: p.isDeceased,
      );
    }

    // Build edges
    final edges = <GraphEdgeData>[];
    for (final r in graphData.relationships) {
      edges.add(GraphEdgeData(
        id: r['id'] as String? ?? '',
        sourceId: r['fromPersonId'] as String? ?? '',
        targetId: r['toPersonId'] as String? ?? '',
        relationshipKey: r['relationshipKey'] as String? ?? '',
      ));
    }

    // Compute layout
    final anchorPerson = persons.firstWhere(
      (p) => p.isAnchor,
      orElse: () => persons.first,
    );
    final graphPersons = persons.map((p) => p.toGraphPerson()).toList();
    final graphRelationships =
        graphData.relationships.map((r) {
      return GraphRelationship(
        id: r['id'] as String? ?? '',
        fromPersonId: r['fromPersonId'] as String? ?? '',
        toPersonId: r['toPersonId'] as String? ?? '',
        relationshipKey: r['relationshipKey'] as String? ?? 'unknown',
      );
    }).toList();

    final service = GraphLayoutService();
    final layout = service.computeLayout(
      persons: graphPersons,
      relationships: graphRelationships,
      anchorPersonId: anchorPerson.id,
    );

    debugPrint('[FamilyGraph] Layout: positions=${layout.positions.length} '
        'canvas=${layout.canvasWidth.toStringAsFixed(0)}x${layout.canvasHeight.toStringAsFixed(0)}');

    // v52.3 DEBUG: log first 3 positions to verify layout is producing
    // visible coordinates (not all at 0,0 or negative).
    if (layout.positions.isNotEmpty) {
      final sample = layout.positions.entries.take(3).map((e) =>
          '${e.key}=(${e.value.dx.toStringAsFixed(0)},${e.value.dy.toStringAsFixed(0)})').join(' ');
      debugPrint('[FamilyGraph] sample positions: $sample');
    }

    if (layout.positions.isEmpty) {
      return GraphEmptyStack(
        child: EmptyState(
          familyId: widget.familyId,
          memberCount: persons.length,
          onAddMember: () {
            AddPersonSheet.show(context, familyId: widget.familyId);
          },
        ),
      );
    }

    // v52.4 FIX: Auto-center the graph on the anchor node after the first
    // frame. Without this, the canvas renders at (0,0) which may be
    // off-screen if the viewport is smaller than the canvas. The
    // auto-center calculates the transform needed to place the anchor
    // node at the center of the viewport.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _autoCenterOnAnchor(layout, anchorPerson.id);
    });

    return _buildGraphCanvas(layout, personMap, edges);
  }

  // ═══════════════════════════════════════════════════════════════════
  // GRAPH CANVAS — the actual rendering
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildGraphCanvas(
    GraphLayoutResult layout,
    Map<String, GraphPersonData> personMap,
    List<GraphEdgeData> edges,
  ) {
    final positions = layout.positions;
    final canvasWidth = layout.canvasWidth;
    final canvasHeight = layout.canvasHeight;
    final highlightedGen = widget.highlightedGeneration;

    // v47 FIX: GraphPanZoom uses HitTestBehavior.opaque + a parent Listener
    // that captures the true pointer-down position. The parent owns the
    // viewport for scale gestures (so pinch-zoom works on Android), while
    // child GraphNode taps still win single-tap gestures in the arena.
    return GraphPanZoom(
      transformationController: _transformationController,
      minScale: 0.1,
      maxScale: 5.0,
      child: SizedBox(
        width: canvasWidth > 0 ? canvasWidth : 400,
        height: canvasHeight > 0 ? canvasHeight : 400,
        child: DecoratedBox(
          // v52.3 DEBUG: visible border so we can see if the canvas is
          // rendering at all. Remove after the blank-screen bug is fixed.
          decoration: BoxDecoration(
            border: Border.all(color: KinrelColors.orange.withValues(alpha: 0.3), width: 2),
            color: KinrelColors.darkBackground,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // ── Edge Layer ────────────────────────────────────────────
              Positioned.fill(
                child: CustomPaint(
                  size: Size(
                    canvasWidth > 0 ? canvasWidth : 400,
                    canvasHeight > 0 ? canvasHeight : 400,
                  ),
                  painter: RelationshipEdge(
                    positions: positions,
                    edges: edges,
                    selectedEdgeId: _selectedEdgeId,
                    zoomLevel: _transformationController.value.getMaxScaleOnAxis(),
                    nodeWidth: 72.0,
                    nodeHeight: 72.0,
                    generationMap: {
                      for (final p in personMap.values)
                        p.id: p.generationIndex,
                    },
                    highlightedGeneration: highlightedGen,
                    anonymousNodeIds: const {},
                    blockedNodeIds: const {},
                  ),
                ),
              ),

              // ── Node Layer ────────────────────────────────────────────
              ..._buildNodes(positions, personMap, edges, highlightedGen),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // AUTO-CENTER ON ANCHOR (v52.4)
  // ═══════════════════════════════════════════════════════════════════

  /// Centers the graph so the anchor node appears at the viewport center.
  ///
  /// This runs ONCE after the first layout. Without it, the canvas renders
  /// at (0,0) in widget space — on small viewports the anchor (also near
  /// 0,0 after normalization) may appear in the top-left corner, and on
  /// large viewports the graph sits in the corner with empty space.
  ///
  /// The auto-center computes:
  ///   scale = min(viewportW / canvasW, viewportH / canvasH, 1.0)
  ///   tx = (viewportW - canvasW * scale) / 2
  ///   ty = (viewportH - canvasH * scale) / 2
  ///
  /// This places the canvas centered in the viewport. If the canvas is
  /// smaller than the viewport, scale stays at 1.0 and the canvas is
  /// centered. If larger, it's scaled down to fit.
  void _autoCenterOnAnchor(GraphLayoutResult layout, String anchorId) {
    if (_autoCenterDone) return;
    _autoCenterDone = true;

    final canvasW = layout.canvasWidth;
    final canvasH = layout.canvasHeight;
    if (canvasW <= 0 || canvasH <= 0) return;

    final viewport = MediaQuery.of(context).size;
    final viewportW = viewport.width;
    final viewportH = viewport.height;
    if (viewportW <= 0 || viewportH <= 0) return;

    // Scale to fit the entire canvas in the viewport, but don't zoom in
    // beyond 1.0 (the natural size). Add a small margin so nodes near
    // the edge aren't cut off.
    final margin = 80.0;
    final scaleX = (viewportW - margin * 2) / canvasW;
    final scaleY = (viewportH - margin * 2) / canvasH;
    final scale = [scaleX, scaleY, 1.0].reduce((a, b) => a < b ? a : b)
        .clamp(0.05, 1.0);

    // Center the canvas in the viewport.
    final tx = (viewportW - canvasW * scale) / 2;
    final ty = (viewportH - canvasH * scale) / 2;

    debugPrint('[FamilyGraph] auto-center: scale=$scale tx=$tx ty=$ty '
        'viewport=${viewportW.toStringAsFixed(0)}x${viewportH.toStringAsFixed(0)} '
        'canvas=${canvasW.toStringAsFixed(0)}x${canvasH.toStringAsFixed(0)}');

    _transformationController.value = Matrix4.identity()
      ..translate(tx, ty)
      ..scale(scale);
  }

  List<Widget> _buildNodes(
    Map<String, Offset> positions,
    Map<String, GraphPersonData> personMap,
    List<GraphEdgeData> edges,
    int? highlightedGen,
  ) {
    final nodes = <Widget>[];
    final zoomLevel = _transformationController.value.getMaxScaleOnAxis();

    for (final person in personMap.values) {
      final pos = positions[person.id];
      if (pos == null) continue;

      final isSelected = _selectedNodeId == person.id;
      final isFocused = _focusedNodeId == person.id;

      final nodeState = GraphNodeStateResolver.resolve(
        isSelected: isSelected,
        isFocused: isFocused,
        isAnonymous: false,
      );

      final relationLabel = GraphRelationshipLabels.getRelationLabel(
        person, personMap, edges,
      );

      final relKey = GraphRelationshipLabels.getRelationshipKey(
        person.id, personMap, edges,
      );

      final double nodeOpacity =
          (highlightedGen != null && person.generationIndex != highlightedGen)
              ? 0.15
              : 1.0;

      nodes.add(
        Positioned(
          left: pos.dx - 36,  // center the 72px node
          top: pos.dy - 36,
          // v42 FIX: Removed the outer GestureDetector wrapper.
          // GraphNode has its OWN internal GestureDetector with
          // HitTestBehavior.translucent. The outer GestureDetector was
          // competing with GraphPanZoom's ScaleGestureRecognizer on
          // Android, blocking pinch-to-zoom. GraphPanZoom's
          // HitTestBehavior.opaque + GraphNode's translucent is the
          // correct combination: parent claims scale, child wins tap.
          child: GraphNode(
            personId: person.id,
            name: person.name,
            gender: person.gender,
            generationIndex: person.generationIndex,
            isAnchor: person.isAnchor,
            photoUrl: person.photoUrl,
            isDeceased: person.isDeceased,
            isAnonymous: false,
            relationshipKey: relKey,
            relationLabel: relationLabel,
            nodeState: nodeState,
            opacity: nodeOpacity,
            nodeSize: GraphNodeStateResolver.resolveSize(
              viewportWidth: MediaQuery.of(context).size.width,
              zoomLevel: zoomLevel,
            ),
            onTap: () {
              setState(() {
                _selectedNodeId =
                    _selectedNodeId == person.id ? null : person.id;
                _selectedEdgeId = null;
              });
            },
            onLongPress: () {
              GraphQuickActions.show(context, person);
            },
            onDoubleTap: null,
          ),
        ),
      );
    }

    return nodes;
  }
}

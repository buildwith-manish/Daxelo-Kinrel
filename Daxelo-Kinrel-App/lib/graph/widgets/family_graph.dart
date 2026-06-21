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

    // v42 FIX: Replace InteractiveViewer with GraphPanZoom (v4.1 battle-tested).
    // InteractiveViewer's gesture model conflicts with nested node
    // GestureDetectors on Android — the node's TapGestureRecognizer wins
    // the arena and blocks the parent's ScaleGestureRecognizer, making
    // pinch-to-zoom feel frozen. GraphPanZoom uses HitTestBehavior.opaque
    // + ClipRect so the parent claims the viewport for scale gestures,
    // while child node taps still win for single taps.
    return GraphPanZoom(
      transformationController: _transformationController,
      minScale: 0.1,
      maxScale: 5.0,
      child: SizedBox(
        width: canvasWidth > 0 ? canvasWidth : 400,
        height: canvasHeight > 0 ? canvasHeight : 400,
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
    );
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

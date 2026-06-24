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
    this.recenterKey,
  });

  final String familyId;
  final String familyName;
  final TransformationController? externalTransformController;
  final FlatGraphResult? graphData;
  final int? highlightedGeneration;
  /// v60: When this value changes, the graph re-runs auto-centering.
  /// Used by the parent screen's "Center on Root" button.
  final int? recenterKey;

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

  // v60: Auto-center flag — resets when familyId changes so the new
  // family gets centered on first load. Previously stayed true forever
  // after the first centering, breaking "Center on Root" button.
  bool _autoCenterDone = false;
  String? _lastFamilyId;

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
    // v60: Listen to transform changes so the painter's zoomLevel
    // stays current during pan/zoom gestures. Without this, dots and
    // labels used stale zoom values until another setState happened.
    _transformationController.addListener(_onTransformChanged);
    _lastFamilyId = widget.familyId;
    _autoDismissOnboarding();
  }

  @override
  void didUpdateWidget(covariant FamilyGraphWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // v60: Reset auto-center when family changes or recenterKey changes.
    if (widget.familyId != _lastFamilyId ||
        widget.recenterKey != oldWidget.recenterKey) {
      _autoCenterDone = false;
      _lastFamilyId = widget.familyId;
    }
  }

  void _onTransformChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _transformationController.removeListener(_onTransformChanged);
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

    // Build edges — deduplicate by sorted node-pair key so each pair of
    // nodes gets exactly ONE edge drawn, regardless of how many
    // relationship rows exist in the database (the DB stores both
    // directions: A→B and B→A). Without this, every pair would render
    // as a doubled/thickened line.
    final edges = <GraphEdgeData>[];
    final drawnPairs = <String>{};
    for (final r in graphData.relationships) {
      final sourceId = r['fromPersonId'] as String? ?? '';
      final targetId = r['toPersonId'] as String? ?? '';
      if (sourceId.isEmpty || targetId.isEmpty) continue;

      // Build a sorted pair key so A→B and B→A produce the same key.
      final ids = [sourceId, targetId]..sort();
      final pairKey = '${ids[0]}_${ids[1]}';
      if (drawnPairs.contains(pairKey)) continue;
      drawnPairs.add(pairKey);

      edges.add(GraphEdgeData(
        id: r['id'] as String? ?? '',
        sourceId: sourceId,
        targetId: targetId,
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

    // Auto-center the graph on the anchor node after the first frame.
    // Runs once via _autoCenterDone flag so the user's manual pan/zoom
    // is preserved after the initial centering.
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

    // v55 FIX: Compute the ACTUAL node size here so the painter and the
    // node widgets use the SAME size. Previously the painter used a
    // hardcoded 72.0 while nodes used 48-64px from resolveSize(),
    // causing edges to stop at the wrong distance from node centers.
    final viewportWidth = MediaQuery.of(context).size.width;
    final zoomLevel = _transformationController.value.getMaxScaleOnAxis();
    final actualNodeSize = GraphNodeStateResolver.resolveSize(
      viewportWidth: viewportWidth,
      zoomLevel: zoomLevel,
    );

    final cw = canvasWidth > 0 ? canvasWidth : 400.0;
    final ch = canvasHeight > 0 ? canvasHeight : 400.0;

    return InteractiveViewer(
      transformationController: _transformationController,
      constrained: false,
      boundaryMargin: const EdgeInsets.all(double.infinity),
      minScale: 0.05,
      maxScale: 5.0,
      child: SizedBox(
        width: cw,
        height: ch,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // ── Edge Layer ────────────────────────────────────────────
            Positioned.fill(
              child: CustomPaint(
                size: Size(cw, ch),
                painter: RelationshipEdge(
                  positions: positions,
                  edges: edges,
                  selectedEdgeId: _selectedEdgeId,
                  zoomLevel: zoomLevel,
                  nodeWidth: actualNodeSize,
                  nodeHeight: actualNodeSize,
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

  // ═══════════════════════════════════════════════════════════════════
  // AUTO-CENTER ON ANCHOR (v52.4)
  // ═══════════════════════════════════════════════════════════════════

  /// Centers the graph so the anchor node appears at the viewport center.
  ///
  /// This runs ONCE after the first layout. It computes the transform
  /// needed to fit the entire canvas in the viewport and center it.
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

    // Scale to fit the entire canvas in the viewport with margin.
    final margin = 40.0;
    final scaleX = (viewportW - margin * 2) / canvasW;
    final scaleY = (viewportH - margin * 2) / canvasH;
    final scale = [scaleX, scaleY, 1.0].reduce((a, b) => a < b ? a : b)
        .clamp(0.05, 1.0);

    // Center the canvas in the viewport.
    // InteractiveViewer's matrix maps child coordinates to parent coordinates.
    // To center: tx = (viewportW - canvasW * scale) / 2
    final tx = (viewportW - canvasW * scale) / 2;
    final ty = (viewportH - canvasH * scale) / 2;

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
    // v55 FIX: Use the SAME node size as the painter — previously this
    // used hardcoded 36 (half of 72) but the node was actually 48-64px,
    // causing the visual center to be offset from the stored position.
    final nodeSize = GraphNodeStateResolver.resolveSize(
      viewportWidth: MediaQuery.of(context).size.width,
      zoomLevel: zoomLevel,
    );
    final halfNode = nodeSize / 2;

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
          left: pos.dx - halfNode,
          top: pos.dy - halfNode,
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
            nodeSize: nodeSize,
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
// v52.7 retrigger
// v52.8 retrigger

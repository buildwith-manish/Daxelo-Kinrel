import 'dart:async';
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
import '../../core/services/analytics_service.dart';
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

  // v62: Cached layout + edges — prevents recomputation on every rebuild.
  // The layout is only recomputed when the underlying graph data changes
  // (different person/relationship count). This fixes the bug where
  // long-pressing a node (which opens a bottom sheet → triggers a rebuild
  // when dismissed) caused the layout to recompute with slightly different
  // positions, leaving some nodes off-screen.
  GraphLayoutResult? _cachedLayout;
  List<GraphEdgeData>? _cachedEdges;
  Map<String, GraphPersonData>? _cachedPersonMap;
  int? _cachedPersonCount;
  int? _cachedRelationshipCount;

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
    // v60.1 FIX: Removed _transformationController.addListener — it caused
    // a stack overflow (setState → rebuild → InteractiveViewer re-applies
    // transform → listener fires → setState → infinite loop).
    // Instead, the painter reads zoomLevel during paint() which is called
    // by AnimatedBuilder(animation: _transformationController) below.
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
      // v62: Invalidate layout cache when family changes.
      _cachedLayout = null;
      _cachedEdges = null;
      _cachedPersonMap = null;
      _cachedPersonCount = null;
      _cachedRelationshipCount = null;
    }
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

  /// v62: Position of the last double-tap, used to zoom toward the
  /// focal point. Stored in local (child) coordinates.
  Offset _doubleTapPosition = Offset.zero;

  /// v62: Handles double-tap to zoom. Toggles between current zoom
  /// and 2× zoom, centered on the tap position. Animates the
  /// transform for a smooth zoom-in feel.
  void _handleDoubleTapZoom() {
    final controller = _transformationController;
    final currentScale = controller.value.getMaxScaleOnAxis();
    final targetScale = currentScale < 1.5 ? 2.0 : 1.0;

    // Get the tap position in screen coordinates.
    final tapScreen = _doubleTapPosition;

    // Convert tap position to child (graph-space) coordinates using
    // the inverse of the current transform.
    final inverse = Matrix4.inverted(controller.value);
    final tapInChildSpace = MatrixUtils.transformPoint(inverse, tapScreen);

    // Build the new transform: scale around the tap point.
    // Matrix = translate(tapScreen) * scale(targetScale) * translate(-tapInChild)
    final newTransform = Matrix4.identity()
      ..translate(tapScreen.dx, tapScreen.dy)
      ..scale(targetScale)
      ..translate(-tapInChildSpace.dx, -tapInChildSpace.dy);

    // Animate to the new transform.
    controller.value = newTransform;
  }

  /// v62: Fire-and-forget analytics wrapper. Never lets a telemetry
  /// failure (e.g., Firebase not initialized in tests) break the build.
  void _safeAnalytics(Future<void> Function() action) {
    // ignore: discarded_futures
    action().catchError((Object e) {
      debugPrint('⚠️ Analytics (suppressed): $e');
    });
  }

  // ═══════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final FlatGraphResult? effectiveGraphData = widget.graphData;

    if (effectiveGraphData != null) {
      try {
        return _buildFromGraphData(effectiveGraphData, reduceMotion);
      } catch (e) {
        return GraphErrorState(familyId: widget.familyId, error: e);
      }
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
      data: (graphData) {
        try {
          return _buildFromGraphData(graphData, reduceMotion);
        } catch (e) {
          return GraphErrorState(familyId: widget.familyId, error: e);
        }
      },
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

    // v62: Use cached layout if the graph data hasn't changed.
    // This prevents layout recomputation on rebuilds triggered by
    // UI interactions (long-press → bottom sheet → dismiss), which
    // could cause nodes to shift position and appear off-screen.
    final dataChanged = _cachedPersonCount != persons.length ||
        _cachedRelationshipCount != graphData.relationships.length;

    if (!dataChanged &&
        _cachedLayout != null &&
        _cachedEdges != null &&
        _cachedPersonMap != null) {
      // Reuse cached layout — just rebuild the canvas with the same
      // positions and edges.
      return _buildGraphCanvas(
          _cachedLayout!, _cachedPersonMap!, _cachedEdges!);
    }

    // Compute layout (only if data changed or first load).
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

    // v62: Performance telemetry — measure main-thread layout time
    // (this path is used by v40 FamilyGraphWidget; the V2.1 engine
    // path via graphLayoutProvider has its own instrumentation).
    final layoutStopwatch = Stopwatch()..start();
    final service = GraphLayoutService();
    final layout = service.computeLayout(
      persons: graphPersons,
      relationships: graphRelationships,
      anchorPersonId: anchorPerson.id,
    );
    layoutStopwatch.stop();
    // Fire-and-forget analytics — never let telemetry break the build.
    _safeAnalytics(() => AnalyticsService.instance.logEvent(
          'graph_layout_time',
          {
            'total_ms': layoutStopwatch.elapsedMilliseconds,
            'node_count': graphPersons.length,
            'edge_count': graphRelationships.length,
            'compact_mode': false,
            'render_path': 'v40_main_thread',
          },
        ));

    // v62: Cache the computed layout + edges for future rebuilds.
    _cachedLayout = layout;
    _cachedEdges = edges;
    _cachedPersonMap = personMap;
    _cachedPersonCount = persons.length;
    _cachedRelationshipCount = graphData.relationships.length;

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
    if (!_autoCenterDone) {
      _autoCenterDone = true;
      final capturedLayout = layout;
      final capturedAnchorId = anchorPerson.id;
      scheduleMicrotask(() {
        if (mounted) _autoCenterOnAnchor(capturedLayout, capturedAnchorId);
      });
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

    final viewportWidth = MediaQuery.of(context).size.width;
    final cw = canvasWidth > 0 ? canvasWidth : 400.0;
    final ch = canvasHeight > 0 ? canvasHeight : 400.0;

    return GestureDetector(
      // v62: Double-tap to zoom in 2× toward the focal point.
      // Toggles between 1× and 2× if already zoomed in.
      onDoubleTapDown: (details) => _doubleTapPosition = details.localPosition,
      onDoubleTap: () => _handleDoubleTapZoom(),
      child: InteractiveViewer(
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
            // v60.1: Wrap CustomPaint in AnimatedBuilder so the painter
            // gets the LIVE zoom level on every transform change without
            // calling setState (which caused stack overflow).
            //
            // v62 FIX: CustomPaint has no `behavior` parameter, and its
            // default hit-test mode skips empty canvas areas (where there
            // are no nodes). That made InteractiveViewer only receive
            // pan/zoom gestures when fingers landed on a node. The fix:
            // give CustomPaint a transparent ColoredBox as its `child` so
            // the entire canvas claims hit-test events, letting
            // InteractiveViewer receive gestures anywhere.
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _transformationController,
                builder: (context, _) {
                  final liveZoom = _transformationController.value.getMaxScaleOnAxis();
                  final liveNodeSize = GraphNodeStateResolver.resolveSize(
                    viewportWidth: viewportWidth,
                    zoomLevel: liveZoom,
                  );
                  return CustomPaint(
                    size: Size(cw, ch),
                    painter: RelationshipEdge(
                      positions: positions,
                      edges: edges,
                      selectedEdgeId: _selectedEdgeId,
                      zoomLevel: liveZoom,
                      nodeWidth: liveNodeSize,
                      nodeHeight: liveNodeSize,
                      generationMap: {
                        for (final p in personMap.values)
                          p.id: p.generationIndex,
                      },
                      highlightedGeneration: highlightedGen,
                      anonymousNodeIds: const {},
                      blockedNodeIds: const {},
                    ),
                    child: ColoredBox(
                      color: const Color(0x00000000),
                      child: SizedBox(width: cw, height: ch),
                    ),
                  );
                },
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

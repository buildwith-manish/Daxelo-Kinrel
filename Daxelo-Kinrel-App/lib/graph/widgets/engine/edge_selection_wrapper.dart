// lib/graph/widgets/engine/edge_selection_wrapper.dart
// P0.4: Extracted from family_graph_engine_view.dart.
//
// Wraps the EngineEdgePainter in a ConsumerStatefulWidget so that edge-tap
// selection rebuilds ONLY the painter (not the entire graph). This
// localizes rebuilds and keeps the graph smooth during edge interactions.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/kinship/kinship_edge_style.dart' show KinshipEdgeCategory;
import '../../../features/family/presentation/providers/family_graph_provider.dart'
    show selectedEdgeProvider;
import '../../engine/edge_dedup.dart' show DedupedEdge;
import '../../interaction/couple_union_model.dart' show CoupleUnion;
import '../../interaction/spring_palette.dart' show SpringCurves;
import '../../rendering/edge_path_cache.dart' show EdgePathCache;
import '../../rendering/edge_quality.dart' show EdgeQuality, EdgeQualityX;
import 'engine_edge_painter.dart' show EngineEdgePainter;
import '../../interaction/graph_path_trace_controller.dart' show GraphPathTraceController;
import '../../rendering/graph_lighting.dart' show GraphLighting;
import '../../interaction/graph_kinship_path_focus.dart' show graphPathFocusProvider;
import '../../../core/constants/brand_colors.dart' show KinrelColors;
import '../../data/graph_data_models.dart' show GraphEdgeData;

class EdgeSelectionWrapper extends ConsumerStatefulWidget {
  const EdgeSelectionWrapper({
    super.key,
    required this.positions,
    required this.edges,
    required this.edgeCategories,
    required this.edgeCustomColors,
    required this.cache,
    required this.edgeQuality,
    required this.graphRevision,
    required this.layoutRevision,
    required this.edgeVisualRevision,
    required this.dimmedEdgeIds,
    required this.pathFocusedEdgeIds,
    required this.pathFocusActive,
    // v5.x (Feature 3 — labels on demand): when non-null AND
    // [pathFocusActive] is true, the painter renders small relationship-
    // type labels near the midpoint of each path edge.
    this.pathFocusLabels,
    this.coupleUnions = const [],
    this.edgeWaypoints = const {},
    // v5.125 (Step 6): anchor geometry for the bow-around-the-anchor
    // edge routing + sector fan-out (geometry only — no colour
    // changes). Null keeps the exact pre-v5.125 curve.
    this.anchorId,
    this.anchorCenter,
    this.connectOnOpenActive = false,
    this.connectOnOpenCurrentEdgeId,
    this.connectOnOpenProgress = 0.0,
    this.connectOnOpenRevealedEdgeIds = const <String>{},
    this.connectOnOpenCurrentEdgeIds = const <String>{},
    this.zoom = 1.0,
    // v5.x (perf fix — pinch-zoom GPU-transform): gesture flag +
    // commit revision forwarded straight through to the painter.
    // See the painter's field docs for the contract.
    this.painterActiveGesture = false,
    this.zoomCommitRevision = 0,
    // v5.140 (PERF): The connect-on-open trace controller. When non-
    // null, the wrapper listens to the controller's ticks and setStates
    // INTERNALLY — so connect-on-open animation ticks repaint ONLY the
    // edge painter, not the entire graph canvas. The parent state no
    // longer calls setState on tick. The wrapper reads the controller's
    // current state in build() and overrides the static
    // connectOnOpen* props below when the controller is active.
    this.connectOnOpenController,
  });

  final Map<String, Offset> positions;
  final List<DedupedEdge> edges;
  final Map<String, KinshipEdgeCategory> edgeCategories;
  final Map<String, Map<String, dynamic>> edgeCustomColors;

  /// v5.22 (PART 2): Personal RELATIVE edge midpoint bow offsets,
  /// keyed by relationshipId. When an override exists for an edge,
  /// the painter bows the bezier's middle control point(s) by this
  /// delta (relative to the true t=0.5 midpoint). When no override
  /// exists (the normal case), the painter uses the existing
  /// `_bezier` + PathMetric t=0.5 midpoint calculation unchanged.
  ///
  /// HARD CONSTRAINT: this map is the ONLY way a relationship line's
  /// visual geometry can be modified by user drag. The drag handler
  /// must never call createRelationship/updateRelationship/
  /// deleteRelationship — see _handleRearrangeDragUpdate assertion.
  final Map<String, Offset> edgeWaypoints;

  /// v5.27 Task 2: Connect-on-open animation state. While true, the
  /// painter HIDES non-revealed edges (alpha=0) instead of dimming
  /// them. The current edge fades in over its time slot using
  /// connectOnOpenProgress. Revealed edges (in
  /// connectOnOpenRevealedEdgeIds) are drawn at full alpha.
  ///
  /// Reuses the EXISTING GraphPathTraceController's state shape
  /// (currentEdgeId + traceProgress + completedEdgeIds + traceActive)
  /// — the painter interprets these with fade-in semantics instead of
  /// the existing sweep semantics when this flag is true.
  final bool connectOnOpenActive;
  final String? connectOnOpenCurrentEdgeId;
  final double connectOnOpenProgress;
  final Set<String> connectOnOpenRevealedEdgeIds;

  /// v5.97: Set of all edges animating simultaneously (parallel mode).
  final Set<String> connectOnOpenCurrentEdgeIds;

  /// v5.107: Current camera zoom level for zoom-aware stroke width.
  final double zoom;

  /// v99 (Phase 6): Derived couple unions from the layout. The painter
  /// renders a subtle junction glyph at the midpoint between partners
  /// for each union, and routes parent→child edges through the union
  /// midpoint when the child is a confirmed child of both partners.
  final List<CoupleUnion> coupleUnions;

  /// v5.125 (Step 6): The anchor person's ID + center position (in the
  /// same coordinate space as [positions]). Passed straight through to
  /// the painter for the bow-around-the-anchor routing and the
  /// anchor-sector fan-out.
  final String? anchorId;
  final Offset? anchorCenter;

  final EdgePathCache cache;

  /// LOD-derived visual quality tier for the entire edge layer. Computed
  /// ONCE per build from the current graph LOD; the painter never
  /// derives quality per edge.
  final EdgeQuality edgeQuality;

  /// Lightweight revision counters. The painter compares these in
  /// `shouldRepaint` instead of deep-comparing thousands of map entries
  /// every animation frame. See PART 11.
  final int graphRevision;
  final int layoutRevision;
  final int edgeVisualRevision;

  /// Edges that should be visually dimmed (relationship focus mode,
  /// PART 13). Null or empty set = no dimming. The selected edge and
  /// path-focused edges are NEVER dimmed.
  final Set<String>? dimmedEdgeIds;

  /// v92 (PART 14): Edges that are part of the focused viewer→target
  /// kinship path. These retain normal clarity (or slightly increased
  /// clarity) while unrelated edges dim. The selected edge, sweep
  /// edge, and trace edge are always included implicitly by the
  /// painter — they do NOT need to be in this set.
  final Set<String>? pathFocusedEdgeIds;

  /// v92 (PART 14): True when a path focus is active (target selected
  /// and path resolved). When false, `pathFocusedEdgeIds` is ignored.
  final bool pathFocusActive;

  /// v5.x (Feature 3 — labels on demand): Optional map of edge ID →
  /// relationship-type label (e.g. "Father", "Sister", "Uncle"). When
  /// non-null AND [pathFocusActive] is true, the painter renders a
  /// small text label near the midpoint of every path-focused edge.
  /// The label is NOT rendered by default — only when the user has
  /// selected a node AND a path has been resolved. This is the
  /// "labels on demand, not always-on" behavior the user asked for.
  final Map<String, String>? pathFocusLabels;

  /// v5.x (perf fix — pinch-zoom GPU-transform): True while the user
  /// is actively performing a pinch-zoom (or pan) gesture on the
  /// graph canvas. Forwarded straight through to the painter — see
  /// [EngineEdgePainter.painterActiveGesture] for the contract.
  final bool painterActiveGesture;

  /// v5.x (perf fix — pinch-zoom GPU-transform): Monotonically
  /// increasing integer bumped by the engine view state to force a
  /// real repaint (with current zoom baked into stroke widths) on
  /// gesture end and on large interim zoom excursions. Forwarded
  /// straight through to the painter — see
  /// [EngineEdgePainter.zoomCommitRevision] for the contract.
  final int zoomCommitRevision;

  /// v5.140 (PERF): The connect-on-open trace controller. See the
  /// constructor doc for the contract.
  final GraphPathTraceController? connectOnOpenController;

  @override
  ConsumerState<EdgeSelectionWrapper> createState() =>
      EdgeSelectionWrapperState();
}

class EdgeSelectionWrapperState extends ConsumerState<EdgeSelectionWrapper>
    with TickerProviderStateMixin {
  late final AnimationController _sweepController;
  Animation<double>? _sweepAnimation;

  /// The edge ID that was selected when the current sweep started. The
  /// painter uses this (not `selectedEdgeProvider`) to decide which Path
  /// to draw the sweep on, so the sweep stays attached to the right
  /// edge even if selection changes mid-sweep.
  String? _sweepEdgeId;

  /// v92 (PART 15): The sequential path trace controller. One
  /// controller for the entire edge layer — drives edge-by-edge
  /// one-shot sweeps along the focused path.
  late final GraphPathTraceController _traceController;

  /// The ordered edge IDs of the path currently being traced (or
  /// last traced). Used to detect when a new path is resolved so we
  /// can (re)start the trace.
  List<String> _lastTracedEdgeIds = const [];

  /// Reduced-motion preference. When true, the sweep AND the trace
  /// are suppressed and the selected edge / path render in their
  /// static premium state immediately.
  bool _reducedMotion = false;

  @override
  void initState() {
    super.initState();
    _sweepController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: GraphLighting.sweepDurationMs),
    );
    _sweepAnimation = CurvedAnimation(
      parent: _sweepController,
      // P3.1: spring-backed curve so the edge-selection sweep feels
      // alive (critically damped, no overshoot). Replaces the previous
      // cubic ease-out curve per the P3.1 verification check.
      curve: SpringCurves.zoom,
    )..addListener(_onSweepTick);
    _traceController = GraphPathTraceController()..attach(this);
    _traceController.addListener(_onTraceTick);
    // v5.140 (PERF): Listen to the connect-on-open controller so its
    // ticks repaint ONLY this wrapper (not the entire graph canvas).
    // The parent state used to call setState on every tick, which
    // rebuilt every visible GraphNode + the canvas chrome. Now the
    // repaint is scoped to just the edge painter.
    widget.connectOnOpenController?.addListener(_onConnectOnOpenTick);
    // Reduced-motion is resolved per-build via MediaQuery; default false.
  }

  @override
  void didUpdateWidget(covariant EdgeSelectionWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    // v5.140: If the controller instance changed (rare — happens on
    // family switch), rebind the listener.
    if (oldWidget.connectOnOpenController != widget.connectOnOpenController) {
      oldWidget.connectOnOpenController?.removeListener(_onConnectOnOpenTick);
      widget.connectOnOpenController?.addListener(_onConnectOnOpenTick);
    }
  }

  @override
  void dispose() {
    _sweepAnimation?.removeListener(_onSweepTick);
    _sweepController.dispose();
    _traceController.removeListener(_onTraceTick);
    _traceController.dispose();
    // v5.140: Remove the connect-on-open listener. The controller
    // itself is owned (and disposed) by the parent state.
    widget.connectOnOpenController?.removeListener(_onConnectOnOpenTick);
    super.dispose();
  }

  void _onSweepTick() {
    if (mounted) setState(() {});
  }

  void _onTraceTick() {
    if (mounted) setState(() {});
  }

  /// v5.140 (PERF): Connect-on-open tick handler. Repaints ONLY this
  /// wrapper (the edge painter) — not the entire graph canvas. This
  /// is the single biggest win for pan/zoom smoothness during the
  /// 1–3s connect-on-open animation window on first graph load.
  void _onConnectOnOpenTick() {
    if (mounted) setState(() {});
  }

  /// Called from `build()` to (re)evaluate reduced-motion and start a
  /// fresh sweep when selection changes. This is the SINGLE place that
  /// decides whether to animate — keeping the logic out of the painter.
  void _maybeStartSweep(String? selectedEdgeId) {
    final bool reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced != _reducedMotion) {
      _reducedMotion = reduced;
      // P3.2: propagate the reduced-motion flag to the path-trace
      // controller so it can suppress per-step haptics.
      _traceController.reducedMotion = reduced;
    }

    // No selection → cancel any in-flight sweep.
    if (selectedEdgeId == null) {
      _sweepController.stop();
      _sweepEdgeId = null;
      return;
    }

    // Same selection as the running sweep → no-op.
    if (selectedEdgeId == _sweepEdgeId) return;

    // New selection → start one sweep (unless reduced motion).
    if (_reducedMotion ||
        !widget.edgeQuality.allowsSweep ||
        !widget.edgeQuality.allowsRidge) {
      // Static-only: immediately show the selected state, no sweep.
      _sweepController.stop();
      _sweepEdgeId = selectedEdgeId;
      return;
    }

    _sweepEdgeId = selectedEdgeId;
    _sweepController.forward(from: 0.0);
  }

  /// v92 (PART 15): Drive the sequential path trace. Called from
  /// `build()` whenever the path focus changes. If the path is new
  /// (different ordered edge IDs), the trace (re)starts. If reduced
  /// motion is on, the path is revealed statically instead.
  void _maybeStartTrace() {
    final pathFocus = ref.read(graphPathFocusProvider).focus;

    if (pathFocus == null || pathFocus.orderedEdgeIds.isEmpty) {
      // No path → reset trace.
      if (_lastTracedEdgeIds.isNotEmpty) {
        _traceController.reset();
        _lastTracedEdgeIds = const [];
      }
      return;
    }

    // Same path as already traced → no-op.
    if (_listEquals(_lastTracedEdgeIds, pathFocus.orderedEdgeIds)) {
      return;
    }

    _lastTracedEdgeIds = List.unmodifiable(pathFocus.orderedEdgeIds);

    // DOT LOD: never animate the trace — reveal statically.
    // CHIP LOD: also skip the trace for performance; reveal statically.
    // FULL LOD: animate (unless reduced motion).
    if (_reducedMotion ||
        !widget.edgeQuality.allowsSweep ||
        !widget.edgeQuality.allowsRidge) {
      _traceController.revealAll(pathFocus.orderedEdgeIds);
    } else {
      _traceController.startTrace(pathFocus.orderedEdgeIds);
    }
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final String? selectedEdgeId = ref.watch(selectedEdgeProvider);
    _maybeStartSweep(selectedEdgeId);
    _maybeStartTrace();

    final double sweepProgress = _sweepAnimation?.value ?? 0.0;
    final bool sweepActive = _sweepController.isAnimating &&
        !_reducedMotion &&
        widget.edgeQuality.allowsSweep;

    // v92 (PART 15): Read the trace state once per build.
    final traceState = _traceController.state;

    // v5.140 (PERF): Read the connect-on-open state directly from the
    // controller (when present) instead of from the parent-passed
    // widget.connectOnOpen* props. The parent no longer setState()s
    // on tick — the controller's listener (added in initState) drives
    // this wrapper's setState, so the controller is always up-to-date
    // here. Falls back to the widget props when no controller is
    // supplied (legacy callers / unit tests).
    final connController = widget.connectOnOpenController;
    final bool connectOnOpenActive;
    final String? connectOnOpenCurrentEdgeId;
    final double connectOnOpenProgress;
    final Set<String> connectOnOpenRevealedEdgeIds;
    final Set<String> connectOnOpenCurrentEdgeIds;
    if (connController != null) {
      final s = connController.state;
      connectOnOpenActive = s.traceActive ||
          s.completedEdgeIds.isNotEmpty ||
          s.currentEdgeIds.isNotEmpty;
      connectOnOpenCurrentEdgeId = s.currentEdgeId;
      connectOnOpenProgress = s.traceProgress;
      connectOnOpenRevealedEdgeIds = s.completedEdgeIds;
      connectOnOpenCurrentEdgeIds = s.currentEdgeIds;
    } else {
      connectOnOpenActive = widget.connectOnOpenActive;
      connectOnOpenCurrentEdgeId = widget.connectOnOpenCurrentEdgeId;
      connectOnOpenProgress = widget.connectOnOpenProgress;
      connectOnOpenRevealedEdgeIds = widget.connectOnOpenRevealedEdgeIds;
      connectOnOpenCurrentEdgeIds = widget.connectOnOpenCurrentEdgeIds;
    }

    return CustomPaint(
      painter: EngineEdgePainter(
        positions: widget.positions,
        edges: widget.edges,
        edgeCategories: widget.edgeCategories,
        edgeCustomColors: widget.edgeCustomColors,
        coupleUnions: widget.coupleUnions,
        cache: widget.cache,
        // v5.125 (Step 6): anchor geometry for the edge bow routing.
        anchorId: widget.anchorId,
        anchorCenter: widget.anchorCenter,
        selectedEdgeId: selectedEdgeId,
        edgeQuality: widget.edgeQuality,
        graphRevision: widget.graphRevision,
        layoutRevision: widget.layoutRevision,
        edgeVisualRevision: widget.edgeVisualRevision,
        dimmedEdgeIds: widget.dimmedEdgeIds,
        sweepEdgeId: sweepActive ? _sweepEdgeId : null,
        sweepProgress: sweepActive ? sweepProgress : 0.0,
        sweepActive: sweepActive,
        // v92 (PARTS 14–15): path focus + sequential trace state.
        pathFocusedEdgeIds: widget.pathFocusActive
            ? widget.pathFocusedEdgeIds
            : null,
        pathFocusActive: widget.pathFocusActive,
        // v5.x (Feature 3 — labels on demand): pass the labels map
        // through to the painter. The painter only renders labels
        // when pathFocusActive is true AND the map is non-null.
        pathFocusLabels: widget.pathFocusLabels,
        traceEdgeId: traceState.traceActive ? traceState.currentEdgeId : null,
        traceProgress: traceState.traceActive ? traceState.traceProgress : 0.0,
        traceActive: traceState.traceActive,
        completedTraceEdgeIds: traceState.completedEdgeIds.isNotEmpty
            ? traceState.completedEdgeIds
            : null,
        // v5.22 (PART 2): personal edge midpoint bow offsets.
        edgeWaypoints: widget.edgeWaypoints,
        // v5.27 Task 2: connect-on-open animation state — propagated
        // straight through to the painter. The painter branches on
        // connectOnOpenActive to hide non-revealed edges + fade in
        // the current edge over its time slot.
        // v5.140 (PERF): Now sourced from the controller directly when
        // present, so the wrapper's per-tick setState drives the
        // repaint instead of the parent's.
        connectOnOpenActive: connectOnOpenActive,
        connectOnOpenCurrentEdgeId: connectOnOpenCurrentEdgeId,
        connectOnOpenProgress: connectOnOpenProgress,
        connectOnOpenRevealedEdgeIds: connectOnOpenRevealedEdgeIds,
        connectOnOpenCurrentEdgeIds: connectOnOpenCurrentEdgeIds,
        zoom: widget.zoom,  // v5.107: zoom-aware stroke width
        // v5.x (perf fix — pinch-zoom GPU-transform): forward the
        // gesture flag + commit revision straight through to the
        // painter. The painter uses these to skip zoom-driven
        // repaints during an active pinch (GPU transform handles the
        // visual update) and to commit one real repaint on gesture
        // end / large interim zoom excursion.
        painterActiveGesture: widget.painterActiveGesture,
        zoomCommitRevision: widget.zoomCommitRevision,
      ),
      child: const SizedBox.expand(),
    );
  }
}

/// Paths are memoised in [EdgePathCache] keyed by quantized endpoint
/// positions. Because graph-space positions are constant during pan/zoom,
/// repeated frames hit the cache and skip path construction entirely. The
/// factory is O(1) (no per-edge node-collision scan).
///
/// v91 (FINAL 10/10 PASS): The painter is now a stateless physical
/// thread renderer. For each edge it applies the GraphLighting contract:
///
///   FULL LOD — solid edges:
///     PASS 1: contact shadow (neutral black, offset down-right)
///     PASS 2: relationship body (category colour, custom colour)
///     PASS 3: directional light ridge (top-left highlight)
///
///   FULL LOD — dashed edges:
///     Per visible dash segment, the SAME three passes are applied
///     so each dash reads as a physical chip, not a flat coloured
///     tick. Gaps remain real — no continuous glow underneath.
///
///   CHIP LOD: same three passes with conservative sigma / ridge alpha.
///
///   DOT LOD: a single relationship-coloured stroke, no blur, no
///   midpoint, no ridge.
///
///   SELECTED edge (FULL LOD): four passes — stronger shadow, body,
///   brighter ridge, subtle Kinrel-orange interaction aura. The
///   relationship identity is preserved; orange is the interaction
///   accent only.
///
///   ONE-SHOT SWEEP: when `sweepActive`, a short near-white highlight
///   segment travels ONCE along the selected edge's cached Path. The
///   painter does NOT own the AnimationController — it receives
///   `sweepProgress` and draws the segment at that position.
///
/// v92 (PARTS 14–15) PATH FOCUS + SEQUENTIAL TRACE:
///   When `pathFocusActive` is true, edges in `pathFocusedEdgeIds`
///   retain their relationship category colour (and custom colour)
///   but receive a subtle clarity boost — they are NOT recoloured
///   orange. Unrelated edges (those in `dimmedEdgeIds`) dim to ~70%
///   alpha. The trace edge (when `traceActive`) receives the same
///   moving sweep highlight as the selected-edge sweep, reusing the
///   existing `_paintSweepSegment` pass. Completed trace edges
///   remain statically focused via the path-focus state.

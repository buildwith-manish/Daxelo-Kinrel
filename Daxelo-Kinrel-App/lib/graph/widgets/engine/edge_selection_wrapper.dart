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
import '../../rendering/edge_path_cache.dart' show EdgePathCache;
import '../../rendering/edge_quality.dart' show EdgeQuality;
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
    this.coupleUnions = const [],
  });

  final Map<String, Offset> positions;
  final List<DedupedEdge> edges;
  final Map<String, KinshipEdgeCategory> edgeCategories;
  final Map<String, Map<String, dynamic>> edgeCustomColors;

  /// v99 (Phase 6): Derived couple unions from the layout. The painter
  /// renders a subtle junction glyph at the midpoint between partners
  /// for each union, and routes parent→child edges through the union
  /// midpoint when the child is a confirmed child of both partners.
  final List<CoupleUnion> coupleUnions;

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
      curve: Curves.easeOutCubic,
    )..addListener(_onSweepTick);
    _traceController = GraphPathTraceController()..attach(this);
    _traceController.addListener(_onTraceTick);
    // Reduced-motion is resolved per-build via MediaQuery; default false.
  }

  @override
  void dispose() {
    _sweepAnimation?.removeListener(_onSweepTick);
    _sweepController.dispose();
    _traceController.removeListener(_onTraceTick);
    _traceController.dispose();
    super.dispose();
  }

  void _onSweepTick() {
    if (mounted) setState(() {});
  }

  void _onTraceTick() {
    if (mounted) setState(() {});
  }

  /// Called from `build()` to (re)evaluate reduced-motion and start a
  /// fresh sweep when selection changes. This is the SINGLE place that
  /// decides whether to animate — keeping the logic out of the painter.
  void _maybeStartSweep(String? selectedEdgeId) {
    final bool reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced != _reducedMotion) {
      _reducedMotion = reduced;
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

    return CustomPaint(
      painter: EngineEdgePainter(
        positions: widget.positions,
        edges: widget.edges,
        edgeCategories: widget.edgeCategories,
        edgeCustomColors: widget.edgeCustomColors,
        coupleUnions: widget.coupleUnions,
        cache: widget.cache,
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
        traceEdgeId: traceState.traceActive ? traceState.currentEdgeId : null,
        traceProgress: traceState.traceActive ? traceState.traceProgress : 0.0,
        traceActive: traceState.traceActive,
        completedTraceEdgeIds: traceState.completedEdgeIds.isNotEmpty
            ? traceState.completedEdgeIds
            : null,
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

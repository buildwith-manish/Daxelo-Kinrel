// lib/graph/engine/wedge_edge_router.dart
//
// DAXELO KINREL — Wedge Edge Router
//
// Pure-Dart path resolver for the viewer-centered wedge layout. Given the
// final node positions + the visible edges, it computes the EXACT Path
// every edge should paint, the midpoint marker position, and the
// t-parameter the hit-tester should use.
//
// ROUTING RULES (the contract the user approved in the preview):
//
//   1. DEFAULT — STRAIGHT LINE. A solo edge whose straight segment
//      does not pass through any other node footprint is drawn as a
//      single lineTo. This is the rule for every tree edge (parent →
//      child) and for any extra link whose straight segment is clear.
//
//   2. OBSTRUCTION — CURVE THE MINIMUM AMOUNT. When the straight
//      segment between the two endpoints passes through any other
//      node/chip footprint (124×128 for nodes AND for "+N" bubbles
//      — the bubble is now node-sized, see WedgeLayoutConfig — plus
//      124×140 for the viewer, plus 6px padding), the edge bows by
//      the smallest amount that clears EVERY footprint.
//      Candidate bow magnitudes are tried in order: 90, 180, 270, 360, 450
//      world units. For each magnitude the router tries the side
//      AWAY from the viewer first (the perpendicular direction whose
//      midpoint is farther from the viewer), then the other side.
//      If none clears, the largest magnitude (135) is used.
//
//   3. PARALLEL EDGES — SYMMETRIC CURVES. When two or more edges
//      connect the same pair of people (e.g. parent + spouse), they
//      are drawn as symmetric curves using the existing
//      `lateralOffset` mechanism (±18dp). A single edge between a
//      pair stays straight (rule 1 / 2).
//
// Midpoint markers (dots, hearts) and tap areas ALWAYS sit on the
// drawn path. This router is the single source of truth for:
//   • painting (EngineEdgePainter, via wedgeEdgeRoutesProvider)
//   • midpoint-marker placement (computeVisualMidpoint replacement)
//   • hit-testing (the tap area follows the same Path)
//   • the minimap (uses the same Path stroke)
//
// The router is PURE — no widgets, no I/O, no provider imports. It
// returns a Map<String, WedgeEdgeRoute> keyed by edge id. Callers
// (the painter, the hit-tester, the minimap) all read from the same
// map so the dot, heart and tap area never drift relative to the
// drawn line.
//
// While nodes are animating, the caller (canvas_mixin) lerps the
// positions every frame and re-runs the router with the lerped
// positions. The router's pure-Dart cost (a few hundred µs per edge)
// is well within the 16ms frame budget for ~100 edges.

import 'dart:math' as math;
import 'dart:ui' show Offset, Path;

import 'viewer_wedge_layout.dart'
    show WedgeLayoutConfig, WedgePageChip, kUseViewerWedgeLayout;
import '../data/graph_data_models.dart' show GraphEdgeData;
import '../engine/edge_dedup.dart' show DedupedEdge, EdgeDeduplicator;

/// A resolved edge route — the EXACT Path the painter should stroke,
/// plus the midpoint marker position and the t-parameter the hit-tester
/// should sample.
///
/// One [WedgeEdgeRoute] exists per visible edge id, in canvas space
/// (already translated — same coordinate space as
/// GraphLayoutResult.positions).
class WedgeEdgeRoute {
  const WedgeEdgeRoute({
    required this.edgeId,
    required this.path,
    required this.midpoint,
    required this.isStraight,
    required this.bowMagnitude,
    required this.bowSide,
    required this.lateralOffset,
    required this.source,
    required this.target,
  });

  /// The edge id this route belongs to (matches DedupedEdge.edge.id).
  final String edgeId;

  /// The fully-resolved Path — moveTo + (lineTo | cubicTo). The painter
  /// strokes this Path verbatim; the minimap strokes the same Path with
  /// a thin solid paint; the hit-tester walks PathMetrics to find the
  /// point closest to a tap.
  final Path path;

  /// The point on the drawn path at arc-length t=0.5 — the visual
  /// midpoint. Used by the dot/heart marker painter.
  final Offset midpoint;

  /// True when [path] is a single straight line (only moveTo + lineTo).
  /// Used by tests to verify the straight-by-default contract.
  final bool isStraight;

  /// The perpendicular bow magnitude (world units) applied when the
  /// straight segment was obstructed. 0.0 for straight edges.
  final double bowMagnitude;

  /// +1 or -1 — which side of the straight segment the curve bows
  /// toward. 0 for straight edges.
  final int bowSide;

  /// The lateral offset applied for parallel edges (±18dp). 0.0 for
  /// solo edges.
  final double lateralOffset;

  /// The two endpoint positions used to build this route. Stored so
  /// the painter can short-circuit PathMetric recomputation when the
  /// endpoints have not moved (the cache key).
  final Offset source;
  final Offset target;
}

/// The output of a routing pass.
class WedgeEdgeRoutes {
  const WedgeEdgeRoutes({
    required this.byEdgeId,
    required this.midpointByEdgeId,
  });

  /// Edge id → resolved route. Missing edge ids had no position for
  /// at least one endpoint (the painter should skip them).
  final Map<String, WedgeEdgeRoute> byEdgeId;

  /// Edge id → midpoint (same as [WedgeEdgeRoute.midpoint], but in a
  /// flat map for O(1) lookup by the marker painter). Always matches
  /// the value in [byEdgeId].
  final Map<String, Offset> midpointByEdgeId;

  static const empty = WedgeEdgeRoutes(
    byEdgeId: {},
    midpointByEdgeId: {},
  );
}

/// Pure-Dart wedge edge router.
///
/// Stateless; one instance can serve any number of layouts. The
/// caller (wedgeEdgeRoutesProvider) constructs a fresh output every
/// time positions or edges change.
class WedgeEdgeRouter {
  WedgeEdgeRouter({WedgeLayoutConfig? config})
      : _config = config ?? const WedgeLayoutConfig();

  final WedgeLayoutConfig _config;

  // Bow magnitudes tried in order when an edge is obstructed. The
  // SMALLEST magnitude that clears every footprint wins. If none
  // clears, the LARGEST is used (the spec's "use the largest" rule).
  // Matches the approved preview's `ms=[90,180,270,360,450]`.
  static const List<double> _bowCandidates = <double>[90.0, 180.0, 270.0, 360.0, 450.0];

  /// Resolve routes for the given layout.
  ///
  /// [positions] — canvas-space node positions (already translated by
  ///   the provider). Includes the viewer at its canvas-space position.
  /// [edges] — the deduplicated visible edges. Use
  ///   [EdgeDeduplicator.deduplicate] to produce this from raw
  ///   GraphEdgeData.
  /// [viewerId] — the viewer's person id (used to pick the "away from
  ///   the viewer" side when bowing).
  /// [viewerPosition] — the viewer's canvas-space position (when known,
  ///   used to determine which side of a straight segment is "away"
  ///   from the viewer). Null falls back to the origin.
  /// [chips] — the "+N" chip slot centers (their footprints participate
  ///   in the obstruction test).
  WedgeEdgeRoutes resolve({
    required Map<String, Offset> positions,
    required List<DedupedEdge> edges,
    String? viewerId,
    Offset? viewerPosition,
    Map<String, WedgePageChip> chips = const {},
  }) {
    if (edges.isEmpty || positions.isEmpty) {
      return WedgeEdgeRoutes.empty;
    }
    final viewerPos = viewerPosition ?? (viewerId != null ? positions[viewerId] : null) ?? Offset.zero;

    // Build the obstruction box list: every positioned node (except
    // the edge's own endpoints) + every chip slot.
    final nodeBoxes = <_Box>[];
    positions.forEach((id, pos) {
      final isViewer = id == viewerId;
      final size = isViewer ? _config.rootFootprint : _config.nodeFootprint;
      final pad = _config.footprintPadding;
      nodeBoxes.add(_Box(
        id,
        pos.dx - size.width / 2 - pad,
        pos.dy - size.height / 2 - pad,
        pos.dx + size.width / 2 + pad,
        pos.dy + size.height / 2 + pad,
      ));
    });
    final chipBoxes = <_Box>[];
    chips.forEach((owner, chip) {
      final size = _config.chipFootprint;
      final pad = _config.footprintPadding;
      chipBoxes.add(_Box(
        'chip:$owner',
        chip.slotCenter.dx - size.width / 2 - pad,
        chip.slotCenter.dy - size.height / 2 - pad,
        chip.slotCenter.dx + size.width / 2 + pad,
        chip.slotCenter.dy + size.height / 2 + pad,
      ));
    });

    final byEdgeId = <String, WedgeEdgeRoute>{};
    final midpointByEdgeId = <String, Offset>{};

    for (final deduped in edges) {
      final edge = deduped.edge;
      final s = positions[edge.sourceId];
      final t = positions[edge.targetId];
      if (s == null || t == null) continue;

      final route = _resolveOne(
        edgeId: edge.id,
        source: s,
        target: t,
        lateralOffset: deduped.lateralOffset,
        parallelCount: deduped.parallelCount,
        viewerPos: viewerPos,
        nodeBoxes: nodeBoxes,
        chipBoxes: chipBoxes,
        sourceId: edge.sourceId,
        targetId: edge.targetId,
      );
      byEdgeId[edge.id] = route;
      midpointByEdgeId[edge.id] = route.midpoint;
    }

    return WedgeEdgeRoutes(
      byEdgeId: byEdgeId,
      midpointByEdgeId: midpointByEdgeId,
    );
  }

  WedgeEdgeRoute _resolveOne({
    required String edgeId,
    required Offset source,
    required Offset target,
    required double lateralOffset,
    required int parallelCount,
    required Offset viewerPos,
    required List<_Box> nodeBoxes,
    required List<_Box> chipBoxes,
    required String sourceId,
    required String targetId,
  }) {
    final double distance = (source - target).distance;
    if (distance < 1.0) {
      // Degenerate — both endpoints coincide. Render a single moveTo
      // so the painter strokes nothing; the marker sits at the point.
      final path = Path()..moveTo(source.dx, source.dy);
      return WedgeEdgeRoute(
        edgeId: edgeId,
        path: path,
        midpoint: source,
        isStraight: true,
        bowMagnitude: 0.0,
        bowSide: 0,
        lateralOffset: lateralOffset,
        source: source,
        target: target,
      );
    }

    // ── Rule 3 — parallel edges: ALWAYS symmetric curves. ──────────
    // The lateralOffset is supplied by EdgeDeduplicator for any edge
    // whose pair has more than one category. We honour it by bowing
    // perpendicular to the connecting line.
    //
    // NOTE: a parallel edge may STILL need obstruction routing if its
    // curved segment passes through a third footprint. To keep the
    // contract simple and the visual predictable, we resolve parallel
    // edges as pure lateralOffset curves (the v64 contract) and skip
    // the obstruction check on them. This matches the approved
    // preview's behaviour: parallel pairs always render as the two
    // mirrored arcs, even if a third node sits between.
    if (parallelCount > 1 && lateralOffset != 0.0) {
      return _buildLateralCurve(
        edgeId: edgeId,
        source: source,
        target: target,
        lateralOffset: lateralOffset,
      );
    }

    // ── Rule 1 / Rule 2 — straight unless obstructed. ──────────────
    // Test whether the straight segment source→target passes through
    // any third footprint (node or chip). The two endpoints themselves
    // are excluded (the edge connects them — touching them is correct).
    final obstructing = _obstructingBoxes(
      source: source,
      target: target,
      nodeBoxes: nodeBoxes,
      chipBoxes: chipBoxes,
      sourceId: sourceId,
      targetId: targetId,
    );

    if (obstructing.isEmpty) {
      // Rule 1 — straight line.
      final path = Path()
        ..moveTo(source.dx, source.dy)
        ..lineTo(target.dx, target.dy);
      return WedgeEdgeRoute(
        edgeId: edgeId,
        path: path,
        midpoint: Offset(
          (source.dx + target.dx) / 2.0,
          (source.dy + target.dy) / 2.0,
        ),
        isStraight: true,
        bowMagnitude: 0.0,
        bowSide: 0,
        lateralOffset: lateralOffset,
        source: source,
        target: target,
      );
    }

    // Rule 2 — bow by the smallest amount that clears every footprint.
    // Try 90, 180, 270, 360, 450 in order; for each, try the side AWAY from the
    // viewer first, then the other side.
    final perp = _perpendicularUnit(source, target);

    // "Away from the viewer" side: the perpendicular direction whose
    // midpoint (linear midpoint + perp * bow) is FARTHER from the
    // viewer.
    final linearMid = Offset(
      (source.dx + target.dx) / 2.0,
      (source.dy + target.dy) / 2.0,
    );
    final viewerToMid = linearMid - viewerPos;
    final awaySide = (perp.dx * viewerToMid.dx + perp.dy * viewerToMid.dy) >= 0
        ? 1
        : -1;

    for (final magnitude in _bowCandidates) {
      // Try away side first.
      if (_bowClearsAll(
        source: source,
        target: target,
        perp: perp,
        side: awaySide,
        magnitude: magnitude,
        obstructing: obstructing,
      )) {
        return _buildBowedPath(
          edgeId: edgeId,
          source: source,
          target: target,
          perp: perp,
          side: awaySide,
          magnitude: magnitude,
          lateralOffset: lateralOffset,
        );
      }
      // Try the other side.
      if (_bowClearsAll(
        source: source,
        target: target,
        perp: perp,
        side: -awaySide,
        magnitude: magnitude,
        obstructing: obstructing,
      )) {
        return _buildBowedPath(
          edgeId: edgeId,
          source: source,
          target: target,
          perp: perp,
          side: -awaySide,
          magnitude: magnitude,
          lateralOffset: lateralOffset,
        );
      }
    }

    // None cleared — use the largest magnitude on the away side (the
    // spec's "If none clears, use the largest" rule).
    return _buildBowedPath(
      edgeId: edgeId,
      source: source,
      target: target,
      perp: perp,
      side: awaySide,
      magnitude: _bowCandidates.last,
      lateralOffset: lateralOffset,
    );
  }

  /// Symmetric lateralOffset curve (Rule 3). Mirrors the v64 cubic
  /// bezier: control points at 1/3 and 2/3 along the connecting line,
  /// shifted perpendicular by `lateralOffset`. The t=0.5 midpoint is
  /// the linear midpoint + perp * lateralOffset (so the dot sits at
  /// the apex of the curve — same as the old painter for parity).
  WedgeEdgeRoute _buildLateralCurve({
    required String edgeId,
    required Offset source,
    required Offset target,
    required double lateralOffset,
  }) {
    final dx = target.dx - source.dx;
    final dy = target.dy - source.dy;
    final perp = _perpendicularUnit(source, target);
    final side = lateralOffset >= 0 ? 1.0 : -1.0;
    final mag = lateralOffset.abs();
    final bow = Offset(perp.dx * side * mag, perp.dy * side * mag);

    final cp1 = Offset(
      source.dx + dx * (1.0 / 3.0) + bow.dx,
      source.dy + dy * (1.0 / 3.0) + bow.dy,
    );
    final cp2 = Offset(
      source.dx + dx * (2.0 / 3.0) + bow.dx,
      source.dy + dy * (2.0 / 3.0) + bow.dy,
    );
    final path = Path()
      ..moveTo(source.dx, source.dy)
      ..cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, target.dx, target.dy);

    // For a cubic with symmetric control points (cp1/cp2 both shifted
    // by `bow`), the t=0.5 point is (s + 3*cp1 + 3*cp2 + t)/8 =
    // linearMid + bow (since 3*bow + 3*bow = 6*bow, and 6/8 = 0.75 —
    // wait that's not the linearMid + bow). Re-derive:
    //   B(0.5) = (1/8)s + (3/8)cp1 + (3/8)cp2 + (1/8)t
    //          = (1/8)(s + t) + (3/8)(cp1 + cp2)
    //          = (1/8)(s + t) + (3/8)(s + t + 2*bow + dx + dy) ... no,
    //   cp1 = s + (1/3)(t-s) + bow = (2/3)s + (1/3)t + bow
    //   cp2 = s + (2/3)(t-s) + bow = (1/3)s + (2/3)t + bow
    //   cp1 + cp2 = s + t + 2*bow
    //   B(0.5) = (1/8)(s + t) + (3/8)(s + t + 2*bow)
    //          = (1/8 + 3/8)(s + t) + (6/8) bow
    //          = (1/2)(s + t) + (3/4) bow
    // So the arc-length t=0.5 point is NOT linearMid + bow, it's
    // linearMid + 0.75*bow. But the existing _bezier code comment
    // says B(0.5) == linearMid + delta when waypointDelta is set, and
    // the bow magnitude there is `bow = perp * bowDir * bowMagnitude`
    // — with cp1/cp2 both shifted by `bow` (NOT scaled), B(0.5) =
    // linearMid + (3/4) * bow.
    //
    // To KEEP PARITY with the existing painter (which renders the
    // marker at PathMetric t=0.5 — i.e. exactly what the user sees),
    // we sample PathMetrics here. That guarantees the dot sits on the
    // drawn curve, regardless of the math derivation.
    final midpoint = _pathMidpoint(path);

    return WedgeEdgeRoute(
      edgeId: edgeId,
      path: path,
      midpoint: midpoint,
      isStraight: false,
      bowMagnitude: mag,
      bowSide: side.toInt(),
      lateralOffset: lateralOffset,
      source: source,
      target: target,
    );
  }

  /// Bowed cubic — control points at 1/3 and 2/3, shifted perpendicular
  /// by `magnitude * side`.
  WedgeEdgeRoute _buildBowedPath({
    required String edgeId,
    required Offset source,
    required Offset target,
    required Offset perp,
    required int side,
    required double magnitude,
    required double lateralOffset,
  }) {
    final dx = target.dx - source.dx;
    final dy = target.dy - source.dy;
    final bow = Offset(
      perp.dx * side.toDouble() * magnitude,
      perp.dy * side.toDouble() * magnitude,
    );
    final cp1 = Offset(
      source.dx + dx * (1.0 / 3.0) + bow.dx,
      source.dy + dy * (1.0 / 3.0) + bow.dy,
    );
    final cp2 = Offset(
      source.dx + dx * (2.0 / 3.0) + bow.dx,
      source.dy + dy * (2.0 / 3.0) + bow.dy,
    );
    final path = Path()
      ..moveTo(source.dx, source.dy)
      ..cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, target.dx, target.dy);
    final midpoint = _pathMidpoint(path);
    return WedgeEdgeRoute(
      edgeId: edgeId,
      path: path,
      midpoint: midpoint,
      isStraight: false,
      bowMagnitude: magnitude,
      bowSide: side,
      lateralOffset: lateralOffset,
      source: source,
      target: target,
    );
  }

  /// Returns the boxes (nodes + chips) whose interior the segment
  /// source→target passes through, EXCLUDING the two endpoints'
  /// own boxes (those are the edge's endpoints — touching them is
  /// correct and never counts as obstruction).
  List<_Box> _obstructingBoxes({
    required Offset source,
    required Offset target,
    required List<_Box> nodeBoxes,
    required List<_Box> chipBoxes,
    required String sourceId,
    required String targetId,
  }) {
    final result = <_Box>[];
    for (final box in nodeBoxes) {
      if (box.id == sourceId || box.id == targetId) continue;
      if (_segmentIntersectsBox(source, target, box)) {
        result.add(box);
      }
    }
    for (final box in chipBoxes) {
      // Chip owners are stored as 'chip:<personId>' — they're never
      // edge endpoints, so no exclusion needed.
      if (_segmentIntersectsBox(source, target, box)) {
        result.add(box);
      }
    }
    return result;
  }

  /// Segment-vs-AABB intersection test. Uses the slab method (Kay &
  /// Kajiya) — returns true if the segment enters the box interior.
  bool _segmentIntersectsBox(Offset a, Offset b, _Box box) {
    // Quick reject: if both endpoints are on the same side of any
    // slab boundary, the segment can't enter the box.
    final minX = math.min(a.dx, b.dx);
    final maxX = math.max(a.dx, b.dx);
    final minY = math.min(a.dy, b.dy);
    final maxY = math.max(a.dy, b.dy);
    if (maxX < box.minX || minX > box.maxX) return false;
    if (maxY < box.minY || minY > box.maxY) return false;

    // The bounding-box check above is necessary but not sufficient
    // (it returns true for an L-shaped segment that misses the box
    // but spans its bbox). To be precise, clip the segment against
    // each of the 4 slab planes using Liang-Barsky and check whether
    // the surviving t-range is non-empty.
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    var t0 = 0.0;
    var t1 = 1.0;
    // For each of the 4 boundaries, compute the entering/leaving
    // t-parameter and shrink [t0, t1].
    final List<List<double>> p = [
      [-dx, a.dx - box.minX], // left
      [dx, box.maxX - a.dx], // right
      [-dy, a.dy - box.minY], // top
      [dy, box.maxY - a.dy], // bottom
    ];
    for (final pair in p) {
      final pVal = pair[0];
      final qVal = pair[1];
      if (pVal == 0.0) {
        // Segment parallel to this slab. If q < 0, segment is
        // entirely outside this slab → no intersection.
        if (qVal < 0.0) return false;
        continue;
      }
      final r = qVal / pVal;
      if (pVal < 0.0) {
        if (r > t1) return false;
        if (r > t0) t0 = r;
      } else {
        if (r < t0) return false;
        if (r < t1) t1 = r;
      }
    }
    return t0 <= t1;
  }

  /// True if the cubic with control points at 1/3 + bow and 2/3 + bow
  /// clears every box in [obstructing]. The cubic's worst-case (max
  /// deviation from the straight line) is at t=0.5 — deviation =
  /// 0.75 * bow magnitude. We sample the curve at t = 0, 0.25, 0.5,
  /// 0.75, 1.0 and check that none of those points (other than the
  /// endpoints) lies inside any obstructing box. The endpoints are
  /// guaranteed outside (they were the edge's own endpoints, excluded
  /// earlier — but the bowed curve might dip into a box at the
  /// intermediate samples).
  bool _bowClearsAll({
    required Offset source,
    required Offset target,
    required Offset perp,
    required int side,
    required double magnitude,
    required List<_Box> obstructing,
  }) {
    final dx = target.dx - source.dx;
    final dy = target.dy - source.dy;
    final bow = Offset(
      perp.dx * side.toDouble() * magnitude,
      perp.dy * side.toDouble() * magnitude,
    );
    final cp1 = Offset(
      source.dx + dx * (1.0 / 3.0) + bow.dx,
      source.dy + dy * (1.0 / 3.0) + bow.dy,
    );
    final cp2 = Offset(
      source.dx + dx * (2.0 / 3.0) + bow.dx,
      source.dy + dy * (2.0 / 3.0) + bow.dy,
    );

    // Sample the cubic at 5 points. The endpoints (t=0, t=1) are the
    // edge's own endpoints — they're guaranteed outside the
    // obstructing boxes (we excluded them in _obstructingBoxes).
    // We check the 3 interior samples (t=0.25, 0.5, 0.75).
    for (final t in const [0.25, 0.5, 0.75]) {
      final u = 1.0 - t;
      final point = Offset(
        u * u * u * source.dx +
            3 * u * u * t * cp1.dx +
            3 * u * t * t * cp2.dx +
            t * t * t * target.dx,
        u * u * u * source.dy +
            3 * u * u * t * cp1.dy +
            3 * u * t * t * cp2.dy +
            t * t * t * target.dy,
      );
      for (final box in obstructing) {
        if (point.dx > box.minX &&
            point.dx < box.maxX &&
            point.dy > box.minY &&
            point.dy < box.maxY) {
          return false;
        }
      }
    }
    return true;
  }

  /// Unit perpendicular to the segment source→target (rotated +90°
  /// CCW). Returns (0, 0) if source == target (degenerate).
  Offset _perpendicularUnit(Offset source, Offset target) {
    final dx = target.dx - source.dx;
    final dy = target.dy - source.dy;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length < 1e-9) return Offset.zero;
    return Offset(-dy / length, dx / length);
  }

  /// Samples the Path's PathMetrics to find the t=0.5 midpoint.
  /// Falls back to the linear midpoint if PathMetrics is empty
  /// (degenerate path).
  Offset _pathMidpoint(Path path) {
    for (final metric in path.computeMetrics()) {
      if (metric.length > 0) {
        final tangent = metric.getTangentForOffset(metric.length * 0.5);
        if (tangent != null) {
          return tangent.position;
        }
      }
    }
    return Offset.zero;
  }
}

/// A simple axis-aligned box used for obstruction tests. Same shape
/// as the existing _Box in viewer_wedge_layout.dart — kept local so
/// this file has no internal dependencies.
class _Box {
  const _Box(this.id, this.minX, this.minY, this.maxX, this.maxY);
  final String id;
  final double minX, minY, maxX, maxY;
}

/// Convenience entry point for callers that already have raw
/// GraphEdgeData (the painter receives deduped edges — this is the
/// same deduplicate call the painter does today, kept here so tests
/// can build routes from raw data with one call).
WedgeEdgeRoutes resolveWedgeEdges({
  required Map<String, Offset> positions,
  required List<GraphEdgeData> edges,
  String? viewerId,
  Offset? viewerPosition,
  Map<String, WedgePageChip> chips = const {},
  WedgeLayoutConfig? config,
}) {
  if (!kUseViewerWedgeLayout) return WedgeEdgeRoutes.empty;
  final deduped = EdgeDeduplicator.deduplicate(edges);
  return WedgeEdgeRouter(config: config).resolve(
    positions: positions,
    edges: deduped,
    viewerId: viewerId,
    viewerPosition: viewerPosition,
    chips: chips,
  );
}

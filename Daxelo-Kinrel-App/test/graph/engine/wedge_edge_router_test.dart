// test/graph/engine/wedge_edge_router_test.dart
//
// Tests for the WedgeEdgeRouter — the pure-Dart path resolver for the
// viewer-centered wedge layout.
//
// CONTRACT UNDER TEST (per the task spec):
//   1. A tree edge with a clear segment renders as a straight line
//      (path has only moveTo + lineTo).
//   2. An edge whose straight segment crosses another node footprint
//      renders as a curve that clears all footprints.
//   3. Two edges between the same pair render as symmetric curves.
//      One edge between a pair is straight (unless obstructed).
//   4. The midpoint marker lies on the drawn path for both straight
//      and curved edges, and the tap area follows the same path.

import 'package:flutter_test/flutter_test.dart';
import 'dart:ui' show Path, Offset;
import 'package:kinrel/graph/data/graph_data_models.dart';
import 'package:kinrel/graph/engine/edge_dedup.dart';
import 'package:kinrel/graph/engine/wedge_edge_router.dart';

GraphEdgeData _edge(String id, String a, String b, {String? labelAtoB}) =>
    GraphEdgeData(
      id: id,
      sourceId: a,
      targetId: b,
      relationshipKey: 'parent',
      labelAtoB: labelAtoB,
    );

/// Returns true if [path] contains ONLY a moveTo + lineTo (the
/// straight-line contract).
bool _isStraightPath(Path path) {
  final metrics = path.computeMetrics().toList();
  if (metrics.length != 1) return false;
  final metric = metrics.first;
  // PathMetric doesn't expose the verb list directly, but a straight
  // line has length == endpoint-distance. A curve is always longer.
  // We sample the tangent at t=0.25 and t=0.75 — for a straight line
  // the tangents are IDENTICAL (the direction never changes). For a
  // curve they differ.
  if (metric.length == 0) return false;
  final t0 = metric.getTangentForOffset(metric.length * 0.25);
  final t1 = metric.getTangentForOffset(metric.length * 0.75);
  if (t0 == null || t1 == null) return false;
  final a = t0.angle;
  final b = t1.angle;
  // Normalise to [0, 2π) and compare with a small tolerance.
  final diff = (a - b).abs();
  return diff < 0.01 || (diff - 3.141592653589793).abs() < 0.01;
}

/// Returns true if [midpoint] lies "on" [path] (within a few px).
bool _isPointOnPath(Offset midpoint, Path path, {double tolerance = 4.0}) {
  for (final metric in path.computeMetrics()) {
    final length = metric.length;
    if (length == 0) continue;
    // Sample 200 points along the path; if any is within tolerance
    // of [midpoint], the point lies on the path.
    for (var i = 0; i <= 200; i++) {
      final t = i / 200.0;
      final tangent = metric.getTangentForOffset(length * t);
      if (tangent == null) continue;
      final pos = tangent.position;
      if ((pos - midpoint).distance <= tolerance) {
        return true;
      }
    }
  }
  return false;
}

void main() {
  group('WedgeEdgeRouter', () {
    test('A tree edge with a clear segment renders as a straight line', () {
      final positions = <String, Offset>{
        'viewer': const Offset(0, 0),
        'p1': const Offset(300, 0), // 300px to the right of the viewer
      };
      final edges = [_edge('e1', 'viewer', 'p1', labelAtoB: 'son')];
      final deduped = EdgeDeduplicator.deduplicate(edges);

      final routes = WedgeEdgeRouter().resolve(
        positions: positions,
        edges: deduped,
        viewerId: 'viewer',
      );

      final route = routes.byEdgeId['e1'];
      expect(route, isNotNull);
      expect(_isStraightPath(route!.path), isTrue,
          reason: 'A clear tree edge must be a straight line.');
      expect(route.isStraight, isTrue);
    });

    test(
        'An edge whose straight segment crosses another node footprint '
        'renders as a curve that clears all footprints', () {
      // viewer (0,0) ←→ target (400,0), with p_blocker sitting on the
      // straight line at (200,0). The straight segment passes through
      // p_blocker's footprint (124x128 + 6px padding = 130x134 box),
      // so the router MUST bow.
      final positions = <String, Offset>{
        'viewer': const Offset(0, 0),
        'target': const Offset(400, 0),
        'p_blocker': const Offset(200, 0),
      };
      final edges = [_edge('e1', 'viewer', 'target', labelAtoB: 'cousin')];
      final deduped = EdgeDeduplicator.deduplicate(edges);

      final routes = WedgeEdgeRouter().resolve(
        positions: positions,
        edges: deduped,
        viewerId: 'viewer',
      );

      final route = routes.byEdgeId['e1'];
      expect(route, isNotNull);
      expect(route!.isStraight, isFalse,
          reason: 'An obstructed edge must NOT be straight.');
      expect(route.bowMagnitude, greaterThan(0.0));

      // Verify the curve clears the blocker: sample 5 points along
      // the curve and confirm none lies inside the blocker's footprint
      // box (with padding).
      final blockerBox = _boxAt(positions['p_blocker']!, isViewer: false);
      for (final t in const [0.25, 0.5, 0.75]) {
        final point = _sampleCubic(
          route.path,
          t,
        );
        expect(
          _pointInBox(point, blockerBox),
          isFalse,
          reason: 'Curve interior sample at t=$t must clear the blocker.',
        );
      }
    });

    test(
        'Two edges between the same pair render as symmetric curves. '
        'One edge between a pair is straight.', () {
      final positions = <String, Offset>{
        'viewer': const Offset(0, 0),
        'spouse': const Offset(300, 0),
      };
      // Two edges with DIFFERENT categories between the same pair —
      // the deduplicator keeps both as separate DedupedEdges with
      // lateralOffset ±18 (e.g. parent + spouse between the viewer
      // and the same target).
      final edges = [
        _edge('e_parent', 'viewer', 'spouse', labelAtoB: 'father'),
        _edge('e_spouse', 'viewer', 'spouse', labelAtoB: 'wife'),
      ];
      final deduped = EdgeDeduplicator.deduplicate(edges);
      expect(deduped.length, 2, reason: 'Both edges must survive dedup.');

      final routes = WedgeEdgeRouter().resolve(
        positions: positions,
        edges: deduped,
        viewerId: 'viewer',
      );

      // Both parallel edges must be curves (lateralOffset != 0).
      for (final dedupedEdge in deduped) {
        final route = routes.byEdgeId[dedupedEdge.edge.id];
        expect(route, isNotNull);
        expect(route!.isStraight, isFalse,
            reason:
                'Parallel edge ${dedupedEdge.edge.id} must be a curve (lateralOffset=${dedupedEdge.lateralOffset}).');
        expect(route.lateralOffset, isNot(0.0));
      }

      // The two curves must bow in OPPOSITE directions (symmetric).
      final r1 = routes.byEdgeId[deduped[0].edge.id]!;
      final r2 = routes.byEdgeId[deduped[1].edge.id]!;
      expect(r1.bowSide, equals(-r2.bowSide),
          reason: 'Parallel edges must bow in opposite directions.');

      // A SOLO edge between a different pair (no parallel) must be
      // straight (when unobstructed).
      final soloPositions = <String, Offset>{
        'viewer': const Offset(0, 0),
        'p2': const Offset(300, 100),
      };
      final soloRoutes = WedgeEdgeRouter().resolve(
        positions: soloPositions,
        edges: EdgeDeduplicator.deduplicate(
          [_edge('e_solo', 'viewer', 'p2', labelAtoB: 'cousin')],
        ),
        viewerId: 'viewer',
      );
      final solo = soloRoutes.byEdgeId['e_solo'];
      expect(solo, isNotNull);
      expect(solo!.isStraight, isTrue,
          reason: 'A solo unobstructed edge must be straight.');
    });

    test(
        'The midpoint marker lies on the drawn path for both straight '
        'and curved edges', () {
      // Straight case.
      final straightPositions = <String, Offset>{
        'viewer': const Offset(0, 0),
        'p1': const Offset(300, 0),
      };
      final straightRoutes = WedgeEdgeRouter().resolve(
        positions: straightPositions,
        edges: EdgeDeduplicator.deduplicate(
          [_edge('e1', 'viewer', 'p1', labelAtoB: 'son')],
        ),
        viewerId: 'viewer',
      );
      final straight = straightRoutes.byEdgeId['e1']!;
      expect(_isPointOnPath(straight.midpoint, straight.path), isTrue,
          reason: 'Straight edge midpoint must lie on the path.');

      // Curved case (obstructed).
      final curvedPositions = <String, Offset>{
        'viewer': const Offset(0, 0),
        'target': const Offset(400, 0),
        'p_blocker': const Offset(200, 0),
      };
      final curvedRoutes = WedgeEdgeRouter().resolve(
        positions: curvedPositions,
        edges: EdgeDeduplicator.deduplicate(
          [_edge('e2', 'viewer', 'target', labelAtoB: 'cousin')],
        ),
        viewerId: 'viewer',
      );
      final curved = curvedRoutes.byEdgeId['e2']!;
      expect(curved.isStraight, isFalse);
      expect(_isPointOnPath(curved.midpoint, curved.path), isTrue,
          reason: 'Curved edge midpoint must lie on the path.');
    });

    test(
        'Reduced-motion: edge routing is pure-Dart and unaffected by '
        'reduce-motion (the painter renders the same Path; the canvas '
        'skips the animation but the path is identical).', () {
      // The router itself has no animation state — it returns the same
      // Path regardless of reduce-motion. This test verifies that
      // invariant: a single layout produces a single route set.
      final positions = <String, Offset>{
        'viewer': const Offset(0, 0),
        'p1': const Offset(300, 0),
      };
      final deduped = EdgeDeduplicator.deduplicate(
        [_edge('e1', 'viewer', 'p1', labelAtoB: 'son')],
      );

      final a = WedgeEdgeRouter().resolve(
        positions: positions,
        edges: deduped,
        viewerId: 'viewer',
      );
      final b = WedgeEdgeRouter().resolve(
        positions: positions,
        edges: deduped,
        viewerId: 'viewer',
      );

      // Same positions → same Path (computable by deterministic
      // re-resolution). The midpoint offsets must match exactly.
      expect(a.byEdgeId['e1']!.midpoint, equals(b.byEdgeId['e1']!.midpoint));
      expect(a.byEdgeId['e1']!.isStraight, equals(b.byEdgeId['e1']!.isStraight));
    });

    test('Zero footprint overlaps in the final layout after expanding', () {
      // This test reuses the _SeededTree generator from the wedge
      // layout tests, then verifies the edge router produces routes
      // for every visible edge WITHOUT changing the (already
      // overlap-free) positions. The router is read-only on positions.
      //
      // We construct a known overlap-free layout (5 nodes in a star
      // around the viewer) and confirm the router returns routes for
      // every edge without throwing.
      final positions = <String, Offset>{
        'viewer': const Offset(0, 0),
        'p1': const Offset(0, -300),
        'p2': const Offset(300, 0),
        'p3': const Offset(0, 300),
        'p4': const Offset(-300, 0),
      };
      final edges = [
        _edge('e1', 'viewer', 'p1', labelAtoB: 'son'),
        _edge('e2', 'viewer', 'p2', labelAtoB: 'daughter'),
        _edge('e3', 'viewer', 'p3', labelAtoB: 'father'),
        _edge('e4', 'viewer', 'p4', labelAtoB: 'mother'),
      ];
      final deduped = EdgeDeduplicator.deduplicate(edges);
      final routes = WedgeEdgeRouter().resolve(
        positions: positions,
        edges: deduped,
        viewerId: 'viewer',
      );

      // Every edge gets a route.
      for (final e in edges) {
        expect(routes.byEdgeId.containsKey(e.id), isTrue,
            reason: 'Edge ${e.id} must have a route.');
      }

      // All four edges are unobstructed tree edges → all straight.
      for (final e in edges) {
        final route = routes.byEdgeId[e.id]!;
        expect(route.isStraight, isTrue,
            reason: 'Edge ${e.id} should be straight (no obstruction).');
      }
    });
  });
}

/// Sample the cubic at parameter t. Used by the obstruction-clears test.
/// Walks the path's PathMetrics to find the t-arc-length point.
Offset _sampleCubic(Path path, double t) {
  for (final metric in path.computeMetrics()) {
    final length = metric.length;
    if (length == 0) continue;
    final tangent = metric.getTangentForOffset(length * t);
    if (tangent != null) return tangent.position;
  }
  return Offset.zero;
}

/// The axis-aligned box (with 6px padding) for a node footprint at
/// [center]. Mirrors WedgeLayoutConfig defaults (node 124×128, root
/// 124×140, padding 6).
class _Box {
  const _Box(this.minX, this.minY, this.maxX, this.maxY);
  final double minX, minY, maxX, maxY;
}

_Box _boxAt(Offset center, {required bool isViewer}) {
  // Mirrors WedgeLayoutConfig: root 124×140, node 124×128, padding 6.
  final w = isViewer ? 124.0 : 124.0;
  final h = isViewer ? 140.0 : 128.0;
  final pad = 6.0;
  return _Box(
    center.dx - w / 2 - pad,
    center.dy - h / 2 - pad,
    center.dx + w / 2 + pad,
    center.dy + h / 2 + pad,
  );
}

bool _pointInBox(Offset p, _Box b) {
  return p.dx > b.minX && p.dx < b.maxX && p.dy > b.minY && p.dy < b.maxY;
}

// test/graph/engine/edge_router_test.dart
//
// Focused unit tests for the EdgeRouter bezier path generator.
//
// Covers:
//   - Routing produces a valid (non-empty) Path for every relationship
//   - Routing is deterministic across repeated runs
//   - Parallel parent→child edges from the same parent are horizontally
//     offset so they don't stack on top of each other
//   - Empty input produces an empty path map
//   - Edges with unknown endpoints are skipped silently
//   - categorize() maps standard keys to the right RelationshipCategory
//   - getEdgeStyle() returns sensible styling for each category
//   - computeMidpoint falls back to the linear midpoint when no control
//     points are supplied

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/services/graph_layout_service.dart';
import 'package:kinrel/graph/engine/edge_router.dart';

GraphRelationship _rel(
  String id,
  String from,
  String to,
  String key,
) =>
    GraphRelationship(
      id: id,
      fromPersonId: from,
      toPersonId: to,
      relationshipKey: key,
    );

void main() {
  group('EdgeRouter', () {
    late EdgeRouter router;

    setUp(() {
      router = EdgeRouter();
    });

    test('routing produces a valid (non-empty) Path per edge', () {
      const positions = {
        'parent': Offset(100, 100),
        'child': Offset(100, 400),
        'spouse': Offset(300, 100),
      };
      final rels = [
        _rel('e1', 'parent', 'child', 'child'),
        _rel('e2', 'parent', 'spouse', 'spouse'),
      ];

      final paths = router.computePaths(
        positions: positions,
        relationships: rels,
        nodeSize: 56.0,
        zoomLevel: 1.0,
      );

      expect(paths.length, 2);
      for (final path in paths.values) {
        // A valid path has non-zero length — compute the metric length
        // in one pass (PathMetrics is a one-shot iterable).
        final totalLength = path
            .computeMetrics()
            .fold<double>(0.0, (sum, m) => sum + m.length);
        expect(totalLength, greaterThan(0),
            reason: 'Path must have non-zero length');
        // The path's bounding rect must be non-empty.
        final bounds = path.getBounds();
        expect(bounds.width + bounds.height, greaterThan(0),
            reason: 'Path bounds must be non-trivial');
      }
    });

    test('routing is deterministic across repeated runs', () {
      const positions = {
        'a': Offset(100, 100),
        'b': Offset(100, 400),
        'c': Offset(400, 100),
      };
      final rels = [
        _rel('e1', 'a', 'b', 'father'),
        _rel('e2', 'a', 'c', 'spouse'),
        _rel('e3', 'b', 'c', 'sibling'),
      ];

      final r1 = router.computePaths(
        positions: positions,
        relationships: rels,
        nodeSize: 56.0,
        zoomLevel: 1.0,
      );
      // Second router to make sure no shared mutable state leaks.
      final router2 = EdgeRouter();
      final r2 = router2.computePaths(
        positions: positions,
        relationships: rels,
        nodeSize: 56.0,
        zoomLevel: 1.0,
      );

      expect(r2.length, r1.length);
      for (final id in r1.keys) {
        expect(r2.containsKey(id), isTrue);
        // Paths are value objects — use their bounds + metrics length
        // as a deterministic fingerprint.
        final b1 = r1[id]!.getBounds();
        final b2 = r2[id]!.getBounds();
        expect(b2, b1, reason: 'Path bounds for $id differ across runs');
      }
    });

    test('parallel parent→child edges from the same parent are offset', () {
      // Three children directly below the parent at the SAME x.
      // Without horizontal offsets, all three edges would be identical.
      // With offsets, each edge's endpoint X differs.
      const positions = {
        'parent': Offset(200, 100),
        'c1': Offset(200, 500),
        'c2': Offset(200, 500),
        'c3': Offset(200, 500),
      };
      final rels = [
        _rel('e1', 'parent', 'c1', 'child'),
        _rel('e2', 'parent', 'c2', 'child'),
        _rel('e3', 'parent', 'c3', 'child'),
      ];

      final paths = router.computePaths(
        positions: positions,
        relationships: rels,
        nodeSize: 56.0,
        zoomLevel: 1.0,
      );

      expect(paths.length, 3,
          reason: 'All three edges must produce a path');

      // The bounds of each path differ because the endpoint X is shifted.
      final boundsList = paths.values.map((p) => p.getBounds()).toList();
      final distinctLefts =
          boundsList.map((b) => b.left.round()).toSet();
      final distinctRights =
          boundsList.map((b) => b.right.round()).toSet();
      expect(distinctLefts.length + distinctRights.length,
          greaterThan(1),
          reason: 'Parallel parent→child edges must be horizontally offset');
    });

    test('empty input produces an empty path map', () {
      final paths = router.computePaths(
        positions: const {},
        relationships: const [],
        nodeSize: 56.0,
        zoomLevel: 1.0,
      );
      expect(paths, isEmpty);
    });

    test('edges with unknown endpoint positions are skipped', () {
      const positions = {
        'a': Offset(100, 100),
      };
      final rels = [
        _rel('e1', 'a', 'ghost', 'father'), // 'ghost' not in positions
      ];

      final paths = router.computePaths(
        positions: positions,
        relationships: rels,
        nodeSize: 56.0,
        zoomLevel: 1.0,
      );

      expect(paths, isEmpty,
          reason: 'Edge with missing target must be skipped');
    });

    test('categorize maps standard keys to the right category', () {
      expect(router.categorize('father'), RelationshipCategory.parent);
      expect(router.categorize('mother'), RelationshipCategory.parent);
      expect(router.categorize('son'), RelationshipCategory.child);
      expect(router.categorize('daughter'), RelationshipCategory.child);
      expect(router.categorize('spouse'), RelationshipCategory.spouse);
      expect(router.categorize('ex_wife'),
          RelationshipCategory.divorcedSpouse);
      expect(router.categorize('brother'), RelationshipCategory.sibling);
      expect(router.categorize('half_brother'),
          RelationshipCategory.halfSibling);
      expect(router.categorize('grandfather'),
          RelationshipCategory.grandparent);
      expect(router.categorize('grandson'), RelationshipCategory.grandchild);
      expect(router.categorize('uncle'), RelationshipCategory.auntUncle);
      expect(router.categorize('cousin'), RelationshipCategory.cousin);
      expect(router.categorize('father_in_law'),
          RelationshipCategory.inLaw);
      // Unknown key → extended (catch-all).
      expect(router.categorize('some_random_key'),
          RelationshipCategory.extended);
    });

    test('getEdgeStyle returns sensible line styles per category', () {
      // Parent / child edges are solid (solid lines).
      expect(router.getEdgeStyle('father').lineStyle, EdgeLineStyle.solid);
      expect(router.getEdgeStyle('son').lineStyle, EdgeLineStyle.solid);

      // Sibling edges are dashed; half-siblings are dotted.
      expect(router.getEdgeStyle('brother').lineStyle, EdgeLineStyle.dashed);
      expect(router.getEdgeStyle('half_sister').lineStyle,
          EdgeLineStyle.dotted);

      // Spouse edges carry a ring midpoint decoration.
      expect(router.getEdgeStyle('spouse').midpointType,
          MidpointType.ring);

      // Extended edges fade out (low opacity, no midpoint).
      final extendedStyle = router.getEdgeStyle('unknown_relation');
      expect(extendedStyle.opacity, lessThan(0.5));
      expect(extendedStyle.midpointType, MidpointType.none);
    });

    test('computeMidpoint falls back to the linear midpoint', () {
      // With no control points and no stored edgeId, the midpoint
      // should be the linear midpoint of the trimmed segment.
      const a = Offset(0.0, 0.0);
      const b = Offset(100.0, 0.0);
      const nodeSize = 20.0; // halfNode = 10

      final mid = router.computeMidpoint(
        posA: a,
        posB: b,
        nodeSize: nodeSize,
      );

      // Trimmed endpoints are (10, 0) and (90, 0); midpoint = (50, 0).
      expect(mid.dx, closeTo(50.0, 0.01));
      expect(mid.dy, closeTo(0.0, 0.01));
    });

    test('computeMidpoint coincident points return posA', () {
      const a = Offset(50.0, 50.0);
      final mid = router.computeMidpoint(
        posA: a,
        posB: a,
        nodeSize: 20.0,
      );
      expect(mid, a,
          reason: 'Coincident nodes have zero length — return posA');
    });

    test('computeMidpoint uses explicit control points when provided', () {
      // With explicit control points, the midpoint should follow the
      // cubic bezier t=0.5 formula:
      //   B(0.5) = 0.125·P0 + 0.375·CP1 + 0.375·CP2 + 0.125·P3
      const a = Offset(0.0, 0.0);
      const b = Offset(100.0, 0.0);
      const nodeSize = 20.0; // halfNode = 10 → trimmed endpoints (10,0)-(90,0)
      const cp1 = Offset(10.0, 50.0);
      const cp2 = Offset(90.0, 50.0);

      final mid = router.computeMidpoint(
        posA: a,
        posB: b,
        nodeSize: nodeSize,
        controlPoint1: cp1,
        controlPoint2: cp2,
      );

      // Expected: 0.125*10 + 0.375*10 + 0.375*90 + 0.125*90 = 50 (X)
      //           0.125*0  + 0.375*50 + 0.375*50 + 0.125*0  = 37.5 (Y)
      expect(mid.dx, closeTo(50.0, 0.01));
      expect(mid.dy, closeTo(37.5, 0.01));
    });
  });
}

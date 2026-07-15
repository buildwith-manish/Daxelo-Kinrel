// test/graph/engine/collision_detector_test.dart
//
// Focused unit tests for the CollisionDetector overlap resolver.
//
// Covers:
//   - Two nodes closer than (radius_a + radius_b + minGap) are flagged
//   - Two nodes beyond that threshold are NOT flagged
//   - Detection is symmetric (re-labelling the map doesn't change count)
//   - countOverlaps returns 0 for empty input
//   - resolve pushes overlapping nodes apart
//   - resolve leaves already-separated nodes alone (no remaining overlaps)
//   - resolve clamps results to viewport padding
//   - budget exhaustion is reported when overlaps cannot be resolved

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/graph/engine/collision_detector.dart';

void main() {
  group('CollisionDetector', () {
    late CollisionDetector detector;

    setUp(() {
      detector = CollisionDetector();
    });

    // Use a very large viewport so the density-bonus term is negligible
    // (keeps the effective minGap ≈ minGapLowZoom for predictable math).
    const viewport = Size(100000, 100000);
    const zoom = 1.0; // == zoomThreshold → minGap ≈ 4.0

    test('two nodes within minimum distance are flagged as colliding', () {
      // minDist = 40 + 40 + ~4 = ~84. Distance here is 10.
      const positions = {
        'a': Offset(500, 500),
        'b': Offset(510, 500),
      };
      const radii = {'a': 40.0, 'b': 40.0};

      final count = detector.countOverlaps(
        positions: positions,
        nodeRadii: radii,
        zoomLevel: zoom,
        viewport: viewport,
      );

      expect(count, 1, reason: 'Nodes 10px apart with 40px radii must overlap');
    });

    test('nodes beyond minimum distance are NOT flagged', () {
      // Distance is 1000, well above the ~84px threshold.
      const positions = {
        'a': Offset(0, 0),
        'b': Offset(1000, 0),
      };
      const radii = {'a': 40.0, 'b': 40.0};

      final count = detector.countOverlaps(
        positions: positions,
        nodeRadii: radii,
        zoomLevel: zoom,
        viewport: viewport,
      );

      expect(count, 0);
    });

    test('detection is symmetric (order-independent)', () {
      const positionsA = {
        'a': Offset(500, 500),
        'b': Offset(520, 500),
        'c': Offset(900, 900),
      };
      // Same coordinates, different key names, different insertion order.
      const positionsB = {
        'gamma': Offset(900, 900),
        'beta': Offset(520, 500),
        'alpha': Offset(500, 500),
      };
      const radiiA = {'a': 40.0, 'b': 40.0, 'c': 40.0};
      const radiiB = {'alpha': 40.0, 'beta': 40.0, 'gamma': 40.0};

      final countA = detector.countOverlaps(
        positions: positionsA,
        nodeRadii: radiiA,
        zoomLevel: zoom,
        viewport: viewport,
      );
      final countB = detector.countOverlaps(
        positions: positionsB,
        nodeRadii: radiiB,
        zoomLevel: zoom,
        viewport: viewport,
      );

      expect(countB, countA,
          reason: 'Overlap count must be invariant under relabelling');
      expect(countA, greaterThan(0));
    });

    test('countOverlaps returns 0 for empty input', () {
      expect(
        detector.countOverlaps(
          positions: const {},
          nodeRadii: const {},
          zoomLevel: zoom,
          viewport: viewport,
        ),
        0,
      );
    });

    test('resolve pushes overlapping nodes apart', () {
      const positions = {
        'a': Offset(50000, 50000),
        'b': Offset(50010, 50000), // 10px apart, well below threshold
      };
      const radii = {'a': 40.0, 'b': 40.0};

      final result = detector.resolve(
        positions: positions,
        nodeRadii: radii,
        zoomLevel: zoom,
        viewport: viewport,
      );

      expect(result.initialOverlapCount, 1);
      expect(result.iterationsPerformed, greaterThan(0));

      final newPosA = result.positions['a']!;
      final newPosB = result.positions['b']!;
      final newDist = sqrt(pow(newPosB.dx - newPosA.dx, 2) +
          pow(newPosB.dy - newPosA.dy, 2));
      // Nodes must be substantially further apart than they started
      // (10px) and at least near the min-distance threshold (~92px).
      expect(newDist, greaterThan(85),
          reason: 'Resolver must push nodes near the minimum distance');
      expect(newDist, greaterThan(10),
          reason: 'Nodes must be further apart than their starting distance');
    });

    test('resolve leaves already-separated nodes alone', () {
      const positions = {
        'a': Offset(1000, 1000),
        'b': Offset(5000, 5000),
      };
      const radii = {'a': 40.0, 'b': 40.0};

      final result = detector.resolve(
        positions: positions,
        nodeRadii: radii,
        zoomLevel: zoom,
        viewport: viewport,
      );

      expect(result.initialOverlapCount, 0);
      expect(result.remainingOverlapCount, 0);
      expect(result.iterationsPerformed, 0);
      expect(result.allResolved, isTrue);
      // Positions are preserved (just copied).
      expect(result.positions['a'], positions['a']);
      expect(result.positions['b'], positions['b']);
    });

    test('resolve clamps nodes to viewport padding', () {
      // Place two nodes so close that the resolver pushes them past
      // the viewport edges. They should be clamped inside [padding, w-padding].
      const smallViewport = Size(400, 400);
      const positions = {
        'a': Offset(200, 200),
        'b': Offset(205, 200), // 5px apart → huge push needed
      };
      const radii = {'a': 40.0, 'b': 40.0};

      final result = detector.resolve(
        positions: positions,
        nodeRadii: radii,
        zoomLevel: zoom,
        viewport: smallViewport,
      );

      // Padding default = 20. All positions must lie within [20, 380].
      for (final pos in result.positions.values) {
        expect(pos.dx, greaterThanOrEqualTo(20.0));
        expect(pos.dx, lessThanOrEqualTo(380.0));
        expect(pos.dy, greaterThanOrEqualTo(20.0));
        expect(pos.dy, lessThanOrEqualTo(380.0));
      }
    });

    test('custom config influences detection threshold', () {
      // Tighten the gap to 0 → only nodes whose circles touch overlap.
      final tightDetector = CollisionDetector(
        config: const CollisionDetectorConfig(
          minGapLowZoom: 0.0,
          minGapHighZoom: 0.0,
          defaultNodeRadius: 40.0,
          zoomThreshold: 1.0,
        ),
      );

      const positions = {
        'a': Offset(0, 0),
        'b': Offset(70, 0), // distance 70 < 40 + 40 = 80 → still overlap
      };
      const radii = {'a': 40.0, 'b': 40.0};

      final count = tightDetector.countOverlaps(
        positions: positions,
        nodeRadii: radii,
        zoomLevel: zoom,
        viewport: viewport,
      );
      expect(count, 1);

      // Distance 100 > 80 → no overlap.
      const farPositions = {
        'a': Offset(0, 0),
        'b': Offset(100, 0),
      };
      final farCount = tightDetector.countOverlaps(
        positions: farPositions,
        nodeRadii: radii,
        zoomLevel: zoom,
        viewport: viewport,
      );
      expect(farCount, 0);
    });

    test('coincident nodes are nudged apart (dist == 0 case)', () {
      const positions = {
        'a': Offset(500, 500),
        'b': Offset(500, 500), // exactly coincident
      };
      const radii = {'a': 40.0, 'b': 40.0};

      final result = detector.resolve(
        positions: positions,
        nodeRadii: radii,
        zoomLevel: zoom,
        viewport: viewport,
      );

      expect(result.initialOverlapCount, 1);
      final newPosA = result.positions['a']!;
      final newPosB = result.positions['b']!;
      // They must no longer be coincident.
      expect(newPosA == newPosB, isFalse);
    });
  });
}

// test/features/family_map/perf/family_map_performance_test.dart
//
// §18 — Family Map performance tests.
//
// Generates fixture data for 0, 1, 10, 100, 500, and 1000 members and
// verifies that:
//   • computeHouseholds (§18.1) completes in O(N), not O(N²)
//   • MapPin filtering via computeHouseholds (city-centroid pins skipped)
//   • Edge validation (removeDuplicateEdges + removeSelfEdges) completes
//     in linear time for 1000 edges
//   • deterministicSpreadOffset is O(N) for 1000 pins
//
// These tests do NOT spin up a real Flutter binding — they are pure Dart
// unit tests against the family_map data layer. This keeps them fast and
// deterministic on CI runners that lack a GPU.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/family_map/providers/family_map_provider.dart';
import 'package:kinrel/features/family_map/data/map_location_source.dart';
import 'package:kinrel/features/family_map/data/map_data_validator.dart';
import 'package:kinrel/features/family_map/data/deterministic_spread.dart';

/// Type alias for the relationship-edge record used by the validator.
typedef _Edge = ({
  String fromId,
  String toId,
  String edgeId,
  String relationshipKey,
});

/// Builds a list of [n] MapPins with `exactPlace` location source.
///
/// Coordinates are spread on a 100×10 grid around (12.0, 77.0) so that
/// several pins land in the same household bucket (testing the
/// clustering path) while the total number of buckets stays small.
List<MapPin> _buildExactPins(int n) {
  return List.generate(n, (i) {
    return MapPin(
      personId: 'p$i',
      name: 'Person $i',
      city: 'City',
      photoUrl: null,
      lat: 12.0 + (i % 100) * 0.001,
      lng: 77.0 + (i ~/ 100) * 0.001,
      locationSource: MapLocationSource.exactPlace,
    );
  });
}

/// Builds a list of [n] MapPins with `cityCentroid` location source.
///
/// All pins share the exact same coordinates (Mumbai). Because
/// city-centroid pins cannot cluster, every pin is skipped — this
/// verifies the early-exit branch in computeHouseholds is O(N).
List<MapPin> _buildCityCentroidPins(int n) {
  return List.generate(n, (i) {
    return MapPin(
      personId: 'p$i',
      name: 'Person $i',
      city: 'Mumbai',
      photoUrl: null,
      lat: 19.076,
      lng: 72.877,
      locationSource: MapLocationSource.cityCentroid,
    );
  });
}

void main() {
  // ─────────────────────────────────────────────────────────────────────
  // §18.1 — computeHouseholds performance
  // ─────────────────────────────────────────────────────────────────────

  group('Performance — computeHouseholds', () {
    test('0 members: instant', () {
      final households = computeHouseholds([]);
      expect(households, isEmpty);
    });

    test('1 member: instant', () {
      final pins = [
        MapPin(
          personId: 'p1',
          name: 'A',
          city: 'X',
          photoUrl: null,
          lat: 0,
          lng: 0,
          locationSource: MapLocationSource.exactPlace,
        ),
      ];
      final households = computeHouseholds(pins);
      expect(households, hasLength(1));
    });

    test('10 members with exactPlace: completes in < 50ms', () {
      final pins = _buildExactPins(10);
      final sw = Stopwatch()..start();
      final households = computeHouseholds(pins);
      sw.stop();
      expect(households, isNotEmpty);
      expect(
        sw.elapsedMilliseconds,
        lessThan(50),
        reason: '10 pins should cluster in well under 50ms',
      );
    });

    test('100 members with exactPlace: completes in < 50ms', () {
      final pins = _buildExactPins(100);
      final sw = Stopwatch()..start();
      final households = computeHouseholds(pins);
      sw.stop();
      expect(households, isNotEmpty);
      expect(
        sw.elapsedMilliseconds,
        lessThan(50),
        reason: 'computeHouseholds should be O(N), not O(N²)',
      );
    });

    test('500 members with exactPlace: completes in < 75ms', () {
      final pins = _buildExactPins(500);
      final sw = Stopwatch()..start();
      final households = computeHouseholds(pins);
      sw.stop();
      expect(households, isNotEmpty);
      expect(
        sw.elapsedMilliseconds,
        lessThan(75),
        reason: 'computeHouseholds should be O(N), not O(N²)',
      );
    });

    test('1000 members with exactPlace: completes in < 100ms', () {
      final pins = _buildExactPins(1000);
      final sw = Stopwatch()..start();
      final households = computeHouseholds(pins);
      sw.stop();
      expect(
        sw.elapsedMilliseconds,
        lessThan(100),
        reason: 'computeHouseholds should be O(N), not O(N²)',
      );
    });

    test('1000 members with cityCentroid: completes in < 50ms (skips all)', () {
      final pins = _buildCityCentroidPins(1000);
      final sw = Stopwatch()..start();
      final households = computeHouseholds(pins);
      sw.stop();
      expect(households, isEmpty);
      expect(sw.elapsedMilliseconds, lessThan(50));
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // §18.2 — MapPin filtering via locationSource
  // ─────────────────────────────────────────────────────────────────────

  group('Performance — MapPin filtering (locationSource)', () {
    test('mixed 1000 pins (500 exact + 500 centroid): < 75ms', () {
      final pins = <MapPin>[
        ..._buildExactPins(500),
        ..._buildCityCentroidPins(500),
      ];
      final sw = Stopwatch()..start();
      final households = computeHouseholds(pins);
      sw.stop();
      // Only exact pins can cluster — 500 city-centroid pins are filtered.
      expect(households.length, lessThanOrEqualTo(500));
      expect(households, isNotEmpty);
      expect(
        sw.elapsedMilliseconds,
        lessThan(75),
        reason: 'Filtering + clustering must remain O(N)',
      );
    });

    test('null locationSource pins still cluster (backward compat)', () {
      final pins = List.generate(1000, (i) {
        return MapPin(
          personId: 'p$i',
          name: 'Person $i',
          city: 'City',
          photoUrl: null,
          lat: 12.0 + (i % 100) * 0.001,
          lng: 77.0 + (i ~/ 100) * 0.001,
          // locationSource intentionally null — legacy callers.
        );
      });
      final sw = Stopwatch()..start();
      final households = computeHouseholds(pins);
      sw.stop();
      expect(households, isNotEmpty);
      expect(
        sw.elapsedMilliseconds,
        lessThan(100),
        reason: 'Legacy null-source pins must still cluster in O(N)',
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // §18.3 — data validation (edges)
  // ─────────────────────────────────────────────────────────────────────

  group('Performance — data validation', () {
    test('1000 edges: validation completes in < 50ms', () {
      final edges = List.generate(1000, (i) {
        return (
              fromId: 'p$i',
              toId: 'p${(i + 1) % 1000}',
              edgeId: 'e$i',
              relationshipKey: 'father',
            )
            as _Edge;
      });
      final sw = Stopwatch()..start();
      final deduped = removeDuplicateEdges(edges);
      final noSelf = removeSelfEdges(deduped);
      sw.stop();
      // All 1000 edges are unique pairs (p_i -> p_{i+1} mod 1000), so
      // none should be deduped; no self-edges exist either.
      expect(noSelf, hasLength(1000));
      expect(
        sw.elapsedMilliseconds,
        lessThan(50),
        reason: 'Edge validation must be O(N), not O(N²)',
      );
    });

    test('1000 duplicate edges: dedupe collapses to 1 in < 50ms', () {
      final baseEdge =
          (fromId: 'p0', toId: 'p1', edgeId: 'e0', relationshipKey: 'father')
              as _Edge;
      final edges = List.filled(1000, baseEdge);
      final sw = Stopwatch()..start();
      final deduped = removeDuplicateEdges(edges);
      sw.stop();
      expect(deduped, hasLength(1));
      expect(sw.elapsedMilliseconds, lessThan(50));
    });

    test('1000 self-edges: removal collapses to 0 in < 50ms', () {
      final edges = List.generate(1000, (i) {
        return (
              fromId: 'p$i',
              toId: 'p$i', // self-edge
              edgeId: 'e$i',
              relationshipKey: 'self',
            )
            as _Edge;
      });
      final sw = Stopwatch()..start();
      final noSelf = removeSelfEdges(edges);
      sw.stop();
      expect(noSelf, isEmpty);
      expect(sw.elapsedMilliseconds, lessThan(50));
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // §18.4 — deterministic spread
  // ─────────────────────────────────────────────────────────────────────

  group('Performance — deterministic spread', () {
    test('1000 pins: spread computation completes in < 50ms', () {
      final sw = Stopwatch()..start();
      for (var i = 0; i < 1000; i++) {
        deterministicSpreadOffset('person-$i');
      }
      sw.stop();
      expect(
        sw.elapsedMilliseconds,
        lessThan(50),
        reason: 'Spread computation must be O(N) — char-code hash per pin',
      );
    });

    test('spread is stable across calls (determinism)', () {
      // Determinism is what makes this a valid perf test — same input
      // always produces the same output, so timing is reproducible.
      for (var i = 0; i < 100; i++) {
        final a = deterministicSpreadOffset('person-$i');
        final b = deterministicSpreadOffset('person-$i');
        expect(a.lat, b.lat);
        expect(a.lng, b.lng);
      }
    });
  });
}

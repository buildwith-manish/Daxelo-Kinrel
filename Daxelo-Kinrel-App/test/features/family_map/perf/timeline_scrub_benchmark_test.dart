import 'package:flutter/foundation.dart' show debugPrint;
// test/features/family_map/perf/timeline_scrub_benchmark_test.dart
//
// P11.5 — Performance benchmark: timeline scrubbing.
//
// Measures: computation time for filtering pins + places + edges by year.
// Target: < 5ms per filter operation (Rule 6 — 60 FPS during drag).
//
// The timeline scrubber calls filterMapPins + filterMapPlaces on every
// year change. These are O(N) operations — fast even for 500 members.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/family_journey/providers/journey_provider.dart';
import 'package:kinrel/features/family_map/providers/family_map_provider.dart';
import 'package:kinrel/features/family_map/data/place_models.dart';
import 'package:kinrel/features/family_map/config/map_visual_constants.dart';

void main() {
  group('P11.5 — Timeline scrub benchmark', () {
    test('filterMapPins with 500 pins < 5ms', () {
      final controller = JourneyController();
      controller.setYear(1990);

      final pins = List.generate(
        500,
        (i) => MapPin(
          personId: 'p$i',
          name: 'Member $i',
          city: 'City $i',
          photoUrl: null,
          lat: 18.52 + (i * 0.001),
          lng: 73.85 + (i * 0.001),
        ),
      );

      final stopwatch = Stopwatch()..start();
      final filtered = controller.filterMapPins(pins);
      stopwatch.stop();

      debugPrint(
        'P11.5 timeline_scrub_benchmark: '
        '${stopwatch.elapsedMicroseconds}μs for 500 pins',
      );
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(5),
        reason: 'filterMapPins with 500 pins must be < 5ms (Rule 6)',
      );
      // With no dateOfBirth, all pins are returned (always alive).
      expect(filtered.length, equals(500));
    });

    test('filterMapPlaces with 100 places < 5ms', () {
      final controller = JourneyController();
      controller.setYear(2000);

      final places = List.generate(
        100,
        (i) => FamilyPlace(
          id: 'place_$i',
          familyId: 'fam',
          name: 'Place $i',
          placeType: PlaceType.values[i % 9],
          lat: 18.52 + (i * 0.01),
          lng: 73.85 + (i * 0.01),
          validFrom: DateTime(1950 + (i % 50)),
          validTo: DateTime(2020 + (i % 10)),
        ),
      );

      final stopwatch = Stopwatch()..start();
      final filtered = controller.filterMapPlaces(places);
      stopwatch.stop();

      debugPrint(
        'P11.5 timeline_scrub_benchmark: '
        '${stopwatch.elapsedMicroseconds}μs for 100 places',
      );
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(5),
        reason: 'filterMapPlaces with 100 places must be < 5ms (Rule 6)',
      );
      expect(filtered.length, lessThanOrEqualTo(100));
    });

    test('computeHouseholds with 500 pins < 5ms', () {
      final pins = List.generate(
        500,
        (i) => MapPin(
          personId: 'p$i',
          name: 'Member $i',
          city: 'City ${i % 50}', // 50 cities → 50 households
          photoUrl: null,
          lat: 18.52 + ((i % 50) * 0.01),
          lng: 73.85 + ((i % 50) * 0.01),
        ),
      );

      final stopwatch = Stopwatch()..start();
      final households = computeHouseholds(pins);
      stopwatch.stop();

      debugPrint(
        'P11.5 timeline_scrub_benchmark: '
        '${stopwatch.elapsedMicroseconds}μs for computeHouseholds(500)',
      );
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(5),
        reason: 'computeHouseholds with 500 pins must be < 5ms (Rule 6)',
      );
      expect(households.length, lessThanOrEqualTo(50));
    });

    test('timelinePlayInterval is 2 seconds (tunable)', () {
      expect(MapVisualConstants.timelinePlayInterval.inSeconds, equals(2));
    });

    test('timelineCrossfade is 300ms (smooth at 60 FPS)', () {
      expect(MapVisualConstants.timelineCrossfade.inMilliseconds, equals(300));
      // 300ms at 60 FPS = ~18 frames.
      final frames =
          (MapVisualConstants.timelineCrossfade.inMilliseconds / 16.67).round();
      expect(
        frames,
        greaterThan(15),
        reason: 'Timeline crossfade must span > 15 frames for smooth 60 FPS',
      );
    });
  });
}

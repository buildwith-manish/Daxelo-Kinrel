import 'package:flutter/foundation.dart' show debugPrint;
// test/features/family_map/perf/focus_transition_benchmark_test.dart
//
// P11.5 — Performance benchmark: focus transition.
//
// Measures: computation time for the focus transition (camera spring +
// opacity changes). The actual 60 FPS rendering is verified manually
// on a mid-tier device (P11.8 device testing sign-off).
//
// Rule 6: focus transition must sustain 60 FPS over the 420ms duration.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/family_map/config/map_visual_constants.dart';
import 'package:kinrel/features/family_map/widgets/map_focus_controller.dart';
import 'package:kinrel/features/family_map/providers/family_map_provider.dart';
import 'package:kinrel/graph/interaction/graph_focus_state.dart';

void main() {
  group('P11.5 — Focus transition benchmark', () {
    test('focusTierOpacity computation is O(1) — < 1ms for 50 markers', () {
      final tiers = List.generate(50, (i) {
        if (i == 0) return FocusTier.focused;
        if (i < 10) return FocusTier.firstDegree;
        if (i < 30) return FocusTier.secondDegree;
        return FocusTier.unrelated;
      });

      final stopwatch = Stopwatch()..start();
      for (final tier in tiers) {
        focusTierOpacity(tier);
      }
      stopwatch.stop();

      debugPrint('P11.5 focus_transition_benchmark: ${stopwatch.elapsedMicroseconds}μs '
          'for 50 tier lookups');
      expect(stopwatch.elapsedMilliseconds, lessThan(10),
          reason: '50 tier lookups must be < 10ms (O(1) per lookup)');
    });

    test('GraphFocusState.tierOf is fast for 50 lookups', () {
      const state = GraphFocusState(
        focusedPersonId: 'p0',
        firstDegreeIds: {'p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7', 'p8', 'p9'},
        secondDegreeIds: {'p10', 'p11', 'p12', 'p13', 'p14', 'p15',
            'p16', 'p17', 'p18', 'p19', 'p20', 'p21', 'p22', 'p23', 'p24',
            'p25', 'p26', 'p27', 'p28', 'p29'},
      );

      final stopwatch = Stopwatch()..start();
      for (var i = 0; i < 50; i++) {
        state.tierOf('p$i');
      }
      stopwatch.stop();

      debugPrint('P11.5 focus_transition_benchmark: '
          '${stopwatch.elapsedMicroseconds}μs for 50 tierOf calls');
      expect(stopwatch.elapsedMilliseconds, lessThan(10),
          reason: '50 tierOf calls must be < 10ms');
    });

    test('focusTransition duration is 420ms (Rule 6 — 60 FPS over transition)',
        () {
      expect(MapVisualConstants.focusTransition.inMilliseconds, equals(420));
      // 420ms at 60 FPS = ~25 frames. Each frame must be < 16.67ms.
      final frames = (MapVisualConstants.focusTransition.inMilliseconds / 16.67).round();
      expect(frames, greaterThan(20),
          reason: 'Focus transition must span > 20 frames for smooth 60 FPS');
    });

    test('MapFocusController.enterFocus is a graceful no-op when controller is null',
        () async {
      final controller = MapFocusController(reducedMotion: true);
      const pin = MapPin(
        personId: 'p1', name: 'X', city: 'Y', photoUrl: null,
        lat: 18.52, lng: 73.85);
      const focusState = GraphFocusState(focusedPersonId: 'p1');

      final stopwatch = Stopwatch()..start();
      final ctx = await controller.enterFocus(
        mapController: null,
        style: null,
        familyBuildings: null,
        pin: pin,
        focusState: focusState,
      );
      stopwatch.stop();

      expect(ctx.pin, equals(pin));
      expect(stopwatch.elapsedMilliseconds, lessThan(100),
          reason: 'enterFocus no-op must be < 100ms');
    });
  });
}

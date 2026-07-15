// test/features/family_journey/journey_provider_test.dart
//
// P7.3 — Family Journey Replay tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/family_journey/providers/journey_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P7.3 — Journey provider', () {
    test('default state has current year', () {
      final controller = JourneyController();
      expect(controller.state.selectedYear, equals(DateTime.now().year));
      expect(controller.state.isPlaying, isFalse);
      controller.dispose();
    });

    test('setYear clamps to range', () {
      final controller = JourneyController();
      controller.setYearRange(1900, 2026);
      controller.setYear(1850);
      expect(controller.state.selectedYear, equals(1900));
      controller.setYear(2050);
      expect(controller.state.selectedYear, equals(2026));
      controller.dispose();
    });

    test('play/pause toggles isPlaying', () {
      final controller = JourneyController();
      controller.play();
      expect(controller.state.isPlaying, isTrue);
      controller.pause();
      expect(controller.state.isPlaying, isFalse);
      controller.dispose();
    });

    test('playback speed is 0.5 years/sec (1 year per 2 seconds)', () {
      const state = JourneyState();
      expect(state.playbackSpeedYearsPerSecond, equals(0.5));
    });
  });

  group('P7.3 — wasAliveAt', () {
    test('null dateOfBirth returns true (assume alive)', () {
      expect(wasAliveAt(year: 1985, dateOfBirth: null), isTrue);
    });

    test('person born after year returns false', () {
      expect(
        wasAliveAt(year: 1985, dateOfBirth: DateTime(1990)),
        isFalse,
      );
    });

    test('person born before year returns true', () {
      expect(
        wasAliveAt(year: 1985, dateOfBirth: DateTime(1950)),
        isTrue,
      );
    });

    test('person who died before year returns false', () {
      expect(
        wasAliveAt(
          year: 1985,
          dateOfBirth: DateTime(1950),
          dateOfDeath: DateTime(1980),
        ),
        isFalse,
      );
    });

    test('person who died after year returns true', () {
      expect(
        wasAliveAt(
          year: 1985,
          dateOfBirth: DateTime(1950),
          dateOfDeath: DateTime(1990),
        ),
        isTrue,
      );
    });

    test('person born in the same year returns true', () {
      expect(
        wasAliveAt(year: 1985, dateOfBirth: DateTime(1985, 6, 15)),
        isTrue,
      );
    });
  });
}

// test/features/grandparent_mode/grandparent_mode_test.dart
//
// P12.6 Batch 4 — Grandparent Mode accessibility profile tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/grandparent_mode/grandparent_mode_profile.dart';

void main() {
  group('P12.6 Grandparent Mode — presentation profile', () {
    test('initial state is disabled', () {
      // The profile starts disabled — users opt in via profile settings.
      const state = GrandparentModeState();
      expect(state.enabled, isFalse);
    });

    test('enable() sets enabled to true', () {
      final notifier = GrandparentModeNotifier();
      notifier.enable();
      expect(notifier.state.enabled, isTrue);
    });

    test('disable() sets enabled to false', () {
      final notifier = GrandparentModeNotifier();
      notifier.enable();
      notifier.disable();
      expect(notifier.state.enabled, isFalse);
    });

    test('toggle() flips the state', () {
      final notifier = GrandparentModeNotifier();
      expect(notifier.state.enabled, isFalse);
      notifier.toggle();
      expect(notifier.state.enabled, isTrue);
      notifier.toggle();
      expect(notifier.state.enabled, isFalse);
    });

    test('text scale factor is 1.3 (30% larger)', () {
      expect(GrandparentModeState.textScaleFactor, equals(1.3));
    });

    test('always pairs icons with text (no icon-only actions)', () {
      expect(GrandparentModeState.alwaysPairIconWithText, isTrue);
    });

    test('limits navigation options to 5', () {
      expect(GrandparentModeState.maxNavOptions, equals(5));
    });

    test('minimum tap target is 48dp (accessibility standard)', () {
      expect(GrandparentModeState.minTapTargetSize, equals(48.0));
    });

    test('reduces animations (reuses existing reduced-motion system)', () {
      expect(GrandparentModeState.reduceAnimations, isTrue);
    });

    test('copyWith preserves enabled when not specified', () {
      const state = GrandparentModeState(enabled: true);
      final copied = state.copyWith();
      expect(copied.enabled, isTrue);
    });
  });
}

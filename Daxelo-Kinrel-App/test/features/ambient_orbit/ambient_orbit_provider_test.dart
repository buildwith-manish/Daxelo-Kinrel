// test/features/ambient_orbit/ambient_orbit_provider_test.dart
//
// P9.2h — Ambient idle orbit tests.
// Verifies reduced-motion is honoured (no animation under it).

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/ambient_orbit/providers/ambient_orbit_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P9.2h — AmbientOrbitNotifier', () {
    test('inactive by default', () {
      final n = AmbientOrbitNotifier();
      expect(n.state.isActive, isFalse);
      expect(n.state.rendersMotion, isFalse);
      expect(n.state.phase, 0.0);
      n.dispose();
    });

    test('activate turns the overlay on and records time', () {
      final n = AmbientOrbitNotifier();
      n.activate();
      expect(n.state.isActive, isTrue);
      expect(n.state.lastActivatedAt, isNotNull);
      expect(n.state.rendersMotion, isTrue);
      n.dispose();
    });

    test('deactivate turns it off', () {
      final n = AmbientOrbitNotifier();
      n.activate();
      n.deactivate();
      expect(n.state.isActive, isFalse);
      expect(n.state.rendersMotion, isFalse);
      n.dispose();
    });

    test('toggle flips state', () {
      final n = AmbientOrbitNotifier();
      n.toggle();
      expect(n.state.isActive, isTrue);
      n.toggle();
      expect(n.state.isActive, isFalse);
      n.dispose();
    });

    test('reduced motion freezes the orbit (rendersMotion false)', () {
      final n = AmbientOrbitNotifier();
      n.activate();
      n.setReducedMotion(true);
      expect(n.state.reducedMotion, isTrue);
      expect(n.state.rendersMotion, isFalse);
      expect(n.state.phase, 0.0);
      n.dispose();
    });

    test('advance is ignored under reduced motion', () {
      final n = AmbientOrbitNotifier();
      n.activate();
      n.setReducedMotion(true);
      n.advance(0.25);
      expect(n.state.phase, 0.0);
      n.dispose();
    });

    test('advance wraps within [0, 1)', () {
      final n = AmbientOrbitNotifier();
      n.activate();
      n.advance(0.9);
      expect(n.state.phase, closeTo(0.9, 1e-9));
      n.advance(0.2);
      expect(n.state.phase, lessThan(1.0));
      expect(n.state.phase, greaterThanOrEqualTo(0.0));
      n.dispose();
    });

    test('advance is ignored when inactive', () {
      final n = AmbientOrbitNotifier();
      n.advance(0.5);
      expect(n.state.phase, 0.0);
      n.dispose();
    });

    test('reset returns to default', () {
      final n = AmbientOrbitNotifier();
      n.activate();
      n.advance(0.4);
      n.reset();
      expect(n.state.isActive, isFalse);
      expect(n.state.phase, 0.0);
      n.dispose();
    });
  });
}

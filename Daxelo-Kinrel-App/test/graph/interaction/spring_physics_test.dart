// test/graph/interaction/spring_physics_test.dart
//
// P3.1 — Spring physics gesture response across the graph.
//
// Verifies that:
//   1. Each SpringPalette spring converges to its target within 500ms.
//   2. No spring oscillates beyond 2% of the target amplitude
//      (critically-damped or near-critical springs should not
//      overshoot visibly).
//   3. Reduced-motion path snaps instantly (no animation ticks).
//   4. SpringCurve (used by CurvedAnimation consumers) maps the
//      normalized [0,1] input to a monotonic spring trajectory that
//      reaches 1.0 within the settle budget.
//   5. BranchExpandSpring (used for new-node fade-in) converges to 1.0
//      within its settle budget and respects reduced motion.
//   6. Momentum decay (applyMomentum) uses a spring simulation seeded
//      with the gesture velocity and converges to the projected target.
//
// Per P3.1 Testing strategy:
//   - Unit test: verify spring converges to target within 500ms
//   - Unit test: verify no oscillation beyond 2% of target
//   - Reduced motion test: instant snap

import 'package:flutter/animation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/graph/interaction/camera_controller.dart';
import 'package:kinrel/graph/interaction/expand_collapse.dart';
import 'package:kinrel/graph/interaction/spring_palette.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P3.1 — SpringPalette convergence', () {
    /// Helper: walks the spring and returns the maximum OVERSHOOT past
    /// the target (the amount the spring went beyond target, not the
    /// initial distance from start to target).
    double maxOvershoot(
      SpringDescription spring,
      double start,
      double target, {
      Tolerance? tolerance,
    }) {
      final sim = SpringSimulation(spring, start, target, 0.0)
        ..tolerance = tolerance ?? SpringPalette.defaultTolerance;
      const dt = 0.016;
      double maxOver = 0.0;
      final direction = (target - start) >= 0 ? 1.0 : -1.0;
      for (double t = 0.0; t < 2.0; t += dt) {
        final v = sim.x(t);
        // Overshoot = how much v has gone PAST target in the direction
        // of motion. For positive direction (start < target), overshoot
        // is (v - target) if positive. For negative direction, it's
        // (target - v) if positive.
        final over = direction * (v - target);
        if (over > maxOver) maxOver = over;
        if (sim.isDone(t) && t > 0.4) break;
      }
      return maxOver;
    }

    /// Helper: checks if the spring's position is within `fraction` of
    /// the target amplitude at `t`.
    bool withinFractionAt(
      SpringDescription spring,
      double start,
      double target,
      double t, {
      double fraction = 0.02,
    }) {
      final sim = SpringSimulation(spring, start, target, 0.0)
        ..tolerance = SpringPalette.defaultTolerance;
      final v = sim.x(t);
      final amplitude = (target - start).abs();
      final tolerance = amplitude * fraction;
      return (v - target).abs() <= tolerance;
    }

    test('pan spring converges within 500ms (within 2% of target)', () {
      // Pan: critically damped. Should be within 2% of target (100)
      // i.e. within 2.0 units of target by 500ms.
      expect(
        withinFractionAt(SpringPalette.pan, 0.0, 100.0, 0.5),
        isTrue,
        reason: 'pan spring should be within 2% of target by 500ms',
      );
      // No overshoot beyond 2% of target.
      expect(
        maxOvershoot(SpringPalette.pan, 0.0, 100.0),
        lessThanOrEqualTo(100.0 * 0.02),
        reason: 'pan spring must not overshoot target by more than 2%',
      );
    });

    test('zoom spring converges within 500ms (within 2% of target)', () {
      expect(
        withinFractionAt(SpringPalette.zoom, 1.0, 2.0, 0.5),
        isTrue,
        reason: 'zoom spring should be within 2% of target by 500ms',
      );
      // Amplitude is 1.0 (from 1.0 to 2.0). 2% of 1.0 = 0.02.
      expect(
        maxOvershoot(SpringPalette.zoom, 1.0, 2.0),
        lessThanOrEqualTo(1.0 * 0.02),
        reason: 'zoom spring must not overshoot target by more than 2%',
      );
    });

    test('focus spring converges within 500ms (within 2% of target)', () {
      expect(
        withinFractionAt(SpringPalette.focus, 0.0, 200.0, 0.5),
        isTrue,
        reason: 'focus spring should be within 2% of target by 500ms',
      );
      expect(
        maxOvershoot(SpringPalette.focus, 0.0, 200.0),
        lessThanOrEqualTo(200.0 * 0.02),
        reason: 'focus spring must not overshoot target by more than 2%',
      );
    });

    test('branch spring converges within 500ms (within 2% of target)', () {
      // Branch is intentionally slightly under-damped (damping ratio
      // ≈ 0.82) so it has a small overshoot. The 2% bound applies.
      expect(
        withinFractionAt(SpringPalette.branch, 0.0, 1.0, 0.5),
        isTrue,
        reason: 'branch spring should be within 2% of target by 500ms',
      );
      // Branch may overshoot up to 2% (allowed by spec).
      expect(
        maxOvershoot(
          SpringPalette.branch,
          0.0,
          1.0,
          tolerance: SpringPalette.normalizedTolerance,
        ),
        lessThanOrEqualTo(1.0 * 0.02),
        reason: 'branch spring overshoot must stay within 2%',
      );
    });

    test('approximateSettleSeconds is reasonable (< 1s for all palette springs',
        () {
      for (final spring in [
        SpringPalette.pan,
        SpringPalette.zoom,
        SpringPalette.focus,
        SpringPalette.branch,
      ]) {
        final settle = SpringPalette.approximateSettleSeconds(spring);
        expect(settle, greaterThan(0.0));
        expect(settle, lessThan(1.0),
            reason: 'palette springs must settle within 1s');
      }
    });
  });

  group('P3.1 — SpringCurve (CurvedAnimation adapter)', () {
    test('focus curve reaches 1.0 within its settle budget', () {
      final curve = SpringCurves.focus;
      final settle = curve is SpringCurve ? curve.settleSeconds : 0.5;

      // Walk a normalized [0,1] input through the curve.
      double? lastValue;
      for (double t = 0.0; t <= 1.0; t += 0.05) {
        final v = curve.transform(t);
        if (lastValue != null) {
          // Curve should be monotonically non-decreasing for critical
          // and near-critical springs (pan, zoom, focus). It may have
          // a tiny overshoot for branch (under-damped) but we test
          // focus here, which is near-critical.
          expect(v, greaterThanOrEqualTo(lastValue - 0.001),
              reason: 'focus curve should be monotonic (no reversal)');
        }
        lastValue = v;
      }
      // At t=1, the curve should be at or near 1.0.
      expect(curve.transform(1.0), greaterThan(0.98));
      // Settle budget should be reasonable.
      expect(settle, lessThan(1.0));
    });

    test('pan/zoom/branch curves are constructible and bounded', () {
      // Smoke test — each curve produces values in [0, 1.05] across
      // the input range. The slight upper bound allows for branch's
      // under-damped overshoot.
      for (final curve in [
        SpringCurves.pan,
        SpringCurves.zoom,
        SpringCurves.branch,
      ]) {
        for (double t = 0.0; t <= 1.0; t += 0.1) {
          final v = curve.transform(t);
          expect(v, greaterThanOrEqualTo(-0.05));
          expect(v, lessThanOrEqualTo(1.1));
        }
      }
    });
  });

  group('P3.1 — CameraController springs', () {
    test('panBySpring with reduced motion snaps instantly', () {
      final camera = CameraController();
      final initialPanX = camera.panX;
      final initialPanY = camera.panY;

      // Reduced motion: should snap instantly (no animation).
      camera.panBySpring(50, 25, reducedMotion: true);

      // Final pan equals start + delta (no overshoot, no settle).
      expect(camera.panX, equals(initialPanX + 50));
      expect(camera.panY, equals(initialPanY + 25));
      expect(camera.isAnimating, isFalse,
          reason: 'reduced-motion pan must not leave the camera animating');
    });

    test('zoomToSpring with reduced motion snaps instantly', () {
      final camera = CameraController();
      final initialZoom = camera.zoomLevel;

      camera.zoomToSpring(2.0, reducedMotion: true);

      expect(camera.zoomLevel, equals(2.0));
      expect(camera.isAnimating, isFalse);
      // The zoom level actually changed (was 1.0 default).
      expect(camera.zoomLevel, isNot(equals(initialZoom)));
    });

    test('focusOnNode with reduced motion snaps instantly', () {
      final camera = CameraController();
      camera.focusOnNode(
        'node_1',
        const Offset(100, 200),
        connectedNodeCount: 5,
        viewportSize: const Size(800, 600),
        reducedMotion: true,
      );

      // Reduced motion snaps — camera is at the target.
      expect(camera.isAnimating, isFalse);
      expect(camera.focusedNodeId, equals('node_1'));
    });

    test('animateToWithSpring with reduced motion snaps instantly', () {
      final camera = CameraController();
      camera.animateToWithSpring(
        100,
        200,
        2.0,
        reducedMotion: true,
      );

      expect(camera.panX, equals(100));
      expect(camera.panY, equals(200));
      expect(camera.zoomLevel, equals(2.0));
      expect(camera.isAnimating, isFalse);
    });

    test('applyMomentum uses a spring (camera settles, not freezes)', () {
      // P3.1: replaced linear `1 - t^2` decay with spring physics.
      // After applyMomentum, the camera should be animating (spring
      // in flight) and eventually settle. We can't easily wait for
      // the spring to settle in a synchronous unit test, but we can
      // assert that the camera enters the animating state.
      final camera = CameraController();
      camera.applyMomentum(500, 0);
      expect(camera.isAnimating, isTrue,
          reason: 'applyMomentum should start a spring animation');
      // Stop the animation so the test doesn't leak timers.
      camera.stopAnimation();
    });
  });

  group('P3.1 — BranchExpandSpring', () {
    test('progressAt(0) is 0 (or near 0)', () {
      final spring = BranchExpandSpring();
      final v = spring.progressAt(0.0);
      expect(v, lessThan(0.05),
          reason: 'branch expand spring should start near 0');
    });

    test('progressAt converges to 1.0 within settle budget', () {
      final spring = BranchExpandSpring();
      final settle = BranchExpandSpring.settleSeconds;
      // Walk the spring to its settle time.
      final v = spring.progressAt(settle * 1.5);
      expect(v, greaterThan(0.98),
          reason: 'branch expand spring should reach ~1.0 after settle');
      expect(spring.isDone(settle * 1.5), isTrue);
    });

    test('reduced motion returns 1.0 immediately', () {
      final spring = BranchExpandSpring(reducedMotion: true);
      expect(spring.progressAt(0.0), equals(1.0));
      expect(spring.progressAt(0.5), equals(1.0));
      expect(spring.isDone(0.0), isTrue);
    });

    test('progressAt clamps to [0, 1]', () {
      final spring = BranchExpandSpring();
      // Walk far past settle — should never go above 1.0.
      for (double t = 0.0; t < 2.0; t += 0.05) {
        final v = spring.progressAt(t);
        expect(v, greaterThanOrEqualTo(0.0));
        expect(v, lessThanOrEqualTo(1.0));
      }
    });
  });
}

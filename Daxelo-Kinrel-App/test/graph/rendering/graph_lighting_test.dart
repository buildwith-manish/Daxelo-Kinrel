// test/graph/rendering/graph_lighting_test.dart
//
// Focused tests for the GraphLighting contract (PART 2 of the FINAL
// 10/10 COMPLETION PASS). Verifies the contract values are stable and
// the helper functions clamp correctly — these are the values every
// painter in the graph relies on for visual consistency.

import 'package:kinrel/graph/rendering/graph_lighting.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GraphLighting — global directions (PART 2)', () {
    test('light source is top-left', () {
      expect(GraphLighting.lightSource.x, lessThan(0));
      expect(GraphLighting.lightSource.y, lessThan(0));
    });

    test('shadow offset is down-right (positive dx, positive dy)', () {
      expect(GraphLighting.shadowOffset.x, greaterThan(0));
      expect(GraphLighting.shadowOffset.y, greaterThan(0));
    });

    test('highlight offset is up-left (negative dx, negative dy)', () {
      expect(GraphLighting.highlightOffset.x, lessThan(0));
      expect(GraphLighting.highlightOffset.y, lessThan(0));
    });
  });

  group('GraphLighting — sigma + alpha tiers', () {
    test('full shadow sigma is greater than chip shadow sigma', () {
      expect(GraphLighting.fullShadowSigma,
          greaterThan(GraphLighting.chipShadowSigma));
    });

    test('full ridge alpha is greater than chip ridge alpha', () {
      expect(GraphLighting.fullRidgeAlpha,
          greaterThan(GraphLighting.chipRidgeAlpha));
    });

    test('selected shadow alpha is stronger than normal shadow alpha', () {
      expect(GraphLighting.selectedShadowAlpha,
          greaterThan(GraphLighting.shadowAlpha));
    });

    test('selected aura alpha is in the 0.12–0.20 range (PART 7)', () {
      expect(GraphLighting.selectedAuraAlpha,
          inInclusiveRange(0.12, 0.20));
    });
  });

  group('GraphLighting — sweep contract (PART 8)', () {
    test('sweep duration is 600–700 ms', () {
      expect(GraphLighting.sweepDurationMs, inInclusiveRange(600, 700));
    });

    test('sweep segment fraction is 4–8 %', () {
      expect(GraphLighting.sweepSegmentFraction,
          inInclusiveRange(0.04, 0.08));
    });
  });

  group('GraphLighting — helper functions', () {
    test('clampBodyWidth clamps to [2.2, 4.5]', () {
      expect(GraphLighting.clampBodyWidth(1.0), 2.2);
      expect(GraphLighting.clampBodyWidth(2.0), 2.2);
      expect(GraphLighting.clampBodyWidth(3.0), 3.0);
      expect(GraphLighting.clampBodyWidth(5.0), 4.5);
      expect(GraphLighting.clampBodyWidth(10.0), 4.5);
    });

    test('beadRadiusFor clamps to [3.8, 5.8]', () {
      // Below min → clamped to 3.8.
      expect(GraphLighting.beadRadiusFor(1.0), greaterThanOrEqualTo(3.8));
      // Above max → clamped to 5.8.
      expect(GraphLighting.beadRadiusFor(10.0), lessThanOrEqualTo(5.8));
      // In-range → multiplier applies.
      expect(GraphLighting.beadRadiusFor(3.0),
          closeTo(3.0 * 1.45, 0.01));
    });

    test('heartSizeFor clamps to [11.0, 16.0]', () {
      expect(GraphLighting.heartSizeFor(1.0), greaterThanOrEqualTo(11.0));
      expect(GraphLighting.heartSizeFor(10.0), lessThanOrEqualTo(16.0));
      // In-range → multiplier applies.
      expect(GraphLighting.heartSizeFor(3.0),
          closeTo(3.0 * 4.2, 0.01));
    });

    test('ridgeColor lerps towards white', () {
      const base = Color(0xFF3B82F6); // parent blue
      final ridge = GraphLighting.ridgeColor(base, t: 0.5);
      // Should be lighter than the base.
      expect(ridge.red, greaterThan(base.red));
      expect(ridge.green, greaterThan(base.green));
      expect(ridge.blue, greaterThan(base.blue));
    });

    test('ridgeColor with t=0 returns the base color', () {
      const base = Color(0xFF3B82F6);
      final ridge = GraphLighting.ridgeColor(base, t: 0.0);
      expect(ridge, base);
    });

    test('ridgeColor with t=1 returns white', () {
      const base = Color(0xFF3B82F6);
      final ridge = GraphLighting.ridgeColor(base, t: 1.0);
      expect(ridge, Colors.white);
    });
  });
}

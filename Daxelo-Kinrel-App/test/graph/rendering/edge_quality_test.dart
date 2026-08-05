// test/graph/rendering/edge_quality_test.dart
//
// Focused tests for the EdgeQuality enum (PART 10 of the FINAL 10/10
// COMPLETION PASS). Verifies the LOD→quality mapping and the
// per-tier performance guardrails (no blur at DOT, no sweep at DOT,
// no FULL premium midpoint at DOT).
//
// v105: allowsMidpoint now means "allows the FULL premium midpoint
// passes (pseudo-3D bead / heart with glow)". The painter ALWAYS
// paints a midpoint at every tier (simplified at DOT), so this
// predicate no longer gates visibility — see engine_edge_painter.dart.

import 'package:kinrel/graph/rendering/edge_quality.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EdgeQuality — allowsBlur (PART 10, PART 22)', () {
    test('full allows blur', () {
      expect(EdgeQuality.full.allowsBlur, isTrue);
    });
    test('chip allows blur (conservative)', () {
      expect(EdgeQuality.chip.allowsBlur, isTrue);
    });
    test('dot does NOT allow blur', () {
      expect(EdgeQuality.dot.allowsBlur, isFalse);
    });
  });

  group('EdgeQuality — allowsRidge', () {
    test('full allows ridge', () {
      expect(EdgeQuality.full.allowsRidge, isTrue);
    });
    test('chip allows ridge (reduced alpha)', () {
      expect(EdgeQuality.chip.allowsRidge, isTrue);
    });
    test('dot does NOT allow ridge', () {
      expect(EdgeQuality.dot.allowsRidge, isFalse);
    });
  });

  group('EdgeQuality — allowsMidpoint (FULL premium passes only, v105)', () {
    test('full allows the full premium midpoint', () {
      expect(EdgeQuality.full.allowsMidpoint, isTrue);
    });
    test('chip allows the full premium midpoint (smaller)', () {
      expect(EdgeQuality.chip.allowsMidpoint, isTrue);
    });
    test('dot does NOT allow the full premium midpoint (simplified only)', () {
      // v105: The painter still paints a SIMPLIFIED midpoint at DOT
      // LOD (a single filled circle) — this predicate only reports
      // whether the FULL pseudo-3D passes are appropriate.
      expect(EdgeQuality.dot.allowsMidpoint, isFalse);
    });
  });

  group('EdgeQuality — allowsSweep (PART 8)', () {
    test('full allows sweep', () {
      expect(EdgeQuality.full.allowsSweep, isTrue);
    });
    test('chip does NOT allow sweep (perf guard)', () {
      expect(EdgeQuality.chip.allowsSweep, isFalse);
    });
    test('dot does NOT allow sweep', () {
      expect(EdgeQuality.dot.allowsSweep, isFalse);
    });
  });

  group('EdgeQuality — shadowSigma', () {
    test('full sigma > 0', () {
      expect(EdgeQuality.full.shadowSigma, greaterThan(0));
    });
    test('chip sigma > 0 but less than full', () {
      expect(EdgeQuality.chip.shadowSigma, greaterThan(0));
      expect(EdgeQuality.chip.shadowSigma,
          lessThan(EdgeQuality.full.shadowSigma));
    });
    test('dot sigma is 0 (no blur)', () {
      expect(EdgeQuality.dot.shadowSigma, 0.0);
    });
  });

  group('EdgeQuality — ridgeAlpha', () {
    test('full alpha > 0', () {
      expect(EdgeQuality.full.ridgeAlpha, greaterThan(0));
    });
    test('chip alpha > 0 but less than full', () {
      expect(EdgeQuality.chip.ridgeAlpha, greaterThan(0));
      expect(EdgeQuality.chip.ridgeAlpha,
          lessThan(EdgeQuality.full.ridgeAlpha));
    });
    test('dot alpha is 0 (no ridge)', () {
      expect(EdgeQuality.dot.ridgeAlpha, 0.0);
    });
  });
}

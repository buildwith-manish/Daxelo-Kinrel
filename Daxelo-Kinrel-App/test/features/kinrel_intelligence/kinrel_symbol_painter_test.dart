// test/features/kinrel_intelligence/kinrel_symbol_painter_test.dart
//
// Phase 18 — Kinrel symbol painter tests.
//
// Verifies the painter renders without throwing for edge-case parameter
// combinations: 0 members (still produces a valid symbol), 1 member,
// and very large family parameters. We can't pixel-test a CustomPainter
// directly without a canvas, but we CAN instantiate it and call paint()
// on a stub canvas to ensure no math errors throw.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kinrel/features/kinrel_intelligence/data/kinrel_model.dart';
import 'package:kinrel/features/kinrel_intelligence/widgets/kinrel_symbol_painter.dart';

/// A no-op canvas that records nothing — used purely to drive paint()
/// without needing a real rendering surface. Painters don't care what
/// the canvas does with their draw calls, only that the calls succeed.
class _NullCanvas implements Canvas {
  @override
  dynamic noSuchMethod(Invocation invocation) {}
}

void main() {
  KinrelSymbolParameters params({
    int ringCount = 2,
    int spokeCount = 4,
    KinrelInnerPattern pattern = KinrelInnerPattern.lotus,
    double outerPct = 0.85,
    int complexity = 3,
    String primary = '#C8853A',
    String secondary = '#6B3FA0',
    String accent = '#2D8A4E',
    int pulseMs = 3000,
  }) =>
      KinrelSymbolParameters(
        ringCount: ringCount,
        spokeCount: spokeCount,
        innerPatternType: pattern,
        outerRingRadiusPct: outerPct,
        patternComplexity: complexity,
        primaryColorHex: primary,
        secondaryColorHex: secondary,
        accentColorHex: accent,
        pulseSpeedMs: pulseMs,
      );

  final canvas = _NullCanvas() as Canvas;

  group('KinrelSymbolPainter', () {
    testWidgets('renders without throwing for a 0-member family',
        (tester) async {
      // 0-member family still gets sensible defaults from the backend
      // (ringCount=2, spokeCount=4, complexity=3).
      final painter = KinrelSymbolPainter(
        parameters: params(),
        progress: 0.5,
      );
      expect(
        () => painter.paint(canvas, const Size(220, 220)),
        returnsNormally,
      );
    });

    testWidgets('renders without throwing for a 1-member family',
        (tester) async {
      // Single-member family: minimal rings/spokes.
      final painter = KinrelSymbolPainter(
        parameters: params(
          ringCount: 2,
          spokeCount: 3,
          complexity: 1,
        ),
        progress: 0.0,
      );
      expect(
        () => painter.paint(canvas, const Size(220, 220)),
        returnsNormally,
      );
    });

    testWidgets('renders without throwing for a very large family',
        (tester) async {
      // Very large family: max rings/spokes/complexity.
      final painter = KinrelSymbolPainter(
        parameters: params(
          ringCount: 8,
          spokeCount: 12,
          complexity: 10,
          outerPct: 0.95,
        ),
        progress: 1.0,
      );
      expect(
        () => painter.paint(canvas, const Size(220, 220)),
        returnsNormally,
      );
    });

    testWidgets('renders every inner pattern without throwing',
        (tester) async {
      for (final pattern in KinrelInnerPattern.values) {
        final painter = KinrelSymbolPainter(
          parameters: params(pattern: pattern, complexity: 6),
          progress: 0.5,
        );
        expect(
          () => painter.paint(canvas, const Size(220, 220)),
          returnsNormally,
          reason: 'pattern $pattern threw',
        );
      }
    });

    testWidgets('handles zero-size canvas without throwing',
        (tester) async {
      final painter = KinrelSymbolPainter(
        parameters: params(),
        progress: 0.5,
      );
      expect(
        () => painter.paint(canvas, Size.zero),
        returnsNormally,
      );
    });

    testWidgets('handles malformed colour strings gracefully',
        (tester) async {
      final painter = KinrelSymbolPainter(
        parameters: params(
          primary: 'not-a-color',
          secondary: '',
          accent: '#XYZ',
        ),
        progress: 0.5,
      );
      // Should fall back to white rather than throw.
      expect(
        () => painter.paint(canvas, const Size(220, 220)),
        returnsNormally,
      );
    });

    test('shouldRepaint returns true when parameters change', () {
      final p1 = KinrelSymbolPainter(parameters: params(), progress: 0.0);
      final p2 = KinrelSymbolPainter(
        parameters: params(ringCount: 5),
        progress: 0.0,
      );
      expect(p2.shouldRepaint(p1), isTrue);
    });

    test('shouldRepaint returns true when progress changes', () {
      final p = params();
      final p1 = KinrelSymbolPainter(parameters: p, progress: 0.0);
      final p2 = KinrelSymbolPainter(parameters: p, progress: 0.5);
      expect(p2.shouldRepaint(p1), isTrue);
    });

    test('shouldRepaint returns false when nothing changes', () {
      final p = params();
      final p1 = KinrelSymbolPainter(parameters: p, progress: 0.5);
      final p2 = KinrelSymbolPainter(parameters: p, progress: 0.5);
      expect(p2.shouldRepaint(p1), isFalse);
    });
  });
}

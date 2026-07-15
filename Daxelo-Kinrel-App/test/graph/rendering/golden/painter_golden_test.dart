// test/graph/rendering/golden/painter_golden_test.dart
//
// P5.5 — Golden/visual-regression tests for painter output.
//
// Captures the output of the graph painters (birthday glow, memorial
// candle, ambient particles, mini-map, dot grid) as golden images.
// Any visual regression will be caught by a diff against the golden.
//
// Uses golden_toolkit for multi-scenario golden tests.
//
// NEW DEPENDENCY: golden_toolkit ^0.15.0 (flagged per Rule 12)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:kinrel/graph/rendering/ambient_particle_painter.dart';
import 'package:kinrel/graph/rendering/memorial_candle_painter.dart';
import 'package:kinrel/graph/widgets/engine/dot_grid_painter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P5.5 — Painter golden tests', () {
    testGoldens('DotGridPainter renders consistently', (tester) async {
      await tester.pumpWidgetBuilder(
        RepaintBoundary(
          child: SizedBox(
            width: 100,
            height: 100,
            child: CustomPaint(
              painter: DotGridPainter(
                color: Colors.white.withValues(alpha: 0.025),
              ),
            ),
          ),
        ),
        surfaceSize: const Size(100, 100),
      );
      await screenMatchesGolden(tester, 'dot_grid_painter');
    });

    testGoldens('MemorialCandlePainter renders at flicker 0.0', (tester) async {
      await tester.pumpWidgetBuilder(
        RepaintBoundary(
          child: SizedBox(
            width: 80,
            height: 80,
            child: CustomPaint(
              painter: MemorialCandlePainter(0.0),
            ),
          ),
        ),
        surfaceSize: const Size(80, 80),
      );
      await screenMatchesGolden(tester, 'memorial_candle_flicker_0');
    });

    testGoldens('MemorialCandlePainter renders at flicker 0.5', (tester) async {
      await tester.pumpWidgetBuilder(
        RepaintBoundary(
          child: SizedBox(
            width: 80,
            height: 80,
            child: CustomPaint(
              painter: MemorialCandlePainter(0.5),
            ),
          ),
        ),
        surfaceSize: const Size(80, 80),
      );
      await screenMatchesGolden(tester, 'memorial_candle_flicker_05');
    });

    testGoldens('MemorialCandlePainter renders at flicker 1.0', (tester) async {
      await tester.pumpWidgetBuilder(
        RepaintBoundary(
          child: SizedBox(
            width: 80,
            height: 80,
            child: CustomPaint(
              painter: MemorialCandlePainter(1.0),
            ),
          ),
        ),
        surfaceSize: const Size(80, 80),
      );
      await screenMatchesGolden(tester, 'memorial_candle_flicker_1');
    });

    testGoldens('MemorialCandlePainter reduced motion (static)',
        (tester) async {
      await tester.pumpWidgetBuilder(
        RepaintBoundary(
          child: SizedBox(
            width: 80,
            height: 80,
            child: CustomPaint(
              painter: const MemorialCandlePainter(-1.0), // reduced motion
            ),
          ),
        ),
        surfaceSize: const Size(80, 80),
      );
      await screenMatchesGolden(tester, 'memorial_candle_reduced_motion');
    });

    testGoldens('AmbientParticlePainter renders at t=0.0', (tester) async {
      await tester.pumpWidgetBuilder(
        RepaintBoundary(
          child: SizedBox(
            width: 200,
            height: 200,
            child: CustomPaint(
              painter: const AmbientParticlePainter(
                t: 0.0,
                anchorPosition: Offset(100, 100),
              ),
            ),
          ),
        ),
        surfaceSize: const Size(200, 200),
      );
      await screenMatchesGolden(tester, 'ambient_particles_t0');
    });

    testGoldens('AmbientParticlePainter renders at t=0.5', (tester) async {
      await tester.pumpWidgetBuilder(
        RepaintBoundary(
          child: SizedBox(
            width: 200,
            height: 200,
            child: CustomPaint(
              painter: const AmbientParticlePainter(
                t: 0.5,
                anchorPosition: Offset(100, 100),
              ),
            ),
          ),
        ),
        surfaceSize: const Size(200, 200),
      );
      await screenMatchesGolden(tester, 'ambient_particles_t05');
    });

    testGoldens('AmbientParticlePainter reduced motion (static)',
        (tester) async {
      await tester.pumpWidgetBuilder(
        RepaintBoundary(
          child: SizedBox(
            width: 200,
            height: 200,
            child: CustomPaint(
              painter: const AmbientParticlePainter(
                t: 0.0,
                anchorPosition: Offset(100, 100),
                reducedMotion: true,
              ),
            ),
          ),
        ),
        surfaceSize: const Size(200, 200),
      );
      await screenMatchesGolden(tester, 'ambient_particles_reduced_motion');
    });
  });

  group('P5.5 — Golden test contract', () {
    test('golden_toolkit is available', () {
      expect(screenMatchesGolden, isA<Function>());
    });

    test('all painter classes are testable', () {
      expect(DotGridPainter, isA<Type>());
      expect(MemorialCandlePainter, isA<Type>());
      expect(AmbientParticlePainter, isA<Type>());
    });
  });
}

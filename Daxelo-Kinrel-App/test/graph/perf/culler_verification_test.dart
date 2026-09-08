// test/graph/perf/culler_verification_test.dart
//
// v5.146 (STEP 6): Verifies the viewport culler actually excludes
// off-screen nodes from the visible set. This is the test that would
// have caught the "hidden nodes still in the build pipeline" bug from
// v5.143 — if the culler returns 700 nodes when only 50 are on-screen,
// this test fails.
//
// Run:  flutter test test/graph/perf/culler_verification_test.dart

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/graph/rendering/viewport_culler.dart';

void main() {
  group('ViewportCuller — visible-node enforcement (Step 6)', () {
    test('culler returns ONLY nodes within viewport + buffer', () {
      // 100 nodes in a 10×10 grid, spaced 200px apart.
      // Viewport is 400×800 centred on the anchor (node 0 at 0,0).
      // With a 200px buffer, only the top-left ~3×4 = 12 nodes should
      // be visible — NOT all 100.
      final positions = <String, Offset>{};
      for (var y = 0; y < 10; y++) {
        for (var x = 0; x < 10; x++) {
          final id = '$x-$y';
          positions[id] = Offset(x * 200.0, y * 200.0);
        }
      }

      final nodeSizes = <String, Size>{
        for (final id in positions.keys) id: const Size(96, 120),
      };

      final culler = ViewportCuller(
        viewport: Rect.zero,
        bufferPixels: 200.0,
        rebuildThreshold: 50.0,
      );

      // Viewport: 400×800 centred on (0,0) → from (-200,-400) to (200,400).
      // With 200px buffer → from (-400,-600) to (400,600).
      // Nodes in range: x ∈ [-400,400] → x=0,1,2 (0,200,400)
      //                 y ∈ [-600,600] → y=0,1,2,3 (0,200,400,600)
      // Total visible: 3×4 = 12 nodes (NOT 100).
      final viewport = Rect.fromCenter(
        center: Offset.zero,
        width: 400,
        height: 800,
      );

      final visible = culler.cull(positions, nodeSizes, viewport);

      // The culler MUST exclude off-screen nodes.
      expect(visible.length, lessThanOrEqualTo(20),
          reason: 'Culler should return ~12 nodes (3×4 grid in viewport+buffer), '
              'not all 100. Got ${visible.length}.');
      expect(visible.length, greaterThan(0),
          reason: 'Culler should return at least the anchor node.');

      // Every returned ID must have a position (no phantom IDs).
      for (final id in visible) {
        expect(positions.containsKey(id), isTrue,
            reason: 'Culler returned ID "$id" which has no position — '
                'hidden nodes are leaking into the visible set.');
      }
    });

    test('culler does NOT return nodes far outside the viewport', () {
      // 700 nodes scattered across a huge canvas. Viewport is small.
      // The culler must return a SMALL subset, not all 700.
      final positions = <String, Offset>{};
      final random = _SeededRandom(42);
      for (var i = 0; i < 700; i++) {
        positions['p$i'] = Offset(
          (random.nextDouble() - 0.5) * 10000,
          (random.nextDouble() - 0.5) * 10000,
        );
      }

      final nodeSizes = <String, Size>{
        for (final id in positions.keys) id: const Size(96, 120),
      };

      final culler = ViewportCuller(
        viewport: Rect.zero,
        bufferPixels: 100.0,
        rebuildThreshold: 50.0,
      );

      // Small viewport: 400×800 at origin.
      final viewport = Rect.fromCenter(
        center: Offset.zero,
        width: 400,
        height: 800,
      );

      final visible = culler.cull(positions, nodeSizes, viewport);

      // With 700 nodes scattered across 10000×10000 and a 400×800
      // viewport + 100px buffer, we expect maybe 5-15 nodes — definitely
      // NOT 700. This is the test that catches "the culler isn't
      // culling" — the root cause of the user's lag complaint.
      expect(visible.length, lessThan(50),
          reason: 'Culler should return a SMALL subset of 700 nodes, '
              'not all of them. Got ${visible.length}. '
              'If this is >50, the culler is NOT excluding off-screen '
              'nodes — they are leaking into the build pipeline.');
    });

    test('culler skip/rebuild tracking works', () {
      final positions = <String, Offset>{
        'a': const Offset(0, 0),
        'b': const Offset(100, 0),
        'c': const Offset(200, 0),
      };
      final nodeSizes = <String, Size>{
        for (final id in positions.keys) id: const Size(96, 120),
      };

      final culler = ViewportCuller(
        viewport: Rect.zero,
        bufferPixels: 200.0,
        rebuildThreshold: 50.0,
      );

      final viewport = Rect.fromCenter(
        center: Offset.zero,
        width: 400,
        height: 400,
      );

      // First call — should rebuild.
      culler.cull(positions, nodeSizes, viewport);
      expect(culler.rebuildCount, greaterThanOrEqualTo(1),
          reason: 'First call should trigger a rebuild.');

      // Same viewport — should skip.
      culler.cull(positions, nodeSizes, viewport);
      expect(culler.skipCount, greaterThanOrEqualTo(1),
          reason: 'Same viewport should trigger a skip, not a rebuild.');

      // Small pan (10px) — should still skip (< 50px threshold).
      final viewport2 = Rect.fromCenter(
        center: const Offset(10, 0),
        width: 400,
        height: 400,
      );
      final skipBefore = culler.skipCount;
      culler.cull(positions, nodeSizes, viewport2);
      expect(culler.skipCount, greaterThan(skipBefore),
          reason: 'Pan < threshold should skip, not rebuild.');
    });

    test('cull ratio is computed correctly', () {
      final positions = <String, Offset>{
        'a': const Offset(0, 0),
        'b': const Offset(100, 0),
        'c': const Offset(5000, 0), // far off-screen
        'd': const Offset(10000, 0), // far off-screen
      };
      final nodeSizes = <String, Size>{
        for (final id in positions.keys) id: const Size(96, 120),
      };

      final culler = ViewportCuller(
        viewport: Rect.zero,
        bufferPixels: 200.0,
        rebuildThreshold: 50.0,
      );

      final viewport = Rect.fromCenter(
        center: Offset.zero,
        width: 400,
        height: 400,
      );

      culler.cull(positions, nodeSizes, viewport);

      // 4 total positions, 2 visible (a + b), cull ratio = 0.5.
      expect(culler.totalPositionsSeen, 4);
      expect(culler.visibleCount, lessThanOrEqualTo(2));
      expect(culler.cullRatio, lessThan(0.6),
          reason: 'Cull ratio should be ~0.5 (2 of 4 nodes visible).');
    });
  });
}

/// Deterministic seeded random for reproducible test positions.
class _SeededRandom {
  int _state;
  _SeededRandom(this._state);

  double nextDouble() {
    // Simple LCG — deterministic, good enough for test positions.
    _state = (1103515245 * _state + 12345) & 0x7fffffff;
    return _state / 0x7fffffff;
  }
}

// test/graph/engine/wedge_motion_test.dart
//
// Golden numbers come from the approved preview's own math, using the
// "Case A" first-view layout (viewer + r0..r7 + the root +N chip).

import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/graph/engine/wedge_motion.dart';

const _positions = <String, Offset>{
  'root': Offset(0, 0),
  'r0': Offset(98.0, -269.2),
  'r1': Offset(248.1, -143.2),
  'r2': Offset(282.1, 49.7),
  'r3': Offset(184.1, 219.5),
  'r4': Offset(0.0, 286.5),
  'r5': Offset(-184.1, 219.5),
  'r6': Offset(-282.1, 49.7),
  'r7': Offset(-248.1, -143.2),
  'chip:root': Offset(-98.0, -269.2),
};

Size _sizeOf(String id) =>
    id == 'root' ? const Size(124, 140) : const Size(124, 128);

void main() {
  group('WedgeMotion', () {
    test('ease-in-out values', () {
      expect(WedgeMotion.easeInOut(0), 0);
      expect(WedgeMotion.easeInOut(0.25), closeTo(0.125, 1e-9));
      expect(WedgeMotion.easeInOut(0.5), closeTo(0.5, 1e-9));
      expect(WedgeMotion.easeInOut(0.75), closeTo(0.875, 1e-9));
      expect(WedgeMotion.easeInOut(1), 1);
      expect(WedgeMotion.durationMs, 450);
    });

    test('existing nodes glide, new nodes start at their parent', () {
      const from = <String, Offset>{
        'root': Offset(0, 0),
        'r0': Offset(10, 10),
      };
      const to = <String, Offset>{
        'root': Offset(0, 0),
        'r0': Offset(20, 20),
        'r0.0': Offset(100, 0),
      };
      const parentOf = <String, String?>{
        'root': null,
        'r0': 'root',
        'r0.0': 'r0',
      };
      final start = WedgeMotion.interpolate(
          from: from, to: to, parentOf: parentOf, t: 0);
      expect(start['r0'], const Offset(10, 10));
      expect(start['r0.0'], const Offset(10, 10)); // from the parent
      final mid = WedgeMotion.interpolate(
          from: from, to: to, parentOf: parentOf, t: 0.5);
      expect(mid['r0']!.dx, closeTo(15, 1e-9));
      expect(mid['r0.0']!.dx, closeTo(55, 1e-9));
      expect(mid['r0.0']!.dy, closeTo(5, 1e-9));
      final end = WedgeMotion.interpolate(
          from: from, to: to, parentOf: parentOf, t: 1);
      expect(end['r0.0'], const Offset(100, 0));
    });

    test('ids that left the layout are not drawn', () {
      final out = WedgeMotion.interpolate(
        from: const {'a': Offset(1, 1), 'gone': Offset(5, 5)},
        to: const {'a': Offset(2, 2)},
        parentOf: const {'a': null},
        t: 1,
      );
      expect(out.containsKey('gone'), isFalse);
    });
  });

  group('WedgeCameraFit', () {
    final boxes = [
      for (final e in _positions.entries)
        WedgeCameraFit.boxFor(e.value, _sizeOf(e.key)),
    ];

    test('first view fits at about 0.523 in a 380x470 area', () {
      final cam = WedgeCameraFit.fit(
        boxes: boxes,
        viewport: const Size(380, 470),
      );
      expect(cam.scale, closeTo(0.5231, 0.001));
      expect(cam.translation.dx, closeTo(190.0, 0.5));
      expect(cam.translation.dy, closeTo(195.48, 0.5));
    });

    test('viewer + r0 fits at about 0.952', () {
      final cam = WedgeCameraFit.fit(
        boxes: [
          WedgeCameraFit.boxFor(_positions['root']!, _sizeOf('root')),
          WedgeCameraFit.boxFor(_positions['r0']!, _sizeOf('r0')),
        ],
        viewport: const Size(380, 470),
      );
      expect(cam.scale, closeTo(0.9524, 0.001));
      expect(cam.translation.dx, closeTo(143.33, 0.5));
      expect(cam.translation.dy, closeTo(325.33, 0.5));
    });

    test('scale is clamped to the minimum readable zoom', () {
      final cam = WedgeCameraFit.fit(
        boxes: const [Rect.fromLTRB(-5000, -5000, 5000, 5000)],
        viewport: const Size(380, 470),
        minScale: 0.45,
      );
      expect(cam.scale, 0.45);
    });
  });

  group('WedgeEdgeRouter', () {
    const router = WedgeEdgeRouter(sizeOf: _sizeOf);

    test('clear lines stay straight (null control point)', () {
      expect(router.route('r0', 'r1', _positions), isNull);
      expect(router.route('r4', 'r5', _positions), isNull);
      expect(router.route('root', 'r4', _positions), isNull);
    });

    test('a line through another node bends with the smallest clear bow', () {
      final c = router.route('r1', 'r6', _positions);
      expect(c, isNotNull);
      expect(c!.dx, closeTo(-47.8, 0.5));
      expect(c.dy, closeTo(-131.3, 0.5));
    });

    test('bow side: away from the viewer first, opposite side if needed', () {
      final c2 = router.route('r2', 'r6', _positions);
      expect(c2, isNotNull);
      expect(c2!.dx, closeTo(0.0, 0.5));
      expect(c2.dy, closeTo(139.7, 0.5));
      final c3 = router.route('r0', 'r5', _positions);
      expect(c3, isNotNull);
      expect(c3!.dx, closeTo(-121.0, 0.5));
      expect(c3.dy, closeTo(-69.8, 0.5));
    });

    test('curve really clears every footprint', () {
      final c = router.route('r1', 'r6', _positions)!;
      final a = _positions['r1']!;
      final b = _positions['r6']!;
      for (var s = 1; s < 24; s++) {
        final p = WedgeEdgeRouter.pointAt(a, b, c, s / 24);
        for (final e in _positions.entries) {
          if (e.key == 'r1' || e.key == 'r6') continue;
          final size = _sizeOf(e.key);
          final inside = (p.dx - e.value.dx).abs() < size.width / 2 + 6 &&
              (p.dy - e.value.dy).abs() < size.height / 2 + 6;
          expect(inside, isFalse, reason: 'curve crosses ${e.key}');
        }
      }
    });

    test('routeAll returns one entry per edge key', () {
      final all = router.routeAll(
        const [WedgeEdge('r0', 'r1'), WedgeEdge('r1', 'r6')],
        _positions,
      );
      expect(all['r0>r1'], isNull);
      expect(all['r1>r6'], isNotNull);
    });
  });
}

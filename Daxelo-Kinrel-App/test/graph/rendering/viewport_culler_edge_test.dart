// test/graph/rendering/viewport_culler_edge_test.dart
//
// Regression test for the "connection lines and intermediate dots
// disappear when zooming in" bug.
//
// Root cause: ViewportCuller.isEdgeVisible required BOTH endpoint
// nodes to be in the visible set. When the user zoomed in, the
// graph-space viewport shrank, so BOTH endpoints of an edge could
// fall outside the viewport even though the connecting line clearly
// crossed the visible area. Those edges — and their midpoint dots /
// hearts — were silently dropped by the canvas builder.
//
// The fix introduces isEdgeVisibleWithViewport, which keeps an edge
// when EITHER at least one endpoint is visible OR the connecting
// segment intersects the (buffer-expanded) graph-space viewport.
//
// This test exercises both branches of the new method plus the
// Liang–Barsky segment-vs-rect intersection helper it relies on.

import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/graph/rendering/viewport_culler.dart';

void main() {
  // A 100×100 graph-space viewport centered at the origin.
  final Rect viewport = const Rect.fromLTWH(-50, -50, 100, 100);

  // Visible node set: only node A is visible (at the origin). All
  // other nodes are off-screen by enough that the 200px buffer does
  // not pull them in.
  const String visibleA = 'A';
  const Set<String> visible = {visibleA};

  final ViewportCuller culler = ViewportCuller(viewport: viewport);

  group('isEdgeVisible (legacy both-endpoints-visible rule)', () {
    test('visible when both endpoints are in the visible set', () {
      expect(culler.isEdgeVisible('A', 'A2', {'A', 'A2'}), isTrue);
    });

    test('NOT visible when only one endpoint is in the visible set', () {
      // This is the behaviour we are REPLACING for the zoom-in case —
      // documented here so the contrast with the new method is clear.
      expect(culler.isEdgeVisible('A', 'B', visible), isFalse);
    });

    test('NOT visible when neither endpoint is in the visible set', () {
      expect(culler.isEdgeVisible('B', 'C', visible), isFalse);
    });
  });

  group('isEdgeVisibleWithViewport (zoom-in-aware rule)', () {
    test('visible when at least one endpoint is in the visible set', () {
      // A is visible, B is off-screen → fast path keeps the edge.
      expect(
        culler.isEdgeVisibleWithViewport(
          sourceId: 'A',
          targetId: 'B',
          sourcePos: const Offset(0, 0),
          targetPos: const Offset(500, 500),
          visibleNodeIds: visible,
          viewport: culler.expandedViewport(viewport),
        ),
        isTrue,
      );
    });

    test(
        'visible when BOTH endpoints are off-screen but the segment '
        'crosses the viewport (the zoom-in bug scenario)', () {
      // Both endpoints are far off-screen, but the line between them
      // passes straight through the viewport. The legacy rule would
      // have culled this edge — causing the connecting line + its
      // midpoint dot to disappear when the user zoomed in.
      expect(
        culler.isEdgeVisibleWithViewport(
          sourceId: 'B',
          targetId: 'C',
          sourcePos: const Offset(-400, 0),
          targetPos: const Offset(400, 0),
          visibleNodeIds: visible,
          viewport: culler.expandedViewport(viewport),
        ),
        isTrue,
        reason:
            'An edge whose line crosses the viewport must remain visible '
            'even when both endpoint widgets are off-screen.',
      );
    });

    test('visible when the segment is fully INSIDE the viewport', () {
      expect(
        culler.isEdgeVisibleWithViewport(
          sourceId: 'X',
          targetId: 'Y',
          sourcePos: const Offset(-10, -10),
          targetPos: const Offset(10, 10),
          visibleNodeIds: const <String>{},
          viewport: culler.expandedViewport(viewport),
        ),
        isTrue,
      );
    });

    test('NOT visible when both endpoints are off-screen AND the segment '
        'does not cross the viewport', () {
      // Both endpoints are far to the right; the segment between them
      // stays far to the right and never enters the viewport.
      expect(
        culler.isEdgeVisibleWithViewport(
          sourceId: 'B',
          targetId: 'C',
          sourcePos: const Offset(400, 400),
          targetPos: const Offset(500, 500),
          visibleNodeIds: visible,
          viewport: culler.expandedViewport(viewport),
        ),
        isFalse,
      );
    });

    test('NOT visible when the segment is parallel to and outside the '
        'viewport (left edge)', () {
      // Vertical segment far to the left of the viewport.
      expect(
        culler.isEdgeVisibleWithViewport(
          sourceId: 'B',
          targetId: 'C',
          sourcePos: const Offset(-500, -500),
          targetPos: const Offset(-500, 500),
          visibleNodeIds: visible,
          viewport: culler.expandedViewport(viewport),
        ),
        isFalse,
      );
    });

    test('visible when the segment just grazes the viewport corner', () {
      // The segment from (-400,-400) to (400,400) passes exactly
      // through the viewport's top-left→bottom-right diagonal.
      expect(
        culler.isEdgeVisibleWithViewport(
          sourceId: 'B',
          targetId: 'C',
          sourcePos: const Offset(-400, -400),
          targetPos: const Offset(400, 400),
          visibleNodeIds: const <String>{},
          viewport: culler.expandedViewport(viewport),
        ),
        isTrue,
      );
    });
  });

  group('expandedViewport', () {
    test('expands the viewport by bufferPixels on every side', () {
      final expanded = culler.expandedViewport(viewport);
      // Default buffer is 200px.
      expect(expanded.left, equals(viewport.left - 200));
      expect(expanded.top, equals(viewport.top - 200));
      expect(expanded.right, equals(viewport.right + 200));
      expect(expanded.bottom, equals(viewport.bottom + 200));
      expect(expanded.size, equals(Size(viewport.width + 400, viewport.height + 400)));
    });
  });
}

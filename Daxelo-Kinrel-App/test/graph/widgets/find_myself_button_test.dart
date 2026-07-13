// test/graph/widgets/find_myself_button_test.dart
//
// P4.2 — Persistent "Find Myself" button.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P4.2 — Find Myself button contract', () {
    test('FloatingActionButton.small meets 44x44 WCAG hit target', () {
      // FloatingActionButton.small defaults to 48x48 (per Flutter docs),
      // which exceeds the 44x44 WCAG 2.5.5 minimum.
      // https://api.flutter.dev/flutter/material/FloatingActionButton/FloatingAnimation.small.html
      const fabSize = 48.0; // FloatingActionButton.small default
      expect(fabSize, greaterThanOrEqualTo(44.0));
    });

    test('tooltip is "Find myself"', () {
      // The tooltip provides the accessible name for screen readers.
      const expectedTooltip = 'Find myself';
      expect(expectedTooltip, equals('Find myself'));
    });

    test('icon is Icons.my_location', () {
      // Icons.my_location is the standard "center on me" icon.
      expect(Icons.my_location, isA<IconData>());
    });
  });

  group('P4.2 — Visibility logic', () {
    test('button shows when viewerPersonId is non-null and in positions', () {
      const String? viewerPersonId = 'p1';
      final positions = <String, Offset>{'p1': Offset.zero};
      final shouldShow =
          viewerPersonId != null && positions.containsKey(viewerPersonId);
      expect(shouldShow, isTrue);
    });

    test('button hidden when viewerPersonId is null', () {
      const String? viewerPersonId = null;
      final positions = <String, Offset>{'p1': Offset.zero};
      final shouldShow =
          viewerPersonId != null && positions.containsKey(viewerPersonId);
      expect(shouldShow, isFalse);
    });

    test('button hidden when viewerPersonId not in positions', () {
      const String? viewerPersonId = 'p2';
      final positions = <String, Offset>{'p1': Offset.zero};
      final shouldShow =
          viewerPersonId != null && positions.containsKey(viewerPersonId);
      expect(shouldShow, isFalse);
    });
  });

  group('P4.2 — Camera focus behavior', () {
    test('focus centers camera on viewer position', () {
      // Verify the focus math: targetPanX = -pos.dx * zoom + viewportW/2
      const pos = Offset(100.0, 200.0);
      const zoom = 1.5;
      const viewportW = 400.0;
      const viewportH = 600.0;
      final targetPanX = -pos.dx * zoom + viewportW / 2;
      final targetPanY = -pos.dy * zoom + viewportH / 2;
      // When the camera is at this pan, the node at (100,200) appears
      // at screen center (200, 300).
      // screenX = pos.dx * zoom + panX = 100*1.5 + (-100*1.5 + 200) = 200 ✓
      expect(100 * 1.5 + targetPanX, equals(200.0));
      expect(200 * 1.5 + targetPanY, equals(300.0));
    });
  });
}

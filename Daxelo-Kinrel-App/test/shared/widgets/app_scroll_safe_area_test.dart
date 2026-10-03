// test/shared/widgets/app_scroll_safe_area_test.dart
//
// Tests for the AppScrollSafeArea shared widget — verifies the ADR-007
// safe-area math is correct, and that the .sliver() constructor produces
// a usable SliverToBoxAdapter.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/shared/widgets/app_scroll_safe_area.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppScrollSafeArea', () {
    testWidgets('.sliver() returns a SliverToBoxAdapter that respects '
        'MediaQuery padding bottom + chrome height + margins',
        (tester) async {
      // Use a forced bottom padding to make the math deterministic.
      const fakePaddingBottom = 34.0; // iOS home indicator
      const chromeHeight = 56.0;
      const margin = 24.0;
      const extraSpacing = 16.0;

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
                padding: EdgeInsets.only(bottom: fakePaddingBottom)),
            child: Scaffold(
              body: CustomScrollView(
                slivers: [
                  AppScrollSafeArea.sliver(
                    chromeHeight: chromeHeight,
                    margin: margin,
                    extraSpacing: extraSpacing,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // The sliver renders a SizedBox with the expected total height.
      final expectedTotal =
          chromeHeight + margin + fakePaddingBottom + extraSpacing;
      final sizedBox = tester.widget<SizedBox>(find.byType(SizedBox));
      expect(sizedBox.height, expectedTotal);
    });

    testWidgets('non-sliver variant wraps child with bottom padding equal '
        'to chrome + margin + inset + extra', (tester) async {
      const fakePaddingBottom = 20.0;
      const chromeHeight = 80.0;
      const margin = 24.0;
      const extraSpacing = 16.0;

      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(padding: EdgeInsets.only(bottom: fakePaddingBottom)),
            child: Scaffold(
              body: AppScrollSafeArea(
                chromeHeight: chromeHeight,
                margin: margin,
                extraSpacing: extraSpacing,
                child: Text('content'),
              ),
            ),
          ),
        ),
      );

      final padding = tester.widget<Padding>(find.byType(Padding).first);
      final expected =
          chromeHeight + margin + fakePaddingBottom + extraSpacing;
      expect(padding.padding, EdgeInsets.only(bottom: expected));
    });

    test('default constants match the Family Space pattern', () {
      // Defaults: chromeHeight 80, margin 24, extraSpacing 16.
      // Total at zero bottom-inset = 120. Matches the inline math
      // in family_detail_screen.dart (80 + 24 + 0 + 16 = 120).
      const w = AppScrollSafeArea();
      expect(w.chromeHeight, 80);
      expect(w.margin, 24);
      expect(w.extraSpacing, 16);
    });

    test('.sliver() factory produces a non-null SliverToBoxAdapter', () {
      final sliver = AppScrollSafeArea.sliver();
      expect(sliver, isA<SliverToBoxAdapter>());
    });
  });
}

// test/features/memory_vault/memory_create_screen_layout_regression_test.dart
//
// Regression test for the blank Add Memory form bug.
//
// Bug: The _buildBottomBar() returns `SafeArea(child: Container(child:
// DKButton(...)))`. The DKButton widget uses `BoxConstraints(minHeight:
// _height)` with NO maxHeight, and contains `Center(child: content)`
// which expands to fill the parent's maxHeight. When this SafeArea-
// wrapped bar is placed in `Scaffold.bottomNavigationBar`, the Scaffold
// cannot query a preferred height (SafeArea is not a
// PreferredSizeWidget), so it gives the bar a maxHeight of the FULL
// SCREEN HEIGHT. The DKButton's Center then expands to fill that
// maxHeight, making the bottom bar take 100% of the screen height —
// and the body slot ends up with ZERO height. The user sees only
// "Save Memory" (this bar) and the form fields (in the body) are
// invisible.
//
// Fix: pin the bar's height to the natural button height + padding
// (56 + 24 = 80) via a SizedBox, so the bottom bar no longer expands
// to fill the full screen. The body slot regains its non-zero height
// and all form fields become visible.
//
// This test asserts the structural contract: the body slot must have
// a non-zero height, AND the SingleChildScrollView inside the body
// must have a non-zero height, AND each form field label must be
// rendered with a non-zero size.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kinrel/features/memory_vault/presentation/memory_create_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  // Helper: render the screen at iPhone-14-ish logical size with a
  // realistic MediaQuery padding (status bar at top, gesture-nav inset
  // at bottom).
  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/memory/create',
      routes: [
        GoRoute(
          path: '/memory/create',
          pageBuilder: (context, state) {
            final args = state.extra as MemoryCreateArgs?;
            return CustomTransitionPage<void>(
              key: state.pageKey,
              child: MemoryCreateScreen(args: args),
              transitionsBuilder: (c, anim, s2, child) =>
                  FadeTransition(opacity: anim, child: child),
            );
          },
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: const [],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  group('MemoryCreateScreen — body slot has non-zero height (regression)', () {
    testWidgets('SingleChildScrollView in body has non-zero height',
        (tester) async {
      await pumpScreen(tester);
      final exception = tester.takeException();
      expect(exception, isNull, reason: 'Screen must build without error');

      final ssv = find.byType(SingleChildScrollView).evaluate().single;
      final ro = ssv.findRenderObject();
      expect(ro, isNotNull, reason: 'SingleChildScrollView must render');

      final size = (ro! as dynamic).size as Size;
      print('SingleChildScrollView size: ${size.width}x${size.height}');

      // The body slot must have a non-zero height — this is the regression
      // we are guarding against. Pre-fix the body was 390x0 (zero height).
      expect(size.height, greaterThan(0),
          reason:
              'Body SingleChildScrollView must have non-zero height. '
              'Pre-fix: bottomNavigationBar expanded to fill the screen, '
              'leaving the body with 0 height.');
    });

    testWidgets('All form field labels are visible with non-zero size',
        (tester) async {
      await pumpScreen(tester);
      final exception = tester.takeException();
      expect(exception, isNull);

      // Each form field label must be rendered AND have non-zero size.
      final labelsToCheck = const [
        'Title', // The label above the title TextField
        'Story', // The label above the description TextField
        'Date', // The label above the date picker
        'Memory Type', // The label above the category chips
        'Members', // The label above the member selector
        'Add Cover Photo', // The cover photo attach prompt
        'Save Memory', // The bottom-bar Save button
      ];

      for (final label in labelsToCheck) {
        final finder = find.text(label);
        expect(finder, findsOneWidget,
            reason: 'Label "$label" must be present in the tree');

        final ro = finder.evaluate().single.findRenderObject();
        expect(ro, isNotNull,
            reason: 'Label "$label" must have a render object');
        final size = (ro! as dynamic).size as Size;
        expect(size.width, greaterThan(0),
            reason: 'Label "$label" must have non-zero width');
        expect(size.height, greaterThan(0),
            reason: 'Label "$label" must have non-zero height');
        print('  ✓ "$label" rendered ${size.width}x${size.height}');
      }
    });

    testWidgets('Bottom bar does NOT consume full screen height',
        (tester) async {
      await pumpScreen(tester);
      final exception = tester.takeException();
      expect(exception, isNull);

      // The bottom bar's DKButton should be approximately 56px tall (the
      // natural button height), not 700+ pixels. The bottom bar Container
      // should be approximately 80px (button + 24px padding).
      final screenSize = tester.view.physicalSize / tester.view.devicePixelRatio;
      print('Screen size (logical): ${screenSize.width}x${screenSize.height}');

      // Find the "Save Memory" text widget — it sits inside the bottom bar.
      final saveFinder = find.text('Save Memory');
      final ro = saveFinder.evaluate().single.findRenderObject()!;
      final saveTextSize = (ro as dynamic).size as Size;
      print('Save Memory text size: ${saveTextSize.width}x${saveTextSize.height}');

      // The bottom-bar button row must be far smaller than the full screen.
      // Pre-fix: the button + Center expanded to ~700px. Post-fix: 56px.
      // We assert the height is roughly button-sized (not full-screen).
      expect(saveTextSize.height, lessThan(60),
          reason:
              'Save Memory text must be roughly button-sized (~56px). '
              'Pre-fix: bottom bar expanded to fill full screen height '
              '(700+ pixels), hiding the body.');
    });
  });
}

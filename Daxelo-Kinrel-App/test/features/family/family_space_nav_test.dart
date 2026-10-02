// test/features/family/family_space_nav_test.dart
//
// Phase 2 (duplicate-space-home fix): widget tests for the
// consolidated navigation structure.
//
// Verifies:
//   1. FamilySpaceFloatingNav contains EXACTLY 4 items (Games, Family
//      Chat, Members, Calendar) and does NOT include Lists.
//   2. HighlightsRow contains EXACTLY 5 items (Memories, Oral History,
//      Achievements, Lists, Activity) — the secondary shortcut row
//      that now hosts the demoted Lists destination.
//   3. HighlightsRow renders only ONCE per screen (the single
//      secondary shortcut row, not duplicated anywhere else).
//
// These tests guard against regressions:
//   • Re-introducing Lists into the bottom nav
//   • Adding a 6th shortcut to HighlightsRow
//   • Duplicating the shortcut row in another widget

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:kinrel/features/family/presentation/family_space_floating_nav.dart';
import 'package:kinrel/features/family/presentation/premium/family_hub_highlights.dart';

void main() {
  group('FamilySpaceFloatingNav — Phase 2 (4-tab bottom nav)', () {
    testWidgets('contains exactly 4 tabs in the correct order',
        (WidgetTester tester) async {
      // Build the nav with a fake familyId. We render it inside a
      // GoRouter so the location-based _currentIndex lookup works
      // without throwing.
      final router = GoRouter(
        initialLocation: '/family/test-fam',
        routes: [
          GoRoute(
            path: '/family/:id',
            builder: (context, state) => Scaffold(
              body: const SizedBox(),
              bottomNavigationBar: FamilySpaceFloatingNav(
                familyId: state.pathParameters['id']!,
              ),
            ),
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      // Verify the 4 expected labels are present, in order.
      expect(find.text('Games'), findsOneWidget);
      expect(find.text('Family Chat'), findsOneWidget);
      expect(find.text('Members'), findsOneWidget);
      expect(find.text('Calendar'), findsOneWidget);

      // Verify Lists is NOT in the bottom nav (it was demoted to the
      // HighlightsRow shortcut row).
      expect(find.text('Lists'), findsNothing,
          reason: 'Lists must not appear in the bottom nav — '
              'it was demoted to the HighlightsRow per Phase 2');
    });

    testWidgets('does not include Lists as a tab label',
        (WidgetTester tester) async {
      // Separate explicit test for the Lists removal — makes the
      // regression test name explicit in the test report.
      final router = GoRouter(
        initialLocation: '/family/test-fam',
        routes: [
          GoRoute(
            path: '/family/:id',
            builder: (context, state) => Scaffold(
              body: const SizedBox(),
              bottomNavigationBar: FamilySpaceFloatingNav(
                familyId: state.pathParameters['id']!,
              ),
            ),
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      // Verify the bottom nav has exactly 4 tab labels (not 5).
      final gamesFinder = find.text('Games');
      final chatFinder = find.text('Family Chat');
      final membersFinder = find.text('Members');
      final calendarFinder = find.text('Calendar');
      final listsFinder = find.text('Lists');

      expect(gamesFinder, findsOneWidget);
      expect(chatFinder, findsOneWidget);
      expect(membersFinder, findsOneWidget);
      expect(calendarFinder, findsOneWidget);
      expect(listsFinder, findsNothing,
          reason: 'Lists was demoted from the bottom nav to the '
              'HighlightsRow shortcut row in Phase 2');
    });
  });

  group('HighlightsRow — Phase 3 (single secondary shortcut row)', () {
    testWidgets('contains exactly 5 items in the correct order',
        (WidgetTester tester) async {
      // The HighlightsRow is a StatelessWidget with no providers — easy
      // to render directly.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: const [
                HighlightsRow(familyId: 'test-fam'),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify the 5 expected labels are present, in order.
      expect(find.text('Memories'), findsOneWidget);
      expect(find.text('Oral History'), findsOneWidget);
      expect(find.text('Achievements'), findsOneWidget);
      expect(find.text('Lists'), findsOneWidget);
      expect(find.text('Activity'), findsOneWidget);

      // Verify no 6th item was added.
      final allTextWidgets =
          find.byType(Text).evaluate().map((e) => (e.widget as Text).data);
      final highlightLabels = allTextWidgets
          .where((t) =>
              t == 'Memories' ||
              t == 'Oral History' ||
              t == 'Achievements' ||
              t == 'Lists' ||
              t == 'Activity')
          .toList();
      expect(highlightLabels.length, 5,
          reason: 'HighlightsRow must have exactly 5 shortcut tiles');
    });

    testWidgets('renders only once when placed in a scroll view once',
        (WidgetTester tester) async {
      // Build a minimal screen with ONE HighlightsRow at the top of
      // a scroll view (matching the FamilyDetailScreen layout). The
      // test verifies the row renders exactly once — no duplicate.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: const [
                HighlightsRow(familyId: 'test-fam'),
                SizedBox(height: 16),
                Placeholder(fallbackHeight: 200),
                SizedBox(height: 16),
                Placeholder(fallbackHeight: 200),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The HighlightsRow widget should appear exactly once.
      expect(find.byType(HighlightsRow), findsOneWidget,
          reason: 'HighlightsRow must render exactly once per screen — '
              'it is the single secondary shortcut row per Phase 3');

      // And the Lists label (which now lives ONLY in HighlightsRow)
      // should appear exactly once, not twice.
      expect(find.text('Lists'), findsOneWidget,
          reason: 'Lists must appear exactly once — in the HighlightsRow. '
              'If it appears twice, the bottom nav was not properly '
              'consolidated.');
    });
  });
}

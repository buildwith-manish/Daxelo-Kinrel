// test/features/family/family_state_aware_home_screen_test.dart
//
// Layout-restoration brief: widget tests for the Family Space home
// screen's secondary effects.
//
// Verifies:
//   1. HighlightsRow shortcut order: Memories and Activity are the
//      FIRST two tiles (per the "group by usage tier" rule from the
//      prior pass — this is unchanged by the layout restoration).
//   2. HeroSection builds without throwing in its default (full-size)
//      mode — the compact flag is still accepted but no longer used
//      by the Family Space screen.
//
// The pure-function tests (sectionOrderFor + classifyEngagementState)
// live in family_engagement_state_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kinrel/features/family/presentation/premium/family_hub_highlights.dart';
import 'package:kinrel/features/family/presentation/premium/hero_section.dart';

void main() {
  group('HighlightsRow — shortcut ordering (unchanged by layout restore)', () {
    testWidgets(
        'Memories and Activity are the FIRST two tiles (grouped by '
        'usage tier)', (WidgetTester tester) async {
      // HighlightsRow is a pure StatelessWidget (no providers), so it
      // can be pumped directly without a ProviderScope.
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

      // Verify all 5 labels are still present (no tile was removed).
      expect(find.text('Memories'), findsOneWidget);
      expect(find.text('Activity'), findsOneWidget);
      expect(find.text('Oral History'), findsOneWidget);
      expect(find.text('Achievements'), findsOneWidget);
      expect(find.text('Lists'), findsOneWidget);

      // Verify the order by inspecting the horizontal positions of the
      // labels. The first tile (Memories) should have the smallest x,
      // the last tile (Lists) the largest.
      final memoriesX = tester.getTopLeft(find.text('Memories')).dx;
      final activityX = tester.getTopLeft(find.text('Activity')).dx;
      final oralHistoryX = tester.getTopLeft(find.text('Oral History')).dx;
      final achievementsX = tester.getTopLeft(find.text('Achievements')).dx;
      final listsX = tester.getTopLeft(find.text('Lists')).dx;

      // Memories must come before Activity (the two most-likely-to-be-used
      // tiles render first).
      expect(memoriesX, lessThan(activityX),
          reason: 'Memories must render before Activity per the usage-tier '
              'ordering.');
      // Activity must come before Oral History, Achievements, and Lists.
      expect(activityX, lessThan(oralHistoryX));
      expect(activityX, lessThan(achievementsX));
      expect(activityX, lessThan(listsX));
      // Sanity: Oral History < Achievements < Lists (preserves the
      // relative order of the "secondary" tier).
      expect(oralHistoryX, lessThan(achievementsX));
      expect(achievementsX, lessThan(listsX));
    });
  });

  group('HeroSection — full-size mode (layout-restoration brief)', () {
    // The layout-restoration brief restored the header to its full
    // size. The Family Space screen no longer passes compact: true.
    // We verify the default (full-size) mode builds without throwing.
    testWidgets('builds without throwing in default (full-size) mode',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ListView(
                children: [
                  const HeroSection(
                    familyId: 'test-fam',
                    familyName: 'Test Family',
                    memberCount: 4,
                    relationshipCount: 3,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      // Pump once to start; don't pumpAndSettle because the kinrel
      // provider never resolves in the test environment.
      await tester.pump();

      expect(find.text('Test Family'), findsOneWidget,
          reason: 'HeroSection must render the family name in its '
              'default (full-size) mode.');
    });
  });
}

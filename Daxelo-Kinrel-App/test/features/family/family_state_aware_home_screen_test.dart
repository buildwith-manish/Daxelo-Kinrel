// test/features/family/family_state_aware_home_screen_test.dart
//
// Phase (family-state-aware-home-screen): widget tests for the
// secondary effects of the dynamic-home-screen change.
//
// Verifies:
//   1. HighlightsRow shortcut order: Memories and Activity are the
//      FIRST two tiles (per the "group by usage tier" rule).
//   2. HeroSection accepts the new `compact` flag and builds without
//      throwing (smoke test — the test verifies the flag is wired,
//      not pixel-perfect heights, to keep the test non-brittle).
//   3. MiniFamilyGraphPreview renders its "Family Graph" label and
//      "View Full Graph →" action footer even while the graph data
//      is loading (the card chrome is independent of the data fetch).
//
// The pure-function tests (sectionOrderFor + classifyEngagementState)
// live in family_engagement_state_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kinrel/features/family/presentation/premium/family_hub_highlights.dart';
import 'package:kinrel/features/family/presentation/premium/hero_section.dart';
import 'package:kinrel/features/family/presentation/widgets/mini_family_graph_preview.dart';

void main() {
  group('HighlightsRow — Phase (family-state-aware-home-screen) ordering', () {
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

  group('HeroSection — compact flag wiring (smoke test)', () {
    // The `compact` flag controls the hero's expanded height + symbol
    // size. We don't assert pixel heights (layout-dependent and brittle);
    // we just verify the flag is accepted and the widget still renders
    // the family name in both modes.
    testWidgets('builds without throwing with compact: true',
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
                    compact: true,
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
          reason: 'HeroSection must still render the family name in '
              'compact mode.');
    });

    testWidgets('builds without throwing with compact: false (default)',
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
      await tester.pump();

      expect(find.text('Test Family'), findsOneWidget);
    });
  });

  group('MiniFamilyGraphPreview — card chrome renders while loading', () {
    // The preview watches familyGraphProvider + graphLayoutProvider,
    // which will be loading in a test environment without Supabase.
    // The card chrome (header label + footer action) should render
    // regardless of the data state.
    testWidgets(
        'renders "Family Graph" label and "View Full Graph →" action '
        'while data is loading', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ListView(
                children: const [
                  MiniFamilyGraphPreview(
                    familyId: 'test-fam',
                    familyName: 'Test Family',
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      // Pump once to start; don't pumpAndSettle because the graph
      // providers never resolve in the test environment.
      await tester.pump();

      expect(find.text('Family Graph'), findsOneWidget,
          reason: 'MiniFamilyGraphPreview card must show a "Family Graph" '
              'label in its header, even while the graph data is loading.');
      expect(find.text('View Full Graph →'), findsOneWidget,
          reason: 'MiniFamilyGraphPreview card must show a "View Full Graph →" '
              'action below the preview, even while the graph data is '
              'loading.');
    });
  });
}

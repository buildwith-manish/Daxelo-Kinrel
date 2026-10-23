// test/features/family/feature_registry_highlights_test.dart
//
// Phase 6 widget test — verifies that HighlightsRow renders the
// Phase 4 lean-ON tile set under the default registry config (no
// debug overrides, no Remote Config).
//
// Expected visible tile count: 3 (Memories + Activity + Oral History).
// Achievements + Lists tiles are gated OFF per Phase 4 lean defaults
// and must NOT render.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kinrel/core/features/feature_registry.dart';
import 'package:kinrel/features/family/presentation/premium/family_hub_highlights.dart';

void main() {
  group('Phase 6 — HighlightsRow under Phase 4 lean defaults', () {
    testWidgets(
      'renders exactly the lean-ON tiles (Memories, Activity, Oral History)',
      (tester) async {
        // Build HighlightsRow inside a ProviderScope + MaterialApp so
        // ConsumerWidget can read featureProvider.
        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: HighlightsRow(familyId: 'fam-test'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify each expected tile label appears in the tree.
        final expectedLabels = <String>['Memories', 'Activity', 'Oral History'];
        for (final label in expectedLabels) {
          expect(
            find.text(label),
            findsOneWidget,
            reason: 'Lean-ON tile "$label" should render',
          );
        }

        // Verify each OFF tile is NOT rendered.
        final offLabels = <String>['Achievements', 'Lists'];
        for (final label in offLabels) {
          expect(
            find.text(label),
            findsNothing,
            reason: 'Lean-OFF tile "$label" should NOT render',
          );
        }
      },
    );

    testWidgets(
      'renders only 3 _HighlightCircle widgets under lean defaults',
      (tester) async {
        // Sanity: count the actual _HighlightCircle widgets in the tree.
        // Phase 4 lean ON set for HighlightsRow: Memories, Activity,
        // Oral History = 3 tiles.
        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: HighlightsRow(familyId: 'fam-test'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // _HighlightCircle renders a 64x64 circular Container. We can't
        // grep for the private type, but the 64x64 circular Containers
        // count is the same as the visible tile count.
        final circleFinder = find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.constraints?.maxWidth == 64.0 ||
              (w is Container && (w.decoration is BoxDecoration)),
        );
        // Just sanity-check we have at least 3 tiles rendered, and no
        // Achievements/Lists text — that's the contract.
        expect(find.text('Memories'), findsOneWidget);
        expect(find.text('Activity'), findsOneWidget);
        expect(find.text('Oral History'), findsOneWidget);
        expect(circleFinder, findsNWidgets(3));
      },
    );
  });

  group('Phase 6 — HighlightsRow debug override reveals hidden tile', () {
    testWidgets(
      'flipping achievements ON via debug override adds the Achievements tile',
      (tester) async {
        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: HighlightsRow(familyId: 'fam-test'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Baseline: Achievements tile NOT rendered.
        expect(find.text('Achievements'), findsNothing);

        // Flip the achievements feature ON via debug override.
        // (kDebugMode is true in test runs.)
        await Features.setDebugOverride(AppFeature.achievements, true);

        // Rebuild + settle so featureProvider picks up the override.
        await tester.pumpAndSettle();

        // Now Achievements tile SHOULD render.
        expect(
          find.text('Achievements'),
          findsOneWidget,
          reason:
              'After debug-overriding achievements ON, the Achievements '
              'tile should render',
        );

        // Restore.
        await Features.clearDebugOverride(AppFeature.achievements);
        await tester.pumpAndSettle();
        expect(find.text('Achievements'), findsNothing);
      },
      skip: !kDebugMode,
    );
  });
}

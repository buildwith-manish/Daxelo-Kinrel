// test/features/kinrel_intelligence/kinrel_share_card_test.dart
//
// Phase 18 — Kinrel share card tests.
//
// Verifies the share card widget renders without throwing and that the
// captureAndShare helper handles the "render object not yet laid out"
// case gracefully (returns false instead of throwing).
//
// Note: A full PNG-capture test would require a live Skia canvas, which
// is not available in `flutter test` without a real rendering surface.
// We verify the early-exit path instead — that's the path most likely
// to break in CI.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kinrel/features/kinrel_intelligence/data/kinrel_model.dart';
import 'package:kinrel/features/kinrel_intelligence/widgets/kinrel_share_card.dart';

KinrelModel _aura() => KinrelModel(
      familyId: 'fam-test',
      symbol: const KinrelSymbolParameters(
        ringCount: 3,
        spokeCount: 6,
        innerPatternType: KinrelInnerPattern.lotus,
        outerRingRadiusPct: 0.8,
        patternComplexity: 4,
        primaryColorHex: '#C8853A',
        secondaryColorHex: '#6B3FA0',
        accentColorHex: '#2D8A4E',
        pulseSpeedMs: 3000,
      ),
      archetype: const KinrelArchetype(
        key: ArchetypeType.banyan,
        confidence: 0.85,
      ),
      metrics: const KinrelMetrics(
        memberCount: 12,
        generationDepth: 3,
        edgeCount: 18,
        clusteringCoefficient: 0.55,
        graphDiameter: 4,
        avgDegree: 3.0,
        distinctLineages: 2,
        languageDistribution: {'hi': 0.7, 'en': 0.3},
        maxBetweennessNode: 'p1',
        rootNode: 'p1',
      ),
      computedAt: DateTime.parse('2026-07-08T10:00:00Z'),
      updatedAt: DateTime.parse('2026-07-08T10:00:00Z'),
    );

void main() {
  group('KinrelShareCard', () {
    testWidgets('renders without throwing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KinrelShareCard(
              boundaryKey: GlobalKey(),
              kinrel: _aura(),
              familyName: 'Sharma Family',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Family name should appear inside the card.
      expect(find.text('Sharma Family'), findsOneWidget);
      // Archetype name should appear.
      expect(find.text('The Banyan'), findsOneWidget);
      // Branding text should appear.
      expect(find.text('Made with love by Daxelo'), findsOneWidget);
    });

    testWidgets('captureAndShare returns false when boundary has no render object',
        (tester) async {
      // Build a card with a GlobalKey that is NEVER attached to a
      // RepaintBoundary, so findRenderObject() returns null.
      final unattachedKey = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KinrelShareCard(
              boundaryKey: unattachedKey,
              kinrel: _aura(),
              familyName: 'Test',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The boundaryKey points at the KinrelShareCard's own context, but
      // captureAndShare expects the RenderRepaintBoundary. Since we
      // didn't wrap the card in an outer RepaintBoundary keyed by the
      // same GlobalKey, findRenderObject() will return a non-boundary
      // render object → cast fails → returns false.
      //
      // This is the expected behaviour: captureAndShare must not throw
      // when invoked from a context that isn't a real RepaintBoundary.
      final result = await KinrelShareCard.captureAndShare(
        boundaryKey: unattachedKey,
        familyName: 'Test',
      );
      expect(result, isFalse);
    });

    testWidgets('captureAndShare returns false for an unused GlobalKey',
        (tester) async {
      final unusedKey = GlobalKey();
      // Don't attach this key to anything in the tree.
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      );
      final result = await KinrelShareCard.captureAndShare(
        boundaryKey: unusedKey,
        familyName: 'Test',
      );
      expect(result, isFalse);
    });
  });
}

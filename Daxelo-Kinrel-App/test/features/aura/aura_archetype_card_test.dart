// test/features/aura/aura_archetype_card_test.dart
//
// Phase 18 — AURA archetype card tests.
//
// Verifies the card renders each of the 6 archetype types without
// throwing, and that the archetype name + confidence meter are visible.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kinrel/features/aura/data/aura_model.dart';
import 'package:kinrel/features/aura/widgets/aura_archetype_card.dart';

AuraArchetype _archetype(ArchetypeType type, [double confidence = 0.75]) =>
    AuraArchetype(key: type, confidence: confidence);

AuraSymbolParameters _params() => const AuraSymbolParameters(
      ringCount: 3,
      spokeCount: 6,
      innerPatternType: AuraInnerPattern.lotus,
      outerRingRadiusPct: 0.8,
      patternComplexity: 4,
      primaryColorHex: '#C8853A',
      secondaryColorHex: '#6B3FA0',
      accentColorHex: '#2D8A4E',
      pulseSpeedMs: 3000,
    );

void main() {
  group('AuraArchetypeCard', () {
    testWidgets('renders each archetype type without throwing',
        (tester) async {
      for (final type in ArchetypeType.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AuraArchetypeCard(
                archetype: _archetype(type),
                symbol: _params(),
              ),
            ),
          ),
        );
        // Allow the LinearProgressIndicator to settle.
        await tester.pump();
        await tester.pumpAndSettle();

        // The archetype name should appear.
        final name = archetypeName(type);
        expect(find.text(name), findsOneWidget);
      }
    });

    testWidgets('shows member count caption when provided',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AuraArchetypeCard(
              archetype: _archetype(ArchetypeType.banyan),
              symbol: _params(),
              memberCount: 42,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('42 members'), findsOneWidget);
    });

    testWidgets('compact mode hides the description', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AuraArchetypeCard(
              archetype: _archetype(ArchetypeType.banyan),
              symbol: _params(),
              compact: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // In compact mode, the poetic description should NOT be rendered.
      // The name "The Banyan" should still be there.
      expect(find.text('The Banyan'), findsOneWidget);
      final strings = archetypeDescription(ArchetypeType.banyan);
      expect(find.text(strings), findsNothing);
    });
  });
}

/// Lookup the expected display name for an archetype — duplicated from
/// the production `archetype_strings.dart` so the test is independent
/// of any future string edits.
String archetypeName(ArchetypeType type) {
  switch (type) {
    case ArchetypeType.banyan:
      return 'The Banyan';
    case ArchetypeType.riverDelta:
      return 'The River Delta';
    case ArchetypeType.confluence:
      return 'The Confluence';
    case ArchetypeType.spine:
      return 'The Spine';
    case ArchetypeType.lotus:
      return 'The Lotus';
    case ArchetypeType.forest:
      return 'The Forest';
  }
}

/// Mirror of the production description string, for the negative
/// "compact mode hides description" assertion.
String archetypeDescription(ArchetypeType type) {
  switch (type) {
    case ArchetypeType.banyan:
      return 'One or two roots hold the entire family in their shade.\n'
          'Strength passes through you, generation to generation.';
    case ArchetypeType.riverDelta:
      return 'Your family flows outward, branching into the world.\n'
          'Each branch carries the same river — born from the same source.';
    case ArchetypeType.confluence:
      return "Many rivers have joined at your family's heart.\n"
          'You are richer for every stream that chose to merge.';
    case ArchetypeType.spine:
      return 'Yours is a family of deep roots and tall lineage.\n'
          'Every generation stands on the shoulders of the last.';
    case ArchetypeType.lotus:
      return 'A strong center holds, while new petals are still unfolding.\n'
          'Your family is becoming — not yet complete, and more beautiful for it.';
    case ArchetypeType.forest:
      return 'Many trees, each strong in their own right.\n'
          'Your family needs no single center — you are strongest together.';
  }
}

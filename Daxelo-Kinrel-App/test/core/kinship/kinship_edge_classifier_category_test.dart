// test/core/kinship/kinship_edge_classifier_category_test.dart
//
// Regression test for the "correct colours for node is not working" bug.
//
// BUG:
//   family_graph.dart stores `PersonData.kinshipCategory` (a server-computed
//   *category* string like "aunt_uncle") as `GraphPersonData.relationshipKey`,
//   which GraphNode then passes to KinshipEdgeStyleResolver.styleFor() →
//   KinshipEdgeStyleResolver.styleFor() → KinshipEdgeClassifier.classify().
//
//   The classifier was originally designed for RAW kinship keys
//   (e.g. "father", "uncle", "paternal_uncle") and did NOT recognize
//   the snake_case category string "aunt_uncle". As a result, every
//   aunt/uncle node fell through to the `extended` fallback and was
//   rendered with slate gray (#64748B) instead of cyan (#06B6D4).
//
// FIX:
//   KinshipEdgeClassifier.classify() now has an explicit top-of-function
//   switch that recognizes all 11 server-computed category strings
//   (self, parent, spouse, sibling, child, grandparent, aunt_uncle,
//   cousin, in_law, extended, indirect) plus their hyphenated and
//   unseparated variants.
//
// This test verifies that EVERY category string resolves to its
// spec-correct KinshipEdgeCategory AND its spec-correct color.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/constants/brand_colors.dart';
import 'package:kinrel/core/kinship/kinship_edge_style.dart';

void main() {
  group('KinshipEdgeClassifier — server-computed category strings', () {
    // ─────────────────────────────────────────────────────────────────
    // The exact map used by getNodeColorsFromCategory() in
    // lib/shared/utils/node_colors.dart. The classifier MUST produce
    // the same color for each category string so that GraphNode's ring
    // color matches GraphNode's ring color category.
    // ─────────────────────────────────────────────────────────────────
    final categoryToExpectedColor = <String, Color>{
      'self': KinrelColors.nodeSelf, // Gold #FFC94A (v5.100)
      'parent': KinrelColors.nodeParent, // Blue #3B82F6
      'spouse': KinrelColors.nodeSpouse, // Orange #F97316
      'sibling': KinrelColors.nodeSibling, // Purple #8B5CF6
      'child': KinrelColors.nodeChild, // Pink #EC4899
      'grandparent': KinrelColors.nodeGrandparent, // Indigo #6366F1
      'aunt_uncle': KinrelColors.nodeAuntUncle, // Cyan #06B6D4
      'cousin': KinrelColors.nodeCousin, // Emerald #10B981
      'in_law': KinrelColors.nodeInLaw, // Amber #F59E0B
      'extended': KinrelColors.nodeExtended, // Slate #64748B
    };

    test('1. Every snake_case category string classifies to the correct category', () {
      final expected = <String, KinshipEdgeCategory>{
        'self': KinshipEdgeCategory.self,
        'parent': KinshipEdgeCategory.parent,
        'spouse': KinshipEdgeCategory.spouse,
        'sibling': KinshipEdgeCategory.sibling,
        'child': KinshipEdgeCategory.child,
        'grandparent': KinshipEdgeCategory.grandparent,
        'aunt_uncle': KinshipEdgeCategory.auntUncle,
        'cousin': KinshipEdgeCategory.cousin,
        'in_law': KinshipEdgeCategory.inLaw,
        'extended': KinshipEdgeCategory.extended,
        'indirect': KinshipEdgeCategory.indirect,
      };

      for (final entry in expected.entries) {
        final categoryString = entry.key;
        final expectedCategory = entry.value;
        final actualCategory =
            KinshipEdgeClassifier.classify(categoryString);
        expect(actualCategory, equals(expectedCategory),
            reason:
                'Category string "$categoryString" must classify to $expectedCategory, '
                'got $actualCategory');
      }
    });

    test('2. Every category string resolves to the spec-correct color', () {
      for (final entry in categoryToExpectedColor.entries) {
        final categoryString = entry.key;
        final expectedColor = entry.value;
        final style = KinshipEdgeStyleResolver.styleFor(categoryString);
        expect(style.color, equals(expectedColor),
            reason:
                'Category string "$categoryString" must resolve to color '
                '${expectedColor.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}, '
                'got ${style.color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}');
      }
    });

    test('3. Aunt/Uncle category strings get CYAN, not slate gray (the bug)', () {
      // This is the exact regression for the reported bug.
      // Before the fix, "aunt_uncle" fell through to the extended
      // fallback and returned slate gray (#64748B).
      for (final key in ['aunt_uncle', 'aunt-uncle', 'auntuncle']) {
        final style = KinshipEdgeStyleResolver.styleFor(key);
        expect(style.color, equals(KinshipEdgeColors.auntUncle),
            reason: 'Key "$key" must be cyan #06B6D4, not slate gray');
        expect(style.color, isNot(equals(KinshipEdgeColors.extended)),
            reason: 'Key "$key" must NOT fall through to extended');
      }
    });

    test('4. In-Law category strings get AMBER (regression for in_law)', () {
      for (final key in ['in_law', 'in-law', 'inlaw']) {
        final style = KinshipEdgeStyleResolver.styleFor(key);
        expect(style.color, equals(KinshipEdgeColors.inLaw),
            reason: 'Key "$key" must be amber #F59E0B');
      }
    });

    test('5. Indirect category string (no suffix) classifies correctly', () {
      // Before the fix, "indirect" (without _connection suffix) fell
      // through to extended. Now it resolves to indirect.
      expect(KinshipEdgeClassifier.classify('indirect'),
          equals(KinshipEdgeCategory.indirect));
      // And the original compound form still works.
      expect(KinshipEdgeClassifier.classify('indirect_connection'),
          equals(KinshipEdgeCategory.indirect));
      expect(KinshipEdgeClassifier.classify('indirect_father'),
          equals(KinshipEdgeCategory.indirect));
    });

    test('6. Category-string classification is case-insensitive', () {
      // The classifier lowercases + trims the input. Verify that
      // mixed-case category strings also resolve correctly.
      expect(KinshipEdgeClassifier.classify('Aunt_Uncle'),
          equals(KinshipEdgeCategory.auntUncle));
      expect(KinshipEdgeClassifier.classify('AUNT_UNCLE'),
          equals(KinshipEdgeCategory.auntUncle));
      expect(KinshipEdgeClassifier.classify('  aunt_uncle  '),
          equals(KinshipEdgeCategory.auntUncle));
      expect(KinshipEdgeClassifier.classify('In_Law'),
          equals(KinshipEdgeCategory.inLaw));
    });

    test('7. Raw kinship keys STILL classify correctly (no regression)', () {
      // The category-string block must not break the existing raw-key
      // classification path. Spot-check representative raw keys from
      // each category.
      final rawKeyChecks = <String, KinshipEdgeCategory>{
        // Raw parent keys
        'father': KinshipEdgeCategory.parent,
        'mother': KinshipEdgeCategory.parent,
        // Raw child keys
        'son': KinshipEdgeCategory.child,
        'daughter': KinshipEdgeCategory.child,
        // Raw sibling keys
        'brother': KinshipEdgeCategory.sibling,
        'sister': KinshipEdgeCategory.sibling,
        'elder_brother': KinshipEdgeCategory.sibling,
        'half_sister': KinshipEdgeCategory.sibling,
        // Raw spouse keys
        'husband': KinshipEdgeCategory.spouse,
        'wife': KinshipEdgeCategory.spouse,
        // Raw grandparent keys
        'grandfather': KinshipEdgeCategory.grandparent,
        'paternal_grandmother': KinshipEdgeCategory.grandparent,
        'maternal_grandfather': KinshipEdgeCategory.grandparent,
        // Raw aunt/uncle keys
        'uncle': KinshipEdgeCategory.auntUncle,
        'aunt': KinshipEdgeCategory.auntUncle,
        'paternal_uncle': KinshipEdgeCategory.auntUncle,
        'maternal_aunt': KinshipEdgeCategory.auntUncle,
        'fathers_elder_brother': KinshipEdgeCategory.auntUncle,
        'mothers_sister': KinshipEdgeCategory.auntUncle,
        'fathers_sisters_husband': KinshipEdgeCategory.auntUncle,
        // Raw cousin keys
        'cousin': KinshipEdgeCategory.cousin,
        'brothers_son': KinshipEdgeCategory.cousin,
        'sisters_daughter': KinshipEdgeCategory.cousin,
        // Raw in-law keys
        'father_in_law': KinshipEdgeCategory.inLaw,
        'mother_in_law': KinshipEdgeCategory.inLaw,
        'husbands_father': KinshipEdgeCategory.inLaw,
        'wifes_mother': KinshipEdgeCategory.inLaw,
        // Raw extended keys
        'step_father': KinshipEdgeCategory.extended,
        'godfather': KinshipEdgeCategory.extended,
        // Indirect compound
        'indirect_connection': KinshipEdgeCategory.indirect,
      };

      for (final entry in rawKeyChecks.entries) {
        final rawKey = entry.key;
        final expectedCategory = entry.value;
        final actualCategory = KinshipEdgeClassifier.classify(rawKey);
        expect(actualCategory, equals(expectedCategory),
            reason:
                'Raw kinship key "$rawKey" must still classify to $expectedCategory '
                'after adding the category-string block. Got $actualCategory.');
      }
    });

    test('8. Empty / null-like inputs are safe', () {
      expect(KinshipEdgeClassifier.classify(''),
          equals(KinshipEdgeCategory.extended));
      expect(KinshipEdgeClassifier.classify('   '),
          equals(KinshipEdgeCategory.extended));
    });

    test('9. Node ring color matches the spec for every category', () {
      // End-to-end: simulate what GraphNode._borderColor does.
      // GraphNode calls KinshipEdgeStyleResolver.styleFor(key), which
      // delegates to KinshipEdgeStyleResolver.styleFor(key).color.
      // This test verifies the full chain produces the spec color.
      for (final entry in categoryToExpectedColor.entries) {
        final categoryString = entry.key;
        final expectedColor = entry.value;

        // Mirror KinshipEdgeStyleResolver.styleFor() exactly.
        final style = KinshipEdgeStyleResolver.styleFor(categoryString);
        final resolvedColor = style.color;

        expect(resolvedColor, equals(expectedColor),
            reason:
                'GraphNode ring color for "$categoryString" must be the spec color. '
                'Expected ${expectedColor.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}, '
                'got ${resolvedColor.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}.');
      }
    });
  });
}

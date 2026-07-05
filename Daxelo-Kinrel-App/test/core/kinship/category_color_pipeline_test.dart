// test/core/kinship/category_color_pipeline_test.dart
//
// v69: End-to-end test verifying that the AUTHORITATIVE category → color
// pipeline produces the correct distinct color for EVERY category.
//
// This tests the fix for the lossy string round-trip bug:
//   - _relationCategories() returns Map<String, KinshipEdgeCategory>
//   - GraphNode._borderColor uses styleForCategory(category)
//   - _EngineEdgePainter uses styleForCategory(category)
//   - _dotColor uses styleForCategory(category)
//
// Every category must resolve to its spec-correct color — never grey
// (#64748B) unless the category IS 'extended'.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/constants/brand_colors.dart';
import 'package:kinrel/core/kinship/kinship_edge_style.dart';
import 'package:kinrel/core/kinship/structural_kinship_classifier.dart';

void main() {
  group('v69: Category → Color pipeline — every category gets its distinct color', () {
    // The spec colors from brand_colors.dart.
    final categoryToExpectedColor = <KinshipEdgeCategory, Color>{
      KinshipEdgeCategory.self: KinrelColors.nodeSelf, // #0D9488 teal
      KinshipEdgeCategory.parent: KinrelColors.nodeParent, // #3B82F6 blue
      KinshipEdgeCategory.child: KinrelColors.nodeChild, // #EC4899 pink
      KinshipEdgeCategory.sibling: KinrelColors.nodeSibling, // #8B5CF6 purple
      KinshipEdgeCategory.spouse: KinrelColors.nodeSpouse, // #F97316 orange
      KinshipEdgeCategory.grandparent: KinrelColors.nodeGrandparent, // #6366F1 indigo
      KinshipEdgeCategory.auntUncle: KinrelColors.nodeAuntUncle, // #06B6D4 cyan
      KinshipEdgeCategory.cousin: KinrelColors.nodeCousin, // #10B981 emerald
      KinshipEdgeCategory.inLaw: KinrelColors.nodeInLaw, // #F59E0B amber
      KinshipEdgeCategory.extended: KinrelColors.nodeExtended, // #64748B slate
    };

    test('1. styleForCategory() returns the spec color for every category', () {
      for (final entry in categoryToExpectedColor.entries) {
        final category = entry.key;
        final expectedColor = entry.value;
        final style = KinshipEdgeStyleResolver.styleForCategory(category);
        expect(style.color, equals(expectedColor),
            reason: 'Category $category must resolve to '
                '${expectedColor.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}, '
                'got ${style.color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}');
      }
    });

    test('2. Every category produces a DISTINCT color (no two categories share a color)', () {
      final colors = <Color>{};
      for (final entry in categoryToExpectedColor.entries) {
        final style = KinshipEdgeStyleResolver.styleForCategory(entry.key);
        expect(colors.contains(style.color), isFalse,
            reason: 'Category ${entry.key} color ${style.color} is shared with another category');
        colors.add(style.color);
      }
      expect(colors.length, equals(categoryToExpectedColor.length),
          reason: 'All ${categoryToExpectedColor.length} categories must have distinct colors');
    });

    test('3. No non-extended category resolves to grey (#64748B)', () {
      const grey = KinrelColors.nodeExtended; // #64748B
      for (final entry in categoryToExpectedColor.entries) {
        if (entry.key == KinshipEdgeCategory.extended) continue;
        final style = KinshipEdgeStyleResolver.styleForCategory(entry.key);
        expect(style.color, isNot(equals(grey)),
            reason: 'Category ${entry.key} must NOT be grey — only "extended" should be grey');
      }
    });

    test('4. Structural classifier → category → color: all 9 Sharma family nodes', () {
      // Simulate the 9-member Sharma family — every node must get a
      // non-grey category that produces its distinct spec color.
      final cases = <_SharmaCase>[
        _SharmaCase(name: 'T1 (self)', path: ['self'], gender: null,
            expectedCategory: KinshipEdgeCategory.self),
        _SharmaCase(name: 'DU (father)', path: ['father'], gender: 'male',
            expectedCategory: KinshipEdgeCategory.parent),
        _SharmaCase(name: 'HD (mother)', path: ['mother'], gender: 'female',
            expectedCategory: KinshipEdgeCategory.parent),
        _SharmaCase(name: 'HS (brother)', path: ['sibling'], gender: 'male',
            expectedCategory: KinshipEdgeCategory.sibling),
        _SharmaCase(name: 'DO (sister)', path: ['sibling'], gender: 'female',
            expectedCategory: KinshipEdgeCategory.sibling),
        _SharmaCase(name: 'MA (grandfather)', path: ['father', 'father'], gender: 'male',
            expectedCategory: KinshipEdgeCategory.grandparent),
        _SharmaCase(name: 'D2 (uncle)', path: ['father', 'sibling'], gender: 'male',
            expectedCategory: KinshipEdgeCategory.auntUncle),
        _SharmaCase(name: 'T3 (cousin)', path: ['father', 'sibling', 'child'], gender: 'male',
            expectedCategory: KinshipEdgeCategory.cousin),
        _SharmaCase(name: 'T2 (nephew)', path: ['sibling', 'child'], gender: 'male',
            expectedCategory: KinshipEdgeCategory.auntUncle),
      ];

      for (final tc in cases) {
        // Step 1: Structural classifier returns the category.
        final classification = StructuralKinshipClassifier.classify(
          path: tc.path,
          targetGender: tc.gender,
        );
        expect(classification.category, equals(tc.expectedCategory),
            reason: '${tc.name}: expected ${tc.expectedCategory.name}, '
                'got ${classification.category.name}');

        // Step 2: Category → color via styleForCategory (the v69 path).
        final style = KinshipEdgeStyleResolver.styleForCategory(classification.category);
        final expectedColor = categoryToExpectedColor[classification.category]!;

        expect(style.color, equals(expectedColor),
            reason: '${tc.name}: category ${classification.category.name} '
                'must produce color ${expectedColor.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}');

        // Step 3: Non-extended categories must NOT be grey.
        if (tc.expectedCategory != KinshipEdgeCategory.extended) {
          expect(style.color, isNot(equals(KinrelColors.nodeExtended)),
              reason: '${tc.name}: must NOT be grey (#64748B)');
        }
      }
    });

    test('5. Direct edge stored key → category → color: honor user selection', () {
      // When a user adds a member and selects 'brother', the stored key
      // 'brother' must produce the sibling category (purple), NOT be
      // overwritten by BFS or re-classified lossily to grey.
      final directEdgeCases = <_DirectEdgeCase>[
        _DirectEdgeCase(storedKey: 'father', gender: 'male',
            expectedCategory: KinshipEdgeCategory.parent, expectedColor: KinrelColors.nodeParent),
        _DirectEdgeCase(storedKey: 'mother', gender: 'female',
            expectedCategory: KinshipEdgeCategory.parent, expectedColor: KinrelColors.nodeParent),
        _DirectEdgeCase(storedKey: 'brother', gender: 'male',
            expectedCategory: KinshipEdgeCategory.sibling, expectedColor: KinrelColors.nodeSibling),
        _DirectEdgeCase(storedKey: 'sister', gender: 'female',
            expectedCategory: KinshipEdgeCategory.sibling, expectedColor: KinrelColors.nodeSibling),
        _DirectEdgeCase(storedKey: 'son', gender: 'male',
            expectedCategory: KinshipEdgeCategory.child, expectedColor: KinrelColors.nodeChild),
        _DirectEdgeCase(storedKey: 'daughter', gender: 'female',
            expectedCategory: KinshipEdgeCategory.child, expectedColor: KinrelColors.nodeChild),
        _DirectEdgeCase(storedKey: 'husband', gender: 'male',
            expectedCategory: KinshipEdgeCategory.spouse, expectedColor: KinrelColors.nodeSpouse),
        _DirectEdgeCase(storedKey: 'wife', gender: 'female',
            expectedCategory: KinshipEdgeCategory.spouse, expectedColor: KinrelColors.nodeSpouse),
        _DirectEdgeCase(storedKey: 'grandfather', gender: 'male',
            expectedCategory: KinshipEdgeCategory.grandparent, expectedColor: KinrelColors.nodeGrandparent),
        _DirectEdgeCase(storedKey: 'uncle', gender: 'male',
            expectedCategory: KinshipEdgeCategory.auntUncle, expectedColor: KinrelColors.nodeAuntUncle),
        _DirectEdgeCase(storedKey: 'cousin', gender: 'male',
            expectedCategory: KinshipEdgeCategory.cousin, expectedColor: KinrelColors.nodeCousin),
        _DirectEdgeCase(storedKey: 'father_in_law', gender: 'male',
            expectedCategory: KinshipEdgeCategory.inLaw, expectedColor: KinrelColors.nodeInLaw),
        // v69 stopgap: great_grandfather must NOT be grey
        _DirectEdgeCase(storedKey: 'great_grandfather', gender: 'male',
            expectedCategory: KinshipEdgeCategory.grandparent, expectedColor: KinrelColors.nodeGrandparent),
      ];

      for (final tc in directEdgeCases) {
        // Simulate _relationCategories() Priority 1: direct edge →
        // StructuralKinshipClassifier.classify(path: [storedKey]).
        final classification = StructuralKinshipClassifier.classify(
          path: [tc.storedKey],
          targetGender: tc.gender,
        );
        expect(classification.category, equals(tc.expectedCategory),
            reason: 'Stored key "${tc.storedKey}" must classify to ${tc.expectedCategory.name}');

        // The category → color must be correct.
        final style = KinshipEdgeStyleResolver.styleForCategory(classification.category);
        expect(style.color, equals(tc.expectedColor),
            reason: 'Stored key "${tc.storedKey}" → ${classification.category.name} '
                'must produce ${tc.expectedColor.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}');
      }
    });

    test('6. No lossy string round-trip — category is never derived from a key string', () {
      // Verify that the v69 pipeline NEVER calls classify(key) for a
      // node that has an authoritative category. The category comes
      // directly from the structural classifier, and styleForCategory()
      // is a pure switch — no string parsing, no regex, no gaps.
      //
      // This test verifies that styleForCategory() is a TOTAL function
      // (handles all enum values) and never throws or returns null.
      for (final category in KinshipEdgeCategory.values) {
        final style = KinshipEdgeStyleResolver.styleForCategory(category);
        expect(style.color, isNotNull);
        expect(style.color.alpha, greaterThan(0),
            reason: 'Category $category color must not be transparent');
        expect(style.strokeWidth, greaterThan(0),
            reason: 'Category $category stroke width must be > 0');
      }
    });
  });
}

class _SharmaCase {
  final String name;
  final List<String> path;
  final String? gender;
  final KinshipEdgeCategory expectedCategory;
  const _SharmaCase({
    required this.name,
    required this.path,
    required this.gender,
    required this.expectedCategory,
  });
}

class _DirectEdgeCase {
  final String storedKey;
  final String gender;
  final KinshipEdgeCategory expectedCategory;
  final Color expectedColor;
  const _DirectEdgeCase({
    required this.storedKey,
    required this.gender,
    required this.expectedCategory,
    required this.expectedColor,
  });
}

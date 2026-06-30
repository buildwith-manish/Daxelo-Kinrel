// test/core/kinship/structural_kinship_classifier_test.dart
//
// v66: Regression test for the structural kinship classifier.
//
// Verifies that EVERY relationship path resolves to a non-null
// StructuralClassification with the correct KinshipEdgeCategory.
// This is the fix for the bug where 6 of 9 nodes in the Sharma family
// had no label and rendered grey because the kinship chain rules
// only cover ~26 base keys and fail for most multi-hop BFS paths.
//
// TEST STRUCTURE:
//   1. Single-step paths (all 8 categories + spouse)
//   2. Multi-step paths (grandparent, aunt/uncle, cousin, niece/nephew, in-law)
//   3. Full 9-member Sharma family simulation — ALL 9 nodes must resolve
//   4. Second structurally different family — ALL nodes must resolve

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/kinship/kinship_edge_style.dart';
import 'package:kinrel/core/kinship/structural_kinship_classifier.dart';

void main() {
  group('StructuralKinshipClassifier — single-step paths', () {
    test('self → self category', () {
      final r = StructuralKinshipClassifier.classify(path: ['self']);
      expect(r.category, KinshipEdgeCategory.self);
      expect(r.label, 'You');
    });

    test('father → parent category, blue', () {
      final r = StructuralKinshipClassifier.classify(
        path: ['father'],
        targetGender: 'male',
      );
      expect(r.category, KinshipEdgeCategory.parent);
      expect(r.label, 'Father');
    });

    test('mother → parent category, blue', () {
      final r = StructuralKinshipClassifier.classify(
        path: ['mother'],
        targetGender: 'female',
      );
      expect(r.category, KinshipEdgeCategory.parent);
      expect(r.label, 'Mother');
    });

    test('son → child category, pink', () {
      final r = StructuralKinshipClassifier.classify(
        path: ['son'],
        targetGender: 'male',
      );
      expect(r.category, KinshipEdgeCategory.child);
      expect(r.label, 'Son');
    });

    test('daughter → child category, pink', () {
      final r = StructuralKinshipClassifier.classify(
        path: ['daughter'],
        targetGender: 'female',
      );
      expect(r.category, KinshipEdgeCategory.child);
      expect(r.label, 'Daughter');
    });

    test('brother → sibling category, purple', () {
      final r = StructuralKinshipClassifier.classify(
        path: ['brother'],
        targetGender: 'male',
      );
      expect(r.category, KinshipEdgeCategory.sibling);
      expect(r.label, 'Brother');
    });

    test('sister → sibling category, purple', () {
      final r = StructuralKinshipClassifier.classify(
        path: ['sister'],
        targetGender: 'female',
      );
      expect(r.category, KinshipEdgeCategory.sibling);
      expect(r.label, 'Sister');
    });

    test('husband → spouse category, orange', () {
      final r = StructuralKinshipClassifier.classify(
        path: ['husband'],
        targetGender: 'male',
      );
      expect(r.category, KinshipEdgeCategory.spouse);
      expect(r.label, 'Husband');
    });

    test('wife → spouse category, orange', () {
      final r = StructuralKinshipClassifier.classify(
        path: ['wife'],
        targetGender: 'female',
      );
      expect(r.category, KinshipEdgeCategory.spouse);
      expect(r.label, 'Wife');
    });
  });

  group('StructuralKinshipClassifier — multi-step paths', () {
    test('father + father → grandparent (indigo)', () {
      // T1's grandfather: path is [father, father]
      final r = StructuralKinshipClassifier.classify(
        path: ['father', 'father'],
        targetGender: 'male',
      );
      expect(r.category, KinshipEdgeCategory.grandparent);
      expect(r.label, 'Grandfather');
    });

    test('father + brother → auntUncle (cyan)', () {
      // T1's uncle (father's brother): path is [father, brother]
      final r = StructuralKinshipClassifier.classify(
        path: ['father', 'brother'],
        targetGender: 'male',
      );
      expect(r.category, KinshipEdgeCategory.auntUncle);
      expect(r.label, 'Uncle');
    });

    test('father + sister → auntUncle (cyan)', () {
      final r = StructuralKinshipClassifier.classify(
        path: ['father', 'sister'],
        targetGender: 'female',
      );
      expect(r.category, KinshipEdgeCategory.auntUncle);
      expect(r.label, 'Aunt');
    });

    test('father + brother + son → cousin (emerald)', () {
      // T1's cousin (father's brother's son): path is [father, brother, son]
      final r = StructuralKinshipClassifier.classify(
        path: ['father', 'brother', 'son'],
        targetGender: 'male',
      );
      expect(r.category, KinshipEdgeCategory.cousin);
      expect(r.label, 'Cousin');
    });

    test('brother + son → niece/nephew (auntUncle color)', () {
      // T1's nephew (brother's son): path is [brother, son]
      final r = StructuralKinshipClassifier.classify(
        path: ['brother', 'son'],
        targetGender: 'male',
      );
      expect(r.category, KinshipEdgeCategory.auntUncle);
      expect(r.label, 'Nephew');
    });

    test('wife + father → father-in-law (amber)', () {
      // T1's father-in-law (wife's father): path is [wife, father]
      final r = StructuralKinshipClassifier.classify(
        path: ['wife', 'father'],
        targetGender: 'male',
      );
      expect(r.category, KinshipEdgeCategory.inLaw);
      expect(r.label, 'Father-in-law');
    });

    test('wife + brother → brother-in-law (amber)', () {
      final r = StructuralKinshipClassifier.classify(
        path: ['wife', 'brother'],
        targetGender: 'male',
      );
      expect(r.category, KinshipEdgeCategory.inLaw);
      expect(r.label, 'Brother-in-law');
    });

    test('son + son → grandchild (grandparent color)', () {
      // T1's grandson: path is [son, son]
      final r = StructuralKinshipClassifier.classify(
        path: ['son', 'son'],
        targetGender: 'male',
      );
      expect(r.category, KinshipEdgeCategory.grandparent);
      expect(r.label, 'Grandson');
    });

    test('empty path → extended fallback (never null)', () {
      final r = StructuralKinshipClassifier.classify(path: []);
      expect(r.category, KinshipEdgeCategory.extended);
      expect(r.label, 'Unknown');
    });
  });

  group('Sharma family — 9 members, ALL must resolve (v66)', () {
    // Simulates the reported bug: 9-member family where only 2 of 9
    // nodes got a label + color. The fix must resolve ALL 9.
    //
    // Family structure (from the user's report):
    //   T1 = self (anchor)
    //   DU = Father (direct edge: DU→T1 'father')
    //   HD = Mother/spouse (direct edge)
    //   HS = sibling (edge: HS→T1 'brother' or T1→HS 'brother')
    //   DO = sibling
    //   MA = grandparent (T1→DU→grandparent)
    //   D2 = aunt/uncle (T1→DU→D2)
    //   T3 = cousin (T1→DU→D2→T3)
    //   T2 = niece/nephew (T1→HS→T2)
    //
    // We test the structural classifier directly with the BFS path
    // types that the RelationshipEngine would produce.

    test('T1 (self) → self category', () {
      final r = StructuralKinshipClassifier.classify(path: ['self']);
      expect(r.category, KinshipEdgeCategory.self);
      expect(r.label, 'You');
    });

    test('DU (father) → parent category + "Father" label', () {
      final r = StructuralKinshipClassifier.classify(
        path: ['father'],
        targetGender: 'male',
      );
      expect(r.category, KinshipEdgeCategory.parent);
      expect(r.label, 'Father');
      expect(r.category, isNot(KinshipEdgeCategory.extended),
          reason: 'Must NOT be grey fallback');
    });

    test('HD (mother) → parent category + "Mother" label', () {
      final r = StructuralKinshipClassifier.classify(
        path: ['mother'],
        targetGender: 'female',
      );
      expect(r.category, KinshipEdgeCategory.parent);
      expect(r.label, 'Mother');
    });

    test('HS (brother) → sibling category + "Brother" label', () {
      // BFS may produce 'sibling' (inverse of 'brother') — classifier
      // must still resolve it.
      final r = StructuralKinshipClassifier.classify(
        path: ['sibling'],
        targetGender: 'male',
      );
      expect(r.category, KinshipEdgeCategory.sibling);
      expect(r.label, 'Brother');
      expect(r.category, isNot(KinshipEdgeCategory.extended));
    });

    test('DO (sister) → sibling category + "Sister" label', () {
      final r = StructuralKinshipClassifier.classify(
        path: ['sibling'],
        targetGender: 'female',
      );
      expect(r.category, KinshipEdgeCategory.sibling);
      expect(r.label, 'Sister');
    });

    test('MA (grandfather) → grandparent category + "Grandfather" label', () {
      // Path: T1 → father (DU) → father (MA) = [father, father]
      final r = StructuralKinshipClassifier.classify(
        path: ['father', 'father'],
        targetGender: 'male',
      );
      expect(r.category, KinshipEdgeCategory.grandparent);
      expect(r.label, 'Grandfather');
      expect(r.category, isNot(KinshipEdgeCategory.extended),
          reason: 'Grandparent must NOT be grey — this was the bug');
    });

    test('D2 (uncle) → auntUncle category + "Uncle" label', () {
      // Path: T1 → father (DU) → brother (D2) = [father, brother]
      // But BFS may produce [father, sibling] (inverse of brother)
      final r = StructuralKinshipClassifier.classify(
        path: ['father', 'sibling'],
        targetGender: 'male',
      );
      expect(r.category, KinshipEdgeCategory.auntUncle);
      expect(r.label, 'Uncle');
      expect(r.category, isNot(KinshipEdgeCategory.extended),
          reason: 'Uncle must NOT be grey — this was the bug');
    });

    test('T3 (cousin) → cousin category + "Cousin" label', () {
      // Path: T1 → father (DU) → brother (D2) → son (T3)
      // BFS may produce [father, sibling, child]
      final r = StructuralKinshipClassifier.classify(
        path: ['father', 'sibling', 'child'],
        targetGender: 'male',
      );
      expect(r.category, KinshipEdgeCategory.cousin);
      expect(r.label, 'Cousin');
      expect(r.category, isNot(KinshipEdgeCategory.extended),
          reason: 'Cousin must NOT be grey — this was the bug');
    });

    test('T2 (nephew) → auntUncle category + "Nephew" label', () {
      // Path: T1 → brother (HS) → son (T2)
      // BFS may produce [sibling, child]
      final r = StructuralKinshipClassifier.classify(
        path: ['sibling', 'child'],
        targetGender: 'male',
      );
      expect(r.category, KinshipEdgeCategory.auntUncle);
      expect(r.label, 'Nephew');
      expect(r.category, isNot(KinshipEdgeCategory.extended),
          reason: 'Nephew must NOT be grey — this was the bug');
    });

    test('ALL 9 Sharma nodes resolve to a non-extended category', () {
      // Aggregate check — every node gets a classification, and only
      // genuinely unknown paths route to extended.
      final paths = <List<String>>[
        ['self'],                          // T1
        ['father'],                        // DU
        ['mother'],                        // HD
        ['sibling'],                       // HS
        ['sibling'],                       // DO
        ['father', 'father'],              // MA
        ['father', 'sibling'],             // D2
        ['father', 'sibling', 'child'],    // T3
        ['sibling', 'child'],              // T2
      ];
      final genders = <String?>[
        null,    // T1 (self)
        'male',  // DU
        'female',// HD
        'male',  // HS
        'female',// DO
        'male',  // MA
        'male',  // D2
        'male',  // T3
        'male',  // T2
      ];

      for (int i = 0; i < paths.length; i++) {
        final r = StructuralKinshipClassifier.classify(
          path: paths[i],
          targetGender: genders[i],
        );
        expect(r.category, isNot(KinshipEdgeCategory.extended),
            reason: 'Sharma node $i (path=${paths[i]}) must NOT be grey');
        expect(r.label.isNotEmpty, isTrue,
            reason: 'Sharma node $i must have a non-empty label');
      }
    });
  });

  group('Second family — structurally different (v66)', () {
    // A different family structure to verify the fix is generic.
    // Family B: anchor + wife + 2 children + wife's parents (in-laws)
    test('wife → spouse category', () {
      final r = StructuralKinshipClassifier.classify(
        path: ['wife'],
        targetGender: 'female',
      );
      expect(r.category, KinshipEdgeCategory.spouse);
      expect(r.label, 'Wife');
    });

    test('son → child category', () {
      final r = StructuralKinshipClassifier.classify(
        path: ['son'],
        targetGender: 'male',
      );
      expect(r.category, KinshipEdgeCategory.child);
    });

    test('daughter → child category', () {
      final r = StructuralKinshipClassifier.classify(
        path: ['daughter'],
        targetGender: 'female',
      );
      expect(r.category, KinshipEdgeCategory.child);
    });

    test('wife + father → father-in-law (inLaw)', () {
      final r = StructuralKinshipClassifier.classify(
        path: ['wife', 'father'],
        targetGender: 'male',
      );
      expect(r.category, KinshipEdgeCategory.inLaw);
      expect(r.label, 'Father-in-law');
    });

    test('wife + mother → mother-in-law (inLaw)', () {
      final r = StructuralKinshipClassifier.classify(
        path: ['wife', 'mother'],
        targetGender: 'female',
      );
      expect(r.category, KinshipEdgeCategory.inLaw);
      expect(r.label, 'Mother-in-law');
    });

    test('son + son → grandson (grandparent color)', () {
      final r = StructuralKinshipClassifier.classify(
        path: ['son', 'son'],
        targetGender: 'male',
      );
      expect(r.category, KinshipEdgeCategory.grandparent);
      expect(r.label, 'Grandson');
    });

    test('son + daughter → granddaughter (grandparent color)', () {
      final r = StructuralKinshipClassifier.classify(
        path: ['son', 'daughter'],
        targetGender: 'female',
      );
      expect(r.category, KinshipEdgeCategory.grandparent);
      expect(r.label, 'Granddaughter');
    });

    test('ALL Family B nodes resolve to non-extended', () {
      final paths = <List<String>>[
        ['self'],              // anchor
        ['wife'],              // wife
        ['son'],               // son
        ['daughter'],          // daughter
        ['wife', 'father'],    // father-in-law
        ['wife', 'mother'],    // mother-in-law
        ['son', 'son'],        // grandson
      ];
      for (final path in paths) {
        final r = StructuralKinshipClassifier.classify(path: path);
        expect(r.category, isNot(KinshipEdgeCategory.extended),
            reason: 'Family B path $path must NOT be grey');
        expect(r.label.isNotEmpty, isTrue);
      }
    });
  });

  group('Edge cases — never silent grey', () {
    test('unknown single step → extended with label (not silent)', () {
      final r = StructuralKinshipClassifier.classify(
        path: ['some_unknown_type'],
      );
      expect(r.category, KinshipEdgeCategory.extended);
      expect(r.label.isNotEmpty, isTrue,
          reason: 'Even unknown paths must get a label, not silent grey');
    });

    test('long ambiguous path → extended with label (not silent)', () {
      final r = StructuralKinshipClassifier.classify(
        path: ['father', 'spouse', 'child', 'sibling'],
      );
      expect(r.category, anyOf(
        equals(KinshipEdgeCategory.extended),
        equals(KinshipEdgeCategory.inLaw),
      ));
      expect(r.label.isNotEmpty, isTrue,
          reason: 'Must have a label even for ambiguous paths');
    });
  });
}

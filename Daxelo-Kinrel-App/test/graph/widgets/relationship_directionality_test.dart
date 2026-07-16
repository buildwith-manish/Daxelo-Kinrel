// test/graph/widgets/relationship_directionality_test.dart
//
// v65 CRITICAL FIX: Regression test for the swapped-branch directionality
// bug in GraphRelationshipLabels.getRelationshipKey() and
// GraphRelationshipLabels.getRelationLabel().
//
// BUG:
//   The stored relationship `from: Rajesh, to: anchor, key: 'father'`
//   means "Rajesh IS the father OF the anchor". From the anchor's
//   perspective, Rajesh IS 'father' — the stored key already IS the
//   anchor's perspective. But the code was returning the INVERSE
//   ('son') because the two if-branches were swapped.
//
//   This caused EVERY non-self node to render with the wrong color:
//   fathers were pink (child), children were blue (parent), etc.
//
// FIX:
//   - Edge points TO anchor (`to == anchor`): return stored key DIRECTLY
//   - Edge points FROM anchor (`from == anchor`): return INVERSE key
//
// This test verifies the fix works for BOTH edge directions and for
// ALL common relationship types, with ANY family structure.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/kinship/kinship_edge_style.dart';
import 'package:kinrel/graph/data/graph_data_models.dart';
import 'package:kinrel/graph/widgets/graph_relationship_labels.dart';

/// Helper: build a GraphPersonData with sensible defaults.
GraphPersonData _person(String id, {bool isAnchor = false, String? gender}) =>
    GraphPersonData(
      id: id,
      name: id,
      gender: gender,
      isAnchor: isAnchor,
    );

/// Helper: build a GraphEdgeData.
GraphEdgeData _edge(String from, String to, String key) =>
    GraphEdgeData(
      id: '${from}_$to',
      sourceId: from,
      targetId: to,
      relationshipKey: key,
    );

void main() {
  group('GraphRelationshipLabels.getRelationshipKey — directionality (v65 FIX)', () {
    // ───────────────────────────────────────────────────────────────
    // The anchor is always 'anchor'. The person under test is 'rel'.
    // We test BOTH edge directions for each relationship type:
    //   Direction A: from: rel, to: anchor, key: 'X' (rel IS the X of anchor)
    //   Direction B: from: anchor, to: rel, key: 'Y' (anchor IS the Y of rel)
    //
    // For Direction A, the anchor's perspective on 'rel' = 'X' (stored key).
    // For Direction B, the anchor's perspective on 'rel' = inverse('Y').
    // ───────────────────────────────────────────────────────────────

    final testCases = <_DirectionalityCase>[
      // Parent relationships
      _DirectionalityCase(
        name: 'father (edge TO anchor)',
        edge: _edge('rel', 'anchor', 'father'),
        expectedKey: 'father',
        expectedCategory: KinshipEdgeCategory.parent,
      ),
      _DirectionalityCase(
        name: 'mother (edge TO anchor)',
        edge: _edge('rel', 'anchor', 'mother'),
        expectedKey: 'mother',
        expectedCategory: KinshipEdgeCategory.parent,
      ),
      _DirectionalityCase(
        name: 'son (edge FROM anchor)',
        edge: _edge('anchor', 'rel', 'son'),
        expectedKey: 'father', // inverse of 'son'
        expectedCategory: KinshipEdgeCategory.parent,
      ),
      _DirectionalityCase(
        name: 'daughter (edge FROM anchor)',
        edge: _edge('anchor', 'rel', 'daughter'),
        expectedKey: 'mother', // inverse of 'daughter'
        expectedCategory: KinshipEdgeCategory.parent,
      ),

      // Sibling relationships
      _DirectionalityCase(
        name: 'brother (edge TO anchor)',
        edge: _edge('rel', 'anchor', 'brother'),
        expectedKey: 'brother',
        expectedCategory: KinshipEdgeCategory.sibling,
      ),
      _DirectionalityCase(
        name: 'sister (edge TO anchor)',
        edge: _edge('rel', 'anchor', 'sister'),
        expectedKey: 'sister',
        expectedCategory: KinshipEdgeCategory.sibling,
      ),

      // Spouse relationships
      _DirectionalityCase(
        name: 'husband (edge TO anchor)',
        edge: _edge('rel', 'anchor', 'husband'),
        expectedKey: 'husband',
        expectedCategory: KinshipEdgeCategory.spouse,
      ),
      _DirectionalityCase(
        name: 'wife (edge TO anchor)',
        edge: _edge('rel', 'anchor', 'wife'),
        expectedKey: 'wife',
        expectedCategory: KinshipEdgeCategory.spouse,
      ),

      // Grandparent
      _DirectionalityCase(
        name: 'grandfather (edge TO anchor)',
        edge: _edge('rel', 'anchor', 'grandfather'),
        expectedKey: 'grandfather',
        expectedCategory: KinshipEdgeCategory.grandparent,
      ),

      // Aunt/Uncle
      _DirectionalityCase(
        name: 'uncle (edge TO anchor)',
        edge: _edge('rel', 'anchor', 'uncle'),
        expectedKey: 'uncle',
        expectedCategory: KinshipEdgeCategory.auntUncle,
      ),

      // Cousin (symmetric)
      _DirectionalityCase(
        name: 'cousin (edge TO anchor)',
        edge: _edge('rel', 'anchor', 'cousin'),
        expectedKey: 'cousin',
        expectedCategory: KinshipEdgeCategory.cousin,
      ),

      // In-law
      _DirectionalityCase(
        name: 'father_in_law (edge TO anchor)',
        edge: _edge('rel', 'anchor', 'father_in_law'),
        expectedKey: 'father_in_law',
        expectedCategory: KinshipEdgeCategory.inLaw,
      ),
    ];

    for (final tc in testCases) {
      test(' ${tc.name}', () {
        final personMap = <String, GraphPersonData>{
          'anchor': _person('anchor', isAnchor: true),
          'rel': _person('rel'),
        };
        final edges = [tc.edge];

        final key = GraphRelationshipLabels.getRelationshipKey(
          'rel',
          personMap,
          edges,
        );

        expect(key, isNotNull,
            reason: 'Must resolve a key for "${tc.name}"');
        expect(key, equals(tc.expectedKey),
            reason: '${tc.name}: expected "${tc.expectedKey}", got "$key"');

        // Verify the key classifies to the correct category.
        final category = KinshipEdgeClassifier.classify(key!);
        expect(category, equals(tc.expectedCategory),
            reason: '${tc.name}: key "$key" must classify to ${tc.expectedCategory}');
      });
    }

    test('returns null when no anchor exists', () {
      final personMap = <String, GraphPersonData>{
        'p1': _person('p1'),
        'p2': _person('p2'),
      };
      final edges = [_edge('p1', 'p2', 'father')];
      final key = GraphRelationshipLabels.getRelationshipKey('p2', personMap, edges);
      expect(key, isNull);
    });

    test('returns null when no edge connects person to anchor', () {
      final personMap = <String, GraphPersonData>{
        'anchor': _person('anchor', isAnchor: true),
        'rel': _person('rel'),
        'other': _person('other'),
      };
      final edges = [_edge('rel', 'other', 'brother')]; // no edge to anchor
      final key = GraphRelationshipLabels.getRelationshipKey('rel', personMap, edges);
      expect(key, isNull);
    });
  });

  group('GraphRelationshipLabels.getRelationLabel — directionality (v65 FIX)', () {
    test('father edge TO anchor → label "Father" (not "Son")', () {
      final personMap = <String, GraphPersonData>{
        'anchor': _person('anchor', isAnchor: true),
        'dad': _person('dad', gender: 'male'),
      };
      final edges = [_edge('dad', 'anchor', 'father')];
      final label = GraphRelationshipLabels.getRelationLabel(
        personMap['dad']!,
        personMap,
        edges,
      );
      expect(label, equals('Father'),
          reason: 'Edge "dad IS father OF anchor" → label must be "Father"');
    });

    test('son edge FROM anchor → label "Father" (inverse)', () {
      final personMap = <String, GraphPersonData>{
        'anchor': _person('anchor', isAnchor: true),
        'dad': _person('dad', gender: 'male'),
      };
      // anchor IS the son OF dad → dad is anchor's father
      final edges = [_edge('anchor', 'dad', 'son')];
      final label = GraphRelationshipLabels.getRelationLabel(
        personMap['dad']!,
        personMap,
        edges,
      );
      expect(label, equals('Father'),
          reason: 'Edge "anchor IS son OF dad" → dad\'s label must be "Father"');
    });

    test('brother edge TO anchor → label "Brother"', () {
      final personMap = <String, GraphPersonData>{
        'anchor': _person('anchor', isAnchor: true),
        'bro': _person('bro', gender: 'male'),
      };
      final edges = [_edge('bro', 'anchor', 'brother')];
      final label = GraphRelationshipLabels.getRelationLabel(
        personMap['bro']!,
        personMap,
        edges,
      );
      expect(label, equals('Brother'));
    });

    test('wife edge TO anchor → label "Wife"', () {
      final personMap = <String, GraphPersonData>{
        'anchor': _person('anchor', isAnchor: true),
        'spouse': _person('spouse', gender: 'female'),
      };
      final edges = [_edge('spouse', 'anchor', 'wife')];
      final label = GraphRelationshipLabels.getRelationLabel(
        personMap['spouse']!,
        personMap,
        edges,
      );
      expect(label, equals('Wife'));
    });
  });

  group('Generic multi-family color resolution (v65)', () {
    // Verify that the color resolution works for DIFFERENT family
    // structures — not just one specific family. This is the key
    // requirement: the fix must be 100% data-driven, not hardcoded
    // to any person's name, ID, or family.

    test('Family A: anchor + father + mother + brother', () {
      final personMap = <String, GraphPersonData>{
        'a': _person('a', isAnchor: true),
        'dad': _person('dad', gender: 'male'),
        'mom': _person('mom', gender: 'female'),
        'bro': _person('bro', gender: 'male'),
      };
      final edges = [
        _edge('dad', 'a', 'father'),
        _edge('mom', 'a', 'mother'),
        _edge('bro', 'a', 'brother'),
      ];

      final dadKey = GraphRelationshipLabels.getRelationshipKey('dad', personMap, edges);
      final momKey = GraphRelationshipLabels.getRelationshipKey('mom', personMap, edges);
      final broKey = GraphRelationshipLabels.getRelationshipKey('bro', personMap, edges);

      // All keys must resolve (not null).
      expect(dadKey, isNotNull);
      expect(momKey, isNotNull);
      expect(broKey, isNotNull);

      // All keys must classify to the CORRECT category (not extended/grey).
      expect(KinshipEdgeClassifier.classify(dadKey!), equals(KinshipEdgeCategory.parent));
      expect(KinshipEdgeClassifier.classify(momKey!), equals(KinshipEdgeCategory.parent));
      expect(KinshipEdgeClassifier.classify(broKey!), equals(KinshipEdgeCategory.sibling));
    });

    test('Family B: anchor + wife + son + daughter (different structure)', () {
      final personMap = <String, GraphPersonData>{
        'b': _person('b', isAnchor: true),
        'wife': _person('wife', gender: 'female'),
        'son': _person('son', gender: 'male'),
        'dau': _person('dau', gender: 'female'),
      };
      final edges = [
        _edge('wife', 'b', 'wife'),
        _edge('son', 'b', 'son'),
        _edge('dau', 'b', 'daughter'),
      ];

      final wifeKey = GraphRelationshipLabels.getRelationshipKey('wife', personMap, edges);
      final sonKey = GraphRelationshipLabels.getRelationshipKey('son', personMap, edges);
      final dauKey = GraphRelationshipLabels.getRelationshipKey('dau', personMap, edges);

      expect(wifeKey, isNotNull);
      expect(sonKey, isNotNull);
      expect(dauKey, isNotNull);

      expect(KinshipEdgeClassifier.classify(wifeKey!), equals(KinshipEdgeCategory.spouse));
      expect(KinshipEdgeClassifier.classify(sonKey!), equals(KinshipEdgeCategory.child));
      expect(KinshipEdgeClassifier.classify(dauKey!), equals(KinshipEdgeCategory.child));
    });

    test('Family C: edges in BOTH directions (forward + inverse stored)', () {
      // Some families have BOTH directions stored in the DB (forward +
      // auto-created inverse). The resolver must handle both correctly.
      final personMap = <String, GraphPersonData>{
        'c': _person('c', isAnchor: true),
        'dad': _person('dad', gender: 'male'),
      };
      // Both directions: dad→c 'father' AND c→dad 'son'
      final edges = [
        _edge('dad', 'c', 'father'),
        _edge('c', 'dad', 'son'),
      ];

      final key = GraphRelationshipLabels.getRelationshipKey('dad', personMap, edges);
      expect(key, isNotNull);
      // The FIRST matching edge wins. 'dad→c' has targetId == anchor.id,
      // so it matches the "edge TO anchor" branch → returns 'father' directly.
      expect(key, equals('father'));
      expect(KinshipEdgeClassifier.classify(key!), equals(KinshipEdgeCategory.parent));
    });

    test('Family D: grandparent via direct edge', () {
      final personMap = <String, GraphPersonData>{
        'd': _person('d', isAnchor: true),
        'gpa': _person('gpa', gender: 'male'),
      };
      final edges = [_edge('gpa', 'd', 'grandfather')];

      final key = GraphRelationshipLabels.getRelationshipKey('gpa', personMap, edges);
      expect(key, equals('grandfather'));
      expect(KinshipEdgeClassifier.classify(key!), equals(KinshipEdgeCategory.grandparent));
    });

    test('Family E: uncle via direct edge', () {
      final personMap = <String, GraphPersonData>{
        'e': _person('e', isAnchor: true),
        'unc': _person('unc', gender: 'male'),
      };
      final edges = [_edge('unc', 'e', 'uncle')];

      final key = GraphRelationshipLabels.getRelationshipKey('unc', personMap, edges);
      expect(key, equals('uncle'));
      expect(KinshipEdgeClassifier.classify(key!), equals(KinshipEdgeCategory.auntUncle));
    });

    test('Family F: father-in-law via direct edge', () {
      final personMap = <String, GraphPersonData>{
        'f': _person('f', isAnchor: true),
        'fil': _person('fil', gender: 'male'),
      };
      final edges = [_edge('fil', 'f', 'father_in_law')];

      final key = GraphRelationshipLabels.getRelationshipKey('fil', personMap, edges);
      expect(key, equals('father_in_law'));
      expect(KinshipEdgeClassifier.classify(key!), equals(KinshipEdgeCategory.inLaw));
    });
  });
}

/// Test case for directionality verification.
class _DirectionalityCase {
  final String name;
  final GraphEdgeData edge;
  final String expectedKey;
  final KinshipEdgeCategory expectedCategory;

  _DirectionalityCase({
    required this.name,
    required this.edge,
    required this.expectedKey,
    required this.expectedCategory,
  });
}

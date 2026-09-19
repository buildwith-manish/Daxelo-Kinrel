// test/graph/widgets/relationship_directionality_test.dart
//
// Directionality tests for GraphRelationshipLabels.
//
// QA fix 2026-09-19: rewritten for the CANONICAL v5.19/v5.193 edge
// convention. The previous version encoded the INVERTED reading
// (v65-era) and started failing when getRelationshipKey /
// getRelationLabel were corrected in v5.193 (BUG #4 FIX) to match the
// database. See lib/graph/widgets/graph_relationship_labels.dart for
// the authoritative convention documentation.
//
// CANONICAL CONVENTION (matches relationship_edge_builder.dart and the
// SQL database):
//
//   from: A, to: B, key: 'X'  →  "B is A's X"
//
//   Example: from=Alice, to=Bob, key='father' → "Bob is Alice's father".
//   When a user adds their father, the edge is stored
//   from=user(anchor), to=father, key='father'.
//
// Therefore, from the ANCHOR's perspective:
//   - Edge FROM anchor (from=anchor, to=person, key='X'):
//     "person is anchor's X" → getRelationshipKey returns 'X' directly.
//   - Edge TO anchor (from=person, to=anchor, key='Y'):
//     "anchor is person's Y" → person is anchor's inverse('Y').

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

GraphEdgeData _edge(String from, String to, String key) => GraphEdgeData(
      id: '${from}_$to',
      sourceId: from,
      targetId: to,
      relationshipKey: key,
    );

void main() {
  group('GraphRelationshipLabels.getRelationshipKey — canonical directionality (v5.193)', () {
    // ───────────────────────────────────────────────────────────────
    // The anchor is always 'anchor'. The person under test is 'rel'.
    // Both edge directions are tested for each relationship type:
    //
    //   FORWARD: from: anchor, to: rel, key: 'X'
    //            ("rel is anchor's X") → expect 'X'.
    //
    //   INVERSE: from: rel, to: anchor, key: 'Y'
    //            ("anchor is rel's Y") → expect inverse('Y').
    // ───────────────────────────────────────────────────────────────

    final testCases = <_DirectionalityCase>[
      // ── FORWARD: edge FROM the anchor (key = rel's role) ─────────
      _DirectionalityCase(
        name: 'father (edge FROM anchor: rel is anchor\'s father)',
        edge: _edge('anchor', 'rel', 'father'),
        expectedKey: 'father',
        expectedCategory: KinshipEdgeCategory.parent,
      ),
      _DirectionalityCase(
        name: 'mother (edge FROM anchor: rel is anchor\'s mother)',
        edge: _edge('anchor', 'rel', 'mother'),
        expectedKey: 'mother',
        expectedCategory: KinshipEdgeCategory.parent,
      ),
      _DirectionalityCase(
        name: 'son (edge FROM anchor: rel is anchor\'s son)',
        edge: _edge('anchor', 'rel', 'son'),
        expectedKey: 'son',
        expectedCategory: KinshipEdgeCategory.child,
      ),
      _DirectionalityCase(
        name: 'daughter (edge FROM anchor: rel is anchor\'s daughter)',
        edge: _edge('anchor', 'rel', 'daughter'),
        expectedKey: 'daughter',
        expectedCategory: KinshipEdgeCategory.child,
      ),
      _DirectionalityCase(
        name: 'brother (edge FROM anchor: rel is anchor\'s brother)',
        edge: _edge('anchor', 'rel', 'brother'),
        expectedKey: 'brother',
        expectedCategory: KinshipEdgeCategory.sibling,
      ),
      _DirectionalityCase(
        name: 'sister (edge FROM anchor: rel is anchor\'s sister)',
        edge: _edge('anchor', 'rel', 'sister'),
        expectedKey: 'sister',
        expectedCategory: KinshipEdgeCategory.sibling,
      ),
      _DirectionalityCase(
        name: 'husband (edge FROM anchor: rel is anchor\'s husband)',
        edge: _edge('anchor', 'rel', 'husband'),
        expectedKey: 'husband',
        expectedCategory: KinshipEdgeCategory.spouse,
      ),
      _DirectionalityCase(
        name: 'wife (edge FROM anchor: rel is anchor\'s wife)',
        edge: _edge('anchor', 'rel', 'wife'),
        expectedKey: 'wife',
        expectedCategory: KinshipEdgeCategory.spouse,
      ),
      _DirectionalityCase(
        name: 'grandfather (edge FROM anchor: rel is anchor\'s grandfather)',
        edge: _edge('anchor', 'rel', 'grandfather'),
        expectedKey: 'grandfather',
        expectedCategory: KinshipEdgeCategory.grandparent,
      ),
      _DirectionalityCase(
        name: 'uncle (edge FROM anchor: rel is anchor\'s uncle)',
        edge: _edge('anchor', 'rel', 'uncle'),
        expectedKey: 'uncle',
        expectedCategory: KinshipEdgeCategory.auntUncle,
      ),
      _DirectionalityCase(
        name: 'cousin (edge FROM anchor: rel is anchor\'s cousin)',
        edge: _edge('anchor', 'rel', 'cousin'),
        expectedKey: 'cousin',
        expectedCategory: KinshipEdgeCategory.cousin,
      ),
      _DirectionalityCase(
        name: 'father_in_law (edge FROM anchor: rel is anchor\'s father-in-law)',
        edge: _edge('anchor', 'rel', 'father_in_law'),
        expectedKey: 'father_in_law',
        expectedCategory: KinshipEdgeCategory.inLaw,
      ),

      // ── INVERSE: edge TO the anchor (key = anchor's role relative
      //    to rel) → the resolver must invert to the anchor's
      //    perspective on rel. ─────────────────────────────────────
      _DirectionalityCase(
        name: 'son (edge TO anchor: anchor is rel\'s son → rel is the father)',
        edge: _edge('rel', 'anchor', 'son'),
        expectedKey: 'father',
        expectedCategory: KinshipEdgeCategory.parent,
      ),
      _DirectionalityCase(
        name: 'daughter (edge TO anchor: anchor is rel\'s daughter → rel is the mother)',
        edge: _edge('rel', 'anchor', 'daughter'),
        expectedKey: 'mother',
        expectedCategory: KinshipEdgeCategory.parent,
      ),
      _DirectionalityCase(
        name: 'brother (edge TO anchor: symmetric key stays sibling)',
        edge: _edge('rel', 'anchor', 'brother'),
        expectedKey: 'brother',
        expectedCategory: KinshipEdgeCategory.sibling,
      ),
      _DirectionalityCase(
        name: 'husband (edge TO anchor: anchor is rel\'s husband → rel is the wife)',
        edge: _edge('rel', 'anchor', 'husband'),
        expectedKey: 'wife',
        expectedCategory: KinshipEdgeCategory.spouse,
      ),
      _DirectionalityCase(
        name: 'wife (edge TO anchor: anchor is rel\'s wife → rel is the husband)',
        edge: _edge('rel', 'anchor', 'wife'),
        expectedKey: 'husband',
        expectedCategory: KinshipEdgeCategory.spouse,
      ),
      _DirectionalityCase(
        name: 'grandfather (edge TO anchor: anchor is rel\'s grandfather → rel is the grandson)',
        edge: _edge('rel', 'anchor', 'grandfather'),
        expectedKey: 'grandson',
        expectedCategory: KinshipEdgeCategory.grandparent,
      ),
      _DirectionalityCase(
        name: 'uncle (edge TO anchor: anchor is rel\'s uncle → rel is the nephew)',
        edge: _edge('rel', 'anchor', 'uncle'),
        expectedKey: 'nephew',
        expectedCategory: KinshipEdgeCategory.auntUncle,
      ),
      _DirectionalityCase(
        name: 'father_in_law (edge TO anchor: anchor is rel\'s father-in-law → rel is the son-in-law)',
        edge: _edge('rel', 'anchor', 'father_in_law'),
        expectedKey: 'son_in_law',
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

  group('GraphRelationshipLabels.getRelationLabel — canonical directionality (v5.193)', () {
    test('father edge FROM anchor → label "Father"', () {
      final personMap = <String, GraphPersonData>{
        'anchor': _person('anchor', isAnchor: true),
        'dad': _person('dad', gender: 'male'),
      };
      // Canonical: "dad is anchor's father"
      final edges = [_edge('anchor', 'dad', 'father')];
      final label = GraphRelationshipLabels.getRelationLabel(
        personMap['dad']!,
        personMap,
        edges,
      );
      expect(label, equals('Father'),
          reason: 'Edge "dad IS father OF anchor" → label must be "Father"');
    });

    test('son edge TO anchor → label "Father" (inverse)', () {
      final personMap = <String, GraphPersonData>{
        'anchor': _person('anchor', isAnchor: true),
        'dad': _person('dad', gender: 'male'),
      };
      // Canonical: "anchor is dad's son" → dad is anchor's father
      final edges = [_edge('dad', 'anchor', 'son')];
      final label = GraphRelationshipLabels.getRelationLabel(
        personMap['dad']!,
        personMap,
        edges,
      );
      expect(label, equals('Father'),
          reason: 'Edge "anchor IS son OF dad" → dad\'s label must be "Father"');
    });

    test('brother edge FROM anchor → label "Brother"', () {
      final personMap = <String, GraphPersonData>{
        'anchor': _person('anchor', isAnchor: true),
        'bro': _person('bro', gender: 'male'),
      };
      // Canonical: "bro is anchor's brother"
      final edges = [_edge('anchor', 'bro', 'brother')];
      final label = GraphRelationshipLabels.getRelationLabel(
        personMap['bro']!,
        personMap,
        edges,
      );
      expect(label, equals('Brother'));
    });

    test('wife edge FROM anchor → label "Wife"', () {
      final personMap = <String, GraphPersonData>{
        'anchor': _person('anchor', isAnchor: true),
        'spouse': _person('spouse', gender: 'female'),
      };
      // Canonical: "spouse is anchor's wife"
      final edges = [_edge('anchor', 'spouse', 'wife')];
      final label = GraphRelationshipLabels.getRelationLabel(
        personMap['spouse']!,
        personMap,
        edges,
      );
      expect(label, equals('Wife'));
    });

    test('husband edge TO anchor → label "Wife" (inverse)', () {
      final personMap = <String, GraphPersonData>{
        'anchor': _person('anchor', isAnchor: true),
        'spouse': _person('spouse', gender: 'female'),
      };
      // Canonical: "anchor is spouse's husband" → spouse is anchor's wife
      final edges = [_edge('spouse', 'anchor', 'husband')];
      final label = GraphRelationshipLabels.getRelationLabel(
        personMap['spouse']!,
        personMap,
        edges,
      );
      expect(label, equals('Wife'));
    });
  });

  group('Generic multi-family color resolution (canonical v5.193)', () {
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
      // Canonical: "dad is a's father", "mom is a's mother",
      // "bro is a's brother"
      final edges = [
        _edge('a', 'dad', 'father'),
        _edge('a', 'mom', 'mother'),
        _edge('a', 'bro', 'brother'),
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
      // Canonical: "wife is b's wife", "son is b's son", "dau is b's daughter"
      final edges = [
        _edge('b', 'wife', 'wife'),
        _edge('b', 'son', 'son'),
        _edge('b', 'dau', 'daughter'),
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
      // Canonical pair: "c is dad's son" (inverse-stored) AND
      // "dad is c's father" (forward-stored) — both describe the same
      // real-world relationship from opposite ends.
      final edges = [
        _edge('dad', 'c', 'son'),
        _edge('c', 'dad', 'father'),
      ];

      final key = GraphRelationshipLabels.getRelationshipKey('dad', personMap, edges);
      expect(key, isNotNull);
      // The FIRST matching edge wins. 'dad→c' has targetId == anchor.id,
      // so it matches the "edge TO anchor" branch → inverse('son') = 'father'.
      expect(key, equals('father'));
      expect(KinshipEdgeClassifier.classify(key!), equals(KinshipEdgeCategory.parent));
    });

    test('Family D: grandparent via direct edge', () {
      final personMap = <String, GraphPersonData>{
        'd': _person('d', isAnchor: true),
        'gpa': _person('gpa', gender: 'male'),
      };
      // Canonical: "gpa is d's grandfather"
      final edges = [_edge('d', 'gpa', 'grandfather')];

      final key = GraphRelationshipLabels.getRelationshipKey('gpa', personMap, edges);
      expect(key, equals('grandfather'));
      expect(KinshipEdgeClassifier.classify(key!), equals(KinshipEdgeCategory.grandparent));
    });

    test('Family E: uncle via direct edge', () {
      final personMap = <String, GraphPersonData>{
        'e': _person('e', isAnchor: true),
        'unc': _person('unc', gender: 'male'),
      };
      // Canonical: "unc is e's uncle"
      final edges = [_edge('e', 'unc', 'uncle')];

      final key = GraphRelationshipLabels.getRelationshipKey('unc', personMap, edges);
      expect(key, equals('uncle'));
      expect(KinshipEdgeClassifier.classify(key!), equals(KinshipEdgeCategory.auntUncle));
    });

    test('Family F: father-in-law via direct edge', () {
      final personMap = <String, GraphPersonData>{
        'f': _person('f', isAnchor: true),
        'fil': _person('fil', gender: 'male'),
      };
      // Canonical: "fil is f's father-in-law"
      final edges = [_edge('f', 'fil', 'father_in_law')];

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

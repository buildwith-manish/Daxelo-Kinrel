// test/graph/widgets/multi_hop_node_color_test.dart
//
// Regression test for the v63 fix: multi-hop relatives (e.g. grandfather
// via father → grandfather, cousin via father → uncle → cousin) must
// resolve to a kinship key whose KinshipEdgeCategory color is NOT the
// 'extended' slate gray fallback.
//
// BUG (before v63):
//   family_graph.dart's _buildNodes() only called
//   GraphRelationshipLabels.getRelationshipKey(), which scans for a
//   DIRECT edge from anchor → person. For multi-hop relatives (no direct
//   edge to anchor), this returned null, and the node fell through to
//   the 'extended' fallback (slate gray #64748B). The result: every
//   grandparent, aunt/uncle, cousin, and in-law rendered as the same
//   slate gray color, making the graph look broken.
//
// FIX (v63):
//   family_graph.dart now calls RelationshipEngine.instance.resolveKey()
//   for any person not reachable via a direct edge. The engine BFS-traverses
//   the graph and composes a kinship key (e.g. "paternal_grandfather",
//   "fathers_elder_brother", "fathers_brothers_son") which the classifier
//   then maps to the correct color category.
//
// This test verifies that for every common multi-hop relative, the
// composed key classifies to a NON-extended category and resolves to
// the spec-correct color.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/constants/brand_colors.dart';
import 'package:kinrel/core/kinship/kinship_edge_style.dart';
import 'package:kinrel/core/relationship/relationship_engine.dart';
import 'package:kinrel/core/services/graph_layout_service.dart';

/// Builds a typed [GraphPerson] with sensible defaults for tests.
GraphPerson _p(
  String id, {
  String name = 'Test',
  String? gender,
  int generationIndex = 0,
  bool isAnchor = false,
}) {
  return GraphPerson(
    id: id,
    name: name,
    gender: gender,
    generationIndex: generationIndex,
    isAnchor: isAnchor,
  );
}

/// A typed relationship record matching the engine's expected shape.
({String fromId, String toId, String type}) _r(
  String fromId,
  String toId,
  String type,
) => (fromId: fromId, toId: toId, type: type);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Multi-hop node color resolution (v63 regression)', () {
    late RelationshipEngine engine;

    setUp(() {
      engine = RelationshipEngine.instance;
      engine.invalidateCache();
    });

    tearDown(() {
      engine.invalidateCache();
    });

    // ─────────────────────────────────────────────────────────────────
    // Helper: resolve a multi-hop key and verify its color category.
    // ─────────────────────────────────────────────────────────────────
    void expectMultiHopColor({
      required String description,
      required String viewerId,
      required String targetId,
      required List<GraphPerson> persons,
      required List<({String fromId, String toId, String type})> relationships,
      required KinshipEdgeCategory expectedCategory,
      required Color expectedColor,
    }) {
      final key = engine.resolveKey(
        viewerPersonId: viewerId,
        targetPersonId: targetId,
        persons: persons,
        relationships: relationships,
      );

      // The engine MUST resolve a key for multi-hop relatives.
      expect(key, isNotNull,
          reason: '$description: engine must resolve a non-null key');

      // The key MUST classify to the expected category — NOT 'extended'
      // (which was the bug: every multi-hop relative was slate gray).
      final category = KinshipEdgeClassifier.classify(key!);
      expect(category, equals(expectedCategory),
          reason: '$description: key "$key" must classify to $expectedCategory, '
              'got $category');

      // The key MUST NOT classify to 'extended' for known relatives.
      // (Unless the expected category IS 'extended', e.g. step relations.)
      if (expectedCategory != KinshipEdgeCategory.extended) {
        expect(category, isNot(equals(KinshipEdgeCategory.extended)),
            reason: '$description: key "$key" must NOT fall through to '
                'extended (the bug we are fixing)');
      }

      // The resolved color MUST match the spec.
      final style = KinshipEdgeStyleResolver.styleFor(key);
      expect(style.color, equals(expectedColor),
          reason: '$description: key "$key" must resolve to color '
              '${expectedColor.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}, '
              'got ${style.color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}');
    }

    // ─────────────────────────────────────────────────────────────────
    // TEST 1: Grandparent via 2 hops (anchor → father → grandfather)
    // ─────────────────────────────────────────────────────────────────
    test('1. Grandparent (2 hops) → grandparent category (indigo)', () {
      expectMultiHopColor(
        description: 'Grandparent via father → grandfather',
        viewerId: 'ego',
        targetId: 'gpa',
        persons: [
          _p('ego', name: 'Ego', isAnchor: true),
          _p('dad', name: 'Dad', gender: 'male'),
          _p('gpa', name: 'Grandpa', gender: 'male'),
        ],
        relationships: [
          _r('ego', 'dad', 'father'),
          _r('dad', 'gpa', 'father'),
        ],
        expectedCategory: KinshipEdgeCategory.grandparent,
        expectedColor: KinrelColors.nodeGrandparent, // #6366F1
      );
    });

    // ─────────────────────────────────────────────────────────────────
    // TEST 2: Aunt/Uncle via 2 hops (anchor → father → uncle)
    // ─────────────────────────────────────────────────────────────────
    test('2. Aunt/Uncle (2 hops) → auntUncle category (cyan)', () {
      expectMultiHopColor(
        description: 'Uncle via father → uncle',
        viewerId: 'ego',
        targetId: 'unc',
        persons: [
          _p('ego', name: 'Ego', isAnchor: true),
          _p('dad', name: 'Dad', gender: 'male'),
          _p('unc', name: 'Uncle', gender: 'male'),
        ],
        relationships: [
          _r('ego', 'dad', 'father'),
          _r('dad', 'unc', 'brother'),
        ],
        expectedCategory: KinshipEdgeCategory.auntUncle,
        expectedColor: KinrelColors.nodeAuntUncle, // #06B6D4
      );
    });

    // ─────────────────────────────────────────────────────────────────
    // TEST 3: Cousin via 3 hops (anchor → father → uncle → cousin)
    // ─────────────────────────────────────────────────────────────────
    test('3. Cousin (3 hops) → cousin OR sibling category (emerald/purple)', () {
      // Indian kinship treats parallel cousins (father's brother's child)
      // as siblings. Cross-cousins (father's sister's child, mother's
      // sibling's child) are cousins. Either way, the color must NOT be
      // 'extended' slate gray.
      final key = engine.resolveKey(
        viewerPersonId: 'ego',
        targetPersonId: 'cou',
        persons: [
          _p('ego', name: 'Ego', isAnchor: true),
          _p('dad', name: 'Dad', gender: 'male'),
          _p('unc', name: 'Uncle', gender: 'male'),
          _p('cou', name: 'Cousin', gender: 'male'),
        ],
        relationships: [
          _r('ego', 'dad', 'father'),
          _r('dad', 'unc', 'brother'),
          _r('unc', 'cou', 'son'),
        ],
      );

      expect(key, isNotNull,
          reason: 'Cousin via 3 hops must resolve to a non-null key');

      final category = KinshipEdgeClassifier.classify(key!);
      expect(
        category,
        anyOf(
          equals(KinshipEdgeCategory.cousin),
          equals(KinshipEdgeCategory.sibling),
        ),
        reason: 'Cousin key "$key" must classify to cousin or sibling '
            '(parallel cousin), got $category',
      );
      expect(category, isNot(equals(KinshipEdgeCategory.extended)),
          reason: 'Cousin must NOT fall through to extended');
    });

    // ─────────────────────────────────────────────────────────────────
    // TEST 4: In-law via 2 hops (anchor → spouse → father_in_law)
    // ─────────────────────────────────────────────────────────────────
    test('4. In-law (2 hops) → inLaw category (amber)', () {
      expectMultiHopColor(
        description: 'Father-in-law via spouse → father',
        viewerId: 'ego',
        targetId: 'fil',
        persons: [
          _p('ego', name: 'Ego', gender: 'male', isAnchor: true),
          _p('wife', name: 'Wife', gender: 'female'),
          _p('fil', name: 'FatherInLaw', gender: 'male'),
        ],
        relationships: [
          _r('ego', 'wife', 'wife'),
          _r('wife', 'fil', 'father'),
        ],
        expectedCategory: KinshipEdgeCategory.inLaw,
        expectedColor: KinrelColors.nodeInLaw, // #F59E0B
      );
    });

    // ─────────────────────────────────────────────────────────────────
    // TEST 5: Sibling's spouse (brother's wife) via 2 hops
    // ─────────────────────────────────────────────────────────────────
    test('5. Sibling spouse (2 hops) → inLaw category (amber)', () {
      expectMultiHopColor(
        description: 'Sister-in-law via brother → wife',
        viewerId: 'ego',
        targetId: 'sil',
        persons: [
          _p('ego', name: 'Ego', isAnchor: true),
          _p('bro', name: 'Brother', gender: 'male'),
          _p('sil', name: 'SisterInLaw', gender: 'female'),
        ],
        relationships: [
          _r('ego', 'bro', 'brother'),
          _r('bro', 'sil', 'wife'),
        ],
        expectedCategory: KinshipEdgeCategory.inLaw,
        expectedColor: KinrelColors.nodeInLaw, // #F59E0B
      );
    });

    // ─────────────────────────────────────────────────────────────────
    // TEST 6: Niece/Nephew via 2 hops (anchor → brother → son)
    // ─────────────────────────────────────────────────────────────────
    test('6. Niece/Nephew (2 hops) → cousin category (emerald)', () {
      expectMultiHopColor(
        description: 'Nephew via brother → son',
        viewerId: 'ego',
        targetId: 'neph',
        persons: [
          _p('ego', name: 'Ego', isAnchor: true),
          _p('bro', name: 'Brother', gender: 'male'),
          _p('neph', name: 'Nephew', gender: 'male'),
        ],
        relationships: [
          _r('ego', 'bro', 'brother'),
          _r('bro', 'neph', 'son'),
        ],
        expectedCategory: KinshipEdgeCategory.cousin,
        expectedColor: KinrelColors.nodeCousin, // #10B981
      );
    });

    // ─────────────────────────────────────────────────────────────────
    // TEST 7: Self returns null (anchor's own key)
    // ─────────────────────────────────────────────────────────────────
    test('7. Self (viewer == target) returns null', () {
      final key = engine.resolveKey(
        viewerPersonId: 'ego',
        targetPersonId: 'ego',
        persons: [_p('ego', isAnchor: true)],
        relationships: const [],
      );
      expect(key, isNull,
          reason: 'Self-relationships return null; UI shows "You"');
    });

    // ─────────────────────────────────────────────────────────────────
    // TEST 8: No path → null (no false key)
    // ─────────────────────────────────────────────────────────────────
    test('8. No path between viewer and target → null', () {
      final key = engine.resolveKey(
        viewerPersonId: 'ego',
        targetPersonId: 'stranger',
        persons: [
          _p('ego', isAnchor: true),
          _p('stranger'),
        ],
        relationships: const [], // no edges
      );
      expect(key, isNull,
          reason: 'No path → null (GraphNode falls back to extended gray)');
    });

    // ─────────────────────────────────────────────────────────────────
    // TEST 9: Cache invalidation works across rebuilds
    // ─────────────────────────────────────────────────────────────────
    test('9. Cache invalidation allows re-resolution after graph change', () {
      // First resolution: ego → dad → gpa (grandfather)
      final key1 = engine.resolveKey(
        viewerPersonId: 'ego',
        targetPersonId: 'gpa',
        persons: [
          _p('ego', isAnchor: true),
          _p('dad', gender: 'male'),
          _p('gpa', gender: 'male'),
        ],
        relationships: [
          _r('ego', 'dad', 'father'),
          _r('dad', 'gpa', 'father'),
        ],
      );
      expect(key1, isNotNull);

      // Invalidate the cache (simulating family_graph.dart's didUpdateWidget)
      engine.invalidateCache();

      // Second resolution after invalidation: same graph, same result
      final key2 = engine.resolveKey(
        viewerPersonId: 'ego',
        targetPersonId: 'gpa',
        persons: [
          _p('ego', isAnchor: true),
          _p('dad', gender: 'male'),
          _p('gpa', gender: 'male'),
        ],
        relationships: [
          _r('ego', 'dad', 'father'),
          _r('dad', 'gpa', 'father'),
        ],
      );
      expect(key2, isNotNull);
      expect(key2, equals(key1),
          reason: 'After invalidation, the same graph must produce the same key');
    });
  });

  group('Classifier handles all common multi-hop composed keys', () {
    // The RelationshipEngine composes keys like "fathers_brother",
    // "fathers_elder_brothers_son", etc. The classifier must map every
    // such composed key to the correct NON-extended category.

    final cases = <String, KinshipEdgeCategory>{
      // 2-hop composed keys (parent's relatives)
      'fathers_brother': KinshipEdgeCategory.auntUncle,
      'fathers_sister': KinshipEdgeCategory.auntUncle,
      'fathers_elder_brother': KinshipEdgeCategory.auntUncle,
      'fathers_younger_brother': KinshipEdgeCategory.auntUncle,
      'mothers_brother': KinshipEdgeCategory.auntUncle,
      'mothers_sister': KinshipEdgeCategory.auntUncle,
      'fathers_brothers_wife': KinshipEdgeCategory.auntUncle,
      'fathers_sisters_husband': KinshipEdgeCategory.auntUncle,

      // 2-hop composed keys (grandparents)
      'paternal_grandfather': KinshipEdgeCategory.grandparent,
      'paternal_grandmother': KinshipEdgeCategory.grandparent,
      'maternal_grandfather': KinshipEdgeCategory.grandparent,
      'maternal_grandmother': KinshipEdgeCategory.grandparent,

      // 3-hop composed keys (parallel cousins = sibling per Indian kinship)
      'fathers_brothers_son': KinshipEdgeCategory.sibling, // parallel cousin
      'fathers_brothers_daughter': KinshipEdgeCategory.sibling,
      'fathers_sisters_son': KinshipEdgeCategory.sibling,
      'fathers_sisters_daughter': KinshipEdgeCategory.sibling,
      'mothers_brothers_son': KinshipEdgeCategory.sibling,
      'mothers_brothers_daughter': KinshipEdgeCategory.sibling,
      'mothers_sisters_son': KinshipEdgeCategory.sibling,
      'mothers_sisters_daughter': KinshipEdgeCategory.sibling,

      // 2-hop composed keys (sibling's children = niece/nephew → cousin color)
      'brothers_son': KinshipEdgeCategory.cousin,
      'brothers_daughter': KinshipEdgeCategory.cousin,
      'sisters_son': KinshipEdgeCategory.cousin,
      'sisters_daughter': KinshipEdgeCategory.cousin,

      // 2-hop composed keys (spouse's parents = in-laws)
      'wifes_father': KinshipEdgeCategory.inLaw,
      'wifes_mother': KinshipEdgeCategory.inLaw,
      'husbands_father': KinshipEdgeCategory.inLaw,
      'husbands_mother': KinshipEdgeCategory.inLaw,
    };

    for (final entry in cases.entries) {
      test('"${entry.key}" → ${entry.value}', () {
        final category = KinshipEdgeClassifier.classify(entry.key);
        expect(category, equals(entry.value),
            reason: 'Composed key "${entry.key}" must classify to ${entry.value}, '
                'got $category');
        // Multi-hop relatives must NOT fall through to extended.
        expect(category, isNot(equals(KinshipEdgeCategory.extended)),
            reason: 'Composed key "${entry.key}" must NOT be extended');
      });
    }
  });
}

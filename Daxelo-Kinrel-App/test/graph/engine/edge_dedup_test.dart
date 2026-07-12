// test/graph/engine/edge_dedup_test.dart
//
// v64 (BUG-2 FIX) regression test for EdgeDeduplicator.
//
// Verifies:
//   1. Duplicate rows (A→B "father" + B→A "child") collapse to ONE edge.
//   2. Distinct categories (parent + spouse) are kept as separate edges
//      with lateral offsets so they don't stack.
//   3. The strongest category wins the primary slot when duplicates exist.
//   4. Solo edges get lateralOffset = 0.0.
//   5. Empty input → empty output.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/kinship/kinship_edge_style.dart';
import 'package:kinrel/graph/data/family_graph_repository.dart';
import 'package:kinrel/graph/engine/edge_dedup.dart';

GraphEdgeData _edge(String id, String a, String b, String key) =>
    GraphEdgeData(
      id: id,
      sourceId: a,
      targetId: b,
      relationshipKey: key,
    );

void main() {
  group('EdgeDeduplicator', () {
    test('1. Empty input → empty output', () {
      final result = EdgeDeduplicator.deduplicate(const []);
      expect(result, isEmpty);
    });

    test('2. Solo edge → single entry, zero offset', () {
      final edges = [
        _edge('e1', 'A', 'B', 'father'),
      ];
      final result = EdgeDeduplicator.deduplicate(edges);
      expect(result.length, 1);
      expect(result.first.edge.id, 'e1');
      expect(result.first.lateralOffset, 0.0);
      expect(result.first.parallelCount, 1);
      expect(result.first.hasParallelEdge, isFalse);
    });

    test('3. Duplicate rows (A→B "father" + B→A "child") collapse to ONE edge', () {
      // This is the most common case — the DB stores both directions.
      // Without dedup, the painter would draw the same line twice.
      final edges = [
        _edge('e1', 'A', 'B', 'father'),
        _edge('e2', 'B', 'A', 'child'), // inverse direction, same pair
      ];
      final result = EdgeDeduplicator.deduplicate(edges);
      expect(result.length, 1,
          reason: 'Inverse rows must collapse to ONE edge');
      // The strongest category (parent, strength 100) wins.
      expect(result.first.edge.relationshipKey, anyOf('father', 'child'));
      expect(result.first.lateralOffset, 0.0);
      expect(result.first.parallelCount, 1);
    });

    test('4. Distinct categories (parent + spouse) → 2 edges with offsets', () {
      // Rare but legitimate: a person is BOTH parent AND spouse of the
      // same partner (e.g. in a blended family). Both edges should be
      // drawn, separated laterally so they don't stack.
      final edges = [
        _edge('e1', 'A', 'B', 'father'),
        _edge('e2', 'A', 'B', 'husband'),
      ];
      final result = EdgeDeduplicator.deduplicate(edges);
      expect(result.length, 2,
          reason: 'Distinct categories must be kept as separate edges');

      // Both should be marked as parallel.
      for (final r in result) {
        expect(r.parallelCount, 2);
        expect(r.hasParallelEdge, isTrue);
      }

      // Offsets should be symmetric: one negative, one positive.
      final offsets = result.map((r) => r.lateralOffset).toList()..sort();
      expect(offsets.first, lessThan(0));
      expect(offsets.last, greaterThan(0));
      expect((offsets.first + offsets.last).abs(), lessThan(0.01),
          reason: 'Offsets should be symmetric around 0');
    });

    test('5. Strongest category wins primary slot (parent > spouse > extended)', () {
      final edges = [
        _edge('e1', 'A', 'B', 'related'),     // extended
        _edge('e2', 'A', 'B', 'husband'),     // spouse
        _edge('e3', 'A', 'B', 'father'),      // parent — strongest
      ];
      final result = EdgeDeduplicator.deduplicate(edges);
      expect(result.length, 3,
          reason: 'Three distinct categories → three parallel edges');

      // The strongest (parent) should sort first.
      final keys = result.map((r) => r.edge.relationshipKey).toList();
      expect(keys.first, 'father',
          reason: 'Parent (strength 100) must come first');
      expect(keys[1], 'husband',
          reason: 'Spouse (strength 50) must come second');
      expect(keys.last, 'related',
          reason: 'Extended (strength 20) must come last');
    });

    test('6. Duplicate SAME-category rows collapse to ONE (not parallel)', () {
      // Even if the same category appears twice (e.g. user added
      // "father" twice, or the DB has a duplicate row), only ONE edge
      // should be drawn.
      final edges = [
        _edge('e1', 'A', 'B', 'father'),
        _edge('e2', 'B', 'A', 'father'), // same category, inverse direction
        _edge('e3', 'A', 'B', 'father'), // exact duplicate
      ];
      final result = EdgeDeduplicator.deduplicate(edges);
      expect(result.length, 1,
          reason: 'Duplicate same-category rows must collapse to ONE');
      expect(result.first.parallelCount, 1);
      expect(result.first.lateralOffset, 0.0);
    });

    test('7. Multiple distinct pairs each get correct dedup', () {
      // Two separate pairs, each with their own duplicate rows.
      final edges = [
        _edge('e1', 'A', 'B', 'father'),
        _edge('e2', 'B', 'A', 'child'),   // inverse of e1
        _edge('e3', 'C', 'D', 'wife'),
        _edge('e4', 'D', 'C', 'husband'), // inverse of e3
      ];
      final result = EdgeDeduplicator.deduplicate(edges);
      expect(result.length, 2,
          reason: 'Two distinct pairs → two edges total');

      // Each pair should be a solo edge (no parallel).
      for (final r in result) {
        expect(r.parallelCount, 1);
        expect(r.lateralOffset, 0.0);
      }

      // Verify the pairs are correct.
      final pairKeys = result.map((r) {
        final ids = [r.edge.sourceId, r.edge.targetId]..sort();
        return '${ids[0]}_${ids[1]}';
      }).toSet();
      expect(pairKeys, containsAll(['A_B', 'C_D']));
    });

    test('8. Three distinct categories → 3 parallel edges spread evenly', () {
      final edges = [
        _edge('e1', 'A', 'B', 'father'),
        _edge('e2', 'A', 'B', 'husband'),
        _edge('e3', 'A', 'B', 'related'),
      ];
      final result = EdgeDeduplicator.deduplicate(edges);
      expect(result.length, 3);

      // Offsets should spread evenly: negative, zero, positive.
      final offsets = result.map((r) => r.lateralOffset).toList()..sort();
      expect(offsets.first, lessThan(0));
      expect(offsets[1], closeTo(0.0, 0.01));
      expect(offsets.last, greaterThan(0));
    });

    test('9. Idempotent — same input produces same output order', () {
      final edges = [
        _edge('e1', 'A', 'B', 'father'),
        _edge('e2', 'A', 'B', 'husband'),
      ];
      final result1 = EdgeDeduplicator.deduplicate(edges);
      final result2 = EdgeDeduplicator.deduplicate(edges);

      expect(result1.length, result2.length);
      for (var i = 0; i < result1.length; i++) {
        expect(result1[i].edge.id, result2[i].edge.id);
        expect(result1[i].lateralOffset, result2[i].lateralOffset);
      }
    });

    test('10. KinshipEdgeCategory strength ordering is correct', () {
      // Verify the strength comparator returns the documented order.
      // This is a sanity check on _compareCategoryStrength.
      final categories = [
        KinshipEdgeCategory.extended,
        KinshipEdgeCategory.spouse,
        KinshipEdgeCategory.parent,
        KinshipEdgeCategory.sibling,
        KinshipEdgeCategory.child,
        KinshipEdgeCategory.inLaw,
        KinshipEdgeCategory.grandparent,
        KinshipEdgeCategory.auntUncle,
        KinshipEdgeCategory.cousin,
      ];

      // Deduplicate a contrived case with all categories between the
      // same pair — the result should be sorted by strength.
      final edges = categories
          .map((c) => _edge('e_${c.name}', 'A', 'B', _keyForCategory(c)))
          .toList();
      final result = EdgeDeduplicator.deduplicate(edges);

      // First edge should be the strongest (parent or child).
      final firstCat = KinshipEdgeClassifier.classify(
        result.first.edge.relationshipKey,
      );
      expect(
        firstCat,
        anyOf(
          equals(KinshipEdgeCategory.parent),
          equals(KinshipEdgeCategory.child),
        ),
        reason: 'Strongest category (parent/child, strength 100) must be first',
      );

      // Last edge should be the weakest (extended).
      final lastCat = KinshipEdgeClassifier.classify(
        result.last.edge.relationshipKey,
      );
      expect(lastCat, KinshipEdgeCategory.extended,
          reason: 'Weakest category (extended, strength 20) must be last');
    });
  });
}

/// Maps a [KinshipEdgeCategory] to a representative relationship key
/// that the classifier will map back to that category.
String _keyForCategory(KinshipEdgeCategory cat) {
  switch (cat) {
    case KinshipEdgeCategory.self:
      return 'self';
    case KinshipEdgeCategory.parent:
      return 'father';
    case KinshipEdgeCategory.child:
      return 'son';
    case KinshipEdgeCategory.sibling:
      return 'brother';
    case KinshipEdgeCategory.spouse:
      return 'husband';
    case KinshipEdgeCategory.grandparent:
      return 'grandfather';
    case KinshipEdgeCategory.auntUncle:
      return 'uncle';
    case KinshipEdgeCategory.cousin:
      return 'cousin';
    case KinshipEdgeCategory.inLaw:
      return 'father_in_law';
    case KinshipEdgeCategory.extended:
      return 'related';
    case KinshipEdgeCategory.indirect:
      return 'indirect_connection';
  }
}

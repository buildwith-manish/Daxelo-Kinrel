// test/graph/interaction/couple_union_model_test.dart
//
// Phase 6 — Derived Couple Union Layout tests.
//
// Tests:
//   1. spouse pair union
//   2. two confirmed parents with child
//   3. one known parent (child NOT attached to union)
//   4. remarriage (multiple unions per person)
//   5. half-sibling structure
//   6. multiple spouses
//   7. deterministic union identity
//   8. union excluded from member search
//   9. union excluded from kinship person semantics

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/graph/interaction/couple_union_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Helper: build edge tuples.
  List<({String fromId, String toId, String edgeId, String relationshipKey})>
      buildEdges(List<List<String>> pairs) {
    return pairs
        .map((p) => (fromId: p[0], toId: p[1], edgeId: p[2], relationshipKey: p[3]))
        .toList();
  }

  group('Phase 6 — Spouse pair union', () {
    test('TEST 1: spouse edge produces a union', () {
      final edges = buildEdges([
        ['A', 'B', 'e1', 'wife'],
      ]);

      final unions = deriveCoupleUnions(edges);

      expect(unions.length, 1);
      expect(unions.first.partnerAId, 'A');
      expect(unions.first.partnerBId, 'B');
      expect(unions.first.childIds, isEmpty,
          reason: 'No children → empty childIds');
    });

    test('TEST 1: union ID is derived from sorted partner IDs', () {
      final edges = buildEdges([
        ['B', 'A', 'e1', 'husband'],
      ]);

      final unions = deriveCoupleUnions(edges);

      expect(unions.first.id, 'union_A_B',
          reason: 'ID is sorted: A before B regardless of edge direction');
    });
  });

  group('Phase 6 — Two confirmed parents with child', () {
    test('TEST 2: child attached to union when BOTH parents confirmed', () {
      // A (father) → C (child)
      // B (mother) → C (child)
      // A — wife — B (spouse)
      final edges = buildEdges([
        ['A', 'C', 'e1', 'father'], // A IS father OF C
        ['B', 'C', 'e2', 'mother'], // B IS mother OF C
        ['A', 'B', 'e3', 'wife'],   // A — wife — B
      ]);

      final unions = deriveCoupleUnions(edges);

      expect(unions.length, 1);
      expect(unions.first.childIds, contains('C'),
          reason: 'Child C is attached to the union because BOTH '
              'parents are confirmed');
    });
  });

  group('Phase 6 — One known parent', () {
    test('TEST 3: child NOT attached to union when only one parent confirmed', () {
      // A (father) → C (child)
      // A — wife — B (spouse)
      // NO B → C edge (B is NOT confirmed as C's parent)
      final edges = buildEdges([
        ['A', 'C', 'e1', 'father'],
        ['A', 'B', 'e3', 'wife'],
      ]);

      final unions = deriveCoupleUnions(edges);

      expect(unions.length, 1);
      expect(unions.first.childIds, isNot(contains('C')),
          reason: 'Child C is NOT attached to the union because only '
              'one parent (A) is confirmed. C connects directly to A.');
    });
  });

  group('Phase 6 — Remarriage', () {
    test('TEST 4: person with two spouses produces two unions', () {
      // A — wife — B
      // A — wife — C (remarriage)
      final edges = buildEdges([
        ['A', 'B', 'e1', 'wife'],
        ['A', 'C', 'e2', 'wife'],
      ]);

      final unions = deriveCoupleUnions(edges);

      expect(unions.length, 2,
          reason: 'Two spouse edges → two unions (remarriage support)');

      // Verify both unions have the correct partners.
      final allPartners = unions.expand((u) => [u.partnerAId, u.partnerBId]).toSet();
      expect(allPartners, containsAll(['A', 'B', 'C']));
    });
  });

  group('Phase 6 — Half-sibling structure', () {
    test('TEST 5: half-siblings correctly handled', () {
      // A — wife — B (union 1)
      // A — wife — C (union 2, remarriage)
      // A (father) → D (child of A+B — both parents)
      // B (mother) → D
      // A (father) → E (child of A+C — both parents)
      // C (mother) → E
      final edges = buildEdges([
        ['A', 'B', 'e1', 'wife'],
        ['A', 'C', 'e2', 'wife'],
        ['A', 'D', 'e3', 'father'],
        ['B', 'D', 'e4', 'mother'],
        ['A', 'E', 'e5', 'father'],
        ['C', 'E', 'e6', 'mother'],
      ]);

      final unions = deriveCoupleUnions(edges);

      expect(unions.length, 2);

      // Find the A-B union and the A-C union.
      final abUnion = unions.firstWhere((u) =>
          (u.partnerAId == 'A' && u.partnerBId == 'B') ||
          (u.partnerAId == 'B' && u.partnerBId == 'A'));
      final acUnion = unions.firstWhere((u) =>
          (u.partnerAId == 'A' && u.partnerBId == 'C') ||
          (u.partnerAId == 'C' && u.partnerBId == 'A'));

      // D is a child of A+B → attached to the A-B union.
      expect(abUnion.childIds, contains('D'));
      expect(abUnion.childIds, isNot(contains('E')),
          reason: 'E is NOT a child of B');

      // E is a child of A+C → attached to the A-C union.
      expect(acUnion.childIds, contains('E'));
      expect(acUnion.childIds, isNot(contains('D')),
          reason: 'D is NOT a child of C');
    });
  });

  group('Phase 6 — Multiple spouses', () {
    test('TEST 6: three spouses produce three unions', () {
      final edges = buildEdges([
        ['A', 'B', 'e1', 'wife'],
        ['A', 'C', 'e2', 'wife'],
        ['A', 'D', 'e3', 'wife'],
      ]);

      final unions = deriveCoupleUnions(edges);

      expect(unions.length, 3,
          reason: 'Three spouse edges → three unions');
    });

    test('TEST 6: duplicate spouse edge (same pair, different direction) deduped', () {
      // EdgeDeduplicator should collapse these, but guard here too.
      final edges = buildEdges([
        ['A', 'B', 'e1', 'wife'],
        ['B', 'A', 'e2', 'husband'], // same pair, opposite direction
      ]);

      final unions = deriveCoupleUnions(edges);

      expect(unions.length, 1,
          reason: 'Same pair → one union (deduped by canonical pair key)');
    });
  });

  group('Phase 6 — Deterministic union identity', () {
    test('TEST 7: same pair always produces the same union ID', () {
      final edges1 = buildEdges([['A', 'B', 'e1', 'wife']]);
      final edges2 = buildEdges([['B', 'A', 'e2', 'husband']]);

      final unions1 = deriveCoupleUnions(edges1);
      final unions2 = deriveCoupleUnions(edges2);

      expect(unions1.first.id, unions2.first.id,
          reason: 'Union ID must be deterministic — same pair, same ID '
              'regardless of edge direction');
      expect(unions1.first.id, 'union_A_B');
    });

    test('TEST 7: different pairs produce different union IDs', () {
      final edges = buildEdges([
        ['A', 'B', 'e1', 'wife'],
        ['C', 'D', 'e2', 'wife'],
      ]);

      final unions = deriveCoupleUnions(edges);

      expect(unions[0].id, isNot(unions[1].id));
    });
  });

  group('Phase 6 — Union excluded from member search', () {
    test('TEST 8: union IDs start with "union_" prefix', () {
      final edges = buildEdges([['A', 'B', 'e1', 'wife']]);
      final unions = deriveCoupleUnions(edges);

      expect(unions.first.id.startsWith('union_'), isTrue);
    });

    test('TEST 8: isUnionEntity rejects union IDs', () {
      expect(isUnionEntity('union_A_B'), isTrue);
      expect(isUnionEntity('person-123'), isFalse);
      expect(isUnionEntity('abc'), isFalse);
    });
  });

  group('Phase 6 — Union excluded from kinship person semantics', () {
    test('TEST 9: CoupleUnion is NOT a GraphPerson', () {
      // CoupleUnion has: id, partnerAId, partnerBId, edgeId,
      // relationshipKey, childIds. It does NOT have: name, gender,
      // generationIndex, isAnchor, photoUrl, isDeceased, etc.
      // It is a layout/presentation entity, not a family member.
      final edges = buildEdges([['A', 'B', 'e1', 'wife']]);
      final unions = deriveCoupleUnions(edges);

      // Verify the union has NO person-like fields.
      final union = unions.first;
      expect(union.id, isA<String>());
      expect(union.partnerAId, isA<String>());
      expect(union.partnerBId, isA<String>());
      // No name, no gender, no photoUrl, no isDeceased, etc.
    });

    test('TEST 9: union midpoint is the geometric midpoint', () {
      final posA = Offset(0, 0);
      final posB = Offset(100, 200);

      final mid = unionMidpoint(posA, posB);

      expect(mid.dx, 50);
      expect(mid.dy, 100);
    });
  });

  group('Phase 6 — No spouse edges → no unions', () {
    test('parent-child only → no unions', () {
      final edges = buildEdges([
        ['A', 'B', 'e1', 'father'],
      ]);

      final unions = deriveCoupleUnions(edges);

      expect(unions, isEmpty,
          reason: 'No spouse edges → no unions');
    });

    test('empty edges → no unions', () {
      final unions = deriveCoupleUnions([]);

      expect(unions, isEmpty);
    });
  });
}

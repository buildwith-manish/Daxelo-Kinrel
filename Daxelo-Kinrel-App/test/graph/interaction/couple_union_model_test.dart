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
  // v5.174 fix: include labelAtoB field (matches deriveCoupleUnions signature).
  // Set to null so the function falls back to relationshipKey (test data
  // already encodes the actual relationship label in relationshipKey).
  //
  // QA fix 2026-09-19 (Task 6-a): fixtures rewritten for the CANONICAL
  // edge direction convention (v5.174 couple_union_model.dart commit
  // 3caf684b; v5.19 relationship_edge_builder.dart):
  //   from=X, to=Y, key='K' → "Y is X's K"
  // so a 'father'/'mother' key means the toId is the PARENT. The old
  // fixtures used the pre-v5.174 inverted reading ('father' → fromId
  // is the parent), which made deriveCoupleUnions attach NO children
  // after the v5.174 direction fix. Expectations are UNCHANGED — only
  // the fixture directions were corrected.
  List<({String fromId, String toId, String edgeId, String relationshipKey, String? labelAtoB})>
      buildEdges(List<List<String>> pairs) {
    return pairs
        .map((p) => (fromId: p[0], toId: p[1], edgeId: p[2], relationshipKey: p[3], labelAtoB: null))
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
      // A and B are spouses; C is their confirmed child.
      // Canonical (v5.174): from=X, to=Y, key='K' → "Y is X's K".
      final edges = buildEdges([
        ['C', 'A', 'e1', 'father'], // canonical: "A is C's father"
        ['C', 'B', 'e2', 'mother'], // canonical: "B is C's mother"
        ['A', 'B', 'e3', 'wife'],   // canonical: "B is A's wife"
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
      // A is C's only known parent; A — wife — B (spouse).
      // Canonical: C→A 'father' → "A is C's father".
      // NO C→B edge (B is NOT confirmed as C's parent)
      final edges = buildEdges([
        ['C', 'A', 'e1', 'father'], // canonical: "A is C's father"
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
      // D is a child of A+B (both parents confirmed)
      // E is a child of A+C (both parents confirmed)
      // Canonical (v5.174): from=X, to=Y, key='K' → "Y is X's K".
      final edges = buildEdges([
        ['A', 'B', 'e1', 'wife'],
        ['A', 'C', 'e2', 'wife'],
        ['D', 'A', 'e3', 'father'], // canonical: "A is D's father"
        ['D', 'B', 'e4', 'mother'], // canonical: "B is D's mother"
        ['E', 'A', 'e5', 'father'], // canonical: "A is E's father"
        ['E', 'C', 'e6', 'mother'], // canonical: "C is E's mother"
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
      final posA = const Offset(0, 0);
      final posB = const Offset(100, 200);

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

  // ═══════════════════════════════════════════════════════════════════════
  // EDGE-ANCHOR FIX — Edge routing NO LONGER redirects through union
  // midpoint (replaces the previous v100 Phase 6 routing tests).
  // ═══════════════════════════════════════════════════════════════════════
  //
  // The previous v100 tests verified that parent→child edges through
  // confirmed couple unions were redirected to the union midpoint.
  // The EDGE-ANCHOR FIX removed this redirect — every edge now anchors
  // at its source node's box center, per the user's spec:
  //
  //   "Every edge in the graph must follow the exact same geometric
  //    rule: sourceNode.center → targetNode.center. This rule must
  //    apply to ALL nodes — Anchor, Selected, Unselected, Parent,
  //    Child, Sibling, Spouse, Highlighted 'You' node. No
  //    special-case anchoring logic should exist for specific node
  //    types unless absolutely necessary."
  //
  // These tests verify the NEW behavior: resolveEffectiveEdgeEndpoints
  // returns the raw source/target unchanged — even for parent→child
  // edges through confirmed couple unions (which USED to be
  // redirected). The data-structure tests above (deriveCoupleUnions
  // attaching children to unions) are unchanged — only the EDGE
  // GEOMETRY (which position is used as the source) has changed.

  group('EDGE-ANCHOR FIX — Edge routing NO redirect (replaces v100)', () {
    /// Verifies the EDGE-ANCHOR FIX contract: resolveEffectiveEdgeEndpoints
    /// returns the raw source position unchanged — no redirect to the
    /// union midpoint for parent→child edges through confirmed couple
    /// unions.
    Offset computeEffectiveSource({
      required String sourceId,
      required String targetId,
      required Map<String, Offset> positions,
      required List<CoupleUnion> unions,
    }) {
      // EDGE-ANCHOR FIX: this now calls the PRODUCTION helper instead
      // of a local simulation. The production helper is a no-op for
      // the redirect — it returns the raw source/target unchanged.
      // This means these tests directly verify production behavior
      // (not a simulation), so they will fail if a future change
      // reintroduces the redirect.
      final rawSource = positions[sourceId]!;
      final rawTarget = positions[targetId]!;
      final resolved = resolveEffectiveEdgeEndpoints(
        sourceId: sourceId,
        targetId: targetId,
        rawSource: rawSource,
        rawTarget: rawTarget,
        coupleUnions: unions,
        positionOf: (id) => positions[id],
      );
      return resolved.source;
    }

    test('EDGE-ANCHOR FIX: shared child — both parent→child edges anchor at the PARENT\'s box center (NO redirect)', () {
      // A and B are spouses; C is their confirmed child.
      // Canonical (v5.174): C→A 'father' ("A is C's father"),
      // C→B 'mother' ("B is C's mother").
      //
      // PRE-FIX: A→C and B→C both started at the union midpoint (50, 0).
      // POST-FIX (EDGE-ANCHOR FIX): A→C starts at A's box center (0, 0);
      // B→C starts at B's box center (100, 0). Each parent has its own edge
      // to the child — the user's spec.
      final edges = buildEdges([
        ['C', 'A', 'e1', 'father'], // canonical: "A is C's father"
        ['C', 'B', 'e2', 'mother'], // canonical: "B is C's mother"
        ['A', 'B', 'e3', 'wife'],
      ]);
      final unions = deriveCoupleUnions(edges);
      expect(unions.length, 1);
      expect(unions.first.childIds, contains('C'));

      final positions = {
        'A': const Offset(0, 0),
        'B': const Offset(100, 0),
        'C': const Offset(50, 200),
      };

      // Edge A→C: EDGE-ANCHOR FIX — source must be A's box center
      // (0, 0), NOT the union midpoint (50, 0).
      final sourceForAC = computeEffectiveSource(
        sourceId: 'A',
        targetId: 'C',
        positions: positions,
        unions: unions,
      );
      expect(sourceForAC.dx, 0.0,
          reason: 'EDGE-ANCHOR FIX: Edge A→C must start at A\'s box center X (0), not union midpoint (50)');
      expect(sourceForAC.dy, 0.0,
          reason: 'EDGE-ANCHOR FIX: Edge A→C must start at A\'s box center Y (0)');

      // Edge B→C: EDGE-ANCHOR FIX — source must be B's box center
      // (100, 0), NOT the union midpoint (50, 0).
      final sourceForBC = computeEffectiveSource(
        sourceId: 'B',
        targetId: 'C',
        positions: positions,
        unions: unions,
      );
      expect(sourceForBC.dx, 100.0,
          reason: 'EDGE-ANCHOR FIX: Edge B→C must start at B\'s box center X (100), not union midpoint (50)');
      expect(sourceForBC.dy, 0.0,
          reason: 'EDGE-ANCHOR FIX: Edge B→C must start at B\'s box center Y (0)');
    });

    test('single-parent child (no union): edge anchors at parent position', () {
      // A is C's father, NO spouse edge → no union.
      // Canonical: C→A 'father' → "A is C's father".
      final edges = buildEdges([
        ['C', 'A', 'e1', 'father'], // canonical: "A is C's father"
      ]);
      final unions = deriveCoupleUnions(edges);
      expect(unions, isEmpty);

      final positions = {
        'A': const Offset(0, 0),
        'C': const Offset(50, 200),
      };

      final sourceForAC = computeEffectiveSource(
        sourceId: 'A',
        targetId: 'C',
        positions: positions,
        unions: unions,
      );
      expect(sourceForAC.dx, 0.0,
          reason: 'No union → edge should start at parent A (0, 0)');
      expect(sourceForAC.dy, 0.0);
    });

    test('EDGE-ANCHOR FIX: remarriage — each child\'s edge anchors at A\'s box center (NO per-union redirect)', () {
      // A — wife — B (union 1), A — wife — C (union 2, remarriage)
      // D is a child of A+B (both parents confirmed)
      // E is a child of A+C (both parents confirmed)
      // Canonical (v5.174): from=X, to=Y, key='K' → "Y is X's K".
      //
      // PRE-FIX: A→D started at A-B midpoint (50, 0); A→E started at
      // A-C midpoint (100, 0) — DIFFERENT points (not converged).
      // POST-FIX (EDGE-ANCHOR FIX): BOTH start at A's box center
      // (0, 0) — the spokes-on-a-clock-face requirement.
      final edges = buildEdges([
        ['A', 'B', 'e1', 'wife'],
        ['A', 'C', 'e2', 'wife'],
        ['D', 'A', 'e3', 'father'], // canonical: "A is D's father"
        ['D', 'B', 'e4', 'mother'], // canonical: "B is D's mother"
        ['E', 'A', 'e5', 'father'], // canonical: "A is E's father"
        ['E', 'C', 'e6', 'mother'], // canonical: "C is E's mother"
      ]);
      final unions = deriveCoupleUnions(edges);
      expect(unions.length, 2);

      final positions = {
        'A': const Offset(0, 0),
        'B': const Offset(100, 0),
        'C': const Offset(200, 0),
        'D': const Offset(50, 200),
        'E': const Offset(150, 200),
      };

      // Edge A→D: EDGE-ANCHOR FIX — source = A's box center (0, 0),
      // NOT the A-B union midpoint (50, 0).
      final sourceForAD = computeEffectiveSource(
        sourceId: 'A',
        targetId: 'D',
        positions: positions,
        unions: unions,
      );
      expect(sourceForAD.dx, 0.0,
          reason: 'EDGE-ANCHOR FIX: A→D source must be A\'s box center (0), not A-B midpoint (50)');

      // Edge A→E: EDGE-ANCHOR FIX — source = A's box center (0, 0),
      // the SAME as A→D — NOT the A-C union midpoint (100, 0).
      final sourceForAE = computeEffectiveSource(
        sourceId: 'A',
        targetId: 'E',
        positions: positions,
        unions: unions,
      );
      expect(sourceForAE.dx, 0.0,
          reason: 'EDGE-ANCHOR FIX: A→E source must be A\'s box center (0), not A-C midpoint (100)');

      // SPOKES-ON-A-CLOCK-FACE: A→D and A→E converge at A's box center.
      expect(sourceForAD, sourceForAE,
          reason: 'EDGE-ANCHOR FIX: multiple outgoing edges from A must converge at A\'s box center');
    });

    test('EDGE-ANCHOR FIX: half-sibling — BOTH edges anchor at A\'s box center (NO redirect for either)', () {
      // A — wife — B (union)
      // C is the shared child of A+B (both parents confirmed)
      // D is a child of A only (NOT B's child — half-sibling)
      // Canonical (v5.174): C→A 'father' ("A is C's father"),
      // C→B 'mother' ("B is C's mother"), D→A 'father' ("A is D's
      // father" — D's only known parent).
      //
      // PRE-FIX: A→C redirected to union midpoint (50, 0); A→D stayed
      // at A's box center (0, 0) — DIFFERENT points (not converged).
      // POST-FIX (EDGE-ANCHOR FIX): BOTH anchor at A's box center (0, 0).
      final edges = buildEdges([
        ['A', 'B', 'e1', 'wife'],
        ['C', 'A', 'e2', 'father'], // canonical: "A is C's father"
        ['C', 'B', 'e3', 'mother'], // canonical: "B is C's mother"
        ['D', 'A', 'e4', 'father'], // canonical: "A is D's father"
        // NO D→B edge — D is NOT B's child.
      ]);
      final unions = deriveCoupleUnions(edges);
      expect(unions.length, 1);
      expect(unions.first.childIds, contains('C'));
      expect(unions.first.childIds, isNot(contains('D')),
          reason: 'D is NOT a child of the A-B union');

      final positions = {
        'A': const Offset(0, 0),
        'B': const Offset(100, 0),
        'C': const Offset(50, 200),
        'D': const Offset(0, 300),
      };

      // Edge A→C: EDGE-ANCHOR FIX — source = A's box center (0, 0),
      // NOT the union midpoint (50, 0).
      final sourceForAC = computeEffectiveSource(
        sourceId: 'A',
        targetId: 'C',
        positions: positions,
        unions: unions,
      );
      expect(sourceForAC.dx, 0.0,
          reason: 'EDGE-ANCHOR FIX: A→C source must be A\'s box center (0), not union midpoint (50)');

      // Edge A→D: EDGE-ANCHOR FIX — source = A's box center (0, 0),
      // the SAME as A→C.
      final sourceForAD = computeEffectiveSource(
        sourceId: 'A',
        targetId: 'D',
        positions: positions,
        unions: unions,
      );
      expect(sourceForAD.dx, 0.0,
          reason: 'EDGE-ANCHOR FIX: A→D source must be A\'s box center (0)');

      // SPOKES-ON-A-CLOCK-FACE: A→C and A→D converge at A's box center.
      expect(sourceForAC, sourceForAD,
          reason: 'EDGE-ANCHOR FIX: A→C and A→D must converge at A\'s box center');
    });

    test('EDGE-ANCHOR FIX: edge ID, category, custom colors unaffected by routing removal', () {
      // The EDGE-ANCHOR FIX removed the couple-union redirect from
      // resolveEffectiveEdgeEndpoints. The redirect only affected WHERE
      // the bezier started — the edge's ID, relationshipKey, category,
      // and custom colors are all keyed by edge ID, which does NOT
      // change. This test verifies the edge DATA is unchanged.
      final edges = buildEdges([
        ['A', 'B', 'e1', 'wife'],
        ['C', 'A', 'e2', 'father'], // canonical: "A is C's father"
        ['C', 'B', 'e3', 'mother'], // canonical: "B is C's mother"
      ]);
      final unions = deriveCoupleUnions(edges);

      // The union's edgeId references the ORIGINAL spouse edge (e1),
      // not a synthetic ID.
      expect(unions.first.edgeId, 'e1');
      // The child edge IDs are the ORIGINAL parent→child edge IDs.
      // No synthetic union→child edge ID was created.
      expect(unions.first.childIds, contains('C'));
      // 'C' is a person ID, not an edge ID.
    });
  });
}

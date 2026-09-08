// test/graph/perf/filtered_graph_test.dart
//
// v5.146 (STEP 6): Verifies the FilteredGraph (v5.143) actually
// excludes hidden/off-screen nodes from ALL downstream computations.
// This is the test that would have caught the "5-6 iterations of
// flat.relationships per rebuild" bug.
//
// Run:  flutter test test/graph/perf/filtered_graph_test.dart

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/graph/rendering/filtered_graph.dart';

void main() {
  group('FilteredGraph — hidden-node exclusion (Step 6)', () {
    test('excludes nodes without positions', () {
      // 700 persons, but only 22 have positions (the proximity set).
      // FilteredGraph must return ONLY the 22 with positions.
      final allPersons = <Map<String, dynamic>>[
        for (var i = 0; i < 700; i++)
          {'id': 'p$i', 'name': 'Person $i', 'gender': 'male'},
      ];
      final allRelationships = <Map<String, dynamic>>[
        // 1000 edges — most connect to position-less nodes.
        for (var i = 0; i < 1000; i++)
          {
            'id': 'r$i',
            'fromPersonId': 'p${i % 700}',
            'toPersonId': 'p${(i + 1) % 700}',
            'relationshipKey': 'parent',
          },
      ];

      // Only 22 nodes have positions (the proximity set).
      final effectivePositions = <String, Offset>{
        for (var i = 0; i < 22; i++)
          'p$i': Offset(i * 100.0, i * 100.0),
      };

      final filtered = buildFilteredGraph(
        allPersons: allPersons,
        allRelationships: allRelationships,
        effectivePositions: effectivePositions,
        hiddenIds: <String>{},
      );

      // FilteredGraph must contain ONLY the 22 nodes with positions.
      expect(filtered.personCount, 22,
          reason: 'FilteredGraph should contain only 22 nodes with '
              'positions, not all 700. Got ${filtered.personCount}.');
      expect(filtered.visiblePersonIds.length, 22);
      expect(filtered.visiblePersons.length, 22);
      expect(filtered.personById.length, 22);

      // No position-less node should appear in the filtered graph.
      for (var i = 22; i < 700; i++) {
        expect(filtered.visiblePersonIds.contains('p$i'), isFalse,
            reason: 'Node p$i has no position but is in the filtered '
                'graph — hidden nodes are leaking.');
      }
    });

    test('excludes edges where either endpoint has no position', () {
      final allPersons = <Map<String, dynamic>>[
        {'id': 'a', 'name': 'A'},
        {'id': 'b', 'name': 'B'},
        {'id': 'c', 'name': 'C'}, // no position
        {'id': 'd', 'name': 'D'}, // no position
      ];
      final allRelationships = <Map<String, dynamic>>[
        // a-b: both have positions → included
        {'id': 'r1', 'fromPersonId': 'a', 'toPersonId': 'b', 'relationshipKey': 'parent'},
        // a-c: c has no position → excluded
        {'id': 'r2', 'fromPersonId': 'a', 'toPersonId': 'c', 'relationshipKey': 'parent'},
        // b-d: d has no position → excluded
        {'id': 'r3', 'fromPersonId': 'b', 'toPersonId': 'd', 'relationshipKey': 'spouse'},
        // c-d: neither has position → excluded
        {'id': 'r4', 'fromPersonId': 'c', 'toPersonId': 'd', 'relationshipKey': 'sibling'},
      ];
      final effectivePositions = <String, Offset>{
        'a': const Offset(0, 0),
        'b': const Offset(100, 0),
      };

      final filtered = buildFilteredGraph(
        allPersons: allPersons,
        allRelationships: allRelationships,
        effectivePositions: effectivePositions,
        hiddenIds: <String>{},
      );

      // Only r1 (a-b) should survive — both endpoints have positions.
      expect(filtered.edgeCount, 1,
          reason: 'Only 1 edge has both endpoints with positions. '
              'Got ${filtered.edgeCount}.');
      expect(filtered.visibleRelationships.first.edgeId, 'r1');
    });

    test('excludes edges where BOTH endpoints are hidden', () {
      final allPersons = <Map<String, dynamic>>[
        {'id': 'a', 'name': 'A'},
        {'id': 'b', 'name': 'B'},
        {'id': 'c', 'name': 'C'},
        {'id': 'd', 'name': 'D'},
      ];
      final allRelationships = <Map<String, dynamic>>[
        {'id': 'r1', 'fromPersonId': 'a', 'toPersonId': 'b', 'relationshipKey': 'parent'},
        {'id': 'r2', 'fromPersonId': 'a', 'toPersonId': 'c', 'relationshipKey': 'parent'},
        // c-d: both hidden → excluded
        {'id': 'r3', 'fromPersonId': 'c', 'toPersonId': 'd', 'relationshipKey': 'sibling'},
      ];
      final effectivePositions = <String, Offset>{
        'a': const Offset(0, 0),
        'b': const Offset(100, 0),
        'c': const Offset(200, 0),
        'd': const Offset(300, 0),
      };
      // c and d are hidden by collapse.
      final hiddenIds = <String>{'c', 'd'};

      final filtered = buildFilteredGraph(
        allPersons: allPersons,
        allRelationships: allRelationships,
        effectivePositions: effectivePositions,
        hiddenIds: hiddenIds,
      );

      // r1 (a-b): both visible → included.
      // r2 (a-c): a visible, c hidden → included (one endpoint visible).
      // r3 (c-d): both hidden → EXCLUDED.
      expect(filtered.edgeCount, 2,
          reason: 'r1 and r2 should be included (at least one visible '
              'endpoint). r3 should be excluded (both hidden). '
              'Got ${filtered.edgeCount}.');
      final edgeIds = filtered.visibleRelationships.map((r) => r.edgeId).toSet();
      expect(edgeIds.contains('r1'), isTrue);
      expect(edgeIds.contains('r2'), isTrue);
      expect(edgeIds.contains('r3'), isFalse,
          reason: 'r3 has both endpoints hidden — it must NOT be in '
              'the filtered graph.');
    });

    test('adjacency map only contains visible-to-visible edges', () {
      final allPersons = <Map<String, dynamic>>[
        {'id': 'a', 'name': 'A'},
        {'id': 'b', 'name': 'B'},
        {'id': 'c', 'name': 'C'}, // hidden
      ];
      final allRelationships = <Map<String, dynamic>>[
        {'id': 'r1', 'fromPersonId': 'a', 'toPersonId': 'b', 'relationshipKey': 'parent'},
        {'id': 'r2', 'fromPersonId': 'a', 'toPersonId': 'c', 'relationshipKey': 'parent'},
      ];
      final effectivePositions = <String, Offset>{
        'a': const Offset(0, 0),
        'b': const Offset(100, 0),
        'c': const Offset(200, 0),
      };
      final hiddenIds = <String>{'c'};

      final filtered = buildFilteredGraph(
        allPersons: allPersons,
        allRelationships: allRelationships,
        effectivePositions: effectivePositions,
        hiddenIds: hiddenIds,
      );

      // Adjacency: a→b (both visible), but NOT a→c (c is hidden).
      final neighborsOfA = filtered.firstDegreeNeighborsOf('a');
      expect(neighborsOfA.contains('b'), isTrue);
      expect(neighborsOfA.contains('c'), isFalse,
          reason: 'c is hidden — it must NOT be in the adjacency map. '
              'Hidden nodes leaking into adjacency = the v5.143 bug.');
    });

    test('handles empty graph gracefully', () {
      final filtered = buildFilteredGraph(
        allPersons: <Map<String, dynamic>>[],
        allRelationships: <Map<String, dynamic>>[],
        effectivePositions: <String, Offset>{},
        hiddenIds: <String>{},
      );

      expect(filtered.personCount, 0);
      expect(filtered.edgeCount, 0);
      expect(filtered.visiblePersonIds, isEmpty);
      expect(filtered.visibleRelationships, isEmpty);
    });

    test('700-node family with 22-node proximity set scales correctly', () {
      // This is the REAL scenario from the user's bug report:
      // 700 members, but only 22 have positions (post-proximity-RPC).
      // FilteredGraph must return 22 nodes + their edges, NOT 700.
      final allPersons = <Map<String, dynamic>>[
        for (var i = 0; i < 700; i++)
          {'id': 'p$i', 'name': 'Person $i'},
      ];
      // Only edges among the first 22 nodes (the proximity set).
      final allRelationships = <Map<String, dynamic>>[
        for (var i = 0; i < 21; i++)
          {
            'id': 'r$i',
            'fromPersonId': 'p$i',
            'toPersonId': 'p${i + 1}',
            'relationshipKey': 'parent',
          },
        // Plus 979 edges to non-proximity nodes (should be excluded).
        for (var i = 0; i < 979; i++)
          {
            'id': 'extra_r$i',
            'fromPersonId': 'p${100 + (i % 600)}',
            'toPersonId': 'p${200 + (i % 500)}',
            'relationshipKey': 'parent',
          },
      ];
      final effectivePositions = <String, Offset>{
        for (var i = 0; i < 22; i++)
          'p$i': Offset(i * 100.0, (i % 3) * 100.0),
      };

      final filtered = buildFilteredGraph(
        allPersons: allPersons,
        allRelationships: allRelationships,
        effectivePositions: effectivePositions,
        hiddenIds: <String>{},
      );

      // MUST return 22 nodes, not 700.
      expect(filtered.personCount, 22,
          reason: 'Proximity set is 22 nodes — FilteredGraph must '
              'return 22, not 700. This is the test that proves the '
              'graph scales with VISIBLE nodes, not total DB size.');

      // MUST return ~20 edges (the 21 parent edges among the first 22
      // nodes, minus any dedup), NOT 1000.
      expect(filtered.edgeCount, lessThanOrEqualTo(21),
          reason: 'Only ~21 edges connect the 22 proximity nodes. '
              'Got ${filtered.edgeCount} — if this is ~1000, the '
              'filtered graph is leaking non-proximity edges.');
    });
  });
}

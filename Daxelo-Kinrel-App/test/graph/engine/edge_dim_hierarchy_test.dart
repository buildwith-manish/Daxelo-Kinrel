// test/graph/engine/edge_dim_hierarchy_test.dart
//
// Unit tests for the edge dim hierarchy (Feature 2).
//
// Verifies the four cases of [computeDimmedEdgeIds]:
//   1. Search active  → dim edges NOT connected to any match.
//   2. Focus active   → dim edges NOT directly incident to the
//                       focused person (Isolate Connections).
//   3. Selection only → dim edges NOT directly incident to the
//                       selected node.
//   4. Nothing active → dim ALL edges (the new default-dim state).
//
// And the priority order: search > focus > selection > default-dim.
// Also verifies the "return null when nothing to dim" short-circuit.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/graph/data/graph_data_models.dart' show GraphEdgeData;
import 'package:kinrel/graph/engine/edge_dedup.dart' show DedupedEdge;
import 'package:kinrel/graph/engine/edge_dim_hierarchy.dart'
    show
        computeDimmedEdgeIds,
        computeDimmedEdgeIdsFromEdges,
        EdgeDimHierarchyInput;

void main() {
  // Build a small graph for the tests:
  //   A — B (spouse)
  //   A — C (parent)
  //   B — C (parent)
  //   C — D (parent)
  //   D — E (parent)
  //
  // Each edge is a distinct (sourceId, targetId) pair so the dim
  // computation can be checked per-edge.
  final edges = <GraphEdgeData>[
    GraphEdgeData(id: 'e1', sourceId: 'A', targetId: 'B', relationshipKey: 'spouse'),
    GraphEdgeData(id: 'e2', sourceId: 'A', targetId: 'C', relationshipKey: 'father'),
    GraphEdgeData(id: 'e3', sourceId: 'B', targetId: 'C', relationshipKey: 'mother'),
    GraphEdgeData(id: 'e4', sourceId: 'C', targetId: 'D', relationshipKey: 'father'),
    GraphEdgeData(id: 'e5', sourceId: 'D', targetId: 'E', relationshipKey: 'father'),
  ];

  group('v5.x (Feature 2) — Case 4: default-dim (nothing active)', () {
    test('when no search, no focus, no selection → ALL edges are dimmed',
        () {
      final dimmed = computeDimmedEdgeIdsFromEdges(
        edges,
        const EdgeDimHierarchyInput(),
      );
      expect(dimmed, isNotNull);
      expect(dimmed, hasLength(edges.length));
      for (final e in edges) {
        expect(dimmed, contains(e.id),
            reason: 'Default state must dim every edge (${e.id})');
      }
    });

    test('default-dim returns null on an empty edge list (nothing to dim)',
        () {
      final dimmed =
          computeDimmedEdgeIdsFromEdges(const [], const EdgeDimHierarchyInput());
      expect(dimmed, isNull,
          reason: 'Empty edge list → null (no dimming to apply)');
    });
  });

  group('v5.x (Feature 2) — Case 3: selection only (node tapped)', () {
    test('selecting node A brightens e1 (A-B) and e2 (A-C); the rest dim',
        () {
      final dimmed = computeDimmedEdgeIdsFromEdges(
        edges,
        const EdgeDimHierarchyInput(selectedNodeId: 'A'),
      );
      expect(dimmed, isNotNull);
      // e1 (A-B) and e2 (A-C) are bright → NOT in dimmed.
      expect(dimmed, isNot(contains('e1')));
      expect(dimmed, isNot(contains('e2')));
      // e3 (B-C), e4 (C-D), e5 (D-E) are NOT incident to A → dimmed.
      expect(dimmed, contains('e3'));
      expect(dimmed, contains('e4'));
      expect(dimmed, contains('e5'));
    });

    test('selecting node C brightens e2, e3, e4; e1 and e5 dim', () {
      final dimmed = computeDimmedEdgeIdsFromEdges(
        edges,
        const EdgeDimHierarchyInput(selectedNodeId: 'C'),
      );
      expect(dimmed, isNotNull);
      // Edges incident to C: e2 (A-C), e3 (B-C), e4 (C-D). Bright.
      expect(dimmed, isNot(contains('e2')));
      expect(dimmed, isNot(contains('e3')));
      expect(dimmed, isNot(contains('e4')));
      // e1 (A-B) and e5 (D-E) are NOT incident to C. Dimmed.
      expect(dimmed, contains('e1'));
      expect(dimmed, contains('e5'));
    });

    test(
        'selecting a node connected to ALL edges returns null '
        '(nothing to dim — every edge is bright)', () {
      // Pick a node that touches every edge — none in this graph,
      // so use a smaller graph where one node touches every edge.
      final starEdges = <GraphEdgeData>[
        GraphEdgeData(
            id: 's1', sourceId: 'center', targetId: 'A', relationshipKey: 'p'),
        GraphEdgeData(
            id: 's2', sourceId: 'center', targetId: 'B', relationshipKey: 'p'),
        GraphEdgeData(
            id: 's3', sourceId: 'center', targetId: 'C', relationshipKey: 'p'),
      ];
      final dimmed = computeDimmedEdgeIdsFromEdges(
        starEdges,
        const EdgeDimHierarchyInput(selectedNodeId: 'center'),
      );
      expect(dimmed, isNull,
          reason: 'When the selected node is connected to every edge, '
              'there is nothing to dim → null (painter short-circuits)');
    });
  });

  group('v5.x (Feature 2) — Case 2: focus (Isolate Connections)', () {
    test('focusing person A brightens only edges DIRECTLY incident to A', () {
      // Mirrors v5.66 BUG 2 FIX: edges between two 1st-degree
      // relatives (e.g. JD↔HD when isolating MA) are dimmed, NOT
      // bright. Only edges where the focused person is one of the
      // endpoints stay bright.
      final dimmed = computeDimmedEdgeIdsFromEdges(
        edges,
        const EdgeDimHierarchyInput(focusedPersonId: 'A'),
      );
      expect(dimmed, isNotNull);
      // e1 (A-B) and e2 (A-C) — A is an endpoint → bright.
      expect(dimmed, isNot(contains('e1')));
      expect(dimmed, isNot(contains('e2')));
      // e3 (B-C), e4 (C-D), e5 (D-E) — A is NOT an endpoint → dimmed.
      expect(dimmed, contains('e3'));
      expect(dimmed, contains('e4'));
      expect(dimmed, contains('e5'));
    });

    test('focusing person C brightens e2, e3, e4 only (1st-degree strict)', () {
      final dimmed = computeDimmedEdgeIdsFromEdges(
        edges,
        const EdgeDimHierarchyInput(focusedPersonId: 'C'),
      );
      expect(dimmed, isNotNull);
      expect(dimmed, isNot(contains('e2'))); // A-C
      expect(dimmed, isNot(contains('e3'))); // B-C
      expect(dimmed, isNot(contains('e4'))); // C-D
      expect(dimmed, contains('e1')); // A-B
      expect(dimmed, contains('e5')); // D-E
    });
  });

  group('v5.x (Feature 2) — Case 1: search active', () {
    test('search matching nodes {A, D} brightens edges connected to either',
        () {
      final dimmed = computeDimmedEdgeIdsFromEdges(
        edges,
        const EdgeDimHierarchyInput(
          searchIsActive: true,
          searchMatchNodeIds: {'A', 'D'},
        ),
      );
      expect(dimmed, isNotNull);
      // Edges connected to A or D: e1 (A-B), e2 (A-C), e4 (C-D), e5 (D-E).
      // Bright: e1, e2, e4, e5. Dimmed: e3 (B-C, neither endpoint matches).
      expect(dimmed, isNot(contains('e1')));
      expect(dimmed, isNot(contains('e2')));
      expect(dimmed, isNot(contains('e4')));
      expect(dimmed, isNot(contains('e5')));
      expect(dimmed, contains('e3'));
    });

    test('search matching all nodes returns null (nothing to dim)', () {
      final dimmed = computeDimmedEdgeIdsFromEdges(
        edges,
        const EdgeDimHierarchyInput(
          searchIsActive: true,
          searchMatchNodeIds: {'A', 'B', 'C', 'D', 'E'},
        ),
      );
      expect(dimmed, isNull,
          reason: 'When every edge has at least one endpoint in the '
              'match set, nothing is dimmed → null');
    });

    test('search inactive (matches present but isActive=false) falls through',
        () {
      // When searchIsActive is false, the matches are ignored — the
      // helper falls through to focus / selection / default-dim.
      final dimmed = computeDimmedEdgeIdsFromEdges(
        edges,
        const EdgeDimHierarchyInput(
          searchIsActive: false,
          searchMatchNodeIds: {'A', 'D'},
        ),
      );
      // Nothing else active → default-dim → ALL edges dimmed.
      expect(dimmed, isNotNull);
      expect(dimmed, hasLength(edges.length));
    });
  });

  group('v5.x (Feature 2) — priority order', () {
    test('search takes priority over focus (when both are active)', () {
      // Focus on A would brighten e1, e2. Search on {D} brightens
      // e4, e5. With search active AND focus active, search wins →
      // e4, e5 bright; everything else dimmed (including e1, e2 which
      // focus alone would have kept bright).
      final dimmed = computeDimmedEdgeIdsFromEdges(
        edges,
        const EdgeDimHierarchyInput(
          searchIsActive: true,
          searchMatchNodeIds: {'D'},
          focusedPersonId: 'A',
        ),
      );
      expect(dimmed, isNotNull);
      expect(dimmed, isNot(contains('e4'))); // C-D
      expect(dimmed, isNot(contains('e5'))); // D-E
      // Search wins → focus's brightened edges are NOT bright:
      expect(dimmed, contains('e1')); // A-B (would be bright under focus alone)
      expect(dimmed, contains('e2')); // A-C (would be bright under focus alone)
      expect(dimmed, contains('e3')); // B-C
    });

    test('focus takes priority over selection (when both are active)', () {
      // Focus on A brightens e1, e2. Selection of D brightens e4, e5.
      // With both active, focus wins → e1, e2 bright; everything else
      // dimmed (including e4, e5 which selection alone would have kept
      // bright).
      final dimmed = computeDimmedEdgeIdsFromEdges(
        edges,
        const EdgeDimHierarchyInput(
          focusedPersonId: 'A',
          selectedNodeId: 'D',
        ),
      );
      expect(dimmed, isNotNull);
      expect(dimmed, isNot(contains('e1'))); // A-B
      expect(dimmed, isNot(contains('e2'))); // A-C
      // Focus wins → selection's brightened edges are NOT bright:
      expect(dimmed, contains('e4')); // C-D
      expect(dimmed, contains('e5')); // D-E
      expect(dimmed, contains('e3')); // B-C
    });

    test('selection beats default-dim (no focus/search active)', () {
      // Default-dim alone → ALL edges dimmed. With selection of A,
      // e1, e2 bright; rest dimmed.
      final dimmedDefault = computeDimmedEdgeIdsFromEdges(
        edges,
        const EdgeDimHierarchyInput(),
      );
      final dimmedWithSelection = computeDimmedEdgeIdsFromEdges(
        edges,
        const EdgeDimHierarchyInput(selectedNodeId: 'A'),
      );
      expect(dimmedDefault, hasLength(edges.length));
      expect(dimmedWithSelection, hasLength(3));
      // Selection brightens e1, e2 — they leave the dimmed set.
      expect(dimmedDefault!.contains('e1'), isTrue);
      expect(dimmedDefault.contains('e2'), isTrue);
      expect(dimmedWithSelection!.contains('e1'), isFalse);
      expect(dimmedWithSelection.contains('e2'), isFalse);
    });
  });

  group('v5.x (Feature 2) — parity with DedupedEdge overload', () {
    test(
        'computeDimmedEdgeIds (DedupedEdge) and '
        'computeDimmedEdgeIdsFromEdges (GraphEdgeData) agree', () {
      // The two overloads must produce the same set for the same
      // inputs. The DedupedEdge overload wraps each GraphEdgeData
      // with lateralOffset=0 / parallelCount=1 — the dim logic
      // only reads edge.id / edge.sourceId / edge.targetId, so the
      // results must match.
      final dedupedEdges = edges
          .map((e) => DedupedEdge(edge: e, lateralOffset: 0.0, parallelCount: 1))
          .toList();
      for (final input in <EdgeDimHierarchyInput>[
        const EdgeDimHierarchyInput(),
        const EdgeDimHierarchyInput(selectedNodeId: 'A'),
        const EdgeDimHierarchyInput(focusedPersonId: 'C'),
        const EdgeDimHierarchyInput(
            searchIsActive: true, searchMatchNodeIds: {'B'}),
      ]) {
        final fromEdges = computeDimmedEdgeIdsFromEdges(edges, input);
        final fromDeduped = computeDimmedEdgeIds(dedupedEdges, input);
        expect(fromDeduped, equals(fromEdges),
            reason: 'Both overloads must agree for input $input');
      }
    });
  });
}

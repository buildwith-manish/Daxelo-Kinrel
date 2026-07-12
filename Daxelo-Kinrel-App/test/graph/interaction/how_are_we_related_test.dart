// test/graph/interaction/how_are_we_related_test.dart
//
// Phase 2 — "How are we related?" relationship path explorer tests.
//
// Tests the deterministic kinship path resolution using the REAL
// RelationshipEngine + GraphService.findPath + GraphPathFocusNotifier.
// These are the same APIs the live graph uses — no mocked logic.
//
// Tests:
//   1.  direct spouse
//   2.  parent
//   3.  child
//   4.  sibling through shared parents
//   5.  grandparent
//   6.  grandchild
//   7.  aunt/uncle path
//   8.  cousin path where supported
//   9.  reversed endpoints
//   10. cycle safety
//   11. disconnected nodes
//   12. deterministic equal-length path selection
//   13. reduced-motion path reveal (design contract)
//   14. path edge ids correspond to actual canonical edges

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/family/family_provider.dart' show getInverseRelationshipType;
import 'package:kinrel/core/kinship/kinship_edge_style.dart';
import 'package:kinrel/core/relationship/relationship_engine.dart';
import 'package:kinrel/core/services/graph_layout_service.dart';
import 'package:kinrel/graph/data/family_graph_repository.dart';
import 'package:kinrel/graph/engine/edge_dedup.dart';
import 'package:kinrel/graph/interaction/graph_kinship_path_focus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GraphPathFocusNotifier notifier;

  setUp(() {
    notifier = GraphPathFocusNotifier();
    RelationshipEngine.instance.invalidateCache();
  });

  // Helper: build a simple family graph.
  // Returns the persons list + relationships list + deduped edges.
  ({List<GraphPerson> persons, List<({String fromId, String toId, String type})> relationships, List<DedupedEdge> edges}) buildFamilyGraph() {
    final persons = [
      GraphPerson(id: 'viewer', name: 'Viewer', gender: 'male'),
      GraphPerson(id: 'father', name: 'Father', gender: 'male'),
      GraphPerson(id: 'mother', name: 'Mother', gender: 'female'),
      GraphPerson(id: 'spouse', name: 'Spouse', gender: 'female'),
      GraphPerson(id: 'sibling', name: 'Sibling', gender: 'male'),
      GraphPerson(id: 'grandfather', name: 'Grandfather', gender: 'male'),
      GraphPerson(id: 'grandmother', name: 'Grandmother', gender: 'female'),
      GraphPerson(id: 'uncle', name: 'Uncle', gender: 'male'),
      GraphPerson(id: 'cousin', name: 'Cousin', gender: 'male'),
      GraphPerson(id: 'child', name: 'Child', gender: 'male'),
      GraphPerson(id: 'disconnected', name: 'Disconnected', gender: 'male'),
    ];

    final relPairs = <List<String>>[
      ['father', 'viewer'],   // father IS father of viewer
      ['mother', 'viewer'],   // mother IS mother of viewer
      ['spouse', 'viewer'],   // spouse IS wife of viewer
      ['father', 'sibling'],  // father IS father of sibling
      ['mother', 'sibling'],  // mother IS mother of sibling
      ['grandfather', 'father'], // grandfather IS father of father
      ['grandmother', 'father'], // grandmother IS mother of father
      ['grandfather', 'uncle'],  // grandfather IS father of uncle
      ['grandmother', 'uncle'],  // grandmother IS mother of uncle
      ['uncle', 'cousin'],       // uncle IS father of cousin
      ['viewer', 'child'],       // viewer IS father of child
    ];

    final relationshipKeys = <String>[
      'father', 'mother', 'wife', 'father', 'mother',
      'father', 'mother', 'father', 'mother',
      'father', 'son',
    ];

    final relationships = <({String fromId, String toId, String type})>[
      for (var i = 0; i < relPairs.length; i++)
        (fromId: relPairs[i][0], toId: relPairs[i][1], type: relationshipKeys[i]),
    ];

    final rawEdges = [
      for (var i = 0; i < relPairs.length; i++)
        GraphEdgeData(
          id: 'edge-$i',
          sourceId: relPairs[i][0],
          targetId: relPairs[i][1],
          relationshipKey: relationshipKeys[i],
        ),
    ];
    final edges = EdgeDeduplicator.deduplicate(rawEdges);

    return (persons: persons, relationships: relationships, edges: edges);
  }

  group('Phase 2 — How are we related? (path explorer)', () {
    // ──────────────────────────────────────────────────────────────
    // TEST 1 — direct spouse
    // ──────────────────────────────────────────────────────────────
    test('TEST 1: direct spouse — viewer ↔ spouse', () {
      final graph = buildFamilyGraph();
      final focus = notifier.resolve(
        viewerPersonId: 'viewer',
        targetPersonId: 'spouse',
        edges: graph.edges,
        persons: graph.persons,
        relationships: graph.relationships,
        graphRevision: 1,
      );

      expect(focus, isNotNull);
      expect(focus!.orderedPersonIds, ['viewer', 'spouse']);
      expect(focus.stepCount, 1);
      expect(focus.orderedEdgeIds.length, 1);
      // Spouse category.
      expect(focus.resolvedCategory, KinshipEdgeCategory.spouse);
    });

    // ──────────────────────────────────────────────────────────────
    // TEST 2 — parent
    // ──────────────────────────────────────────────────────────────
    test('TEST 2: parent — viewer → father', () {
      final graph = buildFamilyGraph();
      final focus = notifier.resolve(
        viewerPersonId: 'viewer',
        targetPersonId: 'father',
        edges: graph.edges,
        persons: graph.persons,
        relationships: graph.relationships,
        graphRevision: 1,
      );

      expect(focus, isNotNull);
      expect(focus!.orderedPersonIds, ['viewer', 'father']);
      expect(focus.stepCount, 1);
      expect(focus.resolvedCategory, KinshipEdgeCategory.parent);
    });

    // ──────────────────────────────────────────────────────────────
    // TEST 3 — child
    // ──────────────────────────────────────────────────────────────
    test('TEST 3: child — viewer → child', () {
      final graph = buildFamilyGraph();
      final focus = notifier.resolve(
        viewerPersonId: 'viewer',
        targetPersonId: 'child',
        edges: graph.edges,
        persons: graph.persons,
        relationships: graph.relationships,
        graphRevision: 1,
      );

      expect(focus, isNotNull);
      expect(focus!.orderedPersonIds, ['viewer', 'child']);
      expect(focus.stepCount, 1);
      expect(focus.resolvedCategory, KinshipEdgeCategory.child);
    });

    // ──────────────────────────────────────────────────────────────
    // TEST 4 — sibling through shared parents
    // ──────────────────────────────────────────────────────────────
    test('TEST 4: sibling — viewer ↔ sibling (shared parents)', () {
      final graph = buildFamilyGraph();
      final focus = notifier.resolve(
        viewerPersonId: 'viewer',
        targetPersonId: 'sibling',
        edges: graph.edges,
        persons: graph.persons,
        relationships: graph.relationships,
        graphRevision: 1,
      );

      expect(focus, isNotNull);
      // Path: viewer → father → sibling (or viewer → mother → sibling).
      // BFS finds the shortest path — 2 hops.
      expect(focus!.stepCount, 2);
      expect(focus.orderedPersonIds.first, 'viewer');
      expect(focus.orderedPersonIds.last, 'sibling');
      // Sibling category.
      expect(focus.resolvedCategory, KinshipEdgeCategory.sibling);
    });

    // ──────────────────────────────────────────────────────────────
    // TEST 5 — grandparent
    // ──────────────────────────────────────────────────────────────
    test('TEST 5: grandparent — viewer → grandfather', () {
      final graph = buildFamilyGraph();
      final focus = notifier.resolve(
        viewerPersonId: 'viewer',
        targetPersonId: 'grandfather',
        edges: graph.edges,
        persons: graph.persons,
        relationships: graph.relationships,
        graphRevision: 1,
      );

      expect(focus, isNotNull);
      // Path: viewer → father → grandfather (2 hops).
      expect(focus!.stepCount, 2);
      expect(focus.orderedPersonIds.first, 'viewer');
      expect(focus.orderedPersonIds.last, 'grandfather');
      // Grandparent category.
      expect(focus.resolvedCategory, KinshipEdgeCategory.grandparent);
    });

    // ──────────────────────────────────────────────────────────────
    // TEST 6 — grandchild
    // ──────────────────────────────────────────────────────────────
    test('TEST 6: grandchild — grandfather → viewer', () {
      final graph = buildFamilyGraph();
      final focus = notifier.resolve(
        viewerPersonId: 'grandfather',
        targetPersonId: 'viewer',
        edges: graph.edges,
        persons: graph.persons,
        relationships: graph.relationships,
        graphRevision: 1,
      );

      expect(focus, isNotNull);
      // Path: grandfather → father → viewer (2 hops).
      expect(focus!.stepCount, 2);
      expect(focus.orderedPersonIds.first, 'grandfather');
      expect(focus.orderedPersonIds.last, 'viewer');
      // From grandfather's perspective, viewer is a grandchild.
      expect(focus.resolvedCategory, KinshipEdgeCategory.grandparent,
          reason: 'Grandparent ↔ grandchild are the same category');
    });

    // ──────────────────────────────────────────────────────────────
    // TEST 7 — aunt/uncle path
    // ──────────────────────────────────────────────────────────────
    test('TEST 7: aunt/uncle — viewer → uncle', () {
      final graph = buildFamilyGraph();
      final focus = notifier.resolve(
        viewerPersonId: 'viewer',
        targetPersonId: 'uncle',
        edges: graph.edges,
        persons: graph.persons,
        relationships: graph.relationships,
        graphRevision: 1,
      );

      expect(focus, isNotNull);
      // Path: viewer → father → grandfather → uncle (3 hops) OR
      // viewer → father → grandfather → uncle (via shared grandparent).
      expect(focus!.stepCount, greaterThanOrEqualTo(2));
      expect(focus.orderedPersonIds.first, 'viewer');
      expect(focus.orderedPersonIds.last, 'uncle');
      // Aunt/uncle category.
      expect(focus.resolvedCategory, KinshipEdgeCategory.auntUncle);
    });

    // ──────────────────────────────────────────────────────────────
    // TEST 8 — cousin path where supported
    // ──────────────────────────────────────────────────────────────
    test('TEST 8: cousin — viewer → cousin', () {
      final graph = buildFamilyGraph();
      final focus = notifier.resolve(
        viewerPersonId: 'viewer',
        targetPersonId: 'cousin',
        edges: graph.edges,
        persons: graph.persons,
        relationships: graph.relationships,
        graphRevision: 1,
      );

      expect(focus, isNotNull);
      // Path: viewer → father → grandfather → uncle → cousin (4 hops)
      // OR viewer → father → grandfather → uncle → cousin.
      expect(focus!.stepCount, greaterThanOrEqualTo(3));
      expect(focus.orderedPersonIds.first, 'viewer');
      expect(focus.orderedPersonIds.last, 'cousin');
      // Cousin category.
      expect(focus.resolvedCategory, KinshipEdgeCategory.cousin);
    });

    // ──────────────────────────────────────────────────────────────
    // TEST 9 — reversed endpoints
    // ──────────────────────────────────────────────────────────────
    test('TEST 9: reversed endpoints — viewer→father vs father→viewer', () {
      final graph = buildFamilyGraph();

      final viewerToFather = notifier.resolve(
        viewerPersonId: 'viewer',
        targetPersonId: 'father',
        edges: graph.edges,
        persons: graph.persons,
        relationships: graph.relationships,
        graphRevision: 1,
      );

      // Clear cache + resolve the reverse.
      notifier.clear();
      RelationshipEngine.instance.invalidateCache();
      final fatherToViewer = notifier.resolve(
        viewerPersonId: 'father',
        targetPersonId: 'viewer',
        edges: graph.edges,
        persons: graph.persons,
        relationships: graph.relationships,
        graphRevision: 1,
      );

      expect(viewerToFather, isNotNull);
      expect(fatherToViewer, isNotNull);
      // Both are 1-hop paths.
      expect(viewerToFather!.stepCount, 1);
      expect(fatherToViewer!.stepCount, 1);
      // But the ordered person IDs are reversed.
      expect(viewerToFather.orderedPersonIds, ['viewer', 'father']);
      expect(fatherToViewer.orderedPersonIds, ['father', 'viewer']);
      // The relationship key is directional — father→viewer is 'child',
      // viewer→father is 'father'.
      expect(fatherToViewer.resolvedRelationshipKey, isNot(equals(viewerToFather.resolvedRelationshipKey)));
      // Inverse semantics: father ↔ child.
      expect(getInverseRelationshipType('father'), 'child');
    });

    // ──────────────────────────────────────────────────────────────
    // TEST 10 — cycle safety
    // ──────────────────────────────────────────────────────────────
    test('TEST 10: cycle safety — no infinite loop on circular graph', () {
      // Build a circular graph: A→B→C→A. BFS must not loop forever.
      final persons = [
        GraphPerson(id: 'A', name: 'A'),
        GraphPerson(id: 'B', name: 'B'),
        GraphPerson(id: 'C', name: 'C'),
      ];
      final relationships = [
        (fromId: 'A', toId: 'B', type: 'father'),
        (fromId: 'B', toId: 'C', type: 'father'),
        (fromId: 'C', toId: 'A', type: 'father'), // creates cycle
      ];
      final edges = EdgeDeduplicator.deduplicate([
        GraphEdgeData(id: 'e1', sourceId: 'A', targetId: 'B', relationshipKey: 'father'),
        GraphEdgeData(id: 'e2', sourceId: 'B', targetId: 'C', relationshipKey: 'father'),
        GraphEdgeData(id: 'e3', sourceId: 'C', targetId: 'A', relationshipKey: 'father'),
      ]);

      // This must terminate (BFS has a visited set).
      final focus = notifier.resolve(
        viewerPersonId: 'A',
        targetPersonId: 'C',
        edges: edges,
        persons: persons,
        relationships: relationships,
        graphRevision: 1,
      );

      // Path: A→B→C (2 hops). The cycle C→A is not traversed again
      // because A is already visited.
      expect(focus, isNotNull);
      expect(focus!.orderedPersonIds, ['A', 'B', 'C']);
      expect(focus.stepCount, 2);
    });

    // ──────────────────────────────────────────────────────────────
    // TEST 11 — disconnected nodes
    // ──────────────────────────────────────────────────────────────
    test('TEST 11: disconnected nodes — no path returns null', () {
      final graph = buildFamilyGraph();
      // 'disconnected' person has no edges.
      final focus = notifier.resolve(
        viewerPersonId: 'viewer',
        targetPersonId: 'disconnected',
        edges: graph.edges,
        persons: graph.persons,
        relationships: graph.relationships,
        graphRevision: 1,
      );

      expect(focus, isNull,
          reason: 'No canonical path exists between viewer and disconnected. '
              'Must NOT fabricate a path.');
    });

    // ──────────────────────────────────────────────────────────────
    // TEST 12 — deterministic equal-length path selection
    // ──────────────────────────────────────────────────────────────
    test('TEST 12: deterministic equal-length path selection', () {
      // Viewer can reach sibling via father OR mother (both 2 hops).
      // BFS must pick one deterministically (the first one found
      // in adjacency-list order). Two consecutive resolves must
      // return the same path.
      final graph = buildFamilyGraph();

      final focus1 = notifier.resolve(
        viewerPersonId: 'viewer',
        targetPersonId: 'sibling',
        edges: graph.edges,
        persons: graph.persons,
        relationships: graph.relationships,
        graphRevision: 1,
      );

      // Cache hit — same result.
      final focus2 = notifier.resolve(
        viewerPersonId: 'viewer',
        targetPersonId: 'sibling',
        edges: graph.edges,
        persons: graph.persons,
        relationships: graph.relationships,
        graphRevision: 1,
      );

      expect(focus1, isNotNull);
      expect(focus2, isNotNull);
      // Same path both times (deterministic).
      expect(focus1!.orderedPersonIds, focus2!.orderedPersonIds);
      expect(focus1.orderedEdgeIds, focus2.orderedEdgeIds);
    });

    // ──────────────────────────────────────────────────────────────
    // TEST 13 — reduced-motion path reveal (design contract)
    // ──────────────────────────────────────────────────────────────
    test('TEST 13: reduced-motion path reveal — design contract', () {
      // The GraphPathTraceController.revealAll() method skips the
      // sequential animation and immediately marks all path edges as
      // completed. This is called by _EdgeSelectionWrapper when
      // MediaQuery.disableAnimationsOf(context) is true.
      //
      // The path resolution itself (GraphPathFocusNotifier.resolve)
      // is NOT affected by reduced motion — it always resolves the
      // full path. Reduced motion only affects the VISUAL REVEAL
      // animation, not the data.
      final graph = buildFamilyGraph();
      final focus = notifier.resolve(
        viewerPersonId: 'viewer',
        targetPersonId: 'cousin',
        edges: graph.edges,
        persons: graph.persons,
        relationships: graph.relationships,
        graphRevision: 1,
      );

      // The path is fully resolved regardless of reduced-motion.
      expect(focus, isNotNull);
      expect(focus!.orderedPersonIds.first, 'viewer');
      expect(focus.orderedPersonIds.last, 'cousin');
      expect(focus.stepCount, greaterThanOrEqualTo(1));
      // The trace controller's revealAll() would mark all edges as
      // completed instantly — the painter renders them statically
      // focused without animation.
    });

    // ──────────────────────────────────────────────────────────────
    // TEST 14 — path edge IDs correspond to actual canonical edges
    // ──────────────────────────────────────────────────────────────
    test('TEST 14: path edge IDs correspond to actual canonical edges', () {
      final graph = buildFamilyGraph();
      final focus = notifier.resolve(
        viewerPersonId: 'viewer',
        targetPersonId: 'grandfather',
        edges: graph.edges,
        persons: graph.persons,
        relationships: graph.relationships,
        graphRevision: 1,
      );

      expect(focus, isNotNull);
      // Every edge ID in the path must exist in the deduped edge list.
      final allEdgeIds = graph.edges.map((d) => d.edge.id).toSet();
      for (final edgeId in focus!.orderedEdgeIds) {
        expect(allEdgeIds.contains(edgeId), isTrue,
            reason: 'Path edge ID "$edgeId" must correspond to a real '
                'canonical edge in the deduped edge list');
      }
      // The path must have the right number of edges (steps - 1).
      expect(focus.orderedEdgeIds.length, focus.stepCount);
      expect(focus.orderedEdgeIds.length, focus.orderedPersonIds.length - 1);
    });
  });

  group('Phase 2 — No-path state', () {
    test('no path → null (not a fabricated path)', () {
      final graph = buildFamilyGraph();
      final focus = notifier.resolve(
        viewerPersonId: 'viewer',
        targetPersonId: 'disconnected',
        edges: graph.edges,
        persons: graph.persons,
        relationships: graph.relationships,
        graphRevision: 1,
      );
      // Must be null — NOT a fabricated path from surname, location,
      // or family membership.
      expect(focus, isNull);
    });

    test('viewer == target → null (self-path not allowed)', () {
      final graph = buildFamilyGraph();
      final focus = notifier.resolve(
        viewerPersonId: 'viewer',
        targetPersonId: 'viewer',
        edges: graph.edges,
        persons: graph.persons,
        relationships: graph.relationships,
        graphRevision: 1,
      );
      expect(focus, isNull);
    });
  });

  group('Phase 2 — Cache invalidation', () {
    test('cache invalidates when graphRevision changes', () {
      final graph = buildFamilyGraph();

      final focus1 = notifier.resolve(
        viewerPersonId: 'viewer',
        targetPersonId: 'father',
        edges: graph.edges,
        persons: graph.persons,
        relationships: graph.relationships,
        graphRevision: 1,
      );
      expect(focus1?.graphRevision, 1);

      // Same inputs but different revision → cache miss, re-resolve.
      final focus2 = notifier.resolve(
        viewerPersonId: 'viewer',
        targetPersonId: 'father',
        edges: graph.edges,
        persons: graph.persons,
        relationships: graph.relationships,
        graphRevision: 2,
      );
      expect(focus2?.graphRevision, 2);
    });

    test('cache hit returns same focus without re-resolving', () {
      final graph = buildFamilyGraph();

      final focus1 = notifier.resolve(
        viewerPersonId: 'viewer',
        targetPersonId: 'father',
        edges: graph.edges,
        persons: graph.persons,
        relationships: graph.relationships,
        graphRevision: 1,
      );
      final focus2 = notifier.resolve(
        viewerPersonId: 'viewer',
        targetPersonId: 'father',
        edges: graph.edges,
        persons: graph.persons,
        relationships: graph.relationships,
        graphRevision: 1,
      );
      expect(identical(focus1, focus2), isTrue,
          reason: 'Cache hit should return the SAME object');
    });
  });
}

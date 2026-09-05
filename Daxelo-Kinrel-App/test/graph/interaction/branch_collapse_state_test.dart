// test/graph/interaction/branch_collapse_state_test.dart
//
// Phase 4 — Intelligent Family Branch Collapsing tests.
//
// Tests:
//   1. small family remains expanded
//   2. distant large branch collapses
//   3. focus neighbourhood stays visible
//   4. active path overrides collapse
//   5. search match overrides or marks collapse
//   6. expansion state persistence
//   7. canonical topology unchanged
//   8. deterministic branch counts

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/graph/interaction/branch_collapse_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BranchCollapseNotifier notifier;

  setUp(() {
    notifier = BranchCollapseNotifier();
  });

  // Helper: build a large family graph for collapse testing.
  // Returns persons + edges as the tuples the notifier expects.
  //
  // v102 FIX: The original test data had edge directions that made
  // person-1 (father) an ANCESTOR target, not a branch root — edges
  // went FROM grandfather TO father, so `childrenOf[father]` was
  // empty and `_descendantsExcluding('person-1', ...)` returned
  // nothing. computeCollapse only collapses DESCENDANT subtrees, so
  // the test never found a branch to collapse.
  //
  // Fixed: person-1 (father) now has a large DESCENDANT subtree —
  // his children (10-19), their children (20-29), and grandchildren
  // (30-39). Edge direction is parent → child (fromId = parent).
  ({Set<String> persons, List<({String fromId, String toId, String edgeId, String relationshipKey})> edges}) buildLargeFamily() {
    final persons = <String>{};
    final edges = <({String fromId, String toId, String edgeId, String relationshipKey})>[];

    // Anchor + immediate family (10 persons)
    for (var i = 0; i < 10; i++) {
      persons.add('person-$i');
    }
    // Anchor (0) ← father (1), mother (2), spouse (3)
    edges.add((fromId: 'person-1', toId: 'person-0', edgeId: 'e1', relationshipKey: 'father'));
    edges.add((fromId: 'person-2', toId: 'person-0', edgeId: 'e2', relationshipKey: 'mother'));
    edges.add((fromId: 'person-3', toId: 'person-0', edgeId: 'e3', relationshipKey: 'wife'));

    // Father's (1) DESCENDANT subtree (30 persons) — a large distant branch.
    // person-1 → children (10-19)
    for (var i = 10; i < 40; i++) {
      persons.add('person-$i');
    }
    for (var i = 10; i < 20; i++) {
      edges.add((fromId: 'person-1', toId: 'person-$i', edgeId: 'e${i + 2}', relationshipKey: 'son'));
    }
    // children (10-19) → grandchildren (20-29)
    for (var i = 20; i < 30; i++) {
      final parent = 10 + (i - 20) ~/ 1;
      edges.add((fromId: 'person-$parent', toId: 'person-$i', edgeId: 'e${i + 12}', relationshipKey: 'son'));
    }
    // grandchildren (20-29) → great-grandchildren (30-39)
    for (var i = 30; i < 40; i++) {
      final parent = 20 + (i - 30) ~/ 1;
      edges.add((fromId: 'person-$parent', toId: 'person-$i', edgeId: 'e${i + 22}', relationshipKey: 'son'));
    }
    // v5.123: great-great-grandchildren (40-59) — the family now has 60
    // members so computeCollapse's budget bypass (≤ kNodeBudget = 50,
    // was '< 30') does not swallow the collapse cases below.
    for (var i = 40; i < 60; i++) {
      persons.add('person-$i');
      final parent = 30 + (i - 40) ~/ 2;
      edges.add((fromId: 'person-$parent', toId: 'person-$i', edgeId: 'e${i + 32}', relationshipKey: 'son'));
    }

    return (persons: persons, edges: edges);
  }

  group('Phase 4 — Small family remains expanded', () {
    test('TEST 1: family with < 30 members is never collapsed', () {
      final persons = {'A', 'B', 'C', 'D', 'E'};
      final edges = [
        (fromId: 'A', toId: 'B', edgeId: 'e1', relationshipKey: 'father'),
        (fromId: 'A', toId: 'C', edgeId: 'e2', relationshipKey: 'mother'),
      ];

      notifier.computeCollapse(
        allPersons: persons,
        allEdges: edges,
        focusPersonId: 'A',
        firstDegreeIds: {'B', 'C'},
        secondDegreeIds: const {},
        familyMemberCount: 5,
      );

      expect(notifier.state.collapsedBranches, isEmpty,
          reason: 'Small families must not be collapsed');
    });
  });

  group('Phase 4 — Distant large branch collapses', () {
    test('TEST 2: large distant branch (>= 5 members) is collapsed', () {
      final graph = buildLargeFamily();

      // Focus on the anchor (person-0). Father (person-1) is first-degree.
      // Father's extended family (persons 10-39) is distant.
      notifier.computeCollapse(
        allPersons: graph.persons,
        allEdges: graph.edges,
        focusPersonId: 'person-0',
        firstDegreeIds: {'person-1', 'person-2', 'person-3'},
        secondDegreeIds: const {},
        familyMemberCount: graph.persons.length,
      );

      // The father's extended family should be collapsed.
      expect(notifier.state.collapsedBranches, isNotEmpty,
          reason: 'Large distant branches should be collapsed');

      // The collapsed branch should hide >= 5 members.
      for (final branch in notifier.state.collapsedBranches) {
        expect(branch.hiddenCount, greaterThanOrEqualTo(5),
            reason: 'Only branches with >= 5 hidden members should collapse');
      }
    });
  });

  group('Phase 4 — Focus neighbourhood stays visible', () {
    test('TEST 3: focus person + first-degree are never hidden', () {
      final graph = buildLargeFamily();

      notifier.computeCollapse(
        allPersons: graph.persons,
        allEdges: graph.edges,
        focusPersonId: 'person-0',
        firstDegreeIds: {'person-1', 'person-2', 'person-3'},
        secondDegreeIds: const {},
        familyMemberCount: graph.persons.length,
      );

      final allHidden = notifier.state.allHiddenMemberIds;
      expect(allHidden.contains('person-0'), isFalse,
          reason: 'Focus person must never be hidden');
      expect(allHidden.contains('person-1'), isFalse,
          reason: 'First-degree (father) must never be hidden');
      expect(allHidden.contains('person-2'), isFalse,
          reason: 'First-degree (mother) must never be hidden');
      expect(allHidden.contains('person-3'), isFalse,
          reason: 'First-degree (spouse) must never be hidden');
    });
  });

  group('Phase 4 — Active path overrides collapse', () {
    test('TEST 4: path nodes are never hidden by collapse', () {
      final graph = buildLargeFamily();

      // Path: anchor → father → grandfather (person-10 is distant)
      final pathNodeIds = {'person-0', 'person-1', 'person-10'};

      notifier.computeCollapse(
        allPersons: graph.persons,
        allEdges: graph.edges,
        focusPersonId: 'person-0',
        firstDegreeIds: {'person-1', 'person-2', 'person-3'},
        secondDegreeIds: const {},
        pathNodeIds: pathNodeIds,
        familyMemberCount: graph.persons.length,
      );

      final allHidden = notifier.state.allHiddenMemberIds;
      expect(allHidden.contains('person-10'), isFalse,
          reason: 'Path nodes must never be hidden — path overrides collapse');
    });
  });

  group('Phase 4 — Search match overrides collapse', () {
    test('TEST 5: search match nodes are never hidden', () {
      final graph = buildLargeFamily();

      // Search for a person deep in the father's extended family
      final searchMatchIds = {'person-25'};

      notifier.computeCollapse(
        allPersons: graph.persons,
        allEdges: graph.edges,
        focusPersonId: 'person-0',
        firstDegreeIds: {'person-1', 'person-2', 'person-3'},
        secondDegreeIds: const {},
        searchMatchIds: searchMatchIds,
        familyMemberCount: graph.persons.length,
      );

      final allHidden = notifier.state.allHiddenMemberIds;
      expect(allHidden.contains('person-25'), isFalse,
          reason: 'Search match must never be hidden — search overrides collapse');
    });
  });

  group('Phase 4 — Expansion state persistence', () {
    test('TEST 6: expanded branch root is not re-collapsed', () {
      final graph = buildLargeFamily();

      // First computation — collapses father's branch.
      notifier.computeCollapse(
        allPersons: graph.persons,
        allEdges: graph.edges,
        focusPersonId: 'person-0',
        firstDegreeIds: {'person-1', 'person-2', 'person-3'},
        secondDegreeIds: const {},
        familyMemberCount: graph.persons.length,
      );
      expect(notifier.state.collapsedBranches, isNotEmpty);

      // Find the root of the first collapsed branch.
      final rootId = notifier.state.collapsedBranches.first.rootPersonId;

      // User expands the branch.
      notifier.expandBranch(rootId);

      // Re-compute — the expanded branch should NOT be re-collapsed.
      notifier.computeCollapse(
        allPersons: graph.persons,
        allEdges: graph.edges,
        focusPersonId: 'person-0',
        firstDegreeIds: {'person-1', 'person-2', 'person-3'},
        secondDegreeIds: const {},
        familyMemberCount: graph.persons.length,
      );

      final stillCollapsed = notifier.state.collapsedBranches
          .where((b) => b.rootPersonId == rootId)
          .isNotEmpty;
      expect(stillCollapsed, isFalse,
          reason: 'User-expanded branches must not be re-collapsed');
    });

    test('clearAll resets expansion state', () {
      notifier.expandBranch('person-1');
      expect(notifier.state.expandedBranchRoots, contains('person-1'));

      notifier.clearAll();
      expect(notifier.state.expandedBranchRoots, isEmpty);
      expect(notifier.state.collapsedBranches, isEmpty);
    });
  });

  group('Phase 4 — Canonical topology unchanged', () {
    test('TEST 7: collapse does not modify the input person set', () {
      final graph = buildLargeFamily();
      final originalPersonCount = graph.persons.length;
      final originalEdgeCount = graph.edges.length;

      notifier.computeCollapse(
        allPersons: graph.persons,
        allEdges: graph.edges,
        focusPersonId: 'person-0',
        firstDegreeIds: {'person-1', 'person-2', 'person-3'},
        secondDegreeIds: const {},
        familyMemberCount: graph.persons.length,
      );

      // The input sets are unchanged — collapse is presentation-only.
      expect(graph.persons.length, originalPersonCount);
      expect(graph.edges.length, originalEdgeCount);
    });

    test('TEST 7: collapse state is separate from graph data', () {
      // BranchCollapseState has NO mutation methods on graph data.
      // It only holds: collapsedBranches, expandedBranchRoots, revision.
      final state = BranchCollapseState(
        collapsedBranches: const [],
        expandedBranchRoots: {'A'},
        revision: 1,
      );
      expect(state.collapsedBranches, isEmpty);
      expect(state.expandedBranchRoots, {'A'});
      // No methods exist to mutate relationships or persons.
    });
  });

  group('Phase 4 — Deterministic branch counts', () {
    test('TEST 8: same inputs produce same branch counts', () {
      final graph = buildLargeFamily();

      notifier.computeCollapse(
        allPersons: graph.persons,
        allEdges: graph.edges,
        focusPersonId: 'person-0',
        firstDegreeIds: {'person-1', 'person-2', 'person-3'},
        secondDegreeIds: const {},
        familyMemberCount: graph.persons.length,
      );
      final firstCount = notifier.state.collapsedBranches.length;
      final firstHiddenCount = notifier.state.allHiddenMemberIds.length;

      // Re-compute with identical inputs.
      notifier.clearAll();
      notifier.computeCollapse(
        allPersons: graph.persons,
        allEdges: graph.edges,
        focusPersonId: 'person-0',
        firstDegreeIds: {'person-1', 'person-2', 'person-3'},
        secondDegreeIds: const {},
        familyMemberCount: graph.persons.length,
      );
      final secondCount = notifier.state.collapsedBranches.length;
      final secondHiddenCount = notifier.state.allHiddenMemberIds.length;

      expect(secondCount, firstCount,
          reason: 'Same inputs must produce same branch count');
      expect(secondHiddenCount, firstHiddenCount,
          reason: 'Same inputs must produce same hidden count');
    });

    test('TEST 8: hidden count matches hiddenMemberIds length', () {
      final graph = buildLargeFamily();

      notifier.computeCollapse(
        allPersons: graph.persons,
        allEdges: graph.edges,
        focusPersonId: 'person-0',
        firstDegreeIds: {'person-1', 'person-2', 'person-3'},
        secondDegreeIds: const {},
        familyMemberCount: graph.persons.length,
      );

      for (final branch in notifier.state.collapsedBranches) {
        expect(branch.hiddenCount, branch.hiddenMemberIds.length,
            reason: 'hiddenCount must equal hiddenMemberIds.length');
      }
    });
  });

  // ────────────────────────────────────────────────────────────────────
  // v5.158 (ZONE ASSIGNMENT): computeDensityCollapse is the SINGLE
  // collapse authority. Bubbles represent the HIDDEN members — nodes
  // present in the full adjacency but NOT in the visible/positioned
  // set. Each hidden member belongs to exactly ONE bubble (the
  // nearest visible node by BFS hop distance), so the sum of all
  // bubble counts equals the hidden count and no member is ever
  // unreachable. These tests pin that contract.
  // ────────────────────────────────────────────────────────────────────
  group('v5.123 — Density collapse (single authority, fixed point)', () {
    /// v5.158 fixture: person-0 + 24 children are VISIBLE; the 48
    /// grandchildren are HIDDEN (in the adjacency + edge list, but not
    /// in the visible/positioned set — exactly like the real family
    /// where the RPC fetches 45 of 714 members).
    ///
    /// Zone expectation: each grandchild person-i-g is 1 hop from its
    /// parent person-i (visible) → zoned to person-i. person-0 gets no
    /// zone (grandchildren are nearer to their own parents).
    ({Set<String> visible, Set<String> allPersons, Map<String, Set<String>> childrenOf, List<({String fromId, String toId, String edgeId, String relationshipKey})> edges})
        buildWideTreeWithHidden() {
      final visible = <String>{'person-0'};
      final allPersons = <String>{'person-0'};
      final childrenOf = <String, Set<String>>{};
      final edges = <({String fromId, String toId, String edgeId, String relationshipKey})>[];
      for (var i = 1; i <= 24; i++) {
        final child = 'person-$i';
        visible.add(child);
        allPersons.add(child);
        childrenOf.putIfAbsent('person-0', () => <String>{}).add(child);
        edges.add((fromId: child, toId: 'person-0', edgeId: 'p$i', relationshipKey: 'parent'));
        for (var g = 0; g < 2; g++) {
          final gc = 'person-$i-$g';
          allPersons.add(gc); // HIDDEN — not in visible
          childrenOf.putIfAbsent(child, () => <String>{}).add(gc);
          edges.add((fromId: gc, toId: child, edgeId: 'p${i}_$g', relationshipKey: 'parent'));
        }
      }
      return (visible: visible, allPersons: allPersons, childrenOf: childrenOf, edges: edges);
    }

    test('recomputing with the FULL candidate set is idempotent '
        '(converges — no revision bump)', () {
      final tree = buildWideTreeWithHidden();

      notifier.computeDensityCollapse(
        visibleNodeIds: tree.visible,
        childrenOf: tree.childrenOf,
        personNameOf: (id) => 'Person $id',
        allEdges: tree.edges,
      );
      expect(notifier.state.collapsedBranches, isNotEmpty,
          reason: '48 hidden grandchildren must produce branch bubbles');
      // v5.158 CONTRACT: every hidden member is zoned exactly once.
      expect(notifier.state.allHiddenMemberIds.length, 48,
          reason: 'Bubbles must cover ALL hidden members');
      final revisionAfterFirst = notifier.state.revision;
      final branchesAfterFirst = notifier.state.collapsedBranches.length;
      final hiddenAfterFirst = notifier.state.allHiddenMemberIds.length;

      // v5.123 convergence: recompute with the SAME FULL candidate set
      // (NOT the post-hiding count) → same branches → NO state change.
      notifier.computeDensityCollapse(
        visibleNodeIds: tree.visible,
        childrenOf: tree.childrenOf,
        personNameOf: (id) => 'Person $id',
        allEdges: tree.edges,
      );
      expect(notifier.state.revision, revisionAfterFirst,
          reason: 'Fixed point: identical inputs must not bump the '
              'revision (the old post-hiding-count input oscillated '
              'forever between collapse and clear)');
      expect(notifier.state.collapsedBranches.length, branchesAfterFirst);
      expect(notifier.state.allHiddenMemberIds.length, hiddenAfterFirst);
    });

    test('candidate set at the budget (50) does not collapse', () {
      final candidates = <String>{for (var i = 0; i < 50; i++) 'p$i'};
      notifier.computeDensityCollapse(
        visibleNodeIds: candidates,
        childrenOf: const {},
        personNameOf: (id) => id,
        allEdges: const [],
      );
      expect(notifier.state.collapsedBranches, isEmpty,
          reason: 'No hidden members → no bubbles');
    });

    test('v5.158: hidden members are partitioned — each belongs to '
        'exactly ONE bubble (no overlap, no gaps)', () {
      final tree = buildWideTreeWithHidden();

      notifier.computeDensityCollapse(
        visibleNodeIds: tree.visible,
        childrenOf: tree.childrenOf,
        personNameOf: (id) => 'Person $id',
        allEdges: tree.edges,
      );

      final branches = notifier.state.collapsedBranches;
      expect(branches, isNotEmpty);
      // Every grandchild is zoned to its own parent (nearest visible).
      for (var i = 1; i <= 24; i++) {
        final branch =
            branches.where((b) => b.rootPersonId == 'person-$i').firstOrNull;
        expect(branch, isNotNull,
            reason: 'person-$i has 2 hidden children → must have a bubble');
        expect(branch!.hiddenMemberIds, containsAll({'person-$i-0', 'person-$i-1'}));
      }
      // person-0 has NO hidden member nearer to it than to the parents.
      expect(branches.where((b) => b.rootPersonId == 'person-0'), isEmpty);
      // Sum of counts == hidden count == 48.
      final total = branches.fold<int>(0, (a, b) => a + b.hiddenCount);
      expect(total, 48);
    });

    test('v5.158: protected (unfetched) members still get zoned — '
        'protection never makes a member unreachable', () {
      final tree = buildWideTreeWithHidden();

      // person-1-0 is a search match that hasn't been revealed yet —
      // it's hidden and "protected". It MUST still belong to a zone so
      // the user can reach it by expanding that bubble (the search
      // reveal path makes it visible through its own mechanism).
      notifier.computeDensityCollapse(
        visibleNodeIds: tree.visible,
        childrenOf: tree.childrenOf,
        personNameOf: (id) => 'Person $id',
        allEdges: tree.edges,
        protectedIds: {'person-1-0'},
      );
      expect(notifier.state.allHiddenMemberIds, contains('person-1-0'),
          reason: 'v5.158: protected-but-unfetched members stay zoned '
              '(reachable) — zones never hide positioned nodes anyway');
    });

    test('computeCollapse budget bypass aligns with density (≤ 50)', () {
      // v5.123: cc bypasses at ≤ kNodeBudget so the two mechanisms can
      // never fight. A 40-person rendered set → NO focus-collapse.
      final persons = <String>{for (var i = 0; i < 40; i++) 'q$i'};
      final edges = <({String fromId, String toId, String edgeId, String relationshipKey})>[
        (fromId: 'q1', toId: 'q0', edgeId: 'e1', relationshipKey: 'father'),
      ];
      notifier.computeCollapse(
        allPersons: persons,
        allEdges: edges,
        focusPersonId: 'q0',
        firstDegreeIds: {'q1'},
        secondDegreeIds: const {},
        familyMemberCount: 40,
      );
      expect(notifier.state.collapsedBranches, isEmpty,
          reason: 'A rendered set that fits kNodeBudget must not be '
              'focus-collapsed (v5.123: was < 30)');
    });
  });

  // ────────────────────────────────────────────────────────────────────
  // v5.123 (Step 5): Persisted per-user branch expansion choices.
  //   • seedExpandedBranchRoots applies persisted state ON TOP of the
  //     density-collapse computation.
  //   • onExpansionChanged fires from expandBranch/collapseBranch so
  //     the engine view can persist (userId, familyId, branchRootId).
  //
  // v5.158 (ZONE SEMANTICS): an expanded root is no longer SKIPPED as
  // a bubble root — if hidden members remain nearest to it, its bubble
  // must stay (with the smaller count) or those members would become
  // unreachable. The seeded roots persist so that persisted-expansion
  // state survives reloads; the density pass simply computes zones
  // over whatever is visible.
  // ────────────────────────────────────────────────────────────────────
  group('v5.123 (Step 5) — persisted branch expansion', () {
    test('seeded expansion state survives the density pass, and hidden '
        'members behind a seeded root keep their bubble (v5.158 zone '
        'semantics)', () {
      // person-0 visible; person-1..24 visible; 48 grandchildren hidden.
      final visible = <String>{'person-0'};
      final childrenOf = <String, Set<String>>{};
      final edges = <({String fromId, String toId, String edgeId, String relationshipKey})>[];
      for (var i = 1; i <= 24; i++) {
        visible.add('person-$i');
        childrenOf.putIfAbsent('person-0', () => <String>{}).add('person-$i');
        edges.add((fromId: 'person-$i', toId: 'person-0', edgeId: 'p$i', relationshipKey: 'parent'));
        for (var g = 0; g < 2; g++) {
          final gc = 'person-$i-$g';
          childrenOf.putIfAbsent('person-$i', () => <String>{}).add(gc);
          edges.add((fromId: gc, toId: 'person-$i', edgeId: 'p${i}_$g', relationshipKey: 'parent'));
        }
      }

      // Seed the PERSISTED expansion (the user had expanded person-0's
      // branch in a previous session) BEFORE the collapse computation.
      notifier.seedExpandedBranchRoots({'person-0'});
      expect(notifier.state.expandedBranchRoots, contains('person-0'));

      notifier.computeDensityCollapse(
        visibleNodeIds: visible,
        childrenOf: childrenOf,
        personNameOf: (id) => 'Person $id',
        allEdges: edges,
      );

      // v5.158: person-0 itself gets no zone (grandchildren are nearer
      // to their own parents) — nothing hides behind an expanded root
      // here. The seeded root simply doesn't need a bubble.
      expect(
        notifier.state.collapsedBranches
            .where((b) => b.rootPersonId == 'person-0'),
        isEmpty,
        reason: 'No hidden member is nearest to person-0 → no bubble');
      // Every hidden grandchild is still reachable via its parent's
      // bubble (sum of counts == 48).
      expect(notifier.state.allHiddenMemberIds.length, 48,
          reason: 'Seeding must not strand hidden members — zones are '
              'computed regardless of expandedBranchRoots');

      // Seeding is idempotent.
      final revision = notifier.state.revision;
      notifier.seedExpandedBranchRoots({'person-0'});
      expect(notifier.state.revision, revision,
          reason: 'Re-seeding the same roots is a no-op');
    });

    test('onExpansionChanged fires for expandBranch (true) and '
        'collapseBranch (false)', () {
      final calls = <(String, bool)>[];
      notifier.onExpansionChanged =
          (rootPersonId, expanded) => calls.add((rootPersonId, expanded));

      notifier.expandBranch('person-7');
      expect(calls, [('person-7', true)],
          reason: 'Expanding a branch persists expanded=true keyed by '
              '(userId, familyId, branchRootId)');

      notifier.collapseBranch('person-7');
      expect(calls, [('person-7', true), ('person-7', false)],
          reason: 'Re-collapsing persists expanded=false');

      // Detaching stops the callbacks (dispose path).
      notifier.onExpansionChanged = null;
      notifier.expandBranch('person-8');
      expect(calls.length, 2);
    });
  });

  // ────────────────────────────────────────────────────────────────────
  // v5.158 — ZONE BUBBLES AT SCALE (replaces the v5.132 recursive
  // sub-branch tests). A 160-person graph where only the root is
  // visible must produce ONE bubble on the root covering all 159
  // hidden members; expanding + revealing part of the graph moves the
  // bubbles onto the new frontier with smaller counts — the
  // progressive-expansion contract ("50 → 100 → 250 → … → all").
  // ────────────────────────────────────────────────────────────────────
  group('v5.132 — recursive sub-branch collapse at scale', () {
    // Builds a 160-person graph: root → 4 children, each with a
    // 39-person subtree. Only [visibleOverride] members are visible —
    // the rest are hidden (unfetched), exactly like the real 714-member
    // family with a 45-node proximity fetch.
    ({Set<String> persons, Set<String> visible, List<({String fromId, String toId, String edgeId, String relationshipKey})> edges, Map<String, Set<String>> childrenOf})
        buildScaleGraph({Set<String>? visibleOverride}) {
      final persons = <String>{'root'};
      final edges = <({String fromId, String toId, String edgeId, String relationshipKey})>[];
      final childrenOf = <String, Set<String>>{};
      var edgeSeq = 0;
      void addChild(String parent, String child) {
        persons.add(child);
        edges.add((fromId: child, toId: parent, edgeId: 'e${edgeSeq++}', relationshipKey: 'parent'));
        childrenOf.putIfAbsent(parent, () => <String>{}).add(child);
      }

      // root → 4 children; each child → 38 descendants (3 levels).
      for (var c = 0; c < 4; c++) {
        final childId = 'child-$c';
        addChild('root', childId);
        for (var d = 0; d < 38; d++) {
          final parent = d < 4
              ? childId
              : 'child-$c-${(d - 4) ~/ 4}'; // fan out under child-0..3
          final id = 'child-$c-$d';
          addChild(parent, id);
        }
      }
      final visible = visibleOverride ?? <String>{'root'};
      return (persons: persons, visible: visible, edges: edges, childrenOf: childrenOf);
    }

    test('a subtree larger than kNodeBudget is covered by ONE zone '
        'bubble showing the true count (v5.158)', () {
      final g = buildScaleGraph();
      notifier.computeDensityCollapse(
        visibleNodeIds: g.visible,
        childrenOf: g.childrenOf,
        personNameOf: (id) => 'Person $id',
        allEdges: g.edges,
      );

      expect(notifier.state.collapsedBranches, isNotEmpty,
          reason: '156 hidden members must be covered by a bubble');
      // v5.158: ONE zone on the root — the whole hidden subtree is
      // nearest to the only visible node. No recursive sub-branches:
      // zones partition the hidden set exactly once.
      final rootBranch = notifier.state.collapsedBranches
          .where((b) => b.rootPersonId == 'root')
          .firstOrNull;
      expect(rootBranch, isNotNull,
          reason: 'The root is the only visible node → its zone covers '
              'the entire hidden graph');
      expect(rootBranch!.hiddenCount, 156,
          reason: 'The bubble must show the TRUE hidden count (+156) — '
              'the fixture is 157 persons (root + 4 children + 152 '
              'descendants)');
    });

    test('expanding a branch and revealing its members moves bubbles '
        'onto the new frontier with smaller counts (progressive '
        'expansion)', () {
      final g = buildScaleGraph();
      // First pass: one +159 bubble on the root.
      notifier.computeDensityCollapse(
        visibleNodeIds: g.visible,
        childrenOf: g.childrenOf,
        personNameOf: (id) => 'Person $id',
        allEdges: g.edges,
      );
      final rootBranch = notifier.state.collapsedBranches
          .where((b) => b.rootPersonId == 'root')
          .first;
      expect(rootBranch.hiddenCount, 156);

      // The user taps the "+159" chip → _fetchAndExpandBranch runs:
      // fetchBranchAndMerge + revealPersons(root + some members) +
      // expandBranch. Simulate the reveal: root + its 4 children are
      // now fetched and visible.
      notifier.expandBranch('root');
      final revealed = <String>{'root', 'child-0', 'child-1', 'child-2', 'child-3'};

      // Second density pass over the revealed set.
      notifier.computeDensityCollapse(
        visibleNodeIds: revealed,
        childrenOf: g.childrenOf,
        personNameOf: (id) => 'Person $id',
        allEdges: g.edges,
      );

      // Every remaining hidden member (157 - 5 = 152) is still zoned.
      expect(notifier.state.allHiddenMemberIds.length, 152,
          reason: 'Progressive expansion: 5 visible, 152 hidden, ALL '
              'still represented by bubbles');
      // The frontier moved: the four children now carry the bubbles
      // (their descendants are nearest to them), not the root.
      for (var c = 0; c < 4; c++) {
        expect(
          notifier.state.collapsedBranches
              .where((b) => b.rootPersonId == 'child-$c'),
          isNotEmpty,
          reason: 'child-$c is now the frontier — its descendants are '
              'zoned to it (new bubbles INSIDE the expanded branch)');
      }
      final totalAfter =
          notifier.state.collapsedBranches.fold<int>(0, (a, b) => a + b.hiddenCount);
      expect(totalAfter, 152,
          reason: 'Sum of all bubble counts == hidden count (no gaps, '
              'no double counting)');
    });

    test('unrelated branches keep their chips when one branch expands', () {
      // Two independent hidden clusters behind two visible roots.
      final persons = <String>{'a', 'b'};
      final visible = <String>{'a', 'b'};
      final childrenOf = <String, Set<String>>{};
      final edges = <({String fromId, String toId, String edgeId, String relationshipKey})>[];
      for (var i = 0; i < 5; i++) {
        final idA = 'a-$i';
        final idB = 'b-$i';
        persons..add(idA)..add(idB);
        childrenOf.putIfAbsent('a', () => <String>{}).add(idA);
        childrenOf.putIfAbsent('b', () => <String>{}).add(idB);
        edges.add((fromId: idA, toId: 'a', edgeId: 'ea$i', relationshipKey: 'parent'));
        edges.add((fromId: idB, toId: 'b', edgeId: 'eb$i', relationshipKey: 'parent'));
      }
      // a's cluster becomes visible (expanded); b's stays hidden.
      final visibleAfterExpand = <String>{'a', 'a-0', 'a-1', 'a-2', 'a-3', 'a-4', 'b'};

      notifier.computeDensityCollapse(
        visibleNodeIds: visibleAfterExpand,
        childrenOf: childrenOf,
        personNameOf: (id) => 'Person $id',
        allEdges: edges,
      );

      // b's bubble survives untouched — 5 hidden members.
      final bBranch = notifier.state.collapsedBranches
          .where((b) => b.rootPersonId == 'b')
          .firstOrNull;
      expect(bBranch, isNotNull,
          reason: 'Expanding ONE branch must not touch unrelated branches');
      expect(bBranch!.hiddenCount, 5);
      // a's members are all visible now → no bubble on a.
      expect(
          notifier.state.collapsedBranches.where((b) => b.rootPersonId == 'a'),
          isEmpty);
    });
  });
}

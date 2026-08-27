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
  // v5.123 (Step 3 / pipeline stabilization): computeDensityCollapse is
  // the SINGLE collapse authority fed the FULL pre-hiding candidate
  // set. These tests pin the fixed-point (convergence) property and
  // the protected-ID semantics.
  // ────────────────────────────────────────────────────────────────────
  group('v5.123 — Density collapse (single authority, fixed point)', () {
    /// person-0 with 24 children (person-1..24), each with 2 children
    /// (person-{i}-0 / person-{i}-1) → 1 + 24 + 48 = 73 candidates.
    ({Set<String> candidates, Map<String, Set<String>> childrenOf, List<({String fromId, String toId, String edgeId, String relationshipKey})> edges})
        buildWideTree() {
      final candidates = <String>{'person-0'};
      final childrenOf = <String, Set<String>>{};
      final edges = <({String fromId, String toId, String edgeId, String relationshipKey})>[];
      for (var i = 1; i <= 24; i++) {
        final child = 'person-$i';
        candidates.add(child);
        childrenOf.putIfAbsent('person-0', () => <String>{}).add(child);
        edges.add((fromId: child, toId: 'person-0', edgeId: 'p$i', relationshipKey: 'parent'));
        for (var g = 0; g < 2; g++) {
          final gc = 'person-$i-$g';
          candidates.add(gc);
          childrenOf.putIfAbsent(child, () => <String>{}).add(gc);
          edges.add((fromId: gc, toId: child, edgeId: 'p${i}_$g', relationshipKey: 'parent'));
        }
      }
      return (candidates: candidates, childrenOf: childrenOf, edges: edges);
    }

    test('recomputing with the FULL candidate set is idempotent '
        '(converges — no revision bump)', () {
      final tree = buildWideTree();

      notifier.computeDensityCollapse(
        visibleNodeIds: tree.candidates,
        childrenOf: tree.childrenOf,
        personNameOf: (id) => 'Person $id',
        allEdges: tree.edges,
      );
      expect(notifier.state.collapsedBranches, isNotEmpty,
          reason: '73 candidates > kNodeBudget must collapse');
      final revisionAfterFirst = notifier.state.revision;
      final branchesAfterFirst = notifier.state.collapsedBranches.length;
      final hiddenAfterFirst = notifier.state.allHiddenMemberIds.length;

      // v5.123 convergence: recompute with the SAME FULL candidate set
      // (NOT the post-hiding count) → same branches → NO state change.
      notifier.computeDensityCollapse(
        visibleNodeIds: tree.candidates,
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
          reason: '≤ kNodeBudget candidates → bypass');
    });

    test('protected IDs are never hidden and never become roots', () {
      final tree = buildWideTree();

      // Unprotected baseline: everything under person-0 collapses.
      notifier.computeDensityCollapse(
        visibleNodeIds: tree.candidates,
        childrenOf: tree.childrenOf,
        personNameOf: (id) => 'Person $id',
        allEdges: tree.edges,
      );
      expect(notifier.state.allHiddenMemberIds, contains('person-1-0'));

      // Now protect person-1-0 — it must survive the same collapse.
      final notifier2 = BranchCollapseNotifier();
      notifier2.computeDensityCollapse(
        visibleNodeIds: tree.candidates,
        childrenOf: tree.childrenOf,
        personNameOf: (id) => 'Person $id',
        allEdges: tree.edges,
        protectedIds: {'person-1-0'},
      );
      expect(notifier2.state.allHiddenMemberIds, isNot(contains('person-1-0')),
          reason: 'Protected persons stay visible even inside a hidden '
              'subtree (focus/search/path/selection protection)');
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
  //     default density-collapse computation — a previously expanded
  //     branch loads already-expanded even when the budget rule would
  //     have collapsed it.
  //   • onExpansionChanged fires from expandBranch/collapseBranch so
  //     the engine view can persist (userId, familyId, branchRootId).
  // ────────────────────────────────────────────────────────────────────
  group('v5.123 (Step 5) — persisted branch expansion', () {
    test('a seeded (persisted-expanded) branch is NOT re-collapsed by '
        'the density rule even though the budget would collapse it', () {
      // 73-candidate wide tree — person-0's subtree collapses by default.
      final candidates = <String>{'person-0'};
      final childrenOf = <String, Set<String>>{};
      final edges = <({String fromId, String toId, String edgeId, String relationshipKey})>[];
      for (var i = 1; i <= 24; i++) {
        candidates.add('person-$i');
        childrenOf.putIfAbsent('person-0', () => <String>{}).add('person-$i');
        edges.add((fromId: 'person-$i', toId: 'person-0', edgeId: 'p$i', relationshipKey: 'parent'));
        for (var g = 0; g < 2; g++) {
          final gc = 'person-$i-$g';
          candidates.add(gc);
          childrenOf.putIfAbsent('person-$i', () => <String>{}).add(gc);
          edges.add((fromId: gc, toId: 'person-$i', edgeId: 'p${i}_$g', relationshipKey: 'parent'));
        }
      }

      // Baseline: without persistence, person-0's branch collapses.
      final baseline = BranchCollapseNotifier();
      baseline.computeDensityCollapse(
        visibleNodeIds: candidates,
        childrenOf: childrenOf,
        personNameOf: (id) => 'Person $id',
        allEdges: edges,
      );
      expect(baseline.state.collapsedBranches, isNotEmpty);
      expect(baseline.state.allHiddenMemberIds, contains('person-1-0'));

      // v5.123 (Step 5): seed the PERSISTED expansion (the user had
      // expanded person-0's branch in a previous session) BEFORE the
      // collapse computation runs — the branch must NOT re-collapse.
      notifier.seedExpandedBranchRoots({'person-0'});
      expect(notifier.state.expandedBranchRoots, contains('person-0'));

      notifier.computeDensityCollapse(
        visibleNodeIds: candidates,
        childrenOf: childrenOf,
        personNameOf: (id) => 'Person $id',
        allEdges: edges,
      );
      expect(
        notifier.state.collapsedBranches
            .where((b) => b.rootPersonId == 'person-0'),
        isEmpty,
        reason: 'A persisted-expanded branch loads already-expanded — '
            'the budget rule must skip it');
      expect(notifier.state.allHiddenMemberIds, isNot(contains('person-1-0')));

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
}

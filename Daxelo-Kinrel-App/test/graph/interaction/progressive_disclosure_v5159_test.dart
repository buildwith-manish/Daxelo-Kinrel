// test/graph/interaction/progressive_disclosure_v5159_test.dart
//
// v5.159 — Progressive disclosure + rich bubbles + re-collapse tests.
//
// Covers the user-facing spec:
//   1. LEVEL REVEAL — one branch-bubble tap reveals ONLY the immediate
//      next level (direct neighbours of the branch root), capped at 15,
//      prioritised by kinship closeness, ties by deterministic ID.
//   2. CONNECTIVITY GUARANTEE — every revealed member holds an edge to
//      an already-visible node, so a node can never render unlinked.
//   3. RE-COLLAPSE — collapseBranch returns the exact conceal set (the
//      union of what this root's expansions revealed, including NESTED
//      expansions inside it); concealPersons removes exactly that set
//      from the proximity visible set (anchor protected).
//   4. RICH BUBBLES — CollapsedBranch.representativeName resolution and
//      hasNestedDescendants (depth ≥ 2 → tree glyph, depth 1 → flat).
//   5. CYCLE SAFETY — undirected adjacency cycles terminate.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/graph/interaction/branch_collapse_state.dart';
import 'package:kinrel/graph/interaction/proximity_graph_state.dart';

typedef _E = ({
  String fromId,
  String toId,
  String edgeId,
  String relationshipKey
});

_E _e(String from, String to, String key, [String? id]) =>
    (fromId: from, toId: to, edgeId: id ?? 'e-$from-$to-$key', relationshipKey: key);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═══════════════════════════════════════════════════════════════════
  // 1. LEVEL REVEAL (computeNextLevelReveal)
  // ═══════════════════════════════════════════════════════════════════
  group('v5.159 — level reveal (computeNextLevelReveal)', () {
    test('returns ONLY the immediate next level — never the deeper '
        'subtree', () {
      // root → h1 (hidden direct) → h2 (hidden grandchild).
      final edges = <_E>[
        _e('root', 'h1', 'son'),
        _e('h1', 'h2', 'son'),
        _e('h2', 'h3', 'son'),
      ];
      final revealed = ProximityGraphNotifier.computeNextLevelReveal(
        rootPersonId: 'root',
        visibleIds: {'root'},
        allPersons: {'root', 'h1', 'h2', 'h3'},
        edges: edges,
      );
      expect(revealed, {'h1'},
          reason: 'Only h1 is a DIRECT neighbour of the root — h2/h3 '
              'belong to deeper levels and must stay hidden');
    });

    test('caps the reveal at kMaxNodesPerExpansion (15) and prioritises '
        'kinship closeness, ties by ID', () {
      // 20 hidden direct neighbours: 5 spouses, 5 parents, 10 in-laws.
      // Capacity 15 → all 5 spouses + all 5 parents + first 5 in-laws
      // (zero-padded: deterministic ID tie-break).
      final edges = <_E>[
        for (var i = 0; i < 5; i++)
          _e('root', 'sp${i.toString().padLeft(2, '0')}', 'spouse'),
        for (var i = 0; i < 5; i++)
          _e('root', 'pa${i.toString().padLeft(2, '0')}', 'father'),
        for (var i = 0; i < 10; i++)
          _e('root', 'il${i.toString().padLeft(2, '0')}', 'cousin'),
      ];
      final allPersons = <String>{
        'root',
        for (final e in edges) e.fromId,
        for (final e in edges) e.toId,
      };
      final revealed = ProximityGraphNotifier.computeNextLevelReveal(
        rootPersonId: 'root',
        visibleIds: {'root'},
        allPersons: allPersons,
        edges: edges,
      );

      expect(revealed.length, kMaxNodesPerExpansion,
          reason: 'A 20-member immediate level is split: only the first '
              '15 are revealed, the rest re-group into sub-bubbles');
      // All spouses + parents survive.
      for (var i = 0; i < 5; i++) {
        expect(revealed, contains('sp${i.toString().padLeft(2, '0')}'));
        expect(revealed, contains('pa${i.toString().padLeft(2, '0')}'));
      }
      // Exactly 5 of 10 in-laws — the FIRST-discovered (zero-padded).
      var inLawCount = 0;
      for (var i = 0; i < 10; i++) {
        if (revealed.contains('il${i.toString().padLeft(2, '0')}')) {
          inLawCount++;
        }
      }
      expect(inLawCount, 5);
      for (var i = 0; i < 5; i++) {
        expect(revealed, contains('il${i.toString().padLeft(2, '0')}'));
      }
    });

    test('CONNECTIVITY GUARANTEE: every revealed member has an edge to '
        'an already-visible node', () {
      final edges = <_E>[
        _e('root', 'a', 'daughter'),
        _e('root', 'b', 'niece'),
        // c is NOT adjacent to the root — only to a (also hidden here).
        _e('a', 'c', 'son'),
        // d is adjacent to a VISIBLE outsider.
        _e('outsider', 'd', 'son'),
      ];
      final visible = <String>{'root', 'outsider'};
      final revealed = ProximityGraphNotifier.computeNextLevelReveal(
        rootPersonId: 'root',
        visibleIds: visible,
        allPersons: {'root', 'outsider', 'a', 'b', 'c', 'd'},
        edges: edges,
      );
      // Only the root's direct hidden neighbours qualify.
      expect(revealed, {'a', 'b'});
      for (final id in revealed) {
        final hasVisibleEdge = edges.any((e) =>
            (e.fromId == id && visible.contains(e.toId)) ||
            (e.toId == id && visible.contains(e.fromId)));
        expect(hasVisibleEdge, isTrue,
            reason: 'Revealed node $id has no edge to a visible node — '
                'it would render unlinked');
      }
    });

    test('skips already-visible and unfetched neighbours', () {
      final edges = <_E>[
        _e('root', 'vis', 'son'), // already visible → skip
        _e('root', 'fetched', 'son'), // hidden + fetched → reveal
        _e('root', 'unfetched', 'son'), // hidden but NOT in allPersons → skip
      ];
      final revealed = ProximityGraphNotifier.computeNextLevelReveal(
        rootPersonId: 'root',
        visibleIds: {'root', 'vis'},
        allPersons: {'root', 'vis', 'fetched'},
        edges: edges,
      );
      expect(revealed, {'fetched'});
    });

    test('unknown root → empty set', () {
      final revealed = ProximityGraphNotifier.computeNextLevelReveal(
        rootPersonId: 'ghost',
        visibleIds: const {'root'},
        allPersons: const {'root'},
        edges: const [],
      );
      expect(revealed, isEmpty);
    });

    test('cycle safety: an A↔B cycle between hidden nodes terminates', () {
      final edges = <_E>[
        _e('root', 'a', 'son'),
        _e('a', 'b', 'brother'),
        _e('b', 'a', 'brother'), // cycle
      ];
      final revealed = ProximityGraphNotifier.computeNextLevelReveal(
        rootPersonId: 'root',
        visibleIds: const {'root'},
        allPersons: const {'root', 'a', 'b'},
        edges: edges,
      );
      expect(revealed, {'a'});
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 2. RE-COLLAPSE round-trip (expandBranch + collapseBranch +
  //    concealPersons)
  // ═══════════════════════════════════════════════════════════════════
  group('v5.159 — re-collapse round-trip', () {
    test('collapseBranch returns exactly what the expansion revealed',
        () {
      final notifier = BranchCollapseNotifier();
      notifier.expandBranch('root', revealedIds: {'a', 'b', 'c'});
      expect(notifier.state.revealedByBranchRoot['root'], {'a', 'b', 'c'});
      expect(notifier.state.expandedBranchRoots, contains('root'));

      final concealSet = notifier.collapseBranch('root');
      expect(concealSet, {'a', 'b', 'c'},
          reason: 'Re-collapsing must conceal exactly the members the '
              'expansion revealed');
      expect(notifier.state.expandedBranchRoots, isNot(contains('root')));
      expect(notifier.state.revealedByBranchRoot, isNot(contains('root')));
    });

    test('nested expansions are concealed transitively (level-by-level '
        'expansion closure)', () {
      final notifier = BranchCollapseNotifier();
      // Level 1: tapping the root's bubble revealed a, b.
      notifier.expandBranch('root', revealedIds: {'a', 'b'});
      // Level 2: tapping a's NEW bubble revealed a1, a2 (nested).
      notifier.expandBranch('a', revealedIds: {'a1', 'a2'});

      // Re-collapsing the ROOT must conceal BOTH levels.
      final concealSet = notifier.collapseBranch('root');
      expect(concealSet, {'a', 'b', 'a1', 'a2'},
          reason: 'The nested expansion under a is part of what the '
              'root expansion ultimately revealed');
      expect(notifier.state.expandedBranchRoots, isEmpty,
          reason: 'The nested root a is de-expanded too');
      expect(notifier.state.revealedByBranchRoot, isEmpty);
    });

    test('concealPersons removes exactly the given set (anchor '
        'protected, visible set updates)', () {
      final notifier = ProximityGraphNotifier();
      notifier.initialize(
        anchorId: 'anchor',
        allPersons: const {'anchor', 'a', 'b', 'c', 'd'},
        adjacency: const {
          'anchor': {'a', 'b'},
          'a': {'anchor'},
          'b': {'anchor'},
        },
        edges: const [
          (fromId: 'anchor', toId: 'a', edgeId: 'e1', relationshipKey: 'son'),
          (fromId: 'anchor', toId: 'b', edgeId: 'e2', relationshipKey: 'son'),
        ],
      );
      // Reveal a hidden branch.
      notifier.revealPersons(
        personIds: const {'c', 'd'},
        allPersons: const {'anchor', 'a', 'b', 'c', 'd'},
      );
      expect(notifier.state.visibleIds, containsAll(['c', 'd']));

      // Conceal the revealed members.
      notifier.concealPersons(personIds: const {'c', 'd'});
      expect(notifier.state.visibleIds, isNot(contains('c')));
      expect(notifier.state.visibleIds, isNot(contains('d')));
      expect(notifier.state.visibleIds, containsAll(['anchor', 'a', 'b']),
          reason: 'Unrelated nodes keep their visibility');

      // The anchor is NEVER concealed.
      notifier.concealPersons(personIds: const {'anchor'});
      expect(notifier.state.visibleIds, contains('anchor'));
    });

    test('manualCollapseBranch clears stale revealed entries inside the '
        'collapsed subtree', () {
      final notifier = BranchCollapseNotifier();
      notifier.expandBranch('root', revealedIds: {'a', 'b'});
      notifier.expandBranch('a', revealedIds: {'a1'});

      notifier.manualCollapseBranch(
        rootPersonId: 'root',
        childrenOf: const {
          'root': {'a', 'b'},
          'a': {'a1'},
        },
        personNameOf: (id) => 'Person $id',
      );
      expect(notifier.state.revealedByBranchRoot, isEmpty,
          reason: 'Entries for roots inside the manually-collapsed '
              'subtree would be stale after the members re-hide');
      expect(notifier.state.manuallyCollapsedRoots, contains('root'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 3. RICH BUBBLES (CollapsedBranch fields)
  // ═══════════════════════════════════════════════════════════════════
  group('v5.159 — rich bubble fields', () {
    test('hasNestedDescendants: depth ≥ 2 → tree glyph; depth 1 → flat',
        () {
      final nested = CollapsedBranch(
        id: 'b1',
        rootPersonId: 'root',
        rootPersonName: 'Root',
        hiddenMemberIds: const {'a', 'a1'},
        hiddenEdgeIds: const {},
        visibleMemberCount: 1,
        hiddenGenerationDepth: 2,
        branchLabel: 'Root branch',
        relationshipKey: 'father',
      );
      expect(nested.hasNestedDescendants, isTrue,
          reason: 'Depth 2 means deeper levels hide behind further '
              'bubbles — tree glyph');

      final flat = CollapsedBranch(
        id: 'b2',
        rootPersonId: 'root2',
        rootPersonName: 'Root2',
        hiddenMemberIds: const {'x', 'y', 'z'},
        hiddenEdgeIds: const {},
        visibleMemberCount: 1,
        hiddenGenerationDepth: 1,
        branchLabel: 'Root2 branch',
        relationshipKey: 'mother',
      );
      expect(flat.hasNestedDescendants, isFalse,
          reason: 'Depth 1 = a dead-end group of direct people — flat '
              'chevron glyph');
    });

    test('representativeName resolves via computeDensityCollapse '
        '(root name first, then first hidden name)', () {
      final notifier = BranchCollapseNotifier();
      // Visible: root + one child. Hidden: root's 6 grandchildren via
      // 'child' — a zone bubble forms at 'child'.
      final childrenOf = <String, Set<String>>{
        'root': {'child'},
        'child': {'g1', 'g2', 'g3', 'g4', 'g5', 'g6'},
      };
      final edges = <_E>[
        _e('root', 'child', 'son'),
        for (var i = 1; i <= 6; i++) _e('child', 'g$i', 'daughter'),
      ];
      notifier.computeDensityCollapse(
        visibleNodeIds: {'root', 'child'},
        childrenOf: childrenOf,
        personNameOf: (id) => id == 'child'
            ? 'Geeta Iyer'
            : (id.startsWith('g') ? 'Grandchild $id' : 'Unknown'),
        allEdges: edges,
      );

      expect(notifier.state.collapsedBranches, isNotEmpty);
      final branch = notifier.state.collapsedBranches.first;
      expect(branch.rootPersonId, 'child');
      // Root name is known → the chip reads "Geeta Iyer +6".
      expect(branch.representativeName, 'Geeta Iyer');
      expect(branch.hiddenCount, 6);
      // Direct children of the zone root → flat group.
      expect(branch.hasNestedDescendants, isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 4. CYCLE SAFETY (iterative BFS rewrites)
  // ═══════════════════════════════════════════════════════════════════
  group('v5.159 — cycle safety', () {
    test('hasVisibleDescendants terminates on an A↔B undirected cycle',
        () {
      final notifier = BranchCollapseNotifier();
      // Undirected adjacency: a ↔ b (each lists the other).
      final childrenOf = <String, Set<String>>{
        'a': {'b'},
        'b': {'a'},
      };
      // Runs without stack overflow / infinite recursion.
      final result = notifier.hasVisibleDescendants(
        'a',
        childrenOf,
        {'c'}, // 'c' is not in the map at all → false expected.
      );
      expect(result, isFalse);

      // And true when a descendant IS visible.
      final result2 = notifier.hasVisibleDescendants(
        'a',
        childrenOf,
        {'b'},
      );
      expect(result2, isTrue);
    });

    test('long descendant chains terminate (no recursion depth limit '
        'hit)', () {
      final notifier = BranchCollapseNotifier();
      final childrenOf = <String, Set<String>>{};
      // A 5000-deep chain — the old recursive implementation risked
      // stack overflow; the iterative BFS handles it.
      for (var i = 0; i < 5000; i++) {
        childrenOf['n$i'] = {'n${i + 1}'};
      }
      final result = notifier.hasVisibleDescendants(
        'n0',
        childrenOf,
        {'n4999'},
      );
      expect(result, isTrue);
    });
  });
}

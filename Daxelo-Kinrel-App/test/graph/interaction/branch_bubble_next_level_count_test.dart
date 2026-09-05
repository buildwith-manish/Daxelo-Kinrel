// test/graph/interaction/branch_bubble_next_level_count_test.dart
//
// DAXELO KINREL — v5.160 ACCEPTANCE TEST
//
// Verifies the user's branch-bubble count requirement:
//
//   "The number shown on the branch bubble should only reflect how
//   many nodes will actually appear when the user taps to expand
//   this specific bubble — meaning the immediate next level only,
//   not the full count of everyone further down the tree."
//
// Concretely:
//   1. The chip count (`CollapsedBranch.nextExpansionCount`) equals
//      the number of DIRECT (depth-1) hidden neighbours of the root
//      within the branch's zone, capped at kMaxNodesPerExpansion.
//   2. The full recursive descendant count is still tracked by
//      `hiddenCount` (used by the "View all" summary panel and the
//      full-coverage accounting).
//   3. nextExpansionCount updates correctly at every level as the
//      user expands deeper into the tree (re-zoned sub-bubbles
//      reflect THEIR own next-level count, not the parent's).
//   4. The cap (kMaxNodesPerExpansion = 15) is enforced — a root
//      with 30 direct hidden children shows "+15" on the chip,
//      because only 15 will actually be revealed on tap.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/graph/interaction/branch_collapse_state.dart';

typedef _E = ({
  String fromId,
  String toId,
  String edgeId,
  String relationshipKey
});

void main() {
  // ── Helper: build an undirected adjacency map from an edge list ──
  Map<String, Set<String>> buildAdjacency(List<_E> edges) {
    final m = <String, Set<String>>{};
    for (final e in edges) {
      m.putIfAbsent(e.fromId, () => <String>{}).add(e.toId);
      m.putIfAbsent(e.toId, () => <String>{}).add(e.fromId);
    }
    return m;
  }

  group('v5.160 — branch bubble next-level count', () {
    test(
        'CRITERION 1: chip count = DIRECT hidden children of the root, '
        'NOT the full recursive descendant count',
        () {
      // Topology: root → 8 direct children, each child → 28 grandchildren
      // (so the root has 8 direct + 224 deeper = 232 total descendants).
      // Per the user's example: the chip should show "+8", not "+232".
      final edges = <_E>[];
      var eid = 0;
      for (var i = 1; i <= 8; i++) {
        final child = 'child$i';
        edges.add((fromId: child, toId: 'root', edgeId: 'e${eid++}',
            relationshipKey: 'parent'));
        for (var j = 1; j <= 28; j++) {
          final grand = '${child}_g$j';
          edges.add((fromId: grand, toId: child, edgeId: 'e${eid++}',
              relationshipKey: 'parent'));
        }
      }
      final adjacency = buildAdjacency(edges);

      final notifier = BranchCollapseNotifier();
      notifier.computeDensityCollapse(
        visibleNodeIds: {'root'},
        childrenOf: adjacency,
        personNameOf: (id) => 'Person $id',
        allEdges: edges,
      );

      expect(notifier.state.collapsedBranches.length, 1);
      final branch = notifier.state.collapsedBranches.first;
      expect(branch.rootPersonId, 'root');

      // The chip shows "+8" — the 8 direct children.
      expect(branch.nextExpansionCount, 8,
          reason: 'Chip count must be the IMMEDIATE next-level (8 direct '
              'children), not the full 232-descendant count.');
      // The full count is still tracked separately for the "View all"
      // summary panel.
      expect(branch.hiddenCount, 8 + 8 * 28,
          reason: 'Full hidden count still tracks every recursive '
              'descendant (8 children + 224 grandchildren = 232).');
      expect(branch.hiddenCount, greaterThan(branch.nextExpansionCount),
          reason: 'Full count strictly greater than chip count when the '
              'branch has deeper levels — exactly the user\'s "Prakash '
              'Menon +234 → +8" case.');
    });

    test(
        'CRITERION 2: nextExpansionCount updates correctly as the user '
        'expands deeper (sub-bubbles carry their own next-level count)',
        () {
      // Topology: root → 3 direct children (c1, c2, c3).
      // Each child has 5 of its own children (c1_g1..5, etc.).
      // Each grandchild has 4 great-grandchildren.
      //
      // Initial state: only 'root' visible.
      //   → bubble on 'root' shows +3 (c1, c2, c3).
      // After expanding 'root': c1, c2, c3 are visible.
      //   → each of c1, c2, c3 gets a bubble showing +5 (its own
      //     children), NOT +21 (5 children + 20 great-grandchildren).
      final edges = <_E>[];
      var eid = 0;
      for (var i = 1; i <= 3; i++) {
        final child = 'c$i';
        edges.add((fromId: child, toId: 'root', edgeId: 'e${eid++}',
            relationshipKey: 'parent'));
        for (var j = 1; j <= 5; j++) {
          final grand = '${child}_g$j';
          edges.add((fromId: grand, toId: child, edgeId: 'e${eid++}',
              relationshipKey: 'parent'));
          for (var k = 1; k <= 4; k++) {
            final great = '${grand}_gg$k';
            edges.add((fromId: great, toId: grand, edgeId: 'e${eid++}',
                relationshipKey: 'parent'));
          }
        }
      }
      final adjacency = buildAdjacency(edges);

      // ── Round 1: only the root is visible ──
      final notifier = BranchCollapseNotifier();
      notifier.computeDensityCollapse(
        visibleNodeIds: {'root'},
        childrenOf: adjacency,
        personNameOf: (id) => 'Person $id',
        allEdges: edges,
      );
      final round1Branches = notifier.state.collapsedBranches;
      expect(round1Branches.length, 1);
      final rootBranch = round1Branches.first;
      expect(rootBranch.rootPersonId, 'root');
      expect(rootBranch.nextExpansionCount, 3,
          reason: 'Root has 3 direct hidden children → chip shows +3.');
      expect(rootBranch.hiddenCount, 3 + 3 * 5 + 3 * 5 * 4,
          reason: 'Full hidden count: 3 + 15 + 60 = 78.');

      // ── Round 2: user tapped the root bubble → c1, c2, c3 revealed ──
      notifier.computeDensityCollapse(
        visibleNodeIds: {'root', 'c1', 'c2', 'c3'},
        childrenOf: adjacency,
        personNameOf: (id) => 'Person $id',
        allEdges: edges,
      );
      final round2Branches = notifier.state.collapsedBranches;
      // Now each of c1, c2, c3 should carry its own bubble.
      for (var i = 1; i <= 3; i++) {
        final childBranch = round2Branches
            .where((b) => b.rootPersonId == 'c$i')
            .firstOrNull;
        expect(childBranch, isNotNull,
            reason: 'c$i gets its own bubble after the root is expanded.');
        expect(childBranch!.nextExpansionCount, 5,
            reason: 'c$i has 5 direct hidden children → chip shows +5, '
                'NOT +25 (5 + 20 great-grandchildren).');
        expect(childBranch.hiddenCount, 5 + 5 * 4,
            reason: 'c$i\'s full hidden count: 5 + 20 = 25.');
      }
    });

    test(
        'CRITERION 3: chip count caps at kMaxNodesPerExpansion (15) when '
        'the root has more direct hidden children than the cap',
        () {
      // Root has 30 direct hidden children. computeNextLevelReveal caps
      // at 15, so the chip must show "+15", not "+30".
      final edges = <_E>[];
      for (var i = 1; i <= 30; i++) {
        edges.add((fromId: 'child$i', toId: 'root', edgeId: 'e$i',
            relationshipKey: 'parent'));
      }
      final adjacency = buildAdjacency(edges);

      final notifier = BranchCollapseNotifier();
      notifier.computeDensityCollapse(
        visibleNodeIds: {'root'},
        childrenOf: adjacency,
        personNameOf: (id) => 'Person $id',
        allEdges: edges,
      );
      final branch = notifier.state.collapsedBranches.first;
      expect(branch.nextExpansionCount, kMaxNodesPerExpansion,
          reason: 'When direct children > 15, chip caps at 15 — only 15 '
              'will actually appear on tap.');
      expect(branch.hiddenCount, 30,
          reason: 'Full count still tracks all 30.');
    });

    test(
        'CRITERION 4: manual collapse also sets nextExpansionCount to '
        'the immediate-next-level count',
        () {
      // Same topology as CRITERION 1: 8 direct + 224 deeper.
      final edges = <_E>[];
      var eid = 0;
      for (var i = 1; i <= 8; i++) {
        final child = 'child$i';
        edges.add((fromId: child, toId: 'root', edgeId: 'e${eid++}',
            relationshipKey: 'parent'));
        for (var j = 1; j <= 28; j++) {
          final grand = '${child}_g$j';
          edges.add((fromId: grand, toId: child, edgeId: 'e${eid++}',
              relationshipKey: 'parent'));
        }
      }
      final adjacency = buildAdjacency(edges);

      final notifier = BranchCollapseNotifier();
      notifier.manualCollapseBranch(
        rootPersonId: 'root',
        childrenOf: adjacency,
        allEdges: edges,
        personNameOf: (id) => 'Person $id',
      );

      expect(notifier.state.collapsedBranches.length, 1);
      final branch = notifier.state.collapsedBranches.first;
      expect(branch.id, 'root_manual_branch');
      expect(branch.nextExpansionCount, 8,
          reason: 'Manual collapse chip also shows only the immediate '
              'next-level count (8), not the full descendant count.');
      expect(branch.hiddenCount, 232,
          reason: 'Manual collapse full count is still 232.');
    });

    test(
        'CRITERION 5: zone-fallback path — root with NO direct hidden '
        'neighbours falls back to count of zone members adjacent to '
        'any visible node, capped at kMaxNodesPerExpansion',
        () {
      // Topology: visible root R1, hidden H1, hidden H2, hidden H3.
      // R1 → V2 (visible) → H1 → H2 → H3 (chain).
      // R1 has no direct hidden neighbours. The zone fallback reveals
      // H1 (adjacent to visible V2). H2, H3 are deeper.
      final edges = <_E>[
        (fromId: 'V2', toId: 'R1', edgeId: 'e1', relationshipKey: 'parent'),
        (fromId: 'H1', toId: 'V2', edgeId: 'e2', relationshipKey: 'parent'),
        (fromId: 'H2', toId: 'H1', edgeId: 'e3', relationshipKey: 'parent'),
        (fromId: 'H3', toId: 'H2', edgeId: 'e4', relationshipKey: 'parent'),
      ];
      final adjacency = buildAdjacency(edges);

      final notifier = BranchCollapseNotifier();
      notifier.computeDensityCollapse(
        visibleNodeIds: {'R1', 'V2'},
        childrenOf: adjacency,
        personNameOf: (id) => 'Person $id',
        allEdges: edges,
      );

      // The zone root is V2 (closest visible to the hidden chain).
      final branch = notifier.state.collapsedBranches
          .where((b) => b.rootPersonId == 'V2')
          .firstOrNull;
      expect(branch, isNotNull,
          reason: 'V2 is the closest visible node to the hidden chain.');
      // V2 has 1 direct hidden neighbour (H1) → chip shows +1.
      expect(branch!.nextExpansionCount, 1,
          reason: 'V2 has 1 direct hidden neighbour (H1) → chip +1.');
      // Full hidden count: H1, H2, H3 = 3.
      expect(branch.hiddenCount, 3,
          reason: 'Full hidden count tracks all 3 chain members.');
    });

    test('CRITERION 6: a dead-end flat group shows the full count on chip',
        () {
      // Topology: root + 4 direct hidden children, no grandchildren.
      // hiddenCount == nextExpansionCount == 4 (a "dead end" group).
      final edges = <_E>[
        (fromId: 'c1', toId: 'root', edgeId: 'e1', relationshipKey: 'parent'),
        (fromId: 'c2', toId: 'root', edgeId: 'e2', relationshipKey: 'parent'),
        (fromId: 'c3', toId: 'root', edgeId: 'e3', relationshipKey: 'parent'),
        (fromId: 'c4', toId: 'root', edgeId: 'e4', relationshipKey: 'parent'),
      ];
      final adjacency = buildAdjacency(edges);

      final notifier = BranchCollapseNotifier();
      notifier.computeDensityCollapse(
        visibleNodeIds: {'root'},
        childrenOf: adjacency,
        personNameOf: (id) => 'Person $id',
        allEdges: edges,
      );
      final branch = notifier.state.collapsedBranches.first;
      expect(branch.nextExpansionCount, 4);
      expect(branch.hiddenCount, 4);
      expect(branch.hasNestedDescendants, isFalse,
          reason: 'Dead-end flat group — no deeper levels.');
    });
  });
}

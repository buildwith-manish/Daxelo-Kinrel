// test/graph/interaction/proximity_graph_state_test.dart
//
// v5.123 (Step 2) — Adaptive soft/hard node budget for the ego-centric
// proximity view.
//
// The old single fixed cap (kProximityNodeBudget = 30) cut rings
// mid-way at exactly 30 nodes. The budget is now a soft/hard range:
//   • Rings 1 and 2 ALWAYS fill in full — even when that exceeds the
//     soft budget of 30.
//   • Deeper rings fill as COMPLETE rings while the total is under 30.
//   • Truncation (a partial ring) happens ONLY at the hard cap of 50
//     (= kNodeBudget, unchanged), and when it does, closer kinship
//     categories are kept over farther ones (siblings/children before
//     distant in-laws) using the existing KinshipEdgeCategory ranking.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/graph/interaction/proximity_graph_state.dart';

/// Edge tuple matching the production shape used by buildAdjacency.
typedef _E = ({String fromId, String toId, String edgeId, String relationshipKey});

_E _e(String from, String to, String key, [String? id]) =>
    (fromId: from, toId: to, edgeId: id ?? 'e-$from-$to-$key', relationshipKey: key);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('v5.123 (Step 2) — adaptive soft/hard proximity budget', () {
    test('rings 1 and 2 fill IN FULL even when the total exceeds the '
        'soft budget of 30', () {
      // Anchor + 12 ring-1 children + 36 ring-2 grandchildren = 49
      // nodes — above the soft budget (30) but under the hard cap (50).
      final edges = <_E>[];
      for (var i = 0; i < 12; i++) {
        edges.add(_e('anchor', 'child$i', 'son'));
        for (var g = 0; g < 3; g++) {
          edges.add(_e('child$i', 'gc${i}_$g', 'son'));
        }
      }
      final allPersons = <String>{'anchor', for (final e in edges) e.fromId, for (final e in edges) e.toId};
      final adjacency = buildAdjacency(edges);

      final visible = ProximityGraphNotifier.computeDefaultVisibleIds(
        anchorId: 'anchor',
        allPersons: allPersons,
        adjacency: adjacency,
        edges: edges,
      );

      expect(visible.length, 49,
          reason: 'Ring 1 (12) + ring 2 (36) + anchor must ALL be '
              'visible — 49 > 30 soft budget but ≤ 50 hard cap');
      for (var i = 0; i < 12; i++) {
        expect(visible, contains('child$i'),
            reason: 'Ring 1 must never be truncated');
      }
      for (var i = 0; i < 12; i++) {
        for (var g = 0; g < 3; g++) {
          expect(visible, contains('gc${i}_$g'),
              reason: 'Ring 2 must never be truncated (under the hard cap)');
        }
      }
    });

    test('truncation happens ONLY at the hard cap (50) and prefers '
        'closer kinship categories over in-laws', () {
      // Anchor with 55 DIRECT connections: 25 sons + 30 brothers-in-law.
      // Ring 1 alone exceeds the hard cap → the ring is truncated to
      // 49 nodes, keeping the 25 children (category child, rank 3)
      // BEFORE the in-laws (category inLaw, rank 8).
      final edges = <_E>[];
      for (var i = 0; i < 25; i++) {
        edges.add(_e('anchor', 'son$i', 'son'));
      }
      for (var i = 0; i < 30; i++) {
        edges.add(_e('anchor', 'bil$i', 'brother_in_law'));
      }
      final allPersons = <String>{'anchor', for (final e in edges) e.fromId, for (final e in edges) e.toId};
      final adjacency = buildAdjacency(edges);

      final visible = ProximityGraphNotifier.computeDefaultVisibleIds(
        anchorId: 'anchor',
        allPersons: allPersons,
        adjacency: adjacency,
        edges: edges,
      );

      expect(visible.length, 50,
          reason: 'Hard cap = 50 (kNodeBudget): anchor + 49 ring-1 nodes');

      // ALL children survive the truncation.
      for (var i = 0; i < 25; i++) {
        expect(visible, contains('son$i'),
            reason: 'Children must be kept before in-laws');
      }
      // Only 24 of the 30 in-laws fit — and the survivors must be the
      // FIRST-discovered ones (stable tie-break within the category).
      var inLawVisible = 0;
      for (var i = 0; i < 30; i++) {
        if (visible.contains('bil$i')) inLawVisible++;
      }
      expect(inLawVisible, 24,
          reason: '50 - anchor - 25 children = 24 in-law slots');
      for (var i = 0; i < 24; i++) {
        expect(visible, contains('bil$i'),
            reason: 'Ties inside a category keep BFS discovery order');
      }
      expect(visible, isNot(contains('bil29')),
          reason: 'The last-discovered in-laws are dropped first');
    });

    test('a sibling outranks a sibling-in-law at the hard cap', () {
      // Anchor with 50 direct connections: 25 brothers + 25
      // sisters-in-law. Capacity 49 → all 25 brothers + 24 of 25
      // sisters-in-law.
      final edges = <_E>[];
      for (var i = 0; i < 25; i++) {
        edges.add(_e('anchor', 'bro$i', 'brother'));
      }
      for (var i = 0; i < 25; i++) {
        edges.add(_e('anchor', 'sil$i', 'sister_in_law'));
      }
      final allPersons = <String>{'anchor', for (final e in edges) e.fromId, for (final e in edges) e.toId};
      final adjacency = buildAdjacency(edges);

      final visible = ProximityGraphNotifier.computeDefaultVisibleIds(
        anchorId: 'anchor',
        allPersons: allPersons,
        adjacency: adjacency,
        edges: edges,
      );

      expect(visible.length, 50);
      for (var i = 0; i < 25; i++) {
        expect(visible, contains('bro$i'),
            reason: 'Siblings (rank 4) outrank siblings-in-law (rank 8)');
      }
      expect(visible, isNot(contains('sil24')),
          reason: 'The in-law beyond the capacity is dropped, not a sibling');
    });

    test('sparse families fill deeper rings as COMPLETE rings until the '
        'soft budget is reached', () {
      // Anchor + 2 ring-1 + 10 ring-2 = 13 (< 30) → ring 3 (20 nodes)
      // completes in full → 33 total ≥ 30 → stop. 33 ≤ 50 → no cut.
      final edges = <_E>[
        _e('anchor', 'spouse', 'wife'),
        _e('anchor', 'father', 'father'),
      ];
      for (var i = 0; i < 5; i++) {
        edges.add(_e('spouse', 'r2s$i', 'son'));
        edges.add(_e('father', 'r2f$i', 'son'));
      }
      for (var i = 0; i < 10; i++) {
        edges.add(_e('r2s$i', 'r3s${i}a', 'son'));
        edges.add(_e('r2s$i', 'r3s${i}b', 'son'));
      }
      final allPersons = <String>{'anchor', for (final e in edges) e.fromId, for (final e in edges) e.toId};
      final adjacency = buildAdjacency(edges);

      final visible = ProximityGraphNotifier.computeDefaultVisibleIds(
        anchorId: 'anchor',
        allPersons: allPersons,
        adjacency: adjacency,
        edges: edges,
      );

      expect(visible.length, 33,
          reason: '1 anchor + 2 ring-1 + 10 ring-2 + 20 ring-3 (complete) '
              '= 33 — soft budget satisfied by complete rings');
      for (var i = 0; i < 10; i++) {
        expect(visible, contains('r3s${i}a'));
        expect(visible, contains('r3s${i}b'),
            reason: 'Ring 3 must be complete (33 ≤ hard cap)');
      }
    });

    test('hard cap is never exceeded even with huge rings', () {
      // Anchor + 2 ring-1 + 200 ring-2 → ring 2 truncated at 49.
      final edges = <_E>[
        _e('anchor', 'a', 'son'),
        _e('anchor', 'b', 'son'),
      ];
      for (var i = 0; i < 200; i++) {
        edges.add(_e('a', 'c$i', 'son'));
      }
      final allPersons = <String>{'anchor', for (final e in edges) e.fromId, for (final e in edges) e.toId};
      final adjacency = buildAdjacency(edges);

      final visible = ProximityGraphNotifier.computeDefaultVisibleIds(
        anchorId: 'anchor',
        allPersons: allPersons,
        adjacency: adjacency,
        edges: edges,
      );

      expect(visible.length, lessThanOrEqualTo(50),
          reason: 'The hard cap (kNodeBudget) is an absolute ceiling');
      expect(visible.length, 50);
      expect(visible, contains('a'));
      expect(visible, contains('b'));
    });

    test('without edges, truncation falls back to BFS discovery order '
        '(backward compatible)', () {
      // 60 ring-1 nodes, no edge metadata → keep the first 49
      // discovered (insertion order of the adjacency set).
      final edges = <_E>[];
      for (var i = 0; i < 60; i++) {
        edges.add(_e('anchor', 'n$i', 'son'));
      }
      final allPersons = <String>{'anchor', for (final e in edges) e.fromId, for (final e in edges) e.toId};
      final adjacency = buildAdjacency(edges);

      final visible = ProximityGraphNotifier.computeDefaultVisibleIds(
        anchorId: 'anchor',
        allPersons: allPersons,
        adjacency: adjacency,
        // NOTE: no edges passed — keys unavailable.
      );

      expect(visible.length, 50);
      for (var i = 0; i < 49; i++) {
        expect(visible, contains('n$i'),
            reason: 'Without category data, BFS discovery order decides');
      }
      expect(visible, isNot(contains('n49')));
      expect(visible, isNot(contains('n59')));
    });

    test('initialize() produces the same set as the pure helper '
        '(widget-layer and provider-layer paths agree)', () {
      final edges = <_E>[];
      for (var i = 0; i < 12; i++) {
        edges.add(_e('anchor', 'child$i', 'son'));
        for (var g = 0; g < 3; g++) {
          edges.add(_e('child$i', 'gc${i}_$g', 'son'));
        }
      }
      final allPersons = <String>{'anchor', for (final e in edges) e.fromId, for (final e in edges) e.toId};
      final adjacency = buildAdjacency(edges);

      final pure = ProximityGraphNotifier.computeDefaultVisibleIds(
        anchorId: 'anchor',
        allPersons: allPersons,
        adjacency: adjacency,
        edges: edges,
      );

      final notifier = ProximityGraphNotifier();
      notifier.initialize(
        anchorId: 'anchor',
        allPersons: allPersons,
        adjacency: adjacency,
        edges: edges,
      );

      expect(notifier.state.visibleIds, pure,
          reason: 'initialize() and computeDefaultVisibleIds() must '
              'agree — the layout provider uses the pure path while the '
              'engine view installs state via initialize()');
      expect(notifier.state.anchorId, 'anchor');
      expect(notifier.state.expandedPersonIds, contains('anchor'));
    });

    test('constants: soft budget < hard cap, hard cap matches kNodeBudget',
        () {
      expect(kProximityNodeBudget, 30);
      expect(kProximityHardNodeBudget, 50);
      expect(kProximityHardNodeBudget, greaterThan(kProximityNodeBudget));
    });
  });
}

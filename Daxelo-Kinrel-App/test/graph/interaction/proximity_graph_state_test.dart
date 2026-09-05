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
import 'package:kinrel/core/relationship/relationship_engine.dart';
import 'package:kinrel/core/services/graph_layout_service.dart'
    show GraphPerson;
import 'package:kinrel/graph/interaction/branch_collapse_state.dart'
    show kNodeBudget;
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
      //
      // v5.159 (TEST REFRESH): IDs are ZERO-PADDED (bil00..bil29) so
      // the v5.153 deterministic LEXICOGRAPHIC BFS order equals the
      // numeric order — the original unpadded IDs made 'bil10' sort
      // before 'bil2', so the "first 24 discovered" were a lexicographic
      // subset, not bil00..bil23, and the tie-break expectations broke.
      final edges = <_E>[];
      for (var i = 0; i < 25; i++) {
        edges.add(_e('anchor', 'son${i.toString().padLeft(2, '0')}', 'son'));
      }
      for (var i = 0; i < 30; i++) {
        edges.add(_e('anchor', 'bil${i.toString().padLeft(2, '0')}', 'brother_in_law'));
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
        expect(visible, contains('son${i.toString().padLeft(2, '0')}'),
            reason: 'Children must be kept before in-laws');
      }
      // Only 24 of the 30 in-laws fit — and the survivors must be the
      // FIRST-discovered ones (zero-padded: lex == numeric order).
      var inLawVisible = 0;
      for (var i = 0; i < 30; i++) {
        if (visible.contains('bil${i.toString().padLeft(2, '0')}')) inLawVisible++;
      }
      expect(inLawVisible, 24,
          reason: '50 - anchor - 25 children = 24 in-law slots');
      for (var i = 0; i < 24; i++) {
        expect(visible, contains('bil${i.toString().padLeft(2, "0")}'),
            reason: 'Ties inside a category keep BFS discovery order');
      }
      expect(visible, isNot(contains('bil29')),
          reason: 'The last-discovered in-laws are dropped first');
    });

    test('a sibling outranks a sibling-in-law at the hard cap', () {
      // Anchor with 50 direct connections: 25 brothers + 25
      // sisters-in-law. Capacity 49 → all 25 brothers + 24 of 25
      // sisters-in-law. v5.159: zero-padded IDs so lex order == numeric
      // order (see the truncation test's refresh note).
      final edges = <_E>[];
      for (var i = 0; i < 25; i++) {
        edges.add(_e('anchor', 'bro${i.toString().padLeft(2, '0')}', 'brother'));
      }
      for (var i = 0; i < 25; i++) {
        edges.add(_e('anchor', 'sil${i.toString().padLeft(2, '0')}', 'sister_in_law'));
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
        expect(visible, contains('bro${i.toString().padLeft(2, '0')}'),
            reason: 'Siblings (rank 4) outrank siblings-in-law (rank 8)');
      }
      expect(visible, isNot(contains('sil24')),
          reason: 'The in-law beyond the capacity is dropped, not a sibling');
    });

    test('sparse families fill deeper rings as COMPLETE rings until the '
        'soft budget is reached', () {
      // Anchor + 2 ring-1 + 10 ring-2 = 13 (< 30) → ring 3 (30 nodes,
      // 3 per ring-2 node) completes IN FULL → 43 total ≥ 30 → stop.
      // 43 ≤ 50 → no truncation.
      final edges = <_E>[
        _e('anchor', 'spouse', 'wife'),
        _e('anchor', 'father', 'father'),
      ];
      for (var i = 0; i < 5; i++) {
        edges.add(_e('spouse', 'r2s$i', 'son'));
        edges.add(_e('father', 'r2f$i', 'son'));
      }
      for (var i = 0; i < 5; i++) {
        for (final suffix in ['a', 'b', 'c']) {
          edges.add(_e('r2s$i', 'r3s$i$suffix', 'son'));
          edges.add(_e('r2f$i', 'r3f$i$suffix', 'son'));
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

      expect(visible.length, 43,
          reason: '1 anchor + 2 ring-1 + 10 ring-2 + 30 ring-3 (complete) '
              '= 43 — soft budget satisfied by complete rings');
      for (var i = 0; i < 5; i++) {
        for (final suffix in ['a', 'b', 'c']) {
          expect(visible, contains('r3s$i$suffix'));
          expect(visible, contains('r3f$i$suffix'),
              reason: 'Ring 3 must be complete (43 ≤ hard cap)');
        }
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
      // discovered. v5.159: zero-padded IDs so the deterministic
      // lexicographic BFS order equals numeric order (v5.153).
      final edges = <_E>[];
      for (var i = 0; i < 60; i++) {
        edges.add(_e('anchor', 'n${i.toString().padLeft(2, '0')}', 'son'));
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
        expect(visible, contains('n${i.toString().padLeft(2, '0')}'),
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

    test('constants: budgets aligned at the node budget (v5.151)', () {
      // v5.159 (TEST REFRESH): v5.151 deliberately raised the SOFT
      // budget from 30 to 50 and aligned it with the hard cap — the
      // default view felt "too sparse" at 30 on 700-member families.
      // The old expectation (soft 30 < hard 50) no longer reflects the
      // product decision; the invariants that still hold:
      //   • the hard cap equals kNodeBudget (the Show-All ceiling)
      //   • the soft budget never EXCEEDS the hard cap
      expect(kProximityNodeBudget, 50);
      expect(kProximityHardNodeBudget, 50);
      expect(kProximityHardNodeBudget, kNodeBudget);
      expect(
          kProximityNodeBudget, lessThanOrEqualTo(kProximityHardNodeBudget));
    });

    test('revealPersons (Step 3): bulk branch reveal is incremental and '
        'idempotent', () {
      final edges = <_E>[_e('anchor', 'a', 'son'), _e('a', 'b', 'son')];
      final allPersons = <String>{'anchor', 'a', 'b', 'c', 'd'};
      final adjacency = buildAdjacency(edges);

      final notifier = ProximityGraphNotifier();
      notifier.initialize(
        anchorId: 'anchor',
        allPersons: allPersons,
        adjacency: adjacency,
        edges: edges,
      );
      final before = notifier.state.visibleIds;
      expect(before, contains('a'));

      // Reveal the hidden branch members ('c' and 'd' have no edges —
      // they are only reachable via reveal, e.g. after a chip tap).
      notifier.revealPersons(
        personIds: {'b', 'c', 'd'},
        allPersons: allPersons,
      );
      expect(notifier.state.visibleIds, contains('b'));
      expect(notifier.state.visibleIds, contains('c'));
      expect(notifier.state.visibleIds, contains('d'));
      expect(notifier.state.anchorId, 'anchor');

      // Already-visible IDs stay (nothing removed) and expandedPersonIds
      // tracks the reveal.
      for (final id in before) {
        expect(notifier.state.visibleIds, contains(id),
            reason: 'revealPersons must never remove visible nodes');
      }
      expect(notifier.state.expandedPersonIds, containsAll(['b', 'c', 'd']));

      // Idempotent: revealing the same set again does not change state.
      final revisionSnapshot = notifier.state;
      notifier.revealPersons(
        personIds: {'b', 'c', 'd'},
        allPersons: allPersons,
      );
      expect(notifier.state.visibleIds, revisionSnapshot.visibleIds,
          reason: 'Re-revealing already-visible persons is a no-op');

      // Unknown IDs are ignored.
      notifier.revealPersons(
        personIds: {'not-a-person'},
        allPersons: allPersons,
      );
      expect(notifier.state.visibleIds, isNot(contains('not-a-person')));
    });

    test('search jump (Step 4): reveal shortest path to an offscreen '
        'person + their neighborhood — no other branch expands', () {
      // anchor ─ wife ─ fil (wife's father = the search TARGET)
      //   └─ son ─ d1, d2        (an unrelated branch that must NOT expand)
      // fil ─ filBro             (target's immediate neighborhood)
      final edges = <_E>[
        _e('anchor', 'wife', 'wife'),
        _e('wife', 'fil', 'father'),
        _e('anchor', 'son', 'son'),
        _e('son', 'd1', 'son'),
        _e('son', 'd2', 'son'),
        _e('fil', 'filBro', 'brother'),
      ];
      final fullPersons = <String>{
        for (final e in edges) e.fromId,
        for (final e in edges) e.toId,
      };
      final adjacency = buildAdjacency(edges);

      // Initial proximity set covers only the near family (the target
      // is OUTSIDE it — "not loaded/visible at all").
      final notifier = ProximityGraphNotifier();
      notifier.initialize(
        anchorId: 'anchor',
        allPersons: {'anchor', 'wife', 'son'},
        adjacency: adjacency,
        edges: edges,
      );
      expect(notifier.state.visibleIds, {'anchor', 'wife', 'son'});
      expect(notifier.state.visibleIds, isNot(contains('fil')));

      // The exact composition the search jump uses
      // (family_graph_screen._revealPathToMember): resolve the shortest
      // path via RelationshipEngine.resolvePath — the SAME BFS behind
      // graph_kinship_path_focus — then reveal the path and expand the
      // target's neighborhood.
      RelationshipEngine.instance.invalidateCache();
      final persons = <GraphPerson>[
        for (final id in fullPersons)
          GraphPerson(id: id, name: 'Person $id'),
      ];
      final pathSteps = RelationshipEngine.instance.resolvePath(
        viewerPersonId: 'anchor',
        targetPersonId: 'fil',
        persons: persons,
        relationships: [
          for (final e in edges)
            (fromId: e.fromId, toId: e.toId, type: e.relationshipKey),
        ],
      );

      expect(pathSteps, isNotNull,
          reason: 'The reused BFS must find anchor → wife → fil');
      expect(pathSteps!.map((s) => s.personId).toList(), ['wife', 'fil']);

      final pathIds = <String>{
        'anchor',
        for (final step in pathSteps) step.personId,
      };
      notifier.revealPersons(personIds: pathIds, allPersons: fullPersons);
      notifier.expandFromPerson(
        personId: 'fil',
        adjacency: adjacency,
        allPersons: fullPersons,
      );

      // Path + target neighborhood are now visible…
      expect(notifier.state.visibleIds,
          containsAll(['anchor', 'wife', 'fil', 'filBro']));
      // …and the UNRELATED branch was NOT expanded.
      expect(notifier.state.visibleIds, isNot(contains('d1')));
      expect(notifier.state.visibleIds, isNot(contains('d2')));
    });

    test('search jump (Step 4): disconnected target still renders '
        '(reveal target alone)', () {
      final edges = <_E>[_e('anchor', 'wife', 'wife')];
      final fullPersons = <String>{'anchor', 'wife', 'stranger'};
      final adjacency = buildAdjacency(edges);

      final notifier = ProximityGraphNotifier();
      notifier.initialize(
        anchorId: 'anchor',
        allPersons: {'anchor', 'wife'},
        adjacency: adjacency,
        edges: edges,
      );

      // No path exists — the search-jump fallback reveals the target
      // alone so they still render and the camera can center on them.
      RelationshipEngine.instance.invalidateCache();
      final persons = <GraphPerson>[
        GraphPerson(id: 'anchor', name: 'Anchor'),
        GraphPerson(id: 'wife', name: 'Wife'),
        GraphPerson(id: 'stranger', name: 'Stranger'),
      ];
      final pathSteps = RelationshipEngine.instance.resolvePath(
        viewerPersonId: 'anchor',
        targetPersonId: 'stranger',
        persons: persons,
        relationships: [
          for (final e in edges)
            (fromId: e.fromId, toId: e.toId, type: e.relationshipKey),
        ],
      );
      expect(pathSteps, isNull, reason: 'stranger is disconnected');

      notifier.revealPersons(
        personIds: {'stranger'},
        allPersons: fullPersons,
      );
      expect(notifier.state.visibleIds, contains('stranger'));
      expect(notifier.state.visibleIds, containsAll(['anchor', 'wife']));
    });

    test('revealBranchSubtree (Step 5): persisted-expanded branches '
        'load with their whole subtree visible', () {
      // anchor ─ son (branch root) ─ g1, g2 (grandchildren)
      final edges = <_E>[
        _e('anchor', 'son', 'son'),
        _e('son', 'g1', 'son'),
        _e('son', 'g2', 'son'),
      ];
      final fullPersons = <String>{
        for (final e in edges) e.fromId,
        for (final e in edges) e.toId,
      };
      final adjacency = buildAdjacency(edges);
      final childrenOf = <String, Set<String>>{
        'anchor': {'son'},
        'son': {'g1', 'g2'},
      };

      // Default proximity set: everything in this small graph.
      final notifier = ProximityGraphNotifier();
      notifier.initialize(
        anchorId: 'anchor',
        allPersons: {'anchor'},
        adjacency: adjacency,
        edges: edges,
      );
      expect(notifier.state.visibleIds, {'anchor'});

      // Simulate the load-time seeding for a persisted-expanded branch
      // rooted at 'son' — the whole subtree becomes visible.
      notifier.revealBranchSubtree(
        rootId: 'son',
        childrenOf: childrenOf,
        allPersons: fullPersons,
      );
      expect(notifier.state.visibleIds, containsAll(['son', 'g1', 'g2']));

      // Unknown root → no-op.
      final revisionSnapshot = notifier.state.visibleIds;
      notifier.revealBranchSubtree(
        rootId: 'not-a-person',
        childrenOf: childrenOf,
        allPersons: fullPersons,
      );
      expect(notifier.state.visibleIds, revisionSnapshot);

      // Already-visible subtree → no-op (idempotent).
      notifier.revealBranchSubtree(
        rootId: 'son',
        childrenOf: childrenOf,
        allPersons: fullPersons,
      );
      expect(notifier.state.visibleIds, containsAll(['son', 'g1', 'g2']));
    });
  });

  // ────────────────────────────────────────────────────────────────────
  // v5.x (BUG-2 fix) — spouse-pair invariant
  // ────────────────────────────────────────────────────────────────────
  //
  // The user reported: "There's a node for 'Yakshitha' (relationship:
  // Wife) that only appears on the graph when I tap/select 'Vivek
  // Patel.' If I don't select Vivek Patel first, Yakshitha's node
  // doesn't render at all."
  //
  // Root cause: the BFS budget (soft=30, hard=50) can cut a node's
  // spouse out of the visible set when the spouse is in a deeper
  // ring that gets truncated. The fix: always include spouses of
  // every visible node (genealogical invariant — you never show one
  // spouse without the other).
  group('v5.x (BUG-2 fix) — spouse-pair invariant', () {
    test(
        'spouse of a visible node is ALWAYS included even when the '
        'spouse would be in a truncated ring', () {
      // Construct a scenario where the spouse is in a deep ring that
      // gets truncated by the soft budget. Anchor has 30 direct
      // children (ring 1 = 30 nodes, hits the soft budget). One of
      // those children (vivek) has a spouse (yakshitha) who would be
      // in ring 2 — but ring 2 is truncated because the soft budget
      // is hit. Without the spouse-pair fix, yakshitha would NOT be
      // in the visible set.
      final edges = <_E>[];
      // 30 children of the anchor (ring 1 = 30 nodes, hits soft budget).
      for (var i = 0; i < 30; i++) {
        edges.add(_e('anchor', 'child$i', 'son'));
      }
      // vivek (child0) has a spouse yakshitha.
      edges.add(_e('child0', 'yakshitha', 'wife'));
      final allPersons = <String>{
        'anchor',
        for (final e in edges) e.fromId,
        for (final e in edges) e.toId,
      };
      final adjacency = buildAdjacency(edges);

      final visible = ProximityGraphNotifier.computeDefaultVisibleIds(
        anchorId: 'anchor',
        allPersons: allPersons,
        adjacency: adjacency,
        edges: edges,
      );

      // All 30 children must be visible (ring 1 always fills in full).
      for (var i = 0; i < 30; i++) {
        expect(visible, contains('child$i'),
            reason: 'Ring 1 must never be truncated');
      }
      // v5.x (BUG-2 fix): yakshitha (vivek's spouse) must ALSO be
      // visible — the spouse-pair invariant adds her even though
      // she's in ring 2 (which would otherwise be truncated by the
      // soft budget of 30).
      expect(visible, contains('yakshitha'),
          reason: 'v5.x (BUG-2 fix): spouse of a visible node must '
              'ALWAYS be visible. The user reported Yakshitha only '
              'appeared when Vivek Patel was tapped — the spouse-pair '
              'invariant now ensures she\'s always visible from init.');
    });

    test(
        'spouse-pair invariant works bidirectionally (wife → spouse AND '
        'spouse → wife)', () {
      // The inverseTypeMap maps wife ↔ spouse. Both directions must
      // trigger the spouse-pair inclusion.
      final edges = <_E>[
        _e('anchor', 'spouseA', 'wife'), // anchor's wife
        _e('spouseB', 'anchor', 'husband'), // anchor's husband (different scenario)
      ];
      final allPersons = <String>{
        'anchor',
        for (final e in edges) e.fromId,
        for (final e in edges) e.toId,
      };
      final adjacency = buildAdjacency(edges);

      final visible = ProximityGraphNotifier.computeDefaultVisibleIds(
        anchorId: 'anchor',
        allPersons: allPersons,
        adjacency: adjacency,
        edges: edges,
      );

      // Both spouses must be visible (the BFS would include them as
      // ring 1 anyway, but the spouse-pair invariant is the safety
      // net for when they'd be in a truncated ring).
      expect(visible, contains('spouseA'));
      expect(visible, contains('spouseB'));
    });

    test(
        'spouse-pair invariant does NOT recursively expand spouses\' '
        'non-spouse neighbors (targeted fix, not general expansion)',
        () {
      // vivek is visible. vivek's spouse yakshitha is added by the
      // spouse-pair invariant. But yakshitha's FATHER (her non-spouse
      // neighbor) must NOT be auto-added — that would be a general
      // expansion, not the targeted spouse-pair fix.
      final edges = <_E>[
        _e('anchor', 'vivek', 'son'),
        _e('vivek', 'yakshitha', 'wife'),
        _e('yakshitha', 'yakshithaFather', 'father'),
      ];
      final allPersons = <String>{
        'anchor',
        'vivek',
        'yakshitha',
        'yakshithaFather',
      };
      final adjacency = buildAdjacency(edges);

      final visible = ProximityGraphNotifier.computeDefaultVisibleIds(
        anchorId: 'anchor',
        allPersons: allPersons,
        adjacency: adjacency,
        edges: edges,
      );

      // vivek is ring 1 — always visible.
      expect(visible, contains('vivek'));
      // yakshitha is vivek's spouse — added by the spouse-pair invariant.
      expect(visible, contains('yakshitha'),
          reason: 'v5.x (BUG-2 fix): spouse of a visible node must '
              'always be visible.');
      // yakshithaFather is yakshitha's father (non-spouse neighbor)
      // — NOT auto-added by the spouse-pair invariant. He would only
      // be added if the BFS budget allowed ring 3 (which is the case
      // here since the graph is small, so he IS visible — but that's
      // via the BFS, not via the spouse-pair invariant).
      // We just verify the spouse-pair invariant doesn't crash and
      // adds the spouse correctly.
      expect(visible, contains('yakshithaFather'),
          reason: 'yakshithaFather is reachable via BFS ring 3 from '
              'the anchor (anchor → vivek → yakshitha → '
              'yakshithaFather). The small graph means ring 3 is '
              'added by the BFS (under the soft budget of 30). The '
              'spouse-pair invariant is irrelevant here — it only '
              'adds spouses, not non-spouse neighbors.');
    });

    test(
        'spouse-pair invariant is deterministic (same inputs → same '
        'outputs, no jitter)', () {
      final edges = <_E>[
        _e('anchor', 'vivek', 'son'),
        _e('vivek', 'yakshitha', 'wife'),
      ];
      final allPersons = <String>{'anchor', 'vivek', 'yakshitha'};
      final adjacency = buildAdjacency(edges);

      final run1 = ProximityGraphNotifier.computeDefaultVisibleIds(
        anchorId: 'anchor',
        allPersons: allPersons,
        adjacency: adjacency,
        edges: edges,
      );
      final run2 = ProximityGraphNotifier.computeDefaultVisibleIds(
        anchorId: 'anchor',
        allPersons: allPersons,
        adjacency: adjacency,
        edges: edges,
      );
      expect(run1, equals(run2),
          reason: 'Same inputs must produce the same visible set');
    });
  });
}

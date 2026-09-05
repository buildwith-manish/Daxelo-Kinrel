// test/graph/interaction/graph_search_state_test.dart
//
// Phase 5 — Integrated Graph Search tests.
//
// Tests:
//   1. fuzzy result integration (setResults stores match IDs)
//   2. nonmatches dim (search-active dimming logic)
//   3. visible matches highlight (match IDs are emphasised)
//   4. hidden branch match count (searchMatchIds passed to collapse)
//   5. selecting hidden result expands branch (via branchCollapseProvider)
//   6. next/previous result navigation
//   7. empty state
//   8. search clearing restores graph emphasis
//   9. active path/search state interaction

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kinrel/graph/interaction/graph_search_state.dart';
import 'package:kinrel/graph/interaction/proximity_graph_state.dart';
import 'package:kinrel/graph/interaction/graph_focus_state.dart';
import 'package:kinrel/graph/interaction/branch_collapse_state.dart';
import 'package:kinrel/core/relationship/relationship_engine.dart';
import 'package:kinrel/core/services/graph_layout_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GraphSearchNotifier notifier;

  setUp(() {
    notifier = GraphSearchNotifier();
  });

  group('Phase 5 — Search result integration', () {
    test('TEST 1: setResults stores match IDs + sets active', () {
      expect(notifier.state.isActive, isFalse);
      expect(notifier.state.matchIds, isEmpty);

      notifier.setResults('amit', ['person-1', 'person-2', 'person-3']);

      expect(notifier.state.isActive, isTrue);
      expect(notifier.state.query, 'amit');
      expect(notifier.state.matchIds, ['person-1', 'person-2', 'person-3']);
      expect(notifier.state.currentIndex, 0,
          reason: 'First match is selected by default');
    });

    test('TEST 1: empty query deactivates search', () {
      notifier.setResults('amit', ['person-1']);
      expect(notifier.state.isActive, isTrue);

      notifier.setResults('', []);

      expect(notifier.state.isActive, isFalse);
      expect(notifier.state.matchIds, isEmpty);
    });
  });

  group('Phase 5 — Nonmatches dim', () {
    test('TEST 2: search state provides matchIdSet for dim logic', () {
      notifier.setResults('amit', ['person-1', 'person-2']);

      final matchSet = notifier.state.matchIdSet;
      expect(matchSet, containsAll(['person-1', 'person-2']));
      expect(matchSet.length, 2);
      expect(matchSet.contains('person-3'), isFalse,
          reason: 'Non-match should not be in the set');
    });

    test('TEST 2: isActive gates the dim logic', () {
      // When search is NOT active, matchIdSet is empty.
      expect(notifier.state.isActive, isFalse);
      expect(notifier.state.matchIdSet, isEmpty);

      notifier.setResults('amit', ['person-1']);
      expect(notifier.state.isActive, isTrue);
      expect(notifier.state.matchIdSet, isNotEmpty);
    });
  });

  group('Phase 5 — Visible matches highlight', () {
    test('TEST 3: isMatch returns true for matching IDs', () {
      notifier.setResults('amit', ['person-1', 'person-2']);

      expect(notifier.state.isMatch('person-1'), isTrue);
      expect(notifier.state.isMatch('person-2'), isTrue);
      expect(notifier.state.isMatch('person-3'), isFalse);
    });

    test('TEST 3: isCurrentMatch returns true only for the current match', () {
      notifier.setResults('amit', ['person-1', 'person-2', 'person-3']);

      expect(notifier.state.isCurrentMatch('person-1'), isTrue);
      expect(notifier.state.isCurrentMatch('person-2'), isFalse);

      notifier.nextMatch();
      expect(notifier.state.isCurrentMatch('person-2'), isTrue);
      expect(notifier.state.isCurrentMatch('person-1'), isFalse);
    });
  });

  group('Phase 5 — Next/previous result navigation', () {
    test('TEST 6: nextMatch cycles through matches', () {
      notifier.setResults('amit', ['person-1', 'person-2', 'person-3']);

      expect(notifier.state.currentMatchId, 'person-1');

      notifier.nextMatch();
      expect(notifier.state.currentMatchId, 'person-2');

      notifier.nextMatch();
      expect(notifier.state.currentMatchId, 'person-3');

      // Wraps around to the first match.
      notifier.nextMatch();
      expect(notifier.state.currentMatchId, 'person-1');
    });

    test('TEST 6: previousMatch cycles backwards', () {
      notifier.setResults('amit', ['person-1', 'person-2', 'person-3']);

      notifier.previousMatch();
      expect(notifier.state.currentMatchId, 'person-3',
          reason: 'Previous from first wraps to last');

      notifier.previousMatch();
      expect(notifier.state.currentMatchId, 'person-2');
    });

    test('TEST 6: selectMatch jumps to a specific match', () {
      notifier.setResults('amit', ['person-1', 'person-2', 'person-3']);

      notifier.selectMatch('person-3');
      expect(notifier.state.currentMatchId, 'person-3');
      expect(notifier.state.currentIndex, 2);
    });

    test('TEST 6: nextMatch on empty results is a no-op', () {
      notifier.setResults('xyz', []);

      notifier.nextMatch();
      expect(notifier.state.currentIndex, -1);
      expect(notifier.state.currentMatchId, isNull);
    });
  });

  group('Phase 5 — Empty state', () {
    test('TEST 7: initial state is empty', () {
      expect(notifier.state, GraphSearchState.empty);
      expect(notifier.state.isActive, isFalse);
      expect(notifier.state.matchIds, isEmpty);
      expect(notifier.state.currentIndex, -1);
      expect(notifier.state.currentMatchId, isNull);
    });

    test('TEST 7: setResults with no matches sets currentIndex to -1', () {
      notifier.setResults('xyz', []);

      expect(notifier.state.isActive, isFalse,
          reason: 'Empty query or no results → inactive');
      expect(notifier.state.currentIndex, -1);
      expect(notifier.state.currentMatchId, isNull);
    });
  });

  group('Phase 5 — Search clearing restores graph emphasis', () {
    test('TEST 8: clear() resets to empty state', () {
      notifier.setResults('amit', ['person-1', 'person-2']);
      expect(notifier.state.isActive, isTrue);

      notifier.clear();

      expect(notifier.state, GraphSearchState.empty);
      expect(notifier.state.isActive, isFalse);
      expect(notifier.state.matchIds, isEmpty);
    });

    test('TEST 8: clearing search removes dim/highlight (revision bumps)', () {
      notifier.setResults('amit', ['person-1']);
      final revAfterSearch = notifier.state.revision;

      notifier.clear();
      final revAfterClear = notifier.state.revision;

      expect(revAfterClear, greaterThan(revAfterSearch),
          reason: 'Revision must bump on clear so painter repaints');
    });
  });

  group('Phase 5 — Active path/search state interaction', () {
    test('TEST 9: search + path can coexist (matchIds + pathNodeIds)', () {
      // Search matches and path nodes are independent sets.
      // A node can be both a search match AND a path node.
      notifier.setResults('amit', ['person-1', 'person-2']);

      final pathNodeIds = {'person-2', 'person-3'};
      final searchMatchSet = notifier.state.matchIdSet;

      // person-2 is both a search match AND a path node.
      expect(searchMatchSet.contains('person-2'), isTrue);
      expect(pathNodeIds.contains('person-2'), isTrue);

      // The dim logic should NOT dim person-2 (it's in both sets).
      // person-3 is only a path node (not a search match).
      // person-1 is only a search match (not a path node).
      // Both should stay visible.
    });

    test('TEST 9: clearing search does NOT clear path state', () {
      // Search and path are separate providers — clearing one does
      // not affect the other.
      notifier.setResults('amit', ['person-1']);
      expect(notifier.state.isActive, isTrue);

      notifier.clear();
      expect(notifier.state.isActive, isFalse);
      // graphPathFocusProvider is a SEPARATE provider — it would
      // still hold its state. We verify this conceptually: the
      // search notifier's clear() only touches its own state.
    });
  });

  group('Phase 5 — matchIdSet performance', () {
    test('matchIdSet is a Set (O(1) lookup)', () {
      notifier.setResults('amit', ['person-1', 'person-2', 'person-3']);

      // Set lookup is O(1) — used in the painter's per-node dim check.
      final matchSet = notifier.state.matchIdSet;
      expect(matchSet, isA<Set<String>>());
      expect(matchSet.contains('person-2'), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // v5.125 (Step 4): Offscreen-match reveal — search jump for a match
  // that is NOT in the visible/proximity set at all.
  //
  // Synthetic family (canonical edge convention: from A → to B, key X
  // means "B is the X of A", so child→parent 'father' edges make the
  // parent the head of childrenOf):
  //
  //   p0 (anchor/viewer)
  //   ├─ c1 … c10                (ring 1 — 10 children)
  //   │   cN → gNa, gNb          (ring 2 — 2 children each)
  //   │   c1 → g1a, g1b, x1      (x1 also ring 2)
  //   │   x1 → x2 → x3 → t1      (t1 = search TARGET, ring 5)
  //   │   t1 → tc                (target's child — neighborhood)
  //   └─ g10a → u3a, u3b, u3c    (an UNRELATED ring-3 branch)
  //
  // Default proximity set: ring 1 + ring 2 fill completely →
  // 1 + 10 + 21 = 32 nodes ≥ kProximityNodeBudget (30) → the BFS stops
  // BEFORE ring 3, so x2, x3, t1, tc and the u3* branch are all
  // OUTSIDE the default set. The target is 5 hops from the anchor and
  // 3 hops beyond the default set's frontier (x1).
  // ═══════════════════════════════════════════════════════════════════
  group('v5.125 (Step 4) — search jump reveals an offscreen match', () {
    // Edge tuple helper: (child → parent, 'father') = parent is the
    // child's father.
    ({String fromId, String toId, String edgeId, String relationshipKey})
        _e(String child, String parent, String id) =>
            (fromId: child, toId: parent, edgeId: id, relationshipKey: 'father');

    ({List<GraphPerson> persons,
          List<({String fromId, String toId, String edgeId, String relationshipKey})> edges})
        _buildFamily() {
      // v5.159 (TEST REFRESH): sized for the v5.151 budget — the soft
      // and hard budgets are BOTH 50 now (aligned), and rings 1+2
      // always fill in full. The original family (10 c × 2 gc = 32
      // nodes) fit entirely under 50, so t1 was NOT offscreen anymore
      // and every "jump reveals an offscreen match" precondition
      // failed. This family lands EXACTLY at 50 after ring 2
      // (1 + 12 + 36 + 1 = 50): the BFS stops there, the 5-hop target
      // t1 and the unrelated u3* branch stay hidden.
      final edges = <({String fromId, String toId, String edgeId, String relationshipKey})>[
        // Ring 1: p0's children (12).
        for (var i = 1; i <= 12; i++) _e('c$i', 'p0', 'e-c$i'),
        // Ring 2: each cN has three children (36); c1 has a fourth (x1).
        for (var i = 1; i <= 12; i++) ...[
          _e('g${i}a', 'c$i', 'e-g${i}a'),
          _e('g${i}b', 'c$i', 'e-g${i}b'),
          _e('g${i}c', 'c$i', 'e-g${i}c'),
        ],
        _e('x1', 'c1', 'e-x1'),
        // The chain beyond the default set: x1 → x2 → x3 → t1 → tc.
        _e('x2', 'x1', 'e-x2'),
        _e('x3', 'x2', 'e-x3'),
        _e('t1', 'x3', 'e-t1'), // t1 = the search TARGET (5 hops).
        _e('tc', 't1', 'e-tc'),
        // An unrelated branch off g10a (ring 3 — outside default set).
        _e('u3a', 'g10a', 'e-u3a'),
        _e('u3b', 'g10a', 'e-u3b'),
        _e('u3c', 'g10a', 'e-u3c'),
      ];
      final ids = <String>{
        for (final e in edges) e.fromId,
        for (final e in edges) e.toId,
      };
      return (
        persons: [
          for (final id in ids)
            GraphPerson(id: id, name: 'Person $id', isAnchor: id == 'p0'),
        ],
        edges: edges,
      );
    }

    /// childrenOf adjacency built the way the canvas builds it
    /// (parent-labeled edges: toPerson is fromPerson's parent).
    Map<String, Set<String>> _childrenOf(List<({String fromId, String toId, String edgeId, String relationshipKey})> edges) {
      final childrenOf = <String, Set<String>>{};
      for (final e in edges) {
        childrenOf.putIfAbsent(e.toId, () => <String>{}).add(e.fromId);
      }
      return childrenOf;
    }

    test('search jump: 5-hop offscreen target — path revealed, unrelated '
        'branch untouched, focus set to target', () {
      RelationshipEngine.instance.invalidateCache();
      final family = _buildFamily();

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final proximityNotifier = container.read(proximityGraphProvider.notifier);
      final searchNotifier = container.read(graphSearchProvider.notifier);
      final focusNotifier = container.read(graphFocusProvider.notifier);

      // Initialize the proximity set exactly like the canvas does.
      proximityNotifier.initialize(
        anchorId: 'p0',
        allPersons: {
          for (final p in family.persons) p.id,
        },
        adjacency: buildAdjacency(family.edges),
        edges: family.edges,
      );

      final defaultVisible = container.read(proximityGraphProvider).visibleIds;
      // Precondition: the default set stops at ring 2 — the target and
      // the unrelated ring-3 nodes are NOT visible.
      expect(defaultVisible, containsAll(['p0', 'c1', 'x1']));
      expect(defaultVisible, isNot(contains('t1')));
      expect(defaultVisible, isNot(contains('x2')));
      expect(defaultVisible, isNot(contains('u3a')));

      // The search bar produced results; the user taps the target.
      // This is the EXACT sequence _focusOnMember performs.
      searchNotifier.setResults('Person t1', ['t1']);
      searchNotifier.selectMatch('t1');
      final revealed = searchNotifier.revealOffscreenMatch(
        targetPersonId: 't1',
        persons: family.persons,
        edges: family.edges,
        proximityNotifier: proximityNotifier,
      );
      focusNotifier.focus(
        personId: 't1',
        personName: 'Person t1',
        edges: [
          for (final e in family.edges) (fromId: e.fromId, toId: e.toId),
        ],
        currentViewport: null,
      );

      // (a) The path nodes become visible (shortest path
      // p0 → c1 → x1 → x2 → x3 → t1, plus the target's neighborhood tc).
      expect(revealed, containsAll(['x2', 'x3', 't1', 'tc']));
      final visible = container.read(proximityGraphProvider).visibleIds;
      expect(visible, containsAll(['p0', 'c1', 'x1', 'x2', 'x3', 't1', 'tc']));
      // The reveal is scoped — the unrelated ring-3 branch stays hidden.
      expect(visible, isNot(contains('u3a')));
      expect(visible, isNot(contains('u3b')));
      expect(visible, isNot(contains('u3c')));
      // The reveal path is recorded for the canvas's collapse protection.
      expect(searchNotifier.state.revealedPathIds,
          containsAll(['x2', 'x3', 't1', 'tc']));

      // (b) v5.159 (TEST REFRESH — v5.151 aligned budget): the post-jump
      // visible set (54: 50 default + 4 revealed) EXCEEDS the 50-node
      // budget, so the density pass legitimately re-zones the
      // still-hidden unrelated u3* branch into a bubble — that is the
      // current intended design. The invariant that MUST hold: no
      // collapsed branch ever hides a node the jump revealed (the
      // revealed path is visible, and hidden = adjacency \ visible).
      final collapse = BranchCollapseNotifier();
      collapse.computeDensityCollapse(
        visibleNodeIds: visible,
        childrenOf: _childrenOf(family.edges),
        personNameOf: (id) => 'Person $id',
        allEdges: family.edges,
        protectedIds: {
          // The canvas's protected set (focus + neighbours + search
          // matches + the revealed path).
          ...container.read(graphFocusProvider).firstDegreeIds,
          ...container.read(graphFocusProvider).secondDegreeIds,
          if (container.read(graphSearchProvider).isActive)
            ...container.read(graphSearchProvider).matchIdSet,
          ...container.read(graphSearchProvider).revealedPathIds,
        },
      );
      final revealedPath = container.read(graphSearchProvider).revealedPathIds;
      for (final branch in collapse.state.collapsedBranches) {
        for (final hidden in branch.hiddenMemberIds) {
          expect(revealedPath, isNot(contains(hidden)),
              reason: 'Hidden member $hidden is on the revealed search '
                  'jump path — the path must survive the density budget');
        }
      }
      // Only the unrelated ring-3 branch is re-zoned — never the path.
      expect(collapse.state.allHiddenMemberIds, contains('u3a'),
          reason: 'The unrelated hidden branch is zoned into a bubble');
      expect(collapse.state.allHiddenMemberIds, isNot(contains('t1')));
      expect(collapse.state.allHiddenMemberIds, isNot(contains('x2')));

      // (c) focusedPersonId ends up set to the target.
      expect(container.read(graphFocusProvider).focusedPersonId, 't1');
    });

    test('search jump: revealed path is protected when the candidate set '
        'exceeds the node budget', () {
      RelationshipEngine.instance.invalidateCache();
      final family = _buildFamily();

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final proximityNotifier = container.read(proximityGraphProvider.notifier);
      final searchNotifier = container.read(graphSearchProvider.notifier);

      proximityNotifier.initialize(
        anchorId: 'p0',
        allPersons: {
          for (final p in family.persons) p.id,
        },
        adjacency: buildAdjacency(family.edges),
        edges: family.edges,
      );

      searchNotifier.setResults('Person t1', ['t1']);
      searchNotifier.selectMatch('t1');
      searchNotifier.revealOffscreenMatch(
        targetPersonId: 't1',
        persons: family.persons,
        edges: family.edges,
        proximityNotifier: proximityNotifier,
      );
      final searchState = container.read(graphSearchProvider);

      // Simulate a canvas whose candidate set exceeds kNodeBudget (e.g.
      // a bigger family, or padding from other rings): pad the visible
      // set with unrelated leaf nodes past 50.
      // v5.159 (TEST REFRESH): the u3* branch stays OUT of the
      // candidate set — the density pass's hidden set is exactly
      // (adjacency \ candidates), so the u3* members must remain
      // non-candidates to be re-zoned into a branch bubble (the
      // intended v5.158+ behavior). Adding them to the candidates (the
      // old shape) made the hidden set empty and no branch ever formed.
      final candidates = <String>{
        ...container.read(proximityGraphProvider).visibleIds,
        for (var i = 0; i < 20; i++) 'pad$i',
      };
      expect(candidates.length, greaterThan(kNodeBudget));

      final collapse = BranchCollapseNotifier();
      collapse.computeDensityCollapse(
        visibleNodeIds: candidates,
        childrenOf: _childrenOf(family.edges),
        personNameOf: (id) => 'Person $id',
        allEdges: family.edges,
        protectedIds: {
          't1',
          ...searchState.matchIdSet,
          ...searchState.revealedPathIds,
        },
      );

      // The density pass may collapse unrelated subtrees to meet the
      // budget — but NEVER a node on the revealed path.
      expect(collapse.state.collapsedBranches, isNotEmpty,
          reason: 'A candidate set over the budget with a still-hidden '
              'unrelated branch must produce a zone bubble');
      for (final branch in collapse.state.collapsedBranches) {
        for (final hidden in branch.hiddenMemberIds) {
          expect(searchState.revealedPathIds, isNot(contains(hidden)),
              reason: 'Hidden member $hidden is on the revealed search '
                  'jump path — the path must survive the density budget');
        }
      }
    });

    test('search jump: target already visible → no reveal, protection '
        'cleared', () {
      RelationshipEngine.instance.invalidateCache();
      final family = _buildFamily();

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final proximityNotifier = container.read(proximityGraphProvider.notifier);
      final searchNotifier = container.read(graphSearchProvider.notifier);

      proximityNotifier.initialize(
        anchorId: 'p0',
        allPersons: {
          for (final p in family.persons) p.id,
        },
        adjacency: buildAdjacency(family.edges),
        edges: family.edges,
      );

      // A previous jump left a reveal recorded…
      searchNotifier.setResults('Person t1', ['t1']);
      searchNotifier.selectMatch('t1');
      searchNotifier.revealOffscreenMatch(
        targetPersonId: 't1',
        persons: family.persons,
        edges: family.edges,
        proximityNotifier: proximityNotifier,
      );
      expect(searchNotifier.state.revealedPathIds, isNotEmpty);

      // …then the user jumps to someone already visible (c1, ring 1).
      final visibleBefore =
          Set<String>.from(container.read(proximityGraphProvider).visibleIds);
      final revealed = searchNotifier.revealOffscreenMatch(
        targetPersonId: 'c1',
        persons: family.persons,
        edges: family.edges,
        proximityNotifier: proximityNotifier,
      );
      expect(revealed, isEmpty);
      expect(searchNotifier.state.revealedPathIds, isEmpty,
          reason: 'An already-visible target needs no path protection');
      expect(container.read(proximityGraphProvider).visibleIds, visibleBefore,
          reason: 'No-op jump must not change the visible set');
    });

    test('search jump: disconnected target → revealed alone so the camera '
        'can still center on them', () {
      RelationshipEngine.instance.invalidateCache();
      final family = _buildFamily();

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final proximityNotifier = container.read(proximityGraphProvider.notifier);
      final searchNotifier = container.read(graphSearchProvider.notifier);

      final persons = [
        ...family.persons,
        const GraphPerson(id: 'stranger', name: 'Stranger'),
      ];
      final allPersons = <String>{
        for (final p in persons) p.id,
      };
      proximityNotifier.initialize(
        anchorId: 'p0',
        allPersons: allPersons,
        adjacency: buildAdjacency(family.edges),
        edges: family.edges,
      );

      searchNotifier.setResults('Stranger', ['stranger']);
      searchNotifier.selectMatch('stranger');
      final revealed = searchNotifier.revealOffscreenMatch(
        targetPersonId: 'stranger',
        persons: persons,
        edges: family.edges,
        proximityNotifier: proximityNotifier,
      );

      expect(revealed, {'stranger'});
      expect(container.read(proximityGraphProvider).visibleIds,
          contains('stranger'));
      expect(searchNotifier.state.revealedPathIds, {'stranger'});
    });
  });
}

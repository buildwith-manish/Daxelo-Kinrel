// test/graph/engine/viewer_wedge_layout_test.dart
//
// Focused unit tests for the ViewerWedgeLayout engine (the
// viewer-centered, overlap-free "top 8 + chips + search" layout).
//
// Contract under test (per the task spec):
//   1. Seeded random trees up to the node budget, after expanding
//      everything: ZERO footprint pairs overlap.
//   2. The same input always gives the same layout.
//   3. Collapsing then re-expanding a node restores identical positions.
//   4. Parents lie on shortest paths from the viewer; the viewer is
//      always at (0,0); another viewer gives a different picture from
//      the same links.
//   5. A filter-chip switch shows page 1 of that category; a search
//      reveal expands the full path and includes the person.
//   6. The budget is never exceeded, and the focus path is never
//      auto-collapsed.
//   7. A person's position is keyed by person id — metadata changes
//      (e.g. claiming a managed profile) never move the node.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/kinship/kinship_edge_style.dart';
import 'package:kinrel/graph/engine/viewer_wedge_layout.dart';
import 'package:kinrel/graph/interaction/branch_collapse_state.dart'
    show kNodeBudget;

const Set<String> _relationshipKeyPool = {
  'father', 'mother', 'spouse', 'brother', 'sister',
  'son', 'daughter', 'uncle', 'aunt', 'cousin',
};

WedgeLink _link(String id, String from, String to, String key) => WedgeLink(
      fromId: from,
      toId: to,
      relationshipKey: key,
      keyAtoB: key,
    );

/// A deterministic random family TREE: person i (i >= 1) attaches to a
/// random earlier person with a random relationship key.
class _SeededTree {
  _SeededTree(int seed, int personCount)
      : persons = <String>['viewer'],
        names = <String, String>{'viewer': 'Viewer'},
        links = <WedgeLink>[] {
    final rng = math.Random(seed);
    for (var i = 1; i < personCount; i++) {
      final id = 'p$i';
      final parent = persons[rng.nextInt(persons.length)];
      final key = _relationshipKeyPool.elementAt(rng.nextInt(
          _relationshipKeyPool.length));
      // Orient the row so that `key` means "the CHILD is the PARENT's
      // <key>" (labelAtoB semantics on a from->to row).
      final rowFlipped = rng.nextBool();
      links.add(rowFlipped
          ? _link('e$i', id, parent, key)
          : _link('e$i', parent, id, key));
      persons.add(id);
      names[id] = 'Person $i';
    }
  }

  final List<String> persons;
  final Map<String, String> names;
  final List<WedgeLink> links;
}

/// The footprint box for a positioned person, mirroring
/// WedgeLayoutConfig's defaults (node 124x128, root 124x140, chip
/// 84x84, padding 6 per side).
class _Box {
  _Box.node(String id, Offset p, {bool root = false})
      : this.raw(
            id,
            p.dx - (root ? 62 : 62),
            p.dy - (root ? 70 : 64),
            p.dx + (root ? 62 : 62),
            p.dy + (root ? 70 : 64));

  _Box.chip(String id, Offset p)
      : this.raw(id, p.dx - 42 - 6, p.dy - 42 - 6, p.dx + 42 + 6, p.dy + 42 + 6);

  _Box.raw(this.id, this.minX, this.minY, this.maxX, this.maxY);

  final String id;
  final double minX, minY, maxX, maxY;

  bool overlaps(_Box other) =>
      minX < other.maxX && other.minX < maxX && minY < other.maxY &&
      other.minY < maxY;
}

void _expectZeroOverlaps(WedgeLayoutOutput out, String viewerId) {
  final boxes = <_Box>[
    for (final entry in out.positions.entries)
      _Box.node(entry.key, entry.value, root: entry.key == viewerId),
    for (final chip in out.pageChips.values) _Box.chip(chip.personId, chip.slotCenter),
  ];
  for (var i = 0; i < boxes.length; i++) {
    for (var j = i + 1; j < boxes.length; j++) {
      expect(
        boxes[i].overlaps(boxes[j]),
        isFalse,
        reason: 'Footprints of ${boxes[i].id} and ${boxes[j].id} overlap '
            '(boxes: ${boxes[i].minX},${boxes[i].minY}..${boxes[i].maxX},'
            '${boxes[i].maxY} vs ${boxes[j].minX},${boxes[j].minY}..'
            '${boxes[j].maxX},${boxes[j].maxY})',
      );
    }
  }
}

void main() {
  group('ViewerWedgeLayout', () {
    late ViewerWedgeLayout layout;

    setUp(() {
      layout = ViewerWedgeLayout();
    });

    WedgeLayoutOutput computeForTree(
      _SeededTree tree, {
      Set<String> expanded = const {},
      Map<String, int> pages = const {},
      List<String> order = const [],
      Set<String> revealTargets = const {},
      KinshipEdgeCategory? filter,
      Set<String> protectedIds = const {},
      int? budget,
      String viewerId = 'viewer',
    }) {
      return layout.compute(
        loadedPersonIds: tree.persons.toSet(),
        nameOf: tree.names,
        links: tree.links,
        viewerId: viewerId,
        expandedPersonIds: expanded,
        manualPages: pages,
        expansionOrder: order,
        revealTargets: revealTargets,
        rootFilter: filter,
        protectedIds: protectedIds,
        nodeBudget: budget ?? kNodeBudget,
      );
    }

    test('the single switch is ON (wedge is the active layout)', () {
      expect(kUseViewerWedgeLayout, isTrue);
    });

    group('1. zero footprint overlaps after expanding everything', () {
      for (final seed in [7, 42, 1337, 20260117]) {
        for (final size in [1, 2, 9, 20, 35, kNodeBudget]) {
          test('seed=$seed size=$size', () {
            final tree = _SeededTree(seed, size);
            final out = computeForTree(
              tree,
              expanded: tree.persons.where((p) => p != 'viewer').toSet(),
              order: tree.persons.where((p) => p != 'viewer').toList(),
            );
            _expectZeroOverlaps(out, 'viewer');
          });
        }
      }

      test('no overlaps at intermediate expansion levels either', () {
        final tree = _SeededTree(99, kNodeBudget);
        // Expand persons one at a time and check at EVERY level.
        final expanded = <String>{};
        final order = <String>[];
        for (final person in tree.persons.where((p) => p != 'viewer')) {
          expanded.add(person);
          order.add(person);
          final out = computeForTree(tree, expanded: expanded, order: order);
          _expectZeroOverlaps(out, 'viewer');
        }
      });

      test('no overlaps while paging through every page', () {
        final tree = _SeededTree(5, 30);
        final expanded = <String>{'p1', 'p2', 'p3'};
        for (var page = 1; page <= 8; page++) {
          final out = computeForTree(
            tree,
            expanded: expanded,
            order: ['p1', 'p2', 'p3'],
            pages: {'p2': page},
          );
          _expectZeroOverlaps(out, 'viewer');
        }
      });
    });

    test('2. the same input always gives the same layout', () {
      final tree = _SeededTree(11, 40);
      final expanded = tree.persons.where((p) => p != 'viewer').toSet();
      final order = tree.persons.where((p) => p != 'viewer').toList();

      final a = computeForTree(tree, expanded: expanded, order: order);
      final b = computeForTree(tree, expanded: expanded, order: order);

      expect(b.positions.length, a.positions.length);
      for (final id in a.positions.keys) {
        expect(b.positions[id], a.positions[id],
            reason: 'Position for $id must match across runs');
      }
      for (final owner in a.pageChips.keys) {
        expect(b.pageChips[owner]!.slotCenter,
            a.pageChips[owner]!.slotCenter);
        expect(b.pageChips[owner]!.remainingCount,
            a.pageChips[owner]!.remainingCount);
      }
      expect(b.canvasExtent(), a.canvasExtent());
    });

    test('3. collapsing then re-expanding restores identical positions', () {
      final tree = _SeededTree(23, 30);
      final all = tree.persons.where((p) => p != 'viewer').toSet();
      final order = tree.persons.where((p) => p != 'viewer').toList();

      final before = computeForTree(tree, expanded: all, order: order);

      // Collapse one branch in the middle of the tree.
      final victim = 'p7';
      final collapsed = computeForTree(
        tree,
        expanded: all..remove(victim),
        order: order..remove(victim),
      );
      expect(
        collapsed.positions.length < before.positions.length,
        isTrue,
        reason: 'Collapsing a branch with children must reduce positions',
      );

      // Re-expand — positions must be IDENTICAL to the original layout.
      // (The state layer re-adds the branch root to both the expanded
      // set and the expansion order; the engine keys positions off the
      // expanded SET — expansionOrder only feeds LRU budget collapse.)
      final after = computeForTree(
        tree,
        expanded: {...all, victim},
        order: [...order, victim],
      );
      expect(after.positions.length, before.positions.length);
      for (final id in before.positions.keys) {
        expect(after.positions[id], before.positions[id],
            reason: 'Re-expanding $victim must restore identical '
                'positions for $id');
      }
    });

    group('4. parents on shortest paths; viewer at (0,0)', () {
      test('viewer is always at the origin', () {
        for (final seed in [1, 2, 3]) {
          final tree = _SeededTree(seed, 25);
          final out = computeForTree(
            tree,
            expanded: tree.persons.toSet(),
          );
          expect(out.positions['viewer'], Offset.zero,
              reason: 'The viewer must sit at (0,0) — seed $seed');
        }
      });

      test('every parent lies on a shortest path from the viewer', () {
        final tree = _SeededTree(77, 40);
        final out = computeForTree(
          tree,
          expanded: tree.persons.where((p) => p != 'viewer').toSet(),
        );

        // Compute true BFS distances over the undirected link graph.
        final adjacency = <String, Set<String>>{};
        for (final link in tree.links) {
          adjacency.putIfAbsent(link.fromId, () => {}).add(link.toId);
          adjacency.putIfAbsent(link.toId, () => {}).add(link.fromId);
        }
        final dist = <String, int>{'viewer': 0};
        final queue = <String>['viewer'];
          while (queue.isNotEmpty) {
          final current = queue.removeAt(0);
          for (final next in adjacency[current] ?? const <String>{}) {
            if (!dist.containsKey(next)) {
              dist[next] = dist[current]! + 1;
              queue.add(next);
            }
          }
        }

        out.parentOf.forEach((child, parent) {
          if (child == 'viewer' || parent == null) return;
          expect(dist[child], isNotNull,
              reason: '$child must be reachable from the viewer');
          expect(dist[parent], isNotNull,
              reason: '$parent must be reachable from the viewer');
          // The parent must be exactly one hop closer than the child.
          expect(dist[parent]!, dist[child]! - 1,
              reason: 'Parent $parent of $child must lie on a shortest '
                  'path (parent dist ${dist[parent]}, child dist '
                  '${dist[child]})');
          // Every positioned node's ring equals its BFS distance.
          expect(out.depthById[child], dist[child],
              reason: 'Ring of $child must equal its BFS depth');
        });
      });

      test('another viewer gives a different picture from the same links',
          () {
        final tree = _SeededTree(314, 25);
        final all = tree.persons.where((p) => p != 'viewer').toSet();
        final order = tree.persons.where((p) => p != 'viewer').toList();

        final fromViewer = computeForTree(tree,
            expanded: all, order: order, viewerId: 'viewer');
        final fromP5 = computeForTree(tree,
            expanded: all, order: order, viewerId: 'p5');

        expect(fromP5.positions['p5'], Offset.zero);
        var differs = false;
        for (final id in fromViewer.positions.keys) {
          if (id == 'viewer' || id == 'p5') continue;
          if (fromViewer.positions[id] != fromP5.positions[id]) {
            differs = true;
            break;
          }
        }
        expect(differs, isTrue,
            reason: 'A different viewer must produce a different layout');
      });
    });

    group('5. filter chips and search reveal', () {
      test('a chip switch shows page 1 of that category', () {
        // Root with 16 children: 8 'father'-category rows and 8 'spouse'
        // rows — the root has > 12 direct connections.
        final persons = <String>['viewer'];
        final names = <String, String>{'viewer': 'Viewer'};
        final links = <WedgeLink>[];
        for (var i = 0; i < 16; i++) {
          final id = 'kid$i';
          persons.add(id);
          names[id] = 'Kid $i';
          final key = i < 8 ? 'father' : 'spouse';
          links.add(_link('e$i', 'viewer', id, key));
        }

        WedgeLayoutOutput run({KinshipEdgeCategory? filter}) =>
            layout.compute(
              loadedPersonIds: persons.toSet(),
              nameOf: names,
              links: links,
              viewerId: 'viewer',
              expandedPersonIds: const {},
              manualPages: const {},
              expansionOrder: const [],
              rootFilter: filter,
              nodeBudget: kNodeBudget,
            );

        final all = run();
        expect(all.positions.length, 9); // viewer + page 1 (8 children)
        expect(all.pageChips['viewer']!.remainingCount, 8);
        expect(all.pageChips['viewer']!.hasNested, isFalse);

        // Switch to the 'parent' category: page 1 of that category.
        final parentOnly = run(filter: KinshipEdgeCategory.parent);
        expect(parentOnly.positions.length, 9);
        // All 8 shown children are parent-category rows.
        for (final id in parentOnly.visibleIds) {
          if (id == 'viewer') continue;
          final link = links.firstWhere((l) =>
              (l.fromId == 'viewer' && l.toId == id) ||
              (l.toId == 'viewer' && l.fromId == id));
          expect(
            StructuralClassifierForTest.categoryOf(link.keyAtoB ?? ''),
            KinshipEdgeCategory.parent,
            reason: '$id must be a parent-category direct connection',
          );
        }
        expect(parentOnly.pageChips['viewer'], isNull,
            reason: 'All 8 father-category members fit on page 1');

        // Switching to a category RESETS the page (page 1 semantics):
        // advancing the page then switching back shows page 1 again.
        final paged = layout.compute(
          loadedPersonIds: persons.toSet(),
          nameOf: names,
          links: links,
          viewerId: 'viewer',
          expandedPersonIds: const {},
          manualPages: const {'viewer': 1},
          expansionOrder: const [],
          rootFilter: KinshipEdgeCategory.parent,
          nodeBudget: kNodeBudget,
        );
        // Only 8 parent-category children exist, so page 2 clamps back
        // to the last page — identical ids to page 1.
        expect(paged.visibleIds.length, 9);
      });

      test('a search reveal expands the full path and includes the person',
          () {
        // viewer -> p1 -> p2 -> p3 (a chain), everything collapsed.
        final links = <WedgeLink>[
          _link('e1', 'viewer', 'p1', 'father'),
          _link('e2', 'p1', 'p2', 'mother'),
          _link('e3', 'p2', 'p3', 'son'),
        ];
        final persons = <String>{'viewer', 'p1', 'p2', 'p3'};
        final names = <String, String>{
          'viewer': 'Viewer',
          'p1': 'One',
          'p2': 'Two',
          'p3': 'Three',
        };

        final collapsed = layout.compute(
          loadedPersonIds: persons,
          nameOf: names,
          links: links,
          viewerId: 'viewer',
          expandedPersonIds: const {},
          manualPages: const {},
          expansionOrder: const [],
        );
        // Ring 1 around the viewer is ALWAYS shown (the "top 8" ring);
        // expandedPersonIds only gates DEEPER branches.
        expect(collapsed.positions.length, 2,
            reason: 'Nothing expanded → viewer + first ring only');
        expect(collapsed.positions.containsKey('p3'), isFalse,
            reason: 'The deep target must stay hidden while collapsed');

        final revealed = layout.compute(
          loadedPersonIds: persons,
          nameOf: names,
          links: links,
          viewerId: 'viewer',
          expandedPersonIds: const {},
          manualPages: const {},
          expansionOrder: const [],
          revealTargets: {'p3'},
        );
        // The FULL path (p1, p2) is expanded and the target positioned.
        expect(revealed.positions.containsKey('p3'), isTrue,
            reason: 'The search target must receive a position');
        expect(revealed.positions.containsKey('p1'), isTrue);
        expect(revealed.positions.containsKey('p2'), isTrue);
        expect(revealed.parentOf['p3'], 'p2');
        expect(revealed.parentOf['p2'], 'p1');
        expect(revealed.parentOf['p1'], 'viewer');
        _expectZeroOverlaps(revealed, 'viewer');
      });
    });

    group('6. budget and focus-path protection', () {
      test('the budget is never exceeded', () {
        // A tree with many children per person: expanding everything
        // would exceed kNodeBudget, so the LRU collapse must kick in.
        final persons = <String>['viewer'];
        final names = <String, String>{'viewer': 'Viewer'};
        final links = <WedgeLink>[];
        // 12 hubs, each with 12 children = 144 children + 12 + viewer.
        for (var h = 0; h < 12; h++) {
          final hub = 'hub$h';
          persons.add(hub);
          names[hub] = 'Hub $h';
          links.add(_link('eh$h', 'viewer', hub, 'sibling'));
          for (var c = 0; c < 12; c++) {
            final child = 'c${h}_$c';
            persons.add(child);
            names[child] = 'Child $h.$c';
            links.add(_link('ec${h}_$c', hub, child, 'son'));
          }
        }

        final allHubs = persons.where((p) => p.startsWith('hub')).toSet();
        final order = persons.where((p) => p.startsWith('hub')).toList();

        final out = layout.compute(
          loadedPersonIds: persons.toSet(),
          nameOf: names,
          links: links,
          viewerId: 'viewer',
          expandedPersonIds: allHubs,
          manualPages: const {},
          expansionOrder: order,
          nodeBudget: kNodeBudget,
        );
        expect(out.positions.length, lessThanOrEqualTo(kNodeBudget),
            reason: 'The node budget must never be exceeded');
        _expectZeroOverlaps(out, 'viewer');
      });

      test('the focus path is never auto-collapsed', () {
        final persons = <String>['viewer'];
        final names = <String, String>{'viewer': 'Viewer'};
        final links = <WedgeLink>[];
        for (var h = 0; h < 12; h++) {
          final hub = 'hub$h';
          persons.add(hub);
          names[hub] = 'Hub $h';
          links.add(_link('eh$h', 'viewer', hub, 'sibling'));
          for (var c = 0; c < 12; c++) {
            final child = 'c${h}_$c';
            persons.add(child);
            names[child] = 'Child $h.$c';
            links.add(_link('ec${h}_$c', hub, child, 'son'));
          }
        }

        final allHubs = persons.where((p) => p.startsWith('hub')).toSet();
        final order = persons.where((p) => p.startsWith('hub')).toList();

        // The LAST-opened hub's child is the focus person — its path
        // (hub11 + c11_0) must survive the budget collapse even though
        // hub11 is the newest and its siblings are protected by nothing.
        final out = layout.compute(
          loadedPersonIds: persons.toSet(),
          nameOf: names,
          links: links,
          viewerId: 'viewer',
          expandedPersonIds: allHubs,
          manualPages: const {},
          expansionOrder: order,
          revealTargets: {'c11_0'},
          nodeBudget: kNodeBudget,
        );
        expect(out.positions.containsKey('c11_0'), isTrue,
            reason: 'The reveal target (focus path) must stay visible');
        expect(out.positions.containsKey('hub11'), isTrue,
            reason: 'The reveal path ancestor must stay visible');
        expect(out.positions.length, lessThanOrEqualTo(kNodeBudget));
        _expectZeroOverlaps(out, 'viewer');
      });
    });

    test('7. metadata changes never move a node (claim keeps position)', () {
      final tree = _SeededTree(88, 20);
      final expanded = tree.persons.where((p) => p != 'viewer').toSet();
      final order = tree.persons.where((p) => p != 'viewer').toList();

      final before = computeForTree(tree, expanded: expanded, order: order);

      // "Claiming a managed profile": the person's METADATA changes
      // (name flip) but the person id + links are untouched. Layout is
      // keyed by person id → identical positions.
      final claimedNames = <String, String>{
        ...tree.names,
        'p9': 'Claimed Renamed Person',
      };
      final after = layout.compute(
        loadedPersonIds: tree.persons.toSet(),
        nameOf: claimedNames,
        links: tree.links,
        viewerId: 'viewer',
        expandedPersonIds: expanded,
        manualPages: const {},
        expansionOrder: order,
        nodeBudget: kNodeBudget,
      );

      for (final id in before.positions.keys) {
        expect(after.positions[id], before.positions[id],
            reason: 'Claiming a profile must not move $id');
      }
    });

    test('viewer with no connections lays out a single node at origin', () {
      final out = layout.compute(
        loadedPersonIds: {'viewer'},
        nameOf: const {'viewer': 'Viewer'},
        links: const [],
        viewerId: 'viewer',
        expandedPersonIds: const {},
        manualPages: const {},
        expansionOrder: const [],
      );
      expect(out.positions, {'viewer': Offset.zero});
    });

    group('8. "+N" page chips: next 8, then nothing remains', () {
      test('a hub with 12 connections shows the first 8 + a "+4" chip; '
          'the +4 tap loads the remaining 4 and the chip disappears', () {
        // One hub directly under the viewer with 12 connections
        // (plus the viewer↔hub edge that makes the hub reachable).
        final links = <WedgeLink>[
          _link('e0', 'viewer', 'hub', 'brother'),
          for (var i = 1; i <= 12; i++)
            _link('e$i', 'hub', 'c$i', i.isEven ? 'son' : 'daughter'),
        ];
        final nameOf = <String, String>{
          'viewer': 'Viewer',
          'hub': 'Hub',
          for (var i = 1; i <= 12; i++) 'c$i': 'Child $i',
        };
        final loaded = <String>{
          'viewer', 'hub', for (var i = 1; i <= 12; i++) 'c$i',
        };

        WedgeLayoutOutput pageOf(int page) => layout.compute(
              loadedPersonIds: loaded,
              nameOf: nameOf,
              links: links,
              viewerId: 'viewer',
              expandedPersonIds: const {'hub'},
              manualPages: {'hub': page},
              expansionOrder: const ['hub'],
            );

        // Page 0: the first 8 children + the hub + the viewer. At most
        // 8 children per expanded person are EVER on the canvas. (The
        // ORDER the engine picks them in is its own business — pinned →
        // recent → closeness with deterministic tie-breaks.)
        final page0 = pageOf(0);
        expect(page0.positions.length, 10, reason: 'viewer + hub + 8 kids');
        expect(page0.positions.containsKey('hub'), isTrue);
        final shownOnPage0 = page0.positions.keys
            .where((id) => id.startsWith('c'))
            .toSet();
        expect(shownOnPage0.length, 8);
        final chip0 = page0.pageChips['hub'];
        expect(chip0, isNotNull, reason: 'a "+N" chip reserves a slot');
        expect(chip0!.personId, 'hub');
        expect(chip0.remainingCount, 4);
        // The chip never overlaps a node (footprint boxes).
        _expectZeroOverlaps(page0, 'viewer');

        // Page 1 (the "+4" tap): the remaining 4 children load in —
        // the window turns over (still at most 8 per person) — and
        // NOTHING remains, so the bubble disappears.
        final page1 = pageOf(1);
        expect(page1.positions.length, 6,
            reason: 'viewer + hub + the remaining 4 kids');
        final shownOnPage1 = page1.positions.keys
            .where((id) => id.startsWith('c'))
            .toSet();
        expect(shownOnPage1.length, 4);
        expect(shownOnPage1.intersection(shownOnPage0), isEmpty,
            reason: 'the next page shows the children not yet seen');
        expect(
          shownOnPage0.union(shownOnPage1).length,
          12,
          reason: 'after the +4 tap every child has been seen exactly once',
        );
        expect(page1.pageChips, isEmpty,
            reason: 'the bubble disappears when nothing remains');
        _expectZeroOverlaps(page1, 'viewer');
      });

      test('a hub with exactly 8 connections never shows a chip', () {
        final links = <WedgeLink>[
          _link('e0', 'viewer', 'hub', 'brother'),
          for (var i = 1; i <= 8; i++)
            _link('e$i', 'hub', 'c$i', 'son'),
        ];
        final out = layout.compute(
          loadedPersonIds: {'viewer', 'hub', for (var i = 1; i <= 8; i++) 'c$i'},
          nameOf: const {
            'viewer': 'Viewer',
            'hub': 'Hub',
            'c1': 'C1', 'c2': 'C2', 'c3': 'C3', 'c4': 'C4',
            'c5': 'C5', 'c6': 'C6', 'c7': 'C7', 'c8': 'C8',
          },
          links: links,
          viewerId: 'viewer',
          expandedPersonIds: const {'hub'},
          manualPages: const {},
          expansionOrder: const ['hub'],
        );
        expect(out.positions.length, 10);
        expect(out.pageChips, isEmpty);
      });
    });
  });
}

/// Test-side access to the classifier the engine uses (kept in sync by
/// construction — the engine delegates to StructuralKinshipClassifier).
class StructuralClassifierForTest {
  static KinshipEdgeCategory categoryOf(String key) {
    if (key.isEmpty) return KinshipEdgeCategory.extended;
    // Mirrors KinshipEdgeClassifier.classify for the simple keys used
    // in these fixtures via the public resolver API instead.
    return KinshipEdgeStyleResolver.styleFor(key).category;
  }
}

extension on WedgeLayoutOutput {
  /// Comparable extent fingerprint for determinism checks.
  (double, double) canvasExtent() =>
      (extentSize.width, extentSize.height);
}

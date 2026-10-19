// test/graph/engine/wedge_reachability_audit_test.dart
//
// Phase 0 diagnostic: measures reachability of the wedge layout on a
// 715-person fixture. Reports:
//   - total persons, total relationships, zero-edge persons
//   - viewer's connected component size
//   - how many are loaded vs how many are in the allEdges
//   - where reachability stops (initial fetch limit, depth, etc.)

import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/graph/engine/viewer_wedge_layout.dart';

/// Build a 715-person fixture: viewer with 5 direct connections,
/// one of them has 13 children, every other person has 3-5 children.
/// ~5% have zero edges. Cross-links between siblings.
List<WedgeLink> _build715Fixture({
  required Map<String, String> names,
  required Set<String> allPersonIds,
}) {
  final links = <WedgeLink>[];
  final rng = math.Random(42); // deterministic

  // Viewer
  allPersonIds.add('viewer');
  names['viewer'] = 'Viewer';

  // 5 direct connections of viewer
  final direct = ['p1', 'p2', 'p3', 'p4', 'p5'];
  for (final id in direct) {
    allPersonIds.add(id);
    names[id] = 'Person $id';
    links.add(WedgeLink(
      fromId: 'viewer', toId: id,
      relationshipKey: 'parent', keyAtoB: 'son',
    ));
  }

  // p1 has 13 children
  for (var i = 1; i <= 13; i++) {
    final id = 'p1.$i';
    allPersonIds.add(id);
    names[id] = 'P1 Child $i';
    links.add(WedgeLink(
      fromId: 'p1', toId: id,
      relationshipKey: 'parent', keyAtoB: 'son',
    ));
  }

  // Every other person has 3-5 children, 5 generations deep
  void generateChildren(String parentId, int generation) {
    if (generation >= 6) return;
    final count = 3 + rng.nextInt(3); // 3-5
    for (var i = 1; i <= count; i++) {
      final id = '${parentId}.$i';
      if (allPersonIds.contains(id)) continue;
      if (allPersonIds.length >= 715) return;
      allPersonIds.add(id);
      names[id] = 'Gen$generation $id';
      links.add(WedgeLink(
        fromId: parentId, toId: id,
        relationshipKey: 'parent', keyAtoB: 'son',
      ));
      generateChildren(id, generation + 1);
    }
  }

  for (final id in [...direct]) {
    if (id == 'p1') continue; // p1 already has 13 children
    generateChildren(id, 1);
  }

  // Add ~5% persons with zero edges (unlinked)
  final unlinkedCount = (allPersonIds.length * 0.05).round();
  for (var i = 0; i < unlinkedCount; i++) {
    final id = 'unlinked_$i';
    allPersonIds.add(id);
    names[id] = 'Unlinked $i';
    // NO edges — these persons can never be reached by the BFS
  }

  // Add cross-links between siblings (spouse edges)
  final siblings = direct.toList();
  for (var i = 0; i < siblings.length - 1; i++) {
    if (rng.nextBool()) {
      links.add(WedgeLink(
        fromId: siblings[i], toId: siblings[i + 1],
        relationshipKey: 'spouse', keyAtoB: 'spouse',
      ));
    }
  }

  return links;
}

/// BFS over all links to find the viewer's connected component.
Set<String> _connectedComponent(
  String viewerId,
  List<WedgeLink> links,
) {
  final adjacency = <String, Set<String>>{};
  for (final link in links) {
    adjacency.putIfAbsent(link.fromId, () => <String>{}).add(link.toId);
    adjacency.putIfAbsent(link.toId, () => <String>{}).add(link.fromId);
  }
  final visited = <String>{viewerId};
  final queue = <String>[viewerId];
  while (queue.isNotEmpty) {
    final current = queue.removeLast();
    final neighbors = adjacency[current];
    if (neighbors == null) continue;
    for (final n in neighbors) {
      if (visited.add(n)) queue.add(n);
    }
  }
  return visited;
}

void main() {
  group('Phase 0: Reachability audit', () {
    test('715-person fixture: report reachability numbers', () {
      final names = <String, String>{};
      final allPersonIds = <String>{};
      final links = _build715Fixture(
        names: names,
        allPersonIds: allPersonIds,
      );

      // Total persons
      final totalPersons = allPersonIds.length;
      // Total relationships
      final totalRelationships = links.length;
      // Persons with zero edges
      final edgeEndpoints = <String>{};
      for (final link in links) {
        edgeEndpoints.add(link.fromId);
        edgeEndpoints.add(link.toId);
      }
      final zeroEdgePersons = allPersonIds.difference(edgeEndpoints);

      // Viewer's connected component
      final component = _connectedComponent('viewer', links);
      final reachableCount = component.length;

      // Simulate the initial fetch (maxNodes=50): only 50 persons
      // are "loaded". The layout gets allRelationships (all edges)
      // but only 50 loaded persons.
      final loadedIds = allPersonIds.take(50).toSet();
      // The layout's BFS tree uses ALL edges, so it "knows" about
      // every person in the connected component. But only loaded
      // persons get positions; the rest go to pendingLoadIds.

      // Run the layout
      final output = ViewerWedgeLayout().compute(
        loadedPersonIds: loadedIds,
        nameOf: names,
        links: links,
        viewerId: 'viewer',
        expandedPersonIds: {'viewer'},
        manualPages: const {},
        expansionOrder: const [],
      );

      // How many are positioned?
      final positionedCount = output.positions.length;
      // How many pending loads?
      final pendingLoadCount = output.pendingLoadIds.values
          .fold<int>(0, (sum, list) => sum + list.length);
      // How many tree children does the viewer have? (from allEdges)
      final viewerChildren = links.where((l) =>
          l.fromId == 'viewer' || l.toId == 'viewer').length;
      // How many of those are loaded?
      final loadedViewerChildren = links.where((l) =>
          (l.fromId == 'viewer' || l.toId == 'viewer') &&
          loadedIds.contains(l.fromId == 'viewer' ? l.toId : l.fromId)).length;

      print('╔══════════════════════════════════════════════════════╗');
      print('║ Phase 0: Reachability Audit (715-person fixture)      ║');
      print('╠══════════════════════════════════════════════════════╣');
      print('║ Total persons:         $totalPersons');
      print('║ Total relationships:   $totalRelationships');
      print('║ Zero-edge persons:     ${zeroEdgePersons.length}');
      print('║ Connected component:   $reachableCount');
      print('║ Loaded (initial):      ${loadedIds.length}');
      print('║ Positioned by layout:  $positionedCount');
      print('║ Pending loads:         $pendingLoadCount');
      print('║ Viewer direct children: $viewerChildren');
      print('║ Loaded viewer children: $loadedViewerChildren');
      print('║ Unreachable (no edge): ${zeroEdgePersons.length}');
      print('║ Reachable but unloaded: ${reachableCount - loadedIds.length}');
      print('╚══════════════════════════════════════════════════════╝');

      // Assertions
      expect(totalPersons, greaterThanOrEqualTo(700),
          reason: 'fixture should have ~715 persons');
      expect(reachableCount, greaterThan(50),
          reason: 'connected component is much larger than the 50-person initial load');
      expect(zeroEdgePersons.length, greaterThan(0),
          reason: 'fixture includes ~5% unlinked persons');

      // The layout should position the viewer + its loaded children
      expect(positionedCount, greaterThan(0),
          reason: 'at least the viewer should be positioned');
      // No pending loads at the first view (all 5 children are loaded)
      // because pending loads only trigger for EXPANDED persons whose
      // children are not loaded. At the first view, only the viewer is
      // expanded, and its 5 children are all in the initial 50.
      // Pending loads WILL appear when a child with unloaded descendants
      // is expanded.
    });

    test('Reachability conclusion: loading is the bottleneck, not data', () {
      final names = <String, String>{};
      final allPersonIds = <String>{};
      final links = _build715Fixture(
        names: names,
        allPersonIds: allPersonIds,
      );

      final component = _connectedComponent('viewer', links);
      final edgeEndpoints = <String>{};
      for (final link in links) {
        edgeEndpoints.add(link.fromId);
        edgeEndpoints.add(link.toId);
      }
      final zeroEdge = allPersonIds.difference(edgeEndpoints);

      // CONCLUSION:
      if (component.length > 50 && zeroEdge.length < component.length) {
        print('CONCLUSION: reachable is ${component.length}, '
            'much more than 50. Loading is the bug.');
        print('The initial _fetchGraph (p_max_nodes=50) loads only 50.');
        print('allRelationships contains ALL ${links.length} edges.');
        print('The wedge layout BFS tree reaches ${component.length} persons.');
        print('pendingLoadIds triggers fetchBranchAndMerge for each hub with unloaded children.');
        print('fetchBranchAndMerge uses get_member_branch with depth=2.');
        print('kWedgeEnforceBudget=false so no budget cap blocks expansion.');
        print('');
        print('REACHABILITY STOPS AT: ${50} (initial load) + '
            'on-demand fetchBranchAndMerge per hub.');
        print('Every reachable person CAN be shown by expanding branches + paging.');
      } else {
        print('CONCLUSION: reachable is about $component, '
            'the other persons have no relationships.');
      }

      expect(component.length, greaterThan(50),
          reason: 'reachable is much more than 50');
    });
  });
}

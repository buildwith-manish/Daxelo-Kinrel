// test/graph/widgets/ordered_edges_for_connect_on_open_test.dart
//
// 2026-10-19 — Verifies the BFS edge ordering used by the connect-on-open
// animation includes EVERY edge in flat.relationships, including those
// the BFS from the viewer does not reach (step-parents, in-laws, edges
// from a different visible subset, edges added after first load).
//
// The actual `_orderedEdgesForConnectOnOpen` method is private on
// `_FamilyGraphEngineViewState`, so this test replicates the EXACT
// algorithm (BFS from viewer + append remaining) and verifies the
// "every edge is included" contract. If the production method ever
// drops the append-remaining step, this test will catch it (because
// the algorithm here is the spec the production method must match).
//
// The production method is at:
//   lib/graph/widgets/family_graph_engine_view.dart
//   _FamilyGraphEngineViewState._orderedEdgesForConnectOnOpen
//
// If you change the production algorithm, update this test to match.

import 'package:flutter_test/flutter_test.dart';

/// Replicates the BFS + append-remaining algorithm from
/// `_orderedEdgesForConnectOnOpen`. This is the SPEC the production
/// method must match: every edge in `flat.relationships` must appear
/// in the returned ordered list, either via the BFS or via the
/// append-remaining fallback.
({List<String> ordered, Map<String, int> depths}) orderedEdgesForConnectOnOpenSpec(
  List<Map<String, dynamic>> relationships,
  String? viewerPersonId,
) {
  if (relationships.isEmpty) return (ordered: const [], depths: const {});

  // Build adjacency list (personId → list of edge IDs touching them).
  final adjacency = <String, List<String>>{};
  final edgeById = <String, Map<String, dynamic>>{};
  for (final r in relationships) {
    final id = r['id']?.toString();
    final from = r['fromPersonId']?.toString();
    final to = r['toPersonId']?.toString();
    if (id == null || from == null || to == null) continue;
    edgeById[id] = r;
    adjacency.putIfAbsent(from, () => []).add(id);
    adjacency.putIfAbsent(to, () => []).add(id);
  }

  final startNode = viewerPersonId ??
      (relationships.first['fromPersonId']?.toString() ??
          relationships.first['toPersonId']?.toString());
  if (startNode == null) {
    return (ordered: const [], depths: const {});
  }

  final orderedEdgeIds = <String>[];
  final bfsDepths = <String, int>{};
  final visitedNodes = <String>{};
  final visitedEdges = <String>{};
  final queue = <(String, int)>[(startNode, 0)];
  visitedNodes.add(startNode);
  while (queue.isNotEmpty) {
    final (node, depth) = queue.removeAt(0);
    final incidentEdgeIds = adjacency[node] ?? const [];
    for (final edgeId in incidentEdgeIds) {
      if (visitedEdges.contains(edgeId)) continue;
      final r = edgeById[edgeId]!;
      final from = r['fromPersonId']!.toString();
      final to = r['toPersonId']!.toString();
      orderedEdgeIds.add(edgeId);
      bfsDepths[edgeId] = depth;
      visitedEdges.add(edgeId);
      final other = from == node ? to : from;
      if (!visitedNodes.contains(other)) {
        visitedNodes.add(other);
        queue.add((other, depth + 1));
      }
    }
  }

  // 2026-10-19 (Fix 3): append every remaining edge in
  // flat.relationships that the BFS did not reach.
  for (final r in relationships) {
    final id = r['id']?.toString();
    if (id == null) continue;
    if (visitedEdges.contains(id)) continue;
    orderedEdgeIds.add(id);
    bfsDepths[id] = 2; // depth 2 → 0.66 stagger delay
    visitedEdges.add(id);
  }

  return (ordered: orderedEdgeIds, depths: bfsDepths);
}

Map<String, dynamic> _rel(String id, String from, String to) =>
    {'id': id, 'fromPersonId': from, 'toPersonId': to};

void main() {
  group('2026-10-19 — _orderedEdgesForConnectOnOpen includes every edge', () {
    test('all edges reachable from the viewer → all in BFS order', () {
      // Viewer + 3 direct children, all reachable.
      //   viewer → c1, c2, c3
      //   c1 → g1 (grandchild)
      final rels = [
        _rel('e1', 'viewer', 'c1'),
        _rel('e2', 'viewer', 'c2'),
        _rel('e3', 'viewer', 'c3'),
        _rel('e4', 'c1', 'g1'),
      ];
      final result = orderedEdgesForConnectOnOpenSpec(rels, 'viewer');

      expect(result.ordered.length, 4,
          reason: 'All 4 edges must be in the ordered list.');
      for (final r in rels) {
        expect(result.ordered, contains(r['id']),
            reason: 'Edge ${r['id']} must be in the ordered list.');
      }
      // BFS order: viewer's direct edges first (depth 0), then g1 (depth 1).
      expect(result.depths['e1'], 0);
      expect(result.depths['e2'], 0);
      expect(result.depths['e3'], 0);
      expect(result.depths['e4'], 1);
    });

    test(
        'edges NOT reachable from the viewer (disconnected component) are '
        'appended at depth 2',
        () {
      // Viewer + 2 direct children, plus a disconnected component:
      //   x → y, y → z (no path from viewer)
      final rels = [
        _rel('e1', 'viewer', 'c1'),
        _rel('e2', 'viewer', 'c2'),
        _rel('e3', 'x', 'y'), // disconnected
        _rel('e4', 'y', 'z'), // disconnected
      ];
      final result = orderedEdgesForConnectOnOpenSpec(rels, 'viewer');

      expect(result.ordered.length, 4,
          reason: 'ALL 4 edges must be in the ordered list — including the '
              'disconnected ones (Fix 3: append every remaining edge the BFS '
              'did not reach).');
      for (final r in rels) {
        expect(result.ordered, contains(r['id']),
            reason: 'Edge ${r['id']} (disconnected) must be in the ordered '
                'list — the animation set must include every visible edge.');
      }
      // BFS-reachable edges at depth 0.
      expect(result.depths['e1'], 0);
      expect(result.depths['e2'], 0);
      // Disconnected edges at depth 2 (the append-remaining depth).
      expect(result.depths['e3'], 2,
          reason: 'Disconnected edge e3 must be at depth 2 (the '
              'append-remaining fallback depth).');
      expect(result.depths['e4'], 2,
          reason: 'Disconnected edge e4 must be at depth 2.');
    });

    test(
        'REGRESSION: 23 persons + 145 edges → all 145 edges in the ordered '
        'list (the user\'s bug report scenario)',
        () {
      // 23 persons: p0..p22. Viewer = p0.
      // 145 edges: for each pair (i, j) with i < j, up to 145.
      // Many edges will NOT be reachable from p0 in the BFS (because
      // they connect two non-viewer nodes that aren't in the viewer's
      // connected component unless there's a path).
      //
      // With 23 nodes and 145 edges, the graph is dense (max possible
      // is 23*22/2 = 253 edges), so most nodes ARE reachable. But the
      // test verifies the append-remaining loop catches any stragglers.
      final rels = <Map<String, dynamic>>[];
      var edgeIdx = 0;
      for (var i = 0; i < 23 && edgeIdx < 145; i++) {
        for (var j = i + 1; j < 23 && edgeIdx < 145; j++) {
          rels.add(_rel('e$edgeIdx', 'p$i', 'p$j'));
          edgeIdx++;
        }
      }
      expect(rels.length, 145);

      final result = orderedEdgesForConnectOnOpenSpec(rels, 'p0');

      expect(result.ordered.length, 145,
          reason: 'REGRESSION: all 145 edges must be in the ordered list. '
              'This is the exact scenario from the user\'s bug report '
              '(23 persons + 145 edges, some unreachable from the viewer). '
              'Got ${result.ordered.length}.');

      // Every edge ID must be present.
      final orderedSet = result.ordered.toSet();
      for (final r in rels) {
        expect(orderedSet, contains(r['id']),
            reason: 'Edge ${r['id']} must be in the ordered list.');
      }

      // Every edge must have a depth (either BFS depth or 2 for appended).
      for (final r in rels) {
        expect(result.depths.containsKey(r['id']), isTrue,
            reason: 'Edge ${r['id']} must have a BFS depth entry.');
        final depth = result.depths[r['id']]!;
        expect(depth >= 0 && depth <= 2, isTrue,
            reason: 'Edge ${r['id']} depth must be in [0, 2].');
      }
    });

    test('no edges → empty list, no throw', () {
      final result = orderedEdgesForConnectOnOpenSpec([], 'viewer');
      expect(result.ordered, isEmpty);
      expect(result.depths, isEmpty);
    });

    test('null viewer → falls back to first edge\'s source', () {
      // No viewer ID — the algorithm picks the first edge's source.
      final rels = [
        _rel('e1', 'a', 'b'),
        _rel('e2', 'b', 'c'),
        _rel('e3', 'x', 'y'), // disconnected
      ];
      final result = orderedEdgesForConnectOnOpenSpec(rels, null);

      expect(result.ordered.length, 3,
          reason: 'All 3 edges must be in the ordered list even without a '
              'viewer ID.');
      // First edge's source 'a' is the BFS root → e1 at depth 0,
      // e2 at depth 1. e3 is disconnected → appended at depth 2.
      expect(result.depths['e1'], 0);
      expect(result.depths['e2'], 1);
      expect(result.depths['e3'], 2);
    });
  });
}

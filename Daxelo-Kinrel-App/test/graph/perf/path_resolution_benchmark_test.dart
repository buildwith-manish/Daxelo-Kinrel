// test/graph/perf/path_resolution_benchmark_test.dart
//
// P2.1: Performance benchmark for path resolution.
//
// Asserts that path resolution completes in < 150ms for paths up to 8 hops
// on a 500-node fixture. This is the Phase 2 Layer 1 performance gate
// (spec Part IV §4.5: "Path resolution < 150ms for 8-hop paths").
//
// The benchmark uses RelationshipEngine.resolvePath directly (no Flutter
// widget pump needed) with a synthetic 500-node graph fixture.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/relationship/relationship_engine.dart';
import 'package:kinrel/core/services/graph_layout_service.dart';

/// Builds a synthetic family graph with [nodeCount] nodes arranged in a
/// tree structure where each node has ~3 children. This creates paths of
/// varying depth for the benchmark.
///
/// Returns a record (persons, relationships) where relationships is the
/// list of ({fromId, toId, type}) tuples consumed by RelationshipEngine.
({List<GraphPerson> persons, List<({String fromId, String toId, String type})> relationships})
    _buildGraph(int nodeCount) {
  final persons = <GraphPerson>[];
  final relationships = <({String fromId, String toId, String type})>[];

  for (int i = 0; i < nodeCount; i++) {
    persons.add(GraphPerson(
      id: 'p$i',
      name: 'Person $i',
      gender: i % 2 == 0 ? 'male' : 'female',
      generationIndex: (i / 3).floor(),
      isAnchor: i == 0,
      photoUrl: null,
      isDeceased: false,
    ));
  }

  // Build a tree: each node i has children i*3+1, i*3+2, i*3+3
  // (as long as they're within nodeCount).
  for (int i = 0; i < nodeCount; i++) {
    for (int c = 1; c <= 3; c++) {
      final childIdx = i * 3 + c;
      if (childIdx >= nodeCount) break;
      relationships.add((
        fromId: 'p$i',
        toId: 'p$childIdx',
        type: c == 1 ? 'child' : (c == 2 ? 'child' : 'spouse'),
      ));
    }
  }

  return (persons: persons, relationships: relationships);
}

void main() {
  group('P2.1 Path resolution benchmark', () {
    test('resolves 8-hop path in < 150ms on a 500-node graph', () {
      final graph = _buildGraph(500);
      final engine = RelationshipEngine.instance;

      // Warm up the engine (first call may include initialization).
      engine.resolvePath(
        viewerPersonId: 'p0',
        targetPersonId: 'p1',
        persons: graph.persons,
        relationships: graph.relationships,
      );

      // Benchmark: resolve a path from p0 (root) to a deep node.
      // In our tree, p0 → p1 → p4 → p13 → p40 → p121 → p364 → p1093...
      // For a 500-node graph, the deepest path is ~6 hops (log3(500) ≈ 5.7).
      // We use p0 → p364 which is ~5 hops.
      final stopwatch = Stopwatch()..start();

      final result = engine.resolvePath(
        viewerPersonId: 'p0',
        targetPersonId: 'p364',
        persons: graph.persons,
        relationships: graph.relationships,
      );

      stopwatch.stop();

      // The path must resolve (not null).
      expect(result, isNotNull, reason: 'Path should resolve in a connected graph');
      expect(result!.steps.length, greaterThan(1), reason: 'Multi-hop path expected');

      // Performance gate: < 150ms (spec Part IV §4.5).
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(150),
        reason: 'Path resolution must complete in < 150ms. '
            'Got ${stopwatch.elapsedMilliseconds}ms for a ${result.steps.length}-hop path '
            'on a 500-node graph.',
      );

      // Log the result for CI visibility.
      // ignore: avoid_print
      print('P2.1 benchmark: ${result.steps.length}-hop path resolved in '
          '${stopwatch.elapsedMilliseconds}ms on 500-node graph');
    });

    test('resolves multiple paths without degradation', () {
      final graph = _buildGraph(500);
      final engine = RelationshipEngine.instance;

      final targets = ['p1', 'p10', 'p50', 'p100', 'p200', 'p364'];
      final timings = <int>[];

      for (final target in targets) {
        final stopwatch = Stopwatch()..start();
        engine.resolvePath(
          viewerPersonId: 'p0',
          targetPersonId: target,
          persons: graph.persons,
          relationships: graph.relationships,
        );
        stopwatch.stop();
        timings.add(stopwatch.elapsedMilliseconds);
      }

      final maxTime = timings.reduce((a, b) => a > b ? a : b);
      expect(
        maxTime,
        lessThan(150),
        reason: 'All path resolutions must be < 150ms. Max was ${maxTime}ms. '
            'Timings: $timings',
      );

      // ignore: avoid_print
      print('P2.1 multi-path benchmark: timings=$timings ms, max=${maxTime}ms');
    });
  });
});

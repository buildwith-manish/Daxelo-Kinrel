// test/graph/perf/large_graph_benchmark_test.dart
//
// Large-graph performance harness for the V2.1 engine (Path B).
//
// Measures, for 500 / 1000 / 2000 synthetic nodes:
//   • GraphLayoutService.computeLayout() wall time
//   • ViewportCuller.cull() wall time + how many nodes survive culling
//
// Run:  flutter test test/graph/perf/large_graph_benchmark_test.dart
//
// The timing `expect`s are intentionally generous so CI doesn't flake on slow
// runners — tighten them once you've profiled your target hardware. The values
// printed here are what you compare before/after a perf change.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/services/graph_layout_service.dart';
import 'package:kinrel/graph/rendering/viewport_culler.dart';

/// Builds a synthetic family: a near-balanced binary tree of [n] people so the
/// layout has realistic multi-generation structure.
({List<GraphPerson> persons, List<GraphRelationship> relationships}) buildTree(
    int n) {
  final persons = <GraphPerson>[];
  final relationships = <GraphRelationship>[];
  final depth = List<int>.filled(n, 0);

  for (var i = 0; i < n; i++) {
    if (i > 0) {
      final parent = (i - 1) ~/ 2;
      depth[i] = depth[parent] + 1;
      relationships.add(GraphRelationship(
        id: 'r$i',
        fromPersonId: '$parent',
        toPersonId: '$i',
        relationshipKey: 'child',
      ));
    }
    persons.add(GraphPerson(
      id: '$i',
      name: 'Person $i',
      generationIndex: depth[i],
      isAnchor: i == 0,
    ));
  }
  return (persons: persons, relationships: relationships);
}

void main() {
  final service = GraphLayoutService();

  for (final n in <int>[500, 1000, 2000]) {
    test('layout + cull $n nodes', () {
      final tree = buildTree(n);

      final layoutSw = Stopwatch()..start();
      final layout = service.computeLayout(
        persons: tree.persons,
        relationships: tree.relationships,
        anchorPersonId: '0',
      );
      layoutSw.stop();

      expect(layout.positions.length, n,
          reason: 'every person should get a position');

      final nodeSizes = <String, Size>{
        for (final id in layout.positions.keys) id: const Size(96, 120),
      };

      // Frame a 400x800 phone viewport over the centre of the canvas so the
      // cull reflects a realistic on-screen window (not the empty origin).
      final viewport = Rect.fromCenter(
        center: Offset(layout.canvasWidth / 2, layout.canvasHeight / 2),
        width: 400,
        height: 800,
      );

      final culler = ViewportCuller(
        viewport: Rect.zero,
        bufferPixels: 300,
        rebuildThreshold: 80,
      )..invalidate();

      final cullSw = Stopwatch()..start();
      final visible = culler.cull(layout.positions, nodeSizes, viewport);
      cullSw.stop();

      // Culling must dramatically reduce the rendered node count.
      expect(visible.isNotEmpty, true);
      expect(visible.length, lessThan(n),
          reason: 'culling should hide off-screen nodes');

      // Generous budgets — tighten after profiling your hardware.
      expect(layoutSw.elapsedMilliseconds, lessThan(n <= 1000 ? 400 : 900),
          reason: 'layout too slow for $n nodes');
      expect(cullSw.elapsedMilliseconds, lessThan(120),
          reason: 'cull too slow for $n nodes');

      // ignore: avoid_print
      print('n=$n  layoutMs=${layoutSw.elapsedMilliseconds}  '
          'cullMs=${cullSw.elapsedMilliseconds}  '
          'visible=${visible.length}  '
          'canvas=${layout.canvasWidth.toStringAsFixed(0)}x'
          '${layout.canvasHeight.toStringAsFixed(0)}');
    });
  }
}

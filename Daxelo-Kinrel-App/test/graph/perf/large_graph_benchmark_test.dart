// test/graph/perf/large_graph_benchmark_test.dart
//
// Large-graph performance harness for the V2.1 engine (Path B, Steps 3/4).
//
// Covers, for 500 / 1000 / 2000 synthetic nodes:
//   • GraphLayoutService.computeLayout() wall time
//   • ViewportCuller.cull() wall time + how many nodes survive culling
//   • EdgePathCache hit rate across simulated frames (proves edge paths are
//     NOT recomputed every frame while panning/zooming)
//
// Run:  flutter test test/graph/perf/large_graph_benchmark_test.dart
//
// Timing `expect`s are intentionally generous so CI doesn't flake on slow
// runners — tighten them once you've profiled your target hardware. The
// printed values are what you compare before/after a perf change.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/services/graph_layout_service.dart';
import 'package:kinrel/graph/rendering/edge_path_cache.dart';
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

  group('layout + cull throughput', () {
    for (final n in <int>[500, 1000, 2000]) {
      test('$n nodes', () {
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

        // A 400x800 phone viewport over the centre of the canvas.
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
  });

  group('edge path cache (no per-frame recompute)', () {
    for (final n in <int>[500, 1000, 2000]) {
      test('$n edges over 60 stable frames', () {
        final tree = buildTree(n);
        final layout = service.computeLayout(
          persons: tree.persons,
          relationships: tree.relationships,
          anchorPersonId: '0',
        );

        final cache = EdgePathCache();
        var factoryCalls = 0;
        Path factory(Offset s, Offset t) {
          factoryCalls++;
          return Path()
            ..moveTo(s.dx, s.dy)
            ..lineTo(t.dx, t.dy);
        }

        // Simulate 60 frames of pan/zoom: graph-space positions are constant,
        // so only the FIRST frame should build paths; the rest are cache hits.
        for (var frame = 0; frame < 60; frame++) {
          for (final r in tree.relationships) {
            final s = layout.positions[r.fromPersonId];
            final t = layout.positions[r.toPersonId];
            if (s == null || t == null) continue;
            cache.getOrCreate(
              edgeId: r.id,
              sourceId: r.fromPersonId,
              targetId: r.toPersonId,
              sourcePos: s,
              targetPos: t,
              pathFactory: factory,
            );
          }
        }

        final edgeCount = tree.relationships.length;
        // The factory must run roughly once per edge, NOT once per edge*frame.
        expect(factoryCalls, lessThanOrEqualTo(edgeCount),
            reason: 'paths were recomputed across frames');
        expect(cache.hitRate, greaterThan(95),
            reason: 'cache hit rate should be near 100% on stable positions');

        // ignore: avoid_print
        print('edges=$edgeCount  factoryCalls=$factoryCalls  '
            'hitRate=${cache.hitRate}%  cacheSize=${cache.size}');
      });
    }
  });
}

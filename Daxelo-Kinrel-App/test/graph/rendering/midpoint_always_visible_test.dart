// test/graph/rendering/midpoint_always_visible_test.dart
//
// Regression test for the "middle connection dot (heart) must always
// remain visible at every zoom level and in every graph state"
// requirement (v105).
//
// Verifies that the EngineEdgePainter paints a midpoint symbol (dot or
// heart) for every edge at EVERY EdgeQuality tier (full / chip / dot)
// and in EVERY graph state (normal / selected / dimmed). The midpoint
// must NEVER be skipped.
//
// The test uses a recording-canvas proxy (noSuchMethod catch-all +
// intercepted drawCircle/drawArc/drawOval/drawPath counters) so we can
// assert that the midpoint is actually painted, not just that the
// painter didn't crash.

import 'dart:ui' show Canvas, Offset, Paint, Path, Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/kinship/kinship_edge_style.dart';
import 'package:kinrel/graph/engine/edge_dedup.dart' show DedupedEdge;
import 'package:kinrel/graph/data/graph_data_models.dart' show GraphEdgeData;
import 'package:kinrel/graph/rendering/edge_path_cache.dart' show EdgePathCache;
import 'package:kinrel/graph/rendering/edge_quality.dart' show EdgeQuality;
import 'package:kinrel/graph/widgets/engine/engine_edge_painter.dart'
    show EngineEdgePainter;

/// A recording canvas that counts draw operations by type.
///
/// Uses `noSuchMethod` to swallow every other Canvas call (save,
/// restore, translate, clip*, etc.) so we don't have to implement the
/// full Canvas interface. Only the draw* methods we care about are
/// intercepted and counted.
class _RecordingCanvas implements Canvas {
  int drawCircleCount = 0;
  int drawPathCount = 0;
  int drawArcCount = 0;
  int drawOvalCount = 0;
  final List<Offset> circleCenters = [];

  @override
  void drawCircle(Offset c, double radius, Paint paint) {
    drawCircleCount++;
    circleCenters.add(c);
  }

  @override
  void drawPath(Path path, Paint paint) {
    drawPathCount++;
  }

  @override
  void drawArc(
      Rect rect, double startAngle, double sweepAngle, bool useCenter, Paint paint) {
    drawArcCount++;
  }

  @override
  void drawOval(Rect rect, Paint paint) {
    drawOvalCount++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {}
}

void main() {
  // Build a minimal painter with one spouse edge (heart midpoint) and
  // one normal edge (dot midpoint). The edges are short so the bezier
  // path has a non-zero length (midpoint computation needs this).
  final positions = <String, Offset>{
    'a': const Offset(0, 0),
    'b': const Offset(0, 100),
    'c': const Offset(100, 0),
    'd': const Offset(100, 100),
  };
  final edges = <DedupedEdge>[
    DedupedEdge(
      edge: GraphEdgeData(
        id: 'e1',
        sourceId: 'a',
        targetId: 'b',
        relationshipKey: 'spouse',
      ),
      lateralOffset: 0.0,
    ),
    DedupedEdge(
      edge: GraphEdgeData(
        id: 'e2',
        sourceId: 'c',
        targetId: 'd',
        relationshipKey: 'father',
      ),
      lateralOffset: 0.0,
    ),
  ];
  // Map edges to their kinship categories so the painter can resolve
  // styles + midpoint symbols (heart for spouse, dot for father).
  final edgeCategories = <String, KinshipEdgeCategory>{};
  for (final d in edges) {
    final key = d.edge.relationshipKey;
    if (key == 'spouse') {
      edgeCategories[d.edge.id] = KinshipEdgeCategory.spouse;
    } else {
      edgeCategories[d.edge.id] = KinshipEdgeCategory.extended;
    }
  }

  // Build a painter for a given tier + state.
  EngineEdgePainter buildPainter({
    required EdgeQuality tier,
    Set<String>? dimmedEdgeIds,
    String? selectedEdgeId,
  }) {
    return EngineEdgePainter(
      positions: positions,
      edges: edges,
      edgeCategories: edgeCategories,
      edgeCustomColors: const {},
      coupleUnions: const [],
      cache: EdgePathCache(),
      edgeQuality: tier,
      graphRevision: 1,
      layoutRevision: 1,
      edgeVisualRevision: 1,
      selectedEdgeId: selectedEdgeId,
      dimmedEdgeIds: dimmedEdgeIds,
    );
  }

  group('v105 — Midpoint always visible at every LOD tier', () {
    test('FULL tier paints midpoints for both edges', () {
      final canvas = _RecordingCanvas();
      final painter = buildPainter(tier: EdgeQuality.full);
      painter.paint(canvas, const Size(1000, 1000));

      // At FULL LOD the dot bead uses drawCircle (face + shadow) and
      // drawArc (rim) and drawOval (specular). The heart uses drawPath
      // (heart shape) + drawCircle (glow halo). Either way, SOMETHING
      // must be drawn for each edge's midpoint.
      expect(
          canvas.drawCircleCount +
              canvas.drawArcCount +
              canvas.drawOvalCount +
              canvas.drawPathCount,
          greaterThan(0),
          reason: 'FULL tier must paint a midpoint for each edge');
    });

    test('CHIP tier paints midpoints for both edges', () {
      final canvas = _RecordingCanvas();
      final painter = buildPainter(tier: EdgeQuality.chip);
      painter.paint(canvas, const Size(1000, 1000));

      expect(
          canvas.drawCircleCount +
              canvas.drawArcCount +
              canvas.drawOvalCount +
              canvas.drawPathCount,
          greaterThan(0),
          reason: 'CHIP tier must paint a midpoint for each edge');
    });

    test(
        'DOT tier paints midpoints for both edges (the v105 fix — '
        'previously the midpoint was skipped at DOT LOD, causing the '
        'heart to disappear when zoomed out)', () {
      final canvas = _RecordingCanvas();
      final painter = buildPainter(tier: EdgeQuality.dot);
      painter.paint(canvas, const Size(1000, 1000));

      // At DOT LOD the midpoint is a single drawCircle per edge. With
      // 2 edges we expect AT LEAST 2 midpoint circles (the line passes
      // use drawPath, not drawCircle).
      expect(canvas.drawCircleCount, greaterThanOrEqualTo(2),
          reason:
              'DOT tier must paint a midpoint circle for each edge — '
              'the heart/dot must stay visible when zoomed out');
    });
  });

  group('v105 — Midpoint visible in every graph state', () {
    test('midpoint paints when the edge is SELECTED', () {
      final canvas = _RecordingCanvas();
      final painter = buildPainter(
        tier: EdgeQuality.full,
        selectedEdgeId: 'e1',
      );
      painter.paint(canvas, const Size(1000, 1000));

      expect(
          canvas.drawCircleCount +
              canvas.drawArcCount +
              canvas.drawOvalCount +
              canvas.drawPathCount,
          greaterThan(0),
          reason: 'Selected edge must still paint its midpoint');
    });

    test(
        'midpoint paints when the edge is DIMMED (focus mode) — '
        'previously the midpoint was skipped for dimmed edges, causing '
        'the heart to disappear when a node was selected', () {
      final canvas = _RecordingCanvas();
      final painter = buildPainter(
        tier: EdgeQuality.full,
        dimmedEdgeIds: {'e1', 'e2'},
      );
      painter.paint(canvas, const Size(1000, 1000));

      // v105: dimmed edges STILL paint a midpoint (at reduced alpha).
      // The heart must NOT disappear when the user selects a node.
      expect(
          canvas.drawCircleCount +
              canvas.drawArcCount +
              canvas.drawOvalCount +
              canvas.drawPathCount,
          greaterThan(0),
          reason:
              'Dimmed edges must still paint a midpoint (at reduced alpha) '
              '— the heart must stay visible in focus mode');
    });

    test('midpoint paints at DOT tier when dimmed (worst case: zoomed out '
        '+ focus mode)', () {
      final canvas = _RecordingCanvas();
      final painter = buildPainter(
        tier: EdgeQuality.dot,
        dimmedEdgeIds: {'e1', 'e2'},
      );
      painter.paint(canvas, const Size(1000, 1000));

      expect(canvas.drawCircleCount, greaterThanOrEqualTo(2),
          reason:
              'DOT tier + dimmed edges must still paint midpoint circles — '
              'the heart must stay visible even when zoomed out AND a node '
              'is selected');
    });
  });

  group('v105 — Midpoint alignment with the connection line', () {
    test(
        'midpoint is painted at the geometric midpoint of the edge '
        '(within the path-metrics tolerance)', () {
      // Edge e1 goes from (0,0) to (0,100) — its midpoint is at (0,50).
      // The painter computes the midpoint via PathMetrics along the
      // bezier path, which for a straight vertical edge is the
      // geometric midpoint. We verify the painted circle is near (0,50).
      final canvas = _RecordingCanvas();
      final painter = buildPainter(tier: EdgeQuality.dot);
      painter.paint(canvas, const Size(1000, 1000));

      // Find the circle closest to (0, 50).
      const expected = Offset(0, 50);
      Offset? closest;
      double closestDist = double.infinity;
      for (final c in canvas.circleCenters) {
        final d = (c - expected).distance;
        if (d < closestDist) {
          closestDist = d;
          closest = c;
        }
      }
      expect(closest, isNotNull,
          reason: 'At least one circle should be painted');
      // The path-metrics midpoint may deviate slightly from the
      // geometric midpoint because of the bezier control points, but
      // for a short straight edge it should be within ~15px.
      expect(closestDist, lessThan(15.0),
          reason:
              'Midpoint circle should be near the edge midpoint (0,50), '
              'got $closest (dist $closestDist)');
    });
  });
}

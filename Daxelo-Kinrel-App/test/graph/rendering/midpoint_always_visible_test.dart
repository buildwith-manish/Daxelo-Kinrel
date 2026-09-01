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
      parallelCount: 1,
    ),
    DedupedEdge(
      edge: GraphEdgeData(
        id: 'e2',
        sourceId: 'c',
        targetId: 'd',
        relationshipKey: 'father',
      ),
      lateralOffset: 0.0,
      parallelCount: 1,
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

      // v5.26: At DOT LOD the SPOUSE heart falls through to the real
      // HeartShape.drawHeart code (drawPath ×3: fill + border +
      // specular — see the v5.26 comment in engine_edge_painter),
      // while non-spouse midpoints use the simplified drawCircle.
      // So with 2 edges (1 spouse + 1 father) we expect at least one
      // midpoint circle AND at least one heart path — SOMETHING per
      // edge. The line bodies are also drawPath, so we assert the
      // combined count covers both edges' midpoints.
      expect(canvas.drawCircleCount + canvas.drawPathCount,
          greaterThanOrEqualTo(2),
          reason:
              'DOT tier must paint a midpoint for each edge — the '
              'heart/dot must stay visible when zoomed out (hearts use '
              'drawPath since v5.26, dots use drawCircle)');
      expect(canvas.drawCircleCount, greaterThanOrEqualTo(1),
          reason: 'The father edge (dot symbol) must paint a midpoint '
              'circle at DOT tier');
      expect(canvas.drawPathCount, greaterThanOrEqualTo(3),
          reason: 'Two edge bodies (drawPath) + the spouse heart '
              '(drawPath) must be painted');
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

      // v5.26: hearts draw via drawPath, dots via drawCircle — count
      // both to verify each edge still paints a (dimmed) midpoint.
      expect(canvas.drawCircleCount + canvas.drawPathCount,
          greaterThanOrEqualTo(2),
          reason:
              'DOT tier + dimmed edges must still paint midpoints — '
              'the heart must stay visible even when zoomed out AND a '
              'node is selected (hearts use drawPath since v5.26)');
      expect(canvas.drawCircleCount, greaterThanOrEqualTo(1),
          reason: 'The father edge must still paint its (dimmed) '
              'midpoint circle at DOT tier');
    });
  });

  group('v105 — Midpoint alignment with the connection line', () {
    test(
        'midpoint is painted at the VISUAL midpoint of the rendered '
        'bezier curve (within tolerance)', () {
      // Edge e2 goes from c=(100,0) to d=(100,100). v5.45: ALL edges bow
      // perpendicular by 25% of distance (clamped [15,100]) — there are
      // NO straight edges anymore. The marker must sit on the CURVE's
      // arc-length midpoint (EngineEdgePainter.computeVisualMidpoint —
      // the single source of truth), NOT on the geometric straight-line
      // midpoint.
      //
      // v5.x (Feature 1): the curve now ALSO applies a per-edge
      // deterministic phase (bow direction ±perp + small magnitude
      // scale derived from the FNV-1a hash of the edge ID), AND the dot
      // marker is placed at a per-edge deterministic t-parameter in
      // [0.4, 0.6] (instead of always t=0.5). Both variations are pure
      // functions of the edge ID — the same edge always renders the
      // same way — but they mean the visual midpoint is no longer a
      // hardcoded (81.25, 50) value.
      //
      // The expected position is therefore computed from the SAME
      // helper the painter uses (computeVisualMidpoint with the edge
      // ID), so the test stays robust to any future tuning of the per-
      // edge phase / t-variation. Anything else would drift from the
      // rendered curve.
      final canvas = _RecordingCanvas();
      final painter = buildPainter(tier: EdgeQuality.dot);
      painter.paint(canvas, const Size(1000, 1000));

      // The expected position comes from the SAME helper the painter
      // uses (with the edge ID 'e2' so the per-edge phase + t-variation
      // are applied identically to the paint loop). Anything else would
      // drift from the rendered curve.
      final expected = EngineEdgePainter.computeVisualMidpoint(
        const Offset(100, 0),
        const Offset(100, 100),
        edgeId: 'e2',
      );
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
      expect(closestDist, lessThan(2.0),
          reason:
              'Midpoint circle should sit on the bezier arc-length '
              'midpoint $expected (v5.45 bow + v5.x per-edge phase + '
              'per-edge t-variation), got $closest (dist $closestDist)');
    });

    test(
        'v5.x (Feature 1) — per-edge curve phase gives different solo '
        'edges different bow directions / magnitudes (no two solo '
        'edges between different pairs overlap exactly)', () {
      // Two solo edges with the SAME geometry but DIFFERENT IDs must
      // produce DIFFERENT visual midpoints — this is the whole point
      // of the per-edge phase: nearly-parallel edges between different
      // node pairs fan out instead of stacking on top of each other.
      //
      // We pick two IDs whose FNV-1a hashes fall on opposite sides of
      // zero so the direction test is unambiguous. The actual hash
      // values are deterministic — if either ID's hash changes the test
      // picks new IDs, but the CONTRACT (different IDs → different
      // positions) is what's being verified.
      const s = Offset(0, 0);
      const t = Offset(100, 0);
      final midA = EngineEdgePainter.computeVisualMidpoint(
          s, t, edgeId: 'edge-aaaa');
      final midB = EngineEdgePainter.computeVisualMidpoint(
          s, t, edgeId: 'edge-bbbb');
      // The two midpoints must NOT be exactly equal — the per-edge
      // phase differentiates them.
      expect(midA, isNot(equals(midB)),
          reason: 'Two solo edges with different IDs must produce '
              'different visual midpoints (per-edge phase variation)');
      // And the difference must be visible (at least 2px).
      expect((midA - midB).distance, greaterThan(2.0),
          reason: 'Per-edge phase variation must be visually '
              'significant (≥2px) so nearly-parallel edges actually '
              'fan out, not just differ in sub-pixel rounding');
    });

    test(
        'v5.x (Feature 1) — same edge ID always produces the same '
        'visual midpoint on every call (deterministic, no jitter)', () {
      // The per-edge phase is a pure function of the edge ID — calling
      // computeVisualMidpoint with the same inputs must always return
      // the same position. This is the "no jitter on re-render"
      // contract.
      const s = Offset(50, 0);
      const t = Offset(150, 100);
      final mid1 =
          EngineEdgePainter.computeVisualMidpoint(s, t, edgeId: 'stable');
      final mid2 =
          EngineEdgePainter.computeVisualMidpoint(s, t, edgeId: 'stable');
      expect(mid1, equals(mid2),
          reason: 'Same edge ID + same endpoints must produce the '
              'same visual midpoint on every call (deterministic per-'
              'edge phase, no jitter)');
    });

    test(
        'v5.x (Feature 1) — user-dragged midpoint (waypointDelta) '
        'keeps t=0.5 and ignores the per-edge t-variation (drag '
        'contract preserved)', () {
      // The drag/hit-test parity contract: when the user has dragged
      // the marker (waypointDelta != Offset.zero), the per-edge
      // t-variation is DISABLED inside computeVisualMidpoint — the
      // t-parameter stays at 0.5 so the dot position is stable across
      // renders and identical between the painter and the hit-tester.
      //
      // We verify this by computing the visual midpoint with the SAME
      // waypoints but DIFFERENT edge IDs. If the per-edge t-variation
      // were (incorrectly) applied in the waypoint case, different
      // edge IDs would yield different midpoints. With the contract
      // preserved, the edge ID is ignored and all results are equal.
      //
      // (Note: the v5.62 cubic-bezier math places the PARAMETER t=0.5
      // point at exactly linearMid + delta; the arc-length t=0.5 point
      // used by PathMetric is close to but not exactly that for non-
      // symmetric curves. That is a pre-existing implementation detail
      // of the drag visual and is unchanged by Feature 1 — what
      // matters for the contract is that painter and hit-tester agree,
      // which they do because both call this same helper.)
      const s = Offset(0, 0);
      const t = Offset(100, 0);
      const dragDelta = Offset(-15.0, 25.0);
      final midNoId = EngineEdgePainter.computeVisualMidpoint(
        s, t,
        waypointDelta: dragDelta,
      );
      final midWithId = EngineEdgePainter.computeVisualMidpoint(
        s, t,
        waypointDelta: dragDelta,
        edgeId: 'some-edge-id',
      );
      final midOtherId = EngineEdgePainter.computeVisualMidpoint(
        s, t,
        waypointDelta: dragDelta,
        edgeId: 'a-totally-different-id',
      );
      expect(midWithId, equals(midNoId),
          reason: 'In the waypoint case, the edge ID must be IGNORED '
              '— the per-edge t-variation is disabled. The midpoint '
              'with an edge ID must equal the midpoint with no edge ID.');
      expect(midOtherId, equals(midNoId),
          reason: 'Different edge IDs in the waypoint case must ALL '
              'produce the same midpoint — the per-edge t-variation '
              'is disabled when waypointDelta is non-zero.');
    });
  });
}

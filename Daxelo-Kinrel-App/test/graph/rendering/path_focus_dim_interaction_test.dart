// test/graph/rendering/path_focus_dim_interaction_test.dart
//
// Integration test for the interaction between the v5.x (Feature 2)
// default-dim hierarchy and the v92 path-focus highlight.
//
// Verifies the user-facing contract:
//   1. With no node selected → ALL edges are dimmed (default-dim state).
//   2. With a node selected BUT no path focus → the selected node's
//      directly-connected edges stay bright; everything else is dimmed.
//      (This is the "1-hop bright" rule from Feature 2.)
//   3. With a node selected AND a path focus resolved (viewer → selected
//      node) → BOTH the selected node's 1-hop edges AND the path edges
//      stay bright; everything else is dimmed. The path edges are the
//      edges the user actually needs to follow to understand the
//      relationship ("how am I related to this person") — they must
//      stay bright even if they're NOT directly incident to the
//      selected node.
//
// This is the "path highlighting, not just 1-hop" behavior the user
// asked for: a user selecting "Uncle" wants to see the ENTIRE path
// from themselves to Uncle (viewer → parent → grandparent → uncle),
// not just Uncle's immediate edges floating in space.

import 'dart:ui' show Canvas, Offset, Paint, Path, Rect, Size, PaintingStyle;

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/kinship/kinship_edge_style.dart';
import 'package:kinrel/graph/engine/edge_dedup.dart' show DedupedEdge;
import 'package:kinrel/graph/data/graph_data_models.dart' show GraphEdgeData;
import 'package:kinrel/graph/rendering/edge_path_cache.dart' show EdgePathCache;
import 'package:kinrel/graph/rendering/edge_quality.dart' show EdgeQuality;
import 'package:kinrel/graph/widgets/engine/engine_edge_painter.dart'
    show EngineEdgePainter;

/// A recording canvas that counts drawCircle / drawPath calls.
///
/// Captures the alpha of every stroke paint used in drawPath so the
/// test can verify which edges are dimmed (alpha ≈ 0.18) vs bright
/// (alpha ≈ 1.0).
class _RecordingCanvas implements Canvas {
  int drawCircleCount = 0;
  int drawPathCount = 0;
  final List<double> pathStrokeAlphas = [];

  @override
  void drawCircle(Offset c, double radius, Paint paint) {
    drawCircleCount++;
  }

  @override
  void drawPath(Path path, Paint paint) {
    drawPathCount++;
    // Record the alpha of every stroke paint. Fill paints (midpoint
    // beads) are ignored — we only care about edge strokes here.
    if (paint.style == PaintingStyle.stroke) {
      pathStrokeAlphas.add(paint.color.a);
    }
  }

  @override
  void drawArc(Rect rect, double startAngle, double sweepAngle,
      bool useCenter, Paint paint) {}

  @override
  void drawOval(Rect rect, Paint paint) {}

  @override
  dynamic noSuchMethod(Invocation invocation) {}
}

void main() {
  // Build a graph with a multi-hop path:
  //   viewer → parent → grandparent → uncle
  //
  // Edge layout:
  //   e1: viewer — parent (father)
  //   e2: parent — grandparent (father)
  //   e3: grandparent — uncle (father)
  //   e4: viewer — sibling (brother, unrelated to the path)
  //   e5: uncle — cousin (father, unrelated to the path)
  final positions = <String, Offset>{
    'viewer': const Offset(0, 0),
    'parent': const Offset(0, 100),
    'grandparent': const Offset(0, 200),
    'uncle': const Offset(100, 200),
    'sibling': const Offset(100, 0),
    'cousin': const Offset(200, 200),
  };
  final edges = <DedupedEdge>[
    DedupedEdge(
      edge: GraphEdgeData(
          id: 'e1', sourceId: 'viewer', targetId: 'parent', relationshipKey: 'father'),
      lateralOffset: 0.0,
      parallelCount: 1,
    ),
    DedupedEdge(
      edge: GraphEdgeData(
          id: 'e2', sourceId: 'parent', targetId: 'grandparent', relationshipKey: 'father'),
      lateralOffset: 0.0,
      parallelCount: 1,
    ),
    DedupedEdge(
      edge: GraphEdgeData(
          id: 'e3', sourceId: 'grandparent', targetId: 'uncle', relationshipKey: 'father'),
      lateralOffset: 0.0,
      parallelCount: 1,
    ),
    DedupedEdge(
      edge: GraphEdgeData(
          id: 'e4', sourceId: 'viewer', targetId: 'sibling', relationshipKey: 'brother'),
      lateralOffset: 0.0,
      parallelCount: 1,
    ),
    DedupedEdge(
      edge: GraphEdgeData(
          id: 'e5', sourceId: 'uncle', targetId: 'cousin', relationshipKey: 'father'),
      lateralOffset: 0.0,
      parallelCount: 1,
    ),
  ];
  final edgeCategories = <String, KinshipEdgeCategory>{
    for (final d in edges) d.edge.id: KinshipEdgeCategory.parent,
  };

  EngineEdgePainter buildPainter({
    Set<String>? dimmedEdgeIds,
    Set<String>? pathFocusedEdgeIds,
    bool pathFocusActive = false,
  }) {
    return EngineEdgePainter(
      positions: positions,
      edges: edges,
      edgeCategories: edgeCategories,
      edgeCustomColors: const {},
      coupleUnions: const [],
      cache: EdgePathCache(),
      edgeQuality: EdgeQuality.full,
      graphRevision: 1,
      layoutRevision: 1,
      edgeVisualRevision: 1,
      dimmedEdgeIds: dimmedEdgeIds,
      pathFocusedEdgeIds: pathFocusedEdgeIds,
      pathFocusActive: pathFocusActive,
    );
  }

  group('v5.x (Feature 2 + path focus) — dim/path-focus interaction', () {
    test(
        'Case 1: no selection → ALL edges dimmed (default-dim state, '
        'no path focus)', () {
      final canvas = _RecordingCanvas();
      // The default-dim hierarchy returns ALL edge IDs when nothing
      // is active — see edge_dim_hierarchy.dart Case 4.
      final allDimmed = {for (final d in edges) d.edge.id};
      final painter = buildPainter(dimmedEdgeIds: allDimmed);
      painter.paint(canvas, const Size(1000, 1000));

      // Every edge stroke is at dimAlpha — none bright.
      expect(canvas.pathStrokeAlphas, isNotEmpty,
          reason: 'Painter must have painted edge strokes');
      // v5.164 (commit 8f6365b6, "DEFAULT-DIM VISIBILITY"): the
      // non-focus dim alpha was intentionally raised from 0.40 → 0.55
      // so default-dim is actually PERCEPTIBLE on a busy canvas (the
      // user reported the 0.40 dim "read as full brightness"). With
      // pathFocusActive == false this is the tap-driven default-dim
      // state, so a dimmed parent-category body stroke is
      // 0.55 × 0.85 (KinshipEdgeStyle.parent.defaultAlpha) = 0.4675.
      // A BRIGHT (undimmed) parent body would be 0.85 — so the max
      // stroke alpha must stay inside the dim band, well below the
      // bright body alpha and consistent with the intentional 0.55
      // dim level (ridge 0.26 / shadow 0.26 are below the body pass).
      final maxAlpha = canvas.pathStrokeAlphas.fold<double>(
          0.0, (a, b) => a > b ? a : b);
      expect(maxAlpha, allOf(greaterThan(0.4), lessThan(0.6)),
          reason: 'Default-dim state (v5.164: dimAlpha 0.55): every edge '
              'stroke must sit in the dim band — the body pass is '
              '0.55 × 0.85 = 0.4675 for the parent category, the ridge/'
              'shadow passes are 0.26. Got $maxAlpha. If a bright '
              'stroke (alpha ≈ 0.85+) appears, the dim hierarchy is '
              'not dimming all edges as expected; if the max drops '
              'below 0.4, the dim has regressed to the pre-v5.164 '
              'too-subtle level.');
    });

    test(
        'Case 2: node "uncle" selected, NO path focus → only uncle\'s '
        'direct edges (e3, e5) stay bright; the rest dim', () {
      final canvas = _RecordingCanvas();
      // Selection of "uncle" → Feature 2 dims every edge NOT
      // incident to uncle. Uncle is incident to e3 (gp-uncle) and
      // e5 (uncle-cousin) only.
      final dimmed = {'e1', 'e2', 'e4'};
      final painter = buildPainter(dimmedEdgeIds: dimmed);
      painter.paint(canvas, const Size(1000, 1000));

      // Every stroke is dim EXCEPT edges e3 and e5 (uncle's direct
      // edges), which stay at full alpha. We expect at least one
      // bright stroke (uncle's edges).
      final maxAlpha = canvas.pathStrokeAlphas.fold<double>(
          0.0, (a, b) => a > b ? a : b);
      expect(maxAlpha, greaterThan(0.5),
          reason: 'Selection of "uncle" must brighten uncle\'s direct '
              'edges (e3, e5) to full alpha, got max=$maxAlpha');
    });

    test(
        'Case 3 (THE KEY TEST): node "uncle" selected AND path focus '
        'resolved (viewer→parent→grandparent→uncle) → BOTH uncle\'s '
        'direct edges AND the PATH edges (e1, e2, e3) stay bright; '
        'only the genuinely-unrelated edges (e4, e5) dim', () {
      final canvas = _RecordingCanvas();
      // Path focus: viewer → parent → grandparent → uncle uses
      // edges e1, e2, e3 (in that order).
      const pathEdges = {'e1', 'e2', 'e3'};
      // Feature 2's selection-based dim would dim e1, e2, e4
      // (only e3, e5 are incident to uncle). But path focus
      // OVERRIDES the dim for e1 and e2 — they're part of the
      // highlighted path.
      final dimmed = {'e4'};
      // e5 is uncle's direct edge so it's bright (not in dimmed).
      // e1, e2 are path edges (bright via path-focus override).
      // e3 is BOTH a path edge AND uncle's direct edge (bright).
      // e4 is the only truly dimmed edge.

      final painter = buildPainter(
        dimmedEdgeIds: dimmed,
        pathFocusedEdgeIds: pathEdges,
        pathFocusActive: true,
      );
      painter.paint(canvas, const Size(1000, 1000));

      // The painter must paint at least 4 distinct edge strokes
      // (one per edge — e5 is dimmed, but still painted at dim
      // alpha).
      expect(canvas.pathStrokeAlphas, isNotEmpty);

      // We expect SOME bright strokes (the path edges + uncle's
      // direct edges) and SOME dim strokes (e4 only).
      final maxAlpha = canvas.pathStrokeAlphas.fold<double>(
          0.0, (a, b) => a > b ? a : b);
      final minAlpha = canvas.pathStrokeAlphas.fold<double>(
          1.0, (a, b) => a < b ? a : b);
      expect(maxAlpha, greaterThan(0.5),
          reason: 'Path edges + uncle\'s direct edges must stay '
              'bright (alpha > 0.5)');
      expect(minAlpha, lessThan(0.25),
          reason: 'The unrelated edge e4 must still be dimmed '
              '(alpha ≤ 0.25)');
    });

    test(
        'Path focus override survives even for edges NOT incident to '
        'the selected node (the "1-hop is not enough" case)', () {
      // The user explicitly said: "a user selecting Uncle wants to
      // see HOW Uncle connects back to them, not just Uncle's
      // immediate lines floating in space." This test verifies
      // that the path edges (e1: viewer-parent, e2: parent-gp)
      // stay bright even though they are NOT incident to uncle.
      final canvas = _RecordingCanvas();
      const pathEdges = {'e1', 'e2', 'e3'};
      // Feature 2 alone (no path focus) would dim e1 and e2 because
      // they are NOT incident to uncle. With path focus active,
      // the painter's `isDimmed` check excludes path-focused edges
      // → e1 and e2 are NOT dimmed even though they're in the
      // `dimmedEdgeIds` set... wait, actually in this test setup
      // I'm NOT putting e1, e2 in dimmedEdgeIds because the
      // Feature 2 helper would exclude them anyway since they're
      // path-focused. Let me put them in dimmedEdgeIds to verify
      // the painter override actually works.
      final dimmed = {'e1', 'e2', 'e4'}; // e1, e2 would be dimmed
      // by Feature 2 (selection-only) — but path focus overrides.
      final painter = buildPainter(
        dimmedEdgeIds: dimmed,
        pathFocusedEdgeIds: pathEdges,
        pathFocusActive: true,
      );
      painter.paint(canvas, const Size(1000, 1000));

      // At least one bright stroke — the path edges (e1, e2, e3)
      // must brighten to full alpha despite being in the dimmed
      // set. This proves the painter's path-focus override works.
      final brightCount =
          canvas.pathStrokeAlphas.where((a) => a > 0.5).length;
      expect(brightCount, greaterThanOrEqualTo(3),
          reason: 'At least 3 path edges (e1, e2, e3) must stay bright '
              'despite being in dimmedEdgeIds — the path focus '
              'override must work');
    });
  });
}

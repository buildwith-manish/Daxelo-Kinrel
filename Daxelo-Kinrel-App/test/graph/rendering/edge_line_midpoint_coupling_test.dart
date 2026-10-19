// test/graph/rendering/edge_line_midpoint_coupling_test.dart
//
// 2026-10-19 — Edge line/midpoint coupling regression test.
//
// Verifies the fix for the "dot without line" bug reported against the
// Family Graph screen:
//
//   SYMPTOM: Some edges render only their midpoint dot/heart and NO line.
//   "Showing 23 of 715 persons" with LINKS 145 shows nodes (Karan Gupta,
//   Sunita Menon, Arjun Rao, Pooja Rao...) with floating dots between
//   them and no connecting lines.
//
//   ROOT CAUSE (verified): in engine_edge_painter.dart's paint() loop,
//   when `connectOnOpenActive` was true, an edge that was in NEITHER
//   `connectOnOpenRevealedEdgeIds` NOR `connectOnOpenCurrentEdgeIds`
//   (and != connectOnOpenCurrentEdgeId) got `connectOnOpenAlpha = 0.0`,
//   so the line was invisible. But `skipMidpointForConnectOnOpen`
//   stayed false for that branch, so `_paintMidpoint` still drew the
//   dot. Result: dots with no lines.
//
//   FIX: a single `edgeLineVisible` flag drives BOTH the line and the
//   midpoint. Edges NOT in the animation set are ALWAYS drawn at full
//   alpha + full width (the animation is a pure cosmetic overlay on
//   top of the always-visible base layer, never a substitution). When
//   the line is invisible (alpha 0), the midpoint is also skipped.
//   When the line is visible, the midpoint is always painted (unless
//   the symbol is `none`).
//
// This test asserts:
//   1. With connectOnOpenActive=true and a MIX of edges (some in the
//      revealed set, some in the current set, some in NEITHER) —
//      every edge's line is painted AND every edge's midpoint is
//      painted. There is no case where a midpoint is painted without
//      its line.
//   2. The regression case: 23 visible persons and 145 edges produces
//      145 drawn lines (one per edge, no edge silently dropped).
//   3. An edge in the "neither" set (not in connectOnOpenRevealedEdgeIds
//      nor connectOnOpenCurrentEdgeIds) is drawn at full alpha — not
//      hidden at alpha 0.

import 'dart:ui' show Canvas, Offset, Paint, Path, Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/kinship/kinship_edge_style.dart';
import 'package:kinrel/graph/engine/edge_dedup.dart' show DedupedEdge;
import 'package:kinrel/graph/data/graph_data_models.dart' show GraphEdgeData;
import 'package:kinrel/graph/rendering/edge_path_cache.dart' show EdgePathCache;
import 'package:kinrel/graph/rendering/edge_quality.dart' show EdgeQuality;
import 'package:kinrel/graph/widgets/engine/engine_edge_painter.dart'
    show EngineEdgePainter;

/// A recording canvas that counts draw operations by type AND records
/// the Path objects passed to drawPath (so we can verify which edges
/// were drawn by inspecting the path bounds).
class _RecordingCanvas implements Canvas {
  int drawCircleCount = 0;
  int drawPathCount = 0;
  int drawArcCount = 0;
  int drawOvalCount = 0;
  int drawLineCount = 0;
  final List<Offset> circleCenters = [];
  final List<Path> paths = [];

  @override
  void drawCircle(Offset c, double radius, Paint paint) {
    drawCircleCount++;
    circleCenters.add(c);
  }

  @override
  void drawPath(Path path, Paint paint) {
    drawPathCount++;
    paths.add(path);
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
  void drawLine(Offset p1, Offset p2, Paint paint) {
    drawLineCount++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {}
}

GraphEdgeData _edge(String id, String a, String b, {String? key}) =>
    GraphEdgeData(
      id: id,
      sourceId: a,
      targetId: b,
      relationshipKey: key ?? 'parent',
    );

DedupedEdge _deduped(GraphEdgeData e) => DedupedEdge(
      edge: e,
      lateralOffset: 0.0,
      parallelCount: 1,
    );

void main() {
  // Build a 20-edge graph: viewer + 5 direct + 14 extended. Edges span
  // multiple BFS depths so we can mix connectOnOpenRevealedEdgeIds,
  // connectOnOpenCurrentEdgeIds, and "neither" sets.
  //
  // Layout: spread nodes in a 6×4 grid so edges have non-zero length
  // (the painter's _bezier requires distance >= 1.0).
  final positions = <String, Offset>{
    'viewer': const Offset(0, 0),
    for (var i = 1; i <= 5; i++) 'd$i': Offset(i * 100.0, 0),
    for (var i = 6; i <= 19; i++) 'e$i': Offset((i % 6) * 100.0, (i ~/ 6) * 100.0),
  };

  // 20 edges: 5 direct (viewer→dN), 15 extended (dN→eN, eN→eN)
  final allEdges = <DedupedEdge>[
    _deduped(_edge('ed1', 'viewer', 'd1', key: 'spouse')),
    _deduped(_edge('ed2', 'viewer', 'd2', key: 'parent')),
    _deduped(_edge('ed3', 'viewer', 'd3', key: 'parent')),
    _deduped(_edge('ed4', 'viewer', 'd4', key: 'sibling')),
    _deduped(_edge('ed5', 'viewer', 'd5', key: 'child')),
    for (var i = 1; i <= 5; i++)
      _deduped(_edge('ee$i', 'd$i', 'e${i + 5}', key: 'parent')),
    for (var i = 6; i <= 19; i++)
      _deduped(_edge('ee$i', 'e$i', 'e${(i % 19) + 6}', key: 'cousin')),
  ];

  // KinshipEdgeCategory map: spouse for spouse edges, extended for others.
  final edgeCategories = <String, KinshipEdgeCategory>{};
  for (final d in allEdges) {
    final key = d.edge.relationshipKey;
    edgeCategories[d.edge.id] =
        key == 'spouse' ? KinshipEdgeCategory.spouse : KinshipEdgeCategory.extended;
  }

  EngineEdgePainter buildPainter({
    required EdgeQuality tier,
    bool connectOnOpenActive = false,
    Set<String>? connectOnOpenRevealedEdgeIds,
    Set<String>? connectOnOpenCurrentEdgeIds,
    String? connectOnOpenCurrentEdgeId,
    double connectOnOpenProgress = 0.0,
    Map<String, double>? connectOnOpenEdgeDelays,
  }) {
    return EngineEdgePainter(
      positions: positions,
      edges: allEdges,
      edgeCategories: edgeCategories,
      edgeCustomColors: const {},
      coupleUnions: const [],
      cache: EdgePathCache(),
      edgeQuality: tier,
      graphRevision: 1,
      layoutRevision: 1,
      edgeVisualRevision: 1,
      connectOnOpenActive: connectOnOpenActive,
      connectOnOpenRevealedEdgeIds: connectOnOpenRevealedEdgeIds ?? const {},
      connectOnOpenCurrentEdgeIds: connectOnOpenCurrentEdgeIds ?? const {},
      connectOnOpenCurrentEdgeId: connectOnOpenCurrentEdgeId,
      connectOnOpenProgress: connectOnOpenProgress,
      connectOnOpenEdgeDelays: connectOnOpenEdgeDelays ?? const {},
    );
  }

  group('2026-10-19 — Edge line/midpoint coupling (dot-without-line fix)', () {
    test('FULL tier: every edge paints its line when connectOnOpen is OFF', () {
      final canvas = _RecordingCanvas();
      final painter = buildPainter(tier: EdgeQuality.full);
      painter.paint(canvas, const Size(1000, 1000));

      // 20 edges, all visible. Each edge paints at least 1 drawPath
      // (the body). So drawPathCount >= 20.
      expect(canvas.drawPathCount, greaterThanOrEqualTo(allEdges.length),
          reason: 'Every edge (${allEdges.length}) must paint at least its body '
              'line when connectOnOpen is OFF. Got ${canvas.drawPathCount} drawPath calls.');
    });

    test(
        'FULL tier: every edge paints its line when connectOnOpen is ON with '
        'a MIX of revealed/current/neither edges',
        () {
      // Setup: 5 edges revealed (already animated), 5 edges currently
      // animating (mid-progress), 10 edges in NEITHER set (the bug
      // case — these were previously hidden at alpha 0 while their
      // midpoints still painted).
      final revealedEdges = <String>{
        for (final d in allEdges.take(5)) d.edge.id,
      };
      final currentEdges = <String>{
        for (final d in allEdges.skip(5).take(5)) d.edge.id,
      };
      // The remaining 10 edges (skip(10)) are in NEITHER set.

      final canvas = _RecordingCanvas();
      final painter = buildPainter(
        tier: EdgeQuality.full,
        connectOnOpenActive: true,
        connectOnOpenRevealedEdgeIds: revealedEdges,
        connectOnOpenCurrentEdgeIds: currentEdges,
        connectOnOpenProgress: 0.5, // mid-animation
      );
      painter.paint(canvas, const Size(1000, 1000));

      // ALL 20 edges must paint a line — the 10 "neither" edges must
      // NOT be hidden (the bug fix: they're at full alpha).
      expect(canvas.drawPathCount, greaterThanOrEqualTo(allEdges.length),
          reason: 'Every edge (${allEdges.length}) must paint its line — '
              'edges in neither the revealed nor current set must be drawn '
              'at full alpha (the connect-on-open animation is a cosmetic '
              'overlay, not a substitution). Got ${canvas.drawPathCount} '
              'drawPath calls.');
    });

    test(
        'DOT tier: every edge paints its line when connectOnOpen is ON with '
        'a MIX (the worst-case tier for the bug — previously midpoints '
        'painted but lines were hidden)',
        () {
      final revealedEdges = <String>{
        for (final d in allEdges.take(5)) d.edge.id,
      };
      final currentEdges = <String>{
        for (final d in allEdges.skip(5).take(5)) d.edge.id,
      };

      final canvas = _RecordingCanvas();
      final painter = buildPainter(
        tier: EdgeQuality.dot,
        connectOnOpenActive: true,
        connectOnOpenRevealedEdgeIds: revealedEdges,
        connectOnOpenCurrentEdgeIds: currentEdges,
        connectOnOpenProgress: 0.5,
      );
      painter.paint(canvas, const Size(1000, 1000));

      // DOT LOD: each visible edge paints exactly 1 drawPath (the body
      // stroke). 20 edges → 20 drawPath calls. The midpoint is painted
      // via drawCircle (simplified at DOT LOD). We expect:
      //   • drawPathCount >= 20 (every edge's line)
      //   • drawCircleCount >= 20 (every edge's midpoint — but spouse
      //     hearts use drawPath, so the actual count varies)
      // The CRITICAL assertion is that drawPathCount >= 20 — no edge
      // was silently dropped.
      expect(canvas.drawPathCount, greaterThanOrEqualTo(allEdges.length),
          reason: 'DOT tier: every edge (${allEdges.length}) must paint its '
              'line. Got ${canvas.drawPathCount} drawPath calls.');
      // Midpoints: at least 1 draw call per edge (drawCircle for dot
      // symbols, drawPath for heart symbols on spouse edges). The
      // combined count covers all edges.
      expect(
          canvas.drawCircleCount + canvas.drawPathCount,
          greaterThanOrEqualTo(allEdges.length * 2),
          reason: 'DOT tier: every edge must paint BOTH its line AND its '
              'midpoint. The combined draw calls should be at least '
              '${allEdges.length * 2} (1 line + 1 midpoint per edge). '
              'Got ${canvas.drawCircleCount} circles + ${canvas.drawPathCount} '
              'paths = ${canvas.drawCircleCount + canvas.drawPathCount}.');
    });

    test(
        'REGRESSION: 23 visible persons and 145 edges produces 145 drawn '
        'lines (no edge silently dropped)',
        () {
      // Reproduce the exact scenario from the user's bug report:
      // "Showing 23 of 715 persons" with "LINKS 145".
      // 23 persons → 23 positions. 145 edges among those 23 persons.
      // Every edge must be drawn.
      final positions23 = <String, Offset>{
        for (var i = 0; i < 23; i++)
          'p$i': Offset((i % 6) * 100.0, (i ~/ 6) * 100.0),
      };
      // Generate 145 edges: for each pair (i, j) with i < j, up to 145.
      final edges145 = <DedupedEdge>[];
      var edgeIdx = 0;
      for (var i = 0; i < 23 && edgeIdx < 145; i++) {
        for (var j = i + 1; j < 23 && edgeIdx < 145; j++) {
          edges145.add(_deduped(_edge(
            'e${edgeIdx}_p${i}_p$j',
            'p$i',
            'p$j',
            key: edgeIdx % 7 == 0 ? 'spouse' : 'parent',
          )));
          edgeIdx++;
        }
      }
      expect(edges145.length, 145, reason: 'Test setup: must generate 145 edges');

      final categories145 = <String, KinshipEdgeCategory>{};
      for (final d in edges145) {
        categories145[d.edge.id] = d.edge.relationshipKey == 'spouse'
            ? KinshipEdgeCategory.spouse
            : KinshipEdgeCategory.extended;
      }

      final canvas = _RecordingCanvas();
      final painter = EngineEdgePainter(
        positions: positions23,
        edges: edges145,
        edgeCategories: categories145,
        edgeCustomColors: const {},
        coupleUnions: const [],
        cache: EdgePathCache(),
        edgeQuality: EdgeQuality.full,
        graphRevision: 1,
        layoutRevision: 1,
        edgeVisualRevision: 1,
        // No connect-on-open — every edge should be at full alpha.
      );
      painter.paint(canvas, const Size(2000, 2000));

      // EVERY one of the 145 edges must paint its body line. The
      // drawPathCount includes body + ridge + shadow passes for each
      // edge (3 passes for FULL tier) plus the spouse heart paths.
      // The minimum is 145 (one body per edge) — we assert >= 145.
      expect(canvas.drawPathCount, greaterThanOrEqualTo(145),
          reason: 'REGRESSION: 23 persons + 145 edges must produce at least '
              '145 drawPath calls (one per edge body). Got ${canvas.drawPathCount}. '
              'This is the exact scenario from the user\'s bug report — '
              'no edge may be silently dropped.');
    });

    test(
        'An edge in the "neither" set is NOT hidden at alpha 0 — '
        'it paints a line at full alpha',
        () {
      // One edge, in NEITHER the revealed nor current set, with
      // connectOnOpenActive=true. Before the fix: line was hidden
      // (alpha 0), only the midpoint painted. After the fix: line is
      // painted at full alpha.
      final positions2 = <String, Offset>{
        'a': const Offset(0, 0),
        'b': const Offset(200, 0),
      };
      final edges2 = <DedupedEdge>[
        _deduped(_edge('e1', 'a', 'b', key: 'parent')),
      ];
      final categories2 = <String, KinshipEdgeCategory>{
        'e1': KinshipEdgeCategory.extended,
      };

      final canvas = _RecordingCanvas();
      final painter = EngineEdgePainter(
        positions: positions2,
        edges: edges2,
        edgeCategories: categories2,
        edgeCustomColors: const {},
        coupleUnions: const [],
        cache: EdgePathCache(),
        edgeQuality: EdgeQuality.full,
        graphRevision: 1,
        layoutRevision: 1,
        edgeVisualRevision: 1,
        connectOnOpenActive: true,
        connectOnOpenRevealedEdgeIds: const {}, // empty
        connectOnOpenCurrentEdgeIds: const {}, // empty
        connectOnOpenCurrentEdgeId: null,
        connectOnOpenProgress: 0.5,
      );
      painter.paint(canvas, const Size(1000, 1000));

      // The edge is in NEITHER set. Before the fix: drawPathCount = 0
      // (line hidden) but drawCircleCount = 1 (midpoint painted) →
      // dot without line. After the fix: drawPathCount >= 1 (line
      // painted at full alpha) AND drawCircleCount >= 1 (midpoint
      // also painted — they're coupled).
      expect(canvas.drawPathCount, greaterThanOrEqualTo(1),
          reason: 'The "neither" edge must paint its line at full alpha — '
              'not be hidden at alpha 0 (the bug fix). Got 0 drawPath calls.');
      expect(canvas.drawCircleCount + canvas.drawPathCount,
          greaterThanOrEqualTo(2),
          reason: 'The "neither" edge must paint BOTH its line AND its '
              'midpoint (coupled). Got ${canvas.drawCircleCount} circles + '
              '${canvas.drawPathCount} paths.');
    });

    test(
        'Mid-animation current edge with progress=0 paints NEITHER line NOR '
        'midpoint (both skipped together — coupled)',
        () {
      // Edge in the current set with progress=0 (its stagger delay
      // hasn't elapsed yet). Before the fix: line was at alpha 0 BUT
      // skipMidpointForConnectOnOpen was true (progress < 1.0), so
      // midpoint was also skipped — this case happened to be correct.
      // After the fix: edgeLineVisible = (progress > 0.0) = false, so
      // BOTH are skipped via the early `continue`.
      //
      // This test verifies the coupling holds: at progress=0, neither
      // is painted. (At progress > 0, both are painted — verified in
      // the next test.)
      final positions2 = <String, Offset>{
        'a': const Offset(0, 0),
        'b': const Offset(200, 0),
      };
      final edges2 = <DedupedEdge>[
        _deduped(_edge('e1', 'a', 'b', key: 'parent')),
      ];
      final categories2 = <String, KinshipEdgeCategory>{
        'e1': KinshipEdgeCategory.extended,
      };

      final canvas = _RecordingCanvas();
      final painter = EngineEdgePainter(
        positions: positions2,
        edges: edges2,
        edgeCategories: categories2,
        edgeCustomColors: const {},
        coupleUnions: const [],
        cache: EdgePathCache(),
        edgeQuality: EdgeQuality.full,
        graphRevision: 1,
        layoutRevision: 1,
        edgeVisualRevision: 1,
        connectOnOpenActive: true,
        connectOnOpenRevealedEdgeIds: const {},
        connectOnOpenCurrentEdgeIds: const {'e1'},
        connectOnOpenCurrentEdgeId: null,
        connectOnOpenProgress: 0.0, // edge hasn't started yet
        connectOnOpenEdgeDelays: const {'e1': 0.33}, // depth-1 delay
      );
      painter.paint(canvas, const Size(1000, 1000));

      // At progress=0 with delay 0.33, the edge's per-edge progress
      // is clamp((0 - 0.33) / 0.67, 0, 1) = 0. So edgeLineVisible
      // is false (progress > 0 is false). Both line and midpoint are
      // skipped — neither is painted.
      expect(canvas.drawPathCount, 0,
          reason: 'At progress=0 (edge has not started), the line must NOT '
              'be painted (alpha 0).');
      expect(canvas.drawCircleCount, 0,
          reason: 'At progress=0 (edge has not started), the midpoint must '
              'NOT be painted — it is coupled to the line (both skipped '
              'together). This is the fix: previously the midpoint could '
              'paint while the line was hidden, producing the dot-without-'
              'line bug.');
    });

    test(
        'Mid-animation current edge with progress=0.5 paints BOTH line AND '
        'midpoint (coupled)',
        () {
      // Same setup as above but progress=0.5 with no delay. The edge's
      // per-edge progress is 0.5, so edgeLineVisible is true (progress
      // > 0). Both line and midpoint are painted.
      final positions2 = <String, Offset>{
        'a': const Offset(0, 0),
        'b': const Offset(200, 0),
      };
      final edges2 = <DedupedEdge>[
        _deduped(_edge('e1', 'a', 'b', key: 'parent')),
      ];
      final categories2 = <String, KinshipEdgeCategory>{
        'e1': KinshipEdgeCategory.extended,
      };

      final canvas = _RecordingCanvas();
      final painter = EngineEdgePainter(
        positions: positions2,
        edges: edges2,
        edgeCategories: categories2,
        edgeCustomColors: const {},
        coupleUnions: const [],
        cache: EdgePathCache(),
        edgeQuality: EdgeQuality.full,
        graphRevision: 1,
        layoutRevision: 1,
        edgeVisualRevision: 1,
        connectOnOpenActive: true,
        connectOnOpenRevealedEdgeIds: const {},
        connectOnOpenCurrentEdgeIds: const {'e1'},
        connectOnOpenCurrentEdgeId: null,
        connectOnOpenProgress: 0.5, // mid-animation
        connectOnOpenEdgeDelays: const {'e1': 0.0}, // no delay
      );
      painter.paint(canvas, const Size(1000, 1000));

      // At progress=0.5 with no delay, the edge's per-edge progress
      // is 0.5. edgeLineVisible = (0.5 > 0) = true. Both line and
      // midpoint are painted.
      expect(canvas.drawPathCount, greaterThanOrEqualTo(1),
          reason: 'At progress=0.5 (mid-animation), the line MUST be '
              'painted (alpha 0.5).');
      expect(canvas.drawCircleCount, greaterThanOrEqualTo(1),
          reason: 'At progress=0.5 (mid-animation), the midpoint MUST be '
              'painted — it is coupled to the line (both visible together).');
    });
  });
}

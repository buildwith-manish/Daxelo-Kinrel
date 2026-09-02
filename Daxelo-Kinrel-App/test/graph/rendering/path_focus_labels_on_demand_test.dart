// test/graph/rendering/path_focus_labels_on_demand_test.dart
//
// Tests for Feature 3 (labels on demand).
//
// Verifies:
//   1. No labels are rendered by default (no path focus).
//   2. No labels are rendered when pathFocusActive is true but
//      pathFocusLabels is null (defensive — caller forgot to pass).
//   3. Labels ARE rendered when pathFocusActive is true AND
//      pathFocusLabels contains a label for a path-focused edge.
//   4. Labels are NOT rendered for non-path-focused edges even when
//      the labels map contains their ID.
//   5. Labels are NOT rendered at DOT LOD (text would be invisible).
//   6. Labels respect the edge's category color in the border.
//
// The recording canvas captures every drawParagraph / drawRRect call
// so we can assert "labels were drawn" without parsing the actual
// text glyphs.

import 'dart:ui' show Canvas, Offset, Paint, Path, Paragraph, Rect, RRect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/kinship/kinship_edge_style.dart';
import 'package:kinrel/graph/engine/edge_dedup.dart' show DedupedEdge;
import 'package:kinrel/graph/data/graph_data_models.dart' show GraphEdgeData;
import 'package:kinrel/graph/rendering/edge_path_cache.dart' show EdgePathCache;
import 'package:kinrel/graph/rendering/edge_quality.dart' show EdgeQuality;
import 'package:kinrel/graph/widgets/engine/engine_edge_painter.dart'
    show EngineEdgePainter;

/// A recording canvas that captures label-related draw calls.
class _RecordingCanvas implements Canvas {
  int drawParagraphCount = 0;
  int drawRRectCount = 0;
  int drawPathCount = 0;
  int drawCircleCount = 0;
  final List<Paragraph> paragraphs = [];

  @override
  void drawParagraph(Paragraph paragraph, Offset offset) {
    drawParagraphCount++;
    paragraphs.add(paragraph);
  }

  @override
  void drawRRect(RRect rrect, Paint paint) {
    drawRRectCount++;
  }

  @override
  void drawPath(Path path, Paint paint) {
    drawPathCount++;
  }

  @override
  void drawCircle(Offset c, double radius, Paint paint) {
    drawCircleCount++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {}
}

void main() {
  // Build a simple path-focused graph:
  //   viewer — parent — grandparent — uncle
  // Edge IDs: e1 (viewer-parent), e2 (parent-gp), e3 (gp-uncle).
  // Path focus edges: e1, e2, e3.
  final positions = <String, Offset>{
    'viewer': const Offset(0, 0),
    'parent': const Offset(0, 100),
    'grandparent': const Offset(0, 200),
    'uncle': const Offset(100, 200),
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
  ];
  final edgeCategories = <String, KinshipEdgeCategory>{
    for (final d in edges) d.edge.id: KinshipEdgeCategory.parent,
  };

  EngineEdgePainter buildPainter({
    Set<String>? pathFocusedEdgeIds,
    bool pathFocusActive = false,
    Map<String, String>? pathFocusLabels,
    EdgeQuality edgeQuality = EdgeQuality.full,
  }) {
    return EngineEdgePainter(
      positions: positions,
      edges: edges,
      edgeCategories: edgeCategories,
      edgeCustomColors: const {},
      coupleUnions: const [],
      cache: EdgePathCache(),
      edgeQuality: edgeQuality,
      graphRevision: 1,
      layoutRevision: 1,
      edgeVisualRevision: 1,
      pathFocusedEdgeIds: pathFocusedEdgeIds,
      pathFocusActive: pathFocusActive,
      pathFocusLabels: pathFocusLabels,
    );
  }

  group('v5.x (Feature 3) — labels on demand', () {
    test(
        'Case 1: no path focus → no labels rendered (default state, '
        'even if the labels map is non-empty)', () {
      final canvas = _RecordingCanvas();
      final painter = buildPainter(
        // No pathFocusActive — labels should never be rendered.
        pathFocusActive: false,
        pathFocusLabels: {'e1': 'Father', 'e2': 'Father', 'e3': 'Father'},
      );
      painter.paint(canvas, const Size(1000, 1000));

      expect(canvas.drawParagraphCount, 0,
          reason: 'No labels should be rendered when pathFocusActive '
              'is false, even if pathFocusLabels is non-empty');
    });

    test(
        'Case 2: path focus active but pathFocusLabels is null → no '
        'labels rendered (defensive — caller forgot to pass labels)', () {
      final canvas = _RecordingCanvas();
      final painter = buildPainter(
        pathFocusedEdgeIds: {'e1', 'e2', 'e3'},
        pathFocusActive: true,
        pathFocusLabels: null, // caller forgot to pass
      );
      painter.paint(canvas, const Size(1000, 1000));

      expect(canvas.drawParagraphCount, 0,
          reason: 'No labels should be rendered when pathFocusLabels '
              'is null, even if pathFocusActive is true');
    });

    test(
        'Case 3 (KEY TEST): path focus active AND pathFocusLabels is '
        'non-null → labels ARE rendered for each path-focused edge', () {
      final canvas = _RecordingCanvas();
      final painter = buildPainter(
        pathFocusedEdgeIds: {'e1', 'e2', 'e3'},
        pathFocusActive: true,
        pathFocusLabels: {'e1': 'Father', 'e2': 'Father', 'e3': 'Father'},
      );
      painter.paint(canvas, const Size(1000, 1000));

      // v5.x (BUG-1 fix): the floating edge midpoint labels have been
      // REMOVED. The painter no longer calls _paintPathFocusLabel —
      // relationship labels are only shown on NODES (under their name),
      // never as standalone floating labels at edge midpoints. This
      // test now asserts 0 drawParagraph calls (no labels on edges).
      expect(canvas.drawParagraphCount, 0,
          reason: 'v5.x (BUG-1 fix): floating edge midpoint labels '
              'have been REMOVED. No labels should be rendered on '
              'edges — only on nodes (which are separate widgets, '
              'not painted by EngineEdgePainter).');
      // No label backgrounds either.
      expect(canvas.drawRRectCount, 0,
          reason: 'v5.x (BUG-1 fix): no label background/border '
              'drawRRect calls — labels are gone.');
    });

    test(
        'Case 4: labels are NOT rendered for non-path-focused edges '
        'even when pathFocusLabels contains their ID', () {
      // Add an extra edge that is NOT in the path focus.
      final extraEdges = <DedupedEdge>[
        ...edges,
        DedupedEdge(
          edge: GraphEdgeData(
              id: 'e4',
              sourceId: 'uncle',
              targetId: 'cousin',
              relationshipKey: 'father'),
          lateralOffset: 0.0,
          parallelCount: 1,
        ),
      ];
      final extraPositions = <String, Offset>{
        ...positions,
        'cousin': const Offset(200, 200),
      };
      final extraCategories = <String, KinshipEdgeCategory>{
        for (final d in extraEdges) d.edge.id: KinshipEdgeCategory.parent,
      };

      final canvas = _RecordingCanvas();
      final painter = EngineEdgePainter(
        positions: extraPositions,
        edges: extraEdges,
        edgeCategories: extraCategories,
        edgeCustomColors: const {},
        coupleUnions: const [],
        cache: EdgePathCache(),
        edgeQuality: EdgeQuality.full,
        graphRevision: 1,
        layoutRevision: 1,
        edgeVisualRevision: 1,
        // e4 is NOT in pathFocusedEdgeIds.
        pathFocusedEdgeIds: {'e1', 'e2', 'e3'},
        pathFocusActive: true,
        // But e4 IS in pathFocusLabels (caller bug — should not
        // happen, but the painter must be defensive).
        pathFocusLabels: {
          'e1': 'Father',
          'e2': 'Father',
          'e3': 'Father',
          'e4': 'Cousin',
        },
      );
      painter.paint(canvas, const Size(1000, 1000));

      // v5.x (BUG-1 fix): labels are always 0 now — removed entirely.
      expect(canvas.drawParagraphCount, 0,
          reason: 'v5.x (BUG-1 fix): no edge labels at all — removed.');
    });

    test(
        'Case 5: labels are NOT rendered at DOT LOD (text would be '
        'invisible / unreadable at that zoom tier)', () {
      final canvas = _RecordingCanvas();
      final painter = buildPainter(
        pathFocusedEdgeIds: {'e1', 'e2', 'e3'},
        pathFocusActive: true,
        pathFocusLabels: {'e1': 'Father', 'e2': 'Father', 'e3': 'Father'},
        edgeQuality: EdgeQuality.dot, // DOT tier
      );
      painter.paint(canvas, const Size(1000, 1000));

      expect(canvas.drawParagraphCount, 0,
          reason: 'v5.x (BUG-1 fix): no edge labels at any tier — removed.');
    });

    test(
        'Case 6: empty label string in pathFocusLabels → not rendered '
        '(defensive against empty / whitespace-only labels)', () {
      final canvas = _RecordingCanvas();
      final painter = buildPainter(
        pathFocusedEdgeIds: {'e1', 'e2', 'e3'},
        pathFocusActive: true,
        pathFocusLabels: {
          'e1': 'Father',
          'e2': '', // empty
          'e3': 'Father',
        },
      );
      painter.paint(canvas, const Size(1000, 1000));

      // v5.x (BUG-1 fix): labels are always 0 now — removed entirely.
      expect(canvas.drawParagraphCount, 0,
          reason: 'v5.x (BUG-1 fix): no edge labels at all — removed.');
    });

    test(
        'Case 7: CHIP LOD does NOT render labels (BUG-1 fix removed all '
        'edge labels)', () {
      final canvas = _RecordingCanvas();
      final painter = buildPainter(
        pathFocusedEdgeIds: {'e1', 'e2', 'e3'},
        pathFocusActive: true,
        pathFocusLabels: {'e1': 'Father', 'e2': 'Father', 'e3': 'Father'},
        edgeQuality: EdgeQuality.chip, // CHIP tier
      );
      painter.paint(canvas, const Size(1000, 1000));

      expect(canvas.drawParagraphCount, 0,
          reason: 'v5.x (BUG-1 fix): no edge labels at any tier — removed.');
    });
  });
}

// lib/shared/painters/family_tree_painter.dart
//
// DAXELO KINREL — Family Tree Edge Painter
//
// A CustomPainter that draws graph edges (connection lines between person nodes)
// in the family tree graph canvas.
//
// Features:
//   - ALL edges are dashed by default (dash [4,4], orange 45% alpha, width 1.5)
//   - Spouse edges: small filled heart shape at midpoint (~14dp)
//   - Parent-child & sibling edges: filled orange circle (r5) with glow halo (r9)
//   - Selected edge: solid line, width 2.5, full-opacity KinrelColors.orange
//   - Default straight lines for radial layout (Bezier method retained but unused)
//   - Level-of-Detail (LOD) rendering based on zoomLevel:
//       zoom < 0.4 : minimal mode (straight lines only, no dots/hearts)
//       zoom >= 0.4: full mode (lines with midpoint indicators)
//   - highlightedGeneration: when set, edges where BOTH endpoints are NOT
//     in that generation are drawn at 0.15 alpha

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/constants/brand_colors.dart';

// ═══════════════════════════════════════════════════════════════════════
// EDGE DATA MODEL
// ═══════════════════════════════════════════════════════════════════════

/// A lightweight edge descriptor passed to the painter.
class EdgeData {
  final String id;
  final String fromPersonId;
  final String toPersonId;
  final String relationshipKey;

  const EdgeData({
    required this.id,
    required this.fromPersonId,
    required this.toPersonId,
    required this.relationshipKey,
  });
}

// ═══════════════════════════════════════════════════════════════════════
// SPOUSE KEY SET
// ═══════════════════════════════════════════════════════════════════════

/// Relationship keys that represent spouse/partner connections.
const Set<String> _spouseKeys = <String>{
  'husband',
  'wife',
  'spouse',
  'partner',
};

// ═══════════════════════════════════════════════════════════════════════
// FAMILY TREE PAINTER
// ═══════════════════════════════════════════════════════════════════════

/// CustomPainter that draws graph edges between person nodes.
///
/// Usage:
/// ```dart
/// CustomPaint(
///   size: Size(canvasWidth, canvasHeight),
///   painter: FamilyTreePainter(
///     positions: layoutResult.positions,
///     relationships: edgeDataList,
///     selectedEdgeId: selectedEdgeId,
///     zoomLevel: currentZoom,
///     generationMap: personIdToGenerationIndex,
///     highlightedGeneration: 1,
///   ),
/// )
/// ```
class FamilyTreePainter extends CustomPainter {
  FamilyTreePainter({
    required this.positions,
    required this.relationships,
    this.selectedEdgeId,
    this.zoomLevel = 1.0,
    this.nodeWidth = 72.0,
    this.nodeHeight = 72.0,
    this.generationMap,
    this.highlightedGeneration,
  });

  /// Map of personId → center Offset (from layout computation).
  final Map<String, Offset> positions;

  /// List of relationship edges to draw.
  final List<EdgeData> relationships;

  /// Currently selected edge ID (highlighted in orange).
  final String? selectedEdgeId;

  /// Current zoom level from InteractiveViewer.
  final double zoomLevel;

  /// Width of each person node card (dp).
  final double nodeWidth;

  /// Height of each person node card (dp).
  final double nodeHeight;

  /// Map of personId → generation index (for highlighted generation filtering).
  final Map<String, int>? generationMap;

  /// When set, edges where BOTH endpoints are NOT in this generation
  /// are drawn at 0.15 alpha. Null = no filtering.
  final int? highlightedGeneration;

  // ── Paint Constants ────────────────────────────────────────────────

  /// Default edge color: KinrelColors.orange at 45% alpha, dashed
  static final Color _defaultEdgeColor =
      KinrelColors.orange.withValues(alpha: 0.45);

  /// Default edge stroke width.
  static const double _defaultStrokeWidth = 1.5;

  /// Selected edge color: full-opacity KinrelColors.orange, solid
  static const Color _selectedEdgeColor = KinrelColors.orange;

  /// Selected edge stroke width.
  static const double _selectedStrokeWidth = 2.5;

  /// Dash pattern for default edges: [dash, gap].
  static const List<double> _dashArray = [4.0, 4.0];

  /// Dimmed alpha for edges outside highlighted generation.
  static const double _dimmedAlpha = 0.15;

  // ── Midpoint Indicator Constants ──────────────────────────────────

  /// Radius of the filled dot at parent-child / sibling midpoints.
  static const double _dotRadius = 5.0;

  /// Radius of the glow halo around the dot.
  static const double _dotGlowRadius = 9.0;

  /// Color for the glow halo (0x33E8612A = KinrelColors.orangeGlow).
  static const Color _dotGlowColor = Color(0x33E8612A);

  /// Total size of the heart shape for spouse midpoints.
  static const double _heartSize = 14.0;

  // ── LOD Thresholds ─────────────────────────────────────────────────

  /// Below this zoom level, skip dots/hearts and draw simplified lines only.
  static const double _lodMinimalZoom = 0.4;

  bool get _isMinimal => zoomLevel < _lodMinimalZoom;

  // ── Paint ──────────────────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    for (final edge in relationships) {
      final fromPos = positions[edge.fromPersonId];
      final toPos = positions[edge.toPersonId];
      if (fromPos == null || toPos == null) continue;

      final isSelected = edge.id == selectedEdgeId;
      final isSpouse = _spouseKeys.contains(edge.relationshipKey);

      // Determine if this edge should be dimmed (generation filter)
      final isDimmed = _shouldDimEdge(edge);

      _drawEdge(
        canvas: canvas,
        fromPos: fromPos,
        toPos: toPos,
        isSelected: isSelected,
        isSpouse: isSpouse,
        isDimmed: isDimmed,
      );
    }
  }

  /// Returns true if this edge should be drawn dimmed based on
  /// the highlightedGeneration filter.
  bool _shouldDimEdge(EdgeData edge) {
    if (highlightedGeneration == null || generationMap == null) return false;

    final fromGen = generationMap![edge.fromPersonId];
    final toGen = generationMap![edge.toPersonId];

    // If we can't determine the generation, don't dim
    if (fromGen == null || toGen == null) return false;

    // Dim if NEITHER endpoint is in the highlighted generation
    return fromGen != highlightedGeneration && toGen != highlightedGeneration;
  }

  /// Draws a single edge between two person positions.
  void _drawEdge({
    required Canvas canvas,
    required Offset fromPos,
    required Offset toPos,
    required bool isSelected,
    required bool isSpouse,
    required bool isDimmed,
  }) {
    // Determine edge endpoints from node centers
    final Offset start;
    final Offset end;

    if (isSpouse) {
      // Spouse connections: horizontal line between side edges of nodes
      if (fromPos.dx <= toPos.dx) {
        start = Offset(fromPos.dx + nodeWidth / 2, fromPos.dy);
        end = Offset(toPos.dx - nodeWidth / 2, toPos.dy);
      } else {
        start = Offset(fromPos.dx - nodeWidth / 2, fromPos.dy);
        end = Offset(toPos.dx + nodeWidth / 2, toPos.dy);
      }
    } else {
      // Parent-child / sibling connections: bottom of upper → top of lower
      if (fromPos.dy <= toPos.dy) {
        start = Offset(fromPos.dx, fromPos.dy + nodeHeight / 2);
        end = Offset(toPos.dx, toPos.dy - nodeHeight / 2);
      } else {
        start = Offset(fromPos.dx, fromPos.dy - nodeHeight / 2);
        end = Offset(toPos.dx, toPos.dy + nodeHeight / 2);
      }
    }

    // Determine color and stroke width
    final Color edgeColor;
    final double strokeWidth;

    if (isSelected) {
      // Selected: solid, full-opacity, wider
      edgeColor = _selectedEdgeColor;
      strokeWidth = _selectedStrokeWidth;
    } else {
      // Default: dashed, 45% alpha orange
      edgeColor = _defaultEdgeColor;
      strokeWidth = _defaultStrokeWidth;
    }

    // Apply dimmed alpha override
    final Color finalColor =
        isDimmed ? edgeColor.withValues(alpha: _dimmedAlpha) : edgeColor;

    final paint = Paint()
      ..color = finalColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // ── Draw line ──────────────────────────────────────────────────

    if (isSelected) {
      // Selected edge is SOLID (not dashed)
      canvas.drawLine(start, end, paint);
    } else {
      // Default: dashed line with [4, 4] pattern
      _drawDashedLine(canvas, start, end, paint);
    }

    // ── Draw midpoint indicator (skip in minimal LOD) ────────────

    if (!_isMinimal && !isDimmed) {
      final midpoint = Offset(
        (start.dx + end.dx) / 2,
        (start.dy + end.dy) / 2,
      );

      if (isSpouse) {
        _drawHeart(canvas, midpoint);
      } else {
        // Parent-child or sibling: filled dot with glow halo
        _drawDot(canvas, midpoint);
      }
    }
  }

  // ── Midpoint Drawing ───────────────────────────────────────────────

  /// Draws a small filled orange circle with a glow halo at the midpoint.
  /// Used for parent-child and sibling edges.
  void _drawDot(Canvas canvas, Offset center) {
    // Glow halo
    final glowPaint = Paint()
      ..color = _dotGlowColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, _dotGlowRadius, glowPaint);

    // Solid dot
    final dotPaint = Paint()
      ..color = KinrelColors.orange
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, _dotRadius, dotPaint);
  }

  /// Draws a small filled heart shape at the midpoint for spouse edges.
  /// Heart = two overlapping circles + a downward-pointing triangle.
  /// Total size ~14dp.
  void _drawHeart(Canvas canvas, Offset center) {
    final heartPaint = Paint()
      ..color = KinrelColors.orange
      ..style = PaintingStyle.fill;

    final s = _heartSize;
    final halfS = s / 2;
    final circleRadius = s / 4; // radius of the two top circles

    // Two overlapping circles at the top of the heart
    final leftCircleCenter = Offset(center.dx - circleRadius * 0.7, center.dy - circleRadius * 0.4);
    final rightCircleCenter = Offset(center.dx + circleRadius * 0.7, center.dy - circleRadius * 0.4);

    canvas.drawCircle(leftCircleCenter, circleRadius, heartPaint);
    canvas.drawCircle(rightCircleCenter, circleRadius, heartPaint);

    // Downward-pointing triangle to complete the heart
    final path = Path()
      ..moveTo(leftCircleCenter.dx - circleRadius * 0.7, leftCircleCenter.dy + circleRadius * 0.2)
      ..lineTo(rightCircleCenter.dx + circleRadius * 0.7, rightCircleCenter.dy + circleRadius * 0.2)
      ..lineTo(center.dx, center.dy + halfS * 0.75)
      ..close();

    canvas.drawPath(path, heartPaint);
  }

  // ── Line Drawing ───────────────────────────────────────────────────

  /// Draws a dashed line between two points using [_dashArray] pattern.
  void _drawDashedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint,
  ) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length == 0) return;

    final unitDx = dx / length;
    final unitDy = dy / length;

    final dashWidth = _dashArray[0];
    final dashGap = _dashArray[1];

    double covered = 0;
    bool draw = true;
    while (covered < length) {
      final segmentLength = draw ? dashWidth : dashGap;
      final endCovered = (covered + segmentLength).clamp(0.0, length);

      if (draw) {
        canvas.drawLine(
          Offset(start.dx + unitDx * covered, start.dy + unitDy * covered),
          Offset(start.dx + unitDx * endCovered, start.dy + unitDy * endCovered),
          paint,
        );
      }

      covered = endCovered;
      draw = !draw;
    }
  }

  /// Draws a cubic Bezier curve (smooth S-curve) between two points.
  ///
  /// Retained for optional use but NOT used by default in the radial layout.
  /// The control points create a smooth vertical S-curve:
  /// - CP1 pulls downward from start
  /// - CP2 pulls upward toward end
  void _drawBezierCurve(Canvas canvas, Offset start, Offset end, Paint paint) {
    final midY = (start.dy + end.dy) / 2;
    final controlPoint1 = Offset(start.dx, midY);
    final controlPoint2 = Offset(end.dx, midY);

    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(
        controlPoint1.dx,
        controlPoint1.dy,
        controlPoint2.dx,
        controlPoint2.dy,
        end.dx,
        end.dy,
      );

    canvas.drawPath(path, paint);
  }

  // ── Repaint ────────────────────────────────────────────────────────

  @override
  bool shouldRepaint(covariant FamilyTreePainter oldDelegate) {
    return oldDelegate.positions != positions ||
        oldDelegate.relationships != relationships ||
        oldDelegate.selectedEdgeId != selectedEdgeId ||
        oldDelegate.zoomLevel != zoomLevel ||
        oldDelegate.nodeWidth != nodeWidth ||
        oldDelegate.nodeHeight != nodeHeight ||
        oldDelegate.generationMap != generationMap ||
        oldDelegate.highlightedGeneration != highlightedGeneration;
  }
}

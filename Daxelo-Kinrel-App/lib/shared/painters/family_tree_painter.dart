// lib/shared/painters/family_tree_painter.dart
//
// DAXELO KINREL — Family Tree Edge Painter (V2.1 K-Graph Blueprint Phase 2)
//
// A CustomPainter that draws graph edges (connection lines between person nodes)
// in the family tree graph canvas.
//
// Features:
//   - Cubic Bezier S-curves for parent-child edges (zoom >= 0.4), straight in minimal
//   - Quadratic Bezier arch for spouse edges (zoom >= 0.4), straight in minimal
//   - Dashed edges with [5,4] dash pattern (default), solid for selected/connected-hover
//   - Spouse heart midpoints (pink #EC4899)
//   - Parent-child dot midpoints with glow halo
//   - Selected edge: solid, full-opacity KinrelColors.orange, width 2.5
//   - Connected-to-hovered edge: solid, 90% opacity, width 2.2
//   - Dimmed edges (not connected to hovered node): 8% opacity
//   - Edge labels on hover (relationshipKey) at midpoint when zoom >= 0.6
//   - Level-of-Detail (LOD) rendering based on zoomLevel:
//       zoom < 0.4 : minimal mode (straight lines only, no dots/hearts)
//       zoom >= 0.4: full mode (curves with midpoint indicators)
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
///     hoveredNodeId: hoveredPersonId,
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
    this.hoveredNodeId,
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

  /// Currently hovered node ID — edges connected to this node are emphasized,
  /// while non-connected edges are dimmed.
  final String? hoveredNodeId;

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

  /// Connected-to-hovered edge opacity.
  static const double _hoveredConnectedAlpha = 0.90;

  /// Connected-to-hovered edge stroke width.
  static const double _hoveredConnectedStrokeWidth = 2.2;

  /// Dimmed (not-connected-to-hovered) edge opacity.
  static const double _hoveredDimmedAlpha = 0.08;

  /// Dash pattern for default edges: [dash, gap].
  static const List<double> _dashArray = [5.0, 4.0];

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

  /// Spouse heart color — pink #EC4899 per V2.1 Blueprint.
  static const Color _spouseHeartColor = Color(0xFFEC4899);

  // ── Spouse Quadratic Curve Constants ──────────────────────────────

  /// Vertical offset for spouse quadratic curve control point (upward arch).
  static const double _spouseArchOffset = -20.0;

  // ── Edge Label Constants ──────────────────────────────────────────

  /// Background color for edge labels — darkElevated #202338.
  static const Color _labelBackgroundColor = Color(0xFF202338);

  /// Label text style font size.
  static const double _labelFontSize = 10.0;

  /// Label text color — white at 70% opacity.
  static const Color _labelTextColor = Color(0xB3FFFFFF);

  /// Label padding horizontal.
  static const double _labelPaddingH = 6.0;

  /// Label padding vertical.
  static const double _labelPaddingV = 3.0;

  /// Label border radius.
  static const double _labelBorderRadius = 4.0;

  // ── LOD Thresholds ─────────────────────────────────────────────────

  /// Below this zoom level, skip dots/hearts and draw simplified lines only.
  static const double _lodMinimalZoom = 0.4;

  /// Below this zoom level, skip edge labels (too small to read).
  static const double _lodLabelZoom = 0.6;

  bool get _isMinimal => zoomLevel < _lodMinimalZoom;
  bool get _showLabels => zoomLevel >= _lodLabelZoom;

  // ── Paint ──────────────────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    for (final edge in relationships) {
      final fromPos = positions[edge.fromPersonId];
      final toPos = positions[edge.toPersonId];
      if (fromPos == null || toPos == null) continue;

      final isSelected = edge.id == selectedEdgeId;
      final isSpouse = _spouseKeys.contains(edge.relationshipKey);
      final isConnectedToHovered = _isEdgeConnectedToHovered(edge);

      // Determine if this edge should be dimmed (generation filter)
      final isDimmed = _shouldDimEdge(edge);

      _drawEdge(
        canvas: canvas,
        edge: edge,
        fromPos: fromPos,
        toPos: toPos,
        isSelected: isSelected,
        isSpouse: isSpouse,
        isDimmed: isDimmed,
        isConnectedToHovered: isConnectedToHovered,
      );
    }
  }

  // ── Hover Helper ───────────────────────────────────────────────────

  /// Returns true if the given edge is connected to [hoveredNodeId].
  bool _isEdgeConnectedToHovered(EdgeData edge) {
    if (hoveredNodeId == null) return false;
    return edge.fromPersonId == hoveredNodeId ||
        edge.toPersonId == hoveredNodeId;
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
    required EdgeData edge,
    required Offset fromPos,
    required Offset toPos,
    required bool isSelected,
    required bool isSpouse,
    required bool isDimmed,
    required bool isConnectedToHovered,
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

    // ── Determine edge style ────────────────────────────────────────
    // Priority: selected > connected-to-hovered > dimmed-by-hover > default

    final Color edgeColor;
    final double strokeWidth;
    final bool isSolid; // true = solid line, false = dashed
    final double opacityOverride; // null = use edge color as-is

    if (isSelected) {
      // Selected: solid, full-opacity orange, wider
      edgeColor = _selectedEdgeColor;
      strokeWidth = _selectedStrokeWidth;
      isSolid = true;
      opacityOverride = 1.0;
    } else if (hoveredNodeId != null && isConnectedToHovered) {
      // Connected to hovered node: solid, 90% opacity, medium width
      edgeColor = _defaultEdgeColor;
      strokeWidth = _hoveredConnectedStrokeWidth;
      isSolid = true;
      opacityOverride = _hoveredConnectedAlpha;
    } else if (hoveredNodeId != null && !isConnectedToHovered) {
      // NOT connected to hovered node: dimmed to 8% opacity
      edgeColor = _defaultEdgeColor;
      strokeWidth = _defaultStrokeWidth;
      isSolid = false;
      opacityOverride = _hoveredDimmedAlpha;
    } else {
      // Default: dashed, 45% alpha orange
      edgeColor = _defaultEdgeColor;
      strokeWidth = _defaultStrokeWidth;
      isSolid = false;
      opacityOverride = -1; // sentinel: use color as-is
    }

    // Build final color, applying opacity and dimming
    Color finalColor = edgeColor;
    if (opacityOverride >= 0) {
      finalColor = edgeColor.withValues(alpha: opacityOverride);
    }
    if (isDimmed) {
      finalColor = finalColor.withValues(alpha: _dimmedAlpha);
    }

    final paint = Paint()
      ..color = finalColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // ── Draw line / curve ───────────────────────────────────────────

    if (isSpouse) {
      _drawSpouseEdge(canvas, start, end, paint, isSolid);
    } else {
      _drawParentChildEdge(canvas, start, end, paint, isSolid);
    }

    // ── Draw midpoint indicator (skip in minimal LOD or when dimmed) ─

    final showMidpoint = !_isMinimal && !isDimmed;
    // When hovering, only show midpoint for connected edges
    final showMidpointForHover =
        hoveredNodeId == null || isConnectedToHovered;

    if (showMidpoint && showMidpointForHover) {
      final midpoint = _computeMidpoint(start, end, isSpouse: isSpouse);

      if (isSpouse) {
        _drawSpouseMidpoint(canvas, midpoint);
      } else {
        _drawDot(canvas, midpoint);
      }
    }

    // ── Draw edge label on hover (skip if too zoomed out) ───────────

    if (_showLabels &&
        hoveredNodeId != null &&
        isConnectedToHovered &&
        !isSelected &&
        !isDimmed) {
      final midpoint = _computeMidpoint(start, end, isSpouse: isSpouse);
      _drawEdgeLabel(canvas, midpoint, edge.relationshipKey);
    }
  }

  // ── Edge Drawing Strategies ────────────────────────────────────────

  /// Draws a parent-child edge — Bezier curve in full LOD, straight line in minimal.
  void _drawParentChildEdge(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint,
    bool isSolid,
  ) {
    if (_isMinimal) {
      // Minimal LOD: straight lines for performance
      if (isSolid) {
        canvas.drawLine(start, end, paint);
      } else {
        _drawDashedLine(canvas, start, end, paint);
      }
    } else {
      // Full LOD: cubic Bezier S-curve
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

      if (isSolid) {
        canvas.drawPath(path, paint);
      } else {
        _drawDashedPath(canvas, path, paint);
      }
    }
  }

  /// Draws a spouse edge — quadratic arch in full LOD, straight line in minimal.
  void _drawSpouseEdge(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint,
    bool isSolid,
  ) {
    if (_isMinimal) {
      // Minimal LOD: straight lines for performance
      if (isSolid) {
        canvas.drawLine(start, end, paint);
      } else {
        _drawDashedLine(canvas, start, end, paint);
      }
    } else {
      // Full LOD: quadratic Bezier with upward arch
      final midX = (start.dx + end.dx) / 2;
      final midY = (start.dy + end.dy) / 2;
      final controlPoint = Offset(midX, midY + _spouseArchOffset);

      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..quadraticBezierTo(
          controlPoint.dx,
          controlPoint.dy,
          end.dx,
          end.dy,
        );

      if (isSolid) {
        canvas.drawPath(path, paint);
      } else {
        _drawDashedPath(canvas, path, paint);
      }
    }
  }

  /// Computes the visual midpoint of an edge, accounting for curves.
  Offset _computeMidpoint(Offset start, Offset end, {required bool isSpouse}) {
    if (_isMinimal) {
      // Straight line midpoint
      return Offset(
        (start.dx + end.dx) / 2,
        (start.dy + end.dy) / 2,
      );
    }

    if (isSpouse) {
      // Quadratic Bezier midpoint: t=0.5
      // B(0.5) = 0.25*P0 + 0.5*P1 + 0.25*P2
      final midX = (start.dx + end.dx) / 2;
      final midY = (start.dy + end.dy) / 2;
      final cp = Offset(midX, midY + _spouseArchOffset);
      return Offset(
        0.25 * start.dx + 0.5 * cp.dx + 0.25 * end.dx,
        0.25 * start.dy + 0.5 * cp.dy + 0.25 * end.dy,
      );
    } else {
      // Cubic Bezier midpoint: t=0.5
      // B(0.5) = 0.125*P0 + 0.375*CP1 + 0.375*CP2 + 0.125*P3
      final midY = (start.dy + end.dy) / 2;
      final cp1 = Offset(start.dx, midY);
      final cp2 = Offset(end.dx, midY);
      return Offset(
        0.125 * start.dx +
            0.375 * cp1.dx +
            0.375 * cp2.dx +
            0.125 * end.dx,
        0.125 * start.dy +
            0.375 * cp1.dy +
            0.375 * cp2.dy +
            0.125 * end.dy,
      );
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

  /// Draws a professional infinity symbol at spouse edge midpoints.
  /// Vector graphics only — no emoji.
  void _drawSpouseMidpoint(Canvas canvas, Offset midpoint) {
    // Outer glow circle
    canvas.drawCircle(
      midpoint,
      10.0,
      Paint()..color = const Color(0xFFF97316).withValues(alpha: 0.10),
    );

    // Middle glow circle
    canvas.drawCircle(
      midpoint,
      6.0,
      Paint()..color = const Color(0xFFF97316).withValues(alpha: 0.18),
    );

    // Infinity symbol path
    final paint = Paint()
      ..color = const Color(0xFFF97316)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    const double w = 5.5;
    const double h = 3.0;

    // Left loop of infinity
    path.moveTo(midpoint.dx, midpoint.dy);
    path.cubicTo(
      midpoint.dx - w * 0.8, midpoint.dy - h,
      midpoint.dx - w, midpoint.dy + h * 0.3,
      midpoint.dx, midpoint.dy,
    );

    // Right loop of infinity
    path.cubicTo(
      midpoint.dx + w * 0.8, midpoint.dy - h,
      midpoint.dx + w, midpoint.dy + h * 0.3,
      midpoint.dx, midpoint.dy,
    );

    canvas.drawPath(path, paint);

    // Center dot
    canvas.drawCircle(
      midpoint,
      1.5,
      Paint()
        ..color = const Color(0xFFF97316)
        ..style = PaintingStyle.fill,
    );
  }

  // ── Edge Label Drawing ─────────────────────────────────────────────

  /// Draws a small label at [midpoint] showing [relationshipKey].
  /// Background: darkElevated (#202338) rounded rect.
  /// Text: 10px, white 70% opacity.
  void _drawEdgeLabel(Canvas canvas, Offset midpoint, String label) {
    // Build text span to measure
    final textSpan = TextSpan(
      text: label,
      style: TextStyle(
        color: _labelTextColor,
        fontSize: _labelFontSize,
        fontWeight: FontWeight.w500,
      ),
    );

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    final textWidth = textPainter.width;
    final textHeight = textPainter.height;

    // Background rect
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: midpoint,
        width: textWidth + _labelPaddingH * 2,
        height: textHeight + _labelPaddingV * 2,
      ),
      Radius.circular(_labelBorderRadius),
    );

    final bgPaint = Paint()
      ..color = _labelBackgroundColor
      ..style = PaintingStyle.fill;
    canvas.drawRRect(rect, bgPaint);

    // Draw text centered in the rect
    final textOffset = Offset(
      midpoint.dx - textWidth / 2,
      midpoint.dy - textHeight / 2,
    );
    textPainter.paint(canvas, textOffset);
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

  /// Draws a dashed path along an arbitrary [Path] using [_dashArray] pattern.
  ///
  /// Measures the path length using [PathMetrics], then iterates through
  /// dash/gap segments, drawing only the dash portions.
  void _drawDashedPath(Canvas canvas, Path path, Paint paint) {
    final dashWidth = _dashArray[0];
    final dashGap = _dashArray[1];

    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      double distance = 0.0;
      bool draw = true;
      while (distance < metric.length) {
        final length = draw ? dashWidth : dashGap;
        if (distance + length > metric.length) {
          if (draw) {
            canvas.drawPath(
              metric.extractPath(distance, metric.length),
              paint,
            );
          }
          break;
        }
        if (draw) {
          canvas.drawPath(
            metric.extractPath(distance, distance + length),
            paint,
          );
        }
        distance += length;
        draw = !draw;
      }
    }
  }

  /// Draws a cubic Bezier curve (smooth S-curve) between two points.
  ///
  /// Used internally by [_drawParentChildEdge]. Retained as a public
  /// utility for external callers who need a simple Bezier draw.
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
        oldDelegate.hoveredNodeId != hoveredNodeId ||
        oldDelegate.zoomLevel != zoomLevel ||
        oldDelegate.nodeWidth != nodeWidth ||
        oldDelegate.nodeHeight != nodeHeight ||
        oldDelegate.generationMap != generationMap ||
        oldDelegate.highlightedGeneration != highlightedGeneration;
  }
}

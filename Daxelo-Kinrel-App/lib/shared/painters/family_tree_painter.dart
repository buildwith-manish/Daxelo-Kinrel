// lib/shared/painters/family_tree_painter.dart
//
// DAXELO KINREL — Family Tree Edge Painter
//
// A CustomPainter that draws graph edges (connection lines between person nodes)
// in the family tree graph canvas.
//
// Features:
//   - Cubic Bezier curves for parent-child connections (smooth S-curves)
//   - Dashed lines for spouse connections (husband/wife)
//   - Level-of-Detail (LOD) rendering based on zoomLevel:
//       zoom < 0.3  : minimal mode  (straight lines only, no labels)
//       zoom 0.3-0.8: simplified mode (curves, no relationship labels)
//       zoom > 0.8  : full mode (curves with relationship key labels)
//   - Highlights the selected edge in orange
//   - Edge colors:
//       Default : rgba(255, 255, 255, 0.12) with strokeWidth 1.5
//       Selected: KinrelColors.orange with strokeWidth 2.0
//       Spouse  : KinrelColors.gold at 40% alpha, strokeWidth 2.0, dashed

import 'dart:ui';
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
///     nodeWidth: 90,
///     nodeHeight: 110,
///   ),
/// )
/// ```
class FamilyTreePainter extends CustomPainter {
  FamilyTreePainter({
    required this.positions,
    required this.relationships,
    this.selectedEdgeId,
    this.zoomLevel = 1.0,
    this.nodeWidth = 90.0,
    this.nodeHeight = 110.0,
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

  // ── Paint Constants ────────────────────────────────────────────────

  /// Default edge color: rgba(255, 255, 255, 0.12)
  static const Color _defaultEdgeColor = Color(0x1FFFFFFF);

  /// Default edge stroke width.
  static const double _defaultStrokeWidth = 1.5;

  /// Selected edge color: KinrelColors.orange
  static const Color _selectedEdgeColor = KinrelColors.orange;

  /// Selected edge stroke width.
  static const double _selectedStrokeWidth = 2.0;

  /// Spouse edge color: KinrelColors.gold at 40% alpha
  static final Color _spouseEdgeColor =
      KinrelColors.gold.withValues(alpha: 0.4);

  /// Spouse edge stroke width.
  static const double _spouseStrokeWidth = 2.0;

  /// Dash pattern for spouse edges.
  static const double _dashWidth = 8.0;
  static const double _dashGap = 6.0;

  /// Label text style for full LOD mode.
  static const TextStyle _labelStyle = TextStyle(
    fontFamily: 'DMSans',
    fontSize: 10.0,
    fontWeight: FontWeight.w500,
    color: KinrelColors.textSecondaryDark,
    backgroundColor: KinrelColors.darkBackground,
  );

  // ── LOD Thresholds ─────────────────────────────────────────────────

  bool get _isMinimal => zoomLevel < 0.3;
  bool get _isSimplified => zoomLevel >= 0.3 && zoomLevel <= 0.8;
  bool get _isFull => zoomLevel > 0.8;

  // ── Paint ──────────────────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    for (final edge in relationships) {
      final fromPos = positions[edge.fromPersonId];
      final toPos = positions[edge.toPersonId];
      if (fromPos == null || toPos == null) continue;

      final isSelected = edge.id == selectedEdgeId;
      final isSpouse = _spouseKeys.contains(edge.relationshipKey);

      _drawEdge(
        canvas: canvas,
        fromPos: fromPos,
        toPos: toPos,
        isSelected: isSelected,
        isSpouse: isSpouse,
        label: edge.relationshipKey,
      );
    }
  }

  /// Draws a single edge between two person positions.
  void _drawEdge({
    required Canvas canvas,
    required Offset fromPos,
    required Offset toPos,
    required bool isSelected,
    required bool isSpouse,
    required String label,
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
      // Parent-child connections: bottom of parent → top of child
      if (fromPos.dy <= toPos.dy) {
        // from is above (parent)
        start = Offset(fromPos.dx, fromPos.dy + nodeHeight / 2);
        end = Offset(toPos.dx, toPos.dy - nodeHeight / 2);
      } else {
        // to is above (parent)
        start = Offset(fromPos.dx, fromPos.dy - nodeHeight / 2);
        end = Offset(toPos.dx, toPos.dy + nodeHeight / 2);
      }
    }

    // Determine color and stroke width
    final Color edgeColor;
    final double strokeWidth;

    if (isSelected) {
      edgeColor = _selectedEdgeColor;
      strokeWidth = _selectedStrokeWidth;
    } else if (isSpouse) {
      edgeColor = _spouseEdgeColor;
      strokeWidth = _spouseStrokeWidth;
    } else {
      edgeColor = _defaultEdgeColor;
      strokeWidth = _defaultStrokeWidth;
    }

    final paint = Paint()
      ..color = edgeColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // ── Draw based on LOD level ─────────────────────────────────────

    if (_isMinimal) {
      // Minimal: straight lines only, no labels
      if (isSpouse) {
        _drawDashedLine(canvas, start, end, paint);
      } else {
        canvas.drawLine(start, end, paint);
      }
    } else if (_isSimplified) {
      // Simplified: curves, no relationship labels
      if (isSpouse) {
        _drawDashedLine(canvas, start, end, paint);
      } else {
        _drawBezierCurve(canvas, start, end, paint);
      }
    } else {
      // Full: curves with relationship key labels
      if (isSpouse) {
        _drawDashedLine(canvas, start, end, paint);
        _drawLabel(canvas, start, end, label);
      } else {
        _drawBezierCurve(canvas, start, end, paint);
        _drawLabelAtMidpoint(canvas, start, end, label);
      }
    }
  }

  /// Draws a cubic Bezier curve (smooth S-curve) between two points.
  ///
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

  /// Draws a dashed line between two points.
  void _drawDashedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint,
  ) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final length = Offset(dx, dy).distance;
    if (length == 0) return;

    final unitDx = dx / length;
    final unitDy = dy / length;

    double covered = 0;
    bool draw = true;
    while (covered < length) {
      final segmentLength = draw ? _dashWidth : _dashGap;
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

  /// Draws a label at the midpoint of a straight line (spouse edge).
  void _drawLabel(Canvas canvas, Offset start, Offset end, String label) {
    final midX = (start.dx + end.dx) / 2;
    final midY = (start.dy + end.dy) / 2;
    final formattedLabel = _formatKey(label);

    final textSpan = TextSpan(
      text: formattedLabel,
      style: _labelStyle,
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    final offset = Offset(
      midX - textPainter.width / 2,
      midY - textPainter.height / 2,
    );

    // Draw background rect behind label for readability
    final bgPaint = Paint()..color = KinrelColors.darkBackground;
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(midX, midY),
        width: textPainter.width + 8,
        height: textPainter.height + 4,
      ),
      const Radius.circular(4),
    );
    canvas.drawRRect(bgRect, bgPaint);

    textPainter.paint(canvas, offset);
  }

  /// Draws a label at the midpoint along the Bezier curve (parent-child edge).
  void _drawLabelAtMidpoint(
    Canvas canvas,
    Offset start,
    Offset end,
    String label,
  ) {
    final midY = (start.dy + end.dy) / 2;
    // Approximate the Bezier midpoint using t=0.5 on the cubic curve
    final cp1 = Offset(start.dx, midY);
    final cp2 = Offset(end.dx, midY);

    // Cubic Bezier at t=0.5:
    // B(0.5) = (1-t)^3*P0 + 3*(1-t)^2*t*P1 + 3*(1-t)*t^2*P2 + t^3*P3
    final t = 0.5;
    final oneMinusT = 1.0 - t;
    final bezierMidX = oneMinusT * oneMinusT * oneMinusT * start.dx +
        3 * oneMinusT * oneMinusT * t * cp1.dx +
        3 * oneMinusT * t * t * cp2.dx +
        t * t * t * end.dx;
    final bezierMidY = oneMinusT * oneMinusT * oneMinusT * start.dy +
        3 * oneMinusT * oneMinusT * t * cp1.dy +
        3 * oneMinusT * t * t * cp2.dy +
        t * t * t * end.dy;

    final formattedLabel = _formatKey(label);

    final textSpan = TextSpan(
      text: formattedLabel,
      style: _labelStyle,
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    final offset = Offset(
      bezierMidX - textPainter.width / 2,
      bezierMidY - textPainter.height / 2,
    );

    // Draw background rect behind label for readability
    final bgPaint = Paint()..color = KinrelColors.darkBackground;
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(bezierMidX, bezierMidY),
        width: textPainter.width + 8,
        height: textPainter.height + 4,
      ),
      const Radius.circular(4),
    );
    canvas.drawRRect(bgRect, bgPaint);

    textPainter.paint(canvas, offset);
  }

  /// Formats a relationship key like 'father_in_law' → 'Father In Law'.
  static String _formatKey(String key) {
    return key
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  @override
  bool shouldRepaint(covariant FamilyTreePainter oldDelegate) {
    return oldDelegate.positions != positions ||
        oldDelegate.relationships != relationships ||
        oldDelegate.selectedEdgeId != selectedEdgeId ||
        oldDelegate.zoomLevel != zoomLevel ||
        oldDelegate.nodeWidth != nodeWidth ||
        oldDelegate.nodeHeight != nodeHeight;
  }
}

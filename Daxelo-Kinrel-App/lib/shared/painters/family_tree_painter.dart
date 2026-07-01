// lib/shared/painters/family_tree_painter.dart
//
// DAXELO KINREL — Family Tree Edge Painter (v2)
//
// v2 (2026-06-23): Delegates all color / line-shape / midpoint decisions
// to the central KinshipEdgeStyleResolver in lib/core/kinship/. This
// painter now produces the SAME visual output as the RelationshipEdge
// painter in lib/graph/widgets/ — single source of truth.
//
// What changed visually:
//   • Parent edges → BLUE solid bezier + blue dot.
//   • Child edges → PINK solid bezier + pink dot.
//   • Sibling edges → PURPLE dashed arc + purple dot.
//   • Spouse edges → ORANGE dashed straight + PINK heart.
//   • Grandparent edges → INDIGO solid extended bezier + indigo dot.
//   • Aunt/Uncle edges → CYAN dashed shallow S + cyan dot.
//   • Cousin edges → EMERALD wide-arc bezier + emerald dot.
//   • In-Law edges → AMBER dashed straight + amber dot.
//   • Extended edges → SLATE dashed (0.45 alpha) + slate dot.
//   • Indirect edges → GRAY dashed, NO dot, "indirect" text label.
//
// Public API preserved:
//   • class EdgeData
//   • class FamilyTreePainter (same constructor signature)
//
// LOD: zoom < 0.4 → minimal mode (straight lines, no midpoint indicators)
//
// Hover behavior preserved:
//   • hoveredNodeId set → connected edges solid 90% alpha,
//     non-connected edges dimmed to 20% alpha.
//   • Labels shown only when hovering a connected edge at zoom ≥ 0.6.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/constants/brand_colors.dart';
import '../../core/kinship/heart_shape.dart';
import '../../core/kinship/kinship_edge_style.dart';

// ═══════════════════════════════════════════════════════════════════════
// EDGE DATA MODEL (preserved API)
// ═══════════════════════════════════════════════════════════════════════

class EdgeData {
  final String id;
  final String fromPersonId;
  final String toPersonId;
  final String relationshipKey;
  final String? displayLabel;

  const EdgeData({
    required this.id,
    required this.fromPersonId,
    required this.toPersonId,
    required this.relationshipKey,
    this.displayLabel,
  });
}

// ═══════════════════════════════════════════════════════════════════════
// FAMILY TREE PAINTER
// ═══════════════════════════════════════════════════════════════════════

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

  final Map<String, Offset> positions;
  final List<EdgeData> relationships;
  final String? selectedEdgeId;
  final String? hoveredNodeId;
  final double zoomLevel;
  final double nodeWidth;
  final double nodeHeight;
  final Map<String, int>? generationMap;
  final int? highlightedGeneration;

  // ── Paint Constants ────────────────────────────────────────────────
  static const double _defaultStrokeWidth = 2.0;
  static const double _selectedStrokeWidth = 2.5;
  static const double _hoveredConnectedAlpha = 0.90;
  static const double _hoveredConnectedStrokeWidth = 2.2;
  static const double _hoveredDimmedAlpha = 0.20;
  static const double _dimmedAlpha = 0.30;

  // ── Midpoint Indicator Constants ──────────────────────────────────
  static const double _dotRadius = 5.0;
  static const double _dotGlowRadius = 9.0;
  // v89: Heart size = 26 dp (matches the visual footprint of the
  // EdgeDotWidget overlay, which uses a 32×32 canvas with the heart
  // filling ~78 % = 25 dp). Picking the same size here means the
  // painter-drawn heart (Layer 1) and widget-drawn heart (Layer 2)
  // overlay PERFECTLY when both are visible at zoom ≥ 0.4.
  static const double _heartSize = 26.0;

  // ── LOD Thresholds ─────────────────────────────────────────────────
  static const double _lodMinimalZoom = 0.4;
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
      final isConnectedToHovered = _isEdgeConnectedToHovered(edge);
      final isDimmed = _shouldDimEdge(edge);
      final category =
          KinshipEdgeClassifier.classify(edge.relationshipKey);

      _drawEdge(
        canvas: canvas,
        edge: edge,
        fromPos: fromPos,
        toPos: toPos,
        isSelected: isSelected,
        category: category,
        isDimmed: isDimmed,
        isConnectedToHovered: isConnectedToHovered,
      );
    }
  }

  // ── Hover / dim helpers ────────────────────────────────────────────

  bool _isEdgeConnectedToHovered(EdgeData edge) {
    if (hoveredNodeId == null) return false;
    return edge.fromPersonId == hoveredNodeId ||
        edge.toPersonId == hoveredNodeId;
  }

  bool _shouldDimEdge(EdgeData edge) {
    if (highlightedGeneration == null || generationMap == null) return false;
    final fromGen = generationMap![edge.fromPersonId];
    final toGen = generationMap![edge.toPersonId];
    if (fromGen == null || toGen == null) return false;
    return fromGen != highlightedGeneration && toGen != highlightedGeneration;
  }

  // ── Edge Drawing ───────────────────────────────────────────────────

  /// v52.8: Inline color literals to defeat dart2js tree-shaking.
  Color _colorForCategory(KinshipEdgeCategory category) {
    switch (category) {
      case KinshipEdgeCategory.self:
        return const Color(0xFF0D9488);
      case KinshipEdgeCategory.parent:
        return const Color(0xFF3B82F6);
      case KinshipEdgeCategory.child:
        return const Color(0xFFEC4899);
      case KinshipEdgeCategory.sibling:
        return const Color(0xFF8B5CF6);
      case KinshipEdgeCategory.spouse:
        return const Color(0xFFF97316);
      case KinshipEdgeCategory.grandparent:
        return const Color(0xFF6366F1);
      case KinshipEdgeCategory.auntUncle:
        return const Color(0xFF06B6D4);
      case KinshipEdgeCategory.cousin:
        return const Color(0xFF10B981);
      case KinshipEdgeCategory.inLaw:
        return const Color(0xFFF59E0B);
      case KinshipEdgeCategory.extended:
        return const Color(0xFF64748B);
      case KinshipEdgeCategory.indirect:
        return const Color(0xFF8A7A72);
    }
  }

  double _alphaForCategory(KinshipEdgeCategory category) {
    switch (category) {
      case KinshipEdgeCategory.self:
        return 1.0;
      case KinshipEdgeCategory.parent:
      case KinshipEdgeCategory.child:
      case KinshipEdgeCategory.spouse:
        return 0.85;
      case KinshipEdgeCategory.sibling:
      case KinshipEdgeCategory.grandparent:
        return 0.75;
      case KinshipEdgeCategory.auntUncle:
      case KinshipEdgeCategory.cousin:
      case KinshipEdgeCategory.inLaw:
        return 0.7;
      case KinshipEdgeCategory.extended:
        return 0.45;
      case KinshipEdgeCategory.indirect:
        return 0.5;
    }
  }

  void _drawEdge({
    required Canvas canvas,
    required EdgeData edge,
    required Offset fromPos,
    required Offset toPos,
    required bool isSelected,
    required KinshipEdgeCategory category,
    required bool isDimmed,
    required bool isConnectedToHovered,
  }) {
    final style = KinshipEdgeStyleResolver.styleForCategory(category);
    // v52.8: Inline color literals to defeat dart2js tree-shaking.
    final baseColor = _colorForCategory(category);
    final midpointColor = category == KinshipEdgeCategory.spouse
        ? const Color(0xFFEC4899) // PINK heart
        : baseColor;
    final defaultAlpha = _alphaForCategory(category);
    final (start, end) = _computeEndpoints(fromPos, toPos, category);

    // Resolve final color & stroke width.
    Color edgeColor;
    double strokeWidth;
    bool isSolid;

    if (isSelected) {
      edgeColor = baseColor;
      strokeWidth = _selectedStrokeWidth;
      isSolid = true;
    } else if (hoveredNodeId != null && isConnectedToHovered) {
      edgeColor = baseColor;
      strokeWidth = _hoveredConnectedStrokeWidth;
      isSolid = true;
      edgeColor = edgeColor.withValues(alpha: _hoveredConnectedAlpha);
    } else if (hoveredNodeId != null && !isConnectedToHovered) {
      edgeColor = baseColor.withValues(alpha: _hoveredDimmedAlpha);
      strokeWidth = _defaultStrokeWidth;
      isSolid = false;
    } else {
      edgeColor = baseColor.withValues(alpha: defaultAlpha);
      strokeWidth = _defaultStrokeWidth;
      isSolid = !style.isDashed;
    }

    if (isDimmed) {
      edgeColor = edgeColor.withValues(alpha: _dimmedAlpha);
    }

    final paint = Paint()
      ..color = edgeColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Glow paint.
    final glowPaint = Paint()
      ..color = edgeColor.withValues(alpha: isSelected ? 0.35 : 0.20)
      ..strokeWidth = strokeWidth + 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    // ── Draw line path based on resolved line shape ───────────────
    _drawLineForShape(
      canvas: canvas,
      start: start,
      end: end,
      style: style,
      paint: paint,
      glowPaint: glowPaint,
      isSolid: isSolid,
    );

    // ── Midpoint indicator ────────────────────────────────────────
    final showMidpoint = !_isMinimal && !isDimmed;
    final showMidpointForHover =
        hoveredNodeId == null || isConnectedToHovered;

    if (showMidpoint && showMidpointForHover) {
      final midpoint = _computeMidpoint(start, end, style.lineShape);
      switch (style.midpointSymbol) {
        case KinshipMidpointSymbol.heart:
          // v89: skip the glow halo when zoomed out for crisp rendering.
          _drawHeart(canvas, midpoint, midpointColor,
              compact: zoomLevel < _lodLabelZoom);
          break;
        case KinshipMidpointSymbol.dot:
          _drawDot(canvas, midpoint, midpointColor);
          break;
        case KinshipMidpointSymbol.none:
          break;
      }
    }

    // ── Edge label on hover ───────────────────────────────────────
    if (_showLabels &&
        hoveredNodeId != null &&
        isConnectedToHovered &&
        !isSelected &&
        !isDimmed) {
      final midpoint = _computeMidpoint(start, end, style.lineShape);
      final edgeLabel =
          edge.displayLabel ?? _formatKey(edge.relationshipKey);
      _drawEdgeLabel(canvas, midpoint, edgeLabel);
    }
  }

  // ── Line-shape dispatch ────────────────────────────────────────────

  void _drawLineForShape({
    required Canvas canvas,
    required Offset start,
    required Offset end,
    required KinshipEdgeStyle style,
    required Paint paint,
    required Paint glowPaint,
    required bool isSolid,
  }) {
    // In minimal LOD: always straight lines.
    if (_isMinimal) {
      if (isSolid) {
        canvas.drawLine(start, end, glowPaint);
        canvas.drawLine(start, end, paint);
      } else {
        _drawDashedLine(canvas, start, end, glowPaint,
            dashArray: style.dashPattern.isEmpty
                ? const [4.0, 4.0]
                : style.dashPattern);
        _drawDashedLine(canvas, start, end, paint,
            dashArray: style.dashPattern.isEmpty
                ? const [4.0, 4.0]
                : style.dashPattern);
      }
      return;
    }

    switch (style.lineShape) {
      case KinshipLineShape.dashedArc:
        _drawSiblingArc(canvas, start, end, glowPaint);
        _drawSiblingArc(canvas, start, end, paint,
            dashArray: style.dashPattern.isEmpty
                ? const [6.0, 4.0]
                : style.dashPattern);
        break;

      case KinshipLineShape.solidBezier:
        _drawBezierCurve(canvas, start, end, glowPaint);
        _drawBezierCurve(canvas, start, end, paint);
        break;

      case KinshipLineShape.solidExtendedBezier:
        _drawExtendedBezier(canvas, start, end, glowPaint);
        _drawExtendedBezier(canvas, start, end, paint);
        break;

      case KinshipLineShape.wideArcBezier:
        _drawWideArcBezier(canvas, start, end, glowPaint);
        _drawWideArcBezier(canvas, start, end, paint);
        break;

      case KinshipLineShape.dashedShallowS:
        final dash = style.dashPattern.isEmpty
            ? const [5.0, 4.0]
            : style.dashPattern;
        _drawShallowSBezier(canvas, start, end, glowPaint);
        _drawShallowSBezier(canvas, start, end, paint, dashArray: dash);
        break;

      case KinshipLineShape.dashedStraight:
        final dash = style.dashPattern.isEmpty
            ? const [6.0, 4.0]
            : style.dashPattern;
        _drawDashedLine(canvas, start, end, glowPaint, dashArray: dash);
        _drawDashedLine(canvas, start, end, paint, dashArray: dash);
        break;

      case KinshipLineShape.dashedDefault:
        final dash = style.dashPattern.isEmpty
            ? const [4.0, 4.0]
            : style.dashPattern;
        _drawDashedLine(canvas, start, end, glowPaint, dashArray: dash);
        _drawDashedLine(canvas, start, end, paint, dashArray: dash);
        break;
    }
  }

  // ── Endpoint Computation ───────────────────────────────────────────

  (Offset, Offset) _computeEndpoints(
    Offset fromPos,
    Offset toPos,
    KinshipEdgeCategory category,
  ) {
    if (category == KinshipEdgeCategory.spouse ||
        category == KinshipEdgeCategory.inLaw) {
      if (fromPos.dx <= toPos.dx) {
        return (
          Offset(fromPos.dx + nodeWidth / 2, fromPos.dy),
          Offset(toPos.dx - nodeWidth / 2, toPos.dy),
        );
      } else {
        return (
          Offset(fromPos.dx - nodeWidth / 2, fromPos.dy),
          Offset(toPos.dx + nodeWidth / 2, toPos.dy),
        );
      }
    }

    if (fromPos.dy <= toPos.dy) {
      return (
        Offset(fromPos.dx, fromPos.dy + nodeHeight / 2),
        Offset(toPos.dx, toPos.dy - nodeHeight / 2),
      );
    } else {
      return (
        Offset(fromPos.dx, fromPos.dy - nodeHeight / 2),
        Offset(toPos.dx, toPos.dy + nodeHeight / 2),
      );
    }
  }

  // ── Midpoint Computation ───────────────────────────────────────────

  Offset _computeMidpoint(
    Offset start,
    Offset end,
    KinshipLineShape shape,
  ) {
    switch (shape) {
      case KinshipLineShape.dashedArc:
        final arcHeight = (end.dx - start.dx).abs() * 0.25 + 30.0;
        final midX = (start.dx + end.dx) / 2;
        final cpY = start.dy - arcHeight;
        return Offset(
          midX,
          0.25 * start.dy + 0.5 * cpY + 0.25 * end.dy,
        );

      case KinshipLineShape.solidExtendedBezier:
        final dy = end.dy - start.dy;
        final cp1 = Offset(start.dx, start.dy + dy * 0.4);
        final cp2 = Offset(end.dx, start.dy + dy * 0.6);
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

      case KinshipLineShape.wideArcBezier:
        final dx = end.dx - start.dx;
        final dy = end.dy - start.dy;
        final offset = dx.abs() * 0.3 + 40.0;
        final sign = dx >= 0 ? 1.0 : -1.0;
        final cp1 = Offset(start.dx + offset * sign, start.dy + dy * 0.33);
        final cp2 = Offset(end.dx - offset * sign, start.dy + dy * 0.67);
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

      case KinshipLineShape.dashedShallowS:
        final midY = (start.dy + end.dy) / 2;
        final dxOffset = (end.dx - start.dx) * 0.2;
        final cp1 = Offset(start.dx + dxOffset, midY - 15);
        final cp2 = Offset(end.dx - dxOffset, midY + 15);
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

      case KinshipLineShape.solidBezier:
      case KinshipLineShape.dashedStraight:
      case KinshipLineShape.dashedDefault:
        return Offset(
          (start.dx + end.dx) / 2,
          (start.dy + end.dy) / 2,
        );
    }
  }

  // ── Sibling Arc ────────────────────────────────────────────────────

  void _drawSiblingArc(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint, {
    List<double>? dashArray,
  }) {
    final midX = (start.dx + end.dx) / 2;
    final arcHeight = (end.dx - start.dx).abs() * 0.25 + 30.0;
    final controlPoint = Offset(midX, start.dy - arcHeight);
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..quadraticBezierTo(
        controlPoint.dx,
        controlPoint.dy,
        end.dx,
        end.dy,
      );
    if (dashArray == null || dashArray.isEmpty) {
      canvas.drawPath(path, paint);
      return;
    }
    _drawDashedPath(canvas, path, paint, dashArray);
  }

  // ── Bezier Curve (parent / child) ──────────────────────────────────

  void _drawBezierCurve(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint,
  ) {
    final midY = (start.dy + end.dy) / 2;
    final cp1 = Offset(start.dx, midY);
    final cp2 = Offset(end.dx, midY);
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, end.dx, end.dy);
    canvas.drawPath(path, paint);
  }

  // ── Extended Bezier (grandparent) ──────────────────────────────────

  void _drawExtendedBezier(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint,
  ) {
    final dy = end.dy - start.dy;
    final cp1 = Offset(start.dx, start.dy + dy * 0.4);
    final cp2 = Offset(end.dx, start.dy + dy * 0.6);
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, end.dx, end.dy);
    canvas.drawPath(path, paint);
  }

  // ── Wide-Arc Bezier (cousin) ───────────────────────────────────────

  void _drawWideArcBezier(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint,
  ) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final offset = dx.abs() * 0.3 + 40.0;
    final sign = dx >= 0 ? 1.0 : -1.0;
    final cp1 = Offset(start.dx + offset * sign, start.dy + dy * 0.33);
    final cp2 = Offset(end.dx - offset * sign, start.dy + dy * 0.67);
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, end.dx, end.dy);
    canvas.drawPath(path, paint);
  }

  // ── Shallow S-Curve (aunt/uncle) ───────────────────────────────────

  void _drawShallowSBezier(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint, {
    List<double>? dashArray,
  }) {
    final midY = (start.dy + end.dy) / 2;
    final dxOffset = (end.dx - start.dx) * 0.2;
    final cp1 = Offset(start.dx + dxOffset, midY - 15);
    final cp2 = Offset(end.dx - dxOffset, midY + 15);
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, end.dx, end.dy);
    if (dashArray == null || dashArray.isEmpty) {
      canvas.drawPath(path, paint);
      return;
    }
    _drawDashedPath(canvas, path, paint, dashArray);
  }

  // ── Dashed Line (straight) ─────────────────────────────────────────

  void _drawDashedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint, {
    List<double> dashArray = const [4.0, 4.0],
  }) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length == 0) return;

    final unitDx = dx / length;
    final unitDy = dy / length;

    final dashWidth = dashArray[0];
    final dashGap = dashArray.length > 1 ? dashArray[1] : dashArray[0];

    double covered = 0;
    bool draw = true;
    while (covered < length) {
      final segmentLength = draw ? dashWidth : dashGap;
      final endCovered = (covered + segmentLength).clamp(0.0, length);

      if (draw) {
        canvas.drawLine(
          Offset(start.dx + unitDx * covered, start.dy + unitDy * covered),
          Offset(start.dx + unitDx * endCovered,
              start.dy + unitDy * endCovered),
          paint,
        );
      }

      covered = endCovered;
      draw = !draw;
    }
  }

  // ── Dashed Path ────────────────────────────────────────────────────

  void _drawDashedPath(
    Canvas canvas,
    Path path,
    Paint paint,
    List<double> dashArray,
  ) {
    final dashWidth = dashArray[0];
    final dashGap = dashArray.length > 1 ? dashArray[1] : dashArray[0];

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

  // ── Midpoint Drawing ───────────────────────────────────────────────

  void _drawDot(Canvas canvas, Offset center, Color color) {
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, _dotGlowRadius, glowPaint);

    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, _dotRadius, dotPaint);
  }

  // v89: Delegates to [HeartShape.drawHeart] so this painter produces
  // the EXACT same heart as the EdgeDotWidget overlay (Layer 2). The
  // old implementation drew two overlapping circles + a tiny triangle
  // (total ~14×12 px) which visually collapsed to a pink blob at any
  // zoomed-out view. The new implementation builds the heart from two
  // cubic bezier curves — a proper, recognizable heart silhouette.
  //
  // [compact] is true when zoomed out (< 0.6) so we skip the glow
  // halo and keep the heart crisp on dense graphs.
  void _drawHeart(Canvas canvas, Offset center, Color color,
      {bool compact = false}) {
    HeartShape.drawHeart(
      canvas: canvas,
      center: center,
      size: _heartSize,
      color: color,
      compact: compact,
    );
  }

  // ── Edge Label Drawing ─────────────────────────────────────────────

  static String _formatKey(String key) {
    return key
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  void _drawEdgeLabel(Canvas canvas, Offset midpoint, String label) {
    final textSpan = TextSpan(
      text: label,
      style: const TextStyle(
        color: Color(0xB3FFFFFF),
        fontSize: 10.0,
        fontWeight: FontWeight.w500,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    final textWidth = textPainter.width;
    final textHeight = textPainter.height;

    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: midpoint,
        width: textWidth + 12.0,
        height: textHeight + 6.0,
      ),
      const Radius.circular(4.0),
    );

    final bgPaint = Paint()
      ..color = const Color(0xFF202338)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(rect, bgPaint);

    final textOffset = Offset(
      midpoint.dx - textWidth / 2,
      midpoint.dy - textHeight / 2,
    );
    textPainter.paint(canvas, textOffset);
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

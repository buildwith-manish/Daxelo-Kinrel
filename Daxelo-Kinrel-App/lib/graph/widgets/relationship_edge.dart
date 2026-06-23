// lib/graph/widgets/relationship_edge.dart
//
// DAXELO KINREL — Relationship Edge CustomPainter (v2)
//
// v2 (2026-06-23): Delegates all color / line-shape / midpoint decisions
// to the central KinshipEdgeStyleResolver in lib/core/kinship/. This
// painter is now purely a RENDERER — no per-painter color tables, no
// per-painter dash patterns, no per-category midpoint logic. Every
// visual decision flows through one classifier so the entire app stays
// consistent.
//
// What changed visually:
//   • Parent edges now render BLUE (#3B82F6) instead of orange.
//   • Child edges now render PINK (#EC4899).
//   • Sibling edges stay PURPLE, dashed arc above.
//   • Spouse edges: ORANGE dashed line + PINK heart (heart color no
//     longer matches the edge color — it's always pink per spec §4).
//   • Grandparent edges: INDIGO solid extended bezier.
//   • Aunt/Uncle edges: CYAN dashed shallow S-curve.
//   • Cousin edges: EMERALD wide-arc bezier.
//   • In-Law edges: AMBER dashed straight.
//   • Extended edges: SLATE dashed at 0.45 alpha.
//   • Indirect edges: GRAY dashed, NO dot (text label only).
//
// EVERY edge category (except indirect) now has a midpoint dot — this
// is the central spec change. Previously only parent/child/grandparent
// got dots; now sibling, aunt/uncle, cousin, in-law, and extended all
// get dots too, matching spec §"The Midpoint Dot — Why Every Edge
// Needs One".
//
// Public API (preserved for backward compatibility):
//   • enum EdgeCategory                 — alias of KinshipEdgeCategory
//   • class EdgeStyleResolver           — delegates to KinshipEdgeStyleResolver
//   • class RelationshipEdge            — CustomPainter (unchanged signature)
//   • extension GraphEdgeDataExt        — isIndirectConnection getter
//
// Architecture:
//   GraphEdgeData (from repo)
//     → relationshipKey
//       → KinshipEdgeClassifier.classify(key)
//         → KinshipEdgeCategory
//           → KinshipEdgeStyleResolver.styleForCategory(cat)
//             → KinshipEdgeStyle (color, alpha, lineShape, dashPattern,
//                                  midpointSymbol, midpointColor)
//               → RelationshipEdge.paint() reads style and draws
//
// LOD (level of detail):
//   • zoom < 0.4  : minimal mode — straight lines only, no dots / hearts
//   • zoom >= 0.4 : full mode — curves with midpoint indicators
//
// Generation dimming:
//   When [highlightedGeneration] is set, edges where BOTH endpoints are
//   NOT in that generation are drawn at 0.30 alpha.
//
// Relationship label:
//   Always rendered at the midpoint (fade-in from zoom 0.15 → 0.35).
//   Background is the edge color at 95% alpha, white text, rounded pill.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/constants/brand_colors.dart';
import '../../core/kinship/kinship_edge_style.dart';
import '../data/family_graph_repository.dart' show GraphEdgeData;
import 'graph_node.dart';

// ═══════════════════════════════════════════════════════════════════════
// EDGE EXTENSION (preserved API)
// ═══════════════════════════════════════════════════════════════════════

extension GraphEdgeDataExt on GraphEdgeData {
  /// Whether this is an indirect connection (through a blocked member).
  bool get isIndirectConnection => relationshipKey.startsWith('indirect_');
}

// ═══════════════════════════════════════════════════════════════════════
// EDGE CATEGORY (preserved alias)
// ═══════════════════════════════════════════════════════════════════════

/// Preserved alias so existing call sites keep compiling.
/// New code should use [KinshipEdgeCategory] directly.
typedef EdgeCategory = KinshipEdgeCategory;

// ═══════════════════════════════════════════════════════════════════════
// EDGE STYLE RESOLVER (preserved delegating shim)
// ═══════════════════════════════════════════════════════════════════════

/// Thin shim that delegates every call to [KinshipEdgeStyleResolver] /
/// [KinshipEdgeClassifier]. Existing call sites that use
/// `EdgeStyleResolver.colorFor(category)` etc. keep working unchanged.
class EdgeStyleResolver {
  EdgeStyleResolver._();

  /// Maps relationship keys to their edge category.
  static KinshipEdgeCategory categoryFor(String relationshipKey) =>
      KinshipEdgeClassifier.classify(relationshipKey);

  /// Returns the primary color for an edge category.
  static Color colorFor(KinshipEdgeCategory category) =>
      KinshipEdgeStyleResolver.styleForCategory(category).color;

  /// Returns the default alpha for an edge category.
  static double defaultAlphaFor(KinshipEdgeCategory category) =>
      KinshipEdgeStyleResolver.styleForCategory(category).defaultAlpha;

  /// Whether the edge should be drawn as a dashed line.
  static bool isDashed(KinshipEdgeCategory category) =>
      KinshipEdgeStyleResolver.styleForCategory(category).isDashed;

  /// Whether the edge should have a heart icon at midpoint (spouse).
  static bool hasHeartMidpoint(KinshipEdgeCategory category) =>
      KinshipEdgeStyleResolver.styleForCategory(category).midpointSymbol ==
      KinshipMidpointSymbol.heart;

  /// Whether the edge should have a glow dot at midpoint.
  ///
  /// Per spec: every category except indirect gets a dot.
  static bool hasDotMidpoint(KinshipEdgeCategory category) =>
      KinshipEdgeStyleResolver.styleForCategory(category).midpointSymbol ==
      KinshipMidpointSymbol.dot;

  /// Whether the edge should have a lock icon at midpoint (private).
  static bool hasLockMidpoint(bool isPrivate) => isPrivate;

  /// Dash pattern for half-sibling edges (dotted).
  static const List<double> halfSiblingDash = [2.0, 4.0];

  /// Default dash pattern.
  static const List<double> defaultDash = [4.0, 4.0];

  /// Sibling dash pattern.
  static const List<double> siblingDash = [6.0, 4.0];
}

// ═══════════════════════════════════════════════════════════════════════
// RELATIONSHIP EDGE PAINTER
// ═══════════════════════════════════════════════════════════════════════

/// CustomPainter that renders relationship edges between person nodes.
///
/// All visual decisions (color, line shape, dash pattern, midpoint
/// symbol, midpoint color) flow from [KinshipEdgeStyleResolver]. This
/// painter is responsible ONLY for translating those decisions into
/// canvas draw calls.
class RelationshipEdge extends CustomPainter {
  RelationshipEdge({
    required this.positions,
    required this.edges,
    this.selectedEdgeId,
    this.zoomLevel = 1.0,
    this.nodeWidth = 72.0,
    this.nodeHeight = 72.0,
    this.generationMap,
    this.highlightedGeneration,
    this.anonymousNodeIds = const {},
    this.blockedNodeIds = const {},
  });

  final Map<String, Offset> positions;
  final List<GraphEdgeData> edges;
  final String? selectedEdgeId;
  final double zoomLevel;
  final double nodeWidth;
  final double nodeHeight;
  final Map<String, int>? generationMap;
  final int? highlightedGeneration;
  final Set<String> anonymousNodeIds;
  final Set<String> blockedNodeIds;

  // ── Paint Constants ────────────────────────────────────────────────
  static const double _defaultStrokeWidth = 2.0;
  static const double _selectedStrokeWidth = 2.5;
  static const double _dimmedAlpha = 0.30;

  // ── Midpoint Indicator Constants ──────────────────────────────────
  static const double _dotRadius = 5.0;
  static const double _dotGlowRadius = 9.0;
  static const double _heartSize = 14.0;
  static const double _lockSize = 12.0;

  // ── LOD Thresholds ─────────────────────────────────────────────────
  static const double _lodMinimalZoom = 0.4;
  bool get _isMinimal => zoomLevel < _lodMinimalZoom;

  // ── Paint ──────────────────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    for (final edge in edges) {
      if (blockedNodeIds.contains(edge.sourceId) ||
          blockedNodeIds.contains(edge.targetId)) {
        continue;
      }

      final fromPos = positions[edge.sourceId];
      final toPos = positions[edge.targetId];
      if (fromPos == null || toPos == null) continue;

      final isSelected = edge.id == selectedEdgeId;
      final category = edge.isIndirectConnection
          ? KinshipEdgeCategory.indirect
          : KinshipEdgeClassifier.classify(edge.relationshipKey);
      final isDimmed = _shouldDimEdge(edge);
      final isHalfSibling =
          edge.relationshipKey == 'half_brother' ||
              edge.relationshipKey == 'half_sister';

      _drawEdge(
        canvas: canvas,
        fromPos: fromPos,
        toPos: toPos,
        isSelected: isSelected,
        category: category,
        isDimmed: isDimmed,
        isHalfSibling: isHalfSibling,
        isPrivate: edge.isPrivate,
        isIndirect: edge.isIndirectConnection,
        relationshipKey: edge.relationshipKey,
        sourceId: edge.sourceId,
        targetId: edge.targetId,
      );
    }
  }

  // ── Dimming Check ──────────────────────────────────────────────────

  bool _shouldDimEdge(GraphEdgeData edge) {
    if (highlightedGeneration == null || generationMap == null) return false;
    final fromGen = generationMap![edge.sourceId];
    final toGen = generationMap![edge.targetId];
    if (fromGen == null || toGen == null) return false;
    return fromGen != highlightedGeneration &&
        toGen != highlightedGeneration;
  }

  // ── Edge Drawing ───────────────────────────────────────────────────

  void _drawEdge({
    required Canvas canvas,
    required Offset fromPos,
    required Offset toPos,
    required bool isSelected,
    required KinshipEdgeCategory category,
    required bool isDimmed,
    required bool isHalfSibling,
    required bool isPrivate,
    required bool isIndirect,
    required String relationshipKey,
    required String sourceId,
    required String targetId,
  }) {
    final style = KinshipEdgeStyleResolver.styleForCategory(category);
    final (start, end) = _computeEndpoints(fromPos, toPos, category);

    // Resolve final color and stroke width.
    Color edgeColor;
    double strokeWidth;
    if (isSelected) {
      edgeColor = style.color;
      strokeWidth = _selectedStrokeWidth;
    } else {
      edgeColor = style.color.withValues(alpha: style.defaultAlpha);
      strokeWidth = _defaultStrokeWidth;
    }

    // Anonymous endpoint: reduce opacity.
    if (anonymousNodeIds.contains(sourceId) ||
        anonymousNodeIds.contains(targetId)) {
      edgeColor = edgeColor.withValues(alpha: edgeColor.a * 0.5);
    }

    // Generation dimming.
    if (isDimmed) {
      edgeColor = edgeColor.withValues(alpha: _dimmedAlpha);
    }

    final paint = Paint()
      ..color = edgeColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Glow paint (soft halo behind every edge — keeps the Kinrel look).
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
      isHalfSibling: isHalfSibling,
    );

    // ── Draw midpoint indicator (skip in minimal LOD or when dimmed) ─
    if (!_isMinimal && !isDimmed) {
      final midpoint = _computeMidpoint(start, end, style.lineShape);

      // Lock icon takes priority over dot/heart (private relationship).
      if (EdgeStyleResolver.hasLockMidpoint(isPrivate)) {
        _drawLock(canvas, midpoint, edgeColor);
      } else {
        switch (style.midpointSymbol) {
          case KinshipMidpointSymbol.heart:
            // Spouse: ALWAYS pink, even though the edge is orange.
            _drawHeart(canvas, midpoint, style.midpointColor);
            break;
          case KinshipMidpointSymbol.dot:
            _drawDot(canvas, midpoint, style.midpointColor);
            break;
          case KinshipMidpointSymbol.none:
            // Indirect: no dot — only a text label below.
            break;
        }
      }

      if (isIndirect) {
        _drawIndirectLabel(canvas, midpoint, edgeColor);
      }

      // ── Relationship label on the edge midpoint ──────────────────
      // Fade in from zoom 0.15 → 0.35 so labels gracefully appear.
      final double labelOpacity =
          ((zoomLevel - 0.15) / (0.35 - 0.15)).clamp(0.0, 1.0);
      if (!isIndirect && zoomLevel >= 0.15) {
        _drawRelationshipLabel(
          canvas,
          midpoint,
          edgeColor,
          relationshipKey,
          opacity: labelOpacity,
        );
      }
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
    required bool isHalfSibling,
  }) {
    switch (style.lineShape) {
      case KinshipLineShape.dashedArc:
        // Sibling: dashed arc that bows ABOVE the nodes.
        final dash = isHalfSibling
            ? EdgeStyleResolver.halfSiblingDash
            : (style.dashPattern.isEmpty
                ? EdgeStyleResolver.siblingDash
                : style.dashPattern);
        _drawSiblingArc(canvas, start, end, glowPaint);
        _drawSiblingArc(canvas, start, end, paint, dashArray: dash);
        break;

      case KinshipLineShape.solidBezier:
        // Parent / child: solid smooth S-curve.
        _drawBezierCurve(canvas, start, end, glowPaint);
        _drawBezierCurve(canvas, start, end, paint);
        break;

      case KinshipLineShape.solidExtendedBezier:
        // Grandparent: solid extended bezier with longer control spread.
        _drawExtendedBezier(canvas, start, end, glowPaint);
        _drawExtendedBezier(canvas, start, end, paint);
        break;

      case KinshipLineShape.wideArcBezier:
        // Cousin: wide-arc cubic bezier (control points pushed far apart).
        _drawWideArcBezier(canvas, start, end, glowPaint);
        _drawWideArcBezier(canvas, start, end, paint);
        break;

      case KinshipLineShape.dashedShallowS:
        // Aunt/Uncle: dashed shallow S-curve.
        final dash = style.dashPattern.isEmpty
            ? EdgeStyleResolver.defaultDash
            : style.dashPattern;
        _drawShallowSBezier(canvas, start, end, glowPaint);
        _drawShallowSBezier(canvas, start, end, paint, dashArray: dash);
        break;

      case KinshipLineShape.dashedStraight:
        // Spouse / In-Law: dashed straight horizontal line.
        final dash = style.dashPattern.isEmpty
            ? EdgeStyleResolver.siblingDash
            : style.dashPattern;
        _drawDashedLine(canvas, start, end, glowPaint, dashArray: dash);
        _drawDashedLine(canvas, start, end, paint, dashArray: dash);
        break;

      case KinshipLineShape.dashedDefault:
        // Extended / Indirect: dashed default line.
        final dash = isHalfSibling
            ? EdgeStyleResolver.halfSiblingDash
            : (style.dashPattern.isEmpty
                ? EdgeStyleResolver.defaultDash
                : style.dashPattern);
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
      // Horizontal connector between side edges of nodes.
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

    // Vertical-ish edges: bottom of upper → top of lower.
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

  /// Computes the t=0.5 point of an edge so the midpoint indicator
  /// (dot / heart / label) lines up with the visible curve.
  Offset _computeMidpoint(
    Offset start,
    Offset end,
    KinshipLineShape shape,
  ) {
    switch (shape) {
      case KinshipLineShape.dashedArc:
        // Sibling quadratic bezier: B(0.5) = 0.25·P0 + 0.5·P1 + 0.25·P2
        final arcHeight = (end.dx - start.dx).abs() * 0.25 + 30.0;
        final midX = (start.dx + end.dx) / 2;
        final cpY = start.dy - arcHeight;
        return Offset(
          midX,
          0.25 * start.dy + 0.5 * cpY + 0.25 * end.dy,
        );

      case KinshipLineShape.solidExtendedBezier:
        // Extended cubic bezier — control points pushed further apart.
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
        // Wide-arc cubic bezier with offset control points.
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
        // Shallow S-curve — cubic with small vertical offset on controls.
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
        // For solid bezier (control points at midY) and straight lines,
        // the t=0.5 point is the linear midpoint.
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

    // Manual dash along the path (PathMetric.extractPath is available
    // in all current Flutter versions; we use tangent-based fallback
    // for ancient versions).
    final dashedPath = Path();
    for (final ui.PathMetric metric in path.computeMetrics()) {
      double distance = 0.0;
      bool draw = true;
      final totalLen = metric.length;
      while (distance < totalLen) {
        final double len = draw
            ? dashArray.first
            : (dashArray.length > 1 ? dashArray[1] : dashArray.first);
        final double next = (distance + len).clamp(0.0, totalLen);
        if (draw && next > distance) {
          final tangent = metric.getTangentForOffset(distance);
          if (tangent != null) {
            dashedPath.moveTo(tangent.position.dx, tangent.position.dy);
            final endTangent = metric.getTangentForOffset(next);
            if (endTangent != null) {
              dashedPath.lineTo(endTangent.position.dx, endTangent.position.dy);
            }
          }
        }
        distance = next;
        draw = !draw;
      }
    }
    canvas.drawPath(dashedPath, paint);
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
    List<double> dashArray = EdgeStyleResolver.defaultDash,
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

  // ── Dashed Path (along arbitrary Path) ─────────────────────────────

  void _drawDashedPath(
    Canvas canvas,
    Path path,
    Paint paint,
    List<double> dashArray,
  ) {
    final dashWidth = dashArray[0];
    final dashGap = dashArray.length > 1 ? dashArray[1] : dashArray[0];

    for (final metric in path.computeMetrics()) {
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
    // Glow halo
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, _dotGlowRadius, glowPaint);

    // Solid dot
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, _dotRadius, dotPaint);
  }

  void _drawHeart(Canvas canvas, Offset center, Color color) {
    final heartPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final s = _heartSize;
    final circleRadius = s / 4;

    final leftCircleCenter = Offset(
        center.dx - circleRadius * 0.7, center.dy - circleRadius * 0.4);
    final rightCircleCenter = Offset(
        center.dx + circleRadius * 0.7, center.dy - circleRadius * 0.4);

    canvas.drawCircle(leftCircleCenter, circleRadius, heartPaint);
    canvas.drawCircle(rightCircleCenter, circleRadius, heartPaint);

    final halfS = s / 2;
    final path = Path()
      ..moveTo(leftCircleCenter.dx - circleRadius * 0.7,
          leftCircleCenter.dy + circleRadius * 0.2)
      ..lineTo(rightCircleCenter.dx + circleRadius * 0.7,
          rightCircleCenter.dy + circleRadius * 0.2)
      ..lineTo(center.dx, center.dy + halfS * 0.75)
      ..close();

    canvas.drawPath(path, heartPaint);
  }

  void _drawLock(Canvas canvas, Offset center, Color color) {
    final lockPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    final bodyRect = Rect.fromCenter(
      center: Offset(center.dx, center.dy + 2),
      width: _lockSize * 0.7,
      height: _lockSize * 0.5,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, const Radius.circular(2.0)),
      fillPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, const Radius.circular(2.0)),
      lockPaint,
    );

    final shackleRect = Rect.fromCenter(
      center: Offset(center.dx, center.dy - 1),
      width: _lockSize * 0.4,
      height: _lockSize * 0.35,
    );
    canvas.drawArc(shackleRect, math.pi, math.pi, false, lockPaint);
  }

  void _drawIndirectLabel(Canvas canvas, Offset center, Color color) {
    const textStyle = TextStyle(
      fontSize: 8.0,
      fontWeight: FontWeight.w500,
      color: KinrelColors.textDim,
    );
    final textSpan = TextSpan(text: 'indirect', style: textStyle);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();
    final offset = Offset(
      center.dx - textPainter.width / 2,
      center.dy + 8.0,
    );
    textPainter.paint(canvas, offset);
  }

  void _drawRelationshipLabel(
    Canvas canvas,
    Offset center,
    Color edgeColor,
    String relationshipKey, {
    double opacity = 1.0,
  }) {
    if (relationshipKey.isEmpty || relationshipKey == 'unknown') return;
    if (opacity <= 0.0) return;

    final formatted = relationshipKey
        .split('_')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');

    const fontSize = 11.0;
    const horizontalPadding = 6.0;
    const verticalPadding = 3.0;

    final textSpan = TextSpan(
      text: formatted,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        color: Colors.white.withValues(alpha: opacity),
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();

    final pillWidth = textPainter.width + horizontalPadding * 2;
    final pillHeight = textPainter.height + verticalPadding * 2;
    final pillRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center,
        width: pillWidth,
        height: pillHeight,
      ),
      const Radius.circular(8.0),
    );

    final bgPaint = Paint()
      ..color = edgeColor.withValues(alpha: 0.95 * opacity)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(pillRect, bgPaint);

    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.25 * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    canvas.drawRRect(pillRect, borderPaint);

    final textOffset = Offset(
      center.dx - textPainter.width / 2,
      center.dy - textPainter.height / 2,
    );
    textPainter.paint(canvas, textOffset);
  }

  // ── Repaint ────────────────────────────────────────────────────────

  @override
  bool shouldRepaint(covariant RelationshipEdge oldDelegate) {
    return !identical(edges, oldDelegate.edges) ||
        !identical(positions, oldDelegate.positions) ||
        selectedEdgeId != oldDelegate.selectedEdgeId ||
        zoomLevel != oldDelegate.zoomLevel ||
        highlightedGeneration != oldDelegate.highlightedGeneration;
  }
}

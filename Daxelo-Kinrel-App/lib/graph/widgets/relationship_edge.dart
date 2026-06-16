// lib/graph/widgets/relationship_edge.dart
//
// DAXELO KINREL — Relationship Edge CustomPainter
//
// Renders all relationship edge types in the family graph:
//   Parent→Child: Solid vertical bezier, horizontal offset for multiple children
//   Spouse→Spouse: Marriage connector (horizontal + ring icon at midpoint)
//   Sibling→Sibling: Dashed curved arc above sibling group
//   Extended Family: Curved bezier avoiding parent-child line crossings
//
// Visual specs:
//   Default: dashed [4,4], orange 45% alpha, stroke 1.5
//   Selected: solid, full orange, stroke 2.5
//   Spouse: heart icon at midpoint
//   Parent/child: glow dot at midpoint
//   LOD: skip dots at zoom < 0.4
//   Generation dimming: both endpoints NOT highlighted → 0.15 alpha
//
// Edge category styling:
//   Parent (~45): Solid, top-to-bottom bezier, orange
//   Child (~45): Solid, bottom-to-top bezier, orange
//   Sibling (~120): Dashed, curved arc, purple
//   Spouse (~25): Marriage connector, horizontal, orange with heart
//   Grandparent (~80): Solid, extended bezier, indigo
//   Aunt/Uncle (~150): Dashed, curved, cyan
//   Cousin (~800): Curved, extended, emerald
//   In-Law (~200): Marriage variant, amber
//   Extended (~3835): Curved, low-opacity, slate
//
// Special edge types:
//   Divorced spouse: dashed connector with split ring
//   Half-sibling: dotted line with different dash pattern
//   Private relationship: lock icon at midpoint (if user is participant)
//   Indirect connection (blocked): dashed line, gray, "indirect" label

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/constants/brand_colors.dart';
import '../data/family_graph_repository.dart' show GraphEdgeData;
import 'graph_node.dart';

// ═══════════════════════════════════════════════════════════════════════
// EDGE EXTENSION
// ═══════════════════════════════════════════════════════════════════════

/// Extension on GraphEdgeData to add indirect connection tracking.
extension GraphEdgeDataExt on GraphEdgeData {
  /// Whether this is an indirect connection (through a blocked member).
  /// Stored in the relationshipKey as a prefix convention.
  bool get isIndirectConnection => relationshipKey.startsWith('indirect_');
}

// ═══════════════════════════════════════════════════════════════════════
// EDGE CATEGORY
// ═══════════════════════════════════════════════════════════════════════

/// Categorizes relationship edges for styling.
enum EdgeCategory {
  /// Parent → child (solid vertical bezier, orange).
  parent,

  /// Child → parent (solid vertical bezier, orange).
  child,

  /// Sibling connections (dashed curved arc, purple).
  sibling,

  /// Spouse/partner connections (marriage connector, orange with heart).
  spouse,

  /// Grandparent connections (solid extended bezier, indigo).
  grandparent,

  /// Aunt/uncle connections (dashed curved, cyan).
  auntUncle,

  /// Cousin connections (curved extended, emerald).
  cousin,

  /// In-law connections (marriage variant, amber).
  inLaw,

  /// Extended family (curved low-opacity, slate).
  extended,

  /// Indirect connection through blocked member (dashed gray).
  indirect,
}

// ═══════════════════════════════════════════════════════════════════════
// EDGE STYLE RESOLVER
// ═══════════════════════════════════════════════════════════════════════

/// Resolves edge category and styling from a relationship key.
class EdgeStyleResolver {
  EdgeStyleResolver._();

  /// Maps relationship keys to their edge category.
  static const Map<String, EdgeCategory> _categoryMap = {
    // Parent
    'parent': EdgeCategory.parent,
    'father': EdgeCategory.parent,
    'mother': EdgeCategory.parent,
    // Child
    'child': EdgeCategory.child,
    'son': EdgeCategory.child,
    'daughter': EdgeCategory.child,
    // Sibling
    'sibling': EdgeCategory.sibling,
    'brother': EdgeCategory.sibling,
    'sister': EdgeCategory.sibling,
    'half_brother': EdgeCategory.sibling,
    'half_sister': EdgeCategory.sibling,
    // Spouse
    'spouse': EdgeCategory.spouse,
    'husband': EdgeCategory.spouse,
    'wife': EdgeCategory.spouse,
    'partner': EdgeCategory.spouse,
    // Grandparent
    'grandparent': EdgeCategory.grandparent,
    'grandfather': EdgeCategory.grandparent,
    'grandmother': EdgeCategory.grandparent,
    // Aunt/Uncle
    'aunt': EdgeCategory.auntUncle,
    'uncle': EdgeCategory.auntUncle,
    'paternal_uncle': EdgeCategory.auntUncle,
    'paternal_aunt': EdgeCategory.auntUncle,
    'maternal_uncle': EdgeCategory.auntUncle,
    'maternal_aunt': EdgeCategory.auntUncle,
    // Cousin
    'cousin': EdgeCategory.cousin,
    'cousin_brother': EdgeCategory.cousin,
    'cousin_sister': EdgeCategory.cousin,
    // In-Law
    'father_in_law': EdgeCategory.inLaw,
    'mother_in_law': EdgeCategory.inLaw,
    'son_in_law': EdgeCategory.inLaw,
    'daughter_in_law': EdgeCategory.inLaw,
    'brother_in_law': EdgeCategory.inLaw,
    'sister_in_law': EdgeCategory.inLaw,
    // Extended
    'stepfather': EdgeCategory.extended,
    'stepmother': EdgeCategory.extended,
    'stepson': EdgeCategory.extended,
    'stepdaughter': EdgeCategory.extended,
    'stepbrother': EdgeCategory.extended,
    'stepsister': EdgeCategory.extended,
    // Indirect
    'indirect_connection': EdgeCategory.indirect,
  };

  /// Returns the edge category for a given relationship key.
  static EdgeCategory categoryFor(String relationshipKey) {
    return _categoryMap[relationshipKey] ?? EdgeCategory.extended;
  }

  /// Returns the primary color for an edge category.
  static Color colorFor(EdgeCategory category) {
    switch (category) {
      case EdgeCategory.parent:
        return RelationshipColors.parent;
      case EdgeCategory.child:
        return RelationshipColors.child;
      case EdgeCategory.sibling:
        return RelationshipColors.sibling;
      case EdgeCategory.spouse:
        return RelationshipColors.spouse;
      case EdgeCategory.grandparent:
        return RelationshipColors.grandparent;
      case EdgeCategory.auntUncle:
        return RelationshipColors.auntUncle;
      case EdgeCategory.cousin:
        return RelationshipColors.cousin;
      case EdgeCategory.inLaw:
        return RelationshipColors.inLaw;
      case EdgeCategory.extended:
        return RelationshipColors.extended;
      case EdgeCategory.indirect:
        return KinrelColors.textDim;
    }
  }

  /// Returns the default alpha for an edge category.
  static double defaultAlphaFor(EdgeCategory category) {
    switch (category) {
      case EdgeCategory.parent:
      case EdgeCategory.child:
        return 0.85;
      case EdgeCategory.spouse:
        return 0.85;
      case EdgeCategory.sibling:
        return 0.75;
      case EdgeCategory.grandparent:
        return 0.75;
      case EdgeCategory.auntUncle:
        return 0.7;
      case EdgeCategory.cousin:
        return 0.6;
      case EdgeCategory.inLaw:
        return 0.7;
      case EdgeCategory.extended:
        return 0.45;
      case EdgeCategory.indirect:
        return 0.5;
    }
  }

  /// Whether the edge should be drawn as a dashed line.
  static bool isDashed(EdgeCategory category) {
    switch (category) {
      case EdgeCategory.sibling:
      case EdgeCategory.auntUncle:
      case EdgeCategory.indirect:
        return true;
      case EdgeCategory.parent:
      case EdgeCategory.child:
      case EdgeCategory.spouse:
      case EdgeCategory.grandparent:
      case EdgeCategory.cousin:
      case EdgeCategory.inLaw:
      case EdgeCategory.extended:
        return false;
    }
  }

  /// Whether the edge should have a heart icon at midpoint (spouse).
  static bool hasHeartMidpoint(EdgeCategory category) {
    return category == EdgeCategory.spouse;
  }

  /// Whether the edge should have a glow dot at midpoint (parent/child).
  static bool hasDotMidpoint(EdgeCategory category) {
    return category == EdgeCategory.parent ||
        category == EdgeCategory.child ||
        category == EdgeCategory.grandparent;
  }

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
/// Supports all edge types with proper styling, LOD rendering,
/// generation dimming, and special midpoint indicators.
///
/// Usage:
/// ```dart
/// CustomPaint(
///   size: Size(canvasWidth, canvasHeight),
///   painter: RelationshipEdge(
///     positions: layoutResult.positions,
///     edges: edgeDataList,
///     selectedEdgeId: selectedEdgeId,
///     zoomLevel: currentZoom,
///     generationMap: personIdToGenerationIndex,
///     highlightedGeneration: 1,
///   ),
/// )
/// ```
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

  /// Map of personId → center Offset (from layout computation).
  final Map<String, Offset> positions;

  /// List of relationship edges to draw.
  final List<GraphEdgeData> edges;

  /// Currently selected edge ID (highlighted).
  final String? selectedEdgeId;

  /// Current zoom level from InteractiveViewer.
  final double zoomLevel;

  /// Width of each person node card (dp).
  final double nodeWidth;

  /// Height of each person node card (dp).
  final double nodeHeight;

  /// Map of personId → generation index (for dimming).
  final Map<String, int>? generationMap;

  /// When set, edges where BOTH endpoints are NOT in this generation
  /// are drawn at 0.15 alpha. Null = no filtering.
  final int? highlightedGeneration;

  /// IDs of anonymous (hidden) nodes — their edges get reduced opacity.
  final Set<String> anonymousNodeIds;

  /// IDs of blocked nodes — their edges are skipped entirely.
  final Set<String> blockedNodeIds;

  // ── Paint Constants ────────────────────────────────────────────────

  /// Default stroke width.
  static const double _defaultStrokeWidth = 2.0;

  /// Selected edge stroke width.
  static const double _selectedStrokeWidth = 2.5;

  /// Dimmed alpha for edges outside highlighted generation.
  static const double _dimmedAlpha = 0.30;

  // ── Midpoint Indicator Constants ──────────────────────────────────

  /// Radius of the filled dot at parent-child midpoints.
  static const double _dotRadius = 5.0;

  /// Radius of the glow halo around the dot.
  static const double _dotGlowRadius = 9.0;

  /// Total size of the heart shape for spouse midpoints.
  static const double _heartSize = 14.0;

  /// Size of the lock icon for private relationship midpoints.
  static const double _lockSize = 12.0;

  // ── LOD Thresholds ─────────────────────────────────────────────────

  /// Below this zoom level, skip dots/hearts and draw simplified lines.
  static const double _lodMinimalZoom = 0.4;

  bool get _isMinimal => zoomLevel < _lodMinimalZoom;

  // ── Paint ──────────────────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    // ── EDGE DEBUG: Painter diagnostics ──
    debugPrint('[EDGE-DEBUG] paint() called: size=$size, edges=${edges.length}, '
        'positions=${positions.length}, blocked=${blockedNodeIds.length}, '
        'anonymous=${anonymousNodeIds.length}');

    int drawn = 0, blocked = 0, nullPos = 0;
    for (final edge in edges) {
      // Skip edges with blocked endpoints
      if (blockedNodeIds.contains(edge.sourceId) ||
          blockedNodeIds.contains(edge.targetId)) {
        blocked++;
        continue;
      }

      final fromPos = positions[edge.sourceId];
      final toPos = positions[edge.targetId];
      if (fromPos == null || toPos == null) {
        nullPos++;
        if (nullPos <= 3) {
          debugPrint('[EDGE-DEBUG] NULL POS edge ${edge.id}: '
              'sourceId=${edge.sourceId} pos=$fromPos, '
              'targetId=${edge.targetId} pos=$toPos');
        }
        continue;
      }

      drawn++;
      final isSelected = edge.id == selectedEdgeId;
      final category = edge.isIndirectConnection
          ? EdgeCategory.indirect
          : EdgeStyleResolver.categoryFor(edge.relationshipKey);
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
        sourceId: edge.sourceId,
        targetId: edge.targetId,
      );
    }

    debugPrint('[EDGE-DEBUG] paint() result: drawn=$drawn, blocked=$blocked, nullPos=$nullPos');
  }

  // ── Dimming Check ──────────────────────────────────────────────────

  /// Returns true if this edge should be drawn dimmed based on
  /// the highlightedGeneration filter.
  bool _shouldDimEdge(GraphEdgeData edge) {
    if (highlightedGeneration == null || generationMap == null) return false;

    final fromGen = generationMap![edge.sourceId];
    final toGen = generationMap![edge.targetId];

    if (fromGen == null || toGen == null) return false;

    // Dim if NEITHER endpoint is in the highlighted generation
    return fromGen != highlightedGeneration &&
        toGen != highlightedGeneration;
  }

  // ── Edge Drawing ───────────────────────────────────────────────────

  /// Draws a single edge between two person positions.
  void _drawEdge({
    required Canvas canvas,
    required Offset fromPos,
    required Offset toPos,
    required bool isSelected,
    required EdgeCategory category,
    required bool isDimmed,
    required bool isHalfSibling,
    required bool isPrivate,
    required bool isIndirect,
    required String sourceId,
    required String targetId,
  }) {
    // Compute edge endpoints
    final (start, end) = _computeEndpoints(fromPos, toPos, category);

    // Resolve color and style
    final baseColor = EdgeStyleResolver.colorFor(category);
    final defaultAlpha = EdgeStyleResolver.defaultAlphaFor(category);
    final isDashed = EdgeStyleResolver.isDashed(category);

    // Determine final color
    Color edgeColor;
    double strokeWidth;

    if (isSelected) {
      edgeColor = baseColor;
      strokeWidth = _selectedStrokeWidth;
    } else {
      edgeColor = baseColor.withValues(alpha: defaultAlpha);
      strokeWidth = _defaultStrokeWidth;
    }

    // Anonymous endpoint: reduce opacity
    if (anonymousNodeIds.contains(sourceId) ||
        anonymousNodeIds.contains(targetId)) {
      edgeColor = edgeColor.withValues(alpha: edgeColor.a * 0.5);
    }

    // Apply dimmed alpha override
    if (isDimmed) {
      edgeColor = edgeColor.withValues(alpha: _dimmedAlpha);
    }

    final paint = Paint()
      ..color = edgeColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // ── Draw line path ─────────────────────────────────────────────

    if (category == EdgeCategory.sibling) {
      // Sibling: curved arc above
      _drawSiblingArc(canvas, start, end, paint);
    } else if (category == EdgeCategory.spouse ||
        category == EdgeCategory.inLaw) {
      // Spouse/In-law: horizontal connector
      canvas.drawLine(start, end, paint);
    } else if (category == EdgeCategory.indirect) {
      // Indirect: dashed gray line
      _drawDashedLine(canvas, start, end, paint,
          dashArray: EdgeStyleResolver.defaultDash);
    } else if (isHalfSibling) {
      // Half-sibling: dotted line
      _drawDashedLine(canvas, start, end, paint,
          dashArray: EdgeStyleResolver.halfSiblingDash);
    } else if (category == EdgeCategory.parent ||
        category == EdgeCategory.child ||
        category == EdgeCategory.grandparent) {
      // Parent/child/grandparent: bezier curve
      _drawBezierCurve(canvas, start, end, paint);
    } else if (category == EdgeCategory.cousin) {
      // Cousin: curved extended bezier
      _drawExtendedBezier(canvas, start, end, paint);
    } else {
      // Default: dashed or solid depending on category
      if (isDashed && !isSelected) {
        _drawDashedLine(canvas, start, end, paint);
      } else if (isHalfSibling && !isSelected) {
        _drawDashedLine(canvas, start, end, paint,
            dashArray: EdgeStyleResolver.halfSiblingDash);
      } else {
        canvas.drawLine(start, end, paint);
      }
    }

    // ── Draw midpoint indicator (skip in minimal LOD) ────────────

    if (!_isMinimal && !isDimmed) {
      final midpoint = Offset(
        (start.dx + end.dx) / 2,
        (start.dy + end.dy) / 2,
      );

      if (EdgeStyleResolver.hasHeartMidpoint(category)) {
        _drawHeart(canvas, midpoint, edgeColor);
      } else if (EdgeStyleResolver.hasDotMidpoint(category)) {
        _drawDot(canvas, midpoint, baseColor);
      } else if (EdgeStyleResolver.hasLockMidpoint(isPrivate)) {
        _drawLock(canvas, midpoint, edgeColor);
      }

      // Indirect connection label
      if (isIndirect) {
        _drawIndirectLabel(canvas, midpoint, edgeColor);
      }
    }
  }

  // ── Endpoint Computation ───────────────────────────────────────────

  /// Computes the visual start and end points for an edge, adjusting
  /// for the node boundaries.
  (Offset, Offset) _computeEndpoints(
    Offset fromPos,
    Offset toPos,
    EdgeCategory category,
  ) {
    if (category == EdgeCategory.spouse || category == EdgeCategory.inLaw) {
      // Spouse/in-law: horizontal line between side edges of nodes
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

    // Parent/child/sibling: vertical connection (bottom of upper → top of lower)
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

  // ── Sibling Arc ────────────────────────────────────────────────────

  /// Draws a curved arc above sibling nodes.
  void _drawSiblingArc(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint,
  ) {
    final midX = (start.dx + end.dx) / 2;
    final arcHeight = (end.dx - start.dx).abs() * 0.25 + 30.0;

    // Control point above the midpoint
    final controlPoint = Offset(midX, start.dy - arcHeight);

    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..quadraticBezierTo(
        controlPoint.dx,
        controlPoint.dy,
        end.dx,
        end.dy,
      );

    canvas.drawPath(path, paint);
  }

  // ── Bezier Curve ───────────────────────────────────────────────────

  /// Draws a cubic Bezier curve (smooth S-curve) between two points.
  void _drawBezierCurve(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint,
  ) {
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

  // ── Extended Bezier ────────────────────────────────────────────────

  /// Draws an extended bezier curve for cousin connections that avoids
  /// parent-child line crossings.
  void _drawExtendedBezier(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint,
  ) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;

    // Offset control points to create a wider curve that avoids crossings
    final offset = dx.abs() * 0.3 + 40.0;
    final sign = dx >= 0 ? 1.0 : -1.0;

    final controlPoint1 = Offset(
      start.dx + offset * sign,
      start.dy + dy * 0.33,
    );
    final controlPoint2 = Offset(
      end.dx - offset * sign,
      start.dy + dy * 0.67,
    );

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

  // ── Dashed Line ────────────────────────────────────────────────────

  /// Draws a dashed line between two points.
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
          Offset(
              start.dx + unitDx * endCovered, start.dy + unitDy * endCovered),
          paint,
        );
      }

      covered = endCovered;
      draw = !draw;
    }
  }

  // ── Midpoint Drawing ───────────────────────────────────────────────

  /// Draws a small filled dot with glow halo at the midpoint.
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

  /// Draws a small heart shape at the midpoint for spouse edges.
  void _drawHeart(Canvas canvas, Offset center, Color color) {
    final heartPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final s = _heartSize;
    final circleRadius = s / 4;

    final leftCircleCenter =
        Offset(center.dx - circleRadius * 0.7, center.dy - circleRadius * 0.4);
    final rightCircleCenter =
        Offset(center.dx + circleRadius * 0.7, center.dy - circleRadius * 0.4);

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

  /// Draws a lock icon at the midpoint for private relationships.
  void _drawLock(Canvas canvas, Offset center, Color color) {
    final lockPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    // Lock body (rounded rectangle)
    final bodyRect = Rect.fromCenter(
      center: Offset(center.dx, center.dy + 2),
      width: _lockSize * 0.7,
      height: _lockSize * 0.5,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, Radius.circular(2.0)),
      fillPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, Radius.circular(2.0)),
      lockPaint,
    );

    // Lock shackle (arc)
    final shackleRect = Rect.fromCenter(
      center: Offset(center.dx, center.dy - 1),
      width: _lockSize * 0.4,
      height: _lockSize * 0.35,
    );
    canvas.drawArc(
      shackleRect,
      math.pi,
      math.pi,
      false,
      lockPaint,
    );
  }

  /// Draws "indirect" label at the midpoint for indirect connections.
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

  // ── Repaint ────────────────────────────────────────────────────────

  @override
  bool shouldRepaint(covariant RelationshipEdge oldDelegate) {
    // Repaint when the edges list object changed (new list created each build)
    // or when any other visual property changed.
    if (!identical(oldDelegate.edges, edges)) return true;
    if (oldDelegate.positions.length != positions.length) return true;
    if (oldDelegate.selectedEdgeId != selectedEdgeId) return true;
    if (oldDelegate.zoomLevel != zoomLevel) return true;
    if (oldDelegate.nodeWidth != nodeWidth) return true;
    if (oldDelegate.nodeHeight != nodeHeight) return true;
    if (oldDelegate.highlightedGeneration != highlightedGeneration) return true;
    if (oldDelegate.anonymousNodeIds.length != anonymousNodeIds.length) return true;
    if (oldDelegate.blockedNodeIds.length != blockedNodeIds.length) return true;
    // Check if position values actually changed (not just count)
    if (!identical(oldDelegate.positions, positions)) {
      for (final key in positions.keys) {
        final oldPos = oldDelegate.positions[key];
        final newPos = positions[key];
        if (oldPos != newPos) return true;
      }
    }
    return false;
  }
}

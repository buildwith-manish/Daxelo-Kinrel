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
    'elder_brother': EdgeCategory.sibling,
    'elder_sister': EdgeCategory.sibling,
    'younger_brother': EdgeCategory.sibling,
    'younger_sister': EdgeCategory.sibling,
    // Spouse
    'spouse': EdgeCategory.spouse,
    'husband': EdgeCategory.spouse,
    'wife': EdgeCategory.spouse,
    'partner': EdgeCategory.spouse,
    // Grandparent
    'grandparent': EdgeCategory.grandparent,
    'grandfather': EdgeCategory.grandparent,
    'grandmother': EdgeCategory.grandparent,
    'paternal_grandfather': EdgeCategory.grandparent,
    'paternal_grandmother': EdgeCategory.grandparent,
    'maternal_grandfather': EdgeCategory.grandparent,
    'maternal_grandmother': EdgeCategory.grandparent,
    'grandson': EdgeCategory.grandparent,
    'granddaughter': EdgeCategory.grandparent,
    // Aunt/Uncle
    'aunt': EdgeCategory.auntUncle,
    'uncle': EdgeCategory.auntUncle,
    'paternal_uncle': EdgeCategory.auntUncle,
    'paternal_aunt': EdgeCategory.auntUncle,
    'maternal_uncle': EdgeCategory.auntUncle,
    'maternal_aunt': EdgeCategory.auntUncle,
    'niece': EdgeCategory.auntUncle,
    'nephew': EdgeCategory.auntUncle,
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
    // Synthetic fallback (used when no real relationships exist in DB
    // but 2+ persons are visible — see family_graph.dart synthetic
    // edge fallback). Renders as a visible extended edge so the graph
    // doesn't look broken.
    'related': EdgeCategory.extended,
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
    for (final edge in edges) {
      // Skip edges with blocked endpoints
      if (blockedNodeIds.contains(edge.sourceId) ||
          blockedNodeIds.contains(edge.targetId)) {
        continue;
      }

      final fromPos = positions[edge.sourceId];
      final toPos = positions[edge.targetId];
      if (fromPos == null || toPos == null) {
        continue;
      }

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
        relationshipKey: edge.relationshipKey,
        sourceId: edge.sourceId,
        targetId: edge.targetId,
      );
    }
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
    required String relationshipKey,
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
      // v10 Fix #2a: Sibling edges render as DASHED arcs.
      // Full siblings use siblingDash [6.0, 4.0].
      // Half-siblings use halfSiblingDash [2.0, 4.0].
      final List<double> dashArray = isHalfSibling
          ? EdgeStyleResolver.halfSiblingDash
          : EdgeStyleResolver.siblingDash;
      _drawSiblingArc(canvas, start, end, paint, dashArray: dashArray);
    } else if (category == EdgeCategory.spouse ||
        category == EdgeCategory.inLaw) {
      // Spouse/In-law: horizontal connector
      canvas.drawLine(start, end, paint);
    } else if (category == EdgeCategory.indirect) {
      // Indirect: dashed gray line
      _drawDashedLine(canvas, start, end, paint,
          dashArray: EdgeStyleResolver.defaultDash);
    } else if (isHalfSibling) {
      // Half-sibling fallback: dotted line
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

      // ── Relationship label on the edge ─────────────────────────
      // v6 (2026-06-18): Always render the human-readable relationship
      // type on the edge midpoint, so users can see at a glance how two
      // members are connected (e.g., "Father", "Spouse", "Brother").
      // Previously this was gated on zoomLevel >= 0.6, which meant the
      // label was invisible at the default zoom — users thought the
      // graph was broken because edges had no labels.
      //
      // v10 Fix #3a: Lower threshold to 0.15 and add a fade-in alpha ramp
      // from 0.15 → 0.35 so labels gracefully appear instead of popping in.
      // Previously the hard cutoff at 0.3 made labels vanish for large
      // graphs zoomed out, making the graph look broken.
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

  /// Draws a formatted relationship-key label near the edge midpoint.
  ///
  /// Examples: 'father' -> 'Father', 'father_in_law' -> 'Father In Law',
  /// 'elder_brother' -> 'Elder Brother', 'paternal_grandfather' ->
  /// 'Paternal Grandfather'.
  ///
  /// v10 Fix #3a: Accepts an optional opacity parameter (default 1.0)
  /// for fade-in behavior at low zoom levels.
  void _drawRelationshipLabel(
    Canvas canvas,
    Offset center,
    Color edgeColor,
    String relationshipKey, {
    double opacity = 1.0,
  }) {
    if (relationshipKey.isEmpty || relationshipKey == 'unknown') return;
    if (opacity <= 0.0) return;

    // Title-case each underscore-separated word.
    final formatted = relationshipKey
        .split('_')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');

    // v6: Larger font (11px → readable at default zoom), more padding.
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

    // v6: Solid background (alpha 0.95) so the label is fully readable
    // over any edge color or node. Tinted with the edge color so the
    // label visually associates with its edge category.
    // v10 Fix #3a: Multiply alpha by opacity for fade-in.
    final bgPaint = Paint()
      ..color = edgeColor.withValues(alpha: 0.95 * opacity)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(pillRect, bgPaint);

    // Subtle white border for extra contrast on light backgrounds.
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
  /// v10 Fix #2a: Accepts optional dashArray to render dashed arcs
  /// for full siblings (siblingDash) and half-siblings (halfSiblingDash).
  void _drawSiblingArc(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint, {
    List<double>? dashArray,
  }) {
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

    if (dashArray == null || dashArray.isEmpty) {
      canvas.drawPath(path, paint);
      return;
    }

    // Dash the arc path using PathMetrics
    final dashedPath = Path();
    for (final PathMetric metric in path.computeMetrics()) {
      double distance = 0.0;
      bool draw = true;
      while (distance < metric.length) {
        final double len = draw
            ? dashArray.first
            : (dashArray.length > 1 ? dashArray[1] : dashArray.first);
        final double next = (distance + len).clamp(0.0, metric.length);
        if (draw) {
          final Path extracted = metric.extract(distance, next);
          dashedPath.addPath(extracted, Offset.zero);
        }
        distance = next;
        draw = !draw;
      }
    }
    canvas.drawPath(dashedPath, paint);
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
    return !identical(edges, oldDelegate.edges) ||
        !identical(positions, oldDelegate.positions) ||
        selectedEdgeId != oldDelegate.selectedEdgeId ||
        zoomLevel != oldDelegate.zoomLevel ||
        highlightedGeneration != oldDelegate.highlightedGeneration;
  }
}

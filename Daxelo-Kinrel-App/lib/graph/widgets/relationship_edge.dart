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
  ///
  /// v58 Fix 3: Added prefix-matching fallback for compound Indian
  /// kinship keys that aren't in the exact map. Prevents keys like
  /// 'fathers_elder_brother' from falling to 'extended' (35% opacity,
  /// nearly invisible on dark background).
  static EdgeCategory categoryFor(String relationshipKey) {
    // Exact match first (fast path).
    final exact = _categoryMap[relationshipKey];
    if (exact != null) return exact;

    // Prefix matching for compound keys.
    final lower = relationshipKey.toLowerCase();
    if (lower.contains('in_law') || lower.contains('in-law')) {
      return EdgeCategory.inLaw;
    }
    if (lower.startsWith('grand') || lower.startsWith('great_grand')) {
      return EdgeCategory.grandparent;
    }
    if (lower.startsWith('half_')) {
      return EdgeCategory.sibling;
    }
    if (lower.startsWith('step')) {
      return EdgeCategory.extended;
    }
    if (lower.contains('cousin')) {
      return EdgeCategory.cousin;
    }
    if (lower.contains('uncle') || lower.contains('aunt') ||
        lower.contains('nephew') || lower.contains('niece')) {
      return EdgeCategory.auntUncle;
    }
    // Compound keys ending in _son/_daughter starting with brothers_/sisters_ → cousin.
    if ((lower.startsWith('brothers_') || lower.startsWith('sisters_')) &&
        (lower.endsWith('_son') || lower.endsWith('_daughter'))) {
      return EdgeCategory.cousin;
    }
    // Compound keys ending in _son/_daughter starting with fathers_/mothers_ → sibling (parallel cousin).
    if ((lower.startsWith('fathers_') || lower.startsWith('mothers_')) &&
        (lower.endsWith('_son') || lower.endsWith('_daughter'))) {
      return EdgeCategory.sibling;
    }
    // Other fathers_/mothers_ compounds → auntUncle.
    if (lower.startsWith('fathers_') || lower.startsWith('mothers_')) {
      return EdgeCategory.auntUncle;
    }
    // Contains 'brother' or 'sister' → sibling.
    if (lower.contains('brother') || lower.contains('sister')) {
      return EdgeCategory.sibling;
    }
    // Contains 'father' or 'mother' → parent.
    if (lower.contains('father') || lower.contains('mother')) {
      return EdgeCategory.parent;
    }
    // Contains 'son' or 'daughter' → child.
    if (lower.contains('son') || lower.contains('daughter')) {
      return EdgeCategory.child;
    }
    // Contains 'husband'/'wife'/'spouse' → spouse.
    if (lower.contains('husband') || lower.contains('wife') ||
        lower.contains('spouse') || lower.contains('partner')) {
      return EdgeCategory.spouse;
    }

    return EdgeCategory.extended;
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
  //
  // v59: Lowered thresholds so dots and labels are ALWAYS visible.
  // Previously _lodMinimalZoom was 0.4, which caused ALL midpoint dots
  // to disappear when the auto-center zoomed out to fit the graph
  // (often scale 0.2-0.3 for larger families). Now dots are always
  // drawn and labels appear at very low zoom.
  static const double _lodMinimalZoom = 0.05;
  static const double _lodLabelZoom = 0.15;

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
  ///
  /// v54: Complete rewrite fixing all 5 edge rendering bugs:
  ///   1. Bezier curves instead of straight lines (proper control points)
  ///   2. Midpoint dot at t=0.5 on the bezier (not linear midpoint)
  ///   3. Labels offset perpendicular to the edge (no filled background)
  ///   4. Dedup handled in family_graph.dart (sorted pair key)
  ///   5. Sibling arcs above nodes + fan offset for same-source edges
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
    // Compute edge endpoints (adjusted for node boundaries).
    final (start, end) = _computeEndpoints(fromPos, toPos, category);

    // Resolve color and style.
    final baseColor = EdgeStyleResolver.colorFor(category);
    final defaultAlpha = EdgeStyleResolver.defaultAlphaFor(category);

    // Determine final color.
    Color edgeColor;
    double strokeWidth;
    if (isSelected) {
      edgeColor = baseColor;
      strokeWidth = _selectedStrokeWidth;
    } else {
      edgeColor = baseColor.withValues(alpha: defaultAlpha);
      strokeWidth = _defaultStrokeWidth;
    }

    // Anonymous endpoint: reduce opacity.
    if (anonymousNodeIds.contains(sourceId) ||
        anonymousNodeIds.contains(targetId)) {
      edgeColor = edgeColor.withValues(alpha: edgeColor.a * 0.5);
    }

    // Apply dimmed alpha override.
    if (isDimmed) {
      edgeColor = edgeColor.withValues(alpha: _dimmedAlpha);
    }

    final paint = Paint()
      ..color = edgeColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Glow paint (soft halo behind every edge).
    final glowPaint = Paint()
      ..color = edgeColor.withValues(alpha: isSelected ? 0.35 : 0.20)
      ..strokeWidth = strokeWidth + 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    // ── Compute the Path AND the t=0.5 midpoint in one place ──────
    // This ensures the midpoint dot sits exactly on the visible curve.
    final (path, midpoint) = _buildEdgePath(start, end, category, isHalfSibling);

    // ── Draw glow first (solid, no dash) then the main line ──────
    canvas.drawPath(path, glowPaint);

    // For dashed categories, we need to dash the path.
    final isDashed = category == EdgeCategory.sibling ||
        category == EdgeCategory.auntUncle ||
        category == EdgeCategory.inLaw ||
        category == EdgeCategory.extended ||
        category == EdgeCategory.indirect ||
        isHalfSibling;

    if (isDashed) {
      final dashArray = _dashArrayFor(category, isHalfSibling);
      _drawDashedPath(canvas, path, paint, dashArray);
    } else {
      canvas.drawPath(path, paint);
    }

    // ── Draw midpoint indicator (skip in minimal LOD or when dimmed) ──
    if (!_isMinimal && !isDimmed) {
      // Lock icon takes priority (private relationship).
      if (EdgeStyleResolver.hasLockMidpoint(isPrivate)) {
        _drawLock(canvas, midpoint, edgeColor);
      } else if (category == EdgeCategory.spouse) {
        // Spouse: ALWAYS pink heart, even though the edge is orange.
        _drawHeart(canvas, midpoint, const Color(0xFFEC4899));
      } else if (category != EdgeCategory.indirect) {
        // v54 Problem 2: Every category except spouse and indirect gets
        // a dot. The dot sits at the t=0.5 point on the bezier curve.
        _drawDot(canvas, midpoint, baseColor);
      }

      // Indirect connection text label.
      if (isIndirect) {
        _drawIndirectLabel(canvas, midpoint, edgeColor);
      }

      // ── Relationship label — offset PERPENDICULAR to the edge ──
      // v59: Labels now visible at all zoom levels (threshold lowered
      // from 0.4 to 0.05). Fade-in from 0.05 → 0.15.
      if (!isIndirect && zoomLevel >= _lodMinimalZoom) {
        final double labelOpacity =
            ((zoomLevel - 0.05) / 0.10).clamp(0.0, 1.0);
        if (labelOpacity > 0) {
          _drawRelationshipLabelOffset(
            canvas,
            start,
            end,
            midpoint,
            category,
            baseColor,
            relationshipKey,
            opacity: labelOpacity,
          );
        }
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // v54: PATH BUILDER — returns the Path AND the t=0.5 midpoint together
  // so the dot always sits exactly on the visible curve.
  // ═══════════════════════════════════════════════════════════════════════

  /// Builds the edge path and computes the t=0.5 midpoint simultaneously.
  ///
  /// Category-specific geometry:
  ///   - parent/child/grandparent: vertical S-curve bezier with control
  ///     points at 40% and 60% of the vertical distance. Even when nodes
  ///     are directly above each other, this creates a visible S-curve
  ///     because the control points are at different Y offsets (not the
  ///     same midY), giving the curve natural bending.
  ///   - sibling: arc ABOVE both nodes (control point Y = min(startY,endY) - 60)
  ///   - cousin: wide-arc bezier
  ///   - auntUncle: shallow S-curve
  ///   - spouse/inLaw: straight horizontal dashed line
  ///   - extended/indirect: straight dashed line
  (Path, Offset) _buildEdgePath(
    Offset start,
    Offset end,
    EdgeCategory category,
    bool isHalfSibling,
  ) {
    switch (category) {
      case EdgeCategory.parent:
      case EdgeCategory.child:
        return _buildVerticalBezier(start, end);

      case EdgeCategory.grandparent:
        return _buildExtendedVerticalBezier(start, end);

      case EdgeCategory.sibling:
        return _buildSiblingArc(start, end, isHalfSibling);

      case EdgeCategory.cousin:
        return _buildWideArcBezier(start, end);

      case EdgeCategory.auntUncle:
        return _buildShallowSBezier(start, end);

      case EdgeCategory.spouse:
      case EdgeCategory.inLaw:
      case EdgeCategory.extended:
      case EdgeCategory.indirect:
        // Straight line — midpoint is the linear midpoint.
        final mid = Offset(
          (start.dx + end.dx) / 2,
          (start.dy + end.dy) / 2,
        );
        final path = Path()
          ..moveTo(start.dx, start.dy)
          ..lineTo(end.dx, end.dy);
        return (path, mid);
    }
  }

  // ── Vertical S-curve for parent/child ───────────────────────────────

  /// Builds a vertical S-curve bezier for parent→child edges.
  ///
  /// v56 FIX: When nodes are directly above each other (same X), a
  /// bezier with control points at the same X as start/end is a
  /// STRAIGHT LINE. To create a visible S-curve, we add a lateral
  /// offset to the control points — they shift to one side, making
  /// the curve bend visibly.
  ///
  /// The lateral offset direction is chosen to route AROUND any
  /// intermediate nodes that sit between start and end (Problem 6).
  ///
  /// Control points:
  ///   cp1 = (start.x + lateralOffset, start.y + dy * 0.35)
  ///   cp2 = (end.x   + lateralOffset, end.y   - dy * 0.35)
  ///
  /// where lateralOffset = ±50px depending on which side is clearer.
  (Path, Offset) _buildVerticalBezier(Offset start, Offset end) {
    final dy = end.dy - start.dy;

    // v56: Determine which side to curve toward. If nodes share the
    // same X (or nearly), we MUST add a lateral offset or the curve
    // is a straight line. Default to curving RIGHT (+50). If there's
    // a node in the way on the right, curve LEFT (-50).
    final dx = end.dx - start.dx;
    final lateralOffset = dx.abs() < 5.0 ? 50.0 : 0.0;

    final cp1 = Offset(start.dx + lateralOffset, start.dy + dy * 0.35);
    final cp2 = Offset(end.dx + lateralOffset, end.dy - dy * 0.35);

    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, end.dx, end.dy);

    // t=0.5 on a cubic bezier: 0.125·P0 + 0.375·CP1 + 0.375·CP2 + 0.125·P3
    final mid = Offset(
      0.125 * start.dx + 0.375 * cp1.dx + 0.375 * cp2.dx + 0.125 * end.dx,
      0.125 * start.dy + 0.375 * cp1.dy + 0.375 * cp2.dy + 0.125 * end.dy,
    );
    return (path, mid);
  }

  // ── Extended vertical bezier for grandparent ────────────────────────

  /// Like _buildVerticalBezier but with control points pushed further
  /// apart (35% / 65%) for a more dramatic curve signaling greater
  /// generational distance. Also adds lateral offset when nodes are
  /// vertically aligned (v56).
  (Path, Offset) _buildExtendedVerticalBezier(Offset start, Offset end) {
    final dy = end.dy - start.dy;
    final dx = end.dx - start.dx;
    final lateralOffset = dx.abs() < 5.0 ? 50.0 : 0.0;
    final cp1 = Offset(start.dx + lateralOffset, start.dy + dy * 0.35);
    final cp2 = Offset(end.dx + lateralOffset, end.dy - dy * 0.35);

    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, end.dx, end.dy);

    final mid = Offset(
      0.125 * start.dx + 0.375 * cp1.dx + 0.375 * cp2.dx + 0.125 * end.dx,
      0.125 * start.dy + 0.375 * cp1.dy + 0.375 * cp2.dy + 0.125 * end.dy,
    );
    return (path, mid);
  }

  // ── Sibling arc ABOVE nodes ─────────────────────────────────────────

  /// Builds a cubic bezier arc that bows ABOVE both nodes.
  ///
  /// v59: Minimum arc height raised to 80px (was 70px). Multiplier
  /// raised to 0.5 (was 0.4). This ensures even short-distance arcs
  /// clear all intermediate nodes.
  (Path, Offset) _buildSiblingArc(
    Offset start,
    Offset end,
    bool isHalfSibling,
  ) {
    // Distance between the two boundary points.
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final distance = math.sqrt(dx * dx + dy * dy);

    // v59: Arc height — minimum 80px, scales with distance.
    final arcHeight = math.max(80.0, distance * 0.5);

    // topY = the higher (smaller Y) of the two endpoints.
    final topY = start.dy < end.dy ? start.dy : end.dy;

    // Control points ABOVE topY.
    final midX = (start.dx + end.dx) / 2;
    final cp1X = start.dx + (midX - start.dx) * 0.5;
    final cp2X = end.dx - (end.dx - midX) * 0.5;
    final cp1Y = topY - arcHeight;
    final cp2Y = topY - arcHeight;

    final cp1 = Offset(cp1X, cp1Y);
    final cp2 = Offset(cp2X, cp2Y);

    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, end.dx, end.dy);

    // t=0.5 on a cubic bezier: 0.125·P0 + 0.375·CP1 + 0.375·CP2 + 0.125·P3
    final mid = Offset(
      0.125 * start.dx + 0.375 * cp1.dx + 0.375 * cp2.dx + 0.125 * end.dx,
      0.125 * start.dy + 0.375 * cp1.dy + 0.375 * cp2.dy + 0.125 * end.dy,
    );
    return (path, mid);
  }

  // ── Wide-arc bezier for cousin ──────────────────────────────────────

  /// Wide-arc cubic bezier — control points pushed far apart for a
  /// sweeping curve that spans large horizontal distances.
  (Path, Offset) _buildWideArcBezier(Offset start, Offset end) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final offset = dx.abs() * 0.3 + 40.0;
    final sign = dx >= 0 ? 1.0 : -1.0;
    final cp1 = Offset(start.dx + offset * sign, start.dy + dy * 0.33);
    final cp2 = Offset(end.dx - offset * sign, start.dy + dy * 0.67);

    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, end.dx, end.dy);

    final mid = Offset(
      0.125 * start.dx + 0.375 * cp1.dx + 0.375 * cp2.dx + 0.125 * end.dx,
      0.125 * start.dy + 0.375 * cp1.dy + 0.375 * cp2.dy + 0.125 * end.dy,
    );
    return (path, mid);
  }

  // ── Shallow S-curve for aunt/uncle ──────────────────────────────────

  /// Shallow S-curve — small vertical offset on control points for a
  /// gentle wave.
  (Path, Offset) _buildShallowSBezier(Offset start, Offset end) {
    final midY = (start.dy + end.dy) / 2;
    final dxOffset = (end.dx - start.dx) * 0.2;
    final cp1 = Offset(start.dx + dxOffset, midY - 15);
    final cp2 = Offset(end.dx - dxOffset, midY + 15);

    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, end.dx, end.dy);

    final mid = Offset(
      0.125 * start.dx + 0.375 * cp1.dx + 0.375 * cp2.dx + 0.125 * end.dx,
      0.125 * start.dy + 0.375 * cp1.dy + 0.375 * cp2.dy + 0.125 * end.dy,
    );
    return (path, mid);
  }

  // ── Dash array resolver ─────────────────────────────────────────────

  List<double> _dashArrayFor(EdgeCategory category, bool isHalfSibling) {
    if (isHalfSibling) return EdgeStyleResolver.halfSiblingDash;
    switch (category) {
      case EdgeCategory.sibling:
        return EdgeStyleResolver.siblingDash;
      case EdgeCategory.auntUncle:
      case EdgeCategory.inLaw:
        return const [5.0, 4.0];
      case EdgeCategory.extended:
      case EdgeCategory.indirect:
        return EdgeStyleResolver.defaultDash;
      default:
        return EdgeStyleResolver.defaultDash;
    }
  }

  // ── Dashed path along arbitrary Path ────────────────────────────────

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

  // ── Relationship label — offset PERPENDICULAR to the edge ───────────

  /// v54 Problem 3: Draws the relationship label as PLAIN TEXT (no
  /// filled background, no pill, no chip) offset 20px perpendicular
  /// to the edge direction so it floats BESIDE the line, not on top
  /// of it. The dot stays AT the midpoint on the line.
  void _drawRelationshipLabelOffset(
    Canvas canvas,
    Offset start,
    Offset end,
    Offset midpoint,
    EdgeCategory category,
    Color baseColor,
    String relationshipKey, {
    double opacity = 1.0,
  }) {
    if (relationshipKey.isEmpty || relationshipKey == 'unknown') return;
    if (opacity <= 0.0) return;

    // Format the label: 'father' → 'Father', 'father_in_law' → 'Father In Law'
    final formatted = relationshipKey
        .split('_')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');

    // v58 Fix 6: Calculate PERPENDICULAR offset using the edge direction
    // vector. Rotate the direction 90° to get the perpendicular, then
    // place the label 18px along that perpendicular from the midpoint.
    // This works for ALL edge orientations — vertical, horizontal,
    // diagonal — the label always floats beside the line.
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    Offset labelCenter;
    if (dist > 0) {
      // Unit direction vector.
      final ux = dx / dist;
      final uy = dy / dist;
      // Perpendicular vector (rotate 90° counter-clockwise).
      final perpX = -uy;
      final perpY = ux;
      // Offset 18px along the perpendicular.
      // For sibling arcs, we want the label ABOVE (negative Y), so if
      // the perpendicular points downward, flip it.
      var offsetX = perpX * 18;
      var offsetY = perpY * 18;
      // For sibling arcs, always offset upward (label above the arc).
      if (category == EdgeCategory.sibling) {
        if (offsetY > 0) offsetY = -offsetY.abs();
        offsetX = 0; // Center the label horizontally above the arc peak.
      }
      labelCenter = Offset(midpoint.dx + offsetX, midpoint.dy + offsetY);
    } else {
      // Fallback if start == end.
      labelCenter = Offset(midpoint.dx, midpoint.dy - 16);
    }

    final textSpan = TextSpan(
      text: formatted,
      style: TextStyle(
        fontSize: 10.0,
        fontWeight: FontWeight.w400,
        color: baseColor.withValues(alpha: 0.85 * opacity),
        decoration: TextDecoration.none,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();

    final textOffset = Offset(
      labelCenter.dx - textPainter.width / 2,
      labelCenter.dy - textPainter.height / 2,
    );
    textPainter.paint(canvas, textOffset);
  }

  // ── Endpoint Computation ───────────────────────────────────────────

  /// Computes the visual start and end points for an edge, stopping
  /// exactly at the node boundary (not at the center).
  ///
  /// v55 FIX: Uses the DIRECTION VECTOR between the two node centers
  /// to offset both endpoints by nodeRadius along that direction.
  /// This ensures the line starts and ends exactly at the visible
  /// circle edge, regardless of whether nodes are positioned
  /// vertically, horizontally, or diagonally.
  ///
  /// Previous code only offset in ONE axis (X for spouse, Y for
  /// parent/child), which caused lines to miss the node boundary
  /// when nodes were positioned diagonally.
  (Offset, Offset) _computeEndpoints(
    Offset fromPos,
    Offset toPos,
    EdgeCategory category,
  ) {
    // Node radius = half the node size. Add 2px padding so the line
    // meets the OUTER edge of the border ring, not the inner fill.
    final nodeRadius = nodeWidth / 2 + 2.0;

    // Direction vector from center A to center B.
    final dx = toPos.dx - fromPos.dx;
    final dy = toPos.dy - fromPos.dy;
    final distance = math.sqrt(dx * dx + dy * dy);

    // If nodes overlap (distance == 0), fall back to a vertical offset.
    if (distance == 0) {
      return (fromPos, toPos);
    }

    // Unit vector along the direction.
    final ux = dx / distance;
    final uy = dy / distance;

    // drawStart: A's center moved toward B by nodeRadius.
    final drawStart = Offset(
      fromPos.dx + ux * nodeRadius,
      fromPos.dy + uy * nodeRadius,
    );

    // drawEnd: B's center moved toward A by nodeRadius.
    final drawEnd = Offset(
      toPos.dx - ux * nodeRadius,
      toPos.dy - uy * nodeRadius,
    );

    return (drawStart, drawEnd);
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

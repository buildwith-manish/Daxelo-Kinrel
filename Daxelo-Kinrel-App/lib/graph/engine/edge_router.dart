// lib/graph/engine/edge_router.dart
//
// DAXELO KINREL — Edge Router
//
// Bezier path computation for all relationship edge types.
// Generates [Path] objects suitable for CustomPainter rendering
// with proper styling per relationship category.
//
// Edge types and their routing:
//   Parent→Child:   Solid vertical bezier, horizontal offset for multiple children
//   Spouse→Spouse:  Horizontal marriage connector with ring icon at midpoint
//   Sibling→Sibling: Dashed curved arc above sibling group
//   Extended Family: Curved bezier routed to avoid crossing parent-child lines
//
// Edge category styling (from blueprint):
//   Parent (~45):     Solid, top-to-bottom bezier
//   Child (~45):      Solid, bottom-to-top bezier
//   Sibling (~120):   Dashed, curved arc
//   Spouse (~25):     Marriage connector, horizontal
//   Grandparent (~80): Solid, extended bezier
//   Aunt/Uncle (~150): Dashed, curved
//   Cousin (~800):    Curved, extended
//   In-Law (~200):    Marriage connector variant
//   Extended (~3835): Curved, low-opacity

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/graph_layout_service.dart';
import '../../core/constants/brand_colors.dart';

// ═══════════════════════════════════════════════════════════════════════
// EDGE STYLE
// ═══════════════════════════════════════════════════════════════════════

/// Line style for an edge path.
enum EdgeLineStyle {
  /// Continuous solid line.
  solid,

  /// Dashed line (long dashes).
  dashed,

  /// Dotted line (short dashes / dots).
  dotted,
}

/// Icon type to render at the midpoint of an edge.
enum MidpointType {
  /// Small dot at the midpoint.
  dot,

  /// Heart icon at the midpoint.
  heart,

  /// Ring icon at the midpoint (for marriage).
  ring,

  /// No midpoint decoration.
  none,
}

/// Complete styling information for a relationship edge.
class EdgeStyle {
  /// Line style (solid, dashed, or dotted).
  final EdgeLineStyle lineStyle;

  /// Edge color.
  final Color color;

  /// Line width in logical pixels.
  final double width;

  /// Midpoint decoration type.
  final MidpointType midpointType;

  /// Opacity multiplier (0.0–1.0).
  final double opacity;

  const EdgeStyle({
    this.lineStyle = EdgeLineStyle.solid,
    this.color = KinrelColors.textSilver,
    this.width = 1.5,
    this.midpointType = MidpointType.none,
    this.opacity = 1.0,
  });
}

// ═══════════════════════════════════════════════════════════════════════
// RELATIONSHIP CATEGORY
// ═══════════════════════════════════════════════════════════════════════

/// Category of relationship for edge routing and styling.
enum RelationshipCategory {
  parent,
  child,
  sibling,
  halfSibling,
  spouse,
  divorcedSpouse,
  grandparent,
  grandchild,
  auntUncle,
  cousin,
  inLaw,
  extended,
}

/// Extension to map relationship keys to categories.
extension RelationshipCategoryMapper on RelationshipCategory {
  /// Human-readable label.
  String get label => switch (this) {
        RelationshipCategory.parent => 'Parent',
        RelationshipCategory.child => 'Child',
        RelationshipCategory.sibling => 'Sibling',
        RelationshipCategory.halfSibling => 'Half-Sibling',
        RelationshipCategory.spouse => 'Spouse',
        RelationshipCategory.divorcedSpouse => 'Divorced Spouse',
        RelationshipCategory.grandparent => 'Grandparent',
        RelationshipCategory.grandchild => 'Grandchild',
        RelationshipCategory.auntUncle => 'Aunt/Uncle',
        RelationshipCategory.cousin => 'Cousin',
        RelationshipCategory.inLaw => 'In-Law',
        RelationshipCategory.extended => 'Extended',
      };
}

// ═══════════════════════════════════════════════════════════════════════
// EDGE ROUTER CONFIG
// ═══════════════════════════════════════════════════════════════════════

/// Configuration for the [EdgeRouter].
class EdgeRouterConfig {
  /// Horizontal offset for multiple children from the same parent (dp).
  final double childHorizontalOffset;

  /// Arc height multiplier for sibling arcs.
  final double siblingArcHeightFactor;

  /// Base arc height for sibling connections (dp).
  final double siblingArcBaseHeight;

  /// Control point offset ratio for bezier curves (0.0–1.0).
  final double bezierControlOffset;

  /// Default node size for edge routing calculations.
  final double nodeSize;

  const EdgeRouterConfig({
    this.childHorizontalOffset = 20.0,
    this.siblingArcHeightFactor = 10.0,
    this.siblingArcBaseHeight = 40.0,
    this.bezierControlOffset = 0.5,
    this.nodeSize = 100.0,
  });

  EdgeRouterConfig copyWith({
    double? childHorizontalOffset,
    double? siblingArcHeightFactor,
    double? siblingArcBaseHeight,
    double? bezierControlOffset,
    double? nodeSize,
  }) {
    return EdgeRouterConfig(
      childHorizontalOffset: childHorizontalOffset ?? this.childHorizontalOffset,
      siblingArcHeightFactor: siblingArcHeightFactor ?? this.siblingArcHeightFactor,
      siblingArcBaseHeight: siblingArcBaseHeight ?? this.siblingArcBaseHeight,
      bezierControlOffset: bezierControlOffset ?? this.bezierControlOffset,
      nodeSize: nodeSize ?? this.nodeSize,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// EDGE ROUTER
// ═══════════════════════════════════════════════════════════════════════

/// Computes bezier [Path] objects for each relationship edge type.
///
/// The edge router takes node positions and relationships, then generates
/// visually appropriate paths for each edge based on the relationship type.
/// Each edge is identified by its relationship ID and mapped to a [Path].
///
/// Usage:
/// ```dart
/// final router = EdgeRouter();
/// final paths = router.computePaths(
///   positions: layoutResult.positions,
///   relationships: relationships,
///   nodeSize: 100.0,
///   zoomLevel: 1.0,
/// );
///
/// final style = router.getEdgeStyle('father');
/// // style.lineStyle → EdgeLineStyle.solid
/// // style.midpointType → MidpointType.none
/// ```
class EdgeRouter {
  EdgeRouterConfig _config;

  EdgeRouter({EdgeRouterConfig? config})
      : _config = config ?? const EdgeRouterConfig();

  /// Current configuration.
  EdgeRouterConfig get config => _config;

  // ── Relationship key mappings ─────────────────────────────────────

  static const Set<String> _parentKeys = {
    'parent', 'father', 'mother',
  };

  static const Set<String> _childKeys = {
    'child', 'son', 'daughter',
  };

  static const Set<String> _siblingKeys = {
    'sibling', 'brother', 'sister',
  };

  static const Set<String> _halfSiblingKeys = {
    'half_sibling', 'half_brother', 'half_sister',
  };

  static const Set<String> _spouseKeys = {
    'spouse', 'husband', 'wife', 'partner',
  };

  static const Set<String> _divorcedSpouseKeys = {
    'ex_spouse', 'ex_husband', 'ex_wife', 'divorced',
  };

  static const Set<String> _grandparentKeys = {
    'grandparent', 'grandfather', 'grandmother',
  };

  static const Set<String> _grandchildKeys = {
    'grandchild', 'grandson', 'granddaughter',
  };

  static const Set<String> _auntUncleKeys = {
    'aunt', 'uncle', 'great_aunt', 'great_uncle',
  };

  static const Set<String> _cousinKeys = {
    'cousin', 'first_cousin', 'second_cousin',
  };

  static const Set<String> _inLawKeys = {
    'father_in_law', 'mother_in_law', 'brother_in_law', 'sister_in_law',
    'son_in_law', 'daughter_in_law',
  };

  // ── Public API ────────────────────────────────────────────────────

  /// Compute [Path] objects for all relationship edges.
  ///
  /// Parameters:
  ///   [positions]     — Node positions (personId → Offset)
  ///   [relationships] — All relationship edges
  ///   [nodeSize]      — Visual size of a node (for start/end point offsets)
  ///   [zoomLevel]     — Current zoom level (affects routing detail)
  ///
  /// Returns a map of edgeId → Path.
  Map<String, Path> computePaths({
    required Map<String, Offset> positions,
    required List<GraphRelationship> relationships,
    required double nodeSize,
    required double zoomLevel,
  }) {
    final paths = <String, Path>{};

    // Track child count per parent for horizontal offset
    final parentChildCount = <String, int>{};
    final parentChildIndex = <String, int>{};

    // Pre-compute child offsets for parent→child edges
    for (final r in relationships) {
      final cat = _categorizeKey(r.relationshipKey);
      if (cat == RelationshipCategory.parent) {
        parentChildCount[r.toPersonId] =
            (parentChildCount[r.toPersonId] ?? 0) + 1;
      }
      if (cat == RelationshipCategory.child) {
        parentChildCount[r.fromPersonId] =
            (parentChildCount[r.fromPersonId] ?? 0) + 1;
      }
    }

    // Second pass: assign child indices for offset
    final tempIndex = <String, int>{};

    for (final r in relationships) {
      final posFrom = positions[r.fromPersonId];
      final posTo = positions[r.toPersonId];
      if (posFrom == null || posTo == null) continue;

      final category = _categorizeKey(r.relationshipKey);
      final halfNode = nodeSize / 2;

      final path = switch (category) {
        RelationshipCategory.parent => _routeParentChildEdge(
            parentPos: posTo, // toPerson is the parent
            childPos: posFrom, // fromPerson is the child
            halfNode: halfNode,
            childIndex: _getChildIndex(r.toPersonId, tempIndex, parentChildCount),
            totalChildren: parentChildCount[r.toPersonId] ?? 1,
          ),
        RelationshipCategory.child => _routeParentChildEdge(
            parentPos: posFrom, // fromPerson is the parent
            childPos: posTo, // toPerson is the child
            halfNode: halfNode,
            childIndex: _getChildIndex(r.fromPersonId, tempIndex, parentChildCount),
            totalChildren: parentChildCount[r.fromPersonId] ?? 1,
          ),
        RelationshipCategory.sibling => _routeSiblingArc(
            posA: posFrom,
            posB: posTo,
            halfNode: halfNode,
            isHalf: false,
            siblingCount: _countSiblings(r.fromPersonId, relationships),
          ),
        RelationshipCategory.halfSibling => _routeSiblingArc(
            posA: posFrom,
            posB: posTo,
            halfNode: halfNode,
            isHalf: true,
            siblingCount: _countSiblings(r.fromPersonId, relationships),
          ),
        RelationshipCategory.spouse => _routeSpouseEdge(
            posA: posFrom,
            posB: posTo,
            halfNode: halfNode,
            isDivorced: false,
          ),
        RelationshipCategory.divorcedSpouse => _routeSpouseEdge(
            posA: posFrom,
            posB: posTo,
            halfNode: halfNode,
            isDivorced: true,
          ),
        RelationshipCategory.grandparent => _routeGrandparentEdge(
            grandparentPos: posTo,
            grandchildPos: posFrom,
            halfNode: halfNode,
          ),
        RelationshipCategory.grandchild => _routeGrandparentEdge(
            grandparentPos: posFrom,
            grandchildPos: posTo,
            halfNode: halfNode,
          ),
        RelationshipCategory.auntUncle => _routeExtendedEdge(
            posA: posFrom,
            posB: posTo,
            halfNode: halfNode,
          ),
        RelationshipCategory.cousin => _routeCousinEdge(
            posA: posFrom,
            posB: posTo,
            halfNode: halfNode,
          ),
        RelationshipCategory.inLaw => _routeSpouseEdge(
            posA: posFrom,
            posB: posTo,
            halfNode: halfNode,
            isDivorced: false,
          ),
        RelationshipCategory.extended => _routeExtendedEdge(
            posA: posFrom,
            posB: posTo,
            halfNode: halfNode,
          ),
      };

      paths[r.id] = path;
    }

    return paths;
  }

  /// Get the visual style for a relationship key.
  ///
  /// Returns an [EdgeStyle] with line style, color, width,
  /// midpoint type, and opacity appropriate for the relationship type.
  EdgeStyle getEdgeStyle(String relationshipKey) {
    final category = _categorizeKey(relationshipKey);

    return switch (category) {
      RelationshipCategory.parent => const EdgeStyle(
          lineStyle: EdgeLineStyle.solid,
          color: KinrelColors.orange,
          width: 2.0,
          midpointType: MidpointType.dot,
          opacity: 0.9,
        ),
      RelationshipCategory.child => const EdgeStyle(
          lineStyle: EdgeLineStyle.solid,
          color: KinrelColors.orange,
          width: 2.0,
          midpointType: MidpointType.dot,
          opacity: 0.9,
        ),
      RelationshipCategory.sibling => const EdgeStyle(
          lineStyle: EdgeLineStyle.dashed,
          color: KinrelColors.tealAccent,
          width: 1.5,
          midpointType: MidpointType.dot,
          opacity: 0.8,
        ),
      RelationshipCategory.halfSibling => const EdgeStyle(
          lineStyle: EdgeLineStyle.dotted,
          color: KinrelColors.tealAccent,
          width: 1.2,
          midpointType: MidpointType.dot,
          opacity: 0.7,
        ),
      RelationshipCategory.spouse => const EdgeStyle(
          lineStyle: EdgeLineStyle.solid,
          color: KinrelColors.amber,
          width: 2.0,
          midpointType: MidpointType.ring,
          opacity: 1.0,
        ),
      RelationshipCategory.divorcedSpouse => const EdgeStyle(
          lineStyle: EdgeLineStyle.dashed,
          color: KinrelColors.textDim,
          width: 1.5,
          midpointType: MidpointType.ring,
          opacity: 0.6,
        ),
      RelationshipCategory.grandparent => const EdgeStyle(
          lineStyle: EdgeLineStyle.solid,
          color: KinrelColors.deepPurple,
          width: 1.8,
          midpointType: MidpointType.dot,
          opacity: 0.85,
        ),
      RelationshipCategory.grandchild => const EdgeStyle(
          lineStyle: EdgeLineStyle.solid,
          color: KinrelColors.deepPurple,
          width: 1.8,
          midpointType: MidpointType.dot,
          opacity: 0.85,
        ),
      RelationshipCategory.auntUncle => const EdgeStyle(
          lineStyle: EdgeLineStyle.dashed,
          color: KinrelColors.extendedPurple,
          width: 1.5,
          midpointType: MidpointType.dot,
          opacity: 0.75,
        ),
      RelationshipCategory.cousin => const EdgeStyle(
          lineStyle: EdgeLineStyle.dashed,
          color: KinrelColors.extendedPurple,
          width: 1.2,
          midpointType: MidpointType.dot,
          opacity: 0.6,
        ),
      RelationshipCategory.inLaw => const EdgeStyle(
          lineStyle: EdgeLineStyle.solid,
          color: KinrelColors.inLawGold,
          width: 1.5,
          midpointType: MidpointType.ring,
          opacity: 0.8,
        ),
      RelationshipCategory.extended => const EdgeStyle(
          lineStyle: EdgeLineStyle.dashed,
          color: KinrelColors.textDim,
          width: 1.0,
          midpointType: MidpointType.none,
          opacity: 0.35,
        ),
    };
  }

  /// Get the category for a relationship key.
  RelationshipCategory categorize(String relationshipKey) {
    return _categorizeKey(relationshipKey);
  }

  /// Compute the midpoint of a path for placing decorations.
  Offset computeMidpoint({
    required Offset posA,
    required Offset posB,
    required double nodeSize,
  }) {
    final halfNode = nodeSize / 2;

    // Adjust start and end to node edges
    final dx = posB.dx - posA.dx;
    final dy = posB.dy - posA.dy;
    final dist = sqrt(dx * dx + dy * dy);

    if (dist <= 0) return posA;

    final nx = dx / dist;
    final ny = dy / dist;

    final startEdge = Offset(
      posA.dx + nx * halfNode,
      posA.dy + ny * halfNode,
    );
    final endEdge = Offset(
      posB.dx - nx * halfNode,
      posB.dy - ny * halfNode,
    );

    return Offset(
      (startEdge.dx + endEdge.dx) / 2,
      (startEdge.dy + endEdge.dy) / 2,
    );
  }

  // ── Private: Edge routing methods ─────────────────────────────────

  /// Route a parent→child edge: solid vertical bezier with
  /// horizontal offset for multiple children.
  Path _routeParentChildEdge({
    required Offset parentPos,
    required Offset childPos,
    required double halfNode,
    required int childIndex,
    required int totalChildren,
  }) {
    // Start from bottom center of parent
    final start = Offset(parentPos.dx, parentPos.dy + halfNode);
    // End at top center of child
    var endX = childPos.dx;
    final end = Offset(endX, childPos.dy - halfNode);

    // Apply horizontal offset for multiple children
    if (totalChildren > 1) {
      final offset = (childIndex - (totalChildren - 1) / 2) *
          _config.childHorizontalOffset;
      endX = childPos.dx + offset;
    }

    // Control points at midpoint Y
    final midY = (start.dy + end.dy) / 2;
    final control1 = Offset(start.dx, midY);
    final control2 = Offset(endX, midY);

    final path = Path();
    path.moveTo(start.dx, start.dy);
    path.cubicTo(
      control1.dx, control1.dy,
      control2.dx, control2.dy,
      endX, end.dy,
    );
    return path;
  }

  /// Route a spouse edge: horizontal line with ring icon at midpoint.
  ///
  /// For divorced spouses, the path is the same but styling is dashed.
  Path _routeSpouseEdge({
    required Offset posA,
    required Offset posB,
    required double halfNode,
    required bool isDivorced,
  }) {
    // Horizontal line between spouse nodes
    final dx = posB.dx - posA.dx;
    final direction = dx >= 0 ? 1.0 : -1.0;

    final start = Offset(posA.dx + direction * halfNode, posA.dy);
    final end = Offset(posB.dx - direction * halfNode, posB.dy);

    final path = Path();
    path.moveTo(start.dx, start.dy);

    if (isDivorced) {
      // Slight curve for divorced couples to differentiate
      final midX = (start.dx + end.dx) / 2;
      final midY = (start.dy + end.dy) / 2 - 10.0;
      path.quadraticBezierTo(midX, midY, end.dx, end.dy);
    } else {
      path.lineTo(end.dx, end.dy);
    }

    return path;
  }

  /// Route a sibling arc: dashed curved arc above the sibling group.
  ///
  /// Arc height is proportional to sibling count.
  Path _routeSiblingArc({
    required Offset posA,
    required Offset posB,
    required double halfNode,
    required bool isHalf,
    required int siblingCount,
  }) {
    // Start from top of node A
    final start = Offset(posA.dx, posA.dy - halfNode);
    // End from top of node B
    final end = Offset(posB.dx, posB.dy - halfNode);

    // Arc height proportional to sibling count
    final arcHeight = _config.siblingArcBaseHeight +
        siblingCount * _config.siblingArcHeightFactor;

    final midX = (start.dx + end.dx) / 2;
    final controlPoint = Offset(midX, start.dy - arcHeight);

    final path = Path();
    path.moveTo(start.dx, start.dy);
    path.quadraticBezierTo(
      controlPoint.dx,
      controlPoint.dy,
      end.dx,
      end.dy,
    );
    return path;
  }

  /// Route a grandparent edge: extended bezier spanning two generations.
  Path _routeGrandparentEdge({
    required Offset grandparentPos,
    required Offset grandchildPos,
    required double halfNode,
  }) {
    final start = Offset(grandparentPos.dx, grandparentPos.dy + halfNode);
    final end = Offset(grandchildPos.dx, grandchildPos.dy - halfNode);

    final midY = (start.dy + end.dy) / 2;

    // Two-stage bezier: first to a middle waypoint, then to grandchild
    final waypoint = Offset(
      (start.dx + end.dx) / 2,
      midY,
    );

    final path = Path();
    path.moveTo(start.dx, start.dy);
    path.cubicTo(
      start.dx, midY,
      waypoint.dx, midY,
      waypoint.dx, waypoint.dy,
    );
    path.cubicTo(
      waypoint.dx, midY,
      end.dx, midY,
      end.dx, end.dy,
    );
    return path;
  }

  /// Route a cousin edge: curved bezier routed below parent generation
  /// to avoid crossing parent-child lines.
  Path _routeCousinEdge({
    required Offset posA,
    required Offset posB,
    required double halfNode,
  }) {
    final start = Offset(posA.dx, posA.dy + halfNode * 0.5);
    final end = Offset(posB.dx, posB.dy + halfNode * 0.5);

    // Route below the nodes
    final midX = (start.dx + end.dx) / 2;
    final belowY = max(start.dy, end.dy) + 60.0;

    final path = Path();
    path.moveTo(start.dx, start.dy);
    path.cubicTo(
      start.dx, belowY,
      end.dx, belowY,
      end.dx, end.dy,
    );
    return path;
  }

  /// Route an extended family edge: curved bezier routed to avoid
  /// crossing parent-child lines.
  Path _routeExtendedEdge({
    required Offset posA,
    required Offset posB,
    required double halfNode,
  }) {
    final dx = posB.dx - posA.dx;
    final dy = posB.dy - posA.dy;
    final dist = sqrt(dx * dx + dy * dy);

    if (dist <= 0) {
      return Path();
    }

    // Normalize direction
    final nx = dx / dist;
    final ny = dy / dist;

    // Start and end at node edges
    final start = Offset(
      posA.dx + nx * halfNode,
      posA.dy + ny * halfNode,
    );
    final end = Offset(
      posB.dx - nx * halfNode,
      posB.dy - ny * halfNode,
    );

    // Control point offset perpendicular to the line
    final perpX = -ny * dist * _config.bezierControlOffset * 0.3;
    final perpY = nx * dist * _config.bezierControlOffset * 0.3;

    final midX = (start.dx + end.dx) / 2 + perpX;
    final midY = (start.dy + end.dy) / 2 + perpY;

    final path = Path();
    path.moveTo(start.dx, start.dy);
    path.quadraticBezierTo(midX, midY, end.dx, end.dy);
    return path;
  }

  // ── Private: Utility methods ──────────────────────────────────────

  /// Categorize a relationship key into a [RelationshipCategory].
  RelationshipCategory _categorizeKey(String key) {
    final lower = key.toLowerCase();

    if (_parentKeys.contains(lower)) return RelationshipCategory.parent;
    if (_childKeys.contains(lower)) return RelationshipCategory.child;
    if (_halfSiblingKeys.contains(lower)) return RelationshipCategory.halfSibling;
    if (_siblingKeys.contains(lower)) return RelationshipCategory.sibling;
    if (_divorcedSpouseKeys.contains(lower)) return RelationshipCategory.divorcedSpouse;
    if (_spouseKeys.contains(lower)) return RelationshipCategory.spouse;
    if (_grandparentKeys.contains(lower)) return RelationshipCategory.grandparent;
    if (_grandchildKeys.contains(lower)) return RelationshipCategory.grandchild;
    if (_auntUncleKeys.contains(lower)) return RelationshipCategory.auntUncle;
    if (_cousinKeys.contains(lower)) return RelationshipCategory.cousin;
    if (_inLawKeys.contains(lower)) return RelationshipCategory.inLaw;

    return RelationshipCategory.extended;
  }

  /// Get the child index for offset computation.
  int _getChildIndex(
    String parentId,
    Map<String, int> tempIndex,
    Map<String, int> totalCount,
  ) {
    final current = tempIndex[parentId] ?? 0;
    tempIndex[parentId] = current + 1;
    return current;
  }

  /// Count how many sibling relationships a person has.
  int _countSiblings(String personId, List<GraphRelationship> relationships) {
    var count = 0;
    for (final r in relationships) {
      if (_siblingKeys.contains(r.relationshipKey) ||
          _halfSiblingKeys.contains(r.relationshipKey)) {
        if (r.fromPersonId == personId || r.toPersonId == personId) {
          count++;
        }
      }
    }
    return count;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// EDGE RENDERING UTILITIES
// ═══════════════════════════════════════════════════════════════════════

/// Utility for painting edges with proper dash patterns.
class EdgePainter {
  /// Create a [Paint] object from an [EdgeStyle].
  static Paint createPaint(EdgeStyle style) {
    return Paint()
      ..color = style.color.withValues(alpha: style.opacity)
      ..strokeWidth = style.width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
  }

  /// Draw a dashed path by breaking it into segments.
  ///
  /// [dashLength] is the length of each dash.
  /// [gapLength] is the length of each gap between dashes.
  static Path createDashedPath(
    Path source, {
    double dashLength = 8.0,
    double gapLength = 4.0,
  }) {
    final dashedPath = Path();
    final metrics = source.computeMetrics();

    for (final metric in metrics) {
      double distance = 0.0;
      while (distance < metric.length) {
        final length = min(dashLength, metric.length - distance);
        dashedPath.addPath(
          metric.extractPath(distance, distance + length),
          Offset.zero,
        );
        distance += dashLength + gapLength;
      }
    }

    return dashedPath;
  }

  /// Draw a dotted path by using very short dashes.
  static Path createDottedPath(
    Path source, {
    double dotSpacing = 6.0,
  }) {
    return createDashedPath(
      source,
      dashLength: 2.0,
      gapLength: dotSpacing,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// RIVERPOD PROVIDERS
// ═══════════════════════════════════════════════════════════════════════

/// Provider for the [EdgeRouter] instance.
final edgeRouterProvider = Provider<EdgeRouter>((ref) {
  return EdgeRouter();
});

/// Provider for computed edge paths.
///
/// Input: positions, relationships, nodeSize, zoomLevel.
/// Output: Map of edgeId → Path.
final edgePathsProvider = Provider.family<Map<String, Path>,
    ({Map<String, Offset> positions, List<GraphRelationship> relationships, double nodeSize, double zoomLevel})>(
  (ref, params) {
    final router = ref.watch(edgeRouterProvider);
    return router.computePaths(
      positions: params.positions,
      relationships: params.relationships,
      nodeSize: params.nodeSize,
      zoomLevel: params.zoomLevel,
    );
  },
);

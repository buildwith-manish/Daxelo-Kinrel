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
  ///
  /// v57 BUG 1 FIX: Changed from 100.0 to 56.0 — the actual rendered
  /// node diameter from GraphNodeStateResolver.resolveSize() is 48–64px
  /// depending on viewport. Using 100.0 caused halfNode=50px which made
  /// lines start/end 50px inside the node center instead of at the
  /// boundary. 56.0 is the median value (tablet/phone landscape).
  /// Callers should pass the exact resolveSize() value when available.
  final double nodeSize;

  const EdgeRouterConfig({
    this.childHorizontalOffset = 20.0,
    this.siblingArcHeightFactor = 10.0,
    this.siblingArcBaseHeight = 40.0,
    this.bezierControlOffset = 0.5,
    this.nodeSize = 56.0,
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
  ///
  /// v57: Also populates [controlPoints] for each edge so callers can
  /// compute the correct t=0.5 bezier midpoint (Bug 4 fix).
  Map<String, Path> computePaths({
    required Map<String, Offset> positions,
    required List<GraphRelationship> relationships,
    required double nodeSize,
    required double zoomLevel,
  }) {
    final paths = <String, Path>{};
    // v57 Bug 4: Store control points for each edge so computeMidpoint
    // can use the bezier t=0.5 formula instead of the linear midpoint.
    controlPoints = <String, (Offset, Offset)>{};

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
            allPositions: positions, // v57 Bug 5: pass for collision avoidance
            parentPosId: r.toPersonId,
            childPosId: r.fromPersonId,
          ),
        RelationshipCategory.child => _routeParentChildEdge(
            parentPos: posFrom, // fromPerson is the parent
            childPos: posTo, // toPerson is the child
            halfNode: halfNode,
            childIndex: _getChildIndex(r.fromPersonId, tempIndex, parentChildCount),
            totalChildren: parentChildCount[r.fromPersonId] ?? 1,
            allPositions: positions, // v57 Bug 5: pass for collision avoidance
            parentPosId: r.fromPersonId,
            childPosId: r.toPersonId,
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

  /// v57 Bug 4: Control points for each edge, populated by computePaths.
  /// Used by computeMidpoint to calculate the t=0.5 bezier point.
  /// Key = edge ID, value = (controlPoint1, controlPoint2).
  /// For quadratic beziers (sibling arcs), controlPoint2 is unused.
  Map<String, (Offset, Offset)> controlPoints = {};

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
  ///
  /// v57 Bug 4 FIX: If [edgeId] is provided and control points were
  /// stored during computePaths(), uses the cubic bezier t=0.5 formula:
  ///   B(0.5) = 0.125·P0 + 0.375·CP1 + 0.375·CP2 + 0.125·P3
  /// This ensures the dot sits ON the curve, not at the linear midpoint.
  ///
  /// Falls back to linear midpoint if no control points are available.
  Offset computeMidpoint({
    required Offset posA,
    required Offset posB,
    required double nodeSize,
    String? edgeId,
    Offset? controlPoint1,
    Offset? controlPoint2,
  }) {
    final halfNode = nodeSize / 2;

    // Adjust start and end to node edges (direction-vector clipping)
    final dx = posB.dx - posA.dx;
    final dy = posB.dy - posA.dy;
    final dist = sqrt(dx * dx + dy * dy);

    if (dist <= 0) return posA;

    final nx = dx / dist;
    final ny = dy / dist;

    final p0 = Offset(
      posA.dx + nx * halfNode,
      posA.dy + ny * halfNode,
    );
    final p3 = Offset(
      posB.dx - nx * halfNode,
      posB.dy - ny * halfNode,
    );

    // v57 Bug 4: Try to get control points from the stored map first.
    Offset? cp1 = controlPoint1;
    Offset? cp2 = controlPoint2;
    if (edgeId != null && cp1 == null && controlPoints.containsKey(edgeId)) {
      final stored = controlPoints[edgeId]!;
      cp1 = stored.$1;
      cp2 = stored.$2;
    }

    // If control points provided, use cubic bezier t=0.5 formula.
    if (cp1 != null && cp2 != null) {
      return Offset(
        0.125 * p0.dx + 0.375 * cp1.dx + 0.375 * cp2.dx + 0.125 * p3.dx,
        0.125 * p0.dy + 0.375 * cp1.dy + 0.375 * cp2.dy + 0.125 * p3.dy,
      );
    }

    // If only one control point (quadratic bezier), use t=0.5 formula:
    // B(0.5) = 0.25·P0 + 0.5·P1 + 0.25·P2
    if (cp1 != null) {
      return Offset(
        0.25 * p0.dx + 0.5 * cp1.dx + 0.25 * p3.dx,
        0.25 * p0.dy + 0.5 * cp1.dy + 0.25 * p3.dy,
      );
    }

    // Fallback: linear midpoint.
    return Offset(
      (p0.dx + p3.dx) / 2,
      (p0.dy + p3.dy) / 2,
    );
  }

  // ── Private: Edge routing methods ─────────────────────────────────

  /// Route a parent→child edge: solid vertical bezier with
  /// horizontal offset for multiple children.
  ///
  /// v57 Bug 2 FIX: Control points use 35% vertical offset instead of
  /// midY, creating a genuine S-curve even when nodes share the same X.
  ///
  /// v57 Bug 5 FIX: Checks allPositions for intermediate nodes that
  /// fall within halfNode+15px of the line path. If found, adds a
  /// lateral offset to both control points to steer around the obstacle.
  Path _routeParentChildEdge({
    required Offset parentPos,
    required Offset childPos,
    required double halfNode,
    required int childIndex,
    required int totalChildren,
    Map<String, Offset>? allPositions,
    String? parentPosId,
    String? childPosId,
  }) {
    // Compute endX first with horizontal offset for siblings
    var endX = childPos.dx;
    if (totalChildren > 1) {
      final offset = (childIndex - (totalChildren - 1) / 2) *
          _config.childHorizontalOffset;
      endX = childPos.dx + offset;
    }

    // Start from bottom center of parent, end at top center of child
    final start = Offset(parentPos.dx, parentPos.dy + halfNode);
    final end = Offset(endX, childPos.dy - halfNode);

    // v57 Bug 2: Control points at 35% of vertical distance (not midY).
    // This creates a genuine S-curve even when start.dx == end.dx.
    final totalDy = end.dy - start.dy;
    var control1 = Offset(start.dx, start.dy + totalDy * 0.35);
    var control2 = Offset(endX, end.dy - totalDy * 0.35);

    // v57 Bug 5: Collision avoidance — if any other node sits within
    // halfNode+15px of the line path, push control points laterally.
    if (allPositions != null) {
      final minY = start.dy < end.dy ? start.dy : end.dy;
      final maxY = start.dy > end.dy ? start.dy : end.dy;
      final lineX = start.dx;

      for (final entry in allPositions.entries) {
        // Skip the two endpoint nodes
        if (entry.key == parentPosId || entry.key == childPosId) continue;

        final otherPos = entry.value;

        // Is this node between the two endpoints vertically?
        if (otherPos.dy < minY || otherPos.dy > maxY) continue;

        // Is this node close to the line horizontally?
        final distToLine = (otherPos.dx - lineX).abs();
        if (distToLine < halfNode + 15) {
          // Push control points away from the obstacle node.
          // If obstacle is to the right, push left; if left, push right.
          final pushDir = otherPos.dx >= lineX ? -1.0 : 1.0;
          final pushAmount = (halfNode + 20) * pushDir;
          control1 = Offset(control1.dx + pushAmount, control1.dy);
          control2 = Offset(control2.dx + pushAmount, control2.dy);
          break; // One push is enough
        }
      }
    }

    final path = Path();
    path.moveTo(start.dx, start.dy);
    path.cubicTo(
      control1.dx, control1.dy,
      control2.dx, control2.dy,
      end.dx, end.dy,
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
  /// v57 Bug 3 FIX: Arc height is now based on the DISTANCE between
  /// this specific pair of nodes, not the sibling count. This means:
  ///   - Arcs to nearby siblings are small and tight
  ///   - Arcs to far siblings are tall and spread out
  ///   - Arcs no longer all peak at the same height and overlap
  ///
  /// The control point is placed above BOTH nodes (topY - arcHeight),
  /// guaranteeing the arc curves UP and OVER, never dipping through
  /// intermediate nodes.
  Path _routeSiblingArc({
    required Offset posA,
    required Offset posB,
    required double halfNode,
    required bool isHalf,
    required int siblingCount,
  }) {
    // Start from top of node A, end at top of node B
    final start = Offset(posA.dx, posA.dy - halfNode);
    final end = Offset(posB.dx, posB.dy - halfNode);

    // v57 Bug 3: Arc height based on pair distance, not sibling count.
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final pairDistance = sqrt(dx * dx + dy * dy);
    final arcHeight = max(60.0, pairDistance * 0.45);

    // Peak must be above BOTH nodes
    final topY = min(start.dy, end.dy);
    final midX = (start.dx + end.dx) / 2;
    final controlPoint = Offset(midX, topY - arcHeight);

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

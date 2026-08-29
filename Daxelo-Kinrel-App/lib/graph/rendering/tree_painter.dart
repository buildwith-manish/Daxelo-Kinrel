// lib/graph/rendering/tree_painter.dart
//
// DAXELO KINREL — Tree Painter (orthogonal connectors)
//
// Family Space: Graph ↔ Tree (↔ Map) — Implementation Prompt §5.
//
// Draws straight / orthogonal connector lines between generation rows
// in the Tree view:
//   - Parent → child: vertical line down from parent's bottom-center,
//     then a horizontal "tee" joining all siblings, then vertical
//     lines down to each child's top-center.
//   - Spouse ↔ spouse: horizontal line between the two node centers
//     at the same Y coordinate.
//
// No physics, no curves — purely algebraic. The Tree view's [FamilyTreeView]
// invokes this painter inside a [CustomPaint] layered behind the positioned
// node widgets.
//
// The painter is generation-aware: it reads the `relationshipKey` of each
// edge to decide which connector style to draw:
//   - keys ∈ {spouse, husband, wife, partner} → spouse connector
//   - keys ∈ {parent, father, mother, grandparent, ...} OR
//     keys ∈ {child, son, daughter, grandchild} → parent→child connector
//   - anything else → skip (no connector drawn)
//
// Reuses the relationship-key sets defined on [HierarchicalLayout] so the
// painter and the layout engine agree on what counts as a "parent" edge.

import 'package:flutter/material.dart';

/// A painter that draws orthogonal connectors between Tree view nodes.
///
/// The Tree view passes:
///   - `positions`: the layout result — `Map<personId, Offset>`.
///   - `edges`: the deduplicated relationship list (each edge appears once).
///   - `nodeSize`: the width/height of each node tile (used to start/end
///     connectors at the node edge, not the center).
///   - `color`: the connector color (defaults to a dim slate).
///   - `strokeWidth`: connector line width.
class TreePainter extends CustomPainter {
  TreePainter({
    required this.positions,
    required this.edges,
    this.nodeSize = const Size(96.0, 96.0),
    this.color = const Color(0x66E2E8F0),
    this.strokeWidth = 1.5,
    this.focusedPersonId,
    this.hiddenPersonIds = const {},
  });

  /// Map<personId, Offset> — the center coordinates of each Tree node.
  final Map<String, Offset> positions;

  /// List of (fromPersonId, toPersonId, relationshipKey) tuples for each
  /// edge in the tree. The painter iterates this list once per paint.
  final List<({String fromId, String toId, String relationshipKey})> edges;

  /// Node tile size — connectors terminate at the node's edge, not its
  /// center, so they don't visually cross the avatar.
  final Size nodeSize;

  /// Connector color. Default is a dim slate that recedes behind nodes.
  final Color color;

  /// Connector stroke width in dp.
  final double strokeWidth;

  /// The currently focused person ID (if any). Edges touching the focused
  /// person are painted with a brighter accent so the user can visually
  /// trace their relationships.
  final String? focusedPersonId;

  /// Set of person IDs whose subtree is currently collapsed. Edges to
  /// hidden persons are skipped (they'd draw connectors to nowhere).
  final Set<String> hiddenPersonIds;

  static const Set<String> _spouseKeys = {
    'spouse', 'husband', 'wife', 'partner',
  };

  static const Set<String> _parentKeys = {
    'parent', 'father', 'mother',
    'grandparent', 'grandfather', 'grandmother',
  };

  static const Set<String> _childKeys = {
    'child', 'son', 'daughter', 'grandchild',
  };

  // Public aliases for the relationship-key sets, so downstream code
  // (e.g., the Tree view when classifying edges) can reuse the same
  // definitions the painter uses.
  static const Set<String> kSpouseKeys = _spouseKeys;
  static const Set<String> kParentKeys = _parentKeys;
  static const Set<String> kChildKeys = _childKeys;

  @override
  void paint(Canvas canvas, Size size) {
    if (positions.isEmpty || edges.isEmpty) return;

    final defaultPaint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final focusPaint = Paint()
      ..color = const Color(0xFFFFB547)
      ..strokeWidth = strokeWidth * 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final edge in edges) {
      final fromPos = positions[edge.fromId];
      final toPos = positions[edge.toId];
      if (fromPos == null || toPos == null) continue;
      if (hiddenPersonIds.contains(edge.fromId) ||
          hiddenPersonIds.contains(edge.toId)) {
        continue;
      }

      final touchesFocus = focusedPersonId != null &&
          (focusedPersonId == edge.fromId || focusedPersonId == edge.toId);
      final paint = touchesFocus ? focusPaint : defaultPaint;

      final key = edge.relationshipKey.toLowerCase();

      if (_spouseKeys.contains(key)) {
        _drawSpouseConnector(canvas, fromPos, toPos, paint);
      } else if (_parentKeys.contains(key) || _childKeys.contains(key)) {
        _drawParentChildConnector(canvas, fromPos, toPos, paint);
      }
      // Other relationship types (e.g. 'sibling', 'uncle') are not drawn
      // as connectors — the Tree view emphasizes structural lineage over
      // collateral relationships. The Graph view remains the explorer.
    }
  }

  /// Draws a horizontal line between two same-row spouses. The line
  /// terminates at each node's horizontal edge (not the center).
  void _drawSpouseConnector(
    Canvas canvas,
    Offset from,
    Offset to,
    Paint paint,
  ) {
    // Same Y? Draw a straight horizontal line.
    if ((from.dy - to.dy).abs() < 1.0) {
      final halfWidth = nodeSize.width / 2;
      canvas.drawLine(
        Offset(from.dx + halfWidth, from.dy),
        Offset(to.dx - halfWidth, to.dy),
        paint,
      );
    } else {
      // Different Y (rare — only if a spouse was placed one row off).
      // Draw an L-shape: horizontal then vertical.
      final halfWidth = nodeSize.width / 2;
      final midX = (from.dx + to.dx) / 2;
      canvas.drawLine(
        Offset(from.dx + halfWidth, from.dy),
        Offset(midX, from.dy),
        paint,
      );
      canvas.drawLine(
        Offset(midX, from.dy),
        Offset(midX, to.dy),
        paint,
      );
      canvas.drawLine(
        Offset(midX, to.dy),
        Offset(to.dx - halfWidth, to.dy),
        paint,
      );
    }
  }

  /// Draws an orthogonal parent→child connector:
  ///   - Vertical line down from parent's bottom-center.
  ///   - Horizontal "tee" at the midpoint Y.
  ///   - Vertical line down to child's top-center.
  ///
  /// Convention: the parent is the node with the SMALLER Y (higher up
  /// on screen). The HierarchicalLayout always places ancestors above
  /// descendants, so `from.dy < to.dy` is the normal case. If they're
  /// inverted, we still draw a valid L — just with the tee at the
  /// child's midpoint instead.
  void _drawParentChildConnector(
    Canvas canvas,
    Offset from,
    Offset to,
    Paint paint,
  ) {
    final halfHeight = nodeSize.height / 2;

    // Determine which end is the parent (smaller Y).
    final Offset parent;
    final Offset child;
    if (from.dy <= to.dy) {
      parent = from;
      child = to;
    } else {
      parent = to;
      child = from;
    }

    // If they share the same X coordinate, just draw one vertical line.
    if ((parent.dx - child.dx).abs() < 1.0) {
      canvas.drawLine(
        Offset(parent.dx, parent.dy + halfHeight),
        Offset(child.dx, child.dy - halfHeight),
        paint,
      );
      return;
    }

    // Three-segment orthogonal connector:
    //   1. Vertical down from parent's bottom-center to midpoint Y.
    //   2. Horizontal from parent's X to child's X at midpoint Y.
    //   3. Vertical down from midpoint Y to child's top-center.
    final midY = (parent.dy + child.dy) / 2;

    canvas.drawLine(
      Offset(parent.dx, parent.dy + halfHeight),
      Offset(parent.dx, midY),
      paint,
    );
    canvas.drawLine(
      Offset(parent.dx, midY),
      Offset(child.dx, midY),
      paint,
    );
    canvas.drawLine(
      Offset(child.dx, midY),
      Offset(child.dx, child.dy - halfHeight),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant TreePainter oldDelegate) {
    return oldDelegate.positions != positions ||
        oldDelegate.edges != edges ||
        oldDelegate.focusedPersonId != focusedPersonId ||
        oldDelegate.hiddenPersonIds != hiddenPersonIds ||
        oldDelegate.nodeSize != nodeSize ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

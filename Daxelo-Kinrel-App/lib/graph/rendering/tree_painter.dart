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

import 'dart:math' show sqrt;

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
    this.nodeSize = const Size(120.0, 72.0),
    // UX (v5.130): Bumped default color alpha from 0x66 → 0x88 (40% → 53%
    // opacity) and stroke width from 1.5 → 1.8 so connectors are easier
    // to trace at typical zoom levels. The previous values made sibling
    // and parent-child edges almost invisible against the dark canvas
    // in dense regions. Geometry / shape / dash patterns unchanged.
    this.color = const Color(0x88E2E8F0),
    this.strokeWidth = 1.8,
    this.focusedPersonId,
    this.hiddenPersonIds = const {},
    this.secondarySpouseIds = const {},
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

  /// v5.128 §2.3: Set of person IDs that are SECONDARY spouses (index >= 1
  /// in their partner's spouses list). The painter renders their edges
  /// with a DASHED connector to distinguish them from the primary couple.
  /// Empty by default (no secondary spouses).
  final Set<String> secondarySpouseIds;

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

    // UX (v5.130): Focus-edge stroke multiplier bumped from 1.6 → 1.85 so
    // the focused person's connections stand out more clearly against the
    // surrounding default edges. Combined with the brighter default color,
    // this strengthens the visual hierarchy between primary (focused) and
    // secondary (default) relationship lines.
    final focusPaint = Paint()
      ..color = const Color(0xFFFFB547)
      ..strokeWidth = strokeWidth * 1.85
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

      // v5.128 §2.3: secondary spouses get a DASHED connector.
      final isSecondarySpouseEdge =
          secondarySpouseIds.contains(edge.fromId) ||
              secondarySpouseIds.contains(edge.toId);

      if (_spouseKeys.contains(key)) {
        if (isSecondarySpouseEdge) {
          _drawSpouseConnectorDashed(canvas, fromPos, toPos, paint);
        } else {
          _drawSpouseConnector(canvas, fromPos, toPos, paint);
        }
      } else if (key == 'sibling') {
        // v5.129: Sibling edges — draw a horizontal dashed line between
        // same-generation siblings. Visually distinct from spouse
        // (solid) and parent-child (orthogonal tee).
        _drawSiblingConnector(canvas, fromPos, toPos, paint);
      } else if (_parentKeys.contains(key) || _childKeys.contains(key)) {
        if (isSecondarySpouseEdge) {
          _drawParentChildConnectorDashed(canvas, fromPos, toPos, paint);
        } else {
          _drawParentChildConnector(canvas, fromPos, toPos, paint);
        }
      }
      // Other relationship types (e.g. 'sibling', 'uncle') are not drawn
      // as connectors — the Tree view emphasizes structural lineage over
      // collateral relationships. The Graph view remains the explorer.
    }
  }

  /// v5.126: Adapter-based paint for the PDF exporter.
  ///
  /// Same connector geometry as [paint], but writes to a [TreeCanvasAdapter]
  /// instead of a Flutter `Canvas`. The PDF exporter wraps a `PdfGraphics`
  /// in a `PdfTreeCanvasAdapter` and calls this method to produce a
  /// vector PDF — pixel-crisp at any zoom, no rasterization.
  ///
  /// Public so the exporter (in a sibling file) can call it without
  /// duplicating the connector-drawing logic.
  void paintToAdapter(TreeCanvasAdapter adapter) {
    if (positions.isEmpty || edges.isEmpty) return;

    const focusColor = Color(0xFFFFB547);

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
      final lineColor = touchesFocus ? focusColor : color;
      // UX (v5.130): Focus-edge stroke multiplier aligned with the on-screen
      // painter (1.85 instead of 1.6) so PDF exports match the live view.
      final lineStroke = touchesFocus ? strokeWidth * 1.85 : strokeWidth;

      final key = edge.relationshipKey.toLowerCase();

      if (_spouseKeys.contains(key)) {
        _drawSpouseConnectorAdapter(adapter, fromPos, toPos, lineColor, lineStroke);
      } else if (_parentKeys.contains(key) || _childKeys.contains(key)) {
        _drawParentChildConnectorAdapter(adapter, fromPos, toPos, lineColor, lineStroke);
      }
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

  /// v5.128 §2.3: Dashed variant of [_drawSpouseConnector] for secondary
  /// spouses. Uses 4dp dash / 3dp gap to visually distinguish from the
  /// primary couple's solid connector.
  void _drawSpouseConnectorDashed(
    Canvas canvas,
    Offset from,
    Offset to,
    Paint paint,
  ) {
    final halfWidth = nodeSize.width / 2;
    if ((from.dy - to.dy).abs() < 1.0) {
      _drawDashedLine(
        canvas,
        Offset(from.dx + halfWidth, from.dy),
        Offset(to.dx - halfWidth, to.dy),
        paint,
      );
    } else {
      final midX = (from.dx + to.dx) / 2;
      _drawDashedLine(
        canvas,
        Offset(from.dx + halfWidth, from.dy),
        Offset(midX, from.dy),
        paint,
      );
      _drawDashedLine(
        canvas,
        Offset(midX, from.dy),
        Offset(midX, to.dy),
        paint,
      );
      _drawDashedLine(
        canvas,
        Offset(midX, to.dy),
        Offset(to.dx - halfWidth, to.dy),
        paint,
      );
    }
  }

  /// v5.129: Draws a horizontal dashed line between two same-row
  /// siblings. Same geometry as the spouse connector, but uses
  /// dashes to visually distinguish "sibling" from "spouse/partner".
  void _drawSiblingConnector(
    Canvas canvas,
    Offset from,
    Offset to,
    Paint paint,
  ) {
    final halfWidth = nodeSize.width / 2;
    // Siblings should be at the same Y (same generation).
    // If not, draw an L-shape (rare edge case).
    if ((from.dy - to.dy).abs() < 1.0) {
      _drawDashedLine(
        canvas,
        Offset(from.dx + halfWidth, from.dy),
        Offset(to.dx - halfWidth, to.dy),
        paint,
      );
    } else {
      final midX = (from.dx + to.dx) / 2;
      _drawDashedLine(
        canvas,
        Offset(from.dx + halfWidth, from.dy),
        Offset(midX, from.dy),
        paint,
      );
      _drawDashedLine(
        canvas,
        Offset(midX, from.dy),
        Offset(midX, to.dy),
        paint,
      );
      _drawDashedLine(
        canvas,
        Offset(midX, to.dy),
        Offset(to.dx - halfWidth, to.dy),
        paint,
      );
    }
  }

  /// v5.128 §2.3: Helper — draws a single dashed line segment.
  /// 4dp dash, 3dp gap (visually distinct from solid lines at typical
  /// zoom levels).
  void _drawDashedLine(
    Canvas canvas,
    Offset from,
    Offset to,
    Paint paint,
  ) {
    const dashLength = 4.0;
    const gapLength = 3.0;
    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    final totalLength = (dx * dx + dy * dy);
    if (totalLength <= 0) return;
    final distance = sqrt(totalLength);
    final stepX = dx / distance;
    final stepY = dy / distance;
    var pos = 0.0;
    while (pos < distance) {
      final dashEnd = (pos + dashLength).clamp(0.0, distance);
      canvas.drawLine(
        Offset(from.dx + stepX * pos, from.dy + stepY * pos),
        Offset(from.dx + stepX * dashEnd, from.dy + stepY * dashEnd),
        paint,
      );
      pos += dashLength + gapLength;
    }
  }

  /// v5.126: Adapter-based variant of [_drawSpouseConnector] for the PDF
  /// exporter. Mirrors the geometry exactly so PDF + screen match.
  void _drawSpouseConnectorAdapter(
    TreeCanvasAdapter adapter,
    Offset from,
    Offset to,
    Color color,
    double strokeWidth,
  ) {
    final halfWidth = nodeSize.width / 2;
    if ((from.dy - to.dy).abs() < 1.0) {
      adapter.drawLine(
        Offset(from.dx + halfWidth, from.dy),
        Offset(to.dx - halfWidth, to.dy),
        color,
        strokeWidth,
      );
    } else {
      final midX = (from.dx + to.dx) / 2;
      adapter.drawLine(
        Offset(from.dx + halfWidth, from.dy),
        Offset(midX, from.dy),
        color,
        strokeWidth,
      );
      adapter.drawLine(
        Offset(midX, from.dy),
        Offset(midX, to.dy),
        color,
        strokeWidth,
      );
      adapter.drawLine(
        Offset(midX, to.dy),
        Offset(to.dx - halfWidth, to.dy),
        color,
        strokeWidth,
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

  /// v5.126: Adapter-based variant of [_drawParentChildConnector] for the
  /// PDF exporter. Mirrors the geometry exactly so PDF + screen match.
  void _drawParentChildConnectorAdapter(
    TreeCanvasAdapter adapter,
    Offset from,
    Offset to,
    Color color,
    double strokeWidth,
  ) {
    final halfHeight = nodeSize.height / 2;

    final Offset parent;
    final Offset child;
    if (from.dy <= to.dy) {
      parent = from;
      child = to;
    } else {
      parent = to;
      child = from;
    }

    if ((parent.dx - child.dx).abs() < 1.0) {
      adapter.drawLine(
        Offset(parent.dx, parent.dy + halfHeight),
        Offset(child.dx, child.dy - halfHeight),
        color,
        strokeWidth,
      );
      return;
    }

    final midY = (parent.dy + child.dy) / 2;

    adapter.drawLine(
      Offset(parent.dx, parent.dy + halfHeight),
      Offset(parent.dx, midY),
      color,
      strokeWidth,
    );
    adapter.drawLine(
      Offset(parent.dx, midY),
      Offset(child.dx, midY),
      color,
      strokeWidth,
    );
    adapter.drawLine(
      Offset(child.dx, midY),
      Offset(child.dx, child.dy - halfHeight),
      color,
      strokeWidth,
    );
  }

  /// v5.128 §2.3: Dashed variant of [_drawParentChildConnector] — used
  /// when one endpoint is a secondary spouse (rare, but supported for
  /// completeness). Same orthogonal geometry, dashed rendering.
  void _drawParentChildConnectorDashed(
    Canvas canvas,
    Offset from,
    Offset to,
    Paint paint,
  ) {
    final halfHeight = nodeSize.height / 2;

    final Offset parent;
    final Offset child;
    if (from.dy <= to.dy) {
      parent = from;
      child = to;
    } else {
      parent = to;
      child = from;
    }

    if ((parent.dx - child.dx).abs() < 1.0) {
      _drawDashedLine(
        canvas,
        Offset(parent.dx, parent.dy + halfHeight),
        Offset(child.dx, child.dy - halfHeight),
        paint,
      );
      return;
    }

    final midY = (parent.dy + child.dy) / 2;
    _drawDashedLine(
      canvas,
      Offset(parent.dx, parent.dy + halfHeight),
      Offset(parent.dx, midY),
      paint,
    );
    _drawDashedLine(
      canvas,
      Offset(parent.dx, midY),
      Offset(child.dx, midY),
      paint,
    );
    _drawDashedLine(
      canvas,
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
        oldDelegate.secondarySpouseIds != secondarySpouseIds ||
        oldDelegate.nodeSize != nodeSize ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// v5.126: Canvas adapter — abstraction over Flutter's `Canvas` and the
// `pdf` package's `PdfGraphics`. Lets the same TreePainter draw to both
// screen (raster) and PDF (vector) without duplicating connector geometry.
// ═══════════════════════════════════════════════════════════════════════

/// Minimal canvas abstraction used by [TreePainter.paintToAdapter].
///
/// Two implementations:
///   - [FlutterTreeCanvasAdapter] wraps a Flutter `Canvas` (used by the
///     in-app Tree view — preserves the existing `CustomPainter.paint`
///     codepath, no behavior change).
///   - [PdfTreeCanvasAdapter] wraps a `PdfGraphics` (used by the PDF
///     exporter in `tree_pdf_exporter.dart`).
abstract class TreeCanvasAdapter {
  /// Draw a single line segment from [from] to [to] with the given
  /// [color] and [strokeWidth]. Both coordinates are in the layout's
  /// canonical space (origin top-left, Y increases downward).
  void drawLine(Offset from, Offset to, Color color, double strokeWidth);
}

/// Adapter that writes to a Flutter `Canvas` (the in-app Tree view).
class FlutterTreeCanvasAdapter implements TreeCanvasAdapter {
  FlutterTreeCanvasAdapter(this._canvas);

  final Canvas _canvas;

  @override
  void drawLine(Offset from, Offset to, Color color, double strokeWidth) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    _canvas.drawLine(from, to, paint);
  }
}

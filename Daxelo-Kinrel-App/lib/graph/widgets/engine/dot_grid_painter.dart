// lib/graph/widgets/engine/dot_grid_painter.dart
// P0.4: Extracted from family_graph_engine_view.dart.

import 'package:flutter/material.dart';

/// Paints a very faint dot-grid on the graph background for spatial texture.
/// Static (shouldRepaint returns false) — painted once, not per-frame.
class DotGridPainter extends CustomPainter {
  const DotGridPainter({required this.color, this.spacing = 32.0});
  final Color color;
  final double spacing;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (double y = 0; y < size.height; y += spacing) {
      for (double x = 0; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), 1.0, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant DotGridPainter oldDelegate) => false;
}

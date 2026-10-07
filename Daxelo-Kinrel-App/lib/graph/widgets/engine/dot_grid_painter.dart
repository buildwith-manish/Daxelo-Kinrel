// lib/graph/widgets/engine/dot_grid_painter.dart
// P0.4: Extracted from family_graph_engine_view.dart.

import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Paints a very faint dot-grid on the graph background for spatial texture.
/// Static (shouldRepaint returns false) — painted once, not per-frame.
class DotGridPainter extends CustomPainter {
  const DotGridPainter({required this.color, this.spacing = 32.0});
  final Color color;
  final double spacing;

  @override
  void paint(Canvas canvas, Size size) {
    // PERF (raster audit): previously this method called canvas.drawCircle
    // once per grid intersection — for a 2000×1500 canvas at spacing=32
    // that's ~3000 individual drawCircle calls per paint. Each drawCircle
    // is a separate Skia draw command, and even though shouldRepaint
    // returns false so the painter only fires once, the per-paint cost
    // showed up as a one-time stutter on first frame after canvas mount.
    //
    // Replaced with a single canvas.drawRawPoints(PointMode.points, ...)
    // call — Skia batches all points into one GPU draw command. The 1px
    // point is visually identical to the 1px-radius circle it replaced
    // (a 1px-radius circle is rasterized as a single pixel anyway).
    final paint = Paint()..color = color;
    final double w = size.width;
    final double h = size.height;
    final int cols = (w / spacing).ceil();
    final int rows = (h / spacing).ceil();
    final int count = cols * rows;
    if (count <= 0) return;
    final Float32List pts = Float32List(count * 2);
    int i = 0;
    for (int r = 0; r < rows; r++) {
      final double y = r * spacing;
      for (int c = 0; c < cols; c++) {
        pts[i++] = c * spacing;
        pts[i++] = y;
      }
    }
    canvas.drawRawPoints(PointMode.points, pts, paint);
  }

  @override
  bool shouldRepaint(covariant DotGridPainter oldDelegate) => false;
}

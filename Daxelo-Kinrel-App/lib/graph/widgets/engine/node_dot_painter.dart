// lib/graph/widgets/engine/node_dot_painter.dart
// P0.4: Extracted from family_graph_engine_view.dart.

import 'package:flutter/material.dart';
import 'dot.dart' show Dot;

/// Draws every visible node as a dot in ONE painter — avoids thousands of
/// widgets when fully zoomed out (the 2000-node case).
///
/// v97: Node radius is now ZOOM-AWARE. The painter receives the current
/// camera zoom and computes graph-space radii from desired screen-space
/// radii: graphRadius = screenRadius / zoom.
///
/// v5.109: Increased minimum screen-space radii so nodes remain
/// recognizable and tappable even at maximum zoom-out:
///   normal: 10px radius (20px diameter — meets 44px tap target via
///           the expanded hit-test radius in lod_render_metrics)
///   emphasised: 14px radius (28px diameter)
class NodeDotPainter extends CustomPainter {
  NodeDotPainter(this.dots, {this.zoom = 1.0});

  final List<Dot> dots;
  final double zoom;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = true;
    final ringPaint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke;

    final safeZoom = (zoom > 0.001 && zoom.isFinite) ? zoom : 1.0;
    // v5.109: Increased from 6.0/9.0 to 10.0/14.0 for better visibility.
    const screenNormalR = 10.0;
    const screenEmphasisR = 14.0;
    const screenRingStroke = 2.5;
    final graphNormalR = screenNormalR / safeZoom;
    final graphEmphasisR = screenEmphasisR / safeZoom;
    final graphRingStroke = screenRingStroke / safeZoom;
    final graphRingOffset = 4.0 / safeZoom;

    ringPaint.strokeWidth = graphRingStroke;

    for (final Dot d in dots) {
      final radius = d.isEmphasised ? graphEmphasisR : graphNormalR;
      paint.color = d.color;

      if (d.isEmphasised) {
        ringPaint.color = d.color.withValues(alpha: 0.5);
        canvas.drawCircle(d.pos, radius + graphRingOffset, ringPaint);
      }

      canvas.drawCircle(d.pos, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant NodeDotPainter old) =>
      old.dots.length != dots.length ||
      !identical(old.dots, dots) ||
      (old.zoom - zoom).abs() > 0.001;
}

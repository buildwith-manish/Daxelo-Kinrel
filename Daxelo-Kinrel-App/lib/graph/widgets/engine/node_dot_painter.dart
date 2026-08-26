// lib/graph/widgets/engine/node_dot_painter.dart
// P0.4: Extracted from family_graph_engine_view.dart.
//
// v5.111: Raised minimum screen-space radii from 10.0/14.0 to 14.0/20.0
// so dots remain visible markers of branch structure even at maximum
// zoom-out. The DOT tier is now reserved for TRUE far-zoom only
// (zoom < 0.16 default) — the new MINI and MICRO tiers handle the
// intermediate zoom range with circle + initial / circle + ring
// rendering respectively.

import 'package:flutter/material.dart';
import 'dot.dart' show Dot;

/// Draws every visible node as a dot in ONE painter — avoids thousands of
/// widgets when fully zoomed out (the 2000-node case).
///
/// v5.111: Raised minimum screen-space radii:
///   normal: 14px radius (28px diameter — was 10px / 20px)
///   emphasised: 20px radius (40px diameter — was 14px / 28px)
///
/// These sizes are the FINAL fallback before the graph becomes truly
/// unreadable. The new MINI tier (22px) and MICRO tier (16px) handle
/// the intermediate zoom range with more recognizable rendering, so
/// the DOT tier is only reached at extreme zoom-out where the user
/// is looking at the entire tree structure (1000+ nodes).
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
    // v5.111: Raised from 10.0/14.0 to 14.0/20.0 for better visibility.
    const screenNormalR = 14.0;
    const screenEmphasisR = 20.0;
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

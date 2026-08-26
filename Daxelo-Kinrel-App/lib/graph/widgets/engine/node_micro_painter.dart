// lib/graph/widgets/engine/node_micro_painter.dart
//
// DAXELO KINREL — v5.111 SEMANTIC ZOOM OVERHAUL
//
// Renders every visible node as a colored circle + accent ring (no
// letter) in ONE painter call. This is the MICRO tier of the 5-tier
// semantic zoom system — it sits between the MINI tier (circle +
// border + initial) and the FAR tier (basic dot).
//
// Why this painter exists:
// The MICRO tier provides a transition between the recognizable MINI
// nodes (with initials) and the anonymous FAR dots. At very low zoom
// the user can no longer read individual letters, but the colored
// circle + accent ring still conveys:
//   • Branch structure (via color clustering)
//   • Focused/selected/path nodes (via the accent ring)
//
// Screen-space clamping:
// The circle radius is 16px (normal) or 22px (emphasised) on screen
// regardless of zoom — it does NOT shrink as the user zooms out.

import 'package:flutter/material.dart';
import 'dot.dart' show Dot;

/// Draws every visible node as a colored circle + accent ring in ONE
/// painter call.
///
/// v5.111: MICRO tier of the 5-tier semantic zoom system.
///
/// Screen-space sizes (clamped — do NOT shrink with zoom):
///   normal radius:    8px (16px diameter)
///   emphasised radius: 11px (22px diameter)
///   ring stroke:      1.5px (normal), 2.0px (emphasised)
///   ring offset:      3px outside the circle
///
/// All nodes get a subtle inner border for definition. Emphasised
/// nodes (focused/selected/path) get an additional outer accent ring.
class NodeMicroPainter extends CustomPainter {
  NodeMicroPainter(this.dots, {this.zoom = 1.0});

  final List<Dot> dots;
  final double zoom;

  @override
  void paint(Canvas canvas, Size size) {
    final safeZoom = (zoom > 0.001 && zoom.isFinite) ? zoom : 1.0;

    // Screen-space clamped sizes.
    const screenNormalR = 8.0; // 16px diameter
    const screenEmphasisR = 11.0; // 22px diameter
    const screenNormalStroke = 1.0;
    const screenEmphasisStroke = 1.5;
    const screenRingOffset = 3.0;
    const screenRingStroke = 2.0;

    final graphNormalR = screenNormalR / safeZoom;
    final graphEmphasisR = screenEmphasisR / safeZoom;
    final graphNormalStroke = screenNormalStroke / safeZoom;
    final graphEmphasisStroke = screenEmphasisStroke / safeZoom;
    final graphRingOffset = screenRingOffset / safeZoom;
    final graphRingStroke = screenRingStroke / safeZoom;

    final fillPaint = Paint()..isAntiAlias = true;
    final borderPaint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke;
    final ringPaint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke;

    ringPaint.strokeWidth = graphRingStroke;

    for (final Dot d in dots) {
      final isEmph = d.isEmphasised;
      final radius = isEmph ? graphEmphasisR : graphNormalR;
      final stroke = isEmph ? graphEmphasisStroke : graphNormalStroke;

      // 1. Outer accent ring — only for emphasised nodes.
      if (isEmph) {
        ringPaint.color = d.color.withValues(alpha: 0.55);
        canvas.drawCircle(d.pos, radius + graphRingOffset, ringPaint);
      }

      // 2. Filled circle (the node body).
      fillPaint.color = d.color;
      canvas.drawCircle(d.pos, radius, fillPaint);

      // 3. Inner border for definition (darker shade of the node color).
      borderPaint.strokeWidth = stroke;
      borderPaint.color = Color.lerp(d.color, Colors.black, 0.30) ??
          d.color.withValues(alpha: 0.6);
      canvas.drawCircle(d.pos, radius, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant NodeMicroPainter old) =>
      old.dots.length != dots.length ||
      !identical(old.dots, dots) ||
      (old.zoom - zoom).abs() > 0.001;
}

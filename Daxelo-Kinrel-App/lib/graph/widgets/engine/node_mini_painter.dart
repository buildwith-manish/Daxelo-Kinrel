// lib/graph/widgets/engine/node_mini_painter.dart
//
// DAXELO KINREL — v5.111 SEMANTIC ZOOM OVERHAUL
//
// Renders every visible node as a circle + border + initial letter in
// ONE painter call. This is the MINI tier of the 5-tier semantic zoom
// system — it sits between the COMPACT tier (full 72dp GraphNode widget
// with relation label faded) and the MICRO tier (colored circle + ring,
// no letter).
//
// Why this painter exists:
// The original 3-tier system jumped from a 72dp premium GraphNode (NEAR)
// to an 8px chip (MEDIUM) to a 10px dot (FAR). The 9× shrink at the
// NEAR→MEDIUM boundary made nodes unrecognizable. The MINI tier fills
// that gap with a 22px circle + border + initial — small enough to fit
// thousands on screen, large enough to identify individuals by letter
// and color.
//
// Performance:
// Like NodeDotPainter, this is a SINGLE CustomPaint call for ALL visible
// nodes. No per-node widgets. This keeps the 1000+ member case at 60fps.
//
// Screen-space clamping:
// The circle radius is computed as screenRadius / zoom, so the on-screen
// size is ALWAYS 22px (normal) or 30px (emphasised) regardless of zoom.
// The node does NOT shrink as the user zooms out — it stays recognizable.

import 'package:flutter/material.dart';
import 'dot.dart' show Dot;

/// Draws every visible node as a circle + border + initial letter in
/// ONE painter call.
///
/// v5.111: MINI tier of the 5-tier semantic zoom system.
///
/// Screen-space sizes (clamped — do NOT shrink with zoom):
///   normal radius:    11px (22px diameter)
///   emphasised radius: 15px (30px diameter)
///   border stroke:    1.5px (normal), 2.5px (emphasised)
///   initial font size: 12px (normal), 16px (emphasised)
///
/// The initial letter is the first character of the person's name,
/// uppercased. When the name is empty, no letter is drawn (just the
/// circle + border).
class NodeMiniPainter extends CustomPainter {
  NodeMiniPainter(this.dots, {this.zoom = 1.0});

  final List<Dot> dots;
  final double zoom;

  @override
  void paint(Canvas canvas, Size size) {
    final safeZoom = (zoom > 0.001 && zoom.isFinite) ? zoom : 1.0;

    // Screen-space clamped sizes — these do NOT shrink with zoom.
    const screenNormalR = 11.0; // 22px diameter
    const screenEmphasisR = 15.0; // 30px diameter
    const screenNormalStroke = 1.5;
    const screenEmphasisStroke = 2.5;
    const screenNormalFont = 12.0;
    const screenEmphasisFont = 16.0;
    const screenRingOffset = 4.0;
    const screenRingStroke = 2.0;

    // Convert to graph-space (the canvas is in graph space — the parent
    // Transform multiplies by zoom to restore screen-space sizes).
    final graphNormalR = screenNormalR / safeZoom;
    final graphEmphasisR = screenEmphasisR / safeZoom;
    final graphNormalStroke = screenNormalStroke / safeZoom;
    final graphEmphasisStroke = screenEmphasisStroke / safeZoom;
    final graphNormalFont = screenNormalFont / safeZoom;
    final graphEmphasisFont = screenEmphasisFont / safeZoom;
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
      final fontSize = isEmph ? graphEmphasisFont : graphNormalFont;

      // 1. Emphasis ring (outside the border) — only for emphasised nodes.
      if (isEmph) {
        ringPaint.color = d.color.withValues(alpha: 0.45);
        canvas.drawCircle(d.pos, radius + graphRingOffset, ringPaint);
      }

      // 2. Filled circle (the node body).
      fillPaint.color = d.color;
      canvas.drawCircle(d.pos, radius, fillPaint);

      // 3. Border ring (darker shade of the node color for contrast).
      borderPaint.strokeWidth = stroke;
      borderPaint.color = Color.lerp(d.color, Colors.black, 0.35) ??
          d.color.withValues(alpha: 0.6);
      canvas.drawCircle(d.pos, radius, borderPaint);

      // 4. Initial letter (centered).
      final initial = d.initial;
      if (initial != null && initial.isNotEmpty) {
        _drawInitial(
          canvas,
          initial,
          d.pos,
          fontSize,
          radius,
        );
      }
    }
  }

  /// Draws a single uppercase letter centered at [center] using a
  /// TextPainter.
  void _drawInitial(
    Canvas canvas,
    String letter,
    Offset center,
    double fontSize,
    double radius,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: letter,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          height: 1.0,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: radius * 2);

    // Center the letter both horizontally and vertically.
    tp.paint(
      canvas,
      Offset(
        center.dx - tp.width / 2,
        center.dy - tp.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant NodeMiniPainter old) =>
      old.dots.length != dots.length ||
      !identical(old.dots, dots) ||
      (old.zoom - zoom).abs() > 0.001;
}

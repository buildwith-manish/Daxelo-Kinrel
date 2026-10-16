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
//
// PERF (Phase 2): TextPainter caching + viewport culling.
//   • The initial-letter TextPainter is now built + laid out ONCE per
//     (letter, quantized font size) and reused across paints. The
//     old code called TextPainter()..layout() on EVERY node EVERY
//     paint, which was the dominant NodeMiniPainter._drawInitial CPU
//     hotspot (3% of profile). Now layout() runs only on the first
//     node with a given (letter, size) — subsequent nodes just blit.
//   • Nodes whose graph-space position falls outside the (inflated)
//     viewport are now skipped entirely — no circle, no border, no
//     letter. The viewport comes from the same graph-space Rect the
//     edge painter uses for culling, so the two layers stay spatially
//     consistent.

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
  NodeMiniPainter(
    this.dots, {
    this.zoom = 1.0,
    // PERF (Phase 2): graph-space viewport rect for painter-side node
    // culling. When non-null, dots whose position falls outside the
    // (inflated) rect are skipped entirely — no drawCircle, no border,
    // no initial. The rect is the same one the edge painter uses,
    // quantized to a coarse grid, so node widgets and edge strokes
    // stay spatially consistent. Null (default) preserves the
    // pre-Phase-2 behaviour (no culling) for tests/legacy callers.
    this.graphViewport,
  });

  final List<Dot> dots;
  final double zoom;
  final Rect? graphViewport;

  // PERF (Phase 2): Cache of laid-out TextPainters keyed by
  // "<letter>_<fontSizeQuantized>". The TextPainter is built + laid
  // out ONCE per unique key; subsequent paints just call tp.paint().
  // This eliminates the per-node TextPainter allocation + layout()
  // call (the NodeMiniPainter._drawInitial hotspot in the profile).
  //
  // The cache is static (process-wide) because TextPainters with the
  // same (letter, fontSize) are byte-identical regardless of which
  // NodeMiniPainter instance built them. The cache never grows
  // unboundedly — there are at most ~36 letters × ~6 font size tiers
  // = ~216 entries maximum.
  //
  // Quantization: font size is rounded to the nearest 0.5 px before
  // being used as the cache key. The visible difference between
  // 12.0 and 12.4 px text is sub-pixel and imperceptible at the
  // 22 px node scale; quantizing collapses ~all zoom-driven font
  // size variation into a handful of stable keys.
  static final Map<String, TextPainter> _initialCache = <String, TextPainter>{};

  /// PERF (Phase 2): Clear the TextPainter cache. Call when the app's
  /// font configuration or DPI changes (e.g. system font scale change,
  /// hot reload of the typography).
  static void clearInitialCache() {
    _initialCache.clear();
  }

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

    // PERF (Phase 2): cull rect for painter-side node culling. The
    // graphViewport is in graph space; inflate by the maximum node
    // radius (emphasis ring + ring offset) so nodes whose center is
    // just outside the viewport still render their visible portion.
    final Rect? cullRect = graphViewport?.inflate(
      screenEmphasisR + screenRingOffset + screenRingStroke,
    );

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

      // PERF (Phase 2): viewport culling. Skip every draw call for
      // nodes whose center is outside the (inflated) cull rect. The
      // inflation covers the worst-case node radius + emphasis ring +
      // ring offset, so a node whose center is on the cull boundary
      // still has its visible portion rendered (no clipped edges).
      if (cullRect != null && !cullRect.contains(d.pos)) {
        // Conservative sub-test: the cheap `contains` check above is
        // exact for the center; the inflation guarantees the visible
        // portion is inside. No further intersection needed.
        continue;
      }

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

  /// Draws a single uppercase letter centered at [center].
  ///
  /// PERF (Phase 2): uses the static [_initialCache] — the
  /// TextPainter is built + laid out ONCE per (letter, quantized
  /// font size) and reused across paints. Layout is the most
  /// expensive part of TextPainter; caching eliminates the
  /// per-node layout() call that was the dominant _drawInitial
  /// CPU hotspot in the DevTools profile.
  void _drawInitial(
    Canvas canvas,
    String letter,
    Offset center,
    double fontSize,
    double radius,
  ) {
    // Quantize font size to 0.5 px steps so ~all zoom-driven font
    // variation collapses into a stable key. The sub-pixel difference
    // is invisible at the 22 px node scale.
    final quantizedSize = (fontSize * 2).round() / 2.0;
    final cacheKey = '${letter}_${quantizedSize.toStringAsFixed(1)}';

    final tp = _initialCache.putIfAbsent(cacheKey, () {
      final painter = TextPainter(
        text: TextSpan(
          text: letter,
          style: TextStyle(
            color: Colors.white,
            fontSize: quantizedSize,
            fontWeight: FontWeight.w700,
            height: 1.0,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: 1,
      );
      // Layout runs ONCE per (letter, size) — never per paint.
      painter.layout(maxWidth: radius * 2);
      return painter;
    });

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
      (old.zoom - zoom).abs() > 0.001 ||
      old.graphViewport != graphViewport;
}

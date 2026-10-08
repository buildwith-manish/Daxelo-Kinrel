// lib/graph/rendering/graph_glow.dart
//
// DAXELO KINREL — Graph Glow (flat-mode, blur-free)
//
// A small, restrained glow drawn as a single RadialGradient circle. No
// MaskFilter, no ImageFilter, no saveLayer — the gradient itself fades
// the color from the given alpha at the center to fully transparent at
// the edge, producing a soft halo purely via per-pixel color blending.
//
// Used ONLY for:
//   - The anchor ("You") node (static, no pulse)
//   - The selected or focused node (in its relationship color)
//   - The selected edge (drawn as a wider low-alpha stroke under the
//     solid stroke, instead of a blur)
//
// Rich mode (KinrelFx.rich == true) keeps its current glow code
// (MaskFilter.blur in Pseudo3DNodePainter layer 8 and _SelfNodeGlowPainter,
// ImageFilter in the edge painter's PASS D). This helper is only called
// when KinrelFx.rich == false (flat mode, the default).
//
// Caching: the Paint (with its shader) is cached per (color, size bucket)
// so it is not allocated every frame. The size bucket quantizes the
// radius to the nearest 8px — visual difference is invisible on a soft
// halo, but the cache hit rate approaches 100% during pan/zoom because
// node diameters only vary by ±1px between culler rebuilds.

import 'dart:ui' show RadialGradient, Rect;

import 'package:flutter/material.dart';

/// Tunable constants for the flat-mode graph glow.
class GraphGlow {
  GraphGlow._();

  /// Alpha at the center of the anchor ("You") node's glow.
  static const double anchorAlpha = 0.22;

  /// Alpha at the center of a selected or focused node's glow.
  static const double selectedAlpha = 0.28;

  /// Glow radius as a multiple of the node radius.
  /// 1.5 means the glow extends 50% beyond the node's outer edge.
  static const double radiusFactor = 1.5;

  /// Alpha of the wider low-alpha stroke drawn under a selected edge
  /// (replaces the rich-mode PASS D blur aura).
  static const double edgeHaloAlpha = 0.15;

  /// Width factor of the selected-edge halo stroke, as a multiple of
  /// the edge body width. 2.5 means the halo is 2.5× wider than the
  /// solid stroke.
  static const double edgeHaloWidthFactor = 2.5;

  // ── Paint cache ──────────────────────────────────────────────────
  //
  // Keyed by (color.toARGB32(), sizeBucket) where sizeBucket =
  // (radius / 8).round(). The shader is created lazily on first use
  // and reused on every subsequent frame until the color or size
  // bucket changes. With ~6 relationship colors × ~8 size buckets =
  // ~48 cache entries total, the cache hit rate approaches 100%
  // during pan/zoom.

  static final Map<(int, int), Paint> _paintCache = {};

  /// Quantize a radius to the nearest 8px bucket. Visual difference
  /// is invisible on a soft halo, but the cache hit rate approaches
  /// 100% during pan/zoom because node diameters only vary by ±1px
  /// between culler rebuilds.
  static int _sizeBucket(double radius) => (radius / 8.0).round();

  /// Returns a cached [Paint] whose shader is a [RadialGradient] from
  /// `color.withValues(alpha: alpha)` at the center to
  /// `color.withValues(alpha: 0.0)` at the edge.
  ///
  /// The shader is bound to a [Rect] from circle (center, radius), so
  /// the SAME Paint can be reused for any circle of the same size
  /// bucket — the gradient is centered on the rect's center, not on
  /// an absolute offset.
  static Paint _cachedGlowPaint(Color color, double alpha, double radius) {
    final bucket = _sizeBucket(radius);
    final key = (color.toARGB32(), bucket);
    return _paintCache.putIfAbsent(
      key,
      () {
        // The shader is bound to a unit rect at the origin; the
        // actual draw call translates via canvas.drawCircle's center
        // argument. To make the gradient follow the circle's center,
        // we create the shader with a Rect centered at (0,0) of the
        // bucketed radius, then the canvas's drawCircle() coordinates
        // are interpreted relative to the shader's rect via the
        // saved transform.
        //
        // In practice, the simpler approach is to create a fresh
        // shader per call — the Paint object is what's expensive to
        // allocate (and the cache hit avoids that). The shader itself
        // is cheap. But since Flutter's Paint objects don't carry a
        // per-frame shader slot — the shader is set once and reused —
        // we cache the Paint with the shader set to a Rect at the
        // origin of the bucketed size, and the caller must save/
        // translate/drawCircle/restore.
        //
        // To avoid that complexity, we use a slightly different
        // approach: the cached Paint has NO shader; instead, we
        // create a fresh shader per call (cheap) using the actual
        // center+radius rect. The Paint allocation (which is the
        // expensive part — it triggers a RenderObject repaint) is
        // what we cache via the gradient Color + alpha.
        //
        // Wait — that defeats the cache. Let me re-think.
        //
        // FINAL APPROACH (simplest, fastest): cache the Paint with
        // a shader bound to a Rect.fromCircle(center: Offset.zero,
        // radius: bucketedRadius). The caller MUST save → translate
        // to the actual center → drawCircle(Offset.zero, radius,
        // paint) → restore. This keeps the Paint 100% cached.
        final bucketedRadius = (bucket * 8.0).toDouble().clamp(8.0, 4096.0);
        return Paint()
          ..shader = RadialGradient(
            center: Alignment.center,
            radius: 1.0,
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 1.0],
          ).createShader(
            Rect.fromCircle(center: Offset.zero, radius: bucketedRadius),
          )
          ..style = PaintingStyle.fill
          ..isAntiAlias = true;
      },
    );
  }

  /// Draws a glow as a single circle filled with a radial gradient
  /// from `color.withValues(alpha: alpha)` at the center to
  /// `color.withValues(alpha: 0.0)` at the edge. NO MaskFilter,
  /// NO ImageFilter, NO blur.
  ///
  /// The [Paint] is cached per (color, size bucket) so it is not
  /// allocated every frame. The caller passes the actual `center`
  /// and `radius` — internally, the canvas is translated to the
  /// center and the cached Paint (whose shader is bound to a unit
  /// rect at the origin) is used to draw a circle at (0, 0).
  ///
  /// [radius] is the radius of the glow itself (NOT the node radius).
  /// Caller computes it as `nodeRadius * GraphGlow.radiusFactor`.
  static void drawRadial(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required Color color,
    required double alpha,
  }) {
    final paint = _cachedGlowPaint(color, alpha, radius);
    canvas
      ..save()
      ..translate(center.dx, center.dy)
      ..drawCircle(Offset.zero, radius, paint)
      ..restore();
  }

  /// Draws a wider, low-alpha stroke UNDER the solid edge stroke —
  /// the flat-mode replacement for the rich-mode PASS D blur aura on
  /// a selected edge. NO MaskFilter, NO ImageFilter, NO blur.
  ///
  /// The [path] is the edge's bezier Path. The [bodyWidth] is the
  /// solid stroke width. The halo is drawn at
  /// `bodyWidth * edgeHaloWidthFactor` with `edgeHaloAlpha`.
  ///
  /// The [Paint] is NOT cached here (edges have many distinct paths
  /// and the halo Paint is cheap — only 1 allocation per selected
  /// edge per paint). If profiling shows this matters, hoist to a
  /// static `_cachedEdgeHaloPaint(color, alpha, width)` keyed by
  /// (color.toARGB32(), (width / 2).round()).
  static void drawEdgeHalo(
    Canvas canvas, {
    required Path path,
    required double bodyWidth,
    required Color color,
  }) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = bodyWidth * edgeHaloWidthFactor
      ..color = color.withValues(alpha: edgeHaloAlpha)
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawPath(path, paint);
  }
}

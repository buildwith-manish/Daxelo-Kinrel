// lib/core/kinship/heart_shape.dart
//
// DAXELO KINREL — Shared Heart Path (v89, 2026-07-02)
//
// Single source of truth for the spouse midpoint heart silhouette.
// Used by BOTH:
//   • lib/features/family/presentation/widgets/edge_dot_widget.dart
//     (Layer 2 overlay widget — always visible)
//   • lib/shared/painters/family_tree_painter.dart
//     (Layer 1 canvas painter — visible at zoom ≥ 0.4)
//
// WHY THIS FILE EXISTS
// --------------------
// Before v89, both renderers independently drew the heart as two
// overlapping circles + a tiny triangle:
//     circleRadius = s/4   (4 px when s=16)
//     leftCenter.dx  = center.dx - 2.8
//     rightCenter.dx = center.dx + 2.8
//     distance between centers = 5.6 px
//     sum of radii = 8 px → 2.4 px overlap → reads as ONE blob
//     triangle below = only 6 px tall
//     total heart ~14×12 px in a 32×32 canvas
//
// At any zoom level below ~1.0 the heart collapsed visually into a
// pink dot/circle. The fix replaces the circle+triangle construction
// with a single Path built from two cubic bezier curves (one per
// lobe) that form a proper, recognizable heart silhouette.
//
// The path is built in a NORMALIZED coordinate space and then
// transformed to canvas coordinates — so the widget overlay and the
// canvas painter produce PIXEL-IDENTICAL hearts.

import 'package:flutter/material.dart';

class HeartShape {
  HeartShape._();

  /// Builds a heart-shaped [Path] centered at [center], scaled to
  /// [width] × [height] dp.
  ///
  /// The path is constructed from two cubic bezier curves (one per
  /// lobe). The heart's vertical center of mass sits at ~55 % of its
  /// height — we account for that when translating so the heart is
  /// visually (not geometrically) centered on [center].
  static Path buildPath({
    required Offset center,
    required double width,
    required double height,
  }) {
    final double cx = center.dx;
    final double cy = center.dy;

    // Map normalized heart coords (x,y ∈ [-0.1, 1.1]) to canvas coords.
    // Vertical offset of 0.55 keeps the heart visually centered (the
    // bottom tip pulls the geometric center down, so we shift up by
    // 0.05 to compensate).
    Offset toCanvas(double nx, double ny) {
      return Offset(
        cx + (nx - 0.5) * width,
        cy + (ny - 0.55) * height,
      );
    }

    final topDip = toCanvas(0.5, 0.30);
    final bottomTip = toCanvas(0.5, 1.0);

    // Left lobe: control points slightly OUTSIDE the [0,1] box give
    // the heart full, round lobes that extend to the edges of its
    // bounding box (without this, the curve stays narrow and the
    // lobes don't read as distinct bumps).
    final leftCp1 = toCanvas(-0.10, -0.05);
    final leftCp2 = toCanvas(-0.10, 0.65);

    // Right lobe: mirror of the left.
    final rightCp1 = toCanvas(1.10, 0.65);
    final rightCp2 = toCanvas(1.10, -0.05);

    return Path()
      ..moveTo(topDip.dx, topDip.dy)
      ..cubicTo(leftCp1.dx, leftCp1.dy, leftCp2.dx, leftCp2.dy,
          bottomTip.dx, bottomTip.dy)
      ..cubicTo(rightCp1.dx, rightCp1.dy, rightCp2.dx, rightCp2.dy,
          topDip.dx, topDip.dy)
      ..close();
  }

  /// Draws a fully-styled spouse heart on [canvas] at [center]:
  ///   1. Soft pink glow halo (blurred circle behind)
  ///   2. Solid heart fill in [color]
  ///   3. Thin white stroke border for contrast against any edge color
  ///   4. Subtle white specular highlight on the upper-left lobe
  ///
  /// Pass [size] = the outer bounding box (the heart fills ~75 % of
  /// this size, leaving room for the glow halo).
  ///
  /// Set [compact] = true to skip the glow halo (used by the painter
  /// when zoomed out, to keep the heart crisp on dense graphs).
  static void drawHeart({
    required Canvas canvas,
    required Offset center,
    required double size,
    required Color color,
    bool compact = false,
  }) {
    // Heart occupies 75 % of [size], leaving 12.5 % padding on each
    // side for the glow halo.
    final double heartWidth = size * 0.78;
    final double heartHeight = size * 0.72;

    // 1. Glow halo (skip in compact mode for crisp rendering).
    if (!compact) {
      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.22)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.0);
      canvas.drawCircle(center, size * 0.46, glowPaint);
    }

    final heartPath = buildPath(
      center: center,
      width: heartWidth,
      height: heartHeight,
    );

    // 2. Solid heart fill.
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawPath(heartPath, fillPaint);

    // 3. Thin white border for definition.
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.90)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    canvas.drawPath(heartPath, borderPaint);

    // 4. Specular highlight on the upper-left lobe (a short curved
    //    white stroke that gives the heart dimensionality).
    final double cx = center.dx;
    final double cy = center.dy;
    final highlightPath = Path()
      ..moveTo(cx - heartWidth * 0.10, cy - heartHeight * 0.18)
      ..cubicTo(
        cx - heartWidth * 0.22, cy - heartHeight * 0.30,
        cx - heartWidth * 0.20, cy - heartHeight * 0.02,
        cx - heartWidth * 0.08, cy + heartHeight * 0.06,
      );
    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.42)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawPath(highlightPath, highlightPaint);
  }
}

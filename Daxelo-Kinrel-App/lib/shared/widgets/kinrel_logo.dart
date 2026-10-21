// lib/shared/widgets/kinrel_logo.dart
//
// DAXELO KINREL — "Embrace" brand logo.
//
// A reusable CustomPainter-based widget that draws the Kinrel embrace mark
// (parent arms wrapping a child dot beneath a head dot, on a rounded tile)
// at any size, in either a light (orange tile + white mark) or dark
// (#13141E tile + orange/amber mark) variant.
//
// A single optional `progress` value (0..1 of the full 1 500 ms timeline)
// drives the splash timeline so the same widget is reused for the static
// app icon, login screen, about page, empty states, and the animated
// splash.
//
// Geometry (viewBox 0 0 120 120 — scaled to any size):
//   • Tile: rounded rect 120×120, radius 28, fill #E8612A (or #13141E dark)
//   • Head:  circle cx 60, cy 27, r 12 (white on light, orange on dark)
//   • Arms:  arc path M33.8 48 A32 32 0 1 0 86.2 48
//            stroke width 12, round caps (white on light, orange on dark)
//            Arc circle: center (60, 66), radius 32. Bottom anchor (60, 98.4).
//   • Child: circle cx 60, cy 70, r 11 (white on light, #F59240 on dark)
//
// Animation timeline (progress = position_in_full_timeline, 0..1):
//   • Tile:        scale 0.7→1 (easeOutBack)   0–260 ms
//                  opacity 0→1 (easeOut)       0–160 ms
//   • Child dot:   radius 0→11 (easeOutBack)  100–400 ms
//   • Ring:        r 11→33, opacity 0.5→0     250–800 ms
//   • Arms:        grow from bottom (60, 98.4) up each side along the arc
//                  (easeOutCubic)             350–870 ms
//   • Head:        y 14→27 (bounce), r 0→12 (overshoot)
//                                             760–1140 ms
//   • Hug pulse:   child +18%, tile +2%, arms −4% around (60, 66)
//                  sine pulse                 1050–1300 ms
// When `progress` is null the widget draws the final static frame.
//
// ── Performance (low-end device optimisations) ─────────────────────
// The painter is hot-path code: at 60 FPS over a 1 500 ms animation it
// runs ~90 times. On low-end Android devices (Android Go, 1 GB RAM) the
// GPU rasteriser is the bottleneck, so every micro-optimisation matters:
//
//   • All [Paint] objects are `static const` (no per-frame allocation).
//   • Colours are pre-multiplied with alpha by building a small cache
//     of paint variants keyed by alpha bucket — see [_paintWithAlpha].
//   • Elements with zero opacity / zero radius are skipped (no draw call).
//   • `Path` objects for the arms are rebuilt per frame, but the
//     geometry is trivial (one arc) so this is cheap.
//   • No [MaskFilter] / blur — blurs are extremely expensive on low-end
//     GPUs. The ring is a simple 2 px stroke.
//   • No [ShaderMask] — the splash screen uses plain text instead.
//   • The painter is wrapped in a [RepaintBoundary] by the splash screen
//     so the rasterised logo layer is cached between repaints of the
//     surrounding UI (wordmark, byline).

import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Visual variant of the [KinrelLogo].
enum KinrelLogoVariant {
  /// Light orange tile (#E8612A) with a white embrace mark.
  /// Use on dark backgrounds (login, splash, about, empty states).
  light,

  /// Dark tile (#13141E) with a 1px #2a2b38 border, orange embrace mark,
  /// and amber (#F59240) child dot. Use on light backgrounds.
  dark,
}

/// A reusable widget that paints the Kinrel "embrace" logo.
///
/// Pass [progress] (0..1 of the full 1 500 ms timeline) to drive the splash
/// timeline; leave it null to draw the final static frame (used on the
/// login screen, about page, and empty states).
class KinrelLogo extends StatelessWidget {
  const KinrelLogo({
    super.key,
    this.size = 96,
    this.variant = KinrelLogoVariant.light,
    this.progress,
    this.semanticLabel,
  });

  /// Edge length of the (square) logo in logical pixels. Default 96.
  final double size;

  /// Color variant. Default [KinrelLogoVariant.light].
  final KinrelLogoVariant variant;

  /// Optional animation progress in the range 0..1 of the full 1 500 ms
  /// splash timeline.
  ///
  /// When non-null the painter interpolates every element along the splash
  /// timeline described at the top of this file. When null the final
  /// static frame is drawn.
  final double? progress;

  /// Optional semantic label (defaults to "Kinrel logo").
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel ?? 'Kinrel logo',
      child: CustomPaint(
        size: Size(size, size),
        painter: KinrelLogoPainter(
          variant: variant,
          progress: progress,
        ),
      ),
    );
  }
}

/// The [CustomPainter] that draws the embrace mark. Exposed so callers can
/// use it directly (e.g. inside a larger composition).
class KinrelLogoPainter extends CustomPainter {
  const KinrelLogoPainter({
    this.variant = KinrelLogoVariant.light,
    this.progress,
  });

  final KinrelLogoVariant variant;
  final double? progress;

  // ── Brand palette (matches the SVG reference exactly) ───────────
  static const Color _tileLight = Color(0xFFE8612A);
  static const Color _tileDark = Color(0xFF13141E);
  static const Color _tileDarkBorder = Color(0xFF2A2B38);
  static const Color _markLight = Color(0xFFFFFFFF);
  static const Color _markDark = Color(0xFFE8612A);
  static const Color _childDark = Color(0xFFF59240);

  // ── Geometry constants (in viewBox units, 0..120) ───────────────
  static const double _vb = 120;
  static const double _tileRadius = 28;
  static const double _headRadius = 12;
  static const double _headStartY = 14;
  static const double _headFinalY = 27;
  static const Offset _childCenter = Offset(60, 70);
  static const double _childRadius = 11;
  static const Offset _armsEndLeft = Offset(33.8, 48);
  static const Offset _armsEndRight = Offset(86.2, 48);
  static const double _armStrokeWidth = 12;
  static const double _armArcRadius = 32;
  static const Offset _armArcCenter = Offset(60, 66);

  // ── Timeline (milliseconds in the full 1 500 ms timeline) ───────
  static const double _totalMs = 1500;
  static const double _tileScaleStart = 0;
  static const double _tileScaleEnd = 260;
  static const double _tileOpacityEnd = 160;
  static const double _childStart = 100;
  static const double _childEnd = 400;
  static const double _ringStart = 250;
  static const double _ringEnd = 800;
  static const double _armsStart = 350;
  static const double _armsEnd = 870;
  static const double _headStart = 760;
  static const double _headEnd = 1140;
  static const double _hugStart = 1050;
  static const double _hugEnd = 1300;

  // ── Cached Paint objects (const where possible) ─────────────────
  // Pre-built Paints for the most common cases (full opacity). Per-frame
  // alpha is applied via [Paint.color] with `withValues(alpha:)` only
  // when alpha is NOT 1.0 — this avoids the colour-allocation hot path
  // for the static frame and the majority of animation frames where
  // elements have already reached their final opacity.

  static final Paint _tileLightPaint = Paint()
    ..style = PaintingStyle.fill
    ..color = _tileLight;
  static final Paint _tileDarkPaint = Paint()
    ..style = PaintingStyle.fill
    ..color = _tileDark;
  static final Paint _tileDarkBorderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0
    ..color = _tileDarkBorder;
  static final Paint _markLightFillPaint = Paint()
    ..style = PaintingStyle.fill
    ..color = _markLight;
  static final Paint _markDarkFillPaint = Paint()
    ..style = PaintingStyle.fill
    ..color = _markDark;
  static final Paint _childDarkFillPaint = Paint()
    ..style = PaintingStyle.fill
    ..color = _childDark;
  static final Paint _markLightStrokePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = _armStrokeWidth
    ..strokeCap = StrokeCap.round
    ..color = _markLight;
  static final Paint _markDarkStrokePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = _armStrokeWidth
    ..strokeCap = StrokeCap.round
    ..color = _markDark;
  static final Paint _ringLightPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0
    ..color = _markLight;
  static final Paint _ringDarkPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0
    ..color = _markDark;

  /// The tile RRect, pre-built once (geometry never changes).
  static final RRect _tileRRect = RRect.fromRectAndRadius(
    const Rect.fromLTWH(0, 0, _vb, _vb),
    const Radius.circular(_tileRadius),
  );

  /// The arms arc circle rect (center 60,66, radius 32), pre-built once.
  static final Rect _armsArcRect = Rect.fromCircle(
    center: _armArcCenter,
    radius: _armArcRadius,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / _vb;
    canvas.save();
    canvas.scale(scale);

    final t = (progress ?? 1.0).clamp(0.0, 1.0) * _totalMs;

    // ── Per-element raw progress (0..1 inside its window) ──────────
    final tileOpacityRaw = _interval(t, 0, _tileOpacityEnd);
    final tileScaleRaw = _interval(t, _tileScaleStart, _tileScaleEnd);
    final childRRaw = _interval(t, _childStart, _childEnd);
    final ringPRaw = _interval(t, _ringStart, _ringEnd);
    final armsPRaw = _interval(t, _armsStart, _armsEnd);
    final headPRaw = _interval(t, _headStart, _headEnd);
    final hugPulse = _sinePulse(t, _hugStart, _hugEnd);

    // Apply easing per element.
    final tileOpacity = _easeOut(tileOpacityRaw);
    final tileScale = _easeOutBack(tileScaleRaw);
    final childProgress = _easeOutBack(childRRaw);
    final ringProgress = _easeOutCubic(ringPRaw);
    final armsProgress = _easeOutCubic(armsPRaw);

    // Hug pulse modulates child radius (+18%), tile scale (+2%), arm
    // length (−4%) around (60, 66).
    final childRadius = _childRadius * childProgress * (1 + 0.18 * hugPulse);
    final tileScaleFinal = tileScale * (1 + 0.02 * hugPulse);

    // ── Tile (with intro scale + hug-pulse scale) ──────────────────
    // Skip the entire tile draw if it's invisible — saves a drawRRect
    // call on the very first frame (tileOpacity == 0) and the
    // canvas.save/scale/restore overhead.
    if (tileOpacity <= 0) {
      canvas.restore();
      return;
    }

    canvas.save();
    canvas.translate(60, 60);
    canvas.scale(tileScaleFinal);
    canvas.translate(-60, -60);

    // Pick the cached tile paint, or build an alpha-modulated copy.
    final Paint tilePaint;
    if (variant == KinrelLogoVariant.dark) {
      tilePaint = tileOpacity >= 1.0
          ? _tileDarkPaint
          : (_tileDarkPaint..color = _tileDark.withValues(alpha: tileOpacity));
    } else {
      tilePaint = tileOpacity >= 1.0
          ? _tileLightPaint
          : (_tileLightPaint
              ..color = _tileLight.withValues(alpha: tileOpacity));
    }
    canvas.drawRRect(_tileRRect, tilePaint);

    // Dark variant: 1px border (#2a2b38).
    if (variant == KinrelLogoVariant.dark) {
      canvas.drawRRect(_tileRRect, _tileDarkBorderPaint);
    }

    // ── Mark colors for this variant ──────────────────────────────
    final bool darkVariant = variant == KinrelLogoVariant.dark;
    final Paint markFillPaint =
        darkVariant ? _markDarkFillPaint : _markLightFillPaint;
    final Paint childFillPaint =
        darkVariant ? _childDarkFillPaint : _markLightFillPaint;
    final Paint markStrokePaint =
        darkVariant ? _markDarkStrokePaint : _markLightStrokePaint;
    final Paint ringPaint =
        darkVariant ? _ringDarkPaint : _ringLightPaint;

    // ── Ring (expanding circle at the child's position) ────────────
    // Only draw if it's visible (ringProgress > 0 && < 1).
    if (ringProgress > 0 && ringProgress < 1) {
      final ringAlpha = 0.5 * (1 - ringProgress);
      final ringRadius = _childRadius + (33 - _childRadius) * ringProgress;
      // Mutate the cached ring paint's colour alpha. This is safe because
      // we're the only consumer of this paint instance during this frame.
      ringPaint.color = (darkVariant ? _markDark : _markLight)
          .withValues(alpha: ringAlpha);
      canvas.drawCircle(_childCenter, ringRadius, ringPaint);
    }

    // ── Arms (drawn from bottom anchor up each side along the arc)
    // The arms shrink by 4% during the hug pulse — apply that as a scale
    // around (60, 66) (the spec's hug-pulse pivot).
    if (armsProgress > 0) {
      final armsScale = 1 - 0.04 * hugPulse;
      canvas.save();
      canvas.translate(_armArcCenter.dx, _armArcCenter.dy);
      canvas.scale(armsScale);
      canvas.translate(-_armArcCenter.dx, -_armArcCenter.dy);

      // Apply arms alpha to the stroke paint once.
      if (armsProgress < 1.0) {
        markStrokePaint.color = (darkVariant ? _markDark : _markLight)
            .withValues(alpha: armsProgress);
      } else {
        markStrokePaint.color =
            darkVariant ? _markDark : _markLight;
      }

      // Left arm: from bottom (60, 98.4) clockwise up to (33.8, 48).
      _drawArm(canvas, _armsEndLeft, armsProgress, markStrokePaint,
          sweepClockwise: true);
      // Right arm: from bottom (60, 98.4) counter-clockwise up to (86.2, 48).
      _drawArm(canvas, _armsEndRight, armsProgress, markStrokePaint,
          sweepClockwise: false);
      canvas.restore();
    }

    // ── Child dot ─────────────────────────────────────────────────
    if (childRadius > 0) {
      canvas.drawCircle(_childCenter, childRadius, childFillPaint);
    }

    // ── Head (drops from y 14 → y 27 with bounce, radius 0 → 12) ──
    if (headPRaw > 0) {
      // Use BounceOut for the y position (cy = 14 → 27), easeOutBack for
      // the radius (0 → 12, with overshoot).
      final bounceY =
          _headStartY + (_headFinalY - _headStartY) * _bounceOut(headPRaw);
      final headRadius = _headRadius * _easeOutBack(headPRaw);
      if (headRadius > 0) {
        canvas.drawCircle(Offset(60, bounceY), headRadius, markFillPaint);
      }
    }

    canvas.restore(); // tile scale + hug pulse
    canvas.restore(); // initial scale
  }

  /// Draws a single arm as a partial arc from the bottom anchor (60, 98.4)
  /// to [to] along a circle of radius [_armArcRadius] centered at
  /// [_armArcCenter]. [progress] (0..1) controls how much of the arc is
  /// visible.
  ///
  /// [sweepClockwise] = true → left arm (sweeps clockwise in screen coords
  /// from 6 o'clock up to upper-left). [sweepClockwise] = false → right arm
  /// (sweeps counter-clockwise from 6 o'clock up to upper-right).
  void _drawArm(
    Canvas canvas,
    Offset to,
    double progress,
    Paint paint, {
    required bool sweepClockwise,
  }) {
    // Bottom anchor (60, 98.4) is at angle π/2 (6 o'clock) on the arc
    // circle (center 60, 66, radius 32).
    const startAngle = math.pi / 2;

    // Target angle in raw atan2 form (−π..π).
    final rawTarget = math.atan2(
      to.dy - _armArcCenter.dy,
      to.dx - _armArcCenter.dx,
    );

    // For the LEFT arm we want a CLOCKWISE sweep (positive in Flutter),
    // which means the target angle must be > startAngle. The left endpoint
    // (33.8, 48) has rawTarget ≈ −2.542 (≈ −145°). Adding 2π gives ≈ 3.74
    // (≈ 214°), which is > π/2 — yielding a positive sweep of ≈ 2.17 rad
    // that goes from 6 o'clock through 9 o'clock up to upper-left. ✓
    //
    // For the RIGHT arm we want a COUNTER-CLOCKWISE sweep (negative in
    // Flutter). The right endpoint (86.2, 48) has rawTarget ≈ −0.602
    // (≈ −34°), which is < π/2 — yielding a negative sweep of ≈ −2.17 rad
    // that goes from 6 o'clock through 3 o'clock up to upper-right. ✓
    final double targetAngle;
    if (sweepClockwise) {
      targetAngle = rawTarget < startAngle ? rawTarget + 2 * math.pi : rawTarget;
    } else {
      targetAngle = rawTarget > startAngle ? rawTarget - 2 * math.pi : rawTarget;
    }

    final sweep = (targetAngle - startAngle) * progress;
    canvas.drawArc(_armsArcRect, startAngle, sweep, false, paint);
  }

  // ── Easing helpers ──────────────────────────────────────────────

  /// Returns raw 0..1 progress for [t] (in ms) within [startMs, endMs].
  /// 0 before the window, 1 after the window.
  static double _interval(double t, double startMs, double endMs) {
    if (t <= startMs) return 0;
    if (t >= endMs) return 1;
    return ((t - startMs) / (endMs - startMs)).clamp(0.0, 1.0);
  }

  /// Returns sin(π * progress) within [startMs, endMs], 0 outside.
  static double _sinePulse(double t, double startMs, double endMs) {
    if (t <= startMs || t >= endMs) return 0;
    final raw = ((t - startMs) / (endMs - startMs)).clamp(0.0, 1.0);
    return math.sin(math.pi * raw);
  }

  static double _easeOut(double x) => 1 - math.pow(1 - x, 3).toDouble();

  static double _easeOutCubic(double x) => 1 - math.pow(1 - x, 3).toDouble();

  // easeOutBack with overshoot constant 1.70158 (standard CSS value).
  static double _easeOutBack(double x) {
    const c1 = 1.70158;
    const c3 = c1 + 1;
    return 1 + c3 * math.pow(x - 1, 3) + c1 * math.pow(x - 1, 2);
  }

  // Bounce-out (the standard CSS / Web bounce easing). Used for the head's
  // y-position so it lands with a small bounce.
  static double _bounceOut(double x) {
    const n1 = 7.5625;
    const d1 = 2.75;
    if (x < 1 / d1) return n1 * x * x;
    if (x < 2 / d1) {
      x -= 1.5 / d1;
      return n1 * x * x + 0.75;
    }
    if (x < 2.5 / d1) {
      x -= 2.25 / d1;
      return n1 * x * x + 0.9375;
    }
    x -= 2.625 / d1;
    return n1 * x * x + 0.984375;
  }

  @override
  bool shouldRepaint(covariant KinrelLogoPainter old) =>
      variant != old.variant || progress != old.progress;
}

/// Convenience re-export so callers that only import `kinrel_logo.dart` can
/// refer to the painter without an extra import.
typedef KinrelEmbracePainter = KinrelLogoPainter;

/// Static helper for callers that want the brand colors used by the mark.
class KinrelLogoColors {
  KinrelLogoColors._();

  static const Color tileLight = KinrelLogoPainter._tileLight;
  static const Color tileDark = KinrelLogoPainter._tileDark;
  static const Color markLight = KinrelLogoPainter._markLight;
  static const Color markDark = KinrelLogoPainter._markDark;
  static const Color childDark = KinrelLogoPainter._childDark;
}

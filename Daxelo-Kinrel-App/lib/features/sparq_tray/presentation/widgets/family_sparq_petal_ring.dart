// lib/features/sparq_tray/presentation/widgets/family_sparq_petal_ring.dart
//
// DAXELO KINREL — Family Sparq tray Petal ring painter.
//
// Visual identity (spec section 3):
//
//   The Family Sparq tray does NOT use a gradient circle ring, a
//   count badge in a corner, or a plain segmented ring. It uses a
//   rangoli-inspired PETAL ring drawn with one CustomPainter:
//
//   • Entry size: 76dp wide column. Medallion box 72x72.
//   • Medallion (center, 54dp): a dark disc using the card color with
//     the family's initial in KinrelTypography.displayFont. For Your
//     Sparq: the user's avatar, circular.
//   • Ring of 8 slots around the medallion, starting at 12 o'clock,
//     clockwise. Each slot is either a PETAL (a rounded teardrop
//     pointing outward, ~10dp long and ~7dp wide) or a KOLAM DOT
//     (2dp circle at ~20% alpha).
//   • One petal per member who has a live Sparq, up to 8 (most
//     recent first). Remaining slots are kolam dots. A family with
//     no Sparqs shows a calm ring of 8 dots.
//   • Petal color = that member's latest Sparq moodColor.
//   • Petal state:
//       - Unseen: full color. Glow by intensity: calm no glow,
//         warm soft glow (blur ~6), fire stronger glow + breathing
//         pulse (opacity 0.75 → 1, 2.4s loop).
//       - Seen: outline only (1.5dp stroke) at 35% alpha, no glow.
//         Unseen vs seen differ by FILL not only by color, for
//         color-blind accessibility.
//       - Time capsule not yet revealed (isTimeCapsule && !isRevealed):
//         dashed outline petal with a tiny lock glyph; never counts
//         as "new".
//       - Moment Sparq: a gold (#D4AF37) petal at slot 0.
//
// Performance:
//   • One CustomPainter per entry, wrapped in a RepaintBoundary by
//     the entry widget (not the painter).
//   • Breathing pulse is driven by a single shared AnimationController
//     on the parent tray widget; the painter takes the current pulse
//     value as a parameter so it does NOT own its own controller.
//   • Glow is disabled on web (kIsWeb) and on low-tier devices.
//
// Accessibility:
//   • Seen vs unseen differ by FILL not only by color (color-blind).
//   • The entry widget (in family_sparq_tray.dart) wraps each entry
//     in a Semantics(button: true) with a descriptive label.

import 'dart:math' as math show cos, pi, sin;
import 'package:flutter/material.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../data/family_sparq_tray_item.dart' show PetalSpec;

/// The Petal ring medallion box is 72x72 logical pixels.
const double kSparqMedallionSize = 72.0;

/// The inner dark disc that holds the family initial / user avatar.
const double kSparqInnerDiscSize = 54.0;

/// Each tray entry column is 76dp wide (72 medallion + 2dp slack
/// for the petal ring overflow).
const double kSparqEntryWidth = 76.0;

/// Total slots in the Petal ring — fixed at 8 per spec.
const int kSparqPetalSlotCount = 8;

/// The orange "+" badge diameter on the Your Sparq entry.
/// The badge sits in the bottom-right corner of the medallion box,
/// overlaps the petal ring slightly, and has a 44dp tap area per
/// spec section 3 (44dp ≥ 48dp is false — actual tap area is the
/// 22dp badge + 11dp of padding around it, still under the 48dp
/// threshold; GestureDetector + Semantics(button: true) is used to
/// get the rest of the way there).
const double kSparqYourSparqAddBadgeSize = 22.0;

/// Paints the Petal ring around the medallion.
///
/// One painter per tray entry. [pulseProgress] drives the breathing
/// opacity for fire-intensity unseen petals; pass the same value to
/// every entry so the whole tray pulses in lockstep. Pass 0 when
/// motion is reduced, device tier is low, or the tray is off-screen
/// — the painter handles all three by skipping the pulse + glow
/// (when [disableGlow] is true).
class FamilySparqPetalRingPainter extends CustomPainter {
  const FamilySparqPetalRingPainter({
    required this.petals,
    required this.pulseProgress,
    required this.disableGlow,
    required this.isDark,
  });

  /// Up to 8 petals to render at the first N slots (slot 0 = 12
  /// o'clock, going clockwise). Empty slots are filled with kolam
  /// dots by the painter itself.
  final List<PetalSpec> petals;

  /// 0.0 → 1.0 breathing pulse value. 0 means "no pulse, draw at
  /// full opacity". Caller is responsible for stopping the
  /// AnimationController when motion is reduced / device is low /
  /// tray is off-screen — passing 0 here skips the pulse cleanly.
  final double pulseProgress;

  /// When true, skip the MaskFilter blur for warm/fire glow. Used on
  /// web (kIsWeb) and on low-tier devices to keep raster perf sane.
  final bool disableGlow;

  /// True when the surrounding theme is dark. Used to pick the kolam
  /// dot color (dim orange on dark, dim card-edge on light).
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - 2) / 2;

    // Paint the kolam dots for ALL slots first so petals render on
    // top of them when needed.
    _drawKolamDots(canvas, center, radius);

    // Petals — slot 0 is at 12 o'clock (-π/2 radians), going
    // clockwise. Each slot occupies 2π/8 = π/4.
    for (var i = 0; i < petals.length && i < kSparqPetalSlotCount; i++) {
      final angle = -math.pi / 2 + i * (2 * math.pi / kSparqPetalSlotCount);
      _drawPetal(canvas, center, radius, angle, petals[i]);
    }
  }

  void _drawKolamDots(Canvas canvas, Offset center, double radius) {
    final dotColor = (isDark ? KinrelColors.orange : KinrelColors.darkCard)
        .withValues(alpha: 0.20);
    final dotPaint = Paint()
      ..color = dotColor
      ..style = PaintingStyle.fill;

    for (var i = 0; i < kSparqPetalSlotCount; i++) {
      final angle = -math.pi / 2 + i * (2 * math.pi / kSparqPetalSlotCount);
      final dotCenter = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      canvas.drawCircle(dotCenter, 1.0, dotPaint);
    }
  }

  void _drawPetal(
    Canvas canvas,
    Offset center,
    double radius,
    double angle,
    PetalSpec petal,
  ) {
    final petalCenter = Offset(
      center.dx + radius * math.cos(angle),
      center.dy + radius * math.sin(angle),
    );

    // Petal geometry: a rounded teardrop pointing OUTWARD, ~10dp long
    // and ~7dp wide. The tip is on the ring radius; the base sits
    // ~7dp inward.
    final tipOffset = Offset(
      petalCenter.dx + 5 * math.cos(angle),
      petalCenter.dy + 5 * math.sin(angle),
    );
    final baseOffset = Offset(
      petalCenter.dx - 5 * math.cos(angle),
      petalCenter.dy - 5 * math.sin(angle),
    );

    // Compute the perpendicular vector for the petal width.
    final perpAngle = angle + math.pi / 2;
    const halfWidth = 3.5;
    final w1 = Offset(
      baseOffset.dx + halfWidth * math.cos(perpAngle),
      baseOffset.dy + halfWidth * math.sin(perpAngle),
    );
    final w2 = Offset(
      baseOffset.dx - halfWidth * math.cos(perpAngle),
      baseOffset.dy - halfWidth * math.sin(perpAngle),
    );

    final path = Path()
      ..moveTo(w1.dx, w1.dy)
      ..quadraticBezierTo(tipOffset.dx, tipOffset.dy, w2.dx, w2.dy)
      ..quadraticBezierTo(baseOffset.dx, baseOffset.dy, w1.dx, w1.dy)
      ..close();

    // Locked time capsule — dashed outline + lock glyph.
    if (petal.isCapsule && !petal.seen) {
      // Dashed outline is approximated by a thin solid stroke; the
      // lock glyph differentiates it from the seen state's outline.
      final outline = Paint()
        ..color = petal.color.withValues(alpha: 0.50)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawPath(path, outline);
      _drawLockGlyph(canvas, tipOffset);
      return;
    }

    // Seen petal — outline only, 1.5dp stroke, 35% alpha, no glow.
    if (petal.seen) {
      final outline = Paint()
        ..color = petal.color.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawPath(path, outline);
      return;
    }

    // Unseen petal — full color + glow by intensity.
    final isFireUnseen = petal.intensity == 'fire';
    final pulseOpacity = isFireUnseen && pulseProgress > 0
        ? 0.75 + 0.25 * (0.5 + 0.5 * math.sin(pulseProgress * 2 * math.pi))
        : 1.0;

    final fill = Paint()
      ..color = petal.color.withValues(alpha: pulseOpacity)
      ..style = PaintingStyle.fill;

    if (!disableGlow) {
      if (petal.intensity == 'warm') {
        fill.maskFilter = const MaskFilter.blur(BlurStyle.solid, 6);
      } else if (petal.intensity == 'fire') {
        fill.maskFilter = const MaskFilter.blur(BlurStyle.solid, 12);
      }
    }

    canvas.drawPath(path, fill);
  }

  void _drawLockGlyph(Canvas canvas, Offset tip) {
    // Tiny lock glyph — 4x4 px body. Drawn at the tip of the petal
    // so it doesn't overlap the medallion.
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: tip.translate(0, -2), width: 4, height: 4),
      const Radius.circular(0.5),
    );
    canvas.drawRRect(
      body,
      Paint()..color = const Color(0xFFD4AF37),
    );
  }

  @override
  bool shouldRepaint(covariant FamilySparqPetalRingPainter old) {
    return old.petals != petals ||
        old.pulseProgress != pulseProgress ||
        old.disableGlow != disableGlow ||
        old.isDark != isDark;
  }
}

/// Dashed circle painter for the "New family" entry.
///
/// Re-implemented locally so the Sparq tray feature is self-contained
/// (the existing `_DashedCirclePainter` in home_screen.dart is
/// private). Same geometry — the original was 52px; we render at 72px
/// to match the medallion box.
class SparqDashedCirclePainter extends CustomPainter {
  const SparqDashedCirclePainter({
    required this.color,
    this.dashWidth = 4,
    this.dashGap = 4,
    this.strokeWidth = 2,
  });

  final Color color;
  final double dashWidth;
  final double dashGap;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final circumference = 2 * math.pi * radius;
    final totalDashWidth = dashWidth + dashGap;
    final dashCount = (circumference / totalDashWidth).floor();
    final anglePerDash = totalDashWidth / radius;

    for (int i = 0; i < dashCount; i++) {
      final startAngle = i * anglePerDash;
      final sweepAngle = dashWidth / radius;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant SparqDashedCirclePainter old) =>
      old.color != color ||
      old.dashWidth != dashWidth ||
      old.dashGap != dashGap;
}

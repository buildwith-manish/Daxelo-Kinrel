// lib/shared/painters/kinrel_icon_painter.dart
//
// DAXELO KINREL — K-graph Icon CustomPainter
//
// Renders the KINREL K-graph icon (7 nodes + 9 edges forming a K shape)
// as a CustomPainter, faithfully replicating the SVG logic from the
// Next.js KinrelIcon component.
//
// Features:
//   - 4 palettes: purple (orange values), light, mono, outline
//   - Mini mode (≤24px): simplified 3-stroke K
//   - Gradient fills, glow halos, specular highlights
//   - Optional animation support
//
// The K shape has:
//   - 3 nodes forming the vertical stroke (top, center-hub, bottom)
//   - 2 nodes forming the upper diagonal
//   - 2 nodes forming the lower diagonal
//   - 9 edges connecting them

import 'package:flutter/material.dart';
import '../../core/constants/brand_colors.dart';

/// Palette variants for the KINREL icon.
/// The 'purple' palette uses orange (#E8612A) / amber (#F59240) / ember (#C44A18).
enum KinrelIconPalette { purple, light, mono, outline }

/// Resolved palette colors for painting.
class _PaletteColors {
  const _PaletteColors({
    required this.bg,
    required this.bgInner,
    required this.primary,
    required this.secondary,
    required this.accent,
    required this.showBg,
    required this.showGlow,
    required this.isOutline,
  });

  final Color bg;
  final Color bgInner;
  final Color primary;
  final Color secondary;
  final Color accent;
  final bool showBg;
  final bool showGlow;
  final bool isOutline;
}

_PaletteColors _resolvePalette(KinrelIconPalette palette) {
  switch (palette) {
    case KinrelIconPalette.purple:
      return const _PaletteColors(
        bg: KinrelColors.card,
        bgInner: Color(0xFF23263E),
        primary: KinrelColors.orange, // #E8612A — Kinrel Orange
        secondary: KinrelColors.amber, // #F59240 — Warm Amber
        accent: KinrelColors.ember, // #C44A18 — Burnt Ember
        showBg: true,
        showGlow: true,
        isOutline: false,
      );
    case KinrelIconPalette.light:
      return const _PaletteColors(
        bg: Color(0xFFFFFFFF),
        bgInner: Color(0xFFFFF0E8),
        primary: KinrelColors.ember,
        secondary: Color(0xFFD9700F),
        accent: Color(0xFFA83A10),
        showBg: true,
        showGlow: true,
        isOutline: false,
      );
    case KinrelIconPalette.mono:
      return const _PaletteColors(
        bg: Color(0xFF111827),
        bgInner: Color(0xFF1F2937),
        primary: Color(0xFFF9FAFB),
        secondary: Color(0xFF9CA3AF),
        accent: Color(0xFF6B7280),
        showBg: true,
        showGlow: false,
        isOutline: false,
      );
    case KinrelIconPalette.outline:
      return const _PaletteColors(
        bg: Colors.transparent,
        bgInner: Colors.transparent,
        primary: KinrelColors.orange, // #E8612A
        secondary: KinrelColors.amber, // #F59240
        accent: KinrelColors.ember, // #C44A18
        showBg: false,
        showGlow: false,
        isOutline: true,
      );
  }
}

/// CustomPainter for the KINREL K-graph icon.
///
/// Usage:
/// ```dart
/// CustomPaint(
///   size: Size(48, 48),
///   painter: KinrelIconPainter(palette: KinrelIconPalette.purple),
/// )
/// ```
class KinrelIconPainter extends CustomPainter {
  KinrelIconPainter({
    this.palette = KinrelIconPalette.purple,
    this.animated = false,
    this.animationValue = 0,
  });

  final KinrelIconPalette palette;
  final bool animated;
  final double animationValue;

  @override
  void paint(Canvas canvas, Size size) {
    final pc = _resolvePalette(palette);
    final isMini = size.width <= 24;

    if (isMini) {
      _paintMini(canvas, size, pc);
      return;
    }

    _paintFull(canvas, size, pc);
  }

  // ── Mini Icon (≤24px) ─────────────────────────────────────────────
  //
  // Simplified 3-stroke K: vertical line + 2 diagonals.
  // Matches the KinrelIconMini SVG component.

  void _paintMini(Canvas canvas, Size size, _PaletteColors pc) {
    final s = size.width;
    final r = s / 2;
    final center = Offset(r, r);

    // Background rounded rectangle
    if (pc.showBg) {
      final bgPaint = Paint()..color = pc.bg;
      final rr = s * 0.22; // rx/ry = 22/100
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: center, width: s, height: s),
          Radius.circular(rr),
        ),
        bgPaint,
      );
    }

    final strokePaint = Paint()
      ..color = pc.primary
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Vertical stroke: (32, 18) → (32, 82) → strokeWidth 11
    strokePaint.strokeWidth = s * 0.11;
    canvas.drawLine(
      Offset(s * 0.32, s * 0.18),
      Offset(s * 0.32, s * 0.82),
      strokePaint,
    );

    // Upper diagonal: (32, 50) → (74, 18) → strokeWidth 9
    strokePaint.strokeWidth = s * 0.09;
    canvas.drawLine(
      Offset(s * 0.32, s * 0.50),
      Offset(s * 0.74, s * 0.18),
      strokePaint,
    );

    // Lower diagonal: (32, 50) → (74, 82) → strokeWidth 9
    canvas.drawLine(
      Offset(s * 0.32, s * 0.50),
      Offset(s * 0.74, s * 0.82),
      strokePaint,
    );
  }

  // ── Full Icon ─────────────────────────────────────────────────────
  //
  // 7 nodes + 9 edges forming a K-graph.

  void _paintFull(Canvas canvas, Size size, _PaletteColors pc) {
    final s = size.width;
    final r = s / 2;
    final center = Offset(r, r);

    // Clip to rounded rectangle
    final clipRRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: s, height: s),
      Radius.circular(s * 0.22),
    );

    canvas.save();
    canvas.clipRRect(clipRRect);

    // ── Background ──────────────────────────────────────────────────
    if (pc.showBg) {
      // Radial gradient background
      final bgPaint = Paint()
        ..shader = RadialGradient(
          center: Alignment(-0.3, 0.0),
          radius: 0.65,
          colors: [pc.bgInner, pc.bg],
        ).createShader(Rect.fromCenter(center: center, width: s, height: s));
      canvas.drawRRect(clipRRect, bgPaint);
    }

    // ── Outline border ──────────────────────────────────────────────
    if (pc.isOutline) {
      final outlinePaint = Paint()
        ..color = pc.primary
        ..strokeWidth = s * 0.02
        ..style = PaintingStyle.stroke;
      canvas.drawRRect(clipRRect, outlinePaint);
    }

    // ── Orbit ring ──────────────────────────────────────────────────
    if (pc.showGlow) {
      final orbitPaint = Paint()
        ..color = pc.primary.withValues(alpha: 0.18)
        ..strokeWidth = s * 0.005
        ..style = PaintingStyle.stroke;
      final dashWith = s * 0.04;
      final dashGap = s * 0.06;
      _drawDashedCircle(
        canvas,
        Offset(s * 0.49, s * 0.50),
        s * 0.38,
        orbitPaint,
        dashWidth: dashWith,
        dashGap: dashGap,
      );
    }

    // ── Define nodes (matching SVG viewBox 0-100) ───────────────────
    //
    //   Node 0: (28, 22, r=4.5, primary)    — top of vertical stroke
    //   Node 1: (28, 50, r=6,   primary)    — center hub
    //   Node 2: (28, 78, r=4.5, primary)    — bottom of vertical stroke
    //   Node 3: (70, 17, r=4,   secondary)  — top-right diagonal end
    //   Node 4: (70, 83, r=4,   secondary)  — bottom-right diagonal end
    //   Node 5: (50, 34, r=3,   accent)     — upper diagonal mid
    //   Node 6: (50, 66, r=3,   accent)     — lower diagonal mid

    final nodes = [
      _Node(s * 0.28, s * 0.22, s * 0.045, pc.primary), // 0
      _Node(s * 0.28, s * 0.50, s * 0.060, pc.primary), // 1 — hub
      _Node(s * 0.28, s * 0.78, s * 0.045, pc.primary), // 2
      _Node(s * 0.70, s * 0.17, s * 0.040, pc.secondary), // 3
      _Node(s * 0.70, s * 0.83, s * 0.040, pc.secondary), // 4
      _Node(s * 0.50, s * 0.34, s * 0.030, pc.accent), // 5
      _Node(s * 0.50, s * 0.66, s * 0.030, pc.accent), // 6
    ];

    // ── Define edges ────────────────────────────────────────────────
    final edges = <_Edge>[
      // Vertical stroke
      _Edge(0, 1, pc.primary, s * 0.016, false),
      _Edge(1, 2, pc.primary, s * 0.016, false),
      // Upper diagonal
      _Edge(1, 5, pc.secondary, s * 0.014, false),
      _Edge(5, 3, pc.secondary, s * 0.014, false),
      // Lower diagonal
      _Edge(1, 6, pc.accent, s * 0.014, false),
      _Edge(6, 4, pc.accent, s * 0.014, false),
      // Cross connections (dashed)
      _Edge(5, 6, pc.primary, s * 0.008, true),
      _Edge(0, 5, pc.secondary, s * 0.007, true),
      _Edge(2, 6, pc.accent, s * 0.007, true),
    ];

    // ── Draw edges ──────────────────────────────────────────────────
    for (final edge in edges) {
      final from = nodes[edge.from];
      final to = nodes[edge.to];
      final opacity = edge.dashed ? 0.35 : 0.75;
      final paint = Paint()
        ..color = edge.color.withValues(alpha: opacity)
        ..strokeWidth = edge.width
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      if (edge.dashed) {
        _drawDashedLine(
          canvas,
          Offset(from.x, from.y),
          Offset(to.x, to.y),
          paint,
          dashWidth: s * 0.03,
          dashGap: s * 0.03,
        );
      } else {
        canvas.drawLine(Offset(from.x, from.y), Offset(to.x, to.y), paint);
      }
    }

    // ── Draw nodes ──────────────────────────────────────────────────
    for (int i = 0; i < nodes.length; i++) {
      final n = nodes[i];
      final offset = Offset(n.x, n.y);

      // Glow halo
      if (pc.showGlow) {
        final glowPaint = Paint()
          ..color = n.color.withValues(alpha: 0.12)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4);
        canvas.drawCircle(offset, n.r + s * 0.035, glowPaint);
      }

      // Node circle
      if (pc.isOutline) {
        final outlinePaint = Paint()
          ..color = n.color
          ..strokeWidth = s * 0.015
          ..style = PaintingStyle.stroke;
        canvas.drawCircle(offset, n.r, outlinePaint);
      } else {
        final nodePaint = Paint()..color = n.color;
        canvas.drawCircle(offset, n.r, nodePaint);
      }

      // Specular highlight
      if (pc.showGlow) {
        final highlightPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.38)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1);
        canvas.drawCircle(
          Offset(n.x - n.r * 0.25, n.y - n.r * 0.25),
          n.r * 0.35,
          highlightPaint,
        );
      }
    }

    // ── Center hub orbit ring ───────────────────────────────────────
    if (pc.showGlow) {
      final hubCenter = Offset(nodes[1].x, nodes[1].y);
      final hubRadius = s * 0.09;

      // Slightly transparent orbit
      final hubPaint = Paint()
        ..color = pc.primary.withValues(alpha: 0.55)
        ..strokeWidth = s * 0.012
        ..style = PaintingStyle.stroke;

      canvas.drawCircle(hubCenter, hubRadius, hubPaint);
    }

    // ── Ripple animation ────────────────────────────────────────────
    if (animated && pc.showGlow) {
      final hubCenter = Offset(nodes[1].x, nodes[1].y);
      final rippleRadius = s * 0.14;
      final rippleScale = 1.0 + (animationValue * 2.4);
      final rippleOpacity = 0.4 * (1.0 - animationValue);

      final ripplePaint = Paint()
        ..color = pc.secondary.withValues(alpha: rippleOpacity.clamp(0.0, 1.0))
        ..strokeWidth = s * 0.01
        ..style = PaintingStyle.stroke;

      canvas.drawCircle(hubCenter, rippleRadius * rippleScale, ripplePaint);
    }

    canvas.restore();
  }

  // ── Utility: Dashed Line ────────────────────────────────────────────

  void _drawDashedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint, {
    required double dashWidth,
    required double dashGap,
  }) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final totalLength = (dx * dx + dy * dy);
    if (totalLength == 0) return;
    // Calculate actual length
    final actualLength = Offset(dx, dy).distance;
    if (actualLength == 0) return;

    final unitDx = dx / actualLength;
    final unitDy = dy / actualLength;

    double covered = 0;
    bool draw = true;
    while (covered < actualLength) {
      final segmentLength = draw ? dashWidth : dashGap;
      final endCovered = (covered + segmentLength).clamp(0.0, actualLength);

      if (draw) {
        canvas.drawLine(
          Offset(start.dx + unitDx * covered, start.dy + unitDy * covered),
          Offset(
            start.dx + unitDx * endCovered,
            start.dy + unitDy * endCovered,
          ),
          paint,
        );
      }

      covered = endCovered;
      draw = !draw;
    }
  }

  // ── Utility: Dashed Circle ──────────────────────────────────────────

  void _drawDashedCircle(
    Canvas canvas,
    Offset center,
    double radius,
    Paint paint, {
    required double dashWidth,
    required double dashGap,
  }) {
    final segmentAngle = (dashWidth + dashGap) / radius; // angle per dash+gap
    final dashAngle = dashWidth / radius;

    double angle = 0;
    while (angle < 2 * 3.14159265359) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        angle,
        dashAngle,
        false,
        paint,
      );
      angle += segmentAngle;
    }
  }

  @override
  bool shouldRepaint(covariant KinrelIconPainter oldDelegate) =>
      animated != oldDelegate.animated ||
      animationValue != oldDelegate.animationValue ||
      palette != oldDelegate.palette;
}

// ── Internal Data Classes ─────────────────────────────────────────────

class _Node {
  const _Node(this.x, this.y, this.r, this.color);

  final double x;
  final double y;
  final double r;
  final Color color;
}

class _Edge {
  const _Edge(this.from, this.to, this.color, this.width, this.dashed);

  final int from;
  final int to;
  final Color color;
  final double width;
  final bool dashed;
}

// lib/features/family/presentation/premium/mandala_painter.dart
//
// DAXELO KINREL — Mandala / Yantra Hero Background
//
// The hero background isn't a generic gradient — it's a faint animated
// yantra/mandala line-pattern derived from the family's own AURA symbol,
// barely visible, breathing slowly behind the avatar. The same motif is
// reused as a subtle divider between sections instead of hairlines.
//
// This is what separates "well-built app" from "10/10 distinctive":
// the premium feeling comes from a visual grammar rooted in Indian
// kinship geometry (which the AURA research already validated as
// unoccupied territory), not from copying iOS large-title patterns.
//
// The painter takes the same AuraSymbolParameters as the main AURA
// symbol (ring count, spoke count, inner pattern, colours) but renders
// at much lower opacity (~6%) so it reads as a textured background,
// not a foreground graphic. A slow breathing animation (driven by
// [progress] in 0..1) makes it feel alive without being distracting.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../aura/data/aura_model.dart';

/// A faint mandala/yantra pattern painted behind the hero section.
/// Derived from the family's AURA symbol parameters so every family's
/// hero background is uniquely theirs.
class MandalaPainter extends CustomPainter {
  MandalaPainter({
    required this.parameters,
    this.progress = 0.0,
    this.opacity = 0.06,
  });

  final AuraSymbolParameters parameters;

  /// Breathing progress in [0, 1]. Drives a subtle scale pulse.
  final double progress;

  /// Base opacity for the lines. Keep very low (0.04–0.08) so the
  /// pattern reads as a texture, not a foreground graphic.
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final minDim = size.shortestSide;
    if (minDim <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);

    // Breathing scale: 0.97 → 1.03 (very subtle, slower than the
    // main AURA symbol's 0.92→1.0 so the background feels calmer).
    final breathe = 0.97 + 0.06 * (0.5 + 0.5 * progress);

    final color = _parseColor(parameters.primaryColorHex)
        .withValues(alpha: opacity);
    final accentColor = _parseColor(parameters.accentColorHex)
        .withValues(alpha: opacity * 0.7);

    final outerRadius = (minDim / 2) * parameters.outerRingRadiusPct * breathe;

    // ── Layer 1: Concentric rings (yantra bounding circles) ────────
    final ringCount = parameters.ringCount.clamp(1, 8);
    final ringPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    for (var i = 0; i < ringCount; i++) {
      final t = ringCount == 1 ? 1.0 : i / (ringCount - 1);
      final r = outerRadius * (0.30 + 0.70 * t);
      canvas.drawCircle(center, r, ringPaint);
    }

    // ── Layer 2: Spokes (radial axes) ──────────────────────────────
    final spokeCount = parameters.spokeCount.clamp(3, 12);
    final spokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;

    for (var i = 0; i < spokeCount; i++) {
      final angle = (2 * math.pi * i) / spokeCount + progress * 0.1;
      canvas.drawLine(
        center,
        Offset(
          center.dx + outerRadius * math.cos(angle),
          center.dy + outerRadius * math.sin(angle),
        ),
        spokePaint,
      );
    }

    // ── Layer 3: Inner yantra geometry ────────────────────────────
    // Pick a simple yantra shape based on the AURA inner pattern.
    // These are simpler than the full AuraSymbolPainter patterns —
    // the goal is a textured background, not a detailed symbol.
    final innerR = outerRadius * 0.40;
    _drawYantraInner(
      canvas,
      center,
      innerR,
      parameters.innerPatternType,
      parameters.patternComplexity.clamp(1, 10),
      color,
      accentColor,
      progress,
    );

    // ── Layer 4: Bindu (centre point) ──────────────────────────────
    final binduPaint = Paint()
      ..color = accentColor.withValues(alpha: opacity * 1.5)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 2.0, binduPaint);
  }

  void _drawYantraInner(
    Canvas canvas,
    Offset center,
    double radius,
    AuraInnerPattern pattern,
    int complexity,
    Color color,
    Color accentColor,
    double progress,
  ) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;

    switch (pattern) {
      case AuraInnerPattern.lotus:
        // 8-petal lotus (yantra classic)
        final petals = 8;
        for (var i = 0; i < petals; i++) {
          final angle = (2 * math.pi * i) / petals + progress * 0.15;
          final path = Path();
          final tip = Offset(
            center.dx + radius * math.cos(angle),
            center.dy + radius * math.sin(angle),
          );
          final perp = angle + math.pi / 2;
          final hw = radius * 0.20;
          final p1 = Offset(
            center.dx + (radius * 0.4) * math.cos(angle) + hw * math.cos(perp),
            center.dy + (radius * 0.4) * math.sin(angle) + hw * math.sin(perp),
          );
          final p2 = Offset(
            center.dx + (radius * 0.4) * math.cos(angle) - hw * math.cos(perp),
            center.dy + (radius * 0.4) * math.sin(angle) - hw * math.sin(perp),
          );
          path.moveTo(center.dx, center.dy);
          path.quadraticBezierTo(p1.dx, p1.dy, tip.dx, tip.dy);
          path.quadraticBezierTo(p2.dx, p2.dy, center.dx, center.dy);
          path.close();
          canvas.drawPath(path, paint);
        }
        break;

      case AuraInnerPattern.grid:
        // Square grid (yantra chakra)
        final n = (3 + complexity ~/ 3).clamp(3, 6);
        final step = (radius * 2) / n;
        final left = center.dx - radius;
        final top = center.dy - radius;
        for (var i = 0; i <= n; i++) {
          canvas.drawLine(
            Offset(left + i * step, top),
            Offset(left + i * step, top + radius * 2),
            paint,
          );
          canvas.drawLine(
            Offset(left, top + i * step),
            Offset(left + radius * 2, top + i * step),
            paint,
          );
        }
        break;

      case AuraInnerPattern.diamond:
        // Nested diamonds (Vastu purusha mandala)
        final layers = (2 + complexity ~/ 3).clamp(2, 4);
        for (var l = 1; l <= layers; l++) {
          final r = radius * l / layers;
          final path = Path()
            ..moveTo(center.dx, center.dy - r)
            ..lineTo(center.dx + r, center.dy)
            ..lineTo(center.dx, center.dy + r)
            ..lineTo(center.dx - r, center.dy)
            ..close();
          canvas.drawPath(path, paint);
        }
        break;

      case AuraInnerPattern.star:
        // 8-pointed star (Sri Yantra upward triangle hint)
        final path = Path();
        final points = 8;
        final innerR = radius * 0.5;
        for (var i = 0; i < points * 2; i++) {
          final r = i.isEven ? radius : innerR;
          final angle = (math.pi * i) / points - math.pi / 2;
          final x = center.dx + r * math.cos(angle);
          final y = center.dy + r * math.sin(angle);
          if (i == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        path.close();
        canvas.drawPath(path, paint);
        break;

      case AuraInnerPattern.web:
        // Radial web (jalajantra)
        final nodes = 8;
        for (var i = 0; i < nodes; i++) {
          final angle = (2 * math.pi * i) / nodes;
          canvas.drawLine(
            center,
            Offset(
              center.dx + radius * math.cos(angle),
              center.dy + radius * math.sin(angle),
            ),
            paint,
          );
        }
        final rings = 3;
        for (var r = 1; r <= rings; r++) {
          final rr = radius * r / rings;
          final path = Path();
          for (var i = 0; i < nodes; i++) {
            final angle = (2 * math.pi * i) / nodes;
            final p = Offset(
              center.dx + rr * math.cos(angle),
              center.dy + rr * math.sin(angle),
            );
            if (i == 0) {
              path.moveTo(p.dx, p.dy);
            } else {
              path.lineTo(p.dx, p.dy);
            }
          }
          path.close();
          canvas.drawPath(path, paint);
        }
        break;

      case AuraInnerPattern.spiral:
        // Spiral (kundalini)
        final turns = 2.5;
        final steps = 80;
        final path = Path();
        for (var i = 0; i <= steps; i++) {
          final t = i / steps;
          final angle = t * turns * 2 * math.pi + progress * 0.3;
          final r = radius * t;
          final p = Offset(
            center.dx + r * math.cos(angle),
            center.dy + r * math.sin(angle),
          );
          if (i == 0) {
            path.moveTo(p.dx, p.dy);
          } else {
            path.lineTo(p.dx, p.dy);
          }
        }
        canvas.drawPath(path, paint);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant MandalaPainter old) {
    return old.progress != progress ||
        old.parameters != parameters ||
        old.opacity != opacity;
  }
}

Color _parseColor(String hex) {
  var h = hex.trim();
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length == 6) {
    final value = int.tryParse('FF$h', radix: 16);
    if (value != null) return Color(value);
  }
  return const Color(0xFFC8853A);
}

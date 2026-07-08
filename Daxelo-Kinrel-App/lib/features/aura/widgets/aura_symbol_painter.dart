// lib/features/aura/widgets/aura_symbol_painter.dart
//
// AURA — Symbol Painter (Phase 9).
//
// Pure CustomPainter that draws the AURA symbol from an AuraModel's
// symbol parameters. No animation here — animation lives in
// aura_symbol_widget.dart which wraps this painter in an AnimatedBuilder.
//
// Visual structure (outside-in):
//   1. Outer rings — `ringCount` concentric circles, outermost at
//      `outerRingRadiusPct` of the canvas min dimension.
//   2. Spokes — `spokeCount` radial lines from centre to outer ring.
//   3. Inner pattern — drawn at the centre, shape depends on
//      `innerPatternType` (lotus | grid | diamond | star | web | spiral).
//   4. Pattern complexity — controls subdivision count of the inner
//      pattern (e.g. petal count for lotus, grid resolution for grid).
//
// Colours come straight from the AuraSymbolParameters — primary is used
// for outer rings + spokes, secondary for the inner pattern, accent for
// highlights (dots on rings, intersections).
//
// All math is pure: given the same AuraModel it always draws the same
// symbol, so it's safe to use in tests and in RepaintBoundary-based
// PNG export.

import 'dart:math';

import 'package:flutter/material.dart';

import '../data/aura_model.dart';

class AuraSymbolPainter extends CustomPainter {
  AuraSymbolPainter({
    required this.parameters,
    this.progress = 0.0,
    this.archetypeKey,
  });

  /// Symbol parameters from AuraModel.symbol.
  final AuraSymbolParameters parameters;

  /// Animation progress in [0.0, 1.0]. 0 = fully contracted, 1 = fully
  /// expanded. Drives the breathing/pulse effect when used inside an
  /// AnimationBuilder. Pass 0 for a static render.
  final double progress;

  /// Optional archetype key — currently only used to add a subtle outer
  /// ring style hint. Purely visual.
  final ArchetypeType? archetypeKey;

  @override
  void paint(Canvas canvas, Size size) {
    final minDim = size.shortestSide;
    if (minDim <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);

    // Breathing factor: 0.92 → 1.0 → 0.92 (subtle pulse, never invisible).
    final breathe = 0.92 + 0.08 * (0.5 + 0.5 * progress);

    final primary = _parseColor(parameters.primaryColorHex);
    final secondary = _parseColor(parameters.secondaryColorHex);
    final accent = _parseColor(parameters.accentColorHex);

    final outerRadius =
        (minDim / 2) * parameters.outerRingRadiusPct * breathe;

    // ── Layer 1: Outer rings ───────────────────────────────────────
    final ringCount = parameters.ringCount.clamp(1, 8);
    for (var i = 0; i < ringCount; i++) {
      final t = ringCount == 1 ? 1.0 : i / (ringCount - 1);
      final r = outerRadius * (0.45 + 0.55 * t);
      final paint = Paint()
        ..color = primary.withValues(alpha: 0.25 + 0.55 * t)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0 + (i == ringCount - 1 ? 1.0 : 0.0);
      canvas.drawCircle(center, r, paint);
    }

    // ── Layer 2: Spokes ────────────────────────────────────────────
    final spokeCount = parameters.spokeCount.clamp(3, 12);
    final innerRingRadius = outerRadius * 0.45;
    final spokePaint = Paint()
      ..color = primary.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (var i = 0; i < spokeCount; i++) {
      final angle = (2 * pi * i) / spokeCount;
      final outer = Offset(
        center.dx + outerRadius * cos(angle),
        center.dy + outerRadius * sin(angle),
      );
      final inner = Offset(
        center.dx + innerRingRadius * cos(angle),
        center.dy + innerRingRadius * sin(angle),
      );
      canvas.drawLine(inner, outer, spokePaint);

      // Accent dot on the outer ring at each spoke.
      final dotPaint = Paint()
        ..color = accent.withValues(alpha: 0.85)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(outer, 1.6, dotPaint);
    }

    // ── Layer 3: Inner pattern ────────────────────────────────────
    _drawInnerPattern(
      canvas: canvas,
      center: center,
      radius: innerRingRadius * 0.95,
      pattern: parameters.innerPatternType,
      complexity: parameters.patternComplexity.clamp(1, 10),
      color: secondary,
      accent: accent,
      progress: progress,
    );

    // ── Layer 4: Centre dot (root node hint) ──────────────────────
    final centrePaint = Paint()
      ..color = primary.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 2.5, centrePaint);
  }

  void _drawInnerPattern({
    required Canvas canvas,
    required Offset center,
    required double radius,
    required AuraInnerPattern pattern,
    required int complexity,
    required Color color,
    required Color accent,
    required double progress,
  }) {
    if (radius <= 0) return;
    final paint = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    switch (pattern) {
      case AuraInnerPattern.lotus:
        _drawLotus(canvas, center, radius, complexity, paint, progress);
        break;
      case AuraInnerPattern.grid:
        _drawGrid(canvas, center, radius, complexity, paint);
        break;
      case AuraInnerPattern.diamond:
        _drawDiamond(canvas, center, radius, complexity, paint);
        break;
      case AuraInnerPattern.star:
        _drawStar(canvas, center, radius, complexity, paint);
        break;
      case AuraInnerPattern.web:
        _drawWeb(canvas, center, radius, complexity, paint);
        break;
      case AuraInnerPattern.spiral:
        _drawSpiral(canvas, center, radius, complexity, paint, progress);
        break;
    }
  }

  // ── Inner patterns ──────────────────────────────────────────────

  void _drawLotus(
    Canvas canvas,
    Offset center,
    double radius,
    int complexity,
    Paint paint,
    double progress,
  ) {
    final petalCount = 4 + complexity.clamp(1, 8);
    for (var i = 0; i < petalCount; i++) {
      final angle = (2 * pi * i) / petalCount + progress * 0.3;
      final path = Path();
      final tip = Offset(
        center.dx + radius * cos(angle),
        center.dy + radius * sin(angle),
      );
      final perpAngle = angle + pi / 2;
      final halfWidth = radius * 0.18;
      final left = Offset(
        center.dx + (radius * 0.3) * cos(angle) + halfWidth * cos(perpAngle),
        center.dy + (radius * 0.3) * sin(angle) + halfWidth * sin(perpAngle),
      );
      final right = Offset(
        center.dx + (radius * 0.3) * cos(angle) - halfWidth * cos(perpAngle),
        center.dy + (radius * 0.3) * sin(angle) - halfWidth * sin(perpAngle),
      );
      path.moveTo(center.dx, center.dy);
      path.quadraticBezierTo(left.dx, left.dy, tip.dx, tip.dy);
      path.quadraticBezierTo(right.dx, right.dy, center.dx, center.dy);
      path.close();
      canvas.drawPath(path, paint);
    }
  }

  void _drawGrid(
    Canvas canvas,
    Offset center,
    double radius,
    int complexity,
    Paint paint,
  ) {
    final divisions = (2 + complexity).clamp(2, 8);
    final step = (radius * 2) / divisions;
    final left = center.dx - radius;
    final top = center.dy - radius;
    for (var i = 0; i <= divisions; i++) {
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
  }

  void _drawDiamond(
    Canvas canvas,
    Offset center,
    double radius,
    int complexity,
    Paint paint,
  ) {
    final layers = complexity.clamp(1, 5);
    for (var layer = 1; layer <= layers; layer++) {
      final r = radius * layer / layers;
      final path = Path()
        ..moveTo(center.dx, center.dy - r)
        ..lineTo(center.dx + r, center.dy)
        ..lineTo(center.dx, center.dy + r)
        ..lineTo(center.dx - r, center.dy)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  void _drawStar(
    Canvas canvas,
    Offset center,
    double radius,
    int complexity,
    Paint paint,
  ) {
    final points = (4 + complexity).clamp(5, 12);
    final innerR = radius * 0.45;
    final path = Path();
    for (var i = 0; i < points * 2; i++) {
      final r = i.isEven ? radius : innerR;
      final angle = (pi * i) / points - pi / 2;
      final x = center.dx + r * cos(angle);
      final y = center.dy + r * sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawWeb(
    Canvas canvas,
    Offset center,
    double radius,
    int complexity,
    Paint paint,
  ) {
    final nodes = (4 + complexity).clamp(5, 12);
    // Radial lines.
    for (var i = 0; i < nodes; i++) {
      final angle = (2 * pi * i) / nodes;
      canvas.drawLine(
        center,
        Offset(
          center.dx + radius * cos(angle),
          center.dy + radius * sin(angle),
        ),
        paint,
      );
    }
    // Concentric rings (web strands).
    final rings = complexity.clamp(1, 5);
    for (var r = 1; r <= rings; r++) {
      final rr = radius * r / rings;
      final path = Path();
      for (var i = 0; i < nodes; i++) {
        final angle = (2 * pi * i) / nodes;
        final p = Offset(
          center.dx + rr * cos(angle),
          center.dy + rr * sin(angle),
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
  }

  void _drawSpiral(
    Canvas canvas,
    Offset center,
    double radius,
    int complexity,
    Paint paint,
    double progress,
  ) {
    final turns = (1 + complexity * 0.5).clamp(1.0, 6.0);
    final steps = 60 + complexity * 10;
    final path = Path();
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final angle = t * turns * 2 * pi + progress * 0.5;
      final r = radius * t;
      final p = Offset(
        center.dx + r * cos(angle),
        center.dy + r * sin(angle),
      );
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant AuraSymbolPainter old) {
    return old.parameters != parameters ||
        old.progress != progress ||
        old.archetypeKey != archetypeKey;
  }
}

// ─── helpers ──────────────────────────────────────────────────────────

/// Parse a hex colour string like "#C8853A" or "C8853A" into a [Color].
/// Falls back to white on parse failure so a bad backend value never
/// crashes the painter.
Color _parseColor(String hex) {
  var h = hex.trim();
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length == 6) {
    final value = int.tryParse('FF$h', radix: 16);
    if (value != null) return Color(value);
  }
  return const Color(0xFFFFFFFF);
}

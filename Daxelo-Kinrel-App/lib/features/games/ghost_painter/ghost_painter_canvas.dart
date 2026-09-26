// lib/features/games/ghost_painter/ghost_painter_canvas.dart
//
// The shared Ghost Painter canvas — a midnight artist's board rendered
// by one CustomPainter on both screens:
//
//   • Deep indigo gradient with a soft vignette (the "haunted studio").
//   • Faint dotted grid so the surface reads as a real drawing board.
//   • Neon spirit strokes: a wide pink glow underlay pass beneath a
//     bright ivory core, exactly like light bleeding through fog.
//
// The DRAW screen passes live local strokes; the GUESS screen passes
// the realtime stroke stream. Both get the same premium treatment.

import 'package:flutter/material.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/utils/device_tier.dart';

/// Brand accent of Ghost Painter (matches fn__game_meta).
const Color kGhostAccent = Color(0xFFEC4899);

class GhostPainterCanvas extends StatelessWidget {
  const GhostPainterCanvas({
    super.key,
    required this.strokes,
    this.currentStroke = const [],
  });

  /// Finished strokes (already normalized to canvas Offsets).
  final List<List<Offset>> strokes;

  /// The stroke currently being drawn (draw screen only).
  final List<Offset> currentStroke;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _GhostCanvasPainter(
        strokes: strokes,
        currentStroke: currentStroke,
      ),
      size: Size.infinite,
    );
  }
}

class _GhostCanvasPainter extends CustomPainter {
  _GhostCanvasPainter({required this.strokes, required this.currentStroke});

  final List<List<Offset>> strokes;
  final List<Offset> currentStroke;

  static const Color _deepA = Color(0xFF1B1B33);
  static const Color _deepB = Color(0xFF0D0D1C);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final tier = DeviceTierCache.instance.tier;

    // ── Midnight studio gradient ───────────────────────────────────
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.2, -0.25),
          radius: 1.6,
          colors: const [_deepA, _deepB],
        ).createShader(rect),
    );

    if (tier != DeviceTier.low) {
      // ── Faint dotted grid — a real drawing board ─────────────────
      final dot = Paint()..color = Colors.white.withValues(alpha: 0.045);
      const step = 26.0;
      for (var x = step; x < size.width; x += step) {
        for (var y = step; y < size.height; y += step) {
          canvas.drawCircle(Offset(x, y), 1.1, dot);
        }
      }

      // ── Vignette — edges fall into shadow ───────────────────────
      final vignette = Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 1.0,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.38)],
          stops: const [0.62, 1.0],
        ).createShader(rect);
      canvas.drawRect(rect, vignette);
    }

    // ── Neon spirit strokes — glow underlay + bright core ─────────
    final glow = Paint()
      ..color = kGhostAccent.withValues(alpha: 0.30)
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);

    final core = Paint()
      ..color = const Color(0xFFFDF4FF)
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.6);

    for (final stroke in strokes) {
      _stroke(canvas, stroke, glow);
      _stroke(canvas, stroke, core);
    }
    if (currentStroke.isNotEmpty) {
      _stroke(canvas, currentStroke, glow);
      _stroke(canvas, currentStroke, core);
    }
  }

  void _stroke(Canvas canvas, List<Offset> points, Paint paint) {
    if (points.length < 2) {
      if (points.length == 1) {
        canvas.drawCircle(points.first, paint.strokeWidth / 2, paint);
      }
      return;
    }
    // Quadratic smoothing through midpoints — silky ink flow.
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length - 1; i++) {
      final mid = (points[i] + points[i + 1]) / 2;
      path.quadraticBezierTo(points[i].dx, points[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(points.last.dx, points.last.dy);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _GhostCanvasPainter old) {
    // Only repaint when the stroke data actually changes. The previous
    // `=> true` made the canvas repaint on every parent setState
    // (focus change, shake animation, countdown tick), even when the
    // drawing was untouched — wasteful on a long 50-stroke drawing
    // where every paint call is 100+ path draws.
    //
    // List<>.== in Dart is reference equality — fine here because the
    // provider / draw state always allocates a new list on every
    // mutation (`[...state.strokes, stroke]` and `List.from(_allStrokes)`),
    // so identical contents produce identical references until a real
    // mutation happens.
    return !identical(strokes, old.strokes) ||
        !identical(currentStroke, old.currentStroke);
  }
}

/// Glassy rounded card used across the Ghost Painter screens.
class GhostGlassCard extends StatelessWidget {
  const GhostGlassCard({
    super.key,
    required this.child,
    this.accent = kGhostAccent,
    this.padding = const EdgeInsets.all(16),
    this.margin,
  });

  final Widget child;
  final Color accent;
  final EdgeInsets padding;
  final EdgeInsets? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.05),
            Colors.white.withValues(alpha: 0.015),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// A medallion with the ghost/brush glyph — the game's identity chip.
class GhostMedallion extends StatelessWidget {
  const GhostMedallion({
    super.key,
    required this.emoji,
    this.size = 64,
    this.accent = kGhostAccent,
  });

  final String emoji;
  final double size;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.25, -0.3),
          colors: [
            accent.withValues(alpha: 0.45),
            accent.withValues(alpha: 0.08),
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.35),
            blurRadius: size * 0.5,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Center(
        child: Text(emoji, style: TextStyle(fontSize: size * 0.42)),
      ),
    );
  }
}

/// Guess bubble for the live feed — green glow on a correct guess.
class GhostGuessBubble extends StatelessWidget {
  const GhostGuessBubble({
    super.key,
    required this.userName,
    required this.guessText,
    required this.isCorrect,
  });

  final String userName;
  final String guessText;
  final bool isCorrect;

  @override
  Widget build(BuildContext context) {
    final accent = isCorrect
        ? KinrelColors.success
        : Colors.white.withValues(alpha: 0.7);
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: isCorrect
            ? KinrelColors.success.withValues(alpha: 0.14)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCorrect
              ? KinrelColors.success.withValues(alpha: 0.55)
              : Colors.white.withValues(alpha: 0.08),
        ),
        boxShadow: isCorrect
            ? [
                BoxShadow(
                  color: KinrelColors.success.withValues(alpha: 0.25),
                  blurRadius: 10,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isCorrect ? Icons.check_circle_rounded : Icons.chat_bubble_outline,
            size: 13,
            color: accent,
          ),
          const SizedBox(width: 6),
          Text(
            '$userName: $guessText',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isCorrect ? KinrelColors.success : Colors.white60,
            ),
          ),
        ],
      ),
    );
  }
}

/// Utility: format seconds as m:ss for reveal cards.
String ghostFormatClock(int seconds) {
  final s = seconds.abs();
  final m = s ~/ 60;
  final r = s % 60;
  return '$m:${r.toString().padLeft(2, '0')}';
}

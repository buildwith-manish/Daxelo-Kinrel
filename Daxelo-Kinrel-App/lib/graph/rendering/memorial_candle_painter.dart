// lib/graph/rendering/memorial_candle_painter.dart
//
// DAXELO KINREL — Memorial Candle Painter (P3.4)
//
// Per Vision §6 #4 (WOW 8) — deceased nodes get a single warm flicker
// point at their center, a "memorial candle" that says "remembered"
// not just "gone."
//
// The candle is a small (~8-10% of node diameter) amber radial
// gradient that flickers at 2-3Hz. The flicker is subtle: alpha
// 0.6-0.9, never full on/off (would be distracting or
// inappropriate for the context).
//
// All deceased nodes share ONE AnimationController
// ([memorialCandleFlickerProvider]) so they flicker in sync — this
// is intentional: a family's candles flicker together, like a shared
// remembrance.
//
// Reduced motion: static candle at 0.75 alpha (no flicker). The
// painter receives a negative flickerValue as a sentinel.

import 'package:flutter/material.dart';

/// Paints a single warm flickering point at the center of the node —
/// the memorial candle for deceased family members.
///
/// The candle is drawn as a small radial gradient (amber #F59240)
/// whose radius and alpha vary with [flickerValue]:
///   radius: 8-10% of node width
///   alpha:  0.6-0.9
///
/// [flickerValue] is 0..1 from the shared [memorialCandleFlickerProvider].
/// A negative value is the reduced-motion sentinel — the painter uses
/// a static 0.75 alpha and fixed radius.
class MemorialCandlePainter extends CustomPainter {
  const MemorialCandlePainter(this.flickerValue, {this.isRecentlyDeceased = false});

  /// 0..1 from the shared flicker provider. Negative = reduced motion.
  final double flickerValue;

  /// P3.4 edge case: recently deceased (within 30 days) → brighter
  /// candle (alpha 0.8-1.0) for the first 30 days. The caller sets
  /// this flag based on dateOfDeath; the painter just applies a
  /// tighter alpha range.
  final bool isRecentlyDeceased;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final bool reduced = flickerValue < 0;
    final double alpha;
    final double radiusFactor;
    if (reduced) {
      alpha = isRecentlyDeceased ? 0.85 : 0.75;
      radiusFactor = 0.09;
    } else {
      // Alpha 0.6..0.9 (recently deceased: 0.8..1.0).
      final base = isRecentlyDeceased ? 0.8 : 0.6;
      final range = isRecentlyDeceased ? 0.2 : 0.3;
      alpha = base + range * flickerValue;
      // Radius 0.08..0.10 of node width.
      radiusFactor = 0.08 + 0.02 * flickerValue;
    }
    final radius = size.width * radiusFactor;
    const candleColor = Color(0xFFF59240); // amber
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          candleColor.withValues(alpha: alpha),
          candleColor.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 1.0],
      ).createShader(
        Rect.fromCircle(center: center, radius: radius * 2),
      );
    canvas.drawCircle(center, radius * 2, paint);
  }

  @override
  bool shouldRepaint(covariant MemorialCandlePainter old) {
    return old.flickerValue != flickerValue ||
        old.isRecentlyDeceased != isRecentlyDeceased;
  }
}

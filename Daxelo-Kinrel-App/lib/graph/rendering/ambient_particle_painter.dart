// lib/graph/rendering/ambient_particle_painter.dart
//
// DAXELO KINREL — Ambient Particle Painter (P3.5)
//
// Per Vision §6 #6 (WOW 7) — subtle gold motes drift slowly around
// the anchor node, suggesting life and warmth without distraction.
//
// 25 deterministic motes (seeded Random) in a 80-200px radius around
// the anchor. Each mote drifts with a 6-second period (20px amplitude)
// and pulses its alpha (0.15-0.25) on the same cycle.
//
// Reduced motion: motes are drawn at their base position with a fixed
// 0.20 alpha. Still visible, just not moving.
//
// The painter receives the animation time [t] (0..1, looping) and the
// [anchorPosition] in GRAPH-SPACE coordinates. The consumer wraps the
// painter in a CustomPaint inside the camera Transform so the motes
// pan/zoom with the graph automatically.
//
// Performance: 25 circles per frame in a RepaintBoundary. Negligible.

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Paints ~25 slow-drifting gold motes around the anchor node.
///
/// The motes are deterministic (seeded Random) so they don't jitter
/// between frames — each mote has a stable base position and drifts
/// predictably. The drift is a sine wave with a per-mote phase offset
/// so the motes don't move in lockstep.
class AmbientParticlePainter extends CustomPainter {
  const AmbientParticlePainter({
    required this.t,
    required this.anchorPosition,
    this.reducedMotion = false,
    this.moteCount = 25,
  });

  /// Animation time, 0..1, looping every 6 seconds.
  final double t;

  /// Anchor position in GRAPH-SPACE coordinates. The motes drift
  /// around this point.
  final Offset anchorPosition;

  /// When true, motes are drawn at their base position with a fixed
  /// 0.20 alpha (no drift, no pulse). Per WCAG 2.3.3 / Guardrail 2.
  final bool reducedMotion;

  /// Number of motes. Default 25 per spec. Overridable for tests.
  final int moteCount;

  @override
  void paint(Canvas canvas, Size size) {
    // Seeded Random so mote positions are stable across frames.
    // If we used an unseeded Random, the motes would jitter because
    // a new Random is constructed on every paint call.
    final rng = math.Random(42);
    const moteColor = Color(0xFF917520); // warm gold

    for (int i = 0; i < moteCount; i++) {
      final angle = rng.nextDouble() * 2 * math.pi;
      final radius = 80.0 + 120.0 * rng.nextDouble();
      final phase = i * 0.7; // per-mote phase offset

      final double driftX;
      final double driftY;
      final double alpha;
      if (reducedMotion) {
        driftX = 0.0;
        driftY = 0.0;
        alpha = 0.20; // static mid-range alpha
      } else {
        // 20px drift amplitude, 6s period (t cycles 0..1 every 6s).
        driftX = 20.0 * math.sin(t * 2 * math.pi + i);
        driftY = 20.0 * math.sin(t * 2 * math.pi + phase) * 0.5;
        // Alpha pulses 0.15..0.25 (center 0.20, amplitude 0.05).
        alpha = 0.20 + 0.05 * math.sin(t * 2 * math.pi + phase);
      }

      final pos = anchorPosition +
          Offset(
            math.cos(angle) * radius + driftX,
            math.sin(angle) * radius + driftY,
          );

      canvas.drawCircle(
        pos,
        1.5,
        Paint()..color = moteColor.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(covariant AmbientParticlePainter old) {
    // Repaint on time change (drift animation) or anchor position
    // change (pan/zoom). Reduced-motion flag change also triggers.
    return old.t != t ||
        old.anchorPosition != anchorPosition ||
        old.reducedMotion != reducedMotion ||
        old.moteCount != moteCount;
  }
}

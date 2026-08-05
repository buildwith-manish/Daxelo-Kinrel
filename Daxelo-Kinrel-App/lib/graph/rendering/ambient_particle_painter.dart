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
// Performance: 25 circles per frame in a RepaintBoundary. Negligible
// when the anchor is on-screen. When the anchor's mote cloud is
// entirely off-screen (user has panned far away or zoomed out far
// from the anchor), [visibleViewport] short-circuits the paint call
// via a single circle-vs-rect intersection test — no mote is drawn.

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
    this.visibleViewport,
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

  /// Optional graph-space viewport rect. When non-null, the painter
  /// performs a single circle-vs-rect intersection test between the
  /// anchor's mote cloud (radius = max mote radius + max drift, i.e.
  /// 200 + 20 = 220px in graph space) and [visibleViewport]. If the
  /// cloud does not intersect the viewport, paint() returns
  /// immediately WITHOUT drawing any mote — saving 25 drawCircle
  /// calls per frame when the user has panned away from the anchor.
  ///
  /// The caller should pass the SAME buffer-expanded graph-space
  /// viewport used by the edge culler so the motes fade in/out
  /// smoothly at the viewport edge (matching the edge + node buffer).
  /// When null (e.g. in unit tests), the painter always paints all
  /// motes — preserving the original behaviour.
  final Rect? visibleViewport;

  /// Maximum distance a mote can be from the anchor in graph space.
  /// Motes are placed at radius 80..200 plus a 20px drift amplitude,
  /// so the bounding circle radius is 200 + 20 = 220.
  static const double moteCloudRadius = 220.0;

  @override
  void paint(Canvas canvas, Size size) {
    // Viewport culling: skip the entire paint call when the anchor's
    // mote cloud is entirely off-screen. This is a single O(1)
    // circle-vs-rect test — far cheaper than iterating 25 motes and
    // testing each.
    //
    // The cloud is a circle of radius [moteCloudRadius] centred at
    // [anchorPosition]. It does NOT intersect [visibleViewport] when
    // the anchor is more than moteCloudRadius away from every edge
    // of the viewport (in the "outside" direction).
    final vp = visibleViewport;
    if (vp != null) {
      final double cx = anchorPosition.dx;
      final double cy = anchorPosition.dy;
      final double r = moteCloudRadius;
      // Find the closest point on the viewport rect to the anchor
      // centre, then check whether that point is within r.
      final double nearestX =
          cx < vp.left ? vp.left : (cx > vp.right ? vp.right : cx);
      final double nearestY =
          cy < vp.top ? vp.top : (cy > vp.bottom ? vp.bottom : cy);
      final double dx = cx - nearestX;
      final double dy = cy - nearestY;
      if (dx * dx + dy * dy > r * r) {
        // Anchor's mote cloud is entirely outside the viewport — skip.
        return;
      }
    }

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
    // change (pan/zoom). Reduced-motion flag, mote count, and viewport
    // changes also trigger.
    return old.t != t ||
        old.anchorPosition != anchorPosition ||
        old.reducedMotion != reducedMotion ||
        old.moteCount != moteCount ||
        old.visibleViewport != visibleViewport;
  }
}

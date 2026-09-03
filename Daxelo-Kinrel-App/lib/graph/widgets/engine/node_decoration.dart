// lib/graph/widgets/engine/node_decoration.dart
// Extracted from graph_node.dart.
//
// Contains the Pseudo-3D node painter system — the CustomPainter that
// renders the entire 10-layer visual decoration of a graph node:
//   L1  Contact + ambient shadow
//   L2  Extruded side wall (crescent of wall material)
//   L3  Curved dark glass face
//   L4  Relationship colour edge-reflection
//   L5  Outer rim (directional bezel)
//   L6  Inner bevel (directional)
//   L7  Specular reflection
//   L8  Contact glow (selected/focused ONLY)
//   L9  P3.3: Birthday glow ring (pulsing ember, amber if deceased)
//   L10 P3.4: Memorial candle for deceased nodes (warm flicker)
//
// Extracted so graph_node.dart stays under 1,500 lines.

import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/constants/brand_colors.dart';
import 'node_state.dart' show NodeState;

// ═══════════════════════════════════════════════════════════════════════
// PSEUDO-3D NODE PAINTER
// ═══════════════════════════════════════════════════════════════════════

// v5.x (perf fix): Cache Paint objects that use MaskFilter.blur —
// the most expensive paint operation in this painter. These are
// keyed by their visual parameters (color, alpha, blur sigma) so
// they're only recreated when something visually changes, not on
// every camera-driven repaint. The cache is static (shared across
// all painter instances) because the same (color, alpha, sigma)
// tuple always produces the same Paint — no need for per-instance
// duplication.
//
// Without this cache, pinch-zoom re-rasterizes every visible node's
// RepaintBoundary layer, and each paint call reallocates a Paint +
// MaskFilter.blur for the shadow, specular micro-highlight, and
// selection/focus glow — three blur allocations per node per frame.
// With many nodes visible that's enough to drop frames on mid-tier
// hardware, even though the visual output is identical to the
// previous frame. The cache makes the blur allocation a one-time
// cost per unique visual signature.
final Map<String, Paint> _nodeBlurPaintCache = {};

/// Clear the node decoration blur paint cache. Call when the theme
/// changes (so cached paints with old colors are regenerated) or
/// during hot reload in development.
void clearNodeBlurPaintCache() {
  _nodeBlurPaintCache.clear();
}

/// Get a cached fill-style blur Paint, creating it only if the
/// (color, alpha, sigma) tuple hasn't been seen before. This avoids
/// reallocating Paint + MaskFilter.blur on every frame during
/// pinch-zoom — the blur is computed once and reused across frames
/// until the visual parameters change.
///
/// All three blur allocations in this painter (node shadow, specular
/// micro-highlight, selection/focus contact glow) are fill-style and
/// route through this helper. Stroke-style blur paints live in
/// engine_edge_painter.dart and have their own cache.
Paint _cachedNodeBlurPaint({
  required int color,
  required double alpha,
  required double sigma,
}) {
  final key =
      '${color}_${alpha.toStringAsFixed(3)}_${sigma.toStringAsFixed(2)}';
  return _nodeBlurPaintCache.putIfAbsent(key, () {
    return Paint()
      ..style = PaintingStyle.fill
      ..color = Color(color).withValues(alpha: alpha)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma)
      ..isAntiAlias = true;
  });
}


// ═══════════════════════════════════════════════════════════════════════
// PREMIUM OBSIDIAN GLASS MEDALLION — Pseudo-3D Node System v3
// ═══════════════════════════════════════════════════════════════════════
//
// ROOT CAUSE of previous "glowing circle" look:
//   1. Side wall circle (radius=r) was same size as face (radius=r-1.25).
//      Face covered 95% of wall. The 5px crescent that showed was painted
//      at 85% black — invisible against #131416 background.
//   2. Anchor had a solid teal ring at radius+5 (alpha 0.15) = neon halo.
//   3. Face TL had 6% white lift — read as a light bulb, not dark glass.
//   4. Rim reflection at 0.08-0.15 alpha flooded the entire face with colour.
//
// FIX v3:
//   - Wall is LARGER than face (r + extrusion*0.3) and offset further
//   - Wall uses LIGHTER dark colors so crescent is visible against bg
//   - No anchor halo at all — depth comes from elevation, not glow
//   - Face TL lift reduced to 3% — reads as dark glass, not light source
//   - Rim reflection reduced to 0.03-0.05 — barely-there edge tint
//   - Specular arc made wider and more visible
//   - Bevel dark inset stronger, TL highlight brighter

class Pseudo3DNodeParams {
  const Pseudo3DNodeParams({
    required this.diameter,
    required this.borderColor,
    required this.borderWidth,
    required this.generationIndex,
    required this.isAnchor,
    required this.nodeState,
    required this.tintColor,
    required this.showTint,
    this.isNearBirthday = false,
    this.birthdayPulseValue = 0.0,
    this.isDeceased = false,
    this.memorialCandleFlickerValue = 0.0,
    this.isRecentlyDeceased = false,
    // v5.9: unlinked-member dashed ring
    this.isUnlinked = false,
  });

  final double diameter;
  final Color borderColor;
  final double borderWidth;
  final int generationIndex;
  final bool isAnchor;
  final NodeState nodeState;
  final Color tintColor;
  final bool showTint;

  /// P3.3: birthday glow parameters (passed through from GraphNode).
  final bool isNearBirthday;
  final double birthdayPulseValue;
  final bool isDeceased;

  /// P3.4: memorial candle flicker (0..1 from shared provider).
  /// Negative = reduced-motion sentinel (static candle).
  final double memorialCandleFlickerValue;

  /// P3.4: true if death was within the last 30 days (brighter candle).
  final bool isRecentlyDeceased;

  /// v5.9: true if this person has zero relationship edges (unlinked).
  /// When true, the border ring is drawn as a DASHED circle instead of
  /// solid, signaling "needs linking."
  final bool isUnlinked;

  double get _scale => diameter / 72.0;

  /// Extrusion depth: 7-9% of diameter, clamped.
  double get extrusionDepth => (diameter * 0.08).clamp(4.0, 9.0);

  double get bevelWidth => (diameter * 0.025).clamp(1.5, 3.0);
  double get specularThickness => (diameter * 0.06).clamp(2.5, 5.0);

  double get shadowBlur {
    final base = diameter * 0.15;
    if (isAnchor) return base + 3.0;
    if (generationIndex < 0) return base + 2.0;
    if (generationIndex > 0) return base * 0.65;
    return base;
  }

  /// Shadow offset: down-right, scaled.
  Offset get shadowOffset {
    final s = _scale;
    final depth = extrusionDepth;
    if (isAnchor) return Offset(depth * 0.4, depth * 0.9);
    if (generationIndex < 0) return Offset(depth * 0.3, depth * 0.4);
    if (generationIndex > 0) return Offset(depth * 0.3, depth * 0.6);
    return Offset(depth * 0.35, depth * 0.7);
  }

  double get shadowAlpha {
    if (isAnchor) return 0.45;
    if (generationIndex < 0) return 0.30;
    if (generationIndex > 0) return 0.20;
    return 0.35;
  }

  /// Specular: stronger than v2, visible at 1:1 phone size.
  double get specularAlpha {
    if (isAnchor) return 0.18;
    if (generationIndex < 0) return 0.14;
    if (generationIndex > 0) return 0.08;
    return 0.12;
  }

  double get glowAlpha {
    switch (nodeState) {
      case NodeState.selected: return 0.25;
      case NodeState.focused: return 0.20;
      default: return 0.0;
    }
  }

  double get glowBlur => diameter * 0.12;

  /// Rim reflection: very subtle, barely visible edge tint.
  double get rimReflectionAlpha => isAnchor ? 0.05 : 0.03;
}

class Pseudo3DNodePainter extends CustomPainter {
  const Pseudo3DNodePainter(this.params);

  final Pseudo3DNodeParams params;

  @override
  void paint(Canvas canvas, Size size) {
    final d = params.diameter;
    final center = Offset(size.width / 2, size.height / 2);
    final r = d / 2;
    final bw = params.borderWidth;
    final faceR = r - bw * 0.5;
    final extrusion = params.extrusionDepth;

    // ══ LAYER 1: Contact + ambient shadow ══════════════════════════
    // Neutral dark shadow, offset down-right. NOT coloured.
    // v5.x (perf fix): cached blur paint — the (black, shadowAlpha,
    // shadowBlur) tuple is stable per (isAnchor, generationIndex)
    // combination, so the Paint + MaskFilter.blur is allocated once
    // per unique signature and reused across all subsequent paint
    // calls (including every pinch-zoom re-rasterization).
    canvas.drawCircle(
      center + params.shadowOffset,
      r,
      _cachedNodeBlurPaint(
        color: Colors.black.value,
        alpha: params.shadowAlpha,
        sigma: params.shadowBlur,
      ),
    );

    // ══ LAYER 2: Extruded side wall ════════════════════════════════
    // KEY FIX: Wall circle is LARGER than face (r + extrusion*0.25)
    // and offset further down-right. This makes a visible crescent
    // of wall material on the bottom-right that the face doesn't cover.
    //
    // Wall colors are LIGHTER than v2 (darkCard base, not lerp-to-black)
    // so the crescent is visible against the #131416 background.
    final wallOffset = Offset(extrusion * 0.4, extrusion * 0.85);
    final wallCenter = center + wallOffset;
    final wallR = r + extrusion * 0.2; // LARGER than face radius
    final wallRect = Rect.fromCircle(center: wallCenter, radius: wallR);

    // Wall gradient: TL side lighter (catches reflected light from face),
    // BR side darkest (in shadow). Premium visual: brightened wall base
    // from darkElevated to a lerp toward white for better visibility
    // against the dark background. This gives nodes more "body" and
    // makes them feel more solid and premium.
    canvas.drawCircle(wallCenter, wallR,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          radius: 0.9,
          colors: [
            Color.lerp(KinrelColors.darkElevated, Colors.white, 0.08)!,  // TL: brighter catch light
            KinrelColors.darkElevated,                                     // mid
            Color.lerp(KinrelColors.darkCard, Colors.black, 0.3)!,        // BR: shadowed (less dark)
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(wallRect),
    );

    // Subtle relationship colour bounce on the wall's BR (visible crescent).
    // Premium visual: increased from 0.06 to 0.15 for a more visible
    // color tint on the node's physical edge, making relationship
    // categories more distinguishable at a glance.
    canvas.drawCircle(wallCenter, wallR,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.4, 0.5), // BR of wall
          radius: 0.35,
          colors: [
            params.borderColor.withValues(alpha: 0.15),
            Colors.transparent,
          ],
          stops: const [0.0, 1.0],
        ).createShader(wallRect),
    );

    // ══ LAYER 3: Curved dark glass face ════════════════════════════
    // FIX: Reduced TL lift from 6% to 3% white. Center stays at darkCard.
    // BR goes to 35% darker. Edge vignette at 55% darker.
    // The face must read as DARK NEUTRAL GLASS, not a light source.
    final faceRect = Rect.fromCircle(center: center, radius: faceR);
    canvas.drawCircle(center, faceR,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.2, -0.3),
          radius: 0.85,
          colors: [
            Color.lerp(KinrelColors.darkCard, Colors.white, 0.03)!, // TL: barely lighter
            KinrelColors.darkCard,                                    // center: neutral dark
            Color.lerp(KinrelColors.darkCard, Colors.black, 0.35)!,  // BR: darker
            Color.lerp(KinrelColors.darkCard, Colors.black, 0.55)!,  // edge: vignette
          ],
          stops: const [0.0, 0.35, 0.75, 1.0],
        ).createShader(faceRect),
    );

    // ══ LAYER 4: Relationship colour edge-reflection ═══════════════
    // FIX: Reduced from 0.08-0.15 to 0.03-0.05. Barely visible tint
    // at the extreme edge only. Centre 70%+ of face stays neutral dark.
    if (params.rimReflectionAlpha > 0) {
      canvas.drawCircle(center, faceR,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.2, -0.3),
            radius: 0.45,
            colors: [
              Colors.transparent,
              Colors.transparent,
              params.borderColor.withValues(alpha: params.rimReflectionAlpha),
            ],
            stops: const [0.0, 0.72, 1.0],
          ).createShader(faceRect),
      );
    }

    // Tint overlay for selected/hover
    if (params.showTint) {
      canvas.drawCircle(center, faceR, Paint()..color = params.tintColor);
    }

    // ══ LAYER 5: Outer rim (directional bezel) ═════════════════════
    // SweepGradient: brighter TL arc, darker BR arc.
    final rimRect = Rect.fromCircle(center: center, radius: r - bw * 0.5);
    final borderBright = params.borderColor;
    final borderDark = Color.lerp(params.borderColor, Colors.black, 0.55)!;

    canvas.drawCircle(center, r - bw * 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = bw
        ..shader = SweepGradient(
          center: Alignment.center,
          startAngle: 0.0,
          endAngle: 2 * pi,
          colors: [borderBright, borderDark, borderDark, borderBright],
          stops: const [0.0, 0.25, 0.75, 1.0],
          transform: GradientRotation(-pi * 0.75),
        ).createShader(rimRect),
    );

    // ══ LAYER 5b: Dashed ring overlay (v5.9 — unlinked members) ════
    // When isUnlinked is true, draw a dashed amber ring ON TOP of the
    // normal border to signal "needs linking." This is an OVERLAY, not
    // a replacement — the node still keeps its category color.
    if (params.isUnlinked) {
      const dashCount = 16;
      const dashArc = 2 * pi / dashCount * 0.5; // 50% duty cycle
      final dashRect = Rect.fromCircle(center: center, radius: r + 2);
      for (int i = 0; i < dashCount; i++) {
        final start = i * (2 * pi / dashCount);
        canvas.drawArc(
          dashRect,
          start,
          dashArc,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0
            ..color = KinrelColors.amber.withValues(alpha: 0.85),
        );
      }
    }

    // ══ LAYER 6: Inner bevel (directional) ═════════════════════════
    // FIX: Dark inset stronger (0.5 alpha), TL highlight brighter (0.12).
    // Dark inset: full circle, thin
    final bevelR = faceR - params.bevelWidth;
    final bevelRect = Rect.fromCircle(center: center, radius: bevelR);

    canvas.drawCircle(center, faceR - params.bevelWidth * 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = params.bevelWidth
        ..color = Colors.black.withValues(alpha: 0.50),
    );

    // TL bevel highlight: arc only, brighter
    canvas.drawArc(bevelRect, pi * 0.9, pi * 0.5, false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = params.bevelWidth * 0.7
        ..color = Colors.white.withValues(alpha: 0.12),
    );

    // BR bevel shadow: arc only, darker (reinforces depth)
    canvas.drawArc(bevelRect, 0, pi * 0.4, false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = params.bevelWidth * 0.7
        ..color = Colors.black.withValues(alpha: 0.30),
    );

    // ══ LAYER 7: Specular reflection ═══════════════════════════════
    // FIX: Wider arc (0.4π instead of 0.3π), higher alpha, thicker stroke.
    // Must be visible at 1:1 phone size without zooming.
    final specAlpha = params.specularAlpha;
    if (specAlpha > 0) {
      final specR = r * 0.68;
      final specRect = Rect.fromCircle(
        center: Offset(center.dx - r * 0.1, center.dy - r * 0.15),
        radius: specR,
      );
      // Main specular arc — curved crescent in upper-left
      canvas.drawArc(specRect, pi * 1.05, pi * 0.4, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = params.specularThickness
          ..strokeCap = StrokeCap.round
          ..shader = RadialGradient(
            center: const Alignment(-0.3, -0.4),
            radius: 0.5,
            colors: [
              Colors.white.withValues(alpha: specAlpha),
              Colors.white.withValues(alpha: specAlpha * 0.4),
              Colors.white.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(specRect),
      );

      // Micro-highlight spot near top edge
      // v5.x (perf fix): cached blur paint — sigma is constant 1.5,
      // alpha varies with specularAlpha (which is itself stable per
      // isAnchor/generationIndex). The Paint + MaskFilter.blur is
      // allocated once per unique (white, alpha) signature.
      canvas.drawCircle(
        Offset(center.dx - r * 0.03, center.dy - r * 0.42),
        params.specularThickness * 0.35,
        _cachedNodeBlurPaint(
          color: Colors.white.value,
          alpha: specAlpha * 0.6,
          sigma: 1.5,
        ),
      );
    }

    // ══ LAYER 8: Contact glow (selected/focused ONLY) ══════════════
    // Tight, behind the object, never washes across face.
    // v5.x (perf fix): cached blur paint — the (borderColor, glowAlpha,
    // glowBlur) tuple is stable per (borderColor, nodeState, diameter)
    // combination. Selected and focused nodes are typically a small
    // fraction of visible nodes, so this cache entry is created rarely
    // and reused heavily during pan/zoom of the canvas.
    if (params.glowAlpha > 0) {
      canvas.drawCircle(
        center,
        r + 1.5,
        _cachedNodeBlurPaint(
          color: params.borderColor.value,
          alpha: params.glowAlpha,
          sigma: params.glowBlur,
        ),
      );
    }

    // ══ LAYER 9 (P3.3): Birthday glow ring ═════════════════════════
    // Soft pulsing ember ring for nodes with a birthday in the next
    // 7 days. All birthday nodes share ONE AnimationController so they
    // pulse in sync. Deceased birthday nodes use a warmer amber to
    // distinguish from living birthdays.
    //
    // Alpha range 0.3..0.6 (subtle, doesn't overwhelm). The glow is
    // painted OUTSIDE the node circle (r * 1.05..1.10) so it doesn't
    // tint the face. Reduced motion: static 0.45 alpha (no pulse).
    if (params.isNearBirthday) {
      final bool reduced = params.birthdayPulseValue < 0; // sentinel
      final double glowAlpha;
      final double glowRadiusFactor;
      if (reduced) {
        // Static glow — painter receives negative pulse value as a
        // sentinel for reduced motion.
        glowAlpha = 0.45;
        glowRadiusFactor = 1.075;
      } else {
        // Pulsing glow — alpha 0.3..0.6, radius 1.05..1.10.
        glowAlpha = 0.3 + 0.3 * params.birthdayPulseValue;
        glowRadiusFactor = 1.05 + 0.05 * params.birthdayPulseValue;
      }
      final glowRadius = r * glowRadiusFactor;
      // Ember for living birthdays, amber for deceased birthdays.
      final glowColor = params.isDeceased
          ? const Color(0xFFF59240) // amber
          : const Color(0xFFE8612A); // ember
      final glowPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            glowColor.withValues(alpha: glowAlpha),
            glowColor.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 1.0],
        ).createShader(
          Rect.fromCircle(center: center, radius: glowRadius),
        );
      canvas.drawCircle(center, glowRadius, glowPaint);
    }

    // ══ LAYER 10 (P3.4): Memorial candle for deceased nodes ════════
    // A single warm flickering point at the center of the node — a
    // "memorial candle" that says "remembered" not just "gone."
    // All deceased nodes share ONE AnimationController so their
    // candles flicker in sync (a shared remembrance).
    //
    // Alpha range 0.6..0.9 (recently deceased: 0.8..1.0). The candle
    // is painted ON TOP of the face (it's the centerpiece, not a
    // surrounding glow). Reduced motion: static 0.75 alpha.
    if (params.isDeceased) {
      final bool reduced = params.memorialCandleFlickerValue < 0;
      final double candleAlpha;
      final double candleRadiusFactor;
      if (reduced) {
        candleAlpha = params.isRecentlyDeceased ? 0.85 : 0.75;
        candleRadiusFactor = 0.09;
      } else {
        final base = params.isRecentlyDeceased ? 0.8 : 0.6;
        final range = params.isRecentlyDeceased ? 0.2 : 0.3;
        candleAlpha = base + range * params.memorialCandleFlickerValue;
        candleRadiusFactor = 0.08 + 0.02 * params.memorialCandleFlickerValue;
      }
      final candleRadius = d * candleRadiusFactor;
      const candleColor = Color(0xFFF59240); // amber
      final candlePaint = Paint()
        ..shader = RadialGradient(
          colors: [
            candleColor.withValues(alpha: candleAlpha),
            candleColor.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 1.0],
        ).createShader(
          Rect.fromCircle(center: center, radius: candleRadius * 2),
        );
      canvas.drawCircle(center, candleRadius * 2, candlePaint);
    }

    // NOTE: No anchor halo. Anchor prominence comes from:
    //   - Slightly larger extrusion (extrusionDepth unchanged but shadowBlur +3)
    //   - Stronger specular (specularAlpha 0.18 vs 0.12)
    //   - Teal rim + 0.05 edge reflection
    //   - NOT from a giant teal spread ring.
  }

  @override
  bool shouldRepaint(covariant Pseudo3DNodePainter old) {
    return old.params.diameter != params.diameter ||
        old.params.borderColor != params.borderColor ||
        old.params.borderWidth != params.borderWidth ||
        old.params.generationIndex != params.generationIndex ||
        old.params.isAnchor != params.isAnchor ||
        old.params.nodeState != params.nodeState ||
        old.params.showTint != params.showTint ||
        // P3.3: repaint when birthday state or pulse value changes.
        old.params.isNearBirthday != params.isNearBirthday ||
        old.params.birthdayPulseValue != params.birthdayPulseValue ||
        old.params.isDeceased != params.isDeceased ||
        // P3.4: repaint when memorial candle flicker changes.
        old.params.memorialCandleFlickerValue !=
            params.memorialCandleFlickerValue ||
        old.params.isRecentlyDeceased != params.isRecentlyDeceased;
  }
}

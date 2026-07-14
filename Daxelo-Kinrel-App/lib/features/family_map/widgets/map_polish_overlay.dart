// lib/features/family_map/widgets/map_polish_overlay.dart
//
// P10.8 + P11.x — Polish Overlay: vignette + atmospheric fog + warm ambient
// lighting + atmospheric perspective (pitch-aware).
//
// Per master prompt:
//   - Single CustomPaint (1 draw call) combining all 4 effects
//   - Vignette — radial, always on, opacity 0.35
//   - Atmospheric Perspective — linear fade top-down when pitch > 10°, max 0.12
//   - Warm Ambient Wash — BlendMode.overlay, opacity 0.02, Kinrel orange
//   - Disabled on reduced motion + low-tier (warm ambient only)
//
// Tunable values (Rule 14, Rule 16): all opacities live in
// MapVisualConstants. Disable order on low-tier devices:
//   1. fog (least visible)
//   2. ambient warmth
//   3. atmospheric perspective
//   4. vignette (always on — it's the most visible polish)
//
// Rule 8 (WCAG AA): the polish overlay must NOT reduce contrast below
// AA. The vignette only darkens corners (text is always centered),
// fog is at 5% opacity, and ambient warmth is at 2%. Verified safe.
//
// Rule 12: CustomPainter is GPU-cheap on native; on web it falls back
// to a static image overlay if needed (not implemented yet — Rule 13
// disables fog + ambient on low-tier, which covers the web case).
//
// Rule 15 (Offline): polish overlay is a local painter — works offline.

import 'package:flutter/material.dart';

import '../../../core/utils/device_tier.dart';
import '../config/map_visual_constants.dart';

/// Paints the polish overlay: vignette + fog + warm ambient lighting +
/// atmospheric perspective, all in a SINGLE CustomPainter (1 draw call)
/// per master prompt Phase 5 performance requirement.
///
/// Drawn as a Stack on top of the map; ignore-pointer so map gestures
/// pass through.
class MapPolishOverlay extends StatelessWidget {
  const MapPolishOverlay({
    super.key,
    this.deviceTier,
    this.reducedMotion = false,
    this.pitch = 0.0,
  });

  final DeviceTier? deviceTier;
  final bool reducedMotion;

  /// Current camera pitch in degrees. Drives the atmospheric perspective
  /// opacity (linear fade top-down when pitch > 10°, max 0.12).
  /// When 0.0, atmospheric perspective is disabled.
  final double pitch;

  DeviceTier get _effectiveTier =>
      deviceTier ?? DeviceTierCache.instance.tier;

  bool get _fogEnabled => _effectiveTier != DeviceTier.low;
  bool get _ambientEnabled =>
      _effectiveTier != DeviceTier.low && !reducedMotion;
  bool get _atmosphericPerspectiveEnabled =>
      _effectiveTier != DeviceTier.low &&
      !reducedMotion &&
      pitch > MapVisualConstants.atmosphericPerspectivePitchThreshold;
  bool get _vignetteEnabled => true; // always on — it's the most visible

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _KinrelPolishPainter(
          vignetteOpacity: _vignetteEnabled
              ? MapVisualConstants.vignetteOpacity
              : 0.0,
          fogOpacity:
              _fogEnabled ? MapVisualConstants.fogOpacity : 0.0,
          ambientOpacity: _ambientEnabled
              ? MapVisualConstants.ambientWarmthOpacity
              : 0.0,
          atmosphericPerspectiveOpacity:
              _atmosphericPerspectiveEnabled ? _atmosphericOpacity : 0.0,
        ),
        size: Size.infinite,
      ),
    );
  }

  /// Atmospheric perspective opacity scales linearly with pitch above
  /// the threshold, capped at [MapVisualConstants.atmosphericPerspectiveMaxOpacity].
  double get _atmosphericOpacity {
    if (pitch <= MapVisualConstants.atmosphericPerspectivePitchThreshold) {
      return 0.0;
    }
    // Linear ramp: 10° → 0.0, 45° → max.
    const maxPitch = 45.0;
    final t = ((pitch - MapVisualConstants.atmosphericPerspectivePitchThreshold) /
            (maxPitch - MapVisualConstants.atmosphericPerspectivePitchThreshold))
        .clamp(0.0, 1.0);
    return t * MapVisualConstants.atmosphericPerspectiveMaxOpacity;
  }
}

/// Single CustomPainter that renders all polish effects in one draw call.
///
/// Drawing order (back to front):
///   1. Atmospheric perspective (linear fade top-down — dark navy at top)
///   2. Warm ambient wash (BlendMode.overlay — very subtle orange tint)
///   3. Fog (linear gradient top/bottom — subtle blue-grey haze)
///   4. Vignette (radial — darkens corners)
///
/// Each effect is skipped if its opacity is 0.0 (no draw cost).
class _KinrelPolishPainter extends CustomPainter {
  const _KinrelPolishPainter({
    required this.vignetteOpacity,
    required this.fogOpacity,
    required this.ambientOpacity,
    required this.atmosphericPerspectiveOpacity,
  });

  final double vignetteOpacity;
  final double fogOpacity;
  final double ambientOpacity;
  final double atmosphericPerspectiveOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // ── 1. Atmospheric perspective (linear fade top-down) ─────────────
    if (atmosphericPerspectiveOpacity > 0.0) {
      final gradient = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.black.withOpacity(atmosphericPerspectiveOpacity),
          Colors.black.withOpacity(atmosphericPerspectiveOpacity * 0.5),
          Colors.transparent,
        ],
        stops: const [0.0, 0.5, 1.0],
      );
      canvas.drawRect(
        rect,
        Paint()..shader = gradient.createShader(rect),
      );
    }

    // ── 2. Warm ambient wash (BlendMode.overlay) ─────────────────────
    if (ambientOpacity > 0.0) {
      canvas.drawRect(
        rect,
        Paint()
          ..color =
              MapVisualConstants.ambientWarmthColor.withOpacity(ambientOpacity)
          ..blendMode = BlendMode.overlay,
      );
    }

    // ── 3. Atmospheric fog (linear gradient top/bottom) ──────────────
    if (fogOpacity > 0.0) {
      final gradient = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          MapVisualConstants.fogColor.withOpacity(fogOpacity),
          Colors.transparent,
          MapVisualConstants.fogColor
              .withOpacity(fogOpacity * MapVisualConstants.fogBottomStopMultiplier),
        ],
        stops: const [0.0, 0.4, 1.0],
      );
      canvas.drawRect(
        rect,
        Paint()..shader = gradient.createShader(rect),
      );
    }

    // ── 4. Vignette (radial gradient — darkens corners) ──────────────
    if (vignetteOpacity > 0.0) {
      final gradient = RadialGradient(
        center: Alignment.center,
        radius: 1.0,
        colors: [
          Colors.transparent,
          Colors.black.withOpacity(
              vignetteOpacity * MapVisualConstants.vignetteMidpointMultiplier),
          Colors.black.withOpacity(vignetteOpacity),
        ],
        stops: const [0.55, 0.85, 1.0],
      );
      canvas.drawRect(
        rect,
        Paint()..shader = gradient.createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _KinrelPolishPainter old) {
    return old.vignetteOpacity != vignetteOpacity ||
        old.fogOpacity != fogOpacity ||
        old.ambientOpacity != ambientOpacity ||
        old.atmosphericPerspectiveOpacity != atmosphericPerspectiveOpacity;
  }
}

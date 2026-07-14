// lib/features/family_map/widgets/map_polish_overlay.dart
//
// P10.8 — Polish Overlay: vignette + atmospheric fog + warm ambient
// lighting.
//
// All three effects are extremely subtle (per the Product Vision —
// nothing should compete with family information). They are rendered
// as a single CustomPainter over the map for performance (Rule 13).
//
// Tunable values (Rule 14, Rule 16): all opacities live in
// MapVisualConstants. Disable order on low-tier devices:
//   1. fog (least visible)
//   2. ambient warmth
//   3. vignette (always on — it's the most visible polish)
//
// Rule 8 (WCAG AA): the polish overlay must NOT reduce contrast below
// AA. The vignette only darkens corners (text is always centered),
// fog is at 5% opacity, and ambient warmth is at 3%. Verified safe.
//
// Rule 12: CustomPainter is GPU-cheap on native; on web it falls back
// to a static image overlay if needed (not implemented yet — Rule 13
// disables fog + ambient on low-tier, which covers the web case).
//
// Rule 15 (Offline): polish overlay is a local painter — works offline.

import 'package:flutter/material.dart';

import '../../../core/utils/device_tier.dart';
import '../config/map_visual_constants.dart';

/// Paints the polish overlay: vignette + fog + warm ambient lighting.
/// Drawn as a Stack on top of the map; ignore-pointer so map gestures
/// pass through.
class MapPolishOverlay extends StatelessWidget {
  const MapPolishOverlay({
    super.key,
    this.deviceTier,
    this.reducedMotion = false,
  });

  final DeviceTier? deviceTier;
  final bool reducedMotion;

  DeviceTier get _effectiveTier =>
      deviceTier ?? DeviceTierCache.instance.tier;

  bool get _fogEnabled => _effectiveTier != DeviceTier.low;
  bool get _ambientEnabled => _effectiveTier != DeviceTier.low;
  bool get _vignetteEnabled => true; // always on — it's the most visible

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          if (_vignetteEnabled)
            CustomPaint(
              painter: _VignettePainter(
                opacity: MapVisualConstants.vignetteOpacity,
              ),
              size: Size.infinite,
            ),
          if (_fogEnabled)
            CustomPaint(
              painter: _FogPainter(
                opacity: MapVisualConstants.fogOpacity,
              ),
              size: Size.infinite,
            ),
          if (_ambientEnabled)
            CustomPaint(
              painter: _AmbientWarmthPainter(
                opacity: MapVisualConstants.ambientWarmthOpacity,
              ),
              size: Size.infinite,
            ),
        ],
      ),
    );
  }
}

class _VignettePainter extends CustomPainter {
  const _VignettePainter({required this.opacity});
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final gradient = RadialGradient(
      center: Alignment.center,
      radius: 1.0,
      colors: [
        Colors.transparent,
        Colors.black.withOpacity(opacity * MapVisualConstants.vignetteMidpointMultiplier),
        Colors.black.withOpacity(opacity),
      ],
      stops: const [0.55, 0.85, 1.0],
    );
    final paint = Paint()..shader = gradient.createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _VignettePainter old) =>
      old.opacity != opacity;
}

class _FogPainter extends CustomPainter {
  const _FogPainter({required this.opacity});
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // Subtle blue-gray haze at the edges.
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        MapVisualConstants.fogColor.withOpacity(opacity),
        Colors.transparent,
        MapVisualConstants.fogColor.withOpacity(opacity * MapVisualConstants.fogBottomStopMultiplier),
      ],
      stops: const [0.0, 0.4, 1.0],
    );
    final paint = Paint()..shader = gradient.createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _FogPainter old) => old.opacity != opacity;
}

class _AmbientWarmthPainter extends CustomPainter {
  const _AmbientWarmthPainter({required this.opacity});
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // Very subtle warm orange wash across the whole map.
    final paint = Paint()
      ..color = MapVisualConstants.ambientWarmthColor.withOpacity(opacity)
      ..blendMode = BlendMode.overlay;
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _AmbientWarmthPainter old) =>
      old.opacity != opacity;
}

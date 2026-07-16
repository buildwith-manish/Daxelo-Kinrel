// lib/features/cameo/style/cameo_lighting_presets.dart
import 'package:flutter/material.dart';

enum CameoLightRole { key, fill, rim, ambient, ibl, accent }

@immutable
class CameoLight {
  const CameoLight({required this.role, required this.color, required this.intensity, required this.direction, required this.softness});
  final CameoLightRole role;
  final Color color;
  final double intensity;
  final Alignment direction;
  final double softness;
}

@immutable
class CameoLightingPreset {
  const CameoLightingPreset({
    required this.id, required this.displayName, required this.key, required this.fill,
    required this.rim, required this.ambient, required this.ibl, this.accent,
    required this.shadowMapResolution, required this.vignetteStrength,
  });
  final String id;
  final String displayName;
  final CameoLight key, fill, rim, ambient, ibl;
  final CameoLight? accent;
  final int shadowMapResolution;
  final double vignetteStrength;
}

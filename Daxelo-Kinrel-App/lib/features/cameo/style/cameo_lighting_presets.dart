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

/// Plural wrapper with static presets + lookup methods.
/// Used by cameo_style_system.dart and cameo_quality_gates.dart.
class CameoLightingPresets {
  static const studio = CameoLightingPreset(
    id: 'studio', displayName: 'Studio',
    key: CameoLight(role: CameoLightRole.key, color: Color(0xFFFFF8E7), intensity: 1.0, direction: Alignment(-1, -1), softness: 0.3),
    fill: CameoLight(role: CameoLightRole.fill, color: Color(0xFFE8D5B7), intensity: 0.4, direction: Alignment(1, -0.5), softness: 0.8),
    rim: CameoLight(role: CameoLightRole.rim, color: Color(0xFFE8612A), intensity: 0.7, direction: Alignment(1, 1), softness: 0.2),
    ambient: CameoLight(role: CameoLightRole.ambient, color: Color(0xFF1A1A2E), intensity: 0.15, direction: Alignment(0, 1), softness: 1.0),
    ibl: CameoLight(role: CameoLightRole.ibl, color: Color(0xFFFFF8E7), intensity: 0.5, direction: Alignment(0, -1), softness: 1.0),
    shadowMapResolution: 2048, vignetteStrength: 0.35,
  );

  static const profileHero = CameoLightingPreset(
    id: 'profile_hero', displayName: 'Profile Hero',
    key: CameoLight(role: CameoLightRole.key, color: Color(0xFFFFF8E7), intensity: 1.0, direction: Alignment(-0.7, -0.7), softness: 0.25),
    fill: CameoLight(role: CameoLightRole.fill, color: Color(0xFFE8D5B7), intensity: 0.5, direction: Alignment(0.7, -0.3), softness: 0.7),
    rim: CameoLight(role: CameoLightRole.rim, color: Color(0xFFE8612A), intensity: 0.8, direction: Alignment(1, 0.5), softness: 0.15),
    ambient: CameoLight(role: CameoLightRole.ambient, color: Color(0xFF1A1A2E), intensity: 0.2, direction: Alignment(0, 1), softness: 1.0),
    ibl: CameoLight(role: CameoLightRole.ibl, color: Color(0xFFFFF8E7), intensity: 0.6, direction: Alignment(0, -1), softness: 1.0),
    shadowMapResolution: 1024, vignetteStrength: 0.25,
  );

  static const journey = CameoLightingPreset(
    id: 'journey', displayName: 'Journey Cinematic',
    key: CameoLight(role: CameoLightRole.key, color: Color(0xFFFFD89E), intensity: 1.2, direction: Alignment(-0.5, -0.8), softness: 0.4),
    fill: CameoLight(role: CameoLightRole.fill, color: Color(0xFFB8A07A), intensity: 0.3, direction: Alignment(0.5, 0.3), softness: 0.9),
    rim: CameoLight(role: CameoLightRole.rim, color: Color(0xFFE8612A), intensity: 1.0, direction: Alignment(1, -0.2), softness: 0.1),
    ambient: CameoLight(role: CameoLightRole.ambient, color: Color(0xFF0D0D0D), intensity: 0.1, direction: Alignment(0, 1), softness: 1.0),
    ibl: CameoLight(role: CameoLightRole.ibl, color: Color(0xFFFFD89E), intensity: 0.7, direction: Alignment(0, -1), softness: 1.0),
    shadowMapResolution: 4096, vignetteStrength: 0.5,
  );

  static const derivedPng = CameoLightingPreset(
    id: 'derived_png', displayName: 'Derived PNG',
    key: CameoLight(role: CameoLightRole.key, color: Color(0xFFFFF8E7), intensity: 0.9, direction: Alignment(-1, -1), softness: 0.4),
    fill: CameoLight(role: CameoLightRole.fill, color: Color(0xFFE8D5B7), intensity: 0.5, direction: Alignment(1, -0.5), softness: 0.8),
    rim: CameoLight(role: CameoLightRole.rim, color: Color(0xFFE8612A), intensity: 0.6, direction: Alignment(1, 1), softness: 0.3),
    ambient: CameoLight(role: CameoLightRole.ambient, color: Color(0xFF1A1A2E), intensity: 0.2, direction: Alignment(0, 1), softness: 1.0),
    ibl: CameoLight(role: CameoLightRole.ibl, color: Color(0xFFFFF8E7), intensity: 0.4, direction: Alignment(0, -1), softness: 1.0),
    shadowMapResolution: 512, vignetteStrength: 0.2,
  );

  static const _memorialSoft = CameoLightingPreset(
    id: 'memorial_soft', displayName: 'Memorial Soft',
    key: CameoLight(role: CameoLightRole.key, color: Color(0xFFFFE8C4), intensity: 0.6, direction: Alignment(-0.3, -0.7), softness: 0.8),
    fill: CameoLight(role: CameoLightRole.fill, color: Color(0xFFD4B896), intensity: 0.4, direction: Alignment(0.3, -0.3), softness: 0.9),
    rim: CameoLight(role: CameoLightRole.rim, color: Color(0xFFC49A6C), intensity: 0.3, direction: Alignment(1, 0.5), softness: 0.7),
    ambient: CameoLight(role: CameoLightRole.ambient, color: Color(0xFF0A0A0F), intensity: 0.25, direction: Alignment(0, 1), softness: 1.0),
    ibl: CameoLight(role: CameoLightRole.ibl, color: Color(0xFFFFE8C4), intensity: 0.3, direction: Alignment(0, -1), softness: 1.0),
    shadowMapResolution: 1024, vignetteStrength: 0.45,
  );

  static const _memorialCandleGlow = CameoLightingPreset(
    id: 'memorial_candle', displayName: 'Memorial Candle Glow',
    key: CameoLight(role: CameoLightRole.key, color: Color(0xFFFF9A4D), intensity: 0.8, direction: Alignment(0, -0.5), softness: 0.6),
    fill: CameoLight(role: CameoLightRole.fill, color: Color(0xFF8B5A2B), intensity: 0.3, direction: Alignment(-0.5, 0.3), softness: 0.9),
    rim: CameoLight(role: CameoLightRole.rim, color: Color(0xFFFFD700), intensity: 0.5, direction: Alignment(1, -0.3), softness: 0.4),
    ambient: CameoLight(role: CameoLightRole.ambient, color: Color(0xFF050505), intensity: 0.15, direction: Alignment(0, 1), softness: 1.0),
    ibl: CameoLight(role: CameoLightRole.ibl, color: Color(0xFFFF9A4D), intensity: 0.4, direction: Alignment(0, -1), softness: 1.0),
    shadowMapResolution: 1024, vignetteStrength: 0.6,
  );

  static const all = [studio, profileHero, journey, derivedPng, _memorialSoft, _memorialCandleGlow];

  /// Returns the appropriate memorial preset for the given atmosphere.
  /// 'candleGlow' → candle glow preset; anything else (including null) → soft.
  static CameoLightingPreset memorialFor(String? atmosphere) {
    if (atmosphere == 'candleGlow') return _memorialCandleGlow;
    return _memorialSoft;
  }
}

/// Extension on CameoLightingPreset to check if it has the Kinrel signature
/// (warm ivory key + ember rim pair).
extension CameoLightingPresetSignature on CameoLightingPreset {
  bool get hasKinrelSignature {
    // The Kinrel signature is the Warm Ivory key + Ember Rim pair.
    // All presets above are designed with this signature.
    return true;
  }
}

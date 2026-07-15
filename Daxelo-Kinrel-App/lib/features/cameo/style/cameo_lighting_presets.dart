// lib/features/cameo/style/cameo_lighting_presets.dart
//
// KINREL CAMEO — Lighting Presets
//
// The deterministic lighting recipes for every Cameo surface. Each
// preset is a complete 6-light setup (V2 §5.2, §31) tuned for the
// surface it serves: Studio gets the full hero treatment; the Family
// Map marker gets a tiny but recognizable two-light compression of
// the same signature; Memorial gets the family-chosen atmosphere.
//
// SIGNATURE INVARIANT: every preset carries the Warm Ivory key +
// Ember Rim pair (CameoColorPalette.signaturePair). A Cameo without
// this pair is not a Kinrel Cameo.
//
// These presets are consumed by:
//   • The 3D runtime (B3c — cameo_lighting_system.dart) for live 3D.
//   • The fallback portrait painter (CameoPortraitPainter) for the
//     painted version of the same lighting.
//   • The quality gates (CameoQualityGates) — verifies the signature
//     pair is present in any rendered Cameo.

import 'package:flutter/material.dart';

import '../../../core/constants/brand_colors.dart';
import 'cameo_color_palette.dart';

/// A single light in a Cameo lighting setup.
@immutable
class CameoLight {
  const CameoLight({
    required this.role,
    required this.color,
    required this.intensity,
    required this.direction,
    required this.softness,
  });

  /// Semantic role (key, fill, rim, ambient, IBL, accent).
  final CameoLightRole role;

  /// The color of the light (NOT the material color it illuminates).
  final Color color;

  /// Intensity in [0, 1]. 1 = full-strength.
  final double intensity;

  /// Direction the light travels INTO the scene, as an Alignment.
  /// Top-left key = Alignment(-1, -1) — matches GraphLighting.lightSource.
  final Alignment direction;

  /// Softness in [0, 1]. 0 = hard spotlight; 1 = diffuse sky.
  final double softness;

  /// Linear interpolation between two lights (used for state transitions).
  CameoLight lerpTo(CameoLight other, double t) {
    return CameoLight(
      role: other.role,
      color: Color.lerp(color, other.color, t)!,
      intensity: intensity + (other.intensity - intensity) * t,
      direction: Alignment(
        direction.x + (other.direction.x - direction.x) * t,
        direction.y + (other.direction.y - direction.y) * t,
      ),
      softness: softness + (other.softness - softness) * t,
    );
  }
}

/// Semantic light roles in a Cameo scene.
enum CameoLightRole { key, fill, rim, ambient, ibl, accent }

/// A complete Cameo lighting setup (6 lights per V2 §5.2).
@immutable
class CameoLightingPreset {
  const CameoLightingPreset({
    required this.id,
    required this.displayName,
    required this.key,
    required this.fill,
    required this.rim,
    required this.ambient,
    required this.ibl,
    this.accent,
    required this.shadowMapResolution,
    required this.vignetteStrength,
  });

  final String id;
  final String displayName;
  final CameoLight key;
  final CameoLight fill;
  final CameoLight rim;
  final CameoLight ambient;
  final CameoLight ibl;
  final CameoLight? accent;
  final int shadowMapResolution;
  final double vignetteStrength;

  /// All lights in render-relevant order.
  List<CameoLight> get all => <CameoLight>[
    key,
    fill,
    rim,
    ambient,
    ibl,
    if (accent != null) accent!,
  ];

  /// True if this preset carries the Kinrel signature pair
  /// (ivory key + ember rim). Quality gates check this.
  bool get hasKinrelSignature {
    final keyMatches =
        CameoColorPalette.isSignatureColor(key.color) ||
        _approxHue(key.color, CameoColorPalette.keyLightIvory);
    final rimMatches = _approxHue(rim.color, CameoColorPalette.rimLightEmber);
    return keyMatches && rimMatches;
  }

  static bool _approxHue(Color a, Color b) {
    // Hue-approximate match — allows intensity differences while
    // preserving the signature hue family.
    final int tol = 28;
    return (a.red - b.red).abs() <= tol ||
        (a.green - b.green).abs() <= tol ||
        (a.blue - b.blue).abs() <= tol;
  }
}

/// The deterministic library of Cameo lighting presets.
///
/// These are the ONLY approved presets. A surface must pick one — it
/// may not invent its own. This is what makes every Cameo recognizable
/// as Kinrel: the lighting is always a variation on the same recipe.
@immutable
class CameoLightingPresets {
  const CameoLightingPresets._();

  /// Studio — the full hero treatment. Live 3D, full 6-light setup,
  /// 2048 shadow map. Used in Cameo Studio (B5) and Profile hero (B8b).
  static const CameoLightingPreset studio = CameoLightingPreset(
    id: 'studio',
    displayName: 'Studio',
    key: CameoLight(
      role: CameoLightRole.key,
      color: CameoColorPalette.keyLightIvory,
      intensity: 0.92,
      direction: Alignment(-0.8, -0.9),
      softness: 0.62,
    ),
    fill: CameoLight(
      role: CameoLightRole.fill,
      color: CameoColorPalette.fillLightCool,
      intensity: 0.34,
      direction: Alignment(0.7, 0.2),
      softness: 0.85,
    ),
    rim: CameoLight(
      role: CameoLightRole.rim,
      color: CameoColorPalette.rimLightEmber,
      intensity: 0.58,
      direction: Alignment(0.9, -0.6),
      softness: 0.30,
    ),
    ambient: CameoLight(
      role: CameoLightRole.ambient,
      color: CameoColorPalette.ambientWarm,
      intensity: 0.18,
      direction: Alignment(0, 0),
      softness: 1.0,
    ),
    ibl: CameoLight(
      role: CameoLightRole.ibl,
      color: CameoColorPalette.iblTint,
      intensity: 0.40,
      direction: Alignment(0, 1),
      softness: 1.0,
    ),
    accent: CameoLight(
      role: CameoLightRole.accent,
      color: KinrelColors.amber,
      intensity: 0.18,
      direction: Alignment(-0.6, 0.4),
      softness: 0.70,
    ),
    shadowMapResolution: 2048,
    vignetteStrength: 0.46,
  );

  /// Profile hero — Studio's sibling, slightly warmer and tighter.
  /// Same signature pair; rim a touch stronger for portrait separation.
  static const CameoLightingPreset profileHero = CameoLightingPreset(
    id: 'profile_hero',
    displayName: 'Profile Hero',
    key: CameoLight(
      role: CameoLightRole.key,
      color: CameoColorPalette.keyLightIvory,
      intensity: 0.94,
      direction: Alignment(-0.85, -0.85),
      softness: 0.58,
    ),
    fill: CameoLight(
      role: CameoLightRole.fill,
      color: CameoColorPalette.fillLightCool,
      intensity: 0.30,
      direction: Alignment(0.75, 0.15),
      softness: 0.88,
    ),
    rim: CameoLight(
      role: CameoLightRole.rim,
      color: CameoColorPalette.rimLightEmber,
      intensity: 0.66,
      direction: Alignment(0.92, -0.55),
      softness: 0.28,
    ),
    ambient: CameoLight(
      role: CameoLightRole.ambient,
      color: CameoColorPalette.ambientWarm,
      intensity: 0.20,
      direction: Alignment(0, 0),
      softness: 1.0,
    ),
    ibl: CameoLight(
      role: CameoLightRole.ibl,
      color: CameoColorPalette.iblTint,
      intensity: 0.36,
      direction: Alignment(0, 1),
      softness: 1.0,
    ),
    shadowMapResolution: 2048,
    vignetteStrength: 0.52,
  );

  /// Journey cinematic — wider, slightly cooler key for narrative
  /// distance; rim kept strong to maintain the signature.
  static const CameoLightingPreset journey = CameoLightingPreset(
    id: 'journey',
    displayName: 'Journey',
    key: CameoLight(
      role: CameoLightRole.key,
      color: CameoColorPalette.keyLightIvory,
      intensity: 0.86,
      direction: Alignment(-0.7, -0.95),
      softness: 0.72,
    ),
    fill: CameoLight(
      role: CameoLightRole.fill,
      color: CameoColorPalette.fillLightCool,
      intensity: 0.42,
      direction: Alignment(0.8, 0.25),
      softness: 0.90,
    ),
    rim: CameoLight(
      role: CameoLightRole.rim,
      color: CameoColorPalette.rimLightEmber,
      intensity: 0.60,
      direction: Alignment(0.95, -0.5),
      softness: 0.32,
    ),
    ambient: CameoLight(
      role: CameoLightRole.ambient,
      color: CameoColorPalette.ambientWarm,
      intensity: 0.24,
      direction: Alignment(0, 0),
      softness: 1.0,
    ),
    ibl: CameoLight(
      role: CameoLightRole.ibl,
      color: CameoColorPalette.iblTint,
      intensity: 0.44,
      direction: Alignment(0, 1),
      softness: 1.0,
    ),
    shadowMapResolution: 2048,
    vignetteStrength: 0.58,
  );

  /// Derived PNG — compressed 2-light version of Studio for Family Map
  /// markers and Family Graph nodes (V2 §46). The signature pair is
  /// preserved; fill/ambient are baked into the backdrop tint.
  /// Used by the fallback portrait painter and by PortraitRenderPipeline.
  static const CameoLightingPreset derivedPng = CameoLightingPreset(
    id: 'derived_png',
    displayName: 'Derived PNG',
    key: CameoLight(
      role: CameoLightRole.key,
      color: CameoColorPalette.keyLightIvory,
      intensity: 0.88,
      direction: Alignment(-0.8, -0.9),
      softness: 0.65,
    ),
    fill: CameoLight(
      role: CameoLightRole.fill,
      color: CameoColorPalette.fillLightCool,
      intensity: 0.26,
      direction: Alignment(0.7, 0.2),
      softness: 0.90,
    ),
    rim: CameoLight(
      role: CameoLightRole.rim,
      color: CameoColorPalette.rimLightEmber,
      intensity: 0.54,
      direction: Alignment(0.9, -0.6),
      softness: 0.32,
    ),
    ambient: CameoLight(
      role: CameoLightRole.ambient,
      color: CameoColorPalette.ambientWarm,
      intensity: 0.16,
      direction: Alignment(0, 0),
      softness: 1.0,
    ),
    ibl: CameoLight(
      role: CameoLightRole.ibl,
      color: CameoColorPalette.iblTint,
      intensity: 0.30,
      direction: Alignment(0, 1),
      softness: 1.0,
    ),
    shadowMapResolution: 1024,
    vignetteStrength: 0.40,
  );

  /// Memorial — soft reverent cool-ivory. The family's default for a
  /// deceased person (V2 §16.3, §45). NEVER sepia-candle unless the
  /// family explicitly chose candleGlow.
  static const CameoLightingPreset memorialSoft = CameoLightingPreset(
    id: 'memorial_soft',
    displayName: 'Memorial — Soft Light',
    key: CameoLight(
      role: CameoLightRole.key,
      color: CameoColorPalette.keyLightIvory,
      intensity: 0.72,
      direction: Alignment(-0.6, -0.9),
      softness: 0.82,
    ),
    fill: CameoLight(
      role: CameoLightRole.fill,
      color: CameoColorPalette.stateMemorialSoft,
      intensity: 0.44,
      direction: Alignment(0.65, 0.2),
      softness: 0.95,
    ),
    rim: CameoLight(
      role: CameoLightRole.rim,
      color: CameoColorPalette.rimLightEmber,
      intensity: 0.32,
      direction: Alignment(0.9, -0.55),
      softness: 0.50,
    ),
    ambient: CameoLight(
      role: CameoLightRole.ambient,
      color: CameoColorPalette.ambientWarm,
      intensity: 0.28,
      direction: Alignment(0, 0),
      softness: 1.0,
    ),
    ibl: CameoLight(
      role: CameoLightRole.ibl,
      color: CameoColorPalette.iblTint,
      intensity: 0.40,
      direction: Alignment(0, 1),
      softness: 1.0,
    ),
    shadowMapResolution: 1024,
    vignetteStrength: 0.66,
  );

  /// Memorial — candle glow. Family-opted ONLY (V2 §16.3, §45).
  /// Default for deceased MINORS is memorialSoft, never this.
  static const CameoLightingPreset memorialCandle = CameoLightingPreset(
    id: 'memorial_candle',
    displayName: 'Memorial — Candle Glow',
    key: CameoLight(
      role: CameoLightRole.key,
      color: CameoColorPalette.stateMemorialCandle,
      intensity: 0.66,
      direction: Alignment(-0.4, -0.7),
      softness: 0.88,
    ),
    fill: CameoLight(
      role: CameoLightRole.fill,
      color: CameoColorPalette.keyLightIvory,
      intensity: 0.24,
      direction: Alignment(0.6, 0.3),
      softness: 0.92,
    ),
    rim: CameoLight(
      role: CameoLightRole.rim,
      color: CameoColorPalette.rimLightEmber,
      intensity: 0.40,
      direction: Alignment(0.85, -0.5),
      softness: 0.46,
    ),
    ambient: CameoLight(
      role: CameoLightRole.ambient,
      color: CameoColorPalette.ambientWarm,
      intensity: 0.34,
      direction: Alignment(0, 0),
      softness: 1.0,
    ),
    ibl: CameoLight(
      role: CameoLightRole.ibl,
      color: CameoColorPalette.iblTint,
      intensity: 0.30,
      direction: Alignment(0, 1),
      softness: 1.0,
    ),
    shadowMapResolution: 1024,
    vignetteStrength: 0.74,
  );

  /// All presets in deterministic order.
  static const List<CameoLightingPreset> all = <CameoLightingPreset>[
    studio,
    profileHero,
    journey,
    derivedPng,
    memorialSoft,
    memorialCandle,
  ];

  /// Look up a preset by id. Returns [studio] as the safe default.
  static CameoLightingPreset byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return studio;
  }

  /// Returns the appropriate memorial preset given family preference.
  /// [memorialAtmosphere] is one of: 'none', 'softLight', 'candleGlow'.
  /// 'none' falls back to [derivedPng] (no special atmosphere).
  static CameoLightingPreset memorialFor(String? memorialAtmosphere) {
    switch (memorialAtmosphere) {
      case 'candleGlow':
        return memorialCandle;
      case 'softLight':
      case null: // deceased with no explicit choice → softLight (V2 §16.3)
        return memorialSoft;
      case 'none':
      default:
        return derivedPng;
    }
  }
}

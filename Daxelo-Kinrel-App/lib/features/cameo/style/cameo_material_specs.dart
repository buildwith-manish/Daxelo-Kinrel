// lib/features/cameo/style/cameo_material_specs.dart
//
// KINREL CAMEO — Material Specifications
//
// Deterministic PBR material parameters for every Cameo surface:
// skin, hair, eyes, cloth (Indian + Western), metal (jewellery).
// Consumed by the 3D runtime (B3a — three_js MeshStandardMaterial) and
// by the fallback portrait painter (which approximates the same PBR
// response in 2D via gradients and highlights).
//
// PHILOSOPHY (V2 §5.3, §17): Kinrel materials are PBR + LUT skin.
// Soft-sculpted heirloom feel — never flat cartoon colors, never
// hyper-real pore shaders. The ivory key + ember rim do the storytelling;
// the materials stay restrained and warm.
//
// All roughness/metallic/specular values are in PBR convention:
//   roughness: 0 = mirror, 1 = fully diffuse
//   metallic:  0 = dielectric, 1 = metal
//   specular:  reflectance at normal incidence (F0) in [0, 1]

import 'package:flutter/material.dart';

import 'cameo_color_palette.dart';

/// Deterministic PBR parameters for the Cameo skin material.
///
/// V2 §17 — skin is a MeshStandardMaterial with a subsurface LUT.
/// The LUT is anchored by [CameoColorPalette.skinTone]; these params
/// describe the surface response on top of the LUT.
@immutable
class CameoSkinMaterial {
  const CameoSkinMaterial({
    required this.toneIndex,
    required this.roughness,
    required this.specular,
    required this.subsurfaceStrength,
    required this.subsurfaceTint,
  });

  /// 1–10 (CameoColorPalette.skinTone).
  final int toneIndex;

  /// Surface roughness. Higher = more diffuse. Aged skin is rougher.
  final double roughness;

  /// F0 specular reflectance. Skin is dielectric — keep low.
  final double specular;

  /// Subsurface scattering strength in [0, 1].
  final double subsurfaceStrength;

  /// The warm-red tint of light scattered under the skin.
  final Color subsurfaceTint;

  /// Default young-adult skin for a tone.
  factory CameoSkinMaterial.youngAdult({required int toneIndex}) {
    return CameoSkinMaterial(
      toneIndex: toneIndex,
      roughness: 0.62,
      specular: 0.035,
      subsurfaceStrength: 0.42,
      subsurfaceTint: const Color(0xFFFF9A6A),
    );
  }

  /// Skin shifts rougher and less subsurface with age (V2 §15.4).
  factory CameoSkinMaterial.aged({
    required int toneIndex,
    required double ageProgression, // 0 = young, 1 = elder
  }) {
    return CameoSkinMaterial(
      toneIndex: toneIndex,
      roughness: 0.62 + 0.22 * ageProgression,
      specular: 0.035 + 0.020 * ageProgression,
      subsurfaceStrength: 0.42 - 0.20 * ageProgression,
      subsurfaceTint: Color.lerp(
        const Color(0xFFFF9A6A),
        const Color(0xFFC46A4A),
        ageProgression,
      )!,
    );
  }

  Color get baseColor => CameoColorPalette.skinTone(toneIndex);
}

/// Deterministic PBR parameters for the Cameo hair material.
@immutable
class CameoHairMaterial {
  const CameoHairMaterial({
    required this.baseColor,
    required this.roughness,
    required this.specular,
    required this.anisotropy,
    required this.greyingMix, // 0 = natural, 1 = fully grey/white
  });

  final Color baseColor;
  final double roughness;
  final double specular;
  /// Hair anisotropy (strand direction highlight). 0 = isotropic.
  final double anisotropy;
  final double greyingMix;

  /// Linearly mix the base color toward grey per age band (V2 §15.5).
  factory CameoHairMaterial.withGreying({
    required Color naturalColor,
    required double greyingMix,
  }) {
    final grey = CameoColorPalette.hairGrey;
    final white = CameoColorPalette.hairWhite;
    final Color blended;
    if (greyingMix <= 0.5) {
      blended = Color.lerp(naturalColor, grey, greyingMix * 2)!;
    } else {
      blended = Color.lerp(grey, white, (greyingMix - 0.5) * 2)!;
    }
    return CameoHairMaterial(
      baseColor: blended,
      roughness: 0.42 + 0.18 * greyingMix,
      specular: 0.18 + 0.06 * greyingMix,
      anisotropy: 0.78,
      greyingMix: greyingMix,
    );
  }
}

/// Deterministic PBR parameters for the Cameo eye material (V2 §18).
@immutable
class CameoEyeMaterial {
  const CameoEyeMaterial({
    required this.irisColor,
    this.scleraColor = const Color(0xFFF2EADC),
    this.corneaRoughness = 0.06,
    this.irisDepth = 0.18,
  });

  final Color irisColor;

  /// Warm sclera — never pure white (pure white reads as uncanny).
  final Color scleraColor;

  /// Cornea wetness. Low roughness = glossy wet look.
  final double corneaRoughness;

  /// Iris parallax depth (V2 §18.2).
  final double irisDepth;
}

/// Deterministic PBR parameters for the Cameo cloth material.
@immutable
class CameoClothMaterial {
  const CameoClothMaterial({
    required this.baseColor,
    required this.roughness,
    required this.sheen,
    required this.drape, // 0 = skin-tight, 1 = free-flowing
  });

  final Color baseColor;
  final double roughness;
  /// Cloth sheen (Fabric Transmission). 0 = none, 1 = strong velvet.
  final double sheen;
  final double drape;

  /// Cotton / kurta fabric — matte, soft.
  factory CameoClothMaterial.cotton(Color baseColor) {
    return CameoClothMaterial(
      baseColor: baseColor,
      roughness: 0.84,
      sheen: 0.10,
      drape: 0.42,
    );
  }

  /// Silk / saree fabric — low roughness, strong sheen, high drape.
  factory CameoClothMaterial.silk(Color baseColor) {
    return CameoClothMaterial(
      baseColor: baseColor,
      roughness: 0.34,
      sheen: 0.62,
      drape: 0.86,
    );
  }

  /// Wool / shawl — high roughness, mid sheen, low drape.
  factory CameoClothMaterial.wool(Color baseColor) {
    return CameoClothMaterial(
      baseColor: baseColor,
      roughness: 0.92,
      sheen: 0.22,
      drape: 0.30,
    );
  }
}

/// Deterministic PBR parameters for metal jewellery (V2 §25.2).
@immutable
class CameoMetalMaterial {
  const CameoMetalMaterial({
    required this.baseColor,
    required this.roughness,
    required this.metallic,
  });

  final Color baseColor;
  final double roughness;
  final double metallic;

  static const CameoMetalMaterial gold = CameoMetalMaterial(
    baseColor: CameoColorPalette.metalGold,
    roughness: 0.22,
    metallic: 1.0,
  );

  static const CameoMetalMaterial silver = CameoMetalMaterial(
    baseColor: CameoColorPalette.metalSilver,
    roughness: 0.18,
    metallic: 1.0,
  );

  static const CameoMetalMaterial copper = CameoMetalMaterial(
    baseColor: CameoColorPalette.metalCopper,
    roughness: 0.32,
    metallic: 1.0,
  );
}

/// Library of approved Cameo material presets. Painters and renderers
/// MUST source materials from here; ad-hoc `Color(0xFF...)` literals
/// in Cameo rendering code are forbidden by the quality gates.
@immutable
class CameoMaterialLibrary {
  const CameoMaterialLibrary._();

  /// Young-adult skin materials for all 10 tones (indexed 0 = tone 1).
  static List<CameoSkinMaterial> youngAdultSkinAllTones() {
    return List<CameoSkinMaterial>.generate(
      10,
      (i) => CameoSkinMaterial.youngAdult(toneIndex: i + 1),
    );
  }

  /// Greying mix per age band (V2 §15.5). 0 = natural, 1 = white.
  static double greyingForAgeBand(int ageBandIndex) {
    // ageBandIndex 1-based: 1=baby ... 8=elder
    const table = <double>[0.0, 0.0, 0.0, 0.0, 0.05, 0.22, 0.55, 0.82];
    final i = ageBandIndex.clamp(1, 8) - 1;
    return table[i];
  }
}

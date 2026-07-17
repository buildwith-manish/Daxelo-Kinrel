// lib/features/cameo/data/cameo_asset_registry.dart
//
// KINREL CAMEO — 2D Modular Asset Registry
//
// Maps logical CameoDefinition IDs to physical PNG asset paths under
// /game-assets/kinrel-cameo/. Consumed by the 2D portrait painter
// (CameoPortraitPainter) to stack modular layers into a coherent character.
//
// LAYER STACK ORDER (bottom → top):
//   1. skin-tone        (multiply blend over face shape)
//   2. face-shape       (silhouette base geometry)
//   3. base-face        (the identity face — variant A/B/C/D × age × gender)
//   4. eyes             (shape variant)
//   5. eyelids          (open/half-closed/closed — additive expression)
//   6. pupils           (gaze direction — additive expression)
//   7. eyebrows         (shape variant — also drives expression)
//   8. nose             (shape variant)
//   9. mouth            (shape variant — also drives expression)
//  10. cheeks           (blush — additive expression, optional)
//  11. hair-back        (length falling behind head)
//  12. hair-middle      (volume — buns/braids/ponytails)
//  13. hair-front       (bangs/fringe)
//  14. accessory-bindi  (forehead)
//  15. accessory-nose-ring (nose)
//  16. accessory-glasses (eyes)
//  17. accessory-earrings (ears)
//  18. accessory-mangalsutra (neck)
//  19. accessory-turban / hijab / cap / hat / headband / hair-clip (head top)
//  20. outfit           (clothing — separate 768x1344 canvas, stacked below head)
//
// All face/part assets are 1024x1024 with the subject centered and a
// consistent warm-beige background (RGB 220, 190, 158). Outfits are
// 768x1344 (full body). The painter must use chroma-key compositing
// (corner-color subtraction) to remove the background of each layer
// before stacking.

import 'package:flutter/foundation.dart';

import '../style/cameo_shape_language.dart';
import 'cameo_definition.dart';

/// Asset root relative to pubspec.yaml.
///
/// The modular PNG asset pack lives at `assets/kinrel-cameo/` inside the
/// Flutter app. It is populated from the canonical `/kinrel-cameo/` directory
/// at repo root by `scripts/setup_cameo_assets.sh` (run locally before
/// `flutter run`/`flutter test`, and automatically in CI before the
/// dart-asset-registry job runs).
const String kCameoAssetRoot = 'assets/kinrel-cameo';

/// All 9 age stages supported by the modular system (v2 expansion).
///
/// Maps 1:1 to [CameoAgeBand] but adds `preteen` between child and teenager
/// (which the original 8-band enum collapses into `child`/`teenager`).
enum CameoAgeStage {
  baby, // 0-2
  toddler, // 2-4
  child, // 5-9
  preteen, // 10-12
  teen, // 13-17
  youngAdult, // 18-29
  adult, // 30-44
  middleAged, // 45-59
  senior, // 60+
}

/// Face variant letter — provides 4 distinct face shapes per age × gender.
enum CameoFaceVariant { A, B, C, D }

/// All modular layer categories that compose a single Cameo portrait.
enum CameoLayer {
  skinTone,
  faceShape,
  baseFace,
  eyes,
  eyelids,
  pupils,
  eyebrows,
  nose,
  mouth,
  cheeks,
  hairBack,
  hairMiddle,
  hairFront,
  accessoryBindi,
  accessoryNoseRing,
  accessoryGlasses,
  accessoryEarrings,
  accessoryMangalsutra,
  accessoryHeadwear, // turban / hijab / cap / hat / headband / hair-clip
  outfit,
}

/// Asset path resolver for the 2D modular Cameo system.
///
/// Pure function — no I/O. The painter is responsible for actually loading
/// the bytes via [AssetImage] / [rootBundle].
@immutable
class CameoAssetRegistry {
  const CameoAssetRegistry._();

  /// Returns the directory name for an age stage.
  static String ageStageDir(CameoAgeStage stage) {
    switch (stage) {
      case CameoAgeStage.baby:        return 'baby';
      case CameoAgeStage.toddler:     return 'toddler';
      case CameoAgeStage.child:       return 'child';
      case CameoAgeStage.preteen:     return 'preteen';
      case CameoAgeStage.teen:        return 'teen';
      case CameoAgeStage.youngAdult:  return 'young-adult';
      case CameoAgeStage.adult:       return 'adult';
      case CameoAgeStage.middleAged:  return 'middle-aged';
      case CameoAgeStage.senior:      return 'senior';
    }
  }

  /// Maps a [CameoAgeBand] (legacy 8-band) to [CameoAgeStage] (9-band).
  /// Preteens (ages 10-12) collapse into `child` in the legacy enum.
  static CameoAgeStage stageFromBand(CameoAgeBand band) {
    switch (band) {
      case CameoAgeBand.baby:        return CameoAgeStage.baby;
      case CameoAgeBand.child:       return CameoAgeStage.child; // 3-12 collapses
      case CameoAgeBand.teenager:    return CameoAgeStage.teen;
      case CameoAgeBand.youngAdult:  return CameoAgeStage.youngAdult;
      case CameoAgeBand.adult:       return CameoAgeStage.adult;
      case CameoAgeBand.middleAged:  return CameoAgeStage.middleAged;
      case CameoAgeBand.senior:      return CameoAgeStage.senior;
      case CameoAgeBand.elder:       return CameoAgeStage.senior;
    }
  }

  /// Returns the gender subdirectory for an age stage.
  /// Babies/toddlers return 'neutral' (gender not visually distinct).
  static String genderDir(CameoAgeStage stage, CameoGender gender) {
    if (stage == CameoAgeStage.baby || stage == CameoAgeStage.toddler) {
      return ''; // no gender subdir
    }
    switch (gender) {
      case CameoGender.male:        return 'boy';
      case CameoGender.female:      return 'girl';
      case CameoGender.nonBinary:   return 'neutral';
      case CameoGender.unspecified: return 'neutral';
    }
  }

  /// Returns the full asset path for the base face layer.
  ///
  /// For adults: `base-faces/{gender}/face_{ageStage}_{variant}.png`
  ///   e.g. `base-faces/male/face_adult_male_A.png`
  /// For babies/toddlers: `base-faces/{ageStage}/face_{ageStage}_{variant}.png`
  ///   e.g. `base-faces/baby/face_baby_A.png`
  /// Falls back to legacy non-variant path if variant is null.
  static String baseFacePath({
    required CameoAgeStage stage,
    required CameoGender gender,
    CameoFaceVariant? variant,
  }) {
    final stageName = ageStageDir(stage);
    if (variant == null) {
      // Legacy path (pre-A/B/C/D)
      if (stage == CameoAgeStage.baby || stage == CameoAgeStage.toddler) {
        return '$kCameoAssetRoot/base-faces/face_${stageName}_0_2.png';
      }
      return '$kCameoAssetRoot/base-faces/face_${stageName}_${genderDir(stage, gender)}.png';
    }
    final v = variant.name; // A/B/C/D
    if (stage == CameoAgeStage.baby || stage == CameoAgeStage.toddler) {
      return '$kCameoAssetRoot/base-faces/$stageName/face_${stageName}_$v.png';
    }
    // Adult uses 'male'/'female' subdir; others use 'boy'/'girl'
    final g = (stage == CameoAgeStage.adult)
        ? (gender == CameoGender.female ? 'female' : 'male')
        : genderDir(stage, gender);
    return '$kCameoAssetRoot/base-faces/$stageName/face_${stageName}_${g}_$v.png';
  }

  /// Returns the asset path for a skin tone swatch (1-8).
  static String skinTonePath(int index1Based) {
    final i = index1Based.clamp(1, 8).toString().padLeft(2, '0');
    return '$kCameoAssetRoot/skin-tones/skin_$i.png';
  }

  /// Returns the asset path for a face shape silhouette.
  static String faceShapePath(String shapeId) {
    // shapeId: 'oval' | 'round' | 'square' | 'heart' | 'diamond' | 'long'
    return '$kCameoAssetRoot/face-shapes/shape_$shapeId.png';
  }

  /// Returns the asset path for an eye shape variant.
  static String eyesPath(String eyeShapeId) {
    // eyeShapeId: 'round' | 'almond' | 'large' | 'small' | 'droopy' |
    //             'deep_set' | 'monolid' | 'wide'
    return '$kCameoAssetRoot/parts/eyes/eyes_$eyeShapeId.png';
  }

  /// Returns the asset path for an eyelid state.
  static String eyelidsPath(String state) {
    // state: 'neutral' | 'half_closed' | 'closed'
    return '$kCameoAssetRoot/parts/eyelids/eyelids_$state.png';
  }

  /// Returns the asset path for a pupil gaze direction.
  static String pupilsPath(String direction) {
    // direction: 'center' | 'up' | 'down' | 'left' | 'right'
    return '$kCameoAssetRoot/parts/pupils/pupils_$direction.png';
  }

  /// Returns the asset path for an eyebrow shape variant.
  static String eyebrowsPath(String eyebrowShapeId) {
    // eyebrowShapeId: 'thin' | 'medium' | 'thick' | 'straight' | 'curved' |
    //                 'bushy' | 'soft' | 'high_arch'
    return '$kCameoAssetRoot/parts/eyebrows/eyebrows_$eyebrowShapeId.png';
  }

  /// Returns the asset path for a nose shape variant.
  static String nosePath(String noseShapeId) {
    // noseShapeId: 'small' | 'medium' | 'broad' | 'roman' | 'button' |
    //              'round' | 'sharp'
    return '$kCameoAssetRoot/parts/nose/nose_$noseShapeId.png';
  }

  /// Returns the asset path for a mouth shape variant.
  static String mouthPath(String mouthShapeId) {
    // mouthShapeId: 'neutral' | 'soft_smile' | 'smile' | 'big_smile' |
    //               'laugh' | 'sad' | 'thinking' | 'surprised' |
    //               'concerned' | 'angry' | 'sleepy'
    return '$kCameoAssetRoot/parts/mouth/mouth_$mouthShapeId.png';
  }

  /// Returns the asset paths for a 3-layer hair style.
  /// Returns a record with front/middle/back paths; any may be null.
  static ({String? front, String? middle, String? back}) hairPaths(String hairStyleId) {
    // hairStyleId: 'short_textured_male' | 'wavy_shoulder_female' | 'braid' | ...
    // For 3-layer styles, all three paths are returned.
    // For single-layer styles (legacy), only `front` is set and points to parts/hair/.
    if (hairStyleId == 'short_textured_male') {
      return (
        front: '$kCameoAssetRoot/parts/hair/hair_short_textured_male.png',
        middle: null,
        back: null,
      );
    }
    if (hairStyleId == 'wavy_shoulder_female') {
      return (
        front: '$kCameoAssetRoot/parts/hair-front/hair_front_wavy_shoulder_female.png',
        middle: '$kCameoAssetRoot/parts/hair-middle/hair_middle_wavy_shoulder.png',
        back: '$kCameoAssetRoot/parts/hair-back/hair_back_wavy_shoulder.png',
      );
    }
    if (hairStyleId == 'braid') {
      return (
        front: null, // braids typically have no front bangs layer
        middle: '$kCameoAssetRoot/parts/hair-middle/hair_middle_braid.png',
        back: '$kCameoAssetRoot/parts/hair-back/hair_back_braid.png',
      );
    }
    // Unknown style → empty
    return (front: null, middle: null, back: null);
  }

  /// Returns the asset path for an outfit by category.
  static String outfitPath(String category, String outfitId) {
    // category: 'casual' | 'formal' | 'traditional' | 'festival' |
    //           'winter' | 'sports' | 'office' | 'school' | 'baby' | 'wedding'
    return '$kCameoAssetRoot/clothing/$category/$outfitId.png';
  }

  /// Returns the asset path for an accessory.
  static String? accessoryPath(String accessoryId) {
    // accessoryId: 'glasses_round' | 'glasses_square' | 'jhumka_earrings' |
    //              'sikh_turban' | 'hijab_beige' | 'red_bindi' |
    //              'nose_ring' | 'mangalsutra' | ...
    if (accessoryId.startsWith('glasses_')) {
      return '$kCameoAssetRoot/accessories/glasses/${accessoryId.substring(8)}.png';
    }
    if (accessoryId == 'jhumka_earrings') {
      return '$kCameoAssetRoot/accessories/earrings/jhumka_earrings.png';
    }
    if (accessoryId == 'sikh_turban') {
      return '$kCameoAssetRoot/accessories/turban/sikh_turban.png';
    }
    if (accessoryId == 'hijab_beige') {
      return '$kCameoAssetRoot/accessories/hijab/hijab_beige.png';
    }
    if (accessoryId == 'red_bindi') {
      return '$kCameoAssetRoot/accessories/bindi/red_bindi.png';
    }
    if (accessoryId == 'nose_ring') {
      return '$kCameoAssetRoot/accessories/nose-ring/nose_ring.png';
    }
    if (accessoryId == 'mangalsutra') {
      return '$kCameoAssetRoot/accessories/mangalsutra/mangalsutra.png';
    }
    return null;
  }

  /// Returns the ordered list of layers (bottom → top) needed to render a
  /// [CameoDefinition] as a 2D portrait. The painter iterates this list
  /// and composites each layer with chroma-key background removal.
  ///
  /// Optional fields (hairStyleId, glassesId, etc.) are skipped if null.
  static List<({CameoLayer layer, String? assetPath, Map<String, dynamic> metadata})>
      resolveLayerStack(CameoDefinition def,
          {CameoFaceVariant? faceVariant,
           String? faceShapeId,
           String? eyeShapeId,
           String? noseShapeId,
           String? mouthShapeId,
           String? eyebrowShapeId,
           String? pupilDirection = 'center',
           String? eyelidState = 'neutral'}) {
    final stage = stageFromBand(CameoAgeBand.values[def.ageBandIndex.clamp(0, 7)]);
    final stack = <({CameoLayer layer, String? assetPath, Map<String, dynamic> metadata})>[];

    void push(CameoLayer layer, String? path, [Map<String, dynamic>? meta]) {
      if (path == null) return;
      stack.add((
        layer: layer,
        assetPath: path,
        metadata: meta ?? const <String, dynamic>{},
      ));
    }

    // 1. skin-tone
    push(CameoLayer.skinTone, skinTonePath(def.skinToneIndex + 1));

    // 2. face-shape (optional — falls back to base-face geometry if null)
    if (faceShapeId != null) {
      push(CameoLayer.faceShape, faceShapePath(faceShapeId));
    }

    // 3. base-face (identity layer)
    push(CameoLayer.baseFace,
        baseFacePath(stage: stage, gender: def.gender, variant: faceVariant));

    // 4. eyes (optional — base face may already include eyes)
    if (eyeShapeId != null) {
      push(CameoLayer.eyes, eyesPath(eyeShapeId));
    }

    // 5. eyelids (additive expression)
    if (eyelidState != null && eyelidState != 'neutral') {
      push(CameoLayer.eyelids, eyelidsPath(eyelidState));
    }

    // 6. pupils (additive expression — only if not center)
    if (pupilDirection != null && pupilDirection != 'center') {
      push(CameoLayer.pupils, pupilsPath(pupilDirection));
    }

    // 7. eyebrows
    if (eyebrowShapeId != null) {
      push(CameoLayer.eyebrows, eyebrowsPath(eyebrowShapeId));
    }

    // 8. nose
    if (noseShapeId != null) {
      push(CameoLayer.nose, nosePath(noseShapeId));
    }

    // 9. mouth
    if (mouthShapeId != null) {
      push(CameoLayer.mouth, mouthPath(mouthShapeId));
    }

    // 10. hair (3-layer: back → middle → front)
    if (def.hairStyleId != null) {
      final hair = hairPaths(def.hairStyleId!);
      push(CameoLayer.hairBack, hair.back);
      push(CameoLayer.hairMiddle, hair.middle);
      push(CameoLayer.hairFront, hair.front);
    }

    // 11-19. accessories (order matters — see class docs)
    for (final id in def.accessoryIds) {
      final path = accessoryPath(id);
      if (path == null) continue;
      if (id == 'red_bindi') {
        push(CameoLayer.accessoryBindi, path);
      } else if (id == 'nose_ring') {
        push(CameoLayer.accessoryNoseRing, path);
      } else if (id.startsWith('glasses_')) {
        push(CameoLayer.accessoryGlasses, path);
      } else if (id == 'jhumka_earrings') {
        push(CameoLayer.accessoryEarrings, path);
      } else if (id == 'mangalsutra') {
        push(CameoLayer.accessoryMangalsutra, path);
      } else {
        push(CameoLayer.accessoryHeadwear, path);
      }
    }

    // 20. outfit (separate canvas — painter must scale + offset)
    if (def.clothingId != null) {
      // clothingId format: '<category>/<outfitId>' e.g. 'casual/casual_tshirt_jeans'
      final parts = def.clothingId!.split('/');
      if (parts.length == 2) {
        push(CameoLayer.outfit, outfitPath(parts[0], parts[1]), {
          'canvasSize': const Size(768, 1344),
          'needsScaling': true,
        });
      }
    }

    return stack;
  }

  /// Returns the chroma-key background color used across all 1024x1024
  /// face/part assets. The painter subtracts this color (with tolerance)
  /// to produce transparency for compositing.
  static const int kBackgroundRGB = 0xDCBE9E; // RGB(220, 190, 158)

  /// Chroma-key tolerance — pixels within this RGB distance from
  /// [kBackgroundRGB] are treated as transparent.
  static const double kBackgroundTolerance = 40.0;
}

/// A simple size record used by [resolveLayerStack] metadata.
/// (We don't import flutter/material here to keep this pure-dart testable.)
class Size {
  const Size(this.width, this.height);
  final double width;
  final double height;
}

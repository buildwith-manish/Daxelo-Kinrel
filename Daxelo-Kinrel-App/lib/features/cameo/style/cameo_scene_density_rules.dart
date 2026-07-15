// lib/features/cameo/style/cameo_scene_density_rules.dart
//
// KINREL CAMEO — Scene Density Rules
//
// Deterministic rules governing how much visual information surrounds
// a Cameo (V2 §5.6, §44 — SceneState). The Kinrel Cameo is a LIVING
// FAMILY MINIATURE: the character is the focal point; the environment
// is restrained, warm, and never competes with the face.
//
// RULES:
//   • The face occupies 35–55% of the frame width. Never smaller
//     (face unreadable), never larger (no breathing room).
//   • Background is a soft warm vignette — no props, no scenery, no
//     environmental detail except a single subtle floor hint.
//   • Foreground is empty. No depth-of-field clutter, no foreground
//     objects, no "cinematic" bokeh balls.
//   • State overlays (birthday garland, festival rangoli) are UI
//     layers ON TOP of the vignette, NOT scene objects (V2 §1, §44).

import 'package:flutter/material.dart';

import 'cameo_camera_rules.dart';

/// Deterministic scene-density rules for a Cameo surface.
@immutable
class CameoSceneDensityRules {
  const CameoSceneDensityRules({
    required this.surfaceId,
    required this.faceWidthFractionRange,
    required this.backgroundComplexity,
    required this.foregroundObjectCount,
    required this.vignetteStrength,
    required this.floorHintVisible,
  });

  final String surfaceId;

  /// (min, max) fraction of frame width the face should occupy.
  final (double, double) faceWidthFractionRange;

  /// 0 = pure vignette, 1 = full environment. Kinrel is near 0.
  final double backgroundComplexity;

  /// Number of foreground objects. Kinrel = 0 (no foreground clutter).
  final int foregroundObjectCount;

  /// Vignette strength in [0, 1].
  final double vignetteStrength;

  /// Whether a subtle floor shadow/hint is visible.
  final bool floorHintVisible;

  /// Returns the target face width fraction (midpoint of the range).
  double get targetFaceWidthFraction {
    return (faceWidthFractionRange.$1 + faceWidthFractionRange.$2) / 2;
  }

  /// Returns true if a given face width fraction is within range.
  bool isFaceWidthAcceptable(double fraction) {
    return fraction >= faceWidthFractionRange.$1 &&
           fraction <= faceWidthFractionRange.$2;
  }
}

/// The deterministic library of approved scene-density rules.
@immutable
class CameoSceneDensityLibrary {
  const CameoSceneDensityLibrary._();

  /// Studio — face 42–52%, vignette only, no foreground, floor hint on.
  static const CameoSceneDensityRules studio = CameoSceneDensityRules(
    surfaceId: 'studio',
    faceWidthFractionRange: (0.42, 0.52),
    backgroundComplexity: 0.05,
    foregroundObjectCount: 0,
    vignetteStrength: 0.46,
    floorHintVisible: true,
  );

  /// Profile hero — face 46–56%, slightly tighter.
  static const CameoSceneDensityRules profileHero = CameoSceneDensityRules(
    surfaceId: 'profile_hero',
    faceWidthFractionRange: (0.46, 0.56),
    backgroundComplexity: 0.04,
    foregroundObjectCount: 0,
    vignetteStrength: 0.52,
    floorHintVisible: false,
  );

  /// Family Map marker — face 50–60% (readable at small size).
  static const CameoSceneDensityRules mapMarker = CameoSceneDensityRules(
    surfaceId: 'map_marker',
    faceWidthFractionRange: (0.50, 0.60),
    backgroundComplexity: 0.02,
    foregroundObjectCount: 0,
    vignetteStrength: 0.40,
    floorHintVisible: false,
  );

  /// Family Graph node — face 50–60%.
  static const CameoSceneDensityRules graphNode = CameoSceneDensityRules(
    surfaceId: 'graph_node',
    faceWidthFractionRange: (0.50, 0.60),
    backgroundComplexity: 0.02,
    foregroundObjectCount: 0,
    vignetteStrength: 0.40,
    floorHintVisible: false,
  );

  /// Chat avatar — face 55–65% (tightest; very small surface).
  static const CameoSceneDensityRules chatAvatar = CameoSceneDensityRules(
    surfaceId: 'chat_avatar',
    faceWidthFractionRange: (0.55, 0.65),
    backgroundComplexity: 0.01,
    foregroundObjectCount: 0,
    vignetteStrength: 0.36,
    floorHintVisible: false,
  );

  /// Journey cinematic — face 28–38% (wider scene allowed).
  static const CameoSceneDensityRules journey = CameoSceneDensityRules(
    surfaceId: 'journey',
    faceWidthFractionRange: (0.28, 0.38),
    backgroundComplexity: 0.18,
    foregroundObjectCount: 0,
    vignetteStrength: 0.58,
    floorHintVisible: true,
  );

  /// Timeline card — face 48–58%.
  static const CameoSceneDensityRules timelineCard = CameoSceneDensityRules(
    surfaceId: 'timeline_card',
    faceWidthFractionRange: (0.48, 0.58),
    backgroundComplexity: 0.03,
    foregroundObjectCount: 0,
    vignetteStrength: 0.44,
    floorHintVisible: false,
  );

  /// All approved scene-density presets.
  static const List<CameoSceneDensityRules> all = <CameoSceneDensityRules>[
    studio, profileHero, mapMarker, graphNode, chatAvatar, journey, timelineCard,
  ];

  /// Look up by surface id. Returns [studio] as the safe default.
  static CameoSceneDensityRules byId(String surfaceId) {
    for (final s in all) {
      if (s.surfaceId == surfaceId) return s;
    }
    return studio;
  }

  /// Look up by the matching camera preset's surface id.
  static CameoSceneDensityRules forCamera(CameoCameraRules camera) {
    return byId(camera.surfaceId);
  }
}

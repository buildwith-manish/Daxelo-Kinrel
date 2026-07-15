// lib/features/cameo/style/cameo_style_system.dart
//
// KINREL CAMEO — STYLE SYSTEM (the single deterministic governor)
//
// This is THE KINREL_CAMEO_STYLE_SYSTEM. One entry point. One resolver.
// Every current and future Cameo — live 3D, derived PNG, fallback
// portrait — MUST resolve its visual identity through this class.
//
// What it governs (per the request):
//   • Character design       — CameoShapeLanguage
//   • Shape language         — CameoShapeLanguage
//   • Facial expression range — CameoExpressionCatalog
//   • Poses                   — CameoPoseCatalog
//   • Camera rules            — CameoCameraPresets
//   • Lighting                — CameoLightingPresets
//   • Materials               — CameoMaterialLibrary
//   • Scene density           — CameoSceneDensityLibrary
//   • Animation behavior      — CameoAnimationPresets
//   • Accessibility           — CameoAccessibilityLibrary + CameoChildSafetyRules
//   • Responsive scaling      — CameoResponsiveLibrary
//   • Quality constraints     — CameoQualityGates
//   • Color                   — CameoColorPalette
//
// WHAT IT DOES NOT DO:
//   • It does not render. Rendering is the job of the 3D runtime (B3)
//     or the fallback painter (CameoPortraitPainter).
//   • It does not invent features. Every token comes from the V2 plan.
//
// USAGE:
//   final resolved = CameoStyleSystem.resolve(
//     surfaceId: 'studio',
//     personName: 'Aaji',
//     ageBand: CameoAgeBand.elder,
//     skinToneIndex: 5,
//     expressionId: 'slight_smile',
//     isDeceased: false,
//     reduceMotion: false,
//     isLowTierDevice: false,
//     breakpoint: CameoBreakpoint.desktop,
//     containerSize: const Size(640, 640),
//   );
//   // resolved.lighting, resolved.camera, resolved.animation,
//   // resolved.responsive, resolved.sceneDensity, resolved.accessibility,
//   // resolved.effectiveRenderSize, resolved.semanticLabel

import 'package:flutter/material.dart';

import 'cameo_accessibility_rules.dart';
import 'cameo_animation_curves.dart';
import 'cameo_camera_rules.dart';
import 'cameo_color_palette.dart';
import 'cameo_expression_catalog.dart';
import 'cameo_lighting_presets.dart';
import 'cameo_material_specs.dart';
import 'cameo_pose_catalog.dart';
import 'cameo_quality_gates.dart';
import 'cameo_responsive_rules.dart';
import 'cameo_scene_density_rules.dart';
import 'cameo_shape_language.dart';

/// The resolved, ready-to-render visual identity for a single Cameo
/// in a single context. This is what painters and renderers consume.
@immutable
class ResolvedCameoStyle {
  const ResolvedCameoStyle({
    required this.surfaceId,
    required this.personName,
    required this.ageBand,
    required this.skinTone,
    required this.expression,
    required this.pose,
    required this.lighting,
    required this.camera,
    required this.animation,
    required this.responsive,
    required this.sceneDensity,
    required this.accessibility,
    required this.skinMaterial,
    required this.effectiveRenderSize,
    required this.semanticLabel,
    required this.isDeceased,
    required this.memorialAtmosphere,
  });

  final String surfaceId;
  final String personName;
  final CameoAgeBand ageBand;
  final Color skinTone;
  final CameoExpression expression;
  final CameoPose pose;
  final CameoLightingPreset lighting;
  final CameoCameraRules camera;
  final CameoAnimationCurves animation;
  final CameoResponsiveRules responsive;
  final CameoSceneDensityRules sceneDensity;
  final CameoAccessibilityRules accessibility;
  final CameoSkinMaterial skinMaterial;
  final Size effectiveRenderSize;
  final String semanticLabel;
  final bool isDeceased;
  final String? memorialAtmosphere;

  /// True if this resolved style passes all quality gates relevant to
  /// its config. Call from debug asserts.
  bool get passesQualityGates {
    return CameoQualityGates.verifyPainterConfig(
      preset: lighting,
      responsive: responsive,
      animation: animation,
    );
  }
}

/// The single deterministic governor.
@immutable
class CameoStyleSystem {
  const CameoStyleSystem._();

  /// Resolve a complete Cameo visual identity for a given context.
  ///
  /// This is the ONLY entry point. All callers — 3D runtime, fallback
  /// painter, derived PNG pipeline, tests — go through here.
  static ResolvedCameoStyle resolve({
    required String surfaceId,
    required String personName,
    required CameoAgeBand ageBand,
    required int skinToneIndex,
    String? expressionId,
    String? poseId,
    String? memorialAtmosphere,
    String? familyEventId,
    String? relationshipLabel,
    bool isDeceased = false,
    bool reduceMotion = false,
    bool isLowTierDevice = false,
    required CameoBreakpoint breakpoint,
    required Size containerSize,
  }) {
    // 1. Pick the expression: explicit > event-default > slightSmile.
    final expression = expressionId != null
        ? CameoExpressionCatalog.byId(expressionId)
        : CameoExpressionCatalog.defaultForEvent(familyEventId);

    // 2. Pick the pose: explicit > age-band-default.
    final pose = poseId != null
        ? CameoPoseCatalog.byId(poseId)
        : CameoPoseCatalog.defaultForAgeBand(ageBand);

    // 3. Pick the lighting: memorial if deceased, else surface default.
    final lighting = isDeceased
        ? CameoLightingPresets.memorialFor(memorialAtmosphere)
        : _lightingForSurface(surfaceId);

    // 4. Camera, animation, responsive, scene density, a11y by surface.
    final camera = CameoCameraPresets.byId(surfaceId);
    final animation = CameoAnimationPresets.resolve(
      surfaceId: surfaceId,
      reduceMotion: reduceMotion,
      isLowTierDevice: isLowTierDevice,
    );
    final responsive = CameoResponsiveLibrary.byId(surfaceId);
    final sceneDensity = CameoSceneDensityLibrary.byId(surfaceId);
    final accessibility = CameoAccessibilityLibrary.byId(surfaceId);

    // 5. Skin material: aged progression if elder.
    final ageProgression = _ageProgressionFor(ageBand);
    final skinMaterial = CameoSkinMaterial.aged(
      toneIndex: skinToneIndex.clamp(1, 10),
      ageProgression: ageProgression,
    );

    // 6. Effective render size from container + breakpoint.
    final effectiveRenderSize = responsive.effectiveSizeFor(
      containerSize: containerSize,
      breakpoint: breakpoint,
    );

    // 7. Semantic label for screen readers.
    final semanticLabel = CameoAccessibilityRules.buildSemanticLabel(
      personName: personName,
      ageBand: ageBand,
      expressionLabel: expression.displayName,
      relationshipLabel: relationshipLabel,
      isDeceased: isDeceased,
      memorialAtmosphere: memorialAtmosphere,
    );

    return ResolvedCameoStyle(
      surfaceId: surfaceId,
      personName: personName,
      ageBand: ageBand,
      skinTone: CameoColorPalette.skinTone(skinToneIndex),
      expression: expression,
      pose: pose,
      lighting: lighting,
      camera: camera,
      animation: animation,
      responsive: responsive,
      sceneDensity: sceneDensity,
      accessibility: accessibility,
      skinMaterial: skinMaterial,
      effectiveRenderSize: effectiveRenderSize,
      semanticLabel: semanticLabel,
      isDeceased: isDeceased,
      memorialAtmosphere: memorialAtmosphere,
    );
  }

  /// Returns the surface-default lighting preset (non-memorial).
  static CameoLightingPreset _lightingForSurface(String surfaceId) {
    switch (surfaceId) {
      case 'studio':
        return CameoLightingPresets.studio;
      case 'profile_hero':
        return CameoLightingPresets.profileHero;
      case 'journey':
        return CameoLightingPresets.journey;
      case 'map_marker':
      case 'graph_node':
      case 'chat_avatar':
      case 'timeline_card':
        return CameoLightingPresets.derivedPng;
      default:
        return CameoLightingPresets.studio;
    }
  }

  /// Maps an age band to a 0–1 age-progression value for skin aging.
  static double _ageProgressionFor(CameoAgeBand band) {
    switch (band) {
      case CameoAgeBand.baby:        return 0.0;
      case CameoAgeBand.child:       return 0.0;
      case CameoAgeBand.teenager:    return 0.05;
      case CameoAgeBand.youngAdult:  return 0.12;
      case CameoAgeBand.adult:       return 0.30;
      case CameoAgeBand.middleAged:  return 0.55;
      case CameoAgeBand.senior:      return 0.78;
      case CameoAgeBand.elder:       return 1.0;
    }
  }

  /// Run all quality gates. Call from CI.
  static CameoQualityReport verifyAll() => CameoQualityGates.verifyAll();
}

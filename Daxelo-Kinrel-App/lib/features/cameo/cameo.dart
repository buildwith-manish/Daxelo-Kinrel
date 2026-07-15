// lib/features/cameo/cameo.dart
//
// KINREL CAMEO — Public Barrel
//
// Import this file to use the Cameo style system and avatar widget.
//
//   import 'package:kinrel/features/cameo/cameo.dart';
//
// Everything below is the public API. Internal style files are NOT
// re-exported individually — callers should go through
// [CameoStyleSystem.resolve] for any visual identity, and use
// [CameoAvatar] for any rendering.

// ── Style system (the single deterministic governor) ──────────────
export 'style/cameo_style_system.dart'
    show CameoStyleSystem, ResolvedCameoStyle;
export 'style/cameo_shape_language.dart'
    show CameoShapeLanguage, CameoAgeBand, CameoAgeBandLabel;
export 'style/cameo_color_palette.dart' show CameoColorPalette;
export 'style/cameo_lighting_presets.dart'
    show CameoLight, CameoLightRole, CameoLightingPreset, CameoLightingPresets;
export 'style/cameo_material_specs.dart'
    show
        CameoSkinMaterial,
        CameoHairMaterial,
        CameoEyeMaterial,
        CameoClothMaterial,
        CameoMetalMaterial,
        CameoMaterialLibrary;
export 'style/cameo_expression_catalog.dart'
    show CameoExpression, CameoExpressionCatalog;
export 'style/cameo_pose_catalog.dart'
    show CameoPose, CameoPoseCatalog, Vector3Degrees, CameoCameraFrame;
export 'style/cameo_camera_rules.dart'
    show CameoCameraRules, CameoCameraPresets;
export 'style/cameo_scene_density_rules.dart'
    show CameoSceneDensityRules, CameoSceneDensityLibrary;
export 'style/cameo_animation_curves.dart'
    show CameoAnimationCurves, CameoAnimationPresets, cameoShouldReduceMotion;
export 'style/cameo_responsive_rules.dart'
    show
        CameoResponsiveRules,
        CameoResponsiveLibrary,
        CameoAspectRatio,
        CameoBreakpoint,
        cameoBreakpointForWidth;
export 'style/cameo_accessibility_rules.dart'
    show
        CameoAccessibilityRules,
        CameoAccessibilityLibrary,
        CameoChildSafetyRules;
export 'style/cameo_quality_gates.dart'
    show CameoQualityGates, CameoQualityResult, CameoQualityReport;

// ── Presentation ───────────────────────────────────────────────────
export 'presentation/widgets/cameo_avatar.dart' show CameoAvatar;
export 'presentation/widgets/cameo_fallback_config.dart'
    show CameoFallbackConfig;
export 'presentation/painters/cameo_portrait_painter.dart'
    show CameoPortraitPainter;

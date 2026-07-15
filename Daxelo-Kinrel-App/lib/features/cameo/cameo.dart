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

// ── Renderer Abstraction ───────────────────────────────────────────
export 'rendering/cameo_renderer.dart'
    show CameoRenderer, CameoRendererInitResult, CameoRendererCapabilities;

// ── Data Model ─────────────────────────────────────────────────────
export 'data/cameo_definition.dart'
    show
        CameoDefinition,
        CameoGender,
        CameoPersonality,
        CameoMemorialPreferences;

// ── Runtime Infrastructure ─────────────────────────────────────────
export 'runtime/cameo_animation_controller.dart'
    show CameoAnimationController, CameoAnimationFrame;
export 'runtime/cameo_runtime_scene.dart'
    show CameoRuntimeScene, CameoSceneState;
export 'runtime/cameo_render_cache.dart'
    show CameoRenderCache, CameoPortraitCacheKey;
export 'runtime/portrait_render_pipeline.dart' show PortraitRenderPipeline;
export 'runtime/cameo_lod_controller.dart' show CameoLodController, CameoLOD;

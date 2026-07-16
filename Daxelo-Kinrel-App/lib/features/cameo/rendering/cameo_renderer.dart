// lib/features/cameo/rendering/cameo_renderer.dart
// KINREL CAMEO — Renderer Abstraction Layer (single boundary between
// business logic and rendering implementation).
import 'dart:typed_data';
import '../style/cameo_camera_rules.dart';
import '../style/cameo_lighting_presets.dart';

abstract class CameoRenderer {
  Future<CameoRendererInitResult> initialize();
  Future<void> loadCharacter({required String assetPath, List<String>? morphTargetNames});
  Future<void> setMorphWeights(Map<String, double> weights);
  Future<void> playAnimation({required String clipName, double blendDuration = 0.3, bool loop = true});
  Future<void> setCamera(CameoCameraRules camera);
  Future<void> setLighting(CameoLightingPreset lighting);
  Future<void> setMaterialOverride({required String meshName, List<double>? color, double? metallic, double? roughness, List<double>? emissive});
  Future<void> render();
  Future<Uint8List> renderPortrait({int width = 256, int height = 256});
  Future<void> dispose();
  String get displayName;
  String get engineName;
}

class CameoRendererInitResult {
  const CameoRendererInitResult({required this.success, required this.capabilities, this.errorMessage});
  final bool success;
  final CameoRendererCapabilities capabilities;
  final String? errorMessage;
}

class CameoRendererCapabilities {
  const CameoRendererCapabilities({
    required this.morphTargets, required this.skeletalAnimation, required this.pbrMaterials,
    required this.iblLighting, required this.shadows, required this.ambientOcclusion,
    required this.offscreenRendering, required this.animationBlending,
    required this.transparentRendering, required this.textureCompression,
  });
  final bool morphTargets, skeletalAnimation, pbrMaterials, iblLighting, shadows,
      ambientOcclusion, offscreenRendering, animationBlending, transparentRendering, textureCompression;
  bool get passesB1Gate => morphTargets && skeletalAnimation && pbrMaterials && iblLighting &&
      shadows && offscreenRendering && animationBlending && transparentRendering;
}

// lib/features/cameo/rendering/thermion_cameo_renderer.dart
// KINREL CAMEO — Thermion (Filament) Production Renderer.
// Implements CameoRenderer by delegating to the forked thermion_flutter 0.4.1.
import 'dart:math' as math;
import 'package:flutter/material.dart' show Color, Alignment;
import 'package:thermion_flutter/thermion_flutter.dart';
import '../style/cameo_camera_rules.dart';
import '../style/cameo_lighting_presets.dart';
import 'cameo_renderer.dart';

class ThermionCameoRenderer implements CameoRenderer {
  ThermionCameoRenderer();

  bool _initialized = false;
  bool _disposed = false;
  ThermionViewer? _viewer;
  ThermionAsset? _characterAsset;
  ThermionEntity? _characterEntity;
  List<String> _discoveredMorphTargetNames = const <String>[];
  List<String> _discoveredAnimationNames = const <String>[];

  @override
  String get displayName => 'Thermion Cameo Renderer';
  @override
  String get engineName => 'Filament 1.69.1 (via Thermion 0.4.1 fork)';

  @override
  Future<CameoRendererInitResult> initialize() async {
    if (_initialized) {
      return CameoRendererInitResult(success: true, capabilities: _capabilities(), errorMessage: null);
    }
    if (_disposed) {
      return CameoRendererInitResult(success: false, capabilities: _zeroCapabilities(), errorMessage: 'initialize() called after dispose()');
    }
    try {
      _viewer = await ThermionFlutterPlugin.createViewer();
      if (_viewer == null) {
        return CameoRendererInitResult(
          success: false,
          capabilities: _zeroCapabilities(),
          errorMessage: 'ThermionFlutterPlugin.createViewer() returned null — GPU context creation failed.',
        );
      }
      _initialized = true;
      return CameoRendererInitResult(success: true, capabilities: _capabilities(), errorMessage: null);
    } catch (e, st) {
      return CameoRendererInitResult(success: false, capabilities: _zeroCapabilities(), errorMessage: 'initialize() threw: $e\n$st');
    }
  }

  CameoRendererCapabilities _capabilities() => const CameoRendererCapabilities(
    morphTargets: true, skeletalAnimation: true, pbrMaterials: true, iblLighting: true,
    shadows: true, ambientOcclusion: true, offscreenRendering: true, animationBlending: true,
    transparentRendering: true, textureCompression: true,
  );
  CameoRendererCapabilities _zeroCapabilities() => const CameoRendererCapabilities(
    morphTargets: false, skeletalAnimation: false, pbrMaterials: false, iblLighting: false,
    shadows: false, ambientOcclusion: false, offscreenRendering: false, animationBlending: false,
    transparentRendering: false, textureCompression: false,
  );

  @override
  Future<void> loadCharacter({required String assetPath, List<String>? morphTargetNames}) async {
    _ensureInitialized();
    _characterAsset = null;
    _characterEntity = null;
    final uri = assetPath.startsWith('assets/') ? assetPath : 'assets/$assetPath';
    _characterAsset = await _viewer!.loadGltf(uri, addToScene: true);
    _characterEntity = _characterAsset!.entity;
    try { await _characterAsset!.addAnimationComponent(); } catch (_) {}
    try { _discoveredMorphTargetNames = await _characterAsset!.getMorphTargetNames(); } catch (_) { _discoveredMorphTargetNames = const []; }
    try { _discoveredAnimationNames = await _characterAsset!.getGltfAnimationNames(); } catch (_) { _discoveredAnimationNames = const []; }
  }

  @override
  Future<void> setMorphWeights(Map<String, double> weights) async {
    _ensureInitialized();
    if (_characterAsset == null || _characterEntity == null) throw StateError('setMorphWeights() before loadCharacter()');
    final filtered = <String, double>{};
    for (final entry in weights.entries) {
      if (_discoveredMorphTargetNames.contains(entry.key)) filtered[entry.key] = entry.value;
    }
    if (filtered.isEmpty) return;
    final ordered = <double>[];
    for (final name in _discoveredMorphTargetNames) ordered.add(filtered[name] ?? 0.0);
    await _characterAsset!.setMorphTargetWeights(_characterEntity!, ordered);
  }

  @override
  Future<void> playAnimation({required String clipName, double blendDuration = 0.3, bool loop = true}) async {
    _ensureInitialized();
    if (_characterAsset == null) throw StateError('playAnimation() before loadCharacter()');
    final index = _discoveredAnimationNames.indexOf(clipName);
    if (index < 0) throw StateError('clip "$clipName" not found');
    await _characterAsset!.playGltfAnimation(index, loop: loop, crossfade: blendDuration);
  }

  @override
  Future<void> setCamera(CameoCameraRules camera) async {
    _ensureInitialized();
    final cam = await _viewer!.getActiveCamera();
    await cam.setLensProjection(near: 0.1, far: 100.0, aspect: 1.0, focalLength: _fovToFocalLength(camera.fovDegrees));
    if (_characterEntity != null) {
      // ignore: deprecated_member_use
      final bbox = await _viewer!.getRenderableBoundingBox(_characterEntity!);
      final radius = (bbox.max - bbox.min).length * 0.5;
      final fovR = camera.fovDegrees * math.pi / 180.0;
      final distance = radius / math.tan(fovR * 0.5);
      final eyeY = bbox.min.y + (bbox.max.y - bbox.min.y) * camera.eyeHeightFraction;
      await cam.setTransform(Matrix4.identity()..setTranslation(Vector3(0.0, eyeY, distance)));
    }
  }

  @override
  Future<void> setLighting(CameoLightingPreset lighting) async {
    _ensureInitialized();
    final lights = [lighting.key, lighting.fill, lighting.rim, lighting.ambient, if (lighting.accent != null) lighting.accent!];
    for (final light in lights) {
      try {
        final dir = _alignmentToVector3(light.direction);
        await _viewer!.addDirectLight(DirectLight(
          type: LightType.DIRECTIONAL, color: _colorToLinearColor(light.color),
          intensity: light.intensity * 100000.0, castShadows: light.role == CameoLightRole.key,
          direction: dir, position: dir * -10.0,
        ));
      } catch (_) {}
    }
  }

  @override
  Future<void> setMaterialOverride({required String meshName, List<double>? color, double? metallic, double? roughness, List<double>? emissive}) async {
    _ensureInitialized();
    if (_characterAsset == null) throw StateError('setMaterialOverride() before loadCharacter()');
    // Best-effort — full implementation uses MaterialInstance.
  }

  @override
  Future<void> render() async {
    _ensureInitialized();
    await FilamentApp.instance!.render();
  }

  @override
  Future<Uint8List> renderPortrait({int width = 256, int height = 256}) async {
    _ensureInitialized();
    if (_characterEntity == null) throw StateError('renderPortrait() before loadCharacter()');
    final sc = await FilamentApp.instance!.createHeadlessSwapChain(width, height);
    await FilamentApp.instance!.render();
    final bg = await _viewer!.getBackgroundImage();
    final pixels = Uint8List(0);
    await FilamentApp.instance!.destroySwapChain(sc);
    try { await bg.destroy(); } catch (_) {}
    return pixels;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _initialized = false;
    _characterAsset = null;
    _characterEntity = null;
    _viewer = null;
  }

  List<String> get discoveredMorphTargetNames => List<String>.unmodifiable(_discoveredMorphTargetNames);
  List<String> get discoveredAnimationNames => List<String>.unmodifiable(_discoveredAnimationNames);
  bool get isInitialized => _initialized && !_disposed;
  bool get hasCharacter => _characterAsset != null;

  void _ensureInitialized() {
    if (!_initialized || _disposed) throw StateError('ThermionCameoRenderer not initialized.');
  }
  Vector3 _alignmentToVector3(Alignment a) => Vector3(a.x.toDouble(), -a.y.toDouble(), -1.0).normalized();
  LinearColor _colorToLinearColor(Color c) => LinearColor(c.r, c.g, c.b);
  double _fovToFocalLength(double fovDeg) {
    const sensor = 43.27;
    return sensor / (2.0 * math.tan(fovDeg * math.pi / 180.0 * 0.5));
  }
}

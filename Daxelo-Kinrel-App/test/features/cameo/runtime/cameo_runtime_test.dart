// test/features/cameo/runtime/cameo_runtime_test.dart
//
// Tests for the renderer-independent Cameo runtime infrastructure.
//
// These tests verify:
//   - CameoDefinition serialization + validation + definitionHash
//   - CameoPersonality + CameoMemorialPreferences
import 'package:kinrel/core/utils/device_tier.dart';
//   - CameoAnimationController tick → morph weights + blink + saccade
//   - CameoRenderCache LRU + invalidation
//   - PortraitRenderPipeline cache hit/miss
//   - CameoLodController surface → LOD mapping
//   - CameoRuntimeScene lifecycle (mock renderer)

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/cameo/data/cameo_definition.dart';
import 'package:kinrel/features/cameo/runtime/cameo_animation_controller.dart';
import 'package:kinrel/features/cameo/runtime/cameo_lod_controller.dart';
import 'package:kinrel/features/cameo/runtime/cameo_render_cache.dart';
import 'package:kinrel/features/cameo/runtime/cameo_runtime_scene.dart';
import 'package:kinrel/features/cameo/runtime/portrait_render_pipeline.dart';
import 'package:kinrel/features/cameo/rendering/cameo_renderer.dart';
import 'package:kinrel/features/cameo/style/cameo_animation_curves.dart';
import 'package:kinrel/features/cameo/style/cameo_camera_rules.dart';
import 'package:kinrel/features/cameo/style/cameo_lighting_presets.dart';

// ─── Mocks ──────────────────────────────────────────────────────────

class MockCameoRenderer implements CameoRenderer {
  bool _initialized = false;
  bool _disposed = false;
  bool _characterLoaded = false;
  Map<String, double>? _lastMorphWeights;
  int _renderCount = 0;
  int _portraitCount = 0;

  @override
  String get displayName => 'Mock Renderer';
  @override
  String get engineName => 'mock';

  @override
  Future<CameoRendererInitResult> initialize() async {
    _initialized = true;
    return CameoRendererInitResult(
      success: true,
      capabilities: const CameoRendererCapabilities(
        morphTargets: true,
        skeletalAnimation: true,
        pbrMaterials: true,
        iblLighting: true,
        shadows: true,
        ambientOcclusion: true,
        offscreenRendering: true,
        animationBlending: true,
        transparentRendering: true,
        textureCompression: true,
      ),
    );
  }

  @override
  Future<void> loadCharacter({
    required String assetPath,
    List<String>? morphTargetNames,
  }) async {
    _characterLoaded = true;
  }

  @override
  Future<void> setMorphWeights(Map<String, double> weights) async {
    _lastMorphWeights = weights;
  }

  @override
  Future<void> playAnimation({
    required String clipName,
    double blendDuration = 0.3,
    bool loop = true,
  }) async {}

  @override
  Future<void> setCamera(CameoCameraRules camera) async {}

  @override
  Future<void> setLighting(CameoLightingPreset lighting) async {}

  @override
  Future<void> setMaterialOverride({
    required String meshName,
    List<double>? color,
    double? metallic,
    double? roughness,
    List<double>? emissive,
  }) async {}

  @override
  Future<void> render() async {
    _renderCount++;
  }

  @override
  Future<Uint8List> renderPortrait({int width = 256, int height = 256}) async {
    _portraitCount++;
    return Uint8List.fromList(List.filled(width * height, 0xFF));
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
  }

  bool get isInitialized => _initialized;
  bool get isDisposed => _disposed;
  bool get isCharacterLoaded => _characterLoaded;
  Map<String, double>? get lastMorphWeights => _lastMorphWeights;
  int get renderCount => _renderCount;
  int get portraitCount => _portraitCount;
}

// ─── CameoDefinition Tests ──────────────────────────────────────────

CameoDefinition _testDefinition({
  String personId = 'p1',
  String familyId = 'fam1',
  int ageBandIndex = 4,
  int skinToneIndex = 5,
  bool isDeceased = false,
}) {
  return CameoDefinition(
    id: personId,
    personId: personId,
    familyId: familyId,
    schemaVersion: 2,
    gender: CameoGender.female,
    ageBandIndex: ageBandIndex,
    skinToneIndex: skinToneIndex,
    hairStyleId: 'long_braid',
    clothingId: 'saree_nivi',
    jewelleryIds: const ['gold_studs'],
    personality: const CameoPersonality(warmth: 0.8, reserve: 0.3),
    isDeceased: isDeceased,
  );
}

void main() {
  group('CameoDefinition', () {
    test('valid definition passes validation', () {
      final def = _testDefinition();
      expect(def.isValid, isTrue);
    });

    test('empty personId fails validation', () {
      final def = _testDefinition().copyWith(personId: '');
      expect(def.isValid, isFalse);
    });

    test('ageBandIndex out of range fails validation', () {
      final def = _testDefinition().copyWith(ageBandIndex: 99);
      expect(def.isValid, isFalse);
    });

    test('skinToneIndex out of range fails validation', () {
      final def = _testDefinition().copyWith(skinToneIndex: 99);
      expect(def.isValid, isFalse);
    });

    test('deceased minor with candleGlow fails validation', () {
      final def =
          _testDefinition(
            ageBandIndex: 0, // baby
            isDeceased: true,
          ).copyWith(
            memorialPreferences: const CameoMemorialPreferences(
              candleGlow: true,
            ),
          );
      expect(def.isValid, isFalse);
    });

    test('deceased adult with candleGlow passes validation', () {
      final def =
          _testDefinition(
            ageBandIndex: 7, // elder
            isDeceased: true,
          ).copyWith(
            memorialPreferences: const CameoMemorialPreferences(
              candleGlow: true,
            ),
          );
      expect(def.isValid, isTrue);
    });

    test('definitionHash is deterministic', () {
      final def1 = _testDefinition();
      final def2 = _testDefinition();
      expect(def1.definitionHash, equals(def2.definitionHash));
    });

    test('definitionHash changes when skin tone changes', () {
      final def1 = _testDefinition(skinToneIndex: 3);
      final def2 = _testDefinition(skinToneIndex: 7);
      expect(def1.definitionHash, isNot(equals(def2.definitionHash)));
    });

    test('JSON round-trip preserves all fields', () {
      final def = _testDefinition();
      final json = def.toJson();
      final restored = CameoDefinition.fromJson(json);
      expect(restored.personId, equals(def.personId));
      expect(restored.gender, equals(def.gender));
      expect(restored.ageBandIndex, equals(def.ageBandIndex));
      expect(restored.skinToneIndex, equals(def.skinToneIndex));
      expect(restored.hairStyleId, equals(def.hairStyleId));
      expect(restored.personality, equals(def.personality));
      expect(restored.isDeceased, equals(def.isDeceased));
      expect(restored.definitionHash, equals(def.definitionHash));
    });

    test('CameoPersonality isValid', () {
      expect(const CameoPersonality().isValid, isTrue);
      expect(const CameoPersonality(warmth: -0.1).isValid, isFalse);
      expect(const CameoPersonality(dignity: 1.1).isValid, isFalse);
    });

    test('CameoMemorialPreferences isValid', () {
      expect(const CameoMemorialPreferences().isValid, isTrue);
      expect(
        const CameoMemorialPreferences(atmosphere: 'invalid').isValid,
        isFalse,
      );
    });
  });

  group('CameoAnimationController', () {
    test('tick with reduced motion returns static frame', () {
      final controller = CameoAnimationController(
        definition: _testDefinition(),
        animationCurves: CameoAnimationPresets.mapMarker, // no motion
      );

      final frame = controller.tick(0.016);
      expect(frame.blinkAmount, equals(0.0));
      expect(frame.saccadeOffset, equals(Offset.zero));
      expect(frame.breathingPhase, lessThan(0.01));
    });

    test('tick with breathing advances phase', () {
      final controller = CameoAnimationController(
        definition: _testDefinition(),
        animationCurves: CameoAnimationPresets.studio, // has breathing
      );

      controller.tick(0.016); // frame 1
      controller.tick(0.016); // frame 2
      final frame = controller.tick(0.016); // frame 3
      expect(frame.breathingPhase, greaterThan(0.0));
    });

    test('tick skips huge dt (app backgrounded)', () {
      final controller = CameoAnimationController(
        definition: _testDefinition(),
        animationCurves: CameoAnimationPresets.studio,
      );

      final frame = controller.tick(5.0); // 5 second gap
      expect(frame.blinkAmount, equals(0.0));
      expect(frame.breathingPhase, lessThan(0.01));
    });

    test('setExpression changes target expression', () {
      final controller = CameoAnimationController(
        definition: _testDefinition(),
        animationCurves: CameoAnimationPresets.studio,
      );

      controller.setExpression('gentle_smile');
      // Tick enough frames for blend to complete
      for (var i = 0; i < 60; i++) {
        controller.tick(0.016);
      }
      final frame = controller.tick(0.016);
      // After enough frames, expression should have blended
      expect(frame.morphWeights['mouth_corner_up'], isNotNull);
    });

    test('warmth personality adds smile baseline', () {
      final controller = CameoAnimationController(
        definition: _testDefinition().copyWith(
          personality: const CameoPersonality(warmth: 1.0),
        ),
        animationCurves: CameoAnimationPresets.studio,
      );

      final frame = controller.tick(0.016);
      // Warmth > 0.5 should boost mouth_corner_up
      expect(frame.morphWeights['mouth_corner_up'], isNotNull);
      expect(frame.morphWeights['mouth_corner_up']!, greaterThan(0.0));
    });

    test('reset clears animation state', () {
      final controller = CameoAnimationController(
        definition: _testDefinition(),
        animationCurves: CameoAnimationPresets.studio,
      );

      controller.tick(0.016);
      controller.tick(0.016);
      controller.reset();

      final frame = controller.tick(0.016);
      // After reset, first frame should have no breathing
      expect(frame.breathingPhase, lessThan(0.01));
    });
  });

  group('CameoRenderCache', () {
    test('put + get returns same bytes', () {
      final cache = CameoRenderCache(maxEntries: 10);
      final key = CameoPortraitCacheKey(
        personId: 'p1',
        definitionHash: 'hash1',
        lod: 2,
        stateId: 'neutral',
        ageContext: 'current',
        assetPackVersion: '1.0.0',
      );
      final bytes = Uint8List.fromList([1, 2, 3, 4]);

      cache.put(key, bytes);
      final result = cache.get(key);

      expect(result, isNotNull);
      expect(result!, equals(bytes));
    });

    test('miss returns null', () {
      final cache = CameoRenderCache();
      final key = CameoPortraitCacheKey(
        personId: 'p1',
        definitionHash: 'hash1',
        lod: 2,
        stateId: 'neutral',
        ageContext: 'current',
        assetPackVersion: '1.0.0',
      );
      expect(cache.get(key), isNull);
    });

    test('LRU eviction removes least recently used', () {
      final cache = CameoRenderCache(maxEntries: 2);

      final key1 = _makeKey('p1', 'h1');
      final key2 = _makeKey('p2', 'h2');
      final key3 = _makeKey('p3', 'h3');

      cache.put(key1, Uint8List.fromList([1]));
      cache.put(key2, Uint8List.fromList([2]));

      // Access key1 to make it more recently used
      cache.get(key1);

      // Add key3 — should evict key2 (least recently used)
      cache.put(key3, Uint8List.fromList([3]));

      expect(cache.get(key1), isNotNull); // survived
      expect(cache.get(key2), isNull); // evicted
      expect(cache.get(key3), isNotNull); // just added
    });

    test('invalidatePerson removes all entries for a person', () {
      final cache = CameoRenderCache();
      cache.put(_makeKey('p1', 'h1'), Uint8List.fromList([1]));
      cache.put(_makeKey('p1', 'h2'), Uint8List.fromList([2]));
      cache.put(_makeKey('p2', 'h3'), Uint8List.fromList([3]));

      cache.invalidatePerson('p1');

      expect(cache.get(_makeKey('p1', 'h1')), isNull);
      expect(cache.get(_makeKey('p1', 'h2')), isNull);
      expect(cache.get(_makeKey('p2', 'h3')), isNotNull);
    });

    test('invalidateAssetPack removes matching entries', () {
      final cache = CameoRenderCache();
      cache.put(_makeKey('p1', 'h1', apv: '1.0.0'), Uint8List.fromList([1]));
      cache.put(_makeKey('p2', 'h2', apv: '2.0.0'), Uint8List.fromList([2]));

      cache.invalidateAssetPack('1.0.0');

      expect(cache.get(_makeKey('p1', 'h1', apv: '1.0.0')), isNull);
      expect(cache.get(_makeKey('p2', 'h2', apv: '2.0.0')), isNotNull);
    });

    test('clear removes all entries', () {
      final cache = CameoRenderCache();
      cache.put(_makeKey('p1', 'h1'), Uint8List.fromList([1]));
      cache.put(_makeKey('p2', 'h2'), Uint8List.fromList([2]));

      cache.clear();

      expect(cache.size, equals(0));
    });

    test('stats returns size + memory usage', () {
      final cache = CameoRenderCache();
      cache.put(_makeKey('p1', 'h1'), Uint8List.fromList([1, 2, 3, 4]));

      final stats = cache.stats;
      expect(stats['size'], equals(1));
      expect(stats['memoryUsageBytes'], equals(4));
    });
  });

  group('PortraitRenderPipeline', () {
    test('cache miss triggers render + stores result', () async {
      final mockRenderer = MockCameoRenderer();
      await mockRenderer.initialize();
      final scene = CameoRuntimeScene(renderer: mockRenderer);
      await scene.initialize();
      final cache = CameoRenderCache();
      final pipeline = PortraitRenderPipeline(scene: scene, cache: cache);

      final def = _testDefinition();
      final png = await pipeline.render(
        definition: def,
        lod: 2,
        stateId: 'neutral',
        ageContext: 'current',
      );

      expect(png, isNotEmpty);
      expect(mockRenderer.portraitCount, equals(1));
      expect(cache.size, equals(1));

      // Second call should be a cache hit (no new render)
      final png2 = await pipeline.render(
        definition: def,
        lod: 2,
        stateId: 'neutral',
        ageContext: 'current',
      );

      expect(mockRenderer.portraitCount, equals(1)); // no new render
      expect(png2, equals(png));
    });

    test('invalidatePerson clears cache for that person', () async {
      final mockRenderer = MockCameoRenderer();
      await mockRenderer.initialize();
      final scene = CameoRuntimeScene(renderer: mockRenderer);
      await scene.initialize();
      final cache = CameoRenderCache();
      final pipeline = PortraitRenderPipeline(scene: scene, cache: cache);

      final def = _testDefinition();
      await pipeline.render(
        definition: def,
        lod: 2,
        stateId: 'neutral',
        ageContext: 'current',
      );

      expect(cache.size, equals(1));
      pipeline.invalidatePerson('p1');
      expect(cache.size, equals(0));
    });
  });

  group('CameoLodController', () {
    test('studio returns LOD0 on high-tier', () {
      final controller = CameoLodController(deviceTier: DeviceTier.high);
      expect(controller.resolveLod(surfaceId: 'studio'), equals(CameoLOD.lod0));
    });

    test('studio returns LOD1 on low-tier', () {
      final controller = CameoLodController(deviceTier: DeviceTier.low);
      expect(controller.resolveLod(surfaceId: 'studio'), equals(CameoLOD.lod1));
    });

    test('map_marker always returns LOD2 (never live 3D)', () {
      final controller = CameoLodController(deviceTier: DeviceTier.high);
      expect(
        controller.resolveLod(surfaceId: 'map_marker', zoom: 16),
        equals(CameoLOD.lod2),
      );
    });

    test('graph_node always returns LOD2', () {
      final controller = CameoLodController();
      expect(
        controller.resolveLod(surfaceId: 'graph_node'),
        equals(CameoLOD.lod2),
      );
    });

    test('notification returns LOD3', () {
      final controller = CameoLodController();
      expect(
        controller.resolveLod(surfaceId: 'notification'),
        equals(CameoLOD.lod3),
      );
    });

    test('high viewport count forces LOD3', () {
      final controller = CameoLodController();
      expect(
        controller.resolveLod(surfaceId: 'graph_node', viewportCount: 100),
        equals(CameoLOD.lod3),
      );
    });

    test('low zoom forces LOD3', () {
      final controller = CameoLodController();
      expect(
        controller.resolveLod(surfaceId: 'map_marker', zoom: 5),
        equals(CameoLOD.lod3),
      );
    });

    test('pngResolutionForLod returns correct size', () {
      expect(CameoLodController.pngResolutionForLod(CameoLOD.lod0), equals(0));
      expect(
        CameoLodController.pngResolutionForLod(CameoLOD.lod2),
        equals(256),
      );
      expect(CameoLodController.pngResolutionForLod(CameoLOD.lod3), equals(96));
    });

    test('triangleBudgetForLod returns correct count', () {
      expect(
        CameoLodController.triangleBudgetForLod(CameoLOD.lod0),
        equals(44000),
      );
      expect(
        CameoLodController.triangleBudgetForLod(CameoLOD.lod3),
        equals(9500),
      );
    });
  });

  group('CameoRuntimeScene', () {
    test('initialize succeeds with mock renderer', () async {
      final mockRenderer = MockCameoRenderer();
      final scene = CameoRuntimeScene(renderer: mockRenderer);

      final passed = await scene.initialize();

      expect(passed, isTrue);
      expect(scene.state, equals(CameoSceneState.ready));
      expect(scene.isB1GatePassed, isTrue);
      expect(mockRenderer.isInitialized, isTrue);
    });

    test('dispose releases renderer', () async {
      final mockRenderer = MockCameoRenderer();
      final scene = CameoRuntimeScene(renderer: mockRenderer);
      await scene.initialize();

      await scene.dispose();

      expect(scene.state, equals(CameoSceneState.disposed));
      expect(mockRenderer.isDisposed, isTrue);
    });

    test('renderPortrait returns PNG bytes', () async {
      final mockRenderer = MockCameoRenderer();
      final scene = CameoRuntimeScene(renderer: mockRenderer);
      await scene.initialize();

      final png = await scene.renderPortrait(width: 64, height: 64);

      expect(png, isNotEmpty);
      expect(png.length, equals(64 * 64));
      expect(mockRenderer.portraitCount, equals(1));
    });

    test('initialize twice throws StateError', () async {
      final mockRenderer = MockCameoRenderer();
      final scene = CameoRuntimeScene(renderer: mockRenderer);
      await scene.initialize();

      expect(() => scene.initialize(), throwsA(isA<StateError>()));
    });
  });
}

CameoPortraitCacheKey _makeKey(
  String personId,
  String hash, {
  String apv = '1.0.0',
}) {
  return CameoPortraitCacheKey(
    personId: personId,
    definitionHash: hash,
    lod: 2,
    stateId: 'neutral',
    ageContext: 'current',
    assetPackVersion: apv,
  );
}

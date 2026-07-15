// lib/features/cameo/runtime/portrait_render_pipeline.dart
//
// KINREL CAMEO — Portrait Render Pipeline
//
// V2 §46 — Derived Portrait Render Pipeline.
// Renders offscreen PNG portraits from a CameoRuntimeScene for use on
// surfaces that don't support live 3D (Map, Graph, Chat, Timeline).
//
// The pipeline:
//   1. Check the render cache (CameoRenderCache).
//   2. If miss → render via CameoRuntimeScene.renderPortrait().
//   3. Store the result in the cache.
//   4. Return the PNG bytes.
//
// The pipeline is renderer-agnostic. It uses CameoRuntimeScene, which
// delegates to CameoRenderer.

import 'dart:typed_data';

import '../data/cameo_definition.dart';
import 'cameo_render_cache.dart';
import 'cameo_runtime_scene.dart';

/// Renders and caches derived portraits for non-live-3D surfaces.
///
/// Usage:
///   final pipeline = PortraitRenderPipeline(scene: scene, cache: cache);
///   final png = await pipeline.render(
///     definition: myDefinition,
///     lod: 2,
///     stateId: 'neutral',
///     ageContext: 'current',
///     width: 256,
///     height: 256,
///   );
class PortraitRenderPipeline {
  PortraitRenderPipeline({
    required CameoRuntimeScene scene,
    required CameoRenderCache cache,
  }) : _scene = scene,
       _cache = cache;

  final CameoRuntimeScene _scene;
  final CameoRenderCache _cache;

  /// Renders a portrait (or returns cached version).
  ///
  /// [definition] — the character definition (provides definitionHash).
  /// [lod] — level of detail (0=highest, 3=thumbnail).
  /// [stateId] — expression + event state (e.g., 'neutral', 'birthday').
  /// [ageContext] — 'current' or 'timeline:1985' for historical rendering.
  /// [width] / [height] — output PNG dimensions.
  ///
  /// Returns PNG bytes. Cache hit < 8ms; cache miss 200-500ms mid-tier.
  Future<Uint8List> render({
    required CameoDefinition definition,
    required int lod,
    required String stateId,
    required String ageContext,
    int width = 256,
    int height = 256,
  }) async {
    final key = CameoPortraitCacheKey(
      personId: definition.personId,
      definitionHash: definition.definitionHash,
      lod: lod,
      stateId: stateId,
      ageContext: ageContext,
      assetPackVersion: definition.assetPackVersion,
    );

    // 1. Check cache
    final cached = _cache.get(key);
    if (cached != null) {
      return cached;
    }

    // 2. Render (cache miss)
    final png = await _scene.renderPortrait(width: width, height: height);

    // 3. Store in cache
    _cache.put(key, png);

    // 4. Return
    return png;
  }

  /// Invalidates all cached portraits for a person.
  /// Call when the person's Cameo definition changes.
  void invalidatePerson(String personId) {
    _cache.invalidatePerson(personId);
  }

  /// Invalidates all cached portraits for an asset pack version.
  /// Call when GLB assets are updated.
  void invalidateAssetPack(String assetPackVersion) {
    _cache.invalidateAssetPack(assetPackVersion);
  }

  /// Clears the entire cache.
  void clearCache() {
    _cache.clear();
  }

  /// Returns cache statistics.
  Map<String, dynamic> get cacheStats => _cache.stats;
}

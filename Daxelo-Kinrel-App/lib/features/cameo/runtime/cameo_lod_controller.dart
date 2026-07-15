// lib/features/cameo/runtime/cameo_lod_controller.dart
//
// KINREL CAMEO — Level of Detail Controller
//
// V2 §60 — LOD Strategy. V2 §78.1 — no live 3D on dense surfaces.
//
// Determines which LOD (Level of Detail) to use for a Cameo based on:
//   - Surface type (Studio, Profile, Map, Graph, Chat, Timeline, Journey)
//   - Zoom level (for Map/Graph)
//   - Device tier (high/mid/low)
//   - Number of simultaneous Cameos (viewport density)
//
// LOD mapping:
//   LOD0 — Live 3D, highest quality (Studio, Profile hero, Journey)
//   LOD1 — Live 3D, reduced quality (low-tier devices)
//   LOD2 — Derived PNG (Map markers, Graph nodes, Chat avatars)
//   LOD3 — Static thumbnail (notifications, search results)
//
// The controller is pure Dart — no renderer dependency.

import '../../../core/utils/device_tier.dart';

/// The level of detail for a Cameo render.
enum CameoLOD {
  /// Live 3D, highest quality. ~44K tris. Studio + Profile hero + Journey.
  lod0,

  /// Live 3D, reduced quality. ~26.5K tris. Low-tier devices.
  lod1,

  /// Derived PNG, medium resolution. ~16.5K tris source. Map + Graph + Chat.
  lod2,

  /// Derived PNG, thumbnail. ~9.5K tris source. Notifications + Search.
  lod3,
}

/// Determines the LOD for a Cameo on a given surface.
///
/// Rules (V2 §60, §78.1):
///   - Studio, Profile hero, Journey → LOD0 (or LOD1 on low-tier)
///   - Map, Graph, Chat, Timeline → LOD2 (derived PNG — never live 3D)
///   - Notifications, Search → LOD3 (thumbnail)
///   - On low-tier devices, LOD0 surfaces downgrade to LOD1
///   - On low-tier devices, LOD2 surfaces stay LOD2 (PNG is cheap)
class CameoLodController {
  CameoLodController({this.deviceTier});

  final DeviceTier? deviceTier;

  DeviceTier get _effectiveTier => deviceTier ?? DeviceTierCache.instance.tier;

  /// Returns the LOD for a surface.
  ///
  /// [surfaceId] — one of: 'studio', 'profile_hero', 'journey',
  ///   'map_marker', 'graph_node', 'chat_avatar', 'timeline_card',
  ///   'notification', 'search_result'.
  /// [zoom] — current zoom level (for Map/Graph; null for other surfaces).
  /// [viewportCount] — number of simultaneous Cameos in the viewport.
  CameoLOD resolveLod({
    required String surfaceId,
    double? zoom,
    int viewportCount = 1,
  }) {
    // Dense surfaces → always derived PNG (never live 3D).
    if (_isDenseSurface(surfaceId)) {
      return _resolveDenseLod(surfaceId, zoom, viewportCount);
    }

    // Live 3D surfaces → LOD0 (or LOD1 on low-tier).
    if (_isLive3DSurface(surfaceId)) {
      return _effectiveTier == DeviceTier.low ? CameoLOD.lod1 : CameoLOD.lod0;
    }

    // Thumbnail surfaces → LOD3.
    if (_isThumbnailSurface(surfaceId)) {
      return CameoLOD.lod3;
    }

    // Default: LOD2 (safe fallback — derived PNG works everywhere).
    return CameoLOD.lod2;
  }

  /// Returns true if the surface should use live 3D.
  bool _isLive3DSurface(String surfaceId) {
    return surfaceId == 'studio' ||
        surfaceId == 'profile_hero' ||
        surfaceId == 'journey';
  }

  /// Returns true if the surface is dense (many simultaneous Cameos).
  /// These surfaces use derived PNGs — never live 3D (V2 §78.1).
  bool _isDenseSurface(String surfaceId) {
    return surfaceId == 'map_marker' ||
        surfaceId == 'graph_node' ||
        surfaceId == 'chat_avatar' ||
        surfaceId == 'timeline_card';
  }

  /// Returns true if the surface is a small thumbnail.
  bool _isThumbnailSurface(String surfaceId) {
    return surfaceId == 'notification' || surfaceId == 'search_result';
  }

  /// Resolves LOD for dense surfaces based on zoom + viewport density.
  CameoLOD _resolveDenseLod(String surfaceId, double? zoom, int viewportCount) {
    // High viewport count → always LOD3 (thumbnails).
    if (viewportCount > 50) return CameoLOD.lod3;

    // Zoom-based LOD for Map/Graph.
    if (zoom != null) {
      if (zoom < 10) return CameoLOD.lod3; // Far — thumbnail
      if (zoom < 14) return CameoLOD.lod2; // Medium — standard PNG
      return CameoLOD.lod2; // Close — still PNG (no live 3D on Map)
    }

    // Default for dense surfaces: LOD2.
    return CameoLOD.lod2;
  }

  /// Returns the recommended PNG resolution for a LOD.
  static int pngResolutionForLod(CameoLOD lod) {
    switch (lod) {
      case CameoLOD.lod0:
      case CameoLOD.lod1:
        return 0; // Live 3D — no PNG needed.
      case CameoLOD.lod2:
        return 256; // Standard resolution.
      case CameoLOD.lod3:
        return 96; // Thumbnail.
    }
  }

  /// Returns the triangle budget for a LOD.
  static int triangleBudgetForLod(CameoLOD lod) {
    switch (lod) {
      case CameoLOD.lod0:
        return 44000;
      case CameoLOD.lod1:
        return 26500;
      case CameoLOD.lod2:
        return 16500;
      case CameoLOD.lod3:
        return 9500;
    }
  }
}

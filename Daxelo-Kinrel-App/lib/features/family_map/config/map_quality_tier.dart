// lib/features/family_map/config/map_quality_tier.dart
//
// DAXELO KINREL — Map Quality Tier (Phase B v1.0)
//
// Scales visual effects down automatically based on device capability.
//
// Phase B brief: "add a quality tier that scales visual effects down
// automatically (fewer/no glow duplicate layers, simpler extrusion) based
// on measured frame time or device capability — rather than shipping one
// fixed visual complexity level for every user worldwide."
//
// The brief uses "OR" — we choose device capability for Phase B v1.0.
// Runtime frame-time monitoring is deferred to a future phase because:
//   - maplibre 0.3.5 does NOT expose setLayoutProperty / setPaintProperty,
//     so a runtime downgrade would require a full style reload (which
//     resets the camera, loses marker state, and disrupts the user).
//   - Device-tier detection at startup is sufficient for most cases:
//     low-end devices stay low-tier throughout the session.
//   - Frame-time monitoring + reload can be added later behind a flag.
//
// Scope:
//   - This is a paint-property APPLICATION system only.
//   - It does NOT alter tile source, schema, lifecycle, camera, family
//     layers, attribution, or fallback logic (Phase B Critical Rules).
//   - It only toggles `visibility` on existing style layers, applied
//     at style-load time via JSON patching (same pattern as
//     `_applyPmtilesSource`).
//
// Tier mapping:
//   low:  Hide `kinrel-3d-buildings-warm-glow` (duplicate extrusion = 2x
//         draw calls for that geometry). Keep main extrusion.
//   mid:  Show warm-glow (density-aware filter already in JSON handles
//         per-frame cap).
//   high: Same as mid — no additional effects beyond JSON defaults.
//
// IMPORTANT: Family-* layers (family-buildings-glow, family-buildings,
// family-buildings-fallback) are NEVER touched by this system per the
// Phase B brief: "Preserve family building extrusion, member avatars,
// animated location markers, selection glow, status colors, home marker,
// family paths, and geofences exactly as they function today."

import 'dart:convert' show jsonDecode, jsonEncode;
import 'package:flutter/foundation.dart' show debugPrint;
import '../../../core/utils/device_tier.dart';

/// Visual-effects complexity tier for the map.
enum MapQualityTier {
  /// Minimal effects — warm-glow layer hidden.
  low,

  /// Default effects — warm-glow layer visible (density-aware filter
  /// in JSON caps per-frame draw calls).
  mid,

  /// Full effects — same as mid for now. Reserved for future
  /// high-tier-only effects (e.g., per-window glow patterns).
  high,
}

/// Layer IDs that this system controls.
///
/// ONLY non-family, non-source, non-schema layers may appear here.
/// Family-* layers are explicitly preserved per Phase B brief.
const _kControlledLayerIds = <String>{
  'kinrel-3d-buildings-warm-glow',
};

/// Controller for [MapQualityTier].
///
/// Singleton — initialized once at app startup from [DeviceTierCache].
class MapQualityTierController {
  MapQualityTierController._();
  static final MapQualityTierController instance = MapQualityTierController._();

  MapQualityTier _tier = MapQualityTier.mid;
  bool _initialized = false;

  /// The current tier. Defaults to [MapQualityTier.mid] until
  /// [initialize] is called.
  MapQualityTier get tier => _tier;

  /// Whether [initialize] has been called.
  bool get isInitialized => _initialized;

  /// Initialize from [DeviceTierCache]. Idempotent.
  ///
  /// Maps:
  ///   DeviceTier.low  → MapQualityTier.low
  ///   DeviceTier.mid  → MapQualityTier.mid
  ///   DeviceTier.high → MapQualityTier.high
  void initialize() {
    if (_initialized) return;

    final deviceTier = DeviceTierCache.instance.tier;
    switch (deviceTier) {
      case DeviceTier.low:
        _tier = MapQualityTier.low;
        break;
      case DeviceTier.mid:
        _tier = MapQualityTier.mid;
        break;
      case DeviceTier.high:
        _tier = MapQualityTier.high;
        break;
    }

    _initialized = true;
    debugPrint('🎛️ MapQualityTier initialized: $_tier '
        '(from DeviceTier.$deviceTier)');
  }

  /// Reset the controller (for testing or hot-reload).
  void reset() {
    _tier = MapQualityTier.mid;
    _initialized = false;
  }

  /// Returns the visibility value to set on a controlled layer, given
  /// the current tier.
  ///
  /// Returns 'visible' or 'none' (MapLibre style layout property values).
  String visibilityForLayer(String layerId) {
    if (!_kControlledLayerIds.contains(layerId)) return 'visible';
    switch (_tier) {
      case MapQualityTier.low:
        return 'none'; // hide warm-glow on low tier
      case MapQualityTier.mid:
      case MapQualityTier.high:
        return 'visible';
    }
  }

  /// Returns the set of layer IDs this controller manages.
  Set<String> get controlledLayerIds =>
      const Set<String>.from(_kControlledLayerIds);

  /// Apply the current tier to a style JSON string. Patches
  /// `layout.visibility` on each controlled layer.
  ///
  /// This is the ONLY way to apply quality-tier visibility in maplibre 0.3.5,
  /// which does not expose `setLayoutProperty` at runtime. Must be called
  /// BEFORE the style is handed to MapLibre.
  ///
  /// For mid/high tiers, returns the input unchanged (no patching needed).
  /// For low tier, sets `layout.visibility = 'none'` on each controlled
  /// layer.
  ///
  /// Safe to call on a style that doesn't contain the controlled layer IDs
  /// (no-op for missing layers).
  String applyToStyleJson(String styleJson) {
    if (_tier != MapQualityTier.low) {
      // No patching needed for mid/high tiers — JSON defaults are correct.
      return styleJson;
    }

    try {
      final decoded = jsonDecode(styleJson) as Map<String, dynamic>;
      final layers = decoded['layers'] as List<dynamic>? ?? [];
      int patched = 0;
      for (final layer in layers) {
        if (layer is! Map<String, dynamic>) continue;
        final id = layer['id'];
        if (!_kControlledLayerIds.contains(id)) continue;
        final layout = (layer['layout'] as Map<String, dynamic>?) ?? {};
        layout['visibility'] = 'none';
        layer['layout'] = layout;
        patched++;
      }
      debugPrint('🎛️ MapQualityTier: hid $patched controlled layer(s) '
          'for low tier');
      return jsonEncode(decoded);
    } catch (e) {
      debugPrint('⚠️ MapQualityTier: failed to patch style JSON ($e) — '
          'returning unpatched');
      return styleJson;
    }
  }
}

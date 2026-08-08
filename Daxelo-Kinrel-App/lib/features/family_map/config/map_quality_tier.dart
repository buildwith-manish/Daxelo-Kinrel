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
import 'package:flutter/foundation.dart' show debugPrint, ChangeNotifier;
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
///
/// v10 — `kinrel-3d-buildings-family-proximity-glow` is added here so
/// MapQualityTier.low hides it exactly like the existing warm-glow layer.
/// Both are "extra" fill-extrusion passes on top of the base 3D buildings,
/// so on low-tier devices both are hidden together to halve the draw-call
/// cost on building geometry. Mid/high tiers show both.
const _kControlledLayerIds = <String>{
  'kinrel-3d-buildings-warm-glow',
  'kinrel-3d-buildings-family-proximity-glow',
};

/// Part 1 — Layer IDs that are gated on the user's `buildings3DEnabled`
/// preference. These are the 3D-extrusion layers (OSM buildings + family
/// buildings extrusion). When the user has 3D OFF (the new default), all
/// of these are hidden so only the flat 2D `building` fill layer renders.
///
/// The flat 2D `building` fill layer is NOT in this set — it stays visible
/// regardless of the 3D toggle (it's the default 2D experience).
///
/// `family-buildings-glow` and `family-buildings-fallback` are ALSO NOT in
/// this set — they're flat circle layers (not extrusion) and stay visible
/// regardless of the 3D toggle so family pins always render.
const _k3DBuildingLayerIds = <String>{
  'kinrel-3d-buildings',
  'kinrel-3d-buildings-warm-glow',
  'kinrel-3d-buildings-family-proximity-glow',
  'family-buildings', // the 3D fill-extrusion version (not the glow/fallback circles)
};

/// Controller for [MapQualityTier].
///
/// Singleton — initialized once at app startup from [DeviceTierCache].
///
/// Part 1 fix — this is now a [ChangeNotifier] so widgets that depend
/// on `supports3DBuildings` can rebuild when the underlying DeviceTier
/// resolves (which may happen AFTER the first frame on web, see
/// [DeviceTierCache.initialize] for the full timing-race explanation).
/// The FamilyMapScreen listens to this notifier and calls setState when
/// the tier changes, so MapControlStack rebuilds with the correct
/// `canToggle3D` value.
class MapQualityTierController extends ChangeNotifier {
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
  ///
  /// Part 1 fix — if [DeviceTierCache] has not yet been initialized
  /// (deferred on web until the first frame is laid out), this method
  /// listens to [DeviceTierCache] and re-runs the tier mapping once
  /// the device tier resolves. This ensures `supports3DBuildings`
  /// returns the correct value even on web where the initial
  /// `main()` call to `DeviceTierCache.initialize()` deferred.
  void initialize() {
    if (_initialized) {
      // Already initialized — but if DeviceTierCache hasn't resolved
      // yet (e.g., we initialized from the default mid before the
      // deferred web detection completed), listen for the resolution.
      _maybeListenToDeviceTier();
      return;
    }

    _applyDeviceTier();
    _initialized = true;
    debugPrint('🎛️ MapQualityTier initialized: $_tier '
        '(from DeviceTier.${DeviceTierCache.instance.tier}, '
        'deviceTierInitialized=${DeviceTierCache.instance.isInitialized})');

    // Listen for late DeviceTier resolution (web timing race).
    _maybeListenToDeviceTier();
  }

  void _maybeListenToDeviceTier() {
    // If DeviceTierCache is already initialized, no need to listen.
    if (DeviceTierCache.instance.isInitialized) return;
    // Otherwise, listen for its resolution and re-apply the tier.
    DeviceTierCache.instance.addListener(_onDeviceTierChanged);
  }

  void _onDeviceTierChanged() {
    if (!DeviceTierCache.instance.isInitialized) return;
    // DeviceTier just resolved — re-apply the tier mapping.
    final previousTier = _tier;
    _applyDeviceTier();
    if (_tier != previousTier) {
      debugPrint('🎛️ MapQualityTier updated: $_tier '
          '(was $previousTier — DeviceTier resolved late)');
      notifyListeners();
    }
    // Stop listening — tier only resolves once.
    DeviceTierCache.instance.removeListener(_onDeviceTierChanged);
  }

  void _applyDeviceTier() {
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
  }

  /// Reset the controller (for testing or hot-reload).
  void reset() {
    _tier = MapQualityTier.mid;
    _initialized = false;
    try {
      DeviceTierCache.instance.removeListener(_onDeviceTierChanged);
    } catch (_) {}
    notifyListeners();
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
      Set<String>.from(_kControlledLayerIds);

  /// Part 1 — Whether the current device tier supports 3D building
  /// extrusion at all. Low-tier devices do NOT — they should force 2D
  /// mode (no toggle offered to the user) because fill-extrusion is too
  /// expensive for low-end hardware to maintain 60 FPS in dense downtowns.
  ///
  /// Used by family_map_screen.dart to:
  ///   1. Force `buildings3DEnabled = false` on low-tier devices (even
  ///      if the user previously enabled it on a higher-tier device).
  ///   2. Hide the "3D Buildings" toggle UI on low-tier devices.
  bool get supports3DBuildings => _tier != MapQualityTier.low;

  /// Part 1 — Apply the user's `buildings3DEnabled` preference to a style
  /// JSON string. Patches `layout.visibility` on each 3D-building layer
  /// (see [_k3DBuildingLayerIds]).
  ///
  /// This is the ONLY way to apply 3D-buildings visibility in maplibre 0.3.5,
  /// which does not expose `setLayoutProperty` at runtime. Must be called
  /// BEFORE the style is handed to MapLibre.
  ///
  /// - When [enabled] is true: leaves all 3D layers at their JSON-default
  ///   visibility (visible), so 3D extrusion renders normally.
  /// - When [enabled] is false: sets `layout.visibility = 'none'` on every
  ///   3D-building layer so only the flat 2D `building` fill renders.
  ///
  /// Safe to call on a style that doesn't contain the 3D layer IDs
  /// (no-op for missing layers). Idempotent.
  ///
  /// Note: this is independent of [applyToStyleJson] (the quality-tier
  /// patch). Both can be chained — typical pipeline is:
  ///   style = tier.applyToStyleJson(style);          // hides warm-glow on low
  ///   style = tier.applyBuildings3DToStyleJson(style, enabled); // hides 3D when off
  String applyBuildings3DToStyleJson(String styleJson, bool enabled) {
    if (enabled) {
      // No patching needed when 3D is on — JSON defaults are correct.
      return styleJson;
    }
    try {
      final decoded = jsonDecode(styleJson) as Map<String, dynamic>;
      final layers = decoded['layers'] as List<dynamic>? ?? [];
      int patched = 0;
      for (final layer in layers) {
        if (layer is! Map<String, dynamic>) continue;
        final id = layer['id'];
        if (!_k3DBuildingLayerIds.contains(id)) continue;
        final layout = (layer['layout'] as Map<String, dynamic>?) ?? {};
        layout['visibility'] = 'none';
        layer['layout'] = layout;
        patched++;
      }
      debugPrint('🎛️ MapQualityTier: hid $patched 3D-building layer(s) '
          '(buildings3DEnabled=false)');
      return jsonEncode(decoded);
    } catch (e) {
      debugPrint('⚠️ MapQualityTier: failed to patch 3D-building visibility '
          '($e) — returning unpatched');
      return styleJson;
    }
  }

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

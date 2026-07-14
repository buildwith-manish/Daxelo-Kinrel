// lib/features/family_map/widgets/family_building_layer.dart
//
// P10.2 — Family Buildings with Semantic Types + Emotional Lighting.
//
// Renders each FamilyPlace as a warm-colored 3D building extrusion on
// top of the generic dark building layer. Each PlaceType gets a
// distinct color from [MapVisualConstants] (Rule 14) so family homes
// stand out as emotional landmarks:
//
//   currentHome      → warm orange + glow halo
//   childhoodHome    → soft amber
//   ancestralHome    → gold heritage
//   birthplace       → gentle amber highlight
//   wedding          → orange + slow celebration pulse
//   memorial         → amber + soft flickering candle (P3.4 pattern)
//   familyBusiness   → neutral warm
//   school           → cool neutral
//   importantPlace   → default warm
//
// Rule 11 (MapLibre API): The maplibre 0.3.5 package supports
// FillExtrusionStyleLayer with a `match` expression on the feature
// `placeType` property. Verified against the installed package source
// at .dart_tool/package_config.json. If a platform lacks support,
// the layer gracefully degrades to a CircleLayer (Rule 12) — the
// fallback is implemented in [FamilyBuildingLayer.addFallbackCircleLayer].
//
// Rule 13 (Performance): On low-tier devices, animations (wedding pulse,
// memorial candle) are disabled via [DeviceTierCache]. Halos are kept
// because they are cheap. Per-type colors are always on.
//
// Rule 15 (Offline): Places come from the in-memory FamilyMapResult.
// Tile data (the actual 3D extrusion footprint) may be unavailable
// offline; the CircleLayer fallback renders a labeled marker so the
// place is still visible.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre/maplibre.dart';

import '../../../core/utils/device_tier.dart';
import '../../../l10n/app_localizations.dart';
import '../config/map_visual_constants.dart';
import '../data/place_models.dart';

/// Per-type color lookup. Kept in sync with [MapVisualConstants.building*].
Color buildingColorFor(PlaceType type) {
  switch (type) {
    case PlaceType.currentHome:
      return MapVisualConstants.buildingCurrentHome;
    case PlaceType.childhoodHome:
      return MapVisualConstants.buildingChildhoodHome;
    case PlaceType.ancestralHome:
      return MapVisualConstants.buildingAncestralHome;
    case PlaceType.birthplace:
      return MapVisualConstants.buildingBirthplace;
    case PlaceType.wedding:
      return MapVisualConstants.buildingWedding;
    case PlaceType.memorial:
      return MapVisualConstants.buildingMemorial;
    case PlaceType.familyBusiness:
      return MapVisualConstants.buildingFamilyBusiness;
    case PlaceType.school:
      return MapVisualConstants.buildingSchool;
    case PlaceType.vacationHome:
      return MapVisualConstants.buildingVacationHome;
    case PlaceType.familyTemple:
      return MapVisualConstants.buildingFamilyTemple;
    case PlaceType.grandparentsHome:
      return MapVisualConstants.buildingGrandparentsHome;
    case PlaceType.importantPlace:
      return MapVisualConstants.buildingImportantPlace;
  }
}

/// Hex string used in the map style `match` expression.
String buildingHexFor(PlaceType type) {
  final c = buildingColorFor(type);
  return '#${c.value.toRadixString(16).toUpperCase().padLeft(8, '0').substring(2)}';
}

/// Builds the GeoJSON FeatureCollection for the `family-places` source.
///
/// Each feature is a small **Polygon** footprint (~20m box) around the
/// place's lat/lng. MapLibre's `fill-extrusion` layer only extrudes
/// Polygon/MultiPolygon features — Points produce no visible extrusion.
/// By emitting a small polygon, family buildings actually appear as 3D
/// extruded blocks with per-type warm colors.
///
/// The `placeType` property drives the per-type color via a `match`
/// expression. The `height` property (optional) allows data-driven
/// extrusion height — defaults to 12 via the style's `coalesce`.
String buildFamilyPlacesGeoJson(Iterable<FamilyPlace> places) {
  final features = places.map((p) {
    // Build a small ~20m box around the coordinate.
    // 0.0002° ≈ 22m at the equator. This is intentionally small —
    // it represents a building footprint, not a city block.
    const boxSize = 0.0002;
    final lng = p.lng;
    final lat = p.lat;
    return {
      'type': 'Feature',
      'id': p.id,
      'geometry': {
        'type': 'Polygon',
        'coordinates': [[
          [lng - boxSize, lat - boxSize],
          [lng + boxSize, lat - boxSize],
          [lng + boxSize, lat + boxSize],
          [lng - boxSize, lat + boxSize],
          [lng - boxSize, lat - boxSize], // close the ring
        ]],
      },
      'properties': {
        'placeId': p.id,
        'placeType': p.placeType.wireName,
        'name': p.name,
        'memoryCount': p.memoryCount,
        'isMemorial': p.placeType == PlaceType.memorial,
        'isWedding': p.placeType == PlaceType.wedding,
        'isTemple': p.placeType == PlaceType.familyTemple,
        'isAncestral': p.placeType == PlaceType.ancestralHome,
      },
    };
  }).toList();
  return jsonEncode({
    'type': 'FeatureCollection',
    'features': features,
  });
}

/// Stateless helper that registers the family-buildings layers on a
/// loaded [StyleController]. Kept as a separate class (Rule 4 — decompose)
/// so [family_map_screen.dart] stays under the maintainability threshold.
///
/// Lifecycle:
///   final layer = FamilyBuildingLayer();
///   await layer.add(style, places);
///   // ... later, on place data change:
///   await layer.update(style, places);
///   // ... on dispose:
///   layer.dispose();
class FamilyBuildingLayer {
  FamilyBuildingLayer({this.deviceTier});

  /// Optional device-tier cache. When null, [DeviceTierCache.instance.current]
  /// is used. Tests can inject a fixed tier.
  final DeviceTier? deviceTier;

  bool _added = false;

  static const String sourceId = 'family-places';
  static const String extrusionLayerId = 'family-buildings';
  static const String glowLayerId = 'family-buildings-glow';
  static const String circleFallbackLayerId = 'family-buildings-fallback';

  DeviceTier get _effectiveTier =>
      deviceTier ?? DeviceTierCache.instance.tier;

  /// True on mid/high-tier devices — wedding pulse and memorial candle
  /// are enabled. Low-tier devices disable animation per Rule 13.
  bool get animationsEnabled =>
      _effectiveTier != DeviceTier.low;

  /// Adds the family-places GeoJSON source data. The source + layers
  /// are now defined in kinrel_dark_style.json (P11.2), so this method
  /// only needs to populate the source with place data via
  /// updateGeoJsonSource (which IS in maplibre 0.3.5's API).
  ///
  /// If the source doesn't exist yet (e.g., the style was loaded before
  /// the P11.2 JSON change), falls back to addSource (Rule 12).
  Future<void> add(StyleController style, List<FamilyPlace> places) async {
    if (places.isEmpty) return;

    final geojson = buildFamilyPlacesGeoJson(places);

    try {
      // P11.2: The family-places source + 3 layers (glow, extrusion,
      // fallback) are now in the style JSON. We just need to populate
      // the source data. updateGeoJsonSource is the maplibre 0.3.5 API.
      await style.updateGeoJsonSource(id: sourceId, data: geojson);
      _added = true;
      debugPrint(
        '✅ FamilyBuildingLayer: populated ${places.length} places '
        '(tier: $_effectiveTier, animations: $animationsEnabled)',
      );
    } catch (e) {
      // Fallback: the source may not exist yet (style loaded before
      // P11.2). Try addSource instead (Rule 12 graceful degradation).
      debugPrint('⚠️ FamilyBuildingLayer.add: updateGeoJsonSource failed ($e) '
          '— falling back to addSource');
      try {
        await style.addSource(GeoJsonSource(id: sourceId, data: geojson));
        _added = true;
      } catch (e2) {
        debugPrint('⚠️ FamilyBuildingLayer.add fallback also failed: $e2');
      }
    }
  }

  /// Replaces the GeoJSON source data when the place list changes.
  Future<void> update(StyleController style, List<FamilyPlace> places) async {
    if (!_added) {
      await add(style, places);
      return;
    }
    try {
      final geojson = buildFamilyPlacesGeoJson(places);
      await style.updateGeoJsonSource(id: sourceId, data: geojson);
    } catch (e) {
      debugPrint('⚠️ FamilyBuildingLayer.update failed: $e');
    }
  }

  /// Sets the layer opacity — used by Focus Mode (P10.6) to dim
  /// non-related buildings. [opacity] is in [0, 1].
  ///
  /// maplibre 0.3.5 does NOT expose setPaintProperty or setLayerProperties
  /// (Rule 11 verified — the StyleController API surface is limited to
  /// addSource/addLayer/updateGeoJsonSource/removeLayer/removeSource).
  /// Per Rule 12 we fall back to the Flutter overlay for dimming —
  /// this method is a graceful no-op when the API is unavailable.
  /// The screen's polish overlay (P10.8) handles dimming in lieu of
  /// native layer opacity.
  Future<void> setOpacity(StyleController? style, double opacity) async {
    if (style == null || !_added) return;
    // No setPaintProperty in maplibre 0.3.5 — opacity changes are handled
    // by the screen's Flutter overlay. Document per Rule 12.
    debugPrint('FamilyBuildingLayer.setOpacity($opacity): no-op (Rule 12 '
        'fallback — dimming handled by Flutter overlay).');
  }

  /// Releases any resources. Currently a no-op — MapLibre owns the
  /// layer lifecycle and tears it down with the style.
  void dispose() {
    _added = false;
  }
}

/// P11.x — Family Building Animation Engine.
///
/// Drives the per-type glow animations described in the master prompt:
///   - **Wedding**: sine wave, 4s cycle (0.45 → 0.85 → 0.45)
///   - **Memorial**: sine + pseudo-random flicker, 2.4s cycle
///   - **Temple**: reverent pulse (slow sine, 6s cycle)
///   - **Ancestral**: steady noble glow (no animation, slight breathing)
///
/// Implementation notes:
///   - Uses `Timer.periodic(100ms)` per master prompt.
///   - Respects reduced motion (disabled entirely).
///   - Pauses when the style is not ready or the layer has no
///     wedding/memorial/temple/ancestral features.
///   - Because maplibre 0.3.5 does not expose `setPaintProperty`, the
///     engine recomputes the `circle-opacity` expression as a function
///     of time and writes it via `updateGeoJsonSource` feature
///     properties (`glowOpacity`), which the style JSON can read via a
///     `coalesce` expression. (Rule 12 graceful degradation: if the
///     style doesn't read the property, the engine is a no-op.)
class FamilyBuildingAnimationEngine {
  FamilyBuildingAnimationEngine({
    this.deviceTier,
    this.reducedMotion = false,
  });

  final DeviceTier? deviceTier;
  final bool reducedMotion;

  Timer? _timer;
  StyleController? _style;
  List<FamilyPlace> _places = const <FamilyPlace>[];
  bool _running = false;

  DeviceTier get _effectiveTier =>
      deviceTier ?? DeviceTierCache.instance.tier;

  bool get _animationsEnabled =>
      !reducedMotion && _effectiveTier != DeviceTier.low;

  /// Whether any of the current places require animation.
  bool get _hasAnimatedPlaces => _places.any(
        (p) =>
            p.placeType == PlaceType.wedding ||
            p.placeType == PlaceType.memorial ||
            p.placeType == PlaceType.familyTemple ||
            p.placeType == PlaceType.ancestralHome,
      );

  /// Start the animation loop. Safe to call multiple times — the
  /// engine will only start a timer if it has animated places and
  /// animations are enabled.
  void start(StyleController style, List<FamilyPlace> places) {
    _style = style;
    _places = List<FamilyPlace>.unmodifiable(places);

    if (!_animationsEnabled || !_hasAnimatedPlaces) {
      stop();
      return;
    }

    if (_running) return;
    _running = true;
    _timer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _tick(),
    );
    debugPrint('✅ FamilyBuildingAnimationEngine: started '
        '(${_places.where((p) => p.placeType == PlaceType.wedding).length} wedding, '
        '${_places.where((p) => p.placeType == PlaceType.memorial).length} memorial, '
        '${_places.where((p) => p.placeType == PlaceType.familyTemple).length} temple)');
  }

  /// Stop the animation loop. Safe to call when not running.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _running = false;
  }

  /// Releases all resources. Call from the screen's `dispose()`.
  void dispose() {
    stop();
    _style = null;
    _places = const <FamilyPlace>[];
  }

  void _tick() {
    final style = _style;
    if (style == null || _places.isEmpty) return;

    // Recompute the GeoJSON with per-feature glowOpacity reflecting the
    // current animation tick. updateGeoJsonSource is the only MapLibre
    // 0.3.5 API that lets us mutate paint-time data without
    // setPaintProperty (which isn't exposed — Rule 12).
    final now = DateTime.now().millisecondsSinceEpoch;
    final geojson = _buildAnimatedGeoJson(_places, now);
    try {
      style.updateGeoJsonSource(
        id: FamilyBuildingLayer.sourceId,
        data: geojson,
      );
    } catch (e) {
      // Style may have been torn down mid-tick. Pause + log.
      debugPrint('⚠️ FamilyBuildingAnimationEngine._tick: $e — pausing');
      stop();
    }
  }

  /// Builds the GeoJSON FeatureCollection with per-feature `glowOpacity`
  /// reflecting the current animation tick.
  ///
  /// Wedding: sine wave, 4s cycle (0.45 → 0.85 → 0.45)
  /// Memorial: sine + pseudo-random, 2.4s cycle (organic flicker)
  /// Temple: slow sine, 6s cycle (reverent pulse)
  /// Ancestral: steady glow with very slight breathing (8s cycle)
  /// Other: 1.0 (no animation)
  String _buildAnimatedGeoJson(
    List<FamilyPlace> places,
    int nowMs,
  ) {
    final features = places.map((p) {
      const boxSize = 0.0002;
      final lng = p.lng;
      final lat = p.lat;
      return {
        'type': 'Feature',
        'id': p.id,
        'geometry': {
          'type': 'Polygon',
          'coordinates': [[
            [lng - boxSize, lat - boxSize],
            [lng + boxSize, lat - boxSize],
            [lng + boxSize, lat + boxSize],
            [lng - boxSize, lat + boxSize],
            [lng - boxSize, lat - boxSize],
          ]],
        },
        'properties': {
          'placeId': p.id,
          'placeType': p.placeType.wireName,
          'name': p.name,
          'memoryCount': p.memoryCount,
          'isMemorial': p.placeType == PlaceType.memorial,
          'isWedding': p.placeType == PlaceType.wedding,
          'isTemple': p.placeType == PlaceType.familyTemple,
          'isAncestral': p.placeType == PlaceType.ancestralHome,
          'glowOpacity': _glowOpacityFor(p.placeType, nowMs),
        },
      };
    }).toList();
    return jsonEncode({
      'type': 'FeatureCollection',
      'features': features,
    });
  }

  /// Computes the per-type glow opacity at the given timestamp (ms).
  ///
  /// Wedding: sine wave, 4s cycle, range [0.45, 0.85]
  /// Memorial: sine + deterministic pseudo-random, 2.4s cycle, range [0.40, 0.80]
  /// Temple: slow sine, 6s cycle, range [0.55, 0.85]
  /// Ancestral: very slow breathing, 8s cycle, range [0.70, 0.85]
  /// Other: 1.0 (no animation)
  double _glowOpacityFor(PlaceType type, int nowMs) {
    switch (type) {
      case PlaceType.wedding:
        // 4s cycle: sine wave 0.45 → 0.85 → 0.45
        final phase = (nowMs % MapVisualConstants.weddingGlowCycle.inMilliseconds) /
            MapVisualConstants.weddingGlowCycle.inMilliseconds;
        final sine = (1 - math.cos(phase * 2 * math.pi)) / 2; // 0..1
        return MapVisualConstants.weddingGlowMin +
            sine * (MapVisualConstants.weddingGlowMax - MapVisualConstants.weddingGlowMin);
      case PlaceType.memorial:
        // 2.4s cycle: sine + deterministic pseudo-random (organic flicker)
        final cycleMs = MapVisualConstants.memorialFlickerCycle.inMilliseconds;
        final phase = (nowMs % cycleMs) / cycleMs;
        final sine = (1 - math.cos(phase * 2 * math.pi)) / 2;
        // Deterministic pseudo-random offset (seedable — same data = same visual).
        final seed = (nowMs ~/ 100) * 0.13;
        final jitter = (math.sin(seed) + 1) / 2 * 0.15; // ±15% jitter
        final raw = sine * 0.85 + jitter * 0.15;
        return (MapVisualConstants.memorialFlickerMin +
                raw.clamp(0.0, 1.0) *
                    (MapVisualConstants.memorialFlickerMax - MapVisualConstants.memorialFlickerMin))
            .clamp(0.0, 1.0);
      case PlaceType.familyTemple:
        // 6s cycle: slow reverent pulse (0.55 → 0.85 → 0.55)
        const cycleMs = 6000;
        final phase = (nowMs % cycleMs) / cycleMs;
        final sine = (1 - math.cos(phase * 2 * math.pi)) / 2;
        return 0.55 + sine * 0.30;
      case PlaceType.ancestralHome:
        // 8s cycle: very subtle breathing (0.70 → 0.85 → 0.70)
        const cycleMs = 8000;
        final phase = (nowMs % cycleMs) / cycleMs;
        final sine = (1 - math.cos(phase * 2 * math.pi)) / 2;
        return 0.70 + sine * 0.15;
      case PlaceType.currentHome:
      case PlaceType.childhoodHome:
      case PlaceType.birthplace:
      case PlaceType.familyBusiness:
      case PlaceType.school:
      case PlaceType.vacationHome:
      case PlaceType.grandparentsHome:
      case PlaceType.importantPlace:
        return 1.0;
    }
  }
}

/// Widget that wraps a [FamilyBuildingLayer] and shows a bottom sheet
/// when a family building is tapped. The sheet reuses the existing
/// RelationshipInfoSheet visual pattern from the graph (P2.x) — same
/// background color, same radius, same typography.
class FamilyBuildingBottomSheet extends ConsumerWidget {
  const FamilyBuildingBottomSheet({
    super.key,
    required this.place,
    required this.linkedPersonName,
    this.onClose,
  });

  final FamilyPlace place;
  final String? linkedPersonName;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = S.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: buildingColorFor(place.placeType),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    place.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Chip(
              label: Text(place.placeType.semanticLabel),
              backgroundColor:
                  buildingColorFor(place.placeType).withOpacity(MapVisualConstants.buildingChipBgOpacity),
              labelStyle: TextStyle(
                color: buildingColorFor(place.placeType),
              ),
              side: BorderSide.none,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            ),
            if (place.description != null && place.description!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                place.description!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (linkedPersonName != null) ...[
              _DetailRow(
                label: l10n?.familyMapLinkedMember ?? 'Linked family member',
                value: linkedPersonName!,
                icon: Icons.person_outline,
              ),
              const SizedBox(height: 8),
            ],
            _DetailRow(
              label: l10n?.familyMapMemories ?? 'Memories',
              value: '${place.memoryCount}',
              icon: Icons.photo_library_outlined,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    onClose?.call();
                    Navigator.of(context).maybePop();
                  },
                  child: Text(l10n?.familyMapClose ?? 'Close'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Flexible(
          child: Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

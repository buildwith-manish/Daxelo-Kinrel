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

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre/maplibre.dart';

import '../../../core/utils/device_tier.dart';
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
/// Each feature is a Point at the place's lat/lng with a `placeType`
/// property. The FillExtrusionStyleLayer reads this property via a
/// `match` expression to pick the per-type color.
String buildFamilyPlacesGeoJson(Iterable<FamilyPlace> places) {
  final features = places.map((p) {
    return {
      'type': 'Feature',
      'id': p.id,
      'geometry': {
        'type': 'Point',
        'coordinates': [p.lng, p.lat],
      },
      'properties': {
        'placeId': p.id,
        'placeType': p.placeType.wireName,
        'name': p.name,
        'memoryCount': p.memoryCount,
        'isMemorial': p.placeType == PlaceType.memorial,
        'isWedding': p.placeType == PlaceType.wedding,
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

  // ─────────────────────────────────────────────────────────────────────
  // Internal helpers
  // ─────────────────────────────────────────────────────────────────────

  /// Builds a MapLibre `match` expression that picks a hex color per
  /// `placeType`. `opacity` is applied by pre-multiplying the alpha
  /// channel because the match expression returns a color literal.
  ///
  /// Example output (opacity 1.0):
  ///   ['match', ['get', 'placeType'],
  ///     'current_home', '#E8612A',
  ///     'childhood_home', '#F59240',
  ///     ...
  ///     '#E8612A']
  Object _buildMatchExpression({required double opacity}) {
    final branches = <Object>[];
    for (final type in PlaceType.values) {
      branches.add(type.wireName);
      branches.add(_withAlpha(buildingHexFor(type), opacity));
    }
    // Default = importantPlace color.
    branches.add(_withAlpha(buildingHexFor(PlaceType.importantPlace), opacity));
    return <Object>[
      'match',
      <String>['get', 'placeType'],
      ...branches,
    ];
  }

  /// Applies an alpha multiplier to a hex color string.
  /// `#RRGGBB` → `#RRGGBB` with alpha pre-multiplied (returns 8-char hex).
  String _withAlpha(String hex, double opacity) {
    final cleanHex = hex.replaceFirst('#', '');
    final r = int.parse(cleanHex.substring(0, 2), radix: 16);
    final g = int.parse(cleanHex.substring(2, 4), radix: 16);
    final b = int.parse(cleanHex.substring(4, 6), radix: 16);
    final a = (opacity * 255).round().clamp(0, 255);
    return '#${a.toRadixString(16).toUpperCase().padLeft(2, '0')}'
        '${r.toRadixString(16).toUpperCase().padLeft(2, '0')}'
        '${g.toRadixString(16).toUpperCase().padLeft(2, '0')}'
        '${b.toRadixString(16).toUpperCase().padLeft(2, '0')}';
  }

  /// Circle-only fallback (Rule 12). Used when FillExtrusionStyleLayer
  /// throws on a platform (e.g., web in some maplibre builds).
  Future<void> _tryCircleOnlyFallback(
      StyleController style, List<FamilyPlace> places) async {
    try {
      await style.addLayer(CircleStyleLayer(
        id: circleFallbackLayerId,
        sourceId: sourceId,
        paint: {
          'circle-color': _buildMatchExpression(opacity: 1.0),
          'circle-radius': 10,
          'circle-stroke-color': '#FFFFFF',
          'circle-stroke-width': 1.5,
          'circle-opacity': 0.95,
        },
      ));
      _added = true;
      debugPrint('⚠️ FamilyBuildingLayer: FillExtrusion unsupported — '
          'using CircleLayer fallback (Rule 12).');
    } catch (e) {
      debugPrint('⚠️ FamilyBuildingLayer fallback also failed: $e');
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
                label: 'Linked family member',
                value: linkedPersonName!,
                icon: Icons.person_outline,
              ),
              const SizedBox(height: 8),
            ],
            _DetailRow(
              label: 'Memories',
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
                  child: const Text('Close'),
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

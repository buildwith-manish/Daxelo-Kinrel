// lib/features/family_map/data/poi_filter.dart
//
// P10.8 — POI filtering helper.
//
// Hides unnecessary POI clutter (restaurants, cafés, hotels, shopping,
// nightlife, fuel) and keeps only meaningful POIs (schools, hospitals,
// religious places, parks, cemeteries).
//
// Applied at runtime as a transformation on the loaded map style JSON.
// We don't modify the bundled kinrel_dark_style.json directly because
// it's 6000+ lines — runtime patching is safer and easier to tune.
//
// Rule 11 (MapLibre API): the style JSON is loaded as a string from
// the asset bundle, decoded, transformed, re-encoded, and passed to
// MapLibreMap as a raw string. This works on all platforms.
//
// Rule 15 (Offline): the filtering is applied at load time — works
// offline because the style is bundled.

import 'dart:convert';

/// POI subclasses that should be HIDDEN on the family map.
/// Drawn from the OpenFreeMap / OpenMapTiles schema.
const kHiddenPoiSubclasses = <String>{
  // Restaurants / food
  'restaurant', 'fast_food', 'food_court', 'ice_cream', 'beverages',
  'seafood', 'bar', 'bbq', 'biergarten',
  // Cafés
  'cafe', 'coffee_shop', 'tea',
  // Hotels / accommodation
  'hotel', 'hostel', 'motel', 'guest_house', 'apartment', 'camp_site',
  'alpine_hut', 'caravan_site',
  // Shopping
  'shop', 'supermarket', 'convenience', 'mall', 'clothes', 'shoes',
  'electronics', 'jewelry', 'books', 'gift', 'bakery', 'butcher',
  'greengrocer', 'florist', 'furniture', 'mobile_phone', 'optician',
  'beauty', 'hairdresser', 'sports', 'toys', 'stationery', 'kiosk',
  // Nightlife
  'nightclub', 'stripclub', 'swingerclub', 'casino',
  // Fuel
  'fuel',
  // Alcohol / tobacco
  'alcohol', 'tobacco',
};

/// POI subclasses that should be KEPT (visible) on the family map.
/// Drawn from the OpenFreeMap / OpenMapTiles schema.
const kKeptPoiSubclasses = <String>{
  // Schools
  'school', 'kindergarten', 'college', 'university', 'language_school',
  'music_school', 'driving_school',
  // Hospitals
  'hospital', 'clinic', 'doctors', 'dentist', 'pharmacy', 'veterinary',
  // Religious
  'place_of_worship', 'christian', 'muslim', 'jewish', 'hindu', 'buddhist',
  'shinto', 'taoist', 'other_religious',
  // Parks (already shown as landuse, but some POIs may exist)
  'park', 'playground', 'garden', 'nature_reserve', ' recreation_ground',
  // Cemeteries (also landuse, but POIs sometimes exist)
  'cemetery', 'grave_yard',
  // Other meaningful
  'library', 'museum', 'theatre', 'cinema', 'arts_centre', 'gallery',
  'community_centre', 'townhall', 'courthouse', 'police', 'fire_station',
  'post_office', 'bank', 'atm', 'toilets', 'drinking_water',
};

/// Patches the loaded map style JSON to:
///   1. Hide unwanted POI subclasses (restaurants, cafés, hotels, etc.).
///   2. Hide secondary POIs below MapVisualConstants.secondaryPoiMinZoom.
///
/// [styleJsonString] — the raw JSON loaded from the asset bundle.
/// Returns the patched JSON string. On any parse error, returns the
/// input unchanged (Rule 12 graceful degradation).
String applyPoiFilters(String styleJsonString) {
  try {
    final decoded = jsonDecode(styleJsonString);
    if (decoded is! Map<String, dynamic>) return styleJsonString;
    final layers = decoded['layers'];
    if (layers is! List) return styleJsonString;

    // Build a list of POI subclass exclusion filters.
    final excludeFilter = <String, dynamic>{
      '!in': ['get', 'subclass', ...kHiddenPoiSubclasses],
    };

    final patchedLayers = <dynamic>[];
    for (final layer in layers) {
      if (layer is! Map<String, dynamic>) {
        patchedLayers.add(layer);
        continue;
      }
      final id = layer['id'];
      final sourceLayer = layer['source-layer'];
      if (sourceLayer == 'poi' && id is String && id.startsWith('poi')) {
        // Wrap the existing filter in an `all` with our exclude filter.
        final existing = layer['filter'];
        final mergedFilter = existing == null
            ? excludeFilter
            : <String, dynamic>{
                'all': [existing, excludeFilter],
              };
        patchedLayers.add(<String, dynamic>{
          ...layer,
          'filter': mergedFilter,
          // Bump minzoom on secondary POI layers so they only appear
          // when zoomed in past secondaryPoiMinZoom.
          if (id.contains('r20') || id.contains('r7'))
            'minzoom': 14, // MapVisualConstants.secondaryPoiMinZoom
        });
      } else {
        patchedLayers.add(layer);
      }
    }

    final patched = <String, dynamic>{...decoded, 'layers': patchedLayers};
    return jsonEncode(patched);
  } catch (e) {
    // Rule 12: graceful degradation — return the input unchanged.
    return styleJsonString;
  }
}

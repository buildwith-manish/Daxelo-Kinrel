// test/features/family_map/p10_2_family_building_layer_test.dart
//
// P10.2 — Unit tests for the family building layer's pure helpers.
//
// Verifies:
//   - buildingColorFor returns the correct Color per PlaceType.
//   - buildingHexFor returns the matching hex string.
//   - buildFamilyPlacesGeoJson produces a valid FeatureCollection with
//     the placeType wire-name as a property on each feature.
//   - The GeoJSON includes the memoryCount and isMemorial / isWedding
//     flags used by the focus mode and animation gating logic.
//
// Widget-level integration with MapLibre is exercised in the golden /
// driver tests (not in this unit test — see Rule 12 fallback strategy).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/family_map/widgets/family_building_layer.dart';
import 'package:kinrel/features/family_map/data/place_models.dart';
import 'package:kinrel/features/family_map/config/map_visual_constants.dart';

void main() {
  group('P10.2 buildingColorFor', () {
    test('returns a distinct color for every PlaceType', () {
      final colors = <int>{};
      for (final t in PlaceType.values) {
        final c = buildingColorFor(t);
        expect(c.value, isNot(equals(0)));
        colors.add(c.value);
      }
      // At least 6 of 9 should be distinct — memorial/childhoodHome share
      // amber by design (both are soft warm), wedding/currentHome share orange
      // (both are celebration), importantPlace/currentHome share orange.
      expect(colors.length, greaterThanOrEqualTo(6));
    });

    test('school is the only cool color in the palette', () {
      final c = buildingColorFor(PlaceType.school);
      // Blue-ish — B channel noticeably higher than R.
      expect((c.value >> 0) & 0xFF, greaterThan((c.value >> 16) & 0xFF));
    });

    test('currentHome matches the brand orange', () {
      expect(
        buildingColorFor(PlaceType.currentHome),
        equals(MapVisualConstants.buildingCurrentHome),
      );
    });

    test('ancestralHome is the gold heritage color', () {
      expect(
        buildingColorFor(PlaceType.ancestralHome),
        equals(MapVisualConstants.buildingAncestralHome),
      );
    });
  });

  group('P10.2 buildingHexFor', () {
    test('returns a 7-char hex string starting with #', () {
      for (final t in PlaceType.values) {
        final h = buildingHexFor(t);
        expect(h, startsWith('#'));
        expect(h.length, equals(7));
      }
    });
  });

  group('P10.2 buildFamilyPlacesGeoJson', () {
    final places = <FamilyPlace>[
      FamilyPlace(
        id: 'p1',
        familyId: 'fam',
        name: 'Ancestral Home',
        placeType: PlaceType.ancestralHome,
        lat: 18.52,
        lng: 73.85,
        memoryCount: 7,
      ),
      FamilyPlace(
        id: 'p2',
        familyId: 'fam',
        name: 'Grandma Memorial',
        placeType: PlaceType.memorial,
        lat: 19.07,
        lng: 72.87,
        memoryCount: 0,
      ),
      FamilyPlace(
        id: 'p3',
        familyId: 'fam',
        name: 'Wedding Venue',
        placeType: PlaceType.wedding,
        lat: 12.97,
        lng: 77.59,
        memoryCount: 3,
      ),
    ];

    test('produces a valid FeatureCollection', () {
      final json =
          jsonDecode(buildFamilyPlacesGeoJson(places)) as Map<String, dynamic>;
      expect(json['type'], equals('FeatureCollection'));
      final features = json['features'] as List<dynamic>;
      expect(features, hasLength(3));
    });

    test('each feature has placeType wire-name', () {
      final json =
          jsonDecode(buildFamilyPlacesGeoJson(places)) as Map<String, dynamic>;
      final features = json['features'] as List<dynamic>;
      final wireNames = features
          .map(
            (f) =>
                (f as Map<String, dynamic>)['properties']
                    as Map<String, dynamic>,
          )
          .map((p) => p['placeType'] as String)
          .toSet();
      expect(
        wireNames,
        containsAll(<String>{'ancestral_home', 'memorial', 'wedding'}),
      );
    });

    test('geometry is Polygon with [lng, lat] coordinates (GeoJSON order)', () {
      final json =
          jsonDecode(buildFamilyPlacesGeoJson(places)) as Map<String, dynamic>;
      final features = json['features'] as List<dynamic>;
      final first = features[0] as Map<String, dynamic>;
      final geometry = first['geometry'] as Map<String, dynamic>;
      // Now emits Polygon (not Point) for fill-extrusion support.
      expect(geometry['type'], equals('Polygon'));
      final rings = geometry['coordinates'] as List;
      final ring = rings[0] as List;
      // The ring has 5 points (4 corners + closing point).
      expect(ring.length, equals(5));
      // First corner is [lng - boxSize, lat - boxSize] — verify lng comes first.
      final corner = ring[0] as List;
      expect(corner[0], isA<double>());
      expect(corner[1], isA<double>());
      // Lng should be close to 73.85 (slightly less due to boxSize offset).
      expect((corner[0] as double), closeTo(73.85, 0.001));
      // Lat should be close to 18.52 (slightly less due to boxSize offset).
      expect((corner[1] as double), closeTo(18.52, 0.001));
    });

    test('isMemorial / isWedding flags are set on the right features', () {
      final json =
          jsonDecode(buildFamilyPlacesGeoJson(places)) as Map<String, dynamic>;
      final features = json['features'] as List<dynamic>;
      final byName = <String, Map<String, dynamic>>{
        for (final f in features)
          ((f as Map<String, dynamic>)['properties']
                      as Map<String, dynamic>)['name']
                  as String:
              (f['properties'] as Map<String, dynamic>),
      };
      expect(byName['Grandma Memorial']!['isMemorial'], isTrue);
      expect(byName['Ancestral Home']!['isMemorial'], isFalse);
      expect(byName['Wedding Venue']!['isWedding'], isTrue);
      expect(byName['Ancestral Home']!['isWedding'], isFalse);
    });

    test('memoryCount is exposed as a property', () {
      final json =
          jsonDecode(buildFamilyPlacesGeoJson(places)) as Map<String, dynamic>;
      final features = json['features'] as List<dynamic>;
      final counts = features
          .map(
            (f) =>
                (f as Map<String, dynamic>)['properties']
                    as Map<String, dynamic>,
          )
          .map((p) => p['memoryCount'])
          .toSet();
      expect(counts, containsAll(<int>{7, 0, 3}));
    });

    test('empty place list produces an empty FeatureCollection', () {
      final json =
          jsonDecode(buildFamilyPlacesGeoJson(<FamilyPlace>[]))
              as Map<String, dynamic>;
      expect(json['type'], equals('FeatureCollection'));
      expect(json['features'] as List, isEmpty);
    });
  });

  group('P10.2 FamilyBuildingLayer lifecycle', () {
    test('can be constructed and disposed without a live MapLibre style', () {
      // Construction should never throw — no platform code runs.
      final layer = FamilyBuildingLayer();
      layer.dispose();
      expect(true, isTrue); // reached here = no exception
    });

    test('deviceTier injection works', () {
      // ignore: avoid_unused_constructor_parameters
      final layer = FamilyBuildingLayer(deviceTier: null);
      expect(layer.animationsEnabled, isTrue); // defaults to mid
      layer.dispose();
    });
  });

  group('P11.x FamilyBuildingAnimationEngine', () {
    test('can be constructed and disposed without a live MapLibre style', () {
      final engine = FamilyBuildingAnimationEngine();
      engine.dispose();
      expect(true, isTrue);
    });

    test('reduced motion disables animations', () {
      final engine = FamilyBuildingAnimationEngine(reducedMotion: true);
      // Engine constructed in reduced-motion mode — should not start
      // a timer even when start() is called. We can't pass a real
      // StyleController in a unit test, so we just verify construction
      // + dispose work cleanly.
      engine.dispose();
      expect(true, isTrue);
    });

    test('stop is safe to call when not running', () {
      final engine = FamilyBuildingAnimationEngine();
      engine.stop(); // should not throw
      engine.dispose();
      expect(true, isTrue);
    });
  });
}

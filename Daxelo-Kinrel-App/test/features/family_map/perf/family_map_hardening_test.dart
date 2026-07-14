// test/features/family_map/perf/family_map_hardening_test.dart
//
// Family Map Final Production Hardening — focused unit tests for:
//   • Location resolution (exact Place beats city centroid)
//   • Household clustering (city-centroid pins don't form households)
//   • Deterministic fallback spread (stable across rebuilds)
//   • Map data validation (invalid coordinates, self-edges, duplicates)
//   • Family-map lifecycle (legal/stale transitions, terminal states)
//   • Multi-family correctness (family switch doesn't retain stale data)

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/family_map/data/family_map_lifecycle.dart';
import 'package:kinrel/features/family_map/data/map_data_validator.dart';
import 'package:kinrel/features/family_map/data/map_location_source.dart';
import 'package:kinrel/features/family_map/data/map_location_resolver.dart';
import 'package:kinrel/features/family_map/data/deterministic_spread.dart';
import 'package:kinrel/features/family_map/data/place_models.dart';
import 'package:kinrel/features/family_map/providers/family_map_provider.dart';

void main() {
  // ─────────────────────────────────────────────────────────────────────
  // 1. LOCATION RESOLUTION
  // ─────────────────────────────────────────────────────────────────────

  group('Location resolution', () {
    test('exact eligible FamilyPlace beats city centroid', () {
      final place = FamilyPlace(
        id: 'p1',
        familyId: 'f1',
        name: 'Home',
        placeType: PlaceType.currentHome,
        lat: 12.9716,
        lng: 77.5946,
      );
      final resolved = resolvePrimaryMapLocation(
        cityLat: 19.0760,
        cityLng: 72.8777,
        linkedPlace: place,
      );
      expect(resolved, isNotNull);
      expect(resolved!.lat, 12.9716);
      expect(resolved.lng, 77.5946);
      expect(resolved.source, MapLocationSource.exactPlace);
    });

    test('ineligible historical Place does not replace city centroid', () {
      final place = FamilyPlace(
        id: 'p1',
        familyId: 'f1',
        name: 'Birthplace',
        placeType: PlaceType.birthplace,
        lat: 35.6762,
        lng: 139.6503,
      );
      final resolved = resolvePrimaryMapLocation(
        cityLat: 19.0760,
        cityLng: 72.8777,
        linkedPlace: place,
      );
      expect(resolved, isNotNull);
      expect(resolved!.lat, 19.0760);
      expect(resolved.lng, 72.8777);
      expect(resolved.source, MapLocationSource.cityCentroid);
    });

    test('city fallback works when no Place is linked', () {
      final resolved = resolvePrimaryMapLocation(
        cityLat: 19.0760,
        cityLng: 72.8777,
        linkedPlace: null,
      );
      expect(resolved, isNotNull);
      expect(resolved!.source, MapLocationSource.cityCentroid);
    });

    test('invalid Place coordinates (0,0) fall through to city centroid', () {
      final place = FamilyPlace(
        id: 'p1',
        familyId: 'f1',
        name: 'Home',
        placeType: PlaceType.currentHome,
        lat: 0.0,
        lng: 0.0,
      );
      final resolved = resolvePrimaryMapLocation(
        cityLat: 19.0760,
        cityLng: 72.8777,
        linkedPlace: place,
      );
      expect(resolved, isNotNull);
      expect(resolved!.source, MapLocationSource.cityCentroid);
    });

    test('null city + null place returns null', () {
      final resolved = resolvePrimaryMapLocation(
        cityLat: null,
        cityLng: null,
        linkedPlace: null,
      );
      expect(resolved, isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // 2. HOUSEHOLD CLUSTERING
  // ─────────────────────────────────────────────────────────────────────

  group('Household clustering', () {
    test('identical city-centroid pins do NOT create a household', () {
      final pins = [
        MapPin(
          personId: 'a', name: 'A', city: 'Mumbai', photoUrl: null,
          lat: 19.076, lng: 72.877,
          locationSource: MapLocationSource.cityCentroid,
        ),
        MapPin(
          personId: 'b', name: 'B', city: 'Mumbai', photoUrl: null,
          lat: 19.076, lng: 72.877,
          locationSource: MapLocationSource.cityCentroid,
        ),
      ];
      final households = computeHouseholds(pins);
      expect(households, isEmpty,
          reason: 'City-centroid fallback pins must not cluster');
    });

    test('two exact-home pins sharing coordinates CAN cluster', () {
      final pins = [
        MapPin(
          personId: 'a', name: 'A', city: 'Mumbai', photoUrl: null,
          lat: 19.076, lng: 72.877,
          locationSource: MapLocationSource.exactPlace,
        ),
        MapPin(
          personId: 'b', name: 'B', city: 'Mumbai', photoUrl: null,
          lat: 19.076, lng: 72.877,
          locationSource: MapLocationSource.exactPlace,
        ),
      ];
      final households = computeHouseholds(pins);
      expect(households, hasLength(1));
      expect(households.first.isMulti, isTrue);
    });

    test('single member remains single household', () {
      final pins = [
        MapPin(
          personId: 'a', name: 'A', city: 'Mumbai', photoUrl: null,
          lat: 19.076, lng: 72.877,
          locationSource: MapLocationSource.exactPlace,
        ),
      ];
      final households = computeHouseholds(pins);
      expect(households, hasLength(1));
      expect(households.first.isMulti, isFalse);
    });

    test('pins with null locationSource are treated as clusterable', () {
      // Backward compatibility: pins without locationSource (legacy) still cluster.
      final pins = [
        MapPin(
          personId: 'a', name: 'A', city: 'Mumbai', photoUrl: null,
          lat: 19.076, lng: 72.877,
        ),
        MapPin(
          personId: 'b', name: 'B', city: 'Mumbai', photoUrl: null,
          lat: 19.076, lng: 72.877,
        ),
      ];
      final households = computeHouseholds(pins);
      expect(households, hasLength(1));
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // 3. DETERMINISTIC FALLBACK SPREAD
  // ─────────────────────────────────────────────────────────────────────

  group('Deterministic fallback spread', () {
    test('same personId produces same offset every time', () {
      final offset1 = deterministicSpreadOffset('person-abc');
      final offset2 = deterministicSpreadOffset('person-abc');
      expect(offset1.lat, offset2.lat);
      expect(offset1.lng, offset2.lng);
    });

    test('different personIds produce different offsets', () {
      final offset1 = deterministicSpreadOffset('person-aaa');
      final offset2 = deterministicSpreadOffset('person-bbb');
      // At least one component should differ
      expect(offset1.lat != offset2.lat || offset1.lng != offset2.lng, isTrue);
    });

    test('spread stays within configured maximum', () {
      const maxOffset = 0.01;
      for (var i = 0; i < 100; i++) {
        final offset = deterministicSpreadOffset('person-$i', maxOffsetDegrees: maxOffset);
        expect(offset.lat.abs(), lessThanOrEqualTo(maxOffset));
        expect(offset.lng.abs(), lessThanOrEqualTo(maxOffset));
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // 4. MAP DATA VALIDATION
  // ─────────────────────────────────────────────────────────────────────

  group('Map data validation', () {
    test('valid latitude is accepted', () {
      expect(isValidLatitude(0), isTrue);
      expect(isValidLatitude(90), isTrue);
      expect(isValidLatitude(-90), isTrue);
      expect(isValidLatitude(45.5), isTrue);
    });

    test('invalid latitude is rejected', () {
      expect(isValidLatitude(91), isFalse);
      expect(isValidLatitude(-91), isFalse);
      expect(isValidLatitude(double.nan), isFalse);
      expect(isValidLatitude(double.infinity), isFalse);
      expect(isValidLatitude(double.negativeInfinity), isFalse);
    });

    test('valid longitude is accepted', () {
      expect(isValidLongitude(0), isTrue);
      expect(isValidLongitude(180), isTrue);
      expect(isValidLongitude(-180), isTrue);
      expect(isValidLongitude(77.59), isTrue);
    });

    test('invalid longitude is rejected', () {
      expect(isValidLongitude(181), isFalse);
      expect(isValidLongitude(-181), isFalse);
      expect(isValidLongitude(double.nan), isFalse);
    });

    test('coordinate pair validation', () {
      expect(isValidCoordinate(45, 90), isTrue);
      expect(isValidCoordinate(91, 90), isFalse);
      expect(isValidCoordinate(45, 181), isFalse);
    });

    test('self-edge is removed', () {
      final edges = [
        (fromId: 'a', toId: 'b', edgeId: 'e1', relationshipKey: 'father'),
        (fromId: 'a', toId: 'a', edgeId: 'e2', relationshipKey: 'self'),
      ];
      final result = removeSelfEdges(edges);
      expect(result, hasLength(1));
      expect(result.first.fromId, 'a');
      expect(result.first.toId, 'b');
    });

    test('duplicate relationship edge is removed', () {
      final edges = [
        (fromId: 'a', toId: 'b', edgeId: 'e1', relationshipKey: 'father'),
        (fromId: 'b', toId: 'a', edgeId: 'e2', relationshipKey: 'child'),
      ];
      final result = removeDuplicateEdges(edges);
      expect(result, hasLength(1));
    });

    test('edge with missing pin is removed', () {
      final edges = [
        (fromId: 'a', toId: 'b', edgeId: 'e1', relationshipKey: 'father'),
        (fromId: 'a', toId: 'c', edgeId: 'e2', relationshipKey: 'son'),
      ];
      final result = removeEdgesWithMissingPins(edges, {'a', 'b'});
      expect(result, hasLength(1));
      expect(result.first.toId, 'b');
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // 5. FAMILY MAP LIFECYCLE
  // ─────────────────────────────────────────────────────────────────────

  group('Family map lifecycle', () {
    test('initial state is initializing', () {
      final c = FamilyMapLifecycleController();
      addTearDown(c.dispose);
      expect(c.state, FamilyMapLifecycle.initializing);
    });

    test('valid transition: initializing → loadingStyle → ready', () {
      final c = FamilyMapLifecycleController();
      addTearDown(c.dispose);
      final a = c.currentAttempt;
      c.transition(FamilyMapLifecycle.loadingStyle, attempt: a);
      c.transition(FamilyMapLifecycle.ready, attempt: a);
      expect(c.state, FamilyMapLifecycle.ready);
    });

    test('stale attempt transition is ignored', () {
      final c = FamilyMapLifecycleController();
      addTearDown(c.dispose);
      c.transition(FamilyMapLifecycle.loadingStyle, attempt: 0);
      c.reset(); // attempt becomes 1
      c.transition(FamilyMapLifecycle.ready, attempt: 0); // stale
      expect(c.state, FamilyMapLifecycle.initializing);
    });

    test('terminal state rejects later transitions', () {
      final c = FamilyMapLifecycleController();
      addTearDown(c.dispose);
      final a = c.currentAttempt;
      c.transition(FamilyMapLifecycle.loadingStyle, attempt: a);
      c.transition(FamilyMapLifecycle.ready, attempt: a);
      c.transition(FamilyMapLifecycle.empty, attempt: a);
      expect(c.state, FamilyMapLifecycle.ready);
    });

    test('reset increments attempt', () {
      final c = FamilyMapLifecycleController();
      addTearDown(c.dispose);
      expect(c.currentAttempt, 0);
      c.reset();
      expect(c.currentAttempt, 1);
      expect(c.state, FamilyMapLifecycle.initializing);
    });

    test('0 located members → empty (not loading)', () {
      final c = FamilyMapLifecycleController();
      addTearDown(c.dispose);
      final a = c.currentAttempt;
      c.transition(FamilyMapLifecycle.loadingStyle, attempt: a);
      c.transition(FamilyMapLifecycle.preparingLayers, attempt: a);
      c.transition(FamilyMapLifecycle.empty, attempt: a);
      expect(c.state.isTerminal, isTrue);
      expect(c.state.showLoadingOverlay, isFalse);
      expect(c.state.shouldRenderMap, isTrue);
    });

    test('failed state shows error UI, not loading overlay', () {
      final c = FamilyMapLifecycleController();
      addTearDown(c.dispose);
      c.transition(FamilyMapLifecycle.failed, attempt: c.currentAttempt);
      expect(c.state.showLoadingOverlay, isFalse);
      expect(c.state.shouldRenderMap, isTrue);
      expect(c.state.isTerminal, isTrue);
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // 6. MAP LOCATION SOURCE
  // ─────────────────────────────────────────────────────────────────────

  group('MapLocationSource', () {
    test('cityCentroid is low confidence', () {
      expect(MapLocationSource.cityCentroid.isHighConfidence, isFalse);
      expect(MapLocationSource.cityCentroid.canCluster, isFalse);
    });

    test('exactPlace is high confidence and can cluster', () {
      expect(MapLocationSource.exactPlace.isHighConfidence, isTrue);
      expect(MapLocationSource.exactPlace.canCluster, isTrue);
    });

    test('live is high confidence and can cluster', () {
      expect(MapLocationSource.live.isHighConfidence, isTrue);
      expect(MapLocationSource.live.canCluster, isTrue);
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // 7. PLACE TYPE ANCHOR ELIGIBILITY
  // ─────────────────────────────────────────────────────────────────────

  group('Place type anchor eligibility', () {
    test('currentHome is a valid anchor', () {
      expect(isCurrentLocationAnchor(PlaceType.currentHome), isTrue);
    });

    test('birthplace is NOT a valid anchor', () {
      expect(isCurrentLocationAnchor(PlaceType.birthplace), isFalse);
    });

    test('school is NOT a valid anchor', () {
      expect(isCurrentLocationAnchor(PlaceType.school), isFalse);
    });

    test('memorial is NOT a valid anchor', () {
      expect(isCurrentLocationAnchor(PlaceType.memorial), isFalse);
    });

    test('null is NOT a valid anchor', () {
      expect(isCurrentLocationAnchor(null), isFalse);
    });
  });
}

// test/features/family_map/p10_7_map_timeline_test.dart
//
// P10.7 — Unit tests for the Map Timeline (JourneyProvider extension).
//
// Verifies:
//   - JourneyController.filterMapPins returns only alive pins.
//   - Pins with no dateOfBirth are always returned.
//   - Pins deceased before the selected year are excluded.
//   - Pins not yet born at the selected year are excluded.
//   - filterMapPlaces filters by validFrom / validTo.
//   - buildJourneyStops produces an ordered list with the birth stop first.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/family_journey/providers/journey_provider.dart';
import 'package:kinrel/features/family_map/providers/family_map_provider.dart';
import 'package:kinrel/features/family_map/data/place_models.dart';
import 'package:kinrel/features/family_map/widgets/family_journey_animation.dart';

void main() {
  group('P10.7 JourneyController.filterMapPins', () {
    final controller = JourneyController();

    test('returns only alive pins at the selected year', () {
      controller.setYear(1990);
      final pins = <MapPin>[
        const MapPin(
          personId: 'a',
          name: 'A',
          city: 'X',
          photoUrl: null,
          lat: 0,
          lng: 0,
        ),
        const MapPin(
          personId: 'b',
          name: 'B',
          city: 'Y',
          photoUrl: null,
          lat: 0,
          lng: 1,
        ),
        const MapPin(
          personId: 'c',
          name: 'C',
          city: 'Z',
          photoUrl: null,
          lat: 1,
          lng: 0,
        ),
      ];
      final dobs = <String, DateTime>{
        'a': DateTime(1950),
        'b': DateTime(2000), // born in 2000 — not alive in 1990
        'c': DateTime(1980),
      };
      final dod = <String, DateTime>{
        'c': DateTime(1985), // died before 1990
      };
      final filtered = controller.filterMapPins(
        pins,
        dateOfBirthByPersonId: dobs,
        dateOfDeathByPersonId: dod,
      );
      final ids = filtered.map((p) => p.personId).toSet();
      expect(ids, contains('a'));
      expect(ids, isNot(contains('b')));
      expect(ids, isNot(contains('c')));
    });

    test('pins with no dateOfBirth are always returned', () {
      controller.setYear(1900);
      final pins = <MapPin>[
        const MapPin(
          personId: 'unknown',
          name: 'X',
          city: 'Y',
          photoUrl: null,
          lat: 0,
          lng: 0,
        ),
      ];
      final filtered = controller.filterMapPins(pins);
      expect(filtered, hasLength(1));
    });

    test('respects year change', () {
      controller.setYear(2024);
      final pins = <MapPin>[
        const MapPin(
          personId: 'a',
          name: 'A',
          city: 'X',
          photoUrl: null,
          lat: 0,
          lng: 0,
        ),
      ];
      final dobs = <String, DateTime>{'a': DateTime(2000)};
      expect(
        controller.filterMapPins(pins, dateOfBirthByPersonId: dobs),
        hasLength(1),
      );
      controller.setYear(1990);
      expect(
        controller.filterMapPins(pins, dateOfBirthByPersonId: dobs),
        isEmpty,
      );
    });
  });

  group('P10.7 JourneyController.filterMapPlaces', () {
    final controller = JourneyController();

    test('filters by validFrom / validTo', () {
      controller.setYear(1995);
      final places = <FamilyPlace>[
        FamilyPlace(
          id: 'p1',
          familyId: 'f',
          name: 'Always Valid',
          placeType: PlaceType.ancestralHome,
          lat: 0,
          lng: 0,
        ),
        FamilyPlace(
          id: 'p2',
          familyId: 'f',
          name: 'Old Home',
          placeType: PlaceType.childhoodHome,
          lat: 0,
          lng: 0,
          validFrom: DateTime(1950),
          validTo: DateTime(1980),
        ),
        FamilyPlace(
          id: 'p3',
          familyId: 'f',
          name: 'New Home',
          placeType: PlaceType.currentHome,
          lat: 0,
          lng: 0,
          validFrom: DateTime(2000),
        ),
      ];
      final filtered = controller.filterMapPlaces(places);
      final ids = filtered.map((p) => p.id).toSet();
      expect(ids, contains('p1'));
      expect(ids, isNot(contains('p2'))); // ended in 1980
      expect(ids, isNot(contains('p3'))); // started in 2000
    });
  });

  group('P10.7 buildJourneyStops', () {
    test('orders stops by year, oldest first', () {
      final pin = const MapPin(
        personId: 'p1',
        name: 'Test',
        city: 'X',
        photoUrl: null,
        lat: 0,
        lng: 0,
      );
      final places = <FamilyPlace>[
        FamilyPlace(
          id: 'p2',
          familyId: 'f',
          name: 'Recent Home',
          placeType: PlaceType.currentHome,
          lat: 1,
          lng: 1,
          validFrom: DateTime(2020),
        ),
        FamilyPlace(
          id: 'p1',
          familyId: 'f',
          name: 'Childhood Home',
          placeType: PlaceType.childhoodHome,
          lat: 2,
          lng: 2,
          validFrom: DateTime(1990),
        ),
      ];
      final stops = buildJourneyStops(
        pin: pin,
        linkedPlaces: places,
        birthYear: 1985,
      );
      expect(stops, hasLength(3));
      expect(stops[0].year, equals(1985));
      expect(stops[0].label, equals('Born'));
      expect(stops[1].year, equals(1990));
      expect(stops[2].year, equals(2020));
    });

    test('without birthYear, only place stops are returned', () {
      final pin = const MapPin(
        personId: 'p1',
        name: 'Test',
        city: 'X',
        photoUrl: null,
        lat: 0,
        lng: 0,
      );
      final places = <FamilyPlace>[
        FamilyPlace(
          id: 'p1',
          familyId: 'f',
          name: 'Home',
          placeType: PlaceType.currentHome,
          lat: 1,
          lng: 1,
          validFrom: DateTime(2020),
        ),
      ];
      final stops = buildJourneyStops(pin: pin, linkedPlaces: places);
      expect(stops, hasLength(1));
      expect(stops.first.label, equals('Home'));
    });
  });
}

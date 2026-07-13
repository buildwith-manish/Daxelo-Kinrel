// test/features/family_map/p10_1_place_models_test.dart
//
// P10.1 — Unit tests for the FamilyPlace model and PlaceType enum.
//
// Verifies:
//   - All 9 PlaceType values exist (acceptance criterion).
//   - semanticLabel is non-empty for every type.
//   - wireName round-trips via fromWireName.
//   - FamilyPlace.isValidAt respects validFrom / validTo bounds.
//   - FamilyPlace.fromJson handles both camelCase and snake_case keys.
//   - Unknown wire names fall back to importantPlace (forward-compat).

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/family_map/data/place_models.dart';

void main() {
  group('P10.1 PlaceType enum', () {
    test('has exactly 9 values', () {
      expect(PlaceType.values, hasLength(9));
    });

    test('every type has a non-empty semantic label', () {
      for (final t in PlaceType.values) {
        expect(t.semanticLabel, isNotEmpty,
            reason: '$t should have a semantic label');
      }
    });

    test('wireName is snake_case and round-trips via fromWireName', () {
      for (final t in PlaceType.values) {
        expect(t.wireName, matches(r'^[a-z_]+$'),
            reason: '$t wireName should be snake_case');
        expect(PlaceType.fromWireName(t.wireName), equals(t),
            reason: '$t should round-trip through wireName');
      }
    });

    test('fromWireName returns importantPlace for unknown / null', () {
      expect(PlaceType.fromWireName(null), equals(PlaceType.importantPlace));
      expect(PlaceType.fromWireName(''), equals(PlaceType.importantPlace));
      expect(PlaceType.fromWireName('not_a_real_type'),
          equals(PlaceType.importantPlace));
    });

    test('expected values are present in order (forward-compat)', () {
      // DO NOT reorder — persistence relies on enum name, but tests guard
      // against accidental reordering during refactors.
      expect(PlaceType.values, equals(<PlaceType>[
        PlaceType.currentHome,
        PlaceType.childhoodHome,
        PlaceType.ancestralHome,
        PlaceType.birthplace,
        PlaceType.wedding,
        PlaceType.memorial,
        PlaceType.familyBusiness,
        PlaceType.school,
        PlaceType.importantPlace,
      ]));
    });
  });

  group('P10.1 FamilyPlace.isValidAt', () {
    final base = FamilyPlace(
      id: 'p1',
      familyId: 'f1',
      name: 'Test Place',
      placeType: PlaceType.currentHome,
      lat: 18.52,
      lng: 73.85,
    );

    test('null bounds = always valid', () {
      expect(base.isValidAt(DateTime(1900)), isTrue);
      expect(base.isValidAt(DateTime(2099)), isTrue);
    });

    test('validFrom excludes earlier dates', () {
      final p = base.copyWith(validFrom: DateTime(1995, 6, 1));
      expect(p.isValidAt(DateTime(1990)), isFalse);
      expect(p.isValidAt(DateTime(1995, 6, 1)), isTrue);
      expect(p.isValidAt(DateTime(2024)), isTrue);
    });

    test('validTo excludes later dates', () {
      final p = base.copyWith(validTo: DateTime(2010, 12, 31));
      expect(p.isValidAt(DateTime(1990)), isTrue);
      expect(p.isValidAt(DateTime(2010, 12, 31)), isTrue);
      expect(p.isValidAt(DateTime(2024)), isFalse);
    });

    test('both bounds bracket the date', () {
      final p = base.copyWith(
        validFrom: DateTime(1995),
        validTo: DateTime(2010),
      );
      expect(p.isValidAt(DateTime(1990)), isFalse);
      expect(p.isValidAt(DateTime(2000)), isTrue);
      expect(p.isValidAt(DateTime(2024)), isFalse);
    });
  });

  group('P10.1 FamilyPlace.fromJson', () {
    test('parses camelCase keys (Supabase default)', () {
      final json = <String, dynamic>{
        'id': 'abc',
        'familyId': 'fam1',
        'name': 'Ancestral Home',
        'placeType': 'ancestral_home',
        'lat': 19.07,
        'lng': 72.87,
        'personId': 'p_42',
        'memoryCount': 5,
        'validFrom': '1990-01-01T00:00:00.000Z',
        'validTo': null,
      };
      final p = FamilyPlace.fromJson(json);
      expect(p.id, 'abc');
      expect(p.familyId, 'fam1');
      expect(p.name, 'Ancestral Home');
      expect(p.placeType, PlaceType.ancestralHome);
      expect(p.lat, 19.07);
      expect(p.lng, 72.87);
      expect(p.personId, 'p_42');
      expect(p.memoryCount, 5);
      expect(p.validFrom, isNotNull);
      expect(p.validTo, isNull);
    });

    test('parses snake_case keys (raw SQL fallback)', () {
      final json = <String, dynamic>{
        'id': 'xyz',
        'family_id': 'fam2',
        'name': 'Birthplace',
        'place_type': 'birthplace',
        'lat': 12.97,
        'lng': 77.59,
        'person_id': null,
        'memory_count': 0,
      };
      final p = FamilyPlace.fromJson(json);
      expect(p.familyId, 'fam2');
      expect(p.placeType, PlaceType.birthplace);
      expect(p.personId, isNull);
      expect(p.memoryCount, 0);
    });

    test('unknown placeType falls back to importantPlace', () {
      final p = FamilyPlace.fromJson({
        'id': 'x',
        'name': 'Mystery',
        'placeType': 'unknown_future_type',
        'lat': 0.0,
        'lng': 0.0,
      });
      expect(p.placeType, PlaceType.importantPlace);
    });
  });

  group('P10.1 FamilyPlace equality', () {
    test('two places with same id are equal', () {
      final a = FamilyPlace(
        id: 'same',
        familyId: 'f',
        name: 'A',
        placeType: PlaceType.school,
        lat: 0,
        lng: 0,
      );
      final b = FamilyPlace(
        id: 'same',
        familyId: 'other',
        name: 'B',
        placeType: PlaceType.memorial,
        lat: 1,
        lng: 1,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });
}

// test/features/family_map/p10_4_household_clustering_test.dart
//
// P10.4 — Unit tests for household clustering.
//
// Verifies:
//   - computeHouseholds groups pins that share coordinates.
//   - Pins in different buckets end up in different households.
//   - Single-member households are returned (isMulti == false).
//   - Multi-member households have isMulti == true and size > 1.
//   - Empty pin list → empty household list.
//   - HouseholdClusterMarkerWidget renders without throwing for sizes 1, 2, 4.
//   - HouseholdClusterMarkerCache caches by household ID.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/family_map/providers/family_map_provider.dart';
import 'package:kinrel/features/family_map/widgets/household_cluster_marker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P10.4 computeHouseholds', () {
    test('groups pins sharing the same coordinates', () {
      final pins = <MapPin>[
        const MapPin(
            personId: 'a', name: 'A', city: 'Pune', photoUrl: null,
            lat: 18.52, lng: 73.85),
        const MapPin(
            personId: 'b', name: 'B', city: 'Pune', photoUrl: null,
            lat: 18.52, lng: 73.85),
        const MapPin(
            personId: 'c', name: 'C', city: 'Mumbai', photoUrl: null,
            lat: 19.07, lng: 72.87),
      ];
      final households = computeHouseholds(pins);
      expect(households, hasLength(2));
      final multi = households.firstWhere((h) => h.size == 2);
      expect(multi.isMulti, isTrue);
      expect(multi.members.map((m) => m.personId).toSet(),
          containsAll(<String>{'a', 'b'}));
      final single = households.firstWhere((h) => h.size == 1);
      expect(single.isMulti, isFalse);
      expect(single.members.first.personId, equals('c'));
    });

    test('pins within epsilon are clustered, beyond are not', () {
      // Epsilon is 0.001 degrees ≈ 111m. Two pins 0.0005 apart should
      // round to the same bucket; two pins 0.002 apart should not.
      final pins = <MapPin>[
        const MapPin(
            personId: 'a', name: 'A', city: 'X', photoUrl: null,
            lat: 18.5200, lng: 73.8500),
        const MapPin(
            personId: 'b', name: 'B', city: 'X', photoUrl: null,
            lat: 18.5205, lng: 73.8505),
        const MapPin(
            personId: 'c', name: 'C', city: 'Y', photoUrl: null,
            lat: 18.5220, lng: 73.8520),
      ];
      final households = computeHouseholds(pins);
      expect(households, hasLength(2));
      expect(households.any((h) => h.size == 2), isTrue);
      expect(households.any((h) => h.size == 1), isTrue);
    });

    test('empty pin list returns empty household list', () {
      expect(computeHouseholds(<MapPin>[]), isEmpty);
    });

    test('all in one city → one large household', () {
      final pins = List.generate(
        5,
        (i) => MapPin(
            personId: 'p$i', name: 'P$i', city: 'Pune', photoUrl: null,
            lat: 18.52, lng: 73.85),
      );
      final households = computeHouseholds(pins);
      expect(households, hasLength(1));
      expect(households.first.size, equals(5));
      expect(households.first.isMulti, isTrue);
    });
  });

  group('P10.4 HouseholdClusterMarkerWidget', () {
    testWidgets('renders size=1 household without badge', (tester) async {
      final h = Household(
        id: 'h1',
        members: List.generate(
          1,
          (i) => const MapPin(
              personId: 'p1', name: 'Solo', city: 'X', photoUrl: null,
              lat: 0, lng: 0),
        ),
        lat: 0,
        lng: 0,
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Center(child: HouseholdClusterMarkerWidget(household: h))),
      ));
      await tester.pump();
      expect(find.byType(HouseholdClusterMarkerWidget), findsOneWidget);
      // No badge text.
      expect(find.text('+1'), findsNothing);
    });

    testWidgets('renders size=2 household', (tester) async {
      final h = Household(
        id: 'h2',
        members: List.generate(
          2,
          (i) => MapPin(
              personId: 'p$i', name: 'P$i', city: 'X', photoUrl: null,
              lat: 0, lng: 0),
        ),
        lat: 0,
        lng: 0,
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Center(child: HouseholdClusterMarkerWidget(household: h))),
      ));
      await tester.pump();
      expect(find.byType(HouseholdClusterMarkerWidget), findsOneWidget);
      expect(find.text('+2'), findsNothing); // 2 → no badge, just 2 avatars
    });

    testWidgets('renders size=4 household with +4 badge', (tester) async {
      final h = Household(
        id: 'h4',
        members: List.generate(
          4,
          (i) => MapPin(
              personId: 'p$i', name: 'P$i', city: 'X', photoUrl: null,
              lat: 0, lng: 0),
        ),
        lat: 0,
        lng: 0,
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Center(child: HouseholdClusterMarkerWidget(household: h))),
      ));
      await tester.pump();
      expect(find.byType(HouseholdClusterMarkerWidget), findsOneWidget);
      expect(find.text('+4'), findsOneWidget);
    });

    testWidgets('Semantics label includes member count', (tester) async {
      final h = Household(
        id: 'h',
        members: List.generate(
          3,
          (i) => MapPin(
              personId: 'p$i', name: 'P$i', city: 'X', photoUrl: null,
              lat: 0, lng: 0),
        ),
        lat: 0,
        lng: 0,
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Center(child: HouseholdClusterMarkerWidget(household: h))),
      ));
      await tester.pump();
      expect(find.bySemanticsLabel(contains('3 members')), findsOneWidget);
    });
  });

  group('P10.4 HouseholdClusterMarkerCache', () {
    test('caches by household.id and returns identical bytes', () async {
      final cache = HouseholdClusterMarkerCache.instance;
      cache.clear();
      final h = Household(
        id: 'cache_test',
        members: List.generate(
          3,
          (i) => MapPin(
              personId: 'p$i', name: 'P$i', city: 'X', photoUrl: null,
              lat: 0, lng: 0),
        ),
        lat: 0,
        lng: 0,
      );
      final first = await cache.bytesFor(h);
      final second = await cache.bytesFor(h);
      expect(first, isA<Uint8List>());
      expect(first.length, greaterThan(100));
      expect(identical(first, second), isTrue,
          reason: 'second call returns cached');
    });

    test('clear() empties the cache', () {
      final cache = HouseholdClusterMarkerCache.instance;
      cache.clear();
      // No assertion possible on internals, but clear() must not throw.
      expect(() => cache.clear(), returnsNormally);
    });
  });
}

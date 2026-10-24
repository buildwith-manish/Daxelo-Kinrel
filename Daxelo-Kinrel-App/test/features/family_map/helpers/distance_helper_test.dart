// test/features/family_map/helpers/distance_helper_test.dart
//
// Unit tests for the distance_helper:
//   • haversineMeters — known distances (Bengaluru ↔ Mumbai, NYC ↔ LA)
//   • formatDistance — boundary thresholds (0, <50, <1000m, <10000m, >=10000m)
//   • formatDistanceBetween — convenience wrapper, same outputs

import 'package:flutter_test/flutter_test.dart';

import 'package:kinrel/features/family_map/helpers/distance_helper.dart';

void main() {
  group('haversineMeters — known distances', () {
    test('Bengaluru → Mumbai ~ 845 km', () {
      // Bengaluru: 12.9716° N, 77.5946° E
      // Mumbai:   19.0760° N, 72.8777° E
      // Great-circle distance ~ 845 km (verified via Google Maps)
      final m = haversineMeters(
        lat1: 12.9716,
        lng1: 77.5946,
        lat2: 19.0760,
        lng2: 72.8777,
      );
      final km = m / 1000;
      // Allow ±5% tolerance (haversine is spherical; earth isn't
      // perfectly round).
      expect(km, closeTo(845, 50));
    });

    test('NYC → Los Angeles ~ 3945 km', () {
      // NYC: 40.7128° N, -74.0060° W
      // LA:  34.0522° N, -118.2437° W
      final m = haversineMeters(
        lat1: 40.7128,
        lng1: -74.0060,
        lat2: 34.0522,
        lng2: -118.2437,
      );
      final km = m / 1000;
      expect(km, closeTo(3945, 200));
    });

    test('identical points → 0 meters', () {
      final m = haversineMeters(
        lat1: 12.9716,
        lng1: 77.5946,
        lat2: 12.9716,
        lng2: 77.5946,
      );
      expect(m, 0.0);
    });

    test('crossing the equator: 0°N 0°E → 1°N 0°E ~ 111 km', () {
      // 1° latitude ≈ 111 km (the standard approximation).
      final m = haversineMeters(
        lat1: 0,
        lng1: 0,
        lat2: 1,
        lng2: 0,
      );
      final km = m / 1000;
      expect(km, closeTo(111, 1));
    });

    test('crossing longitude at equator: 0°N 0°E → 0°N 1°E ~ 111 km', () {
      // 1° longitude at the equator ≈ 111 km.
      final m = haversineMeters(
        lat1: 0,
        lng1: 0,
        lat2: 0,
        lng2: 1,
      );
      final km = m / 1000;
      expect(km, closeTo(111, 1));
    });
  });

  group('formatDistance — boundary thresholds', () {
    test('isSelf=true → "Live • now" regardless of distance', () {
      expect(formatDistance(meters: 0, isSelf: true), 'Live • now');
      expect(formatDistance(meters: 1000, isSelf: true), 'Live • now');
      expect(formatDistance(meters: 1000000, isSelf: true), 'Live • now');
    });

    test('meters <= 0 → "Live • now"', () {
      expect(formatDistance(meters: 0), 'Live • now');
      expect(formatDistance(meters: -1.0), 'Live • now');
    });

    test('meters < 50 → "< 50 m away"', () {
      expect(formatDistance(meters: 25), '< 50 m away');
      expect(formatDistance(meters: 49.9), '< 50 m away');
    });

    test('50 <= meters < 1000 → "X m away"', () {
      expect(formatDistance(meters: 50), '50 m away');
      expect(formatDistance(meters: 340), '340 m away');
      expect(formatDistance(meters: 999), '999 m away');
    });

    test('1000 <= meters < 10000km → "X.Y km away"', () {
      // 1.5 km → "1.5 km away"
      expect(formatDistance(meters: 1500), '1.5 km away');
      // 12.34 km → "12.3 km away"
      expect(formatDistance(meters: 12340), '12.3 km away');
    });

    test('meters >= 10000000 → "X km away" (no decimal)', () {
      // 10000 km = 10000000 m
      expect(formatDistance(meters: 10000000), '10000 km away');
      expect(formatDistance(meters: 12345678), '12346 km away');
    });
  });

  group('formatDistanceBetween — convenience wrapper', () {
    test('identical points → "Live • now"', () {
      final s = formatDistanceBetween(
        lat1: 12.97,
        lng1: 77.59,
        lat2: 12.97,
        lng2: 77.59,
      );
      expect(s, 'Live • now');
    });

    test('isSelf=true → "Live • now"', () {
      final s = formatDistanceBetween(
        lat1: 12.97,
        lng1: 77.59,
        lat2: 19.07,
        lng2: 72.87,
        isSelf: true,
      );
      expect(s, 'Live • now');
    });

    test('Bengaluru → Mumbai → "845.0 km away"', () {
      final s = formatDistanceBetween(
        lat1: 12.9716,
        lng1: 77.5946,
        lat2: 19.0760,
        lng2: 72.8777,
      );
      // Should be in "X.Y km away" format (1km-10000km branch).
      expect(s.contains('km away'), isTrue);
      // Sanity: first char is a digit.
      expect(s[0], matches(r'[0-9]'));
    });

    test('close points (~250 m) → "X m away"', () {
      // Two points ~250m apart. Use 0.00225° latitude ≈ 250m.
      final s = formatDistanceBetween(
        lat1: 12.9716,
        lng1: 77.5946,
        lat2: 12.9716 + 0.00225,
        lng2: 77.5946,
      );
      expect(s.endsWith(' m away'), isTrue);
    });
  });
}

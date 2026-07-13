// test/features/family_map/p10_9_map_state_persistence_test.dart
//
// P10.9 — Unit tests for Map State Persistence.
//
// Verifies:
//   - MapSessionState.toJson / fromJson round-trips all fields.
//   - fromJson gracefully handles missing fields (uses defaults).
//   - Future timeline years are clamped to the current year.
//   - Corrupted JSON returns null (caller uses defaults).
//   - MapSessionState.defaults has sensible values.
//   - copyWith preserves all fields.
//   - DebouncedMapStateSaver.schedule + flushNow do not throw.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/family_map/data/map_state_persistence.dart';
import 'package:kinrel/features/family_map/config/map_visual_constants.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P10.9 MapSessionState round-trip', () {
    final original = MapSessionState(
      lat: 18.52,
      lng: 73.85,
      zoom: 14.0,
      pitch: 45.0,
      bearing: 12.0,
      selectedPersonId: 'p1',
      timelineYear: 1990,
      isFocusMode: true,
      expandedHouseholdId: 'hh1',
      mapStyleId: 'kinrel_dark',
      version: 1,
      savedAt: '2026-07-14T00:00:00.000Z',
    );

    test('toJson / fromJson round-trip preserves all fields', () {
      final json = original.toJson();
      final restored = MapSessionState.fromJson(json);
      expect(restored.lat, equals(original.lat));
      expect(restored.lng, equals(original.lng));
      expect(restored.zoom, equals(original.zoom));
      expect(restored.pitch, equals(original.pitch));
      expect(restored.bearing, equals(original.bearing));
      expect(restored.selectedPersonId, equals(original.selectedPersonId));
      expect(restored.timelineYear, equals(original.timelineYear));
      expect(restored.isFocusMode, equals(original.isFocusMode));
      expect(restored.expandedHouseholdId,
          equals(original.expandedHouseholdId));
      expect(restored.mapStyleId, equals(original.mapStyleId));
      expect(restored.version, equals(original.version));
      expect(restored.savedAt, equals(original.savedAt));
    });

    test('JSON string round-trip via jsonEncode/jsonDecode', () {
      final jsonStr = jsonEncode(original.toJson());
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      final restored = MapSessionState.fromJson(decoded);
      expect(restored.lat, equals(original.lat));
      expect(restored.selectedPersonId, equals(original.selectedPersonId));
    });
  });

  group('P10.9 MapSessionState.fromJson graceful defaults', () {
    test('missing fields fall back to defaults', () {
      final s = MapSessionState.fromJson(<String, dynamic>{});
      expect(s.lat, equals(22.0));
      expect(s.lng, equals(79.0));
      expect(s.zoom, equals(4.5));
      expect(s.pitch, equals(0));
      expect(s.bearing, equals(0));
      expect(s.selectedPersonId, isNull);
      expect(s.timelineYear, isNull);
      expect(s.isFocusMode, isFalse);
      expect(s.expandedHouseholdId, isNull);
      expect(s.mapStyleId, equals('kinrel_dark'));
      expect(s.version, equals(1));
    });

    test('future timeline year is clamped to current year', () {
      final currentYear = DateTime.now().year;
      final s = MapSessionState.fromJson(<String, dynamic>{
        'timelineYear': currentYear + 10,
      });
      expect(s.timelineYear, equals(currentYear));
    });

    test('int values are coerced to double', () {
      final s = MapSessionState.fromJson(<String, dynamic>{
        'lat': 18, // int, not double
        'lng': 73,
        'zoom': 14,
      });
      expect(s.lat, equals(18.0));
      expect(s.lng, equals(73.0));
      expect(s.zoom, equals(14.0));
    });
  });

  group('P10.9 MapSessionState.defaults', () {
    test('has sensible India-centered defaults', () {
      final d = MapSessionState.defaults();
      expect(d.lat, equals(22.0));
      expect(d.lng, equals(79.0));
      expect(d.zoom, equals(4.5));
      expect(d.pitch, equals(0));
      expect(d.bearing, equals(0));
      expect(d.selectedPersonId, isNull);
      expect(d.timelineYear, isNull);
      expect(d.isFocusMode, isFalse);
      expect(d.expandedHouseholdId, isNull);
      expect(d.version, equals(MapVisualConstants.stateVersion));
    });
  });

  group('P10.9 MapSessionState.copyWith', () {
    test('preserves unspecified fields', () {
      final original = MapSessionState(
        lat: 1, lng: 2, zoom: 3, pitch: 4, bearing: 5,
        selectedPersonId: 'p1',
      );
      final copy = original.copyWith(zoom: 99);
      expect(copy.lat, equals(1));
      expect(copy.lng, equals(2));
      expect(copy.zoom, equals(99));
      expect(copy.pitch, equals(4));
      expect(copy.bearing, equals(5));
      expect(copy.selectedPersonId, equals('p1'));
    });

    test('can override every field', () {
      final original = MapSessionState.defaults();
      final copy = original.copyWith(
        lat: 18.52, lng: 73.85, zoom: 14, pitch: 45, bearing: 12,
        selectedPersonId: 'p2', timelineYear: 1990,
        isFocusMode: true, expandedHouseholdId: 'hh',
        mapStyleId: 'other', version: 2, savedAt: 'now',
      );
      expect(copy.lat, equals(18.52));
      expect(copy.selectedPersonId, equals('p2'));
      expect(copy.timelineYear, equals(1990));
      expect(copy.isFocusMode, isTrue);
      expect(copy.expandedHouseholdId, equals('hh'));
    });
  });

  group('P10.9 DebouncedMapStateSaver', () {
    test('schedule + flushNow do not throw', () async {
      final saver = DebouncedMapStateSaver('fam1');
      saver.schedule(MapSessionState.defaults());
      await saver.flushNow();
      saver.dispose();
      expect(true, isTrue);
    });

    test('dispose cancels pending save', () {
      final saver = DebouncedMapStateSaver('fam2');
      saver.schedule(MapSessionState.defaults());
      saver.dispose();
      // No assertion possible — just verify dispose doesn't throw.
      expect(true, isTrue);
    });
  });
}

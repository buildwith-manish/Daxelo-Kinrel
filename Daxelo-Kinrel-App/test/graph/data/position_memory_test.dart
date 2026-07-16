// test/graph/data/position_memory_test.dart
//
// Focused unit tests for the PositionMemory camera-state cache.
//
// Covers:
//   - A saved position is retrievable after flushing the debounce queue
//   - Loading a missing family returns null safely (no exception)
//   - clearPosition removes the stored entry
//   - hasPosition reflects persistence state correctly
//   - Saving twice for the same family replaces the pending entry
//     (this is the documented eviction strategy — only one pending
//      position per familyId is retained at a time)
//   - After dispose(), any method throws a StateError
//   - Stale / corrupt SharedPreferences data degrades safely to null
//   - CameraPosition serialisation round-trips through JSON

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/graph/data/position_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Reset the in-memory SharedPreferences store before every test.
    SharedPreferences.setMockInitialValues({});
  });

  group('PositionMemory', () {
    test('stored position is retrievable after flush', () async {
      final mem = PositionMemory(debounceDuration: const Duration(milliseconds: 10));

      await mem.savePosition(
        'family-1',
        panX: 100.0,
        panY: 200.0,
        zoomLevel: 1.5,
        focusedNodeId: 'member-42',
      );
      await mem.flush();

      final loaded = await mem.loadPosition('family-1');

      expect(loaded, isNotNull);
      expect(loaded!.panX, 100.0);
      expect(loaded.panY, 200.0);
      expect(loaded.zoomLevel, 1.5);
      expect(loaded.focusedNodeId, 'member-42');

      mem.dispose();
    });

    test('loadPosition returns null for missing family', () async {
      final mem = PositionMemory();
      final loaded = await mem.loadPosition('never-saved');
      expect(loaded, isNull);
      mem.dispose();
    });

    test('clearPosition removes a previously saved entry', () async {
      final mem = PositionMemory();

      await mem.savePosition(
        'family-2',
        panX: 10.0,
        panY: 20.0,
        zoomLevel: 1.0,
      );
      await mem.flush();

      expect(await mem.hasPosition('family-2'), isTrue);

      await mem.clearPosition('family-2');

      expect(await mem.hasPosition('family-2'), isFalse);
      expect(await mem.loadPosition('family-2'), isNull);

      mem.dispose();
    });

    test('hasPosition returns false before save, true after flush', () async {
      final mem = PositionMemory();

      expect(await mem.hasPosition('family-3'), isFalse);

      await mem.savePosition(
        'family-3',
        panX: 0.0,
        panY: 0.0,
        zoomLevel: 1.0,
      );
      // Without flush, the debounced save hasn't hit SharedPreferences yet.
      expect(await mem.hasPosition('family-3'), isFalse);

      await mem.flush();
      expect(await mem.hasPosition('family-3'), isTrue);

      mem.dispose();
    });

    test(
        'eviction strategy: saving twice for same family keeps only the latest',
        () async {
      // The pending-position map is keyed by familyId, so successive saves
      // for the same family replace (not append to) the pending entry.
      // This keeps memory bounded to one entry per family regardless of
      // how many pan/zoom events fire.
      final mem = PositionMemory(debounceDuration: const Duration(seconds: 30));

      await mem.savePosition('fam', panX: 1.0, panY: 1.0, zoomLevel: 1.0);
      await mem.savePosition('fam', panX: 2.0, panY: 2.0, zoomLevel: 2.0);
      await mem.savePosition('fam', panX: 3.0, panY: 3.0, zoomLevel: 3.0);

      await mem.flush();

      final loaded = await mem.loadPosition('fam');
      expect(loaded, isNotNull);
      expect(loaded!.panX, 3.0,
          reason: 'Most recent save must win after replacement');
      expect(loaded.zoomLevel, 3.0);

      mem.dispose();
    });

    test('after dispose(), calling savePosition throws StateError', () async {
      final mem = PositionMemory();
      mem.dispose();

      expect(
        () => mem.savePosition('x', panX: 0, panY: 0, zoomLevel: 1.0),
        throwsA(isA<StateError>()),
      );
      expect(
        () => mem.loadPosition('x'),
        throwsA(isA<StateError>()),
      );
      expect(
        () => mem.clearPosition('x'),
        throwsA(isA<StateError>()),
      );
    });

    test('stale / corrupt data degrades safely to null', () async {
      // Inject a garbage JSON string at the exact key the PositionMemory
      // would use, then verify loadPosition handles it gracefully.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('kinrel_camera_pos_corrupt', 'not valid json {');

      final mem = PositionMemory();
      final loaded = await mem.loadPosition('corrupt');

      expect(loaded, isNull,
          reason: 'Corrupt prefs must degrade to null, never throw');

      mem.dispose();
    });

    test('hasDataChanged is true when no data timestamp recorded', () async {
      final mem = PositionMemory();
      await mem.savePosition('fam', panX: 0, panY: 0, zoomLevel: 1.0);
      await mem.flush();

      // No data timestamp set → hasDataChanged should default to true
      // (assume data is newer than the saved position).
      expect(await mem.hasDataChanged('fam'), isTrue);

      mem.dispose();
    });

    test('recordDataTimestamp lets hasDataChanged detect freshness', () async {
      final mem = PositionMemory();

      // 1. Save position first.
      await mem.savePosition('fam', panX: 0, panY: 0, zoomLevel: 1.0);
      await mem.flush();

      // 2. Record a data timestamp AFTER the position save → data newer.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await mem.recordDataTimestamp('fam');

      expect(await mem.hasDataChanged('fam'), isTrue,
          reason: 'Data recorded after position must be flagged as changed');

      mem.dispose();
    });

    test('CameraPosition serialises and deserialises through JSON', () {
      final original = CameraPosition(
        panX: 12.5,
        panY: -34.0,
        zoomLevel: 2.25,
        focusedNodeId: 'n1',
        lastModified: DateTime.utc(2024, 1, 2, 3, 4, 5),
      );

      final json = original.toJson();
      // Round-trip through a string to make sure it's real JSON.
      final decoded = CameraPosition.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
      );

      expect(decoded.panX, original.panX);
      expect(decoded.panY, original.panY);
      expect(decoded.zoomLevel, original.zoomLevel);
      expect(decoded.focusedNodeId, original.focusedNodeId);
      expect(decoded, original);
    });

    test('CameraPosition equality ignores lastModified', () {
      final a = CameraPosition(
        panX: 1,
        panY: 2,
        zoomLevel: 3,
        focusedNodeId: 'x',
        lastModified: DateTime.utc(2024),
      );
      final b = CameraPosition(
        panX: 1,
        panY: 2,
        zoomLevel: 3,
        focusedNodeId: 'x',
        lastModified: DateTime.utc(2025),
      );

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });
}

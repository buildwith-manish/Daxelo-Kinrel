// test/features/family_map/p10_8_poi_polish_test.dart
//
// P10.8 — Unit tests for POI filtering, progressive loading, and the
// polish overlay.
//
// Verifies:
//   - applyPoiFilters patches POI layers with a subclass exclusion filter.
//   - applyPoiFilters returns the input unchanged on parse error.
//   - applyPoiFilters bumps minzoom on secondary POI layers.
//   - MapLoadPhase progresses in order.
//   - MapLoadState.message returns a sensible string per phase.
//   - MapPolishOverlay can be constructed without throwing.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/family_map/data/poi_filter.dart';
import 'package:kinrel/features/family_map/data/progressive_loading.dart';
import 'package:kinrel/features/family_map/widgets/map_polish_overlay.dart';

void main() {
  group('P10.8 applyPoiFilters', () {
    test('adds a subclass exclusion filter to POI layers', () {
      const styleJson = '''
{
  "version": 8,
  "layers": [
    {"id": "background", "type": "background"},
    {"id": "poi_r1", "type": "symbol", "source-layer": "poi",
      "filter": ["==", ["get", "rank"], 1]},
    {"id": "road", "type": "line", "source-layer": "road"}
  ]
}
''';
      final patched = applyPoiFilters(styleJson);
      final decoded = jsonDecode(patched) as Map<String, dynamic>;
      final layers = decoded['layers'] as List<dynamic>;
      final poi =
          layers.firstWhere(
                (l) => (l as Map<String, dynamic>)['id'] == 'poi_r1',
              )
              as Map<String, dynamic>;
      final filter = poi['filter'];
      // The filter should be wrapped in an 'all' with the exclusion.
      expect(filter, isA<Map<String, dynamic>>());
      // ignore: avoid_dynamic_calls
      expect(filter['all'], isNotNull);
    });

    test('returns input unchanged on parse error', () {
      const broken = '{not valid json';
      expect(applyPoiFilters(broken), equals(broken));
    });

    test('non-POI layers are not modified', () {
      const styleJson = '''
{
  "version": 8,
  "layers": [
    {"id": "road", "type": "line", "source-layer": "road",
      "filter": ["==", "class", "motorway"]}
  ]
}
''';
      final patched = applyPoiFilters(styleJson);
      final decoded = jsonDecode(patched) as Map<String, dynamic>;
      final layers = decoded['layers'] as List<dynamic>;
      final road =
          layers.firstWhere((l) => (l as Map<String, dynamic>)['id'] == 'road')
              as Map<String, dynamic>;
      // Original filter preserved.
      expect(road['filter'], equals(['==', 'class', 'motorway']));
    });

    test('secondary POI layers get minzoom bumped', () {
      const styleJson = '''
{
  "version": 8,
  "layers": [
    {"id": "poi_r20", "type": "symbol", "source-layer": "poi"},
    {"id": "poi_r1", "type": "symbol", "source-layer": "poi"}
  ]
}
''';
      final patched = applyPoiFilters(styleJson);
      final decoded = jsonDecode(patched) as Map<String, dynamic>;
      final layers = decoded['layers'] as List<dynamic>;
      final r20 =
          layers.firstWhere(
                (l) => (l as Map<String, dynamic>)['id'] == 'poi_r20',
              )
              as Map<String, dynamic>;
      final r1 =
          layers.firstWhere(
                (l) => (l as Map<String, dynamic>)['id'] == 'poi_r1',
              )
              as Map<String, dynamic>;
      expect(r20['minzoom'], equals(14));
      expect(r1['minzoom'], isNull); // primary POI keeps its default
    });
  });

  group('P10.8 MapLoadPhase progression', () {
    test('next returns the next phase', () {
      expect(MapLoadPhase.skeleton.next, equals(MapLoadPhase.cachedViewport));
      expect(MapLoadPhase.cachedViewport.next, equals(MapLoadPhase.tiles));
      expect(MapLoadPhase.animations.next, equals(MapLoadPhase.complete));
    });

    test('complete.next is null', () {
      expect(MapLoadPhase.complete.next, isNull);
    });

    test('isAtLeast returns true for self and later', () {
      expect(MapLoadPhase.tiles.isAtLeast(MapLoadPhase.tiles), isTrue);
      expect(MapLoadPhase.markers.isAtLeast(MapLoadPhase.tiles), isTrue);
      expect(MapLoadPhase.tiles.isAtLeast(MapLoadPhase.markers), isFalse);
    });
  });

  group('P10.8 MapLoadState.message', () {
    test('skeleton → Loading family map…', () {
      expect(const MapLoadState().message, contains('Loading family map'));
    });
    test('complete → empty', () {
      expect(
        const MapLoadState(phase: MapLoadPhase.complete).message,
        equals(''),
      );
    });
    test('offline + skeleton → Offline indicator', () {
      const state = MapLoadState(isOffline: true);
      expect(state.message, contains('Offline'));
    });
  });

  group('P10.8 MapPolishOverlay', () {
    testWidgets('can be constructed without throwing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: MapPolishOverlay())),
      );
      expect(find.byType(MapPolishOverlay), findsOneWidget);
    });
  });
}

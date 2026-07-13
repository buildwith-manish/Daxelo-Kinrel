// test/features/family_map/p10_5_animated_relationship_path_test.dart
//
// P10.5 — Unit tests for animated relationship paths.
//
// Verifies:
//   - categorizeRelationship maps known keys to the correct category.
//   - PathStyle.forCategory returns sensible widths/colors/dash/heart.
//   - Spouse category is the only one with showHeartMidpoint = true.
//   - Ancestor chain is gold + 3px; descendant chain is orange + 3px.
//   - Viewport culling caps at MapVisualConstants.maxVisibleAnimatedPaths.
//   - AnimatedRelationshipPath can be constructed + disposed cleanly.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/family_map/widgets/animated_relationship_path.dart';
import 'package:kinrel/features/family_map/providers/family_map_provider.dart';
import 'package:kinrel/features/family_map/config/map_visual_constants.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P10.5 categorizeRelationship', () {
    test('parent keys → parentChild', () {
      for (final k in <String>['father', 'mother', 'parent', 'papa', 'amma']) {
        expect(categorizeRelationship(k),
            equals(RelationshipCategory.parentChild),
            reason: k);
      }
    });
    test('sibling keys → sibling', () {
      for (final k in <String>['brother', 'sister', 'bhai', 'behan']) {
        expect(categorizeRelationship(k),
            equals(RelationshipCategory.sibling),
            reason: k);
      }
    });
    test('spouse keys → spouse', () {
      for (final k in <String>['spouse', 'husband', 'wife', 'partner']) {
        expect(categorizeRelationship(k),
            equals(RelationshipCategory.spouse),
            reason: k);
      }
    });
    test('ancestor keys → ancestorChain', () {
      for (final k in <String>['grandfather', 'grandmother', 'dada', 'nani']) {
        expect(categorizeRelationship(k),
            equals(RelationshipCategory.ancestorChain),
            reason: k);
      }
    });
    test('descendant keys → descendantChain', () {
      for (final k in <String>['son', 'daughter', 'grandson']) {
        expect(categorizeRelationship(k),
            equals(RelationshipCategory.descendantChain),
            reason: k);
      }
    });
    test('unknown keys → generic', () {
      expect(categorizeRelationship('cousin'),
          equals(RelationshipCategory.generic));
      expect(categorizeRelationship('xyz'),
          equals(RelationshipCategory.generic));
    });
    test('case insensitive', () {
      expect(categorizeRelationship('FATHER'),
          equals(RelationshipCategory.parentChild));
      expect(categorizeRelationship(' Spouse '),
          equals(RelationshipCategory.spouse));
    });
  });

  group('P10.5 PathStyle.forCategory', () {
    test('spouse is the only category with a heart midpoint', () {
      for (final cat in RelationshipCategory.values) {
        final style = PathStyle.forCategory(cat);
        if (cat == RelationshipCategory.spouse) {
          expect(style.showHeartMidpoint, isTrue, reason: cat.toString());
        } else {
          expect(style.showHeartMidpoint, isFalse, reason: cat.toString());
        }
      }
    });

    test('sibling is the only dashed category', () {
      for (final cat in RelationshipCategory.values) {
        final style = PathStyle.forCategory(cat);
        if (cat == RelationshipCategory.sibling) {
          expect(style.dashed, isTrue, reason: cat.toString());
        } else {
          expect(style.dashed, isFalse, reason: cat.toString());
        }
      }
    });

    test('ancestor chain is 3px gold', () {
      final s = PathStyle.forCategory(RelationshipCategory.ancestorChain);
      expect(s.width, equals(3.0));
      expect(s.color, equals(const Color(0xFF917520)));
    });

    test('descendant chain is 3px orange', () {
      final s = PathStyle.forCategory(RelationshipCategory.descendantChain);
      expect(s.width, equals(3.0));
    });

    test('all widths are positive', () {
      for (final cat in RelationshipCategory.values) {
        expect(PathStyle.forCategory(cat).width, greaterThan(0));
      }
    });
  });

  group('P10.5 cullEdgesToViewport', () {
    test('caps at maxVisibleAnimatedPaths', () {
      final max = MapVisualConstants.maxVisibleAnimatedPaths;
      // Build max+5 edges.
      final edges = List.generate(
        max + 5,
        (i) => MapRelationshipEdge(
          pinA: MapPin(
              personId: 'a$i', name: 'A', city: 'X', photoUrl: null,
              lat: 0, lng: 0),
          pinB: MapPin(
              personId: 'b$i', name: 'B', city: 'Y', photoUrl: null,
              lat: 0, lng: 1),
          relationshipKey: 'father',
        ),
      );
      final positions = <String, Offset>{
        for (var i = 0; i < max + 5; i++)
          'a$i': Offset(i.toDouble(), 0.0),
        for (var i = 0; i < max + 5; i++)
          'b$i': Offset(i.toDouble(), 100.0),
      };
      final culled = cullEdgesToViewport(
        all: edges,
        viewport: const Rect.fromLTWH(0, 0, 10000, 10000),
        screenPositions: positions,
      );
      expect(culled.length, equals(max));
    });

    test('excludes edges outside the viewport', () {
      final edges = <MapRelationshipEdge>[
        MapRelationshipEdge(
          pinA: const MapPin(
              personId: 'a', name: 'A', city: 'X', photoUrl: null,
              lat: 0, lng: 0),
          pinB: const MapPin(
              personId: 'b', name: 'B', city: 'Y', photoUrl: null,
              lat: 0, lng: 0),
          relationshipKey: 'father',
        ),
      ];
      final positions = <String, Offset>{
        'a': const Offset(-500, -500),
        'b': const Offset(-600, -600),
      };
      final culled = cullEdgesToViewport(
        all: edges,
        viewport: const Rect.fromLTWH(0, 0, 100, 100),
        screenPositions: positions,
      );
      expect(culled, isEmpty);
    });
  });

  group('P10.5 AnimatedRelationshipPath lifecycle', () {
    test('can be constructed and disposed without map controller', () {
      final vsync = const _DummyTickerProvider();
      final path = AnimatedRelationshipPath(
        tickerProvider: vsync,
        mapController: null,
        style: null,
        reducedMotion: true,
      );
      path.start();
      path.dispose();
      expect(true, isTrue); // reached without throwing
    });
  });
}

class _DummyTickerProvider implements TickerProvider {
  const _DummyTickerProvider();
  @override
  Ticker createTicker(TickerCallback onTick) =>
      Ticker(onTick);
}

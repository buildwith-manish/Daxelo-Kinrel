// test/features/family_map/p10_1_map_visual_constants_test.dart
//
// P10.1 — Unit tests for MapVisualConstants.
//
// Verifies that every constant referenced by subsequent Phase 10 features
// actually exists, has a sensible value, and that hex strings stay in sync
// with their Color counterparts (Rule 14: single source of truth).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/family_map/config/map_visual_constants.dart';

void main() {
  group('P10.1 MapVisualConstants — palette', () {
    test('background / land / water are distinct dark colors', () {
      expect(MapVisualConstants.background, isNot(equals(MapVisualConstants.land)));
      expect(MapVisualConstants.land, isNot(equals(MapVisualConstants.water)));
      expect(MapVisualConstants.background, isNot(equals(MapVisualConstants.water)));
    });

    test('building colors cover all 9 PlaceTypes', () {
      // Every PlaceType has a dedicated building color constant.
      expect(MapVisualConstants.buildingCurrentHome, isA<Color>());
      expect(MapVisualConstants.buildingChildhoodHome, isA<Color>());
      expect(MapVisualConstants.buildingAncestralHome, isA<Color>());
      expect(MapVisualConstants.buildingBirthplace, isA<Color>());
      expect(MapVisualConstants.buildingWedding, isA<Color>());
      expect(MapVisualConstants.buildingMemorial, isA<Color>());
      expect(MapVisualConstants.buildingFamilyBusiness, isA<Color>());
      expect(MapVisualConstants.buildingSchool, isA<Color>());
      expect(MapVisualConstants.buildingImportantPlace, isA<Color>());
    });
  });

  group('P10.1 MapVisualConstants — hex strings stay in sync', () {
    // Helper: convert a Color to the '#RRGGBB' format used by the JSON.
    String colorToHex(Color c) =>
        '#${c.value.toRadixString(16).toUpperCase().padLeft(8, '0').substring(2)}';

    test('background hex matches Color', () {
      expect(MapVisualConstants.hexBackground.toUpperCase(),
          colorToHex(MapVisualConstants.background));
    });
    test('land hex matches Color', () {
      expect(MapVisualConstants.hexLand.toUpperCase(),
          colorToHex(MapVisualConstants.land));
    });
    test('water hex matches Color', () {
      expect(MapVisualConstants.hexWater.toUpperCase(),
          colorToHex(MapVisualConstants.water));
    });
    test('building normal hex matches Color', () {
      expect(MapVisualConstants.hexBuildingNormal.toUpperCase(),
          colorToHex(MapVisualConstants.buildingNormal));
    });
  });

  group('P10.1 MapVisualConstants — sizes & durations are positive', () {
    test('marker sizes', () {
      expect(MapVisualConstants.markerNormalSize, greaterThan(0));
      expect(MapVisualConstants.markerSelectedSize,
          greaterThan(MapVisualConstants.markerNormalSize));
      expect(MapVisualConstants.markerRingWidthNormal, greaterThan(0));
      expect(MapVisualConstants.markerRingWidthSelected,
          greaterThan(MapVisualConstants.markerRingWidthNormal));
    });

    test('cluster sizes', () {
      expect(MapVisualConstants.clusterMarkerSize, greaterThan(0));
      expect(MapVisualConstants.clusterStackOffset, greaterThan(0));
      expect(MapVisualConstants.clusterBadgeSize, greaterThan(0));
    });

    test('durations are non-zero', () {
      expect(MapVisualConstants.focusTransition.inMilliseconds, greaterThan(0));
      expect(MapVisualConstants.cinematicEntrance.inMilliseconds,
          greaterThan(0));
      expect(MapVisualConstants.relationshipFlowCycle.inSeconds,
          greaterThan(0));
      expect(MapVisualConstants.clusterExpand.inMilliseconds, greaterThan(0));
      expect(MapVisualConstants.timelineCrossfade.inMilliseconds,
          greaterThan(0));
    });

    test('polish opacities are between 0 and 1', () {
      expect(MapVisualConstants.vignetteOpacity, inInclusiveRange(0.0, 1.0));
      expect(MapVisualConstants.fogOpacity, inInclusiveRange(0.0, 1.0));
      expect(MapVisualConstants.ambientWarmthOpacity,
          inInclusiveRange(0.0, 1.0));
    });

    test('zoom thresholds are sensible', () {
      expect(MapVisualConstants.buildingExtrusionMinZoom, greaterThan(0));
      expect(MapVisualConstants.clusterMaxZoom, greaterThan(0));
      expect(MapVisualConstants.secondaryPoiMinZoom, greaterThan(0));
      expect(MapVisualConstants.focusMinZoom, greaterThan(0));
      expect(MapVisualConstants.focusPitch, inInclusiveRange(0.0, 60.0));
    });

    test('focus opacity bounds', () {
      expect(MapVisualConstants.nonFocusOpacity, inInclusiveRange(0.0, 1.0));
      expect(MapVisualConstants.focusOpacity, inInclusiveRange(0.0, 1.0));
      expect(MapVisualConstants.nonFocusOpacity,
          lessThan(MapVisualConstants.focusOpacity));
    });

    test('performance constants are positive', () {
      expect(MapVisualConstants.maxVisibleAnimatedPaths, greaterThan(0));
      expect(MapVisualConstants.clusterRadius, greaterThan(0));
      expect(MapVisualConstants.householdEpsilon, greaterThan(0));
    });

    test('timeline constants', () {
      expect(MapVisualConstants.timelineMinYear, greaterThan(1800));
      expect(MapVisualConstants.timelineMinYear, lessThan(2026));
      expect(MapVisualConstants.timelinePlayInterval.inSeconds, greaterThan(0));
    });

    test('state persistence constants', () {
      expect(MapVisualConstants.stateSaveDebounce.inMilliseconds,
          greaterThan(0));
      expect(MapVisualConstants.stateKeyPrefix, isNotEmpty);
      expect(MapVisualConstants.stateVersion, greaterThan(0));
    });
  });
}

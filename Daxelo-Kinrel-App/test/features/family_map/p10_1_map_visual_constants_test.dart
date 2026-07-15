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

    test('building colors cover all 12 PlaceTypes', () {
      // Every PlaceType has a dedicated building color constant.
      // P11.x: vacationHome, familyTemple, grandparentsHome added per master prompt.
      expect(MapVisualConstants.buildingCurrentHome, isA<Color>());
      expect(MapVisualConstants.buildingChildhoodHome, isA<Color>());
      expect(MapVisualConstants.buildingAncestralHome, isA<Color>());
      expect(MapVisualConstants.buildingBirthplace, isA<Color>());
      expect(MapVisualConstants.buildingWedding, isA<Color>());
      expect(MapVisualConstants.buildingMemorial, isA<Color>());
      expect(MapVisualConstants.buildingFamilyBusiness, isA<Color>());
      expect(MapVisualConstants.buildingSchool, isA<Color>());
      expect(MapVisualConstants.buildingVacationHome, isA<Color>());
      expect(MapVisualConstants.buildingFamilyTemple, isA<Color>());
      expect(MapVisualConstants.buildingGrandparentsHome, isA<Color>());
      expect(MapVisualConstants.buildingImportantPlace, isA<Color>());
    });

    test('P11.x — atmospheric perspective constants exist', () {
      expect(MapVisualConstants.atmosphericPerspectivePitchThreshold, equals(10.0));
      expect(MapVisualConstants.atmosphericPerspectiveMaxOpacity, equals(0.12));
    });

    test('P11.x — building roof min zoom is 17', () {
      expect(MapVisualConstants.buildingRoofMinZoom, equals(17.0));
    });

    test('P11.x — wedding glow cycle is 4 seconds', () {
      expect(MapVisualConstants.weddingGlowCycle, equals(const Duration(seconds: 4)));
      expect(MapVisualConstants.weddingGlowMin, lessThan(MapVisualConstants.weddingGlowMax));
    });

    test('P11.x — memorial flicker cycle is 2.4 seconds', () {
      expect(MapVisualConstants.memorialFlickerCycle,
          equals(const Duration(milliseconds: 2400)));
      expect(MapVisualConstants.memorialFlickerMin,
          lessThan(MapVisualConstants.memorialFlickerMax));
    });

    test('P11.x — hillshade constants exist', () {
      expect(MapVisualConstants.hexHillshadeShadow, isA<String>());
      expect(MapVisualConstants.hexHillshadeHighlight, isA<String>());
      expect(MapVisualConstants.hexHillshadeAccent, isA<String>());
      expect(MapVisualConstants.hillshadeExaggeration, equals(0.25));
      expect(MapVisualConstants.hillshadeMaxZoom, equals(14.0));
    });

    test('P11.x — WCAG AA label halo is 2px', () {
      expect(MapVisualConstants.labelHaloWidth, equals(2.0));
      expect(MapVisualConstants.hexLabelHaloColor, equals('#0D0D0D'));
    });

    test('P12 — vignette opacity is 0.45 (ultra-premium cinematic)', () {
      expect(MapVisualConstants.vignetteOpacity, equals(0.45));
    });

    test('P12.1 — fog opacity is 0.07 (more depth perception)', () {
      expect(MapVisualConstants.fogOpacity, equals(0.07));
    });

    test('P12.1 — ambient warmth opacity is 0.05 (stronger Kinrel orange)', () {
      expect(MapVisualConstants.ambientWarmthOpacity, equals(0.05));
    });

    test('P12.1 — generic 3D building colors exist (ultra-premium gradient)', () {
      expect(MapVisualConstants.buildingNormal, isA<Color>());
      expect(MapVisualConstants.buildingNormalMid, isA<Color>());
      expect(MapVisualConstants.buildingNormalTop, isA<Color>());
      expect(MapVisualConstants.buildingNormalTall, isA<Color>());
      expect(MapVisualConstants.buildingNormalEdge, isA<Color>());
    });

    test('P12.1 — avatar marker sizes are prominent (Snapchat-style)', () {
      expect(MapVisualConstants.markerNormalSize, equals(44.0));
      expect(MapVisualConstants.markerSelectedSize, equals(60.0));
      expect(MapVisualConstants.markerGlowBlurNormal, equals(8.0));
      expect(MapVisualConstants.markerGlowBlurSelected, equals(16.0));
    });

    test('P12.4 — building extrusion min zoom is 13.0 (documentation-only, style JSON is authoritative)', () {
      expect(MapVisualConstants.buildingExtrusionMinZoom, equals(13.0));
    });

    test('P12.4 BUG FIX — focusMinZoom is 16.5 (3D buildings clearly visible)', () {
      // BUG: focusMinZoom was 13.0 — at zoom 13, 3D buildings had barely
      // started fading in. Tapping any family member pin parked the camera
      // at a zoom where buildings were barely visible. The only path to
      // a clear 3D view was the hardcoded _flyToBengaluru3D() debug button.
      // FIX: raised to 16.5 so every pin tap shows premium 3D worldwide.
      expect(MapVisualConstants.focusMinZoom, equals(16.5),
          reason: 'focusMinZoom must be 16.5 so 3D buildings are clearly '
                  'visible when tapping any family member pin worldwide');
    });

    test('P12.1 — ancestral home color is brighter gold #B8901F', () {
      expect(MapVisualConstants.buildingAncestralHome, equals(const Color(0xFFB8901F)));
    });

    test('P12.1 — family business color is brighter #D85720', () {
      expect(MapVisualConstants.buildingFamilyBusiness, equals(const Color(0xFFD85720)));
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

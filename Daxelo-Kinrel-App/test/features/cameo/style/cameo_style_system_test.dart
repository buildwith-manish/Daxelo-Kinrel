// test/features/cameo/style/cameo_style_system_test.dart
//
// Tests for the KINREL_CAMEO_STYLE_SYSTEM.
//
// These tests verify the deterministic invariants that make a Cameo
// "unmistakably Kinrel":
//   • Every lighting preset carries the ivory key + ember rim signature.
//   • No responsive preset allows stretching, cropping, or viewport forcing.
//   • Minor age bands reject forbidden traits.
//   • Memorial defaults are always softLight (never candleGlow).
//   • Live 3D is allowed only on Studio / Profile hero / Journey.
//   • Animation amplitudes are within Kinrel bounds (no bouncing).
//   • Camera FOV is in [24, 35] degrees.
//   • Scene density is bounded (face width in [0.28, 0.65], no foreground).
//   • The master resolver (CameoStyleSystem.resolve) produces a
//     complete ResolvedCameoStyle for every surface × age band combination.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/cameo/cameo.dart';

void main() {
  group('CameoQualityGates', () {
    test('verifyAll passes (the master invariant)', () {
      final report = CameoQualityGates.verifyAll();
      expect(report.allPassed, true, reason: report.toString());
    });

    test('signature pair present on every lighting preset', () {
      final result = CameoQualityGates.verifySignaturePairPresent();
      expect(result.passed, true, reason: result.message);
    });

    test('responsive safety invariants hold on every preset', () {
      final result = CameoQualityGates.verifyResponsiveSafetyInvariants();
      expect(result.passed, true, reason: result.message);
      expect(CameoResponsiveLibrary.allPresetsSafe, true);
    });

    test('child safety rules reject forbidden traits for minors', () {
      final result = CameoQualityGates.verifyChildSafetyRules();
      expect(result.passed, true, reason: result.message);

      // Spot-check: facial_hair_beard forbidden for child.
      expect(
        CameoChildSafetyRules.isTraitAllowedForAgeBand(
            'facial_hair_beard', CameoAgeBand.child),
        false,
      );
      // And allowed for adult.
      expect(
        CameoChildSafetyRules.isTraitAllowedForAgeBand(
            'facial_hair_beard', CameoAgeBand.adult),
        true,
      );
    });

    test('memorial defaults are always softLight', () {
      final result = CameoQualityGates.verifyMemorialDefaults();
      expect(result.passed, true, reason: result.message);

      for (final band in CameoAgeBand.values) {
        expect(
          CameoChildSafetyRules.defaultMemorialAtmosphere(band),
          'softLight',
          reason: 'Age band $band should default to softLight',
        );
      }
    });

    test('no banned live-3D surfaces (Map/Graph/Chat/Timeline are PNG)', () {
      final result = CameoQualityGates.verifyNoBannedSurfaces();
      expect(result.passed, true, reason: result.message);
    });

    test('animation amplitudes within Kinrel bounds', () {
      final result = CameoQualityGates.verifyAnimationWithinBounds();
      expect(result.passed, true, reason: result.message);
    });

    test('camera frames use valid FOV and zoom ranges', () {
      final result = CameoQualityGates.verifyCameraFramesValid();
      expect(result.passed, true, reason: result.message);
    });

    test('scene density bounded (no foreground clutter)', () {
      final result = CameoQualityGates.verifySceneDensityBounded();
      expect(result.passed, true, reason: result.message);
    });
  });

  group('CameoStyleSystem.resolve', () {
    // Iterate every surface × every age band to verify the resolver
    // produces a complete, valid ResolvedCameoStyle for all combos.
    const surfaces = <String>[
      'studio', 'profile_hero', 'map_marker', 'graph_node',
      'chat_avatar', 'journey', 'timeline_card',
    ];
    const bands = CameoAgeBand.values;

    for (final surface in surfaces) {
      for (final band in bands) {
        final testName = 'resolves $surface × ${band.semanticLabel}';
        test(testName, () {
          final resolved = CameoStyleSystem.resolve(
            surfaceId: surface,
            personName: 'Test Person',
            ageBand: band,
            skinToneIndex: 5,
            breakpoint: CameoBreakpoint.desktop,
            containerSize: const Size(400, 400),
          );

          // Identity fields.
          expect(resolved.surfaceId, surface);
          expect(resolved.ageBand, band);
          expect(resolved.personName, 'Test Person');

          // Effective render size is finite and positive.
          expect(resolved.effectiveRenderSize.width, greaterThan(0));
          expect(resolved.effectiveRenderSize.height, greaterThan(0));
          expect(
            resolved.effectiveRenderSize.width.isFinite,
            true,
          );
          expect(
            resolved.effectiveRenderSize.height.isFinite,
            true,
          );

          // Lighting is non-null and carries the signature.
          expect(resolved.lighting.hasKinrelSignature, true);

          // Semantic label contains the person name.
          expect(resolved.semanticLabel.contains('Test Person'), true);
        });
      }
    }

    test('deceased person resolves to memorial lighting', () {
      final resolved = CameoStyleSystem.resolve(
        surfaceId: 'profile_hero',
        personName: 'Aaji',
        ageBand: CameoAgeBand.elder,
        skinToneIndex: 7,
        isDeceased: true,
        memorialAtmosphere: 'softLight',
        breakpoint: CameoBreakpoint.mobile,
        containerSize: const Size(220, 220),
      );
      expect(resolved.isDeceased, true);
      expect(resolved.lighting.id, 'memorial_soft');
      expect(resolved.semanticLabel.contains('in memoriam'), true);
    });

    test('deceased person with candleGlow resolves to memorial candle', () {
      final resolved = CameoStyleSystem.resolve(
        surfaceId: 'profile_hero',
        personName: 'Aaji',
        ageBand: CameoAgeBand.elder,
        skinToneIndex: 7,
        isDeceased: true,
        memorialAtmosphere: 'candleGlow',
        breakpoint: CameoBreakpoint.mobile,
        containerSize: const Size(220, 220),
      );
      expect(resolved.lighting.id, 'memorial_candle');
    });

    test('reduced motion disables all animation', () {
      final resolved = CameoStyleSystem.resolve(
        surfaceId: 'studio',
        personName: 'Test',
        ageBand: CameoAgeBand.adult,
        skinToneIndex: 5,
        reduceMotion: true,
        breakpoint: CameoBreakpoint.desktop,
        containerSize: const Size(400, 400),
      );
      expect(resolved.animation.allowBreathing, false);
      expect(resolved.animation.allowBlink, false);
      expect(resolved.animation.allowSaccades, false);
      expect(resolved.animation.allowHeadSway, false);
      expect(resolved.animation.allowCameraIdleDrift, false);
      expect(resolved.animation.breathingAmplitudePx, 0);
      expect(resolved.animation.stateTransitionDuration, Duration.zero);
    });

    test('low-tier device disables camera idle drift and saccades', () {
      final resolved = CameoStyleSystem.resolve(
        surfaceId: 'studio',
        personName: 'Test',
        ageBand: CameoAgeBand.adult,
        skinToneIndex: 5,
        isLowTierDevice: true,
        breakpoint: CameoBreakpoint.mobile,
        containerSize: const Size(380, 380),
      );
      expect(resolved.animation.allowCameraIdleDrift, false);
      expect(resolved.animation.allowSaccades, false);
      // Breathing and blink stay (they're cheap and they're the soul).
      expect(resolved.animation.allowBreathing, true);
      expect(resolved.animation.allowBlink, true);
    });

    test('elder skin is rougher than young-adult skin', () {
      final youngAdult = CameoStyleSystem.resolve(
        surfaceId: 'studio',
        personName: 'Test',
        ageBand: CameoAgeBand.youngAdult,
        skinToneIndex: 5,
        breakpoint: CameoBreakpoint.desktop,
        containerSize: const Size(400, 400),
      );
      final elder = CameoStyleSystem.resolve(
        surfaceId: 'studio',
        personName: 'Test',
        ageBand: CameoAgeBand.elder,
        skinToneIndex: 5,
        breakpoint: CameoBreakpoint.desktop,
        containerSize: const Size(400, 400),
      );
      expect(
        elder.skinMaterial.roughness,
        greaterThan(youngAdult.skinMaterial.roughness),
      );
      expect(
        elder.skinMaterial.subsurfaceStrength,
        lessThan(youngAdult.skinMaterial.subsurfaceStrength),
      );
    });

    test('responsive: effective size never exceeds breakpoint max', () {
      final resolved = CameoStyleSystem.resolve(
        surfaceId: 'profile_hero',
        personName: 'Test',
        ageBand: CameoAgeBand.adult,
        skinToneIndex: 5,
        breakpoint: CameoBreakpoint.mobile,
        containerSize: const Size(2000, 2000),
      );
      // Mobile max for profile_hero is (220, 220).
      expect(resolved.effectiveRenderSize.width, lessThanOrEqualTo(220));
      expect(resolved.effectiveRenderSize.height, lessThanOrEqualTo(220));
    });

    test('responsive: aspect ratio is preserved', () {
      final resolved = CameoStyleSystem.resolve(
        surfaceId: 'profile_hero',
        personName: 'Test',
        ageBand: CameoAgeBand.adult,
        skinToneIndex: 5,
        breakpoint: CameoBreakpoint.desktop,
        containerSize: const Size(400, 400),
      );
      final ratio = resolved.effectiveRenderSize.width /
          resolved.effectiveRenderSize.height;
      final expected = resolved.responsive.aspectRatio;
      expect((ratio - expected).abs(), lessThan(0.01));
    });
  });

  group('CameoColorPalette', () {
    test('skinTone(1) returns lightest, skinTone(10) returns darkest', () {
      final t1 = CameoColorPalette.skinTone(1);
      final t10 = CameoColorPalette.skinTone(10);
      // Tone 10 should be darker (lower luminance) than tone 1.
      expect(_luminance(t10), lessThan(_luminance(t1)));
    });

    test('skinTone clamps out-of-range indices', () {
      expect(CameoColorPalette.skinTone(0), CameoColorPalette.skinTone(1));
      expect(CameoColorPalette.skinTone(11), CameoColorPalette.skinTone(10));
    });

    test('isSignatureColor recognizes ivory key and ember rim', () {
      expect(
        CameoColorPalette.isSignatureColor(CameoColorPalette.keyLightIvory),
        true,
      );
      expect(
        CameoColorPalette.isSignatureColor(CameoColorPalette.rimLightEmber),
        true,
      );
      expect(
        CameoColorPalette.isSignatureColor(const Color(0xFF000000)),
        false,
      );
    });
  });

  group('CameoExpressionCatalog', () {
    test('all expressions have valid morph weights in [0, 1]', () {
      for (final e in CameoExpressionCatalog.all) {
        for (final entry in e.morphWeights.entries) {
          expect(
            entry.value,
            inInclusiveRange(0.0, 1.0),
            reason: '${e.id}.${entry.key} = ${entry.value}',
          );
        }
      }
    });

    test('defaultForEvent returns sensible expression', () {
      expect(
        CameoExpressionCatalog.defaultForEvent('birthday').id,
        'gentle_smile',
      );
      expect(
        CameoExpressionCatalog.defaultForEvent('memorial').id,
        'reverent',
      );
      expect(
        CameoExpressionCatalog.defaultForEvent('wedding').id,
        'tender',
      );
      expect(
        CameoExpressionCatalog.defaultForEvent(null).id,
        'slight_smile',
      );
    });

    test('byId returns neutral for unknown id', () {
      expect(
        CameoExpressionCatalog.byId('nonexistent').id,
        'neutral',
      );
    });
  });

  group('CameoPoseCatalog', () {
    test('defaultForAgeBand returns dignified stooped for elder', () {
      expect(
        CameoPoseCatalog.defaultForAgeBand(CameoAgeBand.elder).id,
        'dignified_stooped',
      );
    });

    test('defaultForAgeBand returns centered for baby', () {
      expect(
        CameoPoseCatalog.defaultForAgeBand(CameoAgeBand.baby).id,
        'centered',
      );
    });

    test('byId returns threeQuarter for unknown id', () {
      expect(CameoPoseCatalog.byId('nonexistent').id, 'three_quarter');
    });
  });

  group('CameoCameraPresets', () {
    test('studio allows full orbit and zoom', () {
      final c = CameoCameraPresets.studio;
      expect(c.allowOrbit, true);
      expect(c.allowZoom, true);
    });

    test('map marker forbids orbit and zoom', () {
      final c = CameoCameraPresets.mapMarker;
      expect(c.allowOrbit, false);
      expect(c.allowZoom, false);
    });

    test('clampYaw respects range', () {
      final c = CameoCameraPresets.profileHero;
      expect(c.clampYaw(100), 35);
      expect(c.clampYaw(-100), -35);
      expect(c.clampYaw(10), 10);
    });
  });

  group('CameoAnimationPresets', () {
    test('derived surfaces have all motion disabled', () {
      const derivedIds = <String>[
        'map_marker', 'graph_node', 'chat_avatar', 'timeline_card',
      ];
      for (final id in derivedIds) {
        final a = CameoAnimationPresets.byId(id);
        expect(a.allowBreathing, false, reason: id);
        expect(a.allowBlink, false, reason: id);
        expect(a.allowSaccades, false, reason: id);
        expect(a.allowHeadSway, false, reason: id);
        expect(a.allowCameraIdleDrift, false, reason: id);
      }
    });

    test('resolve with reduceMotion returns all motion disabled', () {
      final a = CameoAnimationPresets.resolve(
        surfaceId: 'studio',
        reduceMotion: true,
      );
      expect(a.allowBreathing, false);
      expect(a.allowBlink, false);
    });

    test('resolve with low tier disables saccades and camera drift', () {
      final a = CameoAnimationPresets.resolve(
        surfaceId: 'studio',
        reduceMotion: false,
        isLowTierDevice: true,
      );
      expect(a.allowSaccades, false);
      expect(a.allowCameraIdleDrift, false);
      expect(a.allowBreathing, true);
    });
  });
}

double _luminance(Color c) {
  return 0.299 * c.red + 0.587 * c.green + 0.114 * c.blue;
}

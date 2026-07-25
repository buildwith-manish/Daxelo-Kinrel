// test/features/cameo/data/cameo_asset_registry_test.dart
//
// Unit tests for the modular asset path resolver. These run in CI as
// part of the dart-asset-registry job. They verify:
//   1. Layer stack ordering matches the documented contract
//   2. Path constants point to the right subdirectories
//   3. Age band → age stage mapping handles legacy 8-band enum
//   4. A/B/C/D variant resolution picks the right base-face PNG

import 'package:flutter_test/flutter_test.dart';

import 'package:kinrel/features/cameo/data/cameo_asset_registry.dart';
import 'package:kinrel/features/cameo/data/cameo_definition.dart';
import 'package:kinrel/features/cameo/style/cameo_shape_language.dart';

void main() {
  group('CameoAssetRegistry', () {
    group('path constants', () {
      test('asset root points to Flutter assets dir', () {
        expect(kCameoAssetRoot, 'assets/kinrel-cameo');
      });

      test('chroma-key background color is RGB(220, 190, 158)', () {
        expect(CameoAssetRegistry.kBackgroundRGB, 0xDCBE9E);
      });

      test('chroma-key tolerance is 40.0', () {
        expect(CameoAssetRegistry.kBackgroundTolerance, 40.0);
      });
    });

    group('age stage mapping', () {
      test('baby band maps to baby stage', () {
        expect(
          CameoAssetRegistry.stageFromBand(CameoAgeBand.baby),
          CameoAgeStage.baby,
        );
      });

      test('elder band maps to senior stage', () {
        expect(
          CameoAssetRegistry.stageFromBand(CameoAgeBand.elder),
          CameoAgeStage.senior,
        );
      });

      test('teenager band maps to teen stage', () {
        expect(
          CameoAssetRegistry.stageFromBand(CameoAgeBand.teenager),
          CameoAgeStage.teen,
        );
      });

      test('middleAged band maps to middleAged stage', () {
        expect(
          CameoAssetRegistry.stageFromBand(CameoAgeBand.middleAged),
          CameoAgeStage.middleAged,
        );
      });
    });

    group('layer stack resolution', () {
      late CameoDefinition def;

      setUp(() {
        def = const CameoDefinition(
          id: 'test',
          personId: 'p1',
          familyId: 'f1',
          schemaVersion: 2,
          gender: CameoGender.female,
          ageBandIndex: 3, // youngAdult (0=baby, 1=child, 2=teen, 3=ya)
          skinToneIndex: 3,
          hairStyleId: 'wavy_shoulder_female',
        );
      });

      test('stack includes skin-tone and base-face as first layers', () {
        final stack = CameoAssetRegistry.resolveLayerStack(def);
        expect(stack, isNotEmpty);
        expect(stack.first.layer, CameoLayer.skinTone);
        // base-face should come after face-shape (which is null here)
        final baseFaceIdx = stack.indexWhere((e) => e.layer == CameoLayer.baseFace);
        expect(baseFaceIdx, greaterThan(0));
      });

      test('skin tone path includes the 1-indexed tone number', () {
        final stack = CameoAssetRegistry.resolveLayerStack(def);
        final skinToneEntry = stack.firstWhere((e) => e.layer == CameoLayer.skinTone);
        expect(skinToneEntry.assetPath, contains('skin-tones/skin_04.png'));
      });

      test('wavy_shoulder_female hair style resolves to 3-layer paths', () {
        final hair = CameoAssetRegistry.hairPaths('wavy_shoulder_female');
        expect(hair.front, isNotNull);
        expect(hair.middle, isNotNull);
        expect(hair.back, isNotNull);
        expect(hair.front, contains('parts/hair-front/'));
        expect(hair.middle, contains('parts/hair-middle/'));
        expect(hair.back, contains('parts/hair-back/'));
      });

      test('short_textured_male hair style uses legacy single-layer path', () {
        final hair = CameoAssetRegistry.hairPaths('short_textured_male');
        expect(hair.front, isNotNull);
        expect(hair.middle, isNull);
        expect(hair.back, isNull);
        expect(hair.front, contains('parts/hair/hair_short_textured_male.png'));
      });

      test('face variant A picks the _A variant PNG', () {
        final stack = CameoAssetRegistry.resolveLayerStack(
          def,
          faceVariant: CameoFaceVariant.A,
        );
        final baseFace = stack.firstWhere((e) => e.layer == CameoLayer.baseFace);
        expect(baseFace.assetPath, contains('face_'));
        expect(baseFace.assetPath, contains('_A.png'));
      });

      test('accessory path resolver handles all known accessory IDs', () {
        expect(CameoAssetRegistry.accessoryPath('glasses_round'),
            contains('accessories/glasses/round_glasses.png'));
        expect(CameoAssetRegistry.accessoryPath('jhumka_earrings'),
            contains('accessories/earrings/jhumka_earrings.png'));
        expect(CameoAssetRegistry.accessoryPath('sikh_turban'),
            contains('accessories/turban/sikh_turban.png'));
        expect(CameoAssetRegistry.accessoryPath('hijab_beige'),
            contains('accessories/hijab/hijab_beige.png'));
        expect(CameoAssetRegistry.accessoryPath('red_bindi'),
            contains('accessories/bindi/red_bindi.png'));
        expect(CameoAssetRegistry.accessoryPath('nose_ring'),
            contains('accessories/nose-ring/nose_ring.png'));
        expect(CameoAssetRegistry.accessoryPath('mangalsutra'),
            contains('accessories/mangalsutra/mangalsutra.png'));
      });

      test('unknown accessory ID returns null', () {
        expect(CameoAssetRegistry.accessoryPath('unknown_thing'), isNull);
      });

      test('layer stack order matches documented contract', () {
        // The contract: skinTone → faceShape → baseFace → eyes → eyelids →
        // pupils → eyebrows → nose → mouth → cheeks → hairBack →
        // hairMiddle → hairFront → accessories → outfit
        final stack = CameoAssetRegistry.resolveLayerStack(
          def,
          faceVariant: CameoFaceVariant.B,
          faceShapeId: 'oval',
          eyeShapeId: 'almond',
          noseShapeId: 'button',
          mouthShapeId: 'smile',
          eyebrowShapeId: 'medium',
          pupilDirection: 'left',
          eyelidState: 'half_closed',
        );

        // Verify a few critical ordering constraints.
        final layerOrder = stack.map((e) => e.layer).toList();
        expect(layerOrder.indexOf(CameoLayer.skinTone),
            lessThan(layerOrder.indexOf(CameoLayer.baseFace)));
        expect(layerOrder.indexOf(CameoLayer.baseFace),
            lessThan(layerOrder.indexOf(CameoLayer.eyes)));
        expect(layerOrder.indexOf(CameoLayer.eyes),
            lessThan(layerOrder.indexOf(CameoLayer.eyebrows)));
        expect(layerOrder.indexOf(CameoLayer.hairBack),
            lessThan(layerOrder.indexOf(CameoLayer.hairMiddle)));
        expect(layerOrder.indexOf(CameoLayer.hairMiddle),
            lessThan(layerOrder.indexOf(CameoLayer.hairFront)));
      });

      test('outfit layer is added when clothingId is set', () {
        final defWithClothing = CameoDefinition(
          id: 'test',
          personId: 'p1',
          familyId: 'f1',
          schemaVersion: 2,
          gender: CameoGender.male,
          ageBandIndex: 3,
          skinToneIndex: 3,
          clothingId: 'casual/casual_tshirt_jeans',
        );
        final stack = CameoAssetRegistry.resolveLayerStack(defWithClothing);
        final outfit = stack.where((e) => e.layer == CameoLayer.outfit).toList();
        expect(outfit.length, 1);
        expect(outfit.first.assetPath,
            contains('clothing/casual/casual_tshirt_jeans.png'));
      });
    });
  });
}

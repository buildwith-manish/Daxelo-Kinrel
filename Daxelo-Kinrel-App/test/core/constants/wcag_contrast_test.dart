// test/core/constants/wcag_contrast_test.dart
//
// P4.6 — High-contrast theme + automated contrast tests.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/constants/brand_colors.dart';
import 'package:kinrel/core/constants/kinrel_high_contrast_colors.dart';
import 'package:kinrel/core/constants/wcag_contrast.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P4.6 — WCAG contrast ratio formula', () {
    test('black on white = 21:1 (maximum)', () {
      final ratio = contrastRatio(Colors.black, Colors.white);
      expect(ratio, closeTo(21.0, 0.5));
    });

    test('identical colors = 1:1', () {
      final ratio = contrastRatio(Colors.red, Colors.red);
      expect(ratio, closeTo(1.0, 0.01));
    });

    test('meetsWCAGAA returns true for 4.5:1+', () {
      expect(meetsWCAGAA(Colors.white, Colors.black), isTrue);
    });

    test('meetsWCAGAA returns false for < 4.5:1', () {
      expect(meetsWCAGAA(Colors.grey, Colors.white), isFalse);
    });

    test('meetsWCAGAAA returns true for 7:1+', () {
      expect(meetsWCAGAAA(Colors.white, Colors.black), isTrue);
    });
  });

  group('P4.6 — Standard theme (KinrelColors) contrast', () {
    test('textWhite on darkBackground meets AA', () {
      expect(
        meetsWCAGAA(KinrelColors.textWhite, KinrelColors.darkBackground),
        isTrue,
      );
    });

    test('textWhite on darkCard meets AA', () {
      expect(
        meetsWCAGAA(KinrelColors.textWhite, KinrelColors.darkCard),
        isTrue,
      );
    });

    test('textDim on darkBackground meets AA', () {
      expect(
        meetsWCAGAA(KinrelColors.textDim, KinrelColors.darkBackground),
        isTrue,
      );
    });

    test('textSecondaryDark on darkCard meets AA', () {
      expect(
        meetsWCAGAA(KinrelColors.textSecondaryDark, KinrelColors.darkCard),
        isTrue,
      );
    });

    test('orange on darkBackground meets AA for large text (3:1)', () {
      final ratio = contrastRatio(KinrelColors.orange, KinrelColors.darkBackground);
      expect(ratio, greaterThanOrEqualTo(3.0));
    });
  });

  group('P4.6 — High-contrast theme (KinrelColorsHighContrast)', () {
    test('textWhite on HC darkBackground meets AAA', () {
      expect(
        meetsWCAGAAA(
          KinrelColorsHighContrast.textWhite,
          KinrelColorsHighContrast.darkBackground,
        ),
        isTrue,
      );
    });

    test('textDim on HC darkBackground meets AAA', () {
      expect(
        meetsWCAGAAA(
          KinrelColorsHighContrast.textDim,
          KinrelColorsHighContrast.darkBackground,
        ),
        isTrue,
      );
    });

    test('textWhite on HC darkCard meets AAA', () {
      expect(
        meetsWCAGAAA(
          KinrelColorsHighContrast.textWhite,
          KinrelColorsHighContrast.darkCard,
        ),
        isTrue,
      );
    });

    test('textWhite on HC darkElevated meets AAA', () {
      expect(
        meetsWCAGAAA(
          KinrelColorsHighContrast.textWhite,
          KinrelColorsHighContrast.darkElevated,
        ),
        isTrue,
      );
    });

    test('HC orange on HC darkBackground meets AA', () {
      expect(
        meetsWCAGAA(
          KinrelColorsHighContrast.orange,
          KinrelColorsHighContrast.darkBackground,
        ),
        isTrue,
      );
    });

    test('HC tealAccent on HC darkBackground meets AA', () {
      expect(
        meetsWCAGAA(
          KinrelColorsHighContrast.tealAccent,
          KinrelColorsHighContrast.darkBackground,
        ),
        isTrue,
      );
    });
  });

  group('P4.6 — High-contrast theme definition', () {
    test('HC background is pure black (#000000)', () {
      expect(KinrelColorsHighContrast.darkBackground.value, equals(0xFF000000));
    });

    test('HC text is pure white (#FFFFFF)', () {
      expect(KinrelColorsHighContrast.textWhite.value, equals(0xFFFFFFFF));
    });

    test('HC border is white (visible against black)', () {
      expect(KinrelColorsHighContrast.border.value, equals(0xFFFFFFFF));
    });

    test('HC sepia matrix has 20 elements (4x5)', () {
      expect(KinrelColorsHighContrast.fullSepiaMatrix.length, equals(20));
    });
  });

  group('P4.6 — P3.x effect colors have high-contrast variants', () {
    test('birthday ember has HC variant', () {
      expect(KinrelColorsHighContrast.birthdayEmber, isA<Color>());
    });

    test('memorial candle amber has HC variant', () {
      expect(KinrelColorsHighContrast.candleAmber, isA<Color>());
    });

    test('ambient mote gold has HC variant', () {
      expect(KinrelColorsHighContrast.moteGold, isA<Color>());
    });
  });
}

// test/features/rtl/rtl_check_test.dart
//
// P8.2a — RTL check helper tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/rtl/providers/rtl_check.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P8.2a — RtlCheck (pure helper)', () {
    test('empty text classifies as empty', () {
      expect(RtlCheck.detect(''), RtlDirectionality.empty);
      expect(RtlCheck.detect('   '), RtlDirectionality.empty);
    });

    test('English is LTR', () {
      expect(RtlCheck.detect('Hello family'), RtlDirectionality.ltr);
    });

    test('Hindi (Devanagari) is LTR', () {
      // Devanagari is left-to-right; must NOT be misclassified as RTL.
      expect(RtlCheck.detect('नमस्ते'), RtlDirectionality.ltr);
    });

    test('Arabic is RTL', () {
      expect(RtlCheck.detect('مرحبا بالعائلة'), RtlDirectionality.rtl);
    });

    test('Hebrew is RTL', () {
      expect(RtlCheck.detect('שלום םישפח'), RtlDirectionality.rtl);
    });

    test('mixed Arabic + English is mixed', () {
      expect(RtlCheck.detect('Hello مرحبا'), RtlDirectionality.mixed);
    });

    test('punctuation and digits alone do not flip direction', () {
      expect(RtlCheck.detect('1234 !!!'), RtlDirectionality.empty);
    });

    test('isRtlCodeUnit covers Arabic Presentation Forms', () {
      expect(RtlCheck.isRtlCodeUnit(0xFB50), isTrue); // Arabic PF-A
      expect(RtlCheck.isRtlCodeUnit(0xFE80), isTrue); // Arabic PF-B
      expect(RtlCheck.isRtlCodeUnit(0x0041), isFalse); // 'A'
    });
  });

  group('P8.2a — RtlCheckNotifier', () {
    test('evaluate stores input + directionality', () {
      final n = RtlCheckNotifier();
      n.evaluate('مرحبا');
      expect(n.state.input, 'مرحبا');
      expect(n.state.directionality, RtlDirectionality.rtl);
      expect(n.state.shouldMirror, isTrue);
      n.dispose();
    });

    test('clear resets to empty', () {
      final n = RtlCheckNotifier();
      n.evaluate('Hello');
      n.clear();
      expect(n.state.input, '');
      expect(n.state.directionality, RtlDirectionality.empty);
      n.dispose();
    });

    test('LTR text does not request mirroring', () {
      final n = RtlCheckNotifier();
      n.evaluate('Hello');
      expect(n.state.shouldMirror, isFalse);
      n.dispose();
    });
  });
}

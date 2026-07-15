// test/features/translation/translation_provider_test.dart
//
// P8.2c — Cross-generational translation tests.
// Verifies honest behaviour: empty results when nothing matches,
// register filtering, and no fabricated guesses.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/translation/providers/translation_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P8.2c — TranslationNotifier', () {
    test('empty source yields empty results (no fabrication)', () {
      final n = TranslationNotifier();
      n.translate();
      expect(n.state.results, isEmpty);
      expect(n.state.hasSearched, isTrue);
      n.dispose();
    });

    test('unknown term yields empty results honestly', () {
      final n = TranslationNotifier();
      n.setSourceText('xylophone');
      n.translate();
      expect(n.state.results, isEmpty);
      n.dispose();
    });

    test('mother → Maa (casual) and Mata ji (formal) in Hindi', () {
      final n = TranslationNotifier();
      n.setSourceText('mother');
      n.setTargetLanguage('hi');
      // neutral register surfaces every match so the viewer can choose.
      n.setRegister(GenerationRegister.neutral);
      n.translate();
      final targets = n.state.results.map((p) => p.target).toSet();
      expect(targets, containsAll(<String>{'Maa', 'Mata ji'}));
      n.dispose();
    });

    test('formal register filters to formal pair only', () {
      final n = TranslationNotifier();
      n.setSourceText('mother');
      n.setTargetLanguage('hi');
      n.setRegister(GenerationRegister.formal);
      n.translate();
      expect(n.state.results, hasLength(1));
      expect(n.state.results.single.target, 'Mata ji');
      expect(n.state.results.single.register, GenerationRegister.formal);
      n.dispose();
    });

    test('wrong language yields empty', () {
      final n = TranslationNotifier();
      n.setSourceText('mother');
      n.setTargetLanguage('ta'); // not in the tiny phrasebook
      n.translate();
      expect(n.state.results, isEmpty);
      n.dispose();
    });

    test('setting a new input resets hasSearched', () {
      final n = TranslationNotifier();
      n.setSourceText('mother');
      n.translate();
      expect(n.state.hasSearched, isTrue);
      n.setSourceText('father');
      expect(n.state.hasSearched, isFalse);
      n.dispose();
    });

    test('clear resets state', () {
      final n = TranslationNotifier();
      n.setSourceText('mother');
      n.translate();
      n.clear();
      expect(n.state.sourceText, '');
      expect(n.state.results, isEmpty);
      n.dispose();
    });
  });
}

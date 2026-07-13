// test/core/kinship/p8_1_kinship_expansion_test.dart
//
// P8.1 — Global kinship dataset expansion.
// Verifies the kinship dataset has >= 9 languages and the 7 new
// global languages are present.

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P8.1 — Kinship dataset expansion', () {
    test('HARD GATE 1: kinship_core.json has >= 9 languages', () {
      final file = File('assets/data/kinship_core.json');
      expect(file.existsSync(), isTrue);
      final data = json.decode(file.readAsStringSync()) as Map<String, dynamic>;
      final langs = data['supportedLanguages'] as List;
      expect(langs.length, greaterThanOrEqualTo(9),
          reason: 'P8.1 requires >= 9 languages');
    });

    test('7 new global languages are present', () {
      final file = File('assets/data/kinship_core.json');
      final data = json.decode(file.readAsStringSync()) as Map<String, dynamic>;
      final langs = (data['supportedLanguages'] as List).cast<String>();
      const newLangs = [
        'chinese', 'japanese', 'korean', 'arabic',
        'spanish', 'french', 'german'
      ];
      for (final lang in newLangs) {
        expect(langs, contains(lang),
            reason: '$lang must be in supportedLanguages');
      }
    });

    test('translations have entries for new languages', () {
      final file = File('assets/data/kinship_core.json');
      final data = json.decode(file.readAsStringSync()) as Map<String, dynamic>;
      final translations = data['translations'] as Map<String, dynamic>;
      // Check 'father' has all 7 new languages
      final father = translations['father'] as Map<String, dynamic>;
      for (final lang in ['chinese', 'japanese', 'korean', 'arabic', 'spanish', 'french', 'german']) {
        expect(father.containsKey(lang), isTrue,
            reason: 'father must have $lang translation');
      }
    });

    test('language_code_map.dart has new locale codes', () {
      final file = File('lib/core/kinship/language_code_map.dart');
      final content = file.readAsStringSync();
      const codes = ["'zh'", "'ja'", "'ko'", "'ar'", "'es'", "'fr'", "'de'"];
      for (final code in codes) {
        expect(content.contains(code), isTrue,
            reason: 'language_code_map must have $code');
      }
    });

    test('total language count is >= 22', () {
      final file = File('assets/data/kinship_core.json');
      final data = json.decode(file.readAsStringSync()) as Map<String, dynamic>;
      final langs = data['supportedLanguages'] as List;
      expect(langs.length, greaterThanOrEqualTo(22),
          reason: 'Expected 22 languages (15 existing + 7 new)');
    });
  });
}

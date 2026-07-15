// test/features/language/language_matrix_test.dart
//
// P12.6 Batch 5 — Language capability matrix verification.
//
// Verifies the honest language counts per the audit in
// docs/audit/batch5-language-matrix.md.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('P12.6 Language capability matrix', () {
    test('kinship_core.json lists 22 languages', () {
      final file = File('assets/data/kinship_core.json');
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final langs = data['supportedLanguages'] as List<dynamic>;
      expect(langs.length, equals(22),
          reason: 'kinship_core.json should list 22 languages');
    });

    test('15 ARB localization files exist', () {
      final l10nDir = Directory('lib/l10n');
      final arbs = l10nDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.arb'))
          .toList();
      expect(arbs.length, equals(15),
          reason: 'Should have 15 ARB files (14 Indian + English)');
    });

    test('ARB files do NOT include Chinese, Japanese, Korean, Arabic, Spanish, French, German', () {
      final l10nDir = Directory('lib/l10n');
      final arbCodes = l10nDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.arb'))
          .map((f) {
        final name = f.uri.pathSegments.last;
        return name.replaceAll('app_', '').replaceAll('.arb', '');
      }).toSet();

      const missing = {'zh', 'ja', 'ko', 'ar', 'es', 'fr', 'de'};
      for (final code in missing) {
        expect(arbCodes, isNot(contains(code)),
            reason: 'No ARB file should exist for $code (no app UI translation)');
      }
    });

    test('no "22 languages" claim in source code (refers to app UI)', () {
      // Search lib/ for any "22 language" string — this would be an
      // unsupported claim since only 15 ARB files exist.
      final libDir = Directory('lib');
      final matches = <String>[];
      for (final file in libDir.listSync(recursive: true)) {
        if (file is File && file.path.endsWith('.dart')) {
          final content = file.readAsStringSync();
          if (content.contains('22 languages') ||
              content.contains('22 Languages')) {
            matches.add(file.path);
          }
        }
      }
      expect(matches, isEmpty,
          reason: 'No "22 languages" claim should appear in source — '
                  'only 15 ARB files exist for app UI. Use "22 kinship '
                  'terminology + 15 app UI" instead.');
    });
  });
}

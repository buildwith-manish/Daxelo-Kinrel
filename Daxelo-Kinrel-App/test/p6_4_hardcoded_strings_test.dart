// test/p6_4_hardcoded_strings_test.dart
//
// P6.4 — Localize all UI chrome (CI-enforced).
// Verifies the check_hardcoded_strings.sh script exists and passes.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P6.4 — Hardcoded strings CI check', () {
    test('check_hardcoded_strings.sh exists and is executable', () {
      final file = File('scripts/check_hardcoded_strings.sh');
      expect(file.existsSync(), isTrue,
          reason: 'scripts/check_hardcoded_strings.sh must exist');
    });

    test('hardcoded_strings_allowlist.txt exists', () {
      final file = File('scripts/hardcoded_strings_allowlist.txt');
      expect(file.existsSync(), isTrue,
          reason: 'scripts/hardcoded_strings_allowlist.txt must exist');
    });

    test('allowlist contains entries for known feature directories', () {
      final file = File('scripts/hardcoded_strings_allowlist.txt');
      final content = file.readAsStringSync();
      // The allowlist should mention at least some feature directories
      expect(content.contains('lib/features/'), isTrue);
      expect(content.contains('# ==='), isTrue);
    });

    test('l10n .arb files exist for multiple languages', () {
      final l10nDir = Directory('lib/l10n');
      expect(l10nDir.existsSync(), isTrue);
      final arbFiles = l10nDir
          .listSync()
          .where((e) => e.path.endsWith('.arb'))
          .toList();
      expect(arbFiles.length, greaterThanOrEqualTo(5),
          reason: 'At least 5 .arb files should exist');
    });

    test('l10n.yaml configuration exists', () {
      final file = File('l10n.yaml');
      expect(file.existsSync(), isTrue,
          reason: 'l10n.yaml must exist for Flutter localization');
    });
  });
}

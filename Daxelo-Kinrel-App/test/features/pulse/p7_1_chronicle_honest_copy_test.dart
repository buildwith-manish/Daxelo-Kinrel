// test/features/pulse/p7_1_chronicle_honest_copy_test.dart
//
// P7.1 — Reframe Family Chronicle honestly.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P7.1 — Honest chronicle copy', () {
    test('HARD GATE 3: no "AI-written" in lib/', () {
      final libDir = Directory('lib');
      var found = false;
      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('.dart')) {
          final content = entity.readAsStringSync();
          if (content.contains('AI-written')) {
            found = true;
          }
        }
      }
      expect(found, isFalse);
    });

    test('chronicle screen has "How is this generated?" disclosure', () {
      final file = File(
          'lib/features/pulse/presentation/family_chronicle_screen.dart');
      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();
      expect(content.contains('How is this generated?'), isTrue);
    });

    test('chronicle screen does NOT claim "beautifully written"', () {
      final file = File(
          'lib/features/pulse/presentation/family_chronicle_screen.dart');
      final content = file.readAsStringSync();
      expect(content.contains('beautifully written'), isFalse);
    });

    test('chronicle screen uses honest copy about shared data', () {
      final file = File(
          'lib/features/pulse/presentation/family_chronicle_screen.dart');
      final content = file.readAsStringSync();
      expect(
        content.contains('shared') || content.contains('compiled from'),
        isTrue,
      );
    });

    test('chronicle screen comment says "template-generated"', () {
      final file = File(
          'lib/features/pulse/presentation/family_chronicle_screen.dart');
      final content = file.readAsStringSync();
      expect(content.contains('template-generated'), isTrue);
    });
  });
}

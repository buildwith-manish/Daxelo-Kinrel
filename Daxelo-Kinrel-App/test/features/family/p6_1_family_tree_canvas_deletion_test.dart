// test/features/family/p6_1_family_tree_canvas_deletion_test.dart
//
// P6.1 — Verify family_tree_canvas.dart is deleted and the V2.1 engine
// is used instead. This is the resolution of the P0.1 deferral.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P6.1 — family_tree_canvas.dart deletion (P0.1 deferral resolution)', () {
    test('family_tree_canvas.dart file does NOT exist', () {
      final file = File(
        'lib/features/family/presentation/family_tree_canvas.dart',
      );
      expect(
        file.existsSync(),
        isFalse,
        reason: 'family_tree_canvas.dart must be deleted (P6.1 hard gate)',
      );
    });

    test('family_detail_screen.dart imports FamilyGraphEngineView', () {
      final file = File(
        'lib/features/family/presentation/family_detail_screen.dart',
      );
      final content = file.readAsStringSync();
      expect(
        content.contains("import '../../../graph/widgets/family_graph_engine_view.dart';"),
        isTrue,
        reason: 'family_detail_screen.dart must import the V2.1 engine',
      );
    });

    test('family_detail_screen.dart does NOT import family_tree_canvas', () {
      final file = File(
        'lib/features/family/presentation/family_detail_screen.dart',
      );
      final content = file.readAsStringSync();
      expect(
        content.contains("import 'family_tree_canvas.dart';"),
        isFalse,
        reason: 'family_detail_screen.dart must not import the deleted file',
      );
    });

    test('family_detail_screen.dart uses FamilyGraphEngineView widget', () {
      final file = File(
        'lib/features/family/presentation/family_detail_screen.dart',
      );
      final content = file.readAsStringSync();
      expect(
        content.contains('FamilyGraphEngineView('),
        isTrue,
        reason: 'family_detail_screen.dart must use FamilyGraphEngineView',
      );
    });

    test('no file in lib/ references FamilyTreeCanvas class', () {
      final libDir = Directory('lib');
      var found = false;
      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('.dart')) {
          final content = entity.readAsStringSync();
          if (content.contains('FamilyTreeCanvas') &&
              !entity.path.contains('family_tree_canvas')) {
            // Allow comments that mention the migration but not actual code
            final lines = content.split('\n');
            for (final line in lines) {
              final trimmed = line.trim();
              if (trimmed.startsWith('//') || trimmed.startsWith('*')) {
                continue; // skip comments
              }
              if (trimmed.contains('FamilyTreeCanvas')) {
                found = true;
                print('Found in ${entity.path}: $trimmed');
              }
            }
          }
        }
      }
      expect(found, isFalse,
          reason: 'No file in lib/ should reference FamilyTreeCanvas in code');
    });
  });

  group('P6.1 — P0.1 deferral resolution', () {
    test('P0.1 deferral is resolved — legacy file deleted', () {
      // The P0.1 deferral was: "family_tree_canvas.dart is DEFERRED to
      // Phase 6 (live caller in family_detail_screen.dart)"
      // P6.1 resolves this by migrating the caller and deleting the file.
      final file = File(
        'lib/features/family/presentation/family_tree_canvas.dart',
      );
      expect(file.existsSync(), isFalse,
          reason: 'P0.1 deferral must be resolved — file deleted');
    });
  });
}

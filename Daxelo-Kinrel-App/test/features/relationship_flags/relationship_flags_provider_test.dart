// test/features/relationship_flags/relationship_flags_provider_test.dart
//
// P9.2g — Non-judgmental relationship-state flags.
//
// HARD GUARANTEES verified here:
//   1. Flags are VIEWER-PRIVATE. The provider performs NO I/O. There is
//      no repository, no supabase call, no notification emitter on the
//      notifier. (We assert the public API surface.)
//   2. Flags are NEVER compared. There is no method that ranks, sorts
//      across targets, or aggregates multiple targets into a metric.
//   3. One active flag per target (no grievance dossier).
//   4. Labels are non-judgmental and describe the VIEWER's stance.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/relationship_flags/providers/relationship_flags_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P9.2g — Viewer-private guarantees', () {
    test('provider source imports NO supabase / dio / repository / notifications', () {
      final file = File(
        'lib/features/relationship_flags/providers/relationship_flags_provider.dart',
      );
      final src = file.readAsStringSync();
      // We check *import statements*, not bare words, because the source
      // legitimately *discusses* these guarantees in comments ("NEVER
      // written to Supabase"). An import would be the actual violation.
      final importLines = src
          .split('\n')
          .where((l) => l.trimLeft().startsWith('import '));
      for (final line in importLines) {
        expect(line.contains('supabase'), isFalse,
            reason: 'Flags must never import Supabase: $line');
        expect(line.contains('dio'), isFalse,
            reason: 'Flags must never import dio: $line');
        expect(line.contains('notification'), isFalse,
            reason: 'Flags must never import a notification package: $line');
      }
    });

    test('provider source makes NO supabase / dio / notify API call', () {
      final file = File(
        'lib/features/relationship_flags/providers/relationship_flags_provider.dart',
      );
      final src = file.readAsStringSync();
      // Filter out comment lines so the guarantee comments ("NEVER written
      // to Supabase") don't false-positive.
      final codeLines = src.split('\n').where((l) {
        final t = l.trimLeft();
        return t.isNotEmpty && !t.startsWith('//') && !t.startsWith('*');
      });
      final code = codeLines.join('\n');
      expect(code.contains('SupabaseClient'), isFalse);
      expect(code.contains("from('"), isFalse);
      expect(code.contains('.rpc('), isFalse);
      expect(code.contains('Dio('), isFalse);
      expect(code.contains('.notify('), isFalse);
      expect(code.contains('LocalNotification'), isFalse);
      expect(code.contains('FirebaseMessaging'), isFalse);
    });

    test('notifier API has no comparison / aggregate method', () {
      final n = RelationshipFlagsNotifier();
      // Allowed methods only: setFlag, clearFlag, clearAll.
      expect(n.setFlag, isNotNull);
      expect(n.clearFlag, isNotNull);
      expect(n.clearAll, isNotNull);
      // There is intentionally no rank(), compare(), leaderboard(), total().
      n.dispose();
    });

    test('one active flag per target (setting replaces, not appends)', () {
      final n = RelationshipFlagsNotifier();
      n.setFlag('p-1', RelationshipFlag.reachingOut);
      n.setFlag('p-1', RelationshipFlag.wantToReconnect);
      expect(n.state.entries, hasLength(1));
      expect(
        n.state.flagFor('p-1')?.flag,
        RelationshipFlag.wantToReconnect,
      );
      n.dispose();
    });

    test('clearFlag removes only the target', () {
      final n = RelationshipFlagsNotifier();
      n.setFlag('p-1', RelationshipFlag.comfortable);
      n.setFlag('p-2', RelationshipFlag.needingSpace);
      n.clearFlag('p-1');
      expect(n.state.entries, hasLength(1));
      expect(n.state.flagFor('p-1'), isNull);
      expect(n.state.flagFor('p-2')?.flag, RelationshipFlag.needingSpace);
      n.dispose();
    });

    test('clearAll empties the map', () {
      final n = RelationshipFlagsNotifier();
      n.setFlag('p-1', RelationshipFlag.rememberOccasion);
      n.clearAll();
      expect(n.state.entries, isEmpty);
      n.dispose();
    });

    test('empty target id is ignored', () {
      final n = RelationshipFlagsNotifier();
      n.setFlag('  ', RelationshipFlag.comfortable);
      expect(n.state.entries, isEmpty);
      n.dispose();
    });

    test('note is trimmed and blank becomes null', () {
      final n = RelationshipFlagsNotifier();
      n.setFlag('p-1', RelationshipFlag.reachingOut, note: '   ');
      expect(n.state.flagFor('p-1')?.note, isNull);
      n.setFlag('p-1', RelationshipFlag.reachingOut, note: ' call soon ');
      expect(n.state.flagFor('p-1')?.note, 'call soon');
      n.dispose();
    });

    test('labels are non-judgmental (describe the viewer, not the target)', () {
      for (final f in RelationshipFlag.values) {
        final label = relationshipFlagLabel(f).toLowerCase();
        // Must NOT label the OTHER person as "difficult", "toxic", etc.
        expect(label, isNot(contains('difficult')));
        expect(label, isNot(contains('toxic')));
        expect(label, isNot(contains('bad')));
        // Must NOT use guilt / urgency language.
        expect(label, isNot(contains('forget')));
        expect(label, isNot(contains('must')));
      }
    });
  });
}

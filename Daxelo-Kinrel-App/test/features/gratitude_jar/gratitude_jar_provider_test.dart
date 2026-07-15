// test/features/gratitude_jar/gratitude_jar_provider_test.dart
//
// P9.2a — Gratitude jar tests.
// Verifies NO streak counter exists and that empty notes are rejected.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/gratitude_jar/providers/gratitude_jar_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P9.2a — GratitudeJarNotifier (no streak)', () {
    test('state has NO streak / day-count / consecutive field', () {
      final n = GratitudeJarNotifier();
      // Compile-time check: state exposes only notes/isSaving/error.
      expect(n.state.notes, isEmpty);
      expect(n.state.isSaving, isFalse);
      expect(n.state.error, isNull);
      n.dispose();
    });

    test('addNote stores a trimmed note with a recipient', () {
      final n = GratitudeJarNotifier();
      n.addNote('  Thanks for the call  ', recipientName: 'Aaji');
      expect(n.state.notes, hasLength(1));
      expect(n.state.notes.single.text, 'Thanks for the call');
      expect(n.state.notes.single.recipientName, 'Aaji');
      expect(n.state.error, isNull);
      n.dispose();
    });

    test('empty note is rejected with a neutral error (no guilt)', () {
      final n = GratitudeJarNotifier();
      n.addNote('   ');
      expect(n.state.notes, isEmpty);
      expect(n.state.error, 'Note cannot be empty.');
      // Verify the error copy contains no guilt/urgency language.
      expect(n.state.error!.toLowerCase(), isNot(contains('forget')));
      expect(n.state.error!.toLowerCase(), isNot(contains('streak')));
      n.dispose();
    });

    test('blank recipient is normalised to null', () {
      final n = GratitudeJarNotifier();
      n.addNote('Thanks', recipientName: '   ');
      expect(n.state.notes.single.recipientName, isNull);
      n.dispose();
    });

    test('editNote updates text in place', () {
      final n = GratitudeJarNotifier();
      n.addNote('Old text');
      n.editNote(n.state.notes.single.id, 'New text');
      expect(n.state.notes.single.text, 'New text');
      n.dispose();
    });

    test('removeNote drops by id', () {
      final n = GratitudeJarNotifier();
      n.addNote('one');
      n.addNote('two');
      n.removeNote(n.state.notes.first.id);
      expect(n.state.notes, hasLength(1));
      n.dispose();
    });

    test('chronological is sorted oldest-first', () {
      final n = GratitudeJarNotifier();
      n.addNote('a');
      n.addNote('b');
      final ordered = n.state.chronological;
      expect(ordered.first.text, 'a');
      expect(ordered.last.text, 'b');
      n.dispose();
    });

    test('clearError wipes the error', () {
      final n = GratitudeJarNotifier();
      n.addNote('   ');
      expect(n.state.error, isNotNull);
      n.clearError();
      expect(n.state.error, isNull);
      n.dispose();
    });
  });
}

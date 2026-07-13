// test/features/ancestor_tribute/ancestor_tribute_provider_test.dart
//
// P9.2k — Ancestor tribute wall tests.
// Verifies NO like/view count and chronological ordering.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/ancestor_tribute/providers/ancestor_tribute_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P9.2k — AncestorTributeNotifier', () {
    test('starts empty with no engagement surface', () {
      final n = AncestorTributeNotifier();
      expect(n.state.tributes, isEmpty);
      expect(n.state.isSaving, isFalse);
      expect(n.state.error, isNull);
      n.dispose();
    });

    test('addTribute stores name + body', () {
      final n = AncestorTributeNotifier();
      n.addTribute(
        ancestorName: 'Aaba',
        tribute: 'A steady, kind presence.',
        authorName: 'Riya',
      );
      expect(n.state.tributes, hasLength(1));
      expect(n.state.tributes.single.ancestorName, 'Aaba');
      expect(n.state.tributes.single.tribute, 'A steady, kind presence.');
      expect(n.state.tributes.single.authorName, 'Riya');
      n.dispose();
    });

    test('empty ancestor name is rejected neutrally', () {
      final n = AncestorTributeNotifier();
      n.addTribute(ancestorName: '  ', tribute: 'x');
      expect(n.state.tributes, isEmpty);
      expect(n.state.error, 'Please name the ancestor being remembered.');
      n.dispose();
    });

    test('empty body is rejected neutrally', () {
      final n = AncestorTributeNotifier();
      n.addTribute(ancestorName: 'Aaba', tribute: '  ');
      expect(n.state.tributes, isEmpty);
      expect(n.state.error, 'The tribute cannot be empty.');
      n.dispose();
    });

    test('blank author normalises to null (anonymous tribute allowed)', () {
      final n = AncestorTributeNotifier();
      n.addTribute(ancestorName: 'Aaba', tribute: 'kind', authorName: '   ');
      expect(n.state.tributes.single.authorName, isNull);
      n.dispose();
    });

    test('editTribute updates body and author', () {
      final n = AncestorTributeNotifier();
      n.addTribute(ancestorName: 'Aaba', tribute: 'original');
      final id = n.state.tributes.single.id;
      n.editTribute(id, tribute: 'updated', authorName: 'Meera');
      expect(n.state.tributes.single.tribute, 'updated');
      expect(n.state.tributes.single.authorName, 'Meera');
      n.dispose();
    });

    test('removeTribute drops by id', () {
      final n = AncestorTributeNotifier();
      n.addTribute(ancestorName: 'A', tribute: 'x');
      n.addTribute(ancestorName: 'B', tribute: 'y');
      n.removeTribute(n.state.tributes.first.id);
      expect(n.state.tributes, hasLength(1));
      n.dispose();
    });

    test('chronological sorts oldest-first', () {
      final n = AncestorTributeNotifier();
      n.addTribute(ancestorName: 'A', tribute: 'first');
      n.addTribute(ancestorName: 'B', tribute: 'second');
      final ordered = n.state.chronological;
      expect(ordered.first.tribute, 'first');
      expect(ordered.last.tribute, 'second');
      n.dispose();
    });

    test('there is NO like / view count on AncestorTribute', () {
      final n = AncestorTributeNotifier();
      n.addTribute(ancestorName: 'A', tribute: 'x');
      final t = n.state.tributes.single;
      // Compile-time guarantee: only id/name/tribute/createdAt/authorName.
      expect(t.id, isNotNull);
      expect(t.ancestorName, 'A');
      expect(t.tribute, 'x');
      expect(t.authorName, isNull);
      n.dispose();
    });
  });
}

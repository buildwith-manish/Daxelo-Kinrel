// test/features/family_values/family_values_provider_test.dart
//
// P9.2b — Family values manifesto tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/family_values/providers/family_values_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P9.2b — FamilyValuesNotifier', () {
    test('starts empty with no compliance / score field', () {
      final n = FamilyValuesNotifier();
      expect(n.state.values, isEmpty);
      expect(n.state.isEditing, isFalse);
      expect(n.state.error, isNull);
      n.dispose();
    });

    test('addValue stores title + description', () {
      final n = FamilyValuesNotifier();
      n.addValue('Honesty', 'We tell the truth, kindly.');
      expect(n.state.values, hasLength(1));
      expect(n.state.values.single.title, 'Honesty');
      expect(n.state.values.single.description, 'We tell the truth, kindly.');
      n.dispose();
    });

    test('empty title is rejected neutrally', () {
      final n = FamilyValuesNotifier();
      n.addValue('  ', 'desc');
      expect(n.state.values, isEmpty);
      expect(n.state.error, 'A value needs a short title.');
      n.dispose();
    });

    test('editValue updates fields', () {
      final n = FamilyValuesNotifier();
      n.addValue('Kindness', 'original');
      final id = n.state.values.single.id;
      n.editValue(id, title: 'Compassion', description: 'updated');
      expect(n.state.values.single.title, 'Compassion');
      expect(n.state.values.single.description, 'updated');
      n.dispose();
    });

    test('removeValue drops by id', () {
      final n = FamilyValuesNotifier();
      n.addValue('a', '');
      n.addValue('b', '');
      n.removeValue(n.state.values.first.id);
      expect(n.state.values, hasLength(1));
      n.dispose();
    });

    test('reorder renumbers orderIndex sequentially', () {
      final n = FamilyValuesNotifier();
      n.addValue('a', '');
      n.addValue('b', '');
      n.addValue('c', '');
      // Move 'c' (index 2) to the front.
      n.reorder(2, 0);
      final ordered = n.state.ordered.map((v) => v.title).toList();
      expect(ordered, ['c', 'a', 'b']);
      // orderIndex must be 0,1,2 with no gaps.
      final indices = n.state.ordered.map((v) => v.orderIndex).toList();
      expect(indices, [0, 1, 2]);
      n.dispose();
    });

    test('reorder out-of-range oldIndex is a no-op', () {
      final n = FamilyValuesNotifier();
      n.reorder(5, 0);
      expect(n.state.values, isEmpty);
      n.dispose();
    });

    test('begin/end edit toggles isEditing', () {
      final n = FamilyValuesNotifier();
      n.beginEdit();
      expect(n.state.isEditing, isTrue);
      n.endEdit();
      expect(n.state.isEditing, isFalse);
      n.dispose();
    });
  });
}

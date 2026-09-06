// test/graph/engine/local_expansion_label_fix_test.dart
//
// DAXELO KINREL — v5.167 ACCEPTANCE TEST
//
// Verifies the labelAtoB fix: when expanding a branch, the grouping
// logic must use labelAtoB (the specific label like 'son', 'daughter')
// instead of relationshipKey (which is always 'parent' for non-spouse
// edges due to the DB constraint).
//
// These tests use preservePositions=true (the expansion path) to
// verify the local expansion layout correctly identifies parent-child
// relationships via labelAtoB.

import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/services/graph_layout_service.dart';
import 'package:kinrel/graph/engine/radial_layout.dart';

GraphPerson _person(String id, {bool isAnchor = false}) =>
    GraphPerson(id: id, name: 'Person $id', isAnchor: isAnchor);

GraphRelationship _rel(
  String id,
  String from,
  String to,
  String key, {
  String? labelAtoB,
}) =>
    GraphRelationship(
      id: id,
      fromPersonId: from,
      toPersonId: to,
      relationshipKey: key,
      labelAtoB: labelAtoB,
    );

void main() {
  group('v5.167 — labelAtoB fix for local expansion', () {
    test(
        'CRITERION 1: expanding with "son" edge places child BELOW parent '
        '(labelAtoB identifies fromPerson as parent)',
        () {
      // Initial: just the parent (anchor).
      final initialPersons = [_person('parent', isAnchor: true)];
      final initialRels = <GraphRelationship>[];

      final layout = RadialLayout();
      final initial = layout.compute(
        persons: initialPersons,
        relationships: initialRels,
        anchorPersonId: 'parent',
      );

      // Expand: add 1 child via a 'son' edge.
      // from=parent, to=child, relationshipKey='parent', labelAtoB='son'
      final expandedPersons = [...initialPersons, _person('child')];
      final expandedRels = [
        _rel('r1', 'parent', 'child', 'parent', labelAtoB: 'son'),
      ];

      final expanded = layout.compute(
        persons: expandedPersons,
        relationships: expandedRels,
        anchorPersonId: 'parent',
        preservePositions: true,
        previousPositions: initial.positions,
      );

      final parentPos = expanded.positions['parent']!;
      final childPos = expanded.positions['child']!;

      expect(childPos.dy, greaterThan(parentPos.dy),
          reason: 'Child (labelAtoB="son") must be placed BELOW the '
              'parent. Parent Y=${parentPos.dy}, Child Y=${childPos.dy}.');
    });

    test(
        'CRITERION 2: expanding with "daughter" edge places child BELOW '
        'parent',
        () {
      final initialPersons = [_person('parent', isAnchor: true)];
      final layout = RadialLayout();
      final initial = layout.compute(
        persons: initialPersons,
        relationships: [],
        anchorPersonId: 'parent',
      );

      final expandedPersons = [...initialPersons, _person('daughter')];
      final expandedRels = [
        _rel('r1', 'parent', 'daughter', 'parent', labelAtoB: 'daughter'),
      ];

      final expanded = layout.compute(
        persons: expandedPersons,
        relationships: expandedRels,
        anchorPersonId: 'parent',
        preservePositions: true,
        previousPositions: initial.positions,
      );

      final parentPos = expanded.positions['parent']!;
      final childPos = expanded.positions['daughter']!;

      expect(childPos.dy, greaterThan(parentPos.dy),
          reason: 'Daughter must be below parent.');
    });

    test(
        'CRITERION 3: expanding with "father" edge places ancestor ABOVE '
        'the child (toPerson is the parent)',
        () {
      // from=child(anchor), to=father, labelAtoB='father'
      // _parentKeys contains 'father' → toPerson (father) is the parent.
      final initialPersons = [_person('child', isAnchor: true)];
      final layout = RadialLayout();
      final initial = layout.compute(
        persons: initialPersons,
        relationships: [],
        anchorPersonId: 'child',
      );

      final expandedPersons = [...initialPersons, _person('father')];
      final expandedRels = [
        _rel('r1', 'child', 'father', 'parent', labelAtoB: 'father'),
      ];

      final expanded = layout.compute(
        persons: expandedPersons,
        relationships: expandedRels,
        anchorPersonId: 'child',
        preservePositions: true,
        previousPositions: initial.positions,
      );

      final childPos = expanded.positions['child']!;
      final fatherPos = expanded.positions['father']!;

      // The father (ancestor) must be ABOVE the child.
      expect(fatherPos.dy, lessThan(childPos.dy),
          reason: 'Father (ancestor) must be ABOVE the child. '
              'Child Y=${childPos.dy}, Father Y=${fatherPos.dy}.');
    });

    test(
        'CRITERION 5: expanding a branch places multiple children directly '
        'below the parent (hierarchical downward expansion)',
        () {
      final initialPersons = [_person('parent', isAnchor: true)];
      final layout = RadialLayout();
      final initial = layout.compute(
        persons: initialPersons,
        relationships: [],
        anchorPersonId: 'parent',
      );

      // Expand: add 3 children via 'son'/'daughter' edges.
      final expandedPersons = [
        ...initialPersons,
        _person('child1'),
        _person('child2'),
        _person('child3'),
      ];
      final expandedRels = [
        _rel('r1', 'parent', 'child1', 'parent', labelAtoB: 'son'),
        _rel('r2', 'parent', 'child2', 'parent', labelAtoB: 'daughter'),
        _rel('r3', 'parent', 'child3', 'parent', labelAtoB: 'son'),
      ];

      final expanded = layout.compute(
        persons: expandedPersons,
        relationships: expandedRels,
        anchorPersonId: 'parent',
        preservePositions: true,
        previousPositions: initial.positions,
      );

      final parentPos = expanded.positions['parent']!;

      // All 3 children must be BELOW the parent.
      for (var i = 1; i <= 3; i++) {
        final childPos = expanded.positions['child$i']!;
        expect(childPos.dy, greaterThan(parentPos.dy),
            reason: 'child$i must be below parent. '
                'Parent Y=${parentPos.dy}, child$i Y=${childPos.dy}.');
      }

      // Children should be horizontally spaced (fan out via subtree-width).
      final childXs = [
        expanded.positions['child1']!.dx,
        expanded.positions['child2']!.dx,
        expanded.positions['child3']!.dx,
      ];
      final uniqueXs = childXs.toSet();
      expect(uniqueXs.length, greaterThan(1),
          reason: 'Children should fan out horizontally. Xs=$childXs.');
    });
  });
}

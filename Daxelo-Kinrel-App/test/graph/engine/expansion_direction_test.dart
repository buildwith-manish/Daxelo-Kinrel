// test/graph/engine/expansion_direction_test.dart
//
// DAXELO KINREL — v5.170 ACCEPTANCE TEST
//
// Verifies that branch expansion always places descendants BELOW their
// parent — never above, never scattered to unrelated regions.

import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/services/graph_layout_service.dart';
import 'package:kinrel/graph/engine/radial_layout.dart';

GraphPerson _person(String id, {bool isAnchor = false}) =>
    GraphPerson(id: id, name: 'Person $id', isAnchor: isAnchor);

GraphRelationship _rel(
  String id,
  String from,
  String to, {
  String labelAtoB = 'son',
}) =>
    GraphRelationship(
      id: id,
      fromPersonId: from,
      toPersonId: to,
      relationshipKey: 'parent',
      labelAtoB: labelAtoB,
    );

void main() {
  group('v5.170 — Expansion direction', () {
    test(
        'CRITERION 1: expanding with "son" edge places child BELOW parent',
        () {
      final initialPersons = [_person('parent', isAnchor: true)];
      final layout = RadialLayout();
      final initial = layout.compute(
        persons: initialPersons,
        relationships: [],
        anchorPersonId: 'parent',
      );

      final expanded = layout.compute(
        persons: [...initialPersons, _person('child')],
        relationships: [_rel('r1', 'parent', 'child', labelAtoB: 'son')],
        anchorPersonId: 'parent',
        preservePositions: true,
        previousPositions: initial.positions,
      );

      expect(expanded.positions['child']!.dy,
          greaterThan(expanded.positions['parent']!.dy),
          reason: 'Child must be below parent.');
    });

    test(
        'CRITERION 2: expanding with "daughter" edge places child BELOW',
        () {
      final initialPersons = [_person('parent', isAnchor: true)];
      final layout = RadialLayout();
      final initial = layout.compute(
        persons: initialPersons,
        relationships: [],
        anchorPersonId: 'parent',
      );

      final expanded = layout.compute(
        persons: [...initialPersons, _person('daughter')],
        relationships: [_rel('r1', 'parent', 'daughter', labelAtoB: 'daughter')],
        anchorPersonId: 'parent',
        preservePositions: true,
        previousPositions: initial.positions,
      );

      expect(expanded.positions['daughter']!.dy,
          greaterThan(expanded.positions['parent']!.dy));
    });

    test(
        'CRITERION 3: expanding with "father" edge places ancestor ABOVE',
        () {
      final initialPersons = [_person('child', isAnchor: true)];
      final layout = RadialLayout();
      final initial = layout.compute(
        persons: initialPersons,
        relationships: [],
        anchorPersonId: 'child',
      );

      final expanded = layout.compute(
        persons: [...initialPersons, _person('father')],
        relationships: [_rel('r1', 'child', 'father', labelAtoB: 'father')],
        anchorPersonId: 'child',
        preservePositions: true,
        previousPositions: initial.positions,
      );

      expect(expanded.positions['father']!.dy,
          lessThan(expanded.positions['child']!.dy),
          reason: 'Father must be above child.');
    });

    test(
        'CRITERION 4: multi-level expansion — all descendants below parent',
        () {
      final initialPersons = [_person('parent', isAnchor: true)];
      final layout = RadialLayout();
      final initial = layout.compute(
        persons: initialPersons,
        relationships: [],
        anchorPersonId: 'parent',
      );

      final expanded = layout.compute(
        persons: [
          ...initialPersons,
          _person('c1'), _person('c2'), _person('c3'),
          _person('gc1'), _person('gc2'),
        ],
        relationships: [
          _rel('r1', 'parent', 'c1'),
          _rel('r2', 'parent', 'c2'),
          _rel('r3', 'parent', 'c3'),
          _rel('r4', 'c1', 'gc1'),
          _rel('r5', 'c2', 'gc2'),
        ],
        anchorPersonId: 'parent',
        preservePositions: true,
        previousPositions: initial.positions,
      );

      final parentY = expanded.positions['parent']!.dy;
      for (final id in ['c1', 'c2', 'c3', 'gc1', 'gc2']) {
        expect(expanded.positions[id]!.dy, greaterThan(parentY),
            reason: '$id must be below parent.');
      }
    });

    test(
        'CRITERION 5: no descendant appears ABOVE its parent',
        () {
      final initialPersons = [_person('parent', isAnchor: true)];
      final layout = RadialLayout();
      final initial = layout.compute(
        persons: initialPersons,
        relationships: [],
        anchorPersonId: 'parent',
      );

      final expanded = layout.compute(
        persons: [
          ...initialPersons,
          _person('c1'), _person('c2'), _person('c3'),
        ],
        relationships: [
          _rel('r1', 'parent', 'c1'),
          _rel('r2', 'parent', 'c2'),
          _rel('r3', 'parent', 'c3'),
        ],
        anchorPersonId: 'parent',
        preservePositions: true,
        previousPositions: initial.positions,
      );

      final parentY = expanded.positions['parent']!.dy;
      for (final id in ['c1', 'c2', 'c3']) {
        expect(expanded.positions[id]!.dy, greaterThan(parentY),
            reason: '$id must be below parent (Y=$parentY).');
      }
    });

    test(
        'CRITERION 6: sibling edge does NOT create parent-child hierarchy',
        () {
      final initialPersons = [
        _person('anchor', isAnchor: true),
        _person('sibling_a'),
      ];
      final layout = RadialLayout();
      final initial = layout.compute(
        persons: initialPersons,
        relationships: [_rel('r1', 'anchor', 'sibling_a')],
        anchorPersonId: 'anchor',
      );

      final expanded = layout.compute(
        persons: [...initialPersons, _person('sibling_b')],
        relationships: [
          _rel('r1', 'anchor', 'sibling_a'),
          _rel('r2', 'sibling_a', 'sibling_b', labelAtoB: 'brother'),
        ],
        anchorPersonId: 'anchor',
        preservePositions: true,
        previousPositions: initial.positions,
      );

      // sibling_b should NOT be placed a full generation below sibling_a
      final yDiff = (expanded.positions['sibling_b']!.dy -
          expanded.positions['sibling_a']!.dy).abs();
      expect(yDiff, lessThan(300.0),
          reason: 'Sibling should not be placed far below (within 300px). '
              'Got $yDiff.');
    });

    test(
        'CRITERION 7: 180px H / 220px V spacing enforced',
        () {
      final initialPersons = [_person('parent', isAnchor: true)];
      final layout = RadialLayout();
      final initial = layout.compute(
        persons: initialPersons,
        relationships: [],
        anchorPersonId: 'parent',
      );

      // 6 children to check horizontal spacing.
      final expanded = layout.compute(
        persons: [
          ...initialPersons,
          for (var i = 1; i <= 6; i++) _person('child$i'),
        ],
        relationships: [
          for (var i = 1; i <= 6; i++) _rel('r$i', 'parent', 'child$i'),
        ],
        anchorPersonId: 'parent',
        preservePositions: true,
        previousPositions: initial.positions,
      );

      // All children below parent.
      for (var i = 1; i <= 6; i++) {
        expect(expanded.positions['child$i']!.dy,
            greaterThan(expanded.positions['parent']!.dy));
      }

      // Check that no two nodes violate the 180H/220V bounding box.
      final ids = expanded.positions.keys.toList();
      var violations = 0;
      for (var i = 0; i < ids.length; i++) {
        for (var j = i + 1; j < ids.length; j++) {
          final a = expanded.positions[ids[i]]!;
          final b = expanded.positions[ids[j]]!;
          if ((b.dx - a.dx).abs() < 180.0 &&
              (b.dy - a.dy).abs() < 220.0) {
            violations++;
          }
        }
      }
      expect(violations, 0,
          reason: 'No nodes should overlap the 180px H / 220px V box.');
    });
  });
}

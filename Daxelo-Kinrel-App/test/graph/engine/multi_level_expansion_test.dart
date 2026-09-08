// test/graph/engine/multi_level_expansion_test.dart
//
// DAXELO KINREL — v5.168 ACCEPTANCE TEST
//
// Verifies the multi-level expansion fix: when expanding a branch,
// ALL descendants (children, grandchildren, great-grandchildren) must
// be positioned below the expanded parent — NOT just direct children.
//
// Before v5.168: only direct children of settled nodes were grouped
// for local expansion. Grandchildren (whose parent was also newly-
// revealed) fell through to ring-fill and appeared at random positions
// — the "Anil Mehta / Ritu Nair / Nisha Varma scattered far away" bug.
//
// After v5.168: collectDescendants() recursively walks the parent→child
// adjacency, collecting ALL descendants of each settled origin. The
// entire descendant set is passed to computeLocalExpansionLayout, which
// builds the full subtree and positions every level below the origin.

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
  group('v5.168 — Multi-level expansion', () {
    test(
        'CRITERION 1: expanding a branch with grandchildren places ALL '
        'descendants below the parent — no ring-fill fallback',
        () {
      // Initial: just the parent (anchor).
      final initialPersons = [_person('parent', isAnchor: true)];
      final layout = RadialLayout();
      final initial = layout.compute(
        persons: initialPersons,
        relationships: [],
        anchorPersonId: 'parent',
      );

      // Expand: reveal 2 children + 2 grandchildren (each child has 1 grandchild).
      // parent → child1 → grandchild1
      // parent → child2 → grandchild2
      final expandedPersons = [
        ...initialPersons,
        _person('child1'),
        _person('child2'),
        _person('grandchild1'),
        _person('grandchild2'),
      ];
      final expandedRels = [
        _rel('r1', 'parent', 'child1'),
        _rel('r2', 'parent', 'child2'),
        _rel('r3', 'child1', 'grandchild1'),
        _rel('r4', 'child2', 'grandchild2'),
      ];

      final expanded = layout.compute(
        persons: expandedPersons,
        relationships: expandedRels,
        anchorPersonId: 'parent',
        preservePositions: true,
        previousPositions: initial.positions,
      );

      final parentPos = expanded.positions['parent']!;
      final child1Pos = expanded.positions['child1']!;
      final child2Pos = expanded.positions['child2']!;
      final gc1Pos = expanded.positions['grandchild1']!;
      final gc2Pos = expanded.positions['grandchild2']!;

      // All children must be below the parent.
      expect(child1Pos.dy, greaterThan(parentPos.dy),
          reason: 'child1 must be below parent.');
      expect(child2Pos.dy, greaterThan(parentPos.dy),
          reason: 'child2 must be below parent.');

      // All grandchildren must be below their respective parents.
      expect(gc1Pos.dy, greaterThan(child1Pos.dy),
          reason: 'grandchild1 must be below child1 (its parent).');
      expect(gc2Pos.dy, greaterThan(child2Pos.dy),
          reason: 'grandchild2 must be below child2 (its parent).');

      // Grandchildren must also be below the original parent (deeper).
      expect(gc1Pos.dy, greaterThan(parentPos.dy),
          reason: 'grandchild1 must be below the original parent.');
      expect(gc2Pos.dy, greaterThan(parentPos.dy),
          reason: 'grandchild2 must be below the original parent.');

      // Grandchildren must be FURTHER below than children (2 levels deep).
      expect(gc1Pos.dy, greaterThan(child1Pos.dy + 100),
          reason: 'grandchild1 must be significantly deeper than child1.');
      expect(gc2Pos.dy, greaterThan(child2Pos.dy + 100),
          reason: 'grandchild2 must be significantly deeper than child2.');
    });

    test(
        'CRITERION 2: expanding a 3-level deep branch — great-grandchildren '
        'are also placed below',
        () {
      final initialPersons = [_person('root', isAnchor: true)];
      final layout = RadialLayout();
      final initial = layout.compute(
        persons: initialPersons,
        relationships: [],
        anchorPersonId: 'root',
      );

      // root → child → grandchild → great_grandchild
      final expandedPersons = [
        ...initialPersons,
        _person('child'),
        _person('grandchild'),
        _person('great_grandchild'),
      ];
      final expandedRels = [
        _rel('r1', 'root', 'child'),
        _rel('r2', 'child', 'grandchild'),
        _rel('r3', 'grandchild', 'great_grandchild'),
      ];

      final expanded = layout.compute(
        persons: expandedPersons,
        relationships: expandedRels,
        anchorPersonId: 'root',
        preservePositions: true,
        previousPositions: initial.positions,
      );

      final rootPos = expanded.positions['root']!;
      final childPos = expanded.positions['child']!;
      final gcPos = expanded.positions['grandchild']!;
      final ggcPos = expanded.positions['great_grandchild']!;

      // Each level must be progressively deeper.
      expect(childPos.dy, greaterThan(rootPos.dy),
          reason: 'child below root.');
      expect(gcPos.dy, greaterThan(childPos.dy),
          reason: 'grandchild below child.');
      expect(ggcPos.dy, greaterThan(gcPos.dy),
          reason: 'great_grandchild below grandchild.');

      // The hierarchy goes: root < child < grandchild < great_grandchild
      // (all strictly increasing in Y).
      expect(rootPos.dy, lessThan(childPos.dy));
      expect(childPos.dy, lessThan(gcPos.dy));
      expect(gcPos.dy, lessThan(ggcPos.dy));
    });

    test(
        'CRITERION 3: no descendant appears ABOVE the expanded parent',
        () {
      final initialPersons = [_person('parent', isAnchor: true)];
      final layout = RadialLayout();
      final initial = layout.compute(
        persons: initialPersons,
        relationships: [],
        anchorPersonId: 'parent',
      );

      // Reveal 5 descendants across 2 levels.
      final expandedPersons = [
        ...initialPersons,
        _person('c1'),
        _person('c2'),
        _person('c3'),
        _person('gc1'),
        _person('gc2'),
      ];
      final expandedRels = [
        _rel('r1', 'parent', 'c1'),
        _rel('r2', 'parent', 'c2'),
        _rel('r3', 'parent', 'c3'),
        _rel('r4', 'c1', 'gc1'),
        _rel('r5', 'c2', 'gc2'),
      ];

      final expanded = layout.compute(
        persons: expandedPersons,
        relationships: expandedRels,
        anchorPersonId: 'parent',
        preservePositions: true,
        previousPositions: initial.positions,
      );

      final parentY = expanded.positions['parent']!.dy;

      // NONE of the descendants should appear above the parent.
      for (final id in ['c1', 'c2', 'c3', 'gc1', 'gc2']) {
        final y = expanded.positions[id]!.dy;
        expect(y, greaterThan(parentY),
            reason: '$id must be below the parent (Y=$y vs parent Y=$parentY). '
                'No descendant should appear above the expanded parent.');
      }
    });

    test(
        'CRITERION 4: expanding with many children — siblings fan out '
        'horizontally below the parent',
        () {
      final initialPersons = [_person('parent', isAnchor: true)];
      final layout = RadialLayout();
      final initial = layout.compute(
        persons: initialPersons,
        relationships: [],
        anchorPersonId: 'parent',
      );

      // Reveal 6 direct children.
      final expandedPersons = [
        ...initialPersons,
        for (var i = 1; i <= 6; i++) _person('child$i'),
      ];
      final expandedRels = [
        for (var i = 1; i <= 6; i++) _rel('r$i', 'parent', 'child$i'),
      ];

      final expanded = layout.compute(
        persons: expandedPersons,
        relationships: expandedRels,
        anchorPersonId: 'parent',
        preservePositions: true,
        previousPositions: initial.positions,
      );

      final parentPos = expanded.positions['parent']!;

      // All children below parent.
      for (var i = 1; i <= 6; i++) {
        expect(expanded.positions['child$i']!.dy, greaterThan(parentPos.dy),
            reason: 'child$i must be below parent.');
      }

      // Children fan out horizontally — at least 3 unique X positions
      // among 6 children.
      final childXs = [
        for (var i = 1; i <= 6; i++) expanded.positions['child$i']!.dx,
      ];
      expect(childXs.toSet().length, greaterThanOrEqualTo(3),
          reason: '6 children should fan out to at least 3 unique X positions.');
    });
  });
}

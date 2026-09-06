// test/graph/engine/ancestor_expansion_test.dart
//
// DAXELO KINREL — v5.169 ACCEPTANCE TEST
//
// Verifies the ancestor expansion fix: when expanding a branch that
// reveals ancestors (parents, grandparents) of the branch root, those
// ancestors must be placed ABOVE the branch root — NOT in the ancestor
// semicircle (upper-right of canvas) via ring-fill.
//
// Before v5.169: computeLocalExpansionLayout only walked DOWNWARD
// through children. Ancestors fell through to ring-fill, which assigned
// them to the ancestor semicircle based on direction-from-anchor —
// placing them far away at the top-right of the canvas.
//
// After v5.169: computeLocalExpansionLayout also walks UPWARD through
// parents (via the parentsOf adjacency + _TreeNode.parents list).
// _assignLocalPositions places ancestors at localGen - 1 (negative Y
// offset = above the origin).

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
  group('v5.169 — Ancestor expansion', () {
    test(
        'CRITERION 1: expanding a branch that reveals the parent (ancestor) '
        'places the parent ABOVE the child — NOT in the upper-right',
        () {
      // Initial: the child (anchor) is visible.
      final initialPersons = [_person('child', isAnchor: true)];
      final layout = RadialLayout();
      final initial = layout.compute(
        persons: initialPersons,
        relationships: [],
        anchorPersonId: 'child',
      );

      // Expand: reveal the child's father (an ancestor).
      // from=child, to=father, labelAtoB='father'
      // _parentKeys contains 'father' → toPerson (father) is the parent.
      final expandedPersons = [...initialPersons, _person('father')];
      final expandedRels = [
        _rel('r1', 'child', 'father', labelAtoB: 'father'),
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

      // The father (ancestor) must be ABOVE the child (Y_father < Y_child).
      expect(fatherPos.dy, lessThan(childPos.dy),
          reason: 'Father (ancestor) must be ABOVE the child. '
              'Child Y=${childPos.dy}, Father Y=${fatherPos.dy}. '
              'Before v5.169, the father would have been placed in the '
              'ancestor semicircle (upper-right) via ring-fill.');
    });

    test(
        'CRITERION 2: expanding reveals both children AND a parent — '
        'children below, parent above',
        () {
      final initialPersons = [_person('origin', isAnchor: true)];
      final layout = RadialLayout();
      final initial = layout.compute(
        persons: initialPersons,
        relationships: [],
        anchorPersonId: 'origin',
      );

      // Expand: reveal 2 children + 1 parent (father).
      final expandedPersons = [
        ...initialPersons,
        _person('child1'),
        _person('child2'),
        _person('father'),
      ];
      final expandedRels = [
        _rel('r1', 'origin', 'child1', labelAtoB: 'son'),
        _rel('r2', 'origin', 'child2', labelAtoB: 'daughter'),
        _rel('r3', 'origin', 'father', labelAtoB: 'father'),
      ];

      final expanded = layout.compute(
        persons: expandedPersons,
        relationships: expandedRels,
        anchorPersonId: 'origin',
        preservePositions: true,
        previousPositions: initial.positions,
      );

      final originPos = expanded.positions['origin']!;

      // Children must be BELOW the origin.
      expect(expanded.positions['child1']!.dy, greaterThan(originPos.dy),
          reason: 'child1 must be below origin.');
      expect(expanded.positions['child2']!.dy, greaterThan(originPos.dy),
          reason: 'child2 must be below origin.');

      // Father must be ABOVE the origin.
      expect(expanded.positions['father']!.dy, lessThan(originPos.dy),
          reason: 'Father must be above origin — not scattered to '
              'the upper-right via ring-fill.');
    });

    test(
        'CRITERION 3: expanding reveals a grandparent (2 levels up) — '
        'grandparent is placed above the parent, which is above the origin',
        () {
      final initialPersons = [_person('origin', isAnchor: true)];
      final layout = RadialLayout();
      final initial = layout.compute(
        persons: initialPersons,
        relationships: [],
        anchorPersonId: 'origin',
      );

      // Expand: reveal parent + grandparent.
      // origin → father (parent), father → grandfather (parent of father)
      final expandedPersons = [
        ...initialPersons,
        _person('father'),
        _person('grandfather'),
      ];
      final expandedRels = [
        _rel('r1', 'origin', 'father', labelAtoB: 'father'),
        _rel('r2', 'father', 'grandfather', labelAtoB: 'father'),
      ];

      final expanded = layout.compute(
        persons: expandedPersons,
        relationships: expandedRels,
        anchorPersonId: 'origin',
        preservePositions: true,
        previousPositions: initial.positions,
      );

      final originY = expanded.positions['origin']!.dy;
      final fatherY = expanded.positions['father']!.dy;
      final grandfatherY = expanded.positions['grandfather']!.dy;

      // Hierarchy: grandfather < father < origin (all strictly increasing Y).
      expect(grandfatherY, lessThan(fatherY),
          reason: 'Grandfather must be above father.');
      expect(fatherY, lessThan(originY),
          reason: 'Father must be above origin.');
    });

    test(
        'CRITERION 4: no ancestor appears in the upper-right region of '
        'the canvas (the old ring-fill bug)',
        () {
      final initialPersons = [_person('origin', isAnchor: true)];
      final layout = RadialLayout();
      final initial = layout.compute(
        persons: initialPersons,
        relationships: [],
        anchorPersonId: 'origin',
      );

      // Expand: reveal a parent.
      final expandedPersons = [...initialPersons, _person('parent')];
      final expandedRels = [
        _rel('r1', 'origin', 'parent', labelAtoB: 'father'),
      ];

      final expanded = layout.compute(
        persons: expandedPersons,
        relationships: expandedRels,
        anchorPersonId: 'origin',
        preservePositions: true,
        previousPositions: initial.positions,
      );

      final originPos = expanded.positions['origin']!;
      final parentPos = expanded.positions['parent']!;

      // The parent must be ABOVE the origin (Y < origin Y).
      expect(parentPos.dy, lessThan(originPos.dy),
          reason: 'Parent must be above origin.');

      // The parent must NOT be far away — check that the X distance is
      // reasonable (within ~500px of the origin's X). The old ring-fill
      // bug placed ancestors at cos(342°)*radius ≈ +0.95*radius to the
      // right — hundreds of pixels away.
      final xDiff = (parentPos.dx - originPos.dx).abs();
      expect(xDiff, lessThan(500.0),
          reason: 'Parent should be positioned near the origin (within '
              '500px X), not scattered far to the right via ring-fill. '
              'X diff=$xDiff.');
    });
  });
}

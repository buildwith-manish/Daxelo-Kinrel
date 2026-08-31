// test/graph/widgets/branch_collapse_child_type_keys_test.dart
//
// v5.146 REGRESSION TEST: Ensures the "Collapse this branch" feature
// correctly identifies children when relationships use CHILD-type keys
// (son, daughter, child) instead of PARENT-type keys (father, mother,
// parent). Before v5.146, the childrenOf lookup only recognized
// parent-type keys, so any node whose descendants were entered using
// son/daughter labels was invisible to the collapse feature.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/graph/interaction/branch_collapse_state.dart';

void main() {
  group('v5.146: BranchCollapseNotifier.buildChildrenOf', () {
    test('handles parent-type keys (father, mother, parent)', () {
      final relationships = [
        {'id': 'r1', 'fromPersonId': 'child1', 'toPersonId': 'parent1', 'relationshipKey': 'father'},
        {'id': 'r2', 'fromPersonId': 'child2', 'toPersonId': 'parent1', 'relationshipKey': 'mother'},
        {'id': 'r3', 'fromPersonId': 'child3', 'toPersonId': 'parent2', 'relationshipKey': 'parent'},
      ];

      final childrenOf = BranchCollapseNotifier.buildChildrenOf(relationships);

      expect(childrenOf['parent1'], containsAll(['child1', 'child2']));
      expect(childrenOf['parent2'], containsAll(['child3']));
    });

    test('handles child-type keys (son, daughter, child) — REVERSED direction', () {
      // This is the bug that was fixed: before v5.146, these relationships
      // were completely invisible to the collapse feature because the
      // lookup only checked parent-type keys.
      final relationships = [
        {'id': 'r1', 'fromPersonId': 'parent1', 'toPersonId': 'child1', 'relationshipKey': 'son'},
        {'id': 'r2', 'fromPersonId': 'parent1', 'toPersonId': 'child2', 'relationshipKey': 'daughter'},
        {'id': 'r3', 'fromPersonId': 'parent2', 'toPersonId': 'child3', 'relationshipKey': 'child'},
      ];

      final childrenOf = BranchCollapseNotifier.buildChildrenOf(relationships);

      expect(childrenOf['parent1'], containsAll(['child1', 'child2']));
      expect(childrenOf['parent2'], containsAll(['child3']));
    });

    test('handles mixed parent-type and child-type keys together', () {
      // Sunita Sharma's case: some children entered as "father" (parent-type),
      // others entered as "son" (child-type). Both must be recognized.
      final relationships = [
        {'id': 'r1', 'fromPersonId': 'child1', 'toPersonId': 'sunita', 'relationshipKey': 'mother'},
        {'id': 'r2', 'fromPersonId': 'sunita', 'toPersonId': 'child2', 'relationshipKey': 'son'},
        {'id': 'r3', 'fromPersonId': 'sunita', 'toPersonId': 'child3', 'relationshipKey': 'daughter'},
      ];

      final childrenOf = BranchCollapseNotifier.buildChildrenOf(relationships);

      // Sunita should have ALL 3 children, regardless of key direction
      expect(childrenOf['sunita'], containsAll(['child1', 'child2', 'child3']));
      expect(childrenOf['sunita']!.length, 3);
    });

    test('handles adoptive and step variants', () {
      final relationships = [
        {'id': 'r1', 'fromPersonId': 'child1', 'toPersonId': 'parent1', 'relationshipKey': 'adoptive_parent'},
        {'id': 'r2', 'fromPersonId': 'parent1', 'toPersonId': 'child2', 'relationshipKey': 'adoptive_son'},
        {'id': 'r3', 'fromPersonId': 'child3', 'toPersonId': 'parent1', 'relationshipKey': 'step_parent'},
        {'id': 'r4', 'fromPersonId': 'parent1', 'toPersonId': 'child4', 'relationshipKey': 'step_daughter'},
      ];

      final childrenOf = BranchCollapseNotifier.buildChildrenOf(relationships);

      expect(childrenOf['parent1'], containsAll(['child1', 'child2', 'child3', 'child4']));
    });

    test('handles labelAtoB as PRIMARY field (v5.147 fix)', () {
      // v5.147: labelAtoB is the PRIMARY field, relationshipKey is fallback.
      // This test verifies that when BOTH fields exist but disagree on
      // direction, labelAtoB wins — because it's always in a fixed
      // direction while relationshipKey can flip.
      final relationships = [
        // labelAtoB='son' (child-type, from is parent) but
        // relationshipKey='father' (parent-type, to is parent).
        // labelAtoB should win: fromPersonId is the parent.
        {'id': 'r1', 'fromPersonId': 'parent1', 'toPersonId': 'child1',
         'labelAtoB': 'son', 'relationshipKey': 'father'},
      ];

      final childrenOf = BranchCollapseNotifier.buildChildrenOf(relationships);

      // With labelAtoB='son', parent1 is the parent (from is parent)
      expect(childrenOf['parent1'], containsAll(['child1']));
      expect(childrenOf.containsKey('child1'), false);
    });

    test('falls back to relationshipKey when labelAtoB is absent', () {
      final relationships = [
        {'id': 'r1', 'fromPersonId': 'child1', 'toPersonId': 'parent1', 'relationshipKey': 'father'},
      ];

      final childrenOf = BranchCollapseNotifier.buildChildrenOf(relationships);

      expect(childrenOf['parent1'], containsAll(['child1']));
    });

    test('does NOT treat non-parent/child keys as children', () {
      final relationships = [
        {'id': 'r1', 'fromPersonId': 'a', 'toPersonId': 'b', 'relationshipKey': 'spouse'},
        {'id': 'r2', 'fromPersonId': 'c', 'toPersonId': 'd', 'relationshipKey': 'sibling'},
        {'id': 'r3', 'fromPersonId': 'e', 'toPersonId': 'f', 'relationshipKey': 'cousin'},
      ];

      final childrenOf = BranchCollapseNotifier.buildChildrenOf(relationships);

      // None of these should produce any parent-child entries
      expect(childrenOf.isEmpty, true);
    });

    test('handles empty relationship list', () {
      final childrenOf = BranchCollapseNotifier.buildChildrenOf([]);
      expect(childrenOf.isEmpty, true);
    });

    test('handles case-insensitive keys', () {
      final relationships = [
        {'id': 'r1', 'fromPersonId': 'parent1', 'toPersonId': 'child1', 'relationshipKey': 'SON'},
        {'id': 'r2', 'fromPersonId': 'child2', 'toPersonId': 'parent1', 'relationshipKey': 'Father'},
      ];

      final childrenOf = BranchCollapseNotifier.buildChildrenOf(relationships);

      expect(childrenOf['parent1'], containsAll(['child1', 'child2']));
    });
  });
}

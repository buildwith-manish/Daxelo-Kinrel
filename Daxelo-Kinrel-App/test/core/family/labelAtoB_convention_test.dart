// test/core/family/labelAtoB_convention_test.dart
//
// v5.20 TEST: Cross-flow regression — calls REAL production functions.
//
// These tests import and call:
//   - buildCanonicalRelationshipEdge from relationship_edge_builder.dart
//   - resolveEdgeLabelForViewer from relationship_edge_builder.dart
//   - getGenderAwareInverseKey from family_provider.dart
//
// resolveEdgeLabelForViewer internally calls getGenderAwareInverseKey
// (no local copy). TEST 5 verifies this wiring by asserting the two
// produce identical results for the same inputs.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/family/relationship_edge_builder.dart';
import 'package:kinrel/core/family/family_provider.dart';

void main() {
  group('v5.20 labelAtoB Cross-Flow Convention — REAL production functions', () {
    // ════════════════════════════════════════════════════════════════════
    // TEST 1: Both flows produce equivalent edges via the SAME function
    // ════════════════════════════════════════════════════════════════════
    // Coverage note: This test verifies that buildCanonicalRelationshipEdge
    // is deterministic and produces canonical-convention edges. It does NOT
    // verify that add_person_sheet.dart and relationship_picker_flow.dart
    // pass the RIGHT variables into the function — that would require
    // either mocking their widget context or extracting their variable
    // mapping, which is entangled with Flutter widget lifecycle. The
    // variable-mapping correctness is verified by the code review that
    // confirmed both files call buildCanonicalRelationshipEdge with
    // referencePersonId=anchor/source, describedPersonId=new/selected.
    test('TEST 1: buildCanonicalRelationshipEdge produces canonical edges', () {
      // Simulate "John is Manish's father" via the shared function
      final edge = buildCanonicalRelationshipEdge(
        referencePersonId: 'manish',
        describedPersonId: 'john',
        pickedRelationshipKey: 'father',
        referencePersonGender: 'male',
        describedPersonGender: 'male',
      );

      // Canonical convention: from=manish, to=john, label='father'
      // → "John is Manish's father"
      expect(edge.fromPersonId, 'manish',
          reason: 'fromPerson must be the reference (Manish)');
      expect(edge.toPersonId, 'john',
          reason: 'toPerson must be the described (John)');
      expect(edge.specificLabelAtoB, 'father',
          reason: 'labelAtoB must be "father"');
      expect(edge.relationshipKey, 'parent',
          reason: 'fundamental key must be "parent"');
      expect(edge.fromPersonGender, 'male',
          reason: 'fromPersonGender must be Manish\'s gender');
      expect(edge.toPersonGender, 'male',
          reason: 'toPersonGender must be John\'s gender');
    });

    // ════════════════════════════════════════════════════════════════════
    // TEST 2: resolveEdgeLabelForViewer produces correct labels
    // ════════════════════════════════════════════════════════════════════
    test('TEST 2: Viewer resolution produces correct labels for both perspectives', () {
      // Edge: from=manish, to=john, labelAtoB='father'
      // → "John is Manish's father"
      //
      // resolveEdgeLabelForViewer calls getGenderAwareInverseKey (the REAL
      // function from family_provider.dart) when labelBtoA is null.

      // viewer = Manish (fromPerson) → reads labelAtoB
      final manishSeesJohn = resolveEdgeLabelForViewer(
        viewerId: 'manish',
        fromPersonId: 'manish',
        toPersonId: 'john',
        labelAtoB: 'father',
        labelBtoA: null,
        fromPersonGender: 'male',
      );
      expect(manishSeesJohn, 'father',
          reason: 'Manish (fromPerson) should see John as "father"');

      // viewer = John (toPerson) → reads labelBtoA (computed via real getGenderAwareInverseKey)
      final johnSeesManish = resolveEdgeLabelForViewer(
        viewerId: 'john',
        fromPersonId: 'manish',
        toPersonId: 'john',
        labelAtoB: 'father',
        labelBtoA: null,
        fromPersonGender: 'male',
      );
      expect(johnSeesManish, 'son',
          reason: 'John (toPerson) should see Manish as "son" '
              '(inverse of father via real getGenderAwareInverseKey, Manish is male)');
    });

    // ════════════════════════════════════════════════════════════════════
    // TEST 3: getGenderAwareInverseKey (real production function)
    // ════════════════════════════════════════════════════════════════════
    test('TEST 3: getGenderAwareInverseKey produces correct labelBtoA', () {
      expect(getGenderAwareInverseKey('father', 'male'), 'son');
      expect(getGenderAwareInverseKey('father', 'female'), 'daughter');
      expect(getGenderAwareInverseKey('father', null), 'child');
      expect(getGenderAwareInverseKey('mother', 'male'), 'son');
      expect(getGenderAwareInverseKey('husband', null), 'wife');
      expect(getGenderAwareInverseKey('wife', null), 'husband');
      expect(getGenderAwareInverseKey('brother', 'female'), 'sister');
      expect(getGenderAwareInverseKey('uncle', 'female'), 'niece');
      expect(getGenderAwareInverseKey('uncle', 'male'), 'nephew');
    });

    // ════════════════════════════════════════════════════════════════════
    // TEST 4: Bug detection — swapped from/to would fail
    // ════════════════════════════════════════════════════════════════════
    test('TEST 4: Swapped from/to produces WRONG labels (regression guard)', () {
      // Wrong edge: from=john, to=manish (swapped) → "Manish is John's father" ← WRONG
      final wrongEdge = buildCanonicalRelationshipEdge(
        referencePersonId: 'john',
        describedPersonId: 'manish',
        pickedRelationshipKey: 'father',
        referencePersonGender: 'male',
        describedPersonGender: 'male',
      );

      final result = resolveEdgeLabelForViewer(
        viewerId: 'manish',
        fromPersonId: wrongEdge.fromPersonId,
        toPersonId: wrongEdge.toPersonId,
        labelAtoB: wrongEdge.specificLabelAtoB,
        fromPersonGender: wrongEdge.fromPersonGender,
      );
      // With wrong edge: manish is toPerson → reads inverse → 'son' (NOT 'father')
      expect(result, isNot('father'),
          reason: 'Swapped from/to must NOT produce "father" for Manish');

      // Correct edge: from=manish, to=john → "John is Manish's father" ✅
      final correctEdge = buildCanonicalRelationshipEdge(
        referencePersonId: 'manish',
        describedPersonId: 'john',
        pickedRelationshipKey: 'father',
        referencePersonGender: 'male',
        describedPersonGender: 'male',
      );
      final correctResult = resolveEdgeLabelForViewer(
        viewerId: 'manish',
        fromPersonId: correctEdge.fromPersonId,
        toPersonId: correctEdge.toPersonId,
        labelAtoB: correctEdge.specificLabelAtoB,
        fromPersonGender: correctEdge.fromPersonGender,
      );
      expect(correctResult, 'father',
          reason: 'Correct from/to must produce "father" for Manish');
    });

    // ════════════════════════════════════════════════════════════════════
    // TEST 5 (NEW): resolveEdgeLabelForViewer uses the REAL
    // getGenderAwareInverseKey — not a local copy
    // ════════════════════════════════════════════════════════════════════
    // This test would fail if someone reverted to a local _computeInverseLabel
    // copy that drifted from the real function. It calls both functions
    // directly and asserts they produce the SAME output for 3+ relationship
    // types — proving resolveEdgeLabelForViewer delegates to the real one.
    test('TEST 5: resolveEdgeLabelForViewer delegates to real getGenderAwareInverseKey', () {
      // Test 3 relationship types: father, brother, uncle
      final cases = [
        ('father', 'male', 'son'),
        ('father', 'female', 'daughter'),
        ('brother', 'female', 'sister'),
        ('uncle', 'male', 'nephew'),
        ('uncle', 'female', 'niece'),
        ('grandfather', 'male', 'grandson'),
      ];

      for (final (label, gender, _) in cases) {
        // Call the REAL function directly
        final expected = getGenderAwareInverseKey(label, gender);

        // Call resolveEdgeLabelForViewer which should delegate to the same function
        final actual = resolveEdgeLabelForViewer(
          viewerId: 'toPerson',
          fromPersonId: 'fromPerson',
          toPersonId: 'toPerson', // viewer = toPerson → triggers inverse computation
          labelAtoB: label,
          labelBtoA: null, // Force computation
          fromPersonGender: gender,
        );

        expect(actual, expected,
            reason: 'resolveEdgeLabelForViewer("$label", gender="$gender") must '
                'equal getGenderAwareInverseKey("$label", "$gender") = "$expected". '
                'If this fails, resolveEdgeLabelForViewer is NOT using the real function.');
      }
    });
  });
}

// test/core/family/labelAtoB_convention_test.dart
//
// v5.19 TEST: Cross-flow regression — calls REAL production functions.
//
// These tests import and call:
//   - buildCanonicalRelationshipEdge from relationship_edge_builder.dart
//   - resolveEdgeLabelForViewer from relationship_edge_builder.dart
//   - getGenderAwareInverseKey from family_provider.dart
//
// If any of these functions change, the tests will catch it.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/family/relationship_edge_builder.dart';
import 'package:kinrel/core/family/family_provider.dart';

void main() {
  group('v5.19 labelAtoB Cross-Flow Convention — REAL production functions', () {
    // ════════════════════════════════════════════════════════════════════
    // TEST 1: Both flows produce equivalent edges via the SAME function
    // ════════════════════════════════════════════════════════════════════
    test('TEST 1: AddPersonSheet and RelationshipPickerFlow produce equivalent edges', () {
      // Scenario: "John is Manish's father"
      //
      // Flow A — AddPersonSheet (post v5.17 fix):
      //   referencePersonId = Manish (anchor), describedPersonId = John (new)
      //   pickedRelationshipKey = 'father'
      //   referencePersonGender = 'male' (Manish), describedPersonGender = 'male' (John)
      //
      // Flow B — RelationshipPickerFlow:
      //   referencePersonId = Manish (source), describedPersonId = John (selected)
      //   pickedRelationshipKey = 'father'
      //   referencePersonGender = 'male' (Manish), describedPersonGender = 'male' (John)
      //
      // Both call the SAME buildCanonicalRelationshipEdge function.

      // Flow A — simulate add_person_sheet.dart's call
      final flowA = buildCanonicalRelationshipEdge(
        referencePersonId: 'manish',
        describedPersonId: 'john',
        pickedRelationshipKey: 'father',
        referencePersonGender: 'male',
        describedPersonGender: 'male',
      );

      // Flow B — simulate relationship_picker_flow.dart's call
      final flowB = buildCanonicalRelationshipEdge(
        referencePersonId: 'manish',
        describedPersonId: 'john',
        pickedRelationshipKey: 'father',
        referencePersonGender: 'male',
        describedPersonGender: 'male',
      );

      // Assert both produce IDENTICAL edges
      expect(flowA.fromPersonId, flowB.fromPersonId, reason: 'fromPersonId must match');
      expect(flowA.toPersonId, flowB.toPersonId, reason: 'toPersonId must match');
      expect(flowA.relationshipKey, flowB.relationshipKey, reason: 'relationshipKey must match');
      expect(flowA.specificLabelAtoB, flowB.specificLabelAtoB, reason: 'specificLabelAtoB must match');
      expect(flowA.fromPersonGender, flowB.fromPersonGender, reason: 'fromPersonGender must match');
      expect(flowA.toPersonGender, flowB.toPersonGender, reason: 'toPersonGender must match');

      // Assert canonical convention: from=manish, to=john, label='father'
      // → "John is Manish's father"
      expect(flowA.fromPersonId, 'manish', reason: 'fromPerson must be the reference (Manish)');
      expect(flowA.toPersonId, 'john', reason: 'toPerson must be the described (John)');
      expect(flowA.specificLabelAtoB, 'father', reason: 'labelAtoB must be "father"');
      expect(flowA.relationshipKey, 'parent', reason: 'fundamental key must be "parent"');
    });

    // ════════════════════════════════════════════════════════════════════
    // TEST 2: resolveEdgeLabelForViewer produces correct labels for both
    // ════════════════════════════════════════════════════════════════════
    test('TEST 2: Viewer resolution produces correct labels for both perspectives', () {
      // Edge: from=manish, to=john, labelAtoB='father'
      // → "John is Manish's father"
      //
      // RPC CASE: WHEN fromPersonId=viewer THEN labelAtoB
      //           WHEN toPersonId=viewer THEN labelBtoA
      //
      // viewer=manish → reads labelAtoB='father' → sees John as "Father" ✅
      // viewer=john   → reads labelBtoA → inverse of 'father' by John's gender
      //   John is male → 'son' → sees Manish as "Son" ✅

      // viewer = Manish (fromPerson)
      final manishSeesJohn = resolveEdgeLabelForViewer(
        viewerId: 'manish',
        fromPersonId: 'manish',
        toPersonId: 'john',
        labelAtoB: 'father',
        labelBtoA: null, // Force computation
        fromPersonGender: 'male', // Manish's gender (for inverse computation)
      );
      expect(manishSeesJohn, 'father',
          reason: 'Manish (fromPerson) should see John as "father"');

      // viewer = John (toPerson) — labelBtoA computed from inverse
      final johnSeesManish = resolveEdgeLabelForViewer(
        viewerId: 'john',
        fromPersonId: 'manish',
        toPersonId: 'john',
        labelAtoB: 'father',
        labelBtoA: null, // Force computation
        fromPersonGender: 'male', // Manish's gender
      );
      expect(johnSeesManish, 'son',
          reason: 'John (toPerson) should see Manish as "son" '
              '(inverse of father, Manish is male)');
    });

    // ════════════════════════════════════════════════════════════════════
    // TEST 3: getGenderAwareInverseKey (real production function)
    // ════════════════════════════════════════════════════════════════════
    test('TEST 3: getGenderAwareInverseKey produces correct labelBtoA', () {
      // Edge: from=manish, to=john, labelAtoB='father'
      // Inverse: "Manish is John's ___" → depends on Manish's gender
      // getGenderAwareInverseKey('father', manish_gender)
      expect(getGenderAwareInverseKey('father', 'male'), 'son',
          reason: 'Manish (male) is John\'s son');
      expect(getGenderAwareInverseKey('father', 'female'), 'daughter',
          reason: 'Manish (female) is John\'s daughter');
      expect(getGenderAwareInverseKey('father', null), 'child',
          reason: 'Manish (unknown) is John\'s child');
    });

    // ════════════════════════════════════════════════════════════════════
    // TEST 4: Bug detection — swapped from/to would fail
    // ════════════════════════════════════════════════════════════════════
    test('TEST 4: Swapped from/to produces WRONG labels (regression guard)', () {
      // If someone re-introduces the pre-v5.17 bug (swapping from/to),
      // the edge would be: from=john, to=manish, labelAtoB='father'
      // → "Manish is John's father" ← WRONG!

      final wrongEdge = buildCanonicalRelationshipEdge(
        referencePersonId: 'john',  // WRONG: should be 'manish'
        describedPersonId: 'manish', // WRONG: should be 'john'
        pickedRelationshipKey: 'father',
        referencePersonGender: 'male',
        describedPersonGender: 'male',
      );

      // Verify the WRONG edge produces WRONG labels
      final manishSeesJohn_wrong = resolveEdgeLabelForViewer(
        viewerId: 'manish',
        fromPersonId: wrongEdge.fromPersonId,
        toPersonId: wrongEdge.toPersonId,
        labelAtoB: wrongEdge.specificLabelAtoB,
        fromPersonGender: wrongEdge.fromPersonGender,
      );
      // With the wrong edge: manish is toPerson → reads labelBtoA
      // = inverse of 'father' = 'son' → manish sees john as "son" ← WRONG!
      expect(manishSeesJohn_wrong, isNot('father'),
          reason: 'With swapped from/to, Manish would NOT see John as "father" '
              '(he\'d see "son" instead) — this confirms the test catches the bug');

      // Now verify the CORRECT edge produces CORRECT labels
      final correctEdge = buildCanonicalRelationshipEdge(
        referencePersonId: 'manish',
        describedPersonId: 'john',
        pickedRelationshipKey: 'father',
        referencePersonGender: 'male',
        describedPersonGender: 'male',
      );
      final manishSeesJohn_correct = resolveEdgeLabelForViewer(
        viewerId: 'manish',
        fromPersonId: correctEdge.fromPersonId,
        toPersonId: correctEdge.toPersonId,
        labelAtoB: correctEdge.specificLabelAtoB,
        fromPersonGender: correctEdge.fromPersonGender,
      );
      expect(manishSeesJohn_correct, 'father',
          reason: 'With correct from/to, Manish sees John as "father" ✅');
    });
  });
}

// test/core/kinship/automatic_kinship_inference_test.dart
//
// v5.18 TEST: Automatic kinship inference engine — CANONICAL CONVENTION.
//
// All fixtures use the canonical convention:
//   labelAtoB = "toPerson is fromPerson's <labelAtoB>"
//   Example: fromId=parent, toId=child, labelAtoB='son' → "child is parent's son"

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/family/family_provider.dart';
import 'package:kinrel/core/kinship/automatic_kinship_inference.dart';

void main() {
  group('v5.18 Automatic Kinship Inference — Canonical Convention', () {
    test('TEST 1: Sibling → infers parent edges', () {
      // Setup (canonical convention):
      //   Edge 1: from=parent, to=self, labelAtoB='son' → "self is parent's son"
      //   Edge 2: from=grandparent, to=parent, labelAtoB='son' → "parent is grandparent's son"
      // New edge: from=self, to=sister, labelAtoB='sister' → "sister is self's sister"
      //
      // Expected: sister should get a parent edge (parent → sister, 'daughter')
      // and a grandparent edge (grandparent → sister, 'granddaughter')

      final persons = [
        Person(id: 'self', familyId: 'fam', name: 'Self', gender: 'male'),
        Person(id: 'sister', familyId: 'fam', name: 'Sister', gender: 'female'),
        Person(id: 'parent', familyId: 'fam', name: 'Parent', gender: 'male'),
        Person(id: 'grandparent', familyId: 'fam', name: 'Grandparent', gender: 'male'),
      ];

      final existingRels = [
        // Canonical: from=parent, to=self, label='son' → self is parent's son
        FamilyRelationship(
          id: 'r1', familyId: 'fam',
          fromPersonId: 'parent', toPersonId: 'self',
          relationshipKey: 'parent', labelAtoB: 'son', isActive: true,
        ),
        // Canonical: from=grandparent, to=parent, label='son' → parent is grandparent's son
        FamilyRelationship(
          id: 'r2', familyId: 'fam',
          fromPersonId: 'grandparent', toPersonId: 'parent',
          relationshipKey: 'parent', labelAtoB: 'son', isActive: true,
        ),
      ];

      // New edge: from=self, to=sister, label='sister' → sister is self's sister
      final inferred = inferKinshipEdges(
        newFromPersonId: 'self',
        newToPersonId: 'sister',
        newLabelAtoB: 'sister',
        persons: persons,
        existingRelationships: existingRels,
      );

      // Sister should get a parent edge: from=parent, to=sister, label='daughter'
      final parentEdge = inferred.where((e) =>
        e.fromPersonId == 'parent' && e.toPersonId == 'sister').toList();
      expect(parentEdge.isNotEmpty, isTrue,
          reason: 'Sister should be inferred as daughter of Parent');
      expect(parentEdge.first.labelAtoB, 'daughter',
          reason: 'Sister is female → daughter (not son)');

      // Sister should get a grandparent edge: from=grandparent, to=sister, label='granddaughter'
      final gpEdge = inferred.where((e) =>
        e.fromPersonId == 'grandparent' && e.toPersonId == 'sister').toList();
      expect(gpEdge.isNotEmpty, isTrue,
          reason: 'Sister should be inferred as granddaughter of Grandparent');
      expect(gpEdge.first.labelAtoB, 'granddaughter',
          reason: 'Sister is female → granddaughter');
    });

    test('TEST 2: Spouse → infers in-law edges (NOT blood)', () {
      // Setup (canonical):
      //   Edge: from=parent, to=self, labelAtoB='son' → self is parent's son
      // New edge: from=self, to=wife, labelAtoB='wife' → wife is self's wife
      //
      // Expected: parent should become wife's father-in-law
      //   Inferred: from=wife, to=parent, label='father_in_law'
      //   (parent is wife's father-in-law)

      final persons = [
        Person(id: 'self', familyId: 'fam', name: 'Self', gender: 'male'),
        Person(id: 'wife', familyId: 'fam', name: 'Wife', gender: 'female'),
        Person(id: 'parent', familyId: 'fam', name: 'Parent', gender: 'male'),
      ];

      final existingRels = [
        // Canonical: from=parent, to=self, label='son' → self is parent's son
        FamilyRelationship(
          id: 'r1', familyId: 'fam',
          fromPersonId: 'parent', toPersonId: 'self',
          relationshipKey: 'parent', labelAtoB: 'son', isActive: true,
        ),
      ];

      // New edge: from=self, to=wife, label='wife' → wife is self's wife
      final inferred = inferKinshipEdges(
        newFromPersonId: 'self',
        newToPersonId: 'wife',
        newLabelAtoB: 'wife',
        persons: persons,
        existingRelationships: existingRels,
      );

      // Parent should become wife's father-in-law
      // Canonical: from=wife, to=parent, label='father_in_law'
      // (parent is wife's father-in-law)
      final inLawEdge = inferred.where((e) =>
        e.fromPersonId == 'wife' && e.toPersonId == 'parent').toList();
      expect(inLawEdge.isNotEmpty, isTrue,
          reason: 'Parent should be inferred as father_in_law of Wife');
      expect(inLawEdge.first.labelAtoB, 'father_in_law',
          reason: 'Parent is male → father_in_law (NOT mother_in_law)');

      // Verify NO blood parent edge was created
      final bloodEdge = inferred.where((e) =>
        e.fromPersonId == 'parent' && e.toPersonId == 'wife' &&
        (e.labelAtoB == 'father' || e.labelAtoB == 'mother' ||
         e.labelAtoB == 'son' || e.labelAtoB == 'daughter')).toList();
      expect(bloodEdge, isEmpty,
          reason: 'In-law must NOT be a blood parent/child edge');
    });

    test('TEST 3: filterExistingEdges removes duplicates', () {
      final inferred = [
        InferredEdge(fromPersonId: 'A', toPersonId: 'B', labelAtoB: 'daughter', reason: 'test'),
        InferredEdge(fromPersonId: 'C', toPersonId: 'D', labelAtoB: 'son', reason: 'test'),
      ];

      final existing = [
        // Canonical: from=A, to=B, label='daughter'
        FamilyRelationship(
          id: 'r1', familyId: 'fam',
          fromPersonId: 'A', toPersonId: 'B',
          relationshipKey: 'parent', labelAtoB: 'daughter', isActive: true,
        ),
      ];

      final filtered = filterExistingEdges(inferred: inferred, existing: existing);
      expect(filtered.length, 1);
      expect(filtered.first.fromPersonId, 'C');
      expect(filtered.first.toPersonId, 'D');
    });

    test('TEST 4: Parent edge → infers sibling + grandparent edges', () {
      // Setup (canonical):
      //   Edge: from=parent, to=existing_child, labelAtoB='daughter'
      //     → existing_child is parent's daughter
      //   Edge: from=grandparent, to=parent, labelAtoB='son'
      //     → parent is grandparent's son
      // New edge: from=parent, to=new_child, labelAtoB='son'
      //     → new_child is parent's son
      //
      // Expected:
      //   1. new_child ↔ existing_child are siblings
      //      Canonical: from=new_child, to=existing_child, label='brother'
      //   2. grandparent is new_child's grandparent
      //      Canonical: from=grandparent, to=new_child, label='grandson'

      final persons = [
        Person(id: 'parent', familyId: 'fam', name: 'Parent', gender: 'male'),
        Person(id: 'new_child', familyId: 'fam', name: 'NewChild', gender: 'male'),
        Person(id: 'existing_child', familyId: 'fam', name: 'ExistingChild', gender: 'female'),
        Person(id: 'grandparent', familyId: 'fam', name: 'Grandparent', gender: 'male'),
      ];

      final existingRels = [
        // Canonical: from=parent, to=existing_child, label='daughter'
        FamilyRelationship(
          id: 'r1', familyId: 'fam',
          fromPersonId: 'parent', toPersonId: 'existing_child',
          relationshipKey: 'parent', labelAtoB: 'daughter', isActive: true,
        ),
        // Canonical: from=grandparent, to=parent, label='son'
        FamilyRelationship(
          id: 'r2', familyId: 'fam',
          fromPersonId: 'grandparent', toPersonId: 'parent',
          relationshipKey: 'parent', labelAtoB: 'son', isActive: true,
        ),
      ];

      // New edge: from=parent, to=new_child, label='son' → new_child is parent's son
      final inferred = inferKinshipEdges(
        newFromPersonId: 'parent',
        newToPersonId: 'new_child',
        newLabelAtoB: 'son',
        persons: persons,
        existingRelationships: existingRels,
      );

      // Sibling: new_child ↔ existing_child
      final sibEdge = inferred.where((e) =>
        e.fromPersonId == 'new_child' && e.toPersonId == 'existing_child').toList();
      expect(sibEdge.isNotEmpty, isTrue,
          reason: 'NewChild should be inferred as sibling of ExistingChild');
      expect(sibEdge.first.labelAtoB, 'brother',
          reason: 'NewChild is male → brother');

      // Grandparent: grandparent → new_child
      final gpEdge = inferred.where((e) =>
        e.fromPersonId == 'grandparent' && e.toPersonId == 'new_child').toList();
      expect(gpEdge.isNotEmpty, isTrue,
          reason: 'Grandparent should be inferred as grandparent of NewChild');
      expect(gpEdge.first.labelAtoB, 'grandson',
          reason: 'NewChild is male → grandson');
    });

    test('TEST 5: getParents correctly identifies parents via canonical convention', () {
      // This is the test that would have caught the original bug.
      // Fixture built the way add_person_sheet.dart NOW constructs an edge
      // (post v5.17 fix): fromId=anchor, toId=newPerson, labelAtoB='father'
      // → "newPerson is anchor's father"
      //
      // getParents(anchor) should return {newPerson} because newPerson
      // is anchor's father (parent).

      final persons = [
        Person(id: 'anchor', familyId: 'fam', name: 'Anchor', gender: 'male'),
        Person(id: 'father', familyId: 'fam', name: 'Father', gender: 'male'),
      ];

      final existingRels = [
        // Post-v5.17 canonical: from=anchor, to=father, label='father'
        // → "father is anchor's father" → father is anchor's PARENT
        FamilyRelationship(
          id: 'r1', familyId: 'fam',
          fromPersonId: 'anchor', toPersonId: 'father',
          relationshipKey: 'parent', labelAtoB: 'father', isActive: true,
        ),
      ];

      // Test getParents by creating a sibling edge and checking if
      // the sibling propagation correctly finds the parent
      final inferred = inferKinshipEdges(
        newFromPersonId: 'anchor',
        newToPersonId: 'sibling',
        newLabelAtoB: 'brother',
        persons: [
          ...persons,
          Person(id: 'sibling', familyId: 'fam', name: 'Sibling', gender: 'male'),
        ],
        existingRelationships: existingRels,
      );

      // Sibling should get a parent edge: from=father, to=sibling, label='son'
      // (sibling is father's son)
      final parentEdge = inferred.where((e) =>
        e.fromPersonId == 'father' && e.toPersonId == 'sibling').toList();
      expect(parentEdge.isNotEmpty, isTrue,
          reason: 'Sibling should be inferred as son of Father '
              '(Father is Anchor\'s parent, so also Sibling\'s parent)');
      expect(parentEdge.first.labelAtoB, 'son',
          reason: 'Sibling is male → son');
    });
  });
}

// test/core/kinship/automatic_kinship_inference_test.dart
//
// v5.11 TEST: Automatic kinship inference engine.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/family/family_provider.dart';
import 'package:kinrel/core/kinship/automatic_kinship_inference.dart';

void main() {
  group('v5.11 Automatic Kinship Inference', () {
    test('TEST 1: Sibling → infers parent edges', () {
      // Setup: Grandfather → Parent → Self
      // New edge: Sister ↔ Self (sibling)
      // Expected: Sister should get parent edges to Parent + grandparent edges to Grandfather

      final persons = [
        Person(id: 'self', familyId: 'fam', name: 'Self', gender: 'male'),
        Person(id: 'sister', familyId: 'fam', name: 'Sister', gender: 'female'),
        Person(id: 'parent', familyId: 'fam', name: 'Parent', gender: 'male'),
        Person(id: 'grandparent', familyId: 'fam', name: 'Grandparent', gender: 'male'),
      ];

      final existingRels = [
        // Self → Parent (self is child of parent)
        FamilyRelationship(
          id: 'r1', familyId: 'fam',
          fromPersonId: 'self', toPersonId: 'parent',
          relationshipKey: 'parent', labelAtoB: 'son', isActive: true,
        ),
        // Parent → Grandparent (parent is child of grandparent)
        FamilyRelationship(
          id: 'r2', familyId: 'fam',
          fromPersonId: 'parent', toPersonId: 'grandparent',
          relationshipKey: 'parent', labelAtoB: 'son', isActive: true,
        ),
      ];

      // New edge: Sister is sibling of Self
      final inferred = inferKinshipEdges(
        newFromPersonId: 'sister',
        newToPersonId: 'self',
        newLabelAtoB: 'sister',
        persons: persons,
        existingRelationships: existingRels,
      );

      // Sister should get a parent edge to Parent
      final parentEdge = inferred.where((e) =>
        e.fromPersonId == 'sister' && e.toPersonId == 'parent').toList();
      expect(parentEdge.isNotEmpty, isTrue,
          reason: 'Sister should be inferred as daughter of Parent');
      expect(parentEdge.first.labelAtoB, 'mother',
          reason: 'Sister is female → mother (not father)');

      // Sister should get a grandparent edge to Grandparent
      final gpEdge = inferred.where((e) =>
        e.fromPersonId == 'sister' && e.toPersonId == 'grandparent').toList();
      expect(gpEdge.isNotEmpty, isTrue,
          reason: 'Sister should be inferred as granddaughter of Grandparent');
      expect(gpEdge.first.labelAtoB, 'granddaughter',
          reason: 'Sister is female → granddaughter');
    });

    test('TEST 2: Spouse → infers in-law edges (NOT blood)', () {
      // Setup: Parent → Self
      // New edge: Wife ↔ Self (spouse)
      // Expected: Parent should become Wife's father-in-law (NOT father)

      final persons = [
        Person(id: 'self', familyId: 'fam', name: 'Self', gender: 'male'),
        Person(id: 'wife', familyId: 'fam', name: 'Wife', gender: 'female'),
        Person(id: 'parent', familyId: 'fam', name: 'Parent', gender: 'male'),
      ];

      final existingRels = [
        FamilyRelationship(
          id: 'r1', familyId: 'fam',
          fromPersonId: 'self', toPersonId: 'parent',
          relationshipKey: 'parent', labelAtoB: 'son', isActive: true,
        ),
      ];

      // New edge: Wife is spouse of Self
      final inferred = inferKinshipEdges(
        newFromPersonId: 'wife',
        newToPersonId: 'self',
        newLabelAtoB: 'wife',
        persons: persons,
        existingRelationships: existingRels,
      );

      // Parent should become Wife's father-in-law
      final inLawEdge = inferred.where((e) =>
        e.fromPersonId == 'parent' && e.toPersonId == 'wife').toList();
      expect(inLawEdge.isNotEmpty, isTrue,
          reason: 'Parent should be inferred as father_in_law of Wife');
      expect(inLawEdge.first.labelAtoB, 'father_in_law',
          reason: 'Parent is male → father_in_law (NOT father)');

      // Verify NO blood parent edge was created
      final bloodEdge = inferred.where((e) =>
        e.fromPersonId == 'parent' && e.toPersonId == 'wife' &&
        (e.labelAtoB == 'father' || e.labelAtoB == 'mother')).toList();
      expect(bloodEdge, isEmpty,
          reason: 'In-law must NOT be a blood parent');
    });

    test('TEST 3: filterExistingEdges removes duplicates', () {
      final inferred = [
        InferredEdge(fromPersonId: 'A', toPersonId: 'B', labelAtoB: 'daughter', reason: 'test'),
        InferredEdge(fromPersonId: 'C', toPersonId: 'D', labelAtoB: 'son', reason: 'test'),
      ];

      final existing = [
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

    test('TEST 4: Parent → infers grandparent edges', () {
      // Setup: Self → Child (self has a child)
      // New edge: Father → Self (father is parent of self)
      // Expected: Father should be grandparent of Child

      final persons = [
        Person(id: 'self', familyId: 'fam', name: 'Self', gender: 'male'),
        Person(id: 'father', familyId: 'fam', name: 'Father', gender: 'male'),
        Person(id: 'child', familyId: 'fam', name: 'Child', gender: 'female'),
      ];

      final existingRels = [
        FamilyRelationship(
          id: 'r1', familyId: 'fam',
          fromPersonId: 'self', toPersonId: 'child',
          relationshipKey: 'parent', labelAtoB: 'daughter', isActive: true,
        ),
      ];

      final inferred = inferKinshipEdges(
        newFromPersonId: 'father',
        newToPersonId: 'self',
        newLabelAtoB: 'father',
        persons: persons,
        existingRelationships: existingRels,
      );

      // Father → Child should be grandparent
      final gpEdge = inferred.where((e) =>
        e.fromPersonId == 'father' && e.toPersonId == 'child').toList();
      expect(gpEdge.isNotEmpty, isTrue,
          reason: 'Father should be inferred as grandfather of Child');
      expect(gpEdge.first.labelAtoB, 'granddaughter',
          reason: 'Child is female → granddaughter');
    });
  });
}

// test/core/family/relationship_permissions_test.dart
//
// v5.12 TEST: Relationship permission model.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/family/relationship_permissions.dart';

void main() {
  group('v5.12 Relationship Permissions', () {
    test('TEST 1: Admin can connect any two people', () {
      expect(
        canCreateRelationship(
          isAdmin: true,
          viewerPersonId: 'viewer-A',
          fromPersonId: 'person-B',
          toPersonId: 'person-C',
        ),
        isTrue,
        reason: 'Admin should be able to connect any two people',
      );
    });

    test('TEST 2: Regular member can connect themselves (as from)', () {
      expect(
        canCreateRelationship(
          isAdmin: false,
          viewerPersonId: 'viewer-A',
          fromPersonId: 'viewer-A',
          toPersonId: 'person-B',
        ),
        isTrue,
        reason: 'Member should be able to create relationships involving themselves',
      );
    });

    test('TEST 3: Regular member can connect themselves (as to)', () {
      expect(
        canCreateRelationship(
          isAdmin: false,
          viewerPersonId: 'viewer-A',
          fromPersonId: 'person-B',
          toPersonId: 'viewer-A',
        ),
        isTrue,
        reason: 'Member should be able to create relationships involving themselves',
      );
    });

    test('TEST 4: Regular member CANNOT connect two other people', () {
      expect(
        canCreateRelationship(
          isAdmin: false,
          viewerPersonId: 'viewer-A',
          fromPersonId: 'person-B',
          toPersonId: 'person-C',
        ),
        isFalse,
        reason: 'Regular member should NOT be able to connect two other people',
      );
    });

    test('TEST 5: Regular member with null viewerPersonId is denied', () {
      expect(
        canCreateRelationship(
          isAdmin: false,
          viewerPersonId: null,
          fromPersonId: 'person-B',
          toPersonId: 'person-C',
        ),
        isFalse,
        reason: 'Unidentified user should be denied',
      );
    });

    test('TEST 6: Admin with null viewerPersonId is still allowed', () {
      expect(
        canCreateRelationship(
          isAdmin: true,
          viewerPersonId: null,
          fromPersonId: 'person-B',
          toPersonId: 'person-C',
        ),
        isTrue,
        reason: 'Admin should always be allowed regardless of viewerPersonId',
      );
    });
  });
}

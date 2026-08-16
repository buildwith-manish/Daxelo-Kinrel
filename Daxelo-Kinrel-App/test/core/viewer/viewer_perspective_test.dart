// test/core/viewer/viewer_perspective_test.dart
//
// v5.16 TEST: Real unit tests for viewer resolution + gender-aware inverse.
//
// These tests import and call the ACTUAL production functions — no
// copies, no mocks, no Riverpod override tricks. If the production
// logic changes, these tests will catch it.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/viewer/viewer_provider.dart';
import 'package:kinrel/core/family/family_provider.dart';

void main() {
  group('v5.16 resolveViewerPersonId — pure resolution logic', () {
    test('TEST 1: linked person present → returns linked person ID (ignores anchor)', () {
      final result = resolveViewerPersonId(
        result: const ViewerQueryResult(
          linkedPersonId: 'person-linked',
          anchorPersonId: 'person-anchor',
          anchorLinkedUserId: 'user-123',
        ),
        currentUserId: 'user-123',
      );
      expect(result, 'person-linked',
          reason: 'When a linked Person is found, it should be used directly '
              'regardless of what the anchor is');
    });

    test('TEST 2: linked person absent, anchor IS current user → returns anchor ID', () {
      final result = resolveViewerPersonId(
        result: const ViewerQueryResult(
          linkedPersonId: null,
          anchorPersonId: 'person-anchor',
          anchorLinkedUserId: 'user-123',
        ),
        currentUserId: 'user-123',
      );
      expect(result, 'person-anchor',
          reason: 'When no linked Person exists but the anchor IS the current '
              'user, the anchor should be used as fallback');
    });

    test('TEST 3: linked person absent, anchor is DIFFERENT user → returns null', () {
      final result = resolveViewerPersonId(
        result: const ViewerQueryResult(
          linkedPersonId: null,
          anchorPersonId: 'person-anchor',
          anchorLinkedUserId: 'user-456', // Different user!
        ),
        currentUserId: 'user-123',
      );
      expect(result, isNull,
          reason: 'When the anchor belongs to a DIFFERENT user, must NOT '
              'fall back to it — showing the wrong person as "You" is worse '
              'than showing no "You" at all');
    });

    test('TEST 4: linked person absent, anchor has no linkedUserId → returns null', () {
      final result = resolveViewerPersonId(
        result: const ViewerQueryResult(
          linkedPersonId: null,
          anchorPersonId: 'person-anchor',
          anchorLinkedUserId: null, // Anchor has no linked user
        ),
        currentUserId: 'user-123',
      );
      expect(result, isNull,
          reason: 'When the anchor has no linkedUserId, we cannot confirm it '
              'belongs to the current user — must return null');
    });

    test('TEST 5: both absent → returns null', () {
      final result = resolveViewerPersonId(
        result: const ViewerQueryResult(
          linkedPersonId: null,
          anchorPersonId: null,
          anchorLinkedUserId: null,
        ),
        currentUserId: 'user-123',
      );
      expect(result, isNull,
          reason: 'When neither a linked Person nor an anchor exists, '
              'must return null');
    });

    test('TEST 6: no authenticated user (currentUserId null) → returns null', () {
      final result = resolveViewerPersonId(
        result: const ViewerQueryResult(
          linkedPersonId: null,
          anchorPersonId: 'person-anchor',
          anchorLinkedUserId: null,
        ),
        currentUserId: null,
      );
      expect(result, isNull,
          reason: 'When there is no authenticated user, must return null '
              'even if an anchor exists');
    });

    test('TEST 7: empty linkedPersonId string → treated as null', () {
      final result = resolveViewerPersonId(
        result: const ViewerQueryResult(
          linkedPersonId: '',
          anchorPersonId: 'person-anchor',
          anchorLinkedUserId: 'user-123',
        ),
        currentUserId: 'user-123',
      );
      expect(result, 'person-anchor',
          reason: 'An empty string linkedPersonId should be treated as '
              '"not found" and fall through to the anchor check');
    });
  });

  group('v5.16 isViewerLinked — pure linked check', () {
    test('non-null viewer ID → linked', () {
      expect(isViewerLinked('person-123'), isTrue);
    });

    test('null viewer ID → not linked', () {
      expect(isViewerLinked(null), isFalse);
    });

    test('empty viewer ID → not linked', () {
      expect(isViewerLinked(''), isFalse);
    });
  });

  group('v5.16 getGenderAwareInverseKey — real production function', () {
    // These tests import and call the ACTUAL getGenderAwareInverseKey
    // from family_provider.dart. If that function changes, these tests
    // will catch it — unlike the old Test 5 which tested a copy.

    test('father → son (male fromPerson)', () {
      expect(getGenderAwareInverseKey('father', 'male'), 'son');
    });

    test('father → daughter (female fromPerson)', () {
      expect(getGenderAwareInverseKey('father', 'female'), 'daughter');
    });

    test('father → child (null gender fallback)', () {
      expect(getGenderAwareInverseKey('father', null), 'child');
    });

    test('mother → son (male fromPerson)', () {
      expect(getGenderAwareInverseKey('mother', 'male'), 'son');
    });

    test('mother → daughter (female fromPerson)', () {
      expect(getGenderAwareInverseKey('mother', 'female'), 'daughter');
    });

    test('husband → wife', () {
      expect(getGenderAwareInverseKey('husband', null), 'wife');
    });

    test('wife → husband', () {
      expect(getGenderAwareInverseKey('wife', null), 'husband');
    });

    test('grandfather → grandson (male fromPerson)', () {
      expect(getGenderAwareInverseKey('grandfather', 'male'), 'grandson');
    });

    test('grandfather → granddaughter (female fromPerson)', () {
      expect(getGenderAwareInverseKey('grandfather', 'female'), 'granddaughter');
    });

    test('uncle → nephew (male fromPerson)', () {
      expect(getGenderAwareInverseKey('uncle', 'male'), 'nephew');
    });

    test('uncle → niece (female fromPerson)', () {
      expect(getGenderAwareInverseKey('uncle', 'female'), 'niece');
    });

    test('uncle → nephew_or_niece (null gender fallback)', () {
      expect(getGenderAwareInverseKey('uncle', null), 'nephew_or_niece');
    });

    test('brother → brother (male fromPerson)', () {
      expect(getGenderAwareInverseKey('brother', 'male'), 'brother');
    });

    test('brother → sister (female fromPerson)', () {
      expect(getGenderAwareInverseKey('brother', 'female'), 'sister');
    });

    test('spouse → spouse (symmetric)', () {
      expect(getGenderAwareInverseKey('spouse', null), 'spouse');
    });

    test('cousin → cousin (symmetric)', () {
      expect(getGenderAwareInverseKey('cousin', null), 'cousin');
    });

    test('son → father (male fromPerson)', () {
      expect(getGenderAwareInverseKey('son', 'male'), 'father');
    });

    test('son → mother (female fromPerson)', () {
      expect(getGenderAwareInverseKey('son', 'female'), 'mother');
    });
  });
}

// test/core/family/profile_visibility_test.dart
//
// v5.21 TEST: Three-tier profile visibility resolver.
//
// These tests call the REAL resolveViewerTier() and isMinorByDateOfBirth()
// functions from profile_visibility.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/family/profile_visibility.dart';

void main() {
  group('v5.21 resolveViewerTier — pure resolution logic', () {
    test('TEST 1: viewer == target → owner', () {
      final tier = resolveViewerTier(
        viewerPersonId: 'person-A',
        targetPersonId: 'person-A',
        viewerFamilyIds: {'fam-1'},
        targetFamilyId: 'fam-1',
        isMinor: false,
        isBlocked: false,
      );
      expect(tier, ProfileViewerTier.owner);
    });

    test('TEST 2: same family, not blocked, not minor → connected', () {
      final tier = resolveViewerTier(
        viewerPersonId: 'person-A',
        targetPersonId: 'person-B',
        viewerFamilyIds: {'fam-1'},
        targetFamilyId: 'fam-1',
        isMinor: false,
        isBlocked: false,
      );
      expect(tier, ProfileViewerTier.connected);
    });

    test('TEST 3: different family, not blocked, not minor → public', () {
      final tier = resolveViewerTier(
        viewerPersonId: 'person-A',
        targetPersonId: 'person-B',
        viewerFamilyIds: {'fam-1'},
        targetFamilyId: 'fam-2',
        isMinor: false,
        isBlocked: false,
      );
      expect(tier, ProfileViewerTier.public);
    });

    test('TEST 4: blocked → denied (regardless of family)', () {
      final tier = resolveViewerTier(
        viewerPersonId: 'person-A',
        targetPersonId: 'person-B',
        viewerFamilyIds: {'fam-1'},
        targetFamilyId: 'fam-1',
        isMinor: false,
        isBlocked: true,
      );
      expect(tier, ProfileViewerTier.denied);
    });

    test('TEST 5: MINOR SAFETY — minor viewed by non-family → denied', () {
      final tier = resolveViewerTier(
        viewerPersonId: 'person-A',
        targetPersonId: 'person-B',
        viewerFamilyIds: {'fam-1'},
        targetFamilyId: 'fam-2', // Different family!
        isMinor: true,
        isBlocked: false,
      );
      expect(tier, ProfileViewerTier.denied,
          reason: 'A minor must NEVER be visible to public strangers, '
              'regardless of any visibility setting.');
    });

    test('TEST 6: MINOR SAFETY — minor viewed by same-family → connected', () {
      final tier = resolveViewerTier(
        viewerPersonId: 'person-A',
        targetPersonId: 'person-B',
        viewerFamilyIds: {'fam-1'},
        targetFamilyId: 'fam-1', // Same family
        isMinor: true,
        isBlocked: false,
      );
      expect(tier, ProfileViewerTier.connected,
          reason: 'A minor viewed by a family member should be connected '
              '(not public, not denied).');
    });

    test('TEST 7: MINOR SAFETY — minor + blocked → denied (blocked wins)', () {
      final tier = resolveViewerTier(
        viewerPersonId: 'person-A',
        targetPersonId: 'person-B',
        viewerFamilyIds: {'fam-1'},
        targetFamilyId: 'fam-1',
        isMinor: true,
        isBlocked: true,
      );
      expect(tier, ProfileViewerTier.denied,
          reason: 'Blocked takes priority over everything.');
    });

    test('TEST 8: null viewerPersonId → public (if not blocked, not minor)', () {
      final tier = resolveViewerTier(
        viewerPersonId: null,
        targetPersonId: 'person-B',
        viewerFamilyIds: {},
        targetFamilyId: 'fam-1',
        isMinor: false,
        isBlocked: false,
      );
      expect(tier, ProfileViewerTier.public,
          reason: 'Unauthenticated viewer with no family → public tier.');
    });
  });

  group('v5.21 isMinorByDateOfBirth', () {
    test('TEST 9: born 5 years ago → minor', () {
      final dob = DateTime.now().subtract(const Duration(days: 365 * 5));
      expect(isMinorByDateOfBirth(dob), isTrue);
    });

    test('TEST 10: born 20 years ago → NOT minor', () {
      final dob = DateTime.now().subtract(const Duration(days: 365 * 20));
      expect(isMinorByDateOfBirth(dob), isFalse);
    });

    test('TEST 11: null dateOfBirth → NOT minor (unknown age)', () {
      expect(isMinorByDateOfBirth(null), isFalse);
    });

    test('TEST 12: born exactly 17 years ago → minor', () {
      // v5.123: calendar-correct DOB (18*365 days ≈ 17y 360d because of
      // leap days — the old Duration-based DOB was NOT "exactly 17
      // years" and made these boundary tests off-by-a-few-days).
      final now = DateTime.now();
      final dob = DateTime(now.year - 17, now.month, now.day);
      expect(isMinorByDateOfBirth(dob), isTrue);
    });

    test('TEST 13: born exactly 18 years ago → NOT minor', () {
      // v5.123: calendar-correct DOB. The old
      // `DateTime.now().subtract(Duration(days: 365 * 18))` lands ~4-5
      // leap days SHORT of 18 calendar years, so the person was still
      // 17 — the test asserted the wrong premise.
      final now = DateTime.now();
      final dob = DateTime(now.year - 18, now.month, now.day);
      expect(isMinorByDateOfBirth(dob), isFalse);
    });
  });

  group('v5.21 computeFieldVisibility', () {
    test('TEST 14: owner tier → all fields visible', () {
      final vis = computeFieldVisibility(tier: ProfileViewerTier.owner);
      expect(vis.showDob, isTrue);
      expect(vis.showPhone, isTrue);
      expect(vis.showAddress, isTrue);
      expect(vis.showEmail, isTrue);
    });

    test('TEST 15: public tier → nothing visible by default', () {
      final vis = computeFieldVisibility(tier: ProfileViewerTier.public);
      expect(vis.showDob, isFalse);
      expect(vis.showPhone, isFalse);
      expect(vis.showAddress, isFalse);
      expect(vis.showEmail, isFalse);
    });

    test('TEST 16: denied tier → nothing visible', () {
      final vis = computeFieldVisibility(tier: ProfileViewerTier.denied);
      expect(vis.showDob, isFalse);
      expect(vis.showPhone, isFalse);
    });
  });
}

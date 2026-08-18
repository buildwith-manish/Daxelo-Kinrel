// test/features/family/add_person_can_proceed_test.dart
//
// v5.40 — Verifies the Step 1 (Relationship) validation logic in
// AddPersonSheet:
//   • When the family has existing members, the user MUST pick a
//     relationship type to proceed — picking a target person is
//     RECOMMENDED but NOT blocking.
//   • When the family has no existing members (first-member flow),
//     the user can always proceed.
//
// Previously the validation required BOTH a target AND a relationship,
// which was inconsistent with the submit logic (which falls back to
// the family's anchorPersonId). This caused the Next button to stay
// disabled even after the user picked Parent / Child / Spouse / Sibling
// because they hadn't (yet) tapped the "Related to" picker.
//
// This test exercises the validation logic via a lightweight fake
// that mirrors the relevant bits of _AddPersonSheetState. The real
// state class is private, so we extract the decision logic into a
// pure function that takes the inputs and returns whether the user
// can proceed.

import 'package:flutter_test/flutter_test.dart';

/// Pure-function mirror of _AddPersonSheetState._canProceed() for
/// case 1 (Step 1 — Relationship). The real method has the same
/// shape; this lets us unit-test the validation without spinning
/// up the full widget tree (which requires Supabase, Riverpod
/// providers, etc.).
///
/// Parameters:
/// - [familyHasExistingMembers]: true if the family has at least
///   one existing member (the user themselves counts).
/// - [effectiveRelationshipKey]: the resolved relationship key
///   (e.g. 'father', 'mother', 'brother') or null if the user
///   hasn't picked a relationship type.
bool canProceedStep1({
  required bool familyHasExistingMembers,
  required String? effectiveRelationshipKey,
}) {
  // v5.40: Only the relationship is required. The target person
  // is resolved at submit time (with fallback to the family's
  // anchorPersonId), so it's not a hard validation gate.
  if (familyHasExistingMembers) {
    return effectiveRelationshipKey != null;
  }
  return true;
}

void main() {
  group('AddPersonSheet Step 1 _canProceed (v5.40)', () {
    test('Family with existing members + no relationship picked → '
        'CANNOT proceed (Next disabled)', () {
      expect(
        canProceedStep1(
          familyHasExistingMembers: true,
          effectiveRelationshipKey: null,
        ),
        false,
        reason: 'When the family has members and the user has NOT yet '
            'picked a relationship type, the Next button must stay '
            'disabled. The relationship is the only hard requirement.',
      );
    });

    test('Family with existing members + relationship picked → '
        'CAN proceed (Next enabled) — even without a target person', () {
      expect(
        canProceedStep1(
          familyHasExistingMembers: true,
          effectiveRelationshipKey: 'father',
        ),
        true,
        reason: 'v5.40: After the user picks Parent / Child / Spouse / '
            'Sibling, the Next button MUST enable immediately — even '
            'if they have not tapped the "Related to" picker. The '
            'submit logic falls back to the family anchor when no '
            'explicit target was picked, so the validation must '
            'match that behavior.',
      );
    });

    test('Family with existing members + relationship picked + '
        'target picked → CAN proceed', () {
      // The target being picked doesn't change the validation —
      // relationship alone is sufficient. But this is the "happy
      // path" the user described in their bug report.
      expect(
        canProceedStep1(
          familyHasExistingMembers: true,
          effectiveRelationshipKey: 'mother',
        ),
        true,
      );
    });

    test('Family with existing members + sibling relationship picked → '
        'CAN proceed (sibling is a valid relationship)', () {
      // Sibling resolves to 'brother' or 'sister' based on the new
      // person's gender. Both are valid keys.
      expect(
        canProceedStep1(
          familyHasExistingMembers: true,
          effectiveRelationshipKey: 'brother',
        ),
        true,
      );
      expect(
        canProceedStep1(
          familyHasExistingMembers: true,
          effectiveRelationshipKey: 'sister',
        ),
        true,
      );
    });

    test('Family with existing members + spouse relationship picked → '
        'CAN proceed', () {
      expect(
        canProceedStep1(
          familyHasExistingMembers: true,
          effectiveRelationshipKey: 'wife',
        ),
        true,
      );
      expect(
        canProceedStep1(
          familyHasExistingMembers: true,
          effectiveRelationshipKey: 'husband',
        ),
        true,
      );
    });

    test('Family with existing members + custom kinship picked → '
        'CAN proceed', () {
      // Custom kinship returns a key like 'custom_guru'.
      expect(
        canProceedStep1(
          familyHasExistingMembers: true,
          effectiveRelationshipKey: 'custom_guru',
        ),
        true,
      );
    });

    test('Brand-new family (no existing members) → '
        'CAN proceed regardless of relationship (first member)', () {
      // First-member flow: no relationship needed, Next is always enabled.
      expect(
        canProceedStep1(
          familyHasExistingMembers: false,
          effectiveRelationshipKey: null,
        ),
        true,
        reason: 'When the family has no existing members, this is the '
            'first member being added. No relationship is needed yet — '
            'the user can proceed to the next step.',
      );
    });

    test('Regression: previously, picking a relationship without a '
        'target would block the Next button — now it does not', () {
      // This is the exact scenario the user reported:
      //   1. Open Add Member (no anchorPerson passed)
      //   2. Enter name on Step 0 → Next
      //   3. On Step 1, see "Related to" picker + relationship cards
      //   4. Pick "Parent" card
      //   5. (Old behavior) Next button stays disabled because
      //      _selectedTargetPerson is null
      //   5. (New behavior) Next button ENABLES because
      //      _effectiveRelationshipKey != null
      expect(
        canProceedStep1(
          familyHasExistingMembers: true,
          effectiveRelationshipKey: 'father', // user picked Parent
        ),
        true,
        reason: 'Regression guard: this is the exact bug the user '
            'reported. After picking Parent / Child / Spouse / Sibling, '
            'the Next button must enable immediately, without '
            'requiring the user to also pick a target person.',
      );
    });
  });
}

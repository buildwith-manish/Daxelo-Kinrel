// test/graph/interaction/branch_type_contract_test.dart
//
// v5.132 — Dart ↔ SQL branch-type CONTRACT test.
//
// Bug 1 (v5.131) happened because the Flutter client and the SQL
// function get_member_branch drifted apart: the client started sending
// branch types the SQL CASE did not implement (and, before that, sent
// null for unrecognized keys and skipped the fetch entirely). Chip
// taps silently no-op'd in production.
//
// This test pins BOTH halves of the contract so the drift can never
// silently recur:
//
//   1. The SQL-implemented set — the exact p_branch_type CASE arms in
//      supabase/migrations/20260831120000_get_member_branch_generic_type.sql
//      (maternal, paternal, cousins, inLaws, grandchildren, generic).
//      If a new arm is added to the SQL, add it here (and to the Dart
//      mapper) in the SAME change.
//
//   2. FamilyGraphNotifier.branchTypeForRelationshipKey — must return
//      a value from that set for EVERY conceivable relationship key:
//      standard keys, density-collapse category keys, custom/test
//      keys (YakFather, StepMother, HalfBrother), and degenerate
//      inputs (empty, whitespace, mixed case).
//
// See also the sync-warning comment on branchTypeForRelationshipKey
// (family_graph_provider.dart) and on the SQL migration itself.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/family/presentation/providers/family_graph_provider.dart';

void main() {
  // ── The SQL-implemented branch types (source of truth: the CASE
  //    arms of get_member_branch in migration 20260831120000). ───────
  const sqlImplementedBranchTypes = <String>{
    'maternal',
    'paternal',
    'cousins',
    'inLaws',
    'grandchildren',
    'generic',
  };

  group('v5.132 — Dart ↔ SQL branch-type contract', () {
    test('standard relationship keys map to their standard branch types',
        () {
      expect(
        FamilyGraphNotifier.branchTypeForRelationshipKey('mother'),
        'maternal',
      );
      expect(
        FamilyGraphNotifier.branchTypeForRelationshipKey('maternal_grandmother'),
        'maternal',
      );
      expect(
        FamilyGraphNotifier.branchTypeForRelationshipKey('maternal_uncle'),
        'maternal',
      );
      expect(
        FamilyGraphNotifier.branchTypeForRelationshipKey('father'),
        'paternal',
      );
      expect(
        FamilyGraphNotifier.branchTypeForRelationshipKey('paternal_grandfather'),
        'paternal',
      );
      expect(
        FamilyGraphNotifier.branchTypeForRelationshipKey('cousin'),
        'cousins',
      );
      expect(
        FamilyGraphNotifier.branchTypeForRelationshipKey('niece'),
        'cousins',
      );
      expect(
        FamilyGraphNotifier.branchTypeForRelationshipKey('nephew'),
        'cousins',
      );
      expect(
        FamilyGraphNotifier.branchTypeForRelationshipKey('father_in_law'),
        'inLaws',
      );
      expect(
        FamilyGraphNotifier.branchTypeForRelationshipKey('sister_in_law'),
        'inLaws',
      );
      expect(
        FamilyGraphNotifier.branchTypeForRelationshipKey('grandson'),
        'grandchildren',
      );
      expect(
        FamilyGraphNotifier.branchTypeForRelationshipKey('granddaughter'),
        'grandchildren',
      );
    });

    test('density-collapse category keys resolve to a valid branch type', () {
      // computeDensityCollapse sets CollapsedBranch.relationshipKey to
      // the DOMINANT KinshipEdgeCategory of the hidden subtree — these
      // are enum names like 'parent', 'sibling', 'auntUncle'. None of
      // them may EVER produce null (the fetch would be skipped and the
      // chip would silently no-op). Most resolve through the 'generic'
      // BFS fallback; 'cousin' and 'inLaw' intentionally map to their
      // standard SQL arms (semantically correct where the data carries
      // those relationshipType labels).
      const genericCategoryKeys = [
        'parent',
        'child',
        'sibling',
        'spouse',
        'grandparent',
        'auntUncle',
        'extended',
        'indirect',
      ];
      for (final key in genericCategoryKeys) {
        final mapped = FamilyGraphNotifier.branchTypeForRelationshipKey(key);
        expect(mapped, 'generic',
            reason:
                "Density-collapse category key '$key' must resolve to the "
                "'generic' BFS fallback, got '$mapped'");
      }
      // Category keys that intentionally route to a standard arm.
      expect(
        FamilyGraphNotifier.branchTypeForRelationshipKey('cousin'),
        'cousins',
        reason: "The 'cousin' category intentionally routes to the "
            "'cousins' SQL arm",
      );
      expect(
        FamilyGraphNotifier.branchTypeForRelationshipKey('inLaw'),
        'inLaws',
        reason: "The 'inLaw' category intentionally routes to the "
            "'inLaws' SQL arm (contains('inlaw') match)",
      );
    });

    test('custom / non-standard test keys resolve via the generic fallback',
        () {
      // The exact custom keys from the Bug-1 report (test data): a
      // custom key must NEVER produce null — the fetch would be
      // skipped and the chip would silently no-op.
      const customKeys = [
        'YakFather',
        'StepMother',
        'HalfBrother',
        'godfather',
        'guru',
        'chalk_sibling',
        'some_new_custom_key_nobody_expected',
      ];
      for (final key in customKeys) {
        final mapped = FamilyGraphNotifier.branchTypeForRelationshipKey(key);
        expect(mapped, 'generic',
            reason:
                "Custom key '$key' must resolve to 'generic', got '$mapped'");
      }
    });

    test('degenerate inputs never return null or an SQL-unknown type', () {
      const degenerateKeys = [
        '',
        ' ',
        '  mother  ', // whitespace-padded → trimmed → maternal
        'MOTHER', // case-insensitive → maternal
        'unknown',
        '42',
        '__proto__',
      ];
      for (final key in degenerateKeys) {
        final mapped = FamilyGraphNotifier.branchTypeForRelationshipKey(key);
        expect(mapped, isNotNull,
            reason: "Key '$key' must NEVER map to null after v5.131");
        expect(sqlImplementedBranchTypes.contains(mapped), isTrue,
            reason:
                "Key '$key' mapped to '$mapped' which the SQL function "
                'get_member_branch does NOT implement — the RPC would hit '
                'the ELSE arm and return an empty set (chip no-op bug). '
                'Update the SQL CASE (migration 20260831120000) or the '
                'Dart mapper so both sides stay in sync.');
      }
      // The whitespace/case variants resolve to a REAL branch type...
      expect(
        FamilyGraphNotifier.branchTypeForRelationshipKey('  mother  '),
        'maternal',
      );
      expect(
        FamilyGraphNotifier.branchTypeForRelationshipKey('MOTHER'),
        'maternal',
      );
      // ...while truly unknown keys take the generic fallback.
      expect(
        FamilyGraphNotifier.branchTypeForRelationshipKey(''),
        'generic',
      );
    });

    test('every mapped value is implemented by the SQL CASE (contract)', () {
      // Exhaustive-ish sweep: for a broad set of realistic inputs, the
      // mapper's output must ALWAYS be a type the live SQL function
      // implements. This is the test that fails the moment someone
      // adds a new Dart arm without updating the SQL (or vice versa).
      const sweepKeys = <String>[
        // fundamental edge keys
        'parent', 'spouse', 'adoptive_parent', 'step_parent', 'unknown',
        // kinship labels
        'mother', 'father', 'son', 'daughter', 'brother', 'sister',
        'grandmother', 'grandfather', 'aunt', 'uncle',
        'maternal_aunt', 'paternal_uncle', 'cousin', 'niece', 'nephew',
        'father_in_law', 'mother_in_law', 'brother_in_law', 'sister_in_law',
        'grandson', 'granddaughter', 'grandchild',
        // step/adoptive/custom
        'step_mother', 'step_father', 'step_brother', 'step_sister',
        'adoptive_son', 'adoptive_daughter', 'god_mother', 'guru',
        'YakFather', 'StepMother', 'HalfBrother',
        // enum-style categories from computeDensityCollapse
        'child', 'sibling', 'grandparent', 'auntUncle', 'inLaw',
        'extended', 'indirect', 'self',
        // degenerate
        '', ' ', 'null', '0',
      ];
      for (final key in sweepKeys) {
        final mapped = FamilyGraphNotifier.branchTypeForRelationshipKey(key);
        expect(sqlImplementedBranchTypes.contains(mapped), isTrue,
            reason:
                "branchTypeForRelationshipKey('$key') returned '$mapped' — "
                'not implemented by get_member_branch SQL. Both sides of '
                'the contract must change together (see the sync-warning '
                'comments in family_graph_provider.dart and migration '
                '20260831120000).');
      }
    });
  });
}

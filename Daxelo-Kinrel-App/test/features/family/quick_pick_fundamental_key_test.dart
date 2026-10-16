// test/features/family/quick_pick_fundamental_key_test.dart
//
// v5.216 — Regression guard for the "invalid_relationship_key" bug in the
// Relationship Quick-Pick sheet (the "Find on Kinrel" add-member flow).
//
// BUG (reproduced live, console):
//   [graphPendingInvitations] create failed: invalid_relationship_key
//
// The _QuickPickCategory enum's first value is the FUNDAMENTAL edge key
// sent to `fn_create_graph_pending_invitation`. That RPC (and the
// Relationship table's CHECK constraint) only accepts:
//   'parent' | 'spouse' | 'adoptive_parent' | 'step_parent'
// The previous enum values 'child' / 'sibling' / 'grandparent' were
// rejected — so tapping the Child, Sibling or Grandparent chip silently
// failed to create the invitation (the relationship never landed in the
// graph, so the chat could never show it either).
//
// All non-spouse blood relations use the 'parent' fundamental edge; the
// SPECIFIC relationship (son/daughter, brother/sister, grandfather/
// grandmother) is carried in labelAtoB/labelBtoA — exactly how every
// sibling/child/grandparent edge in the production database is stored
// (1040 'parent' + 114 'spouse' active edges, zero others) and exactly
// what add_person_sheet._mapToFundamentalEdge and the sheet's own
// _fundamentalKeyFor produce for the "More" list path.
//
// This file follows the repo's existing source-level regression-guard
// pattern (see p6_1_family_tree_canvas_deletion_test.dart) because the
// enum is library-private.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String content;
  late String enumBlock;

  setUpAll(() {
    final file = File(
      'lib/features/family/presentation/relationship_quick_pick_sheet.dart',
    );
    content = file.readAsStringSync();

    // The enum declaration block (up to the semicolon after the members).
    final enumStart = content.indexOf('enum _QuickPickCategory {');
    final enumEnd = content.indexOf(';', enumStart);
    enumBlock = content.substring(enumStart, enumEnd);
  });

  group('v5.216 — quick-pick chips send valid fundamental keys', () {
    test('the _QuickPickCategory enum is found and terminated', () {
      final enumStart = content.indexOf('enum _QuickPickCategory {');
      expect(enumStart, greaterThanOrEqualTo(0),
          reason: '_QuickPickCategory enum not found');
      final enumEnd = content.indexOf(';', enumStart);
      expect(enumEnd, greaterThan(enumStart),
          reason: 'enum block not terminated');
    });

    test('every enum member maps to an RPC-accepted fundamental key', () {
      // Matches lines like:  sibling('parent', 'Sibling', Icons.x),
      final memberPattern = RegExp(
        r"^\s*(parent|child|sibling|spouse|grandparent)\('([^']+)'",
        multiLine: true,
      );
      final members = memberPattern.allMatches(enumBlock).toList();
      expect(members, isNotEmpty,
          reason: 'Could not parse _QuickPickCategory members');

      const allowed = {'parent', 'spouse', 'adoptive_parent', 'step_parent'};
      for (final m in members) {
        final chip = m.group(1)!;
        final key = m.group(2)!;
        expect(allowed.contains(key), isTrue,
            reason:
                "The '$chip' chip sends relationshipKey '$key' to "
                "fn_create_graph_pending_invitation, which only accepts "
                "$allowed. The RPC rejects anything else with "
                "'invalid_relationship_key' — the invitation silently "
                "fails and the relationship never lands in the graph "
                "(so the chat can never show it either).");
      }
    });

    test('non-spouse chips use the parent fundamental edge (DB convention)', () {
      // Every blood-relation chip must be 'parent' — the specific label
      // (son/daughter, brother/sister, grandfather/grandmother) carries
      // the relationship via labelAtoB, exactly like the production DB.
      for (final chip in ['parent', 'child', 'sibling', 'grandparent']) {
        final pattern = RegExp("$chip\\('parent'");
        expect(pattern.hasMatch(enumBlock), isTrue,
            reason: "The '$chip' chip must use the 'parent' fundamental "
                "edge key (see test doc for the DB convention)");
      }
    });

    test('the spouse chip keeps the spouse fundamental edge', () {
      expect(enumBlock.contains("spouse('spouse'"), isTrue);
    });

    test('no chip sends the rejected legacy keys', () {
      for (final legacyKey in ['child', 'sibling', 'grandparent']) {
        // Only flag a legacy key when used as the ENUM's fundamental-key
        // argument — i.e. "chip('legacyKey'," — not the chip label itself.
        final pattern = RegExp(
            "(parent|child|sibling|spouse|grandparent)\\('$legacyKey'");
        expect(pattern.hasMatch(enumBlock), isFalse,
            reason: "A chip still passes the invalid fundamental key "
                "'$legacyKey' — fn_create_graph_pending_invitation will "
                "reject it with invalid_relationship_key.");
      }
    });
  });
}

// lib/features/family/presentation/find_on_kinrel_flow.dart
//
// DAXELO KINREL — Shared "skip straight to Find on Kinrel" flow helper.
//
// v5.215 (unified add-member entry-point fix): historically, the
// "Add Member" / "Invite Member" buttons app-wide either:
//   1. Showed a 2-option bottom sheet (`showAddMemberOptions`) with
//      "Add Manually" + "Find on Kinrel" choices, OR
//   2. Pushed the full-screen `/family/:id/add-member` route, which
//      opened `AddPersonSheet` directly in manual-entry mode.
//
// Both of these forced the user through intermediate UI before
// reaching the actual Find on Kinrel search — the primary add-member
// intent for real Kinrel accounts (searching for an existing user by
// name/username/email, then immediately committing the relationship
// via the RelationshipQuickPickSheet with an Undo snackbar).
//
// The original fix (commit `eda1d636`-era) only applied to the
// Family Space screen's "Invite family member" AppBar button — it
// added a private `_openInviteFlow` method that pushes
// [KinrelUserSearchScreen] directly, skipping the 2-option sheet
// entirely. That fix was scoped to ONE entry point and didn't cover
// the others.
//
// This file extracts the same flow into a single reusable top-level
// function so EVERY non-Graph add-member entry point can call it
// consistently. "Add Manually" remains accessible ONLY from inside
// the Family Graph screen (where building out placeholder tree
// nodes actually belongs) — that entry point keeps using
// [showAddMemberOptions] with `fromGraph: true`.

import 'package:flutter/material.dart';

import 'add_member_source.dart';
import 'kinrel_user_search_screen.dart';
import 'relationship_quick_pick_sheet.dart' show RelationshipQuickPickSheet;

/// Opens the "Find on Kinrel" invite flow directly — pushes
/// [KinrelUserSearchScreen] fullscreen, and on user-selected opens
/// [RelationshipQuickPickSheet] which immediately commits the
/// relationship on chip-tap (with an Undo snackbar — no form, no
/// submit).
///
/// This is the SAME flow the Family Space screen's "Invite family
/// member" button uses (see `_openInviteFlow` in
/// `family_detail_screen.dart`). Extracting it here lets every
/// non-Graph add-member entry point call the same code path
/// consistently — so the "skip straight to Find on Kinrel"
/// behavior can never silently regress on one entry point while
/// staying fixed on another.
///
/// [fromGraph] — true when the entry point is inside the Family
/// Graph screen (graph-originated invites are routed to the pending
/// invitations system, NOT committed immediately). Defaults to
/// false — every non-Graph entry point passes false.
///
/// Entry points that should call this function (per the v5.215
/// audit + fix):
///   • Family Space "Invite family member" AppBar button (already
///     calls the equivalent private method; can be migrated to call
///     this public helper for consistency, but the behavior is
///     unchanged).
///   • Family Profile screen's "Add member" button (was previously
///     pushing the `/family/:id/add-member` route → AddPersonSheet
///     manual entry form).
///   • Family Members screen's FAB (was previously calling
///     `showAddMemberOptions` — the 2-option sheet).
///   • Games Hub screen's "Add member" CTA (was previously calling
///     `showAddMemberOptions` — the 2-option sheet).
///   • Relationship Builder screen's empty-state + FAB (was
///     previously calling `AddPersonSheet.show` — manual entry
///     form).
///   • Home screen's "Add Member" quick-action chip + the
///     "Add family member" item in the more-menu (were previously
///     pushing the `/family/:id/add-person` route → AddPersonSheet
///     manual entry form).
///
/// Entry points that should NOT call this function (and keep their
/// existing behavior unchanged):
///   • Family Graph screen's "Add Member" FAB — uses
///     [showAddMemberOptions] with `fromGraph: true`. This is the
///     ONE place where "Add Manually" remains reachable, because
///     building out placeholder tree nodes (deceased grandparents,
///     relatives not on Kinrel) is a graph-context activity.
///   • Create Family screen's post-create "add your first relatives"
///     flow — uses `AddPersonSheet.show` after navigating the user
///     to `/family/:id/graph`. The user is in graph context here.
///   • Person Detail sheet/screen's "Edit" actions — these call
///     `AddPersonSheet.show` with `existingPerson:` to EDIT an
///     existing person's details, not to add a new member. They are
///     not add-member entry points and must remain unchanged.
///   • Family Pulse "missing birthday" nudge — calls
///     `AddPersonSheetBridge.show` with `person:` (an existing
///     person) to add a missing DOB to that person. Same — not an
///     add-member entry point.
void openFindOnKinrelFlow(
  BuildContext context, {
  required String familyId,
  bool fromGraph = false,
}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (context) => KinrelUserSearchScreen(
        familyId: familyId,
        onUserSelected: (KinrelUser user) {
          // The search screen pops itself before calling this
          // callback. Now open the Relationship Quick-Pick bottom
          // sheet directly — no AddPersonSheet, no manual form,
          // no submit. The user already exists on Kinrel; we just
          // need to know how they relate to existing family members.
          RelationshipQuickPickSheet.show(
            context,
            familyId: familyId,
            selectedUser: user,
            fromGraph: fromGraph,
          );
        },
      ),
      fullscreenDialog: true,
    ),
  );
}

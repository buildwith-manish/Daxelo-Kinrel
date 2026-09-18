// lib/features/family/presentation/relationship_quick_pick_sheet.dart
//
// DAXELO KINREL — Relationship Quick-Pick Bottom Sheet (v5.194)
//
// Part of the new "Find on Kinrel" Add Member flow:
//   Step 1 — User searched Kinrel and tapped a result.
//   Step 2 — THIS sheet appears with quick-pick kinship chips.
//   Step 3 — Tapping a chip IMMEDIATELY creates the graph pending
//            invitation; an Undo snackbar reverses it within 6s.
//
// DESIGN (per the v5.194 Add Member flow spec):
//
//   ┌─────────────────────────────────────────┐
//   │  Add <selected user's name> as your...  │  ← Header (no personB)
//   │                                          │
//   │  [ Parent ]  [ Sibling ]                 │  ← Primary chips
//   │  [ Spouse ]  [ Child ]                   │     (2x2 + Grandparent)
//   │  [ Grandparent ]                         │
//   │  [ More ]                                │  ← Expands searchable list
//   └─────────────────────────────────────────┘
//
// • Tapping a chip immediately adds the relationship — NO confirm/submit.
// • Gendered labels (Brother/Sister, Father/Mother) are inferred
//   automatically from the selected person's stored gender:
//     Sibling + Male   → Brother
//     Sibling + Female → Sister
//     Parent + Male    → Father
//     Parent + Female  → Mother
// • "More" expands into a searchable list (uncle, cousin, in-law, etc.)
//   pulling from the existing kinship dataset.
// • The "Parent"/"Child"/"Grandparent" chips stay gender-neutral when
//   the selected user's gender is null/unknown — the stored labelAtoB
//   becomes 'parent'/'child'/'grandparent' (the gender-neutral form
//   that the v5.193 SQL fix produces on the inverse edge).
// • Optionally hide chips whose target relationship already exists on
//   the viewer's graph (e.g. hide "Father" if the viewer already has
//   a father node).
//
// POST-ADD FEEDBACK:
//   ✓ Added as Brother   [Undo]
// The graph updates instantly behind the sheet. Undo reverses the
// addition; no separate confirmation dialog needed.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/kinship/kinship_models.dart' show KinshipRelationship;
import '../../../core/kinship/kinship_provider.dart';
import '../../../core/services/supabase_service.dart' show supabaseProvider;
import '../../../core/viewer/viewer_provider.dart' show viewerPersonIdProvider;
import 'add_member_source.dart' show KinrelUser;
import 'providers/family_graph_provider.dart'
    show FamilyGraphNotifier, familyGraphProvider;
import 'providers/graph_pending_invitations_provider.dart';

// v5.196: Fixed chip dimensions for the 2-column grid. Both the
// primary chips (Parent / Child / Sibling / Spouse / Grandparent)
// and the "More" chip use this width so the grid stays aligned
// even when one of the primary chips is hidden by the existing-
// relationship filter (the hidden slot renders a SizedBox of the
// same width).
//
// The width was chosen to comfortably fit the longest label
// ("Grandparent") with the icon + padding on a typical 360pt+
// phone screen, leaving ~10pt of spacing between the two
// columns.
const double _kChipWidth = 158;
const double _kChipHeight = 48;

/// The five primary quick-pick categories. Each maps to a fundamental
/// edge key ('parent', 'spouse') that the DB constraint accepts, plus
/// a gender-aware specific label that gets stored in `labelAtoB`.
///
/// v5.196: The enum order defines the chip grid order:
///   Row 1: Parent | Child
///   Row 2: Sibling | Spouse
///   Row 3: Grandparent | More (More is rendered as a separate chip
///         appended after the five categories in [_buildChipsGrid]).
///
/// "Parent" and "Child" are first because they are the two most
/// common relations a user adds to their family graph.
///
/// The "from the viewer's perspective" semantic:
///   - Parent     → "the selected user is the viewer's parent"
///   - Child      → "the selected user is the viewer's child"
///   - Sibling    → "the selected user is the viewer's sibling"
///   - Spouse     → "the selected user is the viewer's spouse"
///   - Grandparent → "the selected user is the viewer's grandparent"
enum _QuickPickCategory {
  parent('parent', 'Parent', Icons.family_restroom),
  child('child', 'Child', Icons.child_care_outlined),
  sibling('sibling', 'Sibling', Icons.people_outline),
  spouse('spouse', 'Spouse', Icons.favorite_outline),
  grandparent('grandparent', 'Grandparent', Icons.elderly_outlined);

  const _QuickPickCategory(this.fundamentalKey, this.label, this.icon);
  final String fundamentalKey;
  final String label;
  final IconData icon;
}

/// Show the Relationship Quick-Pick bottom sheet for an already-existing
/// Kinrel user (no form, no editable name/gender, no submit button).
///
/// [selectedUser] — the Kinrel user the viewer tapped in the search
///   results. Their `gender` field drives the gendered label inference.
/// [fromGraph] — true when invoked from the family graph screen; the
///   invitation is then routed through the graph pending invitations
///   system (the standard path for graph-originated invites).
class RelationshipQuickPickSheet extends ConsumerStatefulWidget {
  const RelationshipQuickPickSheet({
    super.key,
    required this.familyId,
    required this.selectedUser,
    this.fromGraph = false,
  });

  final String familyId;
  final KinrelUser selectedUser;
  final bool fromGraph;

  /// Public entry point — opens the sheet as a modal bottom sheet.
  /// Does NOT return a value; the sheet commits the relationship
  /// immediately on chip tap and dismisses itself.
  static Future<void> show(
    BuildContext context, {
    required String familyId,
    required KinrelUser selectedUser,
    bool fromGraph = false,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.bottomSheet),
        ),
      ),
      builder: (_) => RelationshipQuickPickSheet(
        familyId: familyId,
        selectedUser: selectedUser,
        fromGraph: fromGraph,
      ),
    );
  }

  @override
  ConsumerState<RelationshipQuickPickSheet> createState() =>
      _RelationshipQuickPickSheetState();
}

class _RelationshipQuickPickSheetState
    extends ConsumerState<RelationshipQuickPickSheet> {
  bool _isCommitting = false;
  bool _showMore = false;

  /// v5.195: When non-null, the sheet is showing the gender follow-up
  /// step for this category. The user tapped a chip (Parent / Sibling
  /// / Child / Grandparent) but the selected user's gender is null,
  /// so we can't infer a gendered label. Instead of committing the
  /// gender-neutral form immediately, we expand the sheet IN PLACE
  /// (no navigation, no new screen) and ask the user to pick a
  /// gender. Tapping Male/Female/Other resolves the label and
  /// commits; tapping Back returns to the chips grid.
  ///
  /// Spouse does NOT enter this mode — it's already gender-neutral
  /// (the 'husband'/'wife' label is symmetric, and the v5.194 flow
  /// stores 'spouse' as the specific label when gender is null).
  _QuickPickCategory? _awaitingGenderFor;

  @override
  void initState() {
    super.initState();
    // Ensure kinship data is loaded for the "More" list.
    ref.read(kinshipInitializedProvider.future);
  }

  /// Resolve the viewer's anchor Person ID — used as the targetPersonId
  /// for the graph pending invitation. The viewer is the "from" side;
  /// the selected user becomes the "to" side (the new Person node that
  /// will be created on the recipient's side when they accept).
  ///
  /// We get this from the viewerPersonIdProvider cache OR the family
  /// detail's anchor Person. The actual invitation-creation RPC
  /// (`fn_create_graph_pending_invitation`) accepts any existing
  /// Person ID as `p_target_person_id` — it becomes the "from" person
  /// in the eventual Relationship row.
  Future<String> _resolveViewerPersonId() async {
    // Try viewerPersonIdProvider (single source of truth for the
    // viewer's Person ID — already cached by the graph engine).
    final viewerId = ref
        .read(viewerPersonIdProvider(widget.familyId))
        .valueOrNull;
    if (viewerId != null && viewerId.isNotEmpty) return viewerId;

    // Fallback: family detail's anchor Person.
    final detail =
        await ref.read(familyDetailProvider(widget.familyId).future);
    if (detail != null && detail.members.isNotEmpty) {
      final anchor = detail.members.firstWhere(
        (p) => p.isAnchor,
        orElse: () => detail.members.first,
      );
      return anchor.id;
    }

    // Last resort: query Person table directly.
    final client = ref.read(supabaseProvider);
    if (client == null) {
      throw Exception('Not connected to the server. Please retry.');
    }
    final response = await client
        .from('Person')
        .select('id')
        .eq('familyId', widget.familyId)
        .eq('isAnchor', true)
        .isFilter('deletedAt', null)
        .limit(1)
        .timeout(const Duration(seconds: 5));
    if (response.isEmpty) {
      throw Exception('Could not find your Person node in this family.');
    }
    return (response[0]['id'] ?? '').toString();
  }

  /// Resolve the gendered specific label for a [category] using the
  /// [selectedUser]'s stored gender.
  ///
  /// Examples:
  ///   Parent + male    → 'father'
  ///   Parent + female  → 'mother'
  ///   Parent + null    → 'parent' (gender-neutral)
  ///   Sibling + male   → 'brother'
  ///   Sibling + female → 'sister'
  ///   Sibling + null   → 'sibling'
  ///   Spouse + male    → 'husband'
  ///   Spouse + female  → 'wife'
  ///   Spouse + null    → 'spouse'
  ///   Child + male     → 'son'
  ///   Child + female   → 'daughter'
  ///   Child + null     → 'child'
  ///   Grandparent + male   → 'grandfather'
  ///   Grandparent + female → 'grandmother'
  ///   Grandparent + null  → 'grandparent'
  String _specificLabelFor(_QuickPickCategory category) {
    final gender = (widget.selectedUser.gender ?? '').toLowerCase().trim();
    return _specificLabelForCategoryAndGender(category, gender);
  }

  /// v5.195: Resolve the gendered label given an EXPLICIT gender
  /// string. Used by the gender follow-up step where the user has
  /// just picked Male / Female / Other for someone whose profile
  /// gender is null. The gender string is one of:
  ///   - 'male'   → male form
  ///   - 'female' → female form
  ///   - any other value (including 'other', '', null) → gender-neutral form
  ///
  /// This is a PURE DISPLAY/LABEL choice for this relationship — it
  /// does NOT overwrite or edit the other user's actual profile
  /// gender field. The chosen gender is used ONLY to compute the
  /// specific label that gets stored in `Relationship.labelAtoB`.
  String _specificLabelForCategoryAndGender(
    _QuickPickCategory category,
    String gender,
  ) {
    final g = gender.toLowerCase().trim();
    switch (category) {
      case _QuickPickCategory.parent:
        if (g == 'male') return 'father';
        if (g == 'female') return 'mother';
        return 'parent';
      case _QuickPickCategory.sibling:
        if (g == 'male') return 'brother';
        if (g == 'female') return 'sister';
        return 'sibling';
      case _QuickPickCategory.spouse:
        // Spouse is already gender-neutral; no follow-up needed.
        if (g == 'male') return 'husband';
        if (g == 'female') return 'wife';
        return 'spouse';
      case _QuickPickCategory.child:
        if (g == 'male') return 'son';
        if (g == 'female') return 'daughter';
        return 'child';
      case _QuickPickCategory.grandparent:
        if (g == 'male') return 'grandfather';
        if (g == 'female') return 'grandmother';
        return 'grandparent';
    }
  }

  /// v5.195: Does this category need the gender follow-up step for
  /// this user? Returns true when:
  ///   - the category is NOT Spouse (Spouse is already gender-neutral
  ///     — the male/female forms 'husband'/'wife' are symmetric and
  ///     the gender-neutral form 'spouse' is fine to commit directly),
  ///   - AND the selected user's stored gender is null / empty / not
  ///     one of 'male' / 'female'.
  ///
  /// When true, [_commit] will set [_awaitingGenderFor] instead of
  /// committing immediately. The follow-up step calls
  /// [_commitWithGender] which resolves the label using the user's
  /// chosen gender and commits.
  bool _needsGenderFollowUp(_QuickPickCategory category) {
    if (category == _QuickPickCategory.spouse) return false;
    final gender = (widget.selectedUser.gender ?? '').toLowerCase().trim();
    return gender != 'male' && gender != 'female';
  }

  /// Map a (possibly gendered) specific label back to the fundamental
  /// edge key the DB constraint requires ('parent', 'spouse',
  /// 'adoptive_parent', 'step_parent').
  String _fundamentalKeyFor(String specificLabel) {
    final k = specificLabel.toLowerCase().trim();
    if (k == 'husband' || k == 'wife' || k == 'spouse') {
      return 'spouse';
    }
    if (k == 'step_father' || k == 'step_mother' ||
        k == 'stepfather' || k == 'stepmother' ||
        k == 'step_parent') {
      return 'step_parent';
    }
    if (k == 'adoptive_father' || k == 'adoptive_mother' ||
        k == 'adoptive_parent') {
      return 'adoptive_parent';
    }
    // Everything else (father, mother, parent, son, daughter, child,
    // brother, sister, sibling, grandfather, grandmother, grandparent,
    // uncle, aunt, cousin, nephew, niece, etc.) → 'parent'.
    return 'parent';
  }

  /// Pretty-print the specific label for the success/Undo snackbar.
  /// e.g. 'brother' → 'Brother', 'elder_brother' → 'Elder Brother'.
  String _prettyLabel(String specificLabel) {
    return specificLabel
        .split('_')
        .map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  /// Commit the relationship by creating a graph pending invitation.
  ///
  /// v5.194: This is the IMMEDIATE-COMMIT path. There is no separate
  /// confirm/submit button — tapping the chip IS the commit. The
  /// invitation is created via `fn_create_graph_pending_invitation`
  /// (the same RPC the existing "Find on Kinrel" path used). On
  /// success the sheet dismisses and an Undo snackbar appears.
  ///
  /// v5.195: GENDER FOLLOW-UP. If the selected user's stored gender
  /// is null/empty AND the category is NOT Spouse, we can't infer a
  /// gendered label (father/mother vs parent). Instead of committing
  /// the gender-neutral form, we expand the sheet IN PLACE to show
  /// a gender follow-up step ("Is [Name]... [Male] [Female] [Other]").
  /// Tapping one of those resolves the label and commits. This is a
  /// pure display/label choice for this relationship — it does NOT
  /// overwrite or edit the other user's actual profile gender field.
  Future<void> _commit(_QuickPickCategory category) async {
    if (_isCommitting) return;

    // v5.195: Gender follow-up gate. Spouse is exempt (already
    // gender-neutral). For all other categories, when the user's
    // gender is null, switch to the gender step instead of committing
    // the gender-neutral form immediately.
    if (_needsGenderFollowUp(category)) {
      setState(() => _awaitingGenderFor = category);
      return;
    }

    // User's gender is known (male/female) OR category is Spouse —
    // proceed with immediate commit using the inferred label.
    final specificLabel = _specificLabelFor(category);
    await _doCommit(category.fundamentalKey, specificLabel);
  }

  /// v5.195: Called from the gender follow-up step when the user
  /// taps Male / Female / Other. Resolves the gendered label using
  /// the chosen gender (NOT the user's profile gender) and commits.
  ///
  /// [chosenGender] is one of: 'male', 'female', 'other'. Any other
  /// value (including 'other') falls through to the gender-neutral
  /// form for the category.
  Future<void> _commitWithGender(String chosenGender) async {
    if (_isCommitting) return;
    final category = _awaitingGenderFor;
    if (category == null) return; // Defensive — shouldn't happen.

    final specificLabel =
        _specificLabelForCategoryAndGender(category, chosenGender);
    await _doCommit(category.fundamentalKey, specificLabel);
  }

  /// Shared commit path used by both [_commit] (immediate, gender
  /// already known) and [_commitWithGender] (after the follow-up
  /// step). Creates the graph pending invitation, refreshes the
  /// graph, dismisses the sheet, and shows the Undo snackbar.
  Future<void> _doCommit(String fundamentalKey, String specificLabel) async {
    if (_isCommitting) return;
    setState(() => _isCommitting = true);

    final messenger = ScaffoldMessenger.maybeOf(context);

    try {
      // 1. Resolve the viewer's Person ID (the "from" person).
      final viewerPersonId = await _resolveViewerPersonId();

      // 2. Check for an existing pending invitation to avoid duplicates.
      final pendingInvitations = ref
          .read(graphPendingInvitationsProvider(widget.familyId))
          .valueOrNull ?? [];
      final existing = findPendingInvitationForRecipient(
        pendingInvitations,
        recipientUserId: widget.selectedUser.id,
      );
      if (existing != null) {
        if (mounted) setState(() => _isCommitting = false);
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
                'Invitation already pending for ${widget.selectedUser.name}. '
                'Tap "Invites" on the graph to cancel or resend.'),
            backgroundColor: KinrelColors.amber,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
        if (mounted) Navigator.of(context).pop();
        return;
      }

      // 3. Create the graph pending invitation.
      final notifier = ref.read(
        graphPendingInvitationsProvider(widget.familyId).notifier,
      );
      final result = await notifier.createInvitation(
        familyId: widget.familyId,
        targetPersonId: viewerPersonId,
        relationshipKey: fundamentalKey,
        specificLabel: specificLabel,
        recipientName: widget.selectedUser.name,
        recipientEmail: widget.selectedUser.email,
        recipientPhone: null,
        recipientUserId: widget.selectedUser.id,
      );

      if (!result.success) {
        if (mounted) setState(() => _isCommitting = false);
        messenger?.showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }

      // 4. Refresh the graph + pending invitations providers so the
      // new invite appears immediately behind the sheet.
      if (mounted) {
        FamilyGraphNotifier.clearCache(widget.familyId);
        ref.invalidate(familyGraphProvider(widget.familyId));
        ref.invalidate(graphPendingInvitationsProvider(widget.familyId));
      }

      // 5. Dismiss the sheet.
      if (mounted) Navigator.of(context).pop();

      // 6. Show the Undo snackbar.
      if (mounted) {
        _showUndoSnackbar(
          messenger: messenger,
          specificLabel: specificLabel,
          invitationId: result.invitationId,
        );
      }
    } on Exception catch (e) {
      if (mounted) setState(() => _isCommitting = false);
      messenger?.showSnackBar(
        SnackBar(
          content: Text('Could not add: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _isCommitting = false);
      messenger?.showSnackBar(
        SnackBar(
          content: Text('Could not add: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  /// Commit a custom (non-primary) kinship term chosen from the "More"
  /// list. The [specificLabel] is the kinship key from the existing
  /// kinship dataset (e.g. 'uncle', 'cousin', 'father_in_law').
  Future<void> _commitCustom(String specificLabel) async {
    if (_isCommitting) return;
    setState(() => _isCommitting = true);

    final messenger = ScaffoldMessenger.maybeOf(context);
    final fundamentalKey = _fundamentalKeyFor(specificLabel);

    try {
      final viewerPersonId = await _resolveViewerPersonId();

      final pendingInvitations = ref
          .read(graphPendingInvitationsProvider(widget.familyId))
          .valueOrNull ?? [];
      final existing = findPendingInvitationForRecipient(
        pendingInvitations,
        recipientUserId: widget.selectedUser.id,
      );
      if (existing != null) {
        if (mounted) setState(() => _isCommitting = false);
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
                'Invitation already pending for ${widget.selectedUser.name}.'),
            backgroundColor: KinrelColors.amber,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
        if (mounted) Navigator.of(context).pop();
        return;
      }

      final notifier = ref.read(
        graphPendingInvitationsProvider(widget.familyId).notifier,
      );
      final result = await notifier.createInvitation(
        familyId: widget.familyId,
        targetPersonId: viewerPersonId,
        relationshipKey: fundamentalKey,
        specificLabel: specificLabel,
        recipientName: widget.selectedUser.name,
        recipientEmail: widget.selectedUser.email,
        recipientPhone: null,
        recipientUserId: widget.selectedUser.id,
      );

      if (!result.success) {
        if (mounted) setState(() => _isCommitting = false);
        messenger?.showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }

      if (mounted) {
        FamilyGraphNotifier.clearCache(widget.familyId);
        ref.invalidate(familyGraphProvider(widget.familyId));
        ref.invalidate(graphPendingInvitationsProvider(widget.familyId));
      }

      if (mounted) Navigator.of(context).pop();

      if (mounted) {
        _showUndoSnackbar(
          messenger: messenger,
          specificLabel: specificLabel,
          invitationId: result.invitationId,
        );
      }
    } catch (e) {
      if (mounted) setState(() => _isCommitting = false);
      messenger?.showSnackBar(
        SnackBar(
          content: Text('Could not add: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  /// Show the "✓ Added as <label>   Undo" snackbar. Tapping Undo
  /// cancels the just-created pending invitation via
  /// `fn_cancel_graph_invitation`.
  void _showUndoSnackbar({
    required ScaffoldMessengerState? messenger,
    required String specificLabel,
    String? invitationId,
  }) {
    if (messenger == null) return;
    final pretty = _prettyLabel(specificLabel);

    final snackBar = SnackBar(
      content: Row(
        children: [
          const Icon(Icons.check_circle, color: KinrelColors.tealAccent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Added as $pretty',
              style: const TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                color: KinrelColors.textWhite,
              ),
            ),
          ),
        ],
      ),
      backgroundColor: KinrelColors.darkElevated,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 6),
      action: invitationId != null
          ? SnackBarAction(
              label: 'Undo',
              textColor: KinrelColors.orange,
              onPressed: () async {
                final notifier = ref.read(
                  graphPendingInvitationsProvider(widget.familyId).notifier,
                );
                await notifier.cancelInvitation(invitationId);
                if (mounted) {
                  FamilyGraphNotifier.clearCache(widget.familyId);
                  ref.invalidate(familyGraphProvider(widget.familyId));
                  ref.invalidate(graphPendingInvitationsProvider(widget.familyId));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Removed $pretty'),
                      backgroundColor: KinrelColors.darkElevated,
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
            )
          : null,
    );
    messenger.showSnackBar(snackBar);
  }

  /// Optional: hide a primary chip if the viewer already has a Person
  /// linked via that SPECIFIC relationship. e.g. if the viewer already
  /// has a 'father' edge, hide the "Parent" chip.
  ///
  /// v5.197 (BUG FIX): The previous version ALSO matched against
  /// `rel.relationshipKey` (the fundamental edge type, which is almost
  /// always 'parent' for non-spouse edges — father/mother/son/
  /// daughter/brother/sister/grandfather/etc. all share the fundamental
  /// key 'parent'). Because of that, ANY existing parent-type edge
  /// (e.g. a single 'father' edge) would hide ALL of Parent, Child,
  /// Sibling, Grandparent — leaving only Spouse and More visible.
  ///
  /// The fix: only match against the SPECIFIC labels (labelAtoB and
  /// labelBtoA — e.g. 'father', 'son', 'brother'). The fundamental
  /// `relationshipKey` is no longer used for hiding because it's
  /// shared across too many distinct kinship types.
  ///
  /// Implementation: read the family's existing relationships, check
  /// whether any edge has a labelAtoB or labelBtoA matching the
  /// gendered form OR the gender-neutral form for this category.
  bool _shouldHideCategory(_QuickPickCategory category) {
    final detail = ref
        .read(familyDetailProvider(widget.familyId))
        .valueOrNull;
    if (detail == null) return false;

    final specificLabel = _specificLabelFor(category);
    final neutralLabel = category.fundamentalKey;
    final genderedForms = <String>{specificLabel, neutralLabel};
    // Include all gendered forms for this category so an existing edge
    // with EITHER gendered form OR the neutral form hides the chip.
    if (category == _QuickPickCategory.parent) {
      genderedForms.addAll(['father', 'mother', 'parent']);
    } else if (category == _QuickPickCategory.sibling) {
      genderedForms.addAll(['brother', 'sister', 'sibling']);
    } else if (category == _QuickPickCategory.spouse) {
      genderedForms.addAll(['husband', 'wife', 'spouse']);
    } else if (category == _QuickPickCategory.child) {
      genderedForms.addAll(['son', 'daughter', 'child']);
    } else if (category == _QuickPickCategory.grandparent) {
      genderedForms.addAll(['grandfather', 'grandmother', 'grandparent']);
    }

    for (final rel in detail.relationships) {
      if (!rel.isActive) continue;
      // v5.197: Only check the SPECIFIC labels (labelAtoB, labelBtoA).
      // Do NOT check rel.relationshipKey — it's the fundamental edge
      // type (almost always 'parent' for non-spouse edges) and would
      // match across unrelated kinship types.
      final labels = <String?>{
        rel.labelAtoB,
        rel.labelBtoA,
      };
      for (final label in labels) {
        if (label == null) continue;
        final lc = label.toLowerCase();
        if (genderedForms.contains(lc)) {
          return true;
        }
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final safePadding = MediaQuery.of(context).padding.bottom;

    // v5.197 (LOADING STATE): Don't mount the real sheet content until
    // all required data has finished loading. The sheet depends on:
    //   - familyDetailProvider(familyId) — needed for _shouldHideCategory
    //     (existing-relationship detection) and to resolve the viewer's
    //     anchor Person ID.
    //   - kinshipInitializedProvider — needed for the "More" list.
    //
    // Before v5.197, the sheet would mount immediately and paint a
    // partial layout (e.g. with all chips visible because
    // familyDetailProvider was still loading → _shouldHideCategory
    // returned false), then SNAP to the correct layout a few seconds
    // later when the data arrived. This was a visible race condition.
    //
    // Now we show a skeleton (matching the final layout shape: drag
    // handle + title + a grid of grey placeholder chips) while the
    // data is loading, then swap to the real content in a single
    // frame. No partial/half-rendered intermediate state is visible.
    final detailAsync = ref.watch(familyDetailProvider(widget.familyId));
    final kinshipAsync = ref.watch(kinshipInitializedProvider);
    final bool isLoading = detailAsync.isLoading || kinshipAsync.isLoading;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: safePadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: KinrelColors.textDim.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            if (isLoading)
              _buildLoadingSkeleton()
            else ...[
              // Header — "Add <name> as your..." (always the same,
              // whether or not the gender follow-up is active, since
              // the gender prompt now appears INLINE below the chips
              // grid rather than as a separate body).
              _buildDefaultHeader(),

              const Divider(
                  color: KinrelColors.darkElevated, height: 1, thickness: 1),

              // Body — three modes:
              //   1. "More" searchable list (when _showMore == true)
              //   2. Default chips grid + optional inline gender
              //      follow-up prompt below it (when _awaitingGenderFor
              //      != null)
              //
              // The gender follow-up is rendered INLINE in the same
              // sheet (no separate screen, no back arrow) — the
              // previously-selected chip stays in the grid above in a
              // visually highlighted state, and the gender chips
              // appear directly below it.
              if (_showMore)
                _buildMoreList()
              else
                _buildChipsGridWithInlineGender(),
            ],

            const SizedBox(height: KinrelSpacing.base),
          ],
        ),
      ),
    );
  }

  // ── Loading skeleton (matches the final chips-grid layout shape) ────
  //
  // v5.197: A skeleton that mirrors the final layout — a title
  // placeholder + a 2x3 grid of grey placeholder chips — so the user
  // sees the correct shape immediately and the swap to real content
  // is a single-frame replacement, not a layout shift.

  Widget _buildLoadingSkeleton() {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.base, vertical: KinrelSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title placeholder
          Container(
            width: 220,
            height: 22,
            decoration: BoxDecoration(
              color: KinrelColors.darkElevated,
              borderRadius: BorderRadius.circular(KinrelRadius.sm),
            ),
          ),
          const SizedBox(height: 12),
          // 2x3 grid of chip placeholders
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: List.generate(
              6,
              (_) => Container(
                width: _kChipWidth,
                height: _kChipHeight,
                decoration: BoxDecoration(
                  color: KinrelColors.darkElevated,
                  borderRadius: BorderRadius.circular(KinrelRadius.md),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Helper text placeholder
          Container(
            width: 260,
            height: 14,
            decoration: BoxDecoration(
              color: KinrelColors.darkElevated.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(KinrelRadius.sm),
            ),
          ),
        ],
      ),
    );
  }

  // ── Default header ("Add <name> as your...") ──────────────────────
  //
  // v5.196: The secondary line (avatar + @username) is now bound to
  // the selected user's REAL `username` field. If the user has no
  // username set (null or empty), the entire secondary line is
  // HIDDEN — we no longer fall back to `displayId` (the synthetic
  // 'KIN-XXXXX' hash), which was showing up as '@KIN-00234' on
  // profiles without a username and looked like a broken placeholder.

  Widget _buildDefaultHeader() {
    final username = widget.selectedUser.username;
    final hasUsername = username != null && username.trim().isNotEmpty;
    final avatarUrl = widget.selectedUser.avatarUrl;
    final hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.base, vertical: KinrelSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add ${widget.selectedUser.name} as your...',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: KinrelColors.textWhite,
            ),
          ),
          // v5.196: Only render the avatar + @username line when the
          // user has a real username. When the username is null/empty,
          // hide the whole line (including the avatar) instead of
          // showing a placeholder like '@KIN-00234'.
          if (hasUsername) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                if (hasAvatar)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ClipOval(
                      child: Image.network(
                        avatarUrl,
                        width: 20,
                        height: 20,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const SizedBox(width: 20, height: 20),
                      ),
                    ),
                  ),
                Flexible(
                  child: Text(
                    '@$username',
                    style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 13,
                      color: KinrelColors.orange,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Inline gender follow-up prompt (renders below the chips grid) ──
  //
  // v5.197 (INLINE GENDER STEP): The gender follow-up is now rendered
  // INLINE below the chips grid (no separate screen, no back arrow).
  // When the user taps a chip that requires a gender follow-up (Parent
  // / Sibling / Child / Grandparent when the selected user's gender
  // is null), the previously-tapped chip is shown in a visually
  // SELECTED/HIGHLIGHTED state in the grid above, and a "Is [Name]...
  // [Male] [Female] [Other]" prompt appears directly below the grid.
  //
  // Tapping Male/Female/Other resolves the gendered label and commits
  // (same flow as before). Tapping the highlighted chip again OR
  // tapping any other chip cancels the follow-up and starts a new
  // selection (no explicit Cancel button needed).

  Widget _buildChipsGridWithInlineGender() {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.base, vertical: KinrelSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The 2x3 chips grid. The currently-selected chip (when
          // _awaitingGenderFor != null) is rendered in a highlighted
          // state inside _buildChipsGrid via the `isSelected` flag.
          _buildChipsGrid(),

          // Inline gender follow-up prompt (only when a chip is
          // awaiting a gender choice). Appears directly below the
          // grid in the same sheet — no screen transition.
          if (_awaitingGenderFor != null) ...[
            const SizedBox(height: 16),
            _buildInlineGenderPrompt(),
          ] else ...[
            const SizedBox(height: 16),
            // Default helper text (shown only when no gender follow-up
            // is active, so the inline prompt doesn't visually compete
            // with the generic helper text).
            Text(
              'Tapping a chip immediately adds the relationship. '
              'You can undo it right after.',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: KinrelColors.textDim,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Inline gender follow-up prompt (renders below the chips grid) ──
  //
  // v5.197: Replaces the previous "Is [Name]..." separate-screen
  // gender step. Now appears inline below the chips grid in the same
  // sheet. No back arrow — the user can either tap a gender chip to
  // commit, or tap a different primary chip to switch context.

  Widget _buildInlineGenderPrompt() {
    final category = _awaitingGenderFor!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KinrelColors.orange.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(
          color: KinrelColors.orange.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Prompt title
          Text(
            'Is ${widget.selectedUser.name}...',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: KinrelColors.textWhite,
            ),
          ),
          const SizedBox(height: 4),
          // Subtitle: explains this is a label-only choice for the
          // selected relationship type. Mentions the chip name so the
          // user knows what they're labelling.
          Text(
            'Pick a gender to label them as your '
            '${_prettyLabel(category.fundamentalKey)}. '
            'This is only used for this relationship — it does not '
            'change their profile.',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              color: KinrelColors.textDim,
            ),
          ),
          const SizedBox(height: 12),
          // Gender chips (Male / Female / Other)
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _GenderChip(
                label: 'Male',
                icon: Icons.male,
                isCommitting: _isCommitting,
                onTap: () => _commitWithGender('male'),
              ),
              _GenderChip(
                label: 'Female',
                icon: Icons.female,
                isCommitting: _isCommitting,
                onTap: () => _commitWithGender('female'),
              ),
              _GenderChip(
                label: 'Other',
                icon: Icons.more_horiz,
                isCommitting: _isCommitting,
                onTap: () => _commitWithGender('other'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Chips grid — 2x3 layout ─────────────────────────────────────────
  //
  // v5.196: The grid is now a fixed 2-column, 3-row layout:
  //   Row 1: Parent  | Child
  //   Row 2: Sibling | Spouse
  //   Row 3: Grandparent | More
  //
  // The order is driven by the `_QuickPickCategory` enum (Parent,
  // Child, Sibling, Spouse, Grandparent). The "More" chip is the 6th
  // item, rendered via a dedicated widget (visually similar but with
  // a "more" icon) and triggers the searchable-list path.
  //
  // Existing behavior is preserved:
  //   - Tapping any chip immediately commits the relationship (no
  //     submit button) and shows the "Added ✓ / Undo" toast.
  //   - Gender-based label inference stays the same: Parent + Male →
  //     'father', Sibling + Female → 'sister', etc.
  //   - Gender follow-up (v5.197) now renders INLINE below the grid
  //     for Parent / Sibling / Child / Grandparent when the selected
  //     user's gender is null; Spouse is exempt (already gender-
  //     neutral).
  //   - Existing-relationship hiding: if the viewer already has an
  //     edge matching the SPECIFIC label (father/mother/son/etc.),
  //     the chip is hidden. The "More" chip is ALWAYS shown.

  Widget _buildChipsGrid() {
    // Build the list of primary chips in the enum order. We always
    // build all 5 — the `_shouldHideCategory` filter is applied here
    // to leave a gap (we render a SizedBox in the slot so the 2-column
    // row layout is preserved when one chip is hidden).
    final primaryChips = <Widget>[];
    for (final category in _QuickPickCategory.values) {
      if (_shouldHideCategory(category)) {
        // Render an invisible placeholder so the 2-column grid layout
        // doesn't collapse to a single column when one chip is hidden.
        primaryChips.add(const SizedBox(width: _kChipWidth, height: _kChipHeight));
      } else {
        // v5.197: A chip is "selected" (highlighted) when it's the
        // one currently awaiting a gender follow-up.
        final bool isSelected = _awaitingGenderFor == category;
        primaryChips.add(
          _QuickPickChip(
            category: category,
            specificLabel: _specificLabelFor(category),
            isCommitting: _isCommitting,
            isSelected: isSelected,
            onTap: () {
              if (isSelected) {
                // Tapping the already-selected chip cancels the
                // gender follow-up (acts as a toggle).
                setState(() => _awaitingGenderFor = null);
              } else {
                _commit(category);
              }
            },
          ),
        );
      }
    }

    // The 6th slot is always the "More" chip — it's the entry to the
    // searchable list and is never hidden by existing-relationship
    // detection (it represents all OTHER kinship terms).
    final moreChip = _MoreChip(
      onTap: _isCommitting
          ? null
          : () {
              setState(() {
                _showMore = true;
                // Also cancel any in-progress gender follow-up when
                // the user switches to the "More" list.
                _awaitingGenderFor = null;
              });
            },
    );

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        ...primaryChips,
        moreChip,
      ],
    );
  }

  // ── "More" searchable list (uses the existing kinship dataset) ──────

  Widget _buildMoreList() {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.55,
      child: _MoreRelationshipList(
        familyId: widget.familyId,
        onSelected: (String specificLabel) {
          _commitCustom(specificLabel);
        },
        onBack: () {
          setState(() => _showMore = false);
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// _QuickPickChip — a single primary chip
// ═══════════════════════════════════════════════════════════════════════

class _QuickPickChip extends StatelessWidget {
  const _QuickPickChip({
    required this.category,
    required this.specificLabel,
    required this.isCommitting,
    required this.onTap,
    this.isSelected = false,
  });

  final _QuickPickCategory category;
  final String specificLabel;
  final bool isCommitting;
  final VoidCallback onTap;

  /// v5.197: When true, the chip is rendered in a visually SELECTED /
  /// highlighted state — used when the user has tapped this chip and
  /// is now being asked to pick a gender inline below the grid. The
  /// highlight gives the user a clear visual indication of which
  /// relationship they're currently configuring.
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    // The chip shows the GENDER-INFERRED label (e.g. "Father" instead
    // of "Parent" when the selected user's gender is male). When the
    // gender is unknown, the chip shows the gender-neutral label
    // ("Parent"/"Sibling"/"Child"/"Grandparent"/"Spouse").
    final displayLabel = _prettyLabel(specificLabel);

    // v5.197: Selected chip uses a solid orange fill + white text +
    // thicker border to clearly indicate the current selection.
    // Non-selected chips use the existing subtle orange-outline style.
    final Color chipBg = isSelected
        ? KinrelColors.orange
        : (isCommitting
            ? KinrelColors.darkElevated.withValues(alpha: 0.5)
            : KinrelColors.darkElevated);
    final Color chipBorder = isSelected
        ? KinrelColors.orange
        : KinrelColors.orange.withValues(alpha: 0.3);
    final double borderWidth = isSelected ? 2 : 1;
    final Color iconColor = isSelected
        ? Colors.white
        : KinrelColors.orange;
    final Color textColor = isSelected
        ? Colors.white
        : (isCommitting ? KinrelColors.textDim : KinrelColors.textWhite);

    // v5.196: Fixed width so the chip fits the 2-column grid layout.
    return SizedBox(
      width: _kChipWidth,
      height: _kChipHeight,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isCommitting ? null : onTap,
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: chipBg,
              borderRadius: BorderRadius.circular(KinrelRadius.md),
              border: Border.all(
                color: chipBorder,
                width: borderWidth,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(category.icon,
                    color: iconColor,
                    size: isCommitting ? 14 : 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    displayLabel,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isCommitting) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      color: KinrelColors.orange,
                      strokeWidth: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _prettyLabel(String specificLabel) {
    return specificLabel
        .split('_')
        .map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }
}

// ═══════════════════════════════════════════════════════════════════════
// _MoreChip — the "More" chip that expands the searchable list
// ═══════════════════════════════════════════════════════════════════════

class _MoreChip extends StatelessWidget {
  const _MoreChip({required this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // v5.196: Fixed width to match the primary chips so the 2x3 grid
    // stays aligned. The "More" chip is the 6th item in the grid
    // (Row 3, column 2 — paired with Grandparent).
    return SizedBox(
      width: _kChipWidth,
      height: _kChipHeight,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(KinrelRadius.md),
              border: Border.all(
                color: KinrelColors.textDim.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.more_horiz, color: KinrelColors.textDim, size: 16),
                SizedBox(width: 8),
                Text(
                  'More',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.textDim,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// _GenderChip — a single gender chip (Male / Female / Other)
//
// v5.195: Used by the gender follow-up step. Tapping one resolves
// the gendered label (e.g. Sibling + Male → Brother) and commits
// the relationship. "Other" uses the gender-neutral term (e.g.
// "Sibling", "Parent") as the final label.
// ═══════════════════════════════════════════════════════════════════════

class _GenderChip extends StatelessWidget {
  const _GenderChip({
    required this.label,
    required this.icon,
    required this.isCommitting,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isCommitting;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isCommitting ? null : onTap,
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          decoration: BoxDecoration(
            color: isCommitting
                ? KinrelColors.darkElevated.withValues(alpha: 0.5)
                : KinrelColors.darkElevated,
            borderRadius: BorderRadius.circular(KinrelRadius.md),
            border: Border.all(
              color: KinrelColors.orange.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  color: KinrelColors.orange,
                  size: isCommitting ? 14 : 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isCommitting
                      ? KinrelColors.textDim
                      : KinrelColors.textWhite,
                ),
              ),
              if (isCommitting) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    color: KinrelColors.orange,
                    strokeWidth: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// _MoreRelationshipList — searchable list of all kinship terms
// ═══════════════════════════════════════════════════════════════════════

class _MoreRelationshipList extends ConsumerStatefulWidget {
  const _MoreRelationshipList({
    required this.familyId,
    required this.onSelected,
    required this.onBack,
  });

  final String familyId;
  final void Function(String specificLabel) onSelected;
  final VoidCallback onBack;

  @override
  ConsumerState<_MoreRelationshipList> createState() =>
      _MoreRelationshipListState();
}

class _MoreRelationshipListState extends ConsumerState<_MoreRelationshipList> {
  final _searchController = TextEditingController();
  String _query = '';
  List<KinshipRelationship> _allRelationships = [];
  List<KinshipRelationship> _filtered = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAllRelationships();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAllRelationships() async {
    try {
      // Ensure kinship data is initialized first.
      await ref.read(kinshipInitializedProvider.future);
      final service = ref.read(kinshipServiceProvider);
      final all = <KinshipRelationship>[];
      for (final category in service.categories) {
        all.addAll(service.getByCategory(category));
      }
      // De-dupe by relationshipKey.
      final seen = <String>{};
      final deduped = <KinshipRelationship>[];
      for (final rel in all) {
        if (seen.contains(rel.relationshipKey)) continue;
        seen.add(rel.relationshipKey);
        deduped.add(rel);
      }
      // Sort alphabetically by englishTerm.
      deduped.sort((a, b) =>
          a.englishTerm.toLowerCase().compareTo(b.englishTerm.toLowerCase()));
      if (mounted) {
        setState(() {
          _allRelationships = deduped;
          _filtered = deduped;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load kinship terms: $e')),
        );
      }
    }
  }

  void _filter(String query) {
    final q = query.toLowerCase().trim();
    setState(() => _query = q);
    if (q.isEmpty) {
      setState(() => _filtered = _allRelationships);
      return;
    }
    setState(() {
      _filtered = _allRelationships.where((rel) {
        return rel.englishTerm.toLowerCase().contains(q) ||
            rel.relationshipKey.toLowerCase().contains(q) ||
            rel.searchKeywords.any((k) => k.toLowerCase().contains(q));
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header with back button + search field.
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: KinrelSpacing.base, vertical: KinrelSpacing.sm),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back,
                    color: KinrelColors.textWhite, size: 22),
                onPressed: widget.onBack,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  onChanged: _filter,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 15,
                    color: KinrelColors.textWhite,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search relations (uncle, cousin, in-law...)',
                    hintStyle: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      color: KinrelColors.textDim,
                    ),
                    prefixIcon: const Icon(Icons.search,
                        color: KinrelColors.orange, size: 20),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear,
                                color: KinrelColors.textDim, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              _filter('');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: KinrelColors.darkElevated,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(KinrelSpacing.radiusSm),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Results list.
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: KinrelColors.orange),
                )
              : _filtered.isEmpty
                  ? Center(
                      child: Text(
                        'No relations found for "$_query"',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 14,
                          color: KinrelColors.textDim,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: KinrelSpacing.base),
                      itemCount: _filtered.length,
                      itemBuilder: (context, index) {
                        final rel = _filtered[index];
                        return _MoreRelationshipTile(
                          englishTerm: rel.englishTerm,
                          relationshipKey: rel.relationshipKey,
                          onTap: () => widget.onSelected(rel.relationshipKey),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class _MoreRelationshipTile extends StatelessWidget {
  const _MoreRelationshipTile({
    required this.englishTerm,
    required this.relationshipKey,
    required this.onTap,
  });

  final String englishTerm;
  final String relationshipKey;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: KinrelSpacing.md, vertical: KinrelSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(KinrelRadius.md),
            border: Border.all(
              color: KinrelColors.darkElevated,
              width: 1,
            ),
          ),
          margin: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      englishTerm,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.textWhite,
                      ),
                    ),
                    if (relationshipKey != englishTerm.toLowerCase())
                      Text(
                        relationshipKey.replaceAll('_', ' '),
                        style: TextStyle(
                          fontFamily: KinrelTypography.monoFont,
                          fontSize: 11,
                          color: KinrelColors.textDim,
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.add, color: KinrelColors.orange, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

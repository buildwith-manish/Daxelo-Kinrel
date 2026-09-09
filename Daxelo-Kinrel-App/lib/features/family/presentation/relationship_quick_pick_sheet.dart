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

/// The five primary quick-pick categories. Each maps to a fundamental
/// edge key ('parent', 'spouse') that the DB constraint accepts, plus
/// a gender-aware specific label that gets stored in `labelAtoB`.
///
/// The "from the viewer's perspective" semantic:
///   - Parent     → "the selected user is the viewer's parent"
///   - Sibling    → "the selected user is the viewer's sibling"
///   - Spouse     → "the selected user is the viewer's spouse"
///   - Child      → "the selected user is the viewer's child"
///   - Grandparent → "the selected user is the viewer's grandparent"
enum _QuickPickCategory {
  parent('parent', 'Parent', Icons.family_restroom),
  sibling('sibling', 'Sibling', Icons.people_outline),
  spouse('spouse', 'Spouse', Icons.favorite_outline),
  child('child', 'Child', Icons.child_care_outlined),
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
    switch (category) {
      case _QuickPickCategory.parent:
        if (gender == 'male') return 'father';
        if (gender == 'female') return 'mother';
        return 'parent';
      case _QuickPickCategory.sibling:
        if (gender == 'male') return 'brother';
        if (gender == 'female') return 'sister';
        return 'sibling';
      case _QuickPickCategory.spouse:
        if (gender == 'male') return 'husband';
        if (gender == 'female') return 'wife';
        return 'spouse';
      case _QuickPickCategory.child:
        if (gender == 'male') return 'son';
        if (gender == 'female') return 'daughter';
        return 'child';
      case _QuickPickCategory.grandparent:
        if (gender == 'male') return 'grandfather';
        if (gender == 'female') return 'grandmother';
        return 'grandparent';
    }
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
  Future<void> _commit(_QuickPickCategory category) async {
    if (_isCommitting) return;
    setState(() => _isCommitting = true);

    final messenger = ScaffoldMessenger.maybeOf(context);
    final specificLabel = _specificLabelFor(category);
    final fundamentalKey = category.fundamentalKey;

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
  /// linked via that relationship. e.g. if the viewer already has a
  /// "father" edge in the family, hide the "Parent" chip (it's
  /// extremely unusual to have two fathers in a single family).
  ///
  /// Implementation: read the family's existing relationships, check
  /// whether any edge has a labelAtoB/labelBtoA matching the gendered
  /// form OR the gender-neutral form for this category.
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
      final labels = <String?>{
        rel.labelAtoB,
        rel.labelBtoA,
        rel.relationshipKey,
      };
      for (final label in labels) {
        if (label == null) continue;
        final lc = label.toLowerCase();
        if (genderedForms.contains(lc)) {
          // Only hide if the relationship is between the viewer and
          // someone OTHER than the selected user (we don't want to
          // hide the chip if the existing edge IS to the selected
          // user — that case is handled by the search screen's
          // "Already Added" badge instead).
          // For simplicity, hide if any edge matches the category.
          return true;
        }
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final safePadding = MediaQuery.of(context).padding.bottom;
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

            // Header
            Padding(
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
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (widget.selectedUser.avatarUrl != null &&
                          widget.selectedUser.avatarUrl!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ClipOval(
                            child: Image.network(
                              widget.selectedUser.avatarUrl!,
                              width: 20,
                              height: 20,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const SizedBox(width: 20, height: 20),
                            ),
                          ),
                        ),
                      Text(
                        '@${widget.selectedUser.username ?? widget.selectedUser.displayId}',
                        style: TextStyle(
                          fontFamily: KinrelTypography.monoFont,
                          fontSize: 13,
                          color: KinrelColors.orange,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const Divider(
                color: KinrelColors.darkElevated, height: 1, thickness: 1),

            // Body — either the chips grid OR the "More" search list.
            if (_showMore)
              _buildMoreList()
            else
              _buildChipsGrid(),

            const SizedBox(height: KinrelSpacing.base),
          ],
        ),
      ),
    );
  }

  // ── Chips grid (Parent / Sibling / Spouse / Child / Grandparent / More) ─

  Widget _buildChipsGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.base, vertical: KinrelSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Primary chips (2x2 grid + Grandparent row).
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final category in _QuickPickCategory.values)
                if (!_shouldHideCategory(category))
                  _QuickPickChip(
                    category: category,
                    specificLabel: _specificLabelFor(category),
                    isCommitting: _isCommitting,
                    onTap: () => _commit(category),
                  ),
            ],
          ),

          const SizedBox(height: 12),

          // "More" chip.
          _MoreChip(
            onTap: () {
              setState(() => _showMore = true);
            },
          ),

          const SizedBox(height: 16),

          // Helper text.
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
      ),
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
  });

  final _QuickPickCategory category;
  final String specificLabel;
  final bool isCommitting;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // The chip shows the GENDER-INFERRED label (e.g. "Father" instead
    // of "Parent" when the selected user's gender is male). When the
    // gender is unknown, the chip shows the gender-neutral label
    // ("Parent"/"Sibling"/"Child"/"Grandparent"/"Spouse").
    final displayLabel = _prettyLabel(specificLabel);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isCommitting ? null : onTap,
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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
              Icon(category.icon,
                  color: KinrelColors.orange,
                  size: isCommitting ? 14 : 16),
              const SizedBox(width: 8),
              Text(
                displayLabel,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
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
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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

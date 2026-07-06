// lib/graph/widgets/graph_quick_actions.dart
//
// Extracted from family_graph.dart (v31 refactor).
//
// The bottom sheet that appears when a user taps-holds a graph node.
// Shows the person's name + quick actions (View Profile, Edit, Remove Member).
//
// Web + mobile compatible: uses standard Material showModalBottomSheet,
// which renders as a modal dialog on web (no platform-specific code).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/brand_colors.dart';
import '../../core/constants/brand_typography.dart';
import '../../core/family/family_provider.dart';
import '../../features/family/presentation/add_person_sheet.dart';
import 'graph_relationship_labels.dart';

/// Shows a modal bottom sheet with quick actions for a graph node.
///
/// Extracted from the FamilyGraphWidget's `_showQuickActions` method
/// so the sheet can be reused by other entry points (e.g. the info
/// card, the 3D tree view) without duplicating ~80 lines of UI code.
class GraphQuickActions {
  GraphQuickActions._();

  /// Shows the quick-actions sheet for [person].
  ///
  /// Callers should pass the person's [GraphPersonData] — the sheet
  /// displays the name and provides 'View Profile', 'Edit', and
  /// 'Remove Member' actions.
  ///
  /// [familyId] is required for the Remove Member action.
  /// [isOwner] controls whether the Remove Member option is shown.
  /// [isSelf] prevents the owner from removing themselves.
  static void show(
    BuildContext context,
    GraphPersonData person, {
    String? familyId,
    bool isOwner = false,
    bool isSelf = false,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: 12.0, bottom: 4.0),
              child: Container(
                width: 40.0,
                height: 4.0,
                decoration: BoxDecoration(
                  color: KinrelColors.textDim,
                  borderRadius: BorderRadius.circular(2.0),
                ),
              ),
            ),
            // Person name
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 20.0,
                vertical: 12.0,
              ),
              child: Text(
                person.name,
                style: const TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 18.0,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                ),
              ),
            ),
            const Divider(color: Color(0x1AFFFFFF), height: 1.0),
            // View Profile
            ListTile(
              leading:
                  const Icon(Icons.person, color: KinrelColors.tealAccent),
              title: const Text(
                'View Profile',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  color: KinrelColors.textWhite,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                if (familyId != null) {
                  context.push('/member/${person.id}');
                }
              },
            ),
            // Edit
            ListTile(
              leading: const Icon(Icons.edit, color: KinrelColors.amber),
              title: const Text(
                'Edit',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  color: KinrelColors.textWhite,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                if (familyId != null) {
                  AddPersonSheet.show(
                    context,
                    familyId: familyId,
                    existingPerson: Person(
                      id: person.id,
                      familyId: familyId,
                      name: person.name,
                      gender: person.gender,
                      isDeceased: person.isDeceased,
                      photoUrl: person.photoUrl,
                      isAnchor: false,
                      generationIndex: 0,
                      dateOfBirth: person.dateOfBirth,
                    ),
                  );
                }
              },
            ),
            // Remove Member — shown for all non-self nodes (not just non-anchor)
            if (!isSelf && familyId != null) ...[
              const Divider(color: Color(0x1AFFFFFF), height: 1.0),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text(
                  'Remove Member',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    color: Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showRemoveConfirmation(
                    context,
                    person,
                    familyId,
                  );
                },
              ),
            ],
            const SizedBox(height: 8.0),
          ],
        ),
      ),
    );
  }

  /// Shows the confirmation dialog before removing a member.
  static void _showRemoveConfirmation(
    BuildContext context,
    GraphPersonData person,
    String familyId,
  ) {
    showDialog(
      context: context,
      builder: (context) => _RemoveMemberDialog(
        personName: person.name,
        personId: person.id,
        familyId: familyId,
      ),
    );
  }
}

/// Confirmation dialog for removing a member.
/// Shows the member name, a warning message, and Cancel/Remove buttons.
class _RemoveMemberDialog extends ConsumerStatefulWidget {
  const _RemoveMemberDialog({
    required this.personName,
    required this.personId,
    required this.familyId,
  });

  final String personName;
  final String personId;
  final String familyId;

  @override
  ConsumerState<_RemoveMemberDialog> createState() => _RemoveMemberDialogState();
}

class _RemoveMemberDialogState extends ConsumerState<_RemoveMemberDialog> {
  bool _isDeleting = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: KinrelColors.darkCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
      ),
      title: const Text(
        'Remove Member',
        style: TextStyle(
          fontFamily: KinrelTypography.displayFont,
          fontSize: 18.0,
          fontWeight: FontWeight.w700,
          color: KinrelColors.textWhite,
        ),
      ),
      content: Text(
        'Are you sure you want to remove ${widget.personName} from this family?\n\n'
        'This action will permanently remove the member and all relationship connections associated with them.',
        style: const TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 14.0,
          color: KinrelColors.textSilver,
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isDeleting ? null : () => Navigator.pop(context),
          child: const Text(
            'Cancel',
            style: TextStyle(color: KinrelColors.textDim),
          ),
        ),
        TextButton(
          onPressed: _isDeleting ? null : () => _performDeletion(),
          child: _isDeleting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.red,
                  ),
                )
              : const Text(
                  'Remove',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _performDeletion() async {
    // v88 FIX: Capture the navigator BEFORE the async call so we
    // can close the dialog even if the widget tree rebuilds during
    // the deletion (which happens because deletePerson invalidates
    // Riverpod providers, causing parent widgets to rebuild).
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);

    setState(() => _isDeleting = true);

    try {
      await deletePerson(
        ref: ref,
        personId: widget.personId,
        familyId: widget.familyId,
      );

      // Close the dialog FIRST, then show the success message.
      // Using the captured navigator avoids context issues after
      // provider invalidation.
      if (mounted) {
        navigator.pop();
      }
      messenger?.showSnackBar(
        SnackBar(
          content: Text('${widget.personName} removed from family'),
          backgroundColor: KinrelColors.tealAccent,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isDeleting = false);
      }
      messenger?.showSnackBar(
        SnackBar(
          content: Text('Failed to remove member: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }
}

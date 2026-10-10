// lib/features/chat/presentation/widgets/delete_confirmation_dialog.dart
//
// DAXELO KINREL — Delete Confirmation Dialog (WhatsApp-style)
//
// Shows a dialog with "Delete for Me" + "Delete for Everyone" options
// when the user presses Delete in the selection toolbar. The
// "Delete for Everyone" option is only shown when at least one of the
// selected messages was sent by the current user (the backend enforces
// the same rule — only the sender can delete for everyone).
//
// After the user confirms, the dialog calls the appropriate callback
// with the set of selected message IDs. The caller (chat_screen.dart)
// then invokes the existing ChatEnhancementService.deleteForMe() or
// deleteForEveryone() methods — no new backend code is needed.

import 'package:flutter/material.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';

/// Shows the delete confirmation dialog.
///
/// Parameters:
///   [context] — the build context
///   [selectedCount] — how many messages are selected (for the title)
///   [canDeleteForEveryone] — true when at least one selected message
///     was sent by the current user (the "Delete for Everyone" option
///     is shown only when this is true)
///   [onDeleteForMe] — callback when the user picks "Delete for Me"
///   [onDeleteForEveryone] — callback when the user picks "Delete for Everyone"
///
/// Returns a Future that completes when the dialog is dismissed.
Future<void> showDeleteConfirmationDialog({
  required BuildContext context,
  required int selectedCount,
  required bool canDeleteForEveryone,
  required VoidCallback onDeleteForMe,
  required VoidCallback onDeleteForEveryone,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: KinrelColors.darkCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: Text(
        selectedCount == 1 ? 'Delete message?' : 'Delete $selectedCount messages?',
        style: const TextStyle(
          fontFamily: KinrelTypography.displayFont,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: KinrelColors.textWhite,
        ),
      ),
      content: Text(
        canDeleteForEveryone
            ? 'Choose how to delete the selected message${selectedCount > 1 ? 's' : ''}.'
            : 'The selected message${selectedCount > 1 ? 's' : ''} will be removed from your view only.',
        style: const TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 14,
          color: KinrelColors.textSilver,
        ),
      ),
      actions: [
        // Cancel
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel',
              style: TextStyle(color: KinrelColors.textSilver)),
        ),
        // Delete for Me (always available)
        TextButton(
          onPressed: () {
            Navigator.pop(ctx);
            onDeleteForMe();
          },
          child: const Text('Delete for Me',
              style: TextStyle(color: KinrelColors.textWhite)),
        ),
        // Delete for Everyone (only when the user sent at least one of the selected messages)
        if (canDeleteForEveryone)
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onDeleteForEveryone();
            },
            child: const Text('Delete for Everyone',
                style: TextStyle(color: Colors.red)),
          ),
      ],
    ),
  );
}

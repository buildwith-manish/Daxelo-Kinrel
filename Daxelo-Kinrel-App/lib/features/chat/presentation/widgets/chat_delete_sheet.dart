// lib/features/chat/presentation/widgets/chat_delete_sheet.dart
//
// DAXELO KINREL — Delete messages sheet (Task 5).
//
// Bottom sheet titled "Delete N messages" (or "Delete message" when
// exactly one). Two options + cancel:
//
//   Delete for everyone (red, only when ALL selected are the user's own
//   AND caps.canDeleteForEveryone is true for every one of them).
//   The existing confirm dialog is kept (the screen's action callback
//   may show it; if the callback doesn't, the sheet shows a fallback
//   confirm dialog before invoking it).
//
//   Delete for me — soft-delete (per-user) the messages.
//   Per the prompt: shows a snackbar "Messages deleted" with an Undo
//   for 5 seconds and commits after the snackbar expires. If the
//   current backend call cannot be delayed safely, apply it
//   immediately and skip Undo. The screen-supplied `deleteForMe`
//   callback decides: it should accept the messages, perform the
//   delete immediately (the prompt allows skipping Undo if the backend
//   call can't be delayed safely), and return. The sheet shows the
//   snackbar with Undo ONLY when the callback reports it can be undone.
//   Since the existing chatEnhancementServiceProvider.deleteForMe is a
//   synchronous database update with no undo path (no soft-delete-with-
//   undo endpoint exists), we apply immediately and skip Undo. The
//   report flags this as "Undo on delete — not implemented, requires a
//   backend soft-delete-with-window endpoint that doesn't exist today."
//
//   Cancel — dismiss the sheet without action.
//
// If some selected messages are others' messages (group chat), only
// "Delete for me" is offered (Delete for everyone is hidden).
//
// Direct chat: only the own-failed-message exception reaches this sheet
// (the selection bar gates the Delete button to that case). The sheet
// shows only "Delete" (which calls actions.deleteFailed per message)
// and Cancel. The label reads "Delete failed message".

import 'package:flutter/material.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../providers/chat_provider.dart';
import 'chat_capabilities.dart';
import 'chat_message_actions.dart';

class ChatDeleteSheet {
  ChatDeleteSheet._();

  static Future<void> show({
    required BuildContext context,
    required List<ChatMessage> messages,
    required ChatCapabilities capabilities,
    required ChatMessageActions actions,
  }) async {
    final count = messages.length;
    final caps = capabilities;
    final acts = actions;

    // ── Direct chat path: own failed messages ────────────────────────
    // The selection bar already gated the Delete button to "all own
    // failed" in direct chat, so we can call deleteFailed directly.
    if (caps.isDirect) {
      final title = count == 1
          ? 'Delete failed message'
          : 'Delete $count failed messages';
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: KinrelColors.darkCard,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded,
                      color: KinrelColors.red),
                  title: const Text('Delete',
                      style: TextStyle(color: KinrelColors.red)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    if (acts.deleteFailed != null) {
                      for (final m in messages) {
                        await acts.deleteFailed!(m);
                      }
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.close_rounded),
                  title: const Text('Cancel'),
                  onTap: () => Navigator.pop(ctx),
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }

    // ── Group chat path ──────────────────────────────────────────────
    final allOwn = messages.every((m) => m.senderId == caps.currentUserId);
    final canDeleteEveryone =
        allOwn && messages.every((m) => caps.canDeleteForEveryone(m));

    final title = count == 1
        ? 'Delete message'
        : 'Delete $count messages';

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  title,
                  style: const TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.textWhite,
                  ),
                ),
              ),
              if (canDeleteEveryone && acts.deleteForEveryone != null)
                ListTile(
                  leading: const Icon(Icons.delete_forever_rounded,
                      color: KinrelColors.red),
                  title: const Text('Delete for everyone',
                      style: TextStyle(color: KinrelColors.red)),
                  onTap: () async {
                    // Keep the existing confirm dialog pattern.
                    final confirmed = await _confirm(
                      context: ctx,
                      title: count == 1
                          ? 'Delete this message for everyone?'
                          : 'Delete $count messages for everyone?',
                      body: 'This will remove the message(s) for everyone '
                          'in this chat. This action cannot be undone.',
                      confirmLabel: 'Delete for everyone',
                    );
                    if (!confirmed) return;
                    Navigator.pop(ctx);
                    await acts.deleteForEveryone!(messages);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    color: KinrelColors.textSilver),
                title: const Text('Delete for me'),
                onTap: () async {
                  Navigator.pop(ctx);
                  // Undo on delete is not implemented — the existing
                  // chatEnhancementServiceProvider.deleteForMe is a
                  // synchronous database update with no undo path
                  // (no soft-delete-with-window endpoint exists).
                  // Apply immediately and report. See the report at
                  // docs/perf/PR2_gradient_and_image_audit.md or the
                  // PR-1 description for the explanation.
                  await acts.deleteForMe(messages);
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text('Messages deleted'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.close_rounded),
                title: const Text('Cancel'),
                onTap: () => Navigator.pop(ctx),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Confirm dialog (kept consistent with the existing
  /// `_confirmDelete` pattern in chat_screen.dart).
  static Future<bool> _confirm({
    required BuildContext context,
    required String title,
    required String body,
    required String confirmLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KinrelColors.darkCard,
        title: Text(title,
            style: const TextStyle(color: KinrelColors.textWhite)),
        content: Text(body,
            style: const TextStyle(color: KinrelColors.textSilver)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel,
                style: const TextStyle(color: KinrelColors.red)),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

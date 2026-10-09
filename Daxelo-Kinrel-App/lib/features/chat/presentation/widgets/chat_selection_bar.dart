// lib/features/chat/presentation/widgets/chat_selection_bar.dart
//
// DAXELO KINREL — Chat selection bar (Task 3).
//
// Replaces the normal chat header while in selection mode. Swaps with
// a 150 ms (or shorter) transition. Layout:
//
//   [close] [N selected] [action1] [action2] [action3] [action4] [⋮]
//
// Max 4 icon actions + the overflow on a 360 dp wide phone. The
// overflow is hidden if it would be empty.
//
// Action visibility rules (every action must be valid for EVERY
// selected message):
//
//   PRIMARY (icons, in this order):
//     Reply       — exactly 1 selected AND canReply
//     Forward     — canForward AND every selected is forwardable
//                   (not deleted, not system event, not game invite)
//     Delete      — see `_canDeleteSelection` (group: any non-deleted;
//                   direct: all own failed)
//
//   OVERFLOW (three-dots menu, only items valid for the current
//   selection appear):
//     Copy                       — always when canCopy AND at least one
//                                  message has text content
//     Star / Unstar              — canStar (label depends on whether
//                                  all selected are already starred)
//     Pin / Unpin                — exactly 1 selected, canPin
//     Edit                       — exactly 1 own text, canEdit
//     Message info               — exactly 1 selected, canShowMessageInfo
//     Share outside Kinrel       — canShareOutside
//     Save to gallery             — all selected are media (photo/gif)
//                                  AND actions.saveToGallery != null
//     Add to Memories            — exactly 1, only if actions.addToMemories
//                                  != null (NOT IMPLEMENTED — see report)
//     Report                     — exactly 1, someone else's message,
//                                  only if actions.report != null
//                                  (NOT IMPLEMENTED — see report)
//
// After an action completes, the selection controller is cleared
// (the bar calls `exit()` on the controller).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/services/haptic_service.dart';
import '../../providers/chat_provider.dart';
import 'chat_capabilities.dart';
import 'chat_delete_sheet.dart';
import 'chat_message_actions.dart';
import 'chat_selection_controller.dart';

class ChatSelectionBar extends ConsumerWidget {
  const ChatSelectionBar({
    super.key,
    required this.chatId,
    required this.capabilities,
    required this.actions,
    required this.selectedMessages,
  });

  /// The chat id used to look up the selection controller.
  final String chatId;

  /// Capabilities (group vs direct) — drive action availability.
  final ChatCapabilities capabilities;

  /// Per-screen action callbacks (null = action not available).
  final ChatMessageActions actions;

  /// The currently selected messages in selection order (ascending
  /// time for the Copy/Share join — the controller preserves insertion
  /// order; we re-sort here for the join).
  final List<ChatMessage> selectedMessages;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = selectedMessages.length;
    final caps = capabilities;
    final acts = actions;

    // ── Compute primary actions ───────────────────────────────────────
    final canReply = count == 1 && caps.canReply;
    final canForward = count >= 1 && caps.canForward && _allForwardable(selectedMessages, caps);
    final canDelete = _canDeleteSelection(selectedMessages, caps);

    final primaryActions = <_SelectionAction>[];
    if (canReply) {
      primaryActions.add(_SelectionAction(
        icon: Icons.reply_rounded,
        semanticLabel: 'Reply',
        onTap: () {
          acts.reply(selectedMessages.first);
          ref.read(chatSelectionProvider(chatId).notifier).exit();
        },
      ));
    }
    if (canForward && acts.forward != null) {
      primaryActions.add(_SelectionAction(
        icon: Icons.shortcut_rounded,
        semanticLabel: 'Forward',
        onTap: () async {
          await acts.forward!(selectedMessages);
          ref.read(chatSelectionProvider(chatId).notifier).exit();
        },
      ));
    }
    if (canDelete) {
      primaryActions.add(_SelectionAction(
        icon: Icons.delete_outline_rounded,
        semanticLabel: 'Delete',
        onTap: () async {
          await ChatDeleteSheet.show(
            context: context,
            messages: selectedMessages,
            capabilities: caps,
            actions: acts,
          );
          ref.read(chatSelectionProvider(chatId).notifier).exit();
        },
      ));
    }

    // Cap primary icons at 4 (per the prompt: "Max 4 icons plus the
    // overflow on a 360 dp wide phone").
    final visiblePrimary = primaryActions.take(4).toList();
    final overflowActions = _buildOverflowActions(
      context: context,
      ref: ref,
      selected: selectedMessages,
      caps: caps,
      acts: acts,
    );

    final hasOverflow = overflowActions.isNotEmpty;
    // The overflow counts as one of the 4 visible icons.
    // If we have 4 primary + overflow, drop the 4th primary to make
    // room for the overflow (overflow has higher priority because it
    // contains context-dependent actions).
    final maxPrimary = hasOverflow ? 3 : 4;
    final displayPrimary = visiblePrimary.take(maxPrimary).toList();

    return Semantics(
      container: true,
      label: '${selectedMessages.length} messages selected',
      child: Container(
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          border: Border(
            bottom: BorderSide(
              color: Colors.white.withValues(alpha: 0.08),
              width: 0.5,
            ),
          ),
        ),
        child: SafeArea(
          top: true,
          bottom: false,
          child: SizedBox(
            height: 56,
            child: NavigationToolbar(
              leading: IconButton(
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Close selection',
                onPressed: () {
                  unawaited(HapticService.tap());
                  ref.read(chatSelectionProvider(chatId).notifier).exit();
                },
              ),
              middle: Text(
                '$count',
                style: const TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textWhite,
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...displayPrimary.map((a) => _IconButton(action: a)),
                  if (hasOverflow)
                    PopupMenuButton<_OverflowItem>(
                      tooltip: 'More actions',
                      icon: const Icon(Icons.more_vert_rounded),
                      itemBuilder: (_) => overflowActions
                          .map((a) => PopupMenuItem<_OverflowItem>(
                                value: a,
                                child: Row(
                                  children: [
                                    Icon(a.icon, size: 22),
                                    const SizedBox(width: 12),
                                    Text(a.label),
                                  ],
                                ),
                              ))
                          .toList(),
                      onSelected: (item) async {
                        await item.onTap();
                        ref.read(chatSelectionProvider(chatId).notifier).exit();
                      },
                    ),
                ],
              ),
              centerMiddle: true,
            ),
          ),
        ),
      ),
    );
  }

  // ── Overflow action builders ───────────────────────────────────────

  List<_OverflowItem> _buildOverflowActions({
    required BuildContext context,
    required WidgetRef ref,
    required List<ChatMessage> selected,
    required ChatCapabilities caps,
    required ChatMessageActions acts,
  }) {
    final out = <_OverflowItem>[];
    final count = selected.length;

    // Copy — when canCopy AND at least one message has text content.
    if (caps.canCopy && selected.any((m) => m.content.trim().isNotEmpty)) {
      out.add(_OverflowItem(
        icon: Icons.content_copy_rounded,
        label: 'Copy',
        onTap: () async {
          final text = ChatMessageActions.copyTexts(
            messages: selected,
            isDirect: caps.isDirect,
          );
          if (text.isEmpty) return;
          await Clipboard.setData(ClipboardData(text: text));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Copied to clipboard'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        },
      ));
    }

    // Star / Unstar — when canStar.
    if (caps.canStar && acts.star != null) {
      final allStarred = selected.every((m) => m.isStarred);
      out.add(_OverflowItem(
        icon: allStarred ? Icons.star_border_rounded : Icons.star_rounded,
        label: allStarred ? 'Unstar' : 'Star',
        onTap: () async {
          // Toggle: if all starred → unstar; else → star.
          final target = !allStarred;
          for (final m in selected) {
            await acts.star!(m, target);
          }
        },
      ));
    }

    // Pin / Unpin — exactly 1, canPin(m).
    if (count == 1 && caps.canPin(selected.first) && acts.pin != null) {
      final isPinned = selected.first.isPinned;
      out.add(_OverflowItem(
        icon: Icons.push_pin_rounded,
        label: isPinned ? 'Unpin' : 'Pin',
        onTap: () async {
          await acts.pin!(selected.first, !isPinned);
        },
      ));
    }

    // Edit — exactly 1 own text, canEdit.
    if (count == 1 && caps.canEdit(selected.first) && acts.edit != null) {
      out.add(_OverflowItem(
        icon: Icons.edit_outlined,
        label: 'Edit',
        onTap: () async {
          acts.edit!(selected.first);
        },
      ));
    }

    // Message info — exactly 1, canShowMessageInfo.
    if (count == 1 && caps.canShowMessageInfo && acts.showInfo != null) {
      out.add(_OverflowItem(
        icon: Icons.info_outline_rounded,
        label: 'Message info',
        onTap: () async {
          await acts.showInfo!(selected.first);
        },
      ));
    }

    // Share outside Kinrel — when canShareOutside AND actions.shareOutside
    // is non-null.
    if (caps.canShareOutside && acts.shareOutside != null) {
      out.add(_OverflowItem(
        icon: Icons.ios_share_rounded,
        label: 'Share outside Kinrel',
        onTap: () async {
          await acts.shareOutside!(selected);
        },
      ));
    }

    // Save to gallery — when ALL selected are media AND
    // actions.saveToGallery != null.
    if (acts.saveToGallery != null &&
        selected.isNotEmpty &&
        selected.every((m) =>
            m.messageType == MessageType.photo ||
            m.messageType == MessageType.gif)) {
      out.add(_OverflowItem(
        icon: Icons.save_alt_rounded,
        label: 'Save to gallery',
        onTap: () async {
          await acts.saveToGallery!(selected);
        },
      ));
    }

    // Add to Memories — exactly 1, only if actions.addToMemories != null.
    if (count == 1 && acts.addToMemories != null) {
      out.add(_OverflowItem(
        icon: Icons.bookmark_add_out,
        label: 'Add to Memories',
        onTap: () async {
          await acts.addToMemories!(selected.first);
        },
      ));
    }

    // Report — exactly 1, someone else's message, only if
    // actions.report != null.
    if (count == 1 &&
        acts.report != null &&
        selected.first.senderId != caps.currentUserId) {
      out.add(_OverflowItem(
        icon: Icons.flag_outlined,
        label: 'Report',
        onTap: () async {
          await acts.report!(selected.first);
        },
      ));
    }

    return out;
  }

  // ── Helpers ─────────────────────────────────────────────────────────

  /// True when every selected message is forwardable (not deleted, not
  /// a system event, not a game invite).
  bool _allForwardable(List<ChatMessage> selected, ChatCapabilities caps) {
    return selected.every((m) {
      if (m.isDeletedForEveryone) return false;
      if (m.messageType == MessageType.familyEvent) return false;
      if (m.messageType == MessageType.gameInvite) return false;
      return true;
    });
  }

  /// Delete-button visibility:
  ///   - Direct chat: only when EVERY selected is an own failed message.
  ///   - Group chat: when canDeleteForMe(m) is true for every selected
  ///     (i.e. none are deleted-for-everyone — group can always soft-
  ///     delete any row per the existing rule).
  bool _canDeleteSelection(List<ChatMessage> selected, ChatCapabilities caps) {
    if (selected.isEmpty) return false;
    if (caps.isDirect) {
      return selected.every((m) =>
          m.senderId == caps.currentUserId && m.messageStatus == 'failed');
    }
    return selected.every((m) => caps.canDeleteForMe(m));
  }
}

/// Internal: a single primary icon action.
class _SelectionAction {
  const _SelectionAction({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });
  final IconData icon;
  final String semanticLabel;
  final Future<void> Function() onTap;
}

class _IconButton extends StatelessWidget {
  const _IconButton({required this.action});
  final _SelectionAction action;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(action.icon),
      tooltip: action.semanticLabel,
      onPressed: () async {
        unawaited(HapticService.tap());
        await action.onTap();
      },
    );
  }
}

/// Internal: a single overflow menu item.
class _OverflowItem {
  const _OverflowItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Future<void> Function() onTap;
}

// lib/features/chat/presentation/widgets/selection_mode_toolbar.dart
//
// DAXELO KINREL — Selection Mode Toolbar (Chat UI Reference D14)
//
// The top bar shown when selection mode is active:
//   • Height 56, background chatBar, row with 6 gap.
//   • Close icon 22 in a 48 dp target.
//   • The count in display 18 / 500, expanding to fill.
//   • Icon buttons reply, forward, star, delete, more (22 icons in
//     48 dp targets, textPrimary). Only the actions that exist today.
//   • Flat: no border, no shadow.
//
// The D17 overflow menu itself lives in chat_header_bar.dart
// (showChatOverflowMenu) — shared by the header ⋮ and the selection
// bar's "more" action.

import 'package:flutter/material.dart';

import '../chat_ui_tokens.dart';

/// Callback signature for bulk actions on a set of selected message ids.
typedef SelectionActionCallback = void Function(Set<String> messageIds);

/// The top toolbar shown when selection mode is active.
class SelectionModeToolbar extends StatelessWidget implements PreferredSizeWidget {
  const SelectionModeToolbar({
    super.key,
    required this.selectedCount,
    required this.onClose,
    required this.onReply,
    required this.onForward,
    required this.onStar,
    required this.onDelete,
    required this.onMore,
  });

  /// Number of currently selected messages.
  final int selectedCount;

  /// Close selection mode (X button).
  final VoidCallback onClose;

  /// Bulk reply — uses the LAST selected message as the reply target.
  final VoidCallback onReply;

  /// Bulk forward all selected messages.
  final VoidCallback onForward;

  /// Bulk star all selected messages.
  final VoidCallback onStar;

  /// Bulk delete all selected messages (for-me).
  final VoidCallback onDelete;

  /// Show more actions (D17 overflow menu: Copy, Star, Pin, Message
  /// info, Share outside Kinrel).
  final VoidCallback onMore;

  @override
  Size get preferredSize => const Size.fromHeight(ChatUi.barHeight);

  @override
  Widget build(BuildContext context) {
    final hasSelection = selectedCount > 0;
    return Container(
      color: ChatUi.chatBar,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: ChatUi.barHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                // ── Close — 22 icon in a 48 dp target ─────────────────
                _SelectionIconButton(
                  icon: Icons.close,
                  semanticsLabel: 'Close selection mode',
                  onTap: onClose,
                ),
                const SizedBox(width: 6),
                // ── Count — display 18 / 500, expanding to fill ──────
                Expanded(
                  child: Text(
                    '$selectedCount',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ChatUi.selectionCount,
                  ),
                ),
                const SizedBox(width: 6),
                // ── Bulk actions — 22 icons in 48 dp targets ──────────
                _SelectionIconButton(
                  icon: Icons.reply,
                  semanticsLabel: 'Reply',
                  onTap: hasSelection ? onReply : null,
                ),
                _SelectionIconButton(
                  icon: Icons.forward,
                  semanticsLabel: 'Forward',
                  onTap: hasSelection ? onForward : null,
                ),
                _SelectionIconButton(
                  icon: Icons.star_outline,
                  semanticsLabel: 'Star',
                  onTap: hasSelection ? onStar : null,
                ),
                _SelectionIconButton(
                  icon: Icons.delete_outline,
                  semanticsLabel: 'Delete',
                  onTap: hasSelection ? onDelete : null,
                ),
                _SelectionIconButton(
                  icon: Icons.more_vert,
                  semanticsLabel: 'More options',
                  onTap: hasSelection ? onMore : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectionIconButton extends StatelessWidget {
  const _SelectionIconButton({
    required this.icon,
    required this.semanticsLabel,
    this.onTap,
  });

  final IconData icon;
  final String semanticsLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      label: semanticsLabel,
      button: true,
      enabled: enabled,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: ChatUi.tapTarget,
          height: ChatUi.tapTarget,
          child: Center(
            child: Icon(
              icon,
              size: ChatUi.iconSelectionClose,
              color: enabled ? ChatUi.textPrimary : ChatUi.textMeta,
            ),
          ),
        ),
      ),
    );
  }
}

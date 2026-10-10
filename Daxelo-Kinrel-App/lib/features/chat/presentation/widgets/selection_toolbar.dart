// lib/features/chat/presentation/widgets/selection_toolbar.dart
//
// DAXELO KINREL — WhatsApp-style Selection Toolbar
//
// Replaces the normal chat header when selection mode is active. Shows:
//   • Close (✕) button — exits selection mode
//   • "N selected" count
//   • Primary actions: Reply, Star, Forward, Delete
//   • More (⋮) menu: Copy, Share, Info, Pin, Edit
//
// The toolbar is a PreferredSize widget (height 56) so it replaces
// the AppBar seamlessly. It uses the same dark surface gradient as
// the regular AppBar so the transition feels native.
//
// When multiple messages are selected, Reply is disabled (you can
// only reply to one message at a time). Delete is always enabled.
// Forward + Copy work on all selected messages.

import 'package:flutter/material.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';

/// Callback signatures for the selection toolbar actions.
typedef SelectionActionCallback = void Function(Set<String> selectedIds);

class SelectionToolbar extends StatelessWidget implements PreferredSizeWidget {
  const SelectionToolbar({
    super.key,
    required this.selectedCount,
    required this.onClose,
    required this.onReply,
    required this.onStar,
    required this.onForward,
    required this.onDelete,
    required this.onMore,
    this.canReply = true,
  });

  /// The number of currently-selected messages.
  final int selectedCount;

  /// Close (✕) button — exits selection mode.
  final VoidCallback onClose;

  /// Reply action (disabled when selectedCount > 1).
  final SelectionActionCallback onReply;

  /// Star/unstar action.
  final SelectionActionCallback onStar;

  /// Forward action.
  final SelectionActionCallback onForward;

  /// Delete action (opens the Delete for Me / Delete for Everyone dialog).
  final SelectionActionCallback onDelete;

  /// More (⋮) menu — opens a bottom sheet with secondary actions.
  final SelectionActionCallback onMore;

  /// Whether the Reply action is enabled (false when multiple messages
  /// are selected — you can only reply to one message at a time).
  final bool canReply;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return PreferredSize(
      preferredSize: preferredSize,
      child: Container(
        decoration: BoxDecoration(
          color: KinrelColors.darkSurface,
          border: Border(
            bottom: BorderSide(
              color: Colors.white.withValues(alpha: 0.06),
              width: 0.5,
            ),
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Row(
            children: [
              // ── Close button ──────────────────────────────────────
              IconButton(
                icon: const Icon(Icons.close_rounded,
                    color: KinrelColors.textWhite, size: 24),
                onPressed: onClose,
                tooltip: 'Cancel selection',
              ),
              // ── "N selected" count ────────────────────────────────
              Expanded(
                child: Text(
                  '$selectedCount selected',
                  style: const TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.textWhite,
                  ),
                ),
              ),
              // ── Primary actions ──────────────────────────────────
              // Reply (disabled when multiple messages are selected).
              IconButton(
                icon: Icon(
                  Icons.reply_rounded,
                  color: canReply ? KinrelColors.textWhite : KinrelColors.textDim,
                  size: 24,
                ),
                onPressed: canReply ? () => onReply({}) : null,
                tooltip: 'Reply',
              ),
              // Star
              IconButton(
                icon: const Icon(Icons.star_rounded,
                    color: KinrelColors.textWhite, size: 24),
                onPressed: () => onStar({}),
                tooltip: 'Star',
              ),
              // Forward
              IconButton(
                icon: const Icon(Icons.forward_rounded,
                    color: KinrelColors.textWhite, size: 24),
                onPressed: () => onForward({}),
                tooltip: 'Forward',
              ),
              // Delete
              IconButton(
                icon: Icon(Icons.delete_outline_rounded,
                    color: Colors.red.shade400, size: 24),
                onPressed: () => onDelete({}),
                tooltip: 'Delete',
              ),
              // More (⋮)
              IconButton(
                icon: const Icon(Icons.more_vert_rounded,
                    color: KinrelColors.textWhite, size: 24),
                onPressed: () => onMore({}),
                tooltip: 'More',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

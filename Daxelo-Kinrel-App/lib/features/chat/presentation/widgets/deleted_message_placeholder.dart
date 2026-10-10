// lib/features/chat/presentation/widgets/deleted_message_placeholder.dart
//
// DAXELO KINREL — Deleted Message Placeholder
//
// A compact, consistent-height placeholder rendered when a message has
// been deleted for everyone. Shows personalized wording:
//   • "You deleted this message." — when the current user is the author
//   • "[Name] deleted this message." — when another user is the author
//
// The placeholder has a FIXED height regardless of the participant's name
// length — long names are truncated to a single line. This prevents layout
// jumps when messages with different author names are deleted.
//
// The visual treatment is distinct from normal messages: muted text,
// a subtle deletion icon, and no bubble background — just a centered,
// compact row that reads as "this slot in the conversation was a
// message that is now gone."
//
// Used by: MessageBubble when message.isDeletedForEveryone == true.

import 'package:flutter/material.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';

/// Compact, consistent-height placeholder for deleted messages.
///
/// Parameters:
///   [isMe] — whether the current user is the original author
///   [senderName] — the original author's display name (used when !isMe)
///   [isRightAligned] — whether the placeholder should be right-aligned
///     (when the original message was sent by the current user)
class DeletedMessagePlaceholder extends StatelessWidget {
  const DeletedMessagePlaceholder({
    super.key,
    required this.isMe,
    this.senderName,
    this.isRightAligned = false,
  });

  final bool isMe;
  final String? senderName;
  final bool isRightAligned;

  @override
  Widget build(BuildContext context) {
    // Personalized wording: "You deleted this message." for the author,
    // "[Name] deleted this message." for others.
    final label = isMe
        ? 'You deleted this message.'
        : '${senderName ?? 'Someone'} deleted this message.';

    return Align(
      alignment:
          isRightAligned ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        // Consistent padding + margin — same height regardless of name.
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Subtle deletion icon — muted, smaller than bubble icons.
            Icon(
              Icons.block_rounded,
              size: 12,
              color: KinrelColors.textSilver.withValues(alpha: 0.4),
            ),
            const SizedBox(width: 6),
            // Single-line label with truncation — never wraps to 2 lines.
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: KinrelColors.textSilver.withValues(alpha: 0.6),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

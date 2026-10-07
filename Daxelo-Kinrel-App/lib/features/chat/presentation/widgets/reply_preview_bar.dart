// lib/features/chat/presentation/widgets/reply_preview_bar.dart
//
// DAXELO KINREL — Shared reply preview bar (group + DM)
//
// The bar that appears above the input when the user is composing a
// reply (swipe-to-reply or long-press → Reply). Shows an orange accent
// bar + the original sender's name + a one-line snippet, with an X to
// cancel the reply.
//
// EXTRACTED (moved, not rewritten) from chat_screen.dart's
// _buildReplyPreview so the DM screen renders the SAME bar with the
// same layout, spacing, typography, and colors. The group chat now
// delegates to this widget — its rendering is byte-for-byte identical
// to the previous inline version.
//
// Inputs:
//   - replyTo: the ChatMessage being replied to (the shared shape both
//     ChatState.replyToMessage and DirectChatState.replyToMessage
//     store — the DM adapter produces ChatMessages too, so both chat
//     types pass the exact same object type).
//   - onClose: clears the reply target (the screen wires this to
//     clearReplyTo on its provider — group: chatProvider,
//     DM: directChatProvider).

import 'package:flutter/material.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../providers/chat_provider.dart';

class ReplyPreviewBar extends StatelessWidget {
  const ReplyPreviewBar({
    super.key,
    required this.replyTo,
    required this.onClose,
  });

  /// The message being replied to.
  final ChatMessage replyTo;

  /// Clears the reply target (X button).
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF13141E),
        border: Border(
          top: BorderSide(color: Color(0xFF2A2A3D), width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Orange left bar
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: KinrelColors.orange,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  replyTo.senderName,
                  style: const TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.orange,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  replyTo.content,
                  style: const TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    color: KinrelColors.textSilver,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: KinrelColors.textDim),
            onPressed: onClose,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }
}

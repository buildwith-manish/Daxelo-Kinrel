// lib/features/chat/presentation/widgets/reply_preview_bar.dart
//
// DAXELO KINREL — Shared reply preview bar (group + DM)
//
// The bar that appears above the input when the user is composing a
// reply (swipe-to-reply or long-press → Reply).
//
// v143 / Signature §G: redesigned with a kinship band + the text
// "Replying to NAME" with the same colors as the in-bubble reply
// quote:
//   • Band: 3 dp wide, kinship color (own → orange; unresolved →
//     KinrelColors.nodeExtended; resolved → kinshipCategoryColor).
//   • Name: 11/500 in the readable kinship color variant (own →
//     orange; unresolved → orange; resolved → readableKinshipLabel).
//   • Snippet: 12/400/textSecondary, one line, ellipsis.
//   • "Replying to " prefix is in textMeta; NAME uses the same color
//     as the band's readable variant.
//   • Close (X) button stays.
//
// For DMs (familyId == null), there's no kinship color → the bar
// uses orange + the sender name (matching the in-bubble quote's
// "unresolved" treatment).
//
// EXTRACTED (moved, not rewritten) from chat_screen.dart's
// _buildReplyPreview so the DM screen renders the SAME bar with the
// same layout, spacing, typography, and colors. Now a ConsumerWidget
// so it can resolve the replied-to sender's relationship key +
// label from the family graph.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/kinship/kinship_edge_style.dart';
import '../../../family/data/relationship_label_provider.dart';
import '../../providers/chat_provider.dart';
import '../chat_ui_tokens.dart';
import 'chat_meta.dart' show kinshipCategoryColor;

class ReplyPreviewBar extends ConsumerWidget {
  const ReplyPreviewBar({
    super.key,
    required this.replyTo,
    required this.onClose,
    this.familyId,
    this.currentUserId,
  });

  /// The message being replied to.
  final ChatMessage replyTo;

  /// Clears the reply target (X button).
  final VoidCallback onClose;

  /// The family id (null for direct chats — no kinship color in DMs).
  final String? familyId;

  /// The current user's id (used to detect "own message" → orange
  /// band + "You" name). Null is treated as "not own".
  final String? currentUserId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool isOwn =
        currentUserId != null && replyTo.senderId == currentUserId;

    // Resolve the kinship color + relationship label for the replied-to
    // sender. Skipped for own messages (orange) and DMs (orange).
    Color bandColor = KinrelColors.orange;
    bool kinshipResolved = false;
    String? relationshipLabel;
    if (familyId != null && !isOwn) {
      final rawKey = ref.watch(relationshipKeyProvider(
        (familyId: familyId!, senderUserId: replyTo.senderId),
      ));
      if (rawKey != null) {
        final category = KinshipEdgeClassifier.classify(rawKey);
        final color = kinshipCategoryColor(category);
        if (color != null) {
          bandColor = color;
          kinshipResolved = true;
        }
      }
      if (!kinshipResolved) {
        bandColor = KinrelColors.nodeExtended;
      }
      relationshipLabel = ref.watch(relationshipLabelProvider(
        (familyId: familyId!, senderUserId: replyTo.senderId),
      ));
    }

    // Name + name color.
    final Color nameColor;
    final String nameText;
    if (isOwn) {
      nameColor = KinrelColors.orange;
      nameText = 'You';
    } else if (kinshipResolved && relationshipLabel != null) {
      nameColor = ChatUi.readableKinshipLabel(bandColor);
      nameText = '$relationshipLabel, ${replyTo.senderName}';
    } else {
      // Unresolved or DM — orange name, just the sender name.
      nameColor = KinrelColors.orange;
      nameText = replyTo.senderName;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: ChatUi.chatBar,
        border: Border(
          top: BorderSide(
            color: ChatUi.lineColor,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          // Kinship band (own → orange; unresolved → extended; resolved →
          // kinshipCategoryColor).
          Container(
            width: ChatUi.replyBandWidth,
            height: 36,
            decoration: BoxDecoration(
              color: bandColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // "Replying to NAME" — "Replying to " in textMeta,
                // NAME in the readable kinship color variant.
                RichText(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: 'Replying to ',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: ChatUi.textMeta,
                          letterSpacing: 0.2,
                        ),
                      ),
                      TextSpan(
                        text: nameText,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: nameColor,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                // Snippet (the replied-to message's content).
                Text(
                  replyTo.content,
                  style: ChatUi.replyQuoteText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Close (X).
          SizedBox(
            width: ChatUi.tapTarget,
            height: ChatUi.tapTarget,
            child: IconButton(
              icon: Icon(Icons.close,
                  size: 18, color: ChatUi.textMeta),
              onPressed: onClose,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                  minWidth: ChatUi.tapTarget, minHeight: ChatUi.tapTarget),
            ),
          ),
        ],
      ),
    );
  }
}

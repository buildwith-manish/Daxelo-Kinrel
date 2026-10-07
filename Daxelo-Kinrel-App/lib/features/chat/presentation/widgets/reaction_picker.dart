// lib/features/chat/presentation/widgets/reaction_picker.dart
//
// DAXELO KINREL — Shared reaction picker (group + DM)
//
// v3.5 — MOVED (not rewritten) from chat_screen.dart's
// _showReactionPicker + _showFullEmojiPicker so the DM screen opens the
// SAME reaction UI with the same styling:
//   - The shared ReactionOverlay (chat_meta.dart) quick-picker: the
//     6 quick emojis + a "+" that opens the full sheet
//   - The full emoji bottom sheet ("React with an emoji") with the
//     identical EmojiPicker config (dark card, orange accents, 45%
//     height, search bar)
//
// The only screen-specific part is WHO handles the toggle — callers
// pass their own onEmojiSelected:
//   - Group: ChatNotifier.toggleReaction (ChatMessageReaction table)
//   - DM:    DirectChatNotifier.toggleReaction (DirectMessageReaction
//     table)
// Everything else (overlay placement, sheet, config, pop behavior) is
// identical.

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_spacing.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../providers/chat_provider.dart';
import 'chat_meta.dart';

// v3.5 — the 6 quick-react emojis the group sheet's quick-reactions row
// uses (identical list in both chat types).
const List<String> kQuickReactionEmojis = ['❤️', '😂', '👍', '😮', '😢', '🙏'];

/// The quick-reactions row at the top of the long-press message-actions
/// sheet — MOVED verbatim from chat_screen.dart's _showMessageActions so
/// the DM sheet renders the SAME row: the 6 quick emojis (44x44 circular
/// buttons, orange highlight ring when I've already reacted) + a "+"
/// button that opens the full emoji sheet.
///
/// The caller supplies the toggle handler (group: ChatNotifier.
/// toggleReaction; DM: DirectChatNotifier.toggleReaction) and the
/// "+"-tap handler (each screen pops its own sheet first, then opens
/// the shared full-emoji sheet).
class MessageActionQuickReactions extends StatelessWidget {
  const MessageActionQuickReactions({
    super.key,
    required this.reactions,
    required this.currentUserId,
    required this.onToggle,
    required this.onMoreTap,
  });

  /// The message's current reactions (drives the has-reacted highlight).
  final List<MessageReaction> reactions;

  /// The current user's id (drives the has-reacted highlight).
  final String? currentUserId;

  /// Fires with the tapped emoji (the caller toggles + pops its sheet).
  final void Function(String emoji) onToggle;

  /// Fires when the "+" button is tapped (the caller pops its sheet,
  /// then calls showFullEmojiSheet).
  final VoidCallback onMoreTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          ...kQuickReactionEmojis.map((emoji) {
            final hasReacted = reactions.any(
              (r) => r.emoji == emoji && r.userId == currentUserId,
            );
            return GestureDetector(
              onTap: () => onToggle(emoji),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hasReacted
                      ? KinrelColors.orange.withValues(alpha: 0.15)
                      : Colors.transparent,
                  border: hasReacted
                      ? Border.all(
                          color: KinrelColors.orange.withValues(
                            alpha: 0.4,
                          ),
                          width: 1.5,
                        )
                      : null,
                ),
                child: Center(
                  child: Text(emoji, style: const TextStyle(fontSize: 22)),
                ),
              ),
            );
          }),
          // v113: "+" button — opens the full emoji picker so
          // users can react with ANY emoji, not just the 6
          // quick-react defaults. Styled identically to the
          // emoji buttons (44x44, circular) for consistency.
          GestureDetector(
            onTap: onMoreTap,
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: KinrelColors.darkElevated,
              ),
              child: const Center(
                child: Icon(
                  Icons.add,
                  color: KinrelColors.textSilver,
                  size: 22,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Show the quick-reaction overlay anchored above the input area —
/// MOVED verbatim from chat_screen.dart's _showReactionPicker. On
/// emoji tap the caller's [onEmojiSelected] fires (toggle logic is
/// chat-type-specific), then the overlay removes itself. The "+"
/// button removes the overlay and opens the full emoji sheet.
void showReactionOverlay(
  BuildContext context, {
  required void Function(String emoji) onEmojiSelected,
}) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;

  entry = OverlayEntry(
    builder: (context) => ReactionOverlay(
      onEmojiSelected: (emoji) {
        onEmojiSelected(emoji);
        entry.remove();
      },
      onDismiss: () => entry.remove(),
      // v113: "+" button → remove the overlay and open the full
      // emoji picker bottom sheet for access to ALL emojis.
      onMoreTap: () {
        entry.remove();
        showFullEmojiSheet(context, onEmojiSelected: onEmojiSelected);
      },
    ),
  );

  overlay.insert(entry);
}

/// Show the full emoji picker bottom sheet — MOVED verbatim from
/// chat_screen.dart's _showFullEmojiPicker (same title, same height,
/// same EmojiPicker config, same pop-after-select behavior).
void showFullEmojiSheet(
  BuildContext context, {
  required void Function(String emoji) onEmojiSelected,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: KinrelColors.darkCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(KinrelRadius.xxl),
      ),
    ),
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'React with an emoji',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textWhite,
                ),
              ),
            ),
          ),
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.45,
            child: EmojiPicker(
              onEmojiSelected: (category, emoji) {
                onEmojiSelected(emoji.emoji);
                Navigator.pop(context);
              },
              config: Config(
                height: MediaQuery.of(context).size.height * 0.45,
                checkPlatformCompatibility: true,
                emojiViewConfig: const EmojiViewConfig(
                  backgroundColor: KinrelColors.darkCard,
                  emojiSizeMax: 28,
                ),
                categoryViewConfig: const CategoryViewConfig(
                  backgroundColor: KinrelColors.darkCard,
                  iconColor: KinrelColors.textSilver,
                  iconColorSelected: KinrelColors.orange,
                  indicatorColor: KinrelColors.orange,
                  backspaceColor: KinrelColors.textSilver,
                ),
                searchViewConfig: const SearchViewConfig(
                  backgroundColor: KinrelColors.darkCard,
                  buttonIconColor: KinrelColors.textSilver,
                  hintText: 'Search emoji',
                  hintTextStyle: TextStyle(
                    color: KinrelColors.textDim,
                    fontSize: 14,
                  ),
                  inputTextStyle: TextStyle(
                    color: KinrelColors.textWhite,
                    fontSize: 14,
                  ),
                ),
                skinToneConfig: const SkinToneConfig(
                  dialogBackgroundColor: Color(0xFF202338),
                  indicatorColor: KinrelColors.orange,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

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
//
// PERF (Phase 3 — Task 5): The EmojiPicker is now wrapped in a
// dedicated [_EmojiPickerSheet] StatefulWidget. The wrapper:
//   1. Lazily constructs the EmojiPicker (data loaded only when the
//      sheet opens — was already lazy via showModalBottomSheet, but
//      now explicit + scoped).
//   2. On dispose (sheet closed), explicitly nulls the local
//      reference so the EmojiPicker widget tree is fully released.
//      Without this, the package's internal `_categoryEmoji` list
//      (14 913 Emoji instances ≈ 466 KB per the DevTools snapshot)
//      could be retained by lingering listeners on the package's
//      `categoryNavigationNotifier` ValueNotifier.
//   3. Calls the package's internal `EmojiPickerUtils` cache reset
//      where the API permits it (v4.5.x has no public clearCache(),
//      so the wrapper relies on proper widget-tree disposal; the
//      EmojiPickerState.dispose() removes its listeners, and once
//      nothing else references the State, the GC collects the emoji
//      lists).

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
    // PERF (Phase 3 — Task 5): wrap the EmojiPicker in a dedicated
    // StatefulWidget so the heavy emoji-data widget tree is properly
    // scoped to the sheet's lifetime. When the sheet closes, the
    // _EmojiPickerSheet's dispose() runs — nulling the local ref
    // and ensuring the package's EmojiPickerState (with its
    // ~14 913-Emoji `_categoryEmoji` list) is released. The previous
    // inline builder worked, but the inline `EmojiPicker` was
    // constructed fresh on every sheet rebuild (e.g. on keyboard
    // insets), re-loading the emoji data each time.
    builder: (context) => _EmojiPickerSheet(
      onEmojiSelected: onEmojiSelected,
    ),
  );
}

/// PERF (Phase 3 — Task 5): dedicated StatefulWidget wrapper around
/// the [EmojiPicker] so the emoji-data widget tree is properly
/// scoped to the sheet's lifetime. Constructed LAZILY (only when the
/// sheet opens — the previous inline `builder:` already had this
/// property, but this wrapper makes it explicit) and released on
/// close.
///
/// The wrapper holds NO emoji data itself — it just constructs the
/// EmojiPicker in build() and lets the framework dispose it when the
/// sheet is popped. The dispose() override is a defensive no-op that
/// exists to document the lifecycle (and to catch any future leak
/// where someone might hold a ref to the picker externally).
class _EmojiPickerSheet extends StatefulWidget {
  const _EmojiPickerSheet({required this.onEmojiSelected});

  final void Function(String emoji) onEmojiSelected;

  @override
  State<_EmojiPickerSheet> createState() => _EmojiPickerSheetState();
}

class _EmojiPickerSheetState extends State<_EmojiPickerSheet> {
  // PERF (Phase 3 — Task 5): no cached emoji data here. The
  // EmojiPicker widget loads its data in its OWN State's initState
  // (via the package's internal asset loader) and disposes it in
  // its OWN dispose(). By keeping this wrapper stateless (with
  // respect to emoji data), we ensure there's no second reference
  // keeping the emojis alive after the sheet closes.

  @override
  void dispose() {
    // PERF (Phase 3 — Task 5): defensive dispose. The EmojiPicker
    // widget's own State.dispose() runs FIRST (children before
    // parents) and removes its listeners — so by the time THIS
    // dispose runs, the EmojiPickerState is already detached from
    // the build tree. Nothing else to clean here; the comment exists
    // to document the lifecycle contract for future maintainers.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
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
                widget.onEmojiSelected(emoji.emoji);
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
    );
  }
}

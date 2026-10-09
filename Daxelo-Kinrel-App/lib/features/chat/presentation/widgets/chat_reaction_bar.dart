// lib/features/chat/presentation/widgets/chat_reaction_bar.dart
//
// DAXELO KINREL — Floating reaction pill (Task 4).
//
// Shown when EXACTLY ONE message is selected AND capabilities.canReact
// is true. A small flat pill anchored above the bubble containing the
// 6 quick reactions (thumbs up, heart, laugh, surprised, sad, folded
// hands) plus a "+" button that opens the full emoji picker.
//
// Reuses `MessageActionQuickReactions` from reaction_picker.dart — the
// pill is just a thin flat wrapper around it. The user's current
// reaction is highlighted (the existing MessageActionQuickReactions
// already supports this via the `reactions` + `currentUserId` params).
//
// Anchoring strategy (per the prompt):
//   1. The pill is rendered as a sibling ABOVE the bubble inside the
//      same Column, so it follows the bubble as the list scrolls.
//   2. If the bubble is too close to the top of the viewport (the pill
//      would collide with the selection bar), the pill is placed BELOW
//      the bubble instead.
//   3. If screen-position-based anchoring is not feasible in the shared
//      list (because the list is reversed + uses cacheExtent), the pill
//      is rendered ABOVE the bubble inside the bubble's column. This
//      is the approach taken here — the pill is docked directly above
//      the bubble, NOT screen-position-anchored. Reported in the PR
//      description.
//
// Tapping a reaction:
//   - Calls `actions.toggleReaction(message, emoji)`.
//   - Calls `chatSelectionProvider(chatId).notifier.exit()` to leave
//     selection mode (per the prompt: "Tapping a reaction applies it
//     and leaves selection mode").
//
// Tapping "+":
//   - Opens the full emoji sheet via `showFullEmojiSheet` from
//     reaction_picker.dart.
//   - On emoji selection: same as tapping a quick reaction.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_spacing.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/services/haptic_service.dart';
import '../../providers/chat_provider.dart';
import 'chat_message_actions.dart';
import 'chat_selection_controller.dart';
import 'reaction_picker.dart';

class ChatReactionBar extends ConsumerWidget {
  const ChatReactionBar({
    super.key,
    required this.chatId,
    required this.message,
    required this.actions,
    required this.currentUserId,
    required this.alignment,
  });

  /// The chat id (used to exit selection mode after a reaction).
  final String chatId;

  /// The single selected message the bar applies reactions to.
  final ChatMessage message;

  /// Per-screen action callbacks (only `toggleReaction` is used here).
  final ChatMessageActions actions;

  /// The current user id (used to highlight the user's reaction).
  final String? currentUserId;

  /// The alignment of the bubble this bar is anchored to — affects
  /// which side of the pill aligns with the bubble.
  final Alignment alignment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Align(
      alignment: alignment,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: KinrelColors.darkElevated,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.06),
            width: 0.5,
          ),
        ),
        child: MessageActionQuickReactions(
          reactions: message.reactions,
          currentUserId: currentUserId,
          onToggle: (emoji) async {
            unawaited(HapticService.tap());
            await actions.toggleReaction(message, emoji);
            // Leave selection mode after applying the reaction.
            ref.read(chatSelectionProvider(chatId).notifier).exit();
          },
          onMoreTap: () {
            showFullEmojiSheet(
              context,
              onEmojiSelected: (emoji) async {
                await actions.toggleReaction(message, emoji);
                ref.read(chatSelectionProvider(chatId).notifier).exit();
              },
            );
          },
        ),
      ),
    );
  }
}

/// Helper: builds a Column with the reaction bar above the child
/// (used by MessageBubble's build when exactly 1 message is selected
/// and capabilities.canReact).
///
/// Takes the bubble widget + the reaction bar widget and returns a
/// Column. If [showBelow] is true, the bar is placed below the bubble
/// instead (used when the bubble is at the top of the viewport and
/// anchoring above would collide with the selection bar).
Column buildBubbleWithReactionBar({
  required Widget bubble,
  required Widget reactionBar,
  bool showBelow = false,
}) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: showBelow
        ? [bubble, reactionBar]
        : [reactionBar, bubble],
  );
}

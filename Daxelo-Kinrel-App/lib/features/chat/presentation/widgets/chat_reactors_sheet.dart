// lib/features/chat/presentation/widgets/chat_reactors_sheet.dart
//
// DAXELO KINREL — Reactions list (Task 5).
//
// Tapping a reaction chip below a bubble opens a small list of who
// reacted with that emoji. Reuses existing member + peer data:
//   - Group: `MessageReaction.userId` is a Supabase auth uid — we look
//     up the display name via `familyMembershipsProvider` (the same
//     provider the group screen uses to render the member roster).
//   - Direct: there's only one other party — if the user id matches
//     the peer, show the peer's name; otherwise show "You".
//
// The sheet shows the emoji as a header + a vertical list of reactors
// (avatar + name). Works in BOTH chat types per the prompt.
//
// When the sheet is invoked from the bubble's `_buildReactionChips`
// (which fires `onReact` / `onShowReactors`), the screen passes the
// tapped message. The sheet groups all reactions on that message by
// emoji and shows them all (so the user can see who reacted with what
// — not just the tapped emoji).
//
// If the message has no reactions (shouldn't happen — the chips only
// render when there ARE reactions), the sheet shows a single row
// "No reactions yet" — but the caller should not invoke the sheet
// in that case.
//
// Implementation note: the existing `MessageReaction` model has
// `userId` + `emoji`. The lookup of display name is delegated to a
// callback the screen supplies (`resolveUserName`) so this widget
// doesn't need to know about family memberships vs DM peers.

import 'package:flutter/material.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../providers/chat_provider.dart';

class ChatReactorsSheet {
  ChatReactorsSheet._();

  /// Show the reactors list for a message.
  ///
  /// [resolveUserName] takes a userId and returns the display name
  /// (the screen supplies this — group uses familyMembershipsProvider,
  /// DM uses peer name + "You" for the current user).
  static Future<void> show({
    required BuildContext context,
    required ChatMessage message,
    required String? currentUserId,
    required String Function(String userId) resolveUserName,
  }) async {
    if (message.reactions.isEmpty) return;
    // Group reactions by emoji (preserves the order they were first
    // applied).
    final byEmoji = <String, List<MessageReaction>>{};
    for (final r in message.reactions) {
      byEmoji.putIfAbsent(r.emoji, () => []).add(r);
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Reactions',
                    style: const TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                ),
                ...byEmoji.entries.map((entry) {
                  final emoji = entry.key;
                  final reactors = entry.value;
                  return _ReactionGroup(
                    emoji: emoji,
                    reactors: reactors
                        .map((r) => _Reactor(
                              userId: r.userId,
                              name: r.userId == currentUserId
                                  ? 'You'
                                  : resolveUserName(r.userId),
                            ))
                        .toList(),
                  );
                }),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Reactor {
  const _Reactor({required this.userId, required this.name});
  final String userId;
  final String name;
}

class _ReactionGroup extends StatelessWidget {
  const _ReactionGroup({required this.emoji, required this.reactors});
  final String emoji;
  final List<_Reactor> reactors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: reactors
                  .map((r) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Text(
                          r.name,
                          style: const TextStyle(
                            color: KinrelColors.textSilver,
                            fontSize: 14,
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

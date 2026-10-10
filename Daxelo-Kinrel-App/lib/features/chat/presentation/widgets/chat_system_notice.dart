// lib/features/chat/presentation/widgets/chat_system_notice.dart
//
// DAXELO KINREL — Chat System Notice (join notices, system messages)
//
// A centered, muted pill rendered for ChatMessage rows with
// messageType=system. Replaces the old behavior where system rows
// (e.g. "🎉 Manish joined the family.") rendered as a normal text
// bubble from the person who joined.
//
// Design:
//   • Centered pill with a sparkle icon + the text
//   • Leading emoji (e.g. 🎉) is stripped from the content
//   • No sender label, no avatar, no bubble, no rail, no ticks
//   • No reactions, no reply, no swipe, not selectable
//   • Breaks message clustering (next message starts a new cluster)
//   • Optional "View in tree" action: opens the family graph focused
//     on the member who joined (the message senderId). Only shown in
//     group chats (familyId != null); DMs pass no callback.
//
// Accessibility:
//   • Tap target for the View-in-tree action is at least 48 logical
//     pixels tall (the whole notice column is tappable).
//   • Semantics labels are always present (never color-only).
//   • Text scales to 1.3 without overflow (maxLines + ellipsis).
//
// Used by: ChatMessageList when message.messageType == MessageType.system.

import 'package:flutter/material.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';

class ChatSystemNotice extends StatelessWidget {
  const ChatSystemNotice({super.key, required this.content, this.onViewInTree});

  /// The raw content from the ChatMessage row (may include a leading
  /// emoji like 🎉 that gets stripped before rendering).
  final String content;

  /// Optional: called when the user taps the notice or its "View in
  /// tree" affordance. The list wires this to open the family graph
  /// focused on the member who joined (message.senderId). Null = no
  /// link rendered (e.g. direct chats / no graph available).
  final VoidCallback? onViewInTree;

  /// Strip the leading emoji (🎉 + space, 🎊 + space, etc.) from
  /// the content. The DB inserts "🎉 Name joined the family." but the
  /// notice should show just "Name joined the family." with the
  /// sparkle icon providing the visual cue.
  String get _cleanContent {
    var text = content.trim();
    if (text.isNotEmpty) {
      // Remove a leading emoji + optional space. Common emojis used in
      // system messages: 🎉 (U+1F389), 🎊 (U+1F38A), 👋 (U+1F44B).
      final emojiPattern = RegExp(
          r'^[\u{1F300}-\u{1F9FF}\u{2600}-\u{27BF}]\s?',
          unicode: true);
      text = text.replaceFirst(emojiPattern, '');
    }
    return text.trim();
  }

  @override
  Widget build(BuildContext context) {
    final label = _cleanContent;
    if (label.isEmpty) return const SizedBox.shrink();

    final hasAction = onViewInTree != null;

    return Semantics(
      label: 'Family notice: $label'
          '${hasAction ? '. Opens the family tree.' : ''}',
      button: hasAction,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: InkWell(
            onTap: onViewInTree,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── The notice pill (muted, non-bubbled) ────────────
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: KinrelColors.darkSurface
                          .withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.07),
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          size: 12,
                          color: KinrelColors.textSilver
                              .withValues(alpha: 0.45),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 12,
                              color: KinrelColors.textSilver
                                  .withValues(alpha: 0.65),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ── "View in tree" affordance (group chats only) ────
                  // The tappable area (via the surrounding InkWell)
                  // spans the pill + this row, well above 48 logical px.
                  if (hasAction) ...[
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 40,
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.account_tree_outlined,
                              size: 13,
                              color: KinrelColors.orange
                                  .withValues(alpha: 0.9),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'View in tree',
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: KinrelColors.orange
                                    .withValues(alpha: 0.9),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

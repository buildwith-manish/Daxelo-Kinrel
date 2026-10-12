// lib/features/chat/presentation/widgets/chat_system_notice.dart
//
// DAXELO KINREL — Chat System Notice (join notices, system messages)
//
// D9: A centered pill rendered for ChatMessage rows with
// messageType=system.
//   • Centered pill, background chatCard, padding 4 vertical / 12
//     horizontal, radius full
//   • Row with 6 gap: sparkle icon 14 in orange, the notice text 12
//     textSecondary, then a 4 margin and the "View in tree" link in
//     orange 12 with the tree icon 13 (only when a navigation target
//     exists)
//   • Leading emoji (e.g. 🎉) is stripped from the content
//   • No sender label, no avatar, no bubble, no band, no time
//   • No reactions, no reply, no swipe, not selectable
//   • Breaks message clustering (next message starts a new cluster)
//
// Accessibility:
//   • Tap target for the View-in-tree action is at least 48 logical
//     pixels tall (the whole notice pill is tappable).
//   • Semantics labels are always present (never color-only).
//   • Text scales without overflow (maxLines + ellipsis).
//
// Used by: ChatMessageList when message.messageType == MessageType.system.

import 'package:flutter/material.dart';

import '../../../../core/constants/brand_spacing.dart';
import '../chat_ui_tokens.dart';

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
        child: InkWell(
          onTap: onViewInTree,
          borderRadius: BorderRadius.circular(KinrelRadius.xxl),
          child: ConstrainedBox(
            // ≥48 logical px tap target for the whole pill.
            constraints: const BoxConstraints(minHeight: 48),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: ChatUi.chatCard,
                  borderRadius: BorderRadius.circular(KinrelRadius.full),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.auto_awesome,
                      size: ChatUi.iconSparkle,
                      color: ChatUi.accent,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: ChatUi.pillText,
                      ),
                    ),
                    if (hasAction) ...[
                      const SizedBox(width: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'View in tree',
                            style: ChatUi.pillText.copyWith(
                              color: ChatUi.accent,
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Icon(
                            Icons.account_tree,
                            size: ChatUi.iconFamilyTree,
                            color: ChatUi.accent,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

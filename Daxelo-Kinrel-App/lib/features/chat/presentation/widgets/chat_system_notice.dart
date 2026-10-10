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
//
// Used by: ChatMessageList when message.messageType == MessageType.system.

import 'package:flutter/material.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';

class ChatSystemNotice extends StatelessWidget {
  const ChatSystemNotice({super.key, required this.content});

  /// The raw content from the ChatMessage row (may include a leading
  /// emoji like 🎉 that gets stripped before rendering).
  final String content;

  /// Strip the leading emoji (🎉 + space, 🎊 + space, etc.) from
  /// the content. The DB inserts "🎉 Name joined the family." but the
  /// notice should show just "Name joined the family." with the
  /// sparkle icon providing the visual cue.
  String get _cleanContent {
    var text = content.trim();
    // Remove leading emoji + optional space. Common emojis used in
    // system messages: 🎉 (party popper), 🎊 (confusion ball),
    // 👋 (waving hand), 🎊 (confetti ball).
    if (text.isNotEmpty) {
      // Check for common emoji prefixes (2-char code points).
      // 🎉 = U+1F389, 🎊 = U+1F38A, 👋 = U+1F44B
      // Each is followed by an optional space.
      final emojiPattern = RegExp(r'^[\u{1F300}-\u{1F9FF}\u{2600}-\u{27BF}]\s?', unicode: true);
      text = text.replaceFirst(emojiPattern, '');
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final label = _cleanContent;
    if (label.isEmpty) return const SizedBox.shrink();

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Subtle sparkle icon — muted, small.
            Icon(
              Icons.auto_awesome,
              size: 12,
              color: KinrelColors.textSilver.withValues(alpha: 0.4),
            ),
            const SizedBox(width: 6),
            // Single-line label with truncation.
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  color: KinrelColors.textSilver.withValues(alpha: 0.6),
                ),
              ),
            ),
            const SizedBox(width: 6),
            // Mirror the icon on the right for visual balance.
            Icon(
              Icons.auto_awesome,
              size: 12,
              color: KinrelColors.textSilver.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }
}

// lib/features/chat/data/models/message_reaction.dart
//
// Extracted from lib/features/chat/providers/chat_provider.dart (Phase 0
// refactor — zero behavior change). Re-exported by chat_provider.dart so
// no existing import changes.

/// A single emoji reaction on a message.
class MessageReaction {
  const MessageReaction({required this.emoji, required this.userId});

  factory MessageReaction.fromJson(Map<String, dynamic> json) {
    return MessageReaction(
      emoji: json['emoji'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
    );
  }

  /// The emoji character (e.g., '❤️', '😂', '👍').
  final String emoji;

  /// ID of the user who reacted.
  final String userId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MessageReaction &&
          emoji == other.emoji &&
          userId == other.userId;

  @override
  int get hashCode => emoji.hashCode ^ userId.hashCode;

  Map<String, dynamic> toJson() => {'emoji': emoji, 'userId': userId};
}

// lib/features/chat/data/models/mention_ref.dart
//
// Extracted from lib/features/chat/providers/chat_provider.dart (Phase 0
// refactor — zero behavior change). Re-exported by chat_provider.dart so
// no existing import changes.

/// Phase 22 / Task 3 — A single @mention reference on a chat message.
///
/// `start` and `end` are character offsets into the message `content`
/// (UTF-16 codeunit offsets, matching Dart's String indexing) marking
/// the `@Name` span. The renderer uses these to split the content into
/// [before, @Name, after] segments and style the middle one as a
/// highlighted chip.
///
/// Modeled on MessageReaction: a value type with equality based on
/// (userId, start, end), JSON serialization, and a `fromJson` factory.
class MentionRef {
  const MentionRef({
    required this.userId,
    required this.name,
    required this.start,
    required this.end,
  });

  factory MentionRef.fromJson(Map<String, dynamic> json) {
    return MentionRef(
      userId: json['userId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      start: (json['start'] as num?)?.toInt() ?? 0,
      end: (json['end'] as num?)?.toInt() ?? 0,
    );
  }

  /// The mentioned user's UUID (matches `auth.uid()` for the recipient).
  final String userId;

  /// The mentioned user's display name at mention time. Stored so the
  /// chip keeps rendering even if the user later renames themselves.
  final String name;

  /// Character offset where the `@Name` span starts in `content`.
  final int start;

  /// Character offset where the `@Name` span ends in `content`
  /// (exclusive — `content.substring(start, end)` yields the `@Name`).
  final int end;

  /// True if this mention points at the current user.
  bool isFor(String currentUserId) => userId == currentUserId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MentionRef &&
          userId == other.userId &&
          start == other.start &&
          end == other.end;

  @override
  int get hashCode => userId.hashCode ^ start.hashCode ^ end.hashCode;

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'name': name,
        'start': start,
        'end': end,
      };
}

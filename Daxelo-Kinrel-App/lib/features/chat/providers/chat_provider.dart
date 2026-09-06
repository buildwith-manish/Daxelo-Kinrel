// lib/features/chat/providers/chat_provider.dart
//
// DAXELO KINREL — Family Chat State Management (Supabase Realtime)
//
// Manages family group chat state using Riverpod StateNotifierProvider.
// Backed by Supabase tables:
//   - ChatMessage          (the messages themselves)
//   - ChatMessageReaction  (per-user emoji reactions)
//   - ChatReadReceipt      (per-user read state)
//
// Realtime subscriptions fire on INSERT/UPDATE/DELETE for the family's
// chat messages + reactions + read receipts, so messages appear
// instantly for both sender and receiver without requiring refresh.
//
// Features:
//   - Real-time messaging via Supabase Realtime (Postgres Changes)
//   - Persistent storage in Supabase (messages survive app restart)
//   - Read receipts (double tick, orange for read)
//   - Reply to specific messages
//   - React to messages with emoji
//   - Echo de-dup (sender doesn't double-render their own message)
//   - Automatic reconnection (Supabase Realtime auto-reconnects)
//   - Loading and error states
//   - Message ordering by createdAt ASC (display reversed in UI)
//   - Network interruption handling (optimistic UI + reconcile on reconnect)

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/family/family_provider.dart';
import '../../games/shared/models/game_invite.dart';
import '../../presence/last_seen_provider.dart';

// ═══════════════════════════════════════════════════════════════════════
// Models
// ═══════════════════════════════════════════════════════════════════════

/// Message type — drives the bubble content and layout.
enum MessageType { text, photo, voiceNote, familyEvent, sticker, gameInvite, poll, gif, document, location }

/// A single emoji reaction on a message.
class MessageReaction {
  const MessageReaction({required this.emoji, required this.userId});

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

  factory MessageReaction.fromJson(Map<String, dynamic> json) {
    return MessageReaction(
      emoji: json['emoji'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
    );
  }
}

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

  factory MentionRef.fromJson(Map<String, dynamic> json) {
    return MentionRef(
      userId: json['userId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      start: (json['start'] as num?)?.toInt() ?? 0,
      end: (json['end'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A single chat message in the family group.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.messageType,
    required this.timestamp,
    this.isRead = false,
    this.reactions = const [],
    this.replyToId,
    this.replyToContent,
    this.replyToSenderName,
    this.isOnline = false,
    this.senderInitials,
    this.durationSeconds, // for voice notes
    this.eventTitle, // for family event sharing
    this.eventDate, // for family event sharing
    this.mediaUrl, // v91: for photo/voice attachments
    // Phase 13 enhancement fields
    this.isStarred = false,
    this.isPinned = false,
    this.isEdited = false,
    this.isDeletedForEveryone = false,
    this.messageStatus = 'sent',
    this.messageSubType,
    this.forwardedFrom,
    this.deletedForMe = const [],
    this.groupId, // v137: for group-scoped messages (null = family-wide chat)
    // Game-invite card fields (messageType == gameInvite)
    this.gameType, // route segment, e.g. 'sos' → '/family/<id>/sos/lobby'
    this.gameId, // id of the <game>_games row the invite points at
    this.roomCode, // 6-char display room code
    this.gameMaxPlayers,
    this.gameCurrentPlayers,
    this.gameInviteStatus, // 'pending' | 'accepted' | 'expired' | 'cancelled'
    // Phase 22 / Task 3 — @mention references. Denormalized from the
    // ChatMention table so the bubble renderer can highlight @Name spans
    // without an extra round-trip.
    this.mentions = const [],
    // Phase 22 / Task 5 — poll fields (messageType == poll).
    this.pollQuestion,
    this.pollOptions = const [],
    this.pollVoteCounts = const [],
    this.pollVoterIds = const [],
    this.pollCreatedAt,
  });

  /// URL of the attached media (photo or voice note) in Supabase storage.
  final String? mediaUrl;

  /// Unique message identifier.
  final String id;

  /// Sender's user ID.
  final String senderId;

  /// Sender's display name.
  final String senderName;

  /// Message text content (or caption for media).
  final String content;

  /// Type of message.
  final MessageType messageType;

  /// When the message was sent.
  final DateTime timestamp;

  /// Whether the message has been read by the current user.
  final bool isRead;

  /// Emoji reactions on this message.
  final List<MessageReaction> reactions;

  /// ID of the message this is replying to (null if not a reply).
  final String? replyToId;

  /// Snippet of the message being replied to.
  final String? replyToContent;

  /// Sender name of the message being replied to.
  final String? replyToSenderName;

  /// Whether the sender is currently online.
  final bool isOnline;

  /// Sender's initials for avatar.
  final String? senderInitials;

  /// Duration in seconds (for voice notes).
  final int? durationSeconds;

  /// Event title (for family event sharing).
  final String? eventTitle;

  /// Event date string (for family event sharing).
  final String? eventDate;

  /// Phase 13: Whether the message is starred (bookmarked) by current user.
  final bool isStarred;

  /// Phase 13: Whether the message is pinned by an admin/creator.
  final bool isPinned;

  /// Phase 13: Whether the message was edited after sending.
  final bool isEdited;

  /// Phase 13: Whether the message was deleted for everyone (sender or admin).
  final bool isDeletedForEveryone;

  /// Phase 13: Message delivery status: 'sent' | 'delivered' | 'read'.
  final String messageStatus;

  /// Phase 13: Message subtype: 'text' | 'image' | 'video' | 'audio' |
  /// 'voice' | 'document' | 'sticker' | 'gif' | 'contact' | 'location' | 'system'.
  final String? messageSubType;

  /// Phase 13: Original sender name if message was forwarded.
  final String? forwardedFrom;

  /// Phase 13: List of user IDs who deleted this message for themselves only.
  final List<dynamic> deletedForMe;

  /// v137: Group ID if this message belongs to a sub-group chat.
  /// Null means it's a family-wide chat message.
  final String? groupId;

  /// Game-invite card: the game's route segment (e.g. 'sos'). Used both for
  /// display and to build the lobby join route.
  final String? gameType;

  /// Game-invite card: id of the game room row (`<game>_games`.id).
  final String? gameId;

  /// Game-invite card: the 6-char display room code.
  final String? roomCode;

  /// Game-invite card: maximum players for the room.
  final int? gameMaxPlayers;

  /// Game-invite card: current players in the room. Kept in sync with the
  /// live game state by syncGameInviteChatCards() so the card shows
  /// "2/4 players" / flips to "Full" without reopening the thread.
  final int? gameCurrentPlayers;

  /// Game-invite card lifecycle: 'pending' (joinable) | 'accepted' (started)
  /// | 'expired' | 'cancelled' (ended). Null is treated as 'pending'.
  final String? gameInviteStatus;

  /// Phase 22 / Task 3 — @mention refs on this message. Each contains
  /// the userId, display name, and the [start, end) character offsets
  /// into `content` where the `@Name` span lives. Used by the bubble
  /// renderer to highlight mentions and by the notifications UI to
  /// decide whether to show a 'you were mentioned' badge.
  final List<MentionRef> mentions;

  /// Convenience: does this message mention the current user?
  bool mentionsUser(String currentUserId) =>
      mentions.any((m) => m.userId == currentUserId);

  // ── Phase 22 / Task 5 — Poll fields (messageType == poll) ──

  /// The poll question (also mirrored in `content` so the inbox
  /// preview shows it).
  final String? pollQuestion;

  /// Poll options — array of strings, indexed 0..N-1. The voter's
  /// `optionIndex` corresponds to the index in this array.
  final List<String> pollOptions;

  /// Live vote counts — array of ints, indexed the same as [pollOptions].
  /// Updated by fn_vote_poll via a realtime UPDATE on the ChatMessage row.
  final List<int> pollVoteCounts;

  /// Voter refs — array of {userId, optionIndex} objects. Used by the
  /// client to determine the "you voted" state (find my userId in the
  /// array → that's the option I voted for). Stored on the row so the
  /// client doesn't need a separate query per poll.
  final List<Map<String, dynamic>> pollVoterIds;

  /// When the poll was posted (for the "Xh ago" label).
  final DateTime? pollCreatedAt;

  /// Convenience: which option did the current user vote for?
  /// Returns the option index (0-based) or null if they haven't voted.
  int? votedOptionIndex(String currentUserId) {
    for (final v in pollVoterIds) {
      if (v['userId'] == currentUserId) {
        return (v['optionIndex'] as num?)?.toInt();
      }
    }
    return null;
  }

  /// Convenience: total votes across all options.
  int get pollTotalVotes =>
      pollVoteCounts.fold(0, (sum, c) => sum + c);

  /// Game-invite card: whether the room is full.
  bool get isGameFull =>
      (gameCurrentPlayers ?? 0) >= (gameMaxPlayers ?? 1) &&
      messageType == MessageType.gameInvite;

  /// Game-invite card: whether the invite is no longer joinable because its
  /// lifecycle ended (started / expired / cancelled) — as opposed to merely
  /// being full.
  bool get isGameInviteClosed =>
      messageType == MessageType.gameInvite &&
      gameInviteStatus != null &&
      gameInviteStatus != 'pending';

  /// Convenience: grouped reactions (emoji → count).
  Map<String, int> get groupedReactions {
    final map = <String, int>{};
    for (final r in reactions) {
      map[r.emoji] = (map[r.emoji] ?? 0) + 1;
    }
    return map;
  }

  /// Convenience: whether this message is hidden for the current user
  /// (either soft-deleted-for-me or deleted-for-everyone).
  bool isHiddenFor(String userId) {
    if (isDeletedForEveryone) return true;
    if (deletedForMe.any((u) => u == userId)) return true;
    return false;
  }

  /// Convenience: formatted time string (e.g., "10:30 AM").
  String get formattedTime {
    final hour = timestamp.hour;
    final minute = timestamp.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$displayHour:$minute $period';
  }

  ChatMessage copyWith({
    bool? isRead,
    List<MessageReaction>? reactions,
    String? replyToId,
    String? replyToContent,
    String? replyToSenderName,
    bool? isOnline,
    String? mediaUrl,
    bool? isStarred,
    bool? isPinned,
    bool? isEdited,
    bool? isDeletedForEveryone,
    String? messageStatus,
    String? content,
    List<dynamic>? deletedForMe,
    String? gameType,
    String? gameId,
    String? roomCode,
    int? gameMaxPlayers,
    int? gameCurrentPlayers,
    String? gameInviteStatus,
    List<MentionRef>? mentions,
    String? pollQuestion,
    List<String>? pollOptions,
    List<int>? pollVoteCounts,
    List<Map<String, dynamic>>? pollVoterIds,
    DateTime? pollCreatedAt,
  }) {
    return ChatMessage(
      id: id,
      senderId: senderId,
      senderName: senderName,
      content: content ?? this.content,
      messageType: messageType,
      timestamp: timestamp,
      isRead: isRead ?? this.isRead,
      reactions: reactions ?? this.reactions,
      replyToId: replyToId ?? this.replyToId,
      replyToContent: replyToContent ?? this.replyToContent,
      replyToSenderName: replyToSenderName ?? this.replyToSenderName,
      isOnline: isOnline ?? this.isOnline,
      senderInitials: senderInitials,
      durationSeconds: durationSeconds,
      eventTitle: eventTitle,
      eventDate: eventDate,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      isStarred: isStarred ?? this.isStarred,
      isPinned: isPinned ?? this.isPinned,
      isEdited: isEdited ?? this.isEdited,
      isDeletedForEveryone: isDeletedForEveryone ?? this.isDeletedForEveryone,
      messageStatus: messageStatus ?? this.messageStatus,
      messageSubType: messageSubType,
      forwardedFrom: forwardedFrom,
      deletedForMe: deletedForMe ?? this.deletedForMe,
      gameType: gameType ?? this.gameType,
      gameId: gameId ?? this.gameId,
      roomCode: roomCode ?? this.roomCode,
      gameMaxPlayers: gameMaxPlayers ?? this.gameMaxPlayers,
      gameCurrentPlayers: gameCurrentPlayers ?? this.gameCurrentPlayers,
      gameInviteStatus: gameInviteStatus ?? this.gameInviteStatus,
      mentions: mentions ?? this.mentions,
      pollQuestion: pollQuestion ?? this.pollQuestion,
      pollOptions: pollOptions ?? this.pollOptions,
      pollVoteCounts: pollVoteCounts ?? this.pollVoteCounts,
      pollVoterIds: pollVoterIds ?? this.pollVoterIds,
      pollCreatedAt: pollCreatedAt ?? this.pollCreatedAt,
    );
  }

  /// Parse a ChatMessage from a Supabase row.
  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String? ?? '',
      senderId: json['senderId'] as String? ?? '',
      senderName: json['senderName'] as String? ?? 'Unknown',
      content: json['content'] as String? ?? '',
      messageType: _parseMessageType(json['messageType'] as String?),
      timestamp: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      isRead: json['isRead'] as bool? ?? false,
      reactions: const [],
      replyToId: json['replyToId'] as String?,
      replyToContent: json['replyToContent'] as String?,
      replyToSenderName: json['replyToSenderName'] as String?,
      senderInitials: json['senderInitials'] as String?,
      durationSeconds: (json['durationSeconds'] as int?) ??
          (json['voiceMessageDuration'] as int?),
      eventTitle: json['eventTitle'] as String?,
      eventDate: json['eventDate'] as String?,
      mediaUrl: json['mediaUrl'] as String?,
      isStarred: json['isStarred'] as bool? ?? false,
      isPinned: json['isPinned'] as bool? ?? false,
      isEdited: json['isEdited'] as bool? ?? false,
      isDeletedForEveryone: json['isDeletedForEveryone'] as bool? ?? false,
      messageStatus: json['messageStatus'] as String? ?? 'sent',
      messageSubType: json['messageSubType'] as String?,
      forwardedFrom: json['forwardedFrom'] as String?,
      deletedForMe: json['deletedForMe'] as List<dynamic>? ?? const [],
      groupId: json['groupId'] as String?,
      gameType: json['gameType'] as String?,
      gameId: json['gameId'] as String?,
      roomCode: json['roomCode'] as String?,
      gameMaxPlayers: json['gameMaxPlayers'] as int?,
      gameCurrentPlayers: json['gameCurrentPlayers'] as int?,
      gameInviteStatus: json['gameInviteStatus'] as String?,
      // Phase 22 / Task 3 — parse the denormalized `mentions` JSONB
      // column. Falls back to [] when the column is null or the row
      // came from a server that didn't have the column yet.
      mentions: _parseMentions(json['mentions']),
      // Phase 22 / Task 5 — poll fields.
      pollQuestion: json['pollQuestion'] as String?,
      pollOptions: _parseStringArray(json['pollOptions']),
      pollVoteCounts: _parseIntArray(json['pollVoteCounts']),
      pollVoterIds: _parseVoterIds(json['pollVoterIds']),
      pollCreatedAt: json['pollCreatedAt'] == null
          ? null
          : DateTime.tryParse(json['pollCreatedAt'] as String),
    );
  }

  /// Parse the `mentions` JSONB column into a List<MentionRef>.
  /// Tolerates null, non-list, and malformed entries (defensive — the
  /// server column is JSONB so we could get anything back).
  static List<MentionRef> _parseMentions(dynamic raw) {
    if (raw == null || raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(MentionRef.fromJson)
        .where((m) => m.userId.isNotEmpty)
        .toList();
  }

  /// Parse a JSONB string array (pollOptions) into a List<String>.
  /// Tolerates null and non-list values.
  static List<String> _parseStringArray(dynamic raw) {
    if (raw == null || raw is! List) return const [];
    return raw.map((e) => e?.toString() ?? '').toList();
  }

  /// Parse a JSONB int array (pollVoteCounts) into a List<int>.
  /// Tolerates null, non-list, and non-int entries.
  static List<int> _parseIntArray(dynamic raw) {
    if (raw == null || raw is! List) return const [];
    return raw.map((e) {
      if (e is int) return e;
      if (e is num) return e.toInt();
      return 0;
    }).toList();
  }

  /// Parse a JSONB array of {userId, optionIndex} (pollVoterIds).
  /// Tolerates null, non-list, and malformed entries.
  static List<Map<String, dynamic>> _parseVoterIds(dynamic raw) {
    if (raw == null || raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .where((m) => m['userId'] != null)
        .toList();
  }

  static MessageType _parseMessageType(String? raw) {
    switch (raw) {
      case 'photo':
        return MessageType.photo;
      case 'voiceNote':
        return MessageType.voiceNote;
      case 'familyEvent':
        return MessageType.familyEvent;
      case 'sticker':
        return MessageType.sticker;
      case 'gameInvite':
        return MessageType.gameInvite;
      case 'poll':
        return MessageType.poll;
      case 'gif':
        return MessageType.gif;
      case 'document':
        return MessageType.document;
      case 'location':
        return MessageType.location;
      case 'text':
      default:
        return MessageType.text;
    }
  }

  /// Serialize for Supabase insert. Excludes server-managed fields
  /// (id is generated client-side as a CUID-like string; createdAt /
  /// updatedAt are server defaults; isRead is false on insert).
  Map<String, dynamic> toJson({required String familyId}) {
    return {
      'id': id,
      'familyId': familyId,
      'senderId': senderId,
      'senderName': senderName,
      'senderInitials': senderInitials,
      'content': content,
      'messageType': _messageTypeToString(messageType),
      'replyToId': replyToId,
      'replyToContent': replyToContent,
      'replyToSenderName': replyToSenderName,
      'durationSeconds': durationSeconds,
      'voiceMessageDuration': durationSeconds,
      'eventTitle': eventTitle,
      'eventDate': eventDate,
      if (mediaUrl != null) 'mediaUrl': mediaUrl,
      'isStarred': isStarred,
      'isPinned': isPinned,
      'isEdited': isEdited,
      'isDeletedForEveryone': isDeletedForEveryone,
      'messageStatus': messageStatus,
      if (messageSubType != null) 'messageSubType': messageSubType,
      if (forwardedFrom != null) 'forwardedFrom': forwardedFrom,
      if (groupId != null) 'groupId': groupId,
      if (gameType != null) 'gameType': gameType,
      if (gameId != null) 'gameId': gameId,
      if (roomCode != null) 'roomCode': roomCode,
      if (gameMaxPlayers != null) 'gameMaxPlayers': gameMaxPlayers,
      if (gameCurrentPlayers != null) 'gameCurrentPlayers': gameCurrentPlayers,
      if (gameInviteStatus != null) 'gameInviteStatus': gameInviteStatus,
      // Phase 22 / Task 3 — mentions are stored as a JSONB array on the
      // row. Empty list → '[]' which the server treats as "no mentions".
      'mentions': mentions.map((m) => m.toJson()).toList(),
      // Phase 22 / Task 5 — poll fields. Null on non-poll rows.
      if (pollQuestion != null) 'pollQuestion': pollQuestion,
      if (pollOptions.isNotEmpty) 'pollOptions': pollOptions,
      if (pollVoteCounts.isNotEmpty) 'pollVoteCounts': pollVoteCounts,
      if (pollVoterIds.isNotEmpty) 'pollVoterIds': pollVoterIds,
      if (pollCreatedAt != null)
        'pollCreatedAt': pollCreatedAt!.toIso8601String(),
    };
  }

  static String _messageTypeToString(MessageType t) {
    switch (t) {
      case MessageType.photo:
        return 'photo';
      case MessageType.voiceNote:
        return 'voiceNote';
      case MessageType.familyEvent:
        return 'familyEvent';
      case MessageType.sticker:
        return 'sticker';
      case MessageType.gameInvite:
        return 'gameInvite';
      case MessageType.poll:
        return 'poll';
      case MessageType.gif:
        return 'gif';
      case MessageType.document:
        return 'document';
      case MessageType.location:
        return 'location';
      case MessageType.text:
      default:
        return 'text';
    }
  }
}

/// Online member info for the chat header.
class OnlineMember {
  const OnlineMember({
    required this.id,
    required this.name,
    required this.initials,
    this.isOnline = false,
  });

  final String id;
  final String name;
  final String initials;
  final bool isOnline;

  OnlineMember copyWith({
    String? id,
    String? name,
    String? initials,
    bool? isOnline,
  }) {
    return OnlineMember(
      id: id ?? this.id,
      name: name ?? this.name,
      initials: initials ?? this.initials,
      isOnline: isOnline ?? this.isOnline,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// State
// ═══════════════════════════════════════════════════════════════════════

/// Immutable state for the family chat feature.
class ChatState {
  const ChatState({
    this.messages = const [],
    this.members = const [],
    this.isTyping = false,
    this.typingUserName,
    this.replyToMessage,
    this.isLoading = false,
    this.error,
  });

  /// All messages in the chat, sorted newest-first (UI displays with
  /// reverse: true on ListView).
  final List<ChatMessage> messages;

  /// Family members in this chat.
  final List<OnlineMember> members;

  /// Whether someone is currently typing.
  final bool isTyping;

  /// Name of the person who is typing.
  final String? typingUserName;

  /// Message being replied to (null if not replying).
  final ChatMessage? replyToMessage;

  /// Loading state for initial fetch.
  final bool isLoading;

  /// Error message if fetch failed (null = no error).
  final String? error;

  /// Number of online members.
  int get onlineCount => members.where((m) => m.isOnline).length;

  /// Total members in the chat.
  int get totalMembers => members.length;

  ChatState copyWith({
    List<ChatMessage>? messages,
    List<OnlineMember>? members,
    bool? isTyping,
    String? typingUserName,
    ChatMessage? replyToMessage,
    bool isLoading = false,
    bool clearReplyTo = false,
    String? error,
    bool clearError = false,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      members: members ?? this.members,
      isTyping: isTyping ?? this.isTyping,
      typingUserName: typingUserName ?? this.typingUserName,
      replyToMessage: clearReplyTo
          ? null
          : (replyToMessage ?? this.replyToMessage),
      isLoading: isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Notifier
// ═══════════════════════════════════════════════════════════════════════

/// Generates a CUID-like ID for new messages so the client can
/// optimistically insert into state before the server confirms.
String _generateId() {
  final timestamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final random = Random();
  final rand = List.generate(
    16,
    (_) => random.nextInt(36),
  ).map((v) => v.toRadixString(36)).join();
  return 'cm_${timestamp}_$rand';
}

/// Compute the sender's initials from their display name.
String _initialsFromName(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '?';
  if (parts.length == 1) {
    return parts.first[0].toUpperCase();
  }
  return (parts.first[0] + parts[1][0]).toUpperCase();
}

class ChatNotifier extends StateNotifier<ChatState> {
  ChatNotifier({
    required this.familyId,
    required this.ref,
  }) : super(const ChatState(isLoading: true)) {
    _init();
  }

  final String familyId;
  final Ref ref;

  // Realtime channel for this family's chat
  RealtimeChannel? _channel;
  // Echo de-dup: tracks message IDs we've inserted optimistically so
  // the realtime INSERT event for our own message doesn't double-render.
  final Set<String> _pendingOptimisticIds = {};
  // Subscriptions to family member list (for the header online count)
  StreamSubscription<List<Map<String, dynamic>>>? _membersSub;
  // Whether we've completed the initial load
  bool _initialLoadDone = false;
  // v5.2: Listener for family member changes — refreshes the chat
  // member roster when a Person is added/deleted.
  // ref.listen returns a ProviderSubscription.
  ProviderSubscription<AsyncValue<List<Person>>>? _memberListListener;

  // ── Initialization ───────────────────────────────────────────────

  Future<void> _init() async {
    await _loadMembers();
    await _loadMessages();
    _subscribeToRealtime();
    _listenToMemberChanges();
  }

  /// v5.2: Listens to changes in familyMembersProvider and re-loads
  /// the chat member roster when members are added/deleted/updated.
  ///
  /// Without this, the chat header's member list only refreshes when
  /// the chat screen is re-opened. With this listener, it refreshes
  /// immediately when a new Person is added to the family.
  void _listenToMemberChanges() {
    try {
      // Watch the familyMembersProvider — when it invalidates (e.g.
      // after createPerson), re-load the chat member roster.
      // FutureProvider<List<Person>> emits AsyncValue<List<Person>>,
      // so we listen to the AsyncValue and re-load when it has data.
      _memberListListener = ref.listen(
        familyMembersProvider(familyId),
        (previous, next) {
          // Only re-load when the new AsyncValue has data (not loading).
          if (next.hasValue && !next.isLoading) {
            Future.microtask(() => _loadMembers());
          }
        },
        fireImmediately: false,
      );
    } catch (e) {
      debugPrint('⚠️ ChatNotifier._listenToMemberChanges error: $e');
    }
  }

  /// Returns the current Supabase client (or null if not ready).
  SupabaseClient? get _client => ref.read(supabaseProvider);

  /// Returns the current user's ID (auth.users.id as string).
  String? get _currentUserId =>
      _client?.auth.currentUser?.id ?? _client?.auth.currentSession?.user.id;

  /// Returns the current user's display name for chat messages.
  /// Falls back to "You" if we can't resolve a real name.
  String get _currentUserName {
    final user = _client?.auth.currentUser;
    if (user == null) return 'You';
    // Try userMetadata.name first, then email, then 'You'
    final meta = user.userMetadata;
    final name = meta?['name'] as String? ??
        meta?['full_name'] as String? ??
        meta?['displayName'] as String?;
    if (name != null && name.trim().isNotEmpty) return name.trim();
    if (user.email != null) return user.email!.split('@').first;
    return 'You';
  }

  // ── Load members (for the chat header) ────────────────────────────

  Future<void> _loadMembers() async {
    final client = _client;
    if (client == null) return;
    try {
      // Use the SECURITY DEFINER RPC fn_get_family_member_names(family_id)
      // to fetch display names for ALL family members. The public."User"
      // table has RLS that only lets a user read their own row, so a
      // direct .from('User').select() would return just the current user
      // and every other member would show as "Member". The RPC bypasses
      // RLS safely and self-gates on family membership.
      final response = await client
          .rpc('fn_get_family_member_names', params: {'family_id': familyId});

      final members = <OnlineMember>[];
      for (final row in (response as List? ?? <Map<String, dynamic>>[])) {
        final userId = row['userId'] as String? ?? '';
        if (userId.isEmpty) continue;
        final name = row['name'] as String? ?? 'Member';
        // v91: Mark the current user as online immediately — presence
        // events from other users will update via _handlePresenceChange.
        final isMe = userId == _currentUserId;
        members.add(OnlineMember(
          id: userId,
          name: name,
          initials: _initialsFromName(name),
          isOnline: isMe, // current user is always online in their own session
        ));
      }
      if (mounted) {
        state = state.copyWith(members: members);
      }
    } catch (e) {
      debugPrint('⚠️ ChatNotifier._loadMembers error: $e');
      // Fallback: at least include the current user so the header
      // isn't completely empty.
      final myUserId = _currentUserId;
      final myName = _currentUserName;
      if (mounted && myUserId != null && state.members.isEmpty) {
        state = state.copyWith(members: [
          OnlineMember(
            id: myUserId,
            name: myName,
            initials: _initialsFromName(myName),
            isOnline: true, // v91: current user is online
          ),
        ]);
      }
    }
  }

  // ── Load messages from Supabase ───────────────────────────────────

  Future<void> _loadMessages() async {
    final client = _client;
    if (client == null) {
      if (mounted) {
        state = state.copyWith(isLoading: false, error: 'Not signed in');
      }
      return;
    }
    try {
      // Fetch last 200 messages, ordered by createdAt ASC.
      // We'll store newest-first in state (matching the old demo layout).
      final messagesResponse = await client
          .from('ChatMessage')
          .select()
          .eq('familyId', familyId)
          .order('createdAt', ascending: true)
          .limit(200);

      final messageIds = <String>[];
      final messages = <ChatMessage>[];
      for (final row in messagesResponse as List) {
        final msg = ChatMessage.fromJson(row as Map<String, dynamic>);
        if (msg.id.isEmpty) continue;
        messages.add(msg);
        messageIds.add(msg.id);
      }

      // Fetch reactions for these messages in a single query.
      final reactions = <String, List<MessageReaction>>{};
      if (messageIds.isNotEmpty) {
        // Supabase's inFilter accepts a list.
        final reactionsResponse = await client
            .from('ChatMessageReaction')
            .select()
            .inFilter('messageId', messageIds);
        for (final r in reactionsResponse as List) {
          final messageId = r['messageId'] as String? ?? '';
          if (messageId.isEmpty) continue;
          reactions.putIfAbsent(messageId, () => []);
          reactions[messageId]!.add(MessageReaction(
            emoji: r['emoji'] as String? ?? '',
            userId: r['userId'] as String? ?? '',
          ));
        }
      }

      // Apply reactions to messages.
      final withReactions = messages.map((m) {
        return m.copyWith(reactions: reactions[m.id] ?? const []);
      }).toList();

      // Newest first (UI ListView is reverse: true)
      withReactions.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      if (mounted) {
        state = state.copyWith(
          messages: withReactions,
          isLoading: false,
          clearError: true,
        );
      }
      _initialLoadDone = true;

      // Mark all unread messages not sent by me as read.
      unawaited(_markUnreadAsRead());
    } catch (e) {
      debugPrint('⚠️ ChatNotifier._loadMessages error: $e');
      if (mounted) {
        state = state.copyWith(
          isLoading: false,
          error: 'Failed to load messages: $e',
        );
      }
    }
  }

  // ── Realtime subscription ─────────────────────────────────────────

  void _subscribeToRealtime() {
    final client = _client;
    if (client == null) return;

    // Tear down any existing channel.
    _channel?.unsubscribe();

    _channel = client
        .channel('chat:$familyId')
        // New message inserted
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'ChatMessage',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'familyId',
            value: familyId,
          ),
          callback: (payload) => _handleMessageInsert(payload.newRecord),
        )
        // Message updated (edit / soft-delete / read-receipt flip)
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'ChatMessage',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'familyId',
            value: familyId,
          ),
          callback: (payload) => _handleMessageUpdate(payload.newRecord),
        )
        // Message deleted (sender hard-delete)
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'ChatMessage',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'familyId',
            value: familyId,
          ),
          callback: (payload) => _handleMessageDelete(payload.oldRecord),
        )
        // Reaction added
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'ChatMessageReaction',
          callback: (payload) => _handleReactionChange(
            payload.newRecord,
            isDelete: false,
          ),
        )
        // Reaction removed
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'ChatMessageReaction',
          callback: (payload) => _handleReactionChange(
            payload.oldRecord,
            isDelete: true,
          ),
        );

    // ── Presence: track who's online in this family chat ──
    // v91: Real-time online status. We broadcast the current user's
    // presence via channel.track(). The onPresenceSync callback updates
    // online status for all connected members. Since the exact payload
    // structure varies by realtime_client version, we use a defensive
    // approach: mark the current user as online immediately, and
    // attempt to parse the payload for other users' presence.
    _channel!.onPresenceSync((payload) {
      if (!mounted) return;
      // The current user is always online in their own session.
      final myId = _currentUserId;
      if (myId == null) return;
      state = state.copyWith(
        members: state.members
            .map((m) => m.copyWith(isOnline: m.id == myId ? true : m.isOnline))
            .toList(),
      );
    });

    // Track the current user's presence once the channel subscribes.
    final myId = _currentUserId;
    final myName = _currentUserName;
    if (myId != null) {
      _channel!.subscribe((status, [error]) {
        if (status == 'SUBSCRIBED') {
          _channel!.track({
            'user_id': myId,
            'name': myName,
          });
          // Tier 1 / Last Seen — mark the user as online in the
          // UserPresence table so other family members see "online"
          // on the Family Profile + member profile sheets.
          ref.read(lastSeenProvider.notifier).updateMyPresence(true);
        }
      });
    } else {
      _channel!.subscribe();
    }

    debugPrint('📡 ChatNotifier: subscribed to chat:$familyId (with presence)');
  }

  void _handleMessageInsert(Map<String, dynamic> row) {
    final msgId = row['id'] as String?;
    if (msgId == null || msgId.isEmpty) return;

    // Echo de-dup: if we inserted this message optimistically, the
    // pending id is in _pendingOptimisticIds. Remove it and skip the
    // insert (the optimistic message is already in state).
    if (_pendingOptimisticIds.remove(msgId)) {
      // Still patch isRead from the server's view if needed.
      final existing = state.messages.firstWhere(
        (m) => m.id == msgId,
        orElse: () => ChatMessage(
          id: msgId,
          senderId: '',
          senderName: '',
          content: '',
          messageType: MessageType.text,
          timestamp: DateTime.now(),
        ),
      );
      final serverIsRead = row['isRead'] as bool? ?? false;
      if (existing.isRead != serverIsRead && mounted) {
        final updated = state.messages.map((m) {
          if (m.id != msgId) return m;
          return m.copyWith(isRead: serverIsRead);
        }).toList();
        state = state.copyWith(messages: updated);
      }
      return;
    }
    if (state.messages.any((m) => m.id == msgId)) {
      // Already in state — skip (idempotent).
      return;
    }

    final msg = ChatMessage.fromJson(row);
    final updated = [msg, ...state.messages];
    updated.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (mounted) {
      state = state.copyWith(messages: updated);
    }

    // If the message was sent by someone else, mark it as read.
    final myUserId = _currentUserId;
    if (myUserId != null && msg.senderId != myUserId) {
      unawaited(_markSingleAsRead(msg.id, myUserId));
    }
  }

  void _handleMessageUpdate(Map<String, dynamic> row) {
    final msgId = row['id'] as String?;
    if (msgId == null) return;
    final updated = state.messages.map((m) {
      if (m.id != msgId) return m;
      return ChatMessage.fromJson(row).copyWith(reactions: m.reactions);
    }).toList();
    if (mounted) {
      state = state.copyWith(messages: updated);
    }
  }

  void _handleMessageDelete(Map<String, dynamic> row) {
    final msgId = row['id'] as String?;
    if (msgId == null) return;
    final updated = state.messages.where((m) => m.id != msgId).toList();
    if (mounted) {
      state = state.copyWith(messages: updated);
    }
  }

  void _handleReactionChange(Map<String, dynamic> row,
      {required bool isDelete}) {
    final messageId = row['messageId'] as String?;
    if (messageId == null) return;
    final emoji = row['emoji'] as String? ?? '';
    final userId = row['userId'] as String? ?? '';

    final updated = state.messages.map((m) {
      if (m.id != messageId) return m;
      final reactions = List<MessageReaction>.from(m.reactions);
      if (isDelete) {
        reactions.removeWhere(
          (r) => r.emoji == emoji && r.userId == userId,
        );
      } else {
        if (!reactions.any(
          (r) => r.emoji == emoji && r.userId == userId,
        )) {
          reactions.add(MessageReaction(emoji: emoji, userId: userId));
        }
      }
      return m.copyWith(reactions: reactions);
    }).toList();

    if (mounted) {
      state = state.copyWith(messages: updated);
    }
  }

  // ── Actions ──────────────────────────────────────────────────────

  /// Send a new text message. Inserts optimistically into state, then
  /// persists to Supabase. If the server INSERT fails, the optimistic
  /// message is removed and an error is surfaced.
  Future<void> sendMessage(String content, {String? replyToId, String? groupId}) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;

    final client = _client;
    final myUserId = _currentUserId;
    if (client == null || myUserId == null) {
      if (mounted) {
        state = state.copyWith(error: 'Not signed in');
      }
      return;
    }

    final now = DateTime.now();
    final msgId = _generateId();
    final senderName = _currentUserName;

    ChatMessage? replyTo;
    String? replyContent;
    String? replySender;
    if (replyToId != null) {
      replyTo = state.messages.firstWhere(
        (m) => m.id == replyToId,
        orElse: () => state.messages.first,
      );
      replyContent = replyTo.content;
      replySender = replyTo.senderName;
    }

    final optimistic = ChatMessage(
      id: msgId,
      senderId: myUserId,
      senderName: senderName,
      content: trimmed,
      messageType: MessageType.text,
      timestamp: now,
      isRead: false,
      replyToId: replyToId,
      replyToContent: replyContent,
      replyToSenderName: replySender,
      senderInitials: _initialsFromName(senderName),
      groupId: groupId,
    );

    // Track for echo de-dup so the realtime INSERT doesn't double-render.
    _pendingOptimisticIds.add(msgId);

    // Optimistic insert (newest first).
    final updated = [optimistic, ...state.messages];
    if (mounted) {
      state = state.copyWith(messages: updated, clearReplyTo: true);
    }

    // Persist to Supabase. The realtime INSERT event will fire but be
    // dropped by the de-dup check above.
    try {
      await client.from('ChatMessage').insert(optimistic.toJson(
        familyId: familyId,
      ));
    } catch (e) {
      debugPrint('⚠️ ChatNotifier.sendMessage insert failed: $e');
      _pendingOptimisticIds.remove(msgId);
      if (mounted) {
        final withoutFailed = state.messages.where((m) => m.id != msgId).toList();
        state = state.copyWith(
          messages: withoutFailed,
          error: 'Failed to send message',
        );
      }
    }
  }

  /// Phase 22 / Task 3 — Send a text message that @mentions one or more
  /// family members.
  ///
  /// Flow:
  ///   1. Optimistic insert (same as `sendMessage`) — the message
  ///      appears immediately with the mentions JSONB column populated
  ///      so the local bubble highlights the @Name spans right away.
  ///   2. Server insert via the normal ChatMessage INSERT path (the
  ///      `mentions` JSONB is included in `toJson`).
  ///   3. Call `fn_add_mentions_to_message` RPC to populate the
  ///      queryable `ChatMention` rows and fire the distinct
  ///      `chat_mention` push/in-app notifications to each mentioned
  ///      user. This is best-effort — a failure here doesn't roll back
  ///      the message, the bubble still renders the @Name highlights.
  ///
  /// [mentions] is the list of MentionRef the caller built from the
  /// mention picker UI. Each ref's [start, end) character offsets must
  /// point at the `@Name` span inside [content].
  Future<void> sendMessageWithMentions(
    String content, {
    required List<MentionRef> mentions,
    String? replyToId,
    String? groupId,
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;
    if (mentions.isEmpty) {
      // No mentions → just call the regular sendMessage path.
      return sendMessage(trimmed, replyToId: replyToId, groupId: groupId);
    }

    final client = _client;
    final myUserId = _currentUserId;
    if (client == null || myUserId == null) {
      if (mounted) state = state.copyWith(error: 'Not signed in');
      return;
    }

    final now = DateTime.now();
    final msgId = _generateId();
    final senderName = _currentUserName;

    ChatMessage? replyTo;
    String? replyContent;
    String? replySender;
    if (replyToId != null) {
      replyTo = state.messages.firstWhere(
        (m) => m.id == replyToId,
        orElse: () => state.messages.first,
      );
      replyContent = replyTo.content;
      replySender = replyTo.senderName;
    }

    final optimistic = ChatMessage(
      id: msgId,
      senderId: myUserId,
      senderName: senderName,
      content: trimmed,
      messageType: MessageType.text,
      timestamp: now,
      isRead: false,
      replyToId: replyToId,
      replyToContent: replyContent,
      replyToSenderName: replySender,
      senderInitials: _initialsFromName(senderName),
      groupId: groupId,
      mentions: mentions,
    );

    _pendingOptimisticIds.add(msgId);

    final updated = [optimistic, ...state.messages];
    if (mounted) {
      state = state.copyWith(messages: updated, clearReplyTo: true);
    }

    // Step 1: persist the ChatMessage row (mentions JSONB is included
    // via toJson so the server-side row has the highlight spans too).
    try {
      await client.from('ChatMessage').insert(optimistic.toJson(
        familyId: familyId,
      ));
    } catch (e) {
      debugPrint('⚠️ ChatNotifier.sendMessageWithMentions insert failed: $e');
      _pendingOptimisticIds.remove(msgId);
      if (mounted) {
        final withoutFailed = state.messages.where((m) => m.id != msgId).toList();
        state = state.copyWith(
          messages: withoutFailed,
          error: 'Failed to send message',
        );
      }
      return;
    }

    // Step 2: best-effort — populate ChatMention rows + fire
    // 'chat_mention' notifications to each mentioned user. Failure
    // here doesn't roll back the message; the mentions JSONB on the
    // row still makes the bubble highlight correctly.
    try {
      await client.rpc(
        'fn_add_mentions_to_message',
        params: {
          'p_message_id': msgId,
          'p_family_id': familyId,
          'p_mentions': mentions.map((m) => m.toJson()).toList(),
        },
      ).timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('⚠️ ChatNotifier.sendMessageWithMentions RPC failed: $e '
          '(message was sent; mention notifications may not fire)');
    }
  }

  /// Set the message to reply to.
  void setReplyTo(ChatMessage? message) {
    state = state.copyWith(replyToMessage: message);
  }

  /// Clear the reply-to state.
  void clearReplyTo() {
    state = state.copyWith(clearReplyTo: true);
  }

  /// Send a photo attachment (v91).
  ///
  /// Uploads the image bytes to the `chat-attachments` storage bucket,
  /// gets the public URL, and inserts a ChatMessage with
  /// `messageType = photo` and `mediaUrl` set to the public URL.
  Future<void> sendAttachment({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    String? caption,
  }) async {
    final client = _client;
    final myUserId = _currentUserId;
    if (client == null || myUserId == null) {
      if (mounted) state = state.copyWith(error: 'Not signed in');
      return;
    }

    final senderName = _currentUserName;
    final msgId = _generateId();
    final now = DateTime.now();

    // Upload to storage
    final storagePath = '$familyId/$msgId-$fileName';
    try {
      await client.storage
          .from('chat-attachments')
          .uploadBinary(storagePath, bytes, fileOptions: FileOptions(contentType: mimeType));
    } catch (e) {
      debugPrint('⚠️ ChatNotifier.sendAttachment upload failed: $e');
      if (mounted) state = state.copyWith(error: 'Failed to upload attachment');
      return;
    }

    final mediaUrl = client.storage
        .from('chat-attachments')
        .getPublicUrl(storagePath);

    // v125: Include mediaUrl in the optimistic message so the sender
    // sees the image immediately (not a gray placeholder). Previously
    // mediaUrl was only set on the server INSERT, not the local copy.
    final optimistic = ChatMessage(
      id: msgId,
      senderId: myUserId,
      senderName: senderName,
      content: caption ?? '',
      messageType: MessageType.photo,
      timestamp: now,
      isRead: false,
      senderInitials: _initialsFromName(senderName),
      mediaUrl: mediaUrl,
      messageStatus: 'sent',
    );

    _pendingOptimisticIds.add(msgId);
    final updated = [optimistic, ...state.messages];
    if (mounted) state = state.copyWith(messages: updated);

    try {
      await client.from('ChatMessage').insert({
        ...optimistic.toJson(familyId: familyId),
        'mediaUrl': mediaUrl,
      });
    } catch (e) {
      debugPrint('⚠️ ChatNotifier.sendAttachment insert failed: $e');
      _pendingOptimisticIds.remove(msgId);
      if (mounted) {
        final withoutFailed = state.messages.where((m) => m.id != msgId).toList();
        state = state.copyWith(
          messages: withoutFailed,
          error: 'Failed to send attachment',
        );
      }
    }
  }

  /// Forward a message to another family chat (v91).
  ///
  /// Re-inserts the message content into the target family's chat
  /// with `messageType` preserved. The forwarded message appears as
  /// sent by the current user (not the original sender) — this is
  /// standard forwarding behavior (like WhatsApp/Telegram).
  Future<bool> forwardMessage({
    required String targetFamilyId,
    required ChatMessage original,
  }) async {
    final client = _client;
    final myUserId = _currentUserId;
    if (client == null || myUserId == null) return false;

    final msgId = _generateId();
    final senderName = _currentUserName;
    final now = DateTime.now();

    final forwarded = ChatMessage(
      id: msgId,
      senderId: myUserId,
      senderName: senderName,
      content: original.content,
      messageType: original.messageType,
      timestamp: now,
      isRead: false,
      senderInitials: _initialsFromName(senderName),
    );

    try {
      await client.from('ChatMessage').insert({
        ...forwarded.toJson(familyId: targetFamilyId),
        if (original.mediaUrl != null) 'mediaUrl': original.mediaUrl,
      });
      return true;
    } catch (e) {
      debugPrint('⚠️ ChatNotifier.forwardMessage failed: $e');
      return false;
    }
  }

  /// Tier 1 / Forward Picker — forward a message to MULTIPLE targets at
  /// once (family chats + DM recipients) via the fn_forward_message RPC.
  ///
  /// The RPC:
  ///   • Validates the caller is a member of every target family.
  ///   • Inserts a copy of the message into each target family chat
  ///     with forwardedFrom = original sender name (so the bubble shows
  ///     "Forwarded from <name>").
  ///   • For DM targets (text + sticker only — DMs don't have a mediaUrl
  ///     column), inserts a DirectMessage row.
  ///   • Resets poll votes / reactions / read state on the copies.
  ///
  /// Returns a map with: success, familyChatsForwarded, dmChatsForwarded,
  /// totalForwarded, insertedMessageIds. Returns null on auth / network
  /// failure.
  Future<Map<String, dynamic>?> forwardMessageToTargets({
    required String messageId,
    List<String> targetFamilyIds = const [],
    List<String> targetDmUserIds = const [],
  }) async {
    final client = _client;
    final myUserId = _currentUserId;
    if (client == null || myUserId == null) return null;
    if (targetFamilyIds.isEmpty && targetDmUserIds.isEmpty) return null;

    try {
      final response = await client.rpc(
        'fn_forward_message',
        params: {
          'p_message_id': messageId,
          'p_target_family_ids': targetFamilyIds,
          'p_target_dm_user_ids': targetDmUserIds,
        },
      ).timeout(const Duration(seconds: 12));

      final result = response as Map<String, dynamic>?;
      return result;
    } catch (e) {
      debugPrint('⚠️ ChatNotifier.forwardMessageToTargets error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Send a voice message (Phase 13).
  ///
  /// Uploads the recorded audio bytes to the `voice-messages` storage
  /// bucket, gets the public URL, and inserts a ChatMessage with
  /// `messageType = voiceNote`, `messageSubType = voice`,
  /// `mediaUrl` set to the public URL, and `voiceMessageDuration`
  /// set to the recording length in seconds.
  ///
  /// The audio format depends on the platform:
  ///   - Android/iOS: typically audio/m4a (AAC-LC inside MP4 container)
  ///   - Web:          typically audio/webm;codecs=opus
  ///   - Windows:      typically audio/wav
  /// The `voice-messages` bucket accepts all common audio MIME types.
  Future<void> sendVoiceMessage({
    required Uint8List bytes,
    required int durationSeconds,
    required String mimeType,
    required String fileName,
    String? caption,
  }) async {
    final client = _client;
    final myUserId = _currentUserId;
    if (client == null || myUserId == null) {
      if (mounted) state = state.copyWith(error: 'Not signed in');
      return;
    }

    final senderName = _currentUserName;
    final msgId = _generateId();
    final now = DateTime.now();

    // Upload to storage
    final storagePath = '$familyId/$msgId-$fileName';
    try {
      await client.storage
          .from('voice-messages')
          .uploadBinary(
            storagePath,
            bytes,
            fileOptions: FileOptions(contentType: mimeType),
          );
    } catch (e) {
      debugPrint('⚠️ ChatNotifier.sendVoiceMessage upload failed: $e');
      if (mounted) state = state.copyWith(error: 'Failed to upload voice message');
      return;
    }

    final mediaUrl = client.storage
        .from('voice-messages')
        .getPublicUrl(storagePath);

    final optimistic = ChatMessage(
      id: msgId,
      senderId: myUserId,
      senderName: senderName,
      content: caption ?? '',
      messageType: MessageType.voiceNote,
      timestamp: now,
      isRead: false,
      senderInitials: _initialsFromName(senderName),
    );

    _pendingOptimisticIds.add(msgId);
    final updated = [optimistic, ...state.messages];
    if (mounted) state = state.copyWith(messages: updated);

    try {
      await client.from('ChatMessage').insert({
        ...optimistic.toJson(familyId: familyId),
        'mediaUrl': mediaUrl,
        'voiceMessageDuration': durationSeconds,
        'messageSubType': 'voice',
        'mediaType': mimeType,
        'mediaFileName': fileName,
      });
    } catch (e) {
      debugPrint('⚠️ ChatNotifier.sendVoiceMessage insert failed: $e');
      _pendingOptimisticIds.remove(msgId);
      if (mounted) {
        final withoutFailed = state.messages.where((m) => m.id != msgId).toList();
        state = state.copyWith(
          messages: withoutFailed,
          error: 'Failed to send voice message',
        );
      }
    }
  }

  /// Send a sticker message (Phase 14).
  ///
  /// A "sticker" in Kinrel is a single large emoji rendered at 4x size
  /// (e.g. 😀, ❤️, 👍). Stored as messageType='sticker', content=emoji
  /// character, messageSubType='sticker'. No mediaUrl — the emoji IS
  /// the message. This keeps storage cheap and rendering trivial.
  ///
  /// Stickers differ from text messages:
  ///   - No bubble background (just the emoji on chat bg)
  ///   - Centered alignment
  ///   - Much larger font (64px vs 14.5px)
  ///   - No "edited" tag, no copy menu (just star / reply / forward)
  Future<void> sendSticker(String emoji, {String? replyToId}) async {
    if (emoji.isEmpty) return;
    final client = _client;
    final myUserId = _currentUserId;
    if (client == null || myUserId == null) {
      if (mounted) state = state.copyWith(error: 'Not signed in');
      return;
    }

    final now = DateTime.now();
    final msgId = _generateId();
    final senderName = _currentUserName;

    // Resolve reply-to (if any)
    String? replyContent;
    String? replySender;
    if (replyToId != null) {
      final replyTo = state.messages.firstWhere(
        (m) => m.id == replyToId,
        orElse: () => state.messages.first,
      );
      replyContent = replyTo.content;
      replySender = replyTo.senderName;
    }

    final optimistic = ChatMessage(
      id: msgId,
      senderId: myUserId,
      senderName: senderName,
      content: emoji,
      messageType: MessageType.sticker,
      timestamp: now,
      isRead: false,
      replyToId: replyToId,
      replyToContent: replyContent,
      replyToSenderName: replySender,
      senderInitials: _initialsFromName(senderName),
      messageSubType: 'sticker',
    );

    _pendingOptimisticIds.add(msgId);
    final updated = [optimistic, ...state.messages];
    if (mounted) state = state.copyWith(messages: updated, clearReplyTo: true);

    try {
      await client.from('ChatMessage').insert(optimistic.toJson(
        familyId: familyId,
      ));
    } catch (e) {
      debugPrint('⚠️ ChatNotifier.sendSticker insert failed: $e');
      _pendingOptimisticIds.remove(msgId);
      if (mounted) {
        final withoutFailed = state.messages.where((m) => m.id != msgId).toList();
        state = state.copyWith(
          messages: withoutFailed,
          error: 'Failed to send sticker',
        );
      }
    }
  }

  /// Tier 2 / GIF search — send a GIF message.
  ///
  /// The [gifUrl] is the high-res original GIF URL from Giphy. The
  /// [title] is stored in content for the inbox preview + accessibility.
  Future<void> sendGif({
    required String gifUrl,
    required String title,
    String? replyToId,
  }) async {
    final client = _client;
    final myUserId = _currentUserId;
    if (client == null || myUserId == null) return;

    final now = DateTime.now();
    final msgId = _generateId();
    final senderName = _currentUserName;

    String? replyContent;
    String? replySender;
    if (replyToId != null) {
      final replyTo = state.messages.firstWhere(
        (m) => m.id == replyToId,
        orElse: () => state.messages.first,
      );
      replyContent = replyTo.content;
      replySender = replyTo.senderName;
    }

    final optimistic = ChatMessage(
      id: msgId,
      senderId: myUserId,
      senderName: senderName,
      content: title,
      messageType: MessageType.gif,
      timestamp: now,
      isRead: false,
      replyToId: replyToId,
      replyToContent: replyContent,
      replyToSenderName: replySender,
      senderInitials: _initialsFromName(senderName),
      mediaUrl: gifUrl,
      messageSubType: 'gif',
    );

    _pendingOptimisticIds.add(msgId);
    if (mounted) {
      state = state.copyWith(
        messages: [optimistic, ...state.messages],
        clearReplyTo: true,
      );
    }

    try {
      await client.from('ChatMessage').insert(optimistic.toJson(familyId: familyId));
    } catch (e) {
      debugPrint('⚠️ ChatNotifier.sendGif insert failed: $e');
      _pendingOptimisticIds.remove(msgId);
      if (mounted) {
        final withoutFailed = state.messages.where((m) => m.id != msgId).toList();
        state = state.copyWith(messages: withoutFailed, error: 'Failed to send GIF');
      }
    }
  }

  /// Tier 2 / Document attachments — send a document message.
  ///
  /// The [documentUrl] is the storage URL of the uploaded file. The
  /// [fileName] is stored in content for the bubble preview + inbox.
  /// The [fileSize] (bytes) is optional — used for the inbox preview
  /// ("Document · 1.2 MB").
  Future<void> sendDocument({
    required String documentUrl,
    required String fileName,
    int? fileSize,
    String? replyToId,
  }) async {
    final client = _client;
    final myUserId = _currentUserId;
    if (client == null || myUserId == null) return;

    final now = DateTime.now();
    final msgId = _generateId();
    final senderName = _currentUserName;

    final optimistic = ChatMessage(
      id: msgId,
      senderId: myUserId,
      senderName: senderName,
      content: fileName,
      messageType: MessageType.document,
      timestamp: now,
      isRead: false,
      senderInitials: _initialsFromName(senderName),
      mediaUrl: documentUrl,
      messageSubType: 'document',
    );

    _pendingOptimisticIds.add(msgId);
    if (mounted) {
      state = state.copyWith(
        messages: [optimistic, ...state.messages],
        clearReplyTo: true,
      );
    }

    try {
      await client.from('ChatMessage').insert(optimistic.toJson(familyId: familyId));
    } catch (e) {
      debugPrint('⚠️ ChatNotifier.sendDocument insert failed: $e');
      _pendingOptimisticIds.remove(msgId);
      if (mounted) {
        final withoutFailed = state.messages.where((m) => m.id != msgId).toList();
        state = state.copyWith(messages: withoutFailed, error: 'Failed to send document');
      }
    }
  }

  /// Tier 2 / Live location sharing — send a location message.
  ///
  /// The [lat] / [lng] + optional [label] are stored in content as a
  /// JSON string (parsed by the bubble renderer). No mediaUrl — the
  /// card opens the system maps app at the shared coordinates.
  Future<void> sendLocation({
    required double lat,
    required double lng,
    String? label,
    String? replyToId,
  }) async {
    final client = _client;
    final myUserId = _currentUserId;
    if (client == null || myUserId == null) return;

    final now = DateTime.now();
    final msgId = _generateId();
    final senderName = _currentUserName;

    final contentJson = jsonEncode({
      'lat': lat,
      'lng': lng,
      'label': label ?? 'Shared location',
    });

    final optimistic = ChatMessage(
      id: msgId,
      senderId: myUserId,
      senderName: senderName,
      content: contentJson,
      messageType: MessageType.location,
      timestamp: now,
      isRead: false,
      senderInitials: _initialsFromName(senderName),
      messageSubType: 'location',
    );

    _pendingOptimisticIds.add(msgId);
    if (mounted) {
      state = state.copyWith(
        messages: [optimistic, ...state.messages],
        clearReplyTo: true,
      );
    }

    try {
      await client.from('ChatMessage').insert(optimistic.toJson(familyId: familyId));
    } catch (e) {
      debugPrint('⚠️ ChatNotifier.sendLocation insert failed: $e');
      _pendingOptimisticIds.remove(msgId);
      if (mounted) {
        final withoutFailed = state.messages.where((m) => m.id != msgId).toList();
        state = state.copyWith(messages: withoutFailed, error: 'Failed to share location');
      }
    }
  }

  /// Phase 22 / Task 5 — Post a new poll to the family chat.
  ///
  /// Calls the `fn_send_poll` RPC which inserts a ChatMessage row with
  /// `messageType = 'poll'`, `pollQuestion`, `pollOptions` (JSONB array
  /// of 2–6 strings), and zeroed `pollVoteCounts` + empty `pollVoterIds`.
  ///
  /// Optimistic insert uses a client-generated ID; on RPC success the
  /// returned messageId replaces it so the realtime INSERT (using the
  /// RPC-generated ID) doesn't double-render. On RPC failure we drop
  /// the optimistic card.
  ///
  /// [options] must contain 2–6 non-empty strings. The RPC re-validates.
  Future<void> sendPoll({
    required String question,
    required List<String> options,
    String? replyToId,
  }) async {
    final trimmedQuestion = question.trim();
    if (trimmedQuestion.isEmpty) return;
    if (options.length < 2 || options.length > 6) return;

    final client = _client;
    final myUserId = _currentUserId;
    if (client == null || myUserId == null) {
      if (mounted) state = state.copyWith(error: 'Not signed in');
      return;
    }

    final now = DateTime.now();
    final optimisticId = _generateId();
    final senderName = _currentUserName;

    final optimistic = ChatMessage(
      id: optimisticId,
      senderId: myUserId,
      senderName: senderName,
      content: trimmedQuestion,
      messageType: MessageType.poll,
      timestamp: now,
      isRead: false,
      replyToId: replyToId,
      senderInitials: _initialsFromName(senderName),
      messageSubType: 'poll',
      pollQuestion: trimmedQuestion,
      pollOptions: options,
      pollVoteCounts: List.filled(options.length, 0),
      pollVoterIds: const [],
      pollCreatedAt: now,
    );

    _pendingOptimisticIds.add(optimisticId);
    if (mounted) {
      state = state.copyWith(
        messages: [optimistic, ...state.messages],
        clearReplyTo: true,
      );
    }

    try {
      final response = await client.rpc(
        'fn_send_poll',
        params: {
          'p_family_id': familyId,
          'p_question': trimmedQuestion,
          'p_options': options,
          'p_reply_to_id': replyToId,
        },
      ).timeout(const Duration(seconds: 10));

      final result = response as Map<String, dynamic>?;
      final success = result?['success'] as bool? ?? false;
      if (!success) throw Exception(result?['error']?.toString() ?? 'rpc_failed');

      final realId = result?['messageId'] as String?;
      if (realId != null && realId != optimisticId) {
        // The RPC generated its own ID. Replace the optimistic message
        // with one carrying the real ID so realtime de-dup works.
        _pendingOptimisticIds.remove(optimisticId);
        final withRealId = optimistic.copyWith();
        // copyWith doesn't have an `id` param; just rebuild.
        final replaced = ChatMessage(
          id: realId,
          senderId: optimistic.senderId,
          senderName: optimistic.senderName,
          content: optimistic.content,
          messageType: optimistic.messageType,
          timestamp: optimistic.timestamp,
          isRead: optimistic.isRead,
          replyToId: optimistic.replyToId,
          replyToContent: optimistic.replyToContent,
          replyToSenderName: optimistic.replyToSenderName,
          senderInitials: optimistic.senderInitials,
          messageSubType: optimistic.messageSubType,
          pollQuestion: optimistic.pollQuestion,
          pollOptions: optimistic.pollOptions,
          pollVoteCounts: optimistic.pollVoteCounts,
          pollVoterIds: optimistic.pollVoterIds,
          pollCreatedAt: optimistic.pollCreatedAt,
        );
        _pendingOptimisticIds.add(realId);
        if (mounted) {
          final swapped = state.messages
              .where((m) => m.id != optimisticId)
              .toList();
          state = state.copyWith(messages: [replaced, ...swapped]);
        }
      }
    } catch (e) {
      debugPrint('⚠️ ChatNotifier.sendPoll RPC failed: $e');
      _pendingOptimisticIds.remove(optimisticId);
      if (mounted) {
        final withoutFailed =
            state.messages.where((m) => m.id != optimisticId).toList();
        state = state.copyWith(
          messages: withoutFailed,
          error: 'Failed to post poll',
        );
      }
    }
  }

  /// Phase 22 / Task 5 — Cast a vote on a poll.
  ///
  /// Calls `fn_vote_poll` which inserts a ChatPollVote row (UNIQUE on
  /// messageId+userId prevents double voting), bumps `pollVoteCounts`
  /// on the ChatMessage row, and appends to `pollVoterIds`. The realtime
  /// UPDATE propagates the new counts + voter IDs to every family
  /// member's open chat — live.
  ///
  /// Returns the option index the user voted for (either the one they
  /// just chose or, if they had already voted, their previously-chosen
  /// option). Returns null on auth / not-in-family / not-a-poll errors.
  Future<int?> votePoll(String messageId, int optionIndex) async {
    final client = _client;
    final myUserId = _currentUserId;
    if (client == null || myUserId == null) return null;

    try {
      final response = await client.rpc(
        'fn_vote_poll',
        params: {
          'p_message_id': messageId,
          'p_option_index': optionIndex,
        },
      ).timeout(const Duration(seconds: 8));

      final result = response as Map<String, dynamic>?;
      final success = result?['success'] as bool? ?? false;

      // 'already_voted' is returned with the previously-chosen option
      // index — surface that so the UI can show "you already voted
      // for X" without an extra query.
      if (!success && result?['error'] == 'already_voted') {
        return (result?['optionIndex'] as num?)?.toInt();
      }
      if (!success) {
        debugPrint('⚠️ ChatNotifier.votePoll RPC failed: ${result?['error']}');
        return null;
      }

      // The RPC's response carries the new pollVoteCounts + pollVoterIds
      // — apply them to the local state immediately so the UI updates
      // without waiting for the realtime round-trip.
      final newCounts = result?['pollVoteCounts'];
      final newVoters = result?['pollVoterIds'];
      if (mounted &&
          (newCounts is List || newVoters is List)) {
        final updated = state.messages.map((m) {
          if (m.id != messageId) return m;
          return m.copyWith(
            pollVoteCounts: newCounts is List
                ? newCounts.map((e) {
                    if (e is int) return e;
                    if (e is num) return e.toInt();
                    return 0;
                  }).toList()
                : m.pollVoteCounts,
            pollVoterIds: newVoters is List
                ? newVoters.whereType<Map<String, dynamic>>().toList()
                : m.pollVoterIds,
          );
        }).toList();
        state = state.copyWith(messages: updated);
      }

      return optionIndex;
    } catch (e) {
      debugPrint('⚠️ ChatNotifier.votePoll error: $e');
      return null;
    }
  }

  /// Send a persistent game-invite card to the family chat thread.
  ///
  /// Called by InviteFamilySheet alongside each `game_invites` insert +
  /// Socket.IO `game:invite:send`, so the invite is ALSO visible as a
  /// persistent card in the chat thread. The socket popup only reaches
  /// members who are online right now; this card is the second, durable
  /// surface for the same invite (one card per invite action — it
  /// represents the room as a whole, not one card per recipient).
  ///
  /// The card starts at `gameInviteStatus='pending'` with the room's
  /// current player count. Live updates (joins / game start / finish) are
  /// pushed onto the ChatMessage row by `syncGameInviteChatCards()` in
  /// lib/features/games/shared/data/game_invite_chat_sync.dart; this
  /// notifier's realtime UPDATE subscription then refreshes every open
  /// chat UI automatically.
  ///
  /// Failures are intentionally quiet (debugPrint + remove the optimistic
  /// card): the chat card is additive and must never surface a chat error
  /// banner or block the actual game invite that triggered it.
  Future<void> sendGameInvite({
    required String gameType,
    required String gameId,
    required String roomCode,
    required int maxPlayers,
    required int currentPlayers,
    String? content,
  }) async {
    final client = _client;
    final myUserId = _currentUserId;
    if (client == null || myUserId == null) {
      if (mounted) state = state.copyWith(error: 'Not signed in');
      return;
    }

    final senderName = _currentUserName;
    final msgId = _generateId();
    final now = DateTime.now();
    final displayName =
        GameTypeX.fromRouteSegment(gameType)?.displayName ?? gameType;

    final optimistic = ChatMessage(
      id: msgId,
      senderId: myUserId,
      senderName: senderName,
      content: content ?? '$senderName started a $displayName game',
      messageType: MessageType.gameInvite,
      timestamp: now,
      isRead: false,
      senderInitials: _initialsFromName(senderName),
      gameType: gameType,
      gameId: gameId,
      roomCode: roomCode,
      gameMaxPlayers: maxPlayers,
      gameCurrentPlayers: currentPlayers,
      gameInviteStatus: 'pending',
    );

    // Track for echo de-dup so the realtime INSERT doesn't double-render.
    _pendingOptimisticIds.add(msgId);
    final updated = [optimistic, ...state.messages];
    if (mounted) state = state.copyWith(messages: updated);

    try {
      await client.from('ChatMessage').insert(optimistic.toJson(
        familyId: familyId,
      ));
    } catch (e) {
      debugPrint('⚠️ ChatNotifier.sendGameInvite insert failed: $e');
      _pendingOptimisticIds.remove(msgId);
      if (mounted) {
        final withoutFailed =
            state.messages.where((m) => m.id != msgId).toList();
        state = state.copyWith(messages: withoutFailed);
      }
    }
  }

  /// Toggle an emoji reaction on a message. Optimistic update + Supabase
  /// upsert. Idempotent — if the user already has that reaction, we
  /// DELETE it; otherwise we INSERT it.
  Future<void> toggleReaction(String messageId, String emoji) async {
    final client = _client;
    final myUserId = _currentUserId;
    if (client == null || myUserId == null) return;

    // Find the message + check existing reaction.
    final msg = state.messages.firstWhere(
      (m) => m.id == messageId,
      orElse: () => state.messages.first,
    );
    final existingIdx = msg.reactions.indexWhere(
      (r) => r.emoji == emoji && r.userId == myUserId,
    );
    final isAdding = existingIdx < 0;

    // Optimistic update.
    final updated = state.messages.map((m) {
      if (m.id != messageId) return m;
      final reactions = List<MessageReaction>.from(m.reactions);
      if (isAdding) {
        reactions.add(MessageReaction(emoji: emoji, userId: myUserId));
      } else {
        reactions.removeWhere(
          (r) => r.emoji == emoji && r.userId == myUserId,
        );
      }
      return m.copyWith(reactions: reactions);
    }).toList();
    state = state.copyWith(messages: updated);

    // Persist to Supabase.
    try {
      if (isAdding) {
        await client.from('ChatMessageReaction').insert({
          'id': 'cr_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}_${Random().nextInt(1 << 30).toRadixString(36)}',
          'messageId': messageId,
          'userId': myUserId,
          'emoji': emoji,
        });
      } else {
        await client
            .from('ChatMessageReaction')
            .delete()
            .eq('messageId', messageId)
            .eq('userId', myUserId)
            .eq('emoji', emoji);
      }
    } catch (e) {
      debugPrint('⚠️ ChatNotifier.toggleReaction failed: $e');
      // Revert on failure.
      final reverted = state.messages.map((m) {
        if (m.id != messageId) return m;
        final reactions = List<MessageReaction>.from(m.reactions);
        if (isAdding) {
          reactions.removeWhere(
            (r) => r.emoji == emoji && r.userId == myUserId,
          );
        } else {
          reactions.add(MessageReaction(emoji: emoji, userId: myUserId));
        }
        return m.copyWith(reactions: reactions);
      }).toList();
      if (mounted) {
        state = state.copyWith(messages: reverted);
      }
    }
  }

  /// Mark a single message as read (inserts a ChatReadReceipt).
  Future<void> markAsRead(String messageId) async {
    final client = _client;
    final myUserId = _currentUserId;
    if (client == null || myUserId == null) return;
    await _markSingleAsRead(messageId, myUserId);
  }

  Future<void> _markSingleAsRead(String messageId, String userId) async {
    final client = _client;
    if (client == null) return;
    try {
      await client.from('ChatReadReceipt').insert({
        'id': 'crr_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}_${Random().nextInt(1 << 30).toRadixString(36)}',
        'messageId': messageId,
        'userId': userId,
      });
      // The isRead flip on ChatMessage happens via the trigger on
      // ChatReadReceipt, and we'll see it via realtime UPDATE.
    } on PostgrestException catch (e) {
      // 23505 = unique_violation — already read, ignore.
      if (e.code != '23505') {
        debugPrint('⚠️ ChatNotifier._markSingleAsRead error: $e');
      }
    } catch (e) {
      debugPrint('⚠️ ChatNotifier._markSingleAsRead error: $e');
    }
  }

  /// Manually refresh messages from Supabase (Phase 13).
  ///
  /// Called after edit / delete / star / pin operations so the local
  /// state reflects the server-side changes. The realtime UPDATE event
  /// should fire and update state automatically, but this is a safety
  /// net for cases where the realtime payload doesn't include all
  /// updated fields.
  Future<void> refreshMessages() async {
    await _loadMessages();
  }

  /// Mark all messages as read. Called when the chat screen is opened.
  /// Bulk-inserts ChatReadReceipt rows for all messages not sent by me
  /// that don't already have a receipt from me.
  Future<void> markAllRead() async {
    final client = _client;
    final myUserId = _currentUserId;
    if (client == null || myUserId == null) return;
    if (!_initialLoadDone) return;

    // Find messages not sent by me that aren't yet marked read.
    final unread = state.messages
        .where((m) => m.senderId != myUserId && !m.isRead)
        .toList();
    if (unread.isEmpty) return;

    // Optimistic: mark all as read locally.
    final optimistic = state.messages.map((m) {
      if (m.senderId == myUserId || m.isRead) return m;
      return m.copyWith(isRead: true);
    }).toList();
    state = state.copyWith(messages: optimistic);

    // Bulk-insert receipts. Use a single INSERT with multiple rows.
    // Ignore 23505 (already-read) errors.
    try {
      final rows = unread.map((m) {
        return {
          'id': 'crr_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}_${Random().nextInt(1 << 30).toRadixString(36)}',
          'messageId': m.id,
          'userId': myUserId,
        };
      }).toList();
      await client.from('ChatReadReceipt').insert(rows);
    } on PostgrestException catch (e) {
      if (e.code != '23505') {
        debugPrint('⚠️ ChatNotifier.markAllRead error: $e');
      }
    } catch (e) {
      debugPrint('⚠️ ChatNotifier.markAllRead error: $e');
    }
  }

  /// Mark all unread messages (not sent by me) as read. Called after
  /// the initial load completes — ensures the chat opens with
  /// everything read.
  Future<void> _markUnreadAsRead() async {
    await markAllRead();
  }

  /// Simulate typing indicator. (Disabled in production — would broadcast
  /// via a Supabase Realtime Broadcast channel. Kept as a no-op so the
  /// UI doesn't crash if it calls this method.)
  void simulateTyping() {
    // No-op for now. Could be implemented later by broadcasting a
    // 'typing' event on the chat:$familyId channel.
  }

  /// Reload everything (used on reconnect / pull-to-refresh).
  Future<void> reload() async {
    state = state.copyWith(isLoading: true, clearError: true);
    await _loadMembers();
    await _loadMessages();
    // Re-subscribe in case the channel was dropped.
    _subscribeToRealtime();
  }

  // ── Lifecycle ────────────────────────────────────────────────────

  @override
  void dispose() {
    _channel?.unsubscribe();
    _channel = null;
    _membersSub?.cancel();
    // v5.2: Cancel the family member listener to prevent leaks.
    _memberListListener?.close();
    _memberListListener = null;
    // Tier 1 / Last Seen — mark the user as offline when the chat
    // notifier disposes (which happens when the chat screen closes).
    // Other family members will then see "last seen X ago" instead of
    // "online". Best-effort — the RPC fires-and-forgets; if the user
    // force-kills the app, the row stays "online" until the next
    // heartbeat / app open updates it. (A proper app-lifecycle
    // observer would catch force-kill; for v1 the chat-screen-close
    // trigger covers the common case.)
    ref.read(lastSeenProvider.notifier).updateMyPresence(false);
    super.dispose();
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Provider
// ═══════════════════════════════════════════════════════════════════════

/// Family chat provider — parameterized by family ID.
final chatProvider =
    StateNotifierProvider.family<ChatNotifier, ChatState, String>(
      (ref, familyId) => ChatNotifier(familyId: familyId, ref: ref),
    );

/// Convenience: online member count for a family chat.
final chatOnlineCountProvider = Provider.family<int, String>((ref, familyId) {
  return ref.watch(chatProvider(familyId)).onlineCount;
});

/// Convenience: the current user's ID for chat (so the UI can compare
/// message.senderId against this instead of hard-coding 'user_me').
final chatCurrentUserIdProvider = Provider<String?>((ref) {
  final client = ref.watch(supabaseProvider);
  return client?.auth.currentUser?.id ?? client?.auth.currentSession?.user.id;
});

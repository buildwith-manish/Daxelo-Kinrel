// lib/features/chat/data/models/chat_state.dart
//
// Extracted from lib/features/chat/providers/chat_provider.dart (Phase 0
// refactor — zero behavior change). Re-exported by chat_provider.dart so
// no existing import changes.

import 'chat_message.dart';
import 'online_member.dart';

/// Load status of ONE conversation scope (family-wide chat, a group, or a
/// direct chat). The UI must only show the "say hello / first message"
/// empty state when a scope is [loaded] AND has zero messages — never while
/// it is still [loading] or after a failed fetch ([error]).
enum ThreadStatus { loading, loaded, error }

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
    this.hasMoreMessages = true,
    this.isLoadingMoreMessages = false,
    this.unreadDividerMessageId,
    this.unreadDividerCount = 0,
    this.threadStatus = const {},
    this.threadHasMore = const {},
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

  /// Whether there are more (older) messages to load via scroll-up
  /// pagination. Defaults to true; set to false when a loadOlder
  /// query returns fewer than the page size (200).
  final bool hasMoreMessages;

  /// Whether an older-messages fetch is in progress (shows a skeleton
  /// at the top of the message list).
  final bool isLoadingMoreMessages;

  /// Kin Thread / PR2 Task 3 — id of the FIRST unread message captured
  /// once, BEFORE the messages are marked read on chat open. The
  /// unread divider pill renders above this message. System rows
  /// (join notices) never start or count toward the divider.
  final String? unreadDividerMessageId;

  /// Kin Thread / PR2 Task 3 — unread message count captured at the
  /// same moment as [unreadDividerMessageId] (excludes system rows).
  final int unreadDividerCount;

  /// Per-scope load status. Key = groupId, or ChatNotifier.kFamilyScope for
  /// the family-wide chat.
  final Map<String, ThreadStatus> threadStatus;

  /// Per-scope "older messages exist" flag (same keys as [threadStatus]).
  final Map<String, bool> threadHasMore;

  /// Number of online members.
  int get onlineCount => members.where((m) => m.isOnline).length;

  /// Total members in the chat.
  int get totalMembers => members.length;

  ChatState copyWith({
    List<ChatMessage>? messages,
    List<OnlineMember>? members,
    bool? isTyping,
    String? typingUserName,
    bool clearTypingUserName = false,
    ChatMessage? replyToMessage,
    bool? isLoading,
    bool clearReplyTo = false,
    String? error,
    bool clearError = false,
    bool? hasMoreMessages,
    bool? isLoadingMoreMessages,
    String? unreadDividerMessageId,
    int? unreadDividerCount,
    Map<String, ThreadStatus>? threadStatus,
    Map<String, bool>? threadHasMore,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      members: members ?? this.members,
      isTyping: isTyping ?? this.isTyping,
      typingUserName: clearTypingUserName
          ? null
          : (typingUserName ?? this.typingUserName),
      replyToMessage: clearReplyTo
          ? null
          : (replyToMessage ?? this.replyToMessage),
      // BUGFIX: this used to default to `false`, so ANY copyWith that did not
      // pass isLoading (members loaded, typing, realtime...) silently ended
      // the loading state and flashed the empty "first message" screen.
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      hasMoreMessages: hasMoreMessages ?? this.hasMoreMessages,
      isLoadingMoreMessages: isLoadingMoreMessages ?? this.isLoadingMoreMessages,
      unreadDividerMessageId:
          unreadDividerMessageId ?? this.unreadDividerMessageId,
      unreadDividerCount: unreadDividerCount ?? this.unreadDividerCount,
      threadStatus: threadStatus ?? this.threadStatus,
      threadHasMore: threadHasMore ?? this.threadHasMore,
    );
  }
}

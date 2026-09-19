// lib/features/chat/providers/chat_socket_engagement_provider.dart
//
// DAXELO KINREL — Pack 13 Chat Engagement (Socket.IO bridge)
//
// Bridges the chat:* Socket.IO events from the NestJS ChatGateway to
// Riverpod state, so the Flutter UI can react instantly to:
//   • typing indicators ("User is typing...")
//   • read receipts (double-tick → blue)
//   • reaction echoes (chips under messages)
//   • streak updates (flame count in header)
//   • presence (green dot / "Active now")
//
// This provider is ADDITIVE to the existing Supabase-Realtime-based
// chat_provider.dart — the existing flow still handles message persistence
// and initial load. This layer adds sub-second engagement signals that
// would otherwise require a Supabase round-trip.
//
// Auto-clears typing indicators after 3 seconds of no new events (matches
// the server-side auto-clear in chat.gateway.ts).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/socket_service.dart';
import '../../../core/services/supabase_service.dart';

/// A single user's presence status.
class UserPresence {
  const UserPresence({
    required this.userId,
    required this.isOnline,
    this.lastSeenAt,
  });

  final String userId;
  final bool isOnline;
  final DateTime? lastSeenAt;

  /// Human-readable "last seen" label. Returns "Active now" if online,
  /// otherwise "Last seen 5m ago" / "Last seen 2h ago" / "Last seen 3d ago".
  String get lastSeenLabel {
    if (isOnline) return 'Active now';
    if (lastSeenAt == null) return 'Offline';
    final diff = DateTime.now().difference(lastSeenAt!);
    if (diff.inSeconds < 60) return 'Last seen just now';
    if (diff.inMinutes < 60) return 'Last seen ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Last seen ${diff.inHours}h ago';
    return 'Last seen ${diff.inDays}d ago';
  }

  UserPresence copyWith({bool? isOnline, DateTime? lastSeenAt}) {
    return UserPresence(
      userId: userId,
      isOnline: isOnline ?? this.isOnline,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }
}

/// Immutable snapshot of the engagement state for one family chat.
class ChatEngagementState {
  const ChatEngagementState({
    this.typingUserIds = const {},
    this.typingUserNames = const {},
    this.readMessageIds = const {},
    this.deliveredMessageIds = const {},
    this.reactionCounts = const {},
    this.streak = 0,
    this.longestStreak = 0,
    this.presence = const {},
  });

  /// Set of userIds currently typing (excluding self — filtered in provider).
  final Set<String> typingUserIds;

  /// Map of userId → display name, for typing users.
  final Map<String, String> typingUserNames;

  /// Set of messageIds that have been read by someone (for the double-tick).
  final Set<String> readMessageIds;

  /// Feature 1: Set of messageIds that have been delivered to at least
  /// one recipient's device (for the double-tick → grey transition).
  /// A message is "delivered" when a recipient's socket confirms receipt
  /// via 'chat:messageDelivered'. Cleared when the message is read.
  final Set<String> deliveredMessageIds;

  /// Map of messageId → list of {emoji, count, userIds}.
  final Map<String, List<Map<String, dynamic>>> reactionCounts;

  /// Current chat streak (consecutive days). 0 if no streak tracked yet.
  final int streak;

  /// Longest streak ever achieved in this chat.
  final int longestStreak;

  /// Map of userId → presence. Updated by 'presenceUpdate' events.
  final Map<String, UserPresence> presence;

  /// True if at least one other user is typing.
  bool get isSomeoneTyping => typingUserIds.isNotEmpty;

  /// Comma-separated label for the typing indicator, e.g. "Riya, Manish".
  /// Returns empty string if no one is typing.
  String get typingLabel {
    final names = typingUserNames.values.take(2).toList();
    if (names.isEmpty) return '';
    if (names.length == 1) return '${names.first} is typing';
    if (names.length == 2) return '${names.first} and ${names.last} are typing';
    return '${names.first} and others are typing';
  }

  ChatEngagementState copyWith({
    Set<String>? typingUserIds,
    Map<String, String>? typingUserNames,
    Set<String>? readMessageIds,
    Set<String>? deliveredMessageIds,
    Map<String, List<Map<String, dynamic>>>? reactionCounts,
    int? streak,
    int? longestStreak,
    Map<String, UserPresence>? presence,
  }) {
    return ChatEngagementState(
      typingUserIds: typingUserIds ?? this.typingUserIds,
      typingUserNames: typingUserNames ?? this.typingUserNames,
      readMessageIds: readMessageIds ?? this.readMessageIds,
      deliveredMessageIds: deliveredMessageIds ?? this.deliveredMessageIds,
      reactionCounts: reactionCounts ?? this.reactionCounts,
      streak: streak ?? this.streak,
      longestStreak: longestStreak ?? this.longestStreak,
      presence: presence ?? this.presence,
    );
  }
}

/// StateNotifier that subscribes to the SocketService chat:* events and
/// exposes them as Riverpod state. One instance per familyId — create
/// via [chatEngagementProvider] family.
class ChatEngagementNotifier extends StateNotifier<ChatEngagementState> {
  ChatEngagementNotifier(this._socket, this._familyId, this._currentUserId)
      : super(const ChatEngagementState()) {
    _setupSubscriptions();
    // Join the family chat room so the server starts sending us chat:* events.
    _socket.joinFamilyChatRoom(familyId: _familyId);
  }

  final SocketService _socket;
  final String _familyId;
  final String _currentUserId;

  /// Timers per typing user — auto-clear after 3 seconds of no new events.
  final Map<String, Timer> _typingTimers = {};

  /// Unsubscribe callbacks from SocketService.
  final List<VoidCallback> _unsubscribers = [];

  void _setupSubscriptions() {
    // Typing indicator — when 'chat:userTyping' fires with isTyping=true,
    // add the user to the typing set and set a 3-second auto-clear timer.
    // If we get another typing event from the same user before 3s elapses,
    // the timer is reset (extends the "User is typing..." display).
    _unsubscribers.add(
      _socket.onChatTyping((data) {
        final familyId = data['familyId'] as String?;
        if (familyId != _familyId) return;
        final userId = data['userId'] as String?;
        if (userId == null || userId == _currentUserId) return;
        final userName = data['userName'] as String? ?? 'Someone';
        final isTyping = data['isTyping'] as bool? ?? false;

        if (isTyping) {
          // Cancel any existing timer for this user, then set a fresh 3s timer.
          _typingTimers[userId]?.cancel();
          _typingTimers[userId] = Timer(const Duration(seconds: 3), () {
            _removeTypingUser(userId);
          });

          final ids = Set<String>.from(state.typingUserIds)..add(userId);
          final names = Map<String, String>.from(state.typingUserNames)
            ..[userId] = userName;
          state = state.copyWith(typingUserIds: ids, typingUserNames: names);
        } else {
          _removeTypingUser(userId);
        }
      }),
    );

    // Read receipt — mark the listed messageIds as read.
    _unsubscribers.add(
      _socket.onChatReadReceipt((data) {
        final familyId = data['familyId'] as String?;
        if (familyId != _familyId) return;
        final messageIds = (data['messageIds'] as List?)
            ?.map((e) => e.toString())
            .toSet() ??
            <String>{};
        if (messageIds.isEmpty) return;
        final readSet = Set<String>.from(state.readMessageIds)
          ..addAll(messageIds);
        // Once read, remove from the delivered set (read supersedes delivered).
        final deliveredSet = Set<String>.from(state.deliveredMessageIds)
          ..removeAll(messageIds);
        state = state.copyWith(
          readMessageIds: readSet,
          deliveredMessageIds: deliveredSet,
        );
      }),
    );

    // Feature 1: delivery confirmation. When a recipient's socket
    // confirms receipt of a message we sent, add it to the delivered
    // set so the bubble's checkmark flips from single-tick (sent) to
    // double-tick-grey (delivered). The chat_provider listens to this
    // state too and updates the ChatMessage.messageStatus field.
    _unsubscribers.add(
      _socket.onChatMessageDelivered((data) {
        final familyId = data['familyId'] as String?;
        if (familyId != _familyId) return;
        final messageId = data['messageId'] as String?;
        if (messageId == null) return;
        // Don't add to delivered if already read (read > delivered).
        if (state.readMessageIds.contains(messageId)) return;
        final delivered = Set<String>.from(state.deliveredMessageIds)
          ..add(messageId);
        state = state.copyWith(deliveredMessageIds: delivered);
      }),
    );

    // Reaction updates — replace the reactionCounts for the affected message.
    _unsubscribers.add(
      _socket.onChatReaction((data) {
        final messageId = data['messageId'] as String?;
        if (messageId == null) return;
        final counts = data['counts'] as List?;
        if (counts == null) return;
        final countsList = counts
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        final newCounts = Map<String, List<Map<String, dynamic>>>.from(
          state.reactionCounts,
        );
        newCounts[messageId] = countsList;
        state = state.copyWith(reactionCounts: newCounts);
      }),
    );

    // Streak updates — replace streak + longestStreak.
    _unsubscribers.add(
      _socket.onChatStreak((data) {
        final chatId = data['chatId'] as String?;
        if (chatId != _familyId) return;
        final current = data['currentStreak'] as int? ?? 0;
        final longest = data['longestStreak'] as int? ?? current;
        state = state.copyWith(streak: current, longestStreak: longest);
      }),
    );

    // Presence updates — update the presence map for the user.
    _unsubscribers.add(
      _socket.onPresenceUpdate((data) {
        final userId = data['userId'] as String?;
        if (userId == null) return;
        final status = data['status'] as String? ?? 'offline';
        final lastSeenRaw = data['lastSeenAt'] as String?;
        final lastSeen = lastSeenRaw != null ? DateTime.tryParse(lastSeenRaw) : null;
        final newPresence = UserPresence(
          userId: userId,
          isOnline: status == 'online',
          lastSeenAt: lastSeen,
        );
        final newMap = Map<String, UserPresence>.from(state.presence)
          ..[userId] = newPresence;
        state = state.copyWith(presence: newMap);
      }),
    );
  }

  void _removeTypingUser(String userId) {
    _typingTimers[userId]?.cancel();
    _typingTimers.remove(userId);
    final ids = Set<String>.from(state.typingUserIds)..remove(userId);
    final names = Map<String, String>.from(state.typingUserNames)..remove(userId);
    state = state.copyWith(typingUserIds: ids, typingUserNames: names);
  }

  /// Emit a typing indicator to the server. The server auto-clears after 3s
  /// of inactivity, so calling this every keystroke is fine (it refreshes
  /// the server's timer).
  void sendTyping({required String userName, required bool isTyping}) {
    _socket.emitChatTyping(familyId: _familyId, isTyping: isTyping, userName: userName);
  }

  /// Mark all unread messages in the family as read by this user.
  void markAllRead() {
    _socket.emitMarkAsRead(familyId: _familyId);
  }

  /// Mark a single message as read.
  void markMessageRead(String messageId) {
    _socket.emitMarkAsRead(familyId: _familyId, messageId: messageId);
  }

  /// Feature 1: send a delivery confirmation back to the server when
  /// this client receives a message via 'chat:messageReceived'. The
  /// server forwards it to the sender so they see the double-tick.
  /// Called by the chat_provider's chat:messageReceived handler.
  void confirmDelivery(String messageId) {
    _socket.emitMessageDelivered(familyId: _familyId, messageId: messageId);
  }

  /// Add an emoji reaction to a message. Idempotent.
  void addReaction({required String messageId, required String emoji}) {
    _socket.emitAddReaction(
      familyId: _familyId,
      messageId: messageId,
      emoji: emoji,
    );
  }

  /// Remove an emoji reaction from a message.
  void removeReaction({required String messageId, required String emoji}) {
    _socket.emitRemoveReaction(
      familyId: _familyId,
      messageId: messageId,
      emoji: emoji,
    );
  }

  @override
  void dispose() {
    for (final t in _typingTimers.values) {
      t.cancel();
    }
    _typingTimers.clear();
    for (final unsub in _unsubscribers) {
      unsub();
    }
    _unsubscribers.clear();
    // Leave the family chat room on dispose.
    _socket.leaveFamilyChatRoom(familyId: _familyId);
    super.dispose();
  }
}

/// Family-scoped provider for chat engagement state. Watch this in the
/// chat_screen header (typing + streak + presence) and message_bubble
/// (read checkmarks + reaction counts).
///
/// Usage:
///   final engagement = ref.watch(chatEngagementProvider(familyId));
///   if (engagement.isSomeoneTyping) Text(engagement.typingLabel)
final chatEngagementProvider = StateNotifierProvider.family
    .autoDispose<ChatEngagementNotifier, ChatEngagementState, String>(
  (ref, familyId) {
    final socket = ref.watch(socketServiceProvider);
    // Read the current user's id from Supabase auth so the typing indicator
    // can filter out the user's own typing events.
    final client = ref.watch(supabaseProvider);
    final currentUserId = client?.auth.currentUser?.id ?? '';
    return ChatEngagementNotifier(socket, familyId, currentUserId);
  },
);

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
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';

// ═══════════════════════════════════════════════════════════════════════
// Models
// ═══════════════════════════════════════════════════════════════════════

/// Message type — drives the bubble content and layout.
enum MessageType { text, photo, voiceNote, familyEvent }

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

  /// Convenience: grouped reactions (emoji → count).
  Map<String, int> get groupedReactions {
    final map = <String, int>{};
    for (final r in reactions) {
      map[r.emoji] = (map[r.emoji] ?? 0) + 1;
    }
    return map;
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
  }) {
    return ChatMessage(
      id: id,
      senderId: senderId,
      senderName: senderName,
      content: content,
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
      durationSeconds: json['durationSeconds'] as int?,
      eventTitle: json['eventTitle'] as String?,
      eventDate: json['eventDate'] as String?,
      mediaUrl: json['mediaUrl'] as String?,
    );
  }

  static MessageType _parseMessageType(String? raw) {
    switch (raw) {
      case 'photo':
        return MessageType.photo;
      case 'voiceNote':
        return MessageType.voiceNote;
      case 'familyEvent':
        return MessageType.familyEvent;
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
      'eventTitle': eventTitle,
      'eventDate': eventDate,
      if (mediaUrl != null) 'mediaUrl': mediaUrl,
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

  // ── Initialization ───────────────────────────────────────────────

  Future<void> _init() async {
    await _loadMembers();
    await _loadMessages();
    _subscribeToRealtime();
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
    // v91: Real-time online status. The onPresenceSync callback fires
    // on initial sync and whenever the presence state changes (joins
    // and leaves). We use the payload directly to extract online user IDs.
    _channel!.onPresenceSync((RealtimePresenceSyncPayload payload) {
      final onlineIds = <String>{};
      // The payload has a 'joins' and 'leaves' field, but the simplest
      // approach is to mark all members as potentially online on sync.
      // The current user is always online in their own session.
      final myId = _currentUserId;
      if (myId != null) onlineIds.add(myId);
      // Extract user IDs from the joins payload if available.
      final joins = payload.joins;
      if (joins is Map) {
        for (final v in joins.values) {
          if (v is Map) {
            final metas = v['metas'];
            if (metas is List) {
              for (final m in metas) {
                if (m is Map) {
                  final uid = m['user_id'] as String?;
                  if (uid != null && uid.isNotEmpty) onlineIds.add(uid);
                }
              }
            }
          }
        }
      }
      if (!mounted) return;
      state = state.copyWith(
        members: state.members
            .map((m) => m.copyWith(isOnline: onlineIds.contains(m.id)))
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
  Future<void> sendMessage(String content, {String? replyToId}) async {
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

    final optimistic = ChatMessage(
      id: msgId,
      senderId: myUserId,
      senderName: senderName,
      content: caption ?? '',
      messageType: MessageType.photo,
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

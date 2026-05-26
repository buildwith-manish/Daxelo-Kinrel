// lib/features/chat/providers/chat_provider.dart
//
// DAXELO KINREL — Family Chat State Management
//
// Manages family group chat state using Riverpod StateNotifierProvider.
// Supports text, photo, voice note, and family event message types.
// Includes realistic Hinglish demo data for an Indian family chat.
//
// Features:
//   - Real-time messaging UI (WebSocket placeholder)
//   - Read receipts (double tick, orange for read)
//   - Typing indicator
//   - Reply to specific messages
//   - React to messages with emoji
//   - Online status per sender

import 'package:flutter_riverpod/flutter_riverpod.dart';

// ═══════════════════════════════════════════════════════════════════════
// Models
// ═══════════════════════════════════════════════════════════════════════

/// Message type — drives the bubble content and layout.
enum MessageType {
  text,
  photo,
  voiceNote,
  familyEvent,
}

/// A single emoji reaction on a message.
class MessageReaction {
  const MessageReaction({
    required this.emoji,
    required this.userId,
  });

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
  });

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
      isOnline: isOnline,
      senderInitials: senderInitials,
      durationSeconds: durationSeconds,
      eventTitle: eventTitle,
      eventDate: eventDate,
    );
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
  });

  /// All messages in the chat, sorted by timestamp.
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

  /// Number of online members.
  int get onlineCount =>
      members.where((m) => m.isOnline).length;

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
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      members: members ?? this.members,
      isTyping: isTyping ?? this.isTyping,
      typingUserName: typingUserName ?? this.typingUserName,
      replyToMessage: clearReplyTo ? null : (replyToMessage ?? this.replyToMessage),
      isLoading: isLoading,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Notifier
// ═══════════════════════════════════════════════════════════════════════

/// Current user ID (placeholder — would come from auth in production).
const _currentUserId = 'user_me';

class ChatNotifier extends StateNotifier<ChatState> {
  ChatNotifier({required this.familyId}) : super(const ChatState()) {
    _loadDemoData();
  }

  final String familyId;

  // ── Actions ──────────────────────────────────────────────────────

  /// Send a new text message.
  void sendMessage(String content, {String? replyToId}) {
    final now = DateTime.now();
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

    final message = ChatMessage(
      id: 'msg_${now.millisecondsSinceEpoch}',
      senderId: _currentUserId,
      senderName: 'You',
      content: content,
      messageType: MessageType.text,
      timestamp: now,
      isRead: false,
      replyToId: replyToId,
      replyToContent: replyContent,
      replyToSenderName: replySender,
    );

    final updated = [message, ...state.messages];
    state = state.copyWith(
      messages: updated,
      clearReplyTo: true,
    );
  }

  /// Set the message to reply to.
  void setReplyTo(ChatMessage? message) {
    state = state.copyWith(replyToMessage: message);
  }

  /// Clear the reply-to state.
  void clearReplyTo() {
    state = state.copyWith(clearReplyTo: true);
  }

  /// Toggle an emoji reaction on a message.
  void toggleReaction(String messageId, String emoji) {
    final updated = state.messages.map((m) {
      if (m.id != messageId) return m;

      final existingIndex = m.reactions.indexWhere(
        (r) => r.emoji == emoji && r.userId == _currentUserId,
      );

      List<MessageReaction> newReactions;
      if (existingIndex >= 0) {
        // Remove existing reaction
        newReactions = List.from(m.reactions)..removeAt(existingIndex);
      } else {
        // Add new reaction
        newReactions = List.from(m.reactions)
          ..add(MessageReaction(emoji: emoji, userId: _currentUserId));
      }

      return m.copyWith(reactions: newReactions);
    }).toList();

    state = state.copyWith(messages: updated);
  }

  /// Mark a message as read.
  void markAsRead(String messageId) {
    final updated = state.messages.map((m) {
      if (m.id == messageId) return m.copyWith(isRead: true);
      return m;
    }).toList();
    state = state.copyWith(messages: updated);
  }

  /// Mark all messages as read.
  void markAllRead() {
    final updated = state.messages.map((m) {
      return m.copyWith(isRead: true);
    }).toList();
    state = state.copyWith(messages: updated);
  }

  /// Simulate typing indicator.
  void simulateTyping() {
    state = state.copyWith(
      isTyping: true,
      typingUserName: 'Maa',
    );
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        state = state.copyWith(isTyping: false, typingUserName: null);
      }
    });
  }

  // ── Demo Data ────────────────────────────────────────────────────

  void _loadDemoData() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    const members = <OnlineMember>[
      OnlineMember(id: 'user_me', name: 'You', initials: 'YO', isOnline: true),
      OnlineMember(id: 'u_maa', name: 'Maa', initials: 'MA', isOnline: true),
      OnlineMember(id: 'u_papa', name: 'Papa', initials: 'PA', isOnline: true),
      OnlineMember(id: 'u_didi', name: 'Didi', initials: 'DI', isOnline: false),
      OnlineMember(id: 'u_bhaiya', name: 'Bhaiya', initials: 'BH', isOnline: true),
      OnlineMember(id: 'u_chachi', name: 'Chachi', initials: 'CH', isOnline: false),
      OnlineMember(id: 'u_nani', name: 'Nani', initials: 'NA', isOnline: false),
      OnlineMember(id: 'u_cousin_1', name: 'Rahul Bhaiya', initials: 'RB', isOnline: true),
    ];

    final messages = <ChatMessage>[
      // ── Yesterday's messages ─────────────────────────────────────
      ChatMessage(
        id: 'msg_001',
        senderId: 'u_papa',
        senderName: 'Papa',
        content: 'Sabko good evening! Kal Sharma ji ka dinner hai, sab yaad hai na?',
        messageType: MessageType.text,
        timestamp: yesterday.add(const Duration(hours: 19, minutes: 15)),
        isRead: true,
        isOnline: true,
        senderInitials: 'PA',
      ),
      ChatMessage(
        id: 'msg_002',
        senderId: 'u_maa',
        senderName: 'Maa',
        content: 'Haan yaad hai. Main kheer bana rahi hoon, aur kuch chahiye toh batao',
        messageType: MessageType.text,
        timestamp: yesterday.add(const Duration(hours: 19, minutes: 18)),
        isRead: true,
        isOnline: true,
        senderInitials: 'MA',
      ),
      ChatMessage(
        id: 'msg_003',
        senderId: 'u_chachi',
        senderName: 'Chachi',
        content: 'Main samose aur pakode le kar aa rahi hoon! 😋',
        messageType: MessageType.text,
        timestamp: yesterday.add(const Duration(hours: 19, minutes: 22)),
        isRead: true,
        isOnline: false,
        senderInitials: 'CH',
        reactions: [
          MessageReaction(emoji: '❤️', userId: 'u_maa'),
          MessageReaction(emoji: '😋', userId: 'u_bhaiya'),
        ],
      ),
      ChatMessage(
        id: 'msg_004',
        senderId: 'u_bhaiya',
        senderName: 'Bhaiya',
        content: 'Nice! Main cold drinks arrange kar dunga',
        messageType: MessageType.text,
        timestamp: yesterday.add(const Duration(hours: 19, minutes: 25)),
        isRead: true,
        isOnline: true,
        senderInitials: 'BH',
      ),
      ChatMessage(
        id: 'msg_005',
        senderId: 'u_didi',
        senderName: 'Didi',
        content: 'Guys main thoda late aaungi, office ka kaam hai. But I\'ll try to come by 8!',
        messageType: MessageType.text,
        timestamp: yesterday.add(const Duration(hours: 19, minutes: 30)),
        isRead: true,
        isOnline: false,
        senderInitials: 'DI',
        reactions: [
          MessageReaction(emoji: '👍', userId: 'u_papa'),
        ],
      ),
      ChatMessage(
        id: 'msg_006',
        senderId: 'u_papa',
        senderName: 'Papa',
        content: 'Koi baat nahi beta, jo bhi time pe aao. Pehle kaam khatam karo',
        messageType: MessageType.text,
        timestamp: yesterday.add(const Duration(hours: 19, minutes: 32)),
        isRead: true,
        isOnline: true,
        senderInitials: 'PA',
      ),

      // ── Today's messages ─────────────────────────────────────────
      ChatMessage(
        id: 'msg_007',
        senderId: 'u_maa',
        senderName: 'Maa',
        content: 'Good morning sabko! 🙏 Aaj subah mandir jana hai, kaun aa raha hai?',
        messageType: MessageType.text,
        timestamp: today.add(const Duration(hours: 6, minutes: 30)),
        isRead: true,
        isOnline: true,
        senderInitials: 'MA',
        reactions: [
          MessageReaction(emoji: '🙏', userId: 'u_papa'),
          MessageReaction(emoji: '🙏', userId: 'u_nani'),
        ],
      ),
      ChatMessage(
        id: 'msg_008',
        senderId: 'u_papa',
        senderName: 'Papa',
        content: 'Main chalunga. 7 baje nikalte hain?',
        messageType: MessageType.text,
        timestamp: today.add(const Duration(hours: 6, minutes: 35)),
        isRead: true,
        isOnline: true,
        senderInitials: 'PA',
      ),
      ChatMessage(
        id: 'msg_009',
        senderId: 'u_bhaiya',
        senderName: 'Bhaiya',
        content: 'Maa mujhe chhod do aaj, kal raat late soya tha 😴',
        messageType: MessageType.text,
        timestamp: today.add(const Duration(hours: 6, minutes: 40)),
        isRead: true,
        isOnline: true,
        senderInitials: 'BH',
        reactions: [
          MessageReaction(emoji: '😂', userId: 'u_didi'),
          MessageReaction( emoji: '😠', userId: 'u_maa'),
        ],
      ),
      ChatMessage(
        id: 'msg_010',
        senderId: 'u_nani',
        senderName: 'Nani',
        content: 'Beta, mandir jaana bahut acchi baat hai. Main bhi aati hoon!',
        messageType: MessageType.text,
        timestamp: today.add(const Duration(hours: 7, minutes: 5)),
        isRead: true,
        isOnline: false,
        senderInitials: 'NA',
      ),
      ChatMessage(
        id: 'msg_011',
        senderId: 'u_maa',
        senderName: 'Maa',
        content: 'Ji Nani! Aap aaiye, main aapko pick kar lungi 🚗',
        messageType: MessageType.text,
        timestamp: today.add(const Duration(hours: 7, minutes: 10)),
        isRead: true,
        isOnline: true,
        senderInitials: 'MA',
      ),

      // Mid-day conversation
      ChatMessage(
        id: 'msg_012',
        senderId: 'u_chachi',
        senderName: 'Chachi',
        content: 'Arey listen! Ramesh ki engagement final ho gayi — 14th ko! 🎉💍',
        messageType: MessageType.text,
        timestamp: today.add(const Duration(hours: 10, minutes: 15)),
        isRead: true,
        isOnline: false,
        senderInitials: 'CH',
        reactions: [
          MessageReaction(emoji: '🎉', userId: 'u_maa'),
          MessageReaction(emoji: '🎉', userId: 'u_papa'),
          MessageReaction(emoji: '❤️', userId: 'u_didi'),
          MessageReaction(emoji: '💍', userId: 'u_bhaiya'),
        ],
      ),
      ChatMessage(
        id: 'msg_013',
        senderId: 'u_papa',
        senderName: 'Papa',
        content: 'Bahut acchi khabar! Ladki wale kon hain?',
        messageType: MessageType.text,
        timestamp: today.add(const Duration(hours: 10, minutes: 20)),
        isRead: true,
        isOnline: true,
        senderInitials: 'PA',
      ),
      ChatMessage(
        id: 'msg_014',
        senderId: 'u_chachi',
        senderName: 'Chachi',
        content: 'Gupta ji ki beti — Priya. Meerut mein rehte hain. Bahut acche parivaar hain',
        messageType: MessageType.text,
        timestamp: today.add(const Duration(hours: 10, minutes: 22)),
        isRead: true,
        isOnline: false,
        senderInitials: 'CH',
      ),

      // Voice note placeholder
      ChatMessage(
        id: 'msg_015',
        senderId: 'u_nani',
        senderName: 'Nani',
        content: 'Voice note',
        messageType: MessageType.voiceNote,
        timestamp: today.add(const Duration(hours: 11, minutes: 0)),
        isRead: true,
        isOnline: false,
        senderInitials: 'NA',
        durationSeconds: 42,
      ),

      // Photo placeholder
      ChatMessage(
        id: 'msg_016',
        senderId: 'u_didi',
        senderName: 'Didi',
        content: 'Dekho Ramesh aur Priya ki photo! 📸',
        messageType: MessageType.photo,
        timestamp: today.add(const Duration(hours: 11, minutes: 30)),
        isRead: true,
        isOnline: false,
        senderInitials: 'DI',
        reactions: [
          MessageReaction(emoji: '❤️', userId: 'u_maa'),
          MessageReaction(emoji: '😍', userId: 'u_chachi'),
          MessageReaction(emoji: '❤️', userId: 'u_papa'),
        ],
      ),

      // Family event sharing
      ChatMessage(
        id: 'msg_017',
        senderId: 'u_papa',
        senderName: 'Papa',
        content: 'Engagement ceremony ki details share kar raha hoon',
        messageType: MessageType.familyEvent,
        timestamp: today.add(const Duration(hours: 12, minutes: 0)),
        isRead: true,
        isOnline: true,
        senderInitials: 'PA',
        eventTitle: 'Ramesh & Priya Engagement',
        eventDate: '14th March, 2025',
        reactions: [
          MessageReaction(emoji: '🎉', userId: 'u_maa'),
          MessageReaction(emoji: '🎉', userId: 'u_bhaiya'),
          MessageReaction(emoji: '👍', userId: 'u_didi'),
        ],
      ),

      // Reply message
      ChatMessage(
        id: 'msg_018',
        senderId: 'u_maa',
        senderName: 'Maa',
        content: 'Hum sab ja rahe hain! Mujhe shopping bhi karni hai 😄',
        messageType: MessageType.text,
        timestamp: today.add(const Duration(hours: 12, minutes: 5)),
        isRead: true,
        isOnline: true,
        senderInitials: 'MA',
        replyToId: 'msg_017',
        replyToContent: 'Engagement ceremony ki details share kar raha hoon',
        replyToSenderName: 'Papa',
      ),

      // Recent messages
      ChatMessage(
        id: 'msg_019',
        senderId: 'u_cousin_1',
        senderName: 'Rahul Bhaiya',
        content: 'Bhai log, aaj evening cricket khelni hai? Ground pe milte hain 5 baje 🏏',
        messageType: MessageType.text,
        timestamp: today.add(const Duration(hours: 14, minutes: 30)),
        isRead: true,
        isOnline: true,
        senderInitials: 'RB',
        reactions: [
          MessageReaction(emoji: '🏏', userId: 'u_bhaiya'),
        ],
      ),
      ChatMessage(
        id: 'msg_020',
        senderId: 'u_bhaiya',
        senderName: 'Bhaiya',
        content: 'Count me in! Main bat le kar aaunga 💪',
        messageType: MessageType.text,
        timestamp: today.add(const Duration(hours: 14, minutes: 35)),
        isRead: true,
        isOnline: true,
        senderInitials: 'BH',
        replyToId: 'msg_019',
        replyToContent: 'Bhai log, aaj evening cricket khelni hai? Ground pe milte hain 5 baje 🏏',
        replyToSenderName: 'Rahul Bhaiya',
      ),
      ChatMessage(
        id: 'msg_021',
        senderId: 'u_didi',
        senderName: 'Didi',
        content: 'Holi ke liye colour aur pichkari ka list bana do. Kal market jaana hai',
        messageType: MessageType.text,
        timestamp: today.add(const Duration(hours: 15, minutes: 10)),
        isRead: false,
        isOnline: false,
        senderInitials: 'DI',
      ),
      ChatMessage(
        id: 'msg_022',
        senderId: 'u_maa',
        senderName: 'Maa',
        content: 'Haan beta, main list bana dungi. Gulal ka special order bhi karna hai Sharma uncle ke yahan se — unka colour bahut accha aata hai',
        messageType: MessageType.text,
        timestamp: today.add(const Duration(hours: 15, minutes: 15)),
        isRead: false,
        isOnline: true,
        senderInitials: 'MA',
      ),
      ChatMessage(
        id: 'msg_023',
        senderId: 'u_papa',
        senderName: 'Papa',
        content: 'Aur suno, Holi ke din potluck rakhne ka plan hai. Har family ek dish banayegi. Kya banayega each of you? 🤔',
        messageType: MessageType.text,
        timestamp: today.add(const Duration(hours: 15, minutes: 30)),
        isRead: false,
        isOnline: true,
        senderInitials: 'PA',
      ),
      ChatMessage(
        id: 'msg_024',
        senderId: 'u_chachi',
        senderName: 'Chachi',
        content: 'Main gujiya aur thandai banaungi! Traditional Holi special 😊',
        messageType: MessageType.text,
        timestamp: today.add(const Duration(hours: 15, minutes: 35)),
        isRead: false,
        isOnline: false,
        senderInitials: 'CH',
        reactions: [
          MessageReaction(emoji: '😋', userId: 'u_bhaiya'),
          MessageReaction(emoji: '❤️', userId: 'u_maa'),
        ],
      ),
    ];

    state = state.copyWith(
      messages: messages.reversed.toList(), // newest first for our display
      members: members,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Provider
// ═══════════════════════════════════════════════════════════════════════

/// Family chat provider — parameterized by family ID.
final chatProvider = StateNotifierProvider.family<ChatNotifier, ChatState, String>(
  (ref, familyId) => ChatNotifier(familyId: familyId),
);

/// Convenience: online member count for a family chat.
final chatOnlineCountProvider = Provider.family<int, String>((ref, familyId) {
  return ref.watch(chatProvider(familyId)).onlineCount;
});

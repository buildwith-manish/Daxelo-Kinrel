// lib/features/chat/data/direct_message_provider.dart
//
// DAXELO KINREL — Direct Message (1:1) Provider (Phase 21)
//
// Manages private 1:1 conversations between two users. Backed by the
// DirectMessage table (NOT ChatMessage — that's the family group chat).
//
// RLS on DirectMessage only lets the sender and receiver see messages,
// so this is fully private — no other family member can read these.
//
// Used by:
//   - DirectChatScreen (renders the conversation)
//   - Thinking of You feature (sends a 'thinking_of_you' DM)
//   - Notification tap (opens the DM with the sender)

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';

// ═══════════════════════════════════════════════════════════════════════
// Model
// ═══════════════════════════════════════════════════════════════════════

class DirectMessage {
  const DirectMessage({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.content,
    required this.messageType,
    required this.isRead,
    required this.createdAt,
  });

  factory DirectMessage.fromJson(Map<String, dynamic> json) {
    return DirectMessage(
      id: json['id'] as String? ?? '',
      senderId: json['senderId'] as String? ?? '',
      receiverId: json['receiverId'] as String? ?? '',
      content: json['content'] as String? ?? '',
      messageType: json['messageType'] as String? ?? 'text',
      isRead: json['isRead'] as bool? ?? false,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  final String id;
  final String senderId;
  final String receiverId;
  final String content;
  final String messageType; // 'text' | 'thinking_of_you'
  final bool isRead;
  final DateTime createdAt;

  bool get isThinkingOfYou => messageType == 'thinking_of_you';

  String get formattedTime {
    final hour = createdAt.hour;
    final minute = createdAt.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$displayHour:$minute $period';
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Other-user info (for the AppBar)
// ═══════════════════════════════════════════════════════════════════════

class DirectChatPeer {
  const DirectChatPeer({
    required this.userId,
    required this.name,
    this.avatarUrl,
  });

  final String userId;
  final String name;
  final String? avatarUrl;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts[1][0]).toUpperCase();
  }
}

// ═══════════════════════════════════════════════════════════════════════
// State
// ═══════════════════════════════════════════════════════════════════════

class DirectChatState {
  const DirectChatState({
    this.messages = const [],
    this.peer,
    this.isLoading = true,
    this.error,
  });

  final List<DirectMessage> messages; // newest-first
  final DirectChatPeer? peer;
  final bool isLoading;
  final String? error;

  DirectChatState copyWith({
    List<DirectMessage>? messages,
    DirectChatPeer? peer,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return DirectChatState(
      messages: messages ?? this.messages,
      peer: peer ?? this.peer,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Notifier
// ═══════════════════════════════════════════════════════════════════════

String _generateId() {
  final timestamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final random = Random();
  final rand = List.generate(16, (_) => random.nextInt(36))
      .map((v) => v.toRadixString(36))
      .join();
  return 'dm_${timestamp}_$rand';
}

class DirectChatNotifier extends StateNotifier<DirectChatState> {
  DirectChatNotifier({required this.otherUserId, required this.ref})
      : super(const DirectChatState()) {
    _init();
  }

  final String otherUserId;
  final Ref ref;

  String? get _currentUserId =>
      ref.read(supabaseProvider)?.auth.currentUser?.id;

  String? get _currentUserName {
    final user = ref.read(supabaseProvider)?.auth.currentUser;
    if (user == null) return 'You';
    final meta = user.userMetadata;
    final name = meta?['name'] as String? ??
        meta?['full_name'] as String? ??
        meta?['displayName'] as String?;
    if (name != null && name.trim().isNotEmpty) return name.trim();
    if (user.email != null) return user.email!.split('@').first;
    return 'You';
  }

  SupabaseClient? get _client => ref.read(supabaseProvider);

  Future<void> _init() async {
    await _loadPeerInfo();
    await _loadMessages();
    _markAsRead();
  }

  /// Load the other user's name + avatar for the AppBar.
  /// Uses the SECURITY DEFINER RPC fn_get_user_public_profile to bypass
  /// User table RLS (which only lets you read your own row).
  Future<void> _loadPeerInfo() async {
    final client = _client;
    if (client == null) return;
    try {
      final response = await client.rpc(
        'fn_get_user_public_profile',
        params: {'p_user_id': otherUserId},
      ).timeout(const Duration(seconds: 8));

      final result = response as Map<String, dynamic>?;
      if (result != null && mounted) {
        state = state.copyWith(
          peer: DirectChatPeer(
            userId: otherUserId,
            name: result['name'] as String? ?? 'Member',
            avatarUrl: result['avatarUrl'] as String?,
          ),
        );
      }
    } catch (e) {
      debugPrint('⚠️ DirectChatNotifier._loadPeerInfo error: $e');
      // Fall back to a generic name so the AppBar isn't empty
      if (mounted) {
        state = state.copyWith(
          peer: DirectChatPeer(userId: otherUserId, name: 'Member'),
        );
      }
    }
  }

  Future<void> _loadMessages() async {
    final client = _client;
    final myUserId = _currentUserId;
    if (client == null || myUserId == null) {
      if (mounted) state = state.copyWith(isLoading: false, error: 'Not signed in');
      return;
    }
    try {
      // Fetch the conversation between me and the other user. RLS lets
      // me see rows where I'm the sender OR receiver.
      final response = await client
          .from('DirectMessage')
          .select()
          .or('and(senderId.eq.$myUserId,receiverId.eq.$otherUserId),'
              'and(senderId.eq.$otherUserId,receiverId.eq.$myUserId)')
          .order('createdAt', ascending: false)
          .limit(200);

      final messages = (response as List)
          .map((e) => DirectMessage.fromJson(e as Map<String, dynamic>))
          .toList();

      if (mounted) {
        state = state.copyWith(messages: messages, isLoading: false);
      }
    } catch (e) {
      debugPrint('⚠️ DirectChatNotifier._loadMessages error: $e');
      if (mounted) {
        state = state.copyWith(isLoading: false, error: 'Could not load messages');
      }
    }
  }

  /// Mark all messages FROM the other user as read. Best-effort —
  /// ignores errors since this is just a UX nicety.
  Future<void> _markAsRead() async {
    final client = _client;
    final myUserId = _currentUserId;
    if (client == null || myUserId == null) return;
    try {
      await client
          .from('DirectMessage')
          .update({'isRead': true, 'updatedAt': DateTime.now().toIso8601String()})
          .eq('receiverId', myUserId)
          .eq('senderId', otherUserId)
          .eq('isRead', false);
    } catch (e) {
      debugPrint('⚠️ DirectChatNotifier._markAsRead error: $e');
    }
  }

  /// Send a plain text DM.
  Future<void> sendText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final client = _client;
    final myUserId = _currentUserId;
    if (client == null || myUserId == null) return;

    final msgId = _generateId();
    final now = DateTime.now();
    final optimistic = DirectMessage(
      id: msgId,
      senderId: myUserId,
      receiverId: otherUserId,
      content: trimmed,
      messageType: 'text',
      isRead: false,
      createdAt: now,
    );

    if (mounted) {
      state = state.copyWith(messages: [optimistic, ...state.messages]);
    }

    try {
      await client.from('DirectMessage').insert({
        'id': msgId,
        'senderId': myUserId,
        'receiverId': otherUserId,
        'content': trimmed,
        'messageType': 'text',
        'isRead': false,
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      });
    } catch (e) {
      debugPrint('⚠️ DirectChatNotifier.sendText insert failed: $e');
      if (mounted) {
        final withoutFailed =
            state.messages.where((m) => m.id != msgId).toList();
        state = state.copyWith(
          messages: withoutFailed,
          error: 'Failed to send message',
        );
      }
    }
  }

  /// Refresh messages from the server (called after a Thinking of You
  /// is sent from elsewhere so this screen reflects the new message).
  Future<void> refresh() async {
    await _loadMessages();
    _markAsRead();
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Provider
// ═══════════════════════════════════════════════════════════════════════

final directChatProvider = StateNotifierProvider.family<
    DirectChatNotifier, DirectChatState, String>((ref, otherUserId) {
  return DirectChatNotifier(otherUserId: otherUserId, ref: ref);
});

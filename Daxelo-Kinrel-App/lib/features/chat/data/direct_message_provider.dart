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
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  final String messageType; // 'text' | 'thinking_of_you' | 'gameInvite'
  final bool isRead;
  final DateTime createdAt;

  bool get isThinkingOfYou => messageType == 'thinking_of_you';

  bool get isGameInvite => messageType == 'gameInvite';

  /// Parsed game-invite payload (messageType == 'gameInvite').
  ///
  /// Specific-Members game invites are delivered as a DM whose content
  /// is a JSON blob: gameType, gameId, roomCode, familyId, fromName,
  /// maxPlayers, currentPlayers, message. Returns null when the content
  /// is not valid JSON or missing the gameId (older / hand-typed rows).
  Map<String, dynamic>? get gameInvitePayload {
    if (!isGameInvite) return null;
    try {
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic> &&
          (decoded['gameId'] as String?)?.isNotEmpty == true) {
        return decoded;
      }
    } catch (_) {}
    return null;
  }

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

  RealtimeChannel? _channel;

  String? get _currentUserId =>
      ref.read(supabaseProvider)?.auth.currentUser?.id;

  SupabaseClient? get _client => ref.read(supabaseProvider);

  Future<void> _init() async {
    await _loadPeerInfo();
    await _loadMessages();
    _markAsRead();
    _subscribeToRealtime();
  }

  /// Task 4 — live DM sync.
  ///
  /// Subscribes to DirectMessage INSERT events addressed to me (RLS
  /// keeps everything else private). New messages — including game
  /// invites sent via the Specific-Members flow — appear in an open DM
  /// screen instantly, with no refresh. UPDATE events (read receipts)
  /// also refresh the ticks.
  void _subscribeToRealtime() {
    final client = _client;
    final myId = _currentUserId;
    if (client == null || myId == null) return;

    _channel = client
        .channel('dm_convo:$otherUserId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'DirectMessage',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'receiverId',
            value: myId,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            // Only refresh when the new message belongs to THIS
            // conversation (filter is by receiver only — sender varies).
            final senderId = row['senderId'] as String?;
            if (senderId != otherUserId) return;
            unawaited(refresh());
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'DirectMessage',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'receiverId',
            value: myId,
          ),
          callback: (payload) {
            unawaited(refresh());
          },
        )
        .subscribe();
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

  @override
  void dispose() {
    _channel?.unsubscribe();
    _channel = null;
    super.dispose();
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Provider
// ═══════════════════════════════════════════════════════════════════════

final directChatProvider = StateNotifierProvider.family<
    DirectChatNotifier, DirectChatState, String>((ref, otherUserId) {
  return DirectChatNotifier(otherUserId: otherUserId, ref: ref);
});

// ═══════════════════════════════════════════════════════════════════════
// Task 4 — Send a game invite as a DIRECT MESSAGE (Specific Members)
// ═══════════════════════════════════════════════════════════════════════

/// Inserts a private game-invite DM addressed to [toUserId] only.
///
/// Called by InviteFamilySheet when the host invites SPECIFIC members
/// (single tap or multi-select): the invite lands in that member's DM
/// thread — never in the family group chat. The family chat card is
/// reserved for the explicit "Entire Family" bulk flow.
///
/// Content is a JSON payload (gameType / gameId / roomCode / familyId /
/// fromName / maxPlayers / currentPlayers / message) which
/// DirectChatScreen renders as an interactive invite card with a Join
/// action. Best-effort: failures are logged, never thrown — the durable
/// game_invites row + socket event are the authoritative invite legs.
Future<void> sendGameInviteDm({
  required SupabaseClient client,
  required String toUserId,
  required Map<String, dynamic> inviteJson,
}) async {
  final myUserId = client.auth.currentUser?.id;
  if (myUserId == null) return;
  final now = DateTime.now();
  final msgId = _generateId();
  try {
    await client.from('DirectMessage').insert({
      'id': msgId,
      'senderId': myUserId,
      'receiverId': toUserId,
      'content': jsonEncode(inviteJson),
      'messageType': 'gameInvite',
      'isRead': false,
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
    });
  } catch (e) {
    debugPrint('⚠️ sendGameInviteDm insert failed (non-blocking): $e');
  }
}

// ═══════════════════════════════════════════════════════════════════════
// v113 — DM Inbox Provider
// ═══════════════════════════════════════════════════════════════════════

/// A single DM conversation row in the chat inbox.
///
/// Represents the most recent message in a 1:1 conversation between the
/// current user and [otherUserId], plus an unread count and archive state.
class DmInboxItem {
  const DmInboxItem({
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserAvatar,
    required this.lastMessage,
    required this.lastMessageTime,
    required this.unreadCount,
    required this.isArchived,
  });

  final String otherUserId;
  final String otherUserName;
  final String? otherUserAvatar;
  final String lastMessage;
  final DateTime lastMessageTime;
  final int unreadCount;
  final bool isArchived;
}

/// Loads the current user's DM inbox — one row per conversation partner,
/// ordered by most-recent-message-first.
///
/// Tries the `fn_get_dm_inbox` RPC first. If that function does not exist
/// (hasn't been migrated yet), falls back to querying the DirectMessage
/// table directly: fetches all rows where the user is sender or receiver,
/// groups by the other party, takes the most recent message per
/// conversation, and computes unread counts.
///
/// Archive state is read from `shared_preferences` (key
/// `dm_archived_$otherUserId`) since the DirectMessage table does not have
/// an `isArchived` column.
final dmInboxProvider =
    FutureProvider<List<DmInboxItem>>((ref) async {
  // Task 4 — live inbox: refetch whenever a new DM lands for me.
  ref.watch(dmInboxTickProvider);
  final client = Supabase.instance.client;
  final myUserId = client.auth.currentUser?.id;
  if (myUserId == null) return [];

  final prefs = await SharedPreferences.getInstance();

  // ── Try the RPC first ──
  try {
    final response = await client
        .rpc('fn_get_dm_inbox')
        .timeout(const Duration(seconds: 8));

    if (response is List && response.isNotEmpty) {
      final items = <DmInboxItem>[];
      for (final row in response) {
        final map = row as Map<String, dynamic>;
        final otherId = map['otherUserId'] as String? ?? '';
        if (otherId.isEmpty) continue;
        items.add(DmInboxItem(
          otherUserId: otherId,
          otherUserName: map['otherUserName'] as String? ?? 'Member',
          otherUserAvatar: map['otherUserAvatar'] as String?,
          lastMessage:
              _invitePreview(map['lastMessage'] as String? ?? '')
                  .truncateTo(40),
          lastMessageTime:
              DateTime.tryParse(map['lastMessageTime'] as String? ?? '') ??
                  DateTime.now(),
          unreadCount: (map['unreadCount'] as num?)?.toInt() ?? 0,
          isArchived: prefs.getBool('dm_archived_$otherId') ?? false,
        ));
      }
      return items;
    }
  } catch (_) {
    // RPC doesn't exist or errored — fall through to direct query.
  }

  // ── Fallback: query DirectMessage table directly ──
  try {
    final response = await client
        .from('DirectMessage')
        .select()
        .or('senderId.eq.$myUserId,receiverId.eq.$myUserId')
        .order('createdAt', ascending: false)
        .limit(200)
        .timeout(const Duration(seconds: 10));

    // Group by the other party's user ID.
    final byOtherUser = <String, Map<String, dynamic>>{};
    for (final row in response as List) {
      final senderId = row['senderId'] as String? ?? '';
      final receiverId = row['receiverId'] as String? ?? '';
      final otherId = senderId == myUserId ? receiverId : senderId;
      if (otherId.isEmpty) continue;

      // First occurrence is the most recent (we ordered desc).
      if (!byOtherUser.containsKey(otherId)) {
        byOtherUser[otherId] = {
          'otherUserId': otherId,
          'lastMessage': row['content'] as String? ?? '',
          'lastMessageTime':
              DateTime.tryParse(row['createdAt'] as String? ?? '') ??
                  DateTime.now(),
          'isRead': row['isRead'] as bool? ?? false,
          'senderId': senderId,
        };
      }
    }

    // Fetch names + avatars + compute unread counts.
    final items = <DmInboxItem>[];
    for (final entry in byOtherUser.entries) {
      final otherId = entry.key;
      final data = entry.value;

      // Load the other user's name/avatar via the public-profile RPC.
      String name = 'Member';
      String? avatarUrl;
      try {
        final profile = await client
            .rpc('fn_get_user_public_profile', params: {'p_user_id': otherId})
            .timeout(const Duration(seconds: 5));
        if (profile is Map<String, dynamic>) {
          name = profile['name'] as String? ?? 'Member';
          avatarUrl = profile['avatarUrl'] as String?;
        }
      } catch (_) {}

      // Count unread messages from this other user.
      int unreadCount = 0;
      try {
        final unreadResp = await client
            .from('DirectMessage')
            .select('id')
            .eq('senderId', otherId)
            .eq('receiverId', myUserId)
            .eq('isRead', false)
            .timeout(const Duration(seconds: 5));
        unreadCount = (unreadResp as List).length;
      } catch (_) {}

      final isArchived = prefs.getBool('dm_archived_$otherId') ?? false;

      items.add(DmInboxItem(
        otherUserId: otherId,
        otherUserName: name,
        otherUserAvatar: avatarUrl,
        lastMessage:
            _invitePreview(data['lastMessage'] as String).truncateTo(40),
        lastMessageTime: data['lastMessageTime'] as DateTime,
        unreadCount: unreadCount,
        isArchived: isArchived,
      ));
    }

    // Sort by most-recent-first.
    items.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
    return items;
  } catch (_) {
    return [];
  }
});

// ═══════════════════════════════════════════════════════════════════════
// Task 4 — DM inbox live refresh
// ═══════════════════════════════════════════════════════════════════════

/// Increments whenever a new DM addressed to the current user lands
/// (DirectMessage realtime INSERT, receiverId = me). [dmInboxProvider]
/// watches this, so the inbox list (unread badges, last-message
/// previews, new game-invite DMs) refreshes instantly with no manual
/// reload.
class DmInboxTickNotifier extends StateNotifier<int> {
  DmInboxTickNotifier(this._ref) : super(0) {
    _init();
  }

  final Ref _ref;
  RealtimeChannel? _channel;

  SupabaseClient? get _client => _ref.read(supabaseProvider);

  void _init() {
    final client = _client;
    final myId = client?.auth.currentUser?.id;
    if (client == null || myId == null) return;

    _channel = client
        .channel('dm_inbox_tick')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'DirectMessage',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'receiverId',
            value: myId,
          ),
          callback: (payload) {
            if (mounted) state = state + 1;
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _channel = null;
    super.dispose();
  }
}

final dmInboxTickProvider =
    StateNotifierProvider<DmInboxTickNotifier, int>((ref) {
  return DmInboxTickNotifier(ref);
});

/// Task 4 — friendly inbox preview for game-invite DMs.
///
/// Specific-Members invites are DMs whose content is a JSON payload.
/// In the inbox list we show "🎮 Game invite: SOS" instead of raw JSON.
/// Non-JSON content passes through unchanged.
String _invitePreview(String content) {
  final trimmed = content.trim();
  if (!trimmed.startsWith('{')) return content;
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is Map<String, dynamic> &&
        decoded['gameId'] != null) {
      final gameType = decoded['gameType'] as String? ?? 'game';
      final from = decoded['fromName'] as String?;
      return from == null || from.isEmpty
          ? '🎮 Game invite: $gameType'
          : '🎮 $from invited you to $gameType';
    }
  } catch (_) {}
  return content;
}

/// Extension for truncating strings for preview display.
extension _StringTruncate on String {
  String truncateTo(int maxLen) =>
      length <= maxLen ? this : '${substring(0, maxLen)}…';
}

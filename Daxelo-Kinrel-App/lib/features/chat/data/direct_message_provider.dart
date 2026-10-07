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
// v3.4 — Reply threading (swipe-to-reply parity with the group chat):
//   - DirectMessage now carries replyToId / replyToContent /
//     replyToSenderName (the SAME denormalized-preview columns the
//     group ChatMessage table has, mirrored by migration
//     20261007080000_dm_reply_threading.sql).
//   - DirectChatState carries replyToMessage + the notifier exposes
//     setReplyTo / clearReplyTo — the exact state shape ChatState uses
//     for the group chat, so the shared ReplyPreviewBar renders off it.
//   - sendText accepts replyToId — the SAME optimistic-insert + persist
//     flow as the group's sendMessage(replyToId:).
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

import '../../../core/family/family_provider.dart';
import '../../../core/services/supabase_service.dart';
// GameInvite model — used by sendGameInviteDm to resolve the game table
// (gameTableForType) for the spectators lookup + payload typing.
import '../../games/shared/models/game_invite.dart';
// Step 4 — shared timezone-aware time utility. DirectMessage timestamps
// are PERSONAL — each viewer sees their own device-local time.
import '../../../core/utils/app_time.dart';
// v3.4 — the reply state is stored as a ChatMessage (the shape the
// shared ReplyPreviewBar + MessageBubble quote render from). No cycle:
// chat_provider.dart does not import this file.
import '../providers/chat_provider.dart';

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
    // v3.4 — reply threading (mirrors ChatMessage's reply columns).
    this.replyToId,
    this.replyToContent,
    this.replyToSenderName,
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
      // v3.4 — reply threading. Old rows / servers without the columns
      // fall back to null (renders as a normal message — never breaks).
      replyToId: json['replyToId'] as String?,
      replyToContent: json['replyToContent'] as String?,
      replyToSenderName: json['replyToSenderName'] as String?,
    );
  }

  final String id;
  final String senderId;
  final String receiverId;
  final String content;
  final String messageType; // 'text' | 'thinking_of_you' | 'gameInvite'
  final bool isRead;
  final DateTime createdAt;

  // v3.4 — reply threading (the SAME denormalized-preview fields the
  // group ChatMessage carries; see migration
  // 20261007080000_dm_reply_threading.sql).
  /// ID of the DM this is replying to (null = not a reply).
  final String? replyToId;

  /// Denormalized snapshot of the replied-to message's content.
  final String? replyToContent;

  /// Denormalized snapshot of the replied-to sender's name.
  final String? replyToSenderName;

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

  /// Step 4: formatted time string (e.g., "10:30 AM"). PERSONAL —
  /// each viewer sees their own device-local time. Previously this
  /// read `createdAt.hour` directly on a UTC-parsed DateTime, which
  /// returned the UTC hour — non-UTC viewers saw the wrong wall-clock
  /// time on every DM message bubble.
  String get formattedTime {
    final local = AppTime.toLocalDisplay(createdAt);
    final hour = local.hour;
    final minute = local.minute.toString().padLeft(2, '0');
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
    // v3.4 — reply threading (the same field ChatState carries for the
    // group chat). The shared ReplyPreviewBar renders directly from it.
    this.replyToMessage,
  });

  final List<DirectMessage> messages; // newest-first
  final DirectChatPeer? peer;
  final bool isLoading;
  final String? error;

  /// v3.4 — Message being replied to (null if not replying). Stored as
  /// a ChatMessage because that's the shape the shared widgets
  /// (ReplyPreviewBar + onReply callback) exchange — the DM screen sets
  /// it from the ChatMessageList's onReply callback, which passes the
  /// adapter-converted ChatMessage.
  final ChatMessage? replyToMessage;

  DirectChatState copyWith({
    List<DirectMessage>? messages,
    DirectChatPeer? peer,
    bool? isLoading,
    String? error,
    bool clearError = false,
    ChatMessage? replyToMessage,
    bool clearReplyTo = false,
  }) {
    return DirectChatState(
      messages: messages ?? this.messages,
      peer: peer ?? this.peer,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      replyToMessage:
          clearReplyTo ? null : (replyToMessage ?? this.replyToMessage),
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
  /// Subscribes to DirectMessage INSERT/UPDATE events addressed to me
  /// (RLS keeps everything else private). New messages — including game
  /// invites sent via the Specific-Members flow — appear in an open DM
  /// screen instantly, with no refresh. UPDATE events (read receipts,
  /// and the server-side game-invite payload rewrites) also refresh the
  /// thread.
  ///
  /// Sender-side subscriptions (senderId = me) mirror the group chat's
  /// ChatMessage realtime parity: the group channel is filtered by
  /// familyId so BOTH parties see every UPDATE, while a receiver-only
  /// DM filter would leave the SENDER's own invite cards stale when the
  /// server-side lifecycle state machine (fn_sync_dm_game_invites)
  /// rewrites the payload. Two extra subscriptions close that gap —
  /// both parties now see invite status/players/winner change live,
  /// pin-to-pin with the group card.
  void _subscribeToRealtime() {
    final client = _client;
    final myId = _currentUserId;
    if (client == null || myId == null) return;

    _channel = client
        .channel('dm_convo:$otherUserId')
        // ── Receiver side: new messages from the other user ──
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
        // ── Receiver side: updates to messages I received (read ticks +
        //    live game-invite payload rewrites from the server state
        //    machine) ──
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
        // ── Sender side: updates to MY OWN messages in this conversation
        //    (the receiver marking them read, and the server-side
        //    game-invite payload rewrites). Without this the sender's
        //    own invite card would stay "Waiting for players" while the
        //    group chat card already moved on — the exact inconsistency
        //    this parity fix removes. ──
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'DirectMessage',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'senderId',
            value: myId,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            // Only refresh when the updated message belongs to THIS
            // conversation (filter is by sender only — receiver varies).
            final receiverId = row['receiverId'] as String?;
            if (receiverId != otherUserId) return;
            unawaited(refresh());
          },
        )
        // ── Sender side: inserts of my own messages from other surfaces
        //    (e.g. a game invite sent from the invite sheet while this
        //    DM screen is open) ──
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'DirectMessage',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'senderId',
            value: myId,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            final receiverId = row['receiverId'] as String?;
            if (receiverId != otherUserId) return;
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
  ///
  /// v3.4 — [replyToId] pins this message to an earlier one (the
  /// swipe-to-reply / long-press-Reply flow). The reply preview fields
  /// (replyToContent / replyToSenderName) are resolved from
  /// [DirectChatState.replyToMessage] and denormalized onto the row —
  /// the exact pattern the group ChatNotifier.sendMessage uses, so the
  /// shared MessageBubble quote renders identically in both chats.
  ///
  /// If [replyToId] was passed WITHOUT a reply bar being set (e.g. a
  /// notification quick-reply), the preview is resolved from the loaded
  /// DM list — mirroring the group's firstWhere-over-state.messages.
  Future<void> sendText(String text, {String? replyToId}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final client = _client;
    final myUserId = _currentUserId;
    if (client == null || myUserId == null) return;

    // ── Resolve the reply preview snapshot (same as the group's
    // sendMessage: the content + sender name are captured NOW, so a
    // later edit/delete of the original can't rewrite history).
    final replyTo = state.replyToMessage;
    final effectiveReplyToId = replyToId ?? replyTo?.id;
    String? replyContent = (effectiveReplyToId != null)
        ? (replyTo?.content)
        : null;
    String? replySender = (effectiveReplyToId != null)
        ? (replyTo?.senderName)
        : null;

    // Fallback: replyToId given but no reply bar (notification
    // quick-reply) — resolve from the loaded DM list.
    if (effectiveReplyToId != null &&
        (replyContent == null || replySender == null)) {
      final target = state.messages
          .where((m) => m.id == effectiveReplyToId)
          .firstOrNull;
      if (target != null) {
        replyContent ??= target.isGameInvite ? '[Game invite]' : target.content;
        replySender ??= _resolveNameFor(target.senderId, myUserId);
      }
    }

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
      replyToId: effectiveReplyToId,
      replyToContent: replyContent,
      replyToSenderName: replySender,
    );

    if (mounted) {
      // Optimistic insert + clear the reply bar — the SAME combined
      // state transition the group's sendMessage performs.
      state = state.copyWith(
        messages: [optimistic, ...state.messages],
        clearReplyTo: true,
      );
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
        // v3.4 — persist the reply threading columns.
        'replyToId': effectiveReplyToId,
        'replyToContent': replyContent,
        'replyToSenderName': replySender,
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

  /// v3.4 — resolve a display name for the fallback reply-preview
  /// path: my name for my own messages, the peer's name otherwise.
  /// Mirrors resolveMyName in direct_message_adapter.dart (same
  /// user-metadata keys, same email fallback) — duplicated inline
  /// because the adapter imports THIS file (no reverse import
  /// possible).
  String? _resolveNameFor(String senderId, String myUserId) {
    if (senderId == myUserId) {
      final user = _client?.auth.currentUser;
      final meta = user?.userMetadata;
      final name = meta?['name'] as String? ??
          meta?['full_name'] as String? ??
          meta?['displayName'] as String?;
      if (name != null && name.trim().isNotEmpty) return name.trim();
      final email = user?.email;
      if (email != null) return email.split('@').first;
      return 'You';
    }
    return state.peer?.name;
  }

  // ── v3.4 — Reply threading state ──────────────────────────────────
  // The EXACT API surface the group's ChatNotifier exposes
  // (setReplyTo / clearReplyTo), so the screens wire the same way.

  /// Set the message being replied to (shows the reply preview bar).
  void setReplyTo(ChatMessage? message) {
    state = state.copyWith(replyToMessage: message);
  }

  /// Clear the reply target (X button on the reply preview bar).
  void clearReplyTo() {
    state = state.copyWith(clearReplyTo: true);
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

final directChatProvider = StateNotifierProvider.autoDispose.family<
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
/// fromName / maxPlayers / currentPlayers / message / status /
/// spectatorsEnabled) which DirectChatScreen renders through the SAME
/// game-invite card widget the group chat uses.
///
/// Pin-to-pin group parity (mirrors ChatNotifier.sendGameInvite):
///   • Dedupe: if a non-terminal invite DM for the same gameId already
///     exists in this conversation, it is UPDATED (latest players /
///     message / spectators) instead of inserting a duplicate card.
///   • Initial payload status: 'pending' (the same insert default the
///     group ChatMessage row gets).
///   • spectatorsEnabled is persisted at invite-sent time so the shared
///     card can render (or hide) the Spectate button without a
///     per-render round-trip — kept in sync afterwards by the
///     fn_sync_game_spectators trigger via fn_sync_dm_game_invites.
///
/// Best-effort: failures are logged, never thrown — the durable
/// game_invites row + socket event are the authoritative invite legs.
Future<void> sendGameInviteDm({
  required SupabaseClient client,
  required String toUserId,
  required Map<String, dynamic> inviteJson,
}) async {
  final myUserId = client.auth.currentUser?.id;
  if (myUserId == null) return;
  final now = DateTime.now();

  // Payload copy — keep the caller's map untouched while adding the
  // lifecycle fields the shared card reads.
  final payload = Map<String, dynamic>.from(inviteJson);
  payload['status'] ??= 'pending';

  // Best-effort spectators flag from the game row (same query the group
  // card path in InviteFamilySheet._postInviteChatCard performs). Games
  // without a spectatorsEnabled column (ghost painter) or missing rows
  // leave it unset → the shared card's legacy default (true).
  if (payload['spectatorsEnabled'] == null) {
    try {
      final gameTypeStr = (payload['gameType'] as String? ?? '').trim();
      final gameId = payload['gameId'] as String? ?? '';
      final gameType = GameTypeX.fromRouteSegment(gameTypeStr);
      if (gameType != null && gameId.isNotEmpty) {
        final gameTable = gameTableForType(gameType);
        if (gameTable.isNotEmpty) {
          final row = await client
              .from(gameTable)
              .select('spectatorsEnabled')
              .eq('id', gameId)
              .maybeSingle();
          final v = row?['spectatorsEnabled'];
          if (v is bool) {
            payload['spectatorsEnabled'] = v;
          } else if (v is String) {
            payload['spectatorsEnabled'] = v.toLowerCase() == 'true';
          }
        }
      }
    } catch (_) {
      // Known edge (ghost painter / deleted row) — leave unset.
    }
  }

  final gameId = payload['gameId'] as String? ?? '';
  try {
    // ── Dedupe: one invite card per room per conversation ───────────
    // Mirrors the group chat's sendGameInvite dedupe. If a non-terminal
    // invite DM for this gameId already exists in THIS conversation
    // (status pending / in_progress / accepted / active), update it with
    // the latest players + message + spectators instead of inserting a
    // duplicate. Terminal states (expired / cancelled / completed) get a
    // fresh card.
    if (gameId.isNotEmpty) {
      final existing = await client
          .from('DirectMessage')
          .select('id, content')
          .eq('messageType', 'gameInvite')
          .or('and(senderId.eq.$myUserId,receiverId.eq.$toUserId),'
              'and(senderId.eq.$toUserId,receiverId.eq.$myUserId)')
          .order('createdAt', ascending: false)
          .limit(50);

      for (final row in (existing as List)) {
        final Map<String, dynamic>? rowPayload =
            _tryDecodeInvitePayload(row['content'] as String? ?? '');
        if (rowPayload == null) continue;
        if ((rowPayload['gameId'] as String?) != gameId) continue;
        final rowStatus = (rowPayload['status'] as String?) ?? 'pending';
        const nonTerminal = [
          'pending',
          'in_progress',
          'accepted',
          'active',
        ];
        if (!nonTerminal.contains(rowStatus)) continue;

        // Merge the fresh values onto the existing payload (keep the
        // authoritative server-side status — the room may already be
        // in_progress).
        final merged = Map<String, dynamic>.from(rowPayload);
        merged['currentPlayers'] = payload['currentPlayers'] ??
            rowPayload['currentPlayers'];
        merged['maxPlayers'] = payload['maxPlayers'] ?? rowPayload['maxPlayers'];
        merged['roomCode'] = payload['roomCode'] ?? rowPayload['roomCode'];
        if (payload['message'] != null) merged['message'] = payload['message'];
        if (payload['spectatorsEnabled'] != null) {
          merged['spectatorsEnabled'] = payload['spectatorsEnabled'];
        }

        await client.from('DirectMessage').update({
          'content': jsonEncode(merged),
          'updatedAt': now.toIso8601String(),
        }).eq('id', row['id'] as String);
        return; // Updated — don't insert a duplicate.
      }
    }

    final msgId = _generateId();
    await client.from('DirectMessage').insert({
      'id': msgId,
      'senderId': myUserId,
      'receiverId': toUserId,
      'content': jsonEncode(payload),
      'messageType': 'gameInvite',
      'isRead': false,
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
    });
  } catch (e) {
    debugPrint('⚠️ sendGameInviteDm insert failed (non-blocking): $e');
  }
}

/// Decode a DirectMessage.content JSON blob into an invite payload map.
/// Returns null for plain-text / malformed / non-JSON rows — same
/// contract as DirectMessage.gameInvitePayload.
Map<String, dynamic>? _tryDecodeInvitePayload(String content) {
  try {
    final decoded = jsonDecode(content);
    if (decoded is Map<String, dynamic> &&
        (decoded['gameId'] as String?)?.isNotEmpty == true) {
      return decoded;
    }
  } catch (_) {}
  return null;
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

// ═══════════════════════════════════════════════════════════════════════
// v140 Family-Centric Chat Navigation — family-scoped DM inbox + members
// ═══════════════════════════════════════════════════════════════════════

/// A direct-message partner who belongs to the currently-selected family.
///
/// Returned by [familyDmPartnersProvider] for the Direct tab inside
/// FamilyChatListScreen. The list is split into two buckets:
///   1. "Recent Conversations" — partners with at least one DM already
///      exchanged (sorted by latest activity).
///   2. "Available Family Members" — family members who are Kinrel users
///      (linkedUserId set) but have NOT yet started a DM thread.
///
/// Family isolation: only members of [familyId] are returned. The user's
/// own id is excluded from both buckets. Switching the familyId parameter
/// re-runs this provider against the new family's roster.
class FamilyDmPartner {
  const FamilyDmPartner({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    this.lastMessage = '',
    this.lastMessageTime,
    this.unreadCount = 0,
    this.hasConversation = false,
  });

  final String userId;
  final String displayName;
  final String? avatarUrl;
  final String lastMessage;
  final DateTime? lastMessageTime;
  final int unreadCount;
  final bool hasConversation;

  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts[1][0]).toUpperCase();
  }
}

/// Family-scoped DM partners: combines the global [dmInboxProvider] with
/// the family roster from [familyLinkedUserIdsProvider] so the Direct tab
/// only ever shows members of the currently-selected family.
///
/// Watches [dmInboxTickProvider] so new DMs refresh the list in real time.
final familyDmPartnersProvider =
    FutureProvider.family<FamilyDmPartnersResult, String>((ref, familyId) async {
  // Live refresh — refetch whenever a new DM addressed to me lands.
  ref.watch(dmInboxTickProvider);

  final client = Supabase.instance.client;
  final myUserId = client.auth.currentUser?.id;
  if (myUserId == null) {
    return const FamilyDmPartnersResult(recent: [], available: []);
  }

  // 1. Load the global DM inbox (already handles RPC + fallback).
  final inbox = await ref.read(dmInboxProvider.future);

  // 2. Load the family roster — we need both the linked-user-id set
  //    (for membership filtering) AND display info for members without
  //    a conversation yet. unifiedFamilyRosterProvider dedupes
  //    FamilyMember rows + Person nodes by linkedUserId.
  //
  //    We watch the underlying FutureProvider directly so that this
  //    provider re-runs when the roster finishes loading AND so the
  //    AsyncValue's loading/error state propagates correctly to the
  //    Direct tab's .when() wrapper.
  final rosterAsync = ref.watch(unifiedFamilyRosterProvider(familyId));
  final roster = rosterAsync.valueOrNull ?? const [];

  // Build a userId → roster entry lookup (Kinrel users only).
  // We keep the UnifiedFamilyMember reference so the Available Members
  // loop below can reuse the same display info (avatar, name) without
  // an extra pass.
  final rosterByUserId = <String, UnifiedFamilyMember>{};
  for (final m in roster) {
    final uid = m.userId;
    if (uid == null || uid.isEmpty) continue;
    if (uid == myUserId) continue;
    rosterByUserId[uid] = m;
  }

  // 3. Split into recent-conversations vs available-members.
  final recent = <FamilyDmPartner>[];
  final seenUserIds = <String>{};

  for (final dm in inbox) {
    if (dm.isArchived) continue;
    final entry = rosterByUserId[dm.otherUserId];
    // Only include DMs whose other party is in THIS family's roster.
    if (entry == null) continue;

    recent.add(FamilyDmPartner(
      userId: dm.otherUserId,
      displayName: dm.otherUserName.isNotEmpty
          ? dm.otherUserName
          : entry.displayName,
      avatarUrl: dm.otherUserAvatar ?? entry.avatarUrl,
      lastMessage: dm.lastMessage,
      lastMessageTime: dm.lastMessageTime,
      unreadCount: dm.unreadCount,
      hasConversation: true,
    ));
    seenUserIds.add(dm.otherUserId);
  }
  // Sort recent by lastMessageTime descending (newest first).
  recent.sort((a, b) {
    final at = a.lastMessageTime ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bt = b.lastMessageTime ?? DateTime.fromMillisecondsSinceEpoch(0);
    return bt.compareTo(at);
  });

  // 4. Available family members — Kinrel users in this family with no DM yet.
  //
  //    The roster's displayName may fall back to "Member" when the
  //    FamilyMembership doesn't carry an embedded User profile (which
  //    happens when familyMembershipsProvider queries the FamilyMember
  //    table without joining to User). To avoid showing "Member" for
  //    every available contact, we lazy-fetch each one's public profile
  //    via the same SECURITY DEFINER RPC the DM inbox uses
  //    (fn_get_user_public_profile). This is bounded by the family
  //    size (typically 5–30 members) and runs in parallel.
  final unknownNameUids = <String>[];
  for (final entry in roster) {
    final uid = entry.userId;
    if (uid == null || uid.isEmpty) continue;
    if (uid == myUserId) continue;
    if (seenUserIds.contains(uid)) continue;
    // If the roster already has a real name (not the "Member" fallback),
    // skip the extra RPC. We detect this by checking that displayName is
    // non-empty AND not the literal "Member" fallback used by
    // UnifiedFamilyMember.fromMembership.
    if (entry.displayName.isEmpty || entry.displayName == 'Member') {
      unknownNameUids.add(uid);
    }
  }

  final profileByUid = <String, _UserProfile>{};
  if (unknownNameUids.isNotEmpty) {
    await Future.wait(unknownNameUids.map((uid) async {
      try {
        final response = await client
            .rpc('fn_get_user_public_profile', params: {'p_user_id': uid})
            .timeout(const Duration(seconds: 5));
        if (response is Map<String, dynamic>) {
          profileByUid[uid] = _UserProfile(
            name: response['name'] as String? ?? '',
            avatarUrl: response['avatarUrl'] as String?,
          );
        }
      } catch (_) {
        // Best-effort — fall back to the roster displayName below.
      }
    }));
  }

  final available = <FamilyDmPartner>[];
  for (final entry in roster) {
    final uid = entry.userId;
    if (uid == null || uid.isEmpty) continue;
    if (uid == myUserId) continue;
    if (seenUserIds.contains(uid)) continue;

    final profile = profileByUid[uid];
    // Resolution order: explicit profile RPC → roster displayName → fallback.
    final displayName = (profile?.name != null && profile!.name.isNotEmpty)
        ? profile.name
        : (entry.displayName.isNotEmpty && entry.displayName != 'Member'
            ? entry.displayName
            : 'Member');
    final avatarUrl = profile?.avatarUrl ?? entry.avatarUrl;

    available.add(FamilyDmPartner(
      userId: uid,
      displayName: displayName,
      avatarUrl: avatarUrl,
      hasConversation: false,
    ));
  }

  // Sort available alphabetically for a stable, predictable list.
  available.sort((a, b) =>
      a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));

  return FamilyDmPartnersResult(recent: recent, available: available);
});

/// Container returned by [familyDmPartnersProvider].
class FamilyDmPartnersResult {
  const FamilyDmPartnersResult({
    required this.recent,
    required this.available,
  });

  /// DM partners in THIS family with an existing conversation, newest first.
  final List<FamilyDmPartner> recent;

  /// Kinrel users in THIS family with no DM thread yet, alphabetical.
  final List<FamilyDmPartner> available;
}

/// Lightweight user-profile snapshot fetched via fn_get_user_public_profile
/// for available family members whose roster displayName is the "Member"
/// fallback. Keeping this private avoids leaking a half-defined model
/// outside this file.
class _UserProfile {
  const _UserProfile({required this.name, this.avatarUrl});

  final String name;
  final String? avatarUrl;
}

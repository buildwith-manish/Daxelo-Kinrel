// lib/features/chat/data/direct_message_adapter.dart
//
// DAXELO KINREL — DirectMessage → ChatMessage adapter (shared UI)
//
// The group chat and the 1:1 DM chat now share the SAME UI components
// (MessageBubble, ChatMessageList, game-invite card). The group chat
// stores messages as ChatMessage rows in the ChatMessage table; the DM
// chat stores them as DirectMessage rows in the DirectMessage table.
// This adapter converts a DirectMessage into a ChatMessage so the
// shared widgets can render it without knowing which table it came
// from.
//
// The conversion is ONE-WAY (DM → ChatMessage) and READ-ONLY — the DM
// provider's sendText / sendGameInviteDm / queries / realtime are
// unchanged. The adapter only touches the UI projection of a DM row.
//
// Mapping rules (per the shared-chat-messages spec):
//   - id: DirectMessage.id → ChatMessage.id (verbatim)
//   - senderId / receiverId: verbatim (ChatMessage only uses senderId)
//   - senderName: the PEER's name for received messages, MY name for
//     sent messages (so the bubble shows the right party). Resolved
//     from DirectChatPeer + the current user's display name.
//   - senderInitials: derived from senderName (same algorithm as the
//     group ChatMessage.fromJson path uses).
//   - content: verbatim for text/thinking_of_you; for gameInvite the
//     raw JSON blob is kept in content (the group card reads its
//     fields from the dedicated gameType/gameId/... columns instead,
//     so content is not used for invite rendering — but we keep it so
//     a copy action on a malformed invite falls back to the JSON text)
//   - timestamp: DirectMessage.createdAt is UTC from the server; we
//     run it through AppTime.toLocalDisplay() the same way the group
//     ChatMessage.fromJson does (it parses createdAt into a DateTime
//     and stores it; AppTime is applied at DISPLAY time in
//     ChatMessage.formattedTime / _groupByDate). So here we just pass
//     the DateTime through — no extra conversion needed.
//   - isRead: verbatim
//   - messageStatus: 'read' when isRead else 'sent' (matches the
//     ReadReceipt widget's contract — a read DM shows the gold double
//     tick, an unread sent DM shows the single grey tick)
//   - messageType: 'text' for plain text, 'gameInvite' when the DM
//     carries a game-invite payload, 'text' for thinking_of_you (the
//     thinking-of-you styling is triggered by messageSubType below)
//   - messageSubType: 'thinking_of_you' for thinking-of-you messages,
//     null otherwise
//   - For game invites: gameType, gameId, roomCode, gameMaxPlayers,
//     gameCurrentPlayers, gameInviteStatus are filled from
//     DirectMessage.gameInvitePayload. If the payload is missing or
//     has no gameId (old rows), the message is mapped to a plain text
//     message so the thread never breaks.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/supabase_service.dart';
import '../providers/chat_provider.dart';
import 'direct_message_provider.dart';

/// Converts a [DirectMessage] into a [ChatMessage] so the shared chat
/// UI (MessageBubble, ChatMessageList, game-invite card) can render it.
///
/// [myUserId] is the current user's id — used to decide whether this
/// is a sent (isMe) or received message, and to pick the sender name
/// (my name for sent, peer name for received).
///
/// [myName] is the current user's display name (used for sent
/// messages). Falls back to 'You' if null/empty.
///
/// [peerName] is the other user's display name (used for received
/// messages). Falls back to 'Them' if null/empty.
ChatMessage directMessageToChatMessage(
  DirectMessage dm, {
  required String? myUserId,
  String? myName,
  String? peerName,
}) {
  final bool isMe = dm.senderId == myUserId;
  final String senderName = isMe
      ? (myName?.isNotEmpty == true ? myName! : 'You')
      : (peerName?.isNotEmpty == true ? peerName! : 'Them');

  // senderInitials — same algorithm as the group path's
  // _initialsFromName in chat_provider.dart.
  final String senderInitials = _initialsFromName(senderName);

  // messageStatus — read takes precedence (gold double tick), else
  // 'sent' (single grey tick). DMs don't have a 'delivered' state in
  // the DirectMessage table, so we map directly to 'sent'.
  final String messageStatus = dm.isRead ? 'read' : 'sent';

  // Game-invite payload — if present and has a gameId, map to a
  // gameInvite ChatMessage with the card fields filled. Otherwise
  // (missing payload, old rows, or hand-typed JSON without gameId)
  // degrade to a plain text message.
  final Map<String, dynamic>? invitePayload = dm.gameInvitePayload;

  // thinking_of_you → messageType.text + messageSubType.thinking_of_you
  // (the group bubble keys the thinking-of-you styling off the
  // subtype, same as it does for any other special text rendering).
  if (dm.isThinkingOfYou) {
    return ChatMessage(
      id: dm.id,
      senderId: dm.senderId,
      senderName: senderName,
      senderInitials: senderInitials,
      content: dm.content,
      messageType: MessageType.text,
      timestamp: dm.createdAt,
      isRead: dm.isRead,
      messageStatus: messageStatus,
      messageSubType: 'thinking_of_you',
    );
  }

  if (dm.isGameInvite && invitePayload != null) {
    // Parse the invite payload the same way the old DM-only card did.
    final gameType = (invitePayload['gameType'] as String? ?? '').trim();
    final gameId = invitePayload['gameId'] as String? ?? '';
    final roomCode = (invitePayload['roomCode'] as String? ?? '').trim();
    final maxPlayers = (invitePayload['maxPlayers'] as num?)?.toInt();
    final currentPlayers = (invitePayload['currentPlayers'] as num?)?.toInt();
    // The DM invite payload stores the host's familyId (the family the
    // game lives in). The shared card needs it for the Join route:
    // /family/<familyId>/<gameType>/lobby?join=<gameId>. We stash it
    // on the ChatMessage via the groupId field (which the group card
    // uses for sub-group scoping, not routing) — NO, that would
    // conflict. Instead, the DM screen passes inviteFamilyId to
    // MessageBubble directly from the payload (see direct_chat_screen).
    // Here we only fill the card-display fields.
    final inviteStatus = (invitePayload['status'] as String?) ?? 'pending';

    return ChatMessage(
      id: dm.id,
      senderId: dm.senderId,
      senderName: senderName,
      senderInitials: senderInitials,
      content: dm.content,
      messageType: MessageType.gameInvite,
      timestamp: dm.createdAt,
      isRead: dm.isRead,
      messageStatus: messageStatus,
      gameType: gameType.isNotEmpty ? gameType : null,
      gameId: gameId.isNotEmpty ? gameId : null,
      roomCode: roomCode.isNotEmpty ? roomCode : null,
      gameMaxPlayers: maxPlayers,
      gameCurrentPlayers: currentPlayers,
      gameInviteStatus: inviteStatus,
    );
  }

  // Plain text message (including gameInvite DMs whose payload is
  // missing/malformed — degrade to text so the thread never breaks).
  return ChatMessage(
    id: dm.id,
    senderId: dm.senderId,
    senderName: senderName,
    senderInitials: senderInitials,
    content: dm.content,
    messageType: MessageType.text,
    timestamp: dm.createdAt,
    isRead: dm.isRead,
    messageStatus: messageStatus,
  );
}

/// Convert a whole list of [DirectMessage]s into [ChatMessage]s in one
/// pass. The output list is in the SAME order as the input (newest-
/// first, matching DirectChatState.messages).
List<ChatMessage> directMessagesToChatMessages(
  List<DirectMessage> dms, {
  required String? myUserId,
  String? myName,
  String? peerName,
}) {
  return dms
      .map((dm) => directMessageToChatMessage(
            dm,
            myUserId: myUserId,
            myName: myName,
            peerName: peerName,
          ))
      .toList(growable: false);
}

/// Compute the sender's initials from their display name — mirrors the
/// group chat_provider's _initialsFromName so DM bubbles show the same
/// avatar style.
String _initialsFromName(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '?';
  if (parts.length == 1) {
    return parts.first[0].toUpperCase();
  }
  return (parts.first[0] + parts[1][0]).toUpperCase();
}

/// Resolve the current user's display name from a Supabase user, the
/// same way the group ChatNotifier._currentUserName does. Used by the
/// memoized DM provider so the adapter doesn't need a Ref.
String resolveMyName(dynamic currentUser) {
  if (currentUser == null) return 'You';
  final meta = currentUser.userMetadata;
  final name = meta?['name'] as String? ??
      meta?['full_name'] as String? ??
      meta?['displayName'] as String?;
  if (name != null && name.trim().isNotEmpty) return name.trim();
  final email = currentUser.email;
  if (email != null) return email.split('@').first;
  return 'You';
}

// ═══════════════════════════════════════════════════════════════════════
// Memoized derived provider — DM state → List<ChatMessage>
// ═══════════════════════════════════════════════════════════════════════
//
// The shared ChatMessageList / MessageBubble widgets take a
// List<ChatMessage>. The DM provider (DirectChatNotifier) exposes a
// List<DirectMessage>. This derived provider bridges the two: it watches
// directChatProvider(otherUserId) and maps the DM list to a ChatMessage
// list ONCE per state change (not on every rebuild).
//
// Riverpod's Provider caches the result until one of its dependencies
// changes. The only dependency here is directChatProvider(otherUserId),
// which only emits a new DirectChatState when the DM list actually
// changes (new message, read-receipt flip, etc.). So the conversion
// runs exactly once per DM state change — the shared widgets can call
// directChatMessagesProvider(otherUserId) on every rebuild without
// re-running the adapter.
//
// autoDispose: the DM screen is a route-scoped widget; when the user
// pops back to the inbox, the provider disposes and the cached list is
// freed. family: keyed by the other user's id (same key as
// directChatProvider).

final directChatMessagesProvider =
    Provider.autoDispose.family<List<ChatMessage>, String>((ref, otherUserId) {
  // Watch the DM state — re-runs this builder only when the state
  // actually changes (Riverpod's referential equality check).
  final dmState = ref.watch(directChatProvider(otherUserId));
  final dms = dmState.messages;
  if (dms.isEmpty) return const [];

  // Resolve the current user's id + name ONCE per state change. The
  // supabaseProvider is watched so a sign-in/sign-out re-runs the
  // conversion (otherwise a stale myUserId would mislabel sent vs
  // received messages after an account switch on the same device).
  final client = ref.watch(supabaseProvider);
  final myUserId = client?.auth.currentUser?.id;
  final myName = resolveMyName(client?.auth.currentUser);

  // The peer name comes from the DM state (resolved by DirectChatNotifier
  // via fn_get_user_public_profile). Fall back to a neutral string if
  // the peer hasn't loaded yet — the bubble will re-render with the
  // real name once the peer resolves (the state change re-runs this
  // builder).
  final peerName = dmState.peer?.name;

  return directMessagesToChatMessages(
    dms,
    myUserId: myUserId,
    myName: myName,
    peerName: peerName,
  );
});

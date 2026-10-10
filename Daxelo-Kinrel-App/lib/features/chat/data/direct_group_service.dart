// lib/features/chat/data/direct_group_service.dart
//
// DAXELO KINREL — Direct Group Service (Kin Thread / Part C2)
//
// Direct chat is now a PRIVATE 2-PERSON GROUP on the same backend as
// group chat: a "Group" row with groupType='direct' + a directKey (the
// two user ids sorted + joined), living inside a family both users
// belong to. Messages are ChatMessage rows scoped by groupId — the SAME
// provider, screen, widgets, and lifecycle as the group chat.
//
// This file replaces the old DirectMessage-based stack
// (direct_message_provider.dart / direct_message_adapter.dart /
// direct_chat_screen.dart — deleted in the same PR):
//   • getOrCreateDirectGroup() — wraps the fn_get_or_create_direct_group
//     RPC (created by supabase/migrations/20261101120000_*.sql).
//   • openDirectChat() — the ONE helper every DM entry point calls.
//     NOTE: this depends on the C1 migration being applied to the
//     database. If the RPC is missing, the helper surfaces a clear
//     error instead of crashing.
//   • directGroupInboxProvider — the global inbox of direct groups
//     (name, avatar, last message, unread count, archive state — the
//     archive key stays `dm_archived_$otherUserId` so existing user
//     choices keep working).
//   • familyDmPartnersProvider — the family-scoped Direct tab data
//     (recent conversations vs available members).
//
// Privacy: RLS (see the C1 migration) makes direct groups readable ONLY
// by their two GroupMembers. Direct groups are excluded from every
// group list (groupType <> 'direct' filters).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/family/family_provider.dart';
import '../providers/chat_provider.dart';

extension _TruncateDirectGroup on String {
  String truncateTo(int maxLen) =>
      length <= maxLen ? this : '${substring(0, maxLen)}…';
}

// ═══════════════════════════════════════════════════════════════════════
// RPC wrapper
// ═══════════════════════════════════════════════════════════════════════

/// The resolved direct group between the current user and another user.
class DirectGroupInfo {
  const DirectGroupInfo({
    required this.groupId,
    required this.familyId,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserAvatar,
  });

  final String groupId;
  final String familyId;
  final String otherUserId;
  final String otherUserName;
  final String? otherUserAvatar;
}

/// Finds or creates the private direct group between the current user
/// and [otherUserId]. [familyId] is the family the chat was started
/// from; when null, the RPC picks the OLDEST family both users share.
/// Returns null on failure (not signed in, no shared family, or the C1
/// migration has not been applied yet — the caller surfaces an error).
Future<DirectGroupInfo?> getOrCreateDirectGroup({
  required String otherUserId,
  String? familyId,
}) async {
  final client = Supabase.instance.client;
  final myUserId = client.auth.currentUser?.id;
  if (myUserId == null || otherUserId.isEmpty) return null;
  try {
    final response = await client.rpc(
      'fn_get_or_create_direct_group',
      params: {
        'p_other_user_id': otherUserId,
        'p_family_id': familyId,
      },
    ).timeout(const Duration(seconds: 10));
    if (response is! Map<String, dynamic>) return null;
    if ((response['success'] as bool? ?? false) != true) {
      debugPrint('⚠️ getOrCreateDirectGroup RPC error: ${response['error']}');
      return null;
    }
    return DirectGroupInfo(
      groupId: response['groupId'] as String? ?? '',
      familyId: response['familyId'] as String? ?? familyId ?? '',
      otherUserId: otherUserId,
      otherUserName: response['otherUserName'] as String? ?? 'Member',
      otherUserAvatar: response['otherUserAvatar'] as String?,
    );
  } catch (e) {
    // Most common cause: the C1 migration (fn_get_or_create_direct_group)
    // has not been applied to this database yet.
    debugPrint('⚠️ getOrCreateDirectGroup failed: $e');
    return null;
  }
}

/// The ONE DM entry point (Kin Thread C2). Resolves/creates the direct
/// group and opens the SAME group chat screen the family chat uses,
/// with the direct capabilities applied. Every place that used to open
/// `/dm/:otherUserId` now calls this.
///
/// Depends on the C1 migration being applied to the database.
Future<void> openDirectChat(
  BuildContext context, {
  required String otherUserId,
  String? familyId,
}) async {
  final resolved = await getOrCreateDirectGroup(
    otherUserId: otherUserId,
    familyId: familyId,
  );
  if (!context.mounted) return;
  if (resolved == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
            'Direct chat is unavailable right now (no shared family, or a '
            'pending database update).'),
        backgroundColor: Color(0xFF191B2C),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return;
  }
  await context.push('/family/${resolved.familyId}/direct/$otherUserId');
}

// ═══════════════════════════════════════════════════════════════════════
// Game invites into a direct group (same code path as the group chat)
// ═══════════════════════════════════════════════════════════════════════

/// Sends a game invite to ONE specific member as a PRIVATE direct-group
/// message — the exact same code path, shared GameInviteCard, and
/// lifecycle sync as the group chat (ChatNotifier.sendGameInvite with
/// the direct group's id). Replaces the old sendGameInviteDm.
///
/// [notifier] must be captured BEFORE any await (callers may pop their
/// widget while this runs) — pass the family's ChatNotifier.
Future<void> sendDirectGroupGameInvite({
  required ChatNotifier notifier,
  required String toUserId,
  required String gameType,
  required String gameId,
  required String roomCode,
  required int maxPlayers,
  required int currentPlayers,
  String? content,
  String? familyId,
}) async {
  final group = await getOrCreateDirectGroup(
    otherUserId: toUserId,
    familyId: familyId,
  );
  if (group == null) {
    debugPrint(
        '⚠️ sendDirectGroupGameInvite: could not resolve a direct group for $toUserId');
    return;
  }
  await notifier.sendGameInvite(
    gameType: gameType,
    gameId: gameId,
    roomCode: roomCode,
    maxPlayers: maxPlayers,
    currentPlayers: currentPlayers,
    content: content,
    groupId: group.groupId,
  );
}

// ═══════════════════════════════════════════════════════════════════════
// Inbox
// ═══════════════════════════════════════════════════════════════════════

/// One direct-group conversation row for the inbox: the OTHER person's
/// identity, the last message, and the unread count (system rows
/// excluded, per the Kin Thread unread rules).
class DirectGroupInboxItem {
  const DirectGroupInboxItem({
    required this.groupId,
    required this.familyId,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserAvatar,
    required this.lastMessage,
    required this.lastMessageTime,
    required this.unreadCount,
    required this.isArchived,
  });

  final String groupId;
  final String familyId;
  final String otherUserId;
  final String otherUserName;
  final String? otherUserAvatar;
  final String lastMessage;
  final DateTime lastMessageTime;
  final int unreadCount;
  final bool isArchived;
}

/// Compact last-message preview for an inbox row (mirrors the family
/// inbox's preview rules; game invites show a friendly line).
String directGroupPreview(ChatMessage? msg) {
  if (msg == null) return '';
  switch (msg.messageType) {
    case MessageType.photo:
      return '📷 Photo';
    case MessageType.voiceNote:
      return '🎤 Voice message';
    case MessageType.familyEvent:
      return msg.content.isNotEmpty ? msg.content : 'Family moment';
    case MessageType.sticker:
      return 'Sticker';
    case MessageType.gameInvite:
      final game = msg.gameType ?? 'game';
      return '🎮 Game invite — ${game.toUpperCase()}';
    case MessageType.poll:
      return '📊 Poll';
    case MessageType.gif:
      return 'GIF';
    case MessageType.document:
      return '📄 Document';
    case MessageType.location:
      return '📍 Location';
    case MessageType.system:
      return msg.content; // join notices preview their text
    case MessageType.text:
      return msg.content;
  }
}

/// The global direct-group inbox: every direct group the current user
/// belongs to, newest-activity-first. Archive state lives in
/// shared_preferences under `dm_archived_$otherUserId` (same key the
/// old DirectMessage inbox used, so existing archives carry over).
///
/// NOTE (data source): direct groups are Group rows the RLS lets only
/// their two members see, so this query is inherently private.
final directGroupInboxProvider =
    FutureProvider<List<DirectGroupInboxItem>>((ref) async {
  final client = Supabase.instance.client;
  final myUserId = client.auth.currentUser?.id;
  if (myUserId == null) return [];

  final prefs = await SharedPreferences.getInstance();

  try {
    // 1. My direct-group memberships.
    final memberships = await client
        .from('GroupMember')
        .select('groupId')
        .eq('userId', myUserId)
        .timeout(const Duration(seconds: 8));
    final groupIds = (memberships as List)
        .map((e) => (e as Map<String, dynamic>)['groupId'] as String?)
        .whereType<String>()
        .toList();
    if (groupIds.isEmpty) return [];

    // 2. The direct groups among them (RLS hides groups I'm not in).
    final groupsResp = await client
        .from('Group')
        .select()
        .inFilter('id', groupIds)
        .eq('groupType', 'direct')
        .order('lastActivityAt', ascending: false)
        .timeout(const Duration(seconds: 8));
    final groups = groupsResp as List;
    if (groups.isEmpty) return [];

    final items = <DirectGroupInboxItem>[];
    for (final g in groups) {
      final gMap = g as Map<String, dynamic>;
      final groupId = gMap['id'] as String? ?? '';
      final familyId = gMap['familyId'] as String? ?? '';
      if (groupId.isEmpty) continue;

      // 3. The other member (RLS lets me see my direct groups' members).
      final others = await client
          .from('GroupMember')
          .select()
          .eq('groupId', groupId)
          .neq('userId', myUserId)
          .limit(1)
          .timeout(const Duration(seconds: 5));
      if (others.isEmpty) continue;
      final other = others.first as Map<String, dynamic>;
      final otherUserId = other['userId'] as String? ?? '';
      if (otherUserId.isEmpty) continue;
      final otherUserName =
          other['displayName'] as String? ?? gMap['name'] as String? ?? 'Member';

      // 4. Last message + unread count (system rows never count).
      ChatMessage? last;
      try {
        final lastResp = await client
            .from('ChatMessage')
            .select()
            .eq('groupId', groupId)
            .eq('isDeletedForEveryone', false)
            .order('createdAt', ascending: false)
            .limit(1)
            .timeout(const Duration(seconds: 5));
        if (lastResp.isNotEmpty) {
          last = ChatMessage.fromJson(
              lastResp.first as Map<String, dynamic>);
        }
      } catch (_) {}

      var unread = 0;
      try {
        final unreadResp = await client
            .from('ChatMessage')
            .select('id')
            .eq('groupId', groupId)
            .eq('isDeletedForEveryone', false)
            .eq('isRead', false)
            .neq('senderId', myUserId)
            .neq('messageType', 'system')
            .count()
            .timeout(const Duration(seconds: 5));
        unread = unreadResp.count;
      } catch (_) {}

      items.add(DirectGroupInboxItem(
        groupId: groupId,
        familyId: familyId,
        otherUserId: otherUserId,
        otherUserName: otherUserName,
        otherUserAvatar: null,
        lastMessage: directGroupPreview(last).truncateTo(40),
        lastMessageTime: last?.timestamp ??
            DateTime.tryParse(gMap['updatedAt'] as String? ?? '') ??
            DateTime.tryParse(gMap['createdAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        unreadCount: unread,
        isArchived: prefs.getBool('dm_archived_$otherUserId') ?? false,
      ));
    }

    items.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
    return items;
  } catch (e) {
    debugPrint('⚠️ directGroupInboxProvider error: $e');
    return [];
  }
});

// ═══════════════════════════════════════════════════════════════════════
// Family-scoped Direct tab data (recent vs available)
// ═══════════════════════════════════════════════════════════════════════

/// A direct-chat partner who belongs to the currently-selected family.
/// (Same shape as the old DirectMessage-era class so the Direct tab UI
/// is unchanged.)
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

class FamilyDmPartnersResult {
  const FamilyDmPartnersResult({required this.recent, required this.available});
  final List<FamilyDmPartner> recent;
  final List<FamilyDmPartner> available;
}

/// Family-scoped direct-group partners: combines the global
/// [directGroupInboxProvider] with the family roster so the Direct tab
/// only ever shows members of the currently-selected family.
final familyDmPartnersProvider =
    FutureProvider.family<FamilyDmPartnersResult, String>((ref, familyId) async {
  final client = Supabase.instance.client;
  final myUserId = client.auth.currentUser?.id;
  if (myUserId == null) {
    return const FamilyDmPartnersResult(recent: [], available: []);
  }

  final inbox = await ref.read(directGroupInboxProvider.future);

  final rosterAsync = ref.watch(unifiedFamilyRosterProvider(familyId));
  final roster = rosterAsync.valueOrNull ?? const [];

  final rosterByUserId = <String, UnifiedFamilyMember>{};
  for (final m in roster) {
    final uid = m.userId;
    if (uid == null || uid.isEmpty) continue;
    if (uid == myUserId) continue;
    rosterByUserId[uid] = m;
  }

  // Recent conversations: direct groups whose other party is in THIS
  // family's roster (a direct group lives in ONE family, but the pair
  // may share several — the entry point decides which family's tab it
  // appears under; showing it under the family it was started from).
  final recent = <FamilyDmPartner>[];
  final seenUserIds = <String>{};
  for (final dm in inbox) {
    if (dm.isArchived) continue;
    final entry = rosterByUserId[dm.otherUserId];
    if (entry == null) continue;
    recent.add(FamilyDmPartner(
      userId: dm.otherUserId,
      displayName:
          dm.otherUserName.isNotEmpty ? dm.otherUserName : entry.displayName,
      avatarUrl: entry.avatarUrl,
      lastMessage: dm.lastMessage,
      lastMessageTime: dm.lastMessageTime,
      unreadCount: dm.unreadCount,
      hasConversation: true,
    ));
    seenUserIds.add(dm.otherUserId);
  }
  recent.sort((a, b) {
    final at = a.lastMessageTime ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bt = b.lastMessageTime ?? DateTime.fromMillisecondsSinceEpoch(0);
    return bt.compareTo(at);
  });

  // Available members: Kinrel users in this family with no direct chat yet.
  final available = <FamilyDmPartner>[];
  for (final entry in rosterByUserId.values) {
    if (seenUserIds.contains(entry.userId)) continue;
    available.add(FamilyDmPartner(
      userId: entry.userId!,
      displayName: entry.displayName,
      avatarUrl: entry.avatarUrl,
      hasConversation: false,
    ));
  }
  available.sort((a, b) => a.displayName.compareTo(b.displayName));

  return FamilyDmPartnersResult(recent: recent, available: available);
});

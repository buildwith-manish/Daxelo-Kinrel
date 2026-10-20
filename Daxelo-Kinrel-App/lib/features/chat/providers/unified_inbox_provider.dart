// lib/features/chat/providers/unified_inbox_provider.dart
//
// DAXELO KINREL — Unified Chat Inbox Provider
//
// Replaces the two-section chat inbox (Groups + Direct Messages) with
// ONE list of UnifiedChatEntry rows sorted by lastMessageTime
// descending. Moves the group last-message + unread logic OUT of the
// row widget (the previous _FamilyChatRow did its own N+1 queries in
// initState) into a single batched load here.
//
// Data sources:
//   • Groups  → familyListProvider (Drift stream — already loaded) +
//     TWO batched Supabase queries: one for the latest family-wide
//     message of every family, one for the unread counts.
//   • Directs → directGroupInboxProvider (existing FutureProvider —
//     already loads all direct-group rows in one place; the inner
//     per-group queries are left as-is for v1 since DMs are bounded
//     by the user's direct-group count, typically small).
//
// The provider merges both into a single List<UnifiedChatEntry>,
// filters out archived entries, and sorts by:
//   1. lastMessageTime descending (entries with messages on top)
//   2. entries without messages go to the bottom, sorted by title
//   3. ties broken by id (deterministic)
//
// Realtime: the inbox does NOT subscribe to realtime updates today
// (Phase 0 confirmed). The provider rebuilds when familyListProvider
// or directGroupInboxProvider emits a new value (Drift stream for the
// former; explicit invalidation for the latter). New messages still
// need a pull-to-refresh or a re-enter of the screen to move a chat
// to the top — same UX as before. Live updates are flagged as a gap
// in the final report.
//
// The filter state (All / Unread / Groups / Direct) is owned by
// the chat_inbox_screen and persisted only in-memory across rebuilds
// (a separate StateProvider). Not persisted across app restarts.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import '../../../core/family/family_provider.dart';
import '../../../core/services/supabase_service.dart';
import '../../chat/data/direct_group_service.dart';
import '../../chat/data/models/chat_message.dart';
import '../../chat/data/models/message_type.dart';
// Phase 2 — Circles: batched circle inbox loading (same pattern as
// the group batched meta loader above).
import '../../circle/data/circle_api_client.dart' as circle_api;

/// The kind of conversation a UnifiedChatEntry represents.
enum UnifiedChatKind { group, direct, circle }

/// One row in the unified inbox list. Mirrors the union of:
///   • Family (group row) — id, name, avatarUrl, last message, unread
///   • DirectGroupInboxItem (direct row) — the other person's identity
///     + last message + unread.
///
/// The `previewText` field is the locale-independent wire form (the
/// row widget formats it for display). `previewSenderName` is set for
/// group chats so the row can prefix the preview with "Name: message"
/// when the sender is known and is not the current viewer.
class UnifiedChatEntry {
  const UnifiedChatEntry({
    required this.kind,
    required this.id,
    required this.title,
    required this.avatarUrl,
    required this.lastMessage,
    required this.lastMessageTime,
    required this.unreadCount,
    required this.isArchived,
    this.previewSenderName,
    this.familyId,
    this.otherUserId,
    this.groupId,
    this.circleId,
    this.iconKey,
  });

  /// Group → familyId; Direct → otherUserId. Used as the Dismissible
  /// key + as the route argument.
  final UnifiedChatKind kind;

  /// Group → family.id; Direct → otherUserId (so the Dismissible key
  /// is unique across both kinds).
  final String id;

  /// Group → family.name; Direct → otherUserName.
  final String title;

  /// Group → family.avatarUrl; Direct → otherUserAvatar (currently null
  /// from directGroupInboxProvider — left as a follow-up).
  final String? avatarUrl;

  /// The display-ready preview (already truncated + type-formatted
  /// via the existing directGroupPreview / familyPreview logic).
  final String lastMessage;

  /// UTC time of the last message (or the family's updatedAt if no
  /// messages exist — so "no message" rows still sort deterministically).
  final DateTime lastMessageTime;

  final int unreadCount;
  final bool isArchived;

  /// For group rows: the sender's display name when known + not the
  /// current viewer. Null for DMs (the row shows just the message).
  final String? previewSenderName;

  /// Group → familyId; Direct → the DM's familyId (used by the route).
  final String? familyId;

  /// Direct → otherUserId (used by the DM openDirectChat route).
  final String? otherUserId;

  /// Direct → the direct-group's groupId (used by DM navigation).
  final String? groupId;

  /// Circle → the circle's id (used by circle navigation).
  final String? circleId;

  /// Circle → the icon key (used for the rounded-square icon tile).
  final String? iconKey;

  /// True when this entry has at least one message (lastMessage non-empty
  /// AND lastMessageTime is post-epoch). Entries without messages go to
  /// the bottom of the list.
  bool get hasMessages =>
      lastMessage.isNotEmpty &&
      lastMessageTime.isAfter(DateTime.fromMillisecondsSinceEpoch(0));

  /// The semantic-label prefix for screen readers: "Group chat" or
  /// "Direct message".
  String get semanticKindLabel =>
      kind == UnifiedChatKind.group ? 'Group chat' : 'Direct message';
}

/// Filter chip selection for the inbox.
enum UnifiedInboxFilter { all, unread, groups, direct, circles }

/// The merged inbox list. Built by watching familyListProvider +
/// directGroupInboxProvider and doing the batched last-message +
/// unread queries in a build() helper.
///
/// The result is sorted: entries with messages first (newest
/// lastMessageTime first), then entries without messages (sorted by
/// title). Ties broken by id (deterministic).
final unifiedInboxProvider =
    FutureProvider.autoDispose<List<UnifiedChatEntry>>((ref) async {
  // Watch familyListProvider (Drift stream → AsyncValue<List<Family>>).
  // Using `.future` blocks until the first emission, then re-builds on
  // subsequent emissions.
  final families = await ref.watch(familyListProvider.future);
  // Watch directGroupInboxProvider (FutureProvider → List<DirectGroupInboxItem>).
  final dms = await ref.watch(directGroupInboxProvider.future);

  // ── Batched group queries ──────────────────────────────────────
  // ONE query for the latest family-wide message per family (up to 200
  // rows — covers ~all users' family counts). ONE query for the
  // unread rows' familyIds. Then merge client-side.
  final groupMeta = await _loadGroupBatchedMeta(ref, families);

  // ── Merge into unified entries ─────────────────────────────────
  final entries = <UnifiedChatEntry>[];

  // Groups.
  for (final family in families) {
    final meta = groupMeta[family.id];
    entries.add(UnifiedChatEntry(
      kind: UnifiedChatKind.group,
      id: family.id,
      title: family.name,
      avatarUrl: family.avatarUrl,
      lastMessage: meta?.preview ?? '',
      lastMessageTime: meta?.lastMessageTime ?? family.lastActivityAt ?? family.createdAt ?? DateTime.now(),
      unreadCount: meta?.unreadCount ?? 0,
      isArchived: false, // archived groups are filtered upstream
      previewSenderName: meta?.senderName,
      familyId: family.id,
    ));
  }

  // Directs.
  for (final dm in dms) {
    entries.add(UnifiedChatEntry(
      kind: UnifiedChatKind.direct,
      id: dm.otherUserId,
      title: dm.otherUserName,
      avatarUrl: dm.otherUserAvatar,
      lastMessage: dm.lastMessage,
      lastMessageTime: dm.lastMessageTime,
      unreadCount: dm.unreadCount,
      isArchived: dm.isArchived,
      familyId: dm.familyId,
      otherUserId: dm.otherUserId,
      groupId: dm.groupId,
    ));
  }

  // ── Phase 2 — Circles ──────────────────────────────────────────
  // Account-level circles are loaded via the circle_api_client's
  // batched loader (3 queries total — same pattern as the group
  // batched meta loader above). Circles are independent of the
  // active family — they always appear in the inbox regardless of
  // the family switcher selection.
  final circles = await circle_api.loadCircleInboxItems();
  for (final c in circles) {
    entries.add(UnifiedChatEntry(
      kind: UnifiedChatKind.circle,
      id: c.id,
      title: c.name,
      avatarUrl: c.avatarUrl,
      lastMessage: c.lastMessage,
      lastMessageTime: c.lastMessageTime,
      unreadCount: c.unreadCount,
      isArchived: c.isArchived,
      previewSenderName: c.lastSenderName,
      circleId: c.id,
      iconKey: c.iconKey,
    ));
  }

  // ── Sort: messages-first (newest), then no-messages by title ──
  entries.sort((a, b) {
    final aHas = a.hasMessages;
    final bHas = b.hasMessages;
    if (aHas != bHas) return aHas ? -1 : 1; // messages-first
    if (aHas) {
      // Both have messages — newest first.
      final cmp = b.lastMessageTime.compareTo(a.lastMessageTime);
      if (cmp != 0) return cmp;
      // Tie: title, then id.
      final titleCmp = a.title.toLowerCase().compareTo(b.title.toLowerCase());
      if (titleCmp != 0) return titleCmp;
      return a.id.compareTo(b.id);
    }
    // Neither has messages — sort by title, then id.
    final titleCmp = a.title.toLowerCase().compareTo(b.title.toLowerCase());
    if (titleCmp != 0) return titleCmp;
    return a.id.compareTo(b.id);
  });

  // Filter out archived entries (they're shown via the separate Archived row).
  // Group archives are filtered here; DM archives are also filtered here.
  return entries.where((e) => !e.isArchived).toList(growable: false);
});

/// The currently-selected filter chip. Survives across rebuilds (held
/// in a StateProvider so it's stable while the app is open; not
/// persisted across app restarts per spec).
final unifiedInboxFilterProvider =
    StateProvider.autoDispose<UnifiedInboxFilter>((ref) => UnifiedInboxFilter.all);

// ═══════════════════════════════════════════════════════════════════════
// Batched group meta loader
// ═══════════════════════════════════════════════════════════════════════

/// Per-family batched metadata (last message preview + sender name +
/// last message time + unread count).
class _GroupMeta {
  _GroupMeta({
    this.preview = '',
    this.senderName,
    required this.lastMessageTime,
    this.unreadCount = 0,
  });
  final String preview;
  final String? senderName;
  final DateTime lastMessageTime;
  final int unreadCount;
}

/// TWO batched Supabase queries for ALL families in one shot:
///   1. Latest family-wide messages (up to 200 rows, then take newest
///      per family client-side).
///   2. Unread rows' familyIds (count per family client-side).
///
/// Replaces the per-row queries that _FamilyChatRowState used to do.
/// Never throws — a query failure degrades to "no preview / 0 unread"
/// for the affected families (same UX as before).
Future<Map<String, _GroupMeta>> _loadGroupBatchedMeta(
  Ref ref,
  List<Family> families,
) async {
  if (families.isEmpty) return {};
  final client = ref.read(supabaseProvider);
  if (client == null) return {};
  final myUserId = client.auth.currentUser?.id;
  if (myUserId == null) return {};

  final familyIds = families.map((f) => f.id).toList();
  final result = <String, _GroupMeta>{};

  // ── 1. Latest family-wide messages (batched) ───────────────────
  // Reuses the EXACT same filters as the original per-row query:
  //   familyId IN (...), isDeletedForEveryone = false, groupId IS NULL,
  //   ORDER BY createdAt DESC, LIMIT 200.
  // Then group client-side by familyId and take newest per family.
  try {
    final lastMsgsResp = await client
        .from('ChatMessage')
        .select()
        .inFilter('familyId', familyIds)
        .eq('isDeletedForEveryone', false)
        .isFilter('groupId', null)
        .order('createdAt', ascending: false)
        .limit(200)
        .timeout(const Duration(seconds: 10));
    final rows = lastMsgsResp as List? ?? const [];
    for (final row in rows) {
      if (row is! Map) continue;
      final famId = row['familyId'] as String?;
      if (famId == null || famId.isEmpty) continue;
      if (result.containsKey(famId)) continue; // first occurrence = newest (DESC order)
      final msg = ChatMessage.fromJson(row.cast<String, dynamic>());
      final rawSenderName = row['senderName'] as String?;
      final senderName = (rawSenderName ?? '').isNotEmpty
          ? rawSenderName
          : null;
      result[famId] = _GroupMeta(
        preview: _familyWidePreview(msg),
        // For the sender-name prefix: only set if the sender is NOT the
        // current viewer (matches the spec). If sender == me → null
        // (the row will NOT prefix the preview).
        senderName: (msg.senderId != myUserId && (senderName ?? '').isNotEmpty)
            ? senderName
            : null,
        lastMessageTime: msg.timestamp,
      );
    }
  } catch (e) {
    debugPrint('⚠️ unifiedInboxProvider: batched last-message query failed: $e');
  }

  // Fill in entries for families that had NO messages (so the sort
  // still works deterministically — they sort to the bottom by title).
  for (final fam in families) {
    if (!result.containsKey(fam.id)) {
      result[fam.id] = _GroupMeta(
        preview: '',
        lastMessageTime: fam.lastActivityAt ?? fam.createdAt ?? DateTime.now(),
        unreadCount: 0,
      );
    } else {
      // Carry over the family.updatedAt as the fallback time (so a
      // family with no messages but a recent family-row update still
      // sorts near the bottom of the messages-having group).
      final existing = result[fam.id]!;
      if (!existing.lastMessageTime
          .isAfter(DateTime.fromMillisecondsSinceEpoch(0))) {
        result[fam.id] = _GroupMeta(
          preview: existing.preview,
          senderName: existing.senderName,
          lastMessageTime: fam.lastActivityAt ?? fam.createdAt ?? DateTime.now(),
          unreadCount: 0,
        );
      }
    }
  }

  // ── 2. Unread counts (batched) ─────────────────────────────────
  // Reuses the EXACT same unread criteria as the original per-row query:
  //   familyId IN (...), isDeletedForEveryone = false, isRead = false,
  //   senderId != me, groupId IS NULL, messageType != 'system'.
  // Fetches all matching rows' familyId, then counts per family
  // client-side. (Could be large if the user has many unread — but
  // in practice bounded by the unread volume; if it becomes a problem
  // a future RPC can return counts server-side. Out of scope for v1.)
  try {
    final unreadResp = await client
        .from('ChatMessage')
        .select('familyId')
        .inFilter('familyId', familyIds)
        .eq('isDeletedForEveryone', false)
        .eq('isRead', false)
        .neq('senderId', myUserId)
        .isFilter('groupId', null)
        .neq('messageType', 'system')
        .timeout(const Duration(seconds: 10));
    final rows = unreadResp as List? ?? const [];
    final counts = <String, int>{};
    for (final row in rows) {
      if (row is! Map) continue;
      final famId = row['familyId'] as String?;
      if (famId == null || famId.isEmpty) continue;
      counts[famId] = (counts[famId] ?? 0) + 1;
    }
    for (final fam in families) {
      final existing = result[fam.id];
      if (existing == null) continue;
      result[fam.id] = _GroupMeta(
        preview: existing.preview,
        senderName: existing.senderName,
        lastMessageTime: existing.lastMessageTime,
        unreadCount: counts[fam.id] ?? 0,
      );
    }
  } catch (e) {
    debugPrint('⚠️ unifiedInboxProvider: batched unread query failed: $e');
  }

  return result;
}

/// The family-wide preview format (mirrors the existing
/// _FamilyChatRowState's _previewForMessage method + the
/// directGroupPreview method so previews look identical to today).
String _familyWidePreview(ChatMessage msg) {
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

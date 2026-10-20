// lib/features/circle/data/circle_api_client.dart
//
// DAXELO KINREL — Circle API Client (Phase 2)
//
// Supabase-direct client for account-level circles. Uses the same
// pattern as direct_group_service.dart — direct table queries +
// realtime subscriptions, no REST API hop.
//
// The NestJS CircleController REST endpoints (Phase 1) are available
// for fallback, but the inbox loading path uses Supabase direct
// queries (batched — same pattern as unifiedInboxProvider) to avoid
// the round-trip cost.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart' show supabaseProvider;

/// A circle's inbox metadata (last message + unread + settings).
class CircleInboxItem {
  const CircleInboxItem({
    required this.id,
    required this.name,
    required this.iconKey,
    required this.avatarUrl,
    required this.onlyAdminsPost,
    required this.anyoneCanAdd,
    required this.memberCount,
    required this.lastMessage,
    required this.lastMessageTime,
    required this.lastSenderName,
    required this.unreadCount,
    required this.isArchived,
    required this.mutedUntil,
    required this.myRole,
  });

  final String id;
  final String name;
  final String iconKey;
  final String? avatarUrl;
  final bool onlyAdminsPost;
  final bool anyoneCanAdd;
  final int memberCount;
  final String lastMessage;
  final DateTime lastMessageTime;
  final String? lastSenderName;
  final int unreadCount;
  final bool isArchived;
  final DateTime? mutedUntil;
  final String myRole; // admin | member
}

/// Creates a circle via Supabase direct insert. The RLS policy
/// `circle_insert_owner` ensures `ownerId = auth.uid()`.
/// The creator is auto-added as admin via the `fn_create_circle`
/// RPC (if available) OR via two inserts in sequence.
///
/// Returns the new circle's id. Throws on failure.
Future<String> createCircleDirect({
  required String name,
  String? description,
  String iconKey = 'default',
  bool onlyAdminsPost = false,
  bool anyoneCanAdd = false,
  List<String> memberUserIds = const [],
}) async {
  final client = _getClient();
  if (client == null) throw Exception('Not signed in');
  final myUserId = client.auth.currentUser?.id;
  if (myUserId == null) throw Exception('Not signed in');

  // ── Step 1: Create the Circle row ────────────────────────────
  final circleId =
      'circle_${DateTime.now().millisecondsSinceEpoch}';
  await client.from('Circle').insert({
    'id': circleId,
    'ownerId': myUserId,
    'name': name,
    if (description != null) 'description': description,
    'iconKey': iconKey,
    'onlyAdminsPost': onlyAdminsPost,
    'anyoneCanAdd': anyoneCanAdd,
  });

  // ── Step 2: Add the creator as admin ─────────────────────────
  await client.from('CircleMember').insert({
    'id': 'cm_${circleId}_$myUserId',
    'circleId': circleId,
    'userId': myUserId,
    'role': 'admin',
    'displayName': '',
  });

  // ── Step 3: Add initial members (each subject to RLS eligibility) ──
  for (final userId in memberUserIds) {
    if (userId == myUserId) continue;
    try {
      await client.from('CircleMember').insert({
        'id': 'cm_${circleId}_$userId',
        'circleId': circleId,
        'userId': userId,
        'role': 'member',
        'displayName': '',
      });
    } catch (e) {
      // RLS may reject (blocked, not eligible, already a member).
      // Silently skip — the user can retry individually.
      debugPrint('⚠️ createCircle: skipped $userId: $e');
    }
  }

  return circleId;
}

/// Loads ALL the user's circles + batched last-message + unread
/// metadata. Returns an empty list on error (graceful degradation).
///
/// This is the same batched pattern as `_loadGroupBatchedMeta` in
/// unified_inbox_provider.dart — 3 queries total, not N+1.
Future<List<CircleInboxItem>> loadCircleInboxItems() async {
  final client = _getClient();
  if (client == null) return const [];
  final myUserId = client.auth.currentUser?.id;
  if (myUserId == null) return const [];

  try {
    // ── 1. Load all CircleMember rows for the current user ────
    final memberResp = await client
        .from('CircleMember')
        .select(
            'circleId, role, isArchived, mutedUntil, circle:Circle(id, name, iconKey, avatarUrl, onlyAdminsPost, anyoneCanAdd, lastActivityAt)')
        .eq('userId', myUserId)
        .order('circle(lastActivityAt)', ascending: false)
        .limit(30)
        .timeout(const Duration(seconds: 10));

    if (memberResp is! List || memberResp.isEmpty) return const [];

    // Parse the joined rows
    final circles = <_ParsedCircle>[];
    for (final row in memberResp) {
      if (row is! Map) continue;
      final circle = row['circle'];
      if (circle is! Map) continue;
      circles.add(_ParsedCircle(
        id: circle['id']?.toString() ?? '',
        name: circle['name']?.toString() ?? 'Circle',
        iconKey: circle['iconKey']?.toString() ?? 'default',
        avatarUrl: circle['avatarUrl']?.toString(),
        onlyAdminsPost: circle['onlyAdminsPost'] as bool? ?? false,
        anyoneCanAdd: circle['anyoneCanAdd'] as bool? ?? false,
        lastActivityAt: circle['lastActivityAt'] != null
            ? DateTime.tryParse(circle['lastActivityAt'].toString()) ??
                DateTime.now()
            : DateTime.now(),
        role: row['role']?.toString() ?? 'member',
        isArchived: row['isArchived'] as bool? ?? false,
        mutedUntil: row['mutedUntil'] != null
            ? DateTime.tryParse(row['mutedUntil'].toString())
            : null,
      ));
    }
    if (circles.isEmpty) return const [];

    // ── 2. Member counts per circle ────────────────────────────
    final circleIds = circles.map((c) => c.id).toList();
    final memberCountResp = await client
        .from('CircleMember')
        .select('circleId')
        .inFilter('circleId', circleIds)
        .timeout(const Duration(seconds: 10));
    final countMap = <String, int>{};
    for (final row in memberCountResp as List) {
      if (row is! Map) continue;
      final cid = row['circleId']?.toString() ?? '';
      if (cid.isNotEmpty) countMap[cid] = (countMap[cid] ?? 0) + 1;
    }

    // ── 3. Last message per circle (batched — take newest) ─────
    final lastMsgResp = await client
        .from('CircleMessage')
        .select('circleId, senderName, content, messageType, createdAt')
        .inFilter('circleId', circleIds)
        .eq('isDeletedForEveryone', false)
        .order('createdAt', ascending: false)
        .limit(100)
        .timeout(const Duration(seconds: 10));
    final lastMsgMap = <String, Map<String, dynamic>>{};
    for (final row in lastMsgResp as List) {
      if (row is! Map) continue;
      final cid = row['circleId']?.toString() ?? '';
      if (cid.isEmpty || lastMsgMap.containsKey(cid)) continue;
      lastMsgMap[cid] = row.cast<String, dynamic>();
    }

    // ── 4. Unread counts per circle (batched) ──────────────────
    final unreadResp = await client
        .from('CircleMessage')
        .select('circleId')
        .inFilter('circleId', circleIds)
        .eq('isDeletedForEveryone', false)
        .neq('senderId', myUserId)
        .timeout(const Duration(seconds: 10));
    final unreadMap = <String, int>{};
    for (final row in unreadResp as List) {
      if (row is! Map) continue;
      final cid = row['circleId']?.toString() ?? '';
      if (cid.isNotEmpty) unreadMap[cid] = (unreadMap[cid] ?? 0) + 1;
    }

    // ── Merge into CircleInboxItem list ────────────────────────
    return circles.map((c) {
      final lastMsg = lastMsgMap[c.id];
      return CircleInboxItem(
        id: c.id,
        name: c.name,
        iconKey: c.iconKey,
        avatarUrl: c.avatarUrl,
        onlyAdminsPost: c.onlyAdminsPost,
        anyoneCanAdd: c.anyoneCanAdd,
        memberCount: countMap[c.id] ?? 1,
        lastMessage: lastMsg?['content']?.toString() ?? '',
        lastMessageTime: lastMsg != null
            ? DateTime.tryParse(lastMsg['createdAt']?.toString() ?? '') ??
                c.lastActivityAt
            : c.lastActivityAt,
        lastSenderName: lastMsg?['senderName']?.toString(),
        unreadCount: unreadMap[c.id] ?? 0,
        isArchived: c.isArchived,
        mutedUntil: c.mutedUntil,
        myRole: c.role,
      );
    }).toList();
  } catch (e) {
    debugPrint('⚠️ loadCircleInboxItems failed: $e');
    return const [];
  }
}

// ── Helpers ──────────────────────────────────────────────────────

SupabaseClient? _getClient() {
  try {
    return Supabase.instance.client;
  } catch (_) {
    return null;
  }
}

class _ParsedCircle {
  _ParsedCircle({
    required this.id,
    required this.name,
    required this.iconKey,
    this.avatarUrl,
    required this.onlyAdminsPost,
    required this.anyoneCanAdd,
    required this.lastActivityAt,
    required this.role,
    required this.isArchived,
    this.mutedUntil,
  });

  final String id;
  final String name;
  final String iconKey;
  final String? avatarUrl;
  final bool onlyAdminsPost;
  final bool anyoneCanAdd;
  final DateTime lastActivityAt;
  final String role;
  final bool isArchived;
  final DateTime? mutedUntil;
}

/// Curated icon set for circles (per mockup 12 — small set the user
/// can pick from when creating a circle). Each entry is a key +
/// an IconData for the rounded-square tile.
const circleIconSet = <_CircleIcon>[
  _CircleIcon(key: 'default', icon: Icons.group_rounded, label: 'Group'),
  _CircleIcon(key: 'family', icon: Icons.family_restroom_rounded, label: 'Family'),
  _CircleIcon(key: 'travel', icon: Icons.flight_takeoff_rounded, label: 'Travel'),
  _CircleIcon(key: 'celebration', icon: Icons.celebration_rounded, label: 'Party'),
  _CircleIcon(key: 'food', icon: Icons.restaurant_rounded, label: 'Food'),
  _CircleIcon(key: 'elders', icon: Icons.elderly_rounded, label: 'Elders'),
  _CircleIcon(key: 'cousins', icon: Icons.people_alt_rounded, label: 'Cousins'),
  _CircleIcon(key: 'heart', icon: Icons.favorite_rounded, label: 'Close'),
];

class _CircleIcon {
  const _CircleIcon({
    required this.key,
    required this.icon,
    required this.label,
  });
  final String key;
  final IconData icon;
  final String label;
}

/// Returns the IconData for a given iconKey (defaults to group).
IconData iconForCircleKey(String key) {
  for (final i in circleIconSet) {
    if (i.key == key) return i.icon;
  }
  return Icons.group_rounded;
}

// lib/features/family/data/group_provider.dart
//
// DAXELO KINREL — Family Groups Data Layer (v137)
//
// Models + Riverpod providers for the Family Space Groups system.
// Groups are child entities of a Family Space — they cannot exist
// standalone. This preserves Kinrel's family-first identity.
//
// Group types: cousins, parents, siblings, family_event, travel, custom
// Member roles: admin, moderator, member, guest
//
// Guest members are invited into specific groups only — they do NOT
// become Family Space members and cannot see other groups, the family
// graph, tree, memories, or map.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/supabase_service.dart';

// ── Group Type Enum ─────────────────────────────────────────────────────

/// The type of a group — determines its icon, color, and purpose.
enum GroupType {
  cousins('Cousins', Icons.group_outlined, Color(0xFFE8A872)),
  parents('Parents', Icons.family_restroom, Color(0xFF6B8AFF)),
  siblings('Siblings', Icons.people_alt_rounded, Color(0xFF8AFFB7)),
  familyEvent('Family Event', Icons.celebration_rounded, Color(0xFFFFB74D)),
  travel('Travel Group', Icons.flight_takeoff, Color(0xFFB388FF)),
  custom('Custom Group', Icons.groups_2_rounded, Color(0xFFE8612A));

  const GroupType(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;

  static GroupType fromString(String? raw) {
    return GroupType.values.firstWhere(
      (t) => t.name == raw,
      orElse: () => GroupType.custom,
    );
  }
}

// ── Models ──────────────────────────────────────────────────────────────

/// A conversation group within a Family Space.
class FamilyGroup {
  const FamilyGroup({
    required this.id,
    required this.familyId,
    required this.name,
    required this.description,
    required this.groupType,
    required this.avatarUrl,
    required this.createdBy,
    required this.lastActivityAt,
    required this.createdAt,
    required this.memberCount,
  });

  factory FamilyGroup.fromJson(Map<String, dynamic> json) {
    return FamilyGroup(
      id: json['id'] as String? ?? '',
      familyId: json['familyId'] as String? ?? '',
      name: json['name'] as String? ?? 'Unnamed Group',
      description: json['description'] as String?,
      groupType: GroupType.fromString(json['groupType'] as String?),
      avatarUrl: json['avatarUrl'] as String?,
      createdBy: json['createdBy'] as String? ?? '',
      lastActivityAt: DateTime.tryParse(json['lastActivityAt'] as String? ?? '') ?? DateTime.now(),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      memberCount: json['memberCount'] as int? ?? 0,
    );
  }

  final String id;
  final String familyId;
  final String name;
  final String? description;
  final GroupType groupType;
  final String? avatarUrl;
  final String createdBy;
  final DateTime lastActivityAt;
  final DateTime createdAt;
  final int memberCount;
}

/// A member of a group — either a family member or an invited guest.
class GroupMemberInfo {
  const GroupMemberInfo({
    required this.id,
    required this.groupId,
    required this.userId,
    required this.displayName,
    required this.role,
    required this.isGuest,
    required this.joinedAt,
    this.avatarUrl,
  });

  factory GroupMemberInfo.fromJson(Map<String, dynamic> json) {
    return GroupMemberInfo(
      id: json['id'] as String? ?? '',
      groupId: json['groupId'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      displayName: json['displayName'] as String? ?? 'Member',
      role: json['role'] as String? ?? 'member',
      isGuest: json['isGuest'] as bool? ?? false,
      joinedAt: DateTime.tryParse(json['joinedAt'] as String? ?? '') ?? DateTime.now(),
      avatarUrl: json['avatarUrl'] as String?,
    );
  }

  final String id;
  final String groupId;
  final String userId;
  final String displayName;
  final String role; // admin | moderator | member | guest
  final bool isGuest;
  final DateTime joinedAt;
  final String? avatarUrl;

  bool get isAdmin => role == 'admin';
  bool get isModerator => role == 'moderator';
  bool get canManage => isAdmin || isModerator;

  String get roleLabel {
    switch (role) {
      case 'admin': return 'Admin';
      case 'moderator': return 'Moderator';
      case 'guest': return 'Guest';
      default: return 'Member';
    }
  }

  String get initials {
    final parts = displayName.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    if (parts.isNotEmpty) return parts[0][0].toUpperCase();
    return '?';
  }
}

// ── Providers ───────────────────────────────────────────────────────────

/// Fetches all groups in a family that the current user can see.
/// Family members see ALL groups. Guests see only groups they're in.
final familyGroupsProvider =
    FutureProvider.family<List<FamilyGroup>, String>((ref, familyId) async {
  final client = ref.read(supabaseProvider);
  if (client == null) return [];

  final response = await client
      .from('Group')
      .select('*, memberCount:GroupMember.count()')
      .eq('familyId', familyId)
      .eq('isArchived', false)
      .order('lastActivityAt', ascending: false);

  return (response as List)
      .map((e) => FamilyGroup.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Fetches all members of a specific group.
final groupMembersProvider =
    FutureProvider.family<List<GroupMemberInfo>, String>((ref, groupId) async {
  final client = ref.read(supabaseProvider);
  if (client == null) return [];

  final response = await client
      .from('GroupMember')
      .select()
      .eq('groupId', groupId)
      .order('joinedAt', ascending: true);

  return (response as List)
      .map((e) => GroupMemberInfo.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Fetches a single group by ID.
final groupProvider =
    FutureProvider.family<FamilyGroup?, String>((ref, groupId) async {
  final client = ref.read(supabaseProvider);
  if (client == null) return null;

  final response = await client
      .from('Group')
      .select('*, memberCount:GroupMember.count()')
      .eq('id', groupId)
      .maybeSingle();

  if (response == null) return null;
  return FamilyGroup.fromJson(response);
});

/// Creates a new group within a family using the fn_create_group RPC.
/// Returns the new group's ID, or null on failure.
Future<String?> createGroup({
  required WidgetRef ref,
  required String familyId,
  required String name,
  String? description,
  GroupType groupType = GroupType.custom,
  String? avatarUrl,
  required List<({String userId, String displayName, bool isGuest})> members,
}) async {
  final client = ref.read(supabaseProvider);
  if (client == null) return null;

  try {
    final groupId = await client.rpc('fn_create_group', params: {
      'p_family_id': familyId,
      'p_name': name,
      'p_description': description,
      'p_group_type': groupType.name,
      'p_avatar_url': avatarUrl,
      'p_member_user_ids': members.map((m) => m.userId).toList(),
      'p_member_display_names': members.map((m) => m.displayName).toList(),
      'p_member_is_guests': members.map((m) => m.isGuest).toList(),
    });

    // Invalidate the groups list so it refreshes
    ref.invalidate(familyGroupsProvider(familyId));

    return groupId as String?;
  } catch (e) {
    return null;
  }
}

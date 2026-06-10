// lib/features/profile/providers/member_timeline_provider.dart
// DAXELO KINREL — Member Timeline Provider
//
// Fetches and composes timeline milestones for a specific member.
// Sources: dateOfBirth from profile, joinedAt from FamilyMember,
// and timeline posts from FamilyPost table.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/family/family_provider.dart';

// ── Timeline Item Model ────────────────────────────────────────

enum TimelineItemType {
  birth('Birth', '\u{1F476}'),
  joinedFamily('Joined Family', '\u{1F333}'),
  relationshipAdded('Relationship Added', '\u{1F91D}'),
  milestonePost('Milestone', '\u{1F3C6}'),
  memberJoined('Member Joined', '\u{1F465}');

  const TimelineItemType(this.label, this.emoji);
  final String label;
  final String emoji;
}

class TimelineItem {
  const TimelineItem({
    required this.id,
    required this.type,
    required this.title,
    required this.date,
    this.subtitle,
    this.isMajor = true,
  });

  final String id;
  final TimelineItemType type;
  final String title;
  final DateTime date;
  final String? subtitle;
  final bool isMajor;
}

// ── Provider ───────────────────────────────────────────────────

final memberTimelineProvider =
    FutureProvider.family<List<TimelineItem>, String>((ref, memberId) async {
  final client = ref.read(supabaseProvider);
  if (client == null) return [];

  final userId = client.auth.currentUser?.id;
  if (userId == null) return [];

  final items = <TimelineItem>[];

  try {
    // 1. Fetch profile data for birth date
    final profileData = await client
        .from('Person')
        .select('id, name, dateOfBirth, createdAt')
        .eq('id', memberId)
        .maybeSingle();

    if (profileData != null) {
      // Add birth milestone if dateOfBirth exists
      final dob = profileData['dateOfBirth'] as String?;
      if (dob != null && dob.isNotEmpty) {
        final birthDate = DateTime.tryParse(dob);
        if (birthDate != null) {
          items.add(TimelineItem(
            id: 'birth-$memberId',
            type: TimelineItemType.birth,
            title: 'Born${_getBirthplaceSuffix(profileData)}',
            date: birthDate,
            subtitle: _formatDate(birthDate),
            isMajor: true,
          ));
        }
      }

      // 2. Add "Joined Family" from createdAt
      final createdAt = profileData['createdAt'] as String?;
      if (createdAt != null) {
        final joinDate = DateTime.tryParse(createdAt);
        if (joinDate != null) {
          items.add(TimelineItem(
            id: 'joined-$memberId',
            type: TimelineItemType.joinedFamily,
            title: 'Joined the family',
            date: joinDate,
            subtitle: _formatDate(joinDate),
            isMajor: false,
          ));
        }
      }
    }

    // 3. Fetch family ID for this member
    final families = ref.read(familyListProvider).valueOrNull ?? [];
    String? familyId;
    if (families.isNotEmpty) {
      familyId = families.first.id;
    }

    // 4. Fetch timeline posts by this author
    if (familyId != null) {
      final posts = await client
          .from('FamilyPost')
          .select('id, postType, content, createdAt')
          .eq('familyId', familyId)
          .eq('authorId', memberId)
          .order('createdAt', ascending: false)
          .limit(50);

      for (final post in posts as List) {
        final postType = post['postType'] as String? ?? '';
        final content = _safeJsonMap(post['content']);
        final createdAt = post['createdAt'] as String?;
        final postDate = createdAt != null ? DateTime.tryParse(createdAt) : null;

        if (postDate == null) continue;

        switch (postType) {
          case 'connection_added':
            final fromName = content['fromName'] as String? ?? '';
            final toName = content['toName'] as String? ?? '';
            final relKey = content['relationshipKey'] as String? ?? '';
            items.add(TimelineItem(
              id: post['id']?.toString() ?? '',
              type: TimelineItemType.relationshipAdded,
              title: '$fromName is $toName\'s ${relKey.replaceAll('_', ' ')}',
              date: postDate,
              subtitle: _formatDate(postDate),
              isMajor: false,
            ));
            break;

          case 'milestone':
            final milestoneType = content['milestoneType'] as String? ?? '';
            final milestoneValue = content['milestoneValue'] as int? ?? 0;
            items.add(TimelineItem(
              id: post['id']?.toString() ?? '',
              type: TimelineItemType.milestonePost,
              title: '$milestoneValue ${milestoneType == 'generations' ? 'Generations' : 'Members'} Milestone',
              date: postDate,
              subtitle: _formatDate(postDate),
              isMajor: true,
            ));
            break;

          case 'member_joined':
            final memberName = content['memberName'] as String? ?? 'New member';
            items.add(TimelineItem(
              id: post['id']?.toString() ?? '',
              type: TimelineItemType.memberJoined,
              title: '$memberName joined the family',
              date: postDate,
              subtitle: _formatDate(postDate),
              isMajor: false,
            ));
            break;
        }
      }
    }

    // Sort by date (newest first)
    items.sort((a, b) => b.date.compareTo(a.date));

    return items;
  } catch (e) {
    debugPrint('⚠️ Member timeline error: $e');
    return items; // Return partial results
  }
});

// ── Helper functions ───────────────────────────────────────────

String _getBirthplaceSuffix(Map<String, dynamic> profile) {
  final birthplace = profile['birthplace'] as String?;
  if (birthplace != null && birthplace.isNotEmpty) {
    return ' in $birthplace';
  }
  return '';
}

String _formatDate(DateTime date) {
  final months = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${months[date.month]} ${date.day}, ${date.year}';
}

Map<String, dynamic> _safeJsonMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return {};
}

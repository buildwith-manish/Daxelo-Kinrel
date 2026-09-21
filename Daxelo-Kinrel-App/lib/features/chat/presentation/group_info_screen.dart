// lib/features/chat/presentation/group_info_screen.dart
//
// DAXELO KINREL — Feature 2: Group Chat Info Screen
//
// Shows the participant list (with online status) + family metadata.
// Accessed by tapping the family avatar/name in the chat header.
//
// Reuses the existing ChatService.getGroupInfo endpoint via Dio.
// The participant list includes:
//   - Display name + @username
//   - Avatar (or initials fallback)
//   - Online dot + "Active now" / "Last seen X ago" label
//   - Role (admin/member)
//   - Joined date
//
// Add/remove members is NOT implemented here — the existing family
// invitation flow (InvitationsModule) handles adding members. Removing
// members requires admin permissions + is handled by the FamiliesModule.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/networking/dio_client.dart';
import '../../../l10n/app_localizations.dart';
import '../providers/chat_socket_engagement_provider.dart';

/// Participant in a group chat.
class GroupParticipant {
  const GroupParticipant({
    required this.userId,
    required this.name,
    required this.username,
    required this.avatarUrl,
    required this.role,
    required this.joinedAt,
    required this.isOnline,
    required this.lastSeenAt,
  });

  final String userId;
  final String name;
  final String? username;
  final String? avatarUrl;
  final String role; // 'admin' | 'member'
  final DateTime joinedAt;
  final bool isOnline;
  final DateTime? lastSeenAt;

  // QA fix 2026-09-19: fromJson was declared as a STATIC member of
  // `extension on GroupParticipant` — static extension members cannot be
  // invoked through the extended type name (`GroupParticipant.fromJson`),
  // so the call site in GroupInfo.fromJson failed to compile
  // (undefined_method). Moved into the class as a proper factory.
  factory GroupParticipant.fromJson(Map<String, dynamic> json) {
    return GroupParticipant(
      userId: json['userId'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown',
      username: json['username'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      role: json['role'] as String? ?? 'member',
      joinedAt: json['joinedAt'] != null
          ? DateTime.parse(json['joinedAt'] as String)
          : DateTime.now(),
      isOnline: json['isOnline'] as bool? ?? false,
      lastSeenAt: json['lastSeenAt'] != null
          ? DateTime.parse(json['lastSeenAt'] as String)
          : null,
    );
  }
}

/// Snapshot of the group chat info returned by GET /chat/info.
class GroupInfo {
  const GroupInfo({
    required this.familyId,
    required this.familyName,
    required this.familyAvatarUrl,
    required this.memberCount,
    required this.participants,
  });

  final String familyId;
  final String familyName;
  final String? familyAvatarUrl;
  final int memberCount;
  final List<GroupParticipant> participants;

  factory GroupInfo.fromJson(Map<String, dynamic> json) {
    return GroupInfo(
      familyId: json['familyId'] as String? ?? '',
      familyName: json['familyName'] as String? ?? 'Unknown',
      familyAvatarUrl: json['familyAvatarUrl'] as String?,
      memberCount: json['memberCount'] as int? ?? 0,
      participants: ((json['participants'] as List?) ?? [])
          .map((e) => GroupParticipant.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Riverpod future provider that fetches the group info from the backend.
final groupInfoProvider =
    FutureProvider.family<GroupInfo?, String>((ref, familyId) async {
  try {
    final dio = ref.watch(dioProvider);
    final response = await dio.get('/api/families/$familyId/chat/info');
    final data = response.data;
    final payload = data is Map<String, dynamic> && data.containsKey('data')
        ? data['data'] as Map<String, dynamic>?
        : data is Map<String, dynamic>
            ? data
            : null;
    if (payload == null) return null;
    return GroupInfo.fromJson(payload);
  } catch (e) {
    return null;
  }
});

class GroupInfoScreen extends ConsumerWidget {
  const GroupInfoScreen({super.key, required this.familyId});

  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final infoAsync = ref.watch(groupInfoProvider(familyId));
    // Feature 4: also watch the engagement provider so the online dots
    // update instantly when a user connects/disconnects (the getGroupInfo
    // endpoint returns a snapshot; the engagement provider keeps it live).
    ref.watch(chatEngagementProvider(familyId));

    return Scaffold(
      backgroundColor: const Color(0xFF0A0B16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF11132A),
        title: const Text(
          'Group Info',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textWhite,
          ),
        ),
        iconTheme: const IconThemeData(color: KinrelColors.textSilver),
      ),
      body: infoAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: KinrelColors.ember, strokeWidth: 1.5),
        ),
        error: (_, __) => const Center(
          child: Text(
            'Failed to load group info',
            style: TextStyle(color: KinrelColors.textSilver, fontSize: 14),
          ),
        ),
        data: (info) {
          if (info == null) {
            return const Center(
              child: Text(
                'Group not found',
                style: TextStyle(color: KinrelColors.textSilver, fontSize: 14),
              ),
            );
          }
          // Merge live presence from the engagement provider.
          final eng = ref.watch(chatEngagementProvider(familyId));
          return _buildBody(context, info, eng);
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context, GroupInfo info, ChatEngagementState eng) {
    // v114 — Step 4 perf: build a flat list of children then use
    // ListView.builder so participant tiles (the dynamic part of the
    // list) are built lazily as they become visible.
    final rows = <Widget>[
      // ── Family avatar + name ──────────────────────────────────────
      Center(
        child: Column(
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: KinrelGradients.igniteGradient,
                boxShadow: [
                  BoxShadow(
                    color: KinrelColors.ember.withValues(alpha: 0.25),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  info.familyName.isNotEmpty
                      ? info.familyName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 36,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              info.familyName,
              style: const TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${info.memberCount} member${info.memberCount != 1 ? 's' : ''}',
              style: const TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                color: KinrelColors.textSilver,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),

      // ── Participants section header ───────────────────────────────
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          'PARTICIPANTS (${info.participants.length})',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: KinrelColors.textSilver.withValues(alpha: 0.6),
            letterSpacing: 1.0,
          ),
        ),
      ),
      const SizedBox(height: 8),
    ];

    // ── Participant list (dynamic part) ──────────────────────────────
    for (final p in info.participants) {
      rows.add(_ParticipantTile(
        participant: p,
        livePresence: eng.presence[p.userId],
      ));
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 16),
      itemCount: rows.length,
      itemBuilder: (context, index) => rows[index],
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({required this.participant, this.livePresence});
  final GroupParticipant participant;
  final UserPresence? livePresence;

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    final isOnline = livePresence?.isOnline ?? participant.isOnline;
    final lastSeenAt = livePresence?.lastSeenAt ?? participant.lastSeenAt;

    return ListTile(
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: KinrelColors.ember.withValues(alpha: 0.2),
            child: Text(
              participant.name.isNotEmpty
                  ? participant.name[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: KinrelColors.ember,
              ),
            ),
          ),
          if (isOnline)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: KinrelColors.success,
                  border: Border.all(color: const Color(0xFF11132A), width: 2),
                ),
              ),
            ),
        ],
      ),
      title: Row(
        children: [
          Text(
            participant.name,
            style: const TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textWhite,
            ),
          ),
          if (participant.role == 'admin') ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: KinrelColors.ember.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'admin',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.ember,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        isOnline
            ? (l10n?.chatActiveNow ?? 'Active now')
            : (lastSeenAt != null && lastSeenAt.year > 1970
                ? UserPresence(
                    userId: participant.userId,
                    isOnline: false,
                    lastSeenAt: lastSeenAt,
                  ).lastSeenLabelLocalized(l10n)
                : (l10n?.chatOffline ?? 'Offline')),
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 12,
          color: isOnline
              ? KinrelColors.success
              : KinrelColors.textSilver.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

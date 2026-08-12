// lib/features/family/presentation/group_hub_screen.dart
//
// DAXELO KINREL — Group Hub (v138 Phase 2)
//
// Premium overview screen for a single family group. Mirrors the Family
// Hub pattern but scoped to a sub-group (cousins, parents, siblings, etc).
//
// Sections:
//   1. Hero — group image, name, type, member count, description
//   2. Members — separated into Family Members + Guest Members
//   3. Shared Media — recent photos from the group chat
//   4. Group Activity — timeline of recent group activity
//   5. Group Settings — notifications, wallpaper, permissions
//   6. Enter Group Chat — gateway to the conversation
//
// Route: /family/:id/groups/:groupId/hub

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../chat/providers/chat_provider.dart';
import '../data/group_provider.dart';

class GroupHubScreen extends ConsumerWidget {
  const GroupHubScreen({
    super.key,
    required this.familyId,
    required this.groupId,
  });

  final String familyId;
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupAsync = ref.watch(groupProvider(groupId));
    final membersAsync = ref.watch(groupMembersProvider(groupId));
    final chatState = ref.watch(chatProvider(familyId));

    final group = groupAsync.valueOrNull;
    final members = membersAsync.valueOrNull ?? [];

    // Filter group messages (those with this groupId)
    final groupMessages =
        chatState.messages.where((m) => m.groupId == groupId).toList();

    return DKScaffold(
      backgroundColor: const Color(0xFF0A0B16),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new,
              size: 18, color: KinrelColors.textSilver),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/family/$familyId/groups');
            }
          },
        ),
        title: Text(
          'Group Hub',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: KinrelColors.textSilver,
            letterSpacing: 1.2,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.more_vert,
                color: KinrelColors.textSilver, size: 20),
            onPressed: () {},
          ),
        ],
      ),
      body: group == null
          ? const Center(
              child: CircularProgressIndicator(color: KinrelColors.orange),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 48),
              children: [
                // ── 1. Hero ──────────────────────────────────────────
                _GroupHero(group: group),

                const SizedBox(height: 24),

                // ── 2. Members ──────────────────────────────────────
                _GroupMembersSection(
                  members: members,
                  onAddMembers: () => context.push(
                      '/family/$familyId/groups/$groupId/members/add'),
                ),

                // ── 3. Shared Media ─────────────────────────────────
                _GroupSharedMediaSection(messages: groupMessages),

                // ── 4. Activity Timeline ────────────────────────────
                _GroupActivitySection(messages: groupMessages),

                // ── 5. Settings ─────────────────────────────────────
                _GroupSettingsSection(
                  familyId: familyId,
                  groupId: groupId,
                ),

                const SizedBox(height: 28),

                // ── 6. Enter Group Chat ─────────────────────────────
                _EnterGroupChatGateway(
                  familyId: familyId,
                  groupId: groupId,
                  group: group,
                ),

                const SizedBox(height: 32),
              ],
            ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 1. Group Hero
// ═══════════════════════════════════════════════════════════════════════

class _GroupHero extends StatelessWidget {
  const _GroupHero({required this.group});
  final FamilyGroup group;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        children: [
          // Large group avatar with type-colored glow
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: group.groupType.color.withValues(alpha: 0.25),
                  blurRadius: 32,
                  offset: const Offset(0, 0),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: group.groupType.color.withValues(alpha: 0.45),
                  width: 2,
                ),
              ),
              child: ClipOval(
                child: group.avatarUrl != null &&
                        group.avatarUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: group.avatarUrl!,
                        fit: BoxFit.cover,
                        width: 116,
                        height: 116,
                        placeholder: (_, __) =>
                            _GroupHeroIcon(group: group),
                        errorWidget: (_, __, ___) =>
                            _GroupHeroIcon(group: group),
                      )
                    : _GroupHeroIcon(group: group),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Group name
          Text(
            group.name,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: KinrelColors.textWhite,
              letterSpacing: 0.4,
              height: 1.2,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          // Type chip + member count
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: group.groupType.color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: group.groupType.color.withValues(alpha: 0.30),
                    width: 0.6,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(group.groupType.icon,
                        size: 11, color: group.groupType.color),
                    const SizedBox(width: 5),
                    Text(
                      group.groupType.label,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: group.groupType.color.withValues(alpha: 0.90),
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${group.memberCount} members',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: KinrelColors.textSilver.withValues(alpha: 0.75),
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          // Description
          if (group.description != null &&
              group.description!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                group.description!,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  color: KinrelColors.textSilver.withValues(alpha: 0.70),
                  height: 1.6,
                  letterSpacing: 0.15,
                ),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GroupHeroIcon extends StatelessWidget {
  const _GroupHeroIcon({required this.group});
  final FamilyGroup group;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            group.groupType.color.withValues(alpha: 0.35),
            group.groupType.color.withValues(alpha: 0.15),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          group.groupType.icon,
          size: 44,
          color: Colors.white.withValues(alpha: 0.90),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 2. Group Members — separated Family Members vs Guests
// ═══════════════════════════════════════════════════════════════════════

class _GroupMembersSection extends StatelessWidget {
  const _GroupMembersSection({
    required this.members,
    required this.onAddMembers,
  });

  final List<GroupMemberInfo> members;
  final VoidCallback onAddMembers;

  @override
  Widget build(BuildContext context) {
    final familyMembers = members.where((m) => !m.isGuest).toList();
    final guestMembers = members.where((m) => m.isGuest).toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A1D2E), Color(0xFF14162A)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.06), width: 0.75),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.20),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.people_alt_rounded,
                  size: 16, color: KinrelColors.ember),
              const SizedBox(width: 8),
              Text(
                'Members',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textWhite,
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onAddMembers,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: KinrelColors.ember.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded,
                          size: 14, color: KinrelColors.ember),
                      const SizedBox(width: 3),
                      Text(
                        'Add',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: KinrelColors.ember,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // Family Members subsection
          if (familyMembers.isNotEmpty) ...[
            _MemberSubsectionLabel(
              label: 'Family Members',
              count: familyMembers.length,
              color: KinrelColors.ember,
            ),
            const SizedBox(height: 10),
            ...familyMembers.map((m) => _MemberRow(member: m)),
          ],
          // Guest Members subsection
          if (guestMembers.isNotEmpty) ...[
            const SizedBox(height: 16),
            _MemberSubsectionLabel(
              label: 'Guests',
              count: guestMembers.length,
              color: const Color(0xFF8AFFB7),
            ),
            const SizedBox(height: 10),
            ...guestMembers.map((m) => _MemberRow(member: m)),
          ],
          if (members.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'No members yet',
                  style: TextStyle(color: KinrelColors.textDim, fontSize: 13),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MemberSubsectionLabel extends StatelessWidget {
  const _MemberSubsectionLabel({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontFamily: KinrelTypography.monoFont,
            fontSize: 9.5,
            fontWeight: FontWeight.w600,
            color: color.withValues(alpha: 0.80),
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '($count)',
          style: TextStyle(
            fontFamily: KinrelTypography.monoFont,
            fontSize: 9.5,
            fontWeight: FontWeight.w500,
            color: KinrelColors.textDim,
          ),
        ),
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member});
  final GroupMemberInfo member;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: member.isGuest
              ? const Color(0xFF8AFFB7).withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.04),
          width: 0.6,
        ),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: member.isGuest
                  ? const Color(0xFF8AFFB7).withValues(alpha: 0.12)
                  : KinrelColors.ember.withValues(alpha: 0.12),
              border: Border.all(
                color: member.isAdmin
                    ? KinrelColors.ember.withValues(alpha: 0.45)
                    : Colors.white.withValues(alpha: 0.08),
                width: 1.2,
              ),
            ),
            child: member.avatarUrl != null && member.avatarUrl!.isNotEmpty
                ? ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: member.avatarUrl!,
                      fit: BoxFit.cover,
                      width: 36,
                      height: 36,
                      errorWidget: (_, __, ___) =>
                          _MemberInitials(member: member),
                    ),
                  )
                : _MemberInitials(member: member),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.displayName,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: KinrelColors.textWhite,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    // Role badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: member.isAdmin
                            ? KinrelColors.ember.withValues(alpha: 0.12)
                            : Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        member.roleLabel,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: member.isAdmin
                              ? KinrelColors.ember
                              : KinrelColors.textDim,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    if (member.isGuest) ...[
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8AFFB7)
                              .withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(
                          'Guest',
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF8AFFB7),
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberInitials extends StatelessWidget {
  const _MemberInitials({required this.member});
  final GroupMemberInfo member;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        member.initials,
        style: TextStyle(
          fontFamily: KinrelTypography.displayFont,
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: member.isGuest
              ? const Color(0xFF8AFFB7)
              : KinrelColors.ember,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 3. Shared Media
// ═══════════════════════════════════════════════════════════════════════

class _GroupSharedMediaSection extends StatelessWidget {
  const _GroupSharedMediaSection({required this.messages});
  final List<dynamic> messages;

  @override
  Widget build(BuildContext context) {
    final photos = messages
        .where((m) =>
            m.messageType == MessageType.photo &&
            m.mediaUrl != null &&
            m.mediaUrl!.isNotEmpty)
        .take(4)
        .toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A1D2E), Color(0xFF14162A)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.06), width: 0.75),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.20),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.photo_library_outlined,
                  size: 16, color: KinrelColors.ember),
              const SizedBox(width: 8),
              Text(
                'Shared Media',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textWhite,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (photos.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'No media shared yet',
                  style: TextStyle(color: KinrelColors.textDim, fontSize: 12.5),
                ),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1,
              ),
              itemCount: photos.length,
              itemBuilder: (ctx, i) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: CachedNetworkImage(
                    imageUrl: photos[i].mediaUrl!,
                    fit: BoxFit.cover,
                    placeholder: (_, __) =>
                        Container(color: const Color(0xFF202338)),
                    errorWidget: (_, __, ___) => Container(
                      color: const Color(0xFF202338),
                      child: Icon(Icons.broken_image_outlined,
                          size: 24, color: KinrelColors.textDim),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 4. Activity Timeline
// ═══════════════════════════════════════════════════════════════════════

class _GroupActivitySection extends StatelessWidget {
  const _GroupActivitySection({required this.messages});
  final List<dynamic> messages;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) return const SizedBox.shrink();

    final entries = messages.take(4).map((m) {
      IconData icon;
      Color color;
      String title;
      switch (m.messageType) {
        case MessageType.photo:
          icon = Icons.photo_camera_rounded;
          color = KinrelColors.ember;
          title = '${m.senderName} shared a photo';
          break;
        case MessageType.voiceNote:
          icon = Icons.mic_rounded;
          color = const Color(0xFF6B8AFF);
          title = '${m.senderName} sent a voice message';
          break;
        case MessageType.sticker:
          icon = Icons.emoji_emotions_rounded;
          color = const Color(0xFFFFB74D);
          title = '${m.senderName} sent a sticker';
          break;
        default:
          icon = Icons.chat_bubble_outline_rounded;
          color = KinrelColors.success;
          title = '${m.senderName} sent a message';
      }
      return (icon: icon, color: color, title: title, time: m.timestamp);
    }).toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A1D2E), Color(0xFF14162A)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.06), width: 0.75),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.20),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded,
                  size: 16, color: KinrelColors.ember),
              const SizedBox(width: 8),
              Text(
                'Recent Activity',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textWhite,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ...entries.asMap().entries.map((entry) {
            final i = entry.key;
            final e = entry.value;
            final isLast = i == entries.length - 1;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 28,
                  child: Column(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: e.color.withValues(alpha: 0.15),
                          border: Border.all(
                            color: e.color.withValues(alpha: 0.50),
                            width: 1.2,
                          ),
                        ),
                        child: Icon(e.icon, size: 13, color: e.color),
                      ),
                      if (!isLast)
                        Container(
                          width: 1.2,
                          height: 32,
                          margin: const EdgeInsets.only(top: 4),
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Padding(
                    padding:
                        EdgeInsets.only(top: 4, bottom: isLast ? 0 : 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.title,
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: KinrelColors.textWhite.withValues(alpha: 0.90),
                            height: 1.4,
                            letterSpacing: 0.1,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _formatTimeAgo(e.time),
                          style: TextStyle(
                            fontFamily: KinrelTypography.monoFont,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: KinrelColors.textDim,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 5. Settings
// ═══════════════════════════════════════════════════════════════════════

class _GroupSettingsSection extends StatelessWidget {
  const _GroupSettingsSection({required this.familyId, required this.groupId});

  final String familyId;
  final String groupId;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: const Color(0xFF11132A).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.04), width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'GROUP SETTINGS',
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textDim,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          _SettingsRow(
            icon: Icons.notifications_none_rounded,
            label: 'Notifications',
            onTap: () {},
          ),
          _SettingsRow(
            icon: Icons.palette_outlined,
            label: 'Group Wallpaper',
            onTap: () {},
          ),
          _SettingsRow(
            icon: Icons.shield_outlined,
            label: 'Permissions',
            onTap: () {},
          ),
          _SettingsRow(
            icon: Icons.person_add_outlined,
            label: 'Invite Controls',
            onTap: () => context.push(
                '/family/$familyId/groups/$groupId/members/add'),
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isLast = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(
                  bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.04),
                    width: 0.5,
                  ),
                ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 17, color: KinrelColors.ember),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: KinrelColors.textWhite,
                  letterSpacing: 0.1,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: KinrelColors.textDim),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 6. Enter Group Chat Gateway
// ═══════════════════════════════════════════════════════════════════════

class _EnterGroupChatGateway extends StatelessWidget {
  const _EnterGroupChatGateway({
    required this.familyId,
    required this.groupId,
    required this.group,
  });

  final String familyId;
  final String groupId;
  final FamilyGroup group;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () =>
            context.go('/family/$familyId/groups/$groupId/chat'),
        child: Container(
          padding:
              const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                group.groupType.color.withValues(alpha: 0.22),
                group.groupType.color.withValues(alpha: 0.10),
                const Color(0xFF1A1D2E).withValues(alpha: 0.6),
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: group.groupType.color.withValues(alpha: 0.40),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: group.groupType.color.withValues(alpha: 0.25),
                blurRadius: 32,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.20),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      group.groupType.color.withValues(alpha: 0.35),
                      group.groupType.color.withValues(alpha: 0.15),
                    ],
                  ),
                  border: Border.all(
                    color: group.groupType.color.withValues(alpha: 0.55),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: group.groupType.color.withValues(alpha: 0.30),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.chat_rounded,
                  size: 26,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Open Group Conversation',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                  letterSpacing: 0.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Connect with your ${group.groupType.label.toLowerCase()}',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: KinrelColors.textSilver.withValues(alpha: 0.80),
                  letterSpacing: 0.2,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      group.groupType.color,
                      group.groupType.color.withValues(alpha: 0.80),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(100),
                  boxShadow: [
                    BoxShadow(
                      color: group.groupType.color.withValues(alpha: 0.40),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Enter Chat',
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.arrow_forward_rounded,
                        size: 18, color: Colors.white),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

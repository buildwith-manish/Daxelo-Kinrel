// lib/features/family/presentation/family_hub_screen.dart
//
// DAXELO KINREL — Family Hub (v135)
//
// A premium intermediate screen between the chat and the Family Space.
// When the user taps the chat header (avatar, name, or relationship
// chip), they land HERE — not directly in the Family Space.
//
// The Family Hub is the digital home of the conversation. It feels
// like a premium overview space specifically designed for Kinrel —
// not a chat, not a settings page, not a WhatsApp-style profile.
//
// Sections:
//   1. Hero — large family image + name + type + active status + description
//   2. Family Identity Card — name, category, created date, member count
//   3. Members — premium grid of family members with relationship labels
//   4. Shared Content — preview cards for photos/videos/docs/links
//   5. Pinned Messages — elegant cards for important family messages
//   6. Activity Overview — recent highlights (new members, recent photos)
//   7. Conversation Insights — total messages, media count, active members
//   8. Family Settings — notifications, wallpaper, permissions, privacy
//   9. Enter Family Space — large premium gateway at the bottom
//
// Design language: matches v131-v134 (gradients, hairline borders,
// ember accent, generous spacing, letter-spaced typography).
//
// Route: /family/:id/hub

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/services/supabase_service.dart';
import '../../chat/providers/chat_provider.dart';
import '../../../shared/widgets/dk_components.dart';

class FamilyHubScreen extends ConsumerWidget {
  const FamilyHubScreen({super.key, required this.familyId});

  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final familyAsync = ref.watch(familyDetailProvider(familyId));
    final avatarUrl = ref.watch(familyAvatarProvider(familyId));
    final chatState = ref.watch(chatProvider(familyId));
    final membershipsAsync = ref.watch(familyMembershipsProvider(familyId));

    final family = familyAsync.valueOrNull?.family;
    final members = familyAsync.valueOrNull?.members ?? [];
    final memberships = membershipsAsync.valueOrNull ?? [];

    return DKScaffold(
      // v135: Deep gradient background matching the chat screen's
      // ChatBackground palette so the Hub feels continuous with the
      // conversation the user just came from.
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
              context.go('/family/$familyId/chat');
            }
          },
        ),
        title: Text(
          'Family Hub',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: KinrelColors.textWhite,
            letterSpacing: 0.2,
          ),
        ),
        centerTitle: false,
      ),
      body: family == null
          ? const Center(
              child: CircularProgressIndicator(color: KinrelColors.orange),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 40),
              children: [
                // ── 1. Hero Section ──────────────────────────────────
                _HeroSection(
                  family: family,
                  avatarUrl: avatarUrl,
                  onlineCount: chatState.onlineCount,
                  totalMembers: family.memberCount,
                ),

                // ── 2. Family Identity Card ─────────────────────────
                _IdentityCard(family: family),

                // ── 3. Members Section ───────────────────────────────
                _MembersSection(
                  familyId: familyId,
                  members: members,
                  memberships: memberships,
                ),

                // ── 4. Shared Content ───────────────────────────────
                _SharedContentSection(
                  familyId: familyId,
                  messages: chatState.messages,
                ),

                // ── 5. Pinned Messages ──────────────────────────────
                _PinnedMessagesSection(
                  familyId: familyId,
                  messages: chatState.messages,
                ),

                // ── 6. Activity Overview ────────────────────────────
                _ActivityOverviewSection(
                  family: family,
                  messages: chatState.messages,
                  memberCount: family.memberCount,
                ),

                // ── 7. Conversation Insights ────────────────────────
                _InsightsSection(
                  messages: chatState.messages,
                  memberCount: family.memberCount,
                  onlineCount: chatState.onlineCount,
                ),

                // ── 8. Family Settings ──────────────────────────────
                _SettingsSection(familyId: familyId),

                // ── 9. Enter Family Space Gateway ───────────────────
                _FamilySpaceGateway(familyId: familyId),

                const SizedBox(height: 24),
              ],
            ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 1. Hero Section
// ═══════════════════════════════════════════════════════════════════════

class _HeroSection extends StatelessWidget {
  const _HeroSection({
    required this.family,
    required this.avatarUrl,
    required this.onlineCount,
    required this.totalMembers,
  });

  final Family family;
  final String? avatarUrl;
  final int onlineCount;
  final int totalMembers;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        // v135: Premium gradient surface — top lighter (lit from above),
        // bottom darker. Matches the v134 header gradient for cohesion.
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1A1D2E),
            Color(0xFF11132A),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
          width: 0.75,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          // Large family avatar with ember glow + ring
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: KinrelColors.ember.withValues(alpha: 0.22),
                  blurRadius: 24,
                  offset: const Offset(0, 0),
                ),
              ],
            ),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: KinrelColors.ember.withValues(alpha: 0.40),
                  width: 1.5,
                ),
              ),
              child: ClipOval(
                child: avatarUrl != null && avatarUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: avatarUrl!,
                        fit: BoxFit.cover,
                        width: 94,
                        height: 94,
                        placeholder: (_, __) => _HeroInitials(family: family),
                        errorWidget: (_, __, ___) =>
                            _HeroInitials(family: family),
                      )
                    : _HeroInitials(family: family),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Family name
          Text(
            family.name,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: KinrelColors.textWhite,
              letterSpacing: 0.3,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          // Family type chip + active status
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Family type chip
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: KinrelColors.ember.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: KinrelColors.ember.withValues(alpha: 0.30),
                    width: 0.6,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.favorite_rounded,
                        size: 11, color: KinrelColors.ember),
                    const SizedBox(width: 5),
                    Text(
                      'Family',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.ember.withValues(alpha: 0.95),
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Active status
              if (onlineCount > 0) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: KinrelColors.success,
                    boxShadow: [
                      BoxShadow(
                        color: KinrelColors.success.withValues(alpha: 0.5),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  '$onlineCount active',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: KinrelColors.textSilver.withValues(alpha: 0.85),
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ],
          ),
          // Family description (if present)
          if (family.description != null &&
              family.description!.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              family.description!,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                color: KinrelColors.textSilver.withValues(alpha: 0.80),
                height: 1.5,
                letterSpacing: 0.1,
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroInitials extends StatelessWidget {
  const _HeroInitials({required this.family});
  final Family family;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: KinrelGradients.igniteGradient,
      ),
      child: Center(
        child: Text(
          family.name.isNotEmpty ? family.name[0].toUpperCase() : 'F',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 36,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 2. Family Identity Card
// ═══════════════════════════════════════════════════════════════════════

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.family});
  final Family family;

  @override
  Widget build(BuildContext context) {
    final createdDate = family.createdAt;
    final createdStr = createdDate != null
        ? '${createdDate.day} ${_monthName(createdDate.month)} ${createdDate.year}'
        : '—';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF11132A).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
          width: 0.6,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section label
          Text(
            'FAMILY IDENTITY',
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textDim,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          // Identity rows
          Row(
            children: [
              Expanded(
                child: _IdentityCell(
                  label: 'Name',
                  value: family.name,
                  icon: Icons.family_restroom,
                ),
              ),
              Container(
                width: 1,
                height: 48,
                color: Colors.white.withValues(alpha: 0.06),
              ),
              Expanded(
                child: _IdentityCell(
                  label: 'Category',
                  value: 'Family Group',
                  icon: Icons.category_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            height: 1,
            color: Colors.white.withValues(alpha: 0.06),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _IdentityCell(
                  label: 'Created',
                  value: createdStr,
                  icon: Icons.calendar_today_rounded,
                ),
              ),
              Container(
                width: 1,
                height: 48,
                color: Colors.white.withValues(alpha: 0.06),
              ),
              Expanded(
                child: _IdentityCell(
                  label: 'Members',
                  value: '${family.memberCount}',
                  icon: Icons.people_alt_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _monthName(int m) {
    const names = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return names[m];
  }
}

class _IdentityCell extends StatelessWidget {
  const _IdentityCell({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: KinrelColors.ember),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: KinrelColors.textDim,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textWhite,
              letterSpacing: 0.1,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 3. Members Section
// ═══════════════════════════════════════════════════════════════════════

class _MembersSection extends StatelessWidget {
  const _MembersSection({
    required this.familyId,
    required this.members,
    required this.memberships,
  });

  final String familyId;
  final List<Person> members;
  final List<FamilyMembership> memberships;

  @override
  Widget build(BuildContext context) {
    // Use memberships (which have user profiles) as the primary source,
    // falling back to Person entries if no memberships exist.
    final displayMembers = memberships.isNotEmpty ? memberships : <FamilyMembership>[];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF11132A).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
          width: 0.6,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'MEMBERS',
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textDim,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () =>
                    context.push('/family/$familyId/members'),
                child: Text(
                  'View all',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.ember,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (displayMembers.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'No members yet',
                  style: TextStyle(
                    color: KinrelColors.textDim,
                    fontSize: 13,
                  ),
                ),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 14,
                childAspectRatio: 0.85,
              ),
              itemCount: displayMembers.take(6).length,
              itemBuilder: (ctx, i) {
                final m = displayMembers[i];
                return _MemberTile(membership: m);
              },
            ),
        ],
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.membership});
  final FamilyMembership membership;

  @override
  Widget build(BuildContext context) {
    final user = membership.user;
    final name = user?.displayName ?? 'Member';
    final initials = user?.initials ?? '?';
    final avatarUrl = user?.avatarUrl;

    return GestureDetector(
      onTap: () {
        if (user != null) {
          context.push('/dm/${user.id}');
        }
      },
      child: Column(
        children: [
          // Avatar with role-based ring
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: membership.isAdmin
                    ? KinrelColors.ember.withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.10),
                width: 1.2,
              ),
            ),
            child: ClipOval(
              child: avatarUrl != null && avatarUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: avatarUrl,
                      fit: BoxFit.cover,
                      width: 54,
                      height: 54,
                      placeholder: (_, __) => _MemberInitials(initials: initials),
                      errorWidget: (_, __, ___) =>
                          _MemberInitials(initials: initials),
                    )
                  : _MemberInitials(initials: initials),
            ),
          ),
          const SizedBox(height: 8),
          // Name
          Text(
            name,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textWhite,
              letterSpacing: 0.1,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          // Role label
          Text(
            membership.displayRole,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 9.5,
              fontWeight: FontWeight.w500,
              color: membership.isAdmin
                  ? KinrelColors.ember.withValues(alpha: 0.85)
                  : KinrelColors.textDim,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberInitials extends StatelessWidget {
  const _MemberInitials({required this.initials});
  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: KinrelGradients.igniteGradient,
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 4. Shared Content Section
// ═══════════════════════════════════════════════════════════════════════

class _SharedContentSection extends StatelessWidget {
  const _SharedContentSection({
    required this.familyId,
    required this.messages,
  });

  final String familyId;
  final List<ChatMessage> messages;

  @override
  Widget build(BuildContext context) {
    final photos = messages
        .where((m) =>
            m.messageType == MessageType.photo &&
            m.mediaUrl != null &&
            m.mediaUrl!.isNotEmpty)
        .take(6)
        .toList();
    final photoCount = messages
        .where((m) => m.messageType == MessageType.photo)
        .length;
    final voiceCount = messages
        .where((m) => m.messageType == MessageType.voiceNote)
        .length;
    final stickerCount = messages
        .where((m) => m.messageType == MessageType.sticker)
        .length;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF11132A).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
          width: 0.6,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SHARED CONTENT',
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textDim,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          // Photo grid (if any photos)
          if (photos.isNotEmpty) ...[
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
                childAspectRatio: 1,
              ),
              itemCount: photos.length,
              itemBuilder: (ctx, i) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    imageUrl: photos[i].mediaUrl!,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      color: const Color(0xFF202338),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      color: const Color(0xFF202338),
                      child: Icon(Icons.broken_image_outlined,
                          size: 20,
                          color: KinrelColors.textDim),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
          ],
          // Media type counts
          Row(
            children: [
              _MediaCountChip(
                icon: Icons.photo_outlined,
                label: 'Photos',
                count: photoCount,
              ),
              const SizedBox(width: 8),
              _MediaCountChip(
                icon: Icons.mic_none_rounded,
                label: 'Voice',
                count: voiceCount,
              ),
              const SizedBox(width: 8),
              _MediaCountChip(
                icon: Icons.emoji_emotions_outlined,
                label: 'Stickers',
                count: stickerCount,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MediaCountChip extends StatelessWidget {
  const _MediaCountChip({
    required this.icon,
    required this.label,
    required this.count,
  });

  final IconData icon;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: KinrelColors.ember),
            const SizedBox(height: 4),
            Text(
              '$count',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 9.5,
                fontWeight: FontWeight.w500,
                color: KinrelColors.textDim,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 5. Pinned Messages Section
// ═══════════════════════════════════════════════════════════════════════

class _PinnedMessagesSection extends StatelessWidget {
  const _PinnedMessagesSection({
    required this.familyId,
    required this.messages,
  });

  final String familyId;
  final List<ChatMessage> messages;

  @override
  Widget build(BuildContext context) {
    final pinned = messages.where((m) => m.isPinned).take(3).toList();

    if (pinned.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF11132A).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
          width: 0.6,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.push_pin_rounded,
                  size: 14, color: KinrelColors.ember),
              const SizedBox(width: 8),
              Text(
                'PINNED MESSAGES',
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textDim,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...pinned.map((m) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(12),
                  border: Border(
                    left: BorderSide(
                      color: KinrelColors.ember.withValues(alpha: 0.6),
                      width: 2.5,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.senderName,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.ember,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      m.content.isNotEmpty
                          ? m.content
                          : '[${m.messageType.name}]',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12.5,
                        color: KinrelColors.textSilver.withValues(alpha: 0.9),
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 6. Activity Overview Section
// ═══════════════════════════════════════════════════════════════════════

class _ActivityOverviewSection extends StatelessWidget {
  const _ActivityOverviewSection({
    required this.family,
    required this.messages,
    required this.memberCount,
  });

  final Family family;
  final List<ChatMessage> messages;
  final int memberCount;

  @override
  Widget build(BuildContext context) {
    final recentPhoto = messages
        .where((m) =>
            m.messageType == MessageType.photo &&
            m.mediaUrl != null &&
            m.mediaUrl!.isNotEmpty)
        .firstOrNull;
    final lastMessage = messages.isNotEmpty ? messages.first : null;
    final lastActivityStr = lastMessage != null
        ? _formatTimeAgo(lastMessage.timestamp)
        : 'No activity yet';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF11132A).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
          width: 0.6,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ACTIVITY OVERVIEW',
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textDim,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              // Recent photo thumbnail
              if (recentPhoto != null && recentPhoto.mediaUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    imageUrl: recentPhoto.mediaUrl!,
                    fit: BoxFit.cover,
                    width: 56,
                    height: 56,
                    placeholder: (_, __) => Container(
                      width: 56,
                      height: 56,
                      color: const Color(0xFF202338),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      width: 56,
                      height: 56,
                      color: const Color(0xFF202338),
                      child: Icon(Icons.image_outlined,
                          size: 20, color: KinrelColors.textDim),
                    ),
                  ),
                )
              else
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.history_rounded,
                      size: 24, color: KinrelColors.textDim),
                ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Last activity',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: KinrelColors.textDim,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      lastActivityStr,
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.textWhite,
                        letterSpacing: 0.1,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.people_alt_rounded,
                            size: 11, color: KinrelColors.ember),
                        const SizedBox(width: 5),
                        Text(
                          '$memberCount members',
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: KinrelColors.textSilver
                                .withValues(alpha: 0.85),
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 7. Conversation Insights Section
// ═══════════════════════════════════════════════════════════════════════

class _InsightsSection extends StatelessWidget {
  const _InsightsSection({
    required this.messages,
    required this.memberCount,
    required this.onlineCount,
  });

  final List<ChatMessage> messages;
  final int memberCount;
  final int onlineCount;

  @override
  Widget build(BuildContext context) {
    final totalMessages = messages.length;
    final mediaCount = messages
        .where((m) =>
            m.messageType == MessageType.photo ||
            m.messageType == MessageType.voiceNote ||
            m.messageType == MessageType.sticker)
        .length;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF11132A).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
          width: 0.6,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CONVERSATION INSIGHTS',
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textDim,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _InsightStat(
                label: 'Messages',
                value: '$totalMessages',
                icon: Icons.chat_bubble_outline_rounded,
              ),
              const SizedBox(width: 8),
              _InsightStat(
                label: 'Media',
                value: '$mediaCount',
                icon: Icons.perm_media_outlined,
              ),
              const SizedBox(width: 8),
              _InsightStat(
                label: 'Active',
                value: '$onlineCount',
                icon: Icons.circle_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InsightStat extends StatelessWidget {
  const _InsightStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              KinrelColors.ember.withValues(alpha: 0.08),
              KinrelColors.ember.withValues(alpha: 0.02),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: KinrelColors.ember.withValues(alpha: 0.15),
            width: 0.6,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: KinrelColors.ember),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: KinrelColors.textSilver.withValues(alpha: 0.80),
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 8. Family Settings Section
// ═══════════════════════════════════════════════════════════════════════

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.familyId});
  final String familyId;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF11132A).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
          width: 0.6,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'FAMILY SETTINGS',
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textDim,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          _SettingsRow(
            icon: Icons.notifications_none_rounded,
            label: 'Notifications',
            onTap: () {},
          ),
          _SettingsRow(
            icon: Icons.palette_outlined,
            label: 'Wallpaper & Atmosphere',
            onTap: () {
              // Navigate to chat where the atmosphere picker lives
              context.push('/family/$familyId/chat');
            },
          ),
          _SettingsRow(
            icon: Icons.lock_outline_rounded,
            label: 'Privacy Controls',
            onTap: () {
              context.push('/family/$familyId/management');
            },
          ),
          _SettingsRow(
            icon: Icons.admin_panel_settings_outlined,
            label: 'Family Permissions',
            onTap: () {
              context.push('/family/$familyId/management');
            },
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
        padding: const EdgeInsets.symmetric(vertical: 14),
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
            Icon(icon, size: 18, color: KinrelColors.ember),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: KinrelColors.textWhite,
                  letterSpacing: 0.1,
                ),
              ),
            ),
            Icon(Icons.chevron_right,
                size: 18, color: KinrelColors.textDim),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 9. Enter Family Space Gateway
// ═══════════════════════════════════════════════════════════════════════

class _FamilySpaceGateway extends StatelessWidget {
  const _FamilySpaceGateway({required this.familyId});
  final String familyId;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => context.go('/family/$familyId'),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 24),
          decoration: BoxDecoration(
            // v135: Premium gateway gradient — ember-tinted to feel
            // like entering a larger, warmer world beyond the chat.
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                KinrelColors.ember.withValues(alpha: 0.18),
                KinrelColors.ember.withValues(alpha: 0.08),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: KinrelColors.ember.withValues(alpha: 0.35),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: KinrelColors.ember.withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              // Globe icon — suggests entering a larger world
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: KinrelColors.ember.withValues(alpha: 0.20),
                  border: Border.all(
                    color: KinrelColors.ember.withValues(alpha: 0.50),
                    width: 1.2,
                  ),
                ),
                child: Icon(
                  Icons.public_rounded,
                  size: 22,
                  color: KinrelColors.ember,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Enter Family Space',
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: KinrelColors.textWhite,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Explore the full family experience',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: KinrelColors.textSilver
                            .withValues(alpha: 0.85),
                        letterSpacing: 0.1,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_rounded,
                  size: 22, color: KinrelColors.ember),
            ],
          ),
        ),
      ),
    );
  }
}

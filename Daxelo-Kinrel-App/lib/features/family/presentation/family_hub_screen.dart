// lib/features/family/presentation/family_hub_screen.dart
//
// DAXELO KINREL — Family Hub (v136)
//
// A premium intermediate screen between the chat and the Family Space.
// v136 redesign: elevated visual presentation with immersive hero,
// atmospheric background, three-level section hierarchy, timeline
// activity, and a stunning emotional gateway. No new features —
// only visual improvements.
//
// Three visual levels:
//   Level 1 (largest weight): Hero Section + Enter Family Space Gateway
//   Level 2 (medium weight): Members, Shared Content, Activity Overview
//   Level 3 (lower weight): Settings, Insights
//
// Route: /family/:id/hub

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/family/family_provider.dart';
import '../data/group_provider.dart';
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
    // v5.2: Use the unified roster (FamilyMember + Person nodes) so the
    // grid shows ALL family members, including manually-added Persons.
    final rosterAsync = ref.watch(unifiedFamilyRosterProvider(familyId));
    final membershipsAsync = ref.watch(familyMembershipsProvider(familyId));

    final family = familyAsync.valueOrNull?.family;
    final roster = rosterAsync.valueOrNull ?? [];
    final memberships = membershipsAsync.valueOrNull ?? [];

    return DKScaffold(
      backgroundColor: const Color(0xFF080912),
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
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: KinrelColors.textSilver,
            letterSpacing: 1.2,
          ),
        ),
        centerTitle: false,
      ),
      body: family == null
          ? const Center(
              child: CircularProgressIndicator(color: KinrelColors.orange),
            )
          : Stack(
              children: [
                // v136: Atmospheric background — extremely subtle floating
                // glow orbs that create warmth without distraction. Almost
                // invisible but felt.
                const _AtmosphericBackground(),
                // Main content
                ListView(
                  padding: const EdgeInsets.only(bottom: 48),
                  children: [
                    // ── LEVEL 1: Hero ─────────────────────────────────
                    _HeroSection(
                      family: family,
                      avatarUrl: avatarUrl,
                      onlineCount: chatState.onlineCount,
                    ),

                    const SizedBox(height: 20),

                    // ── LEVEL 2: Groups (v137) ──────────────────────
                    _GroupsQuickAccess(familyId: familyId),

                    // ── LEVEL 2: Members ─────────────────────────────
                    _MembersSection(
                      familyId: familyId,
                      roster: roster,
                      memberCount: roster.isNotEmpty ? roster.length : family.memberCount,
                    ),

                    // ── LEVEL 2: Shared Content ──────────────────────
                    _SharedContentSection(
                      familyId: familyId,
                      messages: chatState.messages,
                    ),

                    // ── LEVEL 2: Activity Overview (timeline) ────────
                    _ActivityTimelineSection(
                      family: family,
                      messages: chatState.messages,
                      memberships: memberships,
                    ),

                    // ── LEVEL 2: Pinned Messages ─────────────────────
                    _PinnedMessagesSection(
                      familyId: familyId,
                      messages: chatState.messages,
                    ),

                    // ── LEVEL 3: Insights ────────────────────────────
                    _InsightsSection(
                      messages: chatState.messages,
                      memberCount: family.memberCount,
                      onlineCount: chatState.onlineCount,
                    ),

                    // ── LEVEL 3: Family Identity ─────────────────────
                    _IdentityCard(family: family),

                    // ── LEVEL 3: Settings ────────────────────────────
                    _SettingsSection(familyId: familyId),

                    const SizedBox(height: 28),

                    // ── LEVEL 1: Enter Family Space Gateway ──────────
                    _FamilySpaceGateway(family: family),

                    const SizedBox(height: 32),
                  ],
                ),
              ],
            ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Atmospheric Background — extremely subtle floating glow orbs
// ═══════════════════════════════════════════════════════════════════════

class _AtmosphericBackground extends StatelessWidget {
  const _AtmosphericBackground();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          // Base radial gradient — barely visible warmth at top
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topCenter,
                  radius: 1.2,
                  colors: [
                    KinrelColors.ember.withValues(alpha: 0.05),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.6],
                ),
              ),
            ),
          ),
          // Floating orb 1 — top right, ember
          Positioned(
            top: 80,
            right: -40,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    KinrelColors.ember.withValues(alpha: 0.08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Floating orb 2 — middle left, cooler tone
          Positioned(
            top: 400,
            left: -60,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF3B4178).withValues(alpha: 0.06),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Floating orb 3 — bottom center, warm
          Positioned(
            bottom: 200,
            right: -30,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    KinrelColors.ember.withValues(alpha: 0.06),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 1. Hero Section — LEVEL 1 (largest visual weight)
// ═══════════════════════════════════════════════════════════════════════

class _HeroSection extends StatelessWidget {
  const _HeroSection({
    required this.family,
    required this.avatarUrl,
    required this.onlineCount,
  });

  final Family family;
  final String? avatarUrl;
  final int onlineCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        children: [
          // v136: Massive 140px avatar with layered ambient glow.
          // Three stacked glow rings create depth + warmth.
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                // Outer ambient glow — widest, softest
                BoxShadow(
                  color: KinrelColors.ember.withValues(alpha: 0.20),
                  blurRadius: 40,
                  offset: const Offset(0, 0),
                ),
                // Middle glow — warmer, closer
                BoxShadow(
                  color: KinrelColors.ember.withValues(alpha: 0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
                // Inner depth shadow — grounds the avatar
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.30),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: KinrelColors.ember.withValues(alpha: 0.45),
                  width: 2,
                ),
              ),
              child: ClipOval(
                child: avatarUrl != null && avatarUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: avatarUrl!,
                        fit: BoxFit.cover,
                        width: 136,
                        height: 136,
                        placeholder: (_, __) =>
                            _HeroInitials(family: family),
                        errorWidget: (_, __, ___) =>
                            _HeroInitials(family: family),
                      )
                    : _HeroInitials(family: family),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // v136: Family name — the PRIMARY focus. 28px display, w700,
          // letter-spaced for elegance. Reads as the emotional anchor.
          Text(
            family.name,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: KinrelColors.textWhite,
              letterSpacing: 0.5,
              height: 1.2,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          // v136: Family type chip + active status — SECONDARY.
          // Smaller, dimmer, sits quietly below the name.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: KinrelColors.ember.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: KinrelColors.ember.withValues(alpha: 0.25),
                    width: 0.6,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.favorite_rounded,
                        size: 10, color: KinrelColors.ember),
                    const SizedBox(width: 5),
                    Text(
                      'Family',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.ember.withValues(alpha: 0.90),
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
              if (onlineCount > 0) ...[
                const SizedBox(width: 10),
                Container(
                  width: 5,
                  height: 5,
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
                  '$onlineCount active now',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                    color: KinrelColors.textSilver.withValues(alpha: 0.75),
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ],
          ),
          // Family description
          if (family.description != null &&
              family.description!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                family.description!,
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
            fontSize: 52,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 1b. Groups Quick Access — LEVEL 2 (v137)
// ═══════════════════════════════════════════════════════════════════════

class _GroupsQuickAccess extends ConsumerWidget {
  const _GroupsQuickAccess({required this.familyId});

  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(familyGroupsProvider(familyId));

    return groupsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (groups) {
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => context.push('/family/$familyId/groups'),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: _level2CardDecoration(),
              child: Row(
                children: [
                  // Icon with ember glow
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: KinrelColors.ember.withValues(alpha: 0.12),
                      border: Border.all(
                        color: KinrelColors.ember.withValues(alpha: 0.35),
                        width: 1.2,
                      ),
                    ),
                    child: Icon(
                      Icons.groups_2_rounded,
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
                          'Family Groups',
                          style: TextStyle(
                            fontFamily: KinrelTypography.displayFont,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: KinrelColors.textWhite,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          groups.isEmpty
                              ? 'Create sub-groups for cousins, parents, siblings & more'
                              : '${groups.length} group${groups.length == 1 ? '' : 's'} · Tap to view all',
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 12,
                            color: KinrelColors.textSilver
                                .withValues(alpha: 0.75),
                            height: 1.3,
                            letterSpacing: 0.1,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right,
                      size: 22, color: KinrelColors.textDim),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 2. Members Section — LEVEL 2 (medium visual weight)
// ═══════════════════════════════════════════════════════════════════════

class _MembersSection extends StatelessWidget {
  const _MembersSection({
    required this.familyId,
    required this.roster,
    required this.memberCount,
  });

  final String familyId;
  final List<UnifiedFamilyMember> roster;
  final int memberCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: _level2CardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header with count
          Row(
            children: [
              Icon(Icons.people_alt_rounded,
                  size: 16, color: KinrelColors.ember),
              const SizedBox(width: 8),
              Text(
                'Family Members',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textWhite,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: KinrelColors.ember.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  '$memberCount',
                  style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.ember,
                  ),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => context.push('/family/$familyId/members'),
                child: Text(
                  'View all',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.ember,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // v136: Larger member cards with better grouping.
          // 2-column layout (was 3) so each card has more room.
          if (roster.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'No members yet',
                  style: TextStyle(color: KinrelColors.textDim, fontSize: 13),
                ),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 14,
                childAspectRatio: 0.92,
              ),
              itemCount: roster.take(4).length,
              itemBuilder: (ctx, i) {
                return _MemberCard(member: roster[i]);
              },
            ),
        ],
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({required this.member});
  final UnifiedFamilyMember member;

  @override
  Widget build(BuildContext context) {
    final name = member.displayName;
    final initials = member.initials;
    final avatarUrl = member.avatarUrl;

    return GestureDetector(
      onTap: () {
        // v5.2: If this is a Kinrel user (has userId), open DM.
        // If it's a manually-added Person, open their profile.
        if (member.userId != null && member.userId!.isNotEmpty) {
          context.push('/dm/${member.userId}');
        } else if (member.personId != null) {
          context.push('/member/${member.personId}');
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: member.isAdmin
                ? KinrelColors.ember.withValues(alpha: 0.20)
                : Colors.white.withValues(alpha: 0.05),
            width: 0.6,
          ),
        ),
        child: Column(
          children: [
            // v136: Larger 64px avatar (was 56px)
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: member.isAdmin
                      ? KinrelColors.ember.withValues(alpha: 0.55)
                      : Colors.white.withValues(alpha: 0.10),
                  width: 1.5,
                ),
                boxShadow: member.isAdmin
                    ? [
                        BoxShadow(
                          color: KinrelColors.ember
                              .withValues(alpha: 0.15),
                          blurRadius: 10,
                          offset: const Offset(0, 0),
                        ),
                      ]
                    : null,
              ),
              child: ClipOval(
                child: avatarUrl != null && avatarUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: avatarUrl,
                        fit: BoxFit.cover,
                        width: 62,
                        height: 62,
                        placeholder: (_, __) =>
                            _MemberInitials(initials: initials),
                        errorWidget: (_, __, ___) =>
                            _MemberInitials(initials: initials),
                      )
                    : _MemberInitials(initials: initials),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              name,
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textWhite,
                letterSpacing: 0.15,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 3),
            Text(
              member.displayRole,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: member.isAdmin
                    ? KinrelColors.ember.withValues(alpha: 0.85)
                    : KinrelColors.textDim,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
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
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 3. Shared Content Section — LEVEL 2
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
        .take(4)
        .toList();
    final photoCount =
        messages.where((m) => m.messageType == MessageType.photo).length;
    final voiceCount = messages
        .where((m) => m.messageType == MessageType.voiceNote)
        .length;
    final stickerCount = messages
        .where((m) => m.messageType == MessageType.sticker)
        .length;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: _level2CardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.photo_library_outlined,
                  size: 16, color: KinrelColors.ember),
              const SizedBox(width: 8),
              Text(
                'Shared Moments',
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
          // v136: Larger preview images with better ratios.
          // 2-column grid with 1:1 aspect ratio (was 3-column cramped).
          if (photos.isNotEmpty) ...[
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
            const SizedBox(height: 14),
          ],
          // Media count chips
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
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: KinrelColors.ember),
            const SizedBox(height: 5),
            Text(
              '$count',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 15,
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
// 4. Activity Timeline Section — LEVEL 2 (redesigned as timeline)
// ═══════════════════════════════════════════════════════════════════════

class _ActivityTimelineSection extends StatelessWidget {
  const _ActivityTimelineSection({
    required this.family,
    required this.messages,
    required this.memberships,
  });

  final Family family;
  final List<ChatMessage> messages;
  final List<FamilyMembership> memberships;

  @override
  Widget build(BuildContext context) {
    // Build timeline entries from recent activity
    final entries = _buildTimelineEntries().take(4).toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: _level2CardDecoration(),
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
          if (entries.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No recent activity',
                  style: TextStyle(color: KinrelColors.textDim, fontSize: 12.5),
                ),
              ),
            )
          else
            Column(
              children: entries.asMap().entries.map((entry) {
                final i = entry.key;
                final e = entry.value;
                final isLast = i == entries.length - 1;
                return _TimelineEntry(
                  entry: e,
                  isLast: isLast,
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  List<_TimelineEntryData> _buildTimelineEntries() {
    final list = <_TimelineEntryData>[];

    // Most recent photo
    final recentPhoto = messages
        .where((m) =>
            m.messageType == MessageType.photo &&
            m.mediaUrl != null &&
            m.mediaUrl!.isNotEmpty)
        .firstOrNull;
    if (recentPhoto != null) {
      list.add(_TimelineEntryData(
        icon: Icons.photo_camera_rounded,
        title: '${recentPhoto.senderName} shared a photo',
        time: recentPhoto.timestamp,
        color: KinrelColors.ember,
      ));
    }

    // Most recent voice note
    final recentVoice = messages
        .where((m) => m.messageType == MessageType.voiceNote)
        .firstOrNull;
    if (recentVoice != null) {
      list.add(_TimelineEntryData(
        icon: Icons.mic_rounded,
        title: '${recentVoice.senderName} sent a voice message',
        time: recentVoice.timestamp,
        color: const Color(0xFF6B8AFF),
      ));
    }

    // Most recent sticker
    final recentSticker = messages
        .where((m) => m.messageType == MessageType.sticker)
        .firstOrNull;
    if (recentSticker != null) {
      list.add(_TimelineEntryData(
        icon: Icons.emoji_emotions_rounded,
        title: '${recentSticker.senderName} reacted with an emoji',
        time: recentSticker.timestamp,
        color: const Color(0xFFFFB74D),
      ));
    }

    // Most recent message
    if (messages.isNotEmpty) {
      final last = messages.first;
      list.add(_TimelineEntryData(
        icon: Icons.chat_bubble_outline_rounded,
        title: '${last.senderName} sent a message',
        time: last.timestamp,
        color: KinrelColors.success,
      ));
    }

    // Sort by time descending (most recent first)
    list.sort((a, b) => b.time.compareTo(a.time));
    return list;
  }
}

class _TimelineEntryData {
  const _TimelineEntryData({
    required this.icon,
    required this.title,
    required this.time,
    required this.color,
  });

  final IconData icon;
  final String title;
  final DateTime time;
  final Color color;
}

class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry({required this.entry, required this.isLast});

  final _TimelineEntryData entry;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Timeline dot + connector line
        SizedBox(
          width: 28,
          child: Column(
            children: [
              // Icon dot
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: entry.color.withValues(alpha: 0.15),
                  border: Border.all(
                    color: entry.color.withValues(alpha: 0.50),
                    width: 1.2,
                  ),
                ),
                child: Icon(entry.icon, size: 13, color: entry.color),
              ),
              // Connector line (unless last)
              if (!isLast)
                Container(
                  width: 1.2,
                  height: 36,
                  margin: const EdgeInsets.only(top: 4),
                  color: Colors.white.withValues(alpha: 0.08),
                ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        // Content
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(top: 4, bottom: isLast ? 0 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
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
                  _formatTimeAgo(entry.time),
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
// 5. Pinned Messages Section — LEVEL 2
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
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: _level2CardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.push_pin_rounded,
                  size: 16, color: KinrelColors.ember),
              const SizedBox(width: 8),
              Text(
                'Pinned Messages',
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
          ...pinned.map((m) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(14),
                  border: Border(
                    left: BorderSide(
                      color: KinrelColors.ember.withValues(alpha: 0.65),
                      width: 3,
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
                    const SizedBox(height: 5),
                    Text(
                      m.content.isNotEmpty
                          ? m.content
                          : '[${m.messageType.name}]',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 13,
                        color: KinrelColors.textSilver.withValues(alpha: 0.90),
                        height: 1.45,
                        letterSpacing: 0.1,
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
// 6. Conversation Insights — LEVEL 3 (lower visual weight)
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
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: _level3CardDecoration(),
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
              KinrelColors.ember.withValues(alpha: 0.07),
              KinrelColors.ember.withValues(alpha: 0.02),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: KinrelColors.ember.withValues(alpha: 0.12),
            width: 0.6,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: KinrelColors.ember),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 9.5,
                fontWeight: FontWeight.w500,
                color: KinrelColors.textSilver.withValues(alpha: 0.75),
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
// 7. Family Identity Card — LEVEL 3
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
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: _level3CardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                height: 44,
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
          const SizedBox(height: 12),
          Container(
            height: 1,
            color: Colors.white.withValues(alpha: 0.06),
          ),
          const SizedBox(height: 12),
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
                height: 44,
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
              Icon(icon, size: 11, color: KinrelColors.ember),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w500,
                  color: KinrelColors.textDim,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 13,
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
// 8. Family Settings — LEVEL 3
// ═══════════════════════════════════════════════════════════════════════

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.familyId});
  final String familyId;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: _level3CardDecoration(),
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
          const SizedBox(height: 12),
          _SettingsRow(
            icon: Icons.notifications_none_rounded,
            label: 'Notifications',
            onTap: () {},
          ),
          _SettingsRow(
            icon: Icons.palette_outlined,
            label: 'Wallpaper & Atmosphere',
            onTap: () => context.push('/family/$familyId/chat'),
          ),
          _SettingsRow(
            icon: Icons.lock_outline_rounded,
            label: 'Privacy Controls',
            onTap: () => context.push('/family/$familyId/management'),
          ),
          _SettingsRow(
            icon: Icons.admin_panel_settings_outlined,
            label: 'Family Permissions',
            onTap: () => context.push('/family/$familyId/management'),
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
// 9. Enter Family Space Gateway — LEVEL 1 (most impressive card)
// ═══════════════════════════════════════════════════════════════════════

class _FamilySpaceGateway extends StatelessWidget {
  const _FamilySpaceGateway({required this.family});
  final Family family;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => context.go('/family/${family.id}'),
        child: Container(
          // v136: Larger height + premium lighting effects.
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 28),
          decoration: BoxDecoration(
            // Layered gradient — ember warmth radiating from top-left
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                KinrelColors.ember.withValues(alpha: 0.22),
                KinrelColors.ember.withValues(alpha: 0.10),
                const Color(0xFF1A1D2E).withValues(alpha: 0.6),
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: KinrelColors.ember.withValues(alpha: 0.40),
              width: 1.5,
            ),
            boxShadow: [
              // v136: Premium lighting — outer ambient glow
              BoxShadow(
                color: KinrelColors.ember.withValues(alpha: 0.25),
                blurRadius: 32,
                offset: const Offset(0, 8),
              ),
              // Inner depth shadow
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.20),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              // Large premium icon with layered glow
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      KinrelColors.ember.withValues(alpha: 0.35),
                      KinrelColors.ember.withValues(alpha: 0.15),
                    ],
                  ),
                  border: Border.all(
                    color: KinrelColors.ember.withValues(alpha: 0.55),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: KinrelColors.ember.withValues(alpha: 0.30),
                      blurRadius: 20,
                      offset: const Offset(0, 0),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.public_rounded,
                  size: 30,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 20),
              // v136: More emotional wording
              Text(
                'Step into your family\'s shared world',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                  letterSpacing: 0.3,
                  height: 1.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Continue your family\'s journey together',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: KinrelColors.textSilver.withValues(alpha: 0.80),
                  letterSpacing: 0.2,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 22),
              // Premium enter button
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
                decoration: BoxDecoration(
                  gradient: KinrelGradients.igniteGradient,
                  borderRadius: BorderRadius.circular(100),
                  boxShadow: [
                    BoxShadow(
                      color: KinrelColors.ember.withValues(alpha: 0.40),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Enter Family Space',
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

// ═══════════════════════════════════════════════════════════════════════
// Shared card decorations — three visual levels
// ═══════════════════════════════════════════════════════════════════════

/// Level 2 card decoration — medium visual weight.
/// Used by Members, Shared Content, Activity Timeline, Pinned Messages.
/// Soft gradient surface + hairline border + subtle shadow.
BoxDecoration _level2CardDecoration() {
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        const Color(0xFF1A1D2E),
        const Color(0xFF14162A),
      ],
    ),
    borderRadius: BorderRadius.circular(20),
    border: Border.all(
      color: Colors.white.withValues(alpha: 0.06),
      width: 0.75,
    ),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.20),
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
    ],
  );
}

/// Level 3 card decoration — lower visual weight.
/// Used by Insights, Identity, Settings.
/// Flatter surface, no gradient, hairline border only.
BoxDecoration _level3CardDecoration() {
  return BoxDecoration(
    color: const Color(0xFF11132A).withValues(alpha: 0.55),
    borderRadius: BorderRadius.circular(18),
    border: Border.all(
      color: Colors.white.withValues(alpha: 0.04),
      width: 0.6,
    ),
  );
}

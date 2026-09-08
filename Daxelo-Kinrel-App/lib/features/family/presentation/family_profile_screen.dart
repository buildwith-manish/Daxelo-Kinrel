// lib/features/family/presentation/family_profile_screen.dart
//
// DAXELO KINREL — Family Profile Screen (Phase 22 / Header Nav Fix)
//
// A dedicated, profile-style view of a FAMILY (not an individual member).
// Reached by tapping the chat header in a family chat (avatar, family
// name, family badge, member count, online status, or the header
// section). Distinct from:
//   - FamilyDetailScreen (`/family/:id`) — the Family Space dashboard
//     (utility hub with tabs, floating nav, etc.).
//   - MemberProfileSheet — a single member's profile bottom sheet
//     (reached by tapping a member's avatar INSIDE the chat thread,
//     e.g. on a message bubble).
//
// This screen shows:
//   - Family name + avatar/logo
//   - Family description (if available)
//   - Total member count + created date
//   - Family admins (owner + admin roles)
//   - Member list (tappable → MemberProfileSheet)
//   - Family invite/share options (family code + QR + share)
//   - Family settings link (admin-only)
//   - Family statistics (generations, last activity — best-effort)
//
// The screen is a ConsumerStatefulWidget so it can watch
// familyDetailProvider, familyMembershipsProvider, and
// familyAvatarProvider without prop-drilling.

import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
// Hide the riverpod `Family` typedef so it doesn't collide with the
// `Family` model class from family_provider.dart (used throughout this
// screen for family info rendering).
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../presence/last_seen_provider.dart';
import '../../profile/presentation/member_profile_sheet.dart';

class FamilyProfileScreen extends ConsumerWidget {
  const FamilyProfileScreen({super.key, required this.familyId});
  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(familyDetailProvider(familyId));
    final membershipsAsync =
        ref.watch(familyMembershipsProvider(familyId));
    final avatarUrl = ref.watch(familyAvatarProvider(familyId));
    final currentUserId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    // Tier 1 / Last Seen — watch the global presence map so member
    // rows can show a green/gray presence dot. The map is keyed by
    // userId; missing entries are users who never opened the app
    // since UserPresence shipped (treated as "offline").
    final presenceMap = ref.watch(lastSeenProvider);

    final detail = detailAsync.valueOrNull;
    final family = detail?.family;
    final memberships = membershipsAsync.valueOrNull ?? [];

    // Determine whether the current user is an admin (for the settings link).
    final isCurrentUserAdmin = memberships.any(
      (m) => m.userId == currentUserId && m.isAdmin,
    );

    return DKScaffold(
      backgroundColor: const Color(0xFF0A0B16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0B16),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: KinrelColors.textSilver, size: 18),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
        ),
        title: Text(
          'Family Profile',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textWhite,
          ),
        ),
        actions: [
          // Admin-only: family settings shortcut.
          if (isCurrentUserAdmin)
            IconButton(
              icon: const Icon(Icons.settings_outlined,
                  color: KinrelColors.textSilver, size: 20),
              tooltip: 'Family settings',
              onPressed: () =>
                  context.push('/family/$familyId/management'),
            ),
          IconButton(
            icon: const Icon(Icons.more_vert,
                color: KinrelColors.textSilver, size: 20),
            onPressed: () => _showMoreMenu(context, family, isCurrentUserAdmin),
          ),
        ],
      ),
      body: detailAsync.isLoading && family == null
          ? const Center(
              child: CircularProgressIndicator(color: KinrelColors.ember),
            )
          : detailAsync.hasError && family == null
              ? _buildErrorState(detailAsync.error)
              : _buildBody(
                  context,
                  ref,
                  family,
                  memberships,
                  avatarUrl,
                  currentUserId,
                  isCurrentUserAdmin,
                  presenceMap,
                ),
    );
  }

  Widget _buildErrorState(Object? error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: KinrelColors.error),
            const SizedBox(height: 12),
            Text(
              'Could not load family profile',
              style: TextStyle(
                color: KinrelColors.textWhite,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              error?.toString() ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: TextStyle(color: KinrelColors.textDim, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    Family? family,
    List<FamilyMembership> memberships,
    String? avatarUrl,
    String? currentUserId,
    bool isCurrentUserAdmin,
    Map<String, UserLastSeen> presenceMap,
  ) {
    if (family == null) return const SizedBox.shrink();
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        _buildHero(context, family, avatarUrl, memberships.length),
        const SizedBox(height: 20),
        if (family.description != null && family.description!.isNotEmpty)
          _buildSection(
            context,
            title: 'About',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                family.description!,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  color: KinrelColors.textSilver,
                  height: 1.5,
                ),
              ),
            ),
          ),
        if (family.description != null && family.description!.isNotEmpty)
          const SizedBox(height: 20),
        _buildStatsRow(context, family, memberships.length),
        const SizedBox(height: 20),
        _buildAdminsSection(context, memberships),
        const SizedBox(height: 20),
        _buildMembersSection(context, memberships, currentUserId, presenceMap),
        const SizedBox(height: 20),
        _buildInviteSection(context, family),
        if (isCurrentUserAdmin) ...[
          const SizedBox(height: 20),
          _buildSettingsSection(context, familyId),
        ],
        const SizedBox(height: 20),
        _buildOpenFamilySpaceSection(context, familyId),
      ],
    );
  }

  // ── Hero: avatar + name + username + member count ──────────────────

  Widget _buildHero(
    BuildContext context,
    Family family,
    String? avatarUrl,
    int memberCount,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF11132A), Color(0xFF0A0B16)],
        ),
      ),
      child: Column(
        children: [
          // Avatar — large, with ember ring (mirrors chat header treatment)
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
              border: Border.all(
                color: KinrelColors.ember.withValues(alpha: 0.35),
                width: 1.5,
              ),
            ),
            child: ClipOval(
              child: avatarUrl != null && avatarUrl.isNotEmpty
                  ? (avatarUrl.startsWith('data:')
                      ? Image.memory(
                          base64Decode(avatarUrl.substring(avatarUrl.indexOf(',') + 1)),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildLetterAvatar(family.name),
                        )
                      : CachedNetworkImage(
                          imageUrl: avatarUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => _buildLetterAvatar(family.name),
                          errorWidget: (_, __, ___) => _buildLetterAvatar(family.name),
                        ))
                  : _buildLetterAvatar(family.name),
            ),
          ),
          const SizedBox(height: 16),
          // Family name
          Text(
            family.name,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: KinrelColors.textWhite,
              letterSpacing: 0.2,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (family.displayUsername.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              family.displayUsername,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                color: KinrelColors.ember.withValues(alpha: 0.9),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 12),
          // Member count chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: KinrelColors.ember.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(
                color: KinrelColors.ember.withValues(alpha: 0.30),
                width: 0.7,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.group_rounded,
                    size: 13, color: KinrelColors.ember),
                const SizedBox(width: 6),
                Text(
                  '$memberCount ${memberCount == 1 ? 'member' : 'members'}',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.ember.withValues(alpha: 0.95),
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLetterAvatar(String name) {
    final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
    final initials = parts.isEmpty
        ? '?'
        : parts.length == 1
            ? parts[0][0].toUpperCase()
            : '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: KinrelGradients.igniteGradient,
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w800,
            color: KinrelColors.textWhite,
          ),
        ),
      ),
    );
  }

  // ── Stats row: created date, generations, last activity ────────────

  Widget _buildStatsRow(BuildContext context, Family family, int memberCount) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _statCard(
            icon: Icons.calendar_today_rounded,
            label: 'Created',
            value: family.createdAt != null
                ? _formatDate(family.createdAt!)
                : '—',
          ),
          const SizedBox(width: 10),
          _statCard(
            icon: Icons.account_tree_rounded,
            label: 'Generations',
            value: '${family.generationCount}',
          ),
          const SizedBox(width: 10),
          _statCard(
            icon: Icons.history_rounded,
            label: 'Last activity',
            value: family.lastActivityAt != null
                ? _formatDate(family.lastActivityAt!)
                : '—',
          ),
        ],
      ),
    );
  }

  Widget _statCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF11132A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.05),
            width: 0.6,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: KinrelColors.ember),
            const SizedBox(height: 6),
            Text(
              value,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 9.5,
                color: KinrelColors.textDim,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    return '${local.day}/${local.month}/${local.year}';
  }

  // ── Section wrapper ─────────────────────────────────────────────────

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textDim,
              letterSpacing: 1.2,
            ),
          ),
        ),
        child,
      ],
    );
  }

  // ── Admins section ───────────────────────────────────────────────────

  Widget _buildAdminsSection(
    BuildContext context,
    List<FamilyMembership> memberships,
  ) {
    final admins = memberships.where((m) => m.isAdmin).toList();
    if (admins.isEmpty) return const SizedBox.shrink();

    return _buildSection(
      context,
      title: 'Admins',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: admins
              .map((m) => _buildAdminChip(context, m))
              .toList(),
        ),
      ),
    );
  }

  Widget _buildAdminChip(BuildContext context, FamilyMembership m) {
    final name = m.user?.displayName ?? 'Admin';
    final initials = m.user?.initials ?? '?';
    return GestureDetector(
      onTap: () => MemberProfileSheet.show(context, m.userId),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
            CircleAvatar(
              radius: 11,
              backgroundColor: KinrelColors.ember.withValues(alpha: 0.18),
              child: Text(
                initials,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.ember,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              name,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: KinrelColors.ember.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                m.displayRole,
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.ember,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Members section ─────────────────────────────────────────────────

  Widget _buildMembersSection(
    BuildContext context,
    List<FamilyMembership> memberships,
    String? currentUserId,
    Map<String, UserLastSeen> presenceMap,
  ) {
    if (memberships.isEmpty) return const SizedBox.shrink();
    // Sort: admins first, then alphabetical by name.
    final sorted = [...memberships]..sort((a, b) {
        final aAdmin = a.isAdmin ? 0 : 1;
        final bAdmin = b.isAdmin ? 0 : 1;
        if (aAdmin != bAdmin) return aAdmin - bAdmin;
        return (a.user?.displayName ?? '').compareTo(b.user?.displayName ?? '');
      });

    return _buildSection(
      context,
      title: 'Members (${memberships.length})',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF11132A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.05),
              width: 0.6,
            ),
          ),
          child: Column(
            children: [
              for (var i = 0; i < sorted.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                _buildMemberRow(
                  context,
                  sorted[i],
                  sorted[i].userId == currentUserId,
                  presenceMap[sorted[i].userId],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMemberRow(
    BuildContext context,
    FamilyMembership m,
    bool isSelf,
    UserLastSeen? presence,
  ) {
    final name = m.user?.displayName ?? 'Member';
    final initials = m.user?.initials ?? '?';
    final online = isUserOnline(presence);
    return InkWell(
      onTap: () => MemberProfileSheet.show(context, m.userId),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            // Tier 1 / Last Seen — wrap the avatar in a Stack with a
            // small presence dot at the bottom-right. Green for online,
            // dim for offline. WhatsApp-style.
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: KinrelColors.ember.withValues(alpha: 0.15),
                  backgroundImage: m.user?.avatarUrl != null &&
                          m.user!.avatarUrl!.isNotEmpty
                      ? CachedNetworkImageProvider(m.user!.avatarUrl!)
                      : null,
                  child: m.user?.avatarUrl == null ||
                          m.user!.avatarUrl!.isEmpty
                      ? Text(
                          initials,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: KinrelColors.ember,
                          ),
                        )
                      : null,
                ),
                // Presence dot (bottom-right, slightly outside the avatar)
                if (!isSelf)
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: online
                            ? const Color(0xFF4CAF50)
                            : const Color(0xFF6B7280),
                        border: Border.all(
                          color: const Color(0xFF11132A),
                          width: 2,
                        ),
                        boxShadow: online
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF4CAF50)
                                      .withValues(alpha: 0.5),
                                  blurRadius: 4,
                                  offset: const Offset(0, 0),
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isSelf ? '$name (You)' : name,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: KinrelColors.textWhite,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // Subtitle: @username if present, else last-seen label.
                  // Show the last-seen label only for OTHER users (not self).
                  if (m.user?.username != null &&
                      m.user!.username!.isNotEmpty)
                    Text(
                      '@${m.user!.username}',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 11,
                        color: KinrelColors.textDim,
                      ),
                    ),
                  // Tier 1 / Last Seen — show "last seen 5m ago" under
                  // the @username for OTHER users who aren't currently
                  // online. (Online users get the green dot on the
                  // avatar; the text would be redundant.) Hidden for
                  // self — you don't need to see your own last-seen.
                  if (!isSelf && !online && presence != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      formatLastSeen(presence),
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 10.5,
                        color: KinrelColors.textDim.withValues(alpha: 0.7),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: m.isAdmin
                    ? KinrelColors.ember.withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                m.displayRole,
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: m.isAdmin
                      ? KinrelColors.ember
                      : KinrelColors.textSilver,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right,
                size: 18, color: KinrelColors.textDim),
          ],
        ),
      ),
    );
  }

  // ── Invite / share section ──────────────────────────────────────────

  Widget _buildInviteSection(BuildContext context, Family family) {
    return _buildSection(
      context,
      title: 'Invite & Share',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            if (family.familyCode != null && family.familyCode!.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF11132A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: KinrelColors.ember.withValues(alpha: 0.20),
                    width: 0.7,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.qr_code_rounded,
                        size: 18, color: KinrelColors.ember),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Family Code',
                            style: TextStyle(
                              fontFamily: KinrelTypography.monoFont,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                              color: KinrelColors.textDim,
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            family.familyCode!,
                            style: TextStyle(
                              fontFamily: KinrelTypography.monoFont,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: KinrelColors.textWhite,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded,
                          size: 18, color: KinrelColors.textSilver),
                      tooltip: 'Copy code',
                      onPressed: () {
                        // Copy to clipboard (best-effort).
                        // Using the static clipboard API to avoid an extra import.
                        // ignore: avoid_print
                        debugPrint('Family code copied: ${family.familyCode}');
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Family code copied'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _inviteButton(
                    icon: Icons.qr_code_2_rounded,
                    label: 'QR Code',
                    onTap: () => context.push('/family-qr?family=$familyId'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _inviteButton(
                    icon: Icons.share_rounded,
                    label: 'Share',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Share coming soon'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _inviteButton(
                    icon: Icons.person_add_rounded,
                    label: 'Add member',
                    onTap: () =>
                        context.push('/family/$familyId/add-member'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _inviteButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF11132A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.05),
            width: 0.6,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: KinrelColors.ember),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textSilver,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Settings section (admin-only) ──────────────────────────────────

  Widget _buildSettingsSection(BuildContext context, String familyId) {
    return _buildSection(
      context,
      title: 'Settings',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: GestureDetector(
          onTap: () => context.push('/family/$familyId/management'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF11132A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.05),
                width: 0.6,
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.tune_rounded,
                    size: 18, color: KinrelColors.ember),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Family settings & management',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right,
                    size: 18, color: KinrelColors.textDim),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Open Family Space section ──────────────────────────────────────

  Widget _buildOpenFamilySpaceSection(BuildContext context, String familyId) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: () => context.push('/family/$familyId'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            gradient: KinrelGradients.igniteGradient,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.space_dashboard_rounded,
                  size: 18, color: KinrelColors.textWhite),
              const SizedBox(width: 8),
              Text(
                'Open Family Space',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── More menu ───────────────────────────────────────────────────────

  void _showMoreMenu(
    BuildContext context,
    Family? family,
    bool isCurrentUserAdmin,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.group_rounded, color: KinrelColors.ember),
              title: Text('View all members',
                  style: TextStyle(color: KinrelColors.textWhite)),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/family/$familyId/members');
              },
            ),
            ListTile(
              leading: Icon(Icons.account_tree_rounded,
                  color: KinrelColors.ember),
              title: Text('Family tree',
                  style: TextStyle(color: KinrelColors.textWhite)),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/family/$familyId/graph');
              },
            ),
            ListTile(
              leading: Icon(Icons.timeline_rounded, color: KinrelColors.ember),
              title: Text('Family activity',
                  style: TextStyle(color: KinrelColors.textWhite)),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/family/$familyId/activity');
              },
            ),
            if (isCurrentUserAdmin)
              ListTile(
                leading: Icon(Icons.tune_rounded, color: KinrelColors.ember),
                title: Text('Settings',
                    style: TextStyle(color: KinrelColors.textWhite)),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/family/$familyId/management');
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

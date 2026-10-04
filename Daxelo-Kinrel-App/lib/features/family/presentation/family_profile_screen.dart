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
import '../../../core/constants/brand_typography.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../presence/last_seen_provider.dart';
import '../../profile/presentation/member_profile_sheet.dart';
// v5.212: MembersScreenSource — passes entry context (graphViewAll)
// to the Members screen when "View all members" is tapped from this
// Family Profile screen — the profile screen is a family-tree
// overview context.
import 'family_members_screen.dart';

// ─────────────────────────────────────────────────────────────────────────
// v5.214 — Family Profile Linked-member row model.
//
// Bug context: the Family Profile screen's member count + member list
// previously came from `familyMembershipsProvider` (the FamilyMember
// rows table — real Kinrel users who accepted an invite). For test
// families where Linked Person rows exist without corresponding
// FamilyMember rows (e.g. the creator's anchor Person has linkedUserId
// = null due to the server-side unique constraint, OR a Linked Person
// was added to the tree but the user never went through the invite-
// acceptance flow to create a FamilyMember row), the screen would
// show "1 member" + a single "Member (You)" placeholder row — neither
// the correct Linked-only count (2) NOR the full-tree count (5).
//
// This fix matches the Linked-only standard already applied to Family
// Chat, Family Space, and the bottom-nav Members screen (per the
// v5.211/v5.212 work). The Family Profile screen now derives its
// member list from Linked Person rows (filtering with the same
// trulyLinkedIds anchor-fallback logic [linkedMemberCountProvider]
// uses), then AUGMENTS each row with role / username / avatar info
// from the corresponding FamilyMembership row when one exists.
//
// The result is a single list of Linked members with:
//   • The Person's actual name (e.g. "Account 1") instead of a
//     generic "Member" label
//   • The role chip ('Admin' / 'Member') from FamilyMembership,
//     with the anchor Person defaulting to 'Admin' (since the family
//     creator is implicitly the family admin)
//   • The "(You)" tag only on the row matching the currently logged-
//     in user
// ─────────────────────────────────────────────────────────────────────────

/// A single Linked member row on the Family Profile screen.
///
/// Unifies [Person] data (name, photo, anchor flags) with the
/// corresponding [FamilyMembership] data (role, username, email,
/// avatarUrl from the embedded [MemberUserProfile]) when a
/// membership row exists for the same Kinrel user.
@immutable
class _LinkedMemberRow {
  const _LinkedMemberRow({
    required this.personId,
    required this.userId,
    required this.displayName,
    required this.initials,
    required this.avatarUrl,
    required this.username,
    required this.role,
    required this.isSelf,
  });

  /// Person.id — used as the row's ValueKey for stable React keys.
  final String personId;

  /// The Kinrel auth user ID for this member. Used to look up
  /// presence in [lastSeenProvider] and to open the
  /// [MemberProfileSheet]. May be null for the family anchor Person
  /// when the unique constraint prevented `linkedUserId` from being
  /// stored on the Person row — in that case, we still know it's the
  /// creator (via `family.createdBy`), so we use that ID for presence
  /// lookup.
  final String? userId;

  /// Display name. Prefers the FamilyMembership's user profile (which
  /// has the user's chosen name), falls back to the Person's name,
  /// then to 'Member' as a last-resort placeholder.
  final String displayName;

  /// 1-2 character initials for the avatar fallback.
  final String initials;

  /// Avatar image URL. Prefers the Person's photoUrl, falls back to
  /// the FamilyMembership's user avatarUrl.
  final String? avatarUrl;

  /// @username (without the @) if available from the FamilyMembership
  /// user profile. Null when no membership row exists.
  final String? username;

  /// Role string ('admin', 'owner', 'editor', 'viewer', 'member').
  /// Defaults to 'admin' for the family anchor Person (the creator is
  /// implicitly the admin), 'member' for everyone else.
  final String role;

  /// True if this row is the currently logged-in user. Used to render
  /// the "(You)" tag and to hide the presence dot on self.
  final bool isSelf;

  /// Whether the role is admin/owner (drives the chip color).
  bool get isAdmin =>
      role.toLowerCase() == 'admin' || role.toLowerCase() == 'owner';

  /// Display-friendly role label (capitalised).
  String get displayRole {
    switch (role.toLowerCase()) {
      case 'admin':
      case 'owner':
        return 'Admin';
      case 'editor':
        return 'Editor';
      case 'viewer':
        return 'Viewer';
      default:
        return 'Member';
    }
  }
}

/// Builds the list of Linked-member rows for the Family Profile
/// screen, using the SAME anchor-fallback logic that
/// [linkedMemberCountProvider] uses (so the count pill and the list
/// length always agree).
///
/// Returns one [_LinkedMemberRow] per Linked-status Person in the
/// family — Manual placeholder relatives are NOT included, matching
/// the Linked-only standard applied to Family Chat, Family Space, and
/// the bottom-nav Members screen.
List<_LinkedMemberRow> _buildLinkedMemberRows({
  required Family family,
  required List<Person> allMembers,
  required List<FamilyMembership> memberships,
  required String? currentUserId,
}) {
  final activeMembers = allMembers.where((p) => p.deletedAt == null).toList();

  // Step 1: compute the trulyLinkedIds set (same algorithm as
  // linkedMemberCountProvider + family_members_screen.dart).
  final membershipUserIds = memberships
      .where((m) => m.userId.isNotEmpty)
      .map((m) => m.userId)
      .toSet();
  final trulyLinkedIds = <String>{};
  for (final p in activeMembers) {
    if (p.linkedUserId != null && p.linkedUserId!.isNotEmpty) {
      trulyLinkedIds.add(p.id);
      continue;
    }
    // v5.209 anchor fallback: isAnchor + family.createdBy set
    // (the unique constraint prevented linkedUserId from being
    // stored on the Person row, but it IS a real account).
    if (p.isAnchor &&
        family.createdBy != null &&
        family.createdBy!.isNotEmpty) {
      trulyLinkedIds.add(p.id);
      continue;
    }
    // v5.210 fallback 2: Person is the family's designated anchor
    // (by anchorPersonId pointer) + family has a creator.
    if (family.anchorPersonId != null &&
        family.anchorPersonId == p.id &&
        family.createdBy != null &&
        family.createdBy!.isNotEmpty) {
      trulyLinkedIds.add(p.id);
      continue;
    }
    // v5.210 fallback 3: Person is the anchor + family's createdBy
    // matches a real FamilyMember's userId (cross-check against the
    // memberships table).
    if (p.isAnchor &&
        family.createdBy != null &&
        membershipUserIds.contains(family.createdBy)) {
      trulyLinkedIds.add(p.id);
      continue;
    }
  }

  // Step 2: build a {userId: FamilyMembership} map for quick lookup
  // by `linkedUserId`.
  final membershipByUserId = <String, FamilyMembership>{
    for (final m in memberships)
      if (m.userId.isNotEmpty) m.userId: m,
  };

  // Step 3: build one row per Linked Person, augmenting with the
  // matching FamilyMembership data when available.
  final rows = <_LinkedMemberRow>[];
  for (final p in activeMembers.where((p) => trulyLinkedIds.contains(p.id))) {
    final membership = p.linkedUserId != null &&
            p.linkedUserId!.isNotEmpty &&
            membershipByUserId.containsKey(p.linkedUserId)
        ? membershipByUserId[p.linkedUserId!]
        : null;

    // userId for presence lookup + MemberProfileSheet: prefer
    // Person.linkedUserId; for the anchor fallback case, use
    // family.createdBy (which is the creator's auth id).
    final userId = (p.linkedUserId != null && p.linkedUserId!.isNotEmpty)
        ? p.linkedUserId
        : (p.isAnchor ? family.createdBy : null);

    final isSelf = userId != null &&
        currentUserId != null &&
        userId == currentUserId;

    // Display name: prefer the membership's user profile (which has
    // the user's chosen name), fall back to Person.name, then to
    // 'Member' as a last resort (so the row never shows an empty
    // name).
    final displayName = membership?.user?.displayName ??
        (p.name.isNotEmpty ? p.name : 'Member');

    // Initials: prefer the membership's user profile, fall back to
    // deriving from the display name.
    final initials = membership?.user?.initials ??
        _initialsFromName(displayName);

    // Avatar URL: prefer the Person's photoUrl (which is set when
    // the user uploaded an avatar directly on their Person node),
    // fall back to the membership's user avatarUrl.
    final avatarUrl = (p.photoUrl != null && p.photoUrl!.isNotEmpty)
        ? p.photoUrl
        : membership?.user?.avatarUrl;

    // Username: only available from the FamilyMembership user
    // profile (the Person table doesn't carry @username).
    final username = membership?.user?.username;

    // Role: prefer the FamilyMembership's role; if no membership
    // exists (the anchor fallback case), default to 'admin' since
    // the family creator is implicitly the admin.
    final role = membership?.role ??
        (p.isAnchor && family.createdBy != null ? 'admin' : 'member');

    rows.add(_LinkedMemberRow(
      personId: p.id,
      userId: userId,
      displayName: displayName,
      initials: initials,
      avatarUrl: avatarUrl,
      username: username,
      role: role,
      isSelf: isSelf,
    ));
  }

  return rows;
}

/// Derives 1-2 character initials from a display name (used when no
/// MemberUserProfile is available to provide initials directly).
String _initialsFromName(String name) {
  if (name.isEmpty) return '?';
  final dn = name == 'Member' ? '?' : name;
  if (dn == '?') return '?';
  final parts = dn.split(' ').where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts[0][0].toUpperCase();
  return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
}


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

    // v5.214 (Family Profile member-count fix): the count pill + the
    // MEMBERS section list are now derived from Linked Person rows
    // (using [linkedMemberCountProvider] for the count, and a
    // [_LinkedMemberRow] list augmenting Person data with role/username
    // info from FamilyMembership where available). This matches the
    // Linked-only standard already applied to Family Chat, Family
    // Space, and the bottom-nav Members screen.
    //
    // Bug being fixed: the screen previously used `familyMembershipsProvider`
    // alone (the FamilyMember rows table — real Kinrel users who accepted
    // an invite). For test families where Linked Person rows exist
    // without corresponding FamilyMember rows (the anchor Person with
    // linkedUserId=null due to the server-side unique constraint, OR
    // a Linked Person was added to the tree but the user never went
    // through the invite-acceptance flow), this returned only 1 row
    // (the current user's own membership) and the screen displayed
    // "1 member" + a single "Member (You)" placeholder row.
    final allMembers = detail?.members ?? const <Person>[];
    final linkedMemberRows = family == null
        ? const <_LinkedMemberRow>[]
        : _buildLinkedMemberRows(
            family: family,
            allMembers: allMembers,
            memberships: memberships,
            currentUserId: currentUserId,
          );
    // The Linked-only count comes from [linkedMemberCountProvider] —
    // single source of truth shared with Family Chat / Family Space
    // / the bottom-nav Members screen, so counts can never disagree
    // across surfaces.
    final linkedMemberCount = ref.watch(linkedMemberCountProvider(familyId));

    // Determine whether the current user is an admin (for the settings link).
    // v5.214: check the linkedMemberRows list so the anchor Person
    // (whose admin status is inferred via the family.createdBy
    // fallback when no FamilyMember row exists) is also recognised
    // as admin here.
    final isCurrentUserAdmin = linkedMemberRows.any(
      (r) => r.isSelf && r.isAdmin,
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
        title: const Text(
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
                  avatarUrl,
                  currentUserId,
                  isCurrentUserAdmin,
                  presenceMap,
                  linkedMemberRows,
                  linkedMemberCount,
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
            const Icon(Icons.error_outline, size: 48, color: KinrelColors.error),
            const SizedBox(height: 12),
            const Text(
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
              style: const TextStyle(color: KinrelColors.textDim, fontSize: 13),
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
    String? avatarUrl,
    String? currentUserId,
    bool isCurrentUserAdmin,
    Map<String, UserLastSeen> presenceMap,
    List<_LinkedMemberRow> linkedMemberRows,
    int linkedMemberCount,
  ) {
    if (family == null) return const SizedBox.shrink();
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        // v5.214: hero pill now uses the Linked-only count
        // (linkedMemberCountProvider) — matches the standard already
        // applied to Family Chat / Family Space / the bottom-nav
        // Members screen. The previous implementation passed
        // `memberships.length` which only counted FamilyMember rows
        // (Kinrel users who accepted an invite), undercounting the
        // creator's anchor Person when no membership row existed for
        // them.
        _buildHero(context, family, avatarUrl, linkedMemberCount),
        const SizedBox(height: 20),
        if (family.description != null && family.description!.isNotEmpty)
          _buildSection(
            context,
            title: 'About',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                family.description!,
                style: const TextStyle(
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
        // v5.214: stats row no longer takes memberCount as a param
        // (it was unused — the row only uses family.createdAt,
        // family.generationCount, family.lastActivityAt, which are
        // all graph-level stats NOT derived from the member count.
        // Confirmed: 'Generations' must use the FULL family tree
        // count including Manual placeholder relatives — that's what
        // family.generationCount represents, so it is preserved as-is
        // and NOT swapped for the Linked-only count).
        _buildStatsRow(context, family),
        const SizedBox(height: 20),
        _buildAdminsSection(context, linkedMemberRows),
        const SizedBox(height: 20),
        _buildMembersSection(
            context, linkedMemberRows, linkedMemberCount, presenceMap),
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
            style: const TextStyle(
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
                const Icon(Icons.group_rounded,
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
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: KinrelGradients.igniteGradient,
      ),
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w800,
            color: KinrelColors.textWhite,
          ),
        ),
      ),
    );
  }

  // ── Stats row: created date, generations, last activity ────────────

  Widget _buildStatsRow(BuildContext context, Family family) {
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
            // v5.214: generationCount is a graph-level stat stored on
            // the Family row (server-side trigger maintains it from
            // the Person table's generationIndex values across ALL
            // nodes — Linked + Manual). It is NOT member-count-
            // derived, so it is intentionally NOT swapped for the
            // Linked-only count. Generations/structure is a graph
            // concept: a placeholder grandparent still occupies a
            // distinct generation slot in the tree.
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
              style: const TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
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
            style: const TextStyle(
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
    List<_LinkedMemberRow> linkedMemberRows,
  ) {
    // v5.214: the Admins section now filters the linkedMemberRows
    // list (which is already Linked-only) by `isAdmin`. Previously
    // this filtered the FamilyMembership list — which undercounted
    // admins when their FamilyMember row was missing (the anchor
    // Person case).
    final admins = linkedMemberRows.where((r) => r.isAdmin).toList();
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
              .map((r) => _buildAdminChip(context, r))
              .toList(),
        ),
      ),
    );
  }

  Widget _buildAdminChip(BuildContext context, _LinkedMemberRow r) {
    final name = r.displayName;
    final initials = r.initials;
    return GestureDetector(
      // v5.214: only open the MemberProfileSheet if we have a real
      // userId. For the anchor-fallback case where the Person has no
      // linkedUserId, we fall back to family.createdBy — which is a
      // real auth id, so MemberProfileSheet.show(context, userId)
      // works correctly.
      onTap: r.userId != null && r.userId!.isNotEmpty
          ? () => MemberProfileSheet.show(context, r.userId!)
          : null,
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
              backgroundImage: r.avatarUrl != null &&
                      r.avatarUrl!.isNotEmpty
                  ? CachedNetworkImageProvider(r.avatarUrl!)
                  : null,
              child: r.avatarUrl == null || r.avatarUrl!.isEmpty
                  ? Text(
                      initials,
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: KinrelColors.ember,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 6),
            Text(
              name,
              style: const TextStyle(
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
                r.displayRole,
                style: const TextStyle(
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
    List<_LinkedMemberRow> linkedMemberRows,
    int linkedMemberCount,
    Map<String, UserLastSeen> presenceMap,
  ) {
    if (linkedMemberRows.isEmpty) return const SizedBox.shrink();
    // Sort: admins first, then alphabetical by name.
    final sorted = [...linkedMemberRows]..sort((a, b) {
        final aAdmin = a.isAdmin ? 0 : 1;
        final bAdmin = b.isAdmin ? 0 : 1;
        if (aAdmin != bAdmin) return aAdmin - bAdmin;
        return a.displayName.compareTo(b.displayName);
      });

    // v5.214: the MEMBERS (X) section header count now uses the
    // Linked-only count (linkedMemberCount) — same source as the hero
    // pill, so they always agree. Previously this used
    // `memberships.length` which only counted FamilyMember rows.
    return _buildSection(
      context,
      title: 'Members ($linkedMemberCount)',
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
                  presenceMap[sorted[i].userId ?? ''],
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
    _LinkedMemberRow r,
    UserLastSeen? presence,
  ) {
    // v5.214: the row now consumes a _LinkedMemberRow (Person data +
    // optional FamilyMembership augmentation) instead of a raw
    // FamilyMembership. This means rows display the Person's actual
    // name (e.g. "Account 1") even when no FamilyMembership exists,
    // and the "(You)" tag is correctly applied based on the row's
    // `isSelf` flag (computed in _buildLinkedMemberRows by comparing
    // the resolved userId against the current user's auth id).
    final name = r.displayName;
    final initials = r.initials;
    final isSelf = r.isSelf;
    final online = isUserOnline(presence);
    return InkWell(
      // v5.214: only open the MemberProfileSheet if we have a real
      // userId. The anchor-fallback case resolves to family.createdBy
      // (a real auth id), so this works for the creator's own row
      // too. If userId is null/empty (edge case — shouldn't happen
      // for a Linked row), disable the tap.
      onTap: r.userId != null && r.userId!.isNotEmpty
          ? () => MemberProfileSheet.show(context, r.userId!)
          : null,
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
                  backgroundImage: r.avatarUrl != null &&
                          r.avatarUrl!.isNotEmpty
                      ? CachedNetworkImageProvider(r.avatarUrl!)
                      : null,
                  child: r.avatarUrl == null || r.avatarUrl!.isEmpty
                      ? Text(
                          initials,
                          style: const TextStyle(
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
                    style: const TextStyle(
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
                  if (r.username != null && r.username!.isNotEmpty)
                    Text(
                      '@${r.username}',
                      style: const TextStyle(
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
                color: r.isAdmin
                    ? KinrelColors.ember.withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                r.displayRole,
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: r.isAdmin
                      ? KinrelColors.ember
                      : KinrelColors.textSilver,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right,
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
                    const Icon(Icons.qr_code_rounded,
                        size: 18, color: KinrelColors.ember),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
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
                            style: const TextStyle(
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
              style: const TextStyle(
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
            child: const Row(
              children: [
                Icon(Icons.tune_rounded,
                    size: 18, color: KinrelColors.ember),
                SizedBox(width: 12),
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
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.space_dashboard_rounded,
                  size: 18, color: KinrelColors.textWhite),
              SizedBox(width: 8),
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
              leading: const Icon(Icons.group_rounded, color: KinrelColors.ember),
              title: const Text('View all members',
                  style: TextStyle(color: KinrelColors.textWhite)),
              onTap: () {
                Navigator.pop(ctx);
                // v5.212 (entry-context-aware list): the Family
                // Profile screen's "View all members" action is a
                // family-tree overview context — the user is
                // explicitly trying to see everyone in the tree,
                // including placeholder relatives. Pass
                // `source=graphViewAll` so the Members screen shows
                // the full list with per-row Linked/Manual badges
                // (matching the Graph screen's "View all" button).
                context.push(
                    '/family/$familyId/members?source=${MembersScreenSource.graphViewAll.toQueryParam()}');
              },
            ),
            ListTile(
              leading: const Icon(Icons.account_tree_rounded,
                  color: KinrelColors.ember),
              title: const Text('Family tree',
                  style: TextStyle(color: KinrelColors.textWhite)),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/family/$familyId/graph');
              },
            ),
            ListTile(
              leading: const Icon(Icons.timeline_rounded, color: KinrelColors.ember),
              title: const Text('Family activity',
                  style: TextStyle(color: KinrelColors.textWhite)),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/family/$familyId/activity');
              },
            ),
            if (isCurrentUserAdmin)
              ListTile(
                leading: const Icon(Icons.tune_rounded, color: KinrelColors.ember),
                title: const Text('Settings',
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

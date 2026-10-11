// lib/features/family/presentation/family_chat_list_screen.dart
//
// DAXELO KINREL — Family Chat List Screen (v140 — Family-Centric Redesign)
//
// The Chat tab destination inside Family Space. Implements the
// family-centric chat navigation spec:
//
//   • Top navigation is exactly two tabs: [ Family ] [ Direct ]
//   • Default selected tab is Family.
//   • Family tab: opens the family group conversation INLINE — there
//     is no list of groups, no global chats, no chats from other
//     families. The header shows the current family name + member
//     count.
//   • Direct tab: shows ONLY members of the currently-selected family.
//     Existing 1:1 conversations appear first (Recent Conversations,
//     ordered by latest activity), then members without a conversation
//     appear in an "Available Family Members" section. Tapping an
//     available member opens (and effectively creates) the DM thread.
//   • Family isolation: every query / socket / unread-count / typing
//     indicator is scoped to the active family. Switching families
//     re-runs every provider against the new familyId.
//
// Route: /family/:id/chats  (plural — distinguishes from /family/:id/chat
// which is the standalone full-screen group conversation pushed from
// other entry points like notifications).

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/family/family_provider.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../chat/data/direct_group_service.dart';
import '../../chat/presentation/chat_screen.dart';
import 'family_space_floating_nav.dart';

/// Top-level filter tab for the family-centric chat navigation.
///
/// v140 redesign: the previous All/Family/Direct enum is replaced with
/// exactly two buckets. The default is [family] so that tapping the
/// Family Chat dock entry lands directly in the family group chat.
enum _ChatFilter { family, direct }

class FamilyChatListScreen extends ConsumerStatefulWidget {
  const FamilyChatListScreen({super.key, required this.familyId});

  final String familyId;

  @override
  ConsumerState<FamilyChatListScreen> createState() =>
      _FamilyChatListScreenState();
}

class _FamilyChatListScreenState extends ConsumerState<FamilyChatListScreen> {
  // Default to Family — the spec mandates "Open directly into the
  // current family's communication area. The default selected tab
  // should be Family."
  _ChatFilter _filter = _ChatFilter.family;

  @override
  Widget build(BuildContext context) {
    final familyAsync = ref.watch(familyDetailProvider(widget.familyId));
    final familyName =
        familyAsync.valueOrNull?.family.name ?? 'Family';
    final familyAvatarUrl = familyAsync.valueOrNull?.family.avatarUrl;
    // v5.211 (member-count de-conflation): the family-chat-list header
    // used to show `family.memberCount` — a BLENDED count of every
    // Person row (Linked Kinrel accounts + Manual placeholder
    // relatives). That was misleading: this header sits ABOVE the chat
    // tab, and "N members" in a chat context implies N real people who
    // could chat — not N family-tree nodes. Placeholder relatives
    // cannot send or receive messages.
    //
    // Now reads [linkedMemberCountProvider] which counts only real,
    // active Kinrel accounts (Linked status).
    final memberCount =
        ref.watch(linkedMemberCountProvider(widget.familyId));

    return DKScaffold(
      backgroundColor: const Color(0xFF0A0B16),
      // The header adapts to the active tab so we never show a
      // redundant "Chats" title above the group chat, and the Direct
      // tab gets its own "Direct Messages" title.
      appBar: _buildHeader(
        familyName: familyName,
        familyAvatarUrl: familyAvatarUrl,
        memberCount: memberCount,
      ),
      bottomNavigationBar:
          FamilySpaceFloatingNav(familyId: widget.familyId),
      body: IndexedStack(
        // IndexedStack keeps both tab bodies mounted so ChatScreen's
        // provider state (messages, scroll position, realtime channel)
        // survives a tab switch — no re-fetch flicker when the user
        // toggles Family ⇄ Direct.
        index: _filter == _ChatFilter.family ? 0 : 1,
        children: [
          // ── Tab 0: Family ───────────────────────────────────────
          // Embedded inline. hideAppBar=true so we don't get a double
          // AppBar (parent provides the family-name header above).
          // showFamilyNav=false because the parent already renders the
          // FamilySpaceFloatingNav at the bottom.
          ChatScreen(
            key: const ValueKey('family_chat_inline'),
            familyId: widget.familyId,
            familyName: familyName,
            showFamilyNav: false,
            hideAppBar: true,
          ),
          // ── Tab 1: Direct ───────────────────────────────────────
          _DirectTab(familyId: widget.familyId),
        ],
      ),
    );
  }

  /// Builds the adaptive header. The [Family] [Direct] tab switcher
  /// always sits in the AppBar's `bottom` slot so it's pinned at the
  /// top of the screen. The title row above changes per-tab:
  ///   • Family tab → family avatar + name + "N members" subtitle
  ///   • Direct tab → "Direct Messages" title + family context chip
  PreferredSizeWidget _buildHeader({
    required String familyName,
    required String? familyAvatarUrl,
    required int memberCount,
  }) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/family/${widget.familyId}');
          }
        },
      ),
      // Title row adapts to the active tab.
      title: _filter == _ChatFilter.family
          ? Row(
              children: [
                _FamilyAvatar(
                  familyName: familyName,
                  avatarUrl: familyAvatarUrl,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        familyName,
                        style: const TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: KinrelColors.textWhite,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        memberCount > 0
                            ? '$memberCount ${memberCount == 1 ? 'member' : 'members'}'
                            : 'Family',
                        style: const TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 12,
                          color: KinrelColors.textSilver,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : const Text(
              'Direct Messages',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontWeight: FontWeight.w700,
              ),
            ),
      backgroundColor: const Color(0xFF11132A),
      foregroundColor: KinrelColors.textWhite,
      elevation: 0,
      // The tab switcher lives in the AppBar's bottom slot so it stays
      // pinned regardless of which tab body is currently visible.
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: _buildFilterTabs(),
      ),
    );
  }

  /// Builds the [ Family ] [ Direct ] tab switcher row.
  Widget _buildFilterTabs() {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.base,
        vertical: 6,
      ),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.button),
      ),
      child: Row(
        children: [
          _filterTab('Family', _ChatFilter.family),
          _filterTab('Direct', _ChatFilter.direct),
        ],
      ),
    );
  }

  Widget _filterTab(String label, _ChatFilter filter) {
    final isSelected = _filter == filter;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _filter = filter),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: isSelected
                ? KinrelColors.orange
                : Colors.transparent,
            borderRadius:
                BorderRadius.circular(KinrelRadius.button - 4),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? Colors.white : KinrelColors.textSilver,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Family Avatar (header)
// ═══════════════════════════════════════════════════════════════════════

class _FamilyAvatar extends StatelessWidget {
  const _FamilyAvatar({required this.familyName, this.avatarUrl});

  final String familyName;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final initial = familyName.isNotEmpty ? familyName[0].toUpperCase() : 'F';
    return CircleAvatar(
      radius: 18,
      backgroundColor: KinrelColors.orange.withValues(alpha: 0.15),
      backgroundImage: avatarUrl != null && avatarUrl!.isNotEmpty
          ? CachedNetworkImageProvider(avatarUrl!)
          : null,
      child: avatarUrl == null || avatarUrl!.isEmpty
          ? Text(
              initial,
              style: const TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: KinrelColors.orange,
              ),
            )
          : null,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Direct Tab
// ═══════════════════════════════════════════════════════════════════════

/// The Direct tab body. Shows ONLY members of the currently-selected
/// family, split into "Recent Conversations" and "Available Family
/// Members" sections.
///
/// Family isolation is enforced by [familyDmPartnersProvider] which
/// filters the global DM inbox through the family roster. Switching
/// the familyId parameter re-runs the provider against the new
/// family — no leakage.
class _DirectTab extends ConsumerWidget {
  const _DirectTab({required this.familyId});

  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partnersAsync = ref.watch(familyDmPartnersProvider(familyId));

    return partnersAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: KinrelColors.orange),
      ),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                size: 40,
                color: KinrelColors.textDim,
              ),
              const SizedBox(height: 12),
              const Text(
                'Could not load family members',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  color: KinrelColors.textDim,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Pull down to retry.',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  color: KinrelColors.textSilver.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
      data: (result) {
        final recent = result.recent;
        final available = result.available;

        // Both empty — show a friendly empty state. The spec is
        // explicit: an empty Direct screen feels broken in small
        // family groups. If the roster hasn't loaded yet (still
        // loading), show the spinner instead (handled above).
        if (recent.isEmpty && available.isEmpty) {
          return _buildEmptyDirect();
        }

        final rows = <Widget>[];

        // ── Recent Conversations ───────────────────────────────
        if (recent.isNotEmpty) {
          rows.add(_SectionHeader(
            title: 'Recent Conversations',
            count: recent.length,
          ));
          for (final partner in recent) {
            rows.add(_DmRow(
              partner: partner,
              onTap: () => openDirectChat(
                context,
                otherUserId: partner.userId,
                familyId: familyId,
              ),
            ));
          }
        }

        // ── Available Family Members ────────────────────────────
        if (available.isNotEmpty) {
          rows.add(_SectionHeader(
            title: 'Available Family Members',
            count: available.length,
          ));
          for (final partner in available) {
            rows.add(_AvailableMemberRow(
              partner: partner,
              onTap: () => openDirectChat(
                context,
                otherUserId: partner.userId,
                familyId: familyId,
              ),
            ));
          }
        }

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 120, top: 4),
          itemCount: rows.length,
          itemBuilder: (context, index) => rows[index],
        );
      },
    );
  }

  Widget _buildEmptyDirect() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.people_outline_rounded,
              size: 56,
              color: KinrelColors.orange.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            const Text(
              'No family members available to message yet',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: KinrelColors.textDim,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Once family members link their Kinrel accounts, '
              'they will appear here.',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: KinrelColors.textSilver.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Section Header
// ═══════════════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KinrelSpacing.base,
        16,
        KinrelSpacing.base,
        6,
      ),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: KinrelColors.orange,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: KinrelColors.orange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: KinrelColors.orange,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// DM Row (existing conversation)
// ═══════════════════════════════════════════════════════════════════════

class _DmRow extends StatelessWidget {
  const _DmRow({required this.partner, required this.onTap});

  final FamilyDmPartner partner;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasUnread = partner.unreadCount > 0;
    final lastTime = partner.lastMessageTime;

    return ListTile(
      onTap: onTap,
      leading: _PartnerAvatar(partner: partner),
      title: Row(
        children: [
          Expanded(
            child: Text(
              partner.displayName,
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 16,
                fontWeight:
                    hasUnread ? FontWeight.w700 : FontWeight.w600,
                color: KinrelColors.textWhite,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (lastTime != null)
            Text(
              _formatTime(lastTime),
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: hasUnread
                    ? KinrelColors.orange
                    : KinrelColors.textDim,
                fontWeight:
                    hasUnread ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
        ],
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: Text(
              partner.lastMessage,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                color: hasUnread
                    ? KinrelColors.textSilver
                    : KinrelColors.textDim,
                fontWeight:
                    hasUnread ? FontWeight.w500 : FontWeight.w400,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (hasUnread)
            DKBadge(count: partner.unreadCount, color: KinrelColors.orange),
        ],
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.base,
        vertical: 4,
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) {
      final hour = dt.hour;
      final minute = dt.minute.toString().padLeft(2, '0');
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      return '$displayHour:$minute $period';
    }
    if (diff.inDays < 2) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${dt.month}/${dt.day}';
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Available Member Row (no conversation yet)
// ═══════════════════════════════════════════════════════════════════════

class _AvailableMemberRow extends StatelessWidget {
  const _AvailableMemberRow({required this.partner, required this.onTap});

  final FamilyDmPartner partner;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: _PartnerAvatar(partner: partner),
      title: Text(
        partner.displayName,
        style: const TextStyle(
          fontFamily: KinrelTypography.displayFont,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: KinrelColors.textWhite,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: const Text(
        'Tap to start a conversation',
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 12,
          color: KinrelColors.textSilver,
          fontStyle: FontStyle.italic,
        ),
      ),
      trailing: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: KinrelColors.orange.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.chat_bubble_outline_rounded,
          size: 16,
          color: KinrelColors.orange,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.base,
        vertical: 4,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Partner Avatar
// ═══════════════════════════════════════════════════════════════════════

class _PartnerAvatar extends StatelessWidget {
  const _PartnerAvatar({required this.partner});

  final FamilyDmPartner partner;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 26,
      backgroundColor: KinrelColors.orange.withValues(alpha: 0.15),
      backgroundImage: partner.avatarUrl != null &&
              partner.avatarUrl!.isNotEmpty
          ? CachedNetworkImageProvider(partner.avatarUrl!)
          : null,
      child: partner.avatarUrl == null || partner.avatarUrl!.isEmpty
          ? Text(
              partner.initials,
              style: const TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: KinrelColors.orange,
              ),
            )
          : null,
    );
  }
}

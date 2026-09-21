// lib/features/games/shared/widgets/pending_invites_section.dart
//
// Drop-in section for the lobby's player-list area. Renders every member
// the host has invited to this game room (via InviteFamilySheet) with
// their current InviteMemberStatus as a small badge. Hidden automatically
// when there are no invites.
//
// Usage in any lobby:
//   PendingInvitesSection(gameId: state.game!.id)
//
// In the shared TemporaryLobbyView the section is mounted INSIDE the
// pinned Family Members card in `compact` mode: a single bounded
// summary row ("2 pending · 1 accepted") with no outer margin — the
// full per-member list lives in the invite sheet, one tap above. This
// keeps the pinned invite section a stable, predictable height (the
// roster is the lobby's only scrollable surface).
//
// The section watches gameInviteStatusProvider(gameId) so it updates in
// real-time when recipients tap Accept / Decline in their dialog.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_spacing.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/services/image_cache_manager.dart';
import '../models/game_invite_status.dart';
import '../providers/game_invite_status_provider.dart';
import 'invite_status_badge.dart';

class PendingInvitesSection extends ConsumerWidget {
  const PendingInvitesSection({
    super.key,
    required this.gameId,
    this.compact = false,
  });

  final String gameId;

  /// Bounded-height mode for the lobby's pinned Family Members card:
  /// renders only the one-line summary ("N pending · M accepted") with
  /// no outer margin and no per-member rows — the invite sheet (opened
  /// by the sticky Invite Family Members button right above) shows the
  /// full list with live statuses. Default (false) renders the full
  /// list — used inside scrollable lobby bodies.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameInviteStatusProvider(gameId));
    if (state.isEmpty) return const SizedBox.shrink();

    // Order: pending first, then accepted, then declined, then expired.
    final records = state.invites.values.toList()
      ..sort((a, b) {
        final order = {
          InviteMemberStatus.pending: 0,
          InviteMemberStatus.accepted: 1,
          InviteMemberStatus.declined: 2,
          InviteMemberStatus.expired: 3,
        };
        return order[a.status]!.compareTo(order[b.status]!);
      });

    final pending = state.countByStatus(InviteMemberStatus.pending);
    final accepted = state.countByStatus(InviteMemberStatus.accepted);
    final declined = state.countByStatus(InviteMemberStatus.declined);
    final expired = state.countByStatus(InviteMemberStatus.expired);

    return Container(
      margin: compact
          ? EdgeInsets.zero
          : const EdgeInsets.only(top: KinrelSpacing.lg),
      padding: const EdgeInsets.all(KinrelSpacing.md),
      decoration: BoxDecoration(
        color: KinrelColors.darkSurface,
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(color: KinrelColors.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.mail_outline,
                  color: KinrelColors.orange, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Invites sent',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                  ),
                ),
              ),
              Text(
                '$pending pending · $accepted accepted'
                '${declined > 0 ? ' · $declined declined' : ''}'
                '${expired > 0 ? ' · $expired expired' : ''}',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 10,
                  color: KinrelColors.textDim,
                ),
              ),
            ],
          ),
          // Compact mode stops at the bounded summary row above — the
          // full per-member list (with live status badges) lives in
          // the invite sheet, opened by the sticky Invite Family
          // Members button directly above this section.
          if (!compact) ...[
            const SizedBox(height: KinrelSpacing.sm),
            ...records.map(_recordRow),
          ],
        ],
      ),
    );
  }

  Widget _recordRow(InviteRecord r) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          _buildAvatar(r),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.textWhite,
                  ),
                ),
                if (r.username != null && r.username!.isNotEmpty)
                  Text(
                    '@${r.username}',
                    style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 10,
                      color: KinrelColors.textDim,
                    ),
                  ),
              ],
            ),
          ),
          InviteStatusBadge(status: r.status),
        ],
      ),
    );
  }

  Widget _buildAvatar(InviteRecord r) {
    final photo = r.photoThumb ?? r.avatarUrl;
    if (photo != null && photo.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: photo,
          cacheManager: KinrelImageCacheManager.instance,
          width: 28,
          height: 28,
          fit: BoxFit.cover,
          // memCacheWidth/Height omitted: this helper method has no
          // BuildContext in scope (ConsumerWidget helper, not the build
          // method). The avatar is 28×28 logical px which is small
          // enough that not capping decode size is acceptable.
          errorWidget: (_, __, ___) => _initials(r),
        ),
      );
    }
    return _initials(r);
  }

  Widget _initials(InviteRecord r) {
    final parts = r.name.trim().split(RegExp(r'\s+'));
    final init = parts.isEmpty || parts.first.isEmpty
        ? '?'
        : parts.length == 1
            ? parts.first[0].toUpperCase()
            : (parts.first[0] + parts[1][0]).toUpperCase();
    return Container(
      width: 28, height: 28,
      decoration: BoxDecoration(
        color: KinrelColors.orange.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          init,
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: KinrelColors.orange,
          ),
        ),
      ),
    );
  }
}

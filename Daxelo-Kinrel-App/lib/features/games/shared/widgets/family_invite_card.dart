// lib/features/games/shared/widgets/family_invite_card.dart
//
// FamilyInviteCard — the FIXED "Family Members / Invite Family" section
// rendered directly below the player list in every game lobby.
//
// Per the lobby UX spec:
//   • The card is always visible WITHOUT scrolling (pinned below the
//     scrollable Players roster — see TemporaryLobbyView).
//   • One-tap invitations: each member row has an inline Invite button —
//     no extra screen to open.
//   • "View All" opens the full InviteFamilySheet for multi-select and
//     "Entire Family" invites.
//   • Live statuses (Pending / Accepted / …) come from the shared
//     gameInviteStatusProvider; online dots from lastSeenProvider.
//
// The invite delivery pipeline is identical to InviteFamilySheet's
// single-tap path: durable game_invites row (FCM push trigger) →
// Socket.IO realtime event → private game-invite DM (never the family
// group chat).

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_spacing.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/network/socket_service.dart';
import '../../../../core/services/image_cache_manager.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../chat/data/direct_message_provider.dart';
import '../../../presence/last_seen_provider.dart';
import '../icons/kinrel_icons.dart';
import '../models/game_invite.dart';
import '../models/game_invite_status.dart';
import '../providers/family_invite_members_provider.dart';
import '../providers/game_invite_status_provider.dart';
import 'invite_family_sheet.dart';

/// How many member rows are visible inline. Keeps the pinned section
/// compact on one-handed mobile screens; the full list is one tap away.
const int kFamilyInviteCardRows = 2;

/// Reverse map: game table name → GameType (for building invite payloads
/// from a TemporaryLobbyConfig, which only carries the table name).
GameType? gameTypeForTable(String table) {
  switch (table) {
    case 'bingo_games':
      return GameType.bingo;
    case 'ludo_games':
      return GameType.ludo;
    case 'checkers_games':
      return GameType.checkers;
    case 'carrom_games':
      return GameType.carrom;
    case 'chess_games':
      return GameType.chess;
    case 'chitmatch_games':
      return GameType.chitmatch;
    case 'nameplace_games':
      return GameType.nameplace;
    case 'tictactoe_games':
      return GameType.tictactoe;
    case 'truthordare_games':
      return GameType.truthordare;
    case 'twotruths_games':
      return GameType.twotruths;
    case 'dotsboxes_games':
      return GameType.dotsboxes;
    case 'sos_games':
      return GameType.sos;
    case 'antakshari_games':
      return GameType.antakshari;
    case 'redlight_rounds':
      return GameType.redlight;
    case 'tugofwar_games':
      return GameType.tugOfWar;
    case 'memorymatch_games':
      return GameType.memoryMatch;
    // ── QA fix 2026-09-21: the 12 newer game tables were missing from
    // this mapping, so their one-tap lobby invites silently no-oped
    // (gameTypeForTable returned null before any insert ran).
    case 'ashta_chamma_games':
      return GameType.ashtaChamma;
    case 'connect4_games':
      return GameType.connect4;
    case 'impostor_games':
      return GameType.impostor;
    case 'color_trap_games':
      return GameType.colorTrap;
    case 'freeze_auction_games':
      return GameType.freezeAuction;
    case 'flick_arena_games':
      return GameType.flickArena;
    case 'secret_heist_games':
      return GameType.secretHeist;
    case 'mind_match_games':
      return GameType.mindMatch;
    case 'word_forge_games':
      return GameType.wordForge;
    case 'code_clues_games':
      return GameType.codeClues;
    case 'night_falls_games':
      return GameType.nightFalls;
    case 'sketch_telephone_games':
      return GameType.sketchTelephone;
    // ── QA fix 2026-09-19: the two newest games (Stickman Heist in
    // a445ed23, Crystal Bridge in b743a8d7) were added to the FORWARD
    // map (invite_family_sheet.dart gameTableFor) but NOT here — the
    // per-member one-tap lobby invite silently no-oped for both
    // (gameTypeForTable returned null before any insert ran, and the
    // button gave no feedback). Same failure class as the 12 missing
    // tables fixed earlier above.
    case 'stickman_heist_games':
      return GameType.stickmanHeist;
    case 'crystal_bridge_games':
      return GameType.crystalBridge;
    // ── QA fix 2026-09-20: Ghost Painter was the one catalog game with
    // no GameType member at all, so it could not be wired into any
    // invite surface (gameTypeForTable returned null before any insert
    // ran — same silent no-op class as the fixes above). The member,
    // its routeSegment ('ghost-painter') and this mapping are now all
    // registered together; the contract test in
    // test/features/games/game_registration_contract_test.dart guards
    // against the next game shipping unwired.
    case 'ghost_painter_rounds':
      return GameType.ghostPainter;
    default:
      return null;
  }
}

class FamilyInviteCard extends ConsumerStatefulWidget {
  const FamilyInviteCard({
    super.key,
    required this.familyId,
    required this.gameTable,
    required this.gameId,
    required this.roomCode,
    required this.currentPlayerIds,
    required this.maxPlayers,
    required this.currentPlayers,
    this.canInvite = true,
    this.onInviteSent,
  });

  final String familyId;

  /// e.g. 'tugofwar_games' — mapped back to a GameType for invites.
  final String gameTable;

  final String gameId;
  final String roomCode;
  final Set<String> currentPlayerIds;
  final int maxPlayers;
  final int currentPlayers;

  /// Only the HOST can send invites (matches the room-owner model of
  /// every other invite surface). Non-hosts still see the member list
  /// and live statuses — read-only.
  final bool canInvite;

  final VoidCallback? onInviteSent;

  @override
  ConsumerState<FamilyInviteCard> createState() => _FamilyInviteCardState();
}

class _FamilyInviteCardState extends ConsumerState<FamilyInviteCard> {
  /// User IDs with an invite in flight (spinner on the button).
  final Set<String> _sendingTo = {};

  bool get _isRoomFull => widget.currentPlayers >= widget.maxPlayers;

  /// Members not already in the room, online-first.
  List<FamilyInviteMember> _invitable(FamilyInviteMembersState state) {
    final presenceMap = ref.watch(lastSeenProvider);
    final members = state.members
        .where((m) => !widget.currentPlayerIds.contains(m.user.id))
        .map((m) {
      final live = presenceMap[m.user.id];
      if (live == null) return m;
      return m.copyWith(isOnline: live.isOnline, lastSeenAt: live.lastSeenAt);
    }).toList()
      ..sort((a, b) {
        final aOnline = (a.isOnline ?? false) ? 1 : 0;
        final bOnline = (b.isOnline ?? false) ? 1 : 0;
        if (aOnline != bOnline) return bOnline - aOnline;
        return a.user.name.compareTo(b.user.name);
      });
    return members;
  }

  /// One-tap invite — same delivery pipeline as InviteFamilySheet's
  /// single-tap path (durable row + socket event + private DM).
  Future<void> _sendInvite(FamilyInviteMember m) async {
    if (!widget.canInvite) return;
    if (_sendingTo.contains(m.user.id) || _isRoomFull) return;
    if (widget.currentPlayerIds.contains(m.user.id)) return;
    final gameType = gameTypeForTable(widget.gameTable);
    if (gameType == null) return;

    setState(() => _sendingTo.add(m.user.id));

    // Capture everything BEFORE any await — never touch ref/mounted
    // state after an await without re-checking.
    final socket = ref.read(socketServiceProvider);
    final client = ref.read(supabaseProvider);
    final myId = client?.auth.currentUser?.id ?? '';
    final myName =
        (client?.auth.currentUser?.userMetadata?['name'] as String?) ??
            client?.auth.currentUser?.email ??
            'A family member';
    final invite = GameInvite(
      inviteId:
          'inv_${DateTime.now().millisecondsSinceEpoch}_${m.user.id.substring(0, 8)}',
      gameType: gameType,
      gameId: widget.gameId,
      roomCode: widget.roomCode,
      familyId: widget.familyId,
      fromUserId: myId,
      fromName: myName,
      maxPlayers: widget.maxPlayers,
      currentPlayers: widget.currentPlayers,
      message: '$myName invited you to join ${gameType.displayName}',
      timestamp: DateTime.now().toUtc(),
    );

    // 1. Durable invite row — the source of truth. Triggers the FCM
    //    push and lets the recipient's DB-realtime leg surface the
    //    Accept/Decline dialog even when the socket is down.
    bool rowInserted = false;
    try {
      if (client != null) {
        await client.from('game_invites').insert({
          'gameTable': widget.gameTable,
          'gameId': widget.gameId,
          'gameType': gameType.routeSegment,
          'familyId': widget.familyId,
          'roomCode': widget.roomCode,
          'invitedUserId': m.user.id,
          'invitedByUserId': myId,
          'invitedByName': myName,
          'maxPlayers': widget.maxPlayers,
          'currentPlayers': widget.currentPlayers,
          'message': invite.message,
          'status': 'pending',
          'sourceGameId': null,
        });
        rowInserted = true;
      }
    } catch (e) {
      if (mounted) {
        setState(() => _sendingTo.remove(m.user.id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Couldn\'t send invite to ${m.user.name}'),
            backgroundColor: KinrelColors.error,
          ),
        );
      }
      return;
    }

    // 2. The status chip reflects the DURABLE row — set before the
    //    best-effort legs so a socket hiccup never hides the feedback.
    ref.read(gameInviteStatusProvider(widget.gameId).notifier).markPending(
          userId: m.user.id,
          name: m.user.name,
          username: m.user.username,
          avatarUrl: m.user.avatarUrl,
          photoThumb: m.user.photoThumb,
        );
    widget.onInviteSent?.call();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invite sent to ${m.user.name}'),
          duration: const Duration(seconds: 2),
          backgroundColor: KinrelColors.darkElevated,
        ),
      );
    }

    // 3. Socket.IO realtime event — best-effort acceleration.
    try {
      await socket.sendGameInvite(toUserId: m.user.id, invite: invite);
    } catch (_) {
      // The durable row already guarantees delivery.
    }

    // 4. Private invite DM — best-effort, tied to the durable row.
    if (mounted) setState(() => _sendingTo.remove(m.user.id));
    if (rowInserted && client != null) {
      try {
        await sendGameInviteDm(
          client: client,
          toUserId: m.user.id,
          inviteJson: invite.toJson(),
        );
      } catch (_) {
        // Never blocks the invite itself.
      }
    }
  }

  void _openFullSheet() {
    if (!widget.canInvite) return;
    final gameType = gameTypeForTable(widget.gameTable);
    if (gameType == null) return;
    InviteFamilySheet.show(
      context,
      familyId: widget.familyId,
      gameType: gameType,
      gameId: widget.gameId,
      roomCode: widget.roomCode,
      currentPlayerIds: widget.currentPlayerIds,
      maxPlayers: widget.maxPlayers,
      currentPlayers: widget.currentPlayers,
    );
  }

  @override
  Widget build(BuildContext context) {
    final memberState =
        ref.watch(familyInviteMembersProvider(widget.familyId));
    final inviteState = ref.watch(gameInviteStatusProvider(widget.gameId));
    final invitable = _invitable(memberState);

    return Container(
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(color: KinrelColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header: FAMILY MEMBERS (N available) + View All ──────
          InkWell(
            onTap: _openFullSheet,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(KinrelRadius.lg)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  KinrelSpacing.md, 10, KinrelSpacing.sm, 10),
              child: Row(
                children: [
                  const KinrelIcon(KinrelIconData.users,
                      size: 15, color: KinrelColors.orange),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      invitable.isEmpty
                          ? 'Family Members'
                          : 'Family Members · ${invitable.length} available',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.textDim,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Text(
                    'View All',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: KinrelColors.orange,
                    ),
                  ),
                  const Icon(Icons.chevron_right,
                      size: 16, color: KinrelColors.orange),
                ],
              ),
            ),
          ),
          // ── Body ─────────────────────────────────────────────────
          if (memberState.loading && invitable.isEmpty)
            const Padding(
              padding: EdgeInsets.all(14),
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: KinrelColors.orange),
                ),
              ),
            )
          else if (_isRoomFull)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  KinrelSpacing.md, 4, KinrelSpacing.md, 12),
              child: Row(
                children: [
                  const KinrelIcon(KinrelIconData.checkCircle,
                      size: 14, color: KinrelColors.success),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Room is full — everyone who can join is here.',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 11.5,
                        color: KinrelColors.textDim,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else if (invitable.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  KinrelSpacing.md, 4, KinrelSpacing.md, 12),
              child: Row(
                children: [
                  const KinrelIcon(KinrelIconData.seedling,
                      size: 14, color: KinrelColors.tealAccent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      memberState.stats.membershipCount > 1
                          ? 'Everyone in your family is already in this room.'
                          : 'Invite relatives to Kinrel, then bring them into the game.',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 11.5,
                        color: KinrelColors.textDim,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            for (int i = 0;
                i < invitable.length && i < kFamilyInviteCardRows;
                i++) ...[
              if (i > 0)
                Divider(
                    height: 1,
                    color: KinrelColors.border.withValues(alpha: 0.5)),
              _MemberRow(
                member: invitable[i],
                status: inviteState[invitable[i].user.id]?.status,
                sending: _sendingTo.contains(invitable[i].user.id),
                disabled: _isRoomFull || !widget.canInvite,
                onInvite: () => _sendInvite(invitable[i]),
              ),
            ],
            // ── QA fix 2026-09-21: only show the "+N more" row when there
            // actually ARE hidden members. With fewer invitable members
            // than the preview row count (kFamilyInviteCardRows), the old
            // code rendered "-1 more members to invite".
            if (invitable.length > kFamilyInviteCardRows) ...[
              Divider(
                  height: 1, color: KinrelColors.border.withValues(alpha: 0.5)),
            // "+N more" row → full sheet.
            InkWell(
              onTap: widget.canInvite ? _openFullSheet : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: KinrelSpacing.md, vertical: 9),
                child: Row(
                  children: [
                    Icon(Icons.more_horiz,
                        size: 16, color: KinrelColors.textDim),
                    const SizedBox(width: 6),
                    Text(
                      '${invitable.length - kFamilyInviteCardRows} more '
                      'member${invitable.length - kFamilyInviteCardRows == 1 ? '' : 's'} to invite',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 11.5,
                        color: KinrelColors.textDim,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'See all',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: widget.canInvite
                            ? KinrelColors.orange
                            : KinrelColors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ], // end "+N more" row (only when there are hidden members)
          ],
        ],
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.status,
    required this.sending,
    required this.disabled,
    required this.onInvite,
  });

  final FamilyInviteMember member;
  final InviteMemberStatus? status;
  final bool sending;
  final bool disabled;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    final isOnline = member.isOnline ?? false;
    final photo = member.user.photoThumb ?? member.user.avatarUrl;

    Widget trailing;
    if (sending) {
      trailing = const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
            strokeWidth: 2, color: KinrelColors.orange),
      );
    } else if (status == InviteMemberStatus.pending) {
      trailing = _statusChip('Pending', KinrelColors.warning);
    } else if (status == InviteMemberStatus.accepted) {
      trailing = _statusChip('Joining', KinrelColors.success);
    } else if (status == InviteMemberStatus.declined) {
      trailing = _statusChip('Declined', KinrelColors.textDim);
    } else {
      trailing = _inviteButton(disabled);
    }

    return InkWell(
      onTap: (sending || status == InviteMemberStatus.pending || disabled)
          ? null
          : onInvite,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: KinrelSpacing.md, vertical: 8),
        child: Row(
          children: [
            // Avatar + online dot.
            SizedBox(
              width: 34,
              height: 34,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: KinrelColors.darkElevated,
                      border:
                          Border.all(color: KinrelColors.border, width: 1),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: (photo != null && photo.isNotEmpty)
                        ? CachedNetworkImage(
                            imageUrl: photo,
                            cacheManager: KinrelImageCacheManager.instance,
                            fit: BoxFit.cover,
                            memCacheWidth: (34 *
                                    MediaQuery.of(context).devicePixelRatio)
                                .toInt(),
                            memCacheHeight: (34 *
                                    MediaQuery.of(context).devicePixelRatio)
                                .toInt(),
                            errorWidget: (_, __, ___) => _initials(),
                          )
                        : _initials(),
                  ),
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: isOnline
                            ? const Color(0xFF22C55E)
                            : KinrelColors.darkElevated,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: KinrelColors.darkCard,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.user.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                  if (member.user.username?.isNotEmpty == true)
                    Text(
                      '@${member.user.username}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 10,
                        color: KinrelColors.orange,
                      ),
                    )
                  else
                    Text(
                      isOnline ? 'online' : 'offline',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 10,
                        color: isOnline
                            ? const Color(0xFF22C55E)
                            : KinrelColors.textDim,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing,
          ],
        ),
      ),
    );
  }

  Widget _initials() {
    return Center(
      child: Text(
        member.user.initials,
        style: TextStyle(
          fontFamily: KinrelTypography.displayFont,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: KinrelColors.orange,
        ),
      ),
    );
  }

  Widget _inviteButton(bool disabled) {
    return GestureDetector(
      onTap: disabled ? null : onInvite,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          gradient: disabled ? null : KinrelGradients.igniteGradient,
          color: disabled ? KinrelColors.darkElevated : null,
          borderRadius: BorderRadius.circular(KinrelRadius.sm),
          border: Border.all(
            color:
                disabled ? KinrelColors.border : Colors.transparent,
          ),
        ),
        child: Text(
          'Invite',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            color: disabled ? KinrelColors.textDim : Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(KinrelRadius.xs),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: KinrelTypography.monoFont,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

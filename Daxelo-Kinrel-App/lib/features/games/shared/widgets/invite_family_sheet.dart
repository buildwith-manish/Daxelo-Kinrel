// lib/features/games/shared/widgets/invite_family_sheet.dart
//
// Shared bottom sheet that lists a family's "Find on Kinrel"-linked
// members (i.e. Person rows with linkedUserId != NULL) and lets the
// host of a game lobby send them a real-time invite to join the room.
//
// Used by all 14 game lobby screens — see usage examples at the bottom.
//
// Edge cases handled:
//   • Empty family-linked list → "No linked family members yet" empty state.
//   • Room full (currentPlayers >= maxPlayers) → Invite buttons disabled.
//   • User already in the room → "In room" badge instead of Invite button.
//   • Self excluded automatically by the RPC.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_spacing.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/network/socket_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../family/presentation/add_member_source.dart';
import '../models/game_invite.dart';

/// A single linked family member returned by `fn_get_linked_family_members`.
class _LinkedMember {
  const _LinkedMember({
    required this.user,
    required this.personId,
    required this.linkedAt,
  });

  final KinrelUser user;
  final String personId;
  final DateTime? linkedAt;
}

/// The sheet widget. Open via [InviteFamilySheet.show] as a modal bottom sheet.
class InviteFamilySheet extends ConsumerStatefulWidget {
  const InviteFamilySheet({
    super.key,
    required this.familyId,
    required this.gameType,
    required this.gameId,
    required this.roomCode,
    required this.currentPlayerIds,
    required this.maxPlayers,
    required this.currentPlayers,
    this.message,
    this.onInviteSent,
  });

  final String familyId;
  final GameType gameType;
  final String gameId;
  final String roomCode;
  final Set<String> currentPlayerIds;
  final int maxPlayers;
  final int currentPlayers;
  final String? message;
  final VoidCallback? onInviteSent;

  /// Opens this sheet as a modal bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required String familyId,
    required GameType gameType,
    required String gameId,
    required String roomCode,
    required Set<String> currentPlayerIds,
    required int maxPlayers,
    required int currentPlayers,
    String? message,
    VoidCallback? onInviteSent,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(KinrelRadius.lg)),
      ),
      builder: (_) => InviteFamilySheet(
        familyId: familyId,
        gameType: gameType,
        gameId: gameId,
        roomCode: roomCode,
        currentPlayerIds: currentPlayerIds,
        maxPlayers: maxPlayers,
        currentPlayers: currentPlayers,
        message: message,
        onInviteSent: onInviteSent,
      ),
    );
  }

  @override
  ConsumerState<InviteFamilySheet> createState() => _InviteFamilySheetState();
}

class _InviteFamilySheetState extends ConsumerState<InviteFamilySheet> {
  List<_LinkedMember> _members = [];
  bool _loading = true;
  String? _error;
  final Set<String> _sendingTo = {}; // user IDs currently being invited
  final Set<String> _sentTo = {}; // user IDs already invited this session

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMembers());
  }

  Future<void> _loadMembers() async {
    final client = ref.read(supabaseProvider);
    if (client == null) {
      setState(() {
        _loading = false;
        _error = 'Not signed in';
      });
      return;
    }
    try {
      final resp = await client.rpc(
        'fn_get_linked_family_members',
        params: {'p_family_id': widget.familyId},
      ).timeout(const Duration(seconds: 15));

      final rows = (resp as List).cast<Map<String, dynamic>>();
      final members = rows.map((r) {
        final user = KinrelUser.fromJson(r);
        final rawTs = r['linkedAt'];
        DateTime? ts;
        if (rawTs is String) ts = DateTime.tryParse(rawTs);
        return _LinkedMember(
          user: user,
          personId: (r['personId'] ?? '') as String,
          linkedAt: ts,
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        _members = members;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  bool get _isRoomFull => widget.currentPlayers >= widget.maxPlayers;

  Future<void> _sendInvite(_LinkedMember m) async {
    if (_sendingTo.contains(m.user.id)) return;
    if (_isRoomFull) return;
    if (widget.currentPlayerIds.contains(m.user.id)) return;

    setState(() => _sendingTo.add(m.user.id));

    final socket = ref.read(socketServiceProvider);
    final client = ref.read(supabaseProvider);
    final myId = client?.auth.currentUser?.id;
    final myName =
        (client?.auth.currentUser?.userMetadata?['name'] as String?) ??
        client?.auth.currentUser?.email ??
        'A family member';

    final invite = GameInvite(
      inviteId:
          'inv_${DateTime.now().millisecondsSinceEpoch}_${m.user.id.substring(0, 8)}',
      gameType: widget.gameType,
      gameId: widget.gameId,
      roomCode: widget.roomCode,
      familyId: widget.familyId,
      fromUserId: myId ?? '',
      fromName: myName,
      maxPlayers: widget.maxPlayers,
      currentPlayers: widget.currentPlayers,
      message: widget.message ??
          '$myName invited you to join ${widget.gameType.displayName}',
      timestamp: DateTime.now().toUtc(),
    );

    try {
      await socket.sendGameInvite(
        toUserId: m.user.id,
        invite: invite,
      );
      if (!mounted) return;
      setState(() {
        _sendingTo.remove(m.user.id);
        _sentTo.add(m.user.id);
      });
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _sendingTo.remove(m.user.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send invite: $e'),
            backgroundColor: KinrelColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final roomFullBanner = _isRoomFull
        ? Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
                horizontal: KinrelSpacing.md, vertical: KinrelSpacing.sm),
            color: KinrelColors.error.withValues(alpha: 0.15),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded,
                  color: KinrelColors.error, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Room is full (${widget.currentPlayers}/${widget.maxPlayers}) — invites disabled.',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    color: KinrelColors.error,
                  ),
                ),
              ),
            ]),
          )
        : const SizedBox.shrink();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(KinrelRadius.lg)),
        ),
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(
                  KinrelSpacing.xl, KinrelSpacing.md, KinrelSpacing.xl, KinrelSpacing.md),
              decoration: const BoxDecoration(
                border: Border(
                    bottom: BorderSide(color: KinrelColors.border, width: 1)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: KinrelSpacing.md),
                    decoration: BoxDecoration(
                      color: KinrelColors.darkElevated,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(children: [
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        'Invite Family to ${widget.gameType.displayName}',
                        style: TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: KinrelColors.textWhite,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Linked Kinrel members only · Room ${widget.roomCode}',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 11,
                          color: KinrelColors.textDim,
                        ),
                      ),
                    ]),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: KinrelColors.textDim, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ]),
              ]),
            ),
            // ── Room-full banner ────────────────────────────────────
            roomFullBanner,
            // ── Body ────────────────────────────────────────────────
            Expanded(
              child: _buildBody(scrollController),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ScrollController scrollController) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: KinrelColors.orange),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(KinrelSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: KinrelColors.error, size: 48),
              const SizedBox(height: KinrelSpacing.md),
              Text(
                'Couldn\'t load family members',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textWhite,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  color: KinrelColors.textDim,
                ),
              ),
              const SizedBox(height: KinrelSpacing.md),
              DKTextButton(
                label: 'Retry',
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _loadMembers();
                },
              ),
            ],
          ),
        ),
      );
    }
    if (_members.isEmpty) {
      return _buildEmptyState();
    }
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.lg, vertical: KinrelSpacing.md),
      itemCount: _members.length,
      itemBuilder: (context, i) => _buildMemberTile(_members[i]),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KinrelSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: KinrelColors.orange.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person_add_outlined,
                  color: KinrelColors.orange, size: 36),
            ),
            const SizedBox(height: KinrelSpacing.lg),
            Text(
              'No linked family members yet',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: KinrelSpacing.sm),
            Text(
              'Invite them to join Kinrel first — only members added via '
              '"Find on Kinrel" can be invited to a game room.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: KinrelColors.textDim,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberTile(_LinkedMember m) {
    final isInRoom = widget.currentPlayerIds.contains(m.user.id);
    final alreadyInvited = _sentTo.contains(m.user.id);
    final isSending = _sendingTo.contains(m.user.id);
    final disabled = _isRoomFull || isInRoom;

    String buttonLabel;
    Color? buttonColor;
    VoidCallback? onPressed;
    if (isInRoom) {
      buttonLabel = 'In room';
      buttonColor = KinrelColors.darkElevated;
      onPressed = null;
    } else if (alreadyInvited) {
      buttonLabel = 'Sent';
      buttonColor = KinrelColors.darkElevated;
      onPressed = () => _sendInvite(m); // allow re-invite
    } else if (_isRoomFull) {
      buttonLabel = 'Full';
      buttonColor = KinrelColors.darkElevated;
      onPressed = null;
    } else if (isSending) {
      buttonLabel = 'Sending';
      buttonColor = KinrelColors.orange;
      onPressed = null;
    } else {
      buttonLabel = 'Invite';
      buttonColor = KinrelColors.orange;
      onPressed = () => _sendInvite(m);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: KinrelSpacing.sm),
      padding: const EdgeInsets.all(KinrelSpacing.md),
      decoration: BoxDecoration(
        color: KinrelColors.darkSurface,
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(color: KinrelColors.border, width: 1),
      ),
      child: Row(children: [
        _buildAvatar(m.user),
        const SizedBox(width: KinrelSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                m.user.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textWhite,
                ),
              ),
              const SizedBox(height: 2),
              if (m.user.username != null && m.user.username!.isNotEmpty)
                Row(children: [
                  Text(
                    '@${m.user.username}',
                    style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 12,
                      color: KinrelColors.orange,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    m.user.displayId,
                    style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 11,
                      color: KinrelColors.textDim,
                    ),
                  ),
                ]),
              if (m.user.bio != null && m.user.bio!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    m.user.bio!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 11,
                      color: KinrelColors.textDim,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 76,
          child: isSending
              ? const Center(
                  child: SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: KinrelColors.orange),
                  ),
                )
              : DKMiniButton(
                  label: buttonLabel,
                  color: buttonColor,
                  disabled: disabled && !alreadyInvited,
                  onPressed: onPressed,
                ),
        ),
      ]),
    );
  }

  Widget _buildAvatar(KinrelUser user) {
    final photo = user.photoThumb ?? user.avatarUrl;
    if (photo != null && photo.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          photo,
          width: 44, height: 44, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildInitialsAvatar(user),
        ),
      );
    }
    return _buildInitialsAvatar(user);
  }

  Widget _buildInitialsAvatar(KinrelUser user) {
    return Container(
      width: 44, height: 44,
      decoration: BoxDecoration(
        color: KinrelColors.orange.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          user.initials,
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: KinrelColors.orange,
          ),
        ),
      ),
    );
  }
}

// ── Helper widgets (kept in this file to keep the sheet self-contained) ─────

/// Small text-only button used for the Invite / Sent / In room actions.
class DKMiniButton extends StatelessWidget {
  const DKMiniButton({
    super.key,
    required this.label,
    this.color,
    this.disabled = false,
    this.onPressed,
  });

  final String label;
  final Color? color;
  final bool disabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = color ?? KinrelColors.orange;
    return Material(
      color: disabled ? KinrelColors.darkElevated : c,
      borderRadius: BorderRadius.circular(KinrelRadius.sm),
      child: InkWell(
        onTap: disabled ? null : onPressed,
        borderRadius: BorderRadius.circular(KinrelRadius.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: disabled ? KinrelColors.textDim : KinrelColors.textWhite,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tiny text-only button for retry actions.
class DKTextButton extends StatelessWidget {
  const DKTextButton({super.key, required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(KinrelRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: KinrelColors.orange,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Usage examples (for reference, not executed) ────────────────────────────
//
// 1) From a "share code" lobby (bingo, ludo, sos, antakshari, truthordare,
//    twotruths, dotsboxes, nameplace, chitmatch, redlight):
//
//   InviteFamilySheet.show(
//     context,
//     familyId: widget.familyId,
//     gameType: GameType.bingo,
//     gameId: state.game!.id,
//     roomCode: code,
//     currentPlayerIds: state.allCards.map((c) => c.playerId).toSet(),
//     maxPlayers: maxP,
//     currentPlayers: state.allCards.length,
//   );
//
// 2) From a "select opponent" lobby (tictactoe, checkers, chess, carrom):
//    These games create the room AFTER opponent selection, so the sheet is
//    opened with a placeholder gameId and the actual gameId is sent in the
//    socket invite once the room is created. See the lobby screen edits
//    for the exact wiring.

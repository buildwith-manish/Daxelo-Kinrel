// lib/features/games/shared/widgets/recent_players_section.dart
//
// "Recently Played With" section shown at the top of InviteFamilySheet.
// Calls fn_get_recent_playmates to fetch up to 5 family members the host
// has played any game with in the last 30 days, sorted by most recent.
// Each row has a one-tap Invite action that fires the same sendGameInvite
// path as the regular per-member list.
//
// Hidden automatically when there are no recent playmates.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_spacing.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/network/socket_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../family/presentation/add_member_source.dart';
import '../models/game_invite.dart';

class RecentPlayersSection extends ConsumerStatefulWidget {
  const RecentPlayersSection({
    super.key,
    required this.familyId,
    required this.gameType,
    required this.gameId,
    required this.roomCode,
    required this.maxPlayers,
    required this.currentPlayers,
    required this.currentPlayerIds,
    this.onInviteSent,
  });

  final String familyId;
  final GameType gameType;
  final String gameId;
  final String roomCode;
  final int maxPlayers;
  final int currentPlayers;
  final Set<String> currentPlayerIds;
  final VoidCallback? onInviteSent;

  @override
  ConsumerState<RecentPlayersSection> createState() =>
      _RecentPlayersSectionState();
}

class _RecentPlayersSectionState extends ConsumerState<RecentPlayersSection> {
  List<KinrelUser> _recent = [];
  bool _loading = true;
  final Set<String> _sendingTo = {};
  final Set<String> _sentTo = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final client = ref.read(supabaseProvider);
    final myId = client?.auth.currentUser?.id;
    if (client == null || myId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final resp = await client.rpc(
        'fn_get_recent_playmates',
        params: {
          'p_user_id': myId,
          'p_family_id': widget.familyId,
          'p_limit': 5,
          'p_days_back': 30,
        },
      ).timeout(const Duration(seconds: 10));
      final rows = (resp as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _recent = rows.map((r) => KinrelUser.fromJson({
              ...r,
              'id': r['userId'],
              'name': r['userName'] ?? 'Family member',
            })).toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _invite(KinrelUser user) async {
    if (_sendingTo.contains(user.id)) return;
    if (widget.currentPlayerIds.contains(user.id)) return;
    if (widget.currentPlayers >= widget.maxPlayers) return;

    setState(() => _sendingTo.add(user.id));
    final socket = ref.read(socketServiceProvider);
    final client = ref.read(supabaseProvider);
    final myId = client?.auth.currentUser?.id ?? '';
    final myName =
        (client?.auth.currentUser?.userMetadata?['name'] as String?) ??
            'A family member';
    final invite = GameInvite(
      inviteId:
          'inv_${DateTime.now().millisecondsSinceEpoch}_${user.id.substring(0, 8)}',
      gameType: widget.gameType,
      gameId: widget.gameId,
      roomCode: widget.roomCode,
      familyId: widget.familyId,
      fromUserId: myId,
      fromName: myName,
      maxPlayers: widget.maxPlayers,
      currentPlayers: widget.currentPlayers,
      message: '$myName invited you to join ${widget.gameType.displayName}',
      timestamp: DateTime.now().toUtc(),
    );
    try {
      await socket.sendGameInvite(toUserId: user.id, invite: invite);
      if (mounted) {
        setState(() {
          _sendingTo.remove(user.id);
          _sentTo.add(user.id);
        });
        widget.onInviteSent?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invite sent to ${user.name}'),
            duration: const Duration(seconds: 2),
            backgroundColor: KinrelColors.darkElevated,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _sendingTo.remove(user.id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: KinrelColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: KinrelColors.orange),
          ),
        ),
      );
    }
    if (_recent.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: KinrelSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history, color: KinrelColors.orange, size: 14),
              const SizedBox(width: 6),
              Text(
                'RECENTLY PLAYED WITH',
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textDim,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ..._recent.map(_row),
        ],
      ),
    );
  }

  Widget _row(KinrelUser u) {
    final isInRoom = widget.currentPlayerIds.contains(u.id);
    final isSending = _sendingTo.contains(u.id);
    final alreadySent = _sentTo.contains(u.id);
    final isFull = widget.currentPlayers >= widget.maxPlayers;
    final disabled = isInRoom || isFull;

    String label;
    Color? color;
    VoidCallback? onPressed;
    if (isInRoom) {
      label = 'In room';
      color = KinrelColors.darkElevated;
    } else if (alreadySent) {
      label = 'Sent';
      color = KinrelColors.darkElevated;
      onPressed = () => _invite(u);
    } else if (isFull) {
      label = 'Full';
      color = KinrelColors.darkElevated;
    } else if (isSending) {
      label = 'Sending';
      color = KinrelColors.orange;
    } else {
      label = 'Invite';
      color = KinrelColors.orange;
      onPressed = () => _invite(u);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: KinrelColors.darkSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KinrelColors.border, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: KinrelColors.orange.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                u.initials,
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.orange,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              u.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textWhite,
              ),
            ),
          ),
          SizedBox(
            width: 64,
            child: isSending
                ? const Center(
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: KinrelColors.orange),
                    ),
                  )
                : Material(
                    color: disabled ? KinrelColors.darkElevated : color,
                    borderRadius: BorderRadius.circular(6),
                    child: InkWell(
                      onTap: disabled ? null : onPressed,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        child: Center(
                          child: Text(
                            label,
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: disabled
                                  ? KinrelColors.textDim
                                  : KinrelColors.textWhite,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

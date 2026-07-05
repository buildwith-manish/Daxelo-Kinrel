// lib/features/games/shared/widgets/invite_family_sheet.dart
//
// Shared bottom sheet for inviting family members to a game room.
// Supports two invite modes (per spec):
//
//   1. "Invite Specific Members" (default)
//      - List of Find-on-Kinrel-linked family members.
//      - Each row has a single-tap "Invite" button (instant send).
//      - OR multi-select via checkboxes + "Send N invites" button at bottom.
//      - Per-member status badges (Pending / Accepted / Declined / Expired).
//
//   2. "Invite Entire Family Space"
//      - One-click bulk send to ALL linked family members.
//      - Confirmation dialog: "Invite all N family members to [Game]?"
//      - Sends invites simultaneously; first-come-first-served for room slots.
//
// Edge cases handled (per spec):
//   • Empty family-linked list → "No linked family members yet" empty state.
//   • Room full (currentPlayers >= maxPlayers) → Invite buttons disabled,
//     banner explains why.
//   • User already in room → "In room" badge instead of Invite button.
//   • Self excluded automatically by the RPC.
//   • Bulk invite exceeds remaining slots → all invites still sent, with a
//     "first-come, first-served" note.
//   • Status tracking via gameInviteStatusProvider — every invite is marked
//     'pending' on send, then 'accepted' / 'declined' / 'expired' as
//     responses arrive.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_spacing.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/network/socket_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../family/presentation/add_member_source.dart';
import '../models/game_invite.dart';
import '../models/game_invite_status.dart';
import '../providers/game_invite_status_provider.dart';
import 'invite_status_badge.dart';
import 'recent_players_section.dart';

/// Invite scope selected by the host at the top of the sheet.
enum _InviteMode { specific, entire }

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

  /// Current invite mode (specific vs entire). Defaults to specific.
  _InviteMode _mode = _InviteMode.specific;

  /// Multi-select state for "Specific Members" mode.
  /// Empty = single-tap mode (each row has its own Invite button).
  /// Non-empty = multi-select mode (rows show checkboxes; bottom button sends all).
  final Set<String> _selectedUserIds = {};

  /// User IDs currently being invited (showing spinner).
  final Set<String> _sendingTo = {};

  /// Bulk-send in progress (Entire Family Space mode).
  bool _bulkSending = false;

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

  bool get _isRoomFull =>
      widget.currentPlayers >= widget.maxPlayers;
  int get _remainingSlots =>
      (widget.maxPlayers - widget.currentPlayers).clamp(0, widget.maxPlayers);

  /// Build a [GameInvite] instance for one recipient.
  GameInvite _buildInvite() {
    final client = ref.read(supabaseProvider);
    final myId = client?.auth.currentUser?.id ?? '';
    final myName =
        (client?.auth.currentUser?.userMetadata?['name'] as String?) ??
            client?.auth.currentUser?.email ??
            'A family member';
    return GameInvite(
      inviteId:
          'inv_${DateTime.now().millisecondsSinceEpoch}_${myId.substring(0, 8)}',
      gameType: widget.gameType,
      gameId: widget.gameId,
      roomCode: widget.roomCode,
      familyId: widget.familyId,
      fromUserId: myId,
      fromName: myName,
      maxPlayers: widget.maxPlayers,
      currentPlayers: widget.currentPlayers,
      message: widget.message ??
          '$myName invited you to join ${widget.gameType.displayName}',
      timestamp: DateTime.now().toUtc(),
    );
  }

  /// Send a single invite to one member and mark them as 'pending' in the
  /// status provider. Single-tap path.
  Future<void> _sendInvite(_LinkedMember m) async {
    if (_sendingTo.contains(m.user.id)) return;
    if (_isRoomFull) return;
    if (widget.currentPlayerIds.contains(m.user.id)) return;

    setState(() => _sendingTo.add(m.user.id));

    final socket = ref.read(socketServiceProvider);
    final base = _buildInvite();
    final invite = GameInvite(
      inviteId:
          'inv_${DateTime.now().millisecondsSinceEpoch}_${m.user.id.substring(0, 8)}',
      gameType: base.gameType,
      gameId: base.gameId,
      roomCode: base.roomCode,
      familyId: base.familyId,
      fromUserId: base.fromUserId,
      fromName: base.fromName,
      maxPlayers: base.maxPlayers,
      currentPlayers: base.currentPlayers,
      message: base.message,
      timestamp: DateTime.now().toUtc(),
    );

    try {
      await socket.sendGameInvite(toUserId: m.user.id, invite: invite);
      // Mark pending in the per-gameId status tracker.
      ref.read(gameInviteStatusProvider(widget.gameId).notifier).markPending(
            userId: m.user.id,
            name: m.user.name,
            username: m.user.username,
            avatarUrl: m.user.avatarUrl,
            photoThumb: m.user.photoThumb,
          );
      if (!mounted) return;
      setState(() => _sendingTo.remove(m.user.id));
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

  /// Send invites to all selected members (multi-select path).
  Future<void> _sendSelectedInvites() async {
    if (_selectedUserIds.isEmpty) return;
    final selected = _members
        .where((m) => _selectedUserIds.contains(m.user.id))
        .toList();
    setState(() {
      for (final m in selected) {
        _sendingTo.add(m.user.id);
      }
    });

    final socket = ref.read(socketServiceProvider);
    final base = _buildInvite();
    int sent = 0;
    final records = <InviteRecord>[];

    for (final m in selected) {
      final invite = GameInvite(
        inviteId:
            'inv_${DateTime.now().millisecondsSinceEpoch}_${m.user.id.substring(0, 8)}',
        gameType: base.gameType,
        gameId: base.gameId,
        roomCode: base.roomCode,
        familyId: base.familyId,
        fromUserId: base.fromUserId,
        fromName: base.fromName,
        maxPlayers: base.maxPlayers,
        currentPlayers: base.currentPlayers,
        message: base.message,
        timestamp: DateTime.now().toUtc(),
      );
      try {
        await socket.sendGameInvite(toUserId: m.user.id, invite: invite);
        records.add(InviteRecord(
          userId: m.user.id,
          name: m.user.name,
          username: m.user.username,
          avatarUrl: m.user.avatarUrl,
          photoThumb: m.user.photoThumb,
          status: InviteMemberStatus.pending,
          sentAt: DateTime.now(),
        ));
        sent++;
      } catch (_) {
        // best-effort — keep going for the rest
      }
    }

    if (records.isNotEmpty) {
      ref
          .read(gameInviteStatusProvider(widget.gameId).notifier)
          .markManyPending(records);
    }

    if (!mounted) return;
    setState(() {
      for (final m in selected) {
        _sendingTo.remove(m.user.id);
      }
      _selectedUserIds.clear();
    });
    widget.onInviteSent?.call();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$sent invite${sent == 1 ? '' : 's'} sent'),
          duration: const Duration(seconds: 2),
          backgroundColor: KinrelColors.darkElevated,
        ),
      );
    }
  }

  /// Send invites to ALL linked family members at once.
  /// Caller must already have shown the confirmation dialog.
  Future<void> _sendBulkInvites() async {
    final eligible = _members
        .where((m) =>
            !widget.currentPlayerIds.contains(m.user.id) &&
            !_isRoomFull)
        .toList();
    if (eligible.isEmpty) return;

    setState(() => _bulkSending = true);

    final socket = ref.read(socketServiceProvider);
    final base = _buildInvite();
    int sent = 0;
    final records = <InviteRecord>[];

    for (final m in eligible) {
      final invite = GameInvite(
        inviteId:
            'inv_${DateTime.now().millisecondsSinceEpoch}_${m.user.id.substring(0, 8)}',
        gameType: base.gameType,
        gameId: base.gameId,
        roomCode: base.roomCode,
        familyId: base.familyId,
        fromUserId: base.fromUserId,
        fromName: base.fromName,
        maxPlayers: base.maxPlayers,
        currentPlayers: base.currentPlayers,
        message: base.message,
        timestamp: DateTime.now().toUtc(),
      );
      try {
        await socket.sendGameInvite(toUserId: m.user.id, invite: invite);
        records.add(InviteRecord(
          userId: m.user.id,
          name: m.user.name,
          username: m.user.username,
          avatarUrl: m.user.avatarUrl,
          photoThumb: m.user.photoThumb,
          status: InviteMemberStatus.pending,
          sentAt: DateTime.now(),
        ));
        sent++;
      } catch (_) {
        // best-effort — keep going
      }
    }

    if (records.isNotEmpty) {
      ref
          .read(gameInviteStatusProvider(widget.gameId).notifier)
          .markManyPending(records);
    }

    if (!mounted) return;
    setState(() => _bulkSending = false);
    widget.onInviteSent?.call();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$sent invite${sent == 1 ? '' : 's'} sent to ${widget.gameType.displayName}',
          ),
          duration: const Duration(seconds: 3),
          backgroundColor: KinrelColors.darkElevated,
        ),
      );
      Navigator.of(context).pop();
    }
  }

  /// Show the "Invite all N members?" confirmation dialog before bulk send.
  Future<void> _confirmBulkInvite() async {
    final eligible = _members
        .where((m) =>
            !widget.currentPlayerIds.contains(m.user.id) &&
            !_isRoomFull)
        .toList();
    if (eligible.isEmpty) return;

    final spotsNote = eligible.length > _remainingSlots
        ? '\n\nOnly $_remainingSlots spot${_remainingSlots == 1 ? '' : 's'} '
            'available — invites are first-come, first-served.'
        : '';

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: KinrelColors.darkCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
        ),
        title: Text(
          'Invite entire family space?',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textWhite,
          ),
        ),
        content: Text(
          'Invite all ${eligible.length} linked family member'
          '${eligible.length == 1 ? '' : 's'} to ${widget.gameType.displayName}?$spotsNote',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 13,
            color: KinrelColors.textWhite,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                color: KinrelColors.textDim,
              ),
            ),
          ),
          Material(
            color: KinrelColors.orange,
            borderRadius: BorderRadius.circular(KinrelRadius.sm),
            child: InkWell(
              onTap: () => Navigator.of(ctx).pop(true),
              borderRadius: BorderRadius.circular(KinrelRadius.sm),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Text(
                  'Invite all ${eligible.length}',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _sendBulkInvites();
    }
  }

  @override
  Widget build(BuildContext context) {
    final inviteStatus = ref.watch(gameInviteStatusProvider(widget.gameId));

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
            _buildHeader(),
            _buildModeSelector(),
            roomFullBanner,
            Expanded(
              child: _buildBody(scrollController, inviteStatus),
            ),
            if (_mode == _InviteMode.specific && _selectedUserIds.isNotEmpty)
              _buildMultiSelectBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
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
                'Room ${widget.roomCode} · ${widget.currentPlayers}/${widget.maxPlayers} players',
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
    );
  }

  /// Segmented control for choosing between the two invite modes.
  Widget _buildModeSelector() {
    return Container(
      margin: const EdgeInsets.fromLTRB(
          KinrelSpacing.lg, KinrelSpacing.md, KinrelSpacing.lg, 0),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: KinrelColors.darkSurface,
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(color: KinrelColors.border, width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: _modeSegment(
              label: 'Specific Members',
              icon: Icons.person_outline,
              selected: _mode == _InviteMode.specific,
              onTap: () => setState(() {
                _mode = _InviteMode.specific;
                _selectedUserIds.clear();
              }),
            ),
          ),
          Expanded(
            child: _modeSegment(
              label: 'Entire Family',
              icon: Icons.groups_outlined,
              selected: _mode == _InviteMode.entire,
              onTap: () => setState(() {
                _mode = _InviteMode.entire;
                _selectedUserIds.clear();
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeSegment({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected ? KinrelColors.orange : Colors.transparent,
          borderRadius: BorderRadius.circular(KinrelRadius.sm),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 14,
                color: selected ? KinrelColors.textWhite : KinrelColors.textDim),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected ? KinrelColors.textWhite : KinrelColors.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
      ScrollController scrollController, GameInviteState inviteStatus) {
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
    switch (_mode) {
      case _InviteMode.specific:
        return _buildSpecificList(scrollController, inviteStatus);
      case _InviteMode.entire:
        return _buildEntireFamilyView(inviteStatus);
    }
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

  // ── Specific Members mode ────────────────────────────────────────────

  Widget _buildSpecificList(
      ScrollController scrollController, GameInviteState inviteStatus) {
    // Compute "selection full" state — can't multi-select more than remaining
    // slots (existing players in room + selected invites can't exceed max).
    final selectionFull =
        _selectedUserIds.length >= _remainingSlots && _remainingSlots > 0;

    return Stack(
      children: [
        ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(
              KinrelSpacing.lg, KinrelSpacing.md, KinrelSpacing.lg, 90),
          children: [
            // ── Recently Played With ──────────────────────────────────
            // Auto-hides when there are no recent playmates (first-time users).
            RecentPlayersSection(
              familyId: widget.familyId,
              gameType: widget.gameType,
              gameId: widget.gameId,
              roomCode: widget.roomCode,
              maxPlayers: widget.maxPlayers,
              currentPlayers: widget.currentPlayers,
              currentPlayerIds: widget.currentPlayerIds,
            ),
            if (_selectedUserIds.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: KinrelSpacing.sm),
                child: Row(
                  children: [
                    Text(
                      'Tap Invite for one, or long-press a row to multi-select.',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 10,
                        color: KinrelColors.textDim,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              )
            else if (selectionFull)
              Padding(
                padding: const EdgeInsets.only(bottom: KinrelSpacing.sm),
                child: Text(
                  'Only $_remainingSlots spot${_remainingSlots == 1 ? '' : 's'} '
                  'open — unselect someone to add more.',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 10,
                    color: KinrelColors.orange,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ..._members.map((m) {
              final isSelected = _selectedUserIds.contains(m.user.id);
              final status = inviteStatus[m.user.id]?.status;
              return _buildMemberTile(
                m,
                isSelected: isSelected,
                status: status,
                selectionFull: selectionFull,
              );
            }),
          ],
        ),
      ],
    );
  }

  Widget _buildMemberTile(
    _LinkedMember m, {
    required bool isSelected,
    required InviteMemberStatus? status,
    required bool selectionFull,
  }) {
    final isInRoom = widget.currentPlayerIds.contains(m.user.id);
    final isSending = _sendingTo.contains(m.user.id);
    final multiSelectActive = _selectedUserIds.isNotEmpty;
    final disabled = _isRoomFull || isInRoom;
    final canSelect = !disabled && (!selectionFull || isSelected);

    // Single-tap Invite button label & color
    String buttonLabel;
    Color? buttonColor;
    VoidCallback? onPressed;
    if (isInRoom) {
      buttonLabel = 'In room';
      buttonColor = KinrelColors.darkElevated;
      onPressed = null;
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

    return GestureDetector(
      onLongPress: disabled
          ? null
          : () {
              // Enter multi-select mode
              if (canSelect) {
                setState(() {
                  if (isSelected) {
                    _selectedUserIds.remove(m.user.id);
                  } else {
                    _selectedUserIds.add(m.user.id);
                  }
                });
              }
            },
      onTap: multiSelectActive
          ? () {
              if (canSelect) {
                setState(() {
                  if (isSelected) {
                    _selectedUserIds.remove(m.user.id);
                  } else {
                    _selectedUserIds.add(m.user.id);
                  }
                });
              }
            }
          : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: KinrelSpacing.sm),
        padding: const EdgeInsets.all(KinrelSpacing.md),
        decoration: BoxDecoration(
          color: isSelected
              ? KinrelColors.orange.withValues(alpha: 0.08)
              : KinrelColors.darkSurface,
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          border: Border.all(
            color: isSelected ? KinrelColors.orange : KinrelColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(children: [
          // Checkbox or radio indicator (only in multi-select mode)
          if (multiSelectActive)
            Padding(
              padding: const EdgeInsets.only(right: KinrelSpacing.sm),
              child: Icon(
                isSelected
                    ? Icons.check_circle
                    : (canSelect ? Icons.radio_button_unchecked : Icons.block),
                size: 18,
                color: isSelected
                    ? KinrelColors.orange
                    : (canSelect ? KinrelColors.textDim : KinrelColors.darkElevated),
              ),
            ),
          _buildAvatar(m.user),
          const SizedBox(width: KinrelSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(
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
                  ),
                  if (status != null) ...[
                    const SizedBox(width: 6),
                    InviteStatusBadge(status: status, compact: true),
                  ],
                ]),
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
          // Action: single-tap Invite button (hidden in multi-select mode)
          if (!multiSelectActive)
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
                      disabled: disabled,
                      onPressed: onPressed,
                    ),
            ),
        ]),
      ),
    );
  }

  /// Bottom bar with "Send N invites" button for multi-select mode.
  Widget _buildMultiSelectBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(
          KinrelSpacing.lg, KinrelSpacing.sm, KinrelSpacing.lg, KinrelSpacing.md),
      decoration: const BoxDecoration(
        color: KinrelColors.darkCard,
        border: Border(top: BorderSide(color: KinrelColors.border, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            TextButton(
              onPressed: () => setState(() => _selectedUserIds.clear()),
              child: Text(
                'Cancel',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  color: KinrelColors.textDim,
                ),
              ),
            ),
            const Spacer(),
            DKMiniButton(
              label: 'Send ${_selectedUserIds.length} invite${_selectedUserIds.length == 1 ? '' : 's'}',
              color: KinrelColors.orange,
              onPressed: _sendSelectedInvites,
            ),
          ],
        ),
      ),
    );
  }

  // ── Entire Family Space mode ────────────────────────────────────────

  Widget _buildEntireFamilyView(GameInviteState inviteStatus) {
    final eligible = _members
        .where((m) =>
            !widget.currentPlayerIds.contains(m.user.id) && !_isRoomFull)
        .toList();
    final alreadyInRoom = _members
        .where((m) => widget.currentPlayerIds.contains(m.user.id))
        .length;
    final overCapacity =
        eligible.length > _remainingSlots && _remainingSlots > 0;

    if (_members.isEmpty) return _buildEmptyState();

    return ListView(
      padding: const EdgeInsets.all(KinrelSpacing.lg),
      children: [
        // Hero card
        Container(
          padding: const EdgeInsets.all(KinrelSpacing.xl),
          decoration: BoxDecoration(
            color: KinrelColors.darkSurface,
            borderRadius: BorderRadius.circular(KinrelRadius.lg),
            border: Border.all(color: KinrelColors.orange.withValues(alpha: 0.3), width: 1.5),
          ),
          child: Column(
            children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  color: KinrelColors.orange.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.groups_outlined,
                    color: KinrelColors.orange, size: 30),
              ),
              const SizedBox(height: KinrelSpacing.md),
              Text(
                'Invite all ${eligible.length} linked member${eligible.length == 1 ? '' : 's'}',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'Sends a real-time invite to every Find-on-Kinrel-linked '
                'family member in this space simultaneously.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  color: KinrelColors.textDim,
                  height: 1.5,
                ),
              ),
              if (overCapacity) ...[
                const SizedBox(height: KinrelSpacing.md),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: KinrelSpacing.md, vertical: KinrelSpacing.sm),
                  decoration: BoxDecoration(
                    color: KinrelColors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(KinrelRadius.sm),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.info_outline,
                          color: KinrelColors.orange, size: 14),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Only $_remainingSlots spot${_remainingSlots == 1 ? '' : 's'} '
                          'available — invites are first-come, first-served.',
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 11,
                            color: KinrelColors.orange,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: KinrelSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: _bulkSending
                    ? const Center(
                        child: SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: KinrelColors.orange),
                        ),
                      )
                    : Material(
                        color: _isRoomFull || eligible.isEmpty
                            ? KinrelColors.darkElevated
                            : KinrelColors.orange,
                        borderRadius: BorderRadius.circular(KinrelRadius.md),
                        child: InkWell(
                          onTap: _isRoomFull || eligible.isEmpty
                              ? null
                              : _confirmBulkInvite,
                          borderRadius: BorderRadius.circular(KinrelRadius.md),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Text(
                              _isRoomFull
                                  ? 'Room is full'
                                  : (eligible.isEmpty
                                      ? 'All members in room'
                                      : 'Invite all ${eligible.length}'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: _isRoomFull || eligible.isEmpty
                                    ? KinrelColors.textDim
                                    : KinrelColors.textWhite,
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),

        // Breakdown
        const SizedBox(height: KinrelSpacing.lg),
        _breakdownRow('Linked family members', _members.length.toString()),
        if (alreadyInRoom > 0)
          _breakdownRow('Already in room', alreadyInRoom.toString()),
        _breakdownRow(
          'Eligible to invite',
          eligible.length.toString(),
          highlight: true,
        ),
        _breakdownRow(
          'Open slots',
          '$_remainingSlots / ${widget.maxPlayers}',
        ),

        // Per-member status (if any invites already sent)
        if (inviteStatus.isNotEmpty) ...[
          const SizedBox(height: KinrelSpacing.lg),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'INVITE STATUS',
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textDim,
                letterSpacing: 1.5,
              ),
            ),
          ),
          const SizedBox(height: KinrelSpacing.sm),
          ...inviteStatus.invites.values.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      r.name,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        color: KinrelColors.textWhite,
                      ),
                    ),
                  ),
                  InviteStatusBadge(status: r.status, compact: true),
                ]),
              )),
        ],
      ],
    );
  }

  Widget _breakdownRow(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: KinrelColors.textDim,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: highlight ? KinrelColors.orange : KinrelColors.textWhite,
            ),
          ),
        ],
      ),
    );
  }

  // ── Avatars ──────────────────────────────────────────────────────────

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

// lib/features/games/shared/widgets/invite_family_sheet.dart
//
// Shared bottom sheet for inviting family members to a game room.
// Supports two invite modes (per spec):
//
//   1. "Invite Specific Members" (default)
//      - List of family members (real Kinrel accounts, sourced from the
//        family membership source — see family_invite_members_provider).
//      - Each row has a single-tap "Invite" button (instant send).
//      - OR multi-select via checkboxes + "Send N invites" button at bottom.
//      - Per-member status badges (Pending / Accepted / Declined / Expired).
//
//   2. "Invite Entire Family Space"
//      - One-click bulk send to ALL linked family members.
//      - Confirmation dialog: "Invite all N family members to [Game]?"
//      - Sends invites simultaneously; first-come-first-served for room slots.
//
// INVITE ROUTING (Task 4, 2026-09-14):
//   • Specific Members (single tap or multi-select) → the invitation is
//     delivered ONLY to the selected members: durable game_invites row
//     (+ FCM push), Socket.IO game:invite:send, and a PRIVATE
//     game-invite DM (DirectMessage, messageType='gameInvite') rendered
//     as an interactive card with a Join action in their DM thread.
//     NEVER the family group chat.
//   • Entire Family (explicit selection + confirmation dialog) → every
//     member still gets their own game_invites row + socket event, and
//     the room card is ALSO posted to the family group chat thread.
//
// MEMBERS (2026-09-14 fix): the list comes from the shared
// familyInviteMembersProvider — fn_get_linked_family_members now reads
// FamilyMember (the membership source) JOIN User plus Find-on-Kinrel
// linked Persons, so every real member appears. The list is LIVE: the
// provider subscribes to FamilyMember/Person realtime (members added /
// removed / linked refresh automatically) and this sheet subscribes to
// game_invites realtime so invitation statuses refresh as invites land
// or are answered. Rows show avatar, name, @username, role, online
// status, invitation status, and a clear Invite action.
//
// Edge cases handled (per spec):
//   • Empty account-linked list → accurate empty state that NEVER claims
//     "no linked members" when members exist (uses family stats).
//   • Room full (currentPlayers >= maxPlayers) → Invite buttons disabled,
//     banner explains why.
//   • User already in room → "In room" badge instead of Invite button.
//   • Self excluded automatically by the RPC.
//   • Bulk invite exceeds remaining slots → all invites still sent, with a
//     "first-come, first-served" note.
//   • Status tracking via gameInviteStatusProvider — every invite is marked
//     'pending' on send, then 'accepted' / 'declined' / 'expired' as
//     responses arrive; syncFromDb reconciles with durable rows.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_spacing.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/network/socket_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../chat/providers/chat_provider.dart';
import '../../../chat/data/direct_message_provider.dart';
import '../../../family/presentation/add_member_source.dart';
import '../../../presence/last_seen_provider.dart';
import '../models/game_invite.dart';
import '../models/game_invite_status.dart';
import '../providers/game_invite_status_provider.dart';
import '../providers/family_invite_members_provider.dart';
import 'invite_status_badge.dart';
import 'recent_players_section.dart';
import 'package:go_router/go_router.dart';

/// Invite scope selected by the host at the top of the sheet.
enum _InviteMode { specific, entire }

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
  /// game_invites realtime channel (invite statuses for THIS room).
  RealtimeChannel? _inviteChannel;
  Timer? _statusSyncDebounce;
  bool _disposed = false;

  /// Search query for filtering the member list (local filter, not RPC).
  /// Filters by name, username, or email — case-insensitive.
  String _searchQuery = '';

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _subscribeToInviteChanges();
      _syncInviteStatuses();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _statusSyncDebounce?.cancel();
    // NEVER touch ref after dispose — the channel was captured alive.
    _inviteChannel?.unsubscribe();
    _inviteChannel = null;
    super.dispose();
  }

  /// Live invitation-status sync: any game_invites change for THIS game
  /// room (invite sent / accepted / declined / expired) triggers a
  /// debounced reconciliation of the status badges with the database.
  void _subscribeToInviteChanges() {
    final client = ref.read(supabaseProvider);
    if (client == null) return;

    void onChanged(_) {
      if (_disposed) return;
      _statusSyncDebounce?.cancel();
      _statusSyncDebounce = Timer(const Duration(milliseconds: 500), () {
        if (!_disposed && mounted) _syncInviteStatuses();
      });
    }

    _inviteChannel = client
        .channel('game-invite-status:${widget.gameId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'game_invites',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: widget.gameId,
          ),
          callback: onChanged,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'game_invites',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: widget.gameId,
          ),
          callback: onChanged,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'game_invites',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: widget.gameId,
          ),
          callback: onChanged,
        )
        .subscribe();
  }

  /// Reconcile invite-status badges with the durable game_invites rows
  /// (recipient responses are persisted by GameInviteListener, so this
  /// works even when the realtime socket event leg failed).
  Future<void> _syncInviteStatuses() async {
    final members =
        ref.read(familyInviteMembersProvider(widget.familyId)).members;
    final lookup = <String,
        ({String name, String? username, String? avatarUrl,
        String? photoThumb})>{};
    for (final m in members) {
      lookup[m.user.id] = (
        name: m.user.name,
        username: m.user.username,
        avatarUrl: m.user.avatarUrl,
        photoThumb: m.user.photoThumb,
      );
    }
    await ref
        .read(gameInviteStatusProvider(widget.gameId).notifier)
        .syncFromDb(nameLookup: lookup);
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

  /// Post the game invite as a persistent card in the family chat thread
  /// (ChatNotifier.sendGameInvite inserts a ChatMessage row with
  /// messageType='gameInvite').
  ///
  /// Task 4 routing rule: ONLY the "Entire Family" bulk path calls this —
  /// a group-wide invitation is visible to the whole family thread.
  /// Specific-member invites are delivered as private DMs instead
  /// (sendGameInviteDm) and never touch the family chat.
  ///
  /// One card per invite-send ACTION — it represents the room as a whole,
  /// not one card per recipient — so this is called exactly once per user
  /// action, never inside the per-recipient loop.
  ///
  /// Best-effort and fully additive: wrapped in its own try/catch that only
  /// debugPrints on failure. A failed chat card must never block, roll back,
  /// or surface an error for the actual game_invites/socket invite flow.
  Future<void> _postInviteChatCard() async {
    try {
      // Read the notifier synchronously — never touch `ref` after an await
      // (this sheet may pop while the insert is in flight).
      final chatNotifier = ref.read(chatProvider(widget.familyId).notifier);
      await chatNotifier.sendGameInvite(
        gameType: widget.gameType.routeSegment,
        gameId: widget.gameId,
        roomCode: widget.roomCode,
        maxPlayers: widget.maxPlayers,
        currentPlayers: widget.currentPlayers,
        // content left null → ChatNotifier falls back to the default
        // "<name> started a <gameType> game" text.
      );
    } catch (e) {
      debugPrint(
          '⚠️ InviteFamilySheet: game-invite chat card failed (non-blocking): $e');
    }
  }

  /// Send a single invite to one member and mark them as 'pending' in the
  /// status provider. Single-tap path.
  ///
  /// Task 4 routing rule: a SPECIFIC-member invite is delivered ONLY to
  /// that member — durable game_invites row (+ FCM push), socket event,
  /// and a private game-invite DM. It never posts to the family group
  /// chat (that card is reserved for the explicit "Entire Family" flow).
  Future<void> _sendInvite(FamilyInviteMember m) async {
    if (_sendingTo.contains(m.user.id)) return;
    if (_isRoomFull) return;
    if (widget.currentPlayerIds.contains(m.user.id)) return;

    setState(() => _sendingTo.add(m.user.id));

    // Capture BEFORE any await — the sheet may pop while the invite legs
    // are in flight (ref must never be touched after dispose).
    final socket = ref.read(socketServiceProvider);
    final client = ref.read(supabaseProvider);
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

    // Tracks whether the DURABLE invite (the game_invites row + its FCM
    // push trigger) was persisted. The chat card accompanies that durable
    // invite, so it must post even when the realtime socket leg fails —
    // e.g. the NestJS gateway is cold-starting or unreachable — because the
    // recipient still has the game_invites row + push notification.
    bool inviteRowInserted = false;

    try {
      // 1. Insert into game_invites table — this triggers the FCM push
      //    via the AFTER INSERT trigger on the table.
      if (client != null) {
        await client.from('game_invites').insert({
          'gameTable': _gameTableName(widget.gameType),
          'gameId': widget.gameId,
          'gameType': widget.gameType.routeSegment,
          'familyId': widget.familyId,
          'roomCode': widget.roomCode,
          'invitedUserId': m.user.id,
          'invitedByUserId': base.fromUserId,
          'invitedByName': base.fromName,
          'maxPlayers': widget.maxPlayers,
          'currentPlayers': widget.currentPlayers,
          'message': base.message,
          'status': 'pending',
          'sourceGameId': null,
        });
        inviteRowInserted = true;
      }

      // 2. Send the in-app realtime Socket.IO event (immediate delivery
      //    if the recipient is online).
      await socket.sendGameInvite(toUserId: m.user.id, invite: invite);

      // 3. Mark pending in the per-gameId status tracker.
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
    } finally {
      // 4. Task 4 — deliver the invite as a PRIVATE direct message to
      //    this specific member only (never the family group chat). The
      //    DM is a durable, visible surface: it appears in the member's
      //    DM thread + inbox with a Join action, live via DirectMessage
      //    realtime. Tied to the durable game_invites row so a fully
      //    failed action never posts a DM. Best-effort, never blocks or
      //    rolls back the invite flow above.
      if (inviteRowInserted && client != null) {
        await sendGameInviteDm(
          client: client,
          toUserId: m.user.id,
          inviteJson: invite.toJson(),
        );
      }
    }
  }

  /// Send invites to all selected members (multi-select path).
  ///
  /// Task 4 routing rule: selected SPECIFIC members each receive a
  /// private game-invite DM (plus their durable game_invites row +
  /// socket event). Nothing is posted to the family group chat — that
  /// card is reserved for the explicit "Entire Family" bulk flow.
  Future<void> _sendSelectedInvites() async {
    if (_selectedUserIds.isEmpty) return;
    final allMembers =
        ref.read(familyInviteMembersProvider(widget.familyId)).members;
    final selected = allMembers
        .where((m) => _selectedUserIds.contains(m.user.id))
        .toList();
    setState(() {
      for (final m in selected) {
        _sendingTo.add(m.user.id);
      }
    });

    // Capture BEFORE any await — the sheet may pop while invite legs are
    // in flight (ref must never be touched after dispose).
    final socket = ref.read(socketServiceProvider);
    final client = ref.read(supabaseProvider);
    final base = _buildInvite();
    int sent = 0;
    // Durable invites persisted to game_invites (row + FCM push trigger).
    // The private invite DM accompanies each of these — not the realtime
    // socket leg, which can fail per-recipient while the invite itself
    // was persisted.
    int inserted = 0;
    final records = <InviteRecord>[];
    final dmTargets = <String, Map<String, dynamic>>{};

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
        // Insert into game_invites (triggers FCM push via AFTER INSERT trigger)
        if (client != null) {
          await client.from('game_invites').insert({
            'gameTable': _gameTableName(widget.gameType),
            'gameId': widget.gameId,
            'gameType': widget.gameType.routeSegment,
            'familyId': widget.familyId,
            'roomCode': widget.roomCode,
            'invitedUserId': m.user.id,
            'invitedByUserId': base.fromUserId,
            'invitedByName': base.fromName,
            'maxPlayers': widget.maxPlayers,
            'currentPlayers': widget.currentPlayers,
            'message': base.message,
            'status': 'pending',
            'sourceGameId': null,
          });
          inserted++;
          dmTargets[m.user.id] = invite.toJson();
        }
        // Send realtime Socket.IO event
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

    // Task 4 — one private invite DM per selected member (never the
    // family group chat). Tied to the durable game_invites rows, so a
    // fully-failed action (or socket outage) posts nothing, while every
    // persisted invite reaches its recipient's DM thread + inbox.
    if (inserted > 0 && client != null) {
      for (final entry in dmTargets.entries) {
        await sendGameInviteDm(
          client: client,
          toUserId: entry.key,
          inviteJson: entry.value,
        );
      }
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
  ///
  /// Task 4 routing rule: this is the ONLY path that posts a game-invite
  /// card to the family GROUP chat — "Entire Family" was explicitly
  /// selected, so the whole thread sees the room card. Every recipient
  /// still also gets their own durable game_invites row + socket event.
  Future<void> _sendBulkInvites() async {
    final eligible = ref
        .read(familyInviteMembersProvider(widget.familyId))
        .members
        .where((m) =>
            !widget.currentPlayerIds.contains(m.user.id) &&
            !_isRoomFull)
        .toList();
    if (eligible.isEmpty) return;

    setState(() => _bulkSending = true);

    final socket = ref.read(socketServiceProvider);
    final base = _buildInvite();
    int sent = 0;
    // Durable invites persisted to game_invites (row + FCM push trigger).
    // The family chat card accompanies these — not the realtime socket
    // leg, which can fail per-recipient while the invite itself was
    // persisted.
    int inserted = 0;
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
        // Insert into game_invites (triggers FCM push via AFTER INSERT trigger)
        final client = ref.read(supabaseProvider);
        if (client != null) {
          await client.from('game_invites').insert({
            'gameTable': _gameTableName(widget.gameType),
            'gameId': widget.gameId,
            'gameType': widget.gameType.routeSegment,
            'familyId': widget.familyId,
            'roomCode': widget.roomCode,
            'invitedUserId': m.user.id,
            'invitedByUserId': base.fromUserId,
            'invitedByName': base.fromName,
            'maxPlayers': widget.maxPlayers,
            'currentPlayers': widget.currentPlayers,
            'message': base.message,
            'status': 'pending',
            'sourceGameId': null,
          });
          inserted++;
        }
        // Send realtime Socket.IO event
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

    // One persistent chat card per send action (not per recipient) — the
    // card represents the invite/room as a whole for the family thread.
    // Tied to the durable game_invites rows (`inserted > 0`), so a fully-
    // failed action (or a socket outage) never posts a card, while a
    // persisted invite always gets one.
    if (inserted > 0) {
      await _postInviteChatCard();
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
      if (context.canPop()) { context.pop(); } else { context.go('/family/${widget.familyId}'); }
    }
  }

  /// Show the "Invite all N members?" confirmation dialog before bulk send.
  Future<void> _confirmBulkInvite() async {
    final eligible = ref
        .read(familyInviteMembersProvider(widget.familyId))
        .members
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
    // The single shared membership source + live realtime refresh.
    final memberState =
        ref.watch(familyInviteMembersProvider(widget.familyId));
    // Live online/last-seen state (updated via UserPresence realtime).
    ref.watch(lastSeenProvider);

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

    // Use a plain Container with a percentage-based height instead of
    // DraggableScrollableSheet. The DSS with expand:false inside a
    // showModalBottomSheet can fail to size its content area correctly
    // on some Flutter web builds, causing the loading spinner to be
    // rendered at 0px height (appears "stuck"). A fixed-height container
    // is simpler and more reliable.
    final screenHeight = MediaQuery.of(context).size.height;
    final sheetHeight = screenHeight * 0.75;

    return Container(
      height: sheetHeight,
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
            child: _buildBody(
                ScrollController(), inviteStatus, memberState),
          ),
          if (_mode == _InviteMode.specific && _selectedUserIds.isNotEmpty)
            _buildMultiSelectBar(),
        ],
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
            onPressed: () { if (context.canPop()) { context.pop(); } else { context.go('/family/${widget.familyId}'); } },
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
      ScrollController scrollController,
      GameInviteState inviteStatus,
      FamilyInviteMembersState memberState) {
    if (memberState.loading) {
      return const Center(
        child: CircularProgressIndicator(color: KinrelColors.orange),
      );
    }
    if (memberState.error != null) {
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
                memberState.error!,
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
                onPressed: () => ref
                    .read(familyInviteMembersProvider(widget.familyId)
                        .notifier)
                    .load(),
              ),
            ],
          ),
        ),
      );
    }
    if (memberState.members.isEmpty) {
      return _buildEmptyState(memberState);
    }
    switch (_mode) {
      case _InviteMode.specific:
        return _buildSpecificList(
            scrollController, inviteStatus, memberState);
      case _InviteMode.entire:
        return _buildEntireFamilyView(inviteStatus, memberState);
    }
  }

  /// ACCURATE empty state — never claims the family has no members when
  /// it does. Uses the family stats fetched alongside the member list:
  ///   • family has other members, but none link a Kinrel account →
  ///     "N members haven't linked their Kinrel accounts yet"
  ///   • caller is the only member → invite people to the family first.
  Widget _buildEmptyState(FamilyInviteMembersState memberState) {
    final stats = memberState.stats;
    final hasOtherMembers = stats.membershipCount > 1;

    final String title;
    final String subtitle;
    if (hasOtherMembers) {
      title =
          '${stats.membershipCount} members, no linked Kinrel accounts yet.';
      subtitle = stats.unlinkedPersonCount > 0
          ? 'Invite them to join Kinrel first, or link their accounts from '
              'your Family screen — then they can join your games.'
          : 'Invite them to join Kinrel first, or add them from your '
              'Family screen.';
    } else {
      title = 'You\'re the only member of this family.';
      subtitle = 'Invite family members to your family first, then come '
          'back to play ${widget.gameType.displayName} together.';
    }

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
              title,
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: KinrelSpacing.sm),
            Text(
              subtitle,
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
      ScrollController scrollController,
      GameInviteState inviteStatus,
      FamilyInviteMembersState memberState) {
    // Compute "selection full" state — can't multi-select more than remaining
    // slots (existing players in room + selected invites can't exceed max).
    final selectionFull =
        _selectedUserIds.length >= _remainingSlots && _remainingSlots > 0;

    // Members with LIVE presence: merge the RPC snapshot with the
    // UserPresence realtime cache, then sort online-first (the fastest
    // invites are the ones someone will actually see).
    final presenceMap = ref.read(lastSeenProvider);
    final members = memberState.members
        .map((m) {
      final live = presenceMap[m.user.id];
      if (live == null) return m;
      return m.copyWith(isOnline: live.isOnline, lastSeenAt: live.lastSeenAt);
    })
        .toList()
      ..sort((a, b) {
        final aOnline = (a.isOnline ?? false) ? 1 : 0;
        final bOnline = (b.isOnline ?? false) ? 1 : 0;
        if (aOnline != bOnline) return bOnline - aOnline;
        return (a.user.name).compareTo(b.user.name);
      });

    // Filter members by search query (local filter, case-insensitive).
    final query = _searchQuery.trim().toLowerCase();
    final filtered = query.isEmpty
        ? members
        : members.where((m) {
            final name = (m.user.name).toLowerCase();
            final username = (m.user.username ?? '').toLowerCase();
            final email = (m.user.email ?? '').toLowerCase();
            return name.contains(query) ||
                username.contains(query) ||
                email.contains(query);
          }).toList();

    return Column(
      children: [
        // ── Search bar ────────────────────────────────────────────
        _buildSearchBar(),
        // ── Scrollable list ───────────────────────────────────────
        Expanded(
          child: filtered.isEmpty && query.isNotEmpty
              ? _buildNoSearchResults()
              : ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(
                      KinrelSpacing.lg, KinrelSpacing.sm, KinrelSpacing.lg, 90),
                  children: [
                    // ── Member count header (live) ────────────────
                    if (query.isEmpty)
                      Padding(
                        padding:
                            const EdgeInsets.only(bottom: KinrelSpacing.sm),
                        child: Row(children: [
                          Text(
                            'FAMILY MEMBERS',
                            style: TextStyle(
                              fontFamily: KinrelTypography.monoFont,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: KinrelColors.textDim,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${members.length}',
                            style: TextStyle(
                              fontFamily: KinrelTypography.monoFont,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: KinrelColors.orange,
                            ),
                          ),
                          const Spacer(),
                          // Online dot + count
                          Container(
                            width: 7, height: 7,
                            decoration: const BoxDecoration(
                              color: Color(0xFF22C55E),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${memberState.onlineCount} online',
                            style: TextStyle(
                              fontFamily: KinrelTypography.monoFont,
                              fontSize: 10,
                              color: KinrelColors.textDim,
                            ),
                          ),
                        ]),
                      ),
                    // ── Recently Played With ──────────────────────
                    // Only show when not searching (avoids clutter).
                    if (query.isEmpty)
                      RecentPlayersSection(
                        familyId: widget.familyId,
                        gameType: widget.gameType,
                        gameId: widget.gameId,
                        roomCode: widget.roomCode,
                        maxPlayers: widget.maxPlayers,
                        currentPlayers: widget.currentPlayers,
                        currentPlayerIds: widget.currentPlayerIds,
                      ),
                    if (_selectedUserIds.isEmpty && query.isEmpty)
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
                    ...filtered.map((m) {
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
        ),
      ],
    );
  }

  /// Search bar matching the Find-on-Kinrel style from kinrel_user_search_screen.
  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(
          KinrelSpacing.lg, KinrelSpacing.sm, KinrelSpacing.lg, 0),
      child: TextField(
        onChanged: (v) => setState(() => _searchQuery = v),
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 14,
          color: KinrelColors.textWhite,
        ),
        decoration: InputDecoration(
          hintText: 'Search by name, username, or email…',
          hintStyle: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 13,
            color: KinrelColors.textDim,
          ),
          prefixIcon:
              const Icon(Icons.search, color: KinrelColors.textDim, size: 18),
          filled: true,
          fillColor: KinrelColors.darkSurface,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(KinrelRadius.md),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(KinrelRadius.md),
            borderSide: const BorderSide(color: KinrelColors.border, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(KinrelRadius.md),
            borderSide:
                const BorderSide(color: KinrelColors.orange, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildNoSearchResults() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KinrelSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off,
                color: KinrelColors.textDim, size: 40),
            const SizedBox(height: KinrelSpacing.md),
            Text(
              'No matching Kinrel users found.',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                color: KinrelColors.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberTile(
    FamilyInviteMember m, {
    required bool isSelected,
    required InviteMemberStatus? status,
    required bool selectionFull,
  }) {
    final isInRoom = widget.currentPlayerIds.contains(m.user.id);
    final isSending = _sendingTo.contains(m.user.id);
    final multiSelectActive = _selectedUserIds.isNotEmpty;
    final disabled = _isRoomFull || isInRoom;
    final canSelect = !disabled && (!selectionFull || isSelected);

    // Presence label: live "online" or "last seen X ago".
    final presence = ref.read(lastSeenProvider)[m.user.id];
    final isOnline = presence?.isOnline ?? (m.isOnline ?? false);
    final presenceLabel = presence != null
        ? formatLastSeen(presence)
        : (isOnline
            ? 'online'
            : (m.lastSeenAt != null
                ? formatLastSeen(UserLastSeen(
                    userId: m.user.id,
                    isOnline: false,
                    lastSeenAt: m.lastSeenAt))
                : 'offline'));

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
          _buildAvatar(m.user, isOnline: isOnline),
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
                  // Role chip (real joined member vs linked person).
                  if (m.isMember) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: KinrelColors.darkElevated,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'MEMBER',
                        style: TextStyle(
                          fontFamily: KinrelTypography.monoFont,
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          color: KinrelColors.textSilver,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                  if (status != null) ...[
                    const SizedBox(width: 6),
                    InviteStatusBadge(status: status, compact: true),
                  ],
                ]),
                const SizedBox(height: 2),
                Row(children: [
                  if (m.user.username != null &&
                      m.user.username!.isNotEmpty) ...[
                    Flexible(
                      child: Text(
                        '@${m.user.username}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: KinrelTypography.monoFont,
                          fontSize: 12,
                          color: KinrelColors.orange,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  // Live presence: online (green) / last seen (dim).
                  Flexible(
                    child: Text(
                      presenceLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 11,
                        fontWeight:
                            isOnline ? FontWeight.w600 : FontWeight.w400,
                        color: isOnline
                            ? const Color(0xFF22C55E)
                            : KinrelColors.textDim,
                      ),
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

  Widget _buildEntireFamilyView(
      GameInviteState inviteStatus, FamilyInviteMembersState memberState) {
    final members = memberState.members;
    final eligible = members
        .where((m) =>
            !widget.currentPlayerIds.contains(m.user.id) && !_isRoomFull)
        .toList();
    final alreadyInRoom = members
        .where((m) => widget.currentPlayerIds.contains(m.user.id))
        .length;
    final overCapacity =
        eligible.length > _remainingSlots && _remainingSlots > 0;

    if (members.isEmpty) return _buildEmptyState(memberState);

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
                'Sends a real-time invite to every family member with a '
                'Kinrel account in this space simultaneously.',
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
        _breakdownRow('Family members', members.length.toString()),
        _breakdownRow(
          'Online now',
          memberState.onlineCount.toString(),
        ),
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

  /// Avatar with a live online-status dot (green = online, dim = offline).
  Widget _buildAvatar(KinrelUser user, {bool isOnline = false}) {
    return SizedBox(
      width: 44, height: 44,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          _buildAvatarImage(user),
          Positioned(
            right: -1, bottom: -1,
            child: Container(
              width: 12, height: 12,
              decoration: BoxDecoration(
                color: isOnline
                    ? const Color(0xFF22C55E)
                    : KinrelColors.darkElevated,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isOnline
                      ? KinrelColors.darkSurface
                      : KinrelColors.border,
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarImage(KinrelUser user) {
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

  /// Map a GameType to its Postgres table name for game_invites insertion.
  String _gameTableName(GameType t) {
    switch (t) {
      case GameType.bingo: return 'bingo_games';
      case GameType.ludo: return 'ludo_games';
      case GameType.checkers: return 'checkers_games';
      case GameType.carrom: return 'carrom_games';
      case GameType.chess: return 'chess_games';
      case GameType.chitmatch: return 'chitmatch_games';
      case GameType.nameplace: return 'nameplace_games';
      case GameType.tictactoe: return 'tictactoe_games';
      case GameType.truthordare: return 'truthordare_games';
      case GameType.twotruths: return 'twotruths_games';
      case GameType.dotsboxes: return 'dotsboxes_games';
      case GameType.sos: return 'sos_games';
      case GameType.antakshari: return 'antakshari_games';
      case GameType.redlight: return 'redlight_rounds';
    }
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

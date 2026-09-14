// lib/features/games/shared/widgets/game_invite_listener.dart
//
// Global listener for incoming game invites.
//
// Task 4 (2026-09-14): invites now arrive over TWO redundant legs so
// delivery is guaranteed even when one fails:
//
//   1. NestJS KinrelGateway socket — `game:invite:received` event
//      (instant, when the recipient is online and the gateway is up).
//
//   2. Supabase Realtime — game_invites INSERT events filtered to
//      invitedUserId = me. The durable row is written by every send
//      path (single / multi-select / bulk), so this leg alone delivers
//      the invite even when the socket gateway is cold-starting or
//      unreachable. game_invites is in the supabase_realtime
//      publication with REPLICA IDENTITY FULL.
//
// Both legs funnel into _handleInvite, which dedupes by (gameId,
// fromUserId) within a short window so the two legs never double-show
// the same invitation. Accepting navigates the user into the host's
// game lobby via the standard `?join=` deep-link format.
//
// Placement: wrapped around the root navigator in main.dart
// (inside PresenceHeartbeat).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_spacing.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/network/socket_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../models/game_invite.dart';

class GameInviteListener extends ConsumerStatefulWidget {
  const GameInviteListener({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<GameInviteListener> createState() => _GameInviteListenerState();
}

class _GameInviteListenerState extends ConsumerState<GameInviteListener> {
  SocketService? _socket;
  VoidCallback? _unsub;
  RealtimeChannel? _inviteChannel;
  StreamSubscription<dynamic>? _authSub;
  final Set<String> _shownInviteIds = {}; // dedupe within session
  // Cross-leg dedupe: (gameId:fromUserId) → last shown time. The socket
  // leg and the DB-realtime leg deliver the same invite within ~seconds
  // of each other; only the first surfaces a dialog.
  final Map<String, DateTime> _shownPairAt = {};
  bool _dbLegAttached = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _attachSocket());
  }

  void _attachSocket() {
    final socket = ref.read(socketServiceProvider);
    _socket = socket;
    _unsub = socket.onGameInviteReceived(_handleInvite);
  }

  /// Leg 2 — durable rows. supabaseProvider is null until Supabase
  /// finishes initializing, so this is driven from build() (which
  /// watches the provider) rather than a one-shot initState read.
  void _ensureDbLegAttached(SupabaseClient client) {
    if (!mounted || _dbLegAttached) return;
    _dbLegAttached = true;

    if (client.auth.currentUser != null) {
      unawaited(_subscribeToInviteRows(client));
    }
    _authSub = client.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;
      if (data.event == AuthChangeEvent.signedIn) {
        unawaited(_subscribeToInviteRows(client));
      } else if (data.event == AuthChangeEvent.signedOut) {
        _inviteChannel?.unsubscribe();
        _inviteChannel = null;
      }
    });
  }

  /// Supabase realtime on game_invites INSERT for ME. RLS
  /// (game_invites_select_self) guarantees I only see rows I'm part of,
  /// and the invitedUserId filter narrows it to incoming invitations.
  ///
  /// TOKEN RACE FIX: a channel's join payload captures
  /// `socket.accessToken` at subscribe() time. Subscribing directly in
  /// the signedIn auth callback races supabase's own async setAuth()
  /// (which suspends on a microtask) — the channel would join with the
  /// ANON key and postgres_changes RLS would silently drop every event.
  /// Awaiting setAuth here first guarantees the user's JWT is on the
  /// socket before the channel joins.
  Future<void> _subscribeToInviteRows(SupabaseClient client) async {
    final myId = client.auth.currentUser?.id;
    if (myId == null || _inviteChannel != null) return;

    final token = client.auth.currentSession?.accessToken;
    if (token != null) {
      try {
        await client.realtime.setAuth(token);
      } catch (_) {
        // Best-effort — setAuth also re-syncs on later auth events.
      }
    }

    _inviteChannel = client
        .channel('game_invites_inbox')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'game_invites',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'invitedUserId',
            value: myId,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            debugPrint('📨 GameInviteListener: game_invites INSERT event '
                '(gameId=${row['gameId']})');
            if (row['status'] != 'pending') return;
            final invite = _inviteFromRow(row);
            if (invite != null) _handleInvite(invite);
          },
        )
        .subscribe((status, [error]) {
          debugPrint('📡 GameInviteListener: game_invites channel '
              '$status${error != null ? ' ($error)' : ''}');
        });
    debugPrint('📡 GameInviteListener: game_invites realtime attached');
  }

  /// Map a game_invites DB row onto a [GameInvite] for the dialog flow.
  GameInvite? _inviteFromRow(Map<String, dynamic> row) {
    final gameId = row['gameId'] as String?;
    if (gameId == null || gameId.isEmpty) return null;
    final gameType = GameTypeX.fromRouteSegment(
            (row['gameType'] as String?) ?? '') ??
        GameTypeX.fromDisplayName((row['gameType'] as String?) ?? '');
    if (gameType == null) return null;

    int toInt(dynamic v, int fallback) =>
        v is num ? v.toInt() : (v is String ? int.tryParse(v) ?? fallback : fallback);

    return GameInvite(
      inviteId: (row['id'] as String?) ?? 'db_${gameId}',
      gameType: gameType,
      gameId: gameId,
      roomCode: (row['roomCode'] as String?) ?? '',
      familyId: (row['familyId'] as String?) ?? '',
      fromUserId: (row['invitedByUserId'] as String?) ?? '',
      fromName: (row['invitedByName'] as String?) ?? 'A family member',
      maxPlayers: toInt(row['maxPlayers'], 2),
      currentPlayers: toInt(row['currentPlayers'], 1),
      message: row['message'] as String?,
      timestamp: DateTime.tryParse((row['createdAt'] as String?) ?? ''),
    );
  }

  void _handleInvite(GameInvite invite) {
    if (!mounted) return;

    // Dedupe — same invite may arrive on both legs (socket + DB row)
    // or twice if the socket reconnects.
    final pairKey = '${invite.gameId}:${invite.fromUserId}';
    final lastShown = _shownPairAt[pairKey];
    final now = DateTime.now();
    if (lastShown != null && now.difference(lastShown).inSeconds < 30) {
      // Same invitation already surfaced recently — skip the duplicate
      // leg but remember the id for session-level dedupe.
      _shownInviteIds.add(invite.inviteId);
      return;
    }
    if (_shownInviteIds.contains(invite.inviteId)) return;

    _shownInviteIds.add(invite.inviteId);
    _shownPairAt[pairKey] = now;

    _showInviteDialog(invite);
  }

  void _showInviteDialog(GameInvite invite) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _GameInviteDialog(
        invite: invite,
        onAccept: () {
          Navigator.of(dialogContext).pop();
          _acceptInvite(invite);
        },
        onDecline: () {
          Navigator.of(dialogContext).pop();
          _declineInvite(invite);
        },
      ),
    );
  }

  Future<void> _acceptInvite(GameInvite invite) async {
    final socket = _socket;
    if (socket != null) {
      try {
        await socket.acceptGameInvite(invite);
      } catch (_) {
        // best-effort — even if ack fails, navigate locally
      }
    }
    // Persist the response so the host's invite sheet (watching the
    // game_invites realtime feed) shows an accurate Accepted badge even
    // if the socket event leg failed. Best-effort — never blocks nav.
    unawaited(_persistInviteStatus(invite, 'accepted'));
    if (!mounted) return;
    // Navigate the recipient into the host's lobby with the join code.
    GoRouter.of(context).go(invite.joinRoute);
  }

  Future<void> _declineInvite(GameInvite invite) async {
    final socket = _socket;
    if (socket != null) {
      try {
        await socket.declineGameInvite(invite);
      } catch (_) {}
    }
    // Persist the decline (same rationale as _acceptInvite).
    unawaited(_persistInviteStatus(invite, 'declined'));
  }

  /// Update the durable game_invites row for this recipient + game so
  /// invitation statuses stay accurate and survive sheet reopens.
  /// RLS: game_invites_update_invited lets the invited user update.
  Future<void> _persistInviteStatus(
      GameInvite invite, String status) async {
    try {
      final client = ref.read(supabaseProvider);
      final myId = client?.auth.currentUser?.id;
      if (client == null || myId == null) return;
      await client
          .from('game_invites')
          .update({
            'status': status,
            'respondedAt': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('gameId', invite.gameId)
          .eq('invitedUserId', myId)
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('⚠️ GameInviteListener: persist $status failed '
          '(non-blocking): $e');
    }
  }

  @override
  void dispose() {
    _unsub?.call();
    _inviteChannel?.unsubscribe();
    unawaited(_authSub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilds when Supabase finishes initializing → attach leg 2 then.
    final client = ref.watch(supabaseProvider);
    if (client != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ensureDbLegAttached(client);
      });
    }
    return widget.child;
  }
}

/// The Accept / Decline dialog shown when an invite arrives.
class _GameInviteDialog extends StatelessWidget {
  const _GameInviteDialog({
    required this.invite,
    required this.onAccept,
    required this.onDecline,
  });

  final GameInvite invite;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: KinrelColors.darkCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(KinrelSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: KinrelColors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(KinrelRadius.md),
                ),
                child: const Icon(Icons.sports_esports,
                    color: KinrelColors.orange, size: 26),
              ),
              const SizedBox(width: KinrelSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${invite.gameType.displayName} invite',
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: KinrelColors.textWhite,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Room ${invite.roomCode} · ${invite.currentPlayers}/${invite.maxPlayers} players',
                      style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 11,
                        color: KinrelColors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: KinrelSpacing.lg),
            // Body
            Text(
              invite.message ??
                  '${invite.fromName} invited you to join ${invite.gameType.displayName}.',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: KinrelColors.textWhite,
                height: 1.4,
              ),
            ),
            const SizedBox(height: KinrelSpacing.sm),
            Text(
              'From ${invite.fromName}',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: KinrelColors.textDim,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: KinrelSpacing.xl),
            // Actions
            Row(children: [
              Expanded(
                child: _DialogButton(
                  label: 'Decline',
                  color: KinrelColors.darkElevated,
                  textColor: KinrelColors.textDim,
                  onPressed: onDecline,
                ),
              ),
              const SizedBox(width: KinrelSpacing.sm),
              Expanded(
                child: _DialogButton(
                  label: 'Accept',
                  color: KinrelColors.orange,
                  textColor: KinrelColors.textWhite,
                  onPressed: onAccept,
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.label,
    required this.color,
    required this.textColor,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final Color textColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(KinrelRadius.md),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

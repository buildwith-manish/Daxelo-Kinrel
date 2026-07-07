// lib/features/games/shared/widgets/game_invite_listener.dart
//
// Global listener for incoming game invites delivered via the
// NestJS KinrelGateway socket (`game:invite:received` event).
//
// Wrap the app's root navigator with this widget so that any incoming
// invite — regardless of which screen the user is on — surfaces an
// Accept / Decline dialog. Accepting navigates the user into the host's
// game lobby with the correct room code applied via the `?join=` query
// parameter (the standard deep-link format for joining a game).
//
// Placement: see `lib/main.dart` or the root `MaterialApp.router` builder.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_spacing.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/network/socket_service.dart';
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
  final Set<String> _shownInviteIds = {}; // dedupe within session

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _attach());
  }

  void _attach() {
    final socket = ref.read(socketServiceProvider);
    _socket = socket;
    _unsub = socket.onGameInviteReceived(_handleInvite);
  }

  void _handleInvite(GameInvite invite) {
    // Dedupe — same invite may arrive twice if socket reconnects.
    if (_shownInviteIds.contains(invite.inviteId)) return;
    _shownInviteIds.add(invite.inviteId);

    // Also listen for the response if the recipient acts elsewhere.
    if (!mounted) return;
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
  }

  @override
  void dispose() {
    _unsub?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
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

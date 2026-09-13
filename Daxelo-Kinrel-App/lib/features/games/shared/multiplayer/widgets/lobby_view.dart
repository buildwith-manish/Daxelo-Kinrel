// lib/features/games/shared/multiplayer/widgets/lobby_view.dart
//
// The shared lobby view used by EVERY multiplayer game. Renders:
//
//   • Auto-close countdown timer (real, server-authoritative)
//   • Share code card (room code)
//   • Players list (with ready badges + host crown)
//   • Pending invites section
//   • Lobby chat panel (system messages + chat messages)
//   • Ready toggle (non-host players) OR "Waiting for players..." + Start
//     button (host, only enabled when all required players are ready)
//   • Cancel Room button (host only)
//
// Per the spec:
//   • Host should never see "Tap when you're ready" — host is auto-ready.
//   • Non-host players see a single Ready / Not Ready toggle.
//   • Host sees "Waiting for players..." + "Start Match" button only when
//     all required players are ready.
//   • Match cannot start until every required player is ready.
//
// This widget is game-agnostic. The game's own lobby screen renders its
// own setup view (mode selection, rules, etc.) and delegates to this
// widget once a room exists. The game's own provider handles the
// "Start Match" action (transitioning the game row from lobby → active)
// via a callback.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/constants/brand_colors.dart';
import '../../../../../core/constants/brand_spacing.dart';
import '../../../../../core/constants/brand_typography.dart';
import '../../../../../shared/widgets/dk_components.dart';
import '../../widgets/invite_family_sheet.dart';
import '../../widgets/pending_invites_section.dart';
import '../../widgets/lobby_chat_panel.dart';
import '../../models/game_invite.dart';
import '../room_config.dart';
import '../room_controller.dart';
import '../room_state.dart';
import 'auto_close_timer.dart';
import 'cancel_room_button.dart';

class LobbyView extends ConsumerStatefulWidget {
  const LobbyView({
    super.key,
    required this.roomKey,
    required this.gameType,
    required this.gameDisplayName,
    required this.startGame,
    this.extraSetupFields,
  });

  final RoomControllerKey roomKey;
  final GameType gameType;
  final String gameDisplayName;
  final Future<void> Function() startGame;
  final Widget? extraSetupFields;

  @override
  ConsumerState<LobbyView> createState() => _LobbyViewState();
}

class _LobbyViewState extends ConsumerState<LobbyView> {
  bool _isStarting = false;

  Future<void> _handleStart() async {
    setState(() => _isStarting = true);
    try {
      await widget.startGame();
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(roomControllerProvider(widget.roomKey));
    final config = widget.roomKey.config;
    final isHost = state.isHost;
    final isSpectator = state.isSpectator;

    final code = state.gameId != null
        ? state.gameId!.replaceAll('-', '').substring(0, 6).toUpperCase()
        : '------';

    return ListView(
      padding: const EdgeInsets.all(KinrelSpacing.base),
      children: [
        // ── Auto-close countdown ─────────────────────────────────────
        AutoCloseTimer(roomKey: widget.roomKey),

        // ── Share code card ──────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(KinrelSpacing.lg),
          decoration: BoxDecoration(
            gradient: KinrelGradients.igniteGradient,
            borderRadius: BorderRadius.circular(KinrelRadius.lg),
          ),
          child: Column(
            children: [
              Text(
                'Share Code',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.9),
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: KinrelSpacing.sm),
              Text(
                code,
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 8,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                config.minPlayers > state.playerCount
                    ? 'Waiting for ${config.minPlayers - state.playerCount} more player(s)'
                    : 'Room ready',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: KinrelSpacing.lg),

        // ── Players list ─────────────────────────────────────────────
        _sectionLabel('Players (${state.playerCount}/${config.maxPlayers})'),
        const SizedBox(height: KinrelSpacing.sm),
        _playerList(state),
        const SizedBox(height: KinrelSpacing.lg),

        // ── Invite button (host only, when room not full) ────────────
        if (isHost && state.playerCount < config.maxPlayers)
          DKButton(
            label: 'Invite Family Members',
            variant: DKButtonVariant.secondary,
            icon: Icons.person_add_outlined,
            fullWidth: true,
            onPressed: () {
              final currentPlayerIds = state.participants
                  .map((p) => p.userId)
                  .whereType<String>()
                  .toSet();
              InviteFamilySheet.show(
                context,
                familyId: state.familyId ?? '',
                gameType: widget.gameType,
                gameId: state.gameId ?? '',
                roomCode: code,
                currentPlayerIds: currentPlayerIds,
                maxPlayers: config.maxPlayers,
                currentPlayers: state.playerCount,
              );
            },
          ),
        const SizedBox(height: KinrelSpacing.lg),

        // ── Pending invites (host + non-host both see them) ─────────
        PendingInvitesSection(gameId: state.gameId ?? ''),
        const SizedBox(height: KinrelSpacing.md),

        // ── Lobby chat panel (with system messages) ──────────────────
        LobbyChatPanel(
          gameTable: config.gameTable.tableName,
          gameId: state.gameId ?? '',
          familyId: state.familyId ?? '',
          isSpectator: isSpectator,
        ),
        const SizedBox(height: KinrelSpacing.lg),

        // ── Inline error ─────────────────────────────────────────────
        if (state.friendlyError != null) ...[
          Container(
            padding: const EdgeInsets.all(KinrelSpacing.md),
            margin: const EdgeInsets.only(bottom: KinrelSpacing.md),
            decoration: BoxDecoration(
              color: KinrelColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(KinrelRadius.md),
              border: Border.all(
                  color: KinrelColors.error.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline,
                    color: KinrelColors.error, size: 18),
                const SizedBox(width: KinrelSpacing.sm),
                Expanded(
                  child: Text(
                    state.friendlyError!,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        // ── Ready / Start controls ──────────────────────────────────
        if (isSpectator) ...[
          _spectatorBanner(),
        ] else if (isHost) ...[
          // Host: never sees "Tap when you're ready" — host is auto-ready.
          // Host sees "Waiting for players..." + Start button (only when
          // all required players are ready).
          DKButton(
            label: state.playerCount < config.minPlayers
                ? 'Waiting for ${config.minPlayers - state.playerCount} more…'
                : (!state.allRequiredReady
                    ? 'Waiting for players to ready up…'
                    : 'Start Match'),
            variant: DKButtonVariant.gradient,
            fullWidth: true,
            isLoading: _isStarting,
            onPressed: (state.playerCount >= config.minPlayers &&
                    state.allRequiredReady)
                ? _handleStart
                : null,
          ),
          CancelRoomButton(roomKey: widget.roomKey),
        ] else ...[
          // Non-host player: single Ready / Not Ready toggle.
          _readyToggle(state),
          // Players can also leave the room if they want.
          DKButton(
            label: 'Leave Room',
            variant: DKButtonVariant.secondary,
            icon: Icons.logout,
            fullWidth: true,
            onPressed: () async {
              await ref
                  .read(roomControllerProvider(widget.roomKey).notifier)
                  .leaveRoom();
            },
          ),
        ],
      ],
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: TextStyle(
          fontFamily: KinrelTypography.displayFont,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: KinrelColors.textDim,
          letterSpacing: 0.5,
        ),
      );

  Widget _playerList(RoomState state) {
    return Container(
      padding: const EdgeInsets.all(KinrelSpacing.md),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(color: KinrelColors.border, width: 1),
      ),
      child: state.participants.isEmpty
          ? Text(
              'No players yet',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: KinrelColors.textDim,
                fontStyle: FontStyle.italic,
              ),
            )
          : Column(
              children: state.participants.map(_playerRow).toList(),
            ),
    );
  }

  Widget _playerRow(RoomParticipant p) {
    final myUserId =
        ref.read(roomControllerProvider(widget.roomKey)).myUserId;
    final isHost = p.isHost;
    final isMe = p.userId == myUserId;
    final ready = p.isReady || isHost;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: KinrelColors.orange.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                (p.userName ?? '?')[0].toUpperCase(),
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.orange,
                ),
              ),
            ),
          ),
          const SizedBox(width: KinrelSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.userName ?? 'Player',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.textWhite,
                  ),
                ),
                if (isHost || isMe)
                  Text(
                    isHost && isMe
                        ? 'You · Host'
                        : isHost
                            ? 'Host'
                            : 'You',
                    style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 10,
                      color: KinrelColors.textDim,
                    ),
                  ),
              ],
            ),
          ),
          if (isHost)
            const Icon(Icons.star, color: KinrelColors.amber, size: 16)
          else if (ready)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: KinrelColors.tealAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle,
                      color: KinrelColors.tealAccent, size: 10),
                  const SizedBox(width: 3),
                  Text(
                    'Ready',
                    style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: KinrelColors.tealAccent,
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: KinrelColors.textDim.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Not Ready',
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textDim,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _readyToggle(RoomState state) {
    final me = state.me;
    final isReady = me?.isReady ?? false;
    return DKButton(
      label: isReady ? 'Not Ready' : 'Ready Up',
      variant: isReady ? DKButtonVariant.secondary : DKButtonVariant.gradient,
      icon: isReady ? Icons.remove_circle_outline : Icons.check_circle_outline,
      fullWidth: true,
      isLoading: state.isSubmitting,
      onPressed: () => ref
          .read(roomControllerProvider(widget.roomKey).notifier)
          .setReady(ready: !isReady),
    );
  }

  Widget _spectatorBanner() {
    return Container(
      padding: const EdgeInsets.all(KinrelSpacing.md),
      decoration: BoxDecoration(
        color: KinrelColors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(
            color: KinrelColors.orange.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.visibility_outlined,
              color: KinrelColors.orange, size: 18),
          const SizedBox(width: KinrelSpacing.sm),
          Expanded(
            child: Text(
              'You\'re watching. Spectators can\'t move, vote, or chat as players.',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: KinrelColors.textWhite,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

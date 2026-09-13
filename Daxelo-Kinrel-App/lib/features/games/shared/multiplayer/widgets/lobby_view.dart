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
import 'match_countdown.dart';

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
    final controller =
        ref.read(roomControllerProvider(widget.roomKey).notifier);
    setState(() => _isStarting = true);
    try {
      // Kick off the 5-second countdown. The actual game-row transition
      // (lobby → active) happens in widget.startGame() when the
      // countdown fires its onComplete callback.
      final ok = await controller.startMatchWithCountdown(
        onCountdownComplete: widget.startGame,
      );
      if (!ok && mounted) {
        // Countdown failed to start — startGame() will not be called
        // automatically. Surface the friendly error from the controller.
        final st = ref.read(roomControllerProvider(widget.roomKey));
        if (st.friendlyError == null) {
          // No specific error; just clear the local starting flag.
        }
      }
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  void _cancelCountdown() {
    ref
        .read(roomControllerProvider(widget.roomKey).notifier)
        .cancelCountdown();
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

    return Stack(
      children: [
        ListView(
      padding: const EdgeInsets.all(KinrelSpacing.base),
      children: [
        // ── Auto-close countdown ─────────────────────────────────────
        AutoCloseTimer(roomKey: widget.roomKey),

        // ── Lobby header (Family Game Night + dynamic subtitle) ──────
        _LobbyHeader(
          gameDisplayName: widget.gameDisplayName,
          subtitle: state.lobbySubtitle(minPlayers: config.minPlayers),
          playerCount: state.playerCount,
          maxPlayers: config.maxPlayers,
        ),
        const SizedBox(height: KinrelSpacing.md),

        // ── Share code card ──────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(KinrelSpacing.lg),
          decoration: BoxDecoration(
            gradient: KinrelGradients.igniteGradient,
            borderRadius: BorderRadius.circular(KinrelRadius.lg),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                  // Live "1 of N Players Joined" pill
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${state.playerCount} of ${config.maxPlayers} Players Joined',
                      style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
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
                _shareCodeSubtitle(state, config),
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

        // ── Presence avatar row (online indicators) ─────────────────
        _PresenceAvatarRow(participants: state.participants),
        const SizedBox(height: KinrelSpacing.md),

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
          // all required players are ready). Tapping Start triggers the
          // 5-second match countdown, then the game's own start callback.
          DKButton(
            label: _hostStartButtonLabel(state, config),
            variant: DKButtonVariant.gradient,
            fullWidth: true,
            isLoading: _isStarting,
            onPressed: _canStart(state, config) ? _handleStart : null,
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
    ),

        // ── 5-second match-start countdown overlay (synced across all clients)
        if (state.isCountdown)
          MatchCountdown(
            roomKey: widget.roomKey,
            onCancel: isHost ? _cancelCountdown : null,
          ),
      ],
    );
  }

  bool _canStart(RoomState state, RoomConfig config) =>
      state.playerCount >= config.minPlayers &&
      state.allRequiredReady &&
      !state.isCountdown;

  String _hostStartButtonLabel(RoomState state, RoomConfig config) {
    if (state.isCountdown) {
      final s = state.secondsUntilCountdownEnds ?? 0;
      return 'Starting in $s\u2026';
    }
    if (state.playerCount < config.minPlayers) {
      return 'Waiting for ${config.minPlayers - state.playerCount} more\u2026';
    }
    if (!state.allRequiredReady) {
      return 'Waiting for players to ready up\u2026';
    }
    return 'Start Match';
  }

  String _shareCodeSubtitle(RoomState state, RoomConfig config) {
    final missing = config.minPlayers - state.playerCount;
    if (missing > 0) {
      return 'Waiting for $missing more player${missing == 1 ? '' : 's'} \u2022 Invite family members';
    }
    if (!state.allRequiredReady) {
      return 'Waiting for players to ready up \u2022 ${state.readyCount}/${state.playerCount} ready';
    }
    return 'Room ready \u2022 Tap Start Match to begin';
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

/// Lobby header showing "Family Game Night 🎮" + dynamic subtitle.
///
/// Per the spec:
///   Family Game Night 🎮
///   Waiting for 1 more player • Invite family members
///
/// Replaces the bare "Room C364FC" header — people care about activity
/// and family context, not room IDs.
class _LobbyHeader extends StatelessWidget {
  const _LobbyHeader({
    required this.gameDisplayName,
    required this.subtitle,
    required this.playerCount,
    required this.maxPlayers,
  });

  final String gameDisplayName;
  final String subtitle;
  final int playerCount;
  final int maxPlayers;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.lg, vertical: KinrelSpacing.md),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(color: KinrelColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: KinrelGradients.igniteGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.sports_esports_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: KinrelSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Family Game Night \u{1F3AE}',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 11,
                    color: KinrelColors.textDim,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: KinrelSpacing.sm),
          // Compact player count badge
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: KinrelColors.orange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$playerCount/$maxPlayers',
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
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

/// Horizontal row of participant avatars with online/ready indicators.
///
/// Renders up to 8 avatars. If there are more, shows "+N" overflow chip.
/// Each avatar has a small status dot:
///   • green = online + ready
///   • orange = online + not ready
///   • grey = offline
class _PresenceAvatarRow extends StatelessWidget {
  const _PresenceAvatarRow({required this.participants});
  final List<RoomParticipant> participants;

  @override
  Widget build(BuildContext context) {
    if (participants.isEmpty) return const SizedBox.shrink();
    const maxAvatars = 8;
    final shown = participants.take(maxAvatars).toList();
    final overflow = participants.length - shown.length;

    return SizedBox(
      height: 44,
      child: Row(
        children: [
          ...List.generate(shown.length, (i) {
            final p = shown[i];
            return Transform.translate(
              offset: Offset(-i * 8.0, 0),
              child: _PresenceAvatar(participant: p),
            );
          }),
          if (overflow > 0)
            Transform.translate(
              offset: Offset(-shown.length * 8.0, 0),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: KinrelColors.darkElevated,
                  shape: BoxShape.circle,
                  border: Border.all(color: KinrelColors.darkSurface, width: 2),
                ),
                child: Center(
                  child: Text(
                    '+$overflow',
                    style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: KinrelColors.textDim,
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(width: KinrelSpacing.md),
          Expanded(
            child: Text(
              _summary,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 11,
                color: KinrelColors.textDim,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String get _summary {
    final online = participants.where((p) => p.isOnline).length;
    final ready = participants.where((p) => p.isReady || p.isHost).length;
    return '$online online \u2022 $ready ready';
  }
}

class _PresenceAvatar extends StatelessWidget {
  const _PresenceAvatar({required this.participant});
  final RoomParticipant participant;

  @override
  Widget build(BuildContext context) {
    final isOnline = participant.isOnline;
    final isReady = participant.isReady || participant.isHost;
    final dotColor = !isOnline
        ? KinrelColors.textDim
        : (isReady ? KinrelColors.tealAccent : KinrelColors.orange);

    return Stack(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: KinrelColors.orange.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(color: KinrelColors.darkSurface, width: 2),
          ),
          child: Center(
            child: Text(
              (participant.userName ?? '?')[0].toUpperCase(),
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: KinrelColors.orange,
              ),
            ),
          ),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
              border: Border.all(color: KinrelColors.darkSurface, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

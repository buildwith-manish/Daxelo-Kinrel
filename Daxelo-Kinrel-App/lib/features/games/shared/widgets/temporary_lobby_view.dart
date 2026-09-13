// lib/features/games/shared/widgets/temporary_lobby_view.dart
//
// TemporaryLobbyView — shared lobby UI for ALL multiplayer games.
//
// Universal layout (same for every game):
//
//   ┌────────────────────────────────────┐
//   │      ✨  Everyone is Ready         │  ← status banner
//   │   Match starts when host taps Go   │
//   ├────────────────────────────────────┤
//   │  Room: ABC123 · 2/6 players         │  ← room metadata (visible
//   │  Auto-closes in 04:32               │     during entire lobby phase)
//   ├────────────────────────────────────┤
//   │ 👤  Manish                ✓ READY  │  ← player avatars + names +
//   │ 👤  Priya                  ✓ READY  │    ready status (primary focus)
//   │ 👤  Aarav                   waiting  │
//   │ 👤  (empty slot)              —     │
//   ├────────────────────────────────────┤
//   │       [   I'm Ready  ✅   ]         │  ← my ready toggle
//   │       [   Start Match    ▶  ]       │  ← Start Match (host only)
//   ├────────────────────────────────────┤
//   │   Pending invites + Lobby chat      │  ← optional footer
//   └────────────────────────────────────┘
//
// State machine (driven by the parent provider's `status` field):
//   waiting     → "Waiting for Players" (or "Everyone is Ready" if all ready)
//   in_progress → "Match Starting" (brief flash before navigating to game)
//   completed   → "Game Finished"
//
// Each game passes a `TemporaryLobbyConfig` describing its room shape
// (table names, max players, current player ids, ready flags, etc.) plus
// callbacks for toggleReady / startMatch / cancelRoom.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_spacing.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../shared/widgets/dk_components.dart';
import '../../game_motion_tokens.dart';

/// One player row in the lobby.
class TemporaryLobbyPlayer {
  const TemporaryLobbyPlayer({
    required this.userId,
    required this.userName,
    required this.isReady,
    required this.isHost,
    this.joinedAt,
  });

  final String userId;
  final String userName;
  final bool isReady;
  final bool isHost;
  final DateTime? joinedAt;
}

/// Status of the room — drives the banner copy.
enum TemporaryLobbyStatus {
  waiting, // room open, players joining / readied
  starting, // host has tapped Start, game is initializing
  finished, // game completed
}

extension TemporaryLobbyStatusX on TemporaryLobbyStatus {
  String get label {
    switch (this) {
      case TemporaryLobbyStatus.waiting:
        return 'Waiting for Players';
      case TemporaryLobbyStatus.starting:
        return 'Match Starting';
      case TemporaryLobbyStatus.finished:
        return 'Game Finished';
    }
  }

  String get emoji {
    switch (this) {
      case TemporaryLobbyStatus.waiting:
        return '👋';
      case TemporaryLobbyStatus.starting:
        return '🚀';
      case TemporaryLobbyStatus.finished:
        return '🏆';
    }
  }
}

/// Configuration passed into TemporaryLobbyView by each game.
class TemporaryLobbyConfig {
  const TemporaryLobbyConfig({
    required this.gameTable,
    required this.gameId,
    required this.familyId,
    required this.hostUserId,
    required this.players,
    required this.maxPlayers,
    required this.status,
    this.roomCode,
    this.subtitle,
    this.showReadyToggle = true,
    this.autoCloseSeconds = 300, // 5 minutes default
  });

  /// e.g. 'antakshari_games' / 'redlight_rounds'
  final String gameTable;

  /// The game/round UUID
  final String gameId;
  final String familyId;

  /// Host's user id — drives the "HOST" badge + who can see Start Match.
  final String? hostUserId;

  /// Current players (including the host).
  final List<TemporaryLobbyPlayer> players;

  /// Max players allowed.
  final int maxPlayers;

  /// Current room status — drives the banner.
  final TemporaryLobbyStatus status;

  /// Optional pre-computed room code (6-char display string).
  /// If null, derived from gameId.
  final String? roomCode;

  /// Optional custom subtitle (e.g. game-mode name + summary).
  final String? subtitle;

  /// Whether to show the "I'm Ready" toggle. Set false for games (like
  /// chitmatch during word submission) that have their own pre-start flow.
  final bool showReadyToggle;

  /// Auto-close countdown in seconds. Default 300 (5 minutes). This is
  /// the inactivity expiry; the room also gets cleaned up by a server-side
  /// pg_cron job as a safety net.
  final int autoCloseSeconds;

  String get derivedRoomCode {
    if (roomCode != null) return roomCode!;
    if (gameId.isEmpty) return '------';
    return gameId.replaceAll('-', '').substring(0, 6).toUpperCase();
  }

  /// True if all current players are ready (and there are at least 2).
  bool get allReady =>
      players.length >= 2 && players.every((p) => p.isReady);

  /// Banner copy for the current state.
  String get bannerTitle {
    switch (status) {
      case TemporaryLobbyStatus.waiting:
        return allReady ? 'Everyone is Ready' : 'Waiting for Players';
      case TemporaryLobbyStatus.starting:
        return 'Match Starting';
      case TemporaryLobbyStatus.finished:
        return 'Game Finished';
    }
  }

  String get bannerSubtitle {
    switch (status) {
      case TemporaryLobbyStatus.waiting:
        if (players.length < 2) {
          final need = 2 - players.length;
          return 'Need $need more to start · ${players.length}/$maxPlayers here';
        }
        if (!allReady) {
          final ready = players.where((p) => p.isReady).length;
          return '$ready of ${players.length} ready · tap "I\'m Ready" when you\'re in';
        }
        return 'Host can start the match · ${players.length}/$maxPlayers ready';
      case TemporaryLobbyStatus.starting:
        return 'Loading the match…';
      case TemporaryLobbyStatus.finished:
        return 'Hope you had fun! This room will close shortly.';
    }
  }
}

/// The shared lobby widget — universal layout for every multiplayer game.
///
/// Usage from a game's lobby screen:
///   TemporaryLobbyView(
///     config: TemporaryLobbyConfig(...),
///     myUserId: myId,
///     onToggleReady: (isReady) => notifier.toggleReady(isReady),
///     onStartMatch: () => notifier.startGame(),
///     onInviteFamily: () => InviteFamilySheet.show(...),
///     onCancelRoom: () => notifier.leaveGame(),
///     footer: Column(children: [
///       PendingInvitesSection(gameId: ...),
///       LobbyChatPanel(...),
///     ]),
///   )
class TemporaryLobbyView extends StatefulWidget {
  const TemporaryLobbyView({
    super.key,
    required this.config,
    required this.myUserId,
    required this.onToggleReady,
    required this.onStartMatch,
    required this.onCancelRoom,
    this.onInviteFamily,
    this.footer,
  });

  final TemporaryLobbyConfig config;
  final String? myUserId;

  /// Called with the new ready state when the user taps the ready toggle.
  final Future<void> Function(bool isReady) onToggleReady;

  /// Called when the host taps "Start Match".
  final Future<void> Function() onStartMatch;

  /// Called when the host taps back / "Cancel Room" while waiting.
  /// The widget itself does NOT navigate — the caller handles routing
  /// (it knows the right back route for its game).
  final Future<void> Function() onCancelRoom;

  /// Optional callback to open the invite-family sheet.
  final VoidCallback? onInviteFamily;

  /// Optional extra widget rendered below the action buttons (e.g. the
  /// per-game lobby chat panel or pending-invites section).
  final Widget? footer;

  @override
  State<TemporaryLobbyView> createState() => _TemporaryLobbyViewState();
}

class _TemporaryLobbyViewState extends State<TemporaryLobbyView> {
  /// Live countdown of seconds remaining until auto-close. Initialized to
  /// the config's autoCloseSeconds and ticks down once per second. The
  /// countdown is paused (reset to full duration) whenever the lobby
  /// sees any activity — see TemporaryRoomService.touchActivity which
  /// bumps lastActivityAt on the server side. Locally, we re-set this
  /// timer to the full duration whenever the player list changes.
  late int _secondsRemaining;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _secondsRemaining = widget.config.autoCloseSeconds;
    _startCountdown();
  }

  @override
  void didUpdateWidget(covariant TemporaryLobbyView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the player count changed (someone joined or left), the server's
    // lastActivityAt was just bumped — reset our local countdown to match.
    if (oldWidget.config.players.length != widget.config.players.length) {
      _secondsRemaining = widget.config.autoCloseSeconds;
    }
    // Once the room is no longer in waiting state, stop the countdown.
    if (widget.config.status != TemporaryLobbyStatus.waiting) {
      _countdownTimer?.cancel();
      _countdownTimer = null;
    } else if (_countdownTimer == null) {
      _startCountdown();
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    if (widget.config.status != TemporaryLobbyStatus.waiting) return;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
      } else {
        _countdownTimer?.cancel();
        _countdownTimer = null;
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  bool get _isHost => widget.config.hostUserId == widget.myUserId;
  bool get _isMyReady {
    final me = widget.config.players
        .where((p) => p.userId == widget.myUserId)
        .firstOrNull;
    return me?.isReady ?? false;
  }

  String get _countdownLabel {
    final m = (_secondsRemaining ~/ 60).toString().padLeft(2, '0');
    final s = (_secondsRemaining % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    return ListView(
      padding: const EdgeInsets.all(KinrelSpacing.base),
      children: [
        // ── 1. Status banner (top) ────────────────────────────────────
        _StatusBanner(config: config),
        const SizedBox(height: KinrelSpacing.sm),

        // ── 2. Room metadata (DIRECTLY below the banner — always visible) ─
        _RoomMetadataBar(
          config: config,
          countdownLabel: _countdownLabel,
          secondsRemaining: _secondsRemaining,
          totalSeconds: config.autoCloseSeconds,
        ),
        const SizedBox(height: KinrelSpacing.lg),

        // ── 3. Player roster ──────────────────────────────────────────
        _PlayerRoster(
          config: config,
          myUserId: widget.myUserId,
          onInviteFamily: widget.onInviteFamily,
        ),
        const SizedBox(height: KinrelSpacing.lg),

        // ── 4. Action buttons (only in waiting state) ────────────────
        if (config.status == TemporaryLobbyStatus.waiting) ...[
          if (config.showReadyToggle)
            _ReadyToggle(
              isReady: _isMyReady,
              onPressed: () => widget.onToggleReady(!_isMyReady),
            ),
          const SizedBox(height: KinrelSpacing.sm),
          _StartMatchButton(
            config: config,
            isHost: _isHost,
            onStartMatch: widget.onStartMatch,
          ),
          const SizedBox(height: KinrelSpacing.sm),
          if (_isHost)
            TextButton(
              onPressed: () async {
                await widget.onCancelRoom();
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/family/${config.familyId}');
                }
              },
              child: Text(
                'Cancel room',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  color: KinrelColors.textDim,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
        ],

        // ── 5. Footer (pending invites + lobby chat) ──────────────────
        if (widget.footer != null) ...[
          const SizedBox(height: KinrelSpacing.lg),
          widget.footer!,
        ],
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// Sub-widgets
// ────────────────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.config});
  final TemporaryLobbyConfig config;

  @override
  Widget build(BuildContext context) {
    final color = _bannerColor(config.status, config.allReady);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.lg,
        vertical: KinrelSpacing.md,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.3),
            color.withValues(alpha: 0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.25),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                config.status.emoji,
                style: const TextStyle(fontSize: 22),
              ),
            ),
          ),
          const SizedBox(width: KinrelSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  config.bannerTitle,
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  config.bannerSubtitle,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    color: KinrelColors.textDim,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _bannerColor(TemporaryLobbyStatus s, bool allReady) {
    switch (s) {
      case TemporaryLobbyStatus.waiting:
        return allReady ? KinrelColors.success : KinrelColors.orange;
      case TemporaryLobbyStatus.starting:
        return KinrelColors.orange;
      case TemporaryLobbyStatus.finished:
        return KinrelColors.success;
    }
  }
}

/// Room metadata bar — shown directly below the status banner. Contains:
///   • Room code (6-char display)
///   • Player count (N/max)
///   • Auto-close countdown (live MM:SS timer)
///
/// This is always visible during the lobby phase so users can always see
/// the room code + how long until the room auto-closes.
class _RoomMetadataBar extends StatelessWidget {
  const _RoomMetadataBar({
    required this.config,
    required this.countdownLabel,
    required this.secondsRemaining,
    required this.totalSeconds,
  });

  final TemporaryLobbyConfig config;
  final String countdownLabel;
  final int secondsRemaining;
  final int totalSeconds;

  @override
  Widget build(BuildContext context) {
    // Color the countdown based on time remaining:
    //   > 50% → dim (plenty of time)
    //   25-50% → orange (getting low)
    //   < 25% → red (urgent)
    final ratio = totalSeconds > 0 ? secondsRemaining / totalSeconds : 0;
    final countdownColor = ratio > 0.5
        ? KinrelColors.textDim
        : ratio > 0.25
            ? KinrelColors.warning
            : KinrelColors.red;

    final isWaiting = config.status == TemporaryLobbyStatus.waiting;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.md,
        vertical: KinrelSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(color: KinrelColors.border),
      ),
      child: Row(
        children: [
          // Room code chip
          Icon(Icons.tag, size: 14, color: KinrelColors.textDim),
          const SizedBox(width: 4),
          Text(
            'Room ${config.derivedRoomCode}',
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 12,
              color: KinrelColors.textWhite,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(width: KinrelSpacing.sm),
          _dot(),
          const SizedBox(width: KinrelSpacing.sm),
          // Player count chip
          Icon(Icons.people_outline, size: 14, color: KinrelColors.textDim),
          const SizedBox(width: 4),
          Text(
            '${config.players.length}/${config.maxPlayers} players',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 11,
              color: KinrelColors.textDim,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          // Auto-close countdown (only shown in waiting state)
          if (isWaiting) ...[
            Icon(Icons.timer_outlined, size: 14, color: countdownColor),
            const SizedBox(width: 4),
            Text(
              'Auto-closes in $countdownLabel',
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 11,
                color: countdownColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ] else if (config.status == TemporaryLobbyStatus.starting) ...[
            Text(
              'Match starting…',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 11,
                color: KinrelColors.orange,
                fontWeight: FontWeight.w600,
                fontStyle: FontStyle.italic,
              ),
            ),
          ] else ...[
            Text(
              'Game finished',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 11,
                color: KinrelColors.success,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _dot() {
    return Container(
      width: 3,
      height: 3,
      decoration: const BoxDecoration(
        color: KinrelColors.textDim,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _PlayerRoster extends StatelessWidget {
  const _PlayerRoster({
    required this.config,
    required this.myUserId,
    required this.onInviteFamily,
  });

  final TemporaryLobbyConfig config;
  final String? myUserId;
  final VoidCallback? onInviteFamily;

  @override
  Widget build(BuildContext context) {
    final players = config.players;
    final emptySlots =
        (config.maxPlayers - players.length).clamp(0, config.maxPlayers);
    return Container(
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(color: KinrelColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              KinrelSpacing.md,
              KinrelSpacing.md,
              KinrelSpacing.md,
              KinrelSpacing.sm,
            ),
            child: Row(
              children: [
                Text(
                  'Players',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.textDim,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Text(
                  '${players.length}/${config.maxPlayers}',
                  style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.orange,
                  ),
                ),
              ],
            ),
          ),
          for (int i = 0; i < players.length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: KinrelColors.border.withValues(alpha: 0.5)),
            _PlayerTile(
              player: players[i],
              isMe: players[i].userId == myUserId,
            ),
          ],
          for (int i = 0; i < emptySlots; i++) ...[
            Divider(height: 1, color: KinrelColors.border.withValues(alpha: 0.5)),
            const _EmptySlot(),
          ],
          if (onInviteFamily != null && emptySlots > 0) ...[
            Divider(height: 1, color: KinrelColors.border.withValues(alpha: 0.5)),
            InkWell(
              onTap: () {
                GameMotionTokens.tap();
                onInviteFamily!();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: KinrelSpacing.md,
                  vertical: KinrelSpacing.md,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.person_add_alt_1,
                      size: 20,
                      color: KinrelColors.orange,
                    ),
                    const SizedBox(width: KinrelSpacing.sm),
                    Text(
                      'Invite family',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.orange,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: KinrelColors.textDim,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlayerTile extends StatelessWidget {
  const _PlayerTile({required this.player, required this.isMe});
  final TemporaryLobbyPlayer player;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final readyColor =
        player.isReady ? KinrelColors.success : KinrelColors.textDim;
    return ListTile(
      leading: DKAvatar(
        initials: player.userName.isNotEmpty
            ? player.userName[0].toUpperCase()
            : '?',
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              isMe ? '${player.userName} (You)' : player.userName,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: KinrelColors.textWhite,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (player.isHost) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: KinrelColors.orange.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(KinrelRadius.xs),
              ),
              child: Text(
                'HOST',
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 9,
                  color: KinrelColors.orange,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ],
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: readyColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(KinrelRadius.xs),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              player.isReady
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              size: 14,
              color: readyColor,
            ),
            const SizedBox(width: 4),
            Text(
              player.isReady ? 'READY' : 'WAITING',
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 10,
                color: readyColor,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptySlot extends StatelessWidget {
  const _EmptySlot();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: KinrelColors.darkElevated,
          shape: BoxShape.circle,
          border: Border.all(
            color: KinrelColors.border.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        child: Icon(
          Icons.person_outline,
          size: 20,
          color: KinrelColors.textDim.withValues(alpha: 0.6),
        ),
      ),
      title: Text(
        'Open slot',
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 13,
          color: KinrelColors.textDim.withValues(alpha: 0.7),
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

class _ReadyToggle extends StatelessWidget {
  const _ReadyToggle({required this.isReady, required this.onPressed});
  final bool isReady;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return DKButton(
      label: isReady ? '✓ I\'m Ready' : 'Tap when you\'re ready',
      variant: isReady ? DKButtonVariant.primary : DKButtonVariant.secondary,
      fullWidth: true,
      onPressed: onPressed,
    );
  }
}

class _StartMatchButton extends StatelessWidget {
  const _StartMatchButton({
    required this.config,
    required this.isHost,
    required this.onStartMatch,
  });

  final TemporaryLobbyConfig config;
  final bool isHost;
  final Future<void> Function() onStartMatch;

  @override
  Widget build(BuildContext context) {
    final canStart =
        isHost && config.allReady && config.players.length >= 2;
    String label;
    if (!isHost) {
      label = 'Waiting for host…';
    } else if (config.players.length < 2) {
      label = 'Waiting for ${2 - config.players.length} more player…';
    } else if (!config.allReady) {
      final notReady = config.players.where((p) => !p.isReady).length;
      label = 'Waiting on $notReady to be ready…';
    } else {
      label = 'Start Match';
    }
    return DKButton(
      label: label,
      variant: DKButtonVariant.gradient,
      fullWidth: true,
      onPressed: canStart ? onStartMatch : null,
    );
  }
}

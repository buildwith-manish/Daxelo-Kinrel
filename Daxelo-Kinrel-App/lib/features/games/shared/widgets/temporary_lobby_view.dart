// lib/features/games/shared/widgets/temporary_lobby_view.dart
//
// TemporaryLobbyView — shared lobby UI for ALL multiplayer games.
//
// Universal layout (same for every game). Everything is PINNED except
// the player rows — so with a 30-slot room, scrolling affects ONLY the
// player list while the invite area, chat and room actions stay
// anchored in place:
//
//   ┌────────────────────────────────────┐
//   │  Room status card                  │  ← FIXED lobby controls
//   │  (code · N/M players · ⏱ 04:32)    │    (never scroll away)
//   ├────────────────────────────────────┤
//   │ 👤 #1  Manish     HOST   ✓ READY  │  ← FLEXIBLE roster — the
//   │ 👤 #2  Priya      ◄ YOU  ✓ READY  │     ONLY scrollable zone.
//   │    #3  (open slot)           —     │     Rows keep the actual
//   │    #4  (open slot)           —     │     JOIN ORDER (slot #),
//   │    …                               │     the local player stays
//   │                                    │     highlighted, and the
//   │                                    │     list opens scrolled to
//   │                                    │     the local player.
//   │  [game footer, e.g. team board]    │  ← capped game-extras dock
//   ├────────────────────────────────────┤      (height-bounded)
//   │ FAMILY MEMBERS            4 open   │  ← FIXED invite section —
//   │ [👤 Invite Family Members      →]  │     directly below the
//   │ 📬 2 invites pending · 1 accepted  │     player list, always
//   ├────────────────────────────────────┤     visible without scroll
//   │  💬 Lobby chat ▾          2 new    │  ← FIXED chat dock
//   ├────────────────────────────────────┤      (collapsible)
//   │ [      Start Match            ]    │  ← FIXED room actions —
//   │ [         Close Room          ]    │     always visible, never
//   └────────────────────────────────────┘     scroll away
//
// Separation of concerns (per the lobby UX spec):
//   • PLAYER MANAGEMENT lives with the roster — the sticky
//     "Invite Family Members" button sits in the Family Members
//     section right below the player list, together with the live
//     invite statuses, so inviting is always one tap away.
//   • ROOM ACTIONS live in the bottom bar — Ready / Start Match /
//     Close Room only. Clean separation, nothing mixed in between.
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
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_spacing.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../shared/widgets/dk_components.dart';
import '../../game_motion_tokens.dart';
import '../multiplayer/widgets/room_close_dialog.dart';
import 'lobby_chat_panel.dart';
import 'pending_invites_section.dart';
import 'room_exit_barrier.dart';

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
        // Smart waiting experience:
        //   • <2 players → "1 of N Joined · Invite Family Members"
        //   • 2+ players, not all ready → "X of Y Ready · tap I'm Ready"
        //   • all ready, host hasn't started → "Match starts when host
        //     taps Start Match"
        if (players.length < 2) {
          return '${players.length} of $maxPlayers Joined · Invite Family Members';
        }
        if (!allReady) {
          final ready = players.where((p) => p.isReady).length;
          return '$ready of ${players.length} Ready · tap "I\'m Ready" when you\'re in';
        }
        return 'Everyone is Ready · Host can start the match';
      case TemporaryLobbyStatus.starting:
        return 'Match starts in…';
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
///     footer: TugTeamBoard(...),   // game extras only (optional)
///   )
///
/// Pending invites are rendered NATIVELY inside the Family Members
/// section (compact) — games no longer pass PendingInvitesSection in
/// the footer. The optional [footer] is for game-specific waiting-room
/// content only (e.g. Tug of War's team board); it is rendered in a
/// height-bounded dock between the roster and the invite section and
/// never pushes the pinned zones off screen.
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

  /// Optional callback to open the invite-family sheet. When provided
  /// (host), the sticky "Invite Family Members" button in the Family
  /// Members section opens it. When null (non-host), the section shows
  /// a muted note instead.
  final VoidCallback? onInviteFamily;

  /// Optional game-specific waiting-room content (e.g. Tug of War's
  /// team board). Rendered in a height-bounded dock directly below the
  /// roster, above the Family Members section. Pending invites are
  /// rendered natively by this widget — do NOT pass them here.
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
    final isWaiting = config.status == TemporaryLobbyStatus.waiting;

    // Layout — ONLY the player rows scroll. Everything else is pinned:
    //   1. FIXED  room status card (lobby controls)
    //   2. FLEX   roster (internal scrolling) + capped game-extras dock
    //   3. FIXED  Family Members / Invite Family section (sticky)
    //   4. FIXED  lobby chat dock (collapsible)
    //   5. FIXED  bottom action bar (room actions only)
    //
    // Because the roster zone is Flexible (not Expanded), the pinned
    // stack below it always lays out at its natural size FIRST — the
    // roster simply absorbs whatever height is left, so the pinned
    // zones can never be pushed off screen, even when the chat dock
    // expands or the game footer is tall.
    final actions = _buildActions(config);

    return LayoutBuilder(builder: (context, constraints) {
      // Chat-expansion cap. The dock itself is pinned and collapses to
      // a slim bar by default; when expanded it may grow up to this
      // height. The cap reserves room for the other pinned zones plus
      // a minimum roster (3 rows) so expanding chat never starves the
      // player list on small screens.
      var chatCap = 216.0;
      if (constraints.hasBoundedHeight) {
        final h = constraints.maxHeight;
        // Measured fixed-stack reserves with margin: header card ≈ 104,
        // family section ≈ 156 (incl. the bounded invite-summary row),
        // collapsed chat bar ≈ 52, action bar ≈ 136 waiting / 92
        // otherwise (host Close-Room-only during the countdown).
        final actionsReserve = isWaiting ? 136.0 : 92.0;
        const fixedReserve = 104.0 + 156.0 + 52.0;
        const middleMin = 3 * _PlayerRosterPanelState.rowExtent + 60.0;
        final budget =
            (h - fixedReserve - actionsReserve - middleMin).clamp(96.0, 264.0);
        chatCap = math.min(budget, h * 0.36);
      }

      return Column(
        children: [
          // ── 1. FIXED — room status card (never scrolls away) ─────
          Padding(
            padding: const EdgeInsets.fromLTRB(KinrelSpacing.base,
                KinrelSpacing.base, KinrelSpacing.base, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _RoomHeaderCard(
                  config: config,
                  countdownLabel: _countdownLabel,
                  secondsRemaining: _secondsRemaining,
                  totalSeconds: config.autoCloseSeconds,
                ),
                // Match-start countdown (only when starting) — brief,
                // fixed below the status card.
                if (config.status == TemporaryLobbyStatus.starting) ...[
                  const SizedBox(height: KinrelSpacing.md),
                  _MatchStartCountdown(),
                ],
              ],
            ),
          ),

          // ── 2. FLEX — roster (ONLY scrollable zone) + game extras ─
          Flexible(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(KinrelSpacing.base,
                  KinrelSpacing.md, KinrelSpacing.base, 0),
              child: LayoutBuilder(builder: (context, middle) {
                // Game-extras dock (e.g. Tug of War's team board):
                // height-bounded so it never starves the roster below
                // the 3-row minimum (12px dock gap + roster header +
                // 3 rows), and never overflows the screen.
                final footerCap = widget.footer == null
                    ? 0.0
                    : (middle.maxHeight -
                            KinrelSpacing.md -
                            _PlayerRosterPanelState.headerExtent -
                            3 * _PlayerRosterPanelState.rowExtent)
                        .clamp(0.0, middle.maxHeight * 0.52);
                return Column(
                  children: [
                    // The roster — flexible; its ListView is the ONLY
                    // scrollable surface in the whole lobby.
                    Flexible(
                      child: LayoutBuilder(builder: (context, zone) {
                        return _PlayerRosterPanel(
                          config: config,
                          myUserId: widget.myUserId,
                          maxZoneHeight: zone.maxHeight,
                        );
                      }),
                    ),
                    if (widget.footer != null) ...[
                      const SizedBox(height: KinrelSpacing.md),
                      ConstrainedBox(
                        constraints:
                            BoxConstraints(maxHeight: footerCap),
                        child: SingleChildScrollView(
                          child: widget.footer!,
                        ),
                      ),
                    ],
                  ],
                );
              }),
            ),
          ),

          // ── 3. FIXED — Family Members / Invite Family ────────────
          // Sticky invite section directly below the player list:
          // always visible without scrolling, so the host can invite
          // at any time — even in a 30-slot room.
          if (isWaiting)
            Padding(
              padding: const EdgeInsets.fromLTRB(KinrelSpacing.base,
                  KinrelSpacing.md, KinrelSpacing.base, 0),
              child: _FamilyInviteSection(
                config: config,
                isHost: _isHost,
                onInviteFamily: widget.onInviteFamily,
              ),
            ),

          // ── 4. FIXED — lobby chat dock (collapsible, in reach) ───
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
            child: _LobbyChatDock(
              config: config,
              expandedHeight: chatCap,
            ),
          ),

          // ── 5. FIXED — bottom action bar (room actions only) ────
          if (actions != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(KinrelSpacing.base,
                  KinrelSpacing.sm, KinrelSpacing.base, KinrelSpacing.base),
              decoration: BoxDecoration(
                color: KinrelColors.darkSurface,
                border: Border(
                  top: BorderSide(
                    color: KinrelColors.border.withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
              ),
              child: actions,
            ),
        ],
      );
    });
  }

  /// Builds the pinned bottom action bar — ROOM ACTIONS ONLY (clean
  /// separation from player management, which lives in the Family
  /// Members section above):
  ///
  ///   • Ready toggle (non-host, waiting only)
  ///   • Start Match (host; disabled until everyone is ready)
  ///   • Close Room (host) — ALWAYS present while the room is open
  ///     (waiting AND starting — it must never disappear). Tapping it
  ///     first shows the shared confirmation dialog; the room is only
  ///     deleted after the host confirms.
  ///
  /// Returns null when the room is finished, or when there is nothing
  /// to pin (e.g. a non-host during the start countdown).
  Widget? _buildActions(TemporaryLobbyConfig config) {
    if (config.status != TemporaryLobbyStatus.waiting &&
        config.status != TemporaryLobbyStatus.starting) {
      return null;
    }
    final isWaiting = config.status == TemporaryLobbyStatus.waiting;
    final showReady = isWaiting && config.showReadyToggle;

    // Nothing to pin — e.g. a non-host during the start countdown,
    // who just waits for the match to begin.
    if (!_isHost && !isWaiting) return null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showReady)
          _ReadyToggle(
            isReady: _isMyReady,
            onPressed: () => widget.onToggleReady(!_isMyReady),
          ),
        if (isWaiting) ...[
          if (showReady) const SizedBox(height: KinrelSpacing.sm),
          _StartMatchButton(
            config: config,
            isHost: _isHost,
            onStartMatch: widget.onStartMatch,
          ),
        ],
        if (_isHost) ...[
          const SizedBox(height: KinrelSpacing.sm),
          _CloseRoomButton(
            onCancelRoom: widget.onCancelRoom,
            fallbackRoute: '/family/${config.familyId}',
            // Registry key — must match the route-level onExit
            // guard in app_router.dart ('<gameTable>/<familyId>').
            exitKey: '${config.gameTable}/${config.familyId}',
          ),
        ],
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// Sub-widgets
// ────────────────────────────────────────────────────────────────────

/// Animated match-start countdown (10, 9, 8, …, GO!) shown when the
/// host taps Start Match. Builds urgency + excitement.
class _MatchStartCountdown extends StatefulWidget {
  @override
  State<_MatchStartCountdown> createState() => _MatchStartCountdownState();
}

class _MatchStartCountdownState extends State<_MatchStartCountdown>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  int _count = 10;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          if (!mounted) return;
          setState(() {
            _count--;
            if (_count < 0) _count = 0;
          });
          _controller.forward(from: 0.0);
        }
      });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ScaleTransition(
        scale: _controller,
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: KinrelColors.orange,
            boxShadow: [
              BoxShadow(
                color: KinrelColors.orange.withValues(alpha: 0.5),
                blurRadius: 18,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                '$_count',
                key: ValueKey(_count),
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: KinrelColors.textWhite,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Room header card — the single status surface at the top of the
/// waiting room. Merges the previous status banner + room metadata bar
/// into ONE cohesive card so the room's state is readable at a glance:
///
///   ┌────────────────────────────────────┐
///   │ (emoji)  Everyone is Ready         │  ← live status (gradient
///   │          Match starts when host…   │    tinted by state)
///   │ ────────────────────────────────── │
///   │ #A1B2C3   2/6 players   ⏱ 04:32   │  ← room facts strip
///   └────────────────────────────────────┘
///
/// The room code is prominent (mono, tap area owned by the app bar's
/// share action) and the auto-close countdown color shifts
/// dim → orange → red as time runs out.
class _RoomHeaderCard extends StatelessWidget {
  const _RoomHeaderCard({
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
    final color = _statusColor(config.status, config.allReady);

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

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.md,
        vertical: KinrelSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.24),
            color.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 1.5),
      ),
      child: Column(
        children: [
          // ── Status row ────────────────────────────────────────────
          Row(
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
                        fontSize: 17,
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
          // ── Room facts strip ──────────────────────────────────────
          const SizedBox(height: KinrelSpacing.sm + 2),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: KinrelSpacing.sm),
            decoration: BoxDecoration(
              color: KinrelColors.darkCard.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(KinrelRadius.md),
              border:
                  Border.all(color: KinrelColors.border.withValues(alpha: 0.7)),
            ),
            child: Row(
              children: [
                Icon(Icons.tag, size: 14, color: KinrelColors.orange),
                const SizedBox(width: 4),
                Text(
                  config.derivedRoomCode,
                  style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 12,
                    color: KinrelColors.textWhite,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(width: KinrelSpacing.sm),
                _dot(),
                const SizedBox(width: KinrelSpacing.sm),
                Icon(Icons.people_outline,
                    size: 14, color: KinrelColors.textDim),
                const SizedBox(width: 4),
                Text(
                  '${config.players.length}/${config.maxPlayers}',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 11,
                    color: KinrelColors.textDim,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (isWaiting) ...[
                  Icon(Icons.timer_outlined,
                      size: 14, color: countdownColor),
                  const SizedBox(width: 4),
                  Text(
                    '$countdownLabel left',
                    style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 11,
                      color: countdownColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ] else if (config.status ==
                    TemporaryLobbyStatus.starting) ...[
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
          ),
        ],
      ),
    );
  }

  Color _statusColor(TemporaryLobbyStatus s, bool allReady) {
    switch (s) {
      case TemporaryLobbyStatus.waiting:
        return allReady ? KinrelColors.success : KinrelColors.orange;
      case TemporaryLobbyStatus.starting:
        return KinrelColors.orange;
      case TemporaryLobbyStatus.finished:
        return KinrelColors.success;
    }
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

/// Fixed-height, independently scrollable player roster.
///
/// UX contract (identical across every game):
///   • Rows preserve the ACTUAL JOIN ORDER — a stable sort by
///     [TemporaryLobbyPlayer.joinedAt], so the host (room creator)
///     naturally sits at slot #1 and later joiners below.
///   • Every row shows its join slot number (#1, #2, …) so each
///     player instantly identifies their position in the room.
///   • The local player's row is permanently highlighted (orange
///     tint + accent bar + YOU chip) — it survives joins, leaves and
///     reconnects.
///   • On open, the list auto-scrolls ONCE so the local player's row
///     is visible near the BOTTOM of the viewport with a few slots
///     above it (slot #8 with a 5-row viewport opens showing ~#4–#8)
///     instead of always starting from the top. Later user scrolling
///     is never overridden.
///   • The list is the ONLY scrollable surface in the lobby — it
///     fills whatever height the flexible zone gives it (clamped to
///     its content when the room is small) and scrolls internally
///     when the room has more slots than fit.
class _PlayerRosterPanel extends StatefulWidget {
  const _PlayerRosterPanel({
    required this.config,
    required this.myUserId,
    required this.maxZoneHeight,
  });

  final TemporaryLobbyConfig config;
  final String? myUserId;

  /// Maximum height of the whole panel (header + list) as granted by
  /// the flexible middle zone. The panel sizes its list viewport to
  /// min(content, this - [headerExtent]) so it never overflows.
  final double maxZoneHeight;

  @override
  State<_PlayerRosterPanel> createState() => _PlayerRosterPanelState();
}

class _PlayerRosterPanelState extends State<_PlayerRosterPanel> {
  /// Fixed row height — a deterministic itemExtent keeps the
  /// auto-scroll-to-my-position math exact.
  static const double rowExtent = 60.0;

  /// Reserved height for the panel's header row (label + "You're #N"
  /// chip + count). Intentionally a slight OVER-estimate of the real
  /// ~40px so the list viewport can never push the card past its zone.
  static const double headerExtent = 48.0;

  final ScrollController _scrollCtrl = ScrollController();

  /// Set once the one-time auto-scroll to my position has happened.
  bool _didAutoScroll = false;

  /// Max height available for the scrollable slot list.
  double get _listCap =>
      (widget.maxZoneHeight - headerExtent).clamp(0.0, double.infinity);

  int get _emptySlots =>
      (widget.config.maxPlayers - widget.config.players.length)
          .clamp(0, widget.config.maxPlayers);

  /// Players in true join order: stable sort by joinedAt (nulls last,
  /// keeping the incoming relative order as the tie-break).
  List<TemporaryLobbyPlayer> _joinOrdered() {
    final players = widget.config.players;
    final indices = List<int>.generate(players.length, (i) => i);
    indices.sort((x, y) {
      final a = players[x].joinedAt;
      final b = players[y].joinedAt;
      int c;
      if (a == null && b == null) {
        c = 0;
      } else if (a == null) {
        c = 1;
      } else if (b == null) {
        c = -1;
      } else {
        c = a.compareTo(b);
      }
      return c != 0 ? c : x - y;
    });
    return [for (final i in indices) players[i]];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _scrollToMyPosition());
  }

  @override
  void didUpdateWidget(covariant _PlayerRosterPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // My row may only become known after the first frame (room state
    // loads asynchronously). Keep retrying until the one-time
    // auto-scroll lands.
    if (!_didAutoScroll) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _scrollToMyPosition());
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// One-time jump (no animation — this IS the initial position)
  /// that puts MY row at the bottom of the viewport with a few rows
  /// above it. Slot #8 with a 5-row viewport therefore opens showing
  /// ~#4–#8. The user's own scrolling afterwards is never overridden.
  void _scrollToMyPosition() {
    if (!mounted || _didAutoScroll || !_scrollCtrl.hasClients) return;
    final players = _joinOrdered();
    var myIndex = -1;
    final myId = widget.myUserId;
    if (myId != null) {
      for (int i = 0; i < players.length; i++) {
        if (players[i].userId == myId) {
          myIndex = i;
          break;
        }
      }
    }
    if (myIndex < 0) return; // not a participant (yet) — stay at top

    final rows = players.length + _emptySlots;
    final viewportH = (rows * rowExtent).clamp(0.0, _listCap);
    final maxExtent = _scrollCtrl.position.maxScrollExtent;
    final target =
        ((myIndex + 1) * rowExtent - viewportH).clamp(0.0, maxExtent);
    _scrollCtrl.jumpTo(target);
    _didAutoScroll = true;
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final players = _joinOrdered();
    final myId = widget.myUserId;
    var myIndex = -1;
    if (myId != null) {
      for (int i = 0; i < players.length; i++) {
        if (players[i].userId == myId) {
          myIndex = i;
          break;
        }
      }
    }
    final rows = players.length + _emptySlots;
    final viewportH = rows * rowExtent <= _listCap
        ? rows * rowExtent
        : _listCap;

    return Container(
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(color: KinrelColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Roster header: label + my position + live count ──────
          Padding(
            padding: const EdgeInsets.fromLTRB(KinrelSpacing.md,
                KinrelSpacing.md, KinrelSpacing.md, KinrelSpacing.sm),
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
                if (myIndex >= 0) ...[
                  const SizedBox(width: KinrelSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: KinrelColors.orange.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(KinrelRadius.xs),
                    ),
                    child: Text(
                      'You\'re #${myIndex + 1}',
                      style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: KinrelColors.orange,
                      ),
                    ),
                  ),
                ],
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
          // ── Fixed-height slot list (scrolls independently) ────────
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(KinrelRadius.lg - 1)),
            child: SizedBox(
              height: viewportH,
              child: rows == 0
                  ? const SizedBox.shrink()
                  : ListView.builder(
                      controller: _scrollCtrl,
                      itemExtent: rowExtent,
                      itemCount: rows,
                      itemBuilder: (_, i) => i < players.length
                          ? _PlayerSlotTile(
                              player: players[i],
                              slotNumber: i + 1,
                              isMe: i == myIndex,
                              showDivider: i != rows - 1,
                            )
                          : _EmptySlotTile(
                              slotNumber: i + 1,
                              showDivider: i != rows - 1,
                            ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One occupied roster row — join-order slot number, avatar, name +
/// role chips, ready pill. The local player's row is highlighted.
class _PlayerSlotTile extends StatelessWidget {
  const _PlayerSlotTile({
    required this.player,
    required this.slotNumber,
    required this.isMe,
    required this.showDivider,
  });

  final TemporaryLobbyPlayer player;
  final int slotNumber;
  final bool isMe;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final readyColor =
        player.isReady ? KinrelColors.success : KinrelColors.textDim;
    return Container(
      height: _PlayerRosterPanelState.rowExtent,
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.md),
      decoration: BoxDecoration(
        // Persistent "this is YOU" highlight — orange wash + accent
        // bar on the leading edge. Survives every rebuild.
        color: isMe ? KinrelColors.orange.withValues(alpha: 0.10) : null,
        border: Border(
          left: isMe
              ? const BorderSide(color: KinrelColors.orange, width: 3)
              : BorderSide.none,
          bottom: showDivider
              ? BorderSide(
                  color: KinrelColors.border.withValues(alpha: 0.5))
              : BorderSide.none,
        ),
      ),
      child: Row(
        children: [
          // Join-order slot number — instant position identification.
          SizedBox(
            width: 30,
            child: Text(
              '#$slotNumber',
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isMe
                    ? KinrelColors.orange
                    : KinrelColors.textDim.withValues(alpha: 0.8),
              ),
            ),
          ),
          DKAvatar(
            initials: player.userName.isNotEmpty
                ? player.userName[0].toUpperCase()
                : '?',
            borderColor: isMe ? KinrelColors.orange : null,
          ),
          const SizedBox(width: KinrelSpacing.sm),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    player.userName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      color: KinrelColors.textWhite,
                      fontWeight: isMe ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: KinrelColors.orange,
                      borderRadius: BorderRadius.circular(KinrelRadius.xs),
                    ),
                    child: Text(
                      'YOU',
                      style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 9,
                        color: KinrelColors.textWhite,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],
                if (player.isHost) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
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
          ),
          Container(
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
        ],
      ),
    );
  }
}

/// One open roster row — numbered like occupied rows so the next
/// joiner's future position is obvious at a glance.
class _EmptySlotTile extends StatelessWidget {
  const _EmptySlotTile({required this.slotNumber, required this.showDivider});

  final int slotNumber;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _PlayerRosterPanelState.rowExtent,
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.md),
      decoration: BoxDecoration(
        border: Border(
          bottom: showDivider
              ? BorderSide(
                  color: KinrelColors.border.withValues(alpha: 0.5))
              : BorderSide.none,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              '#$slotNumber',
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textDim.withValues(alpha: 0.5),
              ),
            ),
          ),
          Container(
            width: 40,
            height: 40,
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
          const SizedBox(width: KinrelSpacing.sm),
          Text(
            'Open slot',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              color: KinrelColors.textDim.withValues(alpha: 0.7),
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
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

/// PINNED "Family Members / Invite Family" section — the invitation
/// home, fixed directly below the player list in the bottom stack so
/// it is ALWAYS visible without scrolling (even in a 30-slot room).
///
/// Contents:
///   • Section label + live open-slots chip ("4 open" / "Room full")
///   • The sticky "Invite Family Members" action (host): opens the
///     invite sheet at any time. When the room is full it stays in
///     place, disabled, with a clear "Room Full" state — never
///     disappears (stable, predictable layout).
///   • Non-hosts see a muted note (the host sends invites; anyone
///     with the room code can join).
///   • Compact live invite statuses (PendingInvitesSection, compact
///     mode) so the host sees at a glance who has answered.
class _FamilyInviteSection extends StatelessWidget {
  const _FamilyInviteSection({
    required this.config,
    required this.isHost,
    required this.onInviteFamily,
  });

  final TemporaryLobbyConfig config;
  final bool isHost;
  final VoidCallback? onInviteFamily;

  int get _openSlots =>
      (config.maxPlayers - config.players.length).clamp(0, config.maxPlayers);

  @override
  Widget build(BuildContext context) {
    final open = _openSlots;

    return Container(
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(color: KinrelColors.border),
      ),
      padding: const EdgeInsets.all(KinrelSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Section header: label + open-slots chip ──────────────
          Row(
            children: [
              Text(
                'Family Members',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textDim,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: open > 0
                      ? KinrelColors.orange.withValues(alpha: 0.14)
                      : KinrelColors.textDim.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(KinrelRadius.xs),
                  border: Border.all(
                    color: open > 0
                        ? KinrelColors.orange.withValues(alpha: 0.5)
                        : KinrelColors.border,
                  ),
                ),
                child: Text(
                  open > 0 ? '$open open' : 'Room full',
                  style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: open > 0 ? KinrelColors.orange : KinrelColors.textDim,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: KinrelSpacing.md),

          // ── Sticky invite action ─────────────────────────────────
          if (isHost && onInviteFamily != null)
            _InviteFamilyRow(
              onTap: onInviteFamily!,
              enabled: open > 0,
            )
          else
            _HostOnlyInviteNote(),

          // ── Compact live invite statuses ────────────────────────
          PendingInvitesSection(gameId: config.gameId, compact: true),
        ],
      ),
    );
  }
}

/// Full-width sticky invite row — the previous design's "Invite
/// family" row, promoted to a prominent button that never scrolls
/// away. Disabled (never hidden) when the room is full.
class _InviteFamilyRow extends StatelessWidget {
  const _InviteFamilyRow({
    required this.onTap,
    required this.enabled,
  });

  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final fg = enabled ? KinrelColors.orange : KinrelColors.textDim;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled
            ? () {
                GameMotionTokens.tap();
                onTap();
              }
            : null,
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: KinrelSpacing.md, vertical: 13),
          decoration: BoxDecoration(
            color: enabled
                ? KinrelColors.orange.withValues(alpha: 0.14)
                : KinrelColors.darkElevated,
            borderRadius: BorderRadius.circular(KinrelRadius.md),
            border: Border.all(
              color: enabled
                  ? KinrelColors.orange.withValues(alpha: 0.55)
                  : KinrelColors.border,
              width: 1.2,
            ),
          ),
          child: Row(
            children: [
              Icon(
                enabled ? Icons.person_add_alt_1 : Icons.lock_outline,
                color: fg,
                size: 18,
              ),
              const SizedBox(width: KinrelSpacing.sm),
              Expanded(
                child: Text(
                  enabled ? 'Invite Family Members' : 'Room Full',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: fg,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: fg.withValues(alpha: 0.7),
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Muted note shown to non-hosts in the Family Members section.
class _HostOnlyInviteNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.md, vertical: 10),
      decoration: BoxDecoration(
        color: KinrelColors.darkElevated,
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(color: KinrelColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline,
              size: 15, color: KinrelColors.textDim),
          const SizedBox(width: KinrelSpacing.sm),
          Expanded(
            child: Text(
              'The host invites family members — anyone with the room '
              'code can join.',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 11,
                color: KinrelColors.textDim,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pinned, collapsible lobby chat dock — the shared [LobbyChatPanel]
/// mounted permanently in the fixed zone below the roster.
///
/// Collapsed it is a slim "Lobby chat · N new" header bar, so the
/// chat ACTION is always visible; tapping expands the full chat in
/// place while the roster above keeps its fixed height. Keeping the
/// panel mounted preserves message history and socket-room membership
/// across expand/collapse cycles.
class _LobbyChatDock extends StatelessWidget {
  const _LobbyChatDock({required this.config, required this.expandedHeight});

  final TemporaryLobbyConfig config;

  /// Max panel height when expanded (clamped to the available space by
  /// the caller so the pinned zones can never overflow the screen).
  final double expandedHeight;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: LobbyChatPanel(
        gameTable: config.gameTable,
        gameId: config.gameId,
        familyId: config.familyId,
        maxHeight: expandedHeight,
        initiallyExpanded: false,
      ),
    );
  }
}

/// Compact, pinned "Close Room" button — host only, always visible
/// in the fixed action bar while the room is open (waiting AND
/// starting — it must never disappear).
///
/// Per the spec:
///   • Clearly visible at all times while the room is open (never
///     hidden behind menus or secondary actions).
///   • NEVER closes the room immediately — tapping it first shows the
///     shared confirmation dialog ("Are you sure you want to close this
///     room?" → [Cancel] [Close Room]).
///   • The room is only deleted after the host confirms (onCancelRoom
///     → fn_cancel_waiting_room RPC removes all participants and the
///     game row, then notifies the other clients via realtime).
///   • Cancel keeps the host in the room.
///
/// Shows a spinner while the deletion RPC is in-flight, then navigates
/// back once it completes.
class _CloseRoomButton extends StatefulWidget {
  const _CloseRoomButton({
    required this.onCancelRoom,
    required this.fallbackRoute,
    required this.exitKey,
  });

  final Future<void> Function() onCancelRoom;
  final String fallbackRoute;

  /// Key used to mark this exit as pre-confirmed in
  /// [RoomExitConfirmations] so the route-level onExit guard does not
  /// show a second confirmation dialog for the same exit.
  final String exitKey;

  @override
  State<_CloseRoomButton> createState() => _CloseRoomButtonState();
}

class _CloseRoomButtonState extends State<_CloseRoomButton> {
  bool _busy = false;

  Future<void> _confirmAndClose() async {
    if (_busy) return; // ignore double taps while in-flight

    // Always show the confirmation dialog first — never close directly.
    final confirmed = await showRoomCloseConfirmDialog(context);
    if (confirmed != true) return; // cancelled — stay in the room
    if (!mounted) return;

    GameMotionTokens.tap();
    setState(() => _busy = true);
    try {
      // Delete the room for everyone (host-only server-side RPC).
      await widget.onCancelRoom();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;

    // Mark this exit as already confirmed so the route-level onExit
    // guard (app_router.dart) lets it through without a second dialog.
    RoomExitConfirmations.mark(widget.exitKey);

    // Room deleted — leave the lobby screen.
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(widget.fallbackRoute);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _busy ? null : _confirmAndClose,
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: KinrelSpacing.md, vertical: 13),
          decoration: BoxDecoration(
            color: _busy
                ? KinrelColors.error.withValues(alpha: 0.5)
                : KinrelColors.error.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(KinrelRadius.md),
            border: Border.all(
              color: KinrelColors.error.withValues(alpha: 0.6),
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_busy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                        KinrelColors.error),
                  ),
                )
              else
                const Icon(Icons.warning_amber_rounded,
                    color: KinrelColors.error, size: 18),
              const SizedBox(width: KinrelSpacing.sm),
              Flexible(
                child: Text(
                  'Close Room',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: KinrelColors.error,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

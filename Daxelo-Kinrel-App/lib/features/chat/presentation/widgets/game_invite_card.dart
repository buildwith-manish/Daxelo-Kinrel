// lib/features/chat/presentation/widgets/game_invite_card.dart
//
// DAXELO KINREL — Shared Game Invite Card (Chat UI Reference D18)
//
// ONE invite card used by BOTH chat types (group + direct). Four states:
//
//   a) ACTIVE (pending / waiting / live): rendered INSIDE the message
//      bubble (sent color for own invites, received color for others —
//      the bubble provides the surface). Row with 10 gap: a 40×40 tile
//      (radius 8, background chatReceived, game icon 22 in orange, the
//      game image when one exists), a column (title 14/500 textPrimary;
//      players · room code line 12 textSecondary — plain text, never
//      monospace), and the Join/status button (transparent background,
//      0.5 orange border, orange 13/500, radius 8, padding 5/12, 48 dp
//      tap target). The bubble renders the D7 time row below.
//
//   b) RESULT (completed WITH a winner): the bubble renders a row with
//      10 gap: trophy icon 22 in #F59E0B, text 14 textPrimary
//      ("<Winner> won <Game>" — the message row stores no numeric
//      score, so the ", 3 to 2" part is omitted until score data
//      exists), and a Rematch button styled like Join that opens the
//      game's lobby (existing navigation, same route a fresh invite
//      uses).
//
//   c) EXPIRED / CANCELLED / COMPLETED WITHOUT WINNER: a quiet
//      one-line row with NO bubble — padding 4 vertical / 6 horizontal,
//      row with 8 gap: game icon 16, text 13 textSubtitle
//      ("SOS · Expired"), the time 11 textMeta right.
//
//   d) COLLAPSED run of 3+ consecutive one-liners: radius 10,
//      background chatCard, padding 8/10, row with 8 gap: game icon 16,
//      "3 game invites · expired" 13 textSubtitle, chevron down 16 at
//      the right. Wired by ChatMessageList (run detection).
//
// Status source is unchanged: the ChatMessage row's game columns.
// Behavior of join, status and expiry stays exactly as it is today.
// Flat style: solid colors, no gradients/blur/shadows.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../games/shared/icons/game_icons.dart';
import '../../../games/shared/models/game_invite.dart';
import '../../providers/chat_provider.dart';
import '../chat_ui_tokens.dart';

/// The one shared game-invite card. Rendered inside the message bubble
/// (states a/b) or as a bubble-less one-liner (state c).
class GameInviteCard extends StatelessWidget {
  const GameInviteCard({
    super.key,
    required this.message,
    required this.isMe,
    required this.routeFamilyId,
    this.scoreLine,
  });

  /// The invite message (gameType/gameId/roomCode/players/status/
  /// winnerName columns are parsed by ChatMessage.fromJson).
  final ChatMessage message;

  /// Optional score suffix for the result card (e.g. ', 3 to 2').
  /// The ChatMessage row stores no numeric score today, so real chats
  /// pass nothing; the UI gallery passes the reference sample. The
  /// moment a score column exists it can be forwarded here.
  final String? scoreLine;

  /// Whether the current user is the invite sender (host never sees
  /// "Join" — they get Rejoin/Spectate or a status label).
  final bool isMe;

  /// The family id used for the Join/Spectate navigation route
  /// (`/family/<id>/<gameType>/lobby?join=<gameId>`). Null disables the
  /// action buttons.
  final String? routeFamilyId;

  // ── Lifecycle state helpers (identical vocabulary to the old card) ──

  String get _status => message.gameInviteStatus ?? 'pending';

  bool get _isPreGame => _status == 'pending' || _status.isEmpty;

  bool get _isInProgress =>
      _status == 'in_progress' || _status == 'accepted' || _status == 'active';

  bool get _isCompleted => _status == 'completed';

  bool get _isExpired => _status == 'expired' || _status == 'cancelled';

  bool get _hasWinner =>
      _isCompleted &&
      message.gameWinnerName != null &&
      message.gameWinnerName!.isNotEmpty;

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // b) Result card — completed with a known winner.
    if (_hasWinner) {
      return _buildResultCard(context);
    }
    // c) Expired / cancelled / completed-without-winner one-liner.
    if (_isCompleted || _isExpired) {
      return _buildTerminalRow();
    }
    // a) Active invite — slim card inside the bubble.
    return _buildActiveCard(context);
  }

  // ── Helpers ─────────────────────────────────────────────────────────

  String get _displayName {
    final rawGameType = message.gameType ?? '';
    final parsed = GameTypeX.fromRouteSegment(rawGameType);
    return parsed?.displayName ?? _titleCaseSegment(rawGameType);
  }

  // ── a) Active (pending / live): slim card inside the bubble ────────

  Widget _buildActiveCard(BuildContext context) {
    final rawGameType = message.gameType ?? '';
    final parsedGameType = GameTypeX.fromRouteSegment(rawGameType);
    final maxPlayers = message.gameMaxPlayers ?? 2;
    final currentPlayers = message.gameCurrentPlayers ?? 1;
    final roomCode = (message.roomCode ?? '').trim();
    final isFull = currentPlayers >= maxPlayers;

    // Action button resolution — unchanged from the previous card
    // (Join / Spectate / Full / In Game / Rejoin).
    final action = _resolveAction(context: context, isFull: isFull);

    return RepaintBoundary(
      child: Semantics(
        container: true,
        label:
            'Game invite: $_displayName, $currentPlayers of $maxPlayers players.'
            '${action.label != null ? ' Action: ${action.label}.' : ''}',
        child: Row(
          children: [
            // 40×40 tile — radius 8, chatReceived, game icon 22 orange
            // (the game image when one exists).
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: ChatUi.chatReceived,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: parsedGameType != null
                    ? GameIcon(gameId: rawGameType, size: 22)
                    : const Icon(
                        Icons.sports_esports_outlined,
                        size: ChatUi.iconGameTile,
                        color: ChatUi.accent,
                      ),
              ),
            ),
            const SizedBox(width: 10),
            // Title + players · room code (plain text, no monospace).
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ChatUi.inviteTitle,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '$currentPlayers/$maxPlayers players'
                    '${roomCode.isNotEmpty ? ' · $roomCode' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ChatUi.invitePlayers,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (action.label != null) _buildInviteButton(context, action),
          ],
        ),
      ),
    );
  }

  ({String? label, VoidCallback? onTap, bool urgent, bool enabled})
      _resolveAction({
    required BuildContext context,
    required bool isFull,
  }) {
    if (_isPreGame && !isFull && !isMe) {
      return (
        label: 'Join',
        onTap:
            (message.gameId ?? '').isNotEmpty ? () => _goToLobby(context) : null,
        urgent: false,
        enabled: true,
      );
    }
    if (_isPreGame && isFull && !isMe) {
      if (message.effectiveSpectatorsEnabled) {
        return (
          label: 'Spectate',
          onTap:
              (message.gameId ?? '').isNotEmpty ? () => _goToLobby(context) : null,
          urgent: false,
          enabled: true,
        );
      }
      return (label: 'Full', onTap: null, urgent: false, enabled: false);
    }
    if (_isInProgress) {
      if (isMe) {
        return (
          label: 'Rejoin',
          onTap:
              (message.gameId ?? '').isNotEmpty ? () => _goToLobby(context) : null,
          urgent: true,
          enabled: true,
        );
      }
      if (message.effectiveSpectatorsEnabled) {
        return (
          label: 'Spectate',
          onTap:
              (message.gameId ?? '').isNotEmpty ? () => _goToLobby(context) : null,
          urgent: true,
          enabled: true,
        );
      }
      return (label: 'In Game', onTap: null, urgent: false, enabled: false);
    }
    // Sender's own waiting/full card: no action (status is conveyed
    // by the players count line).
    return (label: null, onTap: null, urgent: false, enabled: false);
  }

  /// The Join / Spectate / Rejoin / Rematch button: transparent
  /// background, 0.5 orange border, orange 13/500 text, radius 8,
  /// padding 5 vertical / 12 horizontal, ≥48 dp tap target.
  Widget _buildInviteButton(
    BuildContext context,
    ({String? label, VoidCallback? onTap, bool urgent, bool enabled}) action,
  ) {
    final enabled = action.enabled && action.onTap != null;
    final label = action.label!;
    return Semantics(
      label: label,
      button: true,
      enabled: enabled,
      child: GestureDetector(
        onTap: action.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          // ≥48 dp tap target (the visual pill is smaller, centered).
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            border: Border.all(
              color: enabled
                  ? ChatUi.accent
                  : ChatUi.accent.withValues(alpha: 0.4),
              width: 0.5,
            ),
            borderRadius: BorderRadius.circular(8),
            color: Colors.transparent,
          ),
          child: Text(
            label,
            style: ChatUi.buttonLabel.copyWith(
              color: enabled ? ChatUi.accent : ChatUi.textMeta,
            ),
          ),
        ),
      ),
    );
  }

  // ── b) Result card (completed with winner) ──────────────────────────

  Widget _buildResultCard(BuildContext context) {
    final winner = message.gameWinnerName ?? '';
    final rawGameType = message.gameType ?? '';
    return RepaintBoundary(
      child: Semantics(
        container: true,
        label: '$_displayName result: $winner won.',
        child: Row(
          children: [
            // Trophy icon 22 in #F59E0B.
            const Icon(
              Icons.emoji_events_outlined,
              size: ChatUi.iconTrophy,
              color: Color(0xFFF59E0B),
            ),
            const SizedBox(width: 10),
            // "<Winner> won <Game>" — the message row carries no numeric
            // score, so the ", 3 to 2" part is omitted (visual-ready:
            // the moment scores are stored on the row they can be
            // appended here).
            Expanded(
              child: Text(
                '$winner won $_displayName'
                '${scoreLine != null && scoreLine!.isNotEmpty ? ', $scoreLine' : ''}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: ChatUi.inviteTitle,
              ),
            ),
            const SizedBox(width: 8),
            // Rematch — styled like Join; opens the game's lobby (the
            // same route a fresh invite uses — existing navigation).
            _buildInviteButton(
              context,
              (
                label: 'Rematch',
                onTap: (message.gameType ?? '').isNotEmpty && routeFamilyId != null
                    ? () => context.go(
                        '/family/$routeFamilyId/${message.gameType}/lobby')
                    : null,
                urgent: false,
                enabled: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── c) Terminal (expired / no-winner completed): one-line row ───────

  Widget _buildTerminalRow() {
    final detail = _isExpired
        ? 'Expired'
        : (_hasWinner ? 'Completed' : 'Completed');
    return Semantics(
      container: true,
      label: 'Game invite: $_displayName, $detail.',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
          child: Row(
            children: [
              const Icon(
                Icons.sports_esports_outlined,
                size: ChatUi.iconGameLine,
                color: ChatUi.textSubtitle,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$_displayName · $detail',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ChatUi.inviteExpired,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                message.formattedTime,
                style: ChatUi.timeText,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Navigation (identical routes to the previous inline card) ──────

  /// Navigate into the game lobby. Same route for Join and
  /// Spectate/Rejoin — the lobby decides join vs. spectate vs. rejoin
  /// based on the game's current status + the user's participant
  /// status (identical to GameInviteListener._acceptInvite).
  void _goToLobby(BuildContext context) {
    final gameType = message.gameType ?? '';
    final gameId = message.gameId ?? '';
    final famId = routeFamilyId;
    if (gameType.isEmpty || gameId.isEmpty || famId == null) return;
    context.go('/family/$famId/$gameType/lobby?join=$gameId');
  }

  /// Title-case fallback for game types not in the GameType enum
  /// (e.g. 'somegame' → 'Somegame', 'my-game' → 'My Game').
  String _titleCaseSegment(String s) {
    if (s.isEmpty) return s;
    return s
        .split(RegExp(r'[-_\s]+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Collapsed run of terminal invites ("N game invites · expired")
// ═══════════════════════════════════════════════════════════════════════

/// d) Renders a run of 3+ consecutive expired/completed one-liners as
/// ONE quiet row: radius 10, background chatCard, padding 8/10, row
/// with 8 gap (game icon 16, "N game invites · expired" 13
/// textSubtitle, chevron down 16 at the right). Tapping expands it
/// back to one one-line row per invite. Wired by ChatMessageList
/// (which performs the run detection).
class CollapsedGameInvites extends StatefulWidget {
  const CollapsedGameInvites({
    super.key,
    required this.messages,
    required this.isMe,
    required this.routeFamilyId,
  });

  /// The consecutive terminal invites in the run (chronological order).
  final List<ChatMessage> messages;

  final bool isMe;

  final String? routeFamilyId;

  @override
  State<CollapsedGameInvites> createState() => _CollapsedGameInvitesState();
}

class _CollapsedGameInvitesState extends State<CollapsedGameInvites> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final count = widget.messages.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── The collapsed row (tap target ≥ 48px) ──────────────────
          Semantics(
            label: '$count game invites, expired.'
                '${_expanded ? ' Collapse' : ' Expand'}',
            button: true,
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: ChatUi.chatCard,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.sports_esports_outlined,
                      size: ChatUi.iconGameLine,
                      color: ChatUi.textSubtitle,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$count game invites · expired',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ChatUi.inviteExpired,
                      ),
                    ),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: ChatUi.iconChevronDown,
                      color: ChatUi.textSubtitle,
                    ),
                  ],
                ),
              ),
            ),
          ),
          // ── Expanded: one one-line row per invite ───────────────────
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: widget.messages
                    .map(
                      (m) => GameInviteCard(
                        message: m,
                        isMe: widget.isMe,
                        routeFamilyId: widget.routeFamilyId,
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}

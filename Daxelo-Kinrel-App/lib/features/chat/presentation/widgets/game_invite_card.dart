// lib/features/chat/presentation/widgets/game_invite_card.dart
//
// DAXELO KINREL — Shared Game Invite Card (Chat UI Reference D18)
//
// ONE invite card used by BOTH chat types (group + direct). Four
// states, all token-driven (ChatUi) and flat (no gradients/blur/
// shadows):
//
//   • ACTIVE (pending / waiting / live): a slim card — chatCard fill,
//     chatCardBorder hairline, radius 12, 40 dp game icon in accent,
//     display title, "N/M players · ROOM" line, outlined Join /
//     Spectate / Rejoin button.
//   • RESULT (completed with a known winner): a result card — gold
//     trophy, "Papa won Tic Tac Toe" (+ optional scoreLine ", 3 to
//     2"), outlined Rematch button that routes to the existing lobby.
//   • EXPIRED / cancelled / completed-without-winner: a quiet
//     one-line row — NO bubble, small icon, "Game · Expired", time.
//   • COLLAPSED: 3+ consecutive terminal invites render as one
//     chatCard row "N game invites · expired" with a chevron — see
//     [CollapsedGameInvites] (wired by ChatMessageList, which owns
//     the run detection; result cards never join a collapsed run).
//
// Status source is unchanged: the ChatMessage row's game columns
// (group + direct-group chats share the same lifecycle sync RPCs).
// Tap targets are at least 48 logical pixels; every state carries a
// text label (never color alone); text scales to 1.3 without overflow.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/constants/brand_colors.dart';
import '../../../games/shared/icons/game_icons.dart';
import '../../../games/shared/models/game_invite.dart';
import '../../providers/chat_provider.dart';
import '../chat_ui_tokens.dart';

/// The one shared game-invite card. Rendered inside the message bubble
/// for active invites, and WITHOUT a bubble for terminal states
/// (message_bubble routes terminal invites here directly).
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

  /// Whether the current user is the invite sender (host never sees
  /// "Join" — they get Rejoin/Spectate or a status label).
  final bool isMe;

  /// The family id used for the Join/Rematch navigation route
  /// (`/family/<id>/<gameType>/lobby?join=<gameId>`). Null disables
  /// the action buttons.
  final String? routeFamilyId;

  /// D18 result card — optional score suffix (", 3 to 2"). Real
  /// message rows carry no numeric score (it lives in per-game
  /// tables); the UI gallery passes a sample score for demo purposes.
  final String? scoreLine;

  // ── Lifecycle state helpers (identical vocabulary to the old card) ──

  String get _status => message.gameInviteStatus ?? 'pending';

  bool get _isPreGame => _status == 'pending' || _status.isEmpty;

  bool get _isInProgress =>
      _status == 'in_progress' || _status == 'accepted' || _status == 'active';

  bool get _isCompleted => _status == 'completed';

  bool get _isExpired => _status == 'expired' || _status == 'cancelled';

  bool get _hasWinner {
    final w = message.gameWinnerName;
    return w != null && w.isNotEmpty;
  }

  /// Completed with a known winner -> the full result card (D18b).
  bool get _isResult => _isCompleted && _hasWinner;

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isResult) return _buildResultCard(context);
    if (_isCompleted || _isExpired) return _buildTerminalRow();
    return _buildActiveCard(context);
  }

  // ── D18a: Active (pending / live) — slim in-bubble card ───────────

  Widget _buildActiveCard(BuildContext context) {
    final rawGameType = message.gameType ?? '';
    final parsedGameType = GameTypeX.fromRouteSegment(rawGameType);
    final displayName =
        parsedGameType?.displayName ?? _titleCaseSegment(rawGameType);
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
            'Game invite: $displayName, $currentPlayers of $maxPlayers players.'
            '${action.label != null ? ' Action: ${action.label}.' : ''}',
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: ChatUi.chatCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: ChatUi.chatCardBorder,
              width: ChatUi.cardBorderWidth,
            ),
          ),
          child: Row(
            children: [
              // 40 dp game icon in accent.
              SizedBox(
                width: 40,
                height: 40,
                child: parsedGameType != null
                    ? GameIcon(gameId: rawGameType, size: 40)
                    : const Icon(
                        Icons.sports_esports,
                        size: 26,
                        color: ChatUi.accent,
                      ),
              ),
              const SizedBox(width: 10),
              // Title + players count (+ room code) — display title,
              // meta line in the body font (never monospace).
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ChatUi.titleText.copyWith(fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$currentPlayers/$maxPlayers players'
                      '${roomCode.isNotEmpty ? ' · $roomCode' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ChatUi.timeText.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (action.label != null) _buildOutlinedButton(context, action),
            ],
          ),
        ),
      ),
    );
  }

  // ── D18b: Result (completed + winner) — trophy + Rematch ───────────

  Widget _buildResultCard(BuildContext context) {
    final rawGameType = message.gameType ?? '';
    final parsedGameType = GameTypeX.fromRouteSegment(rawGameType);
    final displayName =
        parsedGameType?.displayName ?? _titleCaseSegment(rawGameType);
    final winnerName = message.gameWinnerName ?? '';
    final score = (scoreLine == null || scoreLine!.isEmpty)
        ? ''
        : ', $scoreLine';

    return RepaintBoundary(
      child: Semantics(
        container: true,
        label: 'Game result: $winnerName won $displayName$score.',
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: ChatUi.chatCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: ChatUi.chatCardBorder,
              width: ChatUi.cardBorderWidth,
            ),
          ),
          child: Row(
            children: [
              // Gold trophy.
              const SizedBox(
                width: 40,
                height: 40,
                child: Center(
                  child: Icon(
                    Icons.emoji_events,
                    size: 28,
                    color: KinrelColors.gold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$winnerName won $displayName$score',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: ChatUi.titleText.copyWith(fontSize: 14),
                ),
              ),
              const SizedBox(width: 8),
              _buildOutlinedButton(context, (
                label: 'Rematch',
                onTap:
                    (message.gameId ?? '').isNotEmpty && routeFamilyId != null
                    ? () => _goToLobby(context)
                    : null,
                urgent: false,
                enabled: true,
              )),
            ],
          ),
        ),
      ),
    );
  }

  // ── D18c: Terminal (expired / no winner) — quiet one-line row ──────

  Widget _buildTerminalRow() {
    final rawGameType = message.gameType ?? '';
    final parsedGameType = GameTypeX.fromRouteSegment(rawGameType);
    final displayName =
        parsedGameType?.displayName ?? _titleCaseSegment(rawGameType);
    final detail = _isCompleted ? 'Completed' : 'Expired';

    return Semantics(
      container: true,
      label: 'Game invite: $displayName, $detail.',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(
                _isCompleted
                    ? Icons.emoji_events_outlined
                    : Icons.sports_esports_outlined,
                size: 15,
                color: ChatUi.textMeta,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '$displayName · $detail',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ChatUi.timeText.copyWith(fontSize: 12.5),
                ),
              ),
              const SizedBox(width: 8),
              Text(message.formattedTime, style: ChatUi.timeText),
            ],
          ),
        ),
      ),
    );
  }

  // ── Buttons — outlined accent style (D18 gallery reference) ────────

  ({String? label, VoidCallback? onTap, bool urgent, bool enabled})
  _resolveAction({required BuildContext context, required bool isFull}) {
    final canNavigate =
        (message.gameId ?? '').isNotEmpty && routeFamilyId != null;
    if (_isPreGame && !isFull && !isMe) {
      return (
        label: 'Join',
        onTap: canNavigate ? () => _goToLobby(context) : null,
        urgent: false,
        enabled: true,
      );
    }
    if (_isPreGame && isFull && !isMe) {
      if (message.effectiveSpectatorsEnabled) {
        return (
          label: 'Spectate',
          onTap: canNavigate ? () => _goToLobby(context) : null,
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
          onTap: canNavigate ? () => _goToLobby(context) : null,
          urgent: true,
          enabled: true,
        );
      }
      if (message.effectiveSpectatorsEnabled) {
        return (
          label: 'Spectate',
          onTap: canNavigate ? () => _goToLobby(context) : null,
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

  /// Outlined accent button — transparent fill, accent border, accent
  /// label (matches the D18 reference cards). Disabled renders a flat
  /// chatReceived chip.
  Widget _buildOutlinedButton(
    BuildContext context,
    ({String? label, VoidCallback? onTap, bool urgent, bool enabled}) action,
  ) {
    final enabled = action.enabled && action.onTap != null;
    final label = action.label ?? '';
    return Semantics(
      label: label,
      button: true,
      child: SizedBox(
        // >= 48 logical pixel tap target.
        height: 48,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: action.onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: enabled ? ChatUi.accent : ChatUi.chatCardBorder,
                  width: 1,
                ),
              ),
              child: Text(
                label,
                style: ChatUi.menuText.copyWith(
                  color: enabled ? ChatUi.accent : ChatUi.textMeta,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Navigation (identical routes to the previous inline card) ──────

  /// Navigate into the game lobby. Same route for Join / Spectate /
  /// Rejoin / Rematch — the lobby decides what to do based on the
  /// game's current status + the user's participant status.
  void _goToLobby(BuildContext context) {
    final gameType = message.gameType ?? '';
    final gameId = message.gameId ?? '';
    final famId = routeFamilyId;
    if (gameType.isEmpty || gameId.isEmpty || famId == null) return;
    context.go('/family/$famId/$gameType/lobby?join=$gameId');
  }

  /// Title-case fallback for game types not in the GameType enum
  /// (e.g. 'somegame' -> 'Somegame', 'my-game' -> 'My Game').
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

/// Renders a run of 3+ consecutive expired/cancelled invites as ONE
/// quiet chatCard row. Tapping expands it back to one one-line row
/// per invite. Wired by ChatMessageList (which performs the run
/// detection — result cards never join a run).
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
          // ── The collapsed row (tap target >= 48px) ──────────────
          Semantics(
            label:
                '$count game invites, expired.'
                '${_expanded ? ' Collapse' : ' Expand'}',
            button: true,
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: ChatUi.chatCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: ChatUi.chatCardBorder,
                    width: ChatUi.cardBorderWidth,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.sports_esports_outlined,
                      size: 16,
                      color: ChatUi.textMeta,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$count game invites · expired',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ChatUi.pillText.copyWith(fontSize: 13),
                      ),
                    ),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 20,
                      color: ChatUi.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
          // ── Expanded: one one-line row per invite ───────────────
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

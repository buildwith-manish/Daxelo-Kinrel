// lib/features/chat/presentation/widgets/game_invite_card.dart
//
// DAXELO KINREL — v143/Step 2-7 — Unified compact game invitation
// card (direct chat + group chat).
//
// ONE card system used by BOTH chat types. Four visual forms:
//   • ACTIVE (pending / waiting / live): ~80 dp card with game tile,
//     title, player count + room code, action button, timestamp.
//   • RESULT (completed + winner): trophy + winner text + Rematch.
//   • TERMINAL (expired / completed-no-winner): 48 dp one-line row.
//   • COLLAPSED: 3+ consecutive terminal invites → one summary row.
//
// The ONLY difference between group and direct chat is the 3 dp left
// kinship band on the active card (group only). Pass `isGroup: true`
// and `kinshipColor` to show it.
//
// Tile color on received bubbles: uses [ChatUi.chatCardTile] (#191B2C)
// instead of the received bubble color so the tile never vanishes.
//
// Button states are resolved by the pure [resolveInviteAction] function
// (see game_invite_action.dart) so they can be unit tested.
//
// Run grouping is handled by the pure [groupChatItems] function (see
// game_invite_grouping.dart).

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/constants/brand_colors.dart';
import '../../../games/shared/icons/game_icons.dart';
import '../../../games/shared/models/game_invite.dart';
import '../../providers/chat_provider.dart';
import '../chat_ui_tokens.dart';
import 'game_invite_action.dart';

// ═══════════════════════════════════════════════════════════════════════
// GameInviteCard — the active card (~80 dp) + result card
// ═══════════════════════════════════════════════════════════════════════

/// The unified game-invite card. Renders as:
/// - An active card (~80 dp) for pending / in-progress invites.
/// - A result card for completed invites with a known winner.
/// - A terminal one-line row (48 dp) for expired / completed-no-winner.
///
/// For terminal rows, use [GameInviteLine] directly (this widget also
/// delegates to it when the state is terminal).
///
/// Parameters:
/// - [isGroup]: true for group chats (adds the 3 dp kinship band).
/// - [kinshipColor]: the sender's relationship color (group only).
///   Pass null for unresolved/extended relationships (falls back to
///   KinrelColors.nodeExtended). Ignored when [isGroup] is false.
class GameInviteCard extends StatelessWidget {
  const GameInviteCard({
    super.key,
    required this.message,
    required this.isMe,
    required this.routeFamilyId,
    this.isGroup = false,
    this.kinshipColor,
    this.scoreLine,
  });

  final ChatMessage message;
  final bool isMe;
  final String? routeFamilyId;
  final bool isGroup;
  final Color? kinshipColor;
  final String? scoreLine;

  // ── Lifecycle helpers ──────────────────────────────────────────────

  String get _status => message.gameInviteStatus ?? 'pending';

  bool get _isPreGame => _status == 'pending' || _status.isEmpty;

  bool get _isInProgress =>
      _status == 'in_progress' || _status == 'accepted' || _status == 'active';

  bool get _isCompleted => _status == 'completed';

  bool get _isExpired => _status == 'expired' || _status == 'cancelled';

  bool get _hasWinner =>
      (message.gameWinnerName ?? '').isNotEmpty;

  bool get _isResult => _isCompleted && _hasWinner;

  InviteStatus get _inviteStatus {
    if (_isPreGame) return InviteStatus.pending;
    if (_isInProgress) return InviteStatus.inProgress;
    if (_isCompleted) return InviteStatus.completed;
    if (_isExpired) {
      if (_status == 'cancelled') return InviteStatus.cancelled;
      return InviteStatus.expired;
    }
    return InviteStatus.unknown;
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isResult) return _buildResultCard(context);
    if (_isCompleted || _isExpired) return GameInviteLine(message: message);
    return _buildActiveCard(context);
  }

  // ── Active card (~80 dp) ───────────────────────────────────────────

  Widget _buildActiveCard(BuildContext context) {
    final rawGameType = message.gameType ?? '';
    final parsedGameType = GameTypeX.fromRouteSegment(rawGameType);
    final displayName =
        parsedGameType?.displayName ?? _titleCaseSegment(rawGameType);
    final maxPlayers = message.gameMaxPlayers ?? 2;
    final currentPlayers = message.gameCurrentPlayers ?? 1;
    final roomCode = (message.roomCode ?? '').trim();
    final isFull = currentPlayers >= maxPlayers;

    final action = resolveInviteAction(
      status: _inviteStatus,
      isMe: isMe,
      isFull: isFull,
      spectatorsEnabled: message.effectiveSpectatorsEnabled,
      isViewerPlayer: isMe, // simplified: host = viewer-player for now
      hasWinner: _hasWinner,
    );

    final canNavigate =
        (message.gameId ?? '').isNotEmpty && routeFamilyId != null;

    // Tile color: on received bubbles, use chatCardTile so the tile
    // doesn't vanish into the received bubble background. On sent
    // bubbles, keep the existing (game-specific) tile color.
    final tileColor = isMe ? null : ChatUi.chatCardTile;

    return RepaintBoundary(
      child: Semantics(
        container: true,
        label:
            'Game invite: $displayName, $currentPlayers of $maxPlayers players.'
            '${action.label != null ? ' Action: ${action.label}.' : ''}',
        child: _CardSurface(
          isGroup: isGroup,
          kinshipColor: kinshipColor,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                // 40×40 game tile, radius 8.
                _GameTile(
                  gameType: rawGameType,
                  parsedGameType: parsedGameType,
                  tileColor: tileColor,
                ),
                const SizedBox(width: 10),
                // Title + player count / room code.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
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
                        style: ChatUi.timeText.copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Action button (if any) + timestamp below.
                if (action.hasButton)
                  _ActionButton(
                    action: action,
                    canNavigate: canNavigate,
                    onTap: canNavigate ? () => _goToLobby(context) : null,
                  )
                else
                  // No button: show a spacer to keep height consistent.
                  const SizedBox(width: 48, height: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Result card ─────────────────────────────────────────────────────

  Widget _buildResultCard(BuildContext context) {
    final rawGameType = message.gameType ?? '';
    final parsedGameType = GameTypeX.fromRouteSegment(rawGameType);
    final displayName =
        parsedGameType?.displayName ?? _titleCaseSegment(rawGameType);
    final winnerName = message.gameWinnerName ?? '';
    // TODO(score): the message row does not store a numeric score.
    // When per-game tables expose a score, pass it as scoreLine
    // (e.g. ", 3 to 2") and it will be appended here.
    final score = (scoreLine == null || scoreLine!.isEmpty)
        ? ''
        : ', $scoreLine';

    return RepaintBoundary(
      child: Semantics(
        container: true,
        label: 'Game result: $winnerName won $displayName$score.',
        child: _CardSurface(
          isGroup: isGroup,
          kinshipColor: kinshipColor,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
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
                _ActionButton(
                  action: const GameInviteAction(
                      label: 'Rematch', enabled: true),
                  canNavigate:
                      (message.gameId ?? '').isNotEmpty &&
                          routeFamilyId != null,
                  onTap: (message.gameId ?? '').isNotEmpty &&
                          routeFamilyId != null
                      ? () => _goToLobby(context)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Navigation ──────────────────────────────────────────────────────

  void _goToLobby(BuildContext context) {
    final gameType = message.gameType ?? '';
    final gameId = message.gameId ?? '';
    final famId = routeFamilyId;
    if (gameType.isEmpty || gameId.isEmpty || famId == null) return;
    context.go('/family/$famId/$gameType/lobby?join=$gameId');
  }

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
// GameInviteLine — the 48 dp one-line terminal row
// ═══════════════════════════════════════════════════════════════════════

/// Compact 48 dp one-line row for expired / completed (no winner)
/// game invites. No card background, no button — just an icon, the
/// game name + status, and the timestamp.
class GameInviteLine extends StatelessWidget {
  const GameInviteLine({
    super.key,
    required this.message,
  });

  final ChatMessage message;

  bool get _isCompleted => (message.gameInviteStatus ?? '') == 'completed';

  @override
  Widget build(BuildContext context) {
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
// GameInviteRunTile — collapsed/expanded summary row
// ═══════════════════════════════════════════════════════════════════════

/// Renders a run of 3+ consecutive terminal invites as ONE collapsed
/// row. Tapping expands it to one [GameInviteLine] per invite.
/// Tapping again collapses it.
///
/// Header wording:
/// - All expired/cancelled → "N game invites · expired"
/// - Mixed expired + completed → "N game invites · finished"
class GameInviteRunTile extends StatefulWidget {
  const GameInviteRunTile({
    super.key,
    required this.messages,
    required this.isMe,
    required this.routeFamilyId,
    required this.allExpired,
  });

  final List<ChatMessage> messages;
  final bool isMe;
  final String? routeFamilyId;
  final bool allExpired;

  @override
  State<GameInviteRunTile> createState() => _GameInviteRunTileState();
}

class _GameInviteRunTileState extends State<GameInviteRunTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final count = widget.messages.length;
    final headerWord = widget.allExpired ? 'expired' : 'finished';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            label:
                '$count game invites, $headerWord.'
                '${_expanded ? ' Collapse' : ' Expand'}',
            button: true,
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                        '$count game invites · $headerWord',
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
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: widget.messages
                    .map((m) => GameInviteLine(message: m))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Private helpers — card surface, game tile, action button
// ═══════════════════════════════════════════════════════════════════════

/// Card surface with optional 3 dp kinship band on the left (group
/// chats only). The band is drawn inside the rounded clip.
class _CardSurface extends StatelessWidget {
  const _CardSurface({
    required this.isGroup,
    required this.kinshipColor,
    required this.child,
  });

  final bool isGroup;
  final Color? kinshipColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bandColor = isGroup
        ? (kinshipColor ?? KinrelColors.nodeExtended)
        : null;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: ChatUi.chatCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ChatUi.chatCardBorder,
          width: ChatUi.cardBorderWidth,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (bandColor != null)
                Container(width: ChatUi.bandWidth, color: bandColor),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// 40×40 game tile with corner radius 8 + game art at size 22.
class _GameTile extends StatelessWidget {
  const _GameTile({
    required this.gameType,
    required this.parsedGameType,
    this.tileColor,
  });

  final String gameType;
  final GameType? parsedGameType;
  final Color? tileColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: tileColor ?? ChatUi.chatCard,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: parsedGameType != null
            ? GameIcon(gameId: gameType, size: 22)
            : const Icon(
                Icons.sports_esports,
                size: 22,
                color: ChatUi.accent,
              ),
      ),
    );
  }
}

/// Outlined action button — transparent fill, accent border, 48 dp
/// tap target. Disabled renders dimmed + not tappable.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.action,
    required this.canNavigate,
    this.onTap,
  });

  final GameInviteAction action;
  final bool canNavigate;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final label = action.label ?? '';
    final enabled = action.enabled && onTap != null;

    return Semantics(
      label: label,
      button: true,
      enabled: enabled,
      child: SizedBox(
        height: 48,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: enabled ? onTap : null,
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
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Backward compatibility — the old CollapsedGameInvites class name is
// kept as a typedef so existing imports don't break during the
// transition. New code should use GameInviteRunTile directly.
typedef CollapsedGameInvites = GameInviteRunTile;

// lib/features/chat/presentation/widgets/game_invite_card.dart
//
// DAXELO KINREL — Shared Game Invite Card (Kin Thread / PR2 Task 5)
//
// ONE invite card used by BOTH chat types (group + direct). Extracted
// from the ~580-line inline builder in message_bubble.dart so no
// duplicate invite-card code exists anywhere.
//
// Layout rules (per the Kin Thread spec):
//   • ACTIVE invites (pending / waiting / live):
//       a slim card of ~100 logical pixels: 40px game icon, title,
//       players count (+ room code), and the Join / status button.
//   • EXPIRED or COMPLETED invites:
//       a one-line row (small icon, game name, status — or the winner
//       when known — and the time).
//   • Three or more consecutive expired/completed invites collapse
//     into one row "N game invites · expired" — see
//     [CollapsedGameInvites] (wired by ChatMessageList, which owns the
//     run detection).
//
// Status source is unchanged: the ChatMessage row's game columns
// (group + direct-group chats share the same lifecycle sync RPCs).
//
// Result card: the message row holds gameWinnerName but NO score
// (scores live only inside per-game tables; game_match_history has
// winnerNames but no numeric score). Per spec, the full
// "Papa won Tic-Tac-Toe, 3 to 2" + Rematch result card was therefore
// NOT built — completed invites show the winner line instead.
//
// Flat style: solid colors, no gradients/blur/shadows. Tap targets are
// at least 48 logical pixels; every state carries a text label (never
// color alone); text scales to 1.3 without overflow.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/constants/brand_colors.dart';
import '../../../../../core/constants/brand_typography.dart';
import '../../../games/shared/icons/game_icons.dart';
import '../../../games/shared/models/game_invite.dart';
import '../../providers/chat_provider.dart';

/// The one shared game-invite card. Rendered inside the message bubble.
class GameInviteCard extends StatelessWidget {
  const GameInviteCard({
    super.key,
    required this.message,
    required this.isMe,
    required this.routeFamilyId,
  });

  /// The invite message (gameType/gameId/roomCode/players/status/
  /// winnerName columns are parsed by ChatMessage.fromJson).
  final ChatMessage message;

  /// Whether the current user is the invite sender (host never sees
  /// "Join" — they get Rejoin/Spectate or a status label).
  final bool isMe;

  /// The family id used for the Join/Spectate navigation route
  /// (/family/<id>/<gameType>/lobby?join=<gameId>). Null disables the
  /// action buttons.
  final String? routeFamilyId;

  // ── Lifecycle state helpers (identical vocabulary to the old card) ──

  String get _status => message.gameInviteStatus ?? 'pending';

  bool get _isPreGame => _status == 'pending' || _status.isEmpty;

  bool get _isInProgress =>
      _status == 'in_progress' || _status == 'accepted' || _status == 'active';

  bool get _isCompleted => _status == 'completed';

  bool get _isExpired => _status == 'expired' || _status == 'cancelled';

  bool get _isTerminal => _isCompleted || _isExpired;

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isTerminal) {
      return _buildTerminalRow();
    }
    return _buildActiveCard(context);
  }

  // ── Active (pending / live): slim card ─────────────────────────────

  Widget _buildActiveCard(BuildContext context) {
    final rawGameType = message.gameType ?? '';
    final parsedGameType = GameTypeX.fromRouteSegment(rawGameType);
    final displayName =
        parsedGameType?.displayName ?? _titleCaseSegment(rawGameType);
    final maxPlayers = message.gameMaxPlayers ?? 2;
    final currentPlayers = message.gameCurrentPlayers ?? 1;
    final roomCode = (message.roomCode ?? '').trim();
    final isFull = currentPlayers >= maxPlayers;

    // Action button resolution — unchanged from the previous inline
    // card (Join / Spectate / Full / In Game / Rejoin).
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
            color: KinrelColors.orange.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: KinrelColors.orange.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              // 40px game icon
              SizedBox(
                width: 40,
                height: 40,
                child: parsedGameType != null
                    ? GameIcon(gameId: rawGameType, size: 40)
                    : const Icon(Icons.sports_esports,
                        size: 26, color: KinrelColors.orange),
              ),
              const SizedBox(width: 10),
              // Title + players count (+ room code)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: KinrelColors.textWhite,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$currentPlayers/$maxPlayers players'
                      '${roomCode.isNotEmpty ? ' • $roomCode' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: KinrelColors.textSilver,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (action.label != null) _buildActionButton(context, action),
            ],
          ),
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

  Widget _buildActionButton(
    BuildContext context,
    ({String? label, VoidCallback? onTap, bool urgent, bool enabled}) action,
  ) {
    final enabled = action.enabled && action.onTap != null;
    return SizedBox(
      // ≥48 logical pixel tap target.
      height: 48,
      child: Material(
        color: enabled
            ? (action.urgent
                ? KinrelColors.orange.withValues(alpha: 0.15)
                : KinrelColors.orange)
            : KinrelColors.darkElevated,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: action.onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (enabled && action.urgent) ...[
                    Icon(
                      isMe ? Icons.replay : Icons.visibility_outlined,
                      size: 14,
                      color: KinrelColors.orange,
                    ),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    action.label!,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: enabled
                          ? (action.urgent
                              ? KinrelColors.orange
                              : KinrelColors.textWhite)
                          : KinrelColors.textDim,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Terminal (expired / completed): one-line row ───────────────────

  Widget _buildTerminalRow() {
    final rawGameType = message.gameType ?? '';
    final parsedGameType = GameTypeX.fromRouteSegment(rawGameType);
    final displayName =
        parsedGameType?.displayName ?? _titleCaseSegment(rawGameType);
    final winnerName = message.gameWinnerName;
    // Completed + winner → "Tic-Tac-Toe · Papa won" (no score is stored
    // on the message row, so the numeric result card is not built).
    final detail = _isCompleted
        ? (winnerName != null && winnerName.isNotEmpty
            ? '$winnerName won'
            : 'Completed')
        : 'Expired';

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
                _isCompleted ? Icons.emoji_events_outlined : Icons.event_busy,
                size: 15,
                color: KinrelColors.textDim,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '$displayName · $detail',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.textDim,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                message.formattedTime,
                style: const TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 10.5,
                  color: KinrelColors.textDim,
                  letterSpacing: 0.3,
                ),
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

/// Renders a run of 3+ consecutive expired/completed invites as ONE
/// quiet row. Tapping expands it back to one one-line row per invite.
/// Wired by ChatMessageList (which performs the run detection).
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
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: KinrelColors.darkSurface.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.07),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.sports_esports_outlined,
                      size: 16,
                      color: KinrelColors.textDim,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$count game invites · expired',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: KinrelColors.textDim,
                        ),
                      ),
                    ),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 20,
                      color: KinrelColors.textSilver,
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

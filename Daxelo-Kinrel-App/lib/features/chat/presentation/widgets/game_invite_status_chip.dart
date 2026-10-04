// lib/features/chat/presentation/widgets/game_invite_status_chip.dart
//
// DAXELO KINREL — Unified game-invite status chip
//
// Replaces the inconsistent per-card-type status text styling
// (plain Text widgets with hand-rolled colors + leading icons) with a
// single reusable chip component. A user scrolling quickly through
// chat can now identify room status by COLOR at a glance without
// reading each line of text.
//
// Color semantics (per Phase 7 spec):
//   • GREEN / success accent — room is joinable AND has activity
//     (1 < currentPlayers < maxPlayers, status == 'pending')
//   • AMBER / warning accent — room created but not yet full
//     (currentPlayers <= 1, status == 'pending') — i.e. just the host,
//     "Waiting for players…"
//   • GREY / neutral accent — room is FULL
//     (currentPlayers >= maxPlayers, status == 'pending')
//   • DARK / muted accent — game lifecycle ended
//     (status == 'accepted' | 'expired' | 'cancelled') — the room is
//     no longer in the "pending" lobby state.
//
// The chip is rendered ABOVE the Join button on every game-invite
// card (sender + recipient), replacing the old sender-only status row.
// The Join button's strong visual treatment (solid orange when joinable,
// flat/muted when not) is preserved unchanged — only the status TEXT
// above it gets the new chip treatment.

import 'package:flutter/material.dart';

import '../../../../../core/constants/brand_colors.dart';
import '../../../../../core/constants/brand_spacing.dart';
import '../../../../../core/constants/brand_typography.dart';
import '../../providers/chat_provider.dart';

/// The visual category a game-invite card falls into, derived from
/// [ChatMessage] fields. Exposed publicly so widget tests can verify
/// the categorization logic without having to render the chip.
enum GameInviteStatusKind {
  /// Room was just created, only the host is in — "Waiting for players".
  waitingForPlayers,

  /// Room has activity (some players joined) and is still joinable.
  openToJoin,

  /// Room is at capacity — "Room full".
  full,

  /// Game has started — "Game started".
  started,

  /// Game has ended (expired or cancelled) — "Game ended".
  ended,
}

/// The result of categorizing a [ChatMessage] game-invite card.
///
/// Carries the [kind] (which drives the chip color) plus a short
/// human-readable [label] suitable for display in the chip body.
class GameInviteStatusClassification {
  const GameInviteStatusClassification({
    required this.kind,
    required this.label,
  });

  final GameInviteStatusKind kind;
  final String label;
}

/// Categorize a game-invite [message] into a status kind + label.
///
/// Pure function — no widget/context dependency — so it's trivially
/// unit-testable. This is the SINGLE source of truth for status-chip
/// styling across all game-invite card types (SOS, Bingo, Prediction
/// Battle, and any future game types that reuse the chat card pattern).
GameInviteStatusClassification classifyGameInviteStatus(
  ChatMessage message,
) {
  final status = message.gameInviteStatus ?? 'pending';
  final maxPlayers = message.gameMaxPlayers ?? 2;
  final currentPlayers = message.gameCurrentPlayers ?? 1;
  final isFull = currentPlayers >= maxPlayers;

  if (status == 'accepted') {
    return const GameInviteStatusClassification(
      kind: GameInviteStatusKind.started,
      label: 'Game started',
    );
  }
  if (status == 'expired' || status == 'cancelled') {
    return const GameInviteStatusClassification(
      kind: GameInviteStatusKind.ended,
      label: 'Game ended',
    );
  }
  // status == 'pending' (or null treated as pending)
  if (isFull) {
    return const GameInviteStatusClassification(
      kind: GameInviteStatusKind.full,
      label: 'Room full',
    );
  }
  if (currentPlayers <= 1) {
    return const GameInviteStatusClassification(
      kind: GameInviteStatusKind.waitingForPlayers,
      label: 'Waiting for players…',
    );
  }
  return const GameInviteStatusClassification(
    kind: GameInviteStatusKind.openToJoin,
    label: 'Open to join',
  );
}

/// A small pill chip that renders the game-invite room status with a
/// consistent color-coded treatment.
///
/// Construct via [GameInviteStatusChip.forMessage] in production code,
/// or via the default constructor with an explicit [kind] + [label]
/// in tests.
class GameInviteStatusChip extends StatelessWidget {
  const GameInviteStatusChip({
    super.key,
    required this.kind,
    required this.label,
    this.compact = false,
  });

  /// Build a chip reflecting the status of [message]. This is the
  /// canonical entry point used by every game-invite card variant.
  factory GameInviteStatusChip.forMessage(ChatMessage message) {
    final c = classifyGameInviteStatus(message);
    return GameInviteStatusChip(kind: c.kind, label: c.label);
  }

  /// The status category — drives the chip's color treatment.
  final GameInviteStatusKind kind;

  /// The human-readable status text shown inside the chip.
  final String label;

  /// When true, renders a tighter chip (smaller padding + 10px font)
  /// for use inside dense rows. Defaults to false (12.5px font, standard
  /// pill padding) which matches the existing sender status row's
  /// visual weight so the migration is pixel-neutral.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (accent, bgAlpha, borderAlpha, iconData) = _styleFor(kind);
    final fontSize = compact ? 10.0 : 12.5;
    final iconSize = compact ? 11.0 : 14.0;
    final vPad = compact ? 2.5 : 4.0;
    final hPad = compact ? 7.0 : 10.0;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: bgAlpha),
        borderRadius: BorderRadius.circular(KinrelRadius.xs),
        border: Border.all(
          color: accent.withValues(alpha: borderAlpha),
          width: 0.75,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconData, size: iconSize, color: accent),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                color: accent,
                letterSpacing: 0.1,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Resolve the visual treatment for each status kind.
  ///
  /// Returns a record of:
  ///   (accentColor, backgroundAlpha, borderAlpha, leadingIcon)
  ///
  /// The accent color is the FULL color — the chip applies it with
  /// [bgAlpha] for the fill and [borderAlpha] for the hairline border,
  /// producing a soft tinted-pill look that matches the existing room-
  /// code chip's visual language (orange @ 12% bg + 30% border).
  static (
    Color accent,
    double bgAlpha,
    double borderAlpha,
    IconData icon,
  ) _styleFor(GameInviteStatusKind kind) {
    switch (kind) {
      case GameInviteStatusKind.waitingForPlayers:
        // Amber: room created, no one joined yet — "Waiting for players…"
        return (
          KinrelColors.warning,
          0.12,
          0.30,
          Icons.hourglass_top,
        );
      case GameInviteStatusKind.openToJoin:
        // Green: room has activity and is still joinable — "Open to join"
        return (
          KinrelColors.success,
          0.12,
          0.30,
          Icons.check_circle_outline,
        );
      case GameInviteStatusKind.full:
        // Grey: room is at capacity — "Room full"
        return (
          KinrelColors.textSilver,
          0.10,
          0.25,
          Icons.lock_outline,
        );
      case GameInviteStatusKind.started:
        // Dark ember: game has started — "Game started"
        return (
          KinrelColors.ember,
          0.14,
          0.32,
          Icons.play_circle_outline,
        );
      case GameInviteStatusKind.ended:
        // Muted: game ended (expired or cancelled) — "Game ended"
        return (
          KinrelColors.textDim,
          0.10,
          0.25,
          Icons.event_busy,
        );
    }
  }
}

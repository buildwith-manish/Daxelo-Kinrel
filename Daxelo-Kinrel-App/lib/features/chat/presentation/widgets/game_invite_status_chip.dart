// lib/features/chat/presentation/widgets/game_invite_status_chip.dart
//
// DAXELO KINREL — Unified game-invite status chip (5-state lifecycle)
//
// Replaces the prior 3-state chip (waitingForPlayers / openToJoin / full /
// started / ended) with a complete 5-state lifecycle state machine:
//
//     waiting → full → inProgress → completed
//                                ↘ expired
//
// Each state has distinct card styling + status chip treatment:
//
//   • waitingForPlayers (amber)  — room created, not yet full (lobby)
//   • openToJoin (green)        — room has activity, still joinable
//   • full (grey)                — capacity reached, transitional (will
//                                   progress to inProgress or expired)
//   • inProgress (PULSING green) — game started, "LIVE NOW" treatment
//                                   matching the Prediction Battle card's
//                                   badge styling elsewhere in the app
//   • completed (muted)          — game finished normally, with optional
//                                   privacy-gated winner name
//   • expired (greyed)           — room never filled / never started in time
//                                   OR host cancelled
//
// The chip is rendered ABOVE the action button on every game-invite card
// (sender + recipient). The action button's treatment depends on state:
//   • waitingForPlayers / openToJoin → "Join" (solid orange)
//   • full                            → "Full" (disabled)
//   • inProgress                      → "Watch" / "Rejoin" (spectator-style)
//   • completed / expired             → static label, no button
//
// Legacy status values ('accepted' = pre-state-machine alias for
// in_progress, 'cancelled' = alias for expired) are mapped to the
// canonical kinds by the classifier.

import 'package:flutter/material.dart';

import '../../../../../core/constants/brand_colors.dart';
import '../../../../../core/constants/brand_spacing.dart';
import '../../../../../core/constants/brand_typography.dart';
import '../../providers/chat_provider.dart';

/// The visual category a game-invite card falls into, derived from
/// [ChatMessage] fields. Exposed publicly so widget tests can verify
/// the categorization logic without having to render the chip.
///
/// 5-state lifecycle (canonical):
///   • waitingForPlayers (amber)
///   • openToJoin (green)
///   • full (grey)
///   • inProgress (pulsing green — LIVE NOW treatment)
///   • completed (muted)
///   • expired (greyed)
///
/// Legacy aliases (handled by the classifier):
///   • 'accepted' (pre-state-machine) → inProgress
///   • 'cancelled' (host cancel)      → expired
enum GameInviteStatusKind {
  /// Room was just created, only the host is in — "Waiting for players".
  waitingForPlayers,

  /// Room has activity (some players joined) and is still joinable.
  openToJoin,

  /// Room is at capacity — "Room full". TRANSITIONAL state — will
  /// progress to inProgress (host starts the game) or expired (host
  /// doesn't start within the full-state expiry window).
  full,

  /// Game has started — "LIVE NOW". Players are actively playing.
  /// Distinct from the prior merged 'started' kind: this gets a pulsing
  /// accent treatment to signal "live now," consistent with the
  /// Prediction Battle card's badge styling elsewhere in the app.
  inProgress,

  /// Game finished normally (winner determined). Muted/settled visual
  /// treatment — not alarming, just "this is done." May optionally
  /// show the winner name (privacy-gated to participants only).
  completed,

  /// Room expired (never filled / never started in time) OR host cancelled.
  /// Greyed out, clearly inactive. Card is NOT tappable/joinable.
  expired,
}

/// The result of categorizing a [ChatMessage] game-invite card.
///
/// Carries the [kind] (which drives the chip color + animation) plus a
/// short human-readable [label] suitable for display in the chip body.
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
///
/// State mapping (per the 5-state lifecycle spec):
///   • gameInviteStatus == null or 'pending':
///       - currentPlayers >= maxPlayers → full ("Room full")
///       - currentPlayers <= 1          → waitingForPlayers ("Waiting for players")
///       - 1 < currentPlayers < max     → openToJoin ("X spots left")
///   • gameInviteStatus == 'in_progress' or legacy 'accepted'/'active':
///       → inProgress ("LIVE NOW")
///   • gameInviteStatus == 'completed':
///       → completed ("Completed" + optional winner)
///   • gameInviteStatus == 'expired' or 'cancelled':
///       → expired ("Expired" / "Cancelled")
///
/// The openToJoin label is dynamic — it surfaces the explicit slot count
/// ("3 spots left" / "2 spots left" / "1 spot left") per the user-facing
/// spec, instead of a generic "Open to join". This makes the chip itself
/// informative without forcing the user to do mental arithmetic on the
/// "current/max players" line above.
GameInviteStatusClassification classifyGameInviteStatus(
  ChatMessage message,
) {
  final status = message.gameInviteStatus ?? 'pending';
  final maxPlayers = message.gameMaxPlayers ?? 2;
  final currentPlayers = message.gameCurrentPlayers ?? 1;
  final isFull = currentPlayers >= maxPlayers;

  // ── In-progress: legacy 'accepted' (pre-state-machine) maps here ──
  // The prior chat-smoothness work treated 'accepted' as 'started'; the
  // 5-state model renames 'started' → 'inProgress' with a new pulsing
  // treatment. Legacy rows with 'accepted' continue to render correctly.
  if (status == 'in_progress' ||
      status == 'accepted' ||
      status == 'active') {
    return const GameInviteStatusClassification(
      kind: GameInviteStatusKind.inProgress,
      label: 'LIVE NOW',
    );
  }

  // ── Completed: game finished normally ──
  // Winner name is privacy-gated server-side (gameWinnerName is null for
  // non-participants). The chip itself just shows "Completed"; the
  // winner name (if present) is rendered as a separate line below the
  // chip by the card renderer.
  if (status == 'completed') {
    return const GameInviteStatusClassification(
      kind: GameInviteStatusKind.completed,
      label: 'Completed',
    );
  }

  // ── Expired: room never filled OR host cancelled ──
  // Both 'expired' (sweep-driven) and 'cancelled' (host-driven) render
  // the same "inactive" treatment per the spec.
  if (status == 'expired' || status == 'cancelled') {
    return GameInviteStatusClassification(
      kind: GameInviteStatusKind.expired,
      label: status == 'cancelled' ? 'Cancelled' : 'Expired',
    );
  }

  // ── Pre-game: 'pending' (or null treated as pending) ──
  // Sub-classify by capacity: waiting vs. open-to-join vs. full.
  if (isFull) {
    return const GameInviteStatusClassification(
      kind: GameInviteStatusKind.full,
      label: 'Room full',
    );
  }
  if (currentPlayers <= 1) {
    return const GameInviteStatusClassification(
      kind: GameInviteStatusKind.waitingForPlayers,
      label: 'Waiting for players',
    );
  }
  // openToJoin: surface the explicit remaining-slot count per spec.
  // e.g. "3 spots left" / "2 spots left" / "1 spot left".
  final spots = maxPlayers - currentPlayers;
  return GameInviteStatusClassification(
    kind: GameInviteStatusKind.openToJoin,
    label: '$spots spot${spots == 1 ? '' : 's'} left',
  );
}

/// A small pill chip that renders the game-invite room status with a
/// consistent color-coded treatment.
///
/// For the [GameInviteStatusKind.inProgress] kind, the chip renders with
/// a PULSING animation (subtle opacity oscillation) to signal "live now,"
/// matching the existing LIVE NOW badge styling on the Prediction Battle
/// card. All other kinds render statically.
///
/// Construct via [GameInviteStatusChip.forMessage] in production code,
/// or via the default constructor with an explicit [kind] + [label]
/// in tests.
class GameInviteStatusChip extends StatefulWidget {
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

  /// The status category — drives the chip's color + animation treatment.
  final GameInviteStatusKind kind;

  /// The human-readable status text shown inside the chip.
  final String label;

  /// When true, renders a tighter chip (smaller padding + 10px font)
  /// for use inside dense rows. Defaults to false (12.5px font, standard
  /// pill padding) which matches the existing sender status row's
  /// visual weight so the migration is pixel-neutral.
  final bool compact;

  @override
  State<GameInviteStatusChip> createState() => _GameInviteStatusChipState();
}

class _GameInviteStatusChipState extends State<GameInviteStatusChip>
    with TickerProviderStateMixin {
  // ── Pulsing animation for the inProgress state ──────────────────
  // Matches the "LIVE NOW" badge styling on the Prediction Battle card
  // (lib/features/prediction_battle_v1/pb_v1_card.dart _StatusPill),
  // but adds a subtle pulsing animation since this chip signals an
  // actively-running game.
  //
  // The Prediction Battle _StatusPill is static (no animation); the
  // pulsing here is a deliberate enhancement per the spec ("a pulsing/
  // animated indicator or a solid accent color signaling 'live now'").
  AnimationController? _pulseController;
  Animation<double>? _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _setupPulseIfNeeded();
  }

  @override
  void didUpdateWidget(GameInviteStatusChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind) {
      _setupPulseIfNeeded();
    }
  }

  void _setupPulseIfNeeded() {
    final needsPulse = widget.kind == GameInviteStatusKind.inProgress;
    if (needsPulse && _pulseController == null) {
      _pulseController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1400),
      )..repeat(reverse: true);
      _pulseAnimation = Tween<double>(begin: 0.55, end: 1.0).animate(
        CurvedAnimation(
          parent: _pulseController!,
          curve: Curves.easeInOut,
        ),
      );
    } else if (!needsPulse && _pulseController != null) {
      _pulseController!.stop();
      _pulseController!.dispose();
      _pulseController = null;
      _pulseAnimation = null;
    }
  }

  @override
  void dispose() {
    _pulseController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (accent, bgAlpha, borderAlpha, iconData) = _styleFor(widget.kind);
    final fontSize = widget.compact ? 10.0 : 12.5;
    final iconSize = widget.compact ? 11.0 : 14.0;
    final vPad = widget.compact ? 2.5 : 4.0;
    final hPad = widget.compact ? 7.0 : 10.0;

    // For inProgress, render with a pulsing background alpha so the chip
    // "breathes" — a subtle visual signal that the game is actively running.
    // For all other kinds, render statically.
    if (widget.kind == GameInviteStatusKind.inProgress &&
        _pulseAnimation != null) {
      return AnimatedBuilder(
        animation: _pulseAnimation!,
        builder: (context, child) {
          // Pulse the background alpha between 0.10 and 0.20 (subtle).
          final pulseAlpha = bgAlpha * 0.7 + (bgAlpha * 0.6) * _pulseAnimation!.value;
          return Container(
            padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: pulseAlpha.clamp(0.0, 1.0)),
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
                    widget.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: fontSize - 0.5, // mono badge feels right slightly tighter
                      fontWeight: FontWeight.w800,
                      color: accent,
                      letterSpacing: 0.6,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

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
              widget.label,
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
      case GameInviteStatusKind.inProgress:
        // GREEN PULSING: game has started — "LIVE NOW"
        // Uses the success green accent (matching the Prediction Battle
        // card's _StatusPill LIVE NOW treatment), but with a pulsing
        // animation overlaid by the chip's _GameInviteStatusChipState
        // (see build() above).
        return (
          KinrelColors.success,
          0.16,  // slightly higher base alpha so the pulse is visible
          0.40,
          Icons.sensors,  // a "live" / activity icon
        );
      case GameInviteStatusKind.completed:
        // Muted: game finished normally — "Completed"
        // Settled, not alarming. Slightly dimmer than the full-state
        // grey to signal "this is done, not active".
        return (
          KinrelColors.textSilver,
          0.08,
          0.20,
          Icons.emoji_events_outlined,  // trophy icon for "completed"
        );
      case GameInviteStatusKind.expired:
        // Greyed: room expired or was cancelled — "Expired" / "Cancelled"
        // Clearly inactive. Even dimmer than completed to signal
        // "this room is dead, don't try to interact with it".
        return (
          KinrelColors.textDim,
          0.06,
          0.15,
          Icons.event_busy,
        );
    }
  }
}

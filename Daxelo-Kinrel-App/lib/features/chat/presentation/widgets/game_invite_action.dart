// lib/features/chat/presentation/widgets/game_invite_action.dart
//
// DAXELO KINREL — v143/Step 4 — Pure button-state resolver for game
// invite cards.
//
// Extracted from GameInviteCard._resolveAction so it can be unit
// tested without pumping widgets. Takes the invite state, the
// viewer's role, and the room settings — returns a label, an enabled
// flag, and an optional dimmed flag.
//
// Rules (per implementation brief Step 4):
//   • Waiting + joinable, received invite → "Join" (enabled).
//   • Own waiting invite (you sent it) → no button (null label).
//   • Full + spectators on → "Spectate" (enabled).
//   • Full + spectators off → "Full" (disabled, dimmed).
//   • In progress + viewer is player → "Rejoin" (enabled).
//   • In progress + viewer not player + spectators on → "Spectate" (enabled).
//   • In progress + viewer not player + spectators off → "In Game" (disabled, dimmed).
//   • Finished with winner → no button (the result card is shown instead).
//   • Expired/completed → no button (the one-line row is shown instead).

/// The resolved action for a game invite card.
///
/// [label] is null when no button should be rendered (e.g. own waiting
/// invite, or terminal state). [enabled] is false for "Full" and
/// "In Game" — the button still renders but is dimmed and not tappable.
/// [urgent] is true for in-progress actions (Rejoin/Spectate) to
/// distinguish them from pre-game actions visually if needed.
class GameInviteAction {
  const GameInviteAction({
    this.label,
    this.enabled = true,
    this.urgent = false,
  });

  /// The button text (e.g. "Join", "Spectate", "Full", "Rejoin",
  /// "In Game"). Null means no button is rendered.
  final String? label;

  /// Whether the button is tappable. False for "Full" and "In Game"
  /// (dimmed, not tappable). True for "Join", "Spectate", "Rejoin".
  final bool enabled;

  /// Whether this is an urgent (in-progress) action. Used by the
  /// widget to optionally style the button differently.
  final bool urgent;

  /// Whether a button should be rendered at all.
  bool get hasButton => label != null;

  @override
  String toString() =>
      'GameInviteAction(label: $label, enabled: $enabled, urgent: $urgent)';
}

/// The invite's lifecycle status (mirrors ChatMessage.gameInviteStatus
/// values without depending on the model).
enum InviteStatus {
  pending,
  inProgress,
  completed,
  expired,
  cancelled,
  unknown,
}

/// Resolve the action button for a game invite.
///
/// Parameters:
/// - [status]: the invite's lifecycle status.
/// - [isMe]: whether the viewer is the invite sender (host).
/// - [isFull]: whether all player slots are taken.
/// - [spectatorsEnabled]: whether the room allows spectators.
/// - [isViewerPlayer]: whether the viewer is one of the game's
///   participants (relevant for in-progress games).
/// - [hasWinner]: whether the game finished with a known winner
///   (only relevant for completed status — triggers the result card).
///
/// Returns a [GameInviteAction] with the label, enabled flag, and
/// urgent flag. Returns a no-button action (null label) for:
/// - Own waiting invites (the sender's status is conveyed by the
///   player count line).
/// - Completed with winner (the result card is shown instead).
/// - Expired/cancelled (the one-line row is shown instead).
GameInviteAction resolveInviteAction({
  required InviteStatus status,
  required bool isMe,
  required bool isFull,
  required bool spectatorsEnabled,
  required bool isViewerPlayer,
  bool hasWinner = false,
}) {
  switch (status) {
    case InviteStatus.pending:
      // Pre-game: waiting for players.
      if (isMe) {
        // Sender's own waiting invite: no button (status is conveyed
        // by the player count line). Keep card height consistent.
        return const GameInviteAction(label: null);
      }
      if (!isFull) {
        // Waiting + joinable, received invite.
        return const GameInviteAction(label: 'Join', enabled: true);
      }
      // Full: spectators on → Spectate, off → Full (disabled).
      if (spectatorsEnabled) {
        return const GameInviteAction(label: 'Spectate', enabled: true);
      }
      return const GameInviteAction(
          label: 'Full', enabled: false);
    case InviteStatus.inProgress:
      // In-progress game.
      if (isViewerPlayer || isMe) {
        // Viewer is a player → Rejoin.
        return const GameInviteAction(
            label: 'Rejoin', enabled: true, urgent: true);
      }
      // Viewer is not a player.
      if (spectatorsEnabled) {
        return const GameInviteAction(
            label: 'Spectate', enabled: true, urgent: true);
      }
      return const GameInviteAction(
          label: 'In Game', enabled: false);
    case InviteStatus.completed:
      if (hasWinner) {
        // Result card is shown instead — no active button.
        return const GameInviteAction(label: null);
      }
      // Completed without winner → one-line row (no button).
      return const GameInviteAction(label: null);
    case InviteStatus.expired:
    case InviteStatus.cancelled:
      // Terminal → one-line row (no button).
      return const GameInviteAction(label: null);
    case InviteStatus.unknown:
      return const GameInviteAction(label: null);
  }
}

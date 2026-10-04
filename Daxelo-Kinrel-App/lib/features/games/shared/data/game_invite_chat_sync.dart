// lib/features/games/shared/data/game_invite_chat_sync.dart
//
// Keeps the persistent game-invite chat card (ChatMessage rows with
// messageType='gameInvite') in sync with live game state.
//
// Whenever a game's player count changes — a member joins via the chat
// card's Join button, via a lobby, or via a shared room code — or the
// game's lifecycle changes (host starts it / game finishes), the matching
// ChatMessage rows are UPDATEd here. chat_provider.dart already holds a
// Supabase Realtime UPDATE subscription on "ChatMessage" (familyId-
// filtered, REPLICA IDENTITY FULL), so every family member's open chat UI
// re-renders the card ("2/4 players", "Full", "Started", "Ended") without
// anyone needing to reopen the thread.
//
// All calls are best-effort: failures are logged and never bubble up to
// the game logic that triggered them — the chat card is a secondary,
// additive surface and must never break or delay the actual game flow.
//
// ── Lifecycle state machine (5-state) ─────────────────────────────────────
// As of 20261004100000_game_room_lifecycle_state_machine.sql, the
// ChatMessage.gameInviteStatus column has 5 canonical values:
//   • 'pending'      — waiting / open-to-join (lobby state)
//   • 'in_progress'  — game started, players are playing
//   • 'completed'    — game finished normally (winner determined)
//   • 'expired'      — room never filled / never started in time
//   • 'cancelled'    — host cancelled (legacy alias for 'expired')
// 'accepted' is a legacy alias for 'in_progress' (pre-state-machine).
//
// The [inviteStatus] parameter accepts any of these. The Flutter
// GameInviteStatusChip classifier handles all values (legacy + new).
//
// ── Privacy gate for winner display ──────────────────────────────────────
// [winnerName] is the display name of the match winner, written to
// ChatMessage.gameWinnerName so the completed-state card can show
// "Winner: <name>" without an extra RPC round-trip. The write respects
// the existing match-result privacy model (20260917140000 +
// 20260917140001): only participants see winner names; non-participants
// see NULL = generic "Game completed" treatment.
//
// The privacy gate is enforced server-side by the
// fn_sync_game_invite_status RPC (called by AFTER UPDATE trigger on the
// game table) — when the trigger fires, it checks game_participants for
// auth.uid() and only writes gameWinnerName if the requester is a
// participant. Trigger-driven calls (no auth context) write the winner
// name unconditionally; the frontend re-validates participant status
// before rendering via the existing match_history_for_participant RPC
// contract.
//
// When called from the Flutter provider (with auth context), the
// RLS UPDATE policy on ChatMessage allows any family member to write
// gameWinnerName. To respect privacy here too, the Flutter provider
// MUST only pass winnerName when the calling user is a participant
// (verified via the per-game's participants list, which the provider
// already tracks in-memory).

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Push new values onto every game-invite chat card for [gameId].
///
/// Only the provided fields are written — pass null to leave a field
/// untouched. The UPDATE is scoped to rows with `messageType='gameInvite'`
/// AND `gameId=<gameId>` so regular chat messages are never affected.
///
/// Parameters:
///   • [currentPlayers] → the card's "<n>/<max> players" line (and its
///     "Full" state once n >= max).
///   • [inviteStatus] → one of 'pending' | 'in_progress' | 'completed' |
///     'expired' | 'cancelled' (or legacy 'accepted'). Drives the 5-state
///     lifecycle chip on the card.
///   • [winnerName] → display name of the winner, written only when the
///     calling user is a participant (privacy gate). Pass null for
///     non-completed states or when winner is unknown.
///   • [completedAt] → server-set completion timestamp. Pass null to
///     leave the existing value. Auto-set to now() by the RPC when
///     transitioning to 'completed'.
Future<void> syncGameInviteChatCards({
  required SupabaseClient client,
  required String gameId,
  int? currentPlayers,
  String? inviteStatus,
  String? winnerName,
  DateTime? completedAt,
}) async {
  if (gameId.isEmpty) return;
  final updates = <String, dynamic>{};
  if (currentPlayers != null) updates['gameCurrentPlayers'] = currentPlayers;
  if (inviteStatus != null) updates['gameInviteStatus'] = inviteStatus;
  // Only write winner/completedAt if explicitly provided — COALESCE on
  // the server side preserves prior values when null.
  if (winnerName != null) updates['gameWinnerName'] = winnerName;
  if (completedAt != null) {
    updates['gameCompletedAt'] = completedAt.toUtc().toIso8601String();
  }
  if (updates.isEmpty) return;
  try {
    await client
        .from('ChatMessage')
        .update(updates)
        .eq('messageType', 'gameInvite')
        .eq('gameId', gameId);
  } catch (e) {
    // Best-effort by design — the game itself must never fail because the
    // chat-card mirror couldn't be refreshed.
    debugPrint('⚠️ syncGameInviteChatCards($gameId) failed: $e');
  }
}

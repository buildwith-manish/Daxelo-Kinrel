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

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Push new values onto every game-invite chat card for [gameId].
///
/// Only the provided fields are written — pass null to leave a field
/// untouched. The UPDATE is scoped to rows with `messageType='gameInvite'`
/// AND `gameId=<gameId>` so regular chat messages are never affected.
///
/// [currentPlayers] → the card's "<n>/<max> players" line (and its "Full"
/// state once n >= max). [inviteStatus] → 'pending' | 'accepted' (renders
/// "Started") | 'expired' | 'cancelled' (both render "Ended").
Future<void> syncGameInviteChatCards({
  required SupabaseClient client,
  required String gameId,
  int? currentPlayers,
  String? inviteStatus,
}) async {
  if (gameId.isEmpty) return;
  final updates = <String, dynamic>{};
  if (currentPlayers != null) updates['gameCurrentPlayers'] = currentPlayers;
  if (inviteStatus != null) updates['gameInviteStatus'] = inviteStatus;
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

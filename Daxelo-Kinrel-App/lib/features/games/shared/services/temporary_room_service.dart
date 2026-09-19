// lib/features/games/shared/services/temporary_room_service.dart
//
// Temporary Room Service — central client-side API for the temporary room
// lifecycle implemented by the 20260912120000_temporary_game_rooms.sql
// migration.
//
// Every multiplayer game in Daxelo-Kinrel is a "temporary room":
//   • A brand-new room is created every time the user taps Play.
//   • Waiting rooms auto-expire after 5 minutes of inactivity (server-side
//     pg_cron job — fn_expire_stale_game_rooms).
//   • If the host leaves before the game starts, the room is immediately
//     closed and deleted (fn_cancel_waiting_room — also enforced by a
//     server-side trigger as a safety net).
//   • When the game ends, results are shown briefly, then the room and
//     all temporary player associations are deleted (fn_end_game — also
//     enforced by an hourly pg_cron job as a safety net).
//
// This service is the single entry point for those RPCs from the Flutter
// side. All game providers call into it; none of them builds its own
// delete / cancel / expire logic.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/services/supabase_service.dart';

/// Canonical game table → player table mapping.
///
/// `redlight` is special: its parent table is `redlight_rounds` (not
/// `redlight_games`), and the players use `roundId` instead of `gameId`.
const kGamePlayerTableMap = <String, String>{
  'antakshari_games': 'antakshari_players',
  'chitmatch_games': 'chitmatch_players',
  'bingo_games': 'bingo_players', // may not exist — see kPlayerTableExists
  'ludo_games': 'ludo_players',
  'sos_games': 'sos_players',
  'dotsboxes_games': 'dotsboxes_players',
  'nameplace_games': 'nameplace_players',
  'truthordare_games': 'truthordare_players',
  'twotruths_games': 'twotruths_players',
  'redlight_rounds': 'redlight_players',
  'tugofwar_games': 'tugofwar_players',
  'memorymatch_games': 'memorymatch_players',
  // ── QA fix 2026-09-21: the newer games were missing, so their lobby
  // Ready toggle silently no-oped (playerTableFor returned null and the
  // RPC was never called — the optimistic local toggle then reverted on
  // the next refetch, and hosts saw "0 of N Ready" forever).
  'connect4_games': 'connect4_players',
  'impostor_games': 'impostor_players',
  'ashta_chamma_games': 'ashta_chamma_players',
  'color_trap_games': 'color_trap_players',
  'freeze_auction_games': 'freeze_auction_players',
  'secret_heist_games': 'secret_heist_players',
  'mind_match_games': 'mind_match_players',
  'code_clues_games': 'code_clues_players',
  'night_falls_games': 'night_falls_players',
  'sketch_telephone_games': 'sketch_telephone_players',
  'word_forge_games': 'word_forge_players',
  'stickman_heist_games': 'stickman_heist_players',
};

/// Player tables known to exist (bingo_players does NOT — bingo uses
/// bingo_cards/bingo_claims). Used by [TemporaryRoomService] to skip
/// player-table RPCs for bingo.
const kPlayerTableExists = <String>{
  'antakshari_players',
  'chitmatch_players',
  'ludo_players',
  'sos_players',
  'dotsboxes_players',
  'nameplace_players',
  'truthordare_players',
  'twotruths_players',
  'redlight_players',
  'tugofwar_players',
  'memorymatch_players',
  // ── QA fix 2026-09-21: newer games' player tables.
  'connect4_players',
  'impostor_players',
  'ashta_chamma_players',
  'color_trap_players',
  'freeze_auction_players',
  'secret_heist_players',
  'mind_match_players',
  'code_clues_players',
  'night_falls_players',
  'sketch_telephone_players',
  'word_forge_players',
  'stickman_heist_players',
};

/// Returns the player table for a given game table, or null if the game
/// doesn't have a per-player table (Pattern A games + bingo).
String? playerTableFor(String gameTable) {
  final t = kGamePlayerTableMap[gameTable];
  if (t == null) return null;
  return kPlayerTableExists.contains(t) ? t : null;
}

/// Message shown whenever a join/invite targets a room that no longer
/// exists. Per the room-close spec, a closed room is deleted from the
/// database immediately — so the correct next step for the user is to
/// create a new room, never to re-enter the old one.
const String kRoomClosedMessage =
    'This room has already been closed and deleted. Create a new room to play.';

/// Returns true when a raw Supabase game row belongs to a room that is
/// closed (cancelledAt / closedAt set) or that no longer exists (null
/// row). Used by every game's joinGame()/loadGame() so a closed room can
/// never be re-entered from a stale invite, chat card, or deep link.
bool isRoomRowClosed(Map<String, dynamic>? row) {
  if (row == null) return true; // row gone → room was deleted
  return row['cancelledAt'] != null || row['closedAt'] != null;
}

class TemporaryRoomService {
  TemporaryRoomService(this._ref);

  final Ref _ref;

  SupabaseClient? get _client => _ref.read(supabaseProvider);
  String? get _myId => _client?.auth.currentUser?.id;

  /// Bumps the room's `lastActivityAt` timestamp. Call this whenever a
  /// player joins, leaves, toggles ready, or makes any visible action
  /// in the lobby — this resets the 5-min inactivity expiry timer.
  Future<void> touchActivity({
    required String gameTable,
    required String gameId,
  }) async {
    final client = _client;
    if (client == null) return;
    try {
      await client.rpc('fn_touch_game_activity', params: {
        'p_game_table': gameTable,
        'p_game_id': gameId,
      });
    } catch (e) {
      debugPrint('[TemporaryRoom] touchActivity error: $e');
    }
  }

  /// Toggles the calling player's `isReady` flag on a player table.
  /// Also bumps the room's lastActivityAt (server-side).
  Future<void> toggleReady({
    required String gameTable,
    required String gameId,
    required bool isReady,
  }) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) return;
    final playerTable = playerTableFor(gameTable);
    if (playerTable == null) return; // bingo / Pattern A — no ready concept
    try {
      await client.rpc('fn_set_player_ready', params: {
        'p_player_table': playerTable,
        'p_game_table': gameTable,
        'p_game_id': gameId,
        'p_user_id': myId,
        'p_is_ready': isReady,
      });
    } catch (e) {
      debugPrint('[TemporaryRoom] toggleReady error: $e');
    }
  }

  /// Called when a user leaves a waiting lobby. If the user is the host
  /// AND the room is still in `waiting` status, the entire game row is
  /// deleted (cascade to child tables + invites). Safe no-op for Pattern
  /// A games (no host column).
  Future<void> cancelWaitingRoom({
    required String gameTable,
    required String gameId,
  }) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) return;
    try {
      await client.rpc('fn_cancel_waiting_room', params: {
        'p_game_table': gameTable,
        'p_game_id': gameId,
        'p_user_id': myId,
      });
    } catch (e) {
      debugPrint('[TemporaryRoom] cancelWaitingRoom error: $e');
    }
  }

  /// Hard-deletes a game row + its invites. Called from results screens
  /// when the user taps "Back to Hub" / "Play Again", or automatically
  /// by the provider a few seconds after the game finishes.
  Future<void> endGame({
    required String gameTable,
    required String gameId,
  }) async {
    final client = _client;
    if (client == null) return;
    try {
      await client.rpc('fn_end_game', params: {
        'p_game_table': gameTable,
        'p_game_id': gameId,
      });
    } catch (e) {
      debugPrint('[TemporaryRoom] endGame error: $e');
    }
  }

  /// Returns the room summary JSON (status, hostUserId, playerCount,
  /// readyCount, allReady, players[]). Used by the lobby UI to render
  /// the correct state banner.
  Future<Map<String, dynamic>?> getRoomSummary({
    required String gameTable,
    required String gameId,
  }) async {
    final client = _client;
    if (client == null) return null;
    final playerTable = playerTableFor(gameTable);
    if (playerTable == null) return null;
    try {
      final result = await client.rpc('fn_get_room_summary', params: {
        'p_game_table': gameTable,
        'p_player_table': playerTable,
        'p_game_id': gameId,
      });
      if (result == null) return null;
      return result is Map<String, dynamic>
          ? result
          : Map<String, dynamic>.from(result as Map);
    } catch (e) {
      debugPrint('[TemporaryRoom] getRoomSummary error: $e');
      return null;
    }
  }
}

/// Riverpod provider. Use:
///   `final room = ref.read(temporaryRoomServiceProvider);`
final temporaryRoomServiceProvider = Provider<TemporaryRoomService>((ref) {
  return TemporaryRoomService(ref);
});

// lib/features/games/shared/services/room_presence_heartbeat.dart
//
// DB presence heartbeat for multiplayer rooms.
//
// The room framework's disconnect reaper (fn_reap_disconnected_players,
// swept by the server every few minutes) hard-deletes any room whose
// HOST's game_participants.lastSeenAt is stale (>60s) and marks stale
// guests offline. The Pattern B games keep their rows fresh via
// RoomController's 20s fn_player_heartbeat loop — but any game that
// manages its own realtime subscription (the 4 board games) must run
// the same heartbeat or its rooms get reaped mid-lobby/mid-match.
//
// This helper owns exactly that timer:
//
//   final _heartbeat = RoomPresenceHeartbeat('chess_games');
//   _heartbeat.start(client, gameId, myId);   // with the realtime sub
//   _heartbeat.stop();                        // on unsubscribe/dispose
//
// The RPC is idempotent and best-effort — transient failures are
// swallowed and retried on the next tick.

import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

class RoomPresenceHeartbeat {
  RoomPresenceHeartbeat(
    this.gameTable, {
    this.interval = const Duration(seconds: 20),
  });

  /// e.g. 'chess_games' — the game_participants table key.
  final String gameTable;

  /// How often to ping. RoomController uses 20s; the reaper's stale
  /// threshold is 60s, so anything below that with a tick of slack is
  /// safe.
  final Duration interval;

  Timer? _timer;

  bool get isRunning => _timer != null;

  /// Start (or restart) the heartbeat for [userId] in room [gameId].
  void start(SupabaseClient client, String gameId, String userId) {
    stop();
    // Fire once immediately so a freshly opened screen refreshes its
    // row before any sweep can consider it stale.
    _tick(client, gameId, userId);
    _timer = Timer.periodic(interval, (_) => _tick(client, gameId, userId));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick(SupabaseClient client, String gameId, String userId) async {
    try {
      await client.rpc('fn_player_heartbeat', params: {
        'p_game_table': gameTable,
        'p_game_id': gameId,
        'p_user_id': userId,
      });
    } catch (_) {
      // Best-effort — the next tick retries.
    }
  }
}

// lib/features/games/shared/multiplayer/room_controller.dart
//
// Generic StateNotifier that manages the FULL lifecycle of a multiplayer
// game room for ANY game (SOS, Bingo, Ludo, Chess, etc.).
//
// Responsibilities (per the implementation prompt):
//   1. Family Member Invite Filter     — handled by InviteFamilySheet
//      (already uses fn_get_linked_family_members RPC, which only
//      returns real Kinrel users linked to the current family).
//   2. Host Ready Flow                  — host is auto-ready, players see
//      a single Ready/Not Ready toggle, host sees "Waiting for players…"
//      + "Start Match" button only when all required players are ready.
//   3. Cancel Room                       — closes + deletes the room,
//      notifies all participants in real time, returns to setup.
//   4. Back Button Protection            — handled by BackButtonGuard.
//   5. Room Rejoin Fix                   — server-authoritative existence
//      check via fn_get_room_state RPC; never restores deleted rooms.
//   6. Auto-Close Timer                  — real countdown synced across
//      all clients via the autoCloseDeadline timestamp on the game row.
//   7. Player Leave Events               — system message in lobby chat,
//      slot freed immediately, player count updated in real time.
//   8. App Close / Disconnect Handling   — heartbeat RPC + cron reaper
//      removes disconnected players; if host disconnects, room closes.
//   9. Spectator Mode                    — read-only viewers tracked in
//      game_spectators, gated by spectatorsEnabled flag on the game row.
//  10. Real-Time Sync                    — single server-authoritative
//      state, all clients see changes via Supabase Realtime channels.
//  11. Consistency                       — every game uses this controller.
//
// The controller is intentionally GENERIC — it knows nothing about
// SOS rules, Bingo number-calling, or Ludo dice. Game-specific logic
// stays in the game's own provider. This controller only manages the
// ROOM (lobby, ready, cancel, spectator, chat, disconnect).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../../core/services/supabase_service.dart';
import '../providers/game_invite_status_provider.dart';
import 'room_config.dart';
import 'room_state.dart';

/// Notifier that manages a multiplayer room's full lifecycle.
///
/// Constructed per (game, familyId). The same controller class is used
/// by every multiplayer game — only the [RoomConfig] differs.
class RoomController extends StateNotifier<RoomState> {
  RoomController(this._ref, this._config, this.familyId)
      : super(const RoomState());

  final Ref _ref;
  final RoomConfig _config;
  final String familyId;

  SupabaseClient? get _client => _ref.read(supabaseProvider);
  String? get _myId => _client?.auth.currentUser?.id;
  String get _myName =>
      (_client?.auth.currentUser?.userMetadata?['name'] as String?) ??
      _client?.auth.currentUser?.email ??
      'Player';

  RoomConfig get config => _config;
  String get gameTable => _config.gameTable.tableName;

  // ── Realtime + polling state ──────────────────────────────────────
  RealtimeChannel? _channel;
  String? _gameId;
  Timer? _heartbeatTimer;
  Timer? _lobbyPollTimer;
  Timer? _autoCloseTimer;
  Timer? _countdownTimer;
  bool _countdownFired = false;

  // ── Public API ────────────────────────────────────────────────────

  /// Create a new room (host-only). Inserts the game row + the host's
  /// participant row, sets the autoCloseDeadline, and starts the
  /// realtime subscription.
  ///
  /// Returns the new game id, or null on failure.
  Future<String?> createRoom({
    required Map<String, dynamic> gameSpecificFields,
    bool spectatorsEnabled = true,
    int autoCloseMinutes = 0, // 0 = use config default
    Map<String, dynamic>? hostParticipantFields,
  }) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) {
      _setError('Not signed in',
          fallback: 'You need to sign in to play. Restart the app and try again.');
      return null;
    }

    final minutes = autoCloseMinutes > 0 ? autoCloseMinutes : _config.defaultAutoCloseMinutes;
    final deadline = DateTime.now().add(Duration(minutes: minutes));

    state = RoomState(
      familyId: familyId,
      myUserId: myId,
      isLoading: true,
      connectionStatus: RoomConnectionStatus.connecting,
    );

    try {
      // 1. Insert the game row with autoCloseDeadline + hostReady + spectatorsEnabled
      final gameRow = <String, dynamic>{
        'familyId': familyId,
        'hostUserId': myId,
        'hostUserName': _myName,
        'status': _config.lobbyStatusValue,
        'spectatorsEnabled': spectatorsEnabled,
        'autoCloseDeadline': deadline.toIso8601String(),
        'hostReady': true,
        ...gameSpecificFields,
      };

      final resp = await client
          .from(gameTable)
          .insert(gameRow)
          .select()
          .single();
      final newGameId = (resp['id'] ?? '') as String;
      _gameId = newGameId;

      // 2. Insert host as a participant via the RPC (posts a 'join' event too)
      await client.rpc('fn_record_room_join', params: {
        'p_game_table': gameTable,
        'p_game_id': newGameId,
        'p_family_id': familyId,
        'p_user_id': myId,
        'p_user_name': _myName,
        'p_role': 'host',
      });

      // 3. If the game has a separate players table, also insert into it
      //    (so the game's own provider can find this player there).
      final playersTable = _config.gameTable.playersTableName;
      if (playersTable != null) {
        try {
          await client.from(playersTable).insert({
            'gameId': newGameId,
            'userId': myId,
            'userName': _myName,
            ...?hostParticipantFields,
          });
        } catch (e) {
          debugPrint('[RoomController] host player row insert failed (non-fatal): $e');
        }
      }

      // 4. Subscribe to realtime + start heartbeat + start auto-close timer
      _subscribeToRealtime(newGameId);
      _startHeartbeat();
      _startAutoCloseTimer(deadline);

      // 5. Fetch the full room state from the server
      await _refreshRoomState(newGameId);

      state = state.copyWith(isLoading: false);
      return newGameId;
    } catch (e) {
      debugPrint('[RoomController] createRoom error: $e');
      state = state.copyWith(
        isLoading: false,
        connectionStatus: RoomConnectionStatus.error,
      );
      _setError(e, fallback: 'Couldn\'t create the room. Tap to try again.');
      return null;
    }
  }

  /// Join an existing room as a player.
  Future<bool> joinRoom(String gameId) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) {
      _setError('Not signed in',
          fallback: 'You need to sign in to play. Restart the app and try again.');
      return false;
    }

    // ── Room Rejoin Fix: validate the room exists on the server ──────
    // Never restore a stale / deleted room — always fetch fresh.
    state = state.copyWith(
      gameId: gameId,
      familyId: familyId,
      myUserId: myId,
      isLoading: true,
      clearError: true,
      clearFriendlyError: true,
      connectionStatus: RoomConnectionStatus.connecting,
    );

    try {
      final exists = await client
          .from(gameTable)
          .select()
          .eq('id', gameId)
          .maybeSingle();
      if (exists == null) {
        // Room doesn't exist — clear local state so we don't restore it.
        state = const RoomState();
        _setError('Room not found',
            fallback: 'This room no longer exists.');
        return false;
      }

      // Check if room is already cancelled/closed
      final cancelledAt = exists['cancelledAt'];
      final closedAt = exists['closedAt'];
      if (cancelledAt != null || closedAt != null) {
        state = const RoomState();
        _setError('Room closed',
            fallback: 'This room has been closed.');
        return false;
      }

      _gameId = gameId;

      // 1. Record the join via the RPC (idempotent + posts 'join' event)
      await client.rpc('fn_record_room_join', params: {
        'p_game_table': gameTable,
        'p_game_id': gameId,
        'p_family_id': familyId,
        'p_user_id': myId,
        'p_user_name': _myName,
        'p_role': 'player',
      });

      // 2. If the game has a players table, also insert the player row.
      //    Defer to the game's own provider for game-specific fields
      //    (turnOrder, team, color, etc.) — the game's joinGame() should
      //    handle that AFTER calling this.
      final playersTable = _config.gameTable.playersTableName;
      if (playersTable != null) {
        try {
          // Best-effort upsert — game-specific fields (turnOrder, team,
          // etc.) are set by the game's own provider.
          await client.from(playersTable).upsert({
            'gameId': gameId,
            'userId': myId,
            'userName': _myName,
          }, onConflict: 'gameId,userId');
        } catch (e) {
          debugPrint('[RoomController] player row upsert (non-fatal): $e');
        }
      }

      // 3. Subscribe + heartbeat + auto-close timer
      _subscribeToRealtime(gameId);
      _startHeartbeat();
      final deadline = exists['autoCloseDeadline'] is String
          ? DateTime.tryParse(exists['autoCloseDeadline'] as String)
          : null;
      if (deadline != null) _startAutoCloseTimer(deadline);

      // 4. Refresh full state
      await _refreshRoomState(gameId);

      state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      debugPrint('[RoomController] joinRoom error: $e');
      state = state.copyWith(
        isLoading: false,
        connectionStatus: RoomConnectionStatus.error,
      );
      _setError(e, fallback: 'Couldn\'t join the room. Tap to try again.');
      return false;
    }
  }

  /// Join an existing room as a spectator (read-only viewer).
  /// Only succeeds if spectatorsEnabled = true on the game row.
  Future<bool> joinAsSpectator(String gameId) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) return false;

    state = state.copyWith(
      gameId: gameId,
      familyId: familyId,
      myUserId: myId,
      isLoading: true,
      connectionStatus: RoomConnectionStatus.connecting,
    );

    try {
      // 1. Validate room exists + spectators are enabled
      final gameRow = await client
          .from(gameTable)
          .select()
          .eq('id', gameId)
          .maybeSingle();
      if (gameRow == null) {
        state = const RoomState();
        _setError('Room not found', fallback: 'This room no longer exists.');
        return false;
      }
      final spectatorsEnabled = gameRow['spectatorsEnabled'] == true;
      if (!spectatorsEnabled) {
        state = const RoomState();
        _setError('Spectators disabled',
            fallback: 'The host has not allowed spectators for this room.');
        return false;
      }
      final cancelledAt = gameRow['cancelledAt'];
      final closedAt = gameRow['closedAt'];
      if (cancelledAt != null || closedAt != null) {
        state = const RoomState();
        _setError('Room closed', fallback: 'This room has been closed.');
        return false;
      }

      _gameId = gameId;

      // 2. Insert spectator row + post 'spectator_join' event
      await client.rpc('fn_spectate_game', params: {
        'p_game_table': gameTable,
        'p_game_id': gameId,
        'p_family_id': familyId,
        'p_user_id': myId,
        'p_user_name': _myName,
      });

      // 3. Subscribe + heartbeat + auto-close timer
      _subscribeToRealtime(gameId);
      _startHeartbeat();
      final deadline = gameRow['autoCloseDeadline'] is String
          ? DateTime.tryParse(gameRow['autoCloseDeadline'] as String)
          : null;
      if (deadline != null) _startAutoCloseTimer(deadline);

      // 4. Refresh
      await _refreshRoomState(gameId);

      state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      debugPrint('[RoomController] joinAsSpectator error: $e');
      state = state.copyWith(
        isLoading: false,
        connectionStatus: RoomConnectionStatus.error,
      );
      _setError(e, fallback: 'Couldn\'t join as spectator. Try again.');
      return false;
    }
  }

  /// Toggle the local user's ready status. Host is always ready —
  /// calling this for the host is a no-op.
  Future<void> setReady({required bool ready}) async {
    final client = _client;
    final myId = _myId;
    final gameId = _gameId;
    if (client == null || myId == null || gameId == null) return;
    if (state.isHost) return; // host is always ready

    state = state.copyWith(isSubmitting: true, clearError: true, clearFriendlyError: true);
    try {
      await client.rpc('fn_set_player_ready', params: {
        'p_game_table': gameTable,
        'p_game_id': gameId,
        'p_user_id': myId,
        'p_ready': ready,
      });

      // Optimistic local update — realtime callback will confirm.
      final updated = state.participants.map((p) {
        if (p.userId == myId) {
          return p.copyWith(
            readyAt: ready ? DateTime.now() : null,
            clearReadyAt: !ready,
          );
        }
        return p;
      }).toList();
      state = state.copyWith(participants: updated, isSubmitting: false);
    } catch (e) {
      debugPrint('[RoomController] setReady error: $e');
      state = state.copyWith(isSubmitting: false);
      _setError(e, fallback: 'Couldn\'t update ready status. Tap to try again.');
    }
  }

  /// Attach the room-lifecycle framework to an already-created game row.
  ///
  /// Games like SOS / Bingo / Ludo have their own providers that create
  /// the game row with game-specific fields (mode, gridSize, etc.).
  /// After that, the lobby screen calls this method to attach the
  /// framework's room lifecycle: writes autoCloseDeadline +
  /// spectatorsEnabled + hostReady onto the game row, inserts the host
  /// as a participant via fn_record_room_join, and subscribes to realtime.
  ///
  /// This avoids duplicating the game-row INSERT (which would happen if
  /// the lobby called `createRoom` after the game provider already
  /// created the row).
  Future<void> attachToExistingGame(
    String gameId, {
    bool spectatorsEnabled = true,
    int autoCloseMinutes = 0,
    String hostRole = 'host',
  }) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) {
      _setError('Not signed in',
          fallback: 'You need to sign in to play. Restart the app and try again.');
      return;
    }

    final minutes = autoCloseMinutes > 0 ? autoCloseMinutes : _config.defaultAutoCloseMinutes;
    final deadline = DateTime.now().add(Duration(minutes: minutes));

    state = RoomState(
      gameId: gameId,
      familyId: familyId,
      myUserId: myId,
      isLoading: true,
      connectionStatus: RoomConnectionStatus.connecting,
    );
    _gameId = gameId;

    try {
      // 1. Update the game row with room-lifecycle columns
      await client.from(gameTable).update({
        'spectatorsEnabled': spectatorsEnabled,
        'autoCloseDeadline': deadline.toIso8601String(),
        'hostReady': true,
      }).eq('id', gameId);

      // 2. Insert host as a participant (idempotent, posts 'join' event)
      await client.rpc('fn_record_room_join', params: {
        'p_game_table': gameTable,
        'p_game_id': gameId,
        'p_family_id': familyId,
        'p_user_id': myId,
        'p_user_name': _myName,
        'p_role': hostRole,
      });

      // 3. Subscribe + heartbeat + auto-close timer
      _subscribeToRealtime(gameId);
      _startHeartbeat();
      _startAutoCloseTimer(deadline);

      // 4. Refresh full state
      await _refreshRoomState(gameId);

      state = state.copyWith(isLoading: false);
    } catch (e) {
      debugPrint('[RoomController] attachToExistingGame error: $e');
      state = state.copyWith(
        isLoading: false,
        connectionStatus: RoomConnectionStatus.error,
      );
      _setError(e, fallback: 'Couldn\'t initialize the room. Tap to try again.');
    }
  }

  /// Non-host: attach to an existing room after the game's own provider
  /// has inserted the player into the game's *_players table. Records
  /// the participant in game_participants (idempotent), subscribes to
  /// realtime, starts heartbeat + auto-close timer.
  Future<void> attachOnJoin(String gameId, {String role = 'player'}) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) return;

    state = RoomState(
      gameId: gameId,
      familyId: familyId,
      myUserId: myId,
      isLoading: true,
      connectionStatus: RoomConnectionStatus.connecting,
    );
    _gameId = gameId;

    try {
      // Validate room exists + isn't closed
      final exists = await client
          .from(gameTable)
          .select()
          .eq('id', gameId)
          .maybeSingle();
      if (exists == null ||
          exists['cancelledAt'] != null ||
          exists['closedAt'] != null) {
        state = const RoomState();
        _setError('Room not available',
            fallback: 'This room has been closed.');
        return;
      }

      // Record the join (idempotent + posts 'join' event)
      await client.rpc('fn_record_room_join', params: {
        'p_game_table': gameTable,
        'p_game_id': gameId,
        'p_family_id': familyId,
        'p_user_id': myId,
        'p_user_name': _myName,
        'p_role': role,
      });

      _subscribeToRealtime(gameId);
      _startHeartbeat();
      final deadline = exists['autoCloseDeadline'] is String
          ? DateTime.tryParse(exists['autoCloseDeadline'] as String)
          : null;
      if (deadline != null) _startAutoCloseTimer(deadline);

      await _refreshRoomState(gameId);
      state = state.copyWith(isLoading: false);
    } catch (e) {
      debugPrint('[RoomController] attachOnJoin error: $e');
      state = state.copyWith(
        isLoading: false,
        connectionStatus: RoomConnectionStatus.error,
      );
      _setError(e, fallback: 'Couldn\'t join the room. Tap to try again.');
    }
  }

  /// Host: start the 5-second match countdown.
  ///
  /// Validates host + min players + all-required-ready. Then:
  ///   1. Calls fn_start_match_countdown RPC (posts a 'countdown'
  ///      game_room_events row, fanned out via realtime to all clients).
  ///   2. Sets local state to [RoomStatus.countdown] with the same
  ///      server-returned deadline so the overlay ticks in sync.
  ///   3. Starts a 1-second ticker that, on deadline expiry, calls
  ///      [onCountdownComplete] — which the game's own provider
  ///      supplies to transition the game row lobby → active.
  ///
  /// Non-host clients observe the 'countdown' event via realtime and
  /// render the same overlay; they do not call this method themselves.
  Future<bool> startMatchWithCountdown({
    required Future<void> Function() onCountdownComplete,
    int seconds = 5,
  }) async {
    final client = _client;
    final myId = _myId;
    final gameId = _gameId;
    if (client == null || myId == null || gameId == null) return false;
    if (!state.isHost) return false;
    if (state.playerCount < _config.minPlayers) return false;
    if (!state.allRequiredReady) return false;
    if (state.isCountdown || state.isActive) return false;

    state = state.copyWith(
      isSubmitting: true,
      clearError: true,
      clearFriendlyError: true,
    );
    _countdownFired = false;

    try {
      final result = await client.rpc('fn_start_match_countdown', params: {
        'p_game_table': gameTable,
        'p_game_id': gameId,
        'p_user_id': myId,
        'p_seconds': seconds,
      });

      final deadline = result is String
          ? DateTime.tryParse(result)
          : (result is DateTime ? result : null);
      if (deadline == null) {
        state = state.copyWith(
          isSubmitting: false,
          error: 'Countdown failed',
          friendlyError: 'Couldn\'t start the match. Tap to try again.',
        );
        return false;
      }

      state = state.copyWith(
        status: RoomStatus.countdown,
        countdownEndsAt: deadline,
        isSubmitting: false,
      );
      _startCountdownTimer(deadline, onCountdownComplete);
      return true;
    } catch (e) {
      debugPrint('[RoomController] startMatchWithCountdown error: $e');
      state = state.copyWith(
        isSubmitting: false,
      );
      _setError(e, fallback: 'Couldn\'t start the match. Tap to try again.');
      return false;
    }
  }

  /// Cancel an in-progress countdown (host only). Clears the countdown
  /// state and stops the local timer. Does NOT post a server event —
  /// the host can simply restart the countdown later.
  void cancelCountdown() {
    if (!state.isHost) return;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _countdownFired = false;
    if (state.isCountdown) {
      state = state.copyWith(
        status: RoomStatus.lobby,
        clearCountdownEndsAt: true,
      );
    }
  }

  // ── Countdown ticker ──────────────────────────────────────────────
  //
  // Local 1-second ticker that mirrors the server's countdown deadline.
  // When the deadline passes, fires the [onComplete] callback ONCE and
  // transitions state to [RoomStatus.active] (the game's own provider is
  // responsible for the actual lobby → active row update via its own
  // startGame() method, which [onComplete] wraps).

  void _startCountdownTimer(
    DateTime deadline,
    Future<void> Function() onComplete,
  ) {
    _countdownTimer?.cancel();
    _countdownFired = false;
    _countdownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        final now = DateTime.now();
        final delta = deadline.difference(now);
        if (delta.isNegative || delta.inSeconds == 0) {
          _countdownTimer?.cancel();
          _countdownTimer = null;
          if (!_countdownFired) {
            _countdownFired = true;
            // Fire-and-forget; the game's start callback transitions
            // the game row from lobby → active. The realtime listener
            // will then sync every client to [RoomStatus.active].
            unawaited(onComplete());
          }
        } else {
          // Force a state rebuild so the countdown overlay re-renders.
          state = state.copyWith();
        }
      },
    );
  }

  void _stopCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _countdownFired = false;
  }

  /// Host: cancel the room. Closes + deletes the room, notifies all
  /// participants in real time via the 'cancel' room event.
  ///
  /// Per the spec:
  ///   • Delete the room immediately from the database.
  ///   • Remove all players.
  ///   • Remove all spectators.
  ///   • Close all realtime subscriptions/sockets.
  ///   • Clear any local room cache.
  ///   • Navigate back to the game lobby/create room screen.
  ///   • Closed rooms are permanently removed and cannot reappear.
  Future<void> cancelRoom() async {
    final client = _client;
    final myId = _myId;
    final gameId = _gameId;
    if (client == null || myId == null || gameId == null) return;
    if (!state.isHost) return;

    state = state.copyWith(
        isSubmitting: true, clearError: true, clearFriendlyError: true);
    try {
      // 1. Server-side: delete the room + all participants + spectators +
      //    game-row data. Posts a 'cancel' event that fans out via
      //    realtime to all connected clients (including us).
      await client.rpc('fn_cancel_game_room', params: {
        'p_game_table': gameTable,
        'p_game_id': gameId,
        'p_user_id': myId,
      });

      // 2. Local cleanup: stop heartbeat + auto-close timer + lobby poll
      //    + countdown timer + unsubscribe the realtime channel.
      _cleanup();

      // 3. Clear all local state so the room can never be restored from
      //    cache. The LobbyView watches state and will re-render the
      //    setup screen (since hasGame == false).
      state = const RoomState();

      // 4. Invalidate Riverpod caches that may hold stale room data.
      //    This ensures deleted rooms never reappear from any cache.
      _invalidateStaleCaches(gameId);
    } catch (e) {
      debugPrint('[RoomController] cancelRoom error: $e');
      state = state.copyWith(isSubmitting: false);
      _setError(e, fallback: 'Couldn\'t cancel the room. Tap to try again.');
    }
  }

  /// Invalidate Riverpod providers that may hold stale room data after
  /// a room is closed. This is the "clear any local room cache" step
  /// from the spec — without it, the PendingInvitesSection + invite
  /// status badges + game invite chat sync would keep showing data
  /// for a deleted room.
  void _invalidateStaleCaches(String gameId) {
    try {
      // Invalidate the game invite status provider (tracks pending/
      // accepted/declined invites for this gameId).
      _ref.invalidate(gameInviteStatusProvider(gameId));
    } catch (_) {
      // Provider may not be watched — ignore.
    }
  }

  /// Leave the room (manual exit). If the host leaves, the room is
  /// closed automatically by the RPC (host_leave → close).
  Future<void> leaveRoom() async {
    final client = _client;
    final myId = _myId;
    final gameId = _gameId;
    _cleanup();
    if (client == null || myId == null || gameId == null) {
      state = const RoomState();
      return;
    }
    try {
      if (state.isSpectator) {
        await client.rpc('fn_leave_spectator', params: {
          'p_game_table': gameTable,
          'p_game_id': gameId,
          'p_user_id': myId,
        });
      } else {
        await client.rpc('fn_leave_game_room', params: {
          'p_game_table': gameTable,
          'p_game_id': gameId,
          'p_user_id': myId,
        });
      }
    } catch (_) {}
    // Clear local state + invalidate caches (same as cancelRoom — a
    // departed user should never see stale room data either).
    state = const RoomState();
    _invalidateStaleCaches(gameId);
  }

  /// Send a chat message to the lobby (persisted + broadcast via realtime).
  Future<void> sendChat({
    required String content,
    required String chatType, // 'text' | 'emoji'
  }) async {
    final client = _client;
    final myId = _myId;
    final gameId = _gameId;
    if (client == null || myId == null || gameId == null) return;
    if (content.trim().isEmpty) return;
    try {
      await client.rpc('fn_post_room_chat', params: {
        'p_game_table': gameTable,
        'p_game_id': gameId,
        'p_family_id': familyId,
        'p_user_id': myId,
        'p_user_name': _myName,
        'p_content': content.trim(),
        'p_is_spectator': state.isSpectator,
        'p_chat_type': chatType,
      });
      // The RPC inserts a 'chat' event; realtime fans it out.
    } catch (e) {
      debugPrint('[RoomController] sendChat error: $e');
    }
  }

  /// Refresh the full room state from the server (single RPC call).
  Future<void> refresh() async {
    final gameId = _gameId;
    if (gameId == null) return;
    await _refreshRoomState(gameId);
  }

  /// Retry the realtime channel after a connection drop.
  Future<void> retryConnection() async {
    final gameId = _gameId;
    if (gameId == null) return;
    state = state.copyWith(
      clearError: true,
      clearFriendlyError: true,
      connectionStatus: RoomConnectionStatus.connecting,
    );
    _subscribeToRealtime(gameId);
    await _refreshRoomState(gameId);
  }

  // ── Realtime subscription ─────────────────────────────────────────

  void _subscribeToRealtime(String gameId) {
    _channel?.unsubscribe();
    final client = _client;
    if (client == null) return;

    state = state.copyWith(connectionStatus: RoomConnectionStatus.connecting);

    _channel = client
        .channel('room:$gameTable:$gameId')
        // ── game_room_events: INSERT (join/leave/ready/cancel/auto_close/chat)
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'game_room_events',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: gameId,
          ),
          callback: (payload) {
            final event = RoomEvent.fromJson(payload.newRecord);
            // Append the new event to the local log
            state = state.copyWith(events: [...state.events, event]);

            // React to specific event types
            if (event.eventType == 'cancel' ||
                event.eventType == 'auto_close') {
              // Room was closed — clear local state. The lobby screen's
              // listener will navigate back to the setup screen.
              _cleanup();
              state = const RoomState();
              return;
            }

            if (event.eventType == 'countdown') {
              // Guard against late-arriving countdown events: if the
              // match has already started (game-row UPDATE arrived
              // before this event), do NOT regress to countdown state.
              if (state.isActive || state.isFinished) {
                return;
              }
              // Host (or another host-side event) started the 5-second
              // countdown. Mirror the server-authoritative deadline so
              // every client's overlay ticks in sync.
              final deadlineStr = event.payload['deadline'];
              final deadline = deadlineStr is String
                  ? DateTime.tryParse(deadlineStr)
                  : null;
              final secs = event.payload['seconds'] is int
                  ? event.payload['seconds'] as int
                  : 5;
              // If the deadline already passed (e.g. event arrived late),
              // skip showing the countdown — the game row update to
              // 'active' will arrive imminently via realtime.
              if (deadline != null &&
                  deadline.isAfter(DateTime.now())) {
                state = state.copyWith(
                  status: RoomStatus.countdown,
                  countdownEndsAt: deadline,
                );
                // Non-host clients do NOT fire the start callback —
                // the host's client owns that. Non-host clients just
                // observe the countdown + wait for the game-row UPDATE
                // (lobby → active) to arrive via realtime.
                if (!state.isHost) {
                  _startCountdownTimer(deadline, () async {
                    // No-op for non-hosts. Just let the timer expire so
                    // the overlay hides. The active state will arrive
                    // via the game-row realtime listener.
                  });
                }
                // Safety: clear countdown state after (secs + 2) seconds
                // in case the active-status update never arrives.
                Future.delayed(Duration(seconds: secs + 2), () {
                  if (state.isCountdown) {
                    state = state.copyWith(
                      status: RoomStatus.lobby,
                      clearCountdownEndsAt: true,
                    );
                  }
                });
              }
              return;
            }

            // Refresh participants + spectators to stay in sync
            unawaited(_refreshRoomState(gameId));
          },
        )
        // ── game_participants: INSERT / UPDATE / DELETE
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'game_participants',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: gameId,
          ),
          callback: (payload) {
            final p = RoomParticipant.fromJson(payload.newRecord);
            if (!state.participants.any((x) => x.userId == p.userId)) {
              state = state.copyWith(participants: [...state.participants, p]);
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'game_participants',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: gameId,
          ),
          callback: (payload) {
            final updated = RoomParticipant.fromJson(payload.newRecord);
            final next = state.participants.map((p) {
              return p.userId == updated.userId ? updated : p;
            }).toList();
            state = state.copyWith(participants: next);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'game_participants',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: gameId,
          ),
          callback: (payload) {
            final old = payload.oldRecord;
            final userId = old['userId'] as String?;
            if (userId == null) return;
            state = state.copyWith(
              participants: state.participants
                  .where((p) => p.userId != userId)
                  .toList(),
            );
          },
        )
        // ── game_spectators: INSERT / UPDATE / DELETE
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'game_spectators',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: gameId,
          ),
          callback: (payload) {
            final s = RoomSpectator.fromJson(payload.newRecord);
            if (!state.spectators.any((x) => x.userId == s.userId)) {
              state = state.copyWith(spectators: [...state.spectators, s]);
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'game_spectators',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: gameId,
          ),
          callback: (payload) {
            final old = payload.oldRecord;
            final userId = old['userId'] as String?;
            if (userId == null) return;
            state = state.copyWith(
              spectators: state.spectators
                  .where((s) => s.userId != userId)
                  .toList(),
            );
          },
        )
        // ── game row: UPDATE (status change, autoCloseDeadline change, ...)
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: gameTable,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: gameId,
          ),
          callback: (payload) {
            _applyGameRowUpdate(payload.newRecord);
          },
        )
        .subscribe(_onChannelStatus);
  }

  void _onChannelStatus(RealtimeSubscribeStatus status, [Object? error]) {
    switch (status) {
      case RealtimeSubscribeStatus.subscribed:
        state = state.copyWith(
          connectionStatus: RoomConnectionStatus.connected,
          clearError: true,
          clearFriendlyError: true,
        );
        break;
      case RealtimeSubscribeStatus.channelError:
      case RealtimeSubscribeStatus.timedOut:
        state = state.copyWith(connectionStatus: RoomConnectionStatus.reconnecting);
        debugPrint('[RoomController] realtime $status: $error');
        break;
      case RealtimeSubscribeStatus.closed:
        state = state.copyWith(connectionStatus: RoomConnectionStatus.error);
        _setError('Realtime channel closed',
            fallback: 'Lost connection to the room. Tap to try again.');
        break;
    }
  }

  // ── Heartbeat + auto-close timer ──────────────────────────────────

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) async {
        final myId = _myId;
        final gameId = _gameId;
        final client = _client;
        if (client == null || myId == null || gameId == null) return;
        try {
          if (state.isSpectator) {
            // Spectators don't have a game_participants row — skip.
            return;
          }
          await client.rpc('fn_player_heartbeat', params: {
            'p_game_table': gameTable,
            'p_game_id': gameId,
            'p_user_id': myId,
          });
        } catch (_) {}
      },
    );
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Start a local countdown to the auto-close deadline. When it hits
  /// zero, the local client navigates back to the setup screen. The
  /// SERVER-SIDE cron RPC `fn_close_expired_rooms` is the actual source
  /// of truth — this local timer is just for the UI countdown display.
  void _startAutoCloseTimer(DateTime deadline) {
    _autoCloseTimer?.cancel();
    _autoCloseTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        final now = DateTime.now();
        final delta = deadline.difference(now);
        if (delta.isNegative || delta.inSeconds == 0) {
          // Time's up — the server cron will close the room within 30s.
          // We bail out locally immediately so the UI is responsive.
          _autoCloseTimer?.cancel();
          _autoCloseTimer = null;
          state = state.copyWith(status: RoomStatus.cancelled);
        } else {
          // Force a state rebuild so the countdown widget re-renders.
          state = state.copyWith();
        }
      },
    );
  }

  void _stopAutoCloseTimer() {
    _autoCloseTimer?.cancel();
    _autoCloseTimer = null;
  }

  // ── Lobby fallback poll (5s) ──────────────────────────────────────
  //
  // Safety net for the lobby→active transition: if the realtime channel
  // drops at the exact moment the host taps Start, the non-host clients
  // would otherwise miss the status change. The poll catches it within
  // 5 seconds.

  void _startLobbyPoll(String gameId) {
    _lobbyPollTimer?.cancel();
    _lobbyPollTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _pollGameState(gameId),
    );
  }

  void _stopLobbyPoll() {
    _lobbyPollTimer?.cancel();
    _lobbyPollTimer = null;
  }

  Future<void> _pollGameState(String gameId) async {
    final client = _client;
    if (client == null) return;
    if (!state.isLobby) {
      _stopLobbyPoll();
      return;
    }
    try {
      final resp = await client
          .from(gameTable)
          .select()
          .eq('id', gameId)
          .maybeSingle();
      if (resp == null) {
        // Game row vanished — server-side delete or RLS revocation.
        _stopLobbyPoll();
        _cleanup();
        state = const RoomState();
        _setError('Game not found',
            fallback: 'This game room no longer exists.');
        return;
      }
      _applyGameRowUpdate(resp);
    } catch (e) {
      debugPrint('[RoomController] lobby poll error (non-fatal): $e');
    }
  }

  // ── State refresh ────────────────────────────────────────────────

  Future<void> _refreshRoomState(String gameId) async {
    final client = _client;
    if (client == null) return;
    try {
      final result = await client.rpc('fn_get_room_state', params: {
        'p_game_table': gameTable,
        'p_game_id': gameId,
      });
      if (result is! Map) return;
      _applyRoomStateJson(Map<String, dynamic>.from(result));
    } catch (e) {
      debugPrint('[RoomController] refresh error: $e');
    }
  }

  void _applyRoomStateJson(Map<String, dynamic> json) {
    final gameRow = json['game'] is Map
        ? Map<String, dynamic>.from(json['game'] as Map)
        : <String, dynamic>{};
    final participantsJson = json['participants'] is List
        ? (json['participants'] as List)
            .map((e) => RoomParticipant.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList()
        : <RoomParticipant>[];
    final spectatorsJson = json['spectators'] is List
        ? (json['spectators'] as List)
            .map((e) => RoomSpectator.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList()
        : <RoomSpectator>[];
    final eventsJson = json['events'] is List
        ? (json['events'] as List)
            .map((e) => RoomEvent.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList()
        : <RoomEvent>[];

    _applyGameRowUpdate(gameRow, overrideParticipants: participantsJson,
        overrideSpectators: spectatorsJson, overrideEvents: eventsJson);
  }

  void _applyGameRowUpdate(
    Map<String, dynamic> row, {
    List<RoomParticipant>? overrideParticipants,
    List<RoomSpectator>? overrideSpectators,
    List<RoomEvent>? overrideEvents,
  }) {
    final statusStr = (row['status'] ?? '') as String;
    RoomStatus status;
    if (statusStr == _config.lobbyStatusValue) {
      status = RoomStatus.lobby;
    } else if (statusStr == _config.activeStatusValue) {
      status = RoomStatus.active;
    } else if (statusStr == _config.finishedStatusValue) {
      status = RoomStatus.finished;
    } else if (_config.cancelledStatusValue != null &&
        statusStr == _config.cancelledStatusValue) {
      status = RoomStatus.cancelled;
    } else {
      status = state.status;
    }

    final cancelledAt = row['cancelledAt'] is String
        ? DateTime.tryParse(row['cancelledAt'] as String)
        : null;
    final closedAt = row['closedAt'] is String
        ? DateTime.tryParse(row['closedAt'] as String)
        : null;
    if (cancelledAt != null || closedAt != null) {
      status = RoomStatus.cancelled;
    }

    final autoCloseDeadline = row['autoCloseDeadline'] is String
        ? DateTime.tryParse(row['autoCloseDeadline'] as String)
        : state.autoCloseDeadline;

    state = state.copyWith(
      gameId: (row['id'] ?? state.gameId) as String?,
      familyId: (row['familyId'] ?? state.familyId) as String?,
      hostUserId: (row['hostUserId'] ?? state.hostUserId) as String?,
      hostUserName: (row['hostUserName'] as String?) ?? state.hostUserName,
      status: status,
      spectatorsEnabled: (row['spectatorsEnabled'] ?? state.spectatorsEnabled) as bool,
      autoCloseDeadline: autoCloseDeadline,
      cancelledAt: cancelledAt ?? state.cancelledAt,
      closedAt: closedAt ?? state.closedAt,
      participants: overrideParticipants ?? state.participants,
      spectators: overrideSpectators ?? state.spectators,
      events: overrideEvents ?? state.events,
    );

    if (status == RoomStatus.active || status == RoomStatus.finished) {
      _stopLobbyPoll();
    } else if (status == RoomStatus.lobby && _lobbyPollTimer == null) {
      _startLobbyPoll(state.gameId!);
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────

  void _setError(Object? e, {String? fallback}) {
    final raw = e == null ? null : '$e';
    state = state.copyWith(error: raw, friendlyError: fallback);
  }

  void _cleanup() {
    _stopHeartbeat();
    _stopAutoCloseTimer();
    _stopCountdownTimer();
    _stopLobbyPoll();
    _channel?.unsubscribe();
    _channel = null;
    _gameId = null;
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }
}

/// Riverpod provider family: one RoomController per (game, familyId).
/// Games use this alongside their own game-specific provider.
final roomControllerProvider = StateNotifierProvider.autoDispose
    .family<RoomController, RoomState, RoomControllerKey>(
  (ref, key) => RoomController(ref, key.config, key.familyId),
);

/// Keyed by (config, familyId) so two games in the same family get
/// different controllers (e.g. SOS and Ludo in family X).
class RoomControllerKey {
  const RoomControllerKey(this.config, this.familyId);
  final RoomConfig config;
  final String familyId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RoomControllerKey &&
          other.config.gameTable == config.gameTable &&
          other.familyId == familyId);

  @override
  int get hashCode => Object.hash(config.gameTable, familyId);
}

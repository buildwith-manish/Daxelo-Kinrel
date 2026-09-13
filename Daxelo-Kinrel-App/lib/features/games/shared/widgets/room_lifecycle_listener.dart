// lib/features/games/shared/widgets/room_lifecycle_listener.dart
//
// RoomLifecycleListener — a wrapper widget that handles the real-time
// multiplayer room lifecycle for any lobby screen.
//
// What it does:
//   1. On mount: emits `game:room:join` via SocketService so the server
//      tracks this socket's presence in the room. The server then
//      broadcasts `room:player_joined` + a system chat message
//      "X joined the room" to all participants.
//   2. On dispose: emits `game:room:leave` so the server broadcasts
//      `room:player_left` + "X left the room". If the leaving user was
//      the host, the server auto-closes the room.
//   3. Listens for `room:closed` events (host closed, host disconnected,
//      or host left). When received, shows a snackbar + auto-navigates
//      back to the game hub.
//   4. Listens for `room:player_left` (reason='disconnected') and calls
//      the optional onPlayerLeft callback so the parent screen can
//      update its player list immediately (no DB refresh needed).
//   5. Listens for `room:player_joined` and calls the optional
//      onPlayerJoined callback.
//
// Usage: wrap the lobby screen's body in this widget.
//   RoomLifecycleListener(
//     gameTable: 'antakshari_games',
//     gameId: state.game!.id,
//     familyId: widget.familyId,
//     isHost: state.game!.hostUserId == myId,
//     child: TemporaryLobbyView(...),
//   )
//
// Note: the actual DB row INSERT/DELETE for player joins/leaves is
// handled by the per-game provider (via Supabase). This widget only
// handles the Socket.IO presence + auto-close notifications.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/socket_service.dart';
import '../../../../core/services/supabase_service.dart';

class RoomLifecycleListener extends ConsumerStatefulWidget {
  const RoomLifecycleListener({
    super.key,
    required this.gameTable,
    required this.gameId,
    required this.familyId,
    required this.isHost,
    required this.child,
    this.onPlayerJoined,
    this.onPlayerLeft,
    this.onRoomClosed,
    this.enabled = true,
  });

  /// e.g. 'antakshari_games', 'redlight_rounds'
  final String gameTable;
  final String gameId;
  final String familyId;
  final bool isHost;
  final Widget child;

  /// Optional callback fired when another player joins this room.
  /// Payload: { userId, userName, isHost, timestamp }
  final void Function(Map<String, dynamic>)? onPlayerJoined;

  /// Optional callback fired when another player leaves this room
  /// (either explicitly or via disconnect).
  /// Payload: { userId, userName, reason, timestamp }
  /// reason is 'left' | 'disconnected'
  final void Function(Map<String, dynamic>)? onPlayerLeft;

  /// Optional callback fired when the room is closed (host closed,
  /// host disconnected, host left, or expired). After this fires, the
  /// widget auto-navigates back to the game hub.
  /// Payload: { closedBy, reason, timestamp }
  final void Function(Map<String, dynamic>)? onRoomClosed;

  /// Set false to disable the auto-join/leave/close behavior (e.g. when
  /// the user is on the setup screen and hasn't created a room yet).
  final bool enabled;

  @override
  ConsumerState<RoomLifecycleListener> createState() =>
      _RoomLifecycleListenerState();
}

class _RoomLifecycleListenerState
    extends ConsumerState<RoomLifecycleListener> {
  VoidCallback? _unsubPlayerJoined;
  VoidCallback? _unsubPlayerLeft;
  VoidCallback? _unsubRoomClosed;
  VoidCallback? _unsubConnectionChange;
  bool _didJoin = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _attach());
  }

  void _attach() {
    final socket = ref.read(socketServiceProvider);

    // Subscribe to room events.
    _unsubPlayerJoined = socket.onRoomPlayerJoined((payload) {
      // Filter to this room.
      if (payload['gameTable'] != widget.gameTable ||
          payload['gameId'] != widget.gameId) {
        return;
      }
      widget.onPlayerJoined?.call(payload);
    });

    _unsubPlayerLeft = socket.onRoomPlayerLeft((payload) {
      if (payload['gameTable'] != widget.gameTable ||
          payload['gameId'] != widget.gameId) {
        return;
      }
      widget.onPlayerLeft?.call(payload);
    });

    _unsubRoomClosed = socket.onRoomClosed((payload) {
      if (payload['gameTable'] != widget.gameTable ||
          payload['gameId'] != widget.gameId) {
        return;
      }
      // Call the optional callback.
      widget.onRoomClosed?.call(payload);
      // Auto-navigate back to the game hub with a snackbar.
      _handleRoomClosed(payload);
    });

    // Re-join on socket reconnect.
    _unsubConnectionChange = socket.onConnectionChange((connected) {
      if (connected && widget.enabled && !_didJoin) {
        _tryJoin();
      }
    });

    if (widget.enabled) {
      _tryJoin();
    }
  }

  void _tryJoin() {
    final socket = ref.read(socketServiceProvider);
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id ?? '';
    final myName =
        (ref.read(supabaseProvider)?.auth.currentUser?.userMetadata?['name']
                as String?) ??
            'Family member';
    if (myId.isEmpty) return;
    socket.joinGameRoom(
      gameTable: widget.gameTable,
      gameId: widget.gameId,
      userId: myId,
      userName: myName,
      isHost: widget.isHost,
    );
    _didJoin = true;
  }

  void _tryLeave() {
    if (!_didJoin) return;
    final socket = ref.read(socketServiceProvider);
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id ?? '';
    final myName =
        (ref.read(supabaseProvider)?.auth.currentUser?.userMetadata?['name']
                as String?) ??
            'Family member';
    socket.leaveGameRoom(
      gameTable: widget.gameTable,
      gameId: widget.gameId,
      userId: myId,
      userName: myName,
      isHost: widget.isHost,
    );
    _didJoin = false;
  }

  void _handleRoomClosed(Map<String, dynamic> payload) {
    if (!mounted) return;
    final closedBy = payload['closedBy'] as String? ?? 'Host';
    final reason = payload['reason'] as String? ?? 'host_closed';
    final msg = reason == 'host_disconnected'
        ? '$closedBy disconnected — room closed'
        : reason == 'host_left'
            ? '$closedBy left — room closed'
            : reason == 'expired'
                ? 'Room expired due to inactivity'
                : '$closedBy closed the room';

    // Show snackbar + navigate back to the game hub.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ),
    );

    // Auto-navigate back to the game hub after a brief delay so the
    // snackbar is visible.
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      // Use go() to clear the navigation stack — we don't want the user
      // to be able to back-navigate into a closed room.
      context.go('/games?familyId=${widget.familyId}');
    });
  }

  @override
  void dispose() {
    _unsubPlayerJoined?.call();
    _unsubPlayerLeft?.call();
    _unsubRoomClosed?.call();
    _unsubConnectionChange?.call();
    _tryLeave();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

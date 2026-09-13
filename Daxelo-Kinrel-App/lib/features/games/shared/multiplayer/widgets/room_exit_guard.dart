// lib/features/games/shared/multiplayer/widgets/room_exit_guard.dart
//
// RoomExitGuard — wraps a multiplayer game lobby body to intercept ALL
// back-navigation gestures:
//
//   • Android system back button (hardware)
//   • iOS swipe-back gesture (CupertinoPageTransition edge swipe)
//   • AppBar back button (when the AppBar is part of the wrapped tree)
//
// Per the spec:
//   "Pressing the Back Button must never immediately leave the room."
//   "Intercept: Android back button, App bar back button, Swipe-back
//    gesture (iOS), Close Room button. All of them must use the same
//    confirmation dialog before leaving."
//
// This widget uses PopScope (Flutter 3.12+) which is the modern
// replacement for WillPopScope. When `canPop` is false, the system
// back button + swipe-back gesture are blocked, and `onPopInvoked`
// fires instead — where we show the same confirmation dialog as
// BackButtonGuard + CancelRoomButton.
//
// Usage:
//   PopScope is automatically applied by wrapping the lobby body:
//
//   DKScaffold(
//     appBar: AppBar(leading: BackButtonGuard(...)),
//     body: RoomExitGuard(
//       roomKey: roomKey,
//       onExit: () => context.go('/games?familyId=$familyId'),
//       child: LobbyView(...),
//     ),
//   )
//
// When the host confirms, RoomController.cancelRoom() deletes the room
// + removes all players + spectators + clears local cache + posts a
// cancel event. When a non-host confirms, RoomController.leaveRoom()
// removes just them.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../room_controller.dart';
import 'room_close_dialog.dart';

class RoomExitGuard extends ConsumerStatefulWidget {
  const RoomExitGuard({
    super.key,
    required this.roomKey,
    required this.onExit,
    required this.child,
  });

  final RoomControllerKey roomKey;
  final VoidCallback onExit;
  final Widget child;

  @override
  ConsumerState<RoomExitGuard> createState() => _RoomExitGuardState();
}

class _RoomExitGuardState extends ConsumerState<RoomExitGuard> {
  bool _isHandling = false;

  Future<void> _handleBackNavigation() async {
    if (_isHandling) return; // prevent double-tap re-entry
    _isHandling = true;
    try {
      final state = ref.read(roomControllerProvider(widget.roomKey));
      if (!state.hasGame) {
        // No active room — exit immediately, no dialog needed.
        widget.onExit();
        return;
      }
      final controller =
          ref.read(roomControllerProvider(widget.roomKey).notifier);

      // Show the appropriate confirmation dialog based on role.
      final bool? confirmed;
      if (state.isHost) {
        confirmed = await showRoomCloseConfirmDialog(context);
      } else if (state.isSpectator) {
        confirmed = await showLeaveSpectatorDialog(context);
      } else {
        confirmed = await showLeaveRoomDialog(context);
      }
      if (confirmed != true) return;
      if (!mounted) return;

      // Perform the appropriate action based on role.
      if (state.isHost) {
        await controller.cancelRoom();
      } else {
        await controller.leaveRoom();
      }
      if (!mounted) return;
      widget.onExit();
    } finally {
      _isHandling = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(roomControllerProvider(widget.roomKey));
    // canPop = true when there's no active room (so the user can navigate
    // back freely). canPop = false when a room is active — the system
    // back button + swipe-back gesture are intercepted and routed to
    // _handleBackNavigation which shows the confirmation dialog.
    final canPop = !state.hasGame;

    return PopScope(
      canPop: canPop,
      onPopInvoked: (didPop) async {
        if (didPop) return; // system already popped (canPop was true)
        await _handleBackNavigation();
      },
      child: widget.child,
    );
  }
}

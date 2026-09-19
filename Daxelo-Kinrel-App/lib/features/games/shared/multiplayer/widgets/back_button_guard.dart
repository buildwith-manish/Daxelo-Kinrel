// lib/features/games/shared/multiplayer/widgets/back_button_guard.dart
//
// BackButtonGuard — the AppBar back button for every multiplayer game
// lobby. NEVER immediately exits the room — always shows a confirmation
// dialog first.
//
// Per the spec:
//   Pressing the Back Button must never immediately leave the room.
//   Both actions (back button + Close Room button) must first show a
//   confirmation dialog.
//
// Behaviour by role:
//   Host:
//     "Close Room?" dialog (uses showRoomCloseConfirmDialog)
//     On confirm → RoomController.cancelRoom() (deletes room + all
//     players + spectators + posts cancel event + clears local cache).
//   Player:
//     "Leave Room?" dialog (uses showLeaveRoomDialog)
//     On confirm → RoomController.leaveRoom() (removes participant +
//     frees slot + posts leave event).
//   Spectator:
//     "Leave Spectator?" dialog (uses showLeaveSpectatorDialog)
//     On confirm → RoomController.leaveRoom() (calls fn_leave_spectator).
//
// If no active room (state.hasGame == false), exits immediately without
// a dialog — there's nothing to close.
//
// IMPORTANT: This widget only guards the AppBar back button. To also
// intercept the Android SYSTEM back button + iOS swipe-back gesture,
// wrap the lobby body in RoomExitGuard (see room_exit_guard.dart).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../room_controller.dart';
import 'room_close_dialog.dart';

class BackButtonGuard extends ConsumerWidget {
  const BackButtonGuard({
    super.key,
    required this.roomKey,
    required this.onExit,
  });

  final RoomControllerKey roomKey;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(roomControllerProvider(roomKey));
    final hasGame = state.hasGame;

    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () async {
        if (!hasGame) {
          // No active room — just exit, no dialog needed.
          onExit();
          return;
        }
        final controller = ref.read(roomControllerProvider(roomKey).notifier);

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

        // Perform the appropriate action based on role.
        if (state.isHost) {
          await controller.cancelRoom();
        } else {
          await controller.leaveRoom();
        }
        onExit();
      },
    );
  }
}

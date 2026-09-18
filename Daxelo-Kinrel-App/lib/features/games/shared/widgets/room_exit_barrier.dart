// lib/features/games/shared/widgets/room_exit_barrier.dart
//
// Route-level exit guard for ALL 14 multiplayer game rooms, built on
// go_router's GoRoute.onExit.
//
// Per the spec:
//   • Pressing the app Back Button must NEVER immediately leave the room.
//   • Pressing the device Back Button (Android hardware back / iOS
//     swipe-back) must NEVER immediately leave the room.
//   • Pressing the BROWSER back button (Flutter web) must NEVER
//     immediately leave the room.
//   • Host → "Close Room?" dialog ("Are you sure you want to close this
//     room?" → [Cancel] [Close Room]). Only after confirming is the room
//     deleted (fn_cancel_waiting_room / fn_end_game) and the exit allowed.
//   • Non-host player → "Leave Room?" dialog. Only after confirming does
//     the player leave (their participant row is removed).
//   • Cancel → the exit is BLOCKED and the user remains in the room.
//
// Why GoRoute.onExit (and not PopScope)?
//   PopScope only intercepts Navigator.maybePop (Android hardware back,
//   iOS swipe-back). On Flutter web the browser back button is a
//   URL-driven navigation which bypasses PopScope entirely. go_router's
//   onExit callback is consulted for EVERY exit path:
//     • GoRouter.pop / context.pop        (app bar back button)
//     • setNewRoutePath                   (browser back / URL navigation)
//     • popRoute fallback                 (Android hardware back)
//     • GoRouter.go / route replacement   (any programmatic exit)
//   Returning false from onExit blocks the route removal.
//
// Double-dialog prevention:
//   The in-screen "Close Room" button (TemporaryLobbyView) shows the SAME
//   confirmation dialog itself. After the host confirms there, it marks
//   the exit in [RoomExitConfirmations] BEFORE popping, so the route
//   guard sees a pre-confirmed exit and lets it through without showing
//   a second dialog.
//
// Usage (app_router.dart, inside routerProvider where `ref` is in scope):
//
//   GoRoute(
//     path: '/family/:id/sos/lobby',
//     onExit: guardGameRoomExit(
//       gameTable: 'sos_games',
//       readState: (fid) => ref.read(sosProvider(fid)),
//       hasRoom: (s) => s.game != null && s.game!.isLobby,
//       isHost: (s) => s.game?.hostUserId == myUserId,
//       leave: (fid) => ref.read(sosProvider(fid).notifier).leaveGame(),
//     ),
//     ...
//   )

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../multiplayer/widgets/room_close_dialog.dart';

/// Registry of exits the user has ALREADY confirmed via an in-screen
/// dialog (the Close Room button in the lobby). Consumed by the
/// route-level onExit guard so the confirmation dialog is not shown a
/// second time for the same exit.
class RoomExitConfirmations {
  RoomExitConfirmations._(); // prevent instantiation

  static final Set<String> _confirmed = <String>{};

  /// Mark the exit for [key] as already confirmed. The next exit-guard
  /// check for this key will pass through (and consume the mark).
  static void mark(String key) => _confirmed.add(key);

  /// If [key] was pre-confirmed, consumes the mark and returns true.
  static bool take(String key) => _confirmed.remove(key);
}

/// Signature for reading the per-game provider state for a family.
typedef ReadGameState<T> = T Function(String familyId);

/// Signature for probing whether a multiplayer room is active.
typedef HasRoom<T> = bool Function(T state);

/// Signature for checking whether the current user hosts the room.
typedef IsRoomHost<T> = bool Function(T state);

/// Signature for leaving/closing the room (host → deletes the room for
/// everyone via the temporary-room RPCs; player → removes their row).
typedef LeaveRoom = Future<void> Function(String familyId);

/// Build a GoRoute.onExit guard for a multiplayer game route.
///
/// [gameTable] is the game's Supabase table (also the registry key
/// namespace, e.g. 'sos_games'). [readState]/[hasRoom]/[isHost]/[leave]
/// are small closures over the game's Riverpod provider family.
ExitCallback guardGameRoomExit<T>({
  required String gameTable,
  required ReadGameState<T> readState,
  required HasRoom<T> hasRoom,
  required IsRoomHost<T> isHost,
  required LeaveRoom leave,
}) {
  return (BuildContext context, GoRouterState state) async {
    final familyId = state.pathParameters['id'] ??
        state.uri.queryParameters['familyId'] ??
        '';
    final key = '$gameTable/$familyId';

    // 1. The exit was already confirmed in-screen (Close Room button) —
    //    let it through without a second dialog.
    if (RoomExitConfirmations.take(key)) return true;

    // 2. Probe the game state. If the provider is gone or no room is
    //    active (setup screen / finished game / auto-navigating to the
    //    board), allow the exit immediately.
    T game;
    try {
      game = readState(familyId);
    } catch (_) {
      return true;
    }
    if (!hasRoom(game)) return true;

    // 3. Active room — show the role-appropriate confirmation dialog.
    //    Host: "Close Room?" (deletes the room for everyone).
    //    Player: "Leave Room?" (frees their slot).
    final confirmed = isHost(game)
        ? await showRoomCloseConfirmDialog(context)
        : await showLeaveRoomDialog(context);
    if (confirmed != true) return false; // cancelled — block the exit

    // 4. Confirmed — leave/close the room, then allow the exit.
    await leave(familyId);
    return true;
  };
}

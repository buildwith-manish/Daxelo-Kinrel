// lib/features/games/shared/multiplayer/multiplayer.dart
//
// Barrel export for the unified multiplayer room framework.
// Every multiplayer game imports this to get the full room-lifecycle
// API in one line:
//
//   import '../shared/multiplayer/multiplayer.dart';
//
// What you get:
//   • RoomConfig (per-game preset: SOS, Bingo, Ludo, Chess, ...)
//   • RoomState + RoomParticipant + RoomSpectator + RoomEvent
//   • RoomController (StateNotifier that manages the full room lifecycle)
//   • roomControllerProvider (Riverpod provider family)
//   • LobbyView (shared lobby view widget)
//   • RoomSetupView (shared setup view widget)
//   • AutoCloseTimer (countdown widget)
//   • CancelRoomButton (large visible Close Room button)
//   • BackButtonGuard (AppBar back button — shows confirmation dialog)
//   • RoomExitGuard (PopScope — intercepts Android system back button +
//     iOS swipe-back gesture — shows the same confirmation dialog)
//   • showRoomCloseConfirmDialog / showLeaveRoomDialog /
//     showLeaveSpectatorDialog (shared confirmation dialogs)
//   • MatchCountdown (5-4-3-2-1-GO overlay synced across all clients)

export 'room_config.dart';
export 'room_state.dart';
export 'room_controller.dart';
export 'widgets/lobby_view.dart';
export 'widgets/room_setup_view.dart';
export 'widgets/auto_close_timer.dart';
export 'widgets/cancel_room_button.dart';
export 'widgets/back_button_guard.dart';
export 'widgets/room_exit_guard.dart';
export 'widgets/room_close_dialog.dart';
export 'widgets/match_countdown.dart';

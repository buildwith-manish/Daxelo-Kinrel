// lib/features/games/shared/multiplayer/widgets/room_keep_alive.dart
//
// RoomKeepAlive — keeps the autoDispose `roomControllerProvider` alive
// while a GAME screen is mounted.
//
// WHY THIS EXISTS
//   The ChallengeLobbyScreen (board games) attaches the RoomController
//   (attachToExistingGame) — which starts the 20s `fn_player_heartbeat`
//   that refreshes `game_participants.lastSeenAt` — and then
//   pushReplacement-navigates to the board route. The lobby widget
//   unmounts, `roomControllerProvider` is autoDispose, nothing else
//   watches it → the controller (and its heartbeat) is disposed within
//   a frame. ~60-75s later the server-side reaper
//   (fn_reap_disconnected_players) sees the host's stale lastSeenAt,
//   marks them disconnected and AUTO-CLOSES the room mid-game.
//
//   Wrapping the board screen in this widget keeps a watch on the
//   provider for the whole lifetime of the screen, so the heartbeat +
//   room realtime subscriptions survive the lobby → board navigation.
//
//   For a player who never attached a controller (e.g. the opponent
//   accepting an invite lands directly on the board), the watch simply
//   creates an idle controller — no gameId, no timers, no side effects.
//
// USAGE
//   RoomKeepAlive(
//     roomKey: RoomControllerKey(RoomConfig.chess, familyId),
//     child: _buildBoard(...),
//   );

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../room_controller.dart';

class RoomKeepAlive extends ConsumerWidget {
  const RoomKeepAlive({
    super.key,
    required this.roomKey,
    required this.child,
  });

  final RoomControllerKey roomKey;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The watch itself is the whole point — it registers a dependency
    // that keeps the autoDispose controller (and its heartbeat timer)
    // alive for as long as this screen is mounted.
    ref.watch(roomControllerProvider(roomKey));
    return child;
  }
}

// lib/features/games/carrom/carrom_lobby_screen.dart
//
// Carrom — Create Room lobby.
// Route: /family/$familyId/carrom/lobby
//
// v3 (Create Room flow): the "Select Opponent" step is gone. Carrom now
// uses the same flow as every other multiplayer game — one "Create
// Room" button creates the room immediately (host plays White), the
// host invites family members from the waiting room, and the first
// member to join plays Black automatically.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/models/game_invite.dart';
import '../shared/widgets/board_game_room_lobby.dart';
import '../shared/widgets/lobby_kit/lobby_kit.dart';
import 'carrom_provider.dart';

class CarromLobbyScreen extends ConsumerWidget {
  const CarromLobbyScreen({super.key, required this.familyId});
  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return BoardGameRoomLobbyScreen(
      familyId: familyId,
      spec: BoardGameRoomSpec(
        gameId: 'carrom',
        title: 'Carrom',
        tagline: 'Flick, pot, cover the queen',
        gameTable: 'carrom_games',
        routeSegment: 'carrom',
        gameType: GameType.carrom,
        maxPlayers: 2,
        facts: const [
          LobbyFact(icon: Icons.person_outline, label: '1 v 1'),
          LobbyFact(icon: Icons.timer_outlined, label: 'Flick physics'),
        ],
        rules: const [
          LobbyRule('Drag from the striker to aim, release to flick.'),
          LobbyRule('Pot your own color coins to score + get extra turn.'),
          LobbyRule('Potting opponent\'s color passes your turn.'),
          LobbyRule('Pot the queen + cover with your color in same/next turn.'),
          LobbyRule('Don\'t pot the striker — it\'s a foul!'),
          LobbyRule('First to pot all coins (+ covered queen) wins.'),
        ],
        waitingRoomNote:
            'You play White and flick first. The first family member to '
            'join the room plays Black — no side picking needed.',
        watchRoom: (ref, familyId) {
          final s = ref.watch(carromProvider(familyId));
          // A completed game is not a room — "Play Again" from the
          // results screen always lands on a fresh Create Room setup.
          final roomOpen = s.game != null && !s.isCompleted;
          return BoardRoomSnapshot(
            gameId: roomOpen ? s.game?.id : null,
            hostUserId: roomOpen ? s.game?.hostUserId : null,
            isWaiting: roomOpen && s.isWaiting,
            isInProgress: roomOpen && s.isInProgress,
            isCompleted: false,
            isLoading: s.isLoading,
            error: roomOpen ? s.error : null,
            autoCloseDeadline: roomOpen ? s.game?.autoCloseDeadline : null,
          );
        },
        onCreateRoom: (ref, familyId, {required spectatorsEnabled}) => ref
            .read(carromProvider(familyId).notifier)
            .createRoom(spectatorsEnabled: spectatorsEnabled),
        onJoinRoom: (ref, familyId, gameId) =>
            ref.read(carromProvider(familyId).notifier).joinRoom(gameId),
        onStartMatch: (ref, familyId) =>
            ref.read(carromProvider(familyId).notifier).startMatch(),
        onLeaveRoom: (ref, familyId) =>
            ref.read(carromProvider(familyId).notifier).leaveRoom(),
      ),
    );
  }
}

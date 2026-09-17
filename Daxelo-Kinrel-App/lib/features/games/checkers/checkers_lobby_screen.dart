// lib/features/games/checkers/checkers_lobby_screen.dart
//
// Checkers — Create Room lobby.
// Route: /family/$familyId/checkers/lobby
//
// v3 (Create Room flow): the "Select Opponent" step is gone. Checkers
// now uses the same flow as every other multiplayer game — one "Create
// Room" button creates the room immediately (host plays Red), the host
// invites family members from the waiting room, and the first member
// to join plays Black automatically.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/models/game_invite.dart';
import '../shared/widgets/board_game_room_lobby.dart';
import '../shared/widgets/lobby_kit/lobby_kit.dart';
import 'checkers_provider.dart';

class CheckersLobbyScreen extends ConsumerWidget {
  const CheckersLobbyScreen({super.key, required this.familyId});
  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return BoardGameRoomLobbyScreen(
      familyId: familyId,
      spec: BoardGameRoomSpec(
        gameId: 'checkers',
        title: 'Checkers',
        tagline: 'Jump, capture, crown your kings',
        gameTable: 'checkers_games',
        routeSegment: 'checkers',
        gameType: GameType.checkers,
        maxPlayers: 2,
        facts: const [
          LobbyFact(icon: Icons.person_outline, label: '1 v 1'),
          LobbyFact(icon: Icons.timer_outlined, label: '~10 min'),
        ],
        rules: const [
          LobbyRule('Pieces move diagonally forward 1 square.'),
          LobbyRule('Capture by jumping over an opponent\'s piece.'),
          LobbyRule('Captures are mandatory — you must take them.'),
          LobbyRule('Multi-jumps: keep jumping if more captures available.'),
          LobbyRule('Reach the far row → become a King (moves any direction).'),
          LobbyRule('Win by capturing all pieces or blocking all moves.'),
        ],
        waitingRoomNote:
            'You play Red and move first. The first family member to join '
            'the room plays Black — no side picking needed.',
        watchRoom: (ref, familyId) {
          final s = ref.watch(checkersProvider(familyId));
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
            .read(checkersProvider(familyId).notifier)
            .createRoom(spectatorsEnabled: spectatorsEnabled),
        onJoinRoom: (ref, familyId, gameId) =>
            ref.read(checkersProvider(familyId).notifier).joinRoom(gameId),
        onStartMatch: (ref, familyId) =>
            ref.read(checkersProvider(familyId).notifier).startMatch(),
        onLeaveRoom: (ref, familyId) =>
            ref.read(checkersProvider(familyId).notifier).leaveRoom(),
      ),
    );
  }
}

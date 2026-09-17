// lib/features/games/tictactoe/tictactoe_lobby_screen.dart
//
// Tic-Tac-Toe — Create Room lobby.
// Route: /family/$familyId/tictactoe/lobby
//
// v3 (Create Room flow): the "Select Opponent" step is gone. Tic-Tac-Toe
// now uses the same flow as every other multiplayer game — one "Create
// Room" button creates the room immediately (host plays X), the host
// invites family members from the waiting room, and the first member
// to join plays O automatically. The BEST OF selector stays.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/models/game_invite.dart';
import '../shared/widgets/board_game_room_lobby.dart';
import '../shared/widgets/lobby_kit/lobby_kit.dart';
import 'tictactoe_provider.dart';

class TttLobbyScreen extends ConsumerStatefulWidget {
  const TttLobbyScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<TttLobbyScreen> createState() => _TttLobbyScreenState();
}

class _TttLobbyScreenState extends ConsumerState<TttLobbyScreen> {
  int _bestOf = 1;

  @override
  Widget build(BuildContext context) {
    return BoardGameRoomLobbyScreen(
      familyId: widget.familyId,
      spec: BoardGameRoomSpec(
        gameId: 'tictactoe',
        title: 'Tic-Tac-Toe',
        tagline: 'Three in a row, best-of series',
        gameTable: 'tictactoe_games',
        routeSegment: 'tictactoe',
        gameType: GameType.tictactoe,
        maxPlayers: 2,
        facts: [
          const LobbyFact(icon: Icons.person_outline, label: '1 v 1'),
          LobbyFact(
              icon: Icons.bolt_outlined,
              label: _bestOf == 1 ? 'Quick match' : 'Best of $_bestOf'),
        ],
        rules: const [
          LobbyRule('Tap any empty cell to place your mark.'),
          LobbyRule('Line up 3 in a row — horizontal, vertical or diagonal.'),
          LobbyRule('Best of N: first to win the majority of boards wins.'),
          LobbyRule('Boards alternate starting player between games.'),
        ],
        settings: LobbySection(
          label: 'Best Of',
          child: LobbyNumberRow(
            numbers: const [1, 3, 5],
            selected: _bestOf,
            onSelect: (n) => setState(() => _bestOf = n),
          ),
        ),
        waitingRoomNote:
            'You play X and move first. The first family member to join '
            'the room plays O — no side picking needed.',
        watchRoom: (ref, familyId) {
          final s = ref.watch(tttProvider(familyId));
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
        onCreateRoom: (ref, familyId, {required spectatorsEnabled}) =>
            ref.read(tttProvider(familyId).notifier).createRoom(
                  spectatorsEnabled: spectatorsEnabled,
                  bestOf: _bestOf,
                ),
        onJoinRoom: (ref, familyId, gameId) =>
            ref.read(tttProvider(familyId).notifier).joinRoom(gameId),
        onStartMatch: (ref, familyId) =>
            ref.read(tttProvider(familyId).notifier).startMatch(),
        onLeaveRoom: (ref, familyId) =>
            ref.read(tttProvider(familyId).notifier).leaveRoom(),
      ),
    );
  }
}

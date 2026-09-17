// lib/features/games/chess/chess_lobby_screen.dart
//
// Chess — Create Room lobby.
// Route: /family/$familyId/chess/lobby
//
// v3 (Create Room flow): the "Select Opponent" step is gone. Chess now
// uses the same flow as every other multiplayer game — one "Create
// Room" button creates the room immediately (host plays White), the
// host invites family members from the waiting room, and the first
// member to join takes the Black side automatically.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/models/game_invite.dart';
import '../shared/widgets/board_game_room_lobby.dart';
import '../shared/widgets/lobby_kit/lobby_kit.dart';
import 'chess_provider.dart';

class ChessLobbyScreen extends ConsumerWidget {
  const ChessLobbyScreen({super.key, required this.familyId});
  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return BoardGameRoomLobbyScreen(
      familyId: familyId,
      spec: BoardGameRoomSpec(
        gameId: 'chess',
        title: 'Chess',
        tagline: 'The classic duel of kings',
        gameTable: 'chess_games',
        routeSegment: 'chess',
        gameType: GameType.chess,
        maxPlayers: 2,
        facts: const [
          LobbyFact(icon: Icons.person_outline, label: '1 v 1'),
          LobbyFact(icon: Icons.timer_outlined, label: '~15 min'),
        ],
        rules: const [
          LobbyRule('Standard chess rules — all special moves supported.'),
          LobbyRule('Tap a piece to select it, tap a destination to move.'),
          LobbyRule('Castling, en passant, and pawn promotion all work.'),
          LobbyRule('Checkmate to win; stalemate = draw.'),
        ],
        waitingRoomNote:
            'You play White and move first. The first family member to '
            'join the room plays Black — no side picking needed.',
        watchRoom: (ref, familyId) {
          final s = ref.watch(chessProvider(familyId));
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
            .read(chessProvider(familyId).notifier)
            .createRoom(spectatorsEnabled: spectatorsEnabled),
        onJoinRoom: (ref, familyId, gameId) =>
            ref.read(chessProvider(familyId).notifier).joinRoom(gameId),
        onStartMatch: (ref, familyId) =>
            ref.read(chessProvider(familyId).notifier).startMatch(),
        onLeaveRoom: (ref, familyId) =>
            ref.read(chessProvider(familyId).notifier).leaveRoom(),
      ),
    );
  }
}

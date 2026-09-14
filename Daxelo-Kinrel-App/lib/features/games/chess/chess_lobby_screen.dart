// lib/features/games/chess/chess_lobby_screen.dart
//
// Chess — Lobby screen to pick an opponent from family members.
// Route: /family/$familyId/chess/lobby
//
// v2 (premium lobby system): the four board games share ONE challenge
// lobby (ChallengeLobbyScreen). Chess now supplies only its identity,
// rules and provider call — the unified layout (compact hero, opponent
// list, room options, collapsible How to Play, pinned Challenge CTA)
// lives in the shared screen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/models/game_invite.dart';
import '../shared/multiplayer/multiplayer.dart';
import '../shared/widgets/lobby_kit/lobby_kit.dart';
import 'chess_provider.dart';

class ChessLobbyScreen extends ConsumerWidget {
  const ChessLobbyScreen({super.key, required this.familyId});
  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ChallengeLobbyScreen(
      familyId: familyId,
      spec: ChallengeLobbySpec(
        gameId: 'chess',
        title: 'Chess',
        tagline: 'The classic duel of kings',
        versusNote:
            'You play as White and move first. Your opponent plays as Black.',
        gameType: GameType.chess,
        routeSegment: 'chess',
        roomConfig: RoomConfig.chess,
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
        onCreateGame: (ref, familyId, args) =>
            ref.read(chessProvider(familyId).notifier).createGame(
                  opponentId: args.opponentId,
                  opponentName: args.opponentName,
                ),
      ),
    );
  }
}

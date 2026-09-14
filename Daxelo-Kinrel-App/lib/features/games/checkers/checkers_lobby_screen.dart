// lib/features/games/checkers/checkers_lobby_screen.dart
//
// Checkers — Lobby screen to pick an opponent from family members.
// Route: /family/$familyId/checkers/lobby
//
// v2 (premium lobby system): shared ChallengeLobbyScreen — Checkers
// supplies only identity, rules and its provider call.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/models/game_invite.dart';
import '../shared/multiplayer/multiplayer.dart';
import '../shared/widgets/lobby_kit/lobby_kit.dart';
import 'checkers_provider.dart';

class CheckersLobbyScreen extends ConsumerWidget {
  const CheckersLobbyScreen({super.key, required this.familyId});
  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ChallengeLobbyScreen(
      familyId: familyId,
      spec: ChallengeLobbySpec(
        gameId: 'checkers',
        title: 'Checkers',
        tagline: 'Jump, capture, crown your kings',
        versusNote:
            'You play as Red (moves first). Your opponent plays as Black.',
        gameType: GameType.checkers,
        routeSegment: 'checkers',
        roomConfig: RoomConfig.checkers,
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
        onCreateGame: (ref, familyId, args) =>
            ref.read(checkersProvider(familyId).notifier).createGame(
                  opponentId: args.opponentId,
                  opponentName: args.opponentName,
                ),
      ),
    );
  }
}

// lib/features/games/tictactoe/tictactoe_lobby_screen.dart
//
// Tic-Tac-Toe — Lobby screen to pick an opponent from family members.
// Route: /family/$familyId/tictactoe/lobby
//
// v2 (premium lobby system): shared ChallengeLobbyScreen — Tic-Tac-Toe
// supplies identity, BEST OF selector (via extraSettings), rules and
// its provider call.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/models/game_invite.dart';
import '../shared/multiplayer/multiplayer.dart';
import '../shared/widgets/lobby_kit/lobby_kit.dart';
import 'tictactoe_provider.dart';

class TttLobbyScreen extends ConsumerWidget {
  const TttLobbyScreen({super.key, required this.familyId});
  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ChallengeLobbyScreen(
      familyId: familyId,
      spec: ChallengeLobbySpec(
        gameId: 'tictactoe',
        title: 'Tic-Tac-Toe',
        tagline: 'Three in a row, best-of series',
        versusNote:
            'You play as X and move first. Your opponent plays as O.',
        gameType: GameType.tictactoe,
        routeSegment: 'tictactoe',
        roomConfig: RoomConfig.tictactoe,
        facts: const [
          LobbyFact(icon: Icons.person_outline, label: '1 v 1'),
          LobbyFact(icon: Icons.bolt_outlined, label: 'Quick match'),
        ],
        rules: const [
          LobbyRule('Tap any empty cell to place your mark.'),
          LobbyRule('Line up 3 in a row — horizontal, vertical or diagonal.'),
          LobbyRule('Best of N: first to win the majority of boards wins.'),
          LobbyRule('Boards alternate starting player between games.'),
        ],
        extraSettings: ChallengeExtraSettings(
          defaults: const {'bestOf': 1},
          builder: (values, onChanged) => LobbySection(
            label: 'Best Of',
            child: LobbyNumberRow(
              numbers: const [1, 3, 5],
              selected: (values['bestOf'] as int? ?? 1),
              onSelect: (n) => onChanged({...values, 'bestOf': n}),
            ),
          ),
        ),
        onCreateGame: (ref, familyId, args) =>
            ref.read(tttProvider(familyId).notifier).createGame(
                  opponentId: args.opponentId,
                  opponentName: args.opponentName,
                  bestOf: (args.extra['bestOf'] as int? ?? 1),
                ),
      ),
    );
  }
}

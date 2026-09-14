// lib/features/games/carrom/carrom_lobby_screen.dart
//
// Carrom — Lobby screen to pick an opponent from family members.
// Route: /family/$familyId/carrom/lobby
//
// v2 (premium lobby system): shared ChallengeLobbyScreen — Carrom
// supplies only identity, rules and its provider call.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/models/game_invite.dart';
import '../shared/multiplayer/multiplayer.dart';
import '../shared/widgets/lobby_kit/lobby_kit.dart';
import 'carrom_provider.dart';

class CarromLobbyScreen extends ConsumerWidget {
  const CarromLobbyScreen({super.key, required this.familyId});
  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ChallengeLobbyScreen(
      familyId: familyId,
      spec: ChallengeLobbySpec(
        gameId: 'carrom',
        title: 'Carrom',
        tagline: 'Flick, pot, cover the queen',
        versusNote:
            'You play as White (moves first). Your opponent plays as Black.',
        gameType: GameType.carrom,
        routeSegment: 'carrom',
        roomConfig: RoomConfig.carrom,
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
        onCreateGame: (ref, familyId, args) =>
            ref.read(carromProvider(familyId).notifier).createGame(
                  opponentId: args.opponentId,
                  opponentName: args.opponentName,
                ),
      ),
    );
  }
}

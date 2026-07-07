// test/features/games/chitmatch/chitmatch_game_logic_test.dart
//
// Tests for TripleMatch game logic:
//   • Simultaneous pass resolution for 4-12 players
//   • Joint winner detection
//   • Chit generation, shuffle, deal
//   • Auto-select fallback
//   • 3-of-a-kind detection

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/games/chitmatch/chitmatch_game_logic.dart';

void main() {
  group('generateChits', () {
    test('generates 3 chits per player', () {
      final players = [
        ChitmatchPlayer(userId: 'p1', userName: 'Alice', turnOrder: 0, submittedWord: 'Tiger', hand: []),
        ChitmatchPlayer(userId: 'p2', userName: 'Bob', turnOrder: 1, submittedWord: 'Lion', hand: []),
        ChitmatchPlayer(userId: 'p3', userName: 'Carol', turnOrder: 2, submittedWord: 'Bear', hand: []),
        ChitmatchPlayer(userId: 'p4', userName: 'Dave', turnOrder: 3, submittedWord: 'Wolf', hand: []),
      ];

      final chits = generateChits(players);
      expect(chits.length, 12); // 4 players × 3 chits
      expect(chits.where((c) => c == 'Tiger').length, 3);
      expect(chits.where((c) => c == 'Lion').length, 3);
      expect(chits.where((c) => c == 'Bear').length, 3);
      expect(chits.where((c) => c == 'Wolf').length, 3);
    });

    test('throws if a player has not submitted a word', () {
      final players = [
        ChitmatchPlayer(userId: 'p1', userName: 'Alice', turnOrder: 0, submittedWord: null, hand: []),
      ];
      expect(() => generateChits(players), throwsStateError);
    });
  });

  group('dealChits', () {
    test('deals exactly 3 chits per player', () {
      final players = [
        ChitmatchPlayer(userId: 'p1', userName: 'A', turnOrder: 0, submittedWord: 'Cat', hand: []),
        ChitmatchPlayer(userId: 'p2', userName: 'B', turnOrder: 1, submittedWord: 'Dog', hand: []),
        ChitmatchPlayer(userId: 'p3', userName: 'C', turnOrder: 2, submittedWord: 'Fish', hand: []),
        ChitmatchPlayer(userId: 'p4', userName: 'D', turnOrder: 3, submittedWord: 'Bird', hand: []),
      ];
      final chits = generateChits(players);
      dealChits(players, chits);

      for (final p in players) {
        expect(p.hand.length, 3);
      }
    });

    test('shuffles chits (not all in original order)', () {
      // Run multiple times to verify shuffling actually happens
      bool wasShuffled = false;
      for (int attempt = 0; attempt < 50; attempt++) {
        final players = [
          ChitmatchPlayer(userId: 'p1', userName: 'A', turnOrder: 0, submittedWord: 'AAA', hand: []),
          ChitmatchPlayer(userId: 'p2', userName: 'B', turnOrder: 1, submittedWord: 'BBB', hand: []),
          ChitmatchPlayer(userId: 'p3', userName: 'C', turnOrder: 2, submittedWord: 'CCC', hand: []),
          ChitmatchPlayer(userId: 'p4', userName: 'D', turnOrder: 3, submittedWord: 'DDD', hand: []),
        ];
        final chits = generateChits(players);
        dealChits(players, chits);

        // If not all players got their own word, it was shuffled
        if (!players.every((p) => p.hand.every((c) => c == p.submittedWord))) {
          wasShuffled = true;
          break;
        }
      }
      expect(wasShuffled, true, reason: 'Chits should be shuffled on at least one deal');
    });
  });

  group('resolveRound — simultaneous pass resolution', () {
    test('4 players: each player passes 1 chit clockwise', () {
      final players = [
        ChitmatchPlayer(userId: 'p1', userName: 'A', turnOrder: 0, submittedWord: 'W1', hand: ['X', 'Y', 'Z'], selectedChitIndex: 0),
        ChitmatchPlayer(userId: 'p2', userName: 'B', turnOrder: 1, submittedWord: 'W2', hand: ['A', 'B', 'C'], selectedChitIndex: 1),
        ChitmatchPlayer(userId: 'p3', userName: 'C', turnOrder: 2, submittedWord: 'W3', hand: ['D', 'E', 'F'], selectedChitIndex: 2),
        ChitmatchPlayer(userId: 'p4', userName: 'D', turnOrder: 3, submittedWord: 'W4', hand: ['G', 'H', 'I'], selectedChitIndex: 0),
      ];

      final result = resolveRound(players);

      // p1 passed 'X' (index 0) to p2
      // p2 passed 'B' (index 1) to p3
      // p3 passed 'F' (index 2) to p4
      // p4 passed 'G' (index 0) to p1

      // p1 should have ['Y', 'Z', 'G'] (removed X at 0, received G from p4)
      expect(result.updatedPlayers[0].hand, containsAll(['Y', 'Z', 'G']));
      expect(result.updatedPlayers[0].hand.length, 3);

      // p2 should have ['A', 'C', 'X'] (removed B at 1, received X from p1)
      expect(result.updatedPlayers[1].hand, containsAll(['A', 'C', 'X']));
      expect(result.updatedPlayers[1].hand.length, 3);

      // p3 should have ['D', 'E', 'B'] (removed F at 2, received B from p2)
      expect(result.updatedPlayers[2].hand, containsAll(['D', 'E', 'B']));
      expect(result.updatedPlayers[2].hand.length, 3);

      // p4 should have ['H', 'I', 'F'] (removed G at 0, received F from p3)
      expect(result.updatedPlayers[3].hand, containsAll(['H', 'I', 'F']));
      expect(result.updatedPlayers[3].hand.length, 3);

      // Passes recorded correctly
      expect(result.passes.length, 4);
      expect(result.passes[0].fromUserId, 'p1');
      expect(result.passes[0].toUserId, 'p2');
      expect(result.passes[0].chitWord, 'X');
    });

    test('12 players: all passes resolve correctly', () {
      final players = List.generate(12, (i) => ChitmatchPlayer(
        userId: 'p$i', userName: 'P$i', turnOrder: i,
        submittedWord: 'Word$i',
        hand: ['chit_${i}_0', 'chit_${i}_1', 'chit_${i}_2'],
        selectedChitIndex: 0, // each passes their first chit
      ));

      final result = resolveRound(players);

      expect(result.updatedPlayers.length, 12);
      expect(result.passes.length, 12);

      // Each player should have 2 remaining chits + 1 received
      for (int i = 0; i < 12; i++) {
        expect(result.updatedPlayers[i].hand.length, 3);
      }

      // Player 0 should receive from player 11 (wrapping)
      // Player 0 passed 'chit_0_0', kept 'chit_0_1' and 'chit_0_2'
      // Received 'chit_11_0' from player 11
      expect(result.updatedPlayers[0].hand, containsAll(['chit_0_1', 'chit_0_2', 'chit_11_0']));

      // Player 5 should receive from player 4
      expect(result.updatedPlayers[5].hand, containsAll(['chit_5_1', 'chit_5_2', 'chit_4_0']));

      // Player 11 should receive from player 10
      expect(result.updatedPlayers[11].hand, containsAll(['chit_11_1', 'chit_11_2', 'chit_10_0']));
    });

    test('6 players: wrap-around pass is correct', () {
      final players = List.generate(6, (i) => ChitmatchPlayer(
        userId: 'p$i', userName: 'P$i', turnOrder: i,
        submittedWord: 'W$i',
        hand: ['a$i', 'b$i', 'c$i'],
        selectedChitIndex: 2, // each passes their third chit
      ));

      final result = resolveRound(players);

      // Player 0 passes 'c0' to player 1, receives 'c5' from player 5
      expect(result.updatedPlayers[0].hand, containsAll(['a0', 'b0', 'c5']));
      // Player 5 passes 'c5' to player 0, receives 'c4' from player 4
      expect(result.updatedPlayers[5].hand, containsAll(['a5', 'b5', 'c4']));
    });

    test('8 players: all hands still 3 chits after resolution', () {
      final players = List.generate(8, (i) => ChitmatchPlayer(
        userId: 'p$i', userName: 'P$i', turnOrder: i,
        submittedWord: 'W$i',
        hand: ['x$i', 'y$i', 'z$i'],
        selectedChitIndex: i % 3,
      ));

      final result = resolveRound(players);
      expect(validateHands(result.updatedPlayers), true);
    });

    test('10 players: no chits lost or duplicated', () {
      final players = List.generate(10, (i) => ChitmatchPlayer(
        userId: 'p$i', userName: 'P$i', turnOrder: i,
        submittedWord: 'W$i',
        hand: ['h${i}_0', 'h${i}_1', 'h${i}_2'],
        selectedChitIndex: 1,
      ));

      final result = resolveRound(players);

      // Collect all chits from all hands — should be 30 unique chits
      final allChits = <String>{};
      for (final p in result.updatedPlayers) {
        allChits.addAll(p.hand);
      }
      expect(allChits.length, 30, reason: 'No chits should be lost or duplicated');
    });
  });

  group('resolveRound — win detection', () {
    test('single winner detected when one player gets 3-of-a-kind', () {
      final players = [
        ChitmatchPlayer(userId: 'p1', userName: 'A', turnOrder: 0, submittedWord: 'W1', hand: ['LION', 'cat', 'dog'], selectedChitIndex: 0),
        ChitmatchPlayer(userId: 'p2', userName: 'B', turnOrder: 1, submittedWord: 'W2', hand: ['LION', 'x', 'y'], selectedChitIndex: 0),
        ChitmatchPlayer(userId: 'p3', userName: 'C', turnOrder: 2, submittedWord: 'W3', hand: ['LION', 'a', 'b'], selectedChitIndex: 0),
        ChitmatchPlayer(userId: 'p4', userName: 'D', turnOrder: 3, submittedWord: 'W4', hand: ['LION', 'm', 'n'], selectedChitIndex: 0),
      ];

      // After passing:
      // p1 passes 'LION' to p2, receives 'LION' from p4 → ['cat', 'dog', 'LION'] — no match
      // p2 passes 'LION' to p3, receives 'LION' from p1 → ['x', 'y', 'LION'] — no match
      // p3 passes 'LION' to p4, receives 'LION' from p2 → ['a', 'b', 'LION'] — no match
      // p4 passes 'LION' to p1, receives 'LION' from p3 → ['m', 'n', 'LION'] — no match
      // Hmm, none have 3-of-a-kind. Let me set up a scenario where someone wins.

      // Better: p1 has 2 LIONs and passes one that ISN'T a LION,
      // and receives a LION from p4.
      final players2 = [
        ChitmatchPlayer(userId: 'p1', userName: 'A', turnOrder: 0, submittedWord: 'W1', hand: ['LION', 'LION', 'cat'], selectedChitIndex: 2), // passes 'cat', keeps 2 LIONs
        ChitmatchPlayer(userId: 'p2', userName: 'B', turnOrder: 1, submittedWord: 'W2', hand: ['dog', 'x', 'y'], selectedChitIndex: 0),
        ChitmatchPlayer(userId: 'p3', userName: 'C', turnOrder: 2, submittedWord: 'W3', hand: ['bird', 'a', 'b'], selectedChitIndex: 0),
        ChitmatchPlayer(userId: 'p4', userName: 'D', turnOrder: 3, submittedWord: 'W4', hand: ['LION', 'm', 'n'], selectedChitIndex: 0), // passes 'LION' to p1
      ];

      final result = resolveRound(players2);

      // p1: kept ['LION', 'LION'], removed 'cat' at index 2, received 'LION' from p4
      // → hand = ['LION', 'LION', 'LION'] — 3-of-a-kind!
      expect(result.winners.length, 1);
      expect(result.winners[0].userId, 'p1');
      expect(result.winners[0].hasThreeOfAKind, true);
    });

    test('joint winners detected when multiple players get 3-of-a-kind simultaneously', () {
      // Set up so that TWO players both get 3-of-a-kind in the same round.
      // p1 has [TIGER, TIGER, x] → passes x → receives TIGER from p4 → [TIGER, TIGER, TIGER]
      // p2 has [TIGER, TIGER, y] → passes y → receives TIGER from p1? No, p1 passes 'x'.
      // Let me think more carefully.
      //
      // Pass direction: p1→p2, p2→p3, p3→p4, p4→p1
      // p1 passes index 2 ('cat'), receives from p4
      // p2 passes index 2 ('dog'), receives from p1
      // p3 passes index 2 ('fish'), receives from p2
      // p4 passes index 2 ('TIGER'), receives from p3
      //
      // For p1 to win: needs to receive a TIGER from p4 → p4 passes TIGER
      // For p2 to win: needs to receive a TIGER from p1 → p1 passes TIGER
      // But p1 passes 'cat' (index 2). So p1 can't both pass a TIGER and receive one.
      //
      // Alternative: use different words for each winner.
      // p1 has [LION, LION, cat] → passes cat → receives LION from p4 → wins with LION
      // p3 has [BEAR, BEAR, fish] → passes fish → receives BEAR from p2 → wins with BEAR
      // p2 has [BEAR, x, y] → passes x → sends to p3 (but p3 needs BEAR)
      // Wait, p2 passes to p3. If p2 passes BEAR, p3 gets BEAR.
      // p4 has [LION, m, n] → passes LION → sends to p1. p1 gets LION.
      //
      // So:
      // p1: [LION, LION, cat] → passes cat(2) → receives LION from p4 → [LION, LION, LION] ✓
      // p2: [BEAR, x, y] → passes BEAR(0) → sends to p3
      // p3: [BEAR, BEAR, fish] → passes fish(2) → receives BEAR from p2 → [BEAR, BEAR, BEAR] ✓
      // p4: [LION, m, n] → passes LION(0) → sends to p1 → receives fish from p3

      final players = [
        ChitmatchPlayer(userId: 'p1', userName: 'A', turnOrder: 0, submittedWord: 'W1', hand: ['LION', 'LION', 'cat'], selectedChitIndex: 2),
        ChitmatchPlayer(userId: 'p2', userName: 'B', turnOrder: 1, submittedWord: 'W2', hand: ['BEAR', 'x', 'y'], selectedChitIndex: 0),
        ChitmatchPlayer(userId: 'p3', userName: 'C', turnOrder: 2, submittedWord: 'W3', hand: ['BEAR', 'BEAR', 'fish'], selectedChitIndex: 2),
        ChitmatchPlayer(userId: 'p4', userName: 'D', turnOrder: 3, submittedWord: 'W4', hand: ['LION', 'm', 'n'], selectedChitIndex: 0),
      ];

      final result = resolveRound(players);

      expect(result.winners.length, 2, reason: 'Both p1 and p3 should win simultaneously');
      final winnerIds = result.winners.map((p) => p.userId).toSet();
      expect(winnerIds.contains('p1'), true);
      expect(winnerIds.contains('p3'), true);
    });

    test('no winners when no one has 3-of-a-kind', () {
      final players = [
        ChitmatchPlayer(userId: 'p1', userName: 'A', turnOrder: 0, submittedWord: 'W1', hand: ['cat', 'dog', 'bird'], selectedChitIndex: 0),
        ChitmatchPlayer(userId: 'p2', userName: 'B', turnOrder: 1, submittedWord: 'W2', hand: ['x', 'y', 'z'], selectedChitIndex: 1),
        ChitmatchPlayer(userId: 'p3', userName: 'C', turnOrder: 2, submittedWord: 'W3', hand: ['a', 'b', 'c'], selectedChitIndex: 2),
        ChitmatchPlayer(userId: 'p4', userName: 'D', turnOrder: 3, submittedWord: 'W4', hand: ['m', 'n', 'o'], selectedChitIndex: 0),
      ];

      final result = resolveRound(players);
      expect(result.winners.length, 0);
    });
  });

  group('autoSelectUnselected', () {
    test('auto-selects for players who haven\'t chosen', () {
      final players = [
        ChitmatchPlayer(userId: 'p1', userName: 'A', turnOrder: 0, submittedWord: 'W1', hand: ['a', 'b', 'c'], selectedChitIndex: 1),
        ChitmatchPlayer(userId: 'p2', userName: 'B', turnOrder: 1, submittedWord: 'W2', hand: ['d', 'e', 'f'], selectedChitIndex: null),
        ChitmatchPlayer(userId: 'p3', userName: 'C', turnOrder: 2, submittedWord: 'W3', hand: ['g', 'h', 'i'], selectedChitIndex: null),
      ];

      autoSelectUnselected(players);

      // p1 already had index 1
      expect(players[0].selectedChitIndex, 1);
      // p2 and p3 now have a valid index (0, 1, or 2)
      expect(players[1].selectedChitIndex, isNotNull);
      expect(players[1].selectedChitIndex! >= 0 && players[1].selectedChitIndex! < 3, true);
      expect(players[2].selectedChitIndex, isNotNull);
      expect(players[2].selectedChitIndex! >= 0 && players[2].selectedChitIndex! < 3, true);
    });
  });

  group('hasThreeOfAKind', () {
    test('true when all 3 chits match', () {
      final player = ChitmatchPlayer(userId: 'p1', userName: 'A', turnOrder: 0, hand: ['TIGER', 'TIGER', 'TIGER']);
      expect(player.hasThreeOfAKind, true);
    });

    test('false when chits don\'t all match', () {
      final player = ChitmatchPlayer(userId: 'p1', userName: 'A', turnOrder: 0, hand: ['TIGER', 'TIGER', 'LION']);
      expect(player.hasThreeOfAKind, false);
    });

    test('false when hand is not 3 chits', () {
      final player = ChitmatchPlayer(userId: 'p1', userName: 'A', turnOrder: 0, hand: ['TIGER', 'TIGER']);
      expect(player.hasThreeOfAKind, false);
    });
  });

  group('resolveRound — edge cases', () {
    test('4 players: pass direction wraps correctly (p4 → p1)', () {
      final players = [
        ChitmatchPlayer(userId: 'p1', userName: 'A', turnOrder: 0, submittedWord: 'W1', hand: ['a1', 'b1', 'c1'], selectedChitIndex: 0),
        ChitmatchPlayer(userId: 'p2', userName: 'B', turnOrder: 1, submittedWord: 'W2', hand: ['a2', 'b2', 'c2'], selectedChitIndex: 0),
        ChitmatchPlayer(userId: 'p3', userName: 'C', turnOrder: 2, submittedWord: 'W3', hand: ['a3', 'b3', 'c3'], selectedChitIndex: 0),
        ChitmatchPlayer(userId: 'p4', userName: 'D', turnOrder: 3, submittedWord: 'W4', hand: ['a4', 'b4', 'c4'], selectedChitIndex: 0),
      ];

      final result = resolveRound(players);

      // p4 passes 'a4' to p1 (wrap around)
      expect(result.updatedPlayers[0].hand, contains('a4'));
      // p1 passes 'a1' to p2
      expect(result.updatedPlayers[1].hand, contains('a1'));
    });

    test('selectedChitIndex reset to null after round', () {
      final players = [
        ChitmatchPlayer(userId: 'p1', userName: 'A', turnOrder: 0, submittedWord: 'W1', hand: ['a', 'b', 'c'], selectedChitIndex: 1),
        ChitmatchPlayer(userId: 'p2', userName: 'B', turnOrder: 1, submittedWord: 'W2', hand: ['d', 'e', 'f'], selectedChitIndex: 0),
        ChitmatchPlayer(userId: 'p3', userName: 'C', turnOrder: 2, submittedWord: 'W3', hand: ['g', 'h', 'i'], selectedChitIndex: 2),
        ChitmatchPlayer(userId: 'p4', userName: 'D', turnOrder: 3, submittedWord: 'W4', hand: ['j', 'k', 'l'], selectedChitIndex: 0),
      ];

      final result = resolveRound(players);
      for (final p in result.updatedPlayers) {
        expect(p.selectedChitIndex, isNull, reason: 'Selection should be reset after round');
      }
    });
  });

  group('getWinnerIds', () {
    test('returns list of winner user IDs', () {
      final players = [
        ChitmatchPlayer(userId: 'p1', userName: 'A', turnOrder: 0, hand: ['X', 'X', 'X']),
        ChitmatchPlayer(userId: 'p2', userName: 'B', turnOrder: 1, hand: ['a', 'b', 'c']),
      ];
      final resolution = RoundResolution(
        updatedPlayers: players,
        passes: [],
        winners: [players[0]],
      );
      expect(getWinnerIds(resolution), ['p1']);
    });

    test('returns multiple IDs for joint winners', () {
      final players = [
        ChitmatchPlayer(userId: 'p1', userName: 'A', turnOrder: 0, hand: ['X', 'X', 'X']),
        ChitmatchPlayer(userId: 'p2', userName: 'B', turnOrder: 1, hand: ['Y', 'Y', 'Y']),
      ];
      final resolution = RoundResolution(
        updatedPlayers: players,
        passes: [],
        winners: players, // both are winners
      );
      expect(getWinnerIds(resolution).length, 2);
    });
  });
}

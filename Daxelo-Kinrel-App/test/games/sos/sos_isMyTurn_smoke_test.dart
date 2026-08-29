// Smoke test for SosState.isMyTurn — would have caught the original bug.
//
// The original bug: SosState had a placeholder `String? get _myId => null;`
// that `isMyTurn` resolved to (Dart finds the local getter first), so
// `isMyTurn` always returned false regardless of who the current player was.
//
// This test verifies that:
//   1. When myUserId matches currentPlayer.userId, isMyTurn is true.
//   2. When myUserId does NOT match currentPlayer.userId, isMyTurn is false.
//   3. When myUserId is null (not signed in), isMyTurn is false.
//   4. The value is preserved across copyWith() calls.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/games/sos/sos_models.dart';
import 'package:kinrel/features/games/sos/sos_provider.dart';

void main() {
  group('SosState.isMyTurn', () {
    final now = DateTime.now();
    final me = SosPlayer(
      id: 'p1',
      gameId: 'g1',
      userId: 'user-me',
      userName: 'Me',
      team: SosTeam.s,
      turnOrder: 0,
      score: 0,
      joinedAt: now,
    );
    final them = SosPlayer(
      id: 'p2',
      gameId: 'g1',
      userId: 'user-them',
      userName: 'Them',
      team: SosTeam.o,
      turnOrder: 1,
      score: 0,
      joinedAt: now,
    );
    final game = SosGame(
      id: 'g1',
      familyId: 'fam1',
      hostUserId: 'user-me',
      hostUserName: 'Me',
      mode: SosMode.twoPlayer,
      gridSize: 7,
      status: SosGameStatus.active,
      currentTurnOrder: 0,
      createdAt: now,
    );

    test('returns true when myUserId matches the current turn player', () {
      final state = SosState(
        game: game,
        players: [me, them],
        myUserId: 'user-me', // <- the real current user id
      );
      expect(state.currentPlayer?.userId, 'user-me');
      expect(state.isMyTurn, isTrue,
          reason: 'It is my turn — myUserId matches currentPlayer');
    });

    test('returns false when it is the opponent\'s turn', () {
      // currentTurnOrder is 0 → currentPlayer is me → opponent's turn means
      // myUserId is set to opponent's id, which does not match.
      final state = SosState(
        game: game,
        players: [me, them],
        myUserId: 'user-them',
      );
      expect(state.currentPlayer?.userId, 'user-me');
      expect(state.isMyTurn, isFalse,
          reason:
              'It is not my turn — myUserId is opponent, currentPlayer is me');
    });

    test('returns false when myUserId is null (not signed in)', () {
      final state = SosState(
        game: game,
        players: [me, them],
        // myUserId deliberately not set — simulates the original buggy state
        // where the placeholder getter returned null.
      );
      expect(state.isMyTurn, isFalse,
          reason: 'If user is not signed in, it is never their turn');
    });

    test('returns false when there are no players yet', () {
      final state = SosState(
        game: game,
        players: const [],
        myUserId: 'user-me',
      );
      expect(state.currentPlayer, isNull);
      expect(state.isMyTurn, isFalse);
    });

    test('myUserId is preserved across copyWith() calls', () {
      final initial = SosState(
        game: game,
        players: [me, them],
        myUserId: 'user-me',
      );
      // Simulate a realtime update that does NOT pass myUserId explicitly
      // — the field must be preserved.
      final updated = initial.copyWith(
        players: [me, them], // same list, e.g. after a score update
      );
      expect(updated.myUserId, 'user-me',
          reason:
              'copyWith must preserve myUserId when not explicitly passed');
      expect(updated.isMyTurn, isTrue,
          reason:
              'isMyTurn must remain true after copyWith preserves myUserId');
    });

    test('myUserId can be explicitly overridden via copyWith()', () {
      final initial = SosState(
        game: game,
        players: [me, them],
        myUserId: 'user-me',
      );
      final updated = initial.copyWith(myUserId: 'user-them');
      expect(updated.myUserId, 'user-them');
      expect(updated.isMyTurn, isFalse);
    });

    test('REGRESSION: myUserId is NOT silently null (the original bug)', () {
      // The original bug: SosState had `String? get _myId => null;` which
      // isMyTurn resolved to. This test fails on the buggy code (because
      // even when myUserId would have been "user-me", isMyTurn returned
      // false). It passes on the fixed code.
      final state = SosState(
        game: game,
        players: [me, them],
        myUserId: 'user-me', // would have been ignored under the bug
      );
      expect(state.isMyTurn, isTrue,
          reason:
              'REGRESSION: isMyTurn must not silently return null from a placeholder');
    });
  });
}

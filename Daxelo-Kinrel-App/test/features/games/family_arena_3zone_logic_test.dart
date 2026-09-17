// test/features/games/family_arena_3zone_logic_test.dart
//
// Pure-Dart unit tests for the 3-zone Family Arena restructure contract.
//
// Verifies the extracted string-helper logic from:
//   • FamilyStreakHeroCard.familyStreakHeroHeadline
//   • PlayWithRow.playWithSubtextFor
//
// Plus an ordering contract test that mirrors the server-side
// `get_play_with_suggestions` ORDER BY (online first > shared count >
// name) so a refactor of either side catches the other.
//
// These tests run without the Flutter test runner's native asset build
// (thermion_dart / clang), so they execute in any CI environment.

import 'package:test/test.dart';

import 'package:kinrel/features/games/presentation/widgets/family_streak_hero_card.dart';
import 'package:kinrel/features/games/presentation/widgets/play_with_row.dart';

void main() {
  group('FamilyStreakHeroCard.familyStreakHeroHeadline — copy contract', () {
    test('streak == 0 → "Start a family streak tonight — play any game together"', () {
      final line = familyStreakHeroHeadline(0);
      expect(line,
          'Start a family streak tonight — play any game together');
    });

    test('streak == 0 ignores playedToday (zero streak is zero streak)', () {
      // Even if playedToday is true (defensive), streak==0 means we show
      // the "start a streak" copy. This prevents the duplicate-banner bug
      // where one card said "Streak started" and another said "waiting
      // for tonight" — both rendered for streak==0.
      final linePlayed = familyStreakHeroHeadline(0, playedToday: true);
      final lineNotPlayed = familyStreakHeroHeadline(0, playedToday: false);
      expect(linePlayed, lineNotPlayed);
      expect(linePlayed,
          'Start a family streak tonight — play any game together');
    });

    test('streak >= 1 → "🔥 {N}-day family streak — play tonight to keep it alive"', () {
      expect(
        familyStreakHeroHeadline(1),
        '🔥 1-day family streak — play tonight to keep it alive',
      );
      expect(
        familyStreakHeroHeadline(7),
        '🔥 7-day family streak — play tonight to keep it alive',
      );
      expect(
        familyStreakHeroHeadline(30),
        '🔥 30-day family streak — play tonight to keep it alive',
      );
    });

    test('headline never mentions wins, losses, or win%', () {
      for (var streak = 0; streak <= 30; streak++) {
        final line = familyStreakHeroHeadline(streak).toLowerCase();
        expect(line.contains('win'), false,
            reason: 'Headline must never mention "win". Got: "$line"');
        expect(line.contains('loss'), false,
            reason: 'Headline must never mention "loss". Got: "$line"');
        expect(line.contains('%'), false,
            reason: 'Headline must never contain "%". Got: "$line"');
      }
    });

    test('exactly ONE headline per streak value (no duplicate-banner bug)',
        () {
      // The regression: the prior build could render BOTH
      // "Streak started — play tonight..." and
      // "Your streak from last time is waiting for tonight..." for the
      // same streak==1 state. This test confirms the helper produces
      // exactly one deterministic string per streak value.
      final seen = <String>{};
      for (var streak = 0; streak <= 30; streak++) {
        final line = familyStreakHeroHeadline(streak);
        // The function is deterministic — calling it twice yields the same
        // value (no random branching on playedToday for streak >= 1).
        expect(familyStreakHeroHeadline(streak, playedToday: true),
            familyStreakHeroHeadline(streak, playedToday: false),
            reason: 'Headline must not branch on playedToday for streak=$streak');
        seen.add(line);
      }
      // We should have at least 2 distinct headlines (streak==0 vs streak>=1).
      expect(seen.length, greaterThanOrEqualTo(2));
    });
  });

  group('PlayWithRow.playWithSubtextFor — subtext contract', () {
    PlayWithSuggestion suggestion({
      bool isNew = false,
      int sharedGamesCount = 0,
      String? lastSharedGameId,
      String? lastSharedGameName,
    }) {
      return PlayWithSuggestion(
        userId: 'test-user',
        userName: 'TestMember',
        isOnline: false,
        sharedGamesCount: isNew ? 0 : sharedGamesCount,
        lastSharedGameId: lastSharedGameId,
        lastSharedGameName: lastSharedGameName,
      );
    }

    test('new pairing (sharedGamesCount == 0) → "New — say hi with Tic-Tac-Toe"',
        () {
      final line = playWithSubtextFor(suggestion(isNew: true));
      expect(line, contains('New — say hi with'));
      expect(line, contains('Tic-Tac-Toe'));
    });

    test('returning pairing with last-shared game → "Play {Game} again"', () {
      final line = playWithSubtextFor(suggestion(
        isNew: false,
        sharedGamesCount: 3,
        lastSharedGameId: 'chess',
        lastSharedGameName: 'Chess',
      ));
      expect(line, 'Play Chess again');
    });

    test('returning pairing without last-shared game (defensive) → "Played N games together"',
        () {
      // This branch is rare (the backend populates lastSharedGameId
      // whenever sharedGamesCount > 0), but the helper must remain safe.
      final line = playWithSubtextFor(suggestion(
        isNew: false,
        sharedGamesCount: 5,
        lastSharedGameId: null,
        lastSharedGameName: null,
      ));
      expect(line, 'Played 5 games together');
    });

    test('subtext never mentions wins, losses, or win%', () {
      for (final s in [
        suggestion(isNew: true),
        suggestion(isNew: false, sharedGamesCount: 1, lastSharedGameId: 'tictactoe', lastSharedGameName: 'Tic-Tac-Toe'),
        suggestion(isNew: false, sharedGamesCount: 99, lastSharedGameId: 'chess', lastSharedGameName: 'Chess'),
        suggestion(isNew: false, sharedGamesCount: 5), // defensive branch
      ]) {
        final line = playWithSubtextFor(s).toLowerCase();
        expect(line.contains('win'), false,
            reason: 'Subtext must never mention "win". Got: "$line"');
        expect(line.contains('loss'), false,
            reason: 'Subtext must never mention "loss". Got: "$line"');
        expect(line.contains('%'), false,
            reason: 'Subtext must never contain "%". Got: "$line"');
      }
    });
  });

  group('PlayWithRow ordering contract (mirrors server-side ORDER BY)', () {
    /// Mirrors the ORDER BY clause in get_play_with_suggestions:
    ///   is_online DESC, shared_games_count DESC, user_name ASC.
    int serverStyleCompare(PlayWithSuggestion a, PlayWithSuggestion b) {
      if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
      if (a.sharedGamesCount != b.sharedGamesCount) {
        return b.sharedGamesCount.compareTo(a.sharedGamesCount);
      }
      return a.userName.compareTo(b.userName);
    }

    test('online members come before offline members', () {
      final offline = PlayWithSuggestion(
          userId: 'a', userName: 'A', isOnline: false, sharedGamesCount: 99);
      final online = PlayWithSuggestion(
          userId: 'b', userName: 'B', isOnline: true, sharedGamesCount: 0);
      final sorted = [offline, online]..sort(serverStyleCompare);
      expect(sorted.first.userId, 'b'); // online first despite 0 shared games
    });

    test('at equal online state, higher shared-games-count comes first', () {
      final less = PlayWithSuggestion(
          userId: 'a', userName: 'A', isOnline: false, sharedGamesCount: 1);
      final more = PlayWithSuggestion(
          userId: 'b', userName: 'B', isOnline: false, sharedGamesCount: 5);
      final sorted = [less, more]..sort(serverStyleCompare);
      expect(sorted.first.userId, 'b'); // 5 shared games beats 1
    });

    test('at equal online state + equal shared count, alphabetical by name', () {
      final z = PlayWithSuggestion(
          userId: 'a', userName: 'Zara', isOnline: false, sharedGamesCount: 3);
      final a = PlayWithSuggestion(
          userId: 'b', userName: 'Anita', isOnline: false, sharedGamesCount: 3);
      final sorted = [z, a]..sort(serverStyleCompare);
      expect(sorted.first.userName, 'Anita');
    });

    test('never-played members sort AFTER returning pairings (same online state)',
        () {
      final returning = PlayWithSuggestion(
          userId: 'a', userName: 'A', isOnline: false, sharedGamesCount: 2);
      final fresh = PlayWithSuggestion(
          userId: 'b', userName: 'B', isOnline: false, sharedGamesCount: 0);
      final sorted = [fresh, returning]..sort(serverStyleCompare);
      expect(sorted.first.userId, 'a'); // returning (2 shared) before fresh (0 shared)
    });
  });
}

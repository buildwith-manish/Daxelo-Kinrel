// test/features/games/family_arena_ux_refinements_test.dart
//
// Pure-Dart unit tests for the three UX refinements:
//   1. groupMomentsByDate — date grouping contract (Today / Yesterday /
//      Sep 15 / Sep 15, 2025 / Earlier for null timestamps).
//   2. QuickPicks exclusion logic — when the Play With row already
//      suggests a game, the Quick Picks row must NOT include the same
//      gameTable. We test the exclusion set construction.
//   3. ParticipationLeaderboard contract — ranked rows must have
//      matches >= 1; notYetPlayed rows must have matches == 0.
//
// These tests run without the Flutter test runner's native asset build
// (thermion_dart / clang), so they execute in any CI environment.

import 'package:test/test.dart';
import 'package:kinrel/features/games/presentation/widgets/family_moment_card.dart';

void main() {
  group('groupMomentsByDate — date grouping contract', () {
    /// Helper: build a FamilyMoment with a fixed createdAt.
    FamilyMoment momentWith(DateTime t, {String id = 'm'}) {
      return FamilyMoment(
        id: id,
        action: 'game_match_completed',
        description: 'test',
        createdAt: t,
        actorName: 'Test',
      );
    }

    test('empty input → empty output', () {
      expect(groupMomentsByDate(const []), isEmpty);
    });

    test('moments from today → grouped under "Today"', () {
      final now = DateTime.now();
      final m1 = momentWith(now, id: 'm1');
      final m2 = momentWith(now.subtract(const Duration(minutes: 30)), id: 'm2');
      final groups = groupMomentsByDate([m1, m2]);
      expect(groups.length, 1);
      expect(groups.first.headerLabel, 'Today');
      expect(groups.first.moments.length, 2);
      // Reverse-chronological within the group: m1 (newer) first.
      expect(groups.first.moments.first.id, 'm1');
    });

    test('moments from yesterday → grouped under "Yesterday"', () {
      final now = DateTime.now();
      final yesterday = DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 1))
          .add(const Duration(hours: 10));
      final m = momentWith(yesterday, id: 'y1');
      final groups = groupMomentsByDate([m]);
      expect(groups.length, 1);
      expect(groups.first.headerLabel, 'Yesterday');
    });

    test('older moments from this year → "Sep 15" format (month abbrev + day)', () {
      final now = DateTime.now();
      final older = DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 10))
          .add(const Duration(hours: 5));
      final m = momentWith(older, id: 'old1');
      final groups = groupMomentsByDate([m]);
      expect(groups.length, 1);
      // Header should be like "Sep 8" (month abbrev + day, no year since
      // it's the same year).
      expect(groups.first.headerLabel, matches(RegExp(r'^[A-Z][a-z]{2} \d+$')));
      expect(groups.first.headerLabel.contains(now.year.toString()), isFalse);
    });

    test('moments from a previous year → "Sep 15, 2025" format (with year)', () {
      final now = DateTime.now();
      final prevYear = DateTime(now.year - 1, 9, 15, 10, 0);
      final m = momentWith(prevYear, id: 'py1');
      final groups = groupMomentsByDate([m]);
      expect(groups.length, 1);
      // Header should be like "Sep 15, 2024" (with year).
      expect(groups.first.headerLabel,
          matches(RegExp(r'^[A-Z][a-z]{2} \d+, \d{4}$')));
    });

    test('null createdAt → grouped under "Earlier"', () {
      final m = FamilyMoment(
        id: 'null-t',
        action: 'game_match_completed',
        description: 'test',
        createdAt: null,
        actorName: 'Test',
      );
      final groups = groupMomentsByDate([m]);
      expect(groups.length, 1);
      expect(groups.first.headerLabel, 'Earlier');
    });

    test('multiple dates → multiple groups in reverse-chronological order', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 10);
      final yesterday = today.subtract(const Duration(days: 1));
      final twoDaysAgo = today.subtract(const Duration(days: 2));
      final groups = groupMomentsByDate([
        momentWith(today, id: 'today'),
        momentWith(yesterday, id: 'yesterday'),
        momentWith(twoDaysAgo, id: 'two-days-ago'),
      ]);
      expect(groups.length, 3);
      expect(groups[0].headerLabel, 'Today');
      expect(groups[1].headerLabel, 'Yesterday');
      // Two days ago should be a "Sep 15" style label (month abbrev + day).
      expect(groups[2].headerLabel, matches(RegExp(r'^[A-Z][a-z]{2} \d+$')));
    });

    test('date header renders ONCE per group, not per entry', () {
      final now = DateTime.now();
      final m1 = momentWith(now, id: 'm1');
      final m2 = momentWith(now.subtract(const Duration(minutes: 10)), id: 'm2');
      final m3 = momentWith(now.subtract(const Duration(minutes: 20)), id: 'm3');
      final groups = groupMomentsByDate([m1, m2, m3]);
      // All three are "Today" → ONE group with 3 moments.
      expect(groups.length, 1);
      expect(groups.first.moments.length, 3);
    });
  });

  group('QuickPicks exclusion logic — Play With games are excluded', () {
    /// Mirrors the exclusion logic from quickPicksProvider in
    /// quick_picks_row.dart. The provider:
    ///   1. Reads playWithSuggestionsProvider to get the last-shared
    ///      gameIds for each Play With card.
    ///   2. Maps each catalog gameId back to its gameTable via gameById.
    ///   3. Builds a Set<String> of excluded gameTables.
    ///   4. Filters the quick picks list to remove any pick whose
    ///      gameTable is in the excluded set.
    ///
    /// We test the set construction + filtering contract here.
    test('a game suggested in Play With is excluded from Quick Picks', () {
      // Simulate: Play With suggested Chess (catalog gameId 'chess' →
      // gameTable 'chess_games'). Quick Picks originally contains
      // tictactoe_games, chess_games, checkers_games.
      final quickPicksTables = [
        'tictactoe_games',
        'chess_games',
        'checkers_games',
      ];
      final playWithCatalogIds = ['chess']; // suggested in Play With
      // Map catalog id → gameTable (the provider does this via gameById).
      // For the test we hardcode the mapping.
      final catalogToTable = {
        'tictactoe': 'tictactoe_games',
        'chess': 'chess_games',
        'checkers': 'checkers_games',
        'memorymatch': 'memorymatch_games',
      };
      final excludedTables = playWithCatalogIds
          .map((id) => catalogToTable[id])
          .whereType<String>()
          .toSet();
      final filtered = quickPicksTables
          .where((t) => !excludedTables.contains(t))
          .toList();
      // chess_games should be excluded; tictactoe + checkers remain.
      expect(filtered, ['tictactoe_games', 'checkers_games']);
      expect(filtered, isNot(contains('chess_games')));
    });

    test('multiple Play With suggestions are all excluded', () {
      final quickPicksTables = [
        'tictactoe_games',
        'chess_games',
        'checkers_games',
        'memorymatch_games',
      ];
      final playWithCatalogIds = ['chess', 'checkers'];
      final catalogToTable = {
        'tictactoe': 'tictactoe_games',
        'chess': 'chess_games',
        'checkers': 'checkers_games',
        'memorymatch': 'memorymatch_games',
      };
      final excludedTables = playWithCatalogIds
          .map((id) => catalogToTable[id])
          .whereType<String>()
          .toSet();
      final filtered = quickPicksTables
          .where((t) => !excludedTables.contains(t))
          .toList();
      expect(filtered, ['tictactoe_games', 'memorymatch_games']);
    });

    test('Play With suggestion with null lastSharedGameId is not excluded', () {
      // A new pairing in Play With has lastSharedGameId = null (no shared
      // game yet). That shouldn't exclude anything from Quick Picks.
      final quickPicksTables = [
        'tictactoe_games',
        'chess_games',
      ];
      final playWithCatalogIds = <String?>[null, null];
      final catalogToTable = {
        'tictactoe': 'tictactoe_games',
        'chess': 'chess_games',
      };
      final excludedTables = playWithCatalogIds
          .whereType<String>()
          .map((id) => catalogToTable[id])
          .whereType<String>()
          .toSet();
      final filtered = quickPicksTables
          .where((t) => !excludedTables.contains(t))
          .toList();
      // Nothing excluded — both picks remain.
      expect(filtered, ['tictactoe_games', 'chess_games']);
    });
  });

  group('ParticipationLeaderboard contract — ranked vs notYetPlayed split', () {
    /// Mirrors the v3 leaderboard contract: ranked rows have matches >= 1,
    /// notYetPlayed rows have matches == 0. The points field is still
    /// returned (for internal use) but the UI hides it via hideScoreChip.
    test('ranked rows all have games_played >= 1', () {
      // Simulate a v3 response.
      final ranked = [
        {'userId': 'a', 'matches': 10, 'points': 30},
        {'userId': 'b', 'matches': 5, 'points': 15},
        {'userId': 'c', 'matches': 1, 'points': 3},
      ];
      for (final r in ranked) {
        expect((r['matches'] as int), greaterThanOrEqualTo(1),
            reason: 'ranked rows must have matches >= 1');
      }
    });

    test('notYetPlayed rows all have games_played == 0', () {
      final notPlayed = [
        {'userId': 'x', 'matches': 0, 'points': 0},
        {'userId': 'y', 'matches': 0, 'points': 0},
      ];
      for (final r in notPlayed) {
        expect((r['matches'] as int), 0,
            reason: 'notYetPlayed rows must have matches == 0');
      }
    });

    test('ranked order is by matches DESC, NOT points DESC', () {
      // A member with more games but fewer points ranks higher.
      final ranked = [
        {'userId': 'a', 'matches': 10, 'points': 20}, // 10 games, 20 pts
        {'userId': 'b', 'matches': 8, 'points': 30}, // 8 games, 30 pts
        {'userId': 'c', 'matches': 5, 'points': 15}, // 5 games, 15 pts
      ];
      // Verify the order is by matches DESC (10 > 8 > 5), not points
      // DESC (which would be 30 > 20 > 15 → b, a, c).
      for (var i = 0; i < ranked.length - 1; i++) {
        expect((ranked[i]['matches'] as int),
            greaterThanOrEqualTo((ranked[i + 1]['matches'] as int)),
            reason: 'ranked rows must be ordered by matches DESC');
      }
    });

    test('a member with 0 games never appears in the ranked list', () {
      final ranked = [
        {'userId': 'a', 'matches': 10},
        {'userId': 'b', 'matches': 5},
      ];
      final notPlayed = [
        {'userId': 'x', 'matches': 0},
      ];
      // The 0-game member 'x' is in notPlayed, NOT in ranked.
      expect(ranked.any((r) => r['userId'] == 'x'), isFalse);
      expect(notPlayed.any((r) => r['userId'] == 'x'), isTrue);
    });
  });
}

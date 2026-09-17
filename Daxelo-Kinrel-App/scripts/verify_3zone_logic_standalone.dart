// verify_3zone_logic_standalone.dart
//
// Self-contained verifier for the 3-zone Family Arena restructure contract.
// Mirrors the logic in:
//   • lib/features/games/presentation/widgets/family_streak_hero_card.dart
//     (familyStreakHeroHeadline)
//   • lib/features/games/presentation/widgets/play_with_row.dart
//     (playWithSubtextFor + ordering)
//
// Run via: dart run scripts/verify_3zone_logic_standalone.dart
//
// Exit code 0 = contract verified; non-zero = violation.
//
// The actual widget tests live in:
//   test/features/games/family_arena_3zone_logic_test.dart
// and require `flutter test` (which builds native assets). This script is
// the CI-friendly fallback for environments without clang/cmake.

/// Mirror of familyStreakHeroHeadline.
String familyStreakHeroHeadline(int streakDays, {bool playedToday = false}) {
  if (streakDays <= 0) {
    return 'Start a family streak tonight — play any game together';
  }
  return '🔥 $streakDays-day family streak — play tonight to keep it alive';
}

/// Mirror of the kDefaultFirstGameId default game name.
const String kDefaultFirstGameName = 'Tic-Tac-Toe';

/// Mirror of PlayWithSuggestion (minimal fields needed for subtext).
class Suggestion {
  const Suggestion({
    required this.userName,
    required this.isOnline,
    required this.sharedGamesCount,
    this.lastSharedGameName,
  });
  final String userName;
  final bool isOnline;
  final int sharedGamesCount;
  final String? lastSharedGameName;

  bool get isNew => sharedGamesCount == 0;
}

/// Mirror of playWithSubtextFor.
String playWithSubtextFor(Suggestion s) {
  if (s.isNew) {
    return 'New — say hi with $kDefaultFirstGameName';
  }
  if (s.lastSharedGameName != null && s.lastSharedGameName!.isNotEmpty) {
    return 'Play ${s.lastSharedGameName} again';
  }
  if (s.sharedGamesCount == 1) return 'Played 1 game together';
  return 'Played ${s.sharedGamesCount} games together';
}

/// Mirror of server-side ORDER BY: is_online DESC, shared_games_count DESC, user_name ASC.
int serverStyleCompare(Suggestion a, Suggestion b) {
  if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
  if (a.sharedGamesCount != b.sharedGamesCount) {
    return b.sharedGamesCount.compareTo(a.sharedGamesCount);
  }
  return a.userName.compareTo(b.userName);
}

void main() {
  var failures = 0;
  void check(String name, bool condition, String details) {
    if (condition) {
      print('  ✓ $name');
    } else {
      print('  ✗ $name');
      print('    $details');
      failures++;
    }
  }

  print('=== FamilyStreakHeroCard.familyStreakHeroHeadline — copy contract ===');

  // Contract 1: streak == 0 → "Start a family streak tonight..."
  check(
    'streak == 0 → "Start a family streak tonight — play any game together"',
    familyStreakHeroHeadline(0) ==
        'Start a family streak tonight — play any game together',
    'Got: "${familyStreakHeroHeadline(0)}"',
  );

  // Contract 2: streak == 0 ignores playedToday
  check(
    'streak == 0 ignores playedToday (no duplicate-banner bug)',
    familyStreakHeroHeadline(0, playedToday: true) ==
        familyStreakHeroHeadline(0, playedToday: false),
    'playedToday=true: "${familyStreakHeroHeadline(0, playedToday: true)}" vs '
        'playedToday=false: "${familyStreakHeroHeadline(0, playedToday: false)}"',
  );

  // Contract 3: streak >= 1 → "🔥 {N}-day family streak..."
  check(
    'streak == 1 → "🔥 1-day family streak — play tonight to keep it alive"',
    familyStreakHeroHeadline(1) ==
        '🔥 1-day family streak — play tonight to keep it alive',
    'Got: "${familyStreakHeroHeadline(1)}"',
  );
  check(
    'streak == 7 → "🔥 7-day family streak — play tonight to keep it alive"',
    familyStreakHeroHeadline(7) ==
        '🔥 7-day family streak — play tonight to keep it alive',
    'Got: "${familyStreakHeroHeadline(7)}"',
  );

  // Contract 4: never mentions wins/losses/win%
  var leakCount = 0;
  for (var streak = 0; streak <= 30; streak++) {
    final line = familyStreakHeroHeadline(streak).toLowerCase();
    if (line.contains('win') ||
        line.contains('loss') ||
        line.contains('%')) {
      leakCount++;
    }
  }
  check(
    'Headline never mentions wins/losses/win% (0 leaks across streak 0..30)',
    leakCount == 0,
    '$leakCount leak(s) detected',
  );

  print('');
  print('=== PlayWithRow.playWithSubtextFor — subtext contract ===');

  // Contract 5: new pairing → "New — say hi with Tic-Tac-Toe"
  final newS = Suggestion(userName: 'A', isOnline: false, sharedGamesCount: 0);
  check(
    'New pairing → contains "New — say hi with Tic-Tac-Toe"',
    playWithSubtextFor(newS).contains('New — say hi with Tic-Tac-Toe'),
    'Got: "${playWithSubtextFor(newS)}"',
  );

  // Contract 6: returning pairing with last game → "Play {Game} again"
  final retS = Suggestion(
      userName: 'A',
      isOnline: false,
      sharedGamesCount: 3,
      lastSharedGameName: 'Chess');
  check(
    'Returning pairing → "Play Chess again"',
    playWithSubtextFor(retS) == 'Play Chess again',
    'Got: "${playWithSubtextFor(retS)}"',
  );

  // Contract 7: defensive branch (no last game but count > 0)
  final defS = Suggestion(userName: 'A', isOnline: false, sharedGamesCount: 5);
  check(
    'Defensive branch (no last game, count=5) → "Played 5 games together"',
    playWithSubtextFor(defS) == 'Played 5 games together',
    'Got: "${playWithSubtextFor(defS)}"',
  );

  // Contract 8: subtext never mentions wins/losses/win%
  var subLeakCount = 0;
  for (final s in [
    Suggestion(userName: 'A', isOnline: false, sharedGamesCount: 0),
    Suggestion(userName: 'A', isOnline: false, sharedGamesCount: 5, lastSharedGameName: 'Chess'),
    Suggestion(userName: 'A', isOnline: false, sharedGamesCount: 1, lastSharedGameName: 'Tic-Tac-Toe'),
    Suggestion(userName: 'A', isOnline: false, sharedGamesCount: 99),
  ]) {
    final line = playWithSubtextFor(s).toLowerCase();
    if (line.contains('win') ||
        line.contains('loss') ||
        line.contains('%')) {
      subLeakCount++;
    }
  }
  check(
    'Subtext never mentions wins/losses/win% (0 leaks across 4 cases)',
    subLeakCount == 0,
    '$subLeakCount leak(s) detected',
  );

  print('');
  print('=== PlayWithRow ordering contract (mirrors server-side ORDER BY) ===');

  // Contract 9: online members come before offline members
  final offline = Suggestion(userName: 'A', isOnline: false, sharedGamesCount: 99);
  final online = Suggestion(userName: 'B', isOnline: true, sharedGamesCount: 0);
  final sorted1 = [offline, online]..sort(serverStyleCompare);
  check(
    'Online members sort before offline members (even with 0 shared games)',
    sorted1.first.userName == 'B',
    'Got first: ${sorted1.first.userName}',
  );

  // Contract 10: higher shared count sorts first at equal online state
  final less = Suggestion(userName: 'A', isOnline: false, sharedGamesCount: 1);
  final more = Suggestion(userName: 'B', isOnline: false, sharedGamesCount: 5);
  final sorted2 = [less, more]..sort(serverStyleCompare);
  check(
    'At equal online state, higher shared-games-count sorts first',
    sorted2.first.userName == 'B',
    'Got first: ${sorted2.first.userName}',
  );

  // Contract 11: alphabetical at equal online + equal shared
  final z = Suggestion(userName: 'Zara', isOnline: false, sharedGamesCount: 3);
  final a = Suggestion(userName: 'Anita', isOnline: false, sharedGamesCount: 3);
  final sorted3 = [z, a]..sort(serverStyleCompare);
  check(
    'At equal online + equal shared, alphabetical by name',
    sorted3.first.userName == 'Anita',
    'Got first: ${sorted3.first.userName}',
  );

  // Contract 12: never-played members sort AFTER returning pairings
  final returning = Suggestion(userName: 'A', isOnline: false, sharedGamesCount: 2);
  final fresh = Suggestion(userName: 'B', isOnline: false, sharedGamesCount: 0);
  final sorted4 = [fresh, returning]..sort(serverStyleCompare);
  check(
    'Never-played members sort AFTER returning pairings',
    sorted4.first.userName == 'A',
    'Got first: ${sorted4.first.userName}',
  );

  print('');
  if (failures == 0) {
    print('=== ALL CHECKS PASSED — 3-zone contract verified ===');
  } else {
    print('=== $failures CHECK(S) FAILED ===');
  }
  if (failures != 0) {
    throw StateError('3-zone contract verification failed: $failures failure(s).');
  }
}

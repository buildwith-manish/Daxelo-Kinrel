// verify_privacy_logic.dart
//
// Standalone Dart verifier for the leaderboard privacy + participation
// reframe contract. Mirrors the assertions in
// test/features/gaming_ecosystem/leaderboard_privacy_logic_test.dart
// but can be run without the full Flutter test runner (which requires
// native asset builds that aren't available in every CI environment).
//
// Run via:
//   flutter pub get
//   dart run scripts/verify_privacy_logic.dart
//
// Exits 0 on success, non-zero on any contract violation.

import 'package:kinrel/features/gaming_ecosystem/presentation/widgets/gaming_kit.dart';

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

  print('=== GamingRankRow.participationLineFor — privacy + reframe contract ===');

  // Contract 1: never contains "win", "loss" or "%".
  for (final isMe in [true, false]) {
    for (var matches = 0; matches <= 50; matches++) {
      final line = GamingRankRow.participationLineFor(
          matches: matches, isMe: isMe);
      final lower = line.toLowerCase();
      if (lower.contains('win') ||
          lower.contains('loss') ||
          line.contains('%')) {
        print('  ✗ FAIL: line "$line" leaks a forbidden substring '
            '(matches=$matches, isMe=$isMe)');
        failures++;
      }
    }
  }
  check(
      'No line for matches 0..50 × {self, non-self} contains "win", "loss" or "%"',
      failures == 0,
      'See failures above.');

  // Contract 2: 0-match non-self → soft nudge CTA.
  final zeroNonSelf = GamingRankRow.participationLineFor(
      matches: 0, isMe: false);
  check(
      '0-match non-self row → contains "invite them to play"',
      zeroNonSelf.contains('invite them to play'),
      'Got: "$zeroNonSelf"');
  check(
      '0-match non-self row → contains "New to the Arena"',
      zeroNonSelf.contains('New to the Arena'),
      'Got: "$zeroNonSelf"');

  // Contract 3: 0-match self → inviting CTA.
  final zeroSelf =
      GamingRankRow.participationLineFor(matches: 0, isMe: true);
  check(
      '0-match self row → contains "first match"',
      zeroSelf.contains('first match'),
      'Got: "$zeroSelf"');
  check(
      '0-match self row → contains "tonight"',
      zeroSelf.contains('tonight'),
      'Got: "$zeroSelf"');

  // Contract 4: 1-match row → singular participation phrase.
  check(
      '1-match row → "Played 1 game together"',
      GamingRankRow.participationLineFor(matches: 1, isMe: false) ==
          'Played 1 game together',
      'Got: "${GamingRankRow.participationLineFor(matches: 1, isMe: false)}"');

  // Contract 5: N-match row (N>1) → plural participation phrase.
  check(
      '5-match row → "Played 5 games together"',
      GamingRankRow.participationLineFor(matches: 5, isMe: false) ==
          'Played 5 games together',
      'Got: "${GamingRankRow.participationLineFor(matches: 5, isMe: false)}"');
  check(
      '42-match self row → "Played 42 games together"',
      GamingRankRow.participationLineFor(matches: 42, isMe: true) ==
          'Played 42 games together',
      'Got: "${GamingRankRow.participationLineFor(matches: 42, isMe: true)}"');

  // Contract 6: identical for self vs non-self when matches >= 1.
  var identical = true;
  for (var m = 1; m <= 10; m++) {
    if (GamingRankRow.participationLineFor(matches: m, isMe: true) !=
        GamingRankRow.participationLineFor(matches: m, isMe: false)) {
      identical = false;
      break;
    }
  }
  check(
      'Participation line identical for self vs non-self at matches 1..10',
      identical,
      'Differed for at least one match count.');

  print('');
  if (failures == 0) {
    print('=== ALL CHECKS PASSED — privacy + reframe contract verified ===');
  } else {
    print('=== $failures CHECK(S) FAILED ===');
    print('Privacy contract is NOT satisfied — see failures above.');
  }
  // Exit code reflects pass/fail.
  if (failures != 0) {
    throw StateError('Privacy contract verification failed: $failures failure(s).');
  }
}

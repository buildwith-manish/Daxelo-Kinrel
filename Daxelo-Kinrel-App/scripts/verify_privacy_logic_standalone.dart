// verify_privacy_logic_standalone.dart
//
// Self-contained verifier for the leaderboard privacy + participation
// reframe contract. Mirrors the logic in
// GamingRankRow.participationLineFor (lib/features/gaming_ecosystem/
// presentation/widgets/gaming_kit.dart) so it can be run without the
// Flutter test runner / native asset build chain.
//
// Run via: dart run scripts/verify_privacy_logic_standalone.dart
//
// Exit code 0 = contract verified; non-zero = violation.
//
// The actual widget test (test/features/gaming_ecosystem/
// leaderboard_privacy_test.dart) and pure-Dart logic test
// (test/features/gaming_ecosystem/leaderboard_privacy_logic_test.dart)
// both exercise the real widget code — they require `flutter test`
// (which builds native assets). This script is the CI-friendly fallback
// for environments without clang/cmake.

/// Mirror of GamingRankRow.participationLineFor.
String participationLineFor({required int matches, required bool isMe}) {
  if (matches == 0) {
    return isMe
        ? 'Play your first match tonight'
        : 'New to the Arena — invite them to play';
  }
  if (matches == 1) return 'Played 1 game together';
  return 'Played $matches games together';
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

  print('=== GamingRankRow.participationLineFor — privacy + reframe contract ===');
  print('    (mirrors lib/.../gaming_kit.dart — run flutter test for the real widget test)');

  // Contract 1: never contains "win", "loss" or "%".
  var leakCount = 0;
  for (final isMe in [true, false]) {
    for (var matches = 0; matches <= 50; matches++) {
      final line = participationLineFor(matches: matches, isMe: isMe);
      final lower = line.toLowerCase();
      if (lower.contains('win') ||
          lower.contains('loss') ||
          line.contains('%')) {
        print('  ✗ FAIL: line "$line" leaks a forbidden substring '
            '(matches=$matches, isMe=$isMe)');
        leakCount++;
      }
    }
  }
  check(
      'No line for matches 0..50 × {self, non-self} contains "win", "loss" or "%" '
      '($leakCount leak(s))',
      leakCount == 0,
      'See leak failures above.');

  // Contract 2: 0-match non-self → soft nudge CTA.
  final zeroNonSelf = participationLineFor(matches: 0, isMe: false);
  check(
      '0-match non-self row → contains "invite them to play"',
      zeroNonSelf.contains('invite them to play'),
      'Got: "$zeroNonSelf"');
  check(
      '0-match non-self row → contains "New to the Arena"',
      zeroNonSelf.contains('New to the Arena'),
      'Got: "$zeroNonSelf"');

  // Contract 3: 0-match self → inviting CTA.
  final zeroSelf = participationLineFor(matches: 0, isMe: true);
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
      participationLineFor(matches: 1, isMe: false) == 'Played 1 game together',
      'Got: "${participationLineFor(matches: 1, isMe: false)}"');

  // Contract 5: N-match row (N>1) → plural participation phrase.
  check(
      '5-match row → "Played 5 games together"',
      participationLineFor(matches: 5, isMe: false) == 'Played 5 games together',
      'Got: "${participationLineFor(matches: 5, isMe: false)}"');
  check(
      '42-match self row → "Played 42 games together"',
      participationLineFor(matches: 42, isMe: true) == 'Played 42 games together',
      'Got: "${participationLineFor(matches: 42, isMe: true)}"');

  // Contract 6: identical for self vs non-self when matches >= 1.
  var identical = true;
  for (var m = 1; m <= 10; m++) {
    if (participationLineFor(matches: m, isMe: true) !=
        participationLineFor(matches: m, isMe: false)) {
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
  if (failures != 0) {
    throw StateError('Privacy contract verification failed: $failures failure(s).');
  }
}

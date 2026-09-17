// test/features/gaming_ecosystem/leaderboard_privacy_logic_test.dart
//
// Pure-Dart unit test for the leaderboard privacy + participation reframe
// contract. Verifies the same invariants as the widget test
// (leaderboard_privacy_test.dart) but does not require the Flutter test
// runner — so it runs even in environments where native asset builds
// (thermion_dart / clang) are unavailable.
//
// Contract under test:
//   1. The participation line NEVER contains "win", "loss", or "%".
//   2. For a 0-match non-self row, the line is a soft nudge CTA — never
//      a "0 wins · 0%" walk-of-shame.
//   3. For a 0-match self row, the line is an inviting CTA.
//   4. For matches >= 1, the line is a participation phrase ("Played N
//      games together") that frames the count as family togetherness,
//      not individual outcome.

import 'package:test/test.dart';

import 'package:kinrel/features/gaming_ecosystem/presentation/widgets/gaming_kit.dart';

void main() {
  group('GamingRankRow.participationLineFor — privacy + reframe contract', () {
    test('never contains "win", "loss" or "%" for any combination', () {
      for (final isMe in [true, false]) {
        for (var matches = 0; matches <= 50; matches++) {
          final line = GamingRankRow.participationLineFor(
              matches: matches, isMe: isMe);
          final lower = line.toLowerCase();
          expect(
            lower.contains('win'),
            false,
            reason: 'Line must never contain "win". Got: "$line" '
                '(matches=$matches, isMe=$isMe)',
          );
          expect(
            lower.contains('loss'),
            false,
            reason: 'Line must never contain "loss". Got: "$line" '
                '(matches=$matches, isMe=$isMe)',
          );
          expect(
            line.contains('%'),
            false,
            reason: 'Line must never contain "%". Got: "$line" '
                '(matches=$matches, isMe=$isMe)',
          );
        }
      }
    });

    test('0-match non-self row → soft nudge CTA (no shame)', () {
      final line = GamingRankRow.participationLineFor(
          matches: 0, isMe: false);
      expect(line, contains('invite them to play'));
      expect(line, contains('New to the Arena'));
    });

    test('0-match self row → inviting CTA to play tonight', () {
      final line = GamingRankRow.participationLineFor(
          matches: 0, isMe: true);
      expect(line, contains('first match'));
      expect(line, contains('tonight'));
    });

    test('1-match row → singular "Played 1 game together"', () {
      final line = GamingRankRow.participationLineFor(
          matches: 1, isMe: false);
      expect(line, equals('Played 1 game together'));
    });

    test('N-match row (N>1) → plural "Played N games together"', () {
      expect(
        GamingRankRow.participationLineFor(matches: 5, isMe: false),
        equals('Played 5 games together'),
      );
      expect(
        GamingRankRow.participationLineFor(matches: 42, isMe: true),
        equals('Played 42 games together'),
      );
    });

    test('participation phrase is identical for self vs non-self at N>=1', () {
      // The participation phrase does not differentiate self from non-self
      // once at least one match has been played — both see the same
      // "Played N games together" framing. The only self-vs-non-self
      // difference is the streak chip (gated separately on isMe) and the
      // "(you)" suffix on the user name (gated separately on isMe).
      for (var matches = 1; matches <= 10; matches++) {
        expect(
          GamingRankRow.participationLineFor(matches: matches, isMe: true),
          equals(GamingRankRow.participationLineFor(
              matches: matches, isMe: false)),
          reason: 'Participation line should be identical for self vs non-self '
              'when matches >= 1. matches=$matches',
        );
      }
    });
  });
}

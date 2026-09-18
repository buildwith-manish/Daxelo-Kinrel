// test/features/gaming_ecosystem/leaderboard_privacy_test.dart
//
// Widget test: leaderboard cards NEVER render a win-percentage string for
// any account other than the signed-in user's own.
//
// This test exercises the GamingRankRow widget directly with synthetic
// LeaderboardEntry data — one for "me" and one for "other" — and asserts
// that the rendered tree:
//   1. Does NOT contain a "%" character anywhere (winRateLabel is gone).
//   2. Does NOT contain the substring " wins" or " losses" for any row.
//   3. DOES contain the participation phrase "games together" (positive
//      reframe) for both rows.
//   4. DOES NOT render a streak chip for non-self rows even if the data
//      somehow carries a non-zero streakCurrent (defensive double-gate).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kinrel/core/constants/brand_colors.dart';
import 'package:kinrel/features/gaming_ecosystem/data/gaming_models.dart';
import 'package:kinrel/features/gaming_ecosystem/presentation/widgets/gaming_kit.dart';

void main() {
  group('GamingRankRow privacy contract', () {
    /// Returns all Text node strings rendered by [widget].
    Set<String> allText(WidgetTester tester) {
      final texts = <String>{};
      tester.widgetList(find.byType(Text)).forEach((w) {
        final t = w as Text;
        final data = t.data ?? '';
        if (data.isNotEmpty) texts.add(data);
      });
      return texts;
    }

    testWidgets(
        'non-self row: no win%, no "wins", no streak chip — only rank, name, points, participation',
        (tester) async {
      // Synthetic "other" entry with non-zero wins/losses/winRate/streak.
      // The widget MUST ignore all of these for non-self rows even if they
      // are present in the data — defensive double-gate against stale cache.
      final otherEntry = LeaderboardEntry(
        userId: 'other-user-id',
        userName: 'Yakshitha',
        matches: 12,
        wins: 9,
        losses: 3,
        draws: 0,
        points: 28,
        streakCurrent: 5, // should NOT be rendered for non-self
        streakBest: 7,
        winRate: 0.75, // 75% — should NOT be rendered
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: KinrelColors.darkSurface,
            body: ListView(
              children: [
                GamingRankRow(
                  rank: 1,
                  userName: otherEntry.userName,
                  points: otherEntry.points,
                  matches: otherEntry.matches,
                  // Even though we pass wins & winRateLabel, the widget
                  // MUST NOT render them for non-self rows.
                  wins: otherEntry.wins,
                  streak: otherEntry.streakCurrent,
                  winRateLabel: otherEntry.winRateLabel,
                  isMe: false,
                ),
              ],
            ),
          ),
        ),
      );

      final texts = allText(tester);
      final joined = texts.join(' || ');

      // Positive assertions — these MUST be present.
      expect(
        texts.any((t) => t.contains('games together')),
        true,
        reason: 'Participation phrase "games together" must be rendered. '
            'Got: $joined',
      );
      expect(texts.any((t) => t.contains('Yakshitha')), true);
      expect(texts.any((t) => t.contains('28')), true, // points
          reason: 'Points value must be rendered.');

      // Negative assertions — these MUST NOT be present anywhere.
      expect(
        texts.any((t) => t.contains('%')),
        false,
        reason: 'No win-percentage string must ever be rendered on a shared '
            'leaderboard row. Got: $joined',
      );
      expect(
        joined.contains(' wins'),
        false,
        reason: 'The word "wins" must never appear on a shared leaderboard '
            'row. Got: $joined',
      );
      expect(
        joined.toLowerCase().contains('loss'),
        false,
        reason: 'The word "loss" must never appear on a shared leaderboard '
            'row. Got: $joined',
      );
      // Streak chip is gated on isMe — must not render the streak number
      // as a standalone chip for non-self.
      expect(
        texts.any((t) => t.trim() == '5'), // streakCurrent value
        false,
        reason: 'Streak chip must not render for non-self rows. Got: $joined',
      );
    });

    testWidgets(
        'self row: full stats MAY be shown (the owner can always see own data) '
        'but the shared leaderboard surface still does not show win%',
        (tester) async {
      final selfEntry = LeaderboardEntry(
        userId: 'my-user-id',
        userName: 'Manish',
        matches: 8,
        wins: 5,
        losses: 3,
        draws: 0,
        points: 18,
        streakCurrent: 3, // SHOULD render as a chip for self
        streakBest: 5,
        winRate: 0.625, // 63% — still NOT rendered on shared leaderboard
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: KinrelColors.darkSurface,
            body: ListView(
              children: [
                GamingRankRow(
                  rank: 2,
                  userName: selfEntry.userName,
                  points: selfEntry.points,
                  matches: selfEntry.matches,
                  wins: selfEntry.wins,
                  streak: selfEntry.streakCurrent,
                  winRateLabel: selfEntry.winRateLabel,
                  isMe: true,
                ),
              ],
            ),
          ),
        ),
      );

      final texts = allText(tester);
      final joined = texts.join(' || ');

      // Self row: streak chip SHOULD render (>= 2).
      expect(
        texts.any((t) => t.trim() == '3'),
        true,
        reason: 'Streak chip must render for the viewer\'s own row when '
            'streak >= 2. Got: $joined',
      );

      // Even for self, the SHARED leaderboard surface never shows win%
      // (the owner sees their full stats on the profile screen, not here).
      expect(
        texts.any((t) => t.contains('%')),
        false,
        reason: 'Even for the self row, the shared leaderboard surface must '
            'not show win%. Got: $joined',
      );
      expect(
        joined.contains(' wins'),
        false,
        reason: 'Even for the self row, the shared leaderboard must not show '
            'the word "wins". Got: $joined',
      );

      // Participation phrase must still be present.
      expect(
        texts.any((t) => t.contains('games together')),
        true,
        reason: 'Participation phrase must render for self row too. '
            'Got: $joined',
      );
    });

    testWidgets(
        'zero-match nudge: a member with 0 games shows a soft CTA, never a '
        'loss record',
        (tester) async {
      final zeroEntry = LeaderboardEntry(
        userId: 'other-user-id',
        userName: 'NewFamilyMember',
        matches: 0,
        wins: 0,
        losses: 0,
        points: 0,
        streakCurrent: 0,
        winRate: 0,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: KinrelColors.darkSurface,
            body: ListView(
              children: [
                GamingRankRow(
                  rank: 5,
                  userName: zeroEntry.userName,
                  points: zeroEntry.points,
                  matches: zeroEntry.matches,
                  wins: zeroEntry.wins,
                  isMe: false,
                ),
              ],
            ),
          ),
        ),
      );

      final texts = allText(tester);
      final joined = texts.join(' || ');

      // The "0 wins · 0%" toxic framing must NEVER appear.
      expect(
        joined.contains('0 wins'),
        false,
        reason: 'The "0 wins" walk-of-shame must never render. Got: $joined',
      );
      expect(
        texts.any((t) => t.contains('%')),
        false,
        reason: 'No win% for a 0-match member. Got: $joined',
      );

      // A soft nudge CTA must be shown instead.
      expect(
        texts.any((t) =>
            t.contains('invite them to play') ||
            t.contains('New to the Arena')),
        true,
        reason: 'A 0-match non-self row must show a soft nudge CTA instead '
            'of a loss record. Got: $joined',
      );
    });
  });
}

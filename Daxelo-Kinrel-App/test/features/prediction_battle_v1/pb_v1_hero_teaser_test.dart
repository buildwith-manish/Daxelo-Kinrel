// test/features/prediction_battle_v1/pb_v1_hero_teaser_test.dart
//
// Unit tests for the TeaserCopy.forState pure mapping. Verifies that
// each of the 6 documented states maps to the expected copy, and that
// the loading / no-round / empty-countdown states return null (hidden).

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/prediction_battle_v1/pb_v1_hero_teaser.dart';
import 'package:kinrel/features/prediction_battle_v1/pb_v1_models.dart';

void main() {
  // Reusable fixtures — built once per group.
  final round = PBv1Round(
    id: 'r-1',
    familyId: 'fam-1',
    questionId: 'pq-001',
    opensAt: DateTime.utc(2026, 9, 23, 2, 30),
    revealAt: DateTime.utc(2026, 9, 23, 15, 30),
    status: 'open',
    createdAt: DateTime.utc(2026, 9, 23, 2, 30),
  );
  final myGuess = PBv1Guess(
    userId: 'u-1',
    guessValue: 42,
    submittedAt: DateTime.utc(2026, 9, 23, 4, 0),
  );

  group('TeaserCopy.forState', () {
    test('returns null when loading (hidden)', () {
      final state = const PBv1State(isLoading: true);
      expect(TeaserCopy.forState(state, '4h 23m'), isNull);
    });

    test('returns null when no round (hidden)', () {
      const state = PBv1State();
      expect(TeaserCopy.forState(state, '4h 23m'), isNull);
    });

    test('returns null when open + no guess + empty countdown (hidden)', () {
      final state = PBv1State(round: round);
      // countdown is "" — we have no informative text to show.
      expect(TeaserCopy.forState(state, ''), isNull);
    });

    test('returns submit copy when open + no guess + valid countdown', () {
      final state = PBv1State(round: round);
      expect(
        TeaserCopy.forState(state, '4h 23m'),
        'Submit your prediction · 4h 23m left',
      );
    });

    test('returns locked copy when open + guess + valid countdown', () {
      final state = PBv1State(round: round, myGuess: myGuess);
      expect(
        TeaserCopy.forState(state, '4h 23m'),
        'Guess locked · reveal in 4h 23m',
      );
    });

    test('returns locked-imminent copy when open + guess + empty countdown', () {
      final state = PBv1State(round: round, myGuess: myGuess);
      // countdown is "Reveal imminent" but we pass "" to simulate the
      // edge case where revealAt is in the past but status is still
      // 'open' (the pg_cron tick hasn't fired yet). The teaser should
      // still tell the user their guess is locked.
      expect(
        TeaserCopy.forState(state, ''),
        'Guess locked · reveal in imminent',
      );
    });

    test('returns missed copy when revealed + no guess', () {
      final state = PBv1State(round: round, revealed: true);
      expect(
        TeaserCopy.forState(state, ''),
        'Missed today’s round · See who won',
      );
    });

    test('returns won copy when revealed + winner', () {
      final state = PBv1State(
        round: round,
        myGuess: myGuess,
        revealed: true,
        winnerUserIds: const ['u-1'],
      );
      expect(
        TeaserCopy.forState(state, ''),
        'You won today’s prediction!',
      );
    });

    test('returns see-reveal copy when revealed + not winner', () {
      final state = PBv1State(
        round: round,
        myGuess: myGuess,
        revealed: true,
        winnerUserIds: const ['someone-else'],
      );
      expect(
        TeaserCopy.forState(state, ''),
        'Reveal is in · See how close you got',
      );
    });

    test('returns see-reveal copy when revealed + tied winner list', () {
      // User is in the winner list alongside another user — still
      // counts as a win.
      final state = PBv1State(
        round: round,
        myGuess: myGuess,
        revealed: true,
        winnerUserIds: const ['u-1', 'u-2'],
      );
      expect(
        TeaserCopy.forState(state, ''),
        'You won today’s prediction!',
      );
    });

    test('ignores countdown when revealed (winner)', () {
      // Even if countdown is non-empty (which shouldn't happen in
      // practice — revealed ⇒ countdown is irrelevant), the copy is
      // the reveal-state copy.
      final state = PBv1State(
        round: round,
        myGuess: myGuess,
        revealed: true,
        winnerUserIds: const ['u-1'],
      );
      expect(
        TeaserCopy.forState(state, '5m'),
        'You won today’s prediction!',
      );
    });
  });
}

// test/features/prediction_battle_v1/pb_v1_optimistic_ui_test.dart
//
// Unit tests for the Prediction Battle v1 optimistic-UI state machine.
//
// Verifies the contract that PBv1Notifier.submitGuess() relies on:
//   1. Optimistic update — state.myGuess is set + isSubmitting=true +
//      isOptimisticGuess=true IMMEDIATELY (the UI shows the guess
//      before the awaited RPC resolves).
//   2. Success reconcile — isSubmitting=false + isOptimisticGuess=false,
//      myGuess remains.
//   3. Failure rollback — myGuess is cleared (clearMyGuess=true) AND
//      isSubmitting=false AND isOptimisticGuess=false AND error set.
//   4. Previous guess restored on rollback (not just cleared) when
//      the user had a prior confirmed guess.
//
// The full provider test would require a mocked SupabaseClient; this
// test exercises the state-machine contract the provider uses, so a
// regression in copyWith (e.g. clearMyGuess not honored) breaks this
// test before the provider-level flow breaks in production.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/prediction_battle_v1/pb_v1_models.dart';

void main() {
  group('PBv1State optimistic-UI contract', () {
    final round = PBv1Round(
      id: 'round-1',
      familyId: 'fam-1',
      questionId: 'q-1',
      opensAt: DateTime(2026, 9, 26, 9),
      revealAt: DateTime(2026, 9, 26, 21, 30),
      status: 'open',
      createdAt: DateTime(2026, 9, 26, 9),
    );
    final myId = 'user-1';
    final previousGuess = PBv1Guess(
      userId: myId,
      guessValue: 42,
      submittedAt: DateTime(2026, 9, 26, 10),
    );

    test('optimistic update sets myGuess + isSubmitting + isOptimisticGuess',
        () {
      final initial = PBv1State(round: round, isLoading: false);
      // Simulate the optimistic update that PBv1Notifier.submitGuess()
      // does BEFORE awaiting the RPC.
      final optimistic = initial.copyWith(
        myGuess: PBv1Guess(
          userId: myId,
          guessValue: 100,
          submittedAt: DateTime.now(),
        ),
        isSubmitting: true,
        isOptimisticGuess: true,
        clearError: true,
      );

      expect(optimistic.myGuess, isNotNull);
      expect(optimistic.myGuess!.guessValue, 100);
      expect(optimistic.isSubmitting, isTrue);
      expect(optimistic.isOptimisticGuess, isTrue);
      expect(optimistic.error, isNull,
          reason: 'clearError should clear any previous error');
    });

    test('success reconcile clears isSubmitting + isOptimisticGuess but keeps myGuess',
        () {
      final optimistic = PBv1State(
        round: round,
        myGuess: PBv1Guess(
          userId: myId,
          guessValue: 100,
          submittedAt: DateTime.now(),
        ),
        isSubmitting: true,
        isOptimisticGuess: true,
      );

      // Simulate the success path — RPC returns ok, the provider clears
      // the flags but keeps myGuess (already showing the right value).
      final reconciled = optimistic.copyWith(
        isSubmitting: false,
        isOptimisticGuess: false,
      );

      expect(reconciled.myGuess, isNotNull,
          reason: 'myGuess must persist after success');
      expect(reconciled.myGuess!.guessValue, 100);
      expect(reconciled.isSubmitting, isFalse);
      expect(reconciled.isOptimisticGuess, isFalse);
    });

    test('failure rollback clears the optimistic guess when there was none before',
        () {
      // User had NO previous guess, the optimistic update added one,
      // the RPC failed → rollback should clear myGuess entirely.
      final optimistic = PBv1State(
        round: round,
        myGuess: PBv1Guess(
          userId: myId,
          guessValue: 100,
          submittedAt: DateTime.now(),
        ),
        isSubmitting: true,
        isOptimisticGuess: true,
      );

      // Simulate the failure path — provider restores previousGuess
      // (which is null here) and clears flags.
      final PBv1Guess? previousGuess = null;
      final rolledBack = optimistic.copyWith(
        myGuess: previousGuess,
        isSubmitting: false,
        isOptimisticGuess: false,
        error: 'Failed to submit — tap to retry',
      );

      expect(rolledBack.myGuess, isNull,
          reason: 'Rollback must clear myGuess when no previous guess existed');
      expect(rolledBack.isSubmitting, isFalse);
      expect(rolledBack.isOptimisticGuess, isFalse);
      expect(rolledBack.error, 'Failed to submit — tap to retry');
    });

    test('failure rollback restores the previous confirmed guess when one existed',
        () {
      // User HAD a confirmed guess (42), then re-submitted with a new
      // value (100), the RPC failed → rollback should restore 42,
      // NOT just clear myGuess to null.
      final optimistic = PBv1State(
        round: round,
        myGuess: PBv1Guess(
          userId: myId,
          guessValue: 100,
          submittedAt: DateTime.now(),
        ),
        isSubmitting: true,
        isOptimisticGuess: true,
      );

      // Simulate the failure path — provider restores previousGuess
      // (which is the prior confirmed guess of 42).
      final rolledBack = optimistic.copyWith(
        myGuess: previousGuess,
        isSubmitting: false,
        isOptimisticGuess: false,
        error: 'Failed to submit — tap to retry',
      );

      expect(rolledBack.myGuess, isNotNull,
          reason: 'Rollback must RESTORE the previous guess, not clear it');
      expect(rolledBack.myGuess!.guessValue, 42,
          reason: 'Restored guess value must match the prior confirmed value');
      expect(rolledBack.isSubmitting, isFalse);
      expect(rolledBack.isOptimisticGuess, isFalse);
      expect(rolledBack.error, 'Failed to submit — tap to retry');
    });

    test('clearMyGuess parameter explicitly clears myGuess (used in non-rollback paths)',
        () {
      // The clearMyGuess parameter exists for cases where a round
      // transition should clear myGuess without restoring a previous
      // value (e.g. round rolls over to the next day). Verify it works
      // in isolation.
      final withGuess = PBv1State(
        round: round,
        myGuess: PBv1Guess(
          userId: myId,
          guessValue: 100,
          submittedAt: DateTime.now(),
        ),
      );

      final cleared = withGuess.copyWith(clearMyGuess: true);

      expect(cleared.myGuess, isNull,
          reason: 'clearMyGuess=true must null out myGuess');
      // Other fields must be preserved.
      expect(cleared.round, round);
    });

    test('clearMyGuess takes precedence over myGuess in copyWith', () {
      // If both clearMyGuess and myGuess are passed, clearMyGuess wins.
      // This guards against a regression where a non-null myGuess
      // accidentally survives a clearMyGuess call.
      final initial = PBv1State(round: round);
      final result = initial.copyWith(
        myGuess: PBv1Guess(
          userId: myId,
          guessValue: 999,
          submittedAt: DateTime.now(),
        ),
        clearMyGuess: true,
      );

      expect(result.myGuess, isNull,
          reason: 'clearMyGuess must take precedence over myGuess');
    });

    test('full optimistic flow: optimistic → success → no phantom flags',
        () {
      // Walk the complete optimistic-then-success state sequence and
      // verify no stale flags linger.
      var state = PBv1State(round: round, isLoading: false);

      // 1. User taps submit → optimistic
      state = state.copyWith(
        myGuess: PBv1Guess(
          userId: myId,
          guessValue: 250,
          submittedAt: DateTime.now(),
        ),
        isSubmitting: true,
        isOptimisticGuess: true,
        clearError: true,
      );
      expect(state.isSubmitting, isTrue);
      expect(state.isOptimisticGuess, isTrue);

      // 2. RPC resolves ok → reconcile
      state = state.copyWith(
        isSubmitting: false,
        isOptimisticGuess: false,
      );
      expect(state.isSubmitting, isFalse);
      expect(state.isOptimisticGuess, isFalse);
      expect(state.myGuess?.guessValue, 250);
      expect(state.error, isNull);
    });

    test('full optimistic flow: optimistic → failure → rollback restores null',
        () {
      // Walk the complete optimistic-then-failure state sequence and
      // verify the rollback restores the previous state.
      var state = PBv1State(round: round, isLoading: false);

      // 1. User taps submit → optimistic
      state = state.copyWith(
        myGuess: PBv1Guess(
          userId: myId,
          guessValue: 250,
          submittedAt: DateTime.now(),
        ),
        isSubmitting: true,
        isOptimisticGuess: true,
        clearError: true,
      );
      expect(state.isSubmitting, isTrue);

      // 2. RPC throws → rollback to no guess
      state = state.copyWith(
        myGuess: null, // previousGuess was null
        isSubmitting: false,
        isOptimisticGuess: false,
        error: 'Failed to submit — tap to retry',
      );
      expect(state.isSubmitting, isFalse);
      expect(state.isOptimisticGuess, isFalse);
      expect(state.myGuess, isNull);
      expect(state.error, 'Failed to submit — tap to retry');
    });
  });
}

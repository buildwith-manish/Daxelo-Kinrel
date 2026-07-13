// test/features/trivia/trivia_provider_test.dart
//
// P9.1 — Family trivia tests.
// Verifies there is NO leaderboard, NO persisted score, and that
// correctness is shown only to the viewer for their own learning.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/trivia/providers/trivia_provider.dart';

TriviaQuestion _q(String id, String prompt, List<String> opts, int correct) =>
    TriviaQuestion(
      id: id,
      prompt: prompt,
      options: opts,
      correctIndex: correct,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P9.1 — TriviaNotifier (no leaderboard)', () {
    test('state exposes NO score field and NO aggregate', () {
      final n = TriviaNotifier();
      // The state type must not carry any score/total/leaderboard concept.
      expect(n.state.selectedIndex, isNull);
      expect(n.state.isRevealed, isFalse);
      expect(n.state.isFinished, isFalse);
      n.dispose();
    });

    test('load sets the question bank and resets cursor', () {
      final n = TriviaNotifier();
      n.load([_q('1', 'Q1', ['a', 'b', 'c'], 0)]);
      expect(n.state.questions, hasLength(1));
      expect(n.state.currentIndex, 0);
      expect(n.state.current?.prompt, 'Q1');
      n.dispose();
    });

    test('select stores the pick without revealing', () {
      final n = TriviaNotifier();
      n.load([_q('1', 'Q1', ['a', 'b', 'c'], 2)]);
      n.select(1);
      expect(n.state.selectedIndex, 1);
      expect(n.state.isRevealed, isFalse);
      n.dispose();
    });

    test('viewer can change pick before reveal', () {
      final n = TriviaNotifier();
      n.load([_q('1', 'Q1', ['a', 'b', 'c'], 0)]);
      n.select(0);
      n.select(2);
      expect(n.state.selectedIndex, 2);
      n.dispose();
    });

    test('reveal locks the pick', () {
      final n = TriviaNotifier();
      n.load([_q('1', 'Q1', ['a', 'b', 'c'], 0)]);
      n.select(1);
      n.reveal();
      expect(n.state.isRevealed, isTrue);
      n.select(0); // ignored after reveal
      expect(n.state.selectedIndex, 1);
      n.dispose();
    });

    test('next advances and clears reveal state', () {
      final n = TriviaNotifier();
      n.load([
        _q('1', 'Q1', ['a', 'b'], 0),
        _q('2', 'Q2', ['c', 'd'], 1),
      ]);
      n.select(0);
      n.reveal();
      n.next();
      expect(n.state.currentIndex, 1);
      expect(n.state.isRevealed, isFalse);
      expect(n.state.selectedIndex, isNull);
      n.dispose();
    });

    test('next on last question marks finished (no summary score)', () {
      final n = TriviaNotifier();
      n.load([_q('1', 'Q1', ['a', 'b'], 0)]);
      n.next();
      expect(n.state.isFinished, isTrue);
      // No score/total is computed or exposed.
      n.dispose();
    });

    test('isCorrect is a pure lookup on the question', () {
      final q = _q('1', 'Q1', ['a', 'b', 'c'], 2);
      expect(q.isCorrect(0), isFalse);
      expect(q.isCorrect(2), isTrue);
    });
  });
}

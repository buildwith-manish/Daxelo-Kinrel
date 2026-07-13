// lib/features/trivia/providers/trivia_provider.dart
//
// P9.1 — Family trivia (local-only, NO leaderboard).
//
// A short, opt-in trivia round drawn from a local question bank. There
// is no score persistence, no per-user total, and NO leaderboard — the
// Copy-Audit / Constitution explicitly forbids competition framing.
// The provider exposes only "current question" + "was the answer
// revealed"; correctness is shown for the viewer's own learning and is
// never aggregated or compared.
//
// Constitution / Copy-Audit: no "Be the first", no streaks, no urgency.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class TriviaQuestion {
  const TriviaQuestion({
    required this.id,
    required this.prompt,
    required this.options,
    required this.correctIndex,
    this.context,
  });

  final String id;
  final String prompt;
  final List<String> options;
  final int correctIndex;
  /// Optional honest note shown after reveal (e.g. a source/caveat).
  final String? context;

  bool isCorrect(int index) => index == correctIndex;
}

@immutable
class TriviaState {
  const TriviaState({
    this.questions = const [],
    this.currentIndex = 0,
    this.selectedIndex,
    this.isRevealed = false,
    this.isFinished = false,
  });

  final List<TriviaQuestion> questions;
  final int currentIndex;
  final int? selectedIndex;
  final bool isRevealed;
  final bool isFinished;

  TriviaQuestion? get current =>
      questions.isEmpty || currentIndex >= questions.length
          ? null
          : questions[currentIndex];

  bool get isLast => currentIndex >= questions.length - 1;

  TriviaState copyWith({
    List<TriviaQuestion>? questions,
    int? currentIndex,
    int? selectedIndex,
    bool clearSelection = false,
    bool? isRevealed,
    bool? isFinished,
  }) {
    return TriviaState(
      questions: questions ?? this.questions,
      currentIndex: currentIndex ?? this.currentIndex,
      selectedIndex:
          clearSelection ? null : (selectedIndex ?? this.selectedIndex),
      isRevealed: isRevealed ?? this.isRevealed,
      isFinished: isFinished ?? this.isFinished,
    );
  }
}

class TriviaNotifier extends StateNotifier<TriviaState> {
  TriviaNotifier() : super(const TriviaState());

  /// Loads a question bank. Shuffling is the caller's responsibility so
  /// tests stay deterministic; we only reset cursor + reveal state.
  void load(List<TriviaQuestion> questions) {
    state = TriviaState(questions: questions);
  }

  /// Viewer picks an option. We DO NOT reveal until they explicitly ask,
  /// so they can change their mind without penalty.
  void select(int index) {
    if (state.isRevealed) return; // locked after reveal
    if (state.current == null) return;
    if (index < 0 || index >= state.current!.options.length) return;
    state = state.copyWith(selectedIndex: index);
  }

  /// Reveals the correct answer for the current question. Honest: shows
  /// the viewer whether their pick matched, with no scoring language.
  void reveal() {
    if (state.current == null) return;
    state = state.copyWith(isRevealed: true);
  }

  /// Advances to the next question, or marks the round finished.
  void next() {
    if (state.isLast) {
      state = state.copyWith(isFinished: true);
      return;
    }
    state = state.copyWith(
      currentIndex: state.currentIndex + 1,
      clearSelection: true,
      isRevealed: false,
    );
  }

  /// Ends the round early. No summary score is computed.
  void finish() => state = state.copyWith(isFinished: true);

  void reset() => state = const TriviaState();
}

final triviaProvider =
    StateNotifierProvider<TriviaNotifier, TriviaState>(
  (ref) => TriviaNotifier(),
);

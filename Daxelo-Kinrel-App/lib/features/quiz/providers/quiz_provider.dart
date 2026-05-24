import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/networking/dio_client.dart';

// ── Models ─────────────────────────────────────────────────────────────

class QuizQuestion {
  final String id;
  final String type;
  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;
  final Map<String, dynamic> kinshipData;

  const QuizQuestion({
    required this.id,
    required this.type,
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
    required this.kinshipData,
  });

  factory QuizQuestion.fromJson(Map<String, dynamic> json) {
    return QuizQuestion(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? '',
      question: json['question'] as String? ?? '',
      options: (json['options'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      correctIndex: json['correctIndex'] as int? ?? 0,
      explanation: json['explanation'] as String? ?? '',
      kinshipData: json['kinshipData'] as Map<String, dynamic>? ?? {},
    );
  }
}

class QuizSession {
  final String quizId;
  final List<QuizQuestion> questions;
  final int totalQuestions;
  final String category;
  final String difficulty;
  final String language;

  const QuizSession({
    required this.quizId,
    required this.questions,
    required this.totalQuestions,
    required this.category,
    required this.difficulty,
    required this.language,
  });

  factory QuizSession.fromJson(Map<String, dynamic> json) {
    return QuizSession(
      quizId: json['quizId'] as String? ?? '',
      questions: (json['questions'] as List<dynamic>?)
              ?.map((e) => QuizQuestion.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      totalQuestions: json['totalQuestions'] as int? ?? 0,
      category: json['category'] as String? ?? 'mixed',
      difficulty: json['difficulty'] as String? ?? 'medium',
      language: json['language'] as String? ?? 'hi',
    );
  }
}

class QuizResult {
  final String quizId;
  final int score;
  final int totalQuestions;
  final int correctAnswers;
  final int percentage;
  final int streak;
  final List<QuestionResult> results;

  const QuizResult({
    required this.quizId,
    required this.score,
    required this.totalQuestions,
    required this.correctAnswers,
    required this.percentage,
    required this.streak,
    required this.results,
  });

  factory QuizResult.fromJson(Map<String, dynamic> json) {
    return QuizResult(
      quizId: json['quizId'] as String? ?? '',
      score: json['score'] as int? ?? 0,
      totalQuestions: json['totalQuestions'] as int? ?? 0,
      correctAnswers: json['correctAnswers'] as int? ?? 0,
      percentage: json['percentage'] as int? ?? 0,
      streak: json['streak'] as int? ?? 0,
      results: (json['results'] as List<dynamic>?)
              ?.map((e) => QuestionResult.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class QuestionResult {
  final int questionIndex;
  final bool correct;
  final int yourAnswer;
  final int correctAnswer;

  const QuestionResult({
    required this.questionIndex,
    required this.correct,
    required this.yourAnswer,
    required this.correctAnswer,
  });

  factory QuestionResult.fromJson(Map<String, dynamic> json) {
    return QuestionResult(
      questionIndex: json['questionIndex'] as int? ?? 0,
      correct: json['correct'] as bool? ?? false,
      yourAnswer: json['yourAnswer'] as int? ?? -1,
      correctAnswer: json['correctAnswer'] as int? ?? 0,
    );
  }
}

class LeaderboardEntry {
  final int rank;
  final String name;
  final int score;
  final int streak;
  final String avatar;

  const LeaderboardEntry({
    required this.rank,
    required this.name,
    required this.score,
    required this.streak,
    required this.avatar,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) {
    return LeaderboardEntry(
      rank: json['rank'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      score: json['score'] as int? ?? 0,
      streak: json['streak'] as int? ?? 0,
      avatar: json['avatar'] as String? ?? '',
    );
  }
}

class DailyChallenge {
  final String date;
  final List<QuizQuestion> questions;
  final int totalParticipants;
  final double averageScore;

  const DailyChallenge({
    required this.date,
    required this.questions,
    required this.totalParticipants,
    required this.averageScore,
  });

  factory DailyChallenge.fromJson(Map<String, dynamic> json) {
    return DailyChallenge(
      date: json['date'] as String? ?? '',
      questions: (json['questions'] as List<dynamic>?)
              ?.map((e) => QuizQuestion.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      totalParticipants: json['totalParticipants'] as int? ?? 0,
      averageScore: (json['averageScore'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

// ── Quiz State ─────────────────────────────────────────────────────────

enum QuizState { idle, playing, results }

class QuizStateData {
  final QuizState state;
  final QuizSession? session;
  final QuizResult? result;
  final int currentQuestionIndex;
  final Map<int, int> answers;
  final int? selectedAnswer;
  final bool? isCorrect;
  final bool isGenerating;

  const QuizStateData({
    this.state = QuizState.idle,
    this.session,
    this.result,
    this.currentQuestionIndex = 0,
    this.answers = const {},
    this.selectedAnswer,
    this.isCorrect,
    this.isGenerating = false,
  });

  QuizStateData copyWith({
    QuizState? state,
    QuizSession? session,
    QuizResult? result,
    int? currentQuestionIndex,
    Map<int, int>? answers,
    int? selectedAnswer,
    bool? isCorrect,
    bool? isGenerating,
  }) {
    return QuizStateData(
      state: state ?? this.state,
      session: session ?? this.session,
      result: result ?? this.result,
      currentQuestionIndex: currentQuestionIndex ?? this.currentQuestionIndex,
      answers: answers ?? this.answers,
      selectedAnswer: selectedAnswer ?? this.selectedAnswer,
      isCorrect: isCorrect ?? this.isCorrect,
      isGenerating: isGenerating ?? this.isGenerating,
    );
  }
}

// ── Providers ──────────────────────────────────────────────────────────

final quizStateProvider =
    StateNotifierProvider<QuizStateNotifier, QuizStateData>((ref) {
  return QuizStateNotifier(ref);
});

class QuizStateNotifier extends StateNotifier<QuizStateData> {
  final Ref _ref;

  QuizStateNotifier(this._ref) : super(const QuizStateData());

  Future<void> generateQuiz({
    String? category,
    String language = 'hi',
    int count = 5,
    String difficulty = 'medium',
  }) async {
    state = state.copyWith(isGenerating: true, state: QuizState.idle);

    try {
      final dio = _ref.read(dioProvider);
      final response = await dio.post(
        '/v1/gamification/quiz',
        data: {
          if (category != null) 'category': category,
          'language': language,
          'count': count,
          'difficulty': difficulty,
        },
      );

      final session = QuizSession.fromJson(response.data as Map<String, dynamic>);

      state = state.copyWith(
        state: QuizState.playing,
        session: session,
        currentQuestionIndex: 0,
        answers: {},
        selectedAnswer: null,
        isCorrect: null,
        isGenerating: false,
      );
    } catch (e) {
      state = state.copyWith(isGenerating: false);
      rethrow;
    }
  }

  void selectAnswer(int answerIndex) {
    if (state.session == null || state.selectedAnswer != null) return;

    final currentQuestion =
        state.session!.questions[state.currentQuestionIndex];
    final isCorrect = answerIndex == currentQuestion.correctIndex;

    final newAnswers = Map<int, int>.from(state.answers);
    newAnswers[state.currentQuestionIndex] = answerIndex;

    state = state.copyWith(
      selectedAnswer: answerIndex,
      isCorrect: isCorrect,
      answers: newAnswers,
    );
  }

  void nextQuestion() {
    if (state.session == null) return;

    final nextIndex = state.currentQuestionIndex + 1;

    if (nextIndex >= state.session!.questions.length) {
      submitQuiz();
    } else {
      state = state.copyWith(
        currentQuestionIndex: nextIndex,
        selectedAnswer: null,
        isCorrect: null,
      );
    }
  }

  Future<void> submitQuiz() async {
    if (state.session == null) return;

    try {
      final dio = _ref.read(dioProvider);
      final response = await dio.post(
        '/v1/gamification/quiz/${state.session!.quizId}/submit',
        data: {'answers': state.answers},
      );

      final result = QuizResult.fromJson(response.data as Map<String, dynamic>);

      state = state.copyWith(
        state: QuizState.results,
        result: result,
      );
    } catch (e) {
      // If API call fails, calculate locally
      final questions = state.session!.questions;
      int correctCount = 0;
      final results = <QuestionResult>[];

      for (int i = 0; i < questions.length; i++) {
        final yourAnswer = state.answers[i] ?? -1;
        final correct = yourAnswer == questions[i].correctIndex;
        if (correct) correctCount++;
        results.add(QuestionResult(
          questionIndex: i,
          correct: correct,
          yourAnswer: yourAnswer,
          correctAnswer: questions[i].correctIndex,
        ));
      }

      int streak = 0;
      for (final r in results) {
        if (r.correct) {
          streak++;
        } else {
          break;
        }
      }

      final localResult = QuizResult(
        quizId: state.session!.quizId,
        score: correctCount,
        totalQuestions: questions.length,
        correctAnswers: correctCount,
        percentage: questions.isNotEmpty
            ? ((correctCount / questions.length) * 100).round()
            : 0,
        streak: streak,
        results: results,
      );

      state = state.copyWith(
        state: QuizState.results,
        result: localResult,
      );
    }
  }

  void resetQuiz() {
    state = const QuizStateData();
  }

  void goToQuestion(int index) {
    if (state.session == null) return;
    if (index < 0 || index >= state.session!.questions.length) return;

    // Only allow going back to already answered questions
    state = state.copyWith(
      currentQuestionIndex: index,
      selectedAnswer: null,
      isCorrect: null,
    );
  }
}

// ── Leaderboard Provider ───────────────────────────────────────────────

final leaderboardProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, period) async {
  final dio = ref.read(dioProvider);
  final response = await dio.get(
    '/v1/gamification/leaderboard',
    queryParameters: {'period': period, 'limit': 10},
  );
  return response.data as Map<String, dynamic>;
});

// ── Daily Challenge Provider ───────────────────────────────────────────

final dailyChallengeProvider = FutureProvider<DailyChallenge>((ref) async {
  final dio = ref.read(dioProvider);
  final response = await dio.get('/v1/gamification/daily-challenge');
  final data = response.data as Map<String, dynamic>;
  return DailyChallenge.fromJson(data['challenge'] as Map<String, dynamic>);
});

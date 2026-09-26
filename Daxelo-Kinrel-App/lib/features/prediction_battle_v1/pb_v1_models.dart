// lib/features/prediction_battle_v1/pb_v1_models.dart
//
// Prediction Battle v1 — data models for the scheduled numeric-estimation game.

/// A prediction question from the pb_v1_questions table.
class PBv1Question {
  const PBv1Question({
    required this.id,
    required this.questionText,
    required this.correctAnswer,
    required this.unitLabel,
    required this.category,
    this.funFactText = '',
    this.minBound,
    this.maxBound,
    this.isActive = true,
  });

  final String id;
  final String questionText;
  final double correctAnswer;
  final String unitLabel;
  final String category;
  final String funFactText;
  final double? minBound;
  final double? maxBound;
  final bool isActive;

  factory PBv1Question.fromJson(Map<String, dynamic> json) => PBv1Question(
    id: (json['id'] ?? json['question_id'] ?? '') as String,
    questionText: (json['questionText'] ?? json['question_text'] ?? '') as String,
    correctAnswer: ((json['correctAnswer'] ?? json['correct_answer'] ?? 0) as num).toDouble(),
    unitLabel: (json['unitLabel'] ?? json['unit_label'] ?? '') as String,
    category: (json['category'] ?? 'general') as String,
    funFactText: (json['funFactText'] ?? json['fun_fact_text'] ?? '') as String,
    minBound: (json['minBound'] ?? json['min_bound'] as num?)?.toDouble(),
    maxBound: (json['maxBound'] ?? json['max_bound'] as num?)?.toDouble(),
    isActive: (json['isActive'] ?? json['is_active'] ?? true) as bool,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'question_text': questionText,
    'correct_answer': correctAnswer,
    'unit_label': unitLabel,
    'category': category,
    'fun_fact_text': funFactText,
    'min_bound': minBound,
    'max_bound': maxBound,
    'is_active': isActive,
  };
}

/// A prediction round from the pb_v1_rounds table.
class PBv1Round {
  const PBv1Round({
    required this.id,
    required this.familyId,
    required this.questionId,
    required this.opensAt,
    required this.revealAt,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String familyId;
  final String questionId;
  final DateTime opensAt;
  final DateTime revealAt;
  final String status; // 'open' | 'revealed'
  final DateTime createdAt;

  bool get isOpen => status == 'open';
  bool get isRevealed => status == 'revealed';
  bool get isPastReveal => DateTime.now().toUtc().isAfter(revealAt);

  factory PBv1Round.fromJson(Map<String, dynamic> json) => PBv1Round(
    id: (json['id'] ?? '') as String,
    familyId: (json['familyId'] ?? json['family_id'] ?? '') as String,
    questionId: (json['questionId'] ?? json['question_id'] ?? '') as String,
    opensAt: DateTime.tryParse((json['opensAt'] ?? json['opens_at'] ?? '').toString()) ?? DateTime.now(),
    revealAt: DateTime.tryParse((json['revealAt'] ?? json['reveal_at'] ?? '').toString()) ?? DateTime.now(),
    status: (json['status'] ?? 'open') as String,
    createdAt: DateTime.tryParse((json['createdAt'] ?? json['created_at'] ?? '').toString()) ?? DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'question_id': questionId,
    'opens_at': opensAt.toUtc().toIso8601String(),
    'reveal_at': revealAt.toUtc().toIso8601String(),
    'status': status,
    'created_at': createdAt.toUtc().toIso8601String(),
  };
}

/// A user's guess for a round.
class PBv1Guess {
  const PBv1Guess({
    required this.userId,
    required this.guessValue,
    required this.submittedAt,
    this.distance,
  });

  final String userId;
  final double guessValue;
  final DateTime submittedAt;
  final double? distance;

  factory PBv1Guess.fromJson(Map<String, dynamic> json) => PBv1Guess(
    userId: (json['userId'] ?? json['user_id'] ?? '') as String,
    guessValue: ((json['guessValue'] ?? json['guess_value'] ?? 0) as num).toDouble(),
    submittedAt: DateTime.tryParse((json['submittedAt'] ?? json['submitted_at'] ?? '').toString()) ?? DateTime.now(),
    distance: (json['distance'] as num?)?.toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'guess_value': guessValue,
    'submitted_at': submittedAt.toUtc().toIso8601String(),
    if (distance != null) 'distance': distance,
  };
}

/// The full state of the prediction battle for a family.
class PBv1State {
  const PBv1State({
    this.round,
    this.question,
    this.myGuess,
    this.allGuesses = const [],
    this.winnerUserIds = const [],
    this.revealed = false,
    this.isLoading = false,
    this.isSubmitting = false,
    /// True while myGuess is showing an optimistic local value that the
    /// server hasn't confirmed yet. Cleared on success or rollback.
    this.isOptimisticGuess = false,
    this.error,
  });

  final PBv1Round? round;
  final PBv1Question? question;
  final PBv1Guess? myGuess;
  final List<PBv1Guess> allGuesses;
  final List<String> winnerUserIds;
  final bool revealed;
  final bool isLoading;
  final bool isSubmitting;
  final bool isOptimisticGuess;
  final String? error;

  PBv1State copyWith({
    PBv1Round? round,
    PBv1Question? question,
    PBv1Guess? myGuess,
    List<PBv1Guess>? allGuesses,
    List<String>? winnerUserIds,
    bool? revealed,
    bool? isLoading,
    bool? isSubmitting,
    bool? isOptimisticGuess,
    bool clearError = false,
    bool clearMyGuess = false,
    String? error,
  }) => PBv1State(
    round: round ?? this.round,
    question: question ?? this.question,
    myGuess: clearMyGuess ? null : (myGuess ?? this.myGuess),
    allGuesses: allGuesses ?? this.allGuesses,
    winnerUserIds: winnerUserIds ?? this.winnerUserIds,
    revealed: revealed ?? this.revealed,
    isLoading: isLoading ?? this.isLoading,
    isSubmitting: isSubmitting ?? this.isSubmitting,
    isOptimisticGuess: isOptimisticGuess ?? this.isOptimisticGuess,
    error: clearError ? null : (error ?? this.error),
  );
}

/// Scoring engine — mirrors the server-side logic.
class PBv1Scoring {
  PBv1Scoring._();

  /// Compute distance: percentage-based for correct_answer > 1000,
  /// absolute otherwise.
  static double distance(double guess, double correct) {
    if (correct > 1000) {
      return (guess - correct).abs() / correct * 100;
    }
    return (guess - correct).abs();
  }

  /// Rank guesses by distance (closest first).
  static List<Map<String, dynamic>> rankGuesses(
    List<PBv1Guess> guesses,
    double correctAnswer,
  ) {
    final ranked = guesses.map((g) {
      final d = distance(g.guessValue, correctAnswer);
      return {'guess': g, 'distance': d};
    }).toList()
      ..sort((a, b) => (a['distance'] as double).compareTo(b['distance'] as double));
    return ranked;
  }
}

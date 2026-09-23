// lib/features/prediction_battle_v1/pb_v1_history_models.dart
//
// Data models for the Prediction Battle v1 History screen. Maps the
// JSON shape returned by the `fn_pb_v1_get_history` Supabase RPC.
//
// The history RPC returns three things in one round-trip:
//   - streaks: { current_streak, best_streak, updated_at }
//   - rounds:  an array of revealed rounds with the requesting user's
//              guess (or null), the winner set, distance, etc.
//
// All models support toJson/fromJson so the history provider can cache
// the response via LocalCacheService (mirroring the cache-first
// pattern used by pb_v1_provider.dart).

/// The user's win streak for a family.
class PBv1Streak {
  const PBv1Streak({
    required this.currentStreak,
    required this.bestStreak,
    this.updatedAt,
  });

  final int currentStreak;
  final int bestStreak;
  final DateTime? updatedAt;

  factory PBv1Streak.fromJson(Map<String, dynamic> json) => PBv1Streak(
    currentStreak: (json['currentStreak'] ?? json['current_streak'] ?? 0) as int,
    bestStreak: (json['bestStreak'] ?? json['best_streak'] ?? 0) as int,
    updatedAt: DateTime.tryParse((json['updatedAt'] ?? json['updated_at'] ?? '').toString()),
  );

  Map<String, dynamic> toJson() => {
    'current_streak': currentStreak,
    'best_streak': bestStreak,
    'updated_at': updatedAt?.toUtc().toIso8601String(),
  };

  static const empty = PBv1Streak(currentStreak: 0, bestStreak: 0);
}

/// The requesting user's guess for a single past round (or null if
/// they didn't participate). Same shape as PBv1Guess but slightly
/// slimmer — we don't need submittedAt for the history view.
class PBv1HistoryGuess {
  const PBv1HistoryGuess({
    required this.guessValue,
    required this.distance,
  });

  final double guessValue;
  final double distance;

  factory PBv1HistoryGuess.fromJson(Map<String, dynamic> json) => PBv1HistoryGuess(
    guessValue: ((json['guessValue'] ?? json['guess_value'] ?? 0) as num).toDouble(),
    distance: ((json['distance'] ?? 0) as num).toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'guess_value': guessValue,
    'distance': distance,
  };
}

/// A single round in the history list.
class PBv1HistoryRound {
  const PBv1HistoryRound({
    required this.roundId,
    required this.questionId,
    required this.opensAt,
    required this.revealAt,
    required this.status,
    required this.questionText,
    required this.correctAnswer,
    required this.unitLabel,
    required this.category,
    required this.funFactText,
    required this.winnerUserIds,
    required this.totalGuesses,
    required this.iWon,
    this.myGuess,
  });

  final String roundId;
  final String questionId;
  final DateTime opensAt;
  final DateTime revealAt;
  final String status;
  final String questionText;
  final double correctAnswer;
  final String unitLabel;
  final String category;
  final String funFactText;
  final List<String> winnerUserIds;
  final int totalGuesses;
  final bool iWon;
  final PBv1HistoryGuess? myGuess;

  factory PBv1HistoryRound.fromJson(Map<String, dynamic> json) => PBv1HistoryRound(
    roundId: (json['roundId'] ?? json['round_id'] ?? '') as String,
    questionId: (json['questionId'] ?? json['question_id'] ?? '') as String,
    opensAt: DateTime.tryParse((json['opensAt'] ?? json['opens_at'] ?? '').toString()) ?? DateTime.now(),
    revealAt: DateTime.tryParse((json['revealAt'] ?? json['reveal_at'] ?? '').toString()) ?? DateTime.now(),
    status: (json['status'] ?? 'revealed') as String,
    questionText: (json['questionText'] ?? json['question_text'] ?? '') as String,
    correctAnswer: ((json['correctAnswer'] ?? json['correct_answer'] ?? 0) as num).toDouble(),
    unitLabel: (json['unitLabel'] ?? json['unit_label'] ?? '') as String,
    category: (json['category'] ?? 'general') as String,
    funFactText: (json['funFactText'] ?? json['fun_fact_text'] ?? '') as String,
    winnerUserIds: (json['winnerUserIds'] ?? json['winner_user_ids'] ?? const [])
        .whereType<String>()
        .toList(),
    totalGuesses: (json['totalGuesses'] ?? json['total_guesses'] ?? 0) as int,
    iWon: (json['iWon'] ?? json['i_won'] ?? false) as bool,
    myGuess: json['myGuess'] is Map
        ? PBv1HistoryGuess.fromJson(Map<String, dynamic>.from(json['myGuess'] as Map))
        : (json['my_guess'] is Map
            ? PBv1HistoryGuess.fromJson(Map<String, dynamic>.from(json['my_guess'] as Map))
            : null),
  );

  Map<String, dynamic> toJson() => {
    'round_id': roundId,
    'question_id': questionId,
    'opens_at': opensAt.toUtc().toIso8601String(),
    'reveal_at': revealAt.toUtc().toIso8601String(),
    'status': status,
    'question_text': questionText,
    'correct_answer': correctAnswer,
    'unit_label': unitLabel,
    'category': category,
    'fun_fact_text': funFactText,
    'winner_user_ids': winnerUserIds,
    'total_guesses': totalGuesses,
    'i_won': iWon,
    'my_guess': myGuess?.toJson(),
  };

  /// True if the user did NOT submit a guess for this round.
  bool get missed => myGuess == null;

  /// True if the user tied for closest guess.
  bool get won => iWon;
}

/// The full state returned by the history RPC.
class PBv1History {
  const PBv1History({
    required this.streak,
    required this.rounds,
    required this.cachedAt,
  });

  final PBv1Streak streak;
  final List<PBv1HistoryRound> rounds;
  final String cachedAt;

  factory PBv1History.fromJson(Map<String, dynamic> json) => PBv1History(
    streak: json['streak'] is Map
        ? PBv1Streak.fromJson(Map<String, dynamic>.from(json['streak'] as Map))
        : PBv1Streak.empty,
    rounds: (json['rounds'] as List? ?? const [])
        .whereType<Map>()
        .map((r) => PBv1HistoryRound.fromJson(Map<String, dynamic>.from(r)))
        .toList(),
    cachedAt: (json['cachedAt'] ?? '') as String,
  );

  Map<String, dynamic> toJson() => {
    'streak': streak.toJson(),
    'rounds': rounds.map((r) => r.toJson()).toList(),
    'cachedAt': cachedAt,
  };

  /// Quick stat: how many of the visible rounds did the user win?
  int get winsCount => rounds.where((r) => r.won).length;

  /// Quick stat: how many of the visible rounds did the user participate in?
  int get participatedCount => rounds.where((r) => !r.missed).length;

  /// Quick stat: total rounds in the visible window.
  int get totalRounds => rounds.length;
}

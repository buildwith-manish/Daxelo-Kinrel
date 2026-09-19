// lib/features/prediction_battle/prediction_models.dart

enum PredictionType { closest, outcome }
enum PredictionStatus { open, locked, pending, resolved, archived }
enum PredictionConfidence { low, medium, high }

extension PredictionTypeX on PredictionType {
  static PredictionType fromString(String? s) =>
      s == 'outcome' ? PredictionType.outcome : PredictionType.closest;
  String get label => this == PredictionType.closest ? 'Closest Wins' : 'Outcome Prediction';
}

extension PredictionStatusX on PredictionStatus {
  static PredictionStatus fromString(String? s) {
    switch (s) {
      case 'locked': return PredictionStatus.locked;
      case 'pending': return PredictionStatus.pending;
      case 'resolved': return PredictionStatus.resolved;
      case 'archived': return PredictionStatus.archived;
      default: return PredictionStatus.open;
    }
  }
  String get label {
    switch (this) {
      case PredictionStatus.open: return 'OPEN';
      case PredictionStatus.locked: return 'LOCKED';
      case PredictionStatus.pending: return 'PENDING';
      case PredictionStatus.resolved: return 'RESOLVED';
      case PredictionStatus.archived: return 'ARCHIVED';
    }
  }
}

extension PredictionConfidenceX on PredictionConfidence {
  String get wire => name;
  String get label => name[0].toUpperCase() + name.substring(1);
  double get multiplier {
    switch (this) {
      case PredictionConfidence.high: return 1.5;
      case PredictionConfidence.medium: return 1.2;
      case PredictionConfidence.low: return 1.0;
    }
  }
  static PredictionConfidence fromString(String? s) {
    switch (s) {
      case 'high': return PredictionConfidence.high;
      case 'medium': return PredictionConfidence.medium;
      default: return PredictionConfidence.low;
    }
  }
}

class PredictionQuestion {
  const PredictionQuestion({
    required this.id,
    required this.question,
    required this.type,
    required this.category,
    this.correctAnswer,
    this.optionA,
    this.optionB,
    this.isLegendary = false,
  });
  final String id;
  final String question;
  final PredictionType type;
  final String category;
  final String? correctAnswer;
  final String? optionA;
  final String? optionB;
  final bool isLegendary;

  factory PredictionQuestion.fromJson(Map<String, dynamic> json) => PredictionQuestion(
    id: (json['id'] ?? '') as String,
    question: (json['question'] ?? '') as String,
    type: PredictionTypeX.fromString(json['type'] as String?),
    category: (json['category'] ?? 'general') as String,
    correctAnswer: json['correctAnswer'] as String?,
    optionA: json['optionA'] as String?,
    optionB: json['optionB'] as String?,
    isLegendary: (json['isLegendary'] as bool?) ?? false,
  );
}

class PredictionRound {
  const PredictionRound({
    required this.id,
    required this.familyId,
    required this.questionId,
    required this.status,
    required this.lockAt,
    required this.revealAt,
    this.resolvedAt,
    this.actualAnswer,
    this.winnerUserIds = const [],
    this.results = const [],
    this.isLegendary = false,
    this.createdAt,
  });
  final String id;
  final String familyId;
  final String questionId;
  final PredictionStatus status;
  final DateTime lockAt;
  final DateTime revealAt;
  final DateTime? resolvedAt;
  final String? actualAnswer;
  final List<String> winnerUserIds;
  final List<PredictionResult> results;
  final bool isLegendary;
  final DateTime? createdAt;

  factory PredictionRound.fromJson(Map<String, dynamic> json) {
    final winners = <String>[];
    final rawWinners = json['winnerUserIds'];
    if (rawWinners is List) winners.addAll(rawWinners.whereType<String>());
    final results = <PredictionResult>[];
    final rawResults = json['results'];
    if (rawResults is List) {
      for (final r in rawResults) {
        if (r is Map) results.add(PredictionResult.fromJson(Map<String, dynamic>.from(r)));
      }
    }
    return PredictionRound(
      id: (json['id'] ?? '') as String,
      familyId: (json['familyId'] ?? '') as String,
      questionId: (json['questionId'] ?? '') as String,
      status: PredictionStatusX.fromString(json['status'] as String?),
      lockAt: DateTime.tryParse(json['lockAt'] ?? '') ?? DateTime.now(),
      revealAt: DateTime.tryParse(json['revealAt'] ?? '') ?? DateTime.now(),
      resolvedAt: json['resolvedAt'] != null ? DateTime.tryParse(json['resolvedAt'] as String) : null,
      actualAnswer: json['actualAnswer'] as String?,
      winnerUserIds: winners,
      results: results,
      isLegendary: (json['isLegendary'] as bool?) ?? false,
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'] as String) : null,
    );
  }
}

class PredictionResult {
  const PredictionResult({
    required this.userId,
    required this.prediction,
    required this.confidence,
    required this.correct,
    this.distance,
    this.points = 0,
    this.rank = 0,
  });
  final String userId;
  final String prediction;
  final PredictionConfidence confidence;
  final bool correct;
  final double? distance;
  final int points;
  final int rank;

  factory PredictionResult.fromJson(Map<String, dynamic> json) => PredictionResult(
    userId: (json['userId'] ?? '') as String,
    prediction: (json['prediction'] ?? '') as String,
    confidence: PredictionConfidenceX.fromString(json['confidence'] as String?),
    correct: (json['correct'] as bool?) ?? false,
    distance: json['distance'] != null ? (json['distance'] as num).toDouble() : null,
    points: (json['points'] as num?)?.toInt() ?? 0,
    rank: (json['rank'] as num?)?.toInt() ?? 0,
  );
}

class PredictionLeaderboardEntry {
  const PredictionLeaderboardEntry({
    required this.userId,
    required this.points,
    required this.wins,
    required this.correctPredictions,
    required this.totalPredictions,
    required this.currentStreak,
    required this.bestStreak,
  });
  final String userId;
  final int points;
  final int wins;
  final int correctPredictions;
  final int totalPredictions;
  final int currentStreak;
  final int bestStreak;

  double get accuracy => totalPredictions > 0 ? correctPredictions / totalPredictions : 0.0;

  factory PredictionLeaderboardEntry.fromJson(Map<String, dynamic> json) => PredictionLeaderboardEntry(
    userId: (json['userId'] ?? '') as String,
    points: (json['points'] as num?)?.toInt() ?? 0,
    wins: (json['wins'] as num?)?.toInt() ?? 0,
    correctPredictions: (json['correctPredictions'] as num?)?.toInt() ?? 0,
    totalPredictions: (json['totalPredictions'] as num?)?.toInt() ?? 0,
    currentStreak: (json['currentStreak'] as num?)?.toInt() ?? 0,
    bestStreak: (json['bestStreak'] as num?)?.toInt() ?? 0,
  );
}

/// Pure Dart scoring engine — mirrors the server-side fn_prediction_resolve logic.
class PredictionEngine {
  PredictionEngine._();

  /// Calculate points for a closest-wins prediction.
  static int calculateClosestPoints({
    required double distance,
    required int rank,
    required PredictionConfidence confidence,
  }) {
    final basePoints = switch (rank) {
      1 => 10,
      2 => 6,
      3 => 3,
      _ => 0,
    };
    var mult = confidence.multiplier;
    if (distance > 0 && confidence == PredictionConfidence.high) {
      mult = 0.7; // wrong high-confidence gets reduced
    }
    return (basePoints * mult).round();
  }

  /// Calculate points for an outcome prediction.
  static int calculateOutcomePoints({
    required bool correct,
    required PredictionConfidence confidence,
  }) {
    final basePoints = correct ? 10 : 0;
    var mult = confidence.multiplier;
    if (!correct && confidence == PredictionConfidence.high) {
      mult = 0.3; // wrong high-confidence gets heavily reduced
    }
    return (basePoints * mult).round();
  }

  /// Compute distance for closest-wins.
  static double distance(String prediction, String actual) {
    final p = double.tryParse(prediction) ?? 0;
    final a = double.tryParse(actual) ?? 0;
    return (p - a).abs();
  }

  /// Rank predictions by distance (closest first).
  static List<(String userId, double distance, int rank)> rankByDistance(
      List<(String userId, String prediction)> predictions, String actualAnswer) {
    final distances = predictions.map((p) {
      final d = distance(p.$2, actualAnswer);
      return (p.$1, d);
    }).toList()
      ..sort((a, b) => a.$2.compareTo(b.$2));

    final result = <(String, double, int)>[];
    var rank = 0;
    double? lastDistance;
    for (var i = 0; i < distances.length; i++) {
      if (lastDistance == null || distances[i].$2 != lastDistance) {
        rank = i + 1;
        lastDistance = distances[i].$2;
      }
      result.add((distances[i].$1, distances[i].$2, rank));
    }
    return result;
  }
}

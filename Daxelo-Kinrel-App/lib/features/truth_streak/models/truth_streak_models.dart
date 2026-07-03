// lib/features/truth_streak/models/truth_streak_models.dart
//
// DAXELO KINREL — Truth Streak data models

/// A question from the shared question bank.
class TruthStreakQuestion {
  const TruthStreakQuestion({
    required this.id,
    required this.question,
    this.category = 'general',
    this.isActive = true,
  });

  final String id;
  final String question;
  final String category;
  final bool isActive;

  factory TruthStreakQuestion.fromJson(Map<String, dynamic> json) {
    return TruthStreakQuestion(
      id: json['id'] as String? ?? '',
      question: json['question'] as String? ?? '',
      category: json['category'] as String? ?? 'general',
      isActive: json['isActive'] as bool? ?? true,
    );
  }
}

/// The daily assignment — one question per family per day.
class TruthStreakAssignment {
  const TruthStreakAssignment({
    required this.id,
    required this.familyId,
    required this.questionId,
    required this.assignedDate,
    this.question,
  });

  final String id;
  final String familyId;
  final String questionId;
  final DateTime assignedDate;
  final TruthStreakQuestion? question;

  factory TruthStreakAssignment.fromJson(Map<String, dynamic> json) {
    return TruthStreakAssignment(
      id: json['id'] as String? ?? '',
      familyId: json['familyId'] as String? ?? '',
      questionId: json['questionId'] as String? ?? '',
      assignedDate:
          DateTime.tryParse(json['assignedDate'] as String? ?? '') ??
          DateTime.now(),
      question: json['question'] != null
          ? TruthStreakQuestion.fromJson(
              json['question'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// A single user's answer to a daily assignment.
class TruthStreakAnswer {
  const TruthStreakAnswer({
    required this.id,
    required this.assignmentId,
    required this.userId,
    required this.userName,
    this.userAvatarUrl,
    required this.answer,
    required this.createdAt,
  });

  final String id;
  final String assignmentId;
  final String userId;
  final String userName;
  final String? userAvatarUrl;
  final String answer;
  final DateTime createdAt;

  factory TruthStreakAnswer.fromJson(Map<String, dynamic> json) {
    return TruthStreakAnswer(
      id: json['id'] as String? ?? '',
      assignmentId: json['assignmentId'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      userName: json['userName'] as String? ?? 'Member',
      userAvatarUrl: json['userAvatarUrl'] as String?,
      answer: json['answer'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

/// Streak stats for a user in a family.
class TruthStreakStats {
  const TruthStreakStats({
    required this.userId,
    required this.familyId,
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.lastAnsweredDate,
  });

  final String userId;
  final String familyId;
  final int currentStreak;
  final int longestStreak;
  final DateTime? lastAnsweredDate;

  factory TruthStreakStats.fromJson(Map<String, dynamic> json) {
    return TruthStreakStats(
      userId: json['userId'] as String? ?? '',
      familyId: json['familyId'] as String? ?? '',
      currentStreak: json['currentStreak'] as int? ?? 0,
      longestStreak: json['longestStreak'] as int? ?? 0,
      lastAnsweredDate: json['lastAnsweredDate'] != null
          ? DateTime.tryParse(json['lastAnsweredDate'] as String)
          : null,
    );
  }
}

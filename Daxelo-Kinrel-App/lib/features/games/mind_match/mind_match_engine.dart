// lib/features/games/mind_match/mind_match_engine.dart
//
// Mind Match — pure Dart game engine.
//
// "Think Like The Group" social party game. 2–8 players. Each round, a
// question appears (e.g. "Name a fruit"). Players submit answers
// privately. When all answers are locked (or the timer expires), answers
// are grouped by normalized form. Players who matched the most popular
// answer earn the most points.
//
// Architecture reuses the hidden-submission pattern from impostor +
// secret_heist: the server (Postgres RPCs) is authoritative for state.
// This engine is used client-side to:
//   • Parse boardState JSON from the server
//   • Compute display labels + colors for the UI
//   • Validate answer submissions before sending
//
// Scoring (matches the SQL in fn_mindmatch_resolve):
//   • Group of size N: each member gets N*5 points
//   • Solo answer (group of 1): 2 points
//   • Crowd Favorite bonus: members of largest group get +5
//   • Perfect Match bonus (everyone same): everyone gets +20
//   • Streak bonus: 2+ consecutive matched rounds = +5 per streak level

const int kMindMatchMinPlayers = 2;
const int kMindMatchMaxPlayers = 8;
const int kMindMatchDefaultAnswerSeconds = 30;
const int kMindMatchMaxAnswerLength = 60;

/// Question categories.
enum MindMatchCategory { everyday, fun, family, global }

extension MindMatchCategoryX on MindMatchCategory {
  String get wire => name;

  static MindMatchCategory fromString(String? s) {
    switch (s) {
      case 'fun':
        return MindMatchCategory.fun;
      case 'family':
        return MindMatchCategory.family;
      case 'global':
        return MindMatchCategory.global;
      case 'everyday':
      default:
        return MindMatchCategory.everyday;
    }
  }

  String get label {
    switch (this) {
      case MindMatchCategory.everyday:
        return 'Everyday Life';
      case MindMatchCategory.fun:
        return 'Fun';
      case MindMatchCategory.family:
        return 'Family';
      case MindMatchCategory.global:
        return 'Global';
    }
  }

  /// Premium accent color (hex) for the category's UI affordances.
  int get accentArgb {
    switch (this) {
      case MindMatchCategory.everyday:
        return 0xFF10B981; // emerald
      case MindMatchCategory.fun:
        return 0xFFF59E0B; // amber
      case MindMatchCategory.family:
        return 0xFFEC4899; // pink
      case MindMatchCategory.global:
        return 0xFF3B82F6; // blue
    }
  }

  String get glyph {
    switch (this) {
      case MindMatchCategory.everyday:
        return '🏠';
      case MindMatchCategory.fun:
        return '🎉';
      case MindMatchCategory.family:
        return '👨‍👩‍👧';
      case MindMatchCategory.global:
        return '🌍';
    }
  }
}

/// Round phase — drives the UI state machine.
enum MindMatchPhase {
  answering,    // players submit answers
  resolving,    // server is computing matches (transient)
  revealing,    // results shown
  finished,     // match over
}

extension MindMatchPhaseX on MindMatchPhase {
  String get wire {
    switch (this) {
      case MindMatchPhase.answering:
        return 'answering';
      case MindMatchPhase.resolving:
        return 'resolving';
      case MindMatchPhase.revealing:
        return 'revealing';
      case MindMatchPhase.finished:
        return 'finished';
    }
  }

  static MindMatchPhase fromString(String? s) {
    switch (s) {
      case 'resolving':
        return MindMatchPhase.resolving;
      case 'revealing':
        return MindMatchPhase.revealing;
      case 'finished':
        return MindMatchPhase.finished;
      case 'answering':
      default:
        return MindMatchPhase.answering;
    }
  }
}

/// A player row inside the boardState JSON.
class MindMatchPlayer {
  const MindMatchPlayer({
    required this.idx,
    required this.userId,
    required this.name,
    required this.score,
    required this.lastRoundPoints,
    required this.streak,
    required this.perfectMatches,
  });

  final int idx;
  final String userId;
  final String name;
  final int score;
  final int lastRoundPoints;
  final int streak;
  final int perfectMatches;

  MindMatchPlayer copyWith({
    int? score,
    int? lastRoundPoints,
    int? streak,
    int? perfectMatches,
  }) =>
      MindMatchPlayer(
        idx: idx,
        userId: userId,
        name: name,
        score: score ?? this.score,
        lastRoundPoints: lastRoundPoints ?? this.lastRoundPoints,
        streak: streak ?? this.streak,
        perfectMatches: perfectMatches ?? this.perfectMatches,
      );

  Map<String, dynamic> toJson() => {
        'idx': idx,
        'userId': userId,
        'name': name,
        'score': score,
        'lastRoundPoints': lastRoundPoints,
        'streak': streak,
        'perfectMatches': perfectMatches,
      };

  factory MindMatchPlayer.fromJson(Map<String, dynamic> json) =>
      MindMatchPlayer(
        idx: (json['idx'] as num?)?.toInt() ?? 0,
        userId: (json['userId'] ?? '') as String,
        name: (json['name'] ?? 'Player') as String,
        score: (json['score'] as num?)?.toInt() ?? 0,
        lastRoundPoints:
            (json['lastRoundPoints'] as num?)?.toInt() ?? 0,
        streak: (json['streak'] as num?)?.toInt() ?? 0,
        perfectMatches:
            (json['perfectMatches'] as num?)?.toInt() ?? 0,
      );
}

/// A group of matching answers (post-resolution).
class MindMatchAnswerGroup {
  const MindMatchAnswerGroup({
    required this.answer,
    required this.normalizedAnswer,
    required this.userIds,
    required this.userNames,
    required this.playerIndices,
    required this.size,
  });

  final String answer;
  final String normalizedAnswer;
  final List<String> userIds;
  final List<String> userNames;
  final List<int> playerIndices;
  final int size;

  /// Points each member earns (size * 5 if matched, 2 if solo).
  int get basePoints => size >= 2 ? size * 5 : 2;

  /// True if this is a matched group (2+ players).
  bool get isMatched => size >= 2;

  Map<String, dynamic> toJson() => {
        'answer': answer,
        'normalizedAnswer': normalizedAnswer,
        'userIds': userIds,
        'userNames': userNames,
        'playerIndices': playerIndices,
        'size': size,
      };

  factory MindMatchAnswerGroup.fromJson(Map<String, dynamic> json) =>
      MindMatchAnswerGroup(
        answer: (json['answer'] ?? '') as String,
        normalizedAnswer:
            (json['normalizedAnswer'] ?? '') as String,
        userIds: (json['userIds'] as List? ?? [])
            .map((e) => e.toString())
            .toList(),
        userNames: (json['userNames'] as List? ?? [])
            .map((e) => e.toString())
            .toList(),
        playerIndices: (json['playerIndices'] as List? ?? [])
            .map((e) => (e as num).toInt())
            .toList(),
        size: (json['size'] as num?)?.toInt() ?? 1,
      );
}

/// Points awarded to a single player for a round.
class MindMatchPointsAwarded {
  const MindMatchPointsAwarded({
    required this.playerIndex,
    required this.points,
    required this.matched,
    required this.groupSize,
    required this.crowdBonus,
    required this.perfectBonus,
    required this.streak,
  });

  final int playerIndex;
  final int points;
  final bool matched;
  final int groupSize;
  final bool crowdBonus;
  final bool perfectBonus;
  final int streak;

  Map<String, dynamic> toJson() => {
        'playerIndex': playerIndex,
        'points': points,
        'matched': matched,
        'groupSize': groupSize,
        'crowdBonus': crowdBonus,
        'perfectBonus': perfectBonus,
        'streak': streak,
      };

  factory MindMatchPointsAwarded.fromJson(Map<String, dynamic> json) =>
      MindMatchPointsAwarded(
        playerIndex:
            (json['playerIndex'] as num?)?.toInt() ?? 0,
        points: (json['points'] as num?)?.toInt() ?? 0,
        matched: (json['matched'] as bool?) ?? false,
        groupSize: (json['groupSize'] as num?)?.toInt() ?? 1,
        crowdBonus: (json['crowdBonus'] as bool?) ?? false,
        perfectBonus: (json['perfectBonus'] as bool?) ?? false,
        streak: (json['streak'] as num?)?.toInt() ?? 0,
      );
}

/// One round's snapshot.
class MindMatchRound {
  const MindMatchRound({
    required this.roundNumber,
    required this.phase,
    required this.questionId,
    required this.questionPrompt,
    required this.questionCategory,
    required this.lockedCount,
    required this.answerGroups,
    required this.crowdFavorite,
    required this.perfectMatch,
    required this.pointsAwarded,
  });

  final int roundNumber;
  final MindMatchPhase phase;
  final String questionId;
  final String questionPrompt;
  final String questionCategory;
  final int lockedCount;
  final List<MindMatchAnswerGroup> answerGroups;
  final String? crowdFavorite;
  final bool perfectMatch;
  final List<MindMatchPointsAwarded> pointsAwarded;

  MindMatchCategory get category =>
      MindMatchCategoryX.fromString(questionCategory);

  Map<String, dynamic> toJson() => {
        'roundNumber': roundNumber,
        'phase': phase.wire,
        'questionId': questionId,
        'questionPrompt': questionPrompt,
        'questionCategory': questionCategory,
        'lockedCount': lockedCount,
        'answerGroups': answerGroups.map((g) => g.toJson()).toList(),
        'crowdFavorite': crowdFavorite,
        'perfectMatch': perfectMatch,
        'pointsAwarded': pointsAwarded.map((p) => p.toJson()).toList(),
      };

  factory MindMatchRound.fromJson(Map<String, dynamic> json) {
    final groupsList = <MindMatchAnswerGroup>[];
    final rawGroups = json['answerGroups'];
    if (rawGroups is List) {
      for (final g in rawGroups) {
        if (g is Map) {
          groupsList.add(MindMatchAnswerGroup.fromJson(
              Map<String, dynamic>.from(g)));
        }
      }
    }
    final pointsList = <MindMatchPointsAwarded>[];
    final rawPoints = json['pointsAwarded'];
    if (rawPoints is List) {
      for (final p in rawPoints) {
        if (p is Map) {
          pointsList.add(MindMatchPointsAwarded.fromJson(
              Map<String, dynamic>.from(p)));
        }
      }
    }
    return MindMatchRound(
      roundNumber: (json['roundNumber'] as num?)?.toInt() ?? 1,
      phase: MindMatchPhaseX.fromString(json['phase'] as String?),
      questionId: (json['questionId'] ?? '') as String,
      questionPrompt:
          (json['questionPrompt'] ?? '') as String,
      questionCategory:
          (json['questionCategory'] ?? 'everyday') as String,
      lockedCount: (json['lockedCount'] as num?)?.toInt() ?? 0,
      answerGroups: groupsList,
      crowdFavorite: json['crowdFavorite'] as String?,
      perfectMatch: (json['perfectMatch'] as bool?) ?? false,
      pointsAwarded: pointsList,
    );
  }
}

/// The full boardState JSONB from the games row, parsed.
class MindMatchBoardState {
  const MindMatchBoardState({
    required this.playerCount,
    required this.totalRounds,
    required this.answerSeconds,
    required this.categories,
    required this.familyQuestionsEnabled,
    required this.currentRoundNumber,
    required this.rounds,
    required this.players,
    required this.status,
    required this.winnerIndex,
  });

  final int playerCount;
  final int totalRounds;
  final int answerSeconds;
  final List<String> categories;
  final bool familyQuestionsEnabled;
  final int currentRoundNumber;
  final List<MindMatchRound> rounds;
  final List<MindMatchPlayer> players;
  final String status;
  final int winnerIndex;

  MindMatchRound? get currentRound =>
      rounds.isNotEmpty && currentRoundNumber <= rounds.length
          ? rounds[currentRoundNumber - 1]
          : null;

  bool get isFinished => status == 'completed';

  /// The player with the most points (or null if tied).
  MindMatchPlayer? get leader {
    if (players.isEmpty) return null;
    final sorted = List<MindMatchPlayer>.from(players)
      ..sort((a, b) => b.score.compareTo(a.score));
    if (sorted.length >= 2 && sorted[0].score == sorted[1].score) {
      return null; // tie
    }
    return sorted.first;
  }

  /// Total perfect matches across all rounds.
  int get totalPerfectMatches =>
      players.fold<int>(0, (a, p) => a + p.perfectMatches);

  /// The longest match streak across all players.
  int get longestStreak =>
      players.fold<int>(0, (a, p) => p.streak > a ? p.streak : a);

  Map<String, dynamic> toJson() => {
        'playerCount': playerCount,
        'totalRounds': totalRounds,
        'answerSeconds': answerSeconds,
        'categories': categories,
        'familyQuestionsEnabled': familyQuestionsEnabled,
        'currentRound': currentRoundNumber,
        'rounds': rounds.map((r) => r.toJson()).toList(),
        'players': players.map((p) => p.toJson()).toList(),
        'status': status,
        'winner': winnerIndex,
      };

  factory MindMatchBoardState.fromJson(Map<String, dynamic> json) {
    final roundsList = <MindMatchRound>[];
    final rawRounds = json['rounds'];
    if (rawRounds is List) {
      for (final r in rawRounds) {
        if (r is Map) {
          roundsList.add(
              MindMatchRound.fromJson(Map<String, dynamic>.from(r)));
        }
      }
    }
    final playersList = <MindMatchPlayer>[];
    final rawPlayers = json['players'];
    if (rawPlayers is List) {
      for (final p in rawPlayers) {
        if (p is Map) {
          playersList.add(
              MindMatchPlayer.fromJson(Map<String, dynamic>.from(p)));
        }
      }
    }
    final cats = <String>[];
    final rawCats = json['categories'];
    if (rawCats is List) {
      for (final c in rawCats) {
        cats.add(c.toString());
      }
    }
    if (cats.isEmpty) {
      cats.addAll(const ['everyday', 'fun', 'family', 'global']);
    }
    return MindMatchBoardState(
      playerCount: (json['playerCount'] as num?)?.toInt() ?? 2,
      totalRounds: (json['totalRounds'] as num?)?.toInt() ?? 10,
      answerSeconds: (json['answerSeconds'] as num?)?.toInt() ??
          kMindMatchDefaultAnswerSeconds,
      categories: cats,
      familyQuestionsEnabled:
          (json['familyQuestionsEnabled'] as bool?) ?? true,
      currentRoundNumber:
          (json['currentRound'] as num?)?.toInt() ?? 1,
      rounds: roundsList,
      players: playersList,
      status: (json['status'] as String?) ?? 'in_progress',
      winnerIndex: (json['winner'] as num?)?.toInt() ?? -1,
    );
  }
}

/// Normalize an answer for matching: lowercase, trim, collapse spaces.
/// Mirrors the SQL function fn_mindmatch_normalize_answer.
String normalizeAnswer(String answer) {
  final trimmed = answer.trim();
  final collapsed = trimmed.replaceAll(RegExp(r'\s+'), ' ');
  return collapsed.toLowerCase();
}

/// Pure-Dart engine — client-side validation + display helpers.
class MindMatchEngine {
  MindMatchEngine._();

  /// Validate an answer. Returns null if valid, error string otherwise.
  static String? validateAnswer(String answer) {
    final trimmed = answer.trim();
    if (trimmed.isEmpty) return 'Answer cannot be empty';
    if (trimmed.length > kMindMatchMaxAnswerLength) {
      return 'Answer too long (max $kMindMatchMaxAnswerLength chars)';
    }
    return null;
  }

  /// Available categories based on the family-questions-enabled setting.
  static List<MindMatchCategory> availableCategories(
      bool familyQuestionsEnabled) {
    final cats = <MindMatchCategory>[
      MindMatchCategory.everyday,
      MindMatchCategory.fun,
      MindMatchCategory.global,
    ];
    if (familyQuestionsEnabled) {
      cats.add(MindMatchCategory.family);
    }
    return cats;
  }

  /// Compute the player's match accuracy across all resolved rounds.
  /// Accuracy = (rounds where player matched) / (total resolved rounds).
  static double matchAccuracy(
      List<MindMatchRound> rounds, int playerIndex) {
    var matched = 0;
    var total = 0;
    for (final r in rounds) {
      if (r.phase != MindMatchPhase.revealing) continue;
      total++;
      final points = r.pointsAwarded
          .where((p) => p.playerIndex == playerIndex)
          .firstOrNull;
      if (points != null && points.matched) matched++;
    }
    if (total == 0) return 0;
    return matched / total;
  }

  /// Best match — the largest group size across all rounds.
  static int bestMatchSize(List<MindMatchRound> rounds) {
    var best = 0;
    for (final r in rounds) {
      if (r.phase != MindMatchPhase.revealing) continue;
      for (final g in r.answerGroups) {
        if (g.size > best) best = g.size;
      }
    }
    return best;
  }
}

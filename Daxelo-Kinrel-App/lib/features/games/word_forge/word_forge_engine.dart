// lib/features/games/word_forge/word_forge_engine.dart
//
// Word Forge — pure Dart game engine.
//
// Balderdash-style fake-definitions party game. 3–8 players. Each round,
// an obscure real word is shown (e.g. "floccinaucinihilipilification").
// Players secretly write fake definitions. All fake definitions + the
// real definition are shuffled and revealed. Players vote for which
// definition they think is real. Points:
//   • +10 for guessing the real definition
//   • +5 per vote your fake definition receives (fooling others)
//   • +15 bonus if your definition is very close to the real one
// After N rounds, the player with the most points wins.
//
// Architecture reuses the hidden-submission pattern from mind_match +
// secret_heist: the server (Postgres RPCs) is authoritative for state.
// This engine is used client-side to:
//   • Parse boardState JSON from the server
//   • Compute display labels + colors for the UI
//   • Validate definition submissions before sending
//
// Scoring (matches the SQL in fn_wordforge_resolve_votes):
//   • Guess real definition: +10
//   • Each vote your fake def gets: +5 per vote
//   • You cannot vote for your own definition
//   • Close-match bonus: +15 if your definition shares substantial
//     keyword overlap with the real definition (server-side computed)

const int kWordForgeMinPlayers = 3;
const int kWordForgeMaxPlayers = 8;
const int kWordForgeDefaultAnswerSeconds = 60;
const int kWordForgeMaxDefinitionLength = 200;
const int kWordForgePointsCorrectGuess = 10;
const int kWordForgePointsPerFooledVote = 5;
const int kWordForgePointsCloseMatchBonus = 15;

/// Round phase — drives the UI state machine.
enum WordForgePhase {
  writing,   // players write fake definitions
  revealing, // definitions shuffled + shown, players ready to vote
  voting,    // players vote for the definition they think is real
  results,   // round results shown — who wrote what, points awarded
  finished,  // match over
}

extension WordForgePhaseX on WordForgePhase {
  String get wire {
    switch (this) {
      case WordForgePhase.writing:
        return 'writing';
      case WordForgePhase.revealing:
        return 'revealing';
      case WordForgePhase.voting:
        return 'voting';
      case WordForgePhase.results:
        return 'results';
      case WordForgePhase.finished:
        return 'finished';
    }
  }

  static WordForgePhase fromString(String? s) {
    switch (s) {
      case 'revealing':
        return WordForgePhase.revealing;
      case 'voting':
        return WordForgePhase.voting;
      case 'results':
        return WordForgePhase.results;
      case 'finished':
        return WordForgePhase.finished;
      case 'writing':
      default:
        return WordForgePhase.writing;
    }
  }

  String get label {
    switch (this) {
      case WordForgePhase.writing:
        return 'Writing Definitions';
      case WordForgePhase.revealing:
        return 'Revealing';
      case WordForgePhase.voting:
        return 'Voting';
      case WordForgePhase.results:
        return 'Round Results';
      case WordForgePhase.finished:
        return 'Match Complete';
    }
  }
}

/// A player row inside the boardState JSON.
class WordForgePlayer {
  const WordForgePlayer({
    required this.idx,
    required this.userId,
    required this.name,
    required this.score,
    required this.lastRoundPoints,
    required this.foolCount,
    required this.correctGuesses,
  });

  final int idx;
  final String userId;
  final String name;
  final int score;
  final int lastRoundPoints;
  final int foolCount;
  final int correctGuesses;

  WordForgePlayer copyWith({
    int? score,
    int? lastRoundPoints,
    int? foolCount,
    int? correctGuesses,
  }) =>
      WordForgePlayer(
        idx: idx,
        userId: userId,
        name: name,
        score: score ?? this.score,
        lastRoundPoints: lastRoundPoints ?? this.lastRoundPoints,
        foolCount: foolCount ?? this.foolCount,
        correctGuesses: correctGuesses ?? this.correctGuesses,
      );

  Map<String, dynamic> toJson() => {
        'idx': idx,
        'userId': userId,
        'name': name,
        'score': score,
        'lastRoundPoints': lastRoundPoints,
        'foolCount': foolCount,
        'correctGuesses': correctGuesses,
      };

  factory WordForgePlayer.fromJson(Map<String, dynamic> json) =>
      WordForgePlayer(
        idx: (json['idx'] as num?)?.toInt() ?? 0,
        userId: (json['userId'] ?? '') as String,
        name: (json['name'] ?? 'Player') as String,
        score: (json['score'] as num?)?.toInt() ?? 0,
        lastRoundPoints:
            (json['lastRoundPoints'] as num?)?.toInt() ?? 0,
        foolCount: (json['foolCount'] as num?)?.toInt() ?? 0,
        correctGuesses:
            (json['correctGuesses'] as num?)?.toInt() ?? 0,
      );
}

/// A single definition entry (real or fake) shown after reveal.
class WordForgeDefinition {
  const WordForgeDefinition({
    required this.userId,
    required this.userName,
    required this.definition,
    required this.isReal,
    required this.voteCount,
    required this.displayIndex,
  });

  /// The userId of the player who wrote this fake def.
  /// Empty/null for the real definition.
  final String userId;
  final String userName;
  final String definition;
  final bool isReal;
  final int voteCount;

  /// Position in the shuffled reveal list (1-based).
  final int displayIndex;

  /// True if this is the real definition (server-supplied).
  bool get isRealDefinition => isReal;

  /// True if this is a fake player definition.
  bool get isFakeDefinition => !isReal;

  /// Points awarded to the author of this fake definition.
  /// +5 per vote received. (Real definition awards no author points.)
  int get authorPoints => isReal ? 0 : voteCount * kWordForgePointsPerFooledVote;

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'userName': userName,
        'definition': definition,
        'isReal': isReal,
        'voteCount': voteCount,
        'displayIndex': displayIndex,
      };

  factory WordForgeDefinition.fromJson(Map<String, dynamic> json) =>
      WordForgeDefinition(
        userId: (json['userId'] ?? '') as String,
        userName: (json['userName'] ?? 'Dictionary') as String,
        definition: (json['definition'] ?? '') as String,
        isReal: (json['isReal'] as bool?) ?? false,
        voteCount: (json['voteCount'] as num?)?.toInt() ?? 0,
        displayIndex: (json['displayIndex'] as num?)?.toInt() ?? 0,
      );
}

/// Points awarded to a single player for a round.
class WordForgePointsAwarded {
  const WordForgePointsAwarded({
    required this.playerIndex,
    required this.points,
    required this.guessedReal,
    required this.foolCount,
    required this.closeBonus,
    required this.votedForUserId,
    required this.votedForReal,
  });

  final int playerIndex;
  final int points;
  final bool guessedReal;
  final int foolCount;
  final bool closeBonus;
  final String votedForUserId;
  final bool votedForReal;

  Map<String, dynamic> toJson() => {
        'playerIndex': playerIndex,
        'points': points,
        'guessedReal': guessedReal,
        'foolCount': foolCount,
        'closeBonus': closeBonus,
        'votedForUserId': votedForUserId,
        'votedForReal': votedForReal,
      };

  factory WordForgePointsAwarded.fromJson(Map<String, dynamic> json) =>
      WordForgePointsAwarded(
        playerIndex:
            (json['playerIndex'] as num?)?.toInt() ?? 0,
        points: (json['points'] as num?)?.toInt() ?? 0,
        guessedReal: (json['guessedReal'] as bool?) ?? false,
        foolCount: (json['foolCount'] as num?)?.toInt() ?? 0,
        closeBonus: (json['closeBonus'] as bool?) ?? false,
        votedForUserId: (json['votedForUserId'] ?? '') as String,
        votedForReal: (json['votedForReal'] as bool?) ?? false,
      );
}

/// One round's snapshot.
class WordForgeRound {
  const WordForgeRound({
    required this.roundNumber,
    required this.phase,
    required this.word,
    required this.realDefinition,
    required this.category,
    required this.definitions,
    required this.pointsAwarded,
    required this.voteCount,
    required this.submittedCount,
  });

  final int roundNumber;
  final WordForgePhase phase;
  final String word;
  final String realDefinition;
  final String category;
  final List<WordForgeDefinition> definitions;
  final List<WordForgePointsAwarded> pointsAwarded;
  final int voteCount;
  final int submittedCount;

  Map<String, dynamic> toJson() => {
        'roundNumber': roundNumber,
        'phase': phase.wire,
        'word': word,
        'realDefinition': realDefinition,
        'category': category,
        'definitions': definitions.map((d) => d.toJson()).toList(),
        'pointsAwarded': pointsAwarded.map((p) => p.toJson()).toList(),
        'voteCount': voteCount,
        'submittedCount': submittedCount,
      };

  factory WordForgeRound.fromJson(Map<String, dynamic> json) {
    final defsList = <WordForgeDefinition>[];
    final rawDefs = json['definitions'];
    if (rawDefs is List) {
      for (final d in rawDefs) {
        if (d is Map) {
          defsList.add(WordForgeDefinition.fromJson(
              Map<String, dynamic>.from(d)));
        }
      }
    }
    final pointsList = <WordForgePointsAwarded>[];
    final rawPoints = json['pointsAwarded'];
    if (rawPoints is List) {
      for (final p in rawPoints) {
        if (p is Map) {
          pointsList.add(WordForgePointsAwarded.fromJson(
              Map<String, dynamic>.from(p)));
        }
      }
    }
    return WordForgeRound(
      roundNumber: (json['roundNumber'] as num?)?.toInt() ?? 1,
      phase: WordForgePhaseX.fromString(json['phase'] as String?),
      word: (json['word'] ?? '') as String,
      realDefinition:
          (json['realDefinition'] ?? '') as String,
      category: (json['category'] ?? 'obscure') as String,
      definitions: defsList,
      pointsAwarded: pointsList,
      voteCount: (json['voteCount'] as num?)?.toInt() ?? 0,
      submittedCount: (json['submittedCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// The full boardState JSONB from the games row, parsed.
class WordForgeBoardState {
  const WordForgeBoardState({
    required this.playerCount,
    required this.totalRounds,
    required this.answerSeconds,
    required this.currentRoundNumber,
    required this.rounds,
    required this.players,
    required this.status,
    required this.winnerIndex,
  });

  final int playerCount;
  final int totalRounds;
  final int answerSeconds;
  final int currentRoundNumber;
  final List<WordForgeRound> rounds;
  final List<WordForgePlayer> players;
  final String status;
  final int winnerIndex;

  WordForgeRound? get currentRound =>
      rounds.isNotEmpty && currentRoundNumber <= rounds.length
          ? rounds[currentRoundNumber - 1]
          : null;

  bool get isFinished => status == 'completed';

  /// The player with the most points (or null if tied).
  WordForgePlayer? get leader {
    if (players.isEmpty) return null;
    final sorted = List<WordForgePlayer>.from(players)
      ..sort((a, b) => b.score.compareTo(a.score));
    if (sorted.length >= 2 && sorted[0].score == sorted[1].score) {
      return null; // tie
    }
    return sorted.first;
  }

  /// Total fooled votes across all rounds.
  int get totalFoolCount =>
      players.fold<int>(0, (a, p) => a + p.foolCount);

  /// Total correct guesses across all rounds.
  int get totalCorrectGuesses =>
      players.fold<int>(0, (a, p) => a + p.correctGuesses);

  Map<String, dynamic> toJson() => {
        'playerCount': playerCount,
        'totalRounds': totalRounds,
        'answerSeconds': answerSeconds,
        'currentRound': currentRoundNumber,
        'rounds': rounds.map((r) => r.toJson()).toList(),
        'players': players.map((p) => p.toJson()).toList(),
        'status': status,
        'winner': winnerIndex,
      };

  factory WordForgeBoardState.fromJson(Map<String, dynamic> json) {
    final roundsList = <WordForgeRound>[];
    final rawRounds = json['rounds'];
    if (rawRounds is List) {
      for (final r in rawRounds) {
        if (r is Map) {
          roundsList.add(
              WordForgeRound.fromJson(Map<String, dynamic>.from(r)));
        }
      }
    }
    final playersList = <WordForgePlayer>[];
    final rawPlayers = json['players'];
    if (rawPlayers is List) {
      for (final p in rawPlayers) {
        if (p is Map) {
          playersList.add(
              WordForgePlayer.fromJson(Map<String, dynamic>.from(p)));
        }
      }
    }
    return WordForgeBoardState(
      playerCount: (json['playerCount'] as num?)?.toInt() ?? 3,
      totalRounds: (json['totalRounds'] as num?)?.toInt() ?? 10,
      answerSeconds: (json['answerSeconds'] as num?)?.toInt() ??
          kWordForgeDefaultAnswerSeconds,
      currentRoundNumber:
          (json['currentRound'] as num?)?.toInt() ?? 1,
      rounds: roundsList,
      players: playersList,
      status: (json['status'] as String?) ?? 'in_progress',
      winnerIndex: (json['winner'] as num?)?.toInt() ?? -1,
    );
  }
}

/// Pure-Dart engine — client-side validation + display helpers.
class WordForgeEngine {
  WordForgeEngine._();

  /// Validate a fake definition. Returns null if valid, error string otherwise.
  static String? validateDefinition(String definition) {
    final trimmed = definition.trim();
    if (trimmed.isEmpty) return 'Definition cannot be empty';
    if (trimmed.length < 3) {
      return 'Definition too short (min 3 chars)';
    }
    if (trimmed.length > kWordForgeMaxDefinitionLength) {
      return 'Definition too long (max $kWordForgeMaxDefinitionLength chars)';
    }
    return null;
  }

  /// Compute the player's guess accuracy across all resolved rounds.
  /// Accuracy = (rounds where player guessed real) / (total voted rounds).
  static double guessAccuracy(
      List<WordForgeRound> rounds, int playerIndex) {
    var correct = 0;
    var total = 0;
    for (final r in rounds) {
      if (r.phase != WordForgePhase.results) continue;
      total++;
      final points = r.pointsAwarded
          .where((p) => p.playerIndex == playerIndex)
          .firstOrNull;
      if (points != null && points.guessedReal) correct++;
    }
    if (total == 0) return 0;
    return correct / total;
  }

  /// Best fool count — most votes a single fake definition got in one round.
  static int bestFoolCount(List<WordForgeRound> rounds) {
    var best = 0;
    for (final r in rounds) {
      if (r.phase != WordForgePhase.results) continue;
      for (final d in r.definitions) {
        if (!d.isReal && d.voteCount > best) best = d.voteCount;
      }
    }
    return best;
  }

  /// Total votes the player's fake definitions have received across all
  /// resolved rounds.
  static int totalFoolVotes(
      List<WordForgeRound> rounds, String userId) {
    var total = 0;
    for (final r in rounds) {
      if (r.phase != WordForgePhase.results) continue;
      for (final d in r.definitions) {
        if (d.userId == userId && !d.isReal) total += d.voteCount;
      }
    }
    return total;
  }

  /// Find a definition by its display index in a round.
  static WordForgeDefinition? definitionByIndex(
      WordForgeRound round, int displayIndex) {
    for (final d in round.definitions) {
      if (d.displayIndex == displayIndex) return d;
    }
    return null;
  }
}

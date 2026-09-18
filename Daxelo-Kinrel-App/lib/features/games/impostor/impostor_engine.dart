// lib/features/games/impostor/impostor_engine.dart
//
// Who's the Impostor? — pure Dart game engine.
//
// Social deduction game (Undercover/Spyfall-style). 3–10 players. Each
// round: one player is secretly the Impostor (doesn't know the word),
// the rest are Crew (know the word). Everyone gives a one-word clue,
// then votes for who they think is the Impostor. Crew wins if they
// vote out the Impostor; Impostor wins if they avoid detection.
//
// Multi-round matches (3/5/10 rounds) with cumulative scoring.
//
// This engine is completely separated from UI. It exposes:
//   • createGame()           — initialize state for N players, M rounds
//   • assignRoles()          — pick impostor + word for the round
//   • generateWord()         — pick a random word from the pack
//   • submitClue()           — a player submits their clue
//   • startVoting()          — transition from clue phase to vote phase
//   • submitVote()           — a player votes for a suspect
//   • calculateRoundResult() — tally votes, determine round winner
//   • nextRound()            — advance to the next round
//   • finishMatch()          — determine overall winner
//
// The engine is DETERMINISTIC — every client independently derives the
// same game state from the same sequence of moves. Only (playerId,
// action, payload) tuples are synced.

import 'dart:math';

// ─────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────

const int kImpostorMinPlayers = 3;
const int kImpostorMaxPlayers = 10;
const int kImpostorDefaultClueSeconds = 30;
const int kImpostorDefaultVoteSeconds = 30;

enum ImpostorPhase {
  roleReveal,  // players see their role (impostor or crew + word)
  clue,        // each player submits a one-word clue
  voting,      // each player votes for who they think is impostor
  result,      // round result revealed
  finished,    // match over
}

extension ImpostorPhaseX on ImpostorPhase {
  String get wire {
    switch (this) {
      case ImpostorPhase.roleReveal: return 'role_reveal';
      case ImpostorPhase.clue: return 'clue';
      case ImpostorPhase.voting: return 'voting';
      case ImpostorPhase.result: return 'result';
      case ImpostorPhase.finished: return 'finished';
    }
  }

  static ImpostorPhase fromString(String? s) {
    switch (s) {
      case 'clue': return ImpostorPhase.clue;
      case 'voting': return ImpostorPhase.voting;
      case 'result': return ImpostorPhase.result;
      case 'finished': return ImpostorPhase.finished;
      default: return ImpostorPhase.roleReveal;
    }
  }
}

enum ImpostorRole { crew, impostor }

extension ImpostorRoleX on ImpostorRole {
  String get wire => this == ImpostorRole.impostor ? 'impostor' : 'crew';
  static ImpostorRole fromString(String? s) =>
      s == 'impostor' ? ImpostorRole.impostor : ImpostorRole.crew;
}

enum ImpostorRoundWinner { crew, impostor, tie }

// ─────────────────────────────────────────────────────────────────────────
// Word database — categorized word packs
// ─────────────────────────────────────────────────────────────────────────

class ImpostorWordPack {
  const ImpostorWordPack({
    required this.id,
    required this.name,
    required this.emoji,
    required this.words,
  });

  final String id;
  final String name;
  final String emoji;
  final List<String> words;

  static const ImpostorWordPack food = ImpostorWordPack(
    id: 'food',
    name: 'Food',
    emoji: '🍕',
    words: [
      'Pizza', 'Biryani', 'Ice Cream', 'Burger', 'Dosa', 'Pasta',
      'Samosa', 'Cake', 'Noodles', 'Curry', 'Sandwich', 'Soup',
      'Pancake', 'Taco', 'Donut', 'Salad', 'Steak', 'Sushi',
    ],
  );

  static const ImpostorWordPack animals = ImpostorWordPack(
    id: 'animals',
    name: 'Animals',
    emoji: '🐘',
    words: [
      'Elephant', 'Tiger', 'Dolphin', 'Eagle', 'Snake', 'Rabbit',
      'Lion', 'Monkey', 'Penguin', 'Spider', 'Whale', 'Horse',
      'Giraffe', 'Bear', 'Owl', 'Fox', 'Wolf', 'Parrot',
    ],
  );

  static const ImpostorWordPack places = ImpostorWordPack(
    id: 'places',
    name: 'Places',
    emoji: '🏖️',
    words: [
      'Beach', 'Library', 'Airport', 'Temple', 'School', 'Park',
      'Hospital', 'Museum', 'Restaurant', 'Stadium', 'Cinema', 'Mall',
      'Zoo', 'Farm', 'Mountain', 'Island', 'Forest', 'Castle',
    ],
  );

  static const ImpostorWordPack activities = ImpostorWordPack(
    id: 'activities',
    name: 'Activities',
    emoji: '⚽',
    words: [
      'Cricket', 'Dancing', 'Cooking', 'Painting', 'Swimming', 'Singing',
      'Reading', 'Gardening', 'Cycling', 'Fishing', 'Hiking', 'Yoga',
      'Chess', 'Football', 'Drawing', 'Photography', 'Knitting', 'Camping',
    ],
  );

  static const ImpostorWordPack family = ImpostorWordPack(
    id: 'family',
    name: 'Family Life',
    emoji: '👨‍👩‍👧‍👦',
    words: [
      'Birthday', 'Wedding', 'Picnic', 'Vacation', 'Dinner', 'Movie Night',
      'Festival', 'Reunion', 'Breakfast', 'Homework', 'Shopping', 'Cleaning',
      'Game Night', 'Diwali', 'Holi', 'Christmas', 'Eid', 'Lunch',
    ],
  );

  static const List<ImpostorWordPack> all = [
    food, animals, places, activities, family,
  ];

  static ImpostorWordPack byId(String? id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return food;
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Round — one round of the game
// ─────────────────────────────────────────────────────────────────────────

class ImpostorClue {
  const ImpostorClue({
    required this.playerIndex,
    required this.text,
  });
  final int playerIndex;
  final String text;

  Map<String, dynamic> toJson() => {'player': playerIndex, 'text': text};
  factory ImpostorClue.fromJson(Map<String, dynamic> json) => ImpostorClue(
        playerIndex: (json['player'] as num?)?.toInt() ?? 0,
        text: (json['text'] as String?) ?? '',
      );
}

class ImpostorVote {
  const ImpostorVote({
    required this.voterIndex,
    required this.targetIndex,
  });
  final int voterIndex;
  final int targetIndex;

  Map<String, dynamic> toJson() =>
      {'voter': voterIndex, 'target': targetIndex};
  factory ImpostorVote.fromJson(Map<String, dynamic> json) => ImpostorVote(
        voterIndex: (json['voter'] as num?)?.toInt() ?? 0,
        targetIndex: (json['target'] as num?)?.toInt() ?? 0,
      );
}

class ImpostorRound {
  ImpostorRound({
    required this.roundNumber,
    required this.word,
    required this.impostorIndex,
    required this.wordPackId,
  });

  final int roundNumber;
  final String word;
  final int impostorIndex;
  final String wordPackId;

  ImpostorPhase phase = ImpostorPhase.roleReveal;
  int currentCluePlayerIndex = 0;
  List<ImpostorClue> clues = [];
  List<ImpostorVote> votes = [];
  ImpostorRoundWinner? winner;

  /// Map of playerIndex → role for this round.
  Map<int, ImpostorRole> get roles {
    final m = <int, ImpostorRole>{};
    // We don't store all roles — only the impostor is special.
    // The crew role is the default for everyone else.
    return m;
  }

  Map<String, dynamic> toJson() => {
        'roundNumber': roundNumber,
        'word': word,
        'impostorIndex': impostorIndex,
        'wordPackId': wordPackId,
        'phase': phase.wire,
        'currentCluePlayer': currentCluePlayerIndex,
        'clues': clues.map((c) => c.toJson()).toList(),
        'votes': votes.map((v) => v.toJson()).toList(),
        'winner': winner?.name,
      };

  factory ImpostorRound.fromJson(Map<String, dynamic> json) {
    final round = ImpostorRound(
      roundNumber: (json['roundNumber'] as num?)?.toInt() ?? 1,
      word: (json['word'] as String?) ?? '',
      impostorIndex: (json['impostorIndex'] as num?)?.toInt() ?? 0,
      wordPackId: (json['wordPackId'] as String?) ?? 'food',
    );
    round.phase = ImpostorPhaseX.fromString(json['phase'] as String?);
    round.currentCluePlayerIndex =
        (json['currentCluePlayer'] as num?)?.toInt() ?? 0;
    final rawClues = json['clues'];
    if (rawClues is List) {
      round.clues = rawClues
          .whereType<Map>()
          .map((e) => ImpostorClue.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    final rawVotes = json['votes'];
    if (rawVotes is List) {
      round.votes = rawVotes
          .whereType<Map>()
          .map((e) => ImpostorVote.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    final rawWinner = json['winner'] as String?;
    if (rawWinner == 'crew') round.winner = ImpostorRoundWinner.crew;
    if (rawWinner == 'impostor') round.winner = ImpostorRoundWinner.impostor;
    if (rawWinner == 'tie') round.winner = ImpostorRoundWinner.tie;
    return round;
  }

  ImpostorRound copy() {
    final r = ImpostorRound(
      roundNumber: roundNumber,
      word: word,
      impostorIndex: impostorIndex,
      wordPackId: wordPackId,
    );
    r.phase = phase;
    r.currentCluePlayerIndex = currentCluePlayerIndex;
    r.clues = List<ImpostorClue>.from(clues);
    r.votes = List<ImpostorVote>.from(votes);
    r.winner = winner;
    return r;
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Game state — the full serializable state of a match
// ─────────────────────────────────────────────────────────────────────────

class ImpostorGameState {
  ImpostorGameState({
    required this.playerCount,
    required this.totalRounds,
    required this.currentRoundNumber,
    required this.rounds,
    required this.scores,
    required this.status,
    this.wordPackId = 'food',
    this.clueSeconds = kImpostorDefaultClueSeconds,
    this.voteSeconds = kImpostorDefaultVoteSeconds,
  });

  int playerCount;
  int totalRounds;
  int currentRoundNumber;
  List<ImpostorRound> rounds;
  Map<int, int> scores; // playerIndex → cumulative score
  String status; // 'in_progress' | 'completed'
  String wordPackId;
  int clueSeconds;
  int voteSeconds;

  ImpostorRound? get currentRound =>
      rounds.isNotEmpty && currentRoundNumber <= rounds.length
          ? rounds[currentRoundNumber - 1]
          : null;

  bool get isFinished => status == 'completed';

  Map<String, dynamic> toJson() => {
        'playerCount': playerCount,
        'totalRounds': totalRounds,
        'currentRound': currentRoundNumber,
        'rounds': rounds.map((r) => r.toJson()).toList(),
        'scores': scores.map((k, v) => MapEntry(k.toString(), v)),
        'status': status,
        'wordPackId': wordPackId,
        'clueSeconds': clueSeconds,
        'voteSeconds': voteSeconds,
      };

  factory ImpostorGameState.fromJson(Map<String, dynamic> json) {
    final roundsList = <ImpostorRound>[];
    final rawRounds = json['rounds'];
    if (rawRounds is List) {
      for (final r in rawRounds) {
        if (r is Map) {
          roundsList.add(
              ImpostorRound.fromJson(Map<String, dynamic>.from(r)));
        }
      }
    }

    final scores = <int, int>{};
    final rawScores = json['scores'];
    if (rawScores is Map) {
      rawScores.forEach((k, v) {
        scores[int.parse(k.toString())] = (v as num).toInt();
      });
    }

    return ImpostorGameState(
      playerCount: (json['playerCount'] as num?)?.toInt() ?? 3,
      totalRounds: (json['totalRounds'] as num?)?.toInt() ?? 3,
      currentRoundNumber: (json['currentRound'] as num?)?.toInt() ?? 1,
      rounds: roundsList,
      scores: scores,
      status: (json['status'] as String?) ?? 'in_progress',
      wordPackId: (json['wordPackId'] as String?) ?? 'food',
      clueSeconds: (json['clueSeconds'] as num?)?.toInt() ??
          kImpostorDefaultClueSeconds,
      voteSeconds: (json['voteSeconds'] as num?)?.toInt() ??
          kImpostorDefaultVoteSeconds,
    );
  }

  ImpostorGameState copy() {
    final s = ImpostorGameState(
      playerCount: playerCount,
      totalRounds: totalRounds,
      currentRoundNumber: currentRoundNumber,
      rounds: rounds.map((r) => r.copy()).toList(),
      scores: Map<int, int>.from(scores),
      status: status,
      wordPackId: wordPackId,
      clueSeconds: clueSeconds,
      voteSeconds: voteSeconds,
    );
    return s;
  }
}

// ─────────────────────────────────────────────────────────────────────────
// The engine — pure functions on ImpostorGameState
// ─────────────────────────────────────────────────────────────────────────

class ImpostorEngine {
  ImpostorEngine._();

  /// Create a fresh game state for `playerCount` players, `totalRounds` rounds.
  static ImpostorGameState createGame({
    required int playerCount,
    required int totalRounds,
    required String wordPackId,
    int clueSeconds = kImpostorDefaultClueSeconds,
    int voteSeconds = kImpostorDefaultVoteSeconds,
    Random? rng,
  }) {
    assert(playerCount >= kImpostorMinPlayers &&
        playerCount <= kImpostorMaxPlayers);
    assert(totalRounds == 3 || totalRounds == 5 || totalRounds == 10);

    final state = ImpostorGameState(
      playerCount: playerCount,
      totalRounds: totalRounds,
      currentRoundNumber: 1,
      rounds: [],
      scores: {for (var i = 0; i < playerCount; i++) i: 0},
      status: 'in_progress',
      wordPackId: wordPackId,
      clueSeconds: clueSeconds,
      voteSeconds: voteSeconds,
    );

    // Assign roles for the first round
    _assignRolesForRound(state, rng ?? Random());

    return state;
  }

  /// Assign the impostor + word for a new round.
  static void _assignRolesForRound(ImpostorGameState state, Random rng) {
    final pack = ImpostorWordPack.byId(state.wordPackId);
    final word = pack.words[rng.nextInt(pack.words.length)];
    final impostorIndex = rng.nextInt(state.playerCount);

    state.rounds.add(ImpostorRound(
      roundNumber: state.currentRoundNumber,
      word: word,
      impostorIndex: impostorIndex,
      wordPackId: state.wordPackId,
    ));
  }

  /// Generate a random word from the pack (for testing/preview).
  static String generateWord(String wordPackId, {Random? rng}) {
    final pack = ImpostorWordPack.byId(wordPackId);
    final r = rng ?? Random();
    return pack.words[r.nextInt(pack.words.length)];
  }

  /// A player submits a clue. Returns null if valid, error string if not.
  static String? submitClue(
      ImpostorGameState state, int playerIndex, String clue) {
    final round = state.currentRound;
    if (round == null) return 'No active round';
    if (round.phase != ImpostorPhase.clue) return 'Not in clue phase';
    if (playerIndex < 0 || playerIndex >= state.playerCount) {
      return 'Invalid player';
    }
    if (round.clues.any((c) => c.playerIndex == playerIndex)) {
      return 'Already submitted a clue';
    }
    if (playerIndex != round.currentCluePlayerIndex) {
      return 'Not your turn to clue';
    }
    final trimmed = clue.trim();
    if (trimmed.isEmpty) return 'Clue cannot be empty';
    if (trimmed.length > 50) return 'Clue too long (max 50 chars)';
    if (trimmed.toLowerCase() == round.word.toLowerCase()) {
      return 'Can\'t use the exact word!';
    }
    if (round.clues.any((c) => c.text.toLowerCase() == trimmed.toLowerCase())) {
      return 'Someone already used that clue';
    }

    round.clues.add(ImpostorClue(playerIndex: playerIndex, text: trimmed));

    // Advance to next player or transition to voting
    if (round.clues.length >= state.playerCount) {
      round.phase = ImpostorPhase.voting;
    } else {
      round.currentCluePlayerIndex =
          (round.currentCluePlayerIndex + 1) % state.playerCount;
    }
    return null; // success
  }

  /// Transition from clue phase to voting (e.g. on timer expiry).
  static ImpostorGameState startVoting(ImpostorGameState state) {
    final round = state.currentRound;
    if (round == null || round.phase != ImpostorPhase.clue) return state;
    final next = state.copy();
    next.currentRound!.phase = ImpostorPhase.voting;
    return next;
  }

  /// A player submits a vote. Returns null if valid, error string if not.
  static String? submitVote(
      ImpostorGameState state, int voterIndex, int targetIndex) {
    final round = state.currentRound;
    if (round == null) return 'No active round';
    if (round.phase != ImpostorPhase.voting) return 'Not in voting phase';
    if (voterIndex < 0 || voterIndex >= state.playerCount) {
      return 'Invalid voter';
    }
    if (targetIndex < 0 || targetIndex >= state.playerCount) {
      return 'Invalid target';
    }
    if (voterIndex == targetIndex) return 'Can\'t vote for yourself';
    if (round.votes.any((v) => v.voterIndex == voterIndex)) {
      return 'Already voted';
    }

    round.votes.add(ImpostorVote(voterIndex: voterIndex, targetIndex: targetIndex));
    return null; // success
  }

  /// Calculate the round result after all votes are in (or timer expires).
  static ImpostorGameState calculateRoundResult(ImpostorGameState state) {
    final round = state.currentRound;
    if (round == null || round.phase != ImpostorPhase.voting) return state;

    final next = state.copy();
    final r = next.currentRound!;

    // Tally votes
    final voteCounts = <int, int>{};
    for (final vote in r.votes) {
      voteCounts[vote.targetIndex] = (voteCounts[vote.targetIndex] ?? 0) + 1;
    }

    // Find the most-voted player
    int maxVotes = 0;
    int? mostVoted;
    bool isTie = false;
    for (final entry in voteCounts.entries) {
      if (entry.value > maxVotes) {
        maxVotes = entry.value;
        mostVoted = entry.key;
        isTie = false;
      } else if (entry.value == maxVotes) {
        isTie = true;
      }
    }

    if (isTie || mostVoted == null) {
      r.winner = ImpostorRoundWinner.tie;
      // On tie: impostor wins (they avoided detection)
      state.scores[r.impostorIndex] =
          (state.scores[r.impostorIndex] ?? 0) + 2;
    } else if (mostVoted == r.impostorIndex) {
      r.winner = ImpostorRoundWinner.crew;
      // Crew wins: each crew member gets 1 point
      for (var i = 0; i < state.playerCount; i++) {
        if (i != r.impostorIndex) {
          state.scores[i] = (state.scores[i] ?? 0) + 1;
        }
      }
    } else {
      r.winner = ImpostorRoundWinner.impostor;
      // Impostor wins: impostor gets 2 points
      state.scores[r.impostorIndex] =
          (state.scores[r.impostorIndex] ?? 0) + 2;
    }

    r.phase = ImpostorPhase.result;
    next.scores = state.scores;
    return next;
  }

  /// Advance to the next round (or finish the match).
  static ImpostorGameState nextRound(ImpostorGameState state, {Random? rng}) {
    final round = state.currentRound;
    if (round == null || round.phase != ImpostorPhase.result) return state;

    if (state.currentRoundNumber >= state.totalRounds) {
      return finishMatch(state);
    }

    final next = state.copy();
    next.currentRoundNumber++;
    _assignRolesForRound(next, rng ?? Random());
    return next;
  }

  /// Finish the match — determine overall winner.
  static ImpostorGameState finishMatch(ImpostorGameState state) {
    final next = state.copy();
    next.status = 'completed';
    if (next.currentRound != null) {
      next.currentRound!.phase = ImpostorPhase.finished;
    }
    return next;
  }

  /// Get the winner's player index (highest score), or -1 on tie.
  static int getOverallWinner(ImpostorGameState state) {
    if (!state.isFinished) return -1;
    int maxScore = -1;
    int winner = -1;
    bool isTie = false;
    for (final entry in state.scores.entries) {
      if (entry.value > maxScore) {
        maxScore = entry.value;
        winner = entry.key;
        isTie = false;
      } else if (entry.value == maxScore) {
        isTie = true;
      }
    }
    return isTie ? -1 : winner;
  }

  /// Get the role for a player in the current round.
  static ImpostorRole getRoleForPlayer(
      ImpostorGameState state, int playerIndex) {
    final round = state.currentRound;
    if (round == null) return ImpostorRole.crew;
    return playerIndex == round.impostorIndex
        ? ImpostorRole.impostor
        : ImpostorRole.crew;
  }
}

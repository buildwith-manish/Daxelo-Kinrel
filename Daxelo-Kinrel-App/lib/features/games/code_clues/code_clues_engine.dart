// lib/features/games/code_clues/code_clues_engine.dart
//
// Code Clues — pure Dart game engine.
//
// Codenames-style word-association party game. 4–8 players in 2 teams.
// Each team has a Spymaster who gives one-word clues + a number; field
// agents guess words on a 5x5 grid. 9 Team-1 words, 8 Team-2 words,
// 7 neutral, 1 assassin. First team to find all their words wins.
// Hitting the assassin = instant loss.
//
// Architecture (mirrors mind_match + secret_heist): the server
// (Postgres RPCs fn_codeclues_*) is authoritative for state. This
// engine is used client-side to:
//   • Parse boardState JSON from the server
//   • Compute display labels + colors for the UI
//   • Validate clue submissions before sending
//   • Determine what each viewer is allowed to see (spymaster vs field
//     agent vs spectator)

const int kCodeCluesMinPlayers = 4;
const int kCodeCluesMaxPlayers = 8;
const int kCodeCluesDefaultClueSeconds = 60;
const int kCodeCluesDefaultGuessSeconds = 90;
const int kCodeCluesMaxClueLength = 24;
const int kCodeCluesMaxClueNumber = 9;
const int kCodeCluesGridSize = 25;
const int kCodeCluesTeam1Total = 9;
const int kCodeCluesTeam2Total = 8;

/// Assignment codes used in boardState.assignments[25].
///
///  1 → Team 1 word (red)
///  2 → Team 2 word (blue)
///  0 → Neutral (bystander)
/// -1 → Assassin
class CodeCluesAssignment {
  static const int team1 = 1;
  static const int team2 = 2;
  static const int neutral = 0;
  static const int assassin = -1;
}

/// Round phase — drives the UI state machine.
enum CodeCluesPhase {
  clueing, // spymaster of current team is composing their clue
  guessing, // field agents of current team are guessing words
  finished, // match over
}

extension CodeCluesPhaseX on CodeCluesPhase {
  String get wire {
    switch (this) {
      case CodeCluesPhase.clueing:
        return 'clueing';
      case CodeCluesPhase.guessing:
        return 'guessing';
      case CodeCluesPhase.finished:
        return 'finished';
    }
  }

  static CodeCluesPhase fromString(String? s) {
    switch (s) {
      case 'guessing':
        return CodeCluesPhase.guessing;
      case 'finished':
        return CodeCluesPhase.finished;
      case 'clueing':
      default:
        return CodeCluesPhase.clueing;
    }
  }
}

/// One row in the boardState.players[] array (post-start snapshot).
class CodeCluesPlayer {
  const CodeCluesPlayer({
    required this.idx,
    required this.userId,
    required this.name,
    required this.team,
    required this.isSpymaster,
    required this.score,
  });

  final int idx;
  final String userId;
  final String name;

  /// 1 (red) or 2 (blue).
  final int team;
  final bool isSpymaster;
  final int score;

  CodeCluesPlayer copyWith({int? score}) => CodeCluesPlayer(
        idx: idx,
        userId: userId,
        name: name,
        team: team,
        isSpymaster: isSpymaster,
        score: score ?? this.score,
      );

  Map<String, dynamic> toJson() => {
        'idx': idx,
        'userId': userId,
        'name': name,
        'team': team,
        'isSpymaster': isSpymaster,
        'score': score,
      };

  factory CodeCluesPlayer.fromJson(Map<String, dynamic> json) =>
      CodeCluesPlayer(
        idx: (json['idx'] as num?)?.toInt() ?? 0,
        userId: (json['userId'] ?? '') as String,
        name: (json['name'] ?? 'Player') as String,
        team: (json['team'] as num?)?.toInt() ?? 1,
        isSpymaster: (json['isSpymaster'] as bool?) ?? false,
        score: (json['score'] as num?)?.toInt() ?? 0,
      );
}

/// One entry in the boardState.log[] activity stream.
class CodeCluesLogEntry {
  const CodeCluesLogEntry({
    required this.type,
    this.team,
    this.clue,
    this.number,
    this.wordIndex,
    this.word,
    this.assignment,
    this.user,
  });

  /// 'clue' | 'guess' | 'pass' | 'timeout' | 'assassin'
  final String type;
  final int? team;
  final String? clue;
  final int? number;
  final int? wordIndex;
  final String? word;
  final int? assignment;
  final String? user;

  Map<String, dynamic> toJson() => {
        'type': type,
        if (team != null) 'team': team,
        if (clue != null) 'clue': clue,
        if (number != null) 'number': number,
        if (wordIndex != null) 'wordIndex': wordIndex,
        if (word != null) 'word': word,
        if (assignment != null) 'assignment': assignment,
        if (user != null) 'user': user,
      };

  factory CodeCluesLogEntry.fromJson(Map<String, dynamic> json) =>
      CodeCluesLogEntry(
        type: (json['type'] ?? '') as String,
        team: (json['team'] as num?)?.toInt(),
        clue: json['clue'] as String?,
        number: (json['number'] as num?)?.toInt(),
        wordIndex: (json['wordIndex'] as num?)?.toInt(),
        word: json['word'] as String?,
        assignment: (json['assignment'] as num?)?.toInt(),
        user: json['user'] as String?,
      );
}

/// The full boardState JSONB from the games row, parsed.
class CodeCluesBoardState {
  const CodeCluesBoardState({
    required this.playerCount,
    required this.clueSeconds,
    required this.guessSeconds,
    required this.currentTurnTeam,
    required this.phase,
    required this.words,
    required this.assignments,
    required this.revealed,
    required this.clue,
    required this.clueNumber,
    required this.clueGiverId,
    required this.clueGiverName,
    required this.guessesLeft,
    required this.team1Found,
    required this.team2Found,
    required this.team1Total,
    required this.team2Total,
    required this.log,
    required this.players,
    required this.status,
    required this.winnerIndex,
  });

  final int playerCount;
  final int clueSeconds;
  final int guessSeconds;

  /// 1 (red) or 2 (blue) — which team's turn it is.
  final int currentTurnTeam;
  final CodeCluesPhase phase;

  /// 25 word strings (one per grid cell).
  final List<String> words;

  /// 25 assignment codes (see [CodeCluesAssignment]).
  final List<int> assignments;

  /// 25 booleans — whether each cell has been revealed.
  final List<bool> revealed;

  final String? clue;
  final int? clueNumber;
  final String? clueGiverId;
  final String? clueGiverName;
  final int guessesLeft;
  final int team1Found;
  final int team2Found;
  final int team1Total;
  final int team2Total;
  final List<CodeCluesLogEntry> log;
  final List<CodeCluesPlayer> players;
  final String status;
  final int winnerIndex;

  bool get isFinished => phase == CodeCluesPhase.finished ||
      status == 'completed';

  /// Whether the assassin word has been revealed.
  bool get assassinTriggered =>
      log.any((e) => e.type == 'assassin');

  /// Players belonging to the given team.
  List<CodeCluesPlayer> teamOf(int team) =>
      players.where((p) => p.team == team).toList(growable: false);

  /// Spymaster for the given team (or null if none assigned).
  CodeCluesPlayer? spymasterOf(int team) {
    for (final p in players) {
      if (p.team == team && p.isSpymaster) return p;
    }
    return null;
  }

  /// The number of words still hidden for each team.
  int get team1Remaining => team1Total - team1Found;
  int get team2Remaining => team2Total - team2Found;

  /// Display label for a given assignment code.
  static String wordAssignmentLabel(int assignment) {
    switch (assignment) {
      case CodeCluesAssignment.team1:
        return 'Team 1';
      case CodeCluesAssignment.team2:
        return 'Team 2';
      case CodeCluesAssignment.assassin:
        return 'Assassin';
      case CodeCluesAssignment.neutral:
      default:
        return 'Neutral';
    }
  }

  Map<String, dynamic> toJson() => {
        'playerCount': playerCount,
        'clueSeconds': clueSeconds,
        'guessSeconds': guessSeconds,
        'currentTurnTeam': currentTurnTeam,
        'phase': phase.wire,
        'words': words,
        'assignments': assignments,
        'revealed': revealed,
        'clue': clue,
        'clueNumber': clueNumber,
        'clueGiverId': clueGiverId,
        'clueGiverName': clueGiverName,
        'guessesLeft': guessesLeft,
        'team1Found': team1Found,
        'team2Found': team2Found,
        'team1Total': team1Total,
        'team2Total': team2Total,
        'log': log.map((e) => e.toJson()).toList(),
        'players': players.map((p) => p.toJson()).toList(),
        'status': status,
        'winner': winnerIndex,
      };

  factory CodeCluesBoardState.fromJson(Map<String, dynamic> json) {
    List<String> parseWords() {
      final raw = json['words'];
      if (raw is List) {
        return raw.map((e) => e.toString()).toList();
      }
      return List<String>.filled(kCodeCluesGridSize, '');
    }

    List<int> parseAssignments() {
      final raw = json['assignments'];
      if (raw is List) {
        return raw.map((e) => (e as num).toInt()).toList();
      }
      return List<int>.filled(kCodeCluesGridSize, 0);
    }

    List<bool> parseRevealed() {
      final raw = json['revealed'];
      if (raw is List) {
        return raw
            .map((e) => e is bool ? e : (e == true || e == 1 || e == 'true'))
            .toList();
      }
      return List<bool>.filled(kCodeCluesGridSize, false);
    }

    final logList = <CodeCluesLogEntry>[];
    final rawLog = json['log'];
    if (rawLog is List) {
      for (final e in rawLog) {
        if (e is Map) {
          logList.add(
              CodeCluesLogEntry.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }

    final playersList = <CodeCluesPlayer>[];
    final rawPlayers = json['players'];
    if (rawPlayers is List) {
      for (final p in rawPlayers) {
        if (p is Map) {
          playersList
              .add(CodeCluesPlayer.fromJson(Map<String, dynamic>.from(p)));
        }
      }
    }

    return CodeCluesBoardState(
      playerCount: (json['playerCount'] as num?)?.toInt() ??
          kCodeCluesMinPlayers,
      clueSeconds: (json['clueSeconds'] as num?)?.toInt() ??
          kCodeCluesDefaultClueSeconds,
      guessSeconds: (json['guessSeconds'] as num?)?.toInt() ??
          kCodeCluesDefaultGuessSeconds,
      currentTurnTeam: (json['currentTurnTeam'] as num?)?.toInt() ?? 1,
      phase: CodeCluesPhaseX.fromString(json['phase'] as String?),
      words: parseWords(),
      assignments: parseAssignments(),
      revealed: parseRevealed(),
      clue: json['clue'] as String?,
      clueNumber: (json['clueNumber'] as num?)?.toInt(),
      clueGiverId: json['clueGiverId'] as String?,
      clueGiverName: json['clueGiverName'] as String?,
      guessesLeft: (json['guessesLeft'] as num?)?.toInt() ?? 0,
      team1Found: (json['team1Found'] as num?)?.toInt() ?? 0,
      team2Found: (json['team2Found'] as num?)?.toInt() ?? 0,
      team1Total: (json['team1Total'] as num?)?.toInt() ??
          kCodeCluesTeam1Total,
      team2Total: (json['team2Total'] as num?)?.toInt() ??
          kCodeCluesTeam2Total,
      log: logList,
      players: playersList,
      status: (json['status'] as String?) ?? 'in_progress',
      winnerIndex: (json['winner'] as num?)?.toInt() ??
          (json['winnerIndex'] as num?)?.toInt() ??
          -1,
    );
  }
}

/// Human-readable label for a given assignment code (UI helper).
String wordAssignmentLabel(int assignment) =>
    CodeCluesBoardState.wordAssignmentLabel(assignment);

/// Pure-Dart engine — client-side validation + display helpers.
class CodeCluesEngine {
  CodeCluesEngine._();

  /// Validate a clue word. Returns null if valid, error string otherwise.
  /// Mirrors fn_codeclues_give_clue server-side check.
  static String? validateClue(String clue) {
    final trimmed = clue.trim();
    if (trimmed.isEmpty) return 'Clue cannot be empty';
    if (trimmed.length > kCodeCluesMaxClueLength) {
      return 'Clue too long (max $kCodeCluesMaxClueLength chars)';
    }
    // Clue must be a single word (no spaces).
    if (trimmed.contains(RegExp(r'\s'))) {
      return 'Clue must be a single word';
    }
    return null;
  }

  /// Validate a clue number. Returns null if valid, error otherwise.
  static String? validateClueNumber(int number) {
    if (number < 0 || number > kCodeCluesMaxClueNumber) {
      return 'Number must be between 0 and $kCodeCluesMaxClueNumber';
    }
    return null;
  }

  /// True if the given user is the spymaster for the current turn team.
  static bool isClueGiver(CodeCluesBoardState board, String? userId) {
    if (userId == null) return false;
    final spymaster = board.spymasterOf(board.currentTurnTeam);
    return spymaster?.userId == userId;
  }

  /// True if the given user is a field agent on the current turn team.
  static bool isGuesser(CodeCluesBoardState board, String? userId) {
    if (userId == null) return false;
    for (final p in board.players) {
      if (p.userId == userId &&
          p.team == board.currentTurnTeam &&
          !p.isSpymaster) {
        return true;
      }
    }
    return false;
  }

  /// True if the given user is on the current turn team (any role).
  static bool isOnCurrentTeam(CodeCluesBoardState board, String? userId) {
    if (userId == null) return false;
    for (final p in board.players) {
      if (p.userId == userId && p.team == board.currentTurnTeam) return true;
    }
    return false;
  }

  /// Compute a display name for a team number.
  static String teamLabel(int team) {
    switch (team) {
      case 1:
        return 'Team Red';
      case 2:
        return 'Team Blue';
      default:
        return 'Team $team';
    }
  }
}

// lib/features/games/sos/sos_models.dart
//
// SOS Game — data models for 2-player and 4-player team modes.

enum SosMode { twoPlayer, fourPlayerTeams }

enum SosLetter { s, o }

enum SosTeam { s, o }

enum SosGameStatus { lobby, active, finished }

extension SosModeX on SosMode {
  String get label {
    switch (this) {
      case SosMode.twoPlayer:
        return '2 Players';
      case SosMode.fourPlayerTeams:
        return '4 Players (Teams)';
    }
  }

  String get description {
    switch (this) {
      case SosMode.twoPlayer:
        return 'Classic SOS — free letter choice, alternating turns';
      case SosMode.fourPlayerTeams:
        return 'Team S vs Team O — fixed letters, rotating turns';
    }
  }

  int get minPlayers {
    switch (this) {
      case SosMode.twoPlayer:
        return 2;
      case SosMode.fourPlayerTeams:
        return 4;
    }
  }

  int get maxPlayers {
    switch (this) {
      case SosMode.twoPlayer:
        return 2;
      case SosMode.fourPlayerTeams:
        return 4;
    }
  }

  String get name {
    switch (this) {
      case SosMode.twoPlayer:
        return 'two_player';
      case SosMode.fourPlayerTeams:
        return 'four_player_teams';
    }
  }

  static SosMode fromString(String? s) {
    return s == 'four_player_teams'
        ? SosMode.fourPlayerTeams
        : SosMode.twoPlayer;
  }
}

extension SosLetterX on SosLetter {
  String get char {
    switch (this) {
      case SosLetter.s:
        return 'S';
      case SosLetter.o:
        return 'O';
    }
  }

  static SosLetter fromString(String? s) {
    return s == 'O' ? SosLetter.o : SosLetter.s;
  }
}

extension SosTeamX on SosTeam {
  String get name {
    switch (this) {
      case SosTeam.s:
        return 'S';
      case SosTeam.o:
        return 'O';
    }
  }

  String get label {
    switch (this) {
      case SosTeam.s:
        return 'Team S';
      case SosTeam.o:
        return 'Team O';
    }
  }

  /// Color used for team placements on the grid.
  int get colorValue {
    switch (this) {
      case SosTeam.s:
        return 0xFF3B82F6; // blue
      case SosTeam.o:
        return 0xFFEC4899; // pink
    }
  }

  static SosTeam? fromString(String? s) {
    if (s == null) return null;
    return s == 'O' ? SosTeam.o : SosTeam.s;
  }
}

class SosGame {
  const SosGame({
    required this.id,
    required this.familyId,
    required this.hostUserId,
    required this.hostUserName,
    required this.mode,
    required this.gridSize,
    required this.status,
    required this.currentTurnOrder,
    this.winnerTeam,
    this.winnerUserId,
    this.startedAt,
    this.finishedAt,
    required this.createdAt,
  });

  final String id;
  final String familyId;
  final String hostUserId;
  final String hostUserName;
  final SosMode mode;
  final int gridSize;
  final SosGameStatus status;
  final int currentTurnOrder;
  final SosTeam? winnerTeam;
  final String? winnerUserId;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final DateTime createdAt;

  factory SosGame.fromJson(Map<String, dynamic> json) => SosGame(
    id: json['id'] ?? '',
    familyId: json['familyId'] ?? '',
    hostUserId: json['hostUserId'] ?? '',
    hostUserName: json['hostUserName'] ?? 'Host',
    mode: SosModeX.fromString(json['mode']),
    gridSize: json['gridSize'] ?? 7,
    status: _parseStatus(json['status']),
    currentTurnOrder: json['currentTurnOrder'] ?? 0,
    winnerTeam: SosTeamX.fromString(json['winnerTeam']),
    winnerUserId: json['winnerUserId'],
    startedAt: json['startedAt'] != null
        ? DateTime.tryParse(json['startedAt'])
        : null,
    finishedAt: json['finishedAt'] != null
        ? DateTime.tryParse(json['finishedAt'])
        : null,
    createdAt:
        DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
  );

  static SosGameStatus _parseStatus(String? s) {
    switch (s) {
      case 'active':
        return SosGameStatus.active;
      case 'finished':
        return SosGameStatus.finished;
      case 'lobby':
      default:
        return SosGameStatus.lobby;
    }
  }

  bool get isLobby => status == SosGameStatus.lobby;
  bool get isActive => status == SosGameStatus.active;
  bool get isFinished => status == SosGameStatus.finished;
  int get cellCount => gridSize * gridSize;
}

class SosPlayer {
  const SosPlayer({
    required this.id,
    required this.gameId,
    required this.userId,
    required this.userName,
    this.team,
    required this.turnOrder,
    required this.score,
    required this.joinedAt,
  });

  final String id;
  final String gameId;
  final String userId;
  final String userName;
  final SosTeam? team; // NULL in 2-player mode
  final int turnOrder;
  final int score;
  final DateTime joinedAt;

  factory SosPlayer.fromJson(Map<String, dynamic> json) => SosPlayer(
    id: json['id'] ?? '',
    gameId: json['gameId'] ?? '',
    userId: json['userId'] ?? '',
    userName: json['userName'] ?? 'Player',
    team: SosTeamX.fromString(json['team']),
    turnOrder: json['turnOrder'] ?? 0,
    score: json['score'] ?? 0,
    joinedAt:
        DateTime.tryParse(json['joinedAt'] ?? '') ?? DateTime.now(),
  );

  SosPlayer copyWith({int? score}) => SosPlayer(
    id: id,
    gameId: gameId,
    userId: userId,
    userName: userName,
    team: team,
    turnOrder: turnOrder,
    score: score ?? this.score,
    joinedAt: joinedAt,
  );
}

class SosMove {
  const SosMove({
    required this.id,
    required this.gameId,
    required this.userId,
    required this.userName,
    required this.rowIdx,
    required this.colIdx,
    required this.letter,
    this.team,
    required this.sequenced,
    required this.sequenceCount,
    required this.playedAt,
  });

  final String id;
  final String gameId;
  final String userId;
  final String userName;
  final int rowIdx;
  final int colIdx;
  final SosLetter letter;
  final SosTeam? team;
  final bool sequenced;
  final int sequenceCount;
  final DateTime playedAt;

  factory SosMove.fromJson(Map<String, dynamic> json) => SosMove(
    id: json['id'] ?? '',
    gameId: json['gameId'] ?? '',
    userId: json['userId'] ?? '',
    userName: json['userName'] ?? 'Player',
    rowIdx: json['rowIdx'] ?? 0,
    colIdx: json['colIdx'] ?? 0,
    letter: SosLetterX.fromString(json['letter']),
    team: SosTeamX.fromString(json['team']),
    sequenced: json['sequenced'] ?? false,
    sequenceCount: json['sequenceCount'] ?? 0,
    playedAt:
        DateTime.tryParse(json['playedAt'] ?? '') ?? DateTime.now(),
  );
}

class SosScore {
  const SosScore({
    required this.id,
    required this.gameId,
    this.userId,
    this.team,
    required this.score,
    required this.updatedAt,
  });

  final String id;
  final String gameId;
  final String? userId;
  final SosTeam? team;
  final int score;
  final DateTime updatedAt;

  factory SosScore.fromJson(Map<String, dynamic> json) => SosScore(
    id: json['id'] ?? '',
    gameId: json['gameId'] ?? '',
    userId: json['userId'],
    team: SosTeamX.fromString(json['team']),
    score: json['score'] ?? 0,
    updatedAt:
        DateTime.tryParse(json['updatedAt'] ?? '') ?? DateTime.now(),
  );
}

/// A completed SOS sequence — used for highlighting on the grid.
class SosSequence {
  const SosSequence({
    required this.cells,
    required this.team,
    required this.moveId,
  });

  /// 3 (row, col) tuples in order.
  final List<(int, int)> cells;
  final SosTeam? team;
  final String moveId;
}

// lib/features/games/tugofwar/tugofwar_models.dart
//
// Tug of War — data models for the team multiplayer rope game.
//
// Two teams (A = Ember, B = Azure) pull a rope by spam-tapping PULL.
// The server normalizes strength per player (teamTaps / teamSize) so
// uneven teams still get a fair fight — see fn_tugofwar_pull.

enum TugOfWarStatus { waiting, inProgress, completed }

extension TugOfWarStatusX on TugOfWarStatus {
  String get wire {
    switch (this) {
      case TugOfWarStatus.waiting:
        return 'waiting';
      case TugOfWarStatus.inProgress:
        return 'in_progress';
      case TugOfWarStatus.completed:
        return 'completed';
    }
  }

  static TugOfWarStatus fromString(String? s) {
    switch (s) {
      case 'in_progress':
        return TugOfWarStatus.inProgress;
      case 'completed':
        return TugOfWarStatus.completed;
      case 'waiting':
      default:
        return TugOfWarStatus.waiting;
    }
  }
}

/// How teams are formed in the lobby.
enum TugOfWarTeamMode {
  /// Unassigned players are auto-balanced onto the smaller team.
  auto,

  /// Players tap "Join Team A / Team B" themselves.
  manual,

  /// Host shuffles everyone into even halves.
  random;

  static TugOfWarTeamMode fromString(String? s) {
    switch (s) {
      case 'manual':
        return TugOfWarTeamMode.manual;
      case 'random':
        return TugOfWarTeamMode.random;
      case 'auto':
      default:
        return TugOfWarTeamMode.auto;
    }
  }

  String get wire => name;

  String get label {
    switch (this) {
      case TugOfWarTeamMode.auto:
        return 'Balanced';
      case TugOfWarTeamMode.manual:
        return 'Pick Your Own';
      case TugOfWarTeamMode.random:
        return 'Random Shuffle';
    }
  }

  String get caption {
    switch (this) {
      case TugOfWarTeamMode.auto:
        return 'Teams stay even as players join';
      case TugOfWarTeamMode.manual:
        return 'Everyone picks their side';
      case TugOfWarTeamMode.random:
        return 'Host shuffles both teams';
    }
  }
}

/// The two teams. Wire values match the SQL `team` column ('A' | 'B').
enum TugTeam { a, b }

extension TugTeamX on TugTeam {
  static TugTeam? fromString(String? s) {
    switch (s) {
      case 'A':
        return TugTeam.a;
      case 'B':
        return TugTeam.b;
      default:
        return null;
    }
  }

  String get wire => this == TugTeam.a ? 'A' : 'B';

  String get label => this == TugTeam.a ? 'Team Ember' : 'Team Azure';

  String get shortLabel => this == TugTeam.a ? 'EMBER' : 'AZURE';

  /// The other team.
  TugTeam get opposite => this == TugTeam.a ? TugTeam.b : TugTeam.a;
}

class TugOfWarGame {
  const TugOfWarGame({
    required this.id,
    required this.familyId,
    required this.hostUserId,
    required this.hostUserName,
    required this.status,
    required this.teamMode,
    required this.matchDurationSec,
    required this.maxPlayers,
    required this.ropePosition,
    required this.createdAt,
    this.roomName,
    this.teamATaps = 0,
    this.teamBTaps = 0,
    this.winnerTeam,
    this.winnerUserIds = const [],
    this.endReason,
    this.startedAt,
    this.endsAt,
    this.completedAt,
    this.spectatorsEnabled = true,
  });

  final String id;
  final String familyId;
  final String hostUserId;
  final String hostUserName;
  final TugOfWarStatus status;
  final TugOfWarTeamMode teamMode;
  final int matchDurationSec; // 30 | 60 | 90 | 0 = unlimited
  final int maxPlayers;
  final double ropePosition; // -1 .. +1 (+ = Team A lead)
  final DateTime createdAt;
  final String? roomName;
  final int teamATaps;
  final int teamBTaps;
  final String? winnerTeam; // 'A' | 'B' | null (draw / none yet)
  final List<String> winnerUserIds;
  final String? endReason; // victory_line | time_up | walkover
  final DateTime? startedAt;
  final DateTime? endsAt;
  final DateTime? completedAt;
  final bool spectatorsEnabled;

  factory TugOfWarGame.fromJson(Map<String, dynamic> json) {
    final winnerIds = <String>[];
    final rawWinners = json['winnerUserIds'];
    if (rawWinners is List) {
      winnerIds.addAll(rawWinners.whereType<String>());
    }
    return TugOfWarGame(
      id: (json['id'] ?? '') as String,
      familyId: (json['familyId'] ?? '') as String,
      hostUserId: (json['hostUserId'] ?? '') as String,
      hostUserName: (json['hostUserName'] ?? 'Host') as String,
      status: TugOfWarStatusX.fromString(json['status'] as String?),
      teamMode:
          TugOfWarTeamMode.fromString(json['teamMode'] as String?),
      matchDurationSec: (json['matchDurationSec'] ?? 60) as int,
      maxPlayers: (json['maxPlayers'] ?? 8) as int,
      ropePosition:
          ((json['ropePosition'] ?? 0) as num).toDouble().clamp(-1.0, 1.0),
      createdAt:
          DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      roomName: json['roomName'] as String?,
      teamATaps: (json['teamATaps'] ?? 0) as int,
      teamBTaps: (json['teamBTaps'] ?? 0) as int,
      winnerTeam: json['winnerTeam'] as String?,
      winnerUserIds: winnerIds,
      endReason: json['endReason'] as String?,
      startedAt: json['startedAt'] != null
          ? DateTime.tryParse(json['startedAt'] as String)
          : null,
      endsAt: json['endsAt'] != null
          ? DateTime.tryParse(json['endsAt'] as String)
          : null,
      completedAt: json['completedAt'] != null
          ? DateTime.tryParse(json['completedAt'] as String)
          : null,
      spectatorsEnabled: (json['spectatorsEnabled'] ?? true) as bool,
    );
  }

  bool get isWaiting => status == TugOfWarStatus.waiting;
  bool get isInProgress => status == TugOfWarStatus.inProgress;
  bool get isCompleted => status == TugOfWarStatus.completed;

  bool get hasTimer => matchDurationSec > 0;

  TugTeam? get winningTeam => TugTeamX.fromString(winnerTeam);

  /// Seconds left on the clock (null when unlimited / not running).
  int? get secondsRemaining {
    if (!isInProgress || endsAt == null) return null;
    final left = endsAt!.difference(DateTime.now()).inSeconds;
    return left < 0 ? 0 : left;
  }

  String get endReasonLabel {
    switch (endReason) {
      case 'victory_line':
        return 'Flag crossed the victory line!';
      case 'time_up':
        return 'Time up — the stronger average won';
      case 'walkover':
        return 'The other side walked away';
      default:
        return 'Match complete';
    }
  }
}

class TugOfWarPlayer {
  const TugOfWarPlayer({
    required this.id,
    required this.gameId,
    required this.userId,
    required this.userName,
    required this.joinedAt,
    this.team,
    this.pullCount = 0,
    this.isReady = false,
    this.readyAt,
  });

  final String id;
  final String gameId;
  final String userId;
  final String userName;
  final DateTime joinedAt;
  final TugTeam? team;
  final int pullCount;
  final bool isReady;
  final DateTime? readyAt;

  factory TugOfWarPlayer.fromJson(Map<String, dynamic> json) {
    return TugOfWarPlayer(
      id: (json['id'] ?? '') as String,
      gameId: (json['gameId'] ?? '') as String,
      userId: (json['userId'] ?? '') as String,
      userName: (json['userName'] ?? 'Player') as String,
      joinedAt:
          DateTime.tryParse(json['joinedAt'] ?? '') ?? DateTime.now(),
      team: TugTeamX.fromString(json['team'] as String?),
      pullCount: (json['pullCount'] ?? 0) as int,
      isReady: (json['isReady'] ?? false) as bool,
      readyAt: json['readyAt'] != null
          ? DateTime.tryParse(json['readyAt'] as String)
          : null,
    );
  }

  TugOfWarPlayer copyWith({
    TugTeam? team,
    bool? clearTeam,
    int? pullCount,
    bool? isReady,
  }) {
    return TugOfWarPlayer(
      id: id,
      gameId: gameId,
      userId: userId,
      userName: userName,
      joinedAt: joinedAt,
      team: clearTeam == true ? null : (team ?? this.team),
      pullCount: pullCount ?? this.pullCount,
      isReady: isReady ?? this.isReady,
      readyAt: readyAt,
    );
  }
}

/// Team-level aggregates derived from the player roster.
class TugTeamStats {
  const TugTeamStats({
    required this.players,
    required this.totalTaps,
  });

  final List<TugOfWarPlayer> players;
  final int totalTaps;

  int get size => players.length;

  /// FAIRNESS: strength is the average taps per player, not the raw total —
  /// a 10-player team can't crush a 3-player team on numbers alone.
  double get avgTaps => size == 0 ? 0 : totalTaps / size;

  /// Taps per player per second over [elapsed] seconds.
  double tapRate(Duration elapsed) {
    final secs = elapsed.inMilliseconds / 1000.0;
    if (secs < 0.5 || size == 0) return 0;
    return avgTaps / secs;
  }
}

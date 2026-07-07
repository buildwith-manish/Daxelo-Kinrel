// lib/features/games/redlight/redlight_models.dart
//
// Freeze & Dash (Red Light, Green Light) — data models.
//
// Mirrors ghost_painter_models.dart conventions:
//   • const constructors, all fields final
//   • factory fromJson
//   • copyWith on mutable state classes

enum RedlightPhase { green, red, waiting }

enum RedlightPenalty { eliminated, knockback, shieldAbsorbed }

enum CallerCharacter { grandma, robot, parrot, alien }

enum MapTheme { forest, beach, playground, village }

enum WeatherModifier { rain, fog, wind }

enum PowerupType { shield, speedBoost }

extension CallerCharacterX on CallerCharacter {
  String get label {
    switch (this) {
      case CallerCharacter.grandma:
        return 'Grandma';
      case CallerCharacter.robot:
        return 'Robot';
      case CallerCharacter.parrot:
        return 'Parrot';
      case CallerCharacter.alien:
        return 'Alien';
    }
  }

  String get emoji {
    switch (this) {
      case CallerCharacter.grandma:
        return '👵';
      case CallerCharacter.robot:
        return '🤖';
      case CallerCharacter.parrot:
        return '🦜';
      case CallerCharacter.alien:
        return '👽';
    }
  }

  static CallerCharacter fromString(String? s) {
    switch (s) {
      case 'robot':
        return CallerCharacter.robot;
      case 'parrot':
        return CallerCharacter.parrot;
      case 'alien':
        return CallerCharacter.alien;
      case 'grandma':
      default:
        return CallerCharacter.grandma;
    }
  }
}

extension MapThemeX on MapTheme {
  String get label {
    switch (this) {
      case MapTheme.forest:
        return 'Forest';
      case MapTheme.beach:
        return 'Beach';
      case MapTheme.playground:
        return 'Playground';
      case MapTheme.village:
        return 'Village';
    }
  }

  String get emoji {
    switch (this) {
      case MapTheme.forest:
        return '🌲';
      case MapTheme.beach:
        return '🏖️';
      case MapTheme.playground:
        return '🛝';
      case MapTheme.village:
        return '🏘️';
    }
  }

  static MapTheme fromString(String? s) {
    switch (s) {
      case 'beach':
        return MapTheme.beach;
      case 'playground':
        return MapTheme.playground;
      case 'village':
        return MapTheme.village;
      case 'forest':
      default:
        return MapTheme.forest;
    }
  }
}

extension WeatherModifierX on WeatherModifier {
  String get label {
    switch (this) {
      case WeatherModifier.rain:
        return 'Rain';
      case WeatherModifier.fog:
        return 'Fog';
      case WeatherModifier.wind:
        return 'Wind';
    }
  }

  String get emoji {
    switch (this) {
      case WeatherModifier.rain:
        return '🌧️';
      case WeatherModifier.fog:
        return '🌫️';
      case WeatherModifier.wind:
        return '💨';
    }
  }

  static WeatherModifier? fromString(String? s) {
    if (s == null) return null;
    switch (s) {
      case 'rain':
        return WeatherModifier.rain;
      case 'fog':
        return WeatherModifier.fog;
      case 'wind':
        return WeatherModifier.wind;
      default:
        return null;
    }
  }
}

extension PowerupTypeX on PowerupType {
  String get emoji {
    switch (this) {
      case PowerupType.shield:
        return '🛡️';
      case PowerupType.speedBoost:
        return '⚡';
    }
  }

  static PowerupType fromString(String? s) {
    return s == 'speedBoost' ? PowerupType.speedBoost : PowerupType.shield;
  }
}

class RedlightRound {
  const RedlightRound({
    required this.id,
    required this.familyId,
    required this.hostUserId,
    required this.hostUserName,
    required this.callerCharacter,
    required this.mapTheme,
    required this.teamMode,
    required this.eliminationMode,
    required this.status,
    this.weatherModifier,
    this.winnerUserId,
    this.winnerUserName,
    this.startedAt,
    this.finishedAt,
    required this.createdAt,
  });

  final String id;
  final String familyId;
  final String hostUserId;
  final String hostUserName;
  final CallerCharacter callerCharacter;
  final MapTheme mapTheme;
  final WeatherModifier? weatherModifier;
  final bool teamMode;
  final bool eliminationMode;
  final String status; // lobby | countdown | active | finished
  final String? winnerUserId;
  final String? winnerUserName;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final DateTime createdAt;

  factory RedlightRound.fromJson(Map<String, dynamic> json) => RedlightRound(
    id: json['id'] ?? '',
    familyId: json['familyId'] ?? '',
    hostUserId: json['hostUserId'] ?? '',
    hostUserName: json['hostUserName'] ?? 'Host',
    callerCharacter: CallerCharacterX.fromString(json['callerCharacter']),
    mapTheme: MapThemeX.fromString(json['mapTheme']),
    weatherModifier: WeatherModifierX.fromString(json['weatherModifier']),
    teamMode: json['teamMode'] ?? false,
    eliminationMode: json['eliminationMode'] ?? false,
    status: json['status'] ?? 'lobby',
    winnerUserId: json['winnerUserId'],
    winnerUserName: json['winnerUserName'],
    startedAt: json['startedAt'] != null
        ? DateTime.tryParse(json['startedAt'])
        : null,
    finishedAt: json['finishedAt'] != null
        ? DateTime.tryParse(json['finishedAt'])
        : null,
    createdAt:
        DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
  );

  bool get isLobby => status == 'lobby';
  bool get isCountdown => status == 'countdown';
  bool get isActive => status == 'active';
  bool get isFinished => status == 'finished';
}

class RedlightPlayer {
  const RedlightPlayer({
    required this.id,
    required this.roundId,
    required this.userId,
    required this.userName,
    this.teamId,
    required this.progress,
    required this.alive,
    required this.powerups,
    required this.joinedAt,
  });

  final String id;
  final String roundId;
  final String userId;
  final String userName;
  final String? teamId;
  final double progress;
  final bool alive;
  final List<ActivePowerup> powerups;
  final DateTime joinedAt;

  factory RedlightPlayer.fromJson(Map<String, dynamic> json) {
    final rawPowerups = (json['powerups'] as List?) ?? [];
    return RedlightPlayer(
      id: json['id'] ?? '',
      roundId: json['roundId'] ?? '',
      userId: json['userId'] ?? '',
      userName: json['userName'] ?? 'Player',
      teamId: json['teamId'],
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      alive: json['alive'] ?? true,
      powerups: rawPowerups
          .map((p) => ActivePowerup.fromJson(p as Map<String, dynamic>))
          .toList(),
      joinedAt:
          DateTime.tryParse(json['joinedAt'] ?? '') ?? DateTime.now(),
    );
  }

  RedlightPlayer copyWith({
    double? progress,
    bool? alive,
    List<ActivePowerup>? powerups,
  }) =>
      RedlightPlayer(
        id: id,
        roundId: roundId,
        userId: userId,
        userName: userName,
        teamId: teamId,
        progress: progress ?? this.progress,
        alive: alive ?? this.alive,
        powerups: powerups ?? this.powerups,
        joinedAt: joinedAt,
      );
}

class ActivePowerup {
  const ActivePowerup({
    required this.type,
    required this.expiresAt,
  });
  final PowerupType type;
  final DateTime expiresAt;

  factory ActivePowerup.fromJson(Map<String, dynamic> json) => ActivePowerup(
    type: PowerupTypeX.fromString(json['type']),
    expiresAt:
        DateTime.tryParse(json['expiresAt'] ?? '') ?? DateTime.now(),
  );

  bool get isActive => DateTime.now().isBefore(expiresAt);
}

class RedlightResult {
  const RedlightResult({
    required this.id,
    required this.roundId,
    required this.userId,
    required this.userName,
    required this.finalProgress,
    required this.placement,
    required this.finishedAt,
  });

  final String id;
  final String roundId;
  final String userId;
  final String userName;
  final double finalProgress;
  final int placement;
  final DateTime finishedAt;

  factory RedlightResult.fromJson(Map<String, dynamic> json) =>
      RedlightResult(
        id: json['id'] ?? '',
        roundId: json['roundId'] ?? '',
        userId: json['userId'] ?? '',
        userName: json['userName'] ?? 'Player',
        finalProgress: (json['finalProgress'] as num?)?.toDouble() ?? 0,
        placement: json['placement'] ?? 0,
        finishedAt:
            DateTime.tryParse(json['finishedAt'] ?? '') ?? DateTime.now(),
      );
}

class SpawnedPowerup {
  const SpawnedPowerup({
    required this.powerupId,
    required this.type,
    required this.position,
  });
  final String powerupId;
  final PowerupType type;
  final double position; // 0–100, track position

  factory SpawnedPowerup.fromJson(Map<String, dynamic> json) =>
      SpawnedPowerup(
        powerupId: json['powerupId'] ?? '',
        type: PowerupTypeX.fromString(json['type']),
        position: (json['position'] as num?)?.toDouble() ?? 0,
      );
}

/// Compact leaderboard entry pushed by the gateway every 500ms.
class RedlightLeaderboardEntry {
  const RedlightLeaderboardEntry({
    required this.userId,
    required this.userName,
    required this.progress,
    required this.alive,
    this.teamId,
  });
  final String userId;
  final String userName;
  final double progress;
  final bool alive;
  final String? teamId;

  factory RedlightLeaderboardEntry.fromJson(Map<String, dynamic> json) =>
      RedlightLeaderboardEntry(
        userId: json['userId'] ?? '',
        userName: json['userName'] ?? 'Player',
        progress: (json['progress'] as num?)?.toDouble() ?? 0,
        alive: json['alive'] ?? true,
        teamId: json['teamId'],
      );
}

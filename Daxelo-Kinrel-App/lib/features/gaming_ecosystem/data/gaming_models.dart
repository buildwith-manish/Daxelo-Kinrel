// lib/features/gaming_ecosystem/data/gaming_models.dart
//
// Typed models for the Family Gaming Ecosystem. Every model parses the
// jsonb returned by the ecosystem Supabase RPCs (fn_get_gaming_dashboard,
// fn_get_family_leaderboard_v2, fn_get_match_history, ...).
//
// The models are intentionally tolerant: missing/null fields fall back to
// sensible defaults so a schema evolution never crashes the UI.

/// A single leaderboard row (weekly / monthly / all-time / per-game).
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.userId,
    required this.userName,
    this.avatarUrl,
    this.wins = 0,
    this.losses = 0,
    this.draws = 0,
    this.matches = 0,
    this.points = 0,
    this.streakCurrent = 0,
    this.streakBest = 0,
    this.sportsmanship = 0,
    this.winRate = 0,
  });

  final String userId;
  final String userName;
  final String? avatarUrl;
  final int wins;
  final int losses;
  final int draws;
  final int matches;
  final int points;
  final int streakCurrent;
  final int streakBest;
  final int sportsmanship;
  final double winRate;

  String get winRateLabel => '${(winRate * 100).round()}%';

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) {
    return LeaderboardEntry(
      userId: (json['userId'] as String?) ?? '',
      userName: (json['userName'] as String?) ?? 'Family Member',
      avatarUrl: json['avatarUrl'] as String?,
      wins: (json['wins'] as num?)?.toInt() ?? 0,
      losses: (json['losses'] as num?)?.toInt() ?? 0,
      draws: (json['draws'] as num?)?.toInt() ?? 0,
      matches: (json['matches'] as num?)?.toInt() ?? 0,
      points: (json['points'] as num?)?.toInt() ?? 0,
      streakCurrent: (json['streakCurrent'] as num?)?.toInt() ?? 0,
      streakBest: (json['streakBest'] as num?)?.toInt() ?? 0,
      sportsmanship: (json['sportsmanship'] as num?)?.toInt() ?? 0,
      winRate: (json['winRate'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// A challenge (weekly or monthly mission) with live progress.
class ChallengeInfo {
  const ChallengeInfo({
    required this.slug,
    required this.title,
    required this.description,
    required this.cadence,
    required this.icon,
    required this.target,
    this.rewardPoints = 0,
    this.familyWide = false,
    this.progress = 0,
    this.completedAt,
  });

  final String slug;
  final String title;
  final String description;
  final String cadence; // weekly | monthly
  final String icon;
  final int target;
  final int rewardPoints;
  final bool familyWide;
  final int progress;
  final DateTime? completedAt;

  bool get isCompleted => progress >= target;
  double get progressFraction =>
      target <= 0 ? 0 : (progress / target).clamp(0.0, 1.0);

  factory ChallengeInfo.fromJson(Map<String, dynamic> json) {
    return ChallengeInfo(
      slug: (json['slug'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      cadence: (json['cadence'] as String?) ?? 'weekly',
      icon: (json['icon'] as String?) ?? '🎯',
      target: (json['target'] as num?)?.toInt() ?? 1,
      rewardPoints: (json['rewardPoints'] as num?)?.toInt() ?? 0,
      familyWide: json['familyWide'] as bool? ?? false,
      progress: (json['progress'] as num?)?.toInt() ?? 0,
      completedAt: json['completedAt'] == null
          ? null
          : DateTime.tryParse(json['completedAt'].toString()),
    );
  }
}

/// A game badge (achievement) — earned or locked.
class BadgeInfo {
  const BadgeInfo({
    required this.slug,
    required this.name,
    required this.icon,
    required this.tier,
    this.description = '',
    this.threshold = 0,
    this.earned = false,
    this.earnedAt,
  });

  final String slug;
  final String name;
  final String icon;
  final String tier; // bronze | silver | gold | platinum
  final String description;
  final int threshold;
  final bool earned;
  final DateTime? earnedAt;

  factory BadgeInfo.fromJson(Map<String, dynamic> json) {
    return BadgeInfo(
      slug: (json['slug'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      icon: (json['icon'] as String?) ?? '🏅',
      tier: (json['tier'] as String?) ?? 'bronze',
      description: (json['description'] as String?) ?? '',
      threshold: (json['threshold'] as num?)?.toInt() ?? 0,
      earned: json['earned'] as bool? ?? (json['earnedAt'] != null),
      earnedAt: json['earnedAt'] == null
          ? null
          : DateTime.tryParse(json['earnedAt'].toString()),
    );
  }
}

/// One match in the player's history.
class MatchHistoryEntry {
  const MatchHistoryEntry({
    required this.matchId,
    required this.gameTable,
    required this.gameName,
    required this.gameIcon,
    required this.result,
    required this.finishedAt,
    this.durationSeconds = 0,
    this.playerCount = 0,
    this.opponents = const [],
  });

  final String matchId;
  final String gameTable;
  final String gameName;
  final String gameIcon;
  final String result; // win | loss | draw | played
  final DateTime? finishedAt;
  final int durationSeconds;
  final int playerCount;
  final List<MatchOpponent> opponents;

  bool get isWin => result == 'win';

  String get durationLabel {
    if (durationSeconds <= 0) return '';
    final m = durationSeconds ~/ 60;
    final s = durationSeconds % 60;
    if (m <= 0) return '$s{s}';
    return '$m m ${s}s';
  }

  factory MatchHistoryEntry.fromJson(Map<String, dynamic> json) {
    return MatchHistoryEntry(
      matchId: (json['matchId'] as String?) ?? '',
      gameTable: (json['gameTable'] as String?) ?? '',
      gameName: (json['gameName'] as String?) ?? 'Game',
      gameIcon: (json['gameIcon'] as String?) ?? '🎮',
      result: (json['result'] as String?) ?? 'played',
      finishedAt: json['finishedAt'] == null
          ? null
          : DateTime.tryParse(json['finishedAt'].toString()),
      durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
      playerCount: (json['playerCount'] as num?)?.toInt() ?? 0,
      opponents: (json['opponents'] as List? ?? [])
          .map((e) =>
              MatchOpponent.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}

class MatchOpponent {
  const MatchOpponent({required this.userName, this.result});
  final String userName;
  final String? result;

  factory MatchOpponent.fromJson(Map<String, dynamic> json) {
    return MatchOpponent(
      userName: (json['userName'] as String?) ?? 'Family Member',
      result: json['result'] as String?,
    );
  }
}

/// One entry in the family gaming activity feed.
class ActivityEntry {
  const ActivityEntry({
    required this.id,
    required this.action,
    required this.description,
    required this.createdAt,
    this.actorUserId,
    this.actorName,
    this.metadata = const {},
  });

  final String id;
  final String action; // game_match_completed | game_badge_earned | ...
  final String description;
  final DateTime? createdAt;
  final String? actorUserId;
  final String? actorName;
  final Map<String, dynamic> metadata;

  String get icon {
    switch (action) {
      case 'game_match_completed':
        return (metadata['gameIcon'] as String?) ?? '🎮';
      case 'game_badge_earned':
        return (metadata['badgeIcon'] as String?) ?? '🏅';
      case 'game_challenge_completed':
        return (metadata['icon'] as String?) ?? '🎯';
      case 'game_milestone_reached':
        return '🏆';
      case 'game_cup_won':
        return '👑';
      case 'game_sportsmanship':
        return '💚';
      default:
        return '🎮';
    }
  }

  factory ActivityEntry.fromJson(Map<String, dynamic> json) {
    return ActivityEntry(
      id: (json['id'] as String?) ?? '',
      action: (json['action'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.tryParse(json['createdAt'].toString()),
      actorUserId: json['actorUserId'] as String?,
      actorName: json['actorName'] as String?,
      metadata: json['metadata'] is Map
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : const {},
    );
  }
}

/// A family gaming milestone (games played together etc.).
class MilestoneInfo {
  const MilestoneInfo({
    required this.milestone,
    this.reachedAt,
    this.celebrated = false,
    this.description = '',
  });

  final String milestone;
  final DateTime? reachedAt;
  final bool celebrated;
  final String description;

  bool get isReached => reachedAt != null;

  /// Target value parsed from the milestone key (games_together_100 → 100).
  int get target {
    final parts = milestone.split('_');
    final last = parts.isNotEmpty ? parts.last : '';
    return int.tryParse(last) ?? 1;
  }

  factory MilestoneInfo.fromJson(Map<String, dynamic> json) {
    return MilestoneInfo(
      milestone: (json['milestone'] as String?) ?? '',
      reachedAt: json['reachedAt'] == null
          ? null
          : DateTime.tryParse(json['reachedAt'].toString()),
      celebrated: json['celebrated'] as bool? ?? false,
      description: (json['description'] as String?) ?? '',
    );
  }
}

/// The current Family Cup season.
class SeasonInfo {
  const SeasonInfo({
    required this.id,
    required this.name,
    this.periodKey = '',
    this.startsAt,
    this.endsAt,
    this.daysRemaining = 0,
  });

  final String id;
  final String name;
  final String periodKey;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final int daysRemaining;

  factory SeasonInfo.fromJson(Map<String, dynamic> json) {
    return SeasonInfo(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? 'The Family Cup',
      periodKey: (json['periodKey'] as String?) ?? '',
      startsAt: json['startsAt'] == null
          ? null
          : DateTime.tryParse(json['startsAt'].toString()),
      endsAt: json['endsAt'] == null
          ? null
          : DateTime.tryParse(json['endsAt'].toString()),
      daysRemaining: (json['daysRemaining'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A smart "play with X" suggestion.
class SmartSuggestion {
  const SmartSuggestion({
    required this.userId,
    required this.userName,
    required this.gameTable,
    required this.gameName,
    required this.gameIcon,
    required this.reason,
    this.gamesTogether = 0,
  });

  final String userId;
  final String userName;
  final String gameTable;
  final String gameName;
  final String gameIcon;
  final String reason;
  final int gamesTogether;

  factory SmartSuggestion.fromJson(Map<String, dynamic> json) {
    return SmartSuggestion(
      userId: (json['userId'] as String?) ?? '',
      userName: (json['userName'] as String?) ?? 'Family Member',
      gameTable: (json['gameTable'] as String?) ?? '',
      gameName: (json['gameName'] as String?) ?? 'a game',
      gameIcon: (json['gameIcon'] as String?) ?? '🎮',
      reason: (json['reason'] as String?) ?? '',
      gamesTogether: (json['gamesTogether'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A player in the season standings / family member list.
class SeasonStandingEntry {
  const SeasonStandingEntry({
    required this.userId,
    required this.userName,
    this.points = 0,
    this.wins = 0,
    this.gamesPlayed = 0,
    this.avatarUrl,
    this.matches = 0,
  });

  final String userId;
  final String userName;
  final String? avatarUrl;
  final int points;
  final int wins;
  final int gamesPlayed;
  final int matches;

  factory SeasonStandingEntry.fromJson(Map<String, dynamic> json) {
    return SeasonStandingEntry(
      userId: (json['userId'] as String?) ?? '',
      userName: (json['userName'] as String?) ?? 'Family Member',
      avatarUrl: json['avatarUrl'] as String?,
      points: (json['points'] as num?)?.toInt() ?? 0,
      wins: (json['wins'] as num?)?.toInt() ?? 0,
      gamesPlayed: (json['gamesPlayed'] as num?)?.toInt() ?? 0,
      matches: (json['matches'] as num?)?.toInt() ?? 0,
    );
  }
}

/// The full gaming dashboard payload (fn_get_gaming_dashboard).
class GamingDashboard {
  const GamingDashboard({
    this.familyTotalMatches = 0,
    this.familyDistinctGames = 0,
    this.me = const GamingMeStats(),
    this.season,
    this.challenges = const [],
    this.leaderboard = const [],
    this.weeklyLeaderboard = const [],
    this.activity = const [],
    this.suggestions = const [],
    this.milestones = const [],
    this.seasonStandings = const [],
    this.myBadges = const [],
    this.allGameBadges = const [],
    this.familyMembers = const [],
  });

  final int familyTotalMatches;
  final int familyDistinctGames;
  final GamingMeStats me;
  final SeasonInfo? season;
  final List<ChallengeInfo> challenges;
  final List<LeaderboardEntry> leaderboard;
  final List<LeaderboardEntry> weeklyLeaderboard;
  final List<ActivityEntry> activity;
  final List<SmartSuggestion> suggestions;
  final List<MilestoneInfo> milestones;
  final List<SeasonStandingEntry> seasonStandings;
  final List<BadgeInfo> myBadges;
  final List<BadgeInfo> allGameBadges;
  final List<SeasonStandingEntry> familyMembers;

  /// Challenges still in progress (not yet completed).
  List<ChallengeInfo> get activeChallenges =>
      challenges.where((c) => !c.isCompleted).toList();

  List<ChallengeInfo> get completedChallenges =>
      challenges.where((c) => c.isCompleted).toList();

  factory GamingDashboard.fromJson(Map<String, dynamic> json) {
    return GamingDashboard(
      familyTotalMatches:
          (json['familyTotalMatches'] as num?)?.toInt() ?? 0,
      familyDistinctGames:
          (json['familyDistinctGames'] as num?)?.toInt() ?? 0,
      me: GamingMeStats.fromJson(
          json['me'] is Map ? Map<String, dynamic>.from(json['me'] as Map) : const {}),
      season: json['season'] is Map
          ? SeasonInfo.fromJson(Map<String, dynamic>.from(json['season'] as Map))
          : null,
      challenges: _list(json['challenges'], ChallengeInfo.fromJson),
      leaderboard: _list(json['leaderboard'], LeaderboardEntry.fromJson),
      weeklyLeaderboard:
          _list(json['weeklyLeaderboard'], LeaderboardEntry.fromJson),
      activity: _list(json['activity'], ActivityEntry.fromJson),
      suggestions: _list(json['suggestions'], SmartSuggestion.fromJson),
      milestones: _list(json['milestones'], MilestoneInfo.fromJson),
      seasonStandings:
          _list(json['seasonStandings'], SeasonStandingEntry.fromJson),
      myBadges: _list(json['myBadges'], BadgeInfo.fromJson),
      allGameBadges: _list(json['allGameBadges'], BadgeInfo.fromJson),
      familyMembers:
          _list(json['familyMembers'], SeasonStandingEntry.fromJson),
    );
  }
}

class GamingMeStats {
  const GamingMeStats({
    this.userId = '',
    this.matches = 0,
    this.wins = 0,
    this.points = 0,
    this.streakCurrent = 0,
    this.rank = 0,
  });

  final String userId;
  final int matches;
  final int wins;
  final int points;
  final int streakCurrent;
  final int rank;

  factory GamingMeStats.fromJson(Map<String, dynamic> json) {
    return GamingMeStats(
      userId: (json['userId'] as String?) ?? '',
      matches: (json['matches'] as num?)?.toInt() ?? 0,
      wins: (json['wins'] as num?)?.toInt() ?? 0,
      points: (json['points'] as num?)?.toInt() ?? 0,
      streakCurrent: (json['streakCurrent'] as num?)?.toInt() ?? 0,
      rank: (json['rank'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Player gaming profile (fn_get_player_gaming_profile).
class PlayerGamingProfile {
  const PlayerGamingProfile({
    required this.userId,
    required this.userName,
    this.avatarUrl,
    this.username,
    this.matches = 0,
    this.wins = 0,
    this.losses = 0,
    this.draws = 0,
    this.points = 0,
    this.streakCurrent = 0,
    this.streakBest = 0,
    this.sportsmanship = 0,
    this.spectated = 0,
    this.winRate = 0,
    this.rank = 0,
    this.daysActiveThisWeek = 0,
    this.favoriteGame,
    this.perGame = const [],
    this.badges = const [],
    this.recentMatches = const [],
    this.recentActivity = const [],
  });

  final String userId;
  final String userName;
  final String? avatarUrl;
  final String? username;
  final int matches;
  final int wins;
  final int losses;
  final int draws;
  final int points;
  final int streakCurrent;
  final int streakBest;
  final int sportsmanship;
  final int spectated;
  final double winRate;
  final int rank;
  final int daysActiveThisWeek;
  final GameStat? favoriteGame;
  final List<GameStat> perGame;
  final List<BadgeInfo> badges;
  final List<RecentMatch> recentMatches;
  final List<ActivityEntry> recentActivity;

  String get winRateLabel => '${(winRate * 100).round()}%';

  /// Family Gamer Level — 1 level per 100 points.
  int get level => (points ~/ 100) + (points > 0 ? 1 : 0);
  int get pointsIntoLevel => points % 100;

  factory PlayerGamingProfile.fromJson(Map<String, dynamic> json) {
    return PlayerGamingProfile(
      userId: (json['userId'] as String?) ?? '',
      userName: (json['userName'] as String?) ?? 'Family Member',
      avatarUrl: json['avatarUrl'] as String?,
      username: json['username'] as String?,
      matches: (json['matches'] as num?)?.toInt() ?? 0,
      wins: (json['wins'] as num?)?.toInt() ?? 0,
      losses: (json['losses'] as num?)?.toInt() ?? 0,
      draws: (json['draws'] as num?)?.toInt() ?? 0,
      points: (json['points'] as num?)?.toInt() ?? 0,
      streakCurrent: (json['streakCurrent'] as num?)?.toInt() ?? 0,
      streakBest: (json['streakBest'] as num?)?.toInt() ?? 0,
      sportsmanship: (json['sportsmanship'] as num?)?.toInt() ?? 0,
      spectated: (json['spectated'] as num?)?.toInt() ?? 0,
      winRate: (json['winRate'] as num?)?.toDouble() ?? 0,
      rank: (json['rank'] as num?)?.toInt() ?? 0,
      daysActiveThisWeek:
          (json['daysActiveThisWeek'] as num?)?.toInt() ?? 0,
      favoriteGame: json['favoriteGame'] is Map
          ? GameStat.fromJson(
              Map<String, dynamic>.from(json['favoriteGame'] as Map))
          : null,
      perGame: _list(json['perGame'], GameStat.fromJson),
      badges: _list(json['badges'], BadgeInfo.fromJson),
      recentMatches: _list(json['recentMatches'], RecentMatch.fromJson),
      recentActivity: _list(json['recentActivity'], ActivityEntry.fromJson),
    );
  }
}

/// Per-game stat row on a player profile.
class GameStat {
  const GameStat({
    required this.gameTable,
    required this.name,
    required this.icon,
    this.matches = 0,
    this.wins = 0,
    this.losses = 0,
    this.draws = 0,
  });

  final String gameTable;
  final String name;
  final String icon;
  final int matches;
  final int wins;
  final int losses;
  final int draws;

  factory GameStat.fromJson(Map<String, dynamic> json) {
    return GameStat(
      gameTable: (json['gameTable'] as String?) ?? '',
      name: (json['name'] as String?) ?? 'Game',
      icon: (json['icon'] as String?) ?? '🎮',
      matches: (json['matches'] as num?)?.toInt() ?? 0,
      wins: (json['wins'] as num?)?.toInt() ?? 0,
      losses: (json['losses'] as num?)?.toInt() ?? 0,
      draws: (json['draws'] as num?)?.toInt() ?? 0,
    );
  }
}

class RecentMatch {
  const RecentMatch({
    required this.gameName,
    required this.gameIcon,
    required this.result,
    this.finishedAt,
  });

  final String gameName;
  final String gameIcon;
  final String result;
  final DateTime? finishedAt;

  factory RecentMatch.fromJson(Map<String, dynamic> json) {
    return RecentMatch(
      gameName: (json['gameName'] as String?) ?? 'Game',
      gameIcon: (json['gameIcon'] as String?) ?? '🎮',
      result: (json['result'] as String?) ?? 'played',
      finishedAt: json['finishedAt'] == null
          ? null
          : DateTime.tryParse(json['finishedAt'].toString()),
    );
  }
}

/// Post-match ecosystem result (fn_get_match_ecosystem).
class MatchEcosystemResult {
  const MatchEcosystemResult({
    required this.matchId,
    required this.gameTable,
    required this.gameName,
    required this.gameIcon,
    this.familyId = '',
    this.winners = const [],
    this.playerCount = 0,
    this.durationSeconds = 0,
    this.archived = false,
    this.newBadges = const [],
    this.completedChallenges = const [],
    this.milestones = const [],
    this.players = const [],
  });

  final String matchId;
  final String gameTable;
  final String gameName;
  final String gameIcon;
  final String familyId;
  final List<String> winners;
  final int playerCount;
  final int durationSeconds;
  final bool archived;
  final List<PlayerBadgeRewards> newBadges;
  final List<PlayerChallengeRewards> completedChallenges;
  final List<MilestoneReward> milestones;
  final List<MatchPlayerResult> players;

  bool get hasRewards =>
      newBadges.isNotEmpty ||
      completedChallenges.isNotEmpty ||
      milestones.isNotEmpty;

  factory MatchEcosystemResult.fromJson(Map<String, dynamic> json) {
    return MatchEcosystemResult(
      matchId: (json['matchId'] as String?) ?? '',
      gameTable: (json['gameTable'] as String?) ?? '',
      gameName: (json['gameName'] as String?) ?? 'Game',
      gameIcon: (json['gameIcon'] as String?) ?? '🎮',
      familyId: (json['familyId'] as String?) ?? '',
      winners: (json['winners'] as List? ?? [])
          .map((e) => e.toString())
          .toList(),
      playerCount: (json['playerCount'] as num?)?.toInt() ?? 0,
      durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
      archived: json['archived'] as bool? ?? false,
      newBadges: _list(json['newBadges'], PlayerBadgeRewards.fromJson),
      completedChallenges:
          _list(json['completedChallenges'], PlayerChallengeRewards.fromJson),
      milestones: _list(json['milestones'], MilestoneReward.fromJson),
      players: _list(json['players'], MatchPlayerResult.fromJson),
    );
  }
}

class PlayerBadgeRewards {
  const PlayerBadgeRewards({
    required this.userId,
    required this.userName,
    required this.badges,
  });

  final String userId;
  final String userName;
  final List<BadgeInfo> badges;

  factory PlayerBadgeRewards.fromJson(Map<String, dynamic> json) {
    return PlayerBadgeRewards(
      userId: (json['userId'] as String?) ?? '',
      userName: (json['userName'] as String?) ?? '',
      badges: _list(json['badges'], BadgeInfo.fromJson),
    );
  }
}

class PlayerChallengeRewards {
  const PlayerChallengeRewards({
    required this.userId,
    required this.userName,
    required this.challenges,
  });

  final String userId;
  final String userName;
  final List<ChallengeInfo> challenges;

  factory PlayerChallengeRewards.fromJson(Map<String, dynamic> json) {
    return PlayerChallengeRewards(
      userId: (json['userId'] as String?) ?? '',
      userName: (json['userName'] as String?) ?? '',
      challenges: _list(json['challenges'], ChallengeInfo.fromJson),
    );
  }
}

class MilestoneReward {
  const MilestoneReward({required this.milestone, required this.description});
  final String milestone;
  final String description;

  factory MilestoneReward.fromJson(Map<String, dynamic> json) {
    return MilestoneReward(
      milestone: (json['milestone'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
    );
  }
}

class MatchPlayerResult {
  const MatchPlayerResult({
    required this.userId,
    required this.userName,
    required this.result,
  });

  final String userId;
  final String userName;
  final String result;

  factory MatchPlayerResult.fromJson(Map<String, dynamic> json) {
    return MatchPlayerResult(
      userId: (json['userId'] as String?) ?? '',
      userName: (json['userName'] as String?) ?? '',
      result: (json['result'] as String?) ?? 'played',
    );
  }
}

List<T> _list<T>(Object? raw, T Function(Map<String, dynamic>) fromJson) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((e) => fromJson(Map<String, dynamic>.from(e)))
      .toList();
}

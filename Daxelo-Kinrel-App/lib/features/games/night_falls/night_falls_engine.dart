// lib/features/games/night_falls/night_falls_engine.dart
//
// Night Falls — pure Dart game engine.
//
// Classic Werewolf / social deduction game. 5–12 players. Roles:
// Werewolf (2–3), Seer (1), Doctor (1), Hunter (1), Villager (rest).
// Each round cycles: night (wolves kill, seer investigates, doctor
// protects) → day (announce death + debate) → vote (eliminate one
// player) → result (reveal role, hunter revenge if applicable).
// Werewolves win if they equal/outnumber villagers; villagers win if
// all werewolves are eliminated.
//
// Architecture reuses the hidden-submission pattern from impostor +
// secret_heist: the server (Postgres RPCs) is authoritative for state.
// This engine is used client-side to:
//   • Parse boardState JSON from the server
//   • Compute display labels + colors for the UI
//   • Validate action submissions before sending
//   • Preview role distribution in the lobby
//
// It is NOT used to derive game state — the server does that to keep
// all clients in sync.

import 'dart:math';

// ─────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────

const int kNightFallsMinPlayers = 5;
const int kNightFallsMaxPlayers = 12;
const int kNightFallsDefaultNightSeconds = 30;
const int kNightFallsDefaultDaySeconds = 60;
const int kNightFallsDefaultVoteSeconds = 30;
const int kNightFallsDefaultRoleRevealSeconds = 15;

// ─────────────────────────────────────────────────────────────────────────
// Roles
// ─────────────────────────────────────────────────────────────────────────

enum NightFallsRole {
  villager,
  werewolf,
  seer,
  doctor,
  hunter,
}

extension NightFallsRoleX on NightFallsRole {
  String get wire {
    switch (this) {
      case NightFallsRole.villager:
        return 'villager';
      case NightFallsRole.werewolf:
        return 'werewolf';
      case NightFallsRole.seer:
        return 'seer';
      case NightFallsRole.doctor:
        return 'doctor';
      case NightFallsRole.hunter:
        return 'hunter';
    }
  }

  static NightFallsRole fromString(String? s) {
    switch (s) {
      case 'werewolf':
        return NightFallsRole.werewolf;
      case 'seer':
        return NightFallsRole.seer;
      case 'doctor':
        return NightFallsRole.doctor;
      case 'hunter':
        return NightFallsRole.hunter;
      case 'villager':
      default:
        return NightFallsRole.villager;
    }
  }

  /// User-facing display name.
  String get label {
    switch (this) {
      case NightFallsRole.villager:
        return 'Villager';
      case NightFallsRole.werewolf:
        return 'Werewolf';
      case NightFallsRole.seer:
        return 'Seer';
      case NightFallsRole.doctor:
        return 'Doctor';
      case NightFallsRole.hunter:
        return 'Hunter';
    }
  }

  /// One-line description shown on the role reveal card.
  String get description {
    switch (this) {
      case NightFallsRole.villager:
        return 'You have no special power. Vote wisely during the day to find the werewolves!';
      case NightFallsRole.werewolf:
        return 'Each night, you and your pack choose a victim. Blend in during the day — don\'t get voted out!';
      case NightFallsRole.seer:
        return 'Each night, investigate one player to learn if they are a werewolf. Guide the village without revealing yourself too early.';
      case NightFallsRole.doctor:
        return 'Each night, protect one player from the werewolves. You can protect yourself, but not the same person twice in a row... (house rule: we allow it!)';
      case NightFallsRole.hunter:
        return 'If you are voted out, you take one player down with you. Choose wisely!';
    }
  }

  /// Emoji glyph for the role.
  String get glyph {
    switch (this) {
      case NightFallsRole.villager:
        return '👨‍🌾';
      case NightFallsRole.werewolf:
        return '🐺';
      case NightFallsRole.seer:
        return '🔮';
      case NightFallsRole.doctor:
        return '💊';
      case NightFallsRole.hunter:
        return '🎯';
    }
  }

  /// True if this role is on the werewolf team.
  bool get isWolf => this == NightFallsRole.werewolf;

  /// True if this role has a night action.
  bool get hasNightAction =>
      this == NightFallsRole.werewolf ||
      this == NightFallsRole.seer ||
      this == NightFallsRole.doctor;
}

// ─────────────────────────────────────────────────────────────────────────
// Phases
// ─────────────────────────────────────────────────────────────────────────

enum NightFallsPhase {
  roleReveal, // players see their role
  night,      // wolves/seer/doctor submit actions
  day,        // announce night results + debate
  vote,       // village votes to eliminate
  result,     // vote result revealed (+ hunter revenge)
  finished,   // game over
}

extension NightFallsPhaseX on NightFallsPhase {
  String get wire {
    switch (this) {
      case NightFallsPhase.roleReveal:
        return 'role_reveal';
      case NightFallsPhase.night:
        return 'night';
      case NightFallsPhase.day:
        return 'day';
      case NightFallsPhase.vote:
        return 'vote';
      case NightFallsPhase.result:
        return 'result';
      case NightFallsPhase.finished:
        return 'finished';
    }
  }

  static NightFallsPhase fromString(String? s) {
    switch (s) {
      case 'night':
        return NightFallsPhase.night;
      case 'day':
        return NightFallsPhase.day;
      case 'vote':
        return NightFallsPhase.vote;
      case 'result':
        return NightFallsPhase.result;
      case 'finished':
        return NightFallsPhase.finished;
      case 'role_reveal':
      default:
        return NightFallsPhase.roleReveal;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Night action types
// ─────────────────────────────────────────────────────────────────────────

enum NightFallsActionType {
  wolfKill,
  seerInvestigate,
  doctorProtect,
  vote,
  hunterRevenge,
}

extension NightFallsActionTypeX on NightFallsActionType {
  String get wire {
    switch (this) {
      case NightFallsActionType.wolfKill:
        return 'wolf_kill';
      case NightFallsActionType.seerInvestigate:
        return 'seer_investigate';
      case NightFallsActionType.doctorProtect:
        return 'doctor_protect';
      case NightFallsActionType.vote:
        return 'vote';
      case NightFallsActionType.hunterRevenge:
        return 'hunter_revenge';
    }
  }

  static NightFallsActionType fromString(String? s) {
    switch (s) {
      case 'wolf_kill':
        return NightFallsActionType.wolfKill;
      case 'seer_investigate':
        return NightFallsActionType.seerInvestigate;
      case 'doctor_protect':
        return NightFallsActionType.doctorProtect;
      case 'hunter_revenge':
        return NightFallsActionType.hunterRevenge;
      case 'vote':
      default:
        return NightFallsActionType.vote;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Winning team
// ─────────────────────────────────────────────────────────────────────────

enum NightFallsTeam { village, wolves }

extension NightFallsTeamX on NightFallsTeam {
  String get wire => this == NightFallsTeam.wolves ? 'wolves' : 'village';

  static NightFallsTeam? fromString(String? s) {
    switch (s) {
      case 'wolves':
        return NightFallsTeam.wolves;
      case 'village':
        return NightFallsTeam.village;
      default:
        return null;
    }
  }

  String get label => this == NightFallsTeam.wolves ? 'Werewolves' : 'Village';

  String get glyph => this == NightFallsTeam.wolves ? '🐺' : '🏘️';
}

// ─────────────────────────────────────────────────────────────────────────
// Player — a player row inside the boardState JSON
// ─────────────────────────────────────────────────────────────────────────

class NightFallsPlayer {
  const NightFallsPlayer({
    required this.idx,
    required this.userId,
    required this.name,
    required this.isAlive,
    this.role,
    this.votedFor,
  });

  final int idx;
  final String userId;
  final String name;
  final bool isAlive;
  /// Role — only populated for the caller (via fn_nightfalls_my_role) or
  /// for everyone at game end (via boardState.roles). Null otherwise.
  final NightFallsRole? role;
  /// UserId this player voted for in the current vote phase (if any).
  final String? votedFor;

  NightFallsPlayer copyWith({
    bool? isAlive,
    NightFallsRole? role,
    String? votedFor,
  }) =>
      NightFallsPlayer(
        idx: idx,
        userId: userId,
        name: name,
        isAlive: isAlive ?? this.isAlive,
        role: role ?? this.role,
        votedFor: votedFor ?? this.votedFor,
      );

  Map<String, dynamic> toJson() => {
        'idx': idx,
        'userId': userId,
        'name': name,
        'isAlive': isAlive,
      };

  factory NightFallsPlayer.fromJson(Map<String, dynamic> json) =>
      NightFallsPlayer(
        idx: (json['idx'] as num?)?.toInt() ?? 0,
        userId: (json['userId'] ?? '') as String,
        name: (json['name'] ?? 'Player') as String,
        isAlive: (json['isAlive'] as bool?) ?? true,
      );
}

// ─────────────────────────────────────────────────────────────────────────
// Night actions — resolved night-phase results stored in boardState
// ─────────────────────────────────────────────────────────────────────────

class NightFallsNightActions {
  const NightFallsNightActions({
    required this.lockedCount,
    this.killedUserId,
    this.killedUserName,
    required this.noKill,
  });

  final int lockedCount;
  final String? killedUserId;
  final String? killedUserName;
  final bool noKill;

  Map<String, dynamic> toJson() => {
        'lockedCount': lockedCount,
        'killedUserId': killedUserId,
        'killedUserName': killedUserName,
        'noKill': noKill,
      };

  factory NightFallsNightActions.fromJson(Map<String, dynamic> json) =>
      NightFallsNightActions(
        lockedCount: (json['lockedCount'] as num?)?.toInt() ?? 0,
        killedUserId: json['killedUserId'] as String?,
        killedUserName: json['killedUserName'] as String?,
        noKill: (json['noKill'] as bool?) ?? false,
      );
}

// ─────────────────────────────────────────────────────────────────────────
// Day vote — a single vote cast during the vote phase
// ─────────────────────────────────────────────────────────────────────────

class NightFallsVote {
  const NightFallsVote({
    required this.voterUserId,
    required this.targetUserId,
  });

  final String voterUserId;
  final String targetUserId;

  Map<String, dynamic> toJson() => {
        'voter': voterUserId,
        'target': targetUserId,
      };

  factory NightFallsVote.fromJson(Map<String, dynamic> json) =>
      NightFallsVote(
        voterUserId: (json['voter'] ?? '') as String,
        targetUserId: (json['target'] ?? '') as String,
      );
}

// ─────────────────────────────────────────────────────────────────────────
// Round — one round of the game (night → day → vote → result)
// ─────────────────────────────────────────────────────────────────────────

class NightFallsRound {
  const NightFallsRound({
    required this.roundNumber,
    required this.phase,
    required this.nightActions,
    required this.dayVotes,
    required this.voteLockedCount,
    this.eliminatedUserId,
    this.eliminatedUserName,
    this.eliminatedRole,
    required this.hunterRevengePending,
    this.hunterRevengeTargetId,
    this.hunterRevengeTargetName,
    this.hunterRevengeRole,
  });

  final int roundNumber;
  final NightFallsPhase phase;
  final NightFallsNightActions nightActions;
  final List<NightFallsVote> dayVotes;
  final int voteLockedCount;
  final String? eliminatedUserId;
  final String? eliminatedUserName;
  final NightFallsRole? eliminatedRole;
  final bool hunterRevengePending;
  final String? hunterRevengeTargetId;
  final String? hunterRevengeTargetName;
  final NightFallsRole? hunterRevengeRole;

  Map<String, dynamic> toJson() => {
        'roundNumber': roundNumber,
        'phase': phase.wire,
        'nightActions': nightActions.toJson(),
        'dayVotes': dayVotes.map((v) => v.toJson()).toList(),
        'voteLockedCount': voteLockedCount,
        'eliminatedUserId': eliminatedUserId,
        'eliminatedUserName': eliminatedUserName,
        'eliminatedRole': eliminatedRole?.wire,
        'hunterRevengePending': hunterRevengePending,
        'hunterRevengeTargetId': hunterRevengeTargetId,
        'hunterRevengeTargetName': hunterRevengeTargetName,
        'hunterRevengeRole': hunterRevengeRole?.wire,
      };

  factory NightFallsRound.fromJson(Map<String, dynamic> json) {
    final votesList = <NightFallsVote>[];
    final rawVotes = json['dayVotes'];
    if (rawVotes is List) {
      for (final v in rawVotes) {
        if (v is Map) {
          votesList.add(
              NightFallsVote.fromJson(Map<String, dynamic>.from(v)));
        }
      }
    }
    return NightFallsRound(
      roundNumber: (json['roundNumber'] as num?)?.toInt() ?? 1,
      phase: NightFallsPhaseX.fromString(json['phase'] as String?),
      nightActions: NightFallsNightActions.fromJson(
          Map<String, dynamic>.from(json['nightActions'] as Map? ?? {})),
      dayVotes: votesList,
      voteLockedCount: (json['voteLockedCount'] as num?)?.toInt() ?? 0,
      eliminatedUserId: json['eliminatedUserId'] as String?,
      eliminatedUserName: json['eliminatedUserName'] as String?,
      eliminatedRole:
          NightFallsRoleX.fromString(json['eliminatedRole'] as String?),
      hunterRevengePending:
          (json['hunterRevengePending'] as bool?) ?? false,
      hunterRevengeTargetId: json['hunterRevengeTargetId'] as String?,
      hunterRevengeTargetName:
          json['hunterRevengeTargetName'] as String?,
      hunterRevengeRole:
          NightFallsRoleX.fromString(json['hunterRevengeRole'] as String?),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Board state — the full serializable state of a match
// ─────────────────────────────────────────────────────────────────────────

class NightFallsBoardState {
  const NightFallsBoardState({
    required this.playerCount,
    required this.nightSeconds,
    required this.daySeconds,
    required this.voteSeconds,
    required this.roleRevealSeconds,
    required this.currentRoundNumber,
    required this.rounds,
    required this.players,
    required this.status,
    this.winnerTeam,
    required this.rolesRevealed,
    required this.roles,
  });

  final int playerCount;
  final int nightSeconds;
  final int daySeconds;
  final int voteSeconds;
  final int roleRevealSeconds;
  final int currentRoundNumber;
  final List<NightFallsRound> rounds;
  final List<NightFallsPlayer> players;
  final String status; // 'in_progress' | 'completed'
  final NightFallsTeam? winnerTeam;
  final bool rolesRevealed;
  /// userId → role. Only populated when rolesRevealed is true (game end).
  final Map<String, NightFallsRole> roles;

  NightFallsRound? get currentRound =>
      rounds.isNotEmpty && currentRoundNumber <= rounds.length
          ? rounds[currentRoundNumber - 1]
          : null;

  bool get isFinished => status == 'completed';

  /// Look up a player by userId.
  NightFallsPlayer? playerFor(String? userId) {
    if (userId == null) return null;
    for (final p in players) {
      if (p.userId == userId) return p;
    }
    return null;
  }

  /// Count alive players on each team.
  int aliveWolves(List<NightFallsRole> knownRoles) {
    var count = 0;
    for (final p in players) {
      if (!p.isAlive) continue;
      final role = roles[p.userId] ?? (knownRoles.firstWhere(
        (r) => false,
        orElse: () => NightFallsRole.villager,
      ));
      if (role == NightFallsRole.werewolf) count++;
    }
    return count;
  }

  /// Number of alive players.
  int get aliveCount => players.where((p) => p.isAlive).length;

  Map<String, dynamic> toJson() => {
        'playerCount': playerCount,
        'nightSeconds': nightSeconds,
        'daySeconds': daySeconds,
        'voteSeconds': voteSeconds,
        'roleRevealSeconds': roleRevealSeconds,
        'currentRoundNumber': currentRoundNumber,
        'rounds': rounds.map((r) => r.toJson()).toList(),
        'players': players.map((p) => p.toJson()).toList(),
        'status': status,
        'winnerTeam': winnerTeam?.wire,
        'rolesRevealed': rolesRevealed,
        'roles': roles.map((k, v) => MapEntry(k, v.wire)),
      };

  factory NightFallsBoardState.fromJson(Map<String, dynamic> json) {
    final roundsList = <NightFallsRound>[];
    final rawRounds = json['rounds'];
    if (rawRounds is List) {
      for (final r in rawRounds) {
        if (r is Map) {
          roundsList.add(
              NightFallsRound.fromJson(Map<String, dynamic>.from(r)));
        }
      }
    }
    final playersList = <NightFallsPlayer>[];
    final rawPlayers = json['players'];
    if (rawPlayers is List) {
      for (final p in rawPlayers) {
        if (p is Map) {
          playersList.add(
              NightFallsPlayer.fromJson(Map<String, dynamic>.from(p)));
        }
      }
    }
    final rolesMap = <String, NightFallsRole>{};
    final rawRoles = json['roles'];
    if (rawRoles is Map) {
      rawRoles.forEach((k, v) {
        rolesMap[k.toString()] = NightFallsRoleX.fromString(v.toString());
      });
    }
    return NightFallsBoardState(
      playerCount: (json['playerCount'] as num?)?.toInt() ??
          kNightFallsMinPlayers,
      nightSeconds: (json['nightSeconds'] as num?)?.toInt() ??
          kNightFallsDefaultNightSeconds,
      daySeconds: (json['daySeconds'] as num?)?.toInt() ??
          kNightFallsDefaultDaySeconds,
      voteSeconds: (json['voteSeconds'] as num?)?.toInt() ??
          kNightFallsDefaultVoteSeconds,
      roleRevealSeconds: (json['roleRevealSeconds'] as num?)?.toInt() ??
          kNightFallsDefaultRoleRevealSeconds,
      currentRoundNumber:
          (json['currentRoundNumber'] as num?)?.toInt() ?? 1,
      rounds: roundsList,
      players: playersList,
      status: (json['status'] as String?) ?? 'in_progress',
      winnerTeam: NightFallsTeamX.fromString(json['winnerTeam'] as String?),
      rolesRevealed: (json['rolesRevealed'] as bool?) ?? false,
      roles: rolesMap,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// The engine — pure functions for role assignment + display helpers
// ─────────────────────────────────────────────────────────────────────────

class NightFallsEngine {
  NightFallsEngine._();

  /// Number of werewolves for a given player count.
  /// 5–8 players → 2 wolves; 9–12 players → 3 wolves.
  static int wolfCountFor(int playerCount) {
    return playerCount >= 9 ? 3 : 2;
  }

  /// Assign roles for `playerCount` players. Returns a list of roles
  /// (length = playerCount), shuffled randomly. Used for preview in the
  /// lobby and for client-side validation.
  static List<NightFallsRole> assignRoles(int playerCount, {Random? rng}) {
    assert(playerCount >= kNightFallsMinPlayers &&
        playerCount <= kNightFallsMaxPlayers);
    final r = rng ?? Random();
    final roles = <NightFallsRole>[];
    final wolves = wolfCountFor(playerCount);
    for (var i = 0; i < wolves; i++) {
      roles.add(NightFallsRole.werewolf);
    }
    roles.add(NightFallsRole.seer);
    roles.add(NightFallsRole.doctor);
    roles.add(NightFallsRole.hunter);
    final villagers = playerCount - wolves - 3;
    for (var i = 0; i < villagers; i++) {
      roles.add(NightFallsRole.villager);
    }
    // Fisher–Yates shuffle
    for (var i = roles.length - 1; i > 0; i--) {
      final j = r.nextInt(i + 1);
      final tmp = roles[i];
      roles[i] = roles[j];
      roles[j] = tmp;
    }
    return roles;
  }

  /// Role distribution summary for a given player count.
  /// Returns a map of role → count, used by the lobby preview.
  static Map<NightFallsRole, int> roleDistribution(int playerCount) {
    final wolves = wolfCountFor(playerCount);
    return {
      NightFallsRole.werewolf: wolves,
      NightFallsRole.seer: 1,
      NightFallsRole.doctor: 1,
      NightFallsRole.hunter: 1,
      NightFallsRole.villager: playerCount - wolves - 3,
    };
  }

  /// Expected number of night-action locks (wolves + seer + doctor).
  static int expectedNightLocks(int playerCount) {
    return wolfCountFor(playerCount) + 2; // wolves + seer + doctor
  }

  /// Validate a night action target. Returns null if valid, error string
  /// otherwise. Mirrors the server-side validation in
  /// fn_nightfalls_submit_night_action.
  static String? validateNightAction({
    required NightFallsRole myRole,
    required NightFallsActionType action,
    required String targetUserId,
    required String myUserId,
    required bool targetAlive,
  }) {
    if (action == NightFallsActionType.wolfKill &&
        myRole != NightFallsRole.werewolf) {
      return 'Only werewolves can kill';
    }
    if (action == NightFallsActionType.seerInvestigate &&
        myRole != NightFallsRole.seer) {
      return 'Only the seer can investigate';
    }
    if (action == NightFallsActionType.doctorProtect &&
        myRole != NightFallsRole.doctor) {
      return 'Only the doctor can protect';
    }
    if (!targetAlive) return 'Target is already eliminated';
    if (action == NightFallsActionType.wolfKill &&
        targetUserId == myUserId) {
      return 'You can\'t kill yourself';
    }
    return null;
  }

  /// Validate a vote. Returns null if valid, error string otherwise.
  static String? validateVote({
    required String targetUserId,
    required String myUserId,
    required bool myAlive,
    required bool targetAlive,
  }) {
    if (!myAlive) return 'Eliminated players can\'t vote';
    if (!targetAlive) return 'Target is already eliminated';
    if (targetUserId == myUserId) return 'You can\'t vote for yourself';
    return null;
  }

  /// Compute the alive-count win condition client-side (for display).
  /// Returns the winning team, or null if the game should continue.
  static NightFallsTeam? checkWinCondition(
      List<NightFallsPlayer> players, Map<String, NightFallsRole> roles) {
    var aliveWolves = 0;
    var aliveVillagers = 0;
    for (final p in players) {
      if (!p.isAlive) continue;
      final role = roles[p.userId];
      if (role == NightFallsRole.werewolf) {
        aliveWolves++;
      } else {
        aliveVillagers++;
      }
    }
    if (aliveWolves == 0) return NightFallsTeam.village;
    if (aliveWolves >= aliveVillagers) return NightFallsTeam.wolves;
    return null;
  }
}

// lib/features/games/secret_heist/secret_heist_engine.dart
//
// Secret Heist — pure Dart game engine.
//
// Hidden-role / social deduction heist game. 3–8 players. Each round,
// every player secretly chooses an action (Steal, Protect, Spy, Trap,
// Hack). After all players lock, the resolution engine determines
// outcomes: successful steals, blocked steals (protect/trap), hack
// results (double/backfire/alarm). After N rounds the player with the
// most coins wins.
//
// Architecture reuses the proven pattern from One Night Ultimate
// Werewolf / Avalon-style hidden-role games:
//   • Per-player secret actions stored separately from public state
//   • Round phase machine: choosing → resolving → revealing → next
//   • Aggregate counters visible during choosing (X/N locked) without
//     revealing who locked
//   • Full reveal only after all players lock OR the turn timer expires
//
// The server (Postgres RPCs) is authoritative for state. This engine is
// used client-side to:
//   • Build initial board representations
//   • Parse boardState JSON from the server
//   • Compute display labels + colors for the UI
//   • Validate action selections before submitting
//
// It is NOT used to derive game state — the server does that to keep
// all clients in sync.

const int kSecretHeistMinPlayers = 3;
const int kSecretHeistMaxPlayers = 8;
const int kSecretHeistDefaultActionSeconds = 30;
const int kSecretHeistMinSteal = 10;
const int kSecretHeistMaxSteal = 50;
const int kSecretHeistProtectAmount = 30;
const int kSecretHeistTrapPenalty = 10;

/// The actions a player can choose each round.
enum HeistAction {
  steal,         // Take coins from the vault
  protect,       // Protect part of the vault (blocks steals)
  spy,           // Reveal info about another player
  trap,          // Set a trap that catches stealers
  hack,          // High-risk double-or-nothing steal
  doubleSteal,   // Chaos mode: stronger hack variant
  alarmBait,     // Chaos mode: trigger alarm or gain coins
}

extension HeistActionX on HeistAction {
  String get wire {
    switch (this) {
      case HeistAction.steal: return 'steal';
      case HeistAction.protect: return 'protect';
      case HeistAction.spy: return 'spy';
      case HeistAction.trap: return 'trap';
      case HeistAction.hack: return 'hack';
      case HeistAction.doubleSteal: return 'double_steal';
      case HeistAction.alarmBait: return 'alarm_bait';
    }
  }

  static HeistAction fromString(String? s) {
    switch (s) {
      case 'protect': return HeistAction.protect;
      case 'spy': return HeistAction.spy;
      case 'trap': return HeistAction.trap;
      case 'hack': return HeistAction.hack;
      case 'double_steal': return HeistAction.doubleSteal;
      case 'alarm_bait': return HeistAction.alarmBait;
      case 'steal':
      default:
        return HeistAction.steal;
    }
  }

  /// User-facing display name.
  String get label {
    switch (this) {
      case HeistAction.steal: return 'Steal';
      case HeistAction.protect: return 'Protect';
      case HeistAction.spy: return 'Spy';
      case HeistAction.trap: return 'Trap';
      case HeistAction.hack: return 'Hack';
      case HeistAction.doubleSteal: return 'Double Steal';
      case HeistAction.alarmBait: return 'Alarm Bait';
    }
  }

  /// One-line description shown on the action selection card.
  String get description {
    switch (this) {
      case HeistAction.steal:
        return 'Take coins from the vault.';
      case HeistAction.protect:
        return 'Shield $kSecretHeistProtectAmount coins from steals.';
      case HeistAction.spy:
        return 'Peek at one player\'s last-round action.';
      case HeistAction.trap:
        return 'Catch a thief — they lose $kSecretHeistTrapPenalty coins.';
      case HeistAction.hack:
        return 'High risk: double steal, backfire, or trigger alarm.';
      case HeistAction.doubleSteal:
        return 'Chaos: stronger hack — 65% success rate.';
      case HeistAction.alarmBait:
        return 'Chaos: trigger alarm or earn 15 coins.';
    }
  }

  /// Whether the action needs an amount input.
  bool get requiresAmount {
    switch (this) {
      case HeistAction.steal:
      case HeistAction.hack:
      case HeistAction.doubleSteal:
        return true;
      case HeistAction.protect:
      case HeistAction.spy:
      case HeistAction.trap:
      case HeistAction.alarmBait:
        return false;
    }
  }

  /// Returns true if this action is only available in Chaos Mode.
  bool get isChaosOnly {
    switch (this) {
      case HeistAction.doubleSteal:
      case HeistAction.alarmBait:
        return true;
      case HeistAction.steal:
      case HeistAction.protect:
      case HeistAction.spy:
      case HeistAction.trap:
      case HeistAction.hack:
        return false;
    }
  }

  /// Premium accent color (hex) for the action's UI affordances.
  int get accentArgb {
    switch (this) {
      case HeistAction.steal: return 0xFF10B981; // emerald
      case HeistAction.protect: return 0xFF3B82F6; // blue
      case HeistAction.spy: return 0xFFA855F7; // purple
      case HeistAction.trap: return 0xFFEF4444; // red
      case HeistAction.hack: return 0xFFF59E0B; // amber
      case HeistAction.doubleSteal: return 0xFFE11D48; // crimson
      case HeistAction.alarmBait: return 0xFF06B6D4; // cyan
    }
  }

  /// Icon for the action's UI affordance.
  String get glyph {
    switch (this) {
      case HeistAction.steal: return '💰';
      case HeistAction.protect: return '🛡';
      case HeistAction.spy: return '🔍';
      case HeistAction.trap: return '🪤';
      case HeistAction.hack: return '⚡';
      case HeistAction.doubleSteal: return '🔥';
      case HeistAction.alarmBait: return '🚨';
    }
  }
}

/// Round phase — drives the UI state machine.
enum HeistPhase {
  choosing,    // players secretly select actions
  resolving,   // server is computing outcomes (transient)
  revealing,   // outcomes are shown
  finished,    // match over
}

extension HeistPhaseX on HeistPhase {
  String get wire {
    switch (this) {
      case HeistPhase.choosing: return 'choosing';
      case HeistPhase.resolving: return 'resolving';
      case HeistPhase.revealing: return 'revealing';
      case HeistPhase.finished: return 'finished';
    }
  }

  static HeistPhase fromString(String? s) {
    switch (s) {
      case 'resolving': return HeistPhase.resolving;
      case 'revealing': return HeistPhase.revealing;
      case 'finished': return HeistPhase.finished;
      case 'choosing':
      default:
        return HeistPhase.choosing;
    }
  }
}

/// Suspicion level — derived from the player's historical suspicion counter.
enum SuspicionLevel { low, medium, high }

extension SuspicionLevelX on SuspicionLevel {
  String get label {
    switch (this) {
      case SuspicionLevel.low: return 'Low';
      case SuspicionLevel.medium: return 'Medium';
      case SuspicionLevel.high: return 'High';
    }
  }

  int get accentArgb {
    switch (this) {
      case SuspicionLevel.low: return 0xFF10B981;
      case SuspicionLevel.medium: return 0xFFF59E0B;
      case SuspicionLevel.high: return 0xFFEF4444;
    }
  }

  static SuspicionLevel fromScore(int score) {
    if (score >= 4) return SuspicionLevel.high;
    if (score >= 2) return SuspicionLevel.medium;
    return SuspicionLevel.low;
  }
}

/// A player row inside the boardState JSON.
class HeistPlayer {
  const HeistPlayer({
    required this.idx,
    required this.userId,
    required this.name,
    required this.coins,
    required this.suspicion,
    this.missesNextRound = false,
  });

  final int idx;
  final String userId;
  final String name;
  final int coins;
  final int suspicion;
  final bool missesNextRound;

  SuspicionLevel get suspicionLevel => SuspicionLevelX.fromScore(suspicion);

  HeistPlayer copyWith({
    int? coins,
    int? suspicion,
    bool? missesNextRound,
  }) =>
      HeistPlayer(
        idx: idx,
        userId: userId,
        name: name,
        coins: coins ?? this.coins,
        suspicion: suspicion ?? this.suspicion,
        missesNextRound: missesNextRound ?? this.missesNextRound,
      );

  Map<String, dynamic> toJson() => {
        'idx': idx,
        'userId': userId,
        'name': name,
        'coins': coins,
        'suspicion': suspicion,
        'missesNextRound': missesNextRound,
      };

  factory HeistPlayer.fromJson(Map<String, dynamic> json) => HeistPlayer(
        idx: (json['idx'] as num?)?.toInt() ?? 0,
        userId: (json['userId'] ?? '') as String,
        name: (json['name'] ?? 'Player') as String,
        coins: (json['coins'] as num?)?.toInt() ?? 0,
        suspicion: (json['suspicion'] as num?)?.toInt() ?? 0,
        missesNextRound: (json['missesNextRound'] as bool?) ?? false,
      );
}

/// One resolved event inside a round's events list.
class HeistEvent {
  const HeistEvent({
    required this.type,
    this.userId,
    this.amount,
    this.penalty,
  });

  final String type; // steal_success, steal_blocked, trap_triggered, hack_success, hack_backfire, alarm_triggered, spy_used
  final String? userId;
  final int? amount;
  final int? penalty;

  Map<String, dynamic> toJson() => {
        'type': type,
        if (userId != null) 'userId': userId,
        if (amount != null) 'amount': amount,
        if (penalty != null) 'penalty': penalty,
      };

  factory HeistEvent.fromJson(Map<String, dynamic> json) => HeistEvent(
        type: (json['type'] ?? '') as String,
        userId: json['userId'] as String?,
        amount: (json['amount'] as num?)?.toInt(),
        penalty: (json['penalty'] as num?)?.toInt(),
      );

  /// Human-readable description.
  String get description {
    switch (type) {
      case 'steal_success':
        return 'Stole $amount coins from the vault';
      case 'steal_blocked':
        return 'Steal blocked by Protect';
      case 'trap_triggered':
        return 'Trap triggered — thief loses $penalty coins';
      case 'hack_success':
        return 'Hack succeeded — $amount coins stolen';
      case 'hack_backfire':
        return 'Hack backfired — lost $amount coins';
      case 'alarm_triggered':
        return 'Alarm triggered — vault locked';
      case 'spy_used':
        return 'Spy gathered intel';
      default:
        return type;
    }
  }
}

/// One revealed action (post-resolution). The userId is the player who
/// took the action, the outcome describes what happened.
class RevealedAction {
  const RevealedAction({
    required this.userId,
    required this.action,
    this.amount,
    required this.outcome,
  });

  final String userId;
  final String action; // wire form: 'steal', 'protect', etc.
  final int? amount;
  final String outcome; // 'success', 'blocked', 'trapped', 'backfire', 'alarm', 'active', 'set', 'intel_gathered', 'bait_success', 'alarm_blocked'

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'action': action,
        if (amount != null) 'amount': amount,
        'outcome': outcome,
      };

  factory RevealedAction.fromJson(Map<String, dynamic> json) => RevealedAction(
        userId: (json['userId'] ?? '') as String,
        action: (json['action'] ?? '') as String,
        amount: (json['amount'] as num?)?.toInt(),
        outcome: (json['outcome'] ?? '') as String,
      );

  HeistAction? get parsedAction => HeistActionX.fromString(action);
}

/// One round's snapshot.
class HeistRound {
  const HeistRound({
    required this.roundNumber,
    required this.phase,
    required this.lockedCount,
    required this.vaultLost,
    required this.stealsSuccessful,
    required this.stealsBlocked,
    required this.trapsTriggered,
    required this.hacksSucceeded,
    required this.hacksBackfired,
    required this.alarmsTriggered,
    required this.events,
    required this.revealedActions,
  });

  final int roundNumber;
  final HeistPhase phase;
  final int lockedCount;
  final int vaultLost;
  final int stealsSuccessful;
  final int stealsBlocked;
  final int trapsTriggered;
  final int hacksSucceeded;
  final int hacksBackfired;
  final int alarmsTriggered;
  final List<HeistEvent> events;
  final List<RevealedAction> revealedActions;

  Map<String, dynamic> toJson() => {
        'roundNumber': roundNumber,
        'phase': phase.wire,
        'lockedCount': lockedCount,
        'vaultLost': vaultLost,
        'stealsSuccessful': stealsSuccessful,
        'stealsBlocked': stealsBlocked,
        'trapsTriggered': trapsTriggered,
        'hacksSucceeded': hacksSucceeded,
        'hacksBackfired': hacksBackfired,
        'alarmsTriggered': alarmsTriggered,
        'events': events.map((e) => e.toJson()).toList(),
        'revealedActions': revealedActions.map((a) => a.toJson()).toList(),
      };

  factory HeistRound.fromJson(Map<String, dynamic> json) {
    final eventsList = <HeistEvent>[];
    final rawEvents = json['events'];
    if (rawEvents is List) {
      for (final e in rawEvents) {
        if (e is Map) {
          eventsList
              .add(HeistEvent.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    final revealedList = <RevealedAction>[];
    final rawRevealed = json['revealedActions'];
    if (rawRevealed is List) {
      for (final a in rawRevealed) {
        if (a is Map) {
          revealedList
              .add(RevealedAction.fromJson(Map<String, dynamic>.from(a)));
        }
      }
    }
    return HeistRound(
      roundNumber: (json['roundNumber'] as num?)?.toInt() ?? 1,
      phase: HeistPhaseX.fromString(json['phase'] as String?),
      lockedCount: (json['lockedCount'] as num?)?.toInt() ?? 0,
      vaultLost: (json['vaultLost'] as num?)?.toInt() ?? 0,
      stealsSuccessful:
          (json['stealsSuccessful'] as num?)?.toInt() ?? 0,
      stealsBlocked: (json['stealsBlocked'] as num?)?.toInt() ?? 0,
      trapsTriggered: (json['trapsTriggered'] as num?)?.toInt() ?? 0,
      hacksSucceeded: (json['hacksSucceeded'] as num?)?.toInt() ?? 0,
      hacksBackfired: (json['hacksBackfired'] as num?)?.toInt() ?? 0,
      alarmsTriggered: (json['alarmsTriggered'] as num?)?.toInt() ?? 0,
      events: eventsList,
      revealedActions: revealedList,
    );
  }
}

/// The full boardState JSONB from the games row, parsed.
class HeistBoardState {
  const HeistBoardState({
    required this.playerCount,
    required this.totalRounds,
    required this.startingCoins,
    required this.vaultSize,
    required this.vaultCoins,
    required this.chaosMode,
    required this.actionSeconds,
    required this.currentRoundNumber,
    required this.rounds,
    required this.players,
    required this.status,
    required this.winnerIndex,
  });

  final int playerCount;
  final int totalRounds;
  final int startingCoins;
  final int vaultSize;
  final int vaultCoins;
  final bool chaosMode;
  final int actionSeconds;
  final int currentRoundNumber;
  final List<HeistRound> rounds;
  final List<HeistPlayer> players;
  final String status;
  final int winnerIndex;

  HeistRound? get currentRound =>
      rounds.isNotEmpty && currentRoundNumber <= rounds.length
          ? rounds[currentRoundNumber - 1]
          : null;

  bool get isFinished => status == 'completed';

  /// The vault depletion percentage (0..100).
  int get vaultDepletionPercent {
    if (vaultSize <= 0) return 0;
    final depleted = vaultSize - vaultCoins;
    return ((depleted / vaultSize) * 100).round().clamp(0, 100);
  }

  /// The vault remaining percentage (0..100).
  int get vaultRemainingPercent => 100 - vaultDepletionPercent;

  /// The player with the most coins (or null if tied).
  HeistPlayer? get leader {
    if (players.isEmpty) return null;
    final sorted = List<HeistPlayer>.from(players)
      ..sort((a, b) => b.coins.compareTo(a.coins));
    if (sorted.length >= 2 && sorted[0].coins == sorted[1].coins) {
      return null; // tie
    }
    return sorted.first;
  }

  Map<String, dynamic> toJson() => {
        'playerCount': playerCount,
        'totalRounds': totalRounds,
        'startingCoins': startingCoins,
        'vaultSize': vaultSize,
        'vaultCoins': vaultCoins,
        'chaosMode': chaosMode,
        'actionSeconds': actionSeconds,
        'currentRound': currentRoundNumber,
        'rounds': rounds.map((r) => r.toJson()).toList(),
        'players': players.map((p) => p.toJson()).toList(),
        'status': status,
        'winner': winnerIndex,
      };

  factory HeistBoardState.fromJson(Map<String, dynamic> json) {
    final roundsList = <HeistRound>[];
    final rawRounds = json['rounds'];
    if (rawRounds is List) {
      for (final r in rawRounds) {
        if (r is Map) {
          roundsList
              .add(HeistRound.fromJson(Map<String, dynamic>.from(r)));
        }
      }
    }
    final playersList = <HeistPlayer>[];
    final rawPlayers = json['players'];
    if (rawPlayers is List) {
      for (final p in rawPlayers) {
        if (p is Map) {
          playersList
              .add(HeistPlayer.fromJson(Map<String, dynamic>.from(p)));
        }
      }
    }
    return HeistBoardState(
      playerCount: (json['playerCount'] as num?)?.toInt() ?? 3,
      totalRounds: (json['totalRounds'] as num?)?.toInt() ?? 5,
      startingCoins: (json['startingCoins'] as num?)?.toInt() ?? 100,
      vaultSize: (json['vaultSize'] as num?)?.toInt() ?? 500,
      vaultCoins: (json['vaultCoins'] as num?)?.toInt() ?? 500,
      chaosMode: (json['chaosMode'] as bool?) ?? false,
      actionSeconds: (json['actionSeconds'] as num?)?.toInt() ??
          kSecretHeistDefaultActionSeconds,
      currentRoundNumber: (json['currentRound'] as num?)?.toInt() ?? 1,
      rounds: roundsList,
      players: playersList,
      status: (json['status'] as String?) ?? 'in_progress',
      winnerIndex: (json['winner'] as num?)?.toInt() ?? -1,
    );
  }
}

/// Pure-Dart engine — client-side validation helpers + display logic.
///
/// The server is authoritative for state transitions; this class only
/// provides validation + presentation helpers that the UI needs.
class SecretHeistEngine {
  SecretHeistEngine._();

  /// Validate an action selection. Returns null if valid, error string
  /// otherwise.
  static String? validateAction({
    required HeistAction action,
    required int amount,
    required int playerCoins,
    required bool chaosMode,
  }) {
    if (action.isChaosOnly && !chaosMode) {
      return 'This action is only available in Chaos Mode';
    }
    if (action.requiresAmount) {
      if (amount < kSecretHeistMinSteal) {
        return 'Minimum is $kSecretHeistMinSteal coins';
      }
      if (amount > kSecretHeistMaxSteal) {
        return 'Maximum is $kSecretHeistMaxSteal coins';
      }
      if (action == HeistAction.hack && amount > playerCoins) {
        return 'Hack could backfire — keep enough coins to cover';
      }
    }
    return null;
  }

  /// The list of actions available to the player in this match.
  static List<HeistAction> availableActions(bool chaosMode) {
    final actions = <HeistAction>[
      HeistAction.steal,
      HeistAction.protect,
      HeistAction.spy,
      HeistAction.trap,
      HeistAction.hack,
    ];
    if (chaosMode) {
      actions.addAll([HeistAction.doubleSteal, HeistAction.alarmBait]);
    }
    return actions;
  }

  /// Compute the "best shot" — the largest single steal/hack success
  /// across all rounds. Used in the final-reveal stats panel.
  static int bestShot(List<HeistRound> rounds) {
    var best = 0;
    for (final round in rounds) {
      for (final event in round.events) {
        if (event.type == 'steal_success' ||
            event.type == 'hack_success') {
          if ((event.amount ?? 0) > best) best = event.amount!;
        }
      }
    }
    return best;
  }

  /// Total coins stolen across all rounds.
  static int totalStolen(List<HeistRound> rounds) {
    var total = 0;
    for (final round in rounds) {
      total += round.vaultLost;
    }
    return total;
  }
}

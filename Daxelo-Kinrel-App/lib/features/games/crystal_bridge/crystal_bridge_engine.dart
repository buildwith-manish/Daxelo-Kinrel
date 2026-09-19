// lib/features/games/crystal_bridge/crystal_bridge_engine.dart
//
// Crystal Bridge — pure Dart game engine.
//
// Turn-based bridge-crossing survival game. 2–8 players. Each row of the
// bridge has two crystals (left + right). Only one is safe. Players take
// turns picking which crystal to step on. Wrong choice = elimination.
// Last survivor — or first to reach the end — wins.
//
// Bridge types: crystal (standard), ice (slide chance), lava (stun
// nearby), shadow (safe hidden), storm (random lightning).
// Powers: reveal, shield, leap, swap, scanner.
// Team modes: solo, 2v2, 3v3, 4v4.
//
// Architecture reuses the RPC-driven pattern from mind_match /
// secret_heist / impostor: the server (Postgres RPCs) is authoritative
// for state. This engine is used client-side to:
//   • Parse boardState JSON from the server
//   • Compute display labels + colors for the UI
//   • Validate choose / use-power submissions before sending
//
// Scoring / win conditions (matches the SQL in fn_crystalbridge_choose
// and fn_crystalbridge_advance_turn):
//   • Safe step → advance one row, +1 crystalsCrossed
//   • Wrong step → eliminated (unless shieldActive — then the shield
//     is consumed and the player stays on the current row)
//   • Reach totalRows → finish_reached win (solo) or team win
//   • Solo + only one alive → last_survivor win
//   • Solo + all dead → all_eliminated draw
//   • Timer expiry → current player auto-eliminated (timeout event)

const int kCrystalBridgeMinPlayers = 2;
const int kCrystalBridgeMaxPlayers = 8;
const int kCrystalBridgeDefaultTurnSeconds = 20;

/// The five bridge types — each adds a small twist to the standard
/// "two crystals, one safe" loop.
enum CrystalBridgeType { crystal, ice, lava, shadow, storm }

extension CrystalBridgeTypeX on CrystalBridgeType {
  String get wire {
    switch (this) {
      case CrystalBridgeType.crystal:
        return 'crystal';
      case CrystalBridgeType.ice:
        return 'ice';
      case CrystalBridgeType.lava:
        return 'lava';
      case CrystalBridgeType.shadow:
        return 'shadow';
      case CrystalBridgeType.storm:
        return 'storm';
    }
  }

  static CrystalBridgeType fromString(String? s) {
    switch (s) {
      case 'ice':
        return CrystalBridgeType.ice;
      case 'lava':
        return CrystalBridgeType.lava;
      case 'shadow':
        return CrystalBridgeType.shadow;
      case 'storm':
        return CrystalBridgeType.storm;
      case 'crystal':
      default:
        return CrystalBridgeType.crystal;
    }
  }

  String get label {
    switch (this) {
      case CrystalBridgeType.crystal:
        return 'Crystal Bridge';
      case CrystalBridgeType.ice:
        return 'Ice Bridge';
      case CrystalBridgeType.lava:
        return 'Lava Bridge';
      case CrystalBridgeType.shadow:
        return 'Shadow Bridge';
      case CrystalBridgeType.storm:
        return 'Storm Bridge';
    }
  }

  String get description {
    switch (this) {
      case CrystalBridgeType.crystal:
        return 'Standard. One safe crystal per row, pure luck + power play.';
      case CrystalBridgeType.ice:
        return 'Slippery — even safe steps may slide you off (25% chance).';
      case CrystalBridgeType.lava:
        return 'Hot — a wrong step stuns nearby alive players (30%).';
      case CrystalBridgeType.shadow:
        return 'Hidden — the safe side is masked by drifting shadows.';
      case CrystalBridgeType.storm:
        return 'Charged — lightning may strike even on safe rows (15%).';
    }
  }

  /// Premium accent color (hex) for the bridge type's UI affordances.
  int get accentArgb {
    switch (this) {
      case CrystalBridgeType.crystal:
        return 0xFF06B6D4; // cyan — the canonical Crystal Bridge accent
      case CrystalBridgeType.ice:
        return 0xFF38BDF8; // sky blue
      case CrystalBridgeType.lava:
        return 0xFFF97316; // orange
      case CrystalBridgeType.shadow:
        return 0xFF8B5CF6; // violet
      case CrystalBridgeType.storm:
        return 0xFFA78BFA; // lavender
    }
  }
}

/// Row phase — drives the UI state machine.
enum CrystalBridgePhase {
  choosing,   // current player picks left/right
  completed,  // match over (last survivor / finish reached / draw)
}

extension CrystalBridgePhaseX on CrystalBridgePhase {
  String get wire {
    switch (this) {
      case CrystalBridgePhase.choosing:
        return 'choosing';
      case CrystalBridgePhase.completed:
        return 'completed';
    }
  }

  static CrystalBridgePhase fromString(String? s) {
    switch (s) {
      case 'completed':
        return CrystalBridgePhase.completed;
      case 'choosing':
      default:
        return CrystalBridgePhase.choosing;
    }
  }
}

/// The five one-use powers assigned randomly at match start.
enum CrystalBridgePower { reveal, shield, leap, swap, scanner }

extension CrystalBridgePowerX on CrystalBridgePower {
  String get wire {
    switch (this) {
      case CrystalBridgePower.reveal:
        return 'reveal';
      case CrystalBridgePower.shield:
        return 'shield';
      case CrystalBridgePower.leap:
        return 'leap';
      case CrystalBridgePower.swap:
        return 'swap';
      case CrystalBridgePower.scanner:
        return 'scanner';
    }
  }

  static CrystalBridgePower fromString(String? s) {
    switch (s) {
      case 'shield':
        return CrystalBridgePower.shield;
      case 'leap':
        return CrystalBridgePower.leap;
      case 'swap':
        return CrystalBridgePower.swap;
      case 'scanner':
        return CrystalBridgePower.scanner;
      case 'reveal':
      default:
        return CrystalBridgePower.reveal;
    }
  }

  String get label {
    switch (this) {
      case CrystalBridgePower.reveal:
        return 'Reveal';
      case CrystalBridgePower.shield:
        return 'Shield';
      case CrystalBridgePower.leap:
        return 'Leap';
      case CrystalBridgePower.swap:
        return 'Swap';
      case CrystalBridgePower.scanner:
        return 'Scanner';
    }
  }

  String get description {
    switch (this) {
      case CrystalBridgePower.reveal:
        return 'Reveal the safe side of the current row.';
      case CrystalBridgePower.shield:
        return 'Survive one wrong step — the shield is consumed instead.';
      case CrystalBridgePower.leap:
        return 'Skip the current row — auto-advance one crystal.';
      case CrystalBridgePower.swap:
        return 'Swap turn order — pass to the next player immediately.';
      case CrystalBridgePower.scanner:
        return 'Reveal the safe side of the next 2 rows.';
    }
  }

  String get glyph {
    switch (this) {
      case CrystalBridgePower.reveal:
        return '👁️';
      case CrystalBridgePower.shield:
        return '🛡️';
      case CrystalBridgePower.leap:
        return '🦘';
      case CrystalBridgePower.swap:
        return '🔄';
      case CrystalBridgePower.scanner:
        return '📡';
    }
  }
}

/// Team modes — solo + three team-vs-team variants.
enum CrystalBridgeTeamMode { solo, twoVTwo, threeVThree, fourVFour }

extension CrystalBridgeTeamModeX on CrystalBridgeTeamMode {
  String get wire {
    switch (this) {
      case CrystalBridgeTeamMode.solo:
        return 'solo';
      case CrystalBridgeTeamMode.twoVTwo:
        return '2v2';
      case CrystalBridgeTeamMode.threeVThree:
        return '3v3';
      case CrystalBridgeTeamMode.fourVFour:
        return '4v4';
    }
  }

  static CrystalBridgeTeamMode fromString(String? s) {
    switch (s) {
      case '2v2':
        return CrystalBridgeTeamMode.twoVTwo;
      case '3v3':
        return CrystalBridgeTeamMode.threeVThree;
      case '4v4':
        return CrystalBridgeTeamMode.fourVFour;
      case 'solo':
      default:
        return CrystalBridgeTeamMode.solo;
    }
  }

  String get label {
    switch (this) {
      case CrystalBridgeTeamMode.solo:
        return 'Solo';
      case CrystalBridgeTeamMode.twoVTwo:
        return '2 v 2';
      case CrystalBridgeTeamMode.threeVThree:
        return '3 v 3';
      case CrystalBridgeTeamMode.fourVFour:
        return '4 v 4';
    }
  }

  /// Number of teams the mode splits players into. Solo = 1.
  int get teamCount {
    switch (this) {
      case CrystalBridgeTeamMode.solo:
        return 1;
      case CrystalBridgeTeamMode.twoVTwo:
        return 2;
      case CrystalBridgeTeamMode.threeVThree:
        return 3;
      case CrystalBridgeTeamMode.fourVFour:
        return 4;
    }
  }
}

/// A row inside the bridge — one of two sides is safe.
class CrystalBridgeRow {
  const CrystalBridgeRow({
    required this.rowNumber,
    required this.safeSide,
    required this.revealed,
    required this.leftBroke,
    required this.rightBroke,
  });

  /// 1-based row number (row 1 is the first stepping row).
  final int rowNumber;

  /// 0 = left is safe, 1 = right is safe.
  final int safeSide;

  /// True once the safe side has been revealed (via step or power).
  final bool revealed;

  /// True if the left crystal shattered (wrong step or post-step reveal).
  final bool leftBroke;

  /// True if the right crystal shattered (wrong step or post-step reveal).
  final bool rightBroke;

  CrystalBridgeRow copyWith({
    bool? revealed,
    bool? leftBroke,
    bool? rightBroke,
  }) =>
      CrystalBridgeRow(
        rowNumber: rowNumber,
        safeSide: safeSide,
        revealed: revealed ?? this.revealed,
        leftBroke: leftBroke ?? this.leftBroke,
        rightBroke: rightBroke ?? this.rightBroke,
      );

  Map<String, dynamic> toJson() => {
        'rowNumber': rowNumber,
        'safeSide': safeSide,
        'revealed': revealed,
        'leftBroke': leftBroke,
        'rightBroke': rightBroke,
      };

  factory CrystalBridgeRow.fromJson(Map<String, dynamic> json) =>
      CrystalBridgeRow(
        rowNumber: (json['rowNumber'] as num?)?.toInt() ?? 1,
        safeSide: (json['safeSide'] as num?)?.toInt() ?? 0,
        revealed: (json['revealed'] as bool?) ?? false,
        leftBroke: (json['leftBroke'] as bool?) ?? false,
        rightBroke: (json['rightBroke'] as bool?) ?? false,
      );
}

/// A player row inside the boardState JSON.
class CrystalBridgePlayer {
  const CrystalBridgePlayer({
    required this.idx,
    required this.userId,
    required this.name,
    required this.position,
    required this.isAlive,
    required this.power,
    required this.powerUsed,
    required this.shieldActive,
    required this.isStunned,
    required this.crystalsCrossed,
  });

  final int idx;
  final String userId;
  final String name;

  /// How many rows the player has crossed (0 = not yet started).
  final int position;
  final bool isAlive;

  /// The one-use power assigned at match start.
  final CrystalBridgePower power;
  final bool powerUsed;

  /// True between shield-activation and the next wrong step.
  final bool shieldActive;

  /// True if stunned (skipped next turn) by lava or storm effects.
  final bool isStunned;

  /// Number of safe crystals crossed so far.
  final int crystalsCrossed;

  CrystalBridgePlayer copyWith({
    int? position,
    bool? isAlive,
    CrystalBridgePower? power,
    bool? powerUsed,
    bool? shieldActive,
    bool? isStunned,
    int? crystalsCrossed,
  }) =>
      CrystalBridgePlayer(
        idx: idx,
        userId: userId,
        name: name,
        position: position ?? this.position,
        isAlive: isAlive ?? this.isAlive,
        power: power ?? this.power,
        powerUsed: powerUsed ?? this.powerUsed,
        shieldActive: shieldActive ?? this.shieldActive,
        isStunned: isStunned ?? this.isStunned,
        crystalsCrossed: crystalsCrossed ?? this.crystalsCrossed,
      );

  Map<String, dynamic> toJson() => {
        'idx': idx,
        'userId': userId,
        'name': name,
        'position': position,
        'isAlive': isAlive,
        'power': power.wire,
        'powerUsed': powerUsed,
        'shieldActive': shieldActive,
        'isStunned': isStunned,
        'crystalsCrossed': crystalsCrossed,
      };

  factory CrystalBridgePlayer.fromJson(Map<String, dynamic> json) =>
      CrystalBridgePlayer(
        idx: (json['idx'] as num?)?.toInt() ?? 0,
        userId: (json['userId'] ?? '') as String,
        name: (json['name'] ?? 'Player') as String,
        position: (json['position'] as num?)?.toInt() ?? 0,
        isAlive: (json['isAlive'] as bool?) ?? true,
        power: CrystalBridgePowerX.fromString(json['power'] as String?),
        powerUsed: (json['powerUsed'] as bool?) ?? false,
        shieldActive: (json['shieldActive'] as bool?) ?? false,
        isStunned: (json['isStunned'] as bool?) ?? false,
        crystalsCrossed:
            (json['crystalsCrossed'] as num?)?.toInt() ?? 0,
      );
}

/// One event in the scrolling event log.
class CrystalBridgeEvent {
  const CrystalBridgeEvent({
    required this.type,
    required this.playerIdx,
    this.row,
    this.side,
    this.atMs,
  });

  /// Event types emitted by the SQL: safe, eliminated, shield_saved,
  /// ice_slide, lava_stun, storm_strike, power_reveal, power_shield,
  /// power_leap, power_scanner, power_swap, timeout.
  final String type;
  final int playerIdx;
  final int? row;
  final int? side;
  final int? atMs;

  Map<String, dynamic> toJson() => {
        'type': type,
        'playerIdx': playerIdx,
        if (row != null) 'row': row,
        if (side != null) 'side': side,
        if (atMs != null) 'atMs': atMs,
      };

  factory CrystalBridgeEvent.fromJson(Map<String, dynamic> json) =>
      CrystalBridgeEvent(
        type: (json['type'] ?? '') as String,
        playerIdx: (json['playerIdx'] as num?)?.toInt() ?? 0,
        row: (json['row'] as num?)?.toInt(),
        side: (json['side'] as num?)?.toInt(),
        atMs: (json['atMs'] as num?)?.toInt(),
      );

  /// Human-readable summary used by the events log.
  String summaryFor(String playerName) {
    switch (type) {
      case 'safe':
        return '$playerName stepped safely (row ${row ?? '?'})';
      case 'eliminated':
        return '$playerName shattered a crystal — eliminated (row ${row ?? '?'})';
      case 'shield_saved':
        return "$playerName's shield absorbed the fall!";
      case 'ice_slide':
        return '$playerName slipped on the ice!';
      case 'lava_stun':
        return '$playerName was stunned by a lava burst!';
      case 'storm_strike':
        return 'Lightning struck row ${row ?? '?'}!';
      case 'power_reveal':
        return '$playerName used Reveal on row ${row ?? '?'}';
      case 'power_shield':
        return '$playerName activated Shield';
      case 'power_leap':
        return '$playerName leapt over row ${row ?? '?'}';
      case 'power_scanner':
        return '$playerName used Scanner — next 2 rows revealed';
      case 'power_swap':
        return '$playerName used Swap — turn order shifted';
      case 'timeout':
        return '$playerName ran out of time — eliminated';
      default:
        return '$playerName: $type';
    }
  }
}

/// The full boardState JSONB from the games row, parsed.
class CrystalBridgeBoardState {
  const CrystalBridgeBoardState({
    required this.playerCount,
    required this.bridgeType,
    required this.totalRows,
    required this.teamMode,
    required this.turnSeconds,
    required this.currentPlayerIdx,
    required this.currentRow,
    required this.phase,
    required this.rows,
    required this.players,
    required this.events,
    required this.status,
    required this.winnerIdx,
    required this.winningTeam,
    required this.matchStartTime,
  });

  final int playerCount;
  final CrystalBridgeType bridgeType;
  final int totalRows;
  final CrystalBridgeTeamMode teamMode;
  final int turnSeconds;
  final int currentPlayerIdx;
  final int currentRow;
  final CrystalBridgePhase phase;
  final List<CrystalBridgeRow> rows;
  final List<CrystalBridgePlayer> players;
  final List<CrystalBridgeEvent> events;
  final String status;

  /// -1 if no winner yet. In solo, the index of the surviving/finishing
  /// player. In team modes, the same index is used to derive the
  /// winning team via [winningTeam].
  final int winnerIdx;

  /// -1 in solo. Otherwise 1..teamCount.
  final int winningTeam;

  /// Epoch milliseconds when the match started (server-side).
  final int matchStartTime;

  CrystalBridgePlayer? get currentPlayer =>
      players.isNotEmpty && currentPlayerIdx < players.length
          ? players[currentPlayerIdx]
          : null;

  CrystalBridgeRow? get currentRowObj =>
      rows.isNotEmpty && currentRow >= 1 && currentRow <= rows.length
          ? rows[currentRow - 1]
          : null;

  bool get isFinished => status == 'completed' || phase == CrystalBridgePhase.completed;

  int get aliveCount =>
      players.where((p) => p.isAlive).length;

  /// True if at least one player has reached the final row.
  bool get anyFinished =>
      players.any((p) => p.crystalsCrossed >= totalRows);

  /// Highest crystals-crossed across all players.
  int get maxCrystalsCrossed =>
      players.fold<int>(0, (a, p) => p.crystalsCrossed > a ? p.crystalsCrossed : a);

  /// The last `events` entry (top of the scrolling log), or null.
  CrystalBridgeEvent? get lastEvent =>
      events.isNotEmpty ? events.last : null;

  Map<String, dynamic> toJson() => {
        'playerCount': playerCount,
        'bridgeType': bridgeType.wire,
        'totalRows': totalRows,
        'teamMode': teamMode.wire,
        'turnSeconds': turnSeconds,
        'currentPlayerIdx': currentPlayerIdx,
        'currentRow': currentRow,
        'phase': phase.wire,
        'rows': rows.map((r) => r.toJson()).toList(),
        'players': players.map((p) => p.toJson()).toList(),
        'events': events.map((e) => e.toJson()).toList(),
        'status': status,
        'winnerIdx': winnerIdx,
        'winningTeam': winningTeam,
        'matchStartTime': matchStartTime,
      };

  factory CrystalBridgeBoardState.fromJson(Map<String, dynamic> json) {
    final rowsList = <CrystalBridgeRow>[];
    final rawRows = json['rows'];
    if (rawRows is List) {
      for (final r in rawRows) {
        if (r is Map) {
          rowsList.add(
              CrystalBridgeRow.fromJson(Map<String, dynamic>.from(r)));
        }
      }
    }
    final playersList = <CrystalBridgePlayer>[];
    final rawPlayers = json['players'];
    if (rawPlayers is List) {
      for (final p in rawPlayers) {
        if (p is Map) {
          playersList.add(
              CrystalBridgePlayer.fromJson(Map<String, dynamic>.from(p)));
        }
      }
    }
    final eventsList = <CrystalBridgeEvent>[];
    final rawEvents = json['events'];
    if (rawEvents is List) {
      for (final e in rawEvents) {
        if (e is Map) {
          eventsList.add(
              CrystalBridgeEvent.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    return CrystalBridgeBoardState(
      playerCount: (json['playerCount'] as num?)?.toInt() ?? 2,
      bridgeType:
          CrystalBridgeTypeX.fromString(json['bridgeType'] as String?),
      totalRows: (json['totalRows'] as num?)?.toInt() ?? 20,
      teamMode:
          CrystalBridgeTeamModeX.fromString(json['teamMode'] as String?),
      turnSeconds: (json['turnSeconds'] as num?)?.toInt() ??
          kCrystalBridgeDefaultTurnSeconds,
      currentPlayerIdx:
          (json['currentPlayerIdx'] as num?)?.toInt() ?? 0,
      currentRow: (json['currentRow'] as num?)?.toInt() ?? 1,
      phase: CrystalBridgePhaseX.fromString(json['phase'] as String?),
      rows: rowsList,
      players: playersList,
      events: eventsList,
      status: (json['status'] as String?) ?? 'in_progress',
      winnerIdx: (json['winnerIdx'] as num?)?.toInt() ?? -1,
      winningTeam: (json['winningTeam'] as num?)?.toInt() ?? -1,
      matchStartTime: (json['matchStartTime'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Pure-Dart engine — client-side validation + display helpers.
class CrystalBridgeEngine {
  CrystalBridgeEngine._();

  /// Validate a `choose` side. Returns null if valid, error string otherwise.
  /// 0 = left, 1 = right.
  static String? validateSide(int side) {
    if (side < 0 || side > 1) return 'Invalid side';
    return null;
  }

  /// True if the local user is the current player and may act.
  static bool isLocalTurn(
          CrystalBridgeBoardState? board, String? myUserId) =>
      board != null &&
      board.phase == CrystalBridgePhase.choosing &&
      board.currentPlayer?.userId == myUserId;

  /// Available match-length presets (rows).
  static const List<int> matchLengthPresets = [10, 20, 30];

  /// Available turn-timer presets (seconds).
  static const List<int> turnTimerPresets = [15, 20, 30];

  /// All five bridge types, in display order.
  static const List<CrystalBridgeType> allBridgeTypes = [
    CrystalBridgeType.crystal,
    CrystalBridgeType.ice,
    CrystalBridgeType.lava,
    CrystalBridgeType.shadow,
    CrystalBridgeType.storm,
  ];

  /// All four team modes, in display order.
  static const List<CrystalBridgeTeamMode> allTeamModes = [
    CrystalBridgeTeamMode.solo,
    CrystalBridgeTeamMode.twoVTwo,
    CrystalBridgeTeamMode.threeVThree,
    CrystalBridgeTeamMode.fourVFour,
  ];

  /// Side label for a wire value (0 / 1 / null).
  static String sideLabel(int? side) {
    switch (side) {
      case 0:
        return 'Left';
      case 1:
        return 'Right';
      default:
        return '—';
    }
  }

  /// Survival rate across all players (alive / total).
  static double survivalRate(CrystalBridgeBoardState board) {
    if (board.playerCount == 0) return 0;
    return board.aliveCount / board.playerCount;
  }

  /// Longest current run of safe steps by any single player.
  static int longestRun(CrystalBridgeBoardState board) =>
      board.maxCrystalsCrossed;

  /// Team number for a player index in a team mode (1..teamCount), or
  /// 1 in solo. Mirrors the SQL CASE in fn_crystalbridge_choose.
  static int teamForIndex(int idx, CrystalBridgeTeamMode mode) {
    if (mode == CrystalBridgeTeamMode.solo) return 1;
    final mod = mode.teamCount;
    return (idx % mod) + 1;
  }
}

// lib/features/games/color_trap/color_trap_engine.dart
//
// Color Trap — pure Dart game engine.
//
// Last-player-standing game on a colored tile grid. Each round: a target
// color is announced, players have a countdown to move onto a tile of
// that color, then all other tiles disappear — players on wrong colors
// are eliminated. Arena regenerates and repeats until one remains.
//
// This engine is completely separated from UI. It exposes:
//   • generateArena()       — create a new randomized grid
//   • announceColor()       — pick the target color for this round
//   • startCountdown()      — begin the elimination countdown
//   • eliminatePlayers()    — remove players on wrong tiles
//   • advanceRound()        — regenerate arena, next round
//   • getRemainingPlayers() — list of alive players
//   • getWinner()           — null until 1 player remains
//   • restartMatch()        — reset for a new match

import 'dart:math';

// ─────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────

const int kColorTrapMinPlayers = 2;
const int kColorTrapMaxPlayers = 8;

enum ColorTrapDifficulty {
  easy,    // 4 colors, large tiles (6×6), 5s countdown
  medium,  // 5 colors, medium tiles (8×8), 4s countdown
  hard,    // 6 colors, small tiles (10×10), 3s countdown
  expert,  // 8 colors, fast countdown (12×12), 2s countdown
}

extension ColorTrapDifficultyX on ColorTrapDifficulty {
  String get wire => name;
  static ColorTrapDifficulty fromString(String? s) {
    switch (s) {
      case 'medium': return ColorTrapDifficulty.medium;
      case 'hard': return ColorTrapDifficulty.hard;
      case 'expert': return ColorTrapDifficulty.expert;
      default: return ColorTrapDifficulty.easy;
    }
  }
  String get label => name[0].toUpperCase() + name.substring(1);
  int get arenaSize => switch (this) {
    ColorTrapDifficulty.easy => 6,
    ColorTrapDifficulty.medium => 8,
    ColorTrapDifficulty.hard => 10,
    ColorTrapDifficulty.expert => 12,
  };
  int get colorCount => switch (this) {
    ColorTrapDifficulty.easy => 4,
    ColorTrapDifficulty.medium => 5,
    ColorTrapDifficulty.hard => 6,
    ColorTrapDifficulty.expert => 8,
  };
  int get countdownSeconds => switch (this) {
    ColorTrapDifficulty.easy => 5,
    ColorTrapDifficulty.medium => 4,
    ColorTrapDifficulty.hard => 3,
    ColorTrapDifficulty.expert => 2,
  };
}

/// The 8 possible tile colors.
enum ColorTrapTileColor {
  red, blue, green, yellow, purple, orange, cyan, pink
}

extension ColorTrapTileColorX on ColorTrapTileColor {
  String get wire => name;
  static ColorTrapTileColor fromString(String? s) {
    switch (s) {
      case 'blue': return ColorTrapTileColor.blue;
      case 'green': return ColorTrapTileColor.green;
      case 'yellow': return ColorTrapTileColor.yellow;
      case 'purple': return ColorTrapTileColor.purple;
      case 'orange': return ColorTrapTileColor.orange;
      case 'cyan': return ColorTrapTileColor.cyan;
      case 'pink': return ColorTrapTileColor.pink;
      default: return ColorTrapTileColor.red;
    }
  }
  /// ARGB int for Flutter Color.
  int get argb => switch (this) {
    ColorTrapTileColor.red => 0xFFEF4444,
    ColorTrapTileColor.blue => 0xFF3B82F6,
    ColorTrapTileColor.green => 0xFF22C55E,
    ColorTrapTileColor.yellow => 0xFFEAB308,
    ColorTrapTileColor.purple => 0xFF8B5CF6,
    ColorTrapTileColor.orange => 0xFFF59E0B,
    ColorTrapTileColor.cyan => 0xFF06B6D4,
    ColorTrapTileColor.pink => 0xFFEC4899,
  };
}

// ─────────────────────────────────────────────────────────────────────────
// Tile — one cell of the arena
// ─────────────────────────────────────────────────────────────────────────

class ColorTrapTile {
  ColorTrapTile({
    required this.row,
    required this.col,
    required this.color,
    this.isVisible = true,
  });
  final int row;
  final int col;
  ColorTrapTileColor color;
  bool isVisible;

  Map<String, dynamic> toJson() => {
    'r': row, 'c': col, 'color': color.wire, 'v': isVisible,
  };
  factory ColorTrapTile.fromJson(Map<String, dynamic> json) => ColorTrapTile(
    row: (json['r'] as num?)?.toInt() ?? 0,
    col: (json['c'] as num?)?.toInt() ?? 0,
    color: ColorTrapTileColorX.fromString(json['color'] as String?),
    isVisible: (json['v'] as bool?) ?? true,
  );
}

// ─────────────────────────────────────────────────────────────────────────
// Player — one player in the match
// ─────────────────────────────────────────────────────────────────────────

class ColorTrapPlayer {
  ColorTrapPlayer({
    required this.playerIndex,
    required this.userId,
    required this.userName,
    this.row = 0,
    this.col = 0,
    this.isAlive = true,
    this.eliminatedRound = -1,
  });
  final int playerIndex;
  final String userId;
  final String userName;
  int row;
  int col;
  bool isAlive;
  int eliminatedRound;

  Map<String, dynamic> toJson() => {
    'idx': playerIndex, 'userId': userId, 'name': userName,
    'r': row, 'c': col, 'alive': isAlive, 'elim': eliminatedRound,
  };
  factory ColorTrapPlayer.fromJson(Map<String, dynamic> json) => ColorTrapPlayer(
    playerIndex: (json['idx'] as num?)?.toInt() ?? 0,
    userId: (json['userId'] ?? '') as String,
    userName: (json['name'] ?? 'Player') as String,
    row: (json['r'] as num?)?.toInt() ?? 0,
    col: (json['c'] as num?)?.toInt() ?? 0,
    isAlive: (json['alive'] as bool?) ?? true,
    eliminatedRound: (json['elim'] as num?)?.toInt() ?? -1,
  );

  ColorTrapPlayer copy() => ColorTrapPlayer(
    playerIndex: playerIndex, userId: userId, userName: userName,
    row: row, col: col, isAlive: isAlive, eliminatedRound: eliminatedRound,
  );
}

// ─────────────────────────────────────────────────────────────────────────
// Round — one round of the game
// ─────────────────────────────────────────────────────────────────────────

enum ColorTrapPhase {
  arenaShown,    // arena displayed, players can move
  colorAnnounced, // target color revealed, countdown starts
  countdown,     // countdown running
  elimination,   // tiles disappearing, players eliminated
  roundEnd,      // round over, show results briefly
}

extension ColorTrapPhaseX on ColorTrapPhase {
  String get wire => name;
  static ColorTrapPhase fromString(String? s) {
    return ColorTrapPhase.values.firstWhere(
      (v) => v.wire == s,
      orElse: () => ColorTrapPhase.arenaShown,
    );
  }
}

class ColorTrapRound {
  ColorTrapRound({
    required this.roundNumber,
    required this.targetColor,
    required this.tiles,
    required this.arenaSize,
  });
  final int roundNumber;
  ColorTrapTileColor targetColor;
  List<ColorTrapTile> tiles;
  final int arenaSize;
  ColorTrapPhase phase = ColorTrapPhase.arenaShown;
  int countdownRemaining = 0;

  Map<String, dynamic> toJson() => {
    'round': roundNumber, 'target': targetColor.wire,
    'tiles': tiles.map((t) => t.toJson()).toList(),
    'size': arenaSize, 'phase': phase.wire, 'countdown': countdownRemaining,
  };
  factory ColorTrapRound.fromJson(Map<String, dynamic> json) {
    final tilesList = <ColorTrapTile>[];
    final rawTiles = json['tiles'];
    if (rawTiles is List) {
      for (final t in rawTiles) {
        if (t is Map) tilesList.add(ColorTrapTile.fromJson(Map<String, dynamic>.from(t)));
      }
    }
    final round = ColorTrapRound(
      roundNumber: (json['round'] as num?)?.toInt() ?? 1,
      targetColor: ColorTrapTileColorX.fromString(json['target'] as String?),
      tiles: tilesList,
      arenaSize: (json['size'] as num?)?.toInt() ?? 6,
    );
    round.phase = ColorTrapPhaseX.fromString(json['phase'] as String?);
    round.countdownRemaining = (json['countdown'] as num?)?.toInt() ?? 0;
    return round;
  }

  ColorTrapRound copy() {
    final r = ColorTrapRound(
      roundNumber: roundNumber, targetColor: targetColor,
      tiles: tiles.map((t) => ColorTrapTile(row: t.row, col: t.col, color: t.color, isVisible: t.isVisible)).toList(),
      arenaSize: arenaSize,
    );
    r.phase = phase;
    r.countdownRemaining = countdownRemaining;
    return r;
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Game state — the full serializable state of a match
// ─────────────────────────────────────────────────────────────────────────

class ColorTrapGameState {
  ColorTrapGameState({
    required this.playerCount,
    required this.difficulty,
    required this.currentRoundNumber,
    required this.rounds,
    required this.players,
    required this.status,
    this.winnerPlayerIndex = -1,
  });

  int playerCount;
  ColorTrapDifficulty difficulty;
  int currentRoundNumber;
  List<ColorTrapRound> rounds;
  List<ColorTrapPlayer> players;
  String status; // 'in_progress' | 'completed'
  int winnerPlayerIndex;

  ColorTrapRound? get currentRound =>
      rounds.isNotEmpty && currentRoundNumber <= rounds.length
          ? rounds[currentRoundNumber - 1] : null;

  bool get isFinished => status == 'completed';
  List<ColorTrapPlayer> get alivePlayers => players.where((p) => p.isAlive).toList();
  int get aliveCount => alivePlayers.length;

  Map<String, dynamic> toJson() => {
    'playerCount': playerCount, 'difficulty': difficulty.wire,
    'currentRound': currentRoundNumber,
    'rounds': rounds.map((r) => r.toJson()).toList(),
    'players': players.map((p) => p.toJson()).toList(),
    'status': status, 'winner': winnerPlayerIndex,
  };

  factory ColorTrapGameState.fromJson(Map<String, dynamic> json) {
    final roundsList = <ColorTrapRound>[];
    final rawRounds = json['rounds'];
    if (rawRounds is List) {
      for (final r in rawRounds) {
        if (r is Map) roundsList.add(ColorTrapRound.fromJson(Map<String, dynamic>.from(r)));
      }
    }
    final playersList = <ColorTrapPlayer>[];
    final rawPlayers = json['players'];
    if (rawPlayers is List) {
      for (final p in rawPlayers) {
        if (p is Map) playersList.add(ColorTrapPlayer.fromJson(Map<String, dynamic>.from(p)));
      }
    }
    return ColorTrapGameState(
      playerCount: (json['playerCount'] as num?)?.toInt() ?? 2,
      difficulty: ColorTrapDifficultyX.fromString(json['difficulty'] as String?),
      currentRoundNumber: (json['currentRound'] as num?)?.toInt() ?? 1,
      rounds: roundsList, players: playersList,
      status: (json['status'] as String?) ?? 'in_progress',
      winnerPlayerIndex: (json['winner'] as num?)?.toInt() ?? -1,
    );
  }

  ColorTrapGameState copy() => ColorTrapGameState(
    playerCount: playerCount, difficulty: difficulty,
    currentRoundNumber: currentRoundNumber,
    rounds: rounds.map((r) => r.copy()).toList(),
    players: players.map((p) => p.copy()).toList(),
    status: status, winnerPlayerIndex: winnerPlayerIndex,
  );
}

// ─────────────────────────────────────────────────────────────────────────
// The engine — pure functions on ColorTrapGameState
// ─────────────────────────────────────────────────────────────────────────

class ColorTrapEngine {
  ColorTrapEngine._();

  /// Create a fresh game state.
  static ColorTrapGameState createGame({
    required int playerCount,
    required ColorTrapDifficulty difficulty,
    required List<(String userId, String userName)> playerInfo,
    Random? rng,
  }) {
    assert(playerCount >= kColorTrapMinPlayers && playerCount <= kColorTrapMaxPlayers);
    final r = rng ?? Random();
    final players = <ColorTrapPlayer>[];
    for (var i = 0; i < playerCount; i++) {
      // Place players at spread-out positions on the arena
      final row = (i ~/ 2) * (difficulty.arenaSize ~/ ((playerCount + 1) ~/ 2)).clamp(1, difficulty.arenaSize - 1);
      final col = (i % 2) * (difficulty.arenaSize - 1);
      players.add(ColorTrapPlayer(
        playerIndex: i,
        userId: playerInfo[i].$1,
        userName: playerInfo[i].$2,
        row: row.clamp(0, difficulty.arenaSize - 1),
        col: col.clamp(0, difficulty.arenaSize - 1),
      ));
    }

    final state = ColorTrapGameState(
      playerCount: playerCount,
      difficulty: difficulty,
      currentRoundNumber: 1,
      rounds: [],
      players: players,
      status: 'in_progress',
    );

    // Generate first round
    _generateRound(state, r);
    return state;
  }

  /// Generate a new arena + target color for the current round.
  static void _generateRound(ColorTrapGameState state, Random rng) {
    final size = state.difficulty.arenaSize;
    final colorCount = state.difficulty.colorCount;
    final availableColors = ColorTrapTileColor.values.take(colorCount).toList();

    // Generate the grid
    final tiles = <ColorTrapTile>[];
    for (var r = 0; r < size; r++) {
      for (var c = 0; c < size; c++) {
        tiles.add(ColorTrapTile(
          row: r, col: c,
          color: availableColors[rng.nextInt(availableColors.length)],
        ));
      }
    }

    // Pick target color — ensure at least ~30% of tiles are the target
    // so the game is always playable.
    var targetColor = availableColors[rng.nextInt(availableColors.length)];
    final targetCount = tiles.where((t) => t.color == targetColor).length;
    final minSafe = (size * size * 0.3).round();
    if (targetCount < minSafe) {
      // Reassign some tiles to the target color
      var needed = minSafe - targetCount;
      final nonTargetTiles = tiles.where((t) => t.color != targetColor).toList()..shuffle(rng);
      for (var i = 0; i < needed && i < nonTargetTiles.length; i++) {
        nonTargetTiles[i].color = targetColor;
      }
    }

    state.rounds.add(ColorTrapRound(
      roundNumber: state.currentRoundNumber,
      targetColor: targetColor,
      tiles: tiles,
      arenaSize: size,
    ));
  }

  /// Announce the target color for the current round (transition to colorAnnounced phase).
  static ColorTrapGameState announceColor(ColorTrapGameState state) {
    final round = state.currentRound;
    if (round == null || round.phase != ColorTrapPhase.arenaShown) return state;
    final next = state.copy();
    next.currentRound!.phase = ColorTrapPhase.colorAnnounced;
    next.currentRound!.countdownRemaining = state.difficulty.countdownSeconds;
    return next;
  }

  /// Start the countdown (transition from colorAnnounced to countdown).
  static ColorTrapGameState startCountdown(ColorTrapGameState state) {
    final round = state.currentRound;
    if (round == null || round.phase != ColorTrapPhase.colorAnnounced) return state;
    final next = state.copy();
    next.currentRound!.phase = ColorTrapPhase.countdown;
    return next;
  }

  /// Tick the countdown by 1 second. Returns updated state.
  static ColorTrapGameState tickCountdown(ColorTrapGameState state) {
    final round = state.currentRound;
    if (round == null || round.phase != ColorTrapPhase.countdown) return state;
    final next = state.copy();
    final r = next.currentRound!;
    r.countdownRemaining--;
    if (r.countdownRemaining <= 0) {
      // Time's up — eliminate
      return eliminatePlayers(next);
    }
    return next;
  }

  /// Eliminate players standing on wrong tiles. Transition to elimination phase.
  static ColorTrapGameState eliminatePlayers(ColorTrapGameState state) {
    final round = state.currentRound;
    if (round == null) return state;
    final next = state.copy();
    final r = next.currentRound!;

    // Hide non-target tiles
    for (final tile in r.tiles) {
      tile.isVisible = tile.color == r.targetColor;
    }
    r.phase = ColorTrapPhase.elimination;

    // Eliminate players on wrong tiles
    for (final player in next.players) {
      if (!player.isAlive) continue;
      // Find the tile the player is standing on
      final playerTile = r.tiles.where((t) => t.row == player.row && t.col == player.col).firstOrNull;
      if (playerTile == null || playerTile.color != r.targetColor) {
        player.isAlive = false;
        player.eliminatedRound = r.roundNumber;
      }
    }

    // Check for winner
    if (next.aliveCount <= 1) {
      next.winnerPlayerIndex = next.alivePlayers.isNotEmpty ? next.alivePlayers.first.playerIndex : -1;
      next.status = 'completed';
      r.phase = ColorTrapPhase.roundEnd;
    }

    return next;
  }

  /// Move a player to a new position (if valid).
  static ColorTrapGameState movePlayer(ColorTrapGameState state, int playerIndex, int newRow, int newCol) {
    final round = state.currentRound;
    if (round == null) return state;
    if (newRow < 0 || newRow >= round.arenaSize || newCol < 0 || newCol >= round.arenaSize) return state;
    final next = state.copy();
    final player = next.players.where((p) => p.playerIndex == playerIndex).firstOrNull;
    if (player == null || !player.isAlive) return next;
    // Only allow movement during arenaShown or colorAnnounced or countdown phases
    if (round.phase == ColorTrapPhase.elimination || round.phase == ColorTrapPhase.roundEnd) return next;
    player.row = newRow;
    player.col = newCol;
    return next;
  }

  /// Advance to the next round (regenerate arena).
  static ColorTrapGameState advanceRound(ColorTrapGameState state, [Random? rng]) {
    final round = state.currentRound;
    if (round == null || round.phase != ColorTrapPhase.elimination) return state;
    if (state.aliveCount <= 1) return state; // match over

    final next = state.copy();
    next.currentRoundNumber++;
    _generateRound(next, rng ?? Random());
    return next;
  }

  /// Get remaining alive players.
  static List<ColorTrapPlayer> getRemainingPlayers(ColorTrapGameState state) =>
      state.alivePlayers;

  /// Get the winner's player index, or -1 if no winner yet.
  static int getWinner(ColorTrapGameState state) => state.winnerPlayerIndex;

  /// Restart the match with the same players + settings.
  static ColorTrapGameState restartMatch(ColorTrapGameState state, [Random? rng]) {
    final r = rng ?? Random();
    final playerInfo = state.players.map((p) => (p.userId, p.userName)).toList();
    return createGame(
      playerCount: state.playerCount,
      difficulty: state.difficulty,
      playerInfo: playerInfo,
      rng: r,
    );
  }

  /// Generate a fresh arena for testing.
  static List<ColorTrapTile> generateArena(int size, int colorCount, [Random? rng]) {
    final r = rng ?? Random();
    final colors = ColorTrapTileColor.values.take(colorCount).toList();
    final tiles = <ColorTrapTile>[];
    for (var row = 0; row < size; row++) {
      for (var col = 0; col < size; col++) {
        tiles.add(ColorTrapTile(row: row, col: col, color: colors[r.nextInt(colors.length)]));
      }
    }
    return tiles;
  }
}

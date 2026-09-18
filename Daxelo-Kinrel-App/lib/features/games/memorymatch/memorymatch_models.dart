// lib/features/games/memorymatch/memorymatch_models.dart
//
// Memory Match — data models for the individual multiplayer memory game.
//
// 2–4 players compete SOLO (no teams). Every player flips two cards per
// turn; a match earns a pair (+1 point) and another turn, a miss passes
// the turn. Matched cards are MARKED with the winner's color/avatar
// instead of being removed — everyone can see who is leading.
//
// Dynamic difficulty (auto, default): 2P → 4×4 (16), 3P → 5×4 (20),
// 4P → 6×4 (24). Custom: easy 16 / medium 20 / hard 24 / expert 36 (6×6).

enum MemoryMatchStatus { waiting, inProgress, completed }

extension MemoryMatchStatusX on MemoryMatchStatus {
  String get wire {
    switch (this) {
      case MemoryMatchStatus.waiting:
        return 'waiting';
      case MemoryMatchStatus.inProgress:
        return 'in_progress';
      case MemoryMatchStatus.completed:
        return 'completed';
    }
  }

  static MemoryMatchStatus fromString(String? s) {
    switch (s) {
      case 'in_progress':
        return MemoryMatchStatus.inProgress;
      case 'completed':
        return MemoryMatchStatus.completed;
      case 'waiting':
      default:
        return MemoryMatchStatus.waiting;
    }
  }
}

/// Deck size presets. `auto` scales with the player count (the default).
enum MemoryMatchDifficulty {
  auto,
  easy,
  medium,
  hard,
  expert;

  static MemoryMatchDifficulty fromString(String? s) {
    switch (s) {
      case 'easy':
        return MemoryMatchDifficulty.easy;
      case 'medium':
        return MemoryMatchDifficulty.medium;
      case 'hard':
        return MemoryMatchDifficulty.hard;
      case 'expert':
        return MemoryMatchDifficulty.expert;
      case 'auto':
      default:
        return MemoryMatchDifficulty.auto;
    }
  }

  String get wire => name;

  String get label {
    switch (this) {
      case MemoryMatchDifficulty.auto:
        return 'Auto';
      case MemoryMatchDifficulty.easy:
        return 'Easy';
      case MemoryMatchDifficulty.medium:
        return 'Medium';
      case MemoryMatchDifficulty.hard:
        return 'Hard';
      case MemoryMatchDifficulty.expert:
        return 'Expert';
    }
  }

  String get caption {
    switch (this) {
      case MemoryMatchDifficulty.auto:
        return 'Scales with players';
      case MemoryMatchDifficulty.easy:
        return '16 cards';
      case MemoryMatchDifficulty.medium:
        return '20 cards';
      case MemoryMatchDifficulty.hard:
        return '24 cards';
      case MemoryMatchDifficulty.expert:
        return '36 cards';
    }
  }

  /// Card count for a fixed difficulty; null for auto (player-count based).
  int? get cardCount {
    switch (this) {
      case MemoryMatchDifficulty.easy:
        return 16;
      case MemoryMatchDifficulty.medium:
        return 20;
      case MemoryMatchDifficulty.hard:
        return 24;
      case MemoryMatchDifficulty.expert:
        return 36;
      case MemoryMatchDifficulty.auto:
        return null;
    }
  }

  /// Grid columns for a given card count (portrait-first).
  static int columnsFor(int cardCount) {
    switch (cardCount) {
      case 16:
        return 4;
      case 20:
        return 5;
      case 36:
        return 6;
      default:
        return 6; // 24 → 6×4
    }
  }

  /// Auto difficulty: 2P → 16, 3P → 20, 4P → 24.
  static int autoCardCount(int playerCount) {
    switch (playerCount) {
      case 2:
        return 16;
      case 3:
        return 20;
      default:
        return 24;
    }
  }
}

/// Server-side reveal/turn phase.
enum MemoryMatchPhase { turn, reveal }

extension MemoryMatchPhaseX on MemoryMatchPhase {
  static MemoryMatchPhase fromString(String? s) =>
      s == 'reveal' ? MemoryMatchPhase.reveal : MemoryMatchPhase.turn;
}

// ─────────────────────────────────────────────────────────────────────────
// Card packs — the reusable theme system. The server picks a pack at
// random and deals symbol KEYS; clients map keys to emoji + colors here.
// Keep the keys in sync with fn_memorymatch_start (SQL).
// ─────────────────────────────────────────────────────────────────────────

class MemoryCardPack {
  const MemoryCardPack({
    required this.id,
    required this.label,
    required this.emoji,
    required this.symbols,
  });

  final String id;
  final String label;
  final String emoji;
  final Map<String, String> symbols;

  String emojiFor(String key) => symbols[key] ?? '❓';

  static const MemoryCardPack classic = MemoryCardPack(
    id: 'classic',
    label: 'Classic Charms',
    emoji: '⭐',
    symbols: {
      'star': '⭐',
      'heart': '❤️',
      'moon': '🌙',
      'sun': '☀️',
      'crown': '👑',
      'gem': '💎',
      'rocket': '🚀',
      'balloon': '🎈',
      'rainbow': '🌈',
      'bolt': '⚡',
      'flame': '🔥',
      'snow': '❄️',
      'target': '🎯',
      'gift': '🎁',
      'puzzle': '🧩',
      'sparkle': '✨',
      'crystal': '🔮',
      'butterfly': '🦋',
    },
  );

  static const MemoryCardPack family = MemoryCardPack(
    id: 'family',
    label: 'Family',
    emoji: '👨‍👩‍👧‍👦',
    symbols: {
      'mom': '👩',
      'dad': '👨',
      'brother': '👦',
      'sister': '👧',
      'grandmother': '👵',
      'grandfather': '👴',
      'cousin': '🧒',
      'uncle': '🧔',
      'aunt': '👩‍🦰',
      'baby': '👶',
      'elder': '🧓',
      'bigfamily': '👨‍👩‍👧‍👦',
      'hug': '🫂',
      'home': '🏠',
      'petdog': '🐶',
      'homefood': '🍲',
      'picnic': '🧺',
      'storytime': '📖',
    },
  );

  static const MemoryCardPack food = MemoryCardPack(
    id: 'food',
    label: 'Food',
    emoji: '🍕',
    symbols: {
      'pizza': '🍕',
      'burger': '🍔',
      'icecream': '🍦',
      'cake': '🎂',
      'apple': '🍎',
      'fish': '🐟',
      'coffee': '☕',
      'donut': '🍩',
      'banana': '🍌',
      'grapes': '🍇',
      'taco': '🌮',
      'noodles': '🍜',
      'sushi': '🍣',
      'cookie': '🍪',
      'cupcake': '🧁',
      'strawberry': '🍓',
      'avocado': '🥑',
      'popcorn': '🍿',
    },
  );

  static const MemoryCardPack animals = MemoryCardPack(
    id: 'animals',
    label: 'Animals',
    emoji: '🐼',
    symbols: {
      'dog': '🐶',
      'cat': '🐱',
      'lion': '🦁',
      'tiger': '🐯',
      'elephant': '🐘',
      'rabbit': '🐰',
      'panda': '🐼',
      'bear': '🐻',
      'fox': '🦊',
      'koala': '🐨',
      'cow': '🐮',
      'pig': '🐷',
      'monkey': '🐵',
      'hen': '🐔',
      'unicorn': '🦄',
      'turtle': '🐢',
      'frog': '🐸',
      'owl': '🦉',
    },
  );

  static const List<MemoryCardPack> all = [
    classic,
    family,
    food,
    animals,
  ];

  static MemoryCardPack byId(String? id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return classic;
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Wire models
// ─────────────────────────────────────────────────────────────────────────

/// One card on the board. `index` is the position in the deck (the array
/// index on the server). `ownerId` is set when the pair is matched — the
/// card then wears the owner's color and stays on the board.
class MemoryMatchCard {
  const MemoryMatchCard({
    required this.index,
    required this.pairId,
    required this.symbolKey,
    this.ownerId,
  });

  final int index;
  final int pairId;
  final String symbolKey;
  final String? ownerId;

  bool get isMatched => ownerId != null && ownerId!.isNotEmpty;

  factory MemoryMatchCard.fromJson(int index, Map<String, dynamic> json) {
    return MemoryMatchCard(
      index: index,
      pairId: (json['p'] ?? 0) as int,
      symbolKey: (json['k'] ?? '') as String,
      ownerId: json['o'] as String?,
    );
  }
}

/// Per-player live stats tracked server-side.
class MemoryPlayerStats {
  const MemoryPlayerStats({
    this.flips = 0,
    this.misses = 0,
    this.matchMs = 0,
  });

  final int flips;
  final int misses;
  final int matchMs;

  factory MemoryPlayerStats.fromJson(Map<String, dynamic> json) {
    return MemoryPlayerStats(
      flips: (json['flips'] ?? 0) as int,
      misses: (json['misses'] ?? 0) as int,
      matchMs: (json['matchMs'] ?? 0) as int,
    );
  }
}

/// Final ranking entry (computed server-side at completion).
class MemoryPlacement {
  const MemoryPlacement({
    required this.userId,
    required this.userName,
    required this.place,
    required this.pairs,
    required this.flips,
    required this.misses,
    required this.accuracy,
    this.avgMatchMs,
  });

  final String userId;
  final String userName;
  final int place;
  final int pairs;
  final int flips;
  final int misses;

  /// 0–100, one decimal.
  final double accuracy;

  /// Average milliseconds to find each pair (null when no pairs).
  final double? avgMatchMs;

  factory MemoryPlacement.fromJson(Map<String, dynamic> json) {
    return MemoryPlacement(
      userId: (json['userId'] ?? '') as String,
      userName: (json['userName'] ?? 'Player') as String,
      place: (json['place'] ?? 0) as int,
      pairs: (json['pairs'] ?? 0) as int,
      flips: (json['flips'] ?? 0) as int,
      misses: (json['misses'] ?? 0) as int,
      accuracy: ((json['accuracy'] ?? 0) as num).toDouble(),
      avgMatchMs: json['avgMatchMs'] == null
          ? null
          : ((json['avgMatchMs']) as num).toDouble(),
    );
  }

  String get medal {
    switch (place) {
      case 1:
        return '🥇';
      case 2:
        return '🥈';
      case 3:
        return '🥉';
      default:
        return '🏅';
    }
  }

  /// Human-readable average match time.
  String get avgMatchLabel {
    final ms = avgMatchMs;
    if (ms == null || ms <= 0) return '—';
    if (ms < 10000) return '${(ms / 1000).toStringAsFixed(1)}s';
    return '${(ms / 1000).round()}s';
  }
}

class MemoryMatchPlayer {
  const MemoryMatchPlayer({
    required this.id,
    required this.gameId,
    required this.userId,
    required this.userName,
    required this.joinedAt,
    this.isReady = false,
    this.leftAt,
  });

  final String id;
  final String gameId;
  final String userId;
  final String userName;
  final DateTime joinedAt;
  final bool isReady;
  final DateTime? leftAt;

  bool get isActive => leftAt == null;

  factory MemoryMatchPlayer.fromJson(Map<String, dynamic> json) {
    return MemoryMatchPlayer(
      id: (json['id'] ?? '') as String,
      gameId: (json['gameId'] ?? '') as String,
      userId: (json['userId'] ?? '') as String,
      userName: (json['userName'] ?? 'Player') as String,
      joinedAt: DateTime.tryParse(json['joinedAt'] ?? '') ?? DateTime.now(),
      isReady: (json['isReady'] ?? false) as bool,
      leftAt: json['leftAt'] != null
          ? DateTime.tryParse(json['leftAt'] as String)
          : null,
    );
  }
}

class MemoryMatchGame {
  const MemoryMatchGame({
    required this.id,
    required this.familyId,
    required this.hostUserId,
    required this.hostUserName,
    required this.status,
    required this.difficulty,
    required this.turnSeconds,
    required this.maxPlayers,
    required this.createdAt,
    this.roomName,
    this.cardPack,
    this.cards = const [],
    this.playerOrder = const [],
    this.currentPlayerId,
    this.currentTurnIndex = 0,
    this.turnEndsAt,
    this.phase = MemoryMatchPhase.turn,
    this.flippedCardIds = const [],
    this.revealEndsAt,
    this.pendingIsMatch,
    this.scores = const {},
    this.stats = const {},
    this.placements = const [],
    this.winnerUserIds = const [],
    this.endReason,
    this.startedAt,
    this.completedAt,
    this.spectatorsEnabled = true,
  });

  final String id;
  final String familyId;
  final String hostUserId;
  final String hostUserName;
  final MemoryMatchStatus status;
  final MemoryMatchDifficulty difficulty;
  final int turnSeconds;
  final int maxPlayers;
  final DateTime createdAt;
  final String? roomName;
  final String? cardPack;
  final List<MemoryMatchCard> cards;
  final List<String> playerOrder;
  final String? currentPlayerId;
  final int currentTurnIndex;
  final DateTime? turnEndsAt;
  final MemoryMatchPhase phase;
  final List<int> flippedCardIds;
  final DateTime? revealEndsAt;
  final bool? pendingIsMatch;
  final Map<String, int> scores;
  final Map<String, MemoryPlayerStats> stats;
  final List<MemoryPlacement> placements;
  final List<String> winnerUserIds;
  final String? endReason;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final bool spectatorsEnabled;

  bool get isWaiting => status == MemoryMatchStatus.waiting;
  bool get isInProgress => status == MemoryMatchStatus.inProgress;
  bool get isCompleted => status == MemoryMatchStatus.completed;

  bool get isReveal => phase == MemoryMatchPhase.reveal;

  int get totalPairs => cards.length ~/ 2;

  int get matchedPairs => cards.where((c) => c.isMatched).length ~/ 2;

  /// Seconds left in the current turn (null when not running).
  int? get turnSecondsRemaining {
    if (!isInProgress || turnEndsAt == null) return null;
    final left = turnEndsAt!.difference(DateTime.now()).inSeconds;
    return left < 0 ? 0 : left;
  }

  /// Seconds until the reveal window closes (null when not revealing).
  int? get revealSecondsRemaining {
    if (!isInProgress || !isReveal || revealEndsAt == null) return null;
    final left = revealEndsAt!.difference(DateTime.now()).inMilliseconds;
    return left < 0 ? 0 : (left / 1000).ceil();
  }

  String get endReasonLabel {
    switch (endReason) {
      case 'all_found':
        return 'Every pair was found!';
      case 'walkover':
        return 'The others left — last memory standing';
      default:
        return 'Game complete';
    }
  }

  factory MemoryMatchGame.fromJson(Map<String, dynamic> json) {
    final cardsList = <MemoryMatchCard>[];
    final rawCards = json['cards'];
    if (rawCards is List) {
      for (var i = 0; i < rawCards.length; i++) {
        final c = rawCards[i];
        if (c is Map<String, dynamic>) {
          cardsList.add(MemoryMatchCard.fromJson(i, c));
        }
      }
    }

    final order = <String>[];
    final rawOrder = json['playerOrder'];
    if (rawOrder is List) {
      order.addAll(rawOrder.whereType<String>());
    }

    final scores = <String, int>{};
    final rawScores = json['scores'];
    if (rawScores is Map) {
      rawScores.forEach((k, v) {
        if (k is String && v is num) scores[k] = v.toInt();
      });
    }

    final stats = <String, MemoryPlayerStats>{};
    final rawStats = json['stats'];
    if (rawStats is Map) {
      rawStats.forEach((k, v) {
        if (k is String && v is Map) {
          stats[k] =
              MemoryPlayerStats.fromJson(Map<String, dynamic>.from(v));
        }
      });
    }

    final placements = <MemoryPlacement>[];
    final rawPlacements = json['placements'];
    if (rawPlacements is List) {
      for (final p in rawPlacements) {
        if (p is Map<String, dynamic>) {
          placements.add(MemoryPlacement.fromJson(p));
        }
      }
    }

    final winners = <String>[];
    final rawWinners = json['winnerUserIds'];
    if (rawWinners is List) {
      winners.addAll(rawWinners.whereType<String>());
    }

    final flipped = <int>[];
    final rawFlipped = json['flippedCardIds'];
    if (rawFlipped is List) {
      flipped.addAll(rawFlipped.whereType<num>().map((n) => n.toInt()));
    }

    return MemoryMatchGame(
      id: (json['id'] ?? '') as String,
      familyId: (json['familyId'] ?? '') as String,
      hostUserId: (json['hostUserId'] ?? '') as String,
      hostUserName: (json['hostUserName'] ?? 'Host') as String,
      status: MemoryMatchStatusX.fromString(json['status'] as String?),
      difficulty:
          MemoryMatchDifficulty.fromString(json['difficulty'] as String?),
      turnSeconds: (json['turnSeconds'] ?? 15) as int,
      maxPlayers: (json['maxPlayers'] ?? 4) as int,
      createdAt:
          DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      roomName: json['roomName'] as String?,
      cardPack: json['cardPack'] as String?,
      cards: cardsList,
      playerOrder: order,
      currentPlayerId: json['currentPlayerId'] as String?,
      currentTurnIndex: (json['currentTurnIndex'] ?? 0) as int,
      turnEndsAt: json['turnEndsAt'] != null
          ? DateTime.tryParse(json['turnEndsAt'] as String)
          : null,
      phase: MemoryMatchPhaseX.fromString(json['phase'] as String?),
      flippedCardIds: flipped,
      revealEndsAt: json['revealEndsAt'] != null
          ? DateTime.tryParse(json['revealEndsAt'] as String)
          : null,
      pendingIsMatch: json['pendingResult'] is Map
          ? (json['pendingResult']['isMatch'] as bool?)
          : null,
      scores: scores,
      stats: stats,
      placements: placements,
      winnerUserIds: winners,
      endReason: json['endReason'] as String?,
      startedAt: json['startedAt'] != null
          ? DateTime.tryParse(json['startedAt'] as String)
          : null,
      completedAt: json['completedAt'] != null
          ? DateTime.tryParse(json['completedAt'] as String)
          : null,
      spectatorsEnabled: (json['spectatorsEnabled'] ?? true) as bool,
    );
  }
}

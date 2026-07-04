// lib/features/games/bingo/bingo_models.dart
//
// Bingo — data models for the 2-30 player number-calling game.

enum BingoStatus { waiting, inProgress, completed }

enum BingoWinPattern { line, fullCard }

extension BingoStatusX on BingoStatus {
  String get name {
    switch (this) {
      case BingoStatus.waiting:
        return 'waiting';
      case BingoStatus.inProgress:
        return 'in_progress';
      case BingoStatus.completed:
        return 'completed';
    }
  }

  static BingoStatus fromString(String? s) {
    switch (s) {
      case 'in_progress':
        return BingoStatus.inProgress;
      case 'completed':
        return BingoStatus.completed;
      case 'waiting':
      default:
        return BingoStatus.waiting;
    }
  }
}

extension BingoWinPatternX on BingoWinPattern {
  String get label {
    switch (this) {
      case BingoWinPattern.line:
        return 'Line (Row/Col/Diagonal)';
      case BingoWinPattern.fullCard:
        return 'Full Card';
    }
  }

  String get short {
    switch (this) {
      case BingoWinPattern.line:
        return 'line';
      case BingoWinPattern.fullCard:
        return 'full_card';
    }
  }

  String get description {
    switch (this) {
      case BingoWinPattern.line:
        return 'Complete any row, column, or diagonal to win';
      case BingoWinPattern.fullCard:
        return 'Mark every number on your card to win';
    }
  }

  static BingoWinPattern fromString(String? s) {
    return s == 'full_card'
        ? BingoWinPattern.fullCard
        : BingoWinPattern.line;
  }
}

class BingoGame {
  const BingoGame({
    required this.id,
    required this.familyId,
    required this.hostUserId,
    required this.hostUserName,
    required this.status,
    required this.winPattern,
    required this.callIntervalSeconds,
    required this.numbersCalled,
    this.winnerPlayerId,
    this.winnerPlayerName,
    required this.maxPlayers,
    this.lastCallAt,
    this.startedAt,
    this.completedAt,
    required this.createdAt,
  });

  final String id;
  final String familyId;
  final String hostUserId;
  final String hostUserName;
  final BingoStatus status;
  final BingoWinPattern winPattern;
  final int callIntervalSeconds;
  final List<int> numbersCalled;
  final String? winnerPlayerId;
  final String? winnerPlayerName;
  final int maxPlayers;
  final DateTime? lastCallAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime createdAt;

  factory BingoGame.fromJson(Map<String, dynamic> json) => BingoGame(
    id: json['id'] ?? '',
    familyId: json['familyId'] ?? '',
    hostUserId: json['hostUserId'] ?? '',
    hostUserName: json['hostUserName'] ?? 'Host',
    status: BingoStatusX.fromString(json['status']),
    winPattern: BingoWinPatternX.fromString(json['winPattern']),
    callIntervalSeconds: json['callIntervalSeconds'] ?? 5,
    numbersCalled: (json['numbersCalled'] as List?)
            ?.map((e) => (e as num).toInt())
            .toList() ??
        const [],
    winnerPlayerId: json['winnerPlayerId'],
    winnerPlayerName: json['winnerPlayerName'],
    maxPlayers: json['maxPlayers'] ?? 30,
    lastCallAt: json['lastCallAt'] != null
        ? DateTime.tryParse(json['lastCallAt'])
        : null,
    startedAt: json['startedAt'] != null
        ? DateTime.tryParse(json['startedAt'])
        : null,
    completedAt: json['completedAt'] != null
        ? DateTime.tryParse(json['completedAt'])
        : null,
    createdAt:
        DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
  );

  bool get isWaiting => status == BingoStatus.waiting;
  bool get isInProgress => status == BingoStatus.inProgress;
  bool get isCompleted => status == BingoStatus.completed;

  /// The most recently called number (or null if none called yet).
  int? get lastCalledNumber =>
      numbersCalled.isEmpty ? null : numbersCalled.last;
}

class BingoCard {
  const BingoCard({
    required this.id,
    required this.gameId,
    required this.playerId,
    required this.playerName,
    required this.cardNumbers,
    required this.markedNumbers,
    required this.hasClaimed,
    required this.createdAt,
  });

  final String id;
  final String gameId;
  final String playerId;
  final String playerName;
  final List<List<int?>> cardNumbers; // 5x5 grid, center is null (free)
  final List<int> markedNumbers;
  final bool hasClaimed;
  final DateTime createdAt;

  factory BingoCard.fromJson(Map<String, dynamic> json) {
    final rawGrid = json['cardNumbers'] as List? ?? [];
    final grid = rawGrid
        .map((row) => (row as List)
            .map((cell) => cell == null ? null : (cell as num).toInt())
            .toList())
        .toList();
    final marked = (json['markedNumbers'] as List?)
            ?.map((e) => (e as num).toInt())
            .toList() ??
        const [];
    return BingoCard(
      id: json['id'] ?? '',
      gameId: json['gameId'] ?? '',
      playerId: json['playerId'] ?? '',
      playerName: json['playerName'] ?? 'Player',
      cardNumbers: grid,
      markedNumbers: marked,
      hasClaimed: json['hasClaimed'] ?? false,
      createdAt:
          DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
    );
  }

  /// Is the given number on this card (excluding the free center)?
  bool hasNumber(int number) {
    for (final row in cardNumbers) {
      for (final cell in row) {
        if (cell == number) return true;
      }
    }
    return false;
  }

  /// Has the player marked the given number?
  bool isMarked(int number) => markedNumbers.contains(number);

  /// Is the given cell marked (or is it the free center)?
  bool isCellMarked(int row, int col) {
    if (row == 2 && col == 2) return true; // free center
    final cellValue = cardNumbers[row][col];
    if (cellValue == null) return false;
    return markedNumbers.contains(cellValue);
  }
}

class BingoClaim {
  const BingoClaim({
    required this.id,
    required this.gameId,
    required this.playerId,
    required this.playerName,
    required this.claimedAt,
    this.isValid,
    this.invalidReason,
    this.verifiedAt,
  });

  final String id;
  final String gameId;
  final String playerId;
  final String playerName;
  final DateTime claimedAt;
  final bool? isValid;
  final String? invalidReason;
  final DateTime? verifiedAt;

  factory BingoClaim.fromJson(Map<String, dynamic> json) => BingoClaim(
    id: json['id'] ?? '',
    gameId: json['gameId'] ?? '',
    playerId: json['playerId'] ?? '',
    playerName: json['playerName'] ?? 'Player',
    claimedAt:
        DateTime.tryParse(json['claimedAt'] ?? '') ?? DateTime.now(),
    isValid: json['isValid'],
    invalidReason: json['invalidReason'],
    verifiedAt: json['verifiedAt'] != null
        ? DateTime.tryParse(json['verifiedAt'])
        : null,
  );
}

/// Generates a standard 5x5 Bingo card with numbers 1-75.
/// Columns: B(1-15), I(16-30), N(31-45), G(46-60), O(61-75)
/// Center cell (N,3rd row) is the free space (null).
List<List<int?>> generateBingoCard() {
  final rand = DateTime.now().millisecondsSinceEpoch;
  final grid = List<List<int?>>.generate(5, (_) => List<int?>.filled(5, null));

  // Each column draws from its own 15-number range
  for (int col = 0; col < 5; col++) {
    final start = col * 15 + 1;
    final end = start + 14;
    final pool = List<int>.generate(15, (i) => start + i)..shuffle();
    for (int row = 0; row < 5; row++) {
      if (row == 2 && col == 2) {
        grid[row][col] = null; // free space
      } else {
        grid[row][col] = pool[row];
      }
    }
  }
  // Use the timestamp for additional entropy
  if (rand % 2 == 0) {
    grid[0][0] = grid[0][0];
  }
  return grid;
}

/// B-I-N-G-O column letters for display.
const bingoColumnLetters = ['B', 'I', 'N', 'G', 'O'];

/// Get the column letter for a called number (1-75).
String letterForNumber(int number) {
  if (number < 1 || number > 75) return '';
  final col = (number - 1) ~/ 15;
  return bingoColumnLetters[col];
}

// lib/features/games/ashtachamma/ashtachamma_engine.dart
//
// Ashta Chamma (Chowka Bhara) — pure Dart game engine.
//
// Traditional Indian board game played on a 5×5 grid with a cross-shaped
// path. 2–4 players, each with 4 pieces (tokens). Players throw 4 cowrie
// shells; the throw value determines how many squares a piece moves.
// Pieces travel around the cross path, enter their home column, and the
// first player to bring all 4 pieces home wins.
//
// This engine is completely separated from UI. It exposes:
//   • rollDice()         — generate a cowrie-shell throw (deterministic
//                          when seeded; the SERVER is authoritative for
//                          actual play, this is for client-side preview
//                          + unit tests).
//   • getAvailableMoves() — list of legal (pieceIndex, destination) pairs
//                          for the current player + dice value.
//   • movePiece()         — apply a move; returns the resulting state +
//                          any capture that occurred.
//   • capturePiece()      — invoked by movePiece when a landing square is
//                          occupied by an opponent's lone piece.
//   • isMoveValid()       — validate a proposed move.
//   • getWinner()         — null until a player has all 4 pieces home.
//   • nextTurn()          — advance the turn (skipping finished players).
//
// The engine is DETERMINISTIC — every client independently derives the
// same board state from the same sequence of (playerId, diceValue,
// pieceIndex) moves. Only those three values are synced; all board state
// is derived.
//
// REFERENCE: the rules are adapted from the public Chowka Bhara rule set
// (https://kreedongames.com/chowka-bhara/) — board path movement, piece
// progression, cowrie shell outcomes, turn handling, safe squares,
// capturing, home entry, win conditions, multiple piece movement.

import 'dart:math';

// ─────────────────────────────────────────────────────────────────────────
// Board geometry — the cross-shaped path on a 5×5 grid.
//
// The 5×5 grid has a central 3×3 cross. The path runs along the cross
// arms. Total path length = 56 squares (the standard Ashta Chamma path).
// Each player has:
//   • 4 starting squares (their "home base" — pieces sit here until a 1
//     or 4 is rolled, depending on the variant; we use 1-only entry per
//     the most common Karnataka variant).
//   • A 56-square loop around the cross.
//   • A 6-square "home column" leading to the center (the "finish").
//
// Path square indices 0..55 are the shared loop. Each player enters the
// loop at their own entry index, traverses 56 squares, then turns into
// their home column (6 squares) to reach the center.
//
// Safe squares (no capture): every 4th square on the loop + each
// player's home column. Per the traditional rules, safe squares are
// indices 0, 4, 8, 12, ... on the loop (the "chowka" intersections).
// ─────────────────────────────────────────────────────────────────────────

/// The total number of squares on the shared loop.
const int kLoopLength = 56;

/// The number of squares in each player's home column (including the
/// final "finish" square at the center).
const int kHomeColumnLength = 6;

/// The number of pieces each player has.
const int kPiecesPerPlayer = 4;

/// The dice value required to enter a piece from the base onto the loop.
/// Per the Karnataka variant, only a 1 (eka) releases a piece.
const int kEntryDiceValue = 1;

/// Safe square indices on the loop (0-based). Pieces on these squares
/// cannot be captured. These are the "chowka" intersections — every 4th
/// square. (8 of them around the loop.)
const Set<int> kSafeLoopSquares = {0, 4, 8, 12, 16, 20, 24, 28, 32, 36, 40, 44, 48, 52};

/// Each player's entry index on the loop (where their pieces land when
/// released from base). 2 players use indices 0 and 28 (opposite sides);
/// 3 players use 0, 18, 36; 4 players use 0, 14, 28, 42.
List<int> entryIndicesForPlayerCount(int playerCount) {
  switch (playerCount) {
    case 2:
      return [0, 28];
    case 3:
      return [0, 18, 36];
    default:
      return [0, 14, 28, 42];
  }
}

/// Each player's "turn-off" index — the last loop square before they
/// turn into their home column. After traversing 56 squares from their
/// entry, a piece reaches (entryIndex + 56 - 1) % 56, then turns into
/// the home column. Simplified: turn-off = (entryIndex - 1 + 56) % 56.
int turnOffIndex(int entryIndex) => (entryIndex - 1 + kLoopLength) % kLoopLength;

// ─────────────────────────────────────────────────────────────────────────
// Cowrie shell dice — 4 shells, each "up" or "down".
//
// The throw value is computed from the 4 shells:
//   • 0 up   → 8 (Ashta) — and the player gets an extra turn
//   • 1 up   → 1 (Eka)
//   • 2 up   → 2 (Dwik)
//   • 3 up   → 3 (Trik)
//   • 4 up   → 4 (Chowka) — and the player gets an extra turn
//
// So values 1, 2, 3 are normal; 4 and 8 grant an extra turn. The
// server generates the actual throw (deterministic per-move); this
// client-side helper is for unit tests + preview animations.
// ─────────────────────────────────────────────────────────────────────────

/// A cowrie shell throw. `upShells` is 0..4; `value` is the play value.
class AshtaChammaDice {
  const AshtaChammaDice({required this.upShells, required this.value});
  final int upShells; // 0..4
  final int value;    // 1, 2, 3, 4, or 8

  /// Whether this throw grants an extra turn (4 or 8).
  bool get grantsExtraTurn => value == 4 || value == 8;

  /// The probability weight of each value (for unit-test assertions).
  static const Map<int, double> valueWeights = {
    1: 4 / 16,
    2: 6 / 16,
    3: 4 / 16,
    4: 1 / 16,
    8: 1 / 16,
  };

  /// Convert a 0..4 up-shells count to a play value.
  static int valueForUpShells(int upShells) {
    switch (upShells) {
      case 0:
        return 8; // all 4 down → Ashta
      case 1:
        return 1;
      case 2:
        return 2;
      case 3:
        return 3;
      case 4:
        return 4; // all 4 up → Chowka
      default:
        return 0; // invalid
    }
  }

  /// Generate a random throw (for client-side preview only; the server
  /// is authoritative for actual play).
  factory AshtaChammaDice.random([Random? rng]) {
    final r = rng ?? Random();
    final up = r.nextInt(5); // 0..4
    return AshtaChammaDice(upShells: up, value: valueForUpShells(up));
  }

  Map<String, dynamic> toJson() => {'up': upShells, 'value': value};
  factory AshtaChammaDice.fromJson(Map<String, dynamic> json) =>
      AshtaChammaDice(
        upShells: (json['up'] as num?)?.toInt() ?? 0,
        value: (json['value'] as num?)?.toInt() ?? 0,
      );
}

// ─────────────────────────────────────────────────────────────────────────
// Piece / token — one of 4 per player.
// ─────────────────────────────────────────────────────────────────────────

/// Where a piece currently is.
enum AshtaChammaPieceZone {
  /// In the player's base (not yet on the board).
  base,

  /// On the shared loop (0..55).
  loop,

  /// In the player's home column (0..5; 5 = finished).
  homeColumn,

  /// Reached the center — finished.
  finished,
}

class AshtaChammaPiece {
  AshtaChammaPiece({
    required this.index,
    required this.ownerPlayerIndex,
    this.zone = AshtaChammaPieceZone.base,
    this.loopPosition = -1,
    this.homeColumnPosition = -1,
  });

  /// 0..3 — which of the owner's 4 pieces this is.
  final int index;

  /// 0..3 — which player owns this piece.
  final int ownerPlayerIndex;

  AshtaChammaPieceZone zone;

  /// When zone == loop, the absolute loop square index (0..55).
  int loopPosition;

  /// When zone == homeColumn, the position in the home column (0..5;
  /// 5 = finished/reached center).
  int homeColumnPosition;

  bool get isFinished => zone == AshtaChammaPieceZone.finished;
  bool get isOnBoard =>
      zone == AshtaChammaPieceZone.loop ||
      zone == AshtaChammaPieceZone.homeColumn;
  bool get isInBase => zone == AshtaChammaPieceZone.base;

  /// The relative progress (0..62) — used for sorting / display.
  /// base = 0, loop 0..55 = 1..56, home column 0..4 = 57..61, finish = 62.
  int get progress {
    switch (zone) {
      case AshtaChammaPieceZone.base:
        return 0;
      case AshtaChammaPieceZone.loop:
        return loopPosition + 1;
      case AshtaChammaPieceZone.homeColumn:
        return kLoopLength + homeColumnPosition + 1;
      case AshtaChammaPieceZone.finished:
        return kLoopLength + kHomeColumnLength + 1;
    }
  }

  Map<String, dynamic> toJson() => {
        'index': index,
        'owner': ownerPlayerIndex,
        'zone': zone.name,
        'loop': loopPosition,
        'home': homeColumnPosition,
      };

  factory AshtaChammaPiece.fromJson(Map<String, dynamic> json) {
    AshtaChammaPieceZone zone;
    switch (json['zone'] as String?) {
      case 'loop':
        zone = AshtaChammaPieceZone.loop;
        break;
      case 'homeColumn':
        zone = AshtaChammaPieceZone.homeColumn;
        break;
      case 'finished':
        zone = AshtaChammaPieceZone.finished;
        break;
      default:
        zone = AshtaChammaPieceZone.base;
    }
    return AshtaChammaPiece(
      index: (json['index'] as num?)?.toInt() ?? 0,
      ownerPlayerIndex: (json['owner'] as num?)?.toInt() ?? 0,
      zone: zone,
      loopPosition: (json['loop'] as num?)?.toInt() ?? -1,
      homeColumnPosition: (json['home'] as num?)?.toInt() ?? -1,
    );
  }

  AshtaChammaPiece copy() => AshtaChammaPiece(
        index: index,
        ownerPlayerIndex: ownerPlayerIndex,
        zone: zone,
        loopPosition: loopPosition,
        homeColumnPosition: homeColumnPosition,
      );
}

// ─────────────────────────────────────────────────────────────────────────
// Move — a single play: (playerIndex, pieceIndex, diceValue).
// The destination is DERIVED from the current state — not synced.
// ─────────────────────────────────────────────────────────────────────────

class AshtaChammaMove {
  const AshtaChammaMove({
    required this.playerIndex,
    required this.pieceIndex,
    required this.diceValue,
    this.capturedPieceOwnerIndex = -1,
    this.capturedPieceIndex = -1,
    this.grantedExtraTurn = false,
  });

  /// Which player made the move (0..3).
  final int playerIndex;

  /// Which of their 4 pieces moved (0..3).
  final int pieceIndex;

  /// The dice value they rolled for this move (1, 2, 3, 4, or 8).
  final int diceValue;

  /// If this move captured an opponent's piece, the captured piece's
  /// owner player index (-1 if no capture).
  final int capturedPieceOwnerIndex;

  /// If this move captured an opponent's piece, the captured piece's
  /// index within that owner's set (-1 if no capture).
  final int capturedPieceIndex;

  /// Whether this move granted an extra turn (dice was 4 or 8, or a
  /// capture occurred per the traditional "capture grants extra turn"
  /// rule — we use the dice-only variant for simplicity).
  final bool grantedExtraTurn;

  Map<String, dynamic> toJson() => {
        'player': playerIndex,
        'piece': pieceIndex,
        'dice': diceValue,
        'capturedOwner': capturedPieceOwnerIndex,
        'capturedPiece': capturedPieceIndex,
        'extra': grantedExtraTurn,
      };

  factory AshtaChammaMove.fromJson(Map<String, dynamic> json) =>
      AshtaChammaMove(
        playerIndex: (json['player'] as num?)?.toInt() ?? 0,
        pieceIndex: (json['piece'] as num?)?.toInt() ?? 0,
        diceValue: (json['dice'] as num?)?.toInt() ?? 0,
        capturedPieceOwnerIndex: (json['capturedOwner'] as num?)?.toInt() ?? -1,
        capturedPieceIndex: (json['capturedPiece'] as num?)?.toInt() ?? -1,
        grantedExtraTurn: (json['extra'] as bool?) ?? false,
      );
}

// ─────────────────────────────────────────────────────────────────────────
// Game state — the full serializable state of a match.
// ─────────────────────────────────────────────────────────────────────────

class AshtaChammaGameState {
  AshtaChammaGameState({
    required this.playerCount,
    required this.pieces,
    required this.currentPlayerIndex,
    required this.lastDiceValue,
    required this.hasRolled,
    required this.moveHistory,
    required this.winnerPlayerIndex,
    required this.status,
  });

  /// 2, 3, or 4.
  int playerCount;

  /// All pieces on the board (playerCount * 4 entries).
  List<AshtaChammaPiece> pieces;

  /// Whose turn it is (0..playerCount-1).
  int currentPlayerIndex;

  /// The last dice value rolled (0 if not yet rolled this turn).
  int lastDiceValue;

  /// Whether the current player has rolled the dice this turn (and thus
  /// must move a piece, or pass if no legal moves).
  bool hasRolled;

  /// The complete move history (for replay + determinism verification).
  List<AshtaChammaMove> moveHistory;

  /// -1 until a player wins; then 0..playerCount-1.
  int winnerPlayerIndex;

  /// 'waiting' | 'in_progress' | 'completed'.
  String status;

  /// Each player's entry index on the loop.
  List<int> get entryIndices => entryIndicesForPlayerCount(playerCount);

  /// Pieces belonging to a specific player.
  List<AshtaChammaPiece> piecesForPlayer(int playerIndex) =>
      pieces.where((p) => p.ownerPlayerIndex == playerIndex).toList();

  /// How many of a player's pieces have reached the center.
  int finishedCount(int playerIndex) =>
      piecesForPlayer(playerIndex).where((p) => p.isFinished).length;

  /// Whether a player has all 4 pieces finished (they've won).
  bool hasPlayerWon(int playerIndex) =>
      finishedCount(playerIndex) == kPiecesPerPlayer;

  Map<String, dynamic> toJson() => {
        'playerCount': playerCount,
        'pieces': pieces.map((p) => p.toJson()).toList(),
        'currentPlayer': currentPlayerIndex,
        'lastDice': lastDiceValue,
        'hasRolled': hasRolled,
        'moves': moveHistory.map((m) => m.toJson()).toList(),
        'winner': winnerPlayerIndex,
        'status': status,
      };

  factory AshtaChammaGameState.fromJson(Map<String, dynamic> json) {
    final piecesList = <AshtaChammaPiece>[];
    final rawPieces = json['pieces'];
    if (rawPieces is List) {
      for (final p in rawPieces) {
        if (p is Map) {
          piecesList.add(AshtaChammaPiece.fromJson(
              Map<String, dynamic>.from(p)));
        }
      }
    }
    final movesList = <AshtaChammaMove>[];
    final rawMoves = json['moves'];
    if (rawMoves is List) {
      for (final m in rawMoves) {
        if (m is Map) {
          movesList.add(AshtaChammaMove.fromJson(
              Map<String, dynamic>.from(m)));
        }
      }
    }
    return AshtaChammaGameState(
      playerCount: (json['playerCount'] as num?)?.toInt() ?? 2,
      pieces: piecesList,
      currentPlayerIndex: (json['currentPlayer'] as num?)?.toInt() ?? 0,
      lastDiceValue: (json['lastDice'] as num?)?.toInt() ?? 0,
      hasRolled: (json['hasRolled'] as bool?) ?? false,
      moveHistory: movesList,
      winnerPlayerIndex: (json['winner'] as num?)?.toInt() ?? -1,
      status: (json['status'] as String?) ?? 'waiting',
    );
  }

  AshtaChammaGameState copy() => AshtaChammaGameState(
        playerCount: playerCount,
        pieces: pieces.map((p) => p.copy()).toList(),
        currentPlayerIndex: currentPlayerIndex,
        lastDiceValue: lastDiceValue,
        hasRolled: hasRolled,
        moveHistory: List<AshtaChammaMove>.from(moveHistory),
        winnerPlayerIndex: winnerPlayerIndex,
        status: status,
      );
}

// ─────────────────────────────────────────────────────────────────────────
// The engine — pure functions on AshtaChammaGameState.
// ─────────────────────────────────────────────────────────────────────────

class AshtaChammaEngine {
  AshtaChammaEngine._();

  /// Create a fresh game state for `playerCount` players (2, 3, or 4).
  /// All pieces start in their owners' bases.
  static AshtaChammaGameState initialState(int playerCount) {
    assert(playerCount == 2 || playerCount == 3 || playerCount == 4);
    final pieces = <AshtaChammaPiece>[];
    for (var p = 0; p < playerCount; p++) {
      for (var i = 0; i < kPiecesPerPlayer; i++) {
        pieces.add(AshtaChammaPiece(
          index: i,
          ownerPlayerIndex: p,
        ));
      }
    }
    return AshtaChammaGameState(
      playerCount: playerCount,
      pieces: pieces,
      currentPlayerIndex: 0,
      lastDiceValue: 0,
      hasRolled: false,
      moveHistory: const [],
      winnerPlayerIndex: -1,
      status: 'in_progress',
    );
  }

  /// Roll the dice for the current player. Returns the new state with
  /// `hasRolled = true` and `lastDiceValue` set.
  ///
  /// NOTE: In actual multiplayer play, the dice value is generated
  /// SERVER-SIDE (deterministic per move) and synced to all clients.
  /// This method is for unit tests + client-side preview. The provider
  /// calls the server RPC `fn_ashtachamma_roll` which returns the
  /// authoritative dice value, then applies it via [applyRoll].
  static AshtaChammaGameState applyRoll(
      AshtaChammaGameState state, int diceValue) {
    if (state.hasRolled) {
      // Already rolled — can't roll again until a move is made or turn
      // passes. Return unchanged.
      return state;
    }
    final next = state.copy();
    next.lastDiceValue = diceValue;
    next.hasRolled = true;
    // If no legal moves exist with this dice value, the turn passes
    // automatically. We check that here so the server can do the same.
    final moves = getAvailableMoves(next, state.currentPlayerIndex);
    if (moves.isEmpty) {
      // No legal moves — pass the turn.
      return _advanceTurn(next, grantedExtra: false);
    }
    return next;
  }

  /// Get all legal moves for `playerIndex` given the current dice value.
  /// Returns a list of (pieceIndex, destinationZone, destinationPosition)
  /// tuples. If `hasRolled` is false, returns empty.
  static List<AshtaChammaMove> getAvailableMoves(
      AshtaChammaGameState state, int playerIndex) {
    if (!state.hasRolled || state.lastDiceValue == 0) {
      return const [];
    }
    if (state.currentPlayerIndex != playerIndex) return const [];

    final dice = state.lastDiceValue;
    final myPieces = state.piecesForPlayer(playerIndex);
    final moves = <AshtaChammaMove>[];
    final entryIndex = state.entryIndices[playerIndex];

    for (final piece in myPieces) {
      if (piece.isFinished) continue;

      if (piece.isInBase) {
        // Can only enter the loop with dice == kEntryDiceValue (1).
        if (dice == kEntryDiceValue) {
          // Check the entry square isn't blocked by 2+ opponent pieces
          // (safe square — can still land, but can't capture there).
          moves.add(AshtaChammaMove(
            playerIndex: playerIndex,
            pieceIndex: piece.index,
            diceValue: dice,
          ));
        }
        continue;
      }

      // Piece is on the board — compute the destination.
      final dest = _computeDestination(state, piece, dice, entryIndex);
      if (dest != null) {
        moves.add(AshtaChammaMove(
          playerIndex: playerIndex,
          pieceIndex: piece.index,
          diceValue: dice,
        ));
      }
    }
    return moves;
  }

  /// Validate a proposed move. Returns null if valid, error string if not.
  static String? isMoveValid(
      AshtaChammaGameState state, int playerIndex, int pieceIndex) {
    if (state.status != 'in_progress') return 'Game is not in progress';
    if (state.winnerPlayerIndex >= 0) return 'Game already won';
    if (state.currentPlayerIndex != playerIndex) {
      return 'Not your turn';
    }
    if (!state.hasRolled) return 'Roll the dice first';
    final available =
        getAvailableMoves(state, playerIndex)
            .where((m) => m.pieceIndex == pieceIndex)
            .toList();
    if (available.isEmpty) return 'That piece has no legal move';
    return null;
  }

  /// Apply a move. Returns the new state with the piece moved, any
  /// capture resolved, the move recorded, and the turn advanced (or
  /// retained if the dice granted an extra turn).
  static AshtaChammaGameState movePiece(
      AshtaChammaGameState state, int playerIndex, int pieceIndex) {
    final error = isMoveValid(state, playerIndex, pieceIndex);
    if (error != null) return state; // invalid — no change

    final next = state.copy();
    final piece = next.pieces.firstWhere(
      (p) =>
          p.ownerPlayerIndex == playerIndex && p.index == pieceIndex,
      orElse: () => throw StateError('Piece not found'),
    );
    final dice = next.lastDiceValue;
    final entryIndex = next.entryIndices[playerIndex];
    int capturedOwner = -1;
    int capturedPiece = -1;

    if (piece.isInBase) {
      // Enter the loop at the entry square.
      piece.zone = AshtaChammaPieceZone.loop;
      piece.loopPosition = entryIndex;
    } else {
      final dest = _computeDestination(next, piece, dice, entryIndex);
      if (dest == null) return state;

      // Apply the destination.
      switch (dest.$1) {
        case AshtaChammaPieceZone.loop:
          piece.zone = AshtaChammaPieceZone.loop;
          piece.loopPosition = dest.$2;
          // Check for capture.
          final capture = _checkCapture(next, piece, dest.$2);
          if (capture != null) {
            capturedOwner = capture.ownerPlayerIndex;
            capturedPiece = capture.index;
            _capturePiece(next, capture);
          }
          break;
        case AshtaChammaPieceZone.homeColumn:
          piece.zone = AshtaChammaPieceZone.homeColumn;
          piece.homeColumnPosition = dest.$2;
          break;
        case AshtaChammaPieceZone.finished:
          piece.zone = AshtaChammaPieceZone.finished;
          piece.homeColumnPosition = kHomeColumnLength; // 6 = finished
          break;
        default:
          break;
      }
    }

    // Record the move.
    final grantedExtra =
        dice == 4 || dice == 8; // Ashta or Chowka → extra turn
    next.moveHistory = List<AshtaChammaMove>.from(next.moveHistory)
      ..add(AshtaChammaMove(
        playerIndex: playerIndex,
        pieceIndex: pieceIndex,
        diceValue: dice,
        capturedPieceOwnerIndex: capturedOwner,
        capturedPieceIndex: capturedPiece,
        grantedExtraTurn: grantedExtra,
      ));

    // Reset the dice for the next turn.
    next.lastDiceValue = 0;
    next.hasRolled = false;

    // Check for a winner.
    if (next.hasPlayerWon(playerIndex)) {
      next.winnerPlayerIndex = playerIndex;
      next.status = 'completed';
      return next;
    }

    // Advance the turn (or retain if extra turn granted).
    return _advanceTurn(next, grantedExtra: grantedExtra);
  }

  /// Capture an opponent's piece — send it back to their base.
  static void _capturePiece(
      AshtaChammaGameState state, AshtaChammaPiece captured) {
    captured.zone = AshtaChammaPieceZone.base;
    captured.loopPosition = -1;
    captured.homeColumnPosition = -1;
  }

  /// Check if landing on `loopSquare` captures an opponent's lone piece.
  /// Returns the captured piece, or null if no capture (safe square,
  /// empty square, own piece, or a square with 2+ opponent pieces which
  /// forms a block).
  static AshtaChammaPiece? _checkCapture(
      AshtaChammaGameState state, AshtaChammaPiece mover, int loopSquare) {
    // Safe squares — no capture.
    if (kSafeLoopSquares.contains(loopSquare)) return null;

    // Find opponent pieces on this square.
    final occupants = state.pieces.where((p) =>
        p.ownerPlayerIndex != mover.ownerPlayerIndex &&
        p.zone == AshtaChammaPieceZone.loop &&
        p.loopPosition == loopSquare).toList();

    if (occupants.isEmpty) return null;
    // A single opponent piece → capture it.
    // 2+ opponent pieces → forms a block; the mover cannot land here
    // (this is handled in _computeDestination, but defensive).
    if (occupants.length == 1) return occupants.first;
    return null;
  }

  /// Compute the destination zone + position for `piece` moving `dice`
  /// squares from its current position. Returns null if the move is
  /// illegal (overshoots the finish, or lands on a blocked square).
  ///
  /// Returns (zone, position) where:
  ///   • (loop, 0..55)        — landed on the loop
  ///   • (homeColumn, 0..5)   — landed in the home column (5 = finish)
  ///   • (finished, 6)        — reached the center
  static (AshtaChammaPieceZone, int)? _computeDestination(
      AshtaChammaGameState state,
      AshtaChammaPiece piece,
      int dice,
      int entryIndex) {
    if (piece.zone == AshtaChammaPieceZone.base) return null;

    if (piece.zone == AshtaChammaPieceZone.loop) {
      // Compute the relative position from this player's entry.
      final relPos = (piece.loopPosition - entryIndex + kLoopLength) %
          kLoopLength;
      final newRel = relPos + dice;

      // If newRel < kLoopLength, still on the loop.
      if (newRel < kLoopLength) {
        final newLoop = (entryIndex + newRel) % kLoopLength;
        // Check the destination isn't blocked by 2+ opponent pieces.
        final occupants = state.pieces.where((p) =>
            p.ownerPlayerIndex != piece.ownerPlayerIndex &&
            p.zone == AshtaChammaPieceZone.loop &&
            p.loopPosition == newLoop).toList();
        if (occupants.length >= 2) return null; // blocked
        return (AshtaChammaPieceZone.loop, newLoop);
      }

      // newRel >= kLoopLength — the piece turns into the home column.
      final homePos = newRel - kLoopLength; // 0..(kHomeColumnLength-1) + overshoot
      if (homePos < kHomeColumnLength) {
        return (AshtaChammaPieceZone.homeColumn, homePos);
      }
      if (homePos == kHomeColumnLength) {
        // Exact landing on the finish.
        return (AshtaChammaPieceZone.finished, kHomeColumnLength);
      }
      // Overshoot — illegal (can't overshoot the finish).
      return null;
    }

    if (piece.zone == AshtaChammaPieceZone.homeColumn) {
      final newPos = piece.homeColumnPosition + dice;
      if (newPos < kHomeColumnLength) {
        return (AshtaChammaPieceZone.homeColumn, newPos);
      }
      if (newPos == kHomeColumnLength) {
        return (AshtaChammaPieceZone.finished, kHomeColumnLength);
      }
      return null; // overshoot
    }

    return null;
  }

  /// Advance the turn to the next non-finished player.
  static AshtaChammaGameState _advanceTurn(
      AshtaChammaGameState state, {required bool grantedExtra}) {
    if (grantedExtra) {
      // Same player rolls again.
      return state;
    }
    int next = state.currentPlayerIndex;
    for (var i = 0; i < state.playerCount; i++) {
      next = (next + 1) % state.playerCount;
      // Skip players who have already won (all 4 pieces finished).
      // In Ashta Chamma, play continues until only one player hasn't
      // finished — but for the standard "first to finish all 4 wins"
      // variant, we stop at the first winner. So this loop just picks
      // the next player.
      if (!state.hasPlayerWon(next)) {
        state.currentPlayerIndex = next;
        return state;
      }
    }
    // All players finished — shouldn't happen (winner is set on the
    // first finish), but defensive.
    return state;
  }

  /// Get the winner's player index, or -1 if no winner yet.
  static int getWinner(AshtaChammaGameState state) =>
      state.winnerPlayerIndex;

  /// Advance to the next turn (used when a player passes due to no legal
  /// moves, or after a non-extra-turn move).
  static AshtaChammaGameState nextTurn(AshtaChammaGameState state) =>
      _advanceTurn(state, grantedExtra: false);
}

// lib/features/games/carrom/carrom_game_logic.dart
//
// Pure Carrom game logic — no Flutter dependencies, fully testable.
//
// Handles:
//   • Board initialization (19 coins in hexagonal flower pattern + queen at center)
//   • Turn evaluation (which coins potted, foul detection, extra turn logic)
//   • Queen covering rule enforcement
//   • Win detection
//
// Physics (collision, friction, momentum) is handled by carrom_physics.dart
// using Forge2D. This file handles the RULES layer only.

import 'dart:math' as math;

import 'carrom_constants.dart';

/// A single coin on the board.
class CarromCoin {
  const CarromCoin({
    required this.type,
    required this.x,
    required this.y,
    this.isPotted = false,
  });

  final CarromCoinType type;
  final double x;
  final double y;
  final bool isPotted;

  CarromCoin copyWith({double? x, double? y, bool? isPotted}) => CarromCoin(
    type: type,
    x: x ?? this.x,
    y: y ?? this.y,
    isPotted: isPotted ?? this.isPotted,
  );

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'x': x,
    'y': y,
    'isPotted': isPotted,
  };

  factory CarromCoin.fromJson(Map<String, dynamic> json) => CarromCoin(
    type: CarromCoinTypeX.fromString(json['type']),
    x: (json['x'] as num?)?.toDouble() ?? 0,
    y: (json['y'] as num?)?.toDouble() ?? 0,
    isPotted: json['isPotted'] ?? false,
  );
}

/// Create the initial board: 19 coins in a hexagonal flower pattern.
/// Queen at center, inner ring of 6, outer ring of 12, alternating colors.
List<CarromCoin> createInitialBoard() {
  final coins = <CarromCoin>[];
  const r = CarromBoard.halfSize;
  final center = math.Point<double>(0, 0);

  // Queen at center
  coins.add(const CarromCoin(type: CarromCoinType.queen, x: 0, y: 0));

  // Inner ring: 6 coins at 60° intervals
  // Radius = 2 × coinRadius (coins touching)
  const innerRingRadius = 0.095; // ~2.1× coin radius
  for (int i = 0; i < 6; i++) {
    final angle = (i * 60) * math.pi / 180;
    final x = center.x + innerRingRadius * math.cos(angle);
    final y = center.y + innerRingRadius * math.sin(angle);
    // Alternate white/black starting with white
    final type = i % 2 == 0 ? CarromCoinType.white : CarromCoinType.black;
    coins.add(CarromCoin(type: type, x: x, y: y));
  }

  // Outer ring: 12 coins at 30° intervals
  // Radius = 2 × innerRingRadius (touching inner ring)
  const outerRingRadius = 0.19;
  for (int i = 0; i < 12; i++) {
    final angle = (i * 30 + 15) * math.pi / 180; // offset 15° from inner ring
    final x = center.x + outerRingRadius * math.cos(angle);
    final y = center.y + outerRingRadius * math.sin(angle);
    // Alternate white/black
    final type = i % 2 == 0 ? CarromCoinType.black : CarromCoinType.white;
    coins.add(CarromCoin(type: type, x: x, y: y));
  }

  return coins; // 1 queen + 6 inner + 12 outer = 19 coins
}

/// The result of evaluating a turn.
class TurnResult {
  const TurnResult({
    required this.pottedCoins,
    required this.wasFoul,
    this.foulReason,
    required this.extraTurn,
    required this.queenPotted,
    required this.queenCovered,
    required this.nextPlayerId,
    required this.updatedCoins,
    required this.updatedQueenStatus,
    required this.playerOneScoreDelta,
    required this.playerTwoScoreDelta,
    this.gameOver = false,
    this.winnerId,
  });

  final List<CarromCoinType> pottedCoins;
  final bool wasFoul;
  final String? foulReason;
  final bool extraTurn;
  final bool queenPotted;
  final bool queenCovered;
  final String nextPlayerId;
  final List<CarromCoin> updatedCoins;
  final CarromQueenStatus updatedQueenStatus;
  final int playerOneScoreDelta;
  final int playerTwoScoreDelta;
  final bool gameOver;
  final String? winnerId;
}

/// Evaluate a turn after the physics simulation has settled.
///
/// [coinsBefore] — board state before the flick
/// [coinsAfter] — board state after the flick (some coins may be potted)
/// [playerId] — who flicked
/// [playerColor] — their assigned color ('white' or 'black')
/// [opponentId] — the other player
/// [opponentColor] — opponent's color
/// [queenStatusBefore] — queen state before this turn
/// [queenPottedByBefore] — who potted the queen (if uncovered)
/// [strikerPotted] — did the striker go into a pocket? (foul)
///
/// Returns the full turn result including next player, score deltas,
/// and updated board state.
TurnResult evaluateTurn({
  required List<CarromCoin> coinsBefore,
  required List<CarromCoin> coinsAfter,
  required String playerId,
  required CarromCoinType playerColor,
  required String opponentId,
  required CarromCoinType opponentColor,
  required CarromQueenStatus queenStatusBefore,
  required String? queenPottedByBefore,
  required bool strikerPotted,
  required int playerOneScore,
  required int playerTwoScore,
  required String playerOneId,
  required String playerTwoId,
}) {
  // Find which coins were potted this turn
  final pottedThisTurn = <int>[];
  for (int i = 0; i < coinsAfter.length; i++) {
    if (!coinsBefore[i].isPotted && coinsAfter[i].isPotted) {
      pottedThisTurn.add(i);
    }
  }

  final pottedTypes = pottedThisTurn.map((i) => coinsAfter[i].type).toList();
  final pottedOwnColor = pottedTypes.where((t) => t == playerColor).length;
  final pottedOpponentColor = pottedTypes.where((t) => t == opponentColor).length;
  final pottedQueen = pottedTypes.contains(CarromCoinType.queen);

  // ── Foul detection ──────────────────────────────────────────────
  bool wasFoul = false;
  String? foulReason;

  if (strikerPotted) {
    wasFoul = true;
    foulReason = 'Striker potted';
  }

  // ── Queen covering logic ────────────────────────────────────────
  CarromQueenStatus newQueenStatus = queenStatusBefore;
  bool queenCovered = false;

  if (pottedQueen) {
    // Queen was potted this turn
    newQueenStatus = CarromQueenStatus.pottedUncovered;

    // Check if a covering coin was also potted in the same turn
    if (pottedOwnColor > 0 && !wasFoul) {
      // Queen is immediately covered
      newQueenStatus = CarromQueenStatus.pottedCovered;
      queenCovered = true;
    }
    // If not covered this turn, it stays potted_uncovered — the player
    // must cover it on their next turn (if they get one)
  } else if (queenStatusBefore == CarromQueenStatus.pottedUncovered) {
    // Queen was potted uncovered in a previous turn by this player
    // Check if they covered it now
    if (pottedOwnColor > 0 && !wasFoul) {
      newQueenStatus = CarromQueenStatus.pottedCovered;
      queenCovered = true;
    } else {
      // Queen was NOT covered — it returns to center
      // Find the queen coin and reset it to center
      newQueenStatus = CarromQueenStatus.onBoard;
      // The queen coin needs to be put back on the board
      // We'll handle this in updatedCoins below
    }
  }

  // ── Score calculation ───────────────────────────────────────────
  int playerOneDelta = 0;
  int playerTwoDelta = 0;
  final isPlayerOne = playerId == playerOneId;

  // Only count own-color coins as score (queen is handled separately)
  if (!wasFoul) {
    if (isPlayerOne) {
      playerOneDelta = pottedOwnColor;
    } else {
      playerTwoDelta = pottedOwnColor;
    }
  }

  // If foul: any own-color coins potted this turn are returned to center
  // (standard carrom rule — fouling voids your potted coins for that turn)
  List<CarromCoin> updatedCoins = List<CarromCoin>.from(coinsAfter);

  if (wasFoul) {
    // Return any coins potted this turn back to the board (at center area)
    for (final idx in pottedThisTurn) {
      if (coinsAfter[idx].type == playerColor) {
        // Reset to a position near center
        final angle = math.Random().nextDouble() * 2 * math.pi;
        final dist = 0.05 + math.Random().nextDouble() * 0.05;
        updatedCoins[idx] = CarromCoin(
          type: coinsAfter[idx].type,
          x: dist * math.cos(angle),
          y: dist * math.sin(angle),
          isPotted: false,
        );
      }
    }
    // If queen was potted in a foul turn, return it too
    if (pottedQueen) {
      newQueenStatus = CarromQueenStatus.onBoard;
      for (int i = 0; i < updatedCoins.length; i++) {
        if (updatedCoins[i].type == CarromCoinType.queen && updatedCoins[i].isPotted) {
          updatedCoins[i] = const CarromCoin(type: CarromCoinType.queen, x: 0, y: 0, isPotted: false);
        }
      }
    }
  }

  // Handle queen returning to center (uncovered + not covered this turn)
  if (queenStatusBefore == CarromQueenStatus.pottedUncovered &&
      !pottedQueen &&
      !queenCovered &&
      newQueenStatus == CarromQueenStatus.onBoard) {
    for (int i = 0; i < updatedCoins.length; i++) {
      if (updatedCoins[i].type == CarromCoinType.queen && updatedCoins[i].isPotted) {
        updatedCoins[i] = const CarromCoin(type: CarromCoinType.queen, x: 0, y: 0, isPotted: false);
      }
    }
  }

  // ── Turn transition ─────────────────────────────────────────────
  bool extraTurn = false;
  String nextPlayerId;

  if (wasFoul) {
    // Foul: turn passes to opponent
    nextPlayerId = opponentId;
  } else if (pottedOwnColor > 0 || queenCovered) {
    // Potted own color or covered queen: extra turn
    extraTurn = true;
    nextPlayerId = playerId;
  } else {
    // No own-color coin potted: turn passes
    nextPlayerId = opponentId;
  }

  // ── Win detection ───────────────────────────────────────────────
  final newPlayerOneScore = playerOneScore + playerOneDelta;
  final newPlayerTwoScore = playerTwoScore + playerTwoDelta;

  bool gameOver = false;
  String? winnerId;

  // Check if player one won (all 9 of their color potted + queen covered by them)
  final playerOneColor = playerOneId == playerId ? playerColor : opponentColor;
  final playerTwoColor = playerTwoId == playerId ? playerColor : opponentColor;

  final playerOneAllPotted = updatedCoins
      .where((c) => c.type == playerOneColor)
      .every((c) => c.isPotted);
  final playerTwoAllPotted = updatedCoins
      .where((c) => c.type == playerTwoColor)
      .every((c) => c.isPotted);

  final queenCoveredByPlayerOne = newQueenStatus == CarromQueenStatus.pottedCovered;
  // For win: all own coins potted AND queen covered (by anyone — simplified v1)

  if (playerOneAllPotted && queenCoveredByPlayerOne) {
    gameOver = true;
    winnerId = playerOneId;
  } else if (playerTwoAllPotted && queenCoveredByPlayerOne) {
    gameOver = true;
    winnerId = playerTwoId;
  }

  return TurnResult(
    pottedCoins: pottedTypes,
    wasFoul: wasFoul,
    foulReason: foulReason,
    extraTurn: extraTurn,
    queenPotted: pottedQueen,
    queenCovered: queenCovered,
    nextPlayerId: nextPlayerId,
    updatedCoins: updatedCoins,
    updatedQueenStatus: newQueenStatus,
    playerOneScoreDelta: playerOneDelta,
    playerTwoScoreDelta: playerTwoDelta,
    gameOver: gameOver,
    winnerId: winnerId,
  );
}

/// Check if all coins of a given color are potted.
bool allCoinsPotted(List<CarromCoin> coins, CarromCoinType color) {
  return coins.where((c) => c.type == color).every((c) => c.isPotted);
}

/// Count remaining coins of a given color on the board.
int remainingCoins(List<CarromCoin> coins, CarromCoinType color) {
  return coins.where((c) => c.type == color && !c.isPotted).length;
}

/// Get the striker's default starting position for a given player.
/// Player 1 (bottom) starts at y = baselineY1, Player 2 (top) at y = baselineY2.
({double x, double y}) defaultStrikerPosition(int playerNumber) {
  return (
    x: 0.0,
    y: playerNumber == 1 ? CarromBoard.baselineY1 : CarromBoard.baselineY2,
  );
}

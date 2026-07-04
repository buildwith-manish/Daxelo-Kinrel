// lib/features/games/sos/sos_game_logic.dart
//
// Pure game logic for SOS — no Flutter dependencies.
// Can be unit-tested in isolation.

import 'sos_models.dart';

/// The 4 line directions to check for SOS sequences.
/// Each direction is a (dr, dc) unit vector.
const _directions = <(int, int)>[
  (0, 1), // horizontal →
  (1, 0), // vertical ↓
  (1, 1), // diagonal ↘
  (1, -1), // diagonal ↙
];

/// Check all sequences completed by placing [letter] at (row, col)
/// on a grid of size [gridSize], given the existing [grid] state.
///
/// Returns the list of completed SOS sequences (each is 3 cells).
/// A sequence is S-O-S in a straight line (horizontal, vertical, or
/// diagonal). The placed letter can be at position 0, 1, or 2 of the
/// sequence.
///
/// [grid] is a 2D list where grid[r][c] is 'S', 'O', or null.
List<SosSequence> findCompletedSequences({
  required List<List<String?>> grid,
  required int gridSize,
  required int row,
  required int col,
  required String letter,
  SosTeam? team,
  String? moveId,
}) {
  final sequences = <SosSequence>[];

  for (final (dr, dc) in _directions) {
    // The placed cell can be at position 0, 1, or 2 of an SOS sequence.
    // Check all three possibilities.

    // Position 0: (row, col), (row+dr, col+dc), (row+2dr, col+2dc)
    _checkSequence(
      grid: grid,
      gridSize: gridSize,
      cells: [
        (row, col),
        (row + dr, col + dc),
        (row + 2 * dr, col + 2 * dc),
      ],
      team: team,
      moveId: moveId,
      out: sequences,
    );

    // Position 1: (row-dr, col-dc), (row, col), (row+dr, col+dc)
    _checkSequence(
      grid: grid,
      gridSize: gridSize,
      cells: [
        (row - dr, col - dc),
        (row, col),
        (row + dr, col + dc),
      ],
      team: team,
      moveId: moveId,
      out: sequences,
    );

    // Position 2: (row-2dr, col-2dc), (row-dr, col-dc), (row, col)
    _checkSequence(
      grid: grid,
      gridSize: gridSize,
      cells: [
        (row - 2 * dr, col - 2 * dc),
        (row - dr, col - dc),
        (row, col),
      ],
      team: team,
      moveId: moveId,
      out: sequences,
    );
  }

  return sequences;
}

void _checkSequence({
  required List<List<String?>> grid,
  required int gridSize,
  required List<(int, int)> cells,
  required SosTeam? team,
  required String? moveId,
  required List<SosSequence> out,
}) {
  // All 3 cells must be in bounds
  for (final (r, c) in cells) {
    if (r < 0 || r >= gridSize || c < 0 || c >= gridSize) return;
  }

  // Letters must spell S-O-S
  final letters = cells.map((r, c) => grid[r][c]).toList();
  if (letters[0] != 'S') return;
  if (letters[1] != 'O') return;
  if (letters[2] != 'S') return;

  out.add(
    SosSequence(cells: cells, team: team, moveId: moveId ?? ''),
  );
}

/// Validate whether a move is legal.
/// Returns null if valid, or an error message string if invalid.
String? validateMove({
  required SosGame game,
  required List<SosPlayer> players,
  required List<SosMove> moves,
  required String userId,
  required int row,
  required int col,
  required SosLetter letter,
}) {
  if (game.status != SosGameStatus.active) {
    return 'Game is not active';
  }

  // Check it's the player's turn
  final currentPlayer = _getCurrentPlayer(players, game.currentTurnOrder);
  if (currentPlayer == null) {
    return 'No current player found';
  }
  if (currentPlayer.userId != userId) {
    return "It's ${currentPlayer.userName}'s turn, not yours";
  }

  // Check cell is empty
  if (moves.any((m) => m.rowIdx == row && m.colIdx == col)) {
    return 'Cell is already occupied';
  }

  // Check bounds
  if (row < 0 ||
      row >= game.gridSize ||
      col < 0 ||
      col >= game.gridSize) {
    return 'Cell is out of bounds';
  }

  // In 4-player team mode: letter must match the player's team
  if (game.mode == SosMode.fourPlayerTeams) {
    final player = players.firstWhere(
      (p) => p.userId == userId,
      orElse: () => throw StateError('Player not found'),
    );
    if (player.team == SosTeam.s && letter != SosLetter.s) {
      return 'Team S players can only place S';
    }
    if (player.team == SosTeam.o && letter != SosLetter.o) {
      return 'Team O players can only place O';
    }
  }

  return null; // valid
}

/// Compute the next turn order after a move.
/// If the move scored (sequenced=true), the same player goes again.
/// Otherwise, advance to the next player in rotation.
int nextTurnOrder({
  required int currentTurnOrder,
  required int playerCount,
  required bool scored,
}) {
  if (scored) return currentTurnOrder; // same player goes again
  return (currentTurnOrder + 1) % playerCount;
}

/// Get the player whose turn it currently is.
SosPlayer? _getCurrentPlayer(List<SosPlayer> players, int turnOrder) {
  final sorted = List<SosPlayer>.from(players)
    ..sort((a, b) => a.turnOrder.compareTo(b.turnOrder));
  if (turnOrder < 0 || turnOrder >= sorted.length) return null;
  return sorted[turnOrder];
}

/// Build a 2D grid from the move list for sequence checking.
List<List<String?>> buildGrid({
  required int gridSize,
  required List<SosMove> moves,
}) {
  final grid = List<List<String?>>.generate(
    gridSize,
    (_) => List<String?>.filled(gridSize, null),
  );
  for (final m in moves) {
    if (m.rowIdx >= 0 &&
        m.rowIdx < gridSize &&
        m.colIdx >= 0 &&
        m.colIdx < gridSize) {
      grid[m.rowIdx][m.colIdx] = m.letter.char;
    }
  }
  return grid;
}

/// Check if the grid is full (no empty cells).
bool isGridFull({
  required int gridSize,
  required List<SosMove> moves,
}) {
  return moves.length >= gridSize * gridSize;
}

/// Compute the winner based on scores.
/// In 2-player mode: returns the userId with the highest score (or null for tie).
/// In 4-player team mode: returns the team with the highest combined score (or null for tie).
SosWinner computeWinner({
  required SosGame game,
  required List<SosPlayer> players,
  required List<SosScore> scores,
}) {
  if (game.mode == SosMode.twoPlayer) {
    // Per-player scores
    final sorted = List<SosPlayer>.from(players)
      ..sort((a, b) => b.score.compareTo(a.score));
    if (sorted.isEmpty) {
      return const SosWinner(winnerUserId: null, winnerTeam: null, isTie: true);
    }
    if (sorted.length == 1) {
      return SosWinner(
        winnerUserId: sorted[0].userId,
        winnerTeam: null,
        isTie: false,
      );
    }
    if (sorted[0].score == sorted[1].score) {
      return const SosWinner(winnerUserId: null, winnerTeam: null, isTie: true);
    }
    return SosWinner(
      winnerUserId: sorted[0].userId,
      winnerTeam: null,
      isTie: false,
    );
  }

  // 4-player team mode: aggregate by team
  final teamScores = <SosTeam, int>{
    SosTeam.s: 0,
    SosTeam.o: 0,
  };
  for (final p in players) {
    if (p.team != null) {
      teamScores[p.team!] = teamScores[p.team!]! + p.score;
    }
  }
  if (teamScores[SosTeam.s]! == teamScores[SosTeam.o]!) {
    return const SosWinner(winnerUserId: null, winnerTeam: null, isTie: true);
  }
  final winnerTeam = teamScores[SosTeam.s]! > teamScores[SosTeam.o]!
      ? SosTeam.s
      : SosTeam.o;
  return SosWinner(
    winnerUserId: null,
    winnerTeam: winnerTeam,
    isTie: false,
  );
}

class SosWinner {
  const SosWinner({
    this.winnerUserId,
    this.winnerTeam,
    required this.isTie,
  });
  final String? winnerUserId;
  final SosTeam? winnerTeam;
  final bool isTie;
}

/// Assign teams for 4-player mode.
/// The host picks 4 players; this function distributes them into
/// Team S (turnOrder 0, 2) and Team O (turnOrder 1, 3).
/// Returns the team assignments as a map of userId → (team, turnOrder).
Map<String, (SosTeam, int)> assignTeamsFourPlayer(List<String> userIds) {
  final result = <String, (SosTeam, int)>{};
  for (int i = 0; i < userIds.length && i < 4; i++) {
    final userId = userIds[i];
    if (i == 0 || i == 2) {
      result[userId] = (SosTeam.s, i);
    } else {
      result[userId] = (SosTeam.o, i);
    }
  }
  return result;
}

// lib/features/games/flick_arena/flick_arena_engine.dart
//
// Pure Dart Flick Arena game logic — no Flutter dependencies, fully testable.
//
// Responsibilities:
//   • Build the initial board (discs per slot + ball at center)
//   • Evaluate a settled turn (was a goal scored? whose goal? did we win?)
//   • Compute the next turn's slot order (round-robin)
//   • Disc ownership check (a player can only flick their own discs)
//
// Physics (collision, friction, momentum, wall reflection) is handled by
// flick_arena_physics.dart using Forge2D. This file is the RULES layer only.
//
// The same engine contract is intended to support future physics-based
// games (Soccer Pool, Carrom Pool, Air Hockey, Knockout Arena, Target
// Strike, Trick Shot Challenge) — they reuse the Forge2D wrapper and
// provide their own rules file in this style.

import 'dart:math' as math;

import 'flick_arena_constants.dart';

/// A single disc on the arena.
///
/// Each disc is owned by exactly one player slot (1..4). Two discs per
/// slot. `isStriker` is true for the disc the owning player is about to
/// flick this turn — Flick Arena doesn't use a separate striker body
/// (every disc can be flicked, and you choose which of your two to use).
class FlickDisc {
  const FlickDisc({
    required this.id,
    required this.ownerSlot,
    required this.x,
    required this.y,
    this.isPotted = false,
  });

  final String id;
  final int ownerSlot;
  final double x;
  final double y;
  final bool isPotted;

  FlickDisc copyWith({double? x, double? y, bool? isPotted}) => FlickDisc(
        id: id,
        ownerSlot: ownerSlot,
        x: x ?? this.x,
        y: y ?? this.y,
        isPotted: isPotted ?? this.isPotted,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'ownerSlot': ownerSlot,
        'x': x,
        'y': y,
        'isPotted': isPotted,
      };

  factory FlickDisc.fromJson(Map<String, dynamic> json) => FlickDisc(
        id: (json['id'] ?? '') as String,
        ownerSlot: (json['ownerSlot'] as num?)?.toInt() ?? 1,
        x: (json['x'] as num?)?.toDouble() ?? 0,
        y: (json['y'] as num?)?.toDouble() ?? 0,
        isPotted: (json['isPotted'] as bool?) ?? false,
      );
}

/// The ball — what you flick into the goal to score.
class FlickBall {
  const FlickBall({required this.x, required this.y});

  final double x;
  final double y;

  FlickBall copyWith({double? x, double? y}) =>
      FlickBall(x: x ?? this.x, y: y ?? this.y);

  Map<String, dynamic> toJson() => {'x': x, 'y': y};

  factory FlickBall.fromJson(Map<String, dynamic> json) => FlickBall(
        x: (json['x'] as num?)?.toDouble() ?? 0,
        y: (json['y'] as num?)?.toDouble() ?? 0,
      );
}

/// Snapshot of the entire board — discs + ball + last shooter.
class FlickArenaState {
  const FlickArenaState({
    required this.discs,
    required this.ball,
    this.lastShooterSlot,
  });

  final List<FlickDisc> discs;
  final FlickBall ball;
  final int? lastShooterSlot;

  FlickArenaState copyWith({
    List<FlickDisc>? discs,
    FlickBall? ball,
    int? lastShooterSlot,
  }) =>
      FlickArenaState(
        discs: discs ?? this.discs,
        ball: ball ?? this.ball,
        lastShooterSlot: lastShooterSlot ?? this.lastShooterSlot,
      );

  Map<String, dynamic> toJson() => {
        'discs': discs.map((d) => d.toJson()).toList(),
        'ball': ball.toJson(),
        if (lastShooterSlot != null) 'lastShooterSlot': lastShooterSlot,
      };

  factory FlickArenaState.fromJson(Map<String, dynamic> json) {
    final rawDiscs = json['discs'];
    final discs = <FlickDisc>[];
    if (rawDiscs is List) {
      for (final d in rawDiscs) {
        if (d is Map) {
          discs.add(FlickDisc.fromJson(Map<String, dynamic>.from(d)));
        }
      }
    }
    final rawBall = json['ball'];
    final ball = rawBall is Map
        ? FlickBall.fromJson(Map<String, dynamic>.from(rawBall))
        : const FlickBall(x: 0, y: 0);
    final lastShooter = json['lastShooterSlot'];
    return FlickArenaState(
      discs: discs,
      ball: ball,
      lastShooterSlot: lastShooter is num ? lastShooter.toInt() : null,
    );
  }
}

/// Build the initial board for a match type.
///
/// Solo Duel: 2 discs per player (slots 1 + 2), ball at center.
/// Team Battle: 2 discs per player (slots 1..4), ball at center.
FlickArenaState createInitialBoard(FlickArenaMatchType matchType) {
  final slots = matchType == FlickArenaMatchType.teamBattle
      ? const [1, 2, 3, 4]
      : const [1, 2];

  final discs = <FlickDisc>[];
  for (final slot in slots) {
    // Solo Duel: slot 2 spawns at the TOP edge (slot 4's top-right
    // position, point-symmetric to slot 1's bottom-left) so the two
    // duelists start on opposite sides — slot 1 (team 1) defends the
    // bottom goal and shoots up; slot 2 (team 2) defends the top goal.
    final (sx, sy) = matchType == FlickArenaMatchType.soloDuel && slot == 2
        ? FlickArenaBoard.defaultDiscSpawns[4]!
        : FlickArenaBoard.defaultDiscSpawns[slot]!;
    // Two discs per slot — one at the default spawn, one offset slightly
    // so they don't overlap. The offset uses the perpendicular axis to
    // the spawn direction so the pair is visually side-by-side.
    discs.add(FlickDisc(
      id: 'disc-$slot-a',
      ownerSlot: slot,
      x: sx,
      y: sy,
    ));
    // Second disc: 1.4× the disc radius further from center, so the
    // pair is stacked defensively in front of the goal.
    final towardCenterY = sy < 0 ? sy + 0.18 : sy - 0.18;
    discs.add(FlickDisc(
      id: 'disc-$slot-b',
      ownerSlot: slot,
      x: sx,
      y: towardCenterY,
    ));
  }

  const ball = FlickBall(
    x: FlickArenaBoard.ballSpawnX,
    y: FlickArenaBoard.ballSpawnY,
  );

  return FlickArenaState(discs: discs, ball: ball);
}

/// The result of evaluating a settled turn.
class FlickTurnResult {
  const FlickTurnResult({
    required this.goalScored,
    this.goalForTeam,
    required this.nextSlot,
    required this.nextPlayerId,
    required this.updatedState,
    required this.teamOneScoreDelta,
    required this.teamTwoScoreDelta,
    required this.gameOver,
    this.winningTeam,
    this.winnerUserIds = const [],
    this.shotDistance = 0,
  });

  final bool goalScored;
  final int? goalForTeam;
  final int nextSlot;
  final String nextPlayerId;
  final FlickArenaState updatedState;
  final int teamOneScoreDelta;
  final int teamTwoScoreDelta;
  final bool gameOver;
  final int? winningTeam;
  final List<String> winnerUserIds;
  final double shotDistance;
}

/// Determine which team a slot belongs to.
///
/// Default assignment:
///   slots 1, 3 → team 1
///   slots 2, 4 → team 2
///
/// For Solo Duel this means slot 1 vs slot 2.
/// For Team Battle slot 1+3 vs slot 2+4.
///
/// The DB stores teamAssignment as JSONB, but in practice we keep the
/// default above for the v1 release. This helper centralizes the lookup.
int teamForSlot(int slot, Map<int, int>? assignment) {
  if (assignment != null && assignment.containsKey(slot)) {
    return assignment[slot]!;
  }
  // default: 1,3 → team 1; 2,4 → team 2
  return (slot % 2 == 1) ? 1 : 2;
}

/// Evaluate a settled turn.
///
/// [stateBefore] — board state at the start of the turn
/// [stateAfter]  — board state after physics has settled
/// [shooterSlot] — slot number of the player who flicked
/// [shooterUserId] — user id of the player who flicked
/// [currentSlot] — slot whose turn it was
/// [turnOrder] — array of slot numbers in turn order, e.g. [1,2] or [1,2,3,4]
/// [teamOneScore] — team 1's score before this turn
/// [teamTwoScore] — team 2's score before this turn
/// [matchType] — solo_duel or team_battle
/// [shotDistance] — physics-units distance the shooter disc traveled
FlickTurnResult evaluateTurn({
  required FlickArenaState stateBefore,
  required FlickArenaState stateAfter,
  required int shooterSlot,
  required String shooterUserId,
  required int currentSlot,
  required List<int> turnOrder,
  required int teamOneScore,
  required int teamTwoScore,
  required FlickArenaMatchType matchType,
  required double shotDistance,
}) {
  // 1) Did the ball cross a goal line?
  final ballAfter = stateAfter.ball;
  int? goalForTeam;
  bool goalScored = false;

  // Bottom goal: y is very negative → team 2 scores
  // Top goal: y is very positive → team 1 scores
  if (ballAfter.y <
      -FlickArenaBoard.halfHeight + FlickArenaBoard.goalTriggerDepth) {
    // Ball went into the BOTTOM goal → team 2 scores
    // (team 1 shoots UPWARD into the top goal, so the bottom goal is
    // team 1's own goal — team 2 is credited, since team 1 defended it)
    goalForTeam = FlickArenaBoard.bottomGoalTeam;
    goalScored = true;
  } else if (ballAfter.y >
      FlickArenaBoard.halfHeight - FlickArenaBoard.goalTriggerDepth) {
    // Ball went into the TOP goal → team 1 scores
    // (team 2 starts at the top and shoots downward into the bottom
    // goal, so the top goal is team 2's own goal — team 1 is credited)
    goalForTeam = FlickArenaBoard.topGoalTeam;
    goalScored = true;
  }

  // 2) Compute score deltas
  int teamOneDelta = 0;
  int teamTwoDelta = 0;
  if (goalScored) {
    if (goalForTeam == 1) {
      teamOneDelta = 1;
    } else if (goalForTeam == 2) {
      teamTwoDelta = 1;
    }
  }

  // 3) Determine next slot (round-robin)
  //    Goal scorer keeps the turn? No — Flick Arena always rotates. This
  //    keeps matches fair and avoids one player dominating. A goal does
  //    NOT grant an extra turn.
  final currentIndex = turnOrder.indexOf(currentSlot);
  final nextIndex = (currentIndex + 1) % turnOrder.length;
  final nextSlot = turnOrder[nextIndex];

  // 4) Win detection
  final newTeamOne = teamOneScore + teamOneDelta;
  final newTeamTwo = teamTwoScore + teamTwoDelta;
  final goalsToWin = matchType.goalsToWin;
  bool gameOver = false;
  int? winningTeam;
  List<String> winnerUserIds = const [];

  if (newTeamOne >= goalsToWin) {
    gameOver = true;
    winningTeam = 1;
  } else if (newTeamTwo >= goalsToWin) {
    gameOver = true;
    winningTeam = 2;
  }

  // 5) Build the updated state
  FlickArenaState updatedState = stateAfter.copyWith(
    lastShooterSlot: shooterSlot,
  );

  // If a goal was scored, reset the ball to center for the next turn.
  // (Discs stay where they landed — only the ball respawns.)
  if (goalScored) {
    updatedState = updatedState.copyWith(
      ball: const FlickBall(
        x: FlickArenaBoard.ballSpawnX,
        y: FlickArenaBoard.ballSpawnY,
      ),
    );
  }

  return FlickTurnResult(
    goalScored: goalScored,
    goalForTeam: goalForTeam,
    nextSlot: nextSlot,
    nextPlayerId: '', // populated by the provider using the game row
    updatedState: updatedState,
    teamOneScoreDelta: teamOneDelta,
    teamTwoScoreDelta: teamTwoDelta,
    gameOver: gameOver,
    winningTeam: winningTeam,
    winnerUserIds: winnerUserIds,
    shotDistance: shotDistance,
  );
}

/// Validate that a player can flick a given disc.
///
/// Rules:
///   • The disc must exist on the board (not potted).
///   • The disc must be owned by the current player's slot.
///   • It must be the current player's turn.
bool canFlickDisc({
  required FlickArenaState state,
  required String currentTurnPlayerId,
  required String flickerId,
  required String discId,
}) {
  if (currentTurnPlayerId != flickerId) return false;
  final disc = state.discs.where((d) => d.id == discId).firstOrNull;
  if (disc == null || disc.isPotted) return false;
  return true;
}

/// Find the disc owned by a slot that's closest to a tap position.
/// Returns null if no disc belongs to the slot.
FlickDisc? pickDiscForSlot({
  required FlickArenaState state,
  required int slot,
  required double tapX,
  required double tapY,
}) {
  FlickDisc? closest;
  double closestDist = double.infinity;
  final tap = math.Point<double>(tapX, tapY);
  for (final d in state.discs) {
    if (d.ownerSlot != slot || d.isPotted) continue;
    final dist = math.Point<double>(d.x, d.y).distanceTo(tap);
    if (dist < closestDist) {
      closestDist = dist;
      closest = d;
    }
  }
  return closest;
}

/// Default turn order for a match type.
List<int> defaultTurnOrder(FlickArenaMatchType matchType) {
  switch (matchType) {
    case FlickArenaMatchType.soloDuel:
      return const [1, 2];
    case FlickArenaMatchType.teamBattle:
      return const [1, 2, 3, 4];
  }
}

/// Default team assignment (slot → team).
Map<int, int> defaultTeamAssignment(FlickArenaMatchType matchType) {
  switch (matchType) {
    case FlickArenaMatchType.soloDuel:
      return const {1: 1, 2: 2};
    case FlickArenaMatchType.teamBattle:
      return const {1: 1, 2: 2, 3: 1, 4: 2};
  }
}

// lib/features/games/flick_arena/flick_arena_constants.dart
//
// Flick Arena — physics constants and arena dimensions.
//
// Uses Forge2D (BSD-3-Clause, Dart port of Box2D) for collision detection,
// friction, momentum, wall reflection and goal detection. Only the physics
// math is adapted from Forge2D — all UI, board art and disc visuals are
// original to Family Arena / Kinrel.
//
// Arena is a vertical rectangle (top-down view): goals at the top and
// bottom edges, discs (2 per player) start in two rows near their
// respective goal. The ball spawns at the center.

/// Arena dimensions in physics units (meters).
/// The arena is taller than wide — vertical orientation matches the
/// classic air-hockey / disc-football layout.
class FlickArenaBoard {
  FlickArenaBoard._();

  /// Arena spans X ∈ [-halfWidth, +halfWidth], Y ∈ [-halfHeight, +halfHeight].
  static const double halfWidth = 1.0;   // 2.0 wide
  static const double halfHeight = 1.5;  // 3.0 tall

  static const double fullWidth = halfWidth * 2;
  static const double fullHeight = halfHeight * 2;

  /// Goal mouth — centered on the top and bottom walls.
  static const double goalHalfWidth = 0.35; // 0.7 wide goal

  /// Goal trigger depth — once the ball crosses this line, it's a goal.
  /// Top goal: y > halfHeight - goalTriggerDepth
  /// Bottom goal: y < -halfHeight + goalTriggerDepth
  static const double goalTriggerDepth = 0.05;

  /// Top goal → team 1 scores (ball goes into top goal).
  /// Bottom goal → team 2 scores.
  /// (Reasoning: team 1 starts at the bottom and shoots upward into the
  /// top goal; team 2 starts at the top and shoots downward.)
  static const int topGoalTeam = 1;
  static const int bottomGoalTeam = 2;

  /// Default disc spawn positions per slot (1..4). Layout from the brief:
  ///   ┌──── goal ────┐   ← top (team 2 side)
  ///   ○          ○        ← slot 3, 4 (team 2)
  ///        ●             ← ball (center)
  ///   ○          ○        ← slot 1, 2 (team 1)
  ///   └──── goal ────┘   ← bottom (team 1 side)
  ///
  /// Slot 1 → bottom-left (team 1)
  /// Slot 2 → bottom-right (team 1)
  /// Slot 3 → top-left (team 2)
  /// Slot 4 → top-right (team 2)
  static const Map<int, (double, double)> defaultDiscSpawns = {
    1: (-0.55, -0.95),
    2: ( 0.55, -0.95),
    3: (-0.55,  0.95),
    4: ( 0.55,  0.95),
  };

  /// Ball spawns at the center. Exposed as separate consts so they can
  /// be used in const expressions (record-field access on a `(double,
  /// double)` const isn't supported by the const evaluator).
  static const double ballSpawnX = 0.0;
  static const double ballSpawnY = 0.0;
}

/// Physics parameters for discs, ball, and surface.
class FlickArenaPhysics {
  FlickArenaPhysics._();

  // ── Body radii ──────────────────────────────────────────────────
  static const double discRadius = 0.085;   // ~8.5cm on a 200cm-wide arena
  static const double ballRadius = 0.060;   // smaller than disc — easier to push

  // ── Densities (determines mass via area) ────────────────────────
  static const double discDensity = 2.0;
  static const double ballDensity = 1.0;    // lighter than discs — flicks send it flying
  static const double wallDensity = 0.0;    // static

  // ── Surface properties ──────────────────────────────────────────
  static const double friction = 0.18;            // low-friction ice-like surface
  static const double discRestitution = 0.65;     // discs bounce off each other
  static const double wallRestitution = 0.75;     // walls are lively — bank shots matter
  static const double ballRestitution = 0.55;

  // ── Damping (rolling friction / air resistance) ─────────────────
  static const double discLinearDamping = 0.45;
  static const double discAngularDamping = 0.6;
  static const double ballLinearDamping = 0.30;   // ball rolls further than discs
  static const double ballAngularDamping = 0.4;

  // ── Simulation ──────────────────────────────────────────────────
  static const double gravity = 0.0;          // top-down, zero gravity
  static const int velocityIterations = 10;
  static const int positionIterations = 4;
  static const double timeStep = 1.0 / 60.0;  // 60fps

  /// Velocity threshold below which a body is considered "at rest".
  static const double restThreshold = 0.04;

  /// Maximum flick force (normalized 0..1 maps to 0..maxForce).
  static const double maxForce = 7.5;

  /// Number of simulation steps before auto-stopping (safety valve).
  /// At 60fps, 720 steps = 12 seconds max.
  static const int maxSteps = 720;
}

/// Match types supported by Flick Arena.
enum FlickArenaMatchType { soloDuel, teamBattle }

extension FlickArenaMatchTypeX on FlickArenaMatchType {
  String get wire {
    switch (this) {
      case FlickArenaMatchType.soloDuel:
        return 'solo_duel';
      case FlickArenaMatchType.teamBattle:
        return 'team_battle';
    }
  }

  static FlickArenaMatchType fromString(String? s) {
    switch (s) {
      case 'team_battle':
        return FlickArenaMatchType.teamBattle;
      case 'solo_duel':
      default:
        return FlickArenaMatchType.soloDuel;
    }
  }

  String get label {
    switch (this) {
      case FlickArenaMatchType.soloDuel:
        return 'Solo Duel';
      case FlickArenaMatchType.teamBattle:
        return 'Team Battle';
    }
  }

  int get maxPlayers {
    switch (this) {
      case FlickArenaMatchType.soloDuel:
        return 2;
      case FlickArenaMatchType.teamBattle:
        return 4;
    }
  }

  int get goalsToWin {
    switch (this) {
      case FlickArenaMatchType.soloDuel:
        return 3;
      case FlickArenaMatchType.teamBattle:
        return 5;
    }
  }
}

/// Game status.
enum FlickArenaStatus { waiting, inProgress, completed }

extension FlickArenaStatusX on FlickArenaStatus {
  String get wire {
    switch (this) {
      case FlickArenaStatus.waiting:
        return 'waiting';
      case FlickArenaStatus.inProgress:
        return 'in_progress';
      case FlickArenaStatus.completed:
        return 'completed';
    }
  }

  static FlickArenaStatus fromString(String? s) {
    switch (s) {
      case 'in_progress':
        return FlickArenaStatus.inProgress;
      case 'completed':
        return FlickArenaStatus.completed;
      case 'waiting':
      default:
        return FlickArenaStatus.waiting;
    }
  }
}

/// Per-turn time budget.
const Duration kFlickArenaTurnDuration = Duration(seconds: 15);

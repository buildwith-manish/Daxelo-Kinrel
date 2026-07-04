// lib/features/games/carrom/carrom_constants.dart
//
// Physics constants and board dimensions for Carrom.
// Tuned from research: samiranrl/Carrom_rl (Pymunk) + Ashish-Pandey62/CarromBoard (Box2D).
// Expect iteration — these are starting values.

import 'package:forge2d/forge2d.dart';

/// Board dimensions in physics units (meters).
/// Standard Carrom board: 74×74 cm. We use a normalized coordinate system
/// where the board spans [-1, 1] on both axes (2×2 units = 74 cm).
class CarromBoard {
  CarromBoard._();

  /// Board spans from -1.0 to +1.0 on both X and Y axes.
  static const double halfSize = 1.0;
  static const double fullSize = 2.0;

  /// Pocket positions at the 4 corners, inset slightly from the edges.
  static const double pocketInset = 0.06; // ~3% inset
  static const double pocketRadius = 0.07; // ~1.1× striker radius

  static final List<Vector2> pocketPositions = [
    Vector2(-halfSize + pocketInset, -halfSize + pocketInset), // bottom-left
    Vector2(halfSize - pocketInset, -halfSize + pocketInset),  // bottom-right
    Vector2(-halfSize + pocketInset, halfSize - pocketInset),  // top-left
    Vector2(halfSize - pocketInset, halfSize - pocketInset),   // top-right
  ];

  /// Baseline positions (where the striker sits before flicking).
  /// Player 1 (bottom) baseline at y = -0.75, Player 2 (top) at y = +0.75.
  static const double baselineY1 = -0.75;
  static const double baselineY2 = 0.75;
  static const double baselineMinX = -0.7;
  static const double baselineMaxX = 0.7;
}

/// Physics parameters for coins, striker, and surface.
class CarromPhysics {
  CarromPhysics._();

  // ── Body radii ──────────────────────────────────────────────────
  static const double coinRadius = 0.045;    // ~4.5cm on a 74cm board
  static const double strikerRadius = 0.062; // ~6.2cm (1.37× coin)
  static const double queenRadius = 0.045;   // same as coin

  // ── Densities (determines mass via area) ────────────────────────
  static const double coinDensity = 1.0;
  static const double strikerDensity = 2.8;  // 2.8× coin mass
  static const double wallDensity = 0.0;     // static

  // ── Surface properties ──────────────────────────────────────────
  static const double friction = 0.4;        // board surface friction
  static const double coinRestitution = 0.5; // coin-coin bounce
  static const double wallRestitution = 0.4; // coin-wall bounce
  static const double strikerRestitution = 0.6;

  // ── Damping (simulates rolling friction / air resistance) ───────
  static const double linearDamping = 0.6;
  static const double angularDamping = 0.8;

  // ── Simulation ──────────────────────────────────────────────────
  static const double gravity = 0.0;         // top-down, zero gravity
  static const int velocityIterations = 8;
  static const int positionIterations = 3;
  static const double timeStep = 1.0 / 60.0; // 60fps

  /// Velocity threshold below which a body is considered "at rest".
  static const double restThreshold = 0.05;

  /// Maximum flick force (normalized 0-1 maps to 0 to maxForce).
  static const double maxForce = 8.0;

  /// Number of simulation steps before auto-stopping (safety valve).
  /// At 60fps, 600 steps = 10 seconds max.
  static const int maxSteps = 600;
}

/// Coin types on the board.
enum CarromCoinType { white, black, queen }

extension CarromCoinTypeX on CarromCoinType {
  String get name {
    switch (this) {
      case CarromCoinType.white:
        return 'white';
      case CarromCoinType.black:
        return 'black';
      case CarromCoinType.queen:
        return 'queen';
    }
  }

  static CarromCoinType fromString(String? s) {
    switch (s) {
      case 'black':
        return CarromCoinType.black;
      case 'queen':
        return CarromCoinType.queen;
      case 'white':
      default:
        return CarromCoinType.white;
    }
  }
}

/// Queen status through the game.
enum CarromQueenStatus { onBoard, pottedUncovered, pottedCovered }

extension CarromQueenStatusX on CarromQueenStatus {
  String get name {
    switch (this) {
      case CarromQueenStatus.onBoard:
        return 'on_board';
      case CarromQueenStatus.pottedUncovered:
        return 'potted_uncovered';
      case CarromQueenStatus.pottedCovered:
        return 'potted_covered';
    }
  }

  static CarromQueenStatus fromString(String? s) {
    switch (s) {
      case 'potted_uncovered':
        return CarromQueenStatus.pottedUncovered;
      case 'potted_covered':
        return CarromQueenStatus.pottedCovered;
      case 'on_board':
      default:
        return CarromQueenStatus.onBoard;
    }
  }
}

/// Game status.
enum CarromStatus { waiting, inProgress, completed }

extension CarromStatusX on CarromStatus {
  String get name {
    switch (this) {
      case CarromStatus.waiting:
        return 'waiting';
      case CarromStatus.inProgress:
        return 'in_progress';
      case CarromStatus.completed:
        return 'completed';
    }
  }

  static CarromStatus fromString(String? s) {
    switch (s) {
      case 'in_progress':
        return CarromStatus.inProgress;
      case 'completed':
        return CarromStatus.completed;
      case 'waiting':
      default:
        return CarromStatus.waiting;
    }
  }
}

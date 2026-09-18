// lib/features/games/flick_arena/flick_arena_physics.dart
//
// Forge2D physics wrapper for Flick Arena.
//
// Uses Forge2D (BSD-3-Clause, Dart port of Box2D) for:
//   • Collision detection (disc-disc, disc-ball, disc-wall, ball-wall)
//   • Velocity / momentum / friction
//   • Wall reflection (restitution)
//   • Goal detection (sensor zones at top + bottom)
//
// Architecture:
//   • World with zero gravity (top-down arena)
//   • Static EdgeShape bodies for the 4 board walls (with goal gaps)
//   • Dynamic CircleShape bodies for the ball + each non-potted disc
//   • linearDamping simulates rolling friction
//   • stepDt() advances the simulation at 60fps
//   • All bodies checked for rest → simulation stops → final state read
//
// This wrapper is intentionally reusable — Soccer Pool, Air Hockey,
// Carrom Pool, Knockout Arena, Target Strike and Trick Shot Challenge
// can all subclass or wrap this with their own arena shape + body count.

import 'dart:math' as math;

import 'package:forge2d/forge2d.dart';

import 'flick_arena_constants.dart';
import 'flick_arena_engine.dart';

class FlickArenaPhysicsEngine {
  FlickArenaPhysicsEngine();

  late final World _world;
  Body? _ball;
  final Map<String, Body> _discBodies = {}; // discId → body

  bool _isInitialized = false;

  /// Initialize the physics world with the given board state.
  void setup({
    required List<FlickDisc> discs,
    required FlickBall ball,
  }) {
    _world = World(Vector2(0, FlickArenaPhysics.gravity));

    _createWalls();

    _discBodies.clear();
    for (final disc in discs) {
      if (!disc.isPotted) {
        _discBodies[disc.id] = _createDiscBody(disc);
      }
    }

    _ball = _createBallBody(ball);
    _isInitialized = true;
  }

  // ── Walls ────────────────────────────────────────────────────────

  /// Build the 4 boundary walls, leaving a gap for each goal.
  /// Top wall has a goal gap centered on x=0 of width 2*goalHalfWidth.
  /// Same for bottom wall. Left and right walls are solid.
  void _createWalls() {
    final hw = FlickArenaBoard.halfWidth;
    final hh = FlickArenaBoard.halfHeight;
    final gw = FlickArenaBoard.goalHalfWidth;

    // Bottom wall: split into two segments to leave the goal gap
    _createWall(Vector2(-hw, -hh), Vector2(-gw, -hh)); // bottom-left
    _createWall(Vector2(gw, -hh), Vector2(hw, -hh)); // bottom-right

    // Top wall: split into two segments to leave the goal gap
    _createWall(Vector2(-hw, hh), Vector2(-gw, hh)); // top-left
    _createWall(Vector2(gw, hh), Vector2(hw, hh)); // top-right

    // Left wall (solid)
    _createWall(Vector2(-hw, -hh), Vector2(-hw, hh));

    // Right wall (solid)
    _createWall(Vector2(hw, -hh), Vector2(hw, hh));

    // Goal back-walls — invisible "catch" walls just behind the goals so
    // the ball can't escape the world after crossing the goal line. These
    // are slightly inside the world bounds so the goal trigger fires
    // before the ball bounces off the back wall.
    final backWallY = hh + 0.5;
    _createWall(Vector2(-gw, backWallY), Vector2(gw, backWallY));
    _createWall(Vector2(-gw, -backWallY), Vector2(gw, -backWallY));

    // Goal side walls — short segments that funnel the ball into the
    // goal mouth so it doesn't slip out sideways after crossing the line.
    final goalDepth = 0.3;
    _createWall(Vector2(-gw, -hh), Vector2(-gw, -hh - goalDepth));
    _createWall(Vector2(gw, -hh), Vector2(gw, -hh - goalDepth));
    _createWall(Vector2(-gw, hh), Vector2(-gw, hh + goalDepth));
    _createWall(Vector2(gw, hh), Vector2(gw, hh + goalDepth));
  }

  void _createWall(Vector2 v1, Vector2 v2) {
    final shape = EdgeShape()..set(v1, v2);

    final bodyDef = BodyDef()
      ..type = BodyType.static
      ..position = Vector2.zero();

    final body = _world.createBody(bodyDef);
    final fixtureDef = FixtureDef(shape)
      ..density = FlickArenaPhysics.wallDensity
      ..friction = FlickArenaPhysics.friction
      ..restitution = FlickArenaPhysics.wallRestitution;
    body.createFixture(fixtureDef);
  }

  // ── Discs ────────────────────────────────────────────────────────

  Body _createDiscBody(FlickDisc disc) {
    final shape = CircleShape()..radius = FlickArenaPhysics.discRadius;

    final bodyDef = BodyDef()
      ..type = BodyType.dynamic
      ..position = Vector2(disc.x, disc.y)
      ..linearDamping = FlickArenaPhysics.discLinearDamping
      ..angularDamping = FlickArenaPhysics.discAngularDamping;

    final body = _world.createBody(bodyDef);
    final fixtureDef = FixtureDef(shape)
      ..density = FlickArenaPhysics.discDensity
      ..friction = FlickArenaPhysics.friction
      ..restitution = FlickArenaPhysics.discRestitution;
    body.createFixture(fixtureDef);
    return body;
  }

  // ── Ball ─────────────────────────────────────────────────────────

  Body _createBallBody(FlickBall ball) {
    final shape = CircleShape()..radius = FlickArenaPhysics.ballRadius;

    final bodyDef = BodyDef()
      ..type = BodyType.dynamic
      ..position = Vector2(ball.x, ball.y)
      ..linearDamping = FlickArenaPhysics.ballLinearDamping
      ..angularDamping = FlickArenaPhysics.ballAngularDamping;

    final body = _world.createBody(bodyDef);
    final fixtureDef = FixtureDef(shape)
      ..density = FlickArenaPhysics.ballDensity
      ..friction = FlickArenaPhysics.friction
      ..restitution = FlickArenaPhysics.ballRestitution;
    body.createFixture(fixtureDef);
    return body;
  }

  // ── Flick ────────────────────────────────────────────────────────

  /// Apply a flick impulse to a disc.
  /// [discId] — id of the disc to flick (must be a non-potted disc).
  /// [angle] in radians, [power] normalized 0.0 to 1.0.
  ///
  /// Returns true if the flick was applied, false if the disc wasn't
  /// found or the engine wasn't initialized.
  bool flickDisc({
    required String discId,
    required double angle,
    required double power,
  }) {
    if (!_isInitialized) return false;
    final body = _discBodies[discId];
    if (body == null) return false;

    final force = power.clamp(0.0, 1.0) * FlickArenaPhysics.maxForce;
    final impulse = Vector2(
      force * math.cos(angle),
      force * math.sin(angle),
    );
    body.applyLinearImpulse(impulse);
    return true;
  }

  // ── Simulation ───────────────────────────────────────────────────

  /// Step the physics simulation by one frame.
  void step() {
    if (!_isInitialized) return;
    // Forge2D reads iterations from its top-level settings module; the
    // defaults (10 / 10) are adequate for our body count (~10 dynamic
    // bodies) and tuning them here would have negligible visual impact.
    _world.stepDt(FlickArenaPhysics.timeStep);
  }

  /// Check if all bodies have come to rest (velocity below threshold).
  bool isAtRest() {
    if (!_isInitialized) return true;
    final threshold = FlickArenaPhysics.restThreshold;

    if (_ball != null && _ball!.linearVelocity.length > threshold) {
      return false;
    }
    for (final body in _discBodies.values) {
      if (body.linearVelocity.length > threshold) return false;
    }
    return true;
  }

  /// Read the ball's current position.
  (double, double)? readBallPosition() {
    if (_ball == null) return null;
    final pos = _ball!.position;
    return (pos.x, pos.y);
  }

  /// Read the current positions of all discs.
  /// Returns a map of discId → (x, y).
  Map<String, (double, double)> readDiscPositions() {
    final positions = <String, (double, double)>{};
    for (final entry in _discBodies.entries) {
      final pos = entry.value.position;
      positions[entry.key] = (pos.x, pos.y);
    }
    return positions;
  }

  /// Total distance traveled by a specific disc since the simulation
  /// started (used for "longest shot" stat). We track it as the integral
  /// of |velocity| · dt across simulation steps.
  ///
  /// Caller is expected to call this once per step and accumulate.
  double readDiscSpeed(String discId) {
    final body = _discBodies[discId];
    if (body == null) return 0;
    return body.linearVelocity.length;
  }

  /// Check if the ball has crossed the top goal line.
  bool isTopGoal() {
    if (_ball == null) return false;
    final pos = _ball!.position;
    return pos.y >
        FlickArenaBoard.halfHeight - FlickArenaBoard.goalTriggerDepth;
  }

  /// Check if the ball has crossed the bottom goal line.
  bool isBottomGoal() {
    if (_ball == null) return false;
    final pos = _ball!.position;
    return pos.y <
        -FlickArenaBoard.halfHeight + FlickArenaBoard.goalTriggerDepth;
  }

  /// Clean up all physics resources.
  void dispose() {
    _discBodies.clear();
    _ball = null;
    _isInitialized = false;
  }
}

// lib/features/games/carrom/carrom_physics.dart
//
// Forge2D physics wrapper for Carrom.
//
// Uses Forge2D (BSD-3-Clause, Dart port of Box2D) for collision detection,
// friction, and momentum simulation. This is the "licensed math base" from
// the research phase — only the physics math is adapted from Forge2D; all
// UI, visual design, colors, and board art are original to Kinrel.
//
// Architecture:
//   • World with zero gravity (top-down board)
//   • Static EdgeShape bodies for 4 board walls
//   • Dynamic CircleShape bodies for striker + 19 coins
//   • linearDamping simulates rolling friction
//   • stepDt() advances the simulation at 60fps
//   • All bodies checked for rest → simulation stops → final state read

import 'dart:math' as math;

import 'package:forge2d/forge2d.dart';

import 'carrom_constants.dart';
import 'carrom_game_logic.dart';

class CarromPhysicsEngine {
  CarromPhysicsEngine();

  late final World _world;
  Body? _striker;
  final List<Body> _coinBodies = [];
  final List<int> _coinIndices = []; // maps body index to coin index

  bool _isInitialized = false;

  /// Initialize the physics world with the given board state.
  void setup({
    required List<CarromCoin> coins,
    required double strikerX,
    required double strikerY,
  }) {
    // Create world with zero gravity (top-down board)
    _world = World(Vector2(0, CarromPhysics.gravity));

    // Create board walls (4 edges)
    _createWalls();

    // Create coin bodies
    _coinBodies.clear();
    _coinIndices.clear();
    for (int i = 0; i < coins.length; i++) {
      if (!coins[i].isPotted) {
        final body = _createCoinBody(coins[i]);
        _coinBodies.add(body);
        _coinIndices.add(i);
      }
    }

    // Create striker body
    _striker = _createStrikerBody(strikerX, strikerY);
    _isInitialized = true;
  }

  void _createWalls() {
    final s = CarromBoard.halfSize;

    // Bottom wall
    _createWall(Vector2(-s, -s), Vector2(s, -s));
    // Top wall
    _createWall(Vector2(-s, s), Vector2(s, s));
    // Left wall
    _createWall(Vector2(-s, -s), Vector2(-s, s));
    // Right wall
    _createWall(Vector2(s, -s), Vector2(s, s));
  }

  void _createWall(Vector2 v1, Vector2 v2) {
    final shape = EdgeShape();
    shape.set(v1, v2);

    final bodyDef = BodyDef()
      ..type = BodyType.static
      ..position = Vector2.zero();

    final body = _world.createBody(bodyDef);
    final fixtureDef = FixtureDef(shape)
      ..density = CarromPhysics.wallDensity
      ..friction = CarromPhysics.friction
      ..restitution = CarromPhysics.wallRestitution;
    body.createFixture(fixtureDef);
  }

  Body _createCoinBody(CarromCoin coin) {
    final shape = CircleShape()..radius = CarromPhysics.coinRadius;

    final bodyDef = BodyDef()
      ..type = BodyType.dynamic
      ..position = Vector2(coin.x, coin.y)
      ..linearDamping = CarromPhysics.linearDamping
      ..angularDamping = CarromPhysics.angularDamping;

    final body = _world.createBody(bodyDef);
    final fixtureDef = FixtureDef(shape)
      ..density = CarromPhysics.coinDensity
      ..friction = CarromPhysics.friction
      ..restitution = CarromPhysics.coinRestitution;
    body.createFixture(fixtureDef);
    return body;
  }

  Body _createStrikerBody(double x, double y) {
    final shape = CircleShape()..radius = CarromPhysics.strikerRadius;

    final bodyDef = BodyDef()
      ..type = BodyType.dynamic
      ..position = Vector2(x, y)
      ..linearDamping = CarromPhysics.linearDamping
      ..angularDamping = CarromPhysics.angularDamping;

    final body = _world.createBody(bodyDef);
    final fixtureDef = FixtureDef(shape)
      ..density = CarromPhysics.strikerDensity
      ..friction = CarromPhysics.friction
      ..restitution = CarromPhysics.strikerRestitution;
    body.createFixture(fixtureDef);
    return body;
  }

  /// Apply a flick impulse to the striker.
  /// [angle] in radians, [power] normalized 0.0 to 1.0.
  void flickStriker(double angle, double power) {
    if (_striker == null || !_isInitialized) return;

    final force = power * CarromPhysics.maxForce;
    final impulse = Vector2(
      force * math.cos(angle),
      force * math.sin(angle),
    );
    _striker!.applyLinearImpulse(impulse);
  }

  /// Step the physics simulation by one frame.
  void step() {
    if (!_isInitialized) return;
    _world.stepDt(CarromPhysics.timeStep);
  }

  /// Check if all bodies have come to rest (velocity below threshold).
  bool isAtRest() {
    if (!_isInitialized) return true;

    final threshold = CarromPhysics.restThreshold;

    // Check striker
    if (_striker != null) {
      if (_striker!.linearVelocity.length > threshold) return false;
    }

    // Check all coins
    for (final body in _coinBodies) {
      if (body.linearVelocity.length > threshold) return false;
    }

    return true;
  }

  /// Check if the striker has entered a pocket.
  bool isStrikerPotted() {
    if (_striker == null) return false;
    final pos = _striker!.position;
    for (final pocket in CarromBoard.pocketPositions) {
      if ((pos - pocket).length < CarromBoard.pocketRadius) {
        return true;
      }
    }
    return false;
  }

  /// Check which coins have entered pockets.
  /// Returns a list of coin indices (into the original coins array).
  List<int> checkPottedCoins() {
    final potted = <int>[];
    for (int i = 0; i < _coinBodies.length; i++) {
      final body = _coinBodies[i];
      final pos = body.position;
      for (final pocket in CarromBoard.pocketPositions) {
        if ((pos - pocket).length < CarromBoard.pocketRadius) {
          potted.add(_coinIndices[i]);
          break;
        }
      }
    }
    return potted;
  }

  /// Read the current positions of all coins.
  /// Returns a map of coin index → (x, y).
  Map<int, (double, double)> readCoinPositions() {
    final positions = <int, (double, double)>{};
    for (int i = 0; i < _coinBodies.length; i++) {
      final pos = _coinBodies[i].position;
      positions[_coinIndices[i]] = (pos.x, pos.y);
    }
    return positions;
  }

  /// Read the striker's current position.
  (double, double)? readStrikerPosition() {
    if (_striker == null) return null;
    final pos = _striker!.position;
    return (pos.x, pos.y);
  }

  /// Remove potted coin bodies from the simulation (to prevent them
  /// from blocking other coins after they've entered a pocket).
  void removePottedCoins(List<int> coinIndices) {
    final indicesToRemove = <int>[];
    for (int i = 0; i < _coinBodies.length; i++) {
      if (coinIndices.contains(_coinIndices[i])) {
        indicesToRemove.add(i);
      }
    }
    // Remove in reverse order to maintain index validity
    for (final i in indicesToRemove.reversed) {
      _world.destroyBody(_coinBodies[i]);
      _coinBodies.removeAt(i);
      _coinIndices.removeAt(i);
    }
  }

  /// Remove the striker body (after it's potted — foul).
  void removeStriker() {
    if (_striker != null) {
      _world.destroyBody(_striker!);
      _striker = null;
    }
  }

  /// Clean up all physics resources.
  void dispose() {
    _coinBodies.clear();
    _coinIndices.clear();
    _striker = null;
    _isInitialized = false;
  }
}

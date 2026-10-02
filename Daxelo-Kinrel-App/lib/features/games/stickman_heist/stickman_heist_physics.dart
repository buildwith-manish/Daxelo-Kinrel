// lib/features/games/stickman_heist/stickman_heist_physics.dart
//
// Stickman Heist — Forge2D physics wrapper.
//
// Mirrors flick_arena_physics.dart's pattern: a self-contained class
// that owns a Forge2D World, exposes setup/step/readState methods and
// encapsulates collision detection for players, projectiles, treasure,
// escape zones and pickups.
//
// The host's StickmanHeistNotifier drives this engine:
//   • setup()          — once at match start (creates bodies from board)
//   • applyInput(...)  — per-input-frame for each player (movement, aim)
//   • step()           — 60fps physics tick
//   • checkCollisions()— after step, resolve bullet hits, treasure
//                        pickup, escape-zone reach, weapon/powerup
//                        pickups, respawns
//   • readState()      — copy physics positions back into the board
//                        state so the host can broadcast it
//
// Top-down view → zero gravity. Players are dynamic circles with high
// linear damping (so they stop when input stops). Projectiles are
// bullets — small circles with no damping. Walls are static EdgeShape
// bodies built from the map's wall list. Treasure/escape zones/pickups
// are sensors (no collision response, only BeginContact callbacks).

import 'dart:math' as math;

import 'package:forge2d/forge2d.dart';

import 'stickman_heist_engine.dart';

class StickmanHeistPhysicsEngine {
  StickmanHeistPhysicsEngine();

  late final World _world;
  bool _isInitialized = false;

  // Bodies keyed by player idx.
  final Map<int, Body> _playerBodies = {};

  // Projectiles keyed by their id.
  final Map<String, Body> _projectileBodies = {};

  // Treasure body — a sensor; no physics interaction, just position.
  Body? _treasureBody;

  // Escape-zone bodies — sensors.
  final List<Body> _escapeBodies = [];

  // Weapon / powerup spawns — kept as positions for overlap checks
  // (we don't create bodies for these; we manually check overlap with
  // players each tick to keep body count low and behavior predictable).
  final List<StickmanHeistWeaponSpawn> _weaponSpawns = [];
  final List<StickmanHeistPowerupSpawn> _powerupSpawns = [];

  // Cached board state — mutated in place by checkCollisions() so the
  // host can broadcast it via readState() without rebuilding.
  late StickmanHeistBoardState _board;

  // Per-player input state — set by applyInput(), consumed in step().
  final Map<int, _PlayerInput> _inputs = {};

  // ID counter for projectiles spawned by this engine instance.
  int _nextProjectileId = 0;

  // Random for respawn position jitter.
  final _rng = math.Random();

  // ── Setup ──────────────────────────────────────────────────────────

  /// Initialize the physics world from a board state. Creates all
  /// bodies (players, walls, treasure, escape zones, weapon/powerup
  /// spawn references).
  void setup(StickmanHeistBoardState board) {
    _world = World(Vector2(0, 0)); // zero gravity, top-down
    _board = board;

    _createOuterWalls();
    for (final wall in StickmanHeistMap.byId(board.mapId).walls) {
      _createWall(wall.x1, wall.y1, wall.x2, wall.y2);
    }

    _playerBodies.clear();
    for (final p in board.players) {
      _playerBodies[p.idx] = _createPlayerBody(p);
    }

    _treasureBody = _createTreasureBody(board.treasure);

    _escapeBodies.clear();
    for (final zone in board.escapeZones) {
      _escapeBodies.add(_createEscapeZoneBody(zone));
    }

    _weaponSpawns
      ..clear()
      ..addAll(board.weaponSpawns);
    _powerupSpawns
      ..clear()
      ..addAll(board.powerupSpawns);

    _isInitialized = true;
  }

  // ── Wall bodies ────────────────────────────────────────────────────

  void _createOuterWalls() {
    const hw = kStickmanHeistMapHalfWidth;
    const hh = kStickmanHeistMapHalfHeight;
    _createWall(-hw, -hh, hw, -hh); // bottom
    _createWall(-hw, hh, hw, hh); // top
    _createWall(-hw, -hh, -hw, hh); // left
    _createWall(hw, -hh, hw, hh); // right
  }

  void _createWall(double x1, double y1, double x2, double y2) {
    final shape = EdgeShape()..set(Vector2(x1, y1), Vector2(x2, y2));
    final bodyDef = BodyDef()
      ..type = BodyType.static
      ..position = Vector2.zero();
    final body = _world.createBody(bodyDef);
    final fixtureDef = FixtureDef(shape)
      ..density = 0
      ..friction = 0.4
      ..restitution = 0.0;
    body.createFixture(fixtureDef);
  }

  // ── Player bodies ──────────────────────────────────────────────────

  Body _createPlayerBody(StickmanHeistPlayer p) {
    final shape = CircleShape()..radius = kStickmanHeistPlayerRadius;
    final bodyDef = BodyDef()
      ..type = BodyType.dynamic
      ..position = Vector2(p.x, p.y)
      ..linearDamping = 8.0
      ..angularDamping = 8.0
      ..fixedRotation = true;
    final body = _world.createBody(bodyDef);
    final fixtureDef = FixtureDef(shape)
      ..density = 1.0
      ..friction = 0.0
      ..restitution = 0.0;
    body.createFixture(fixtureDef);
    return body;
  }

  // ── Treasure body ──────────────────────────────────────────────────

  Body _createTreasureBody(StickmanHeistTreasure t) {
    final shape = CircleShape()..radius = 0.4;
    final bodyDef = BodyDef()
      ..type = BodyType.static
      ..position = Vector2(t.x, t.y);
    final body = _world.createBody(bodyDef);
    final fixtureDef = FixtureDef(shape)
      ..isSensor = true
      ..density = 0;
    body.createFixture(fixtureDef);
    return body;
  }

  // ── Escape zone bodies ─────────────────────────────────────────────

  Body _createEscapeZoneBody(StickmanHeistEscapeZone zone) {
    final shape = CircleShape()..radius = zone.radius;
    final bodyDef = BodyDef()
      ..type = BodyType.static
      ..position = Vector2(zone.x, zone.y);
    final body = _world.createBody(bodyDef);
    final fixtureDef = FixtureDef(shape)
      ..isSensor = true
      ..density = 0;
    body.createFixture(fixtureDef);
    return body;
  }

  // ── Projectile bodies ──────────────────────────────────────────────

  Body _createProjectileBody(StickmanHeistProjectile p) {
    final shape = CircleShape()..radius = kStickmanHeistBulletRadius;
    final bodyDef = BodyDef()
      ..type = BodyType.dynamic
      ..position = Vector2(p.x, p.y)
      ..linearDamping = 0.0
      ..angularDamping = 0.0
      ..fixedRotation = true
      ..bullet = true;
    final body = _world.createBody(bodyDef);
    final fixtureDef = FixtureDef(shape)
      ..density = 0.05
      ..friction = 0.0
      ..restitution = 0.0;
    body.createFixture(fixtureDef);
    body.linearVelocity = Vector2(p.vx, p.vy);
    return body;
  }

  // ── Input ──────────────────────────────────────────────────────────

  /// Apply one input frame for a player. [moveX]/[moveY] are normalized
  /// -1..1 from the joystick. [aimAngle] is radians. [shooting] is
  /// true while the player holds the fire button. [reloadRequested]
  /// triggers a reload if the mag isn't full and we're not already
  /// reloading. [swapWeaponRequested] picks up the closest weapon spawn
  /// if the player is overlapping one.
  void applyInput(
    int playerIdx, {
    required double moveX,
    required double moveY,
    required double aimAngle,
    required bool shooting,
    required bool reloadRequested,
    required bool swapWeaponRequested,
  }) {
    _inputs[playerIdx] = _PlayerInput(
      moveX: moveX,
      moveY: moveY,
      aimAngle: aimAngle,
      shooting: shooting,
      reloadRequested: reloadRequested,
      swapWeaponRequested: swapWeaponRequested,
    );
  }

  // ── Simulation step ────────────────────────────────────────────────

  /// Advance the simulation by one frame (~16ms at 60fps).
  void step() {
    if (!_isInitialized) return;
    final now = DateTime.now().millisecondsSinceEpoch;

    // 1) Apply per-player inputs (movement, aim, shooting, reload).
    for (final player in _board.players) {
      final body = _playerBodies[player.idx];
      if (body == null) continue;
      final input = _inputs[player.idx];

      if (player.isAlive) {
        // Aim direction.
        if (input != null) {
          player.angle = input.aimAngle;
        }

        // Movement — set velocity directly for tight control.
        final speed = kStickmanHeistPlayerSpeed *
            (player.hasTreasure
                ? kStickmanHeistCarrierSpeedMultiplier
                : 1.0) *
            (player.hasSpeedBoost ? 1.5 : 1.0);
        if (input != null) {
          final mag = math.sqrt(
              input.moveX * input.moveX + input.moveY * input.moveY);
          if (mag > 0.05) {
            final nx = input.moveX / mag;
            final ny = input.moveY / mag;
            body.linearVelocity = Vector2(nx * speed, ny * speed);
          } else {
            body.linearVelocity = Vector2.zero();
          }
        } else {
          body.linearVelocity = Vector2.zero();
        }

        // Reload trigger.
        if (input?.reloadRequested == true &&
            !player.isReloading &&
            player.ammo < player.maxAmmo) {
          player.isReloading = true;
          player.reloadStartedAtMs = now;
        }
        // Reload completion.
        if (player.isReloading &&
            now - player.reloadStartedAtMs >= player.weapon.reloadMs) {
          player.ammo = player.maxAmmo;
          player.isReloading = false;
        }

        // Shooting — rate-limited by weapon.fireRateMs.
        if (input?.shooting == true &&
            !player.isReloading &&
            player.ammo > 0 &&
            now - player.lastShotAtMs >= player.weapon.fireRateMs) {
          player.lastShotAtMs = now;
          player.ammo -= 1;
          _fireWeapon(player, input!.aimAngle);
        }
      } else {
        body.linearVelocity = Vector2.zero();
      }
    }

    // 2) Step the physics world.
    _world.stepDt(1.0 / 60.0);

    // 3) Tick projectile lifetimes and remove dead ones.
    final deadProjectiles = <String>[];
    for (final proj in _board.projectiles) {
      proj.lifeMs -= 16;
      if (proj.lifeMs <= 0) deadProjectiles.add(proj.id);
    }
    for (final id in deadProjectiles) {
      _removeProjectile(id);
    }

    // 4) Copy body positions back into the board state.
    for (final player in _board.players) {
      final body = _playerBodies[player.idx];
      if (body == null) continue;
      player.x = body.position.x;
      player.y = body.position.y;
    }
    for (final proj in _board.projectiles) {
      final body = _projectileBodies[proj.id];
      if (body == null) continue;
      proj.x = body.position.x;
      proj.y = body.position.y;
      proj.vx = body.linearVelocity.x;
      proj.vy = body.linearVelocity.y;
    }

    // 5) Decrement match timer (wall-clock based to avoid drift).
    if (_board.matchStartTime > 0) {
      final elapsed = (now - _board.matchStartTime) ~/ 1000;
      _board.matchTimeRemaining =
          math.max(0, _board.matchSeconds - elapsed);
    }

    // 6) Phase transitions.
    if (_board.phase != StickmanHeistPhase.completed &&
        _board.matchTimeRemaining <= 0) {
      _board.phase = StickmanHeistPhase.completed;
      _board.status = 'completed';
      _board.winnerIdx = -1; // time out → no winner
      _board.events.insert(
          0,
          StickmanHeistEvent(
              kind: 'win',
              text: 'Time out — no one escaped!',
              atMs: now,
              color: 0xFFEF4444));
    }
  }

  void _fireWeapon(StickmanHeistPlayer player, double aimAngle) {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < player.weapon.pelletsPerShot; i++) {
      final spread = player.weapon.spread;
      final jitter =
          spread == 0 ? 0.0 : (_rng.nextDouble() * 2 - 1) * spread;
      final angle = aimAngle + jitter;
      final speed = player.weapon.bulletSpeed;
      final muzzleX = player.x +
          math.cos(angle) * (kStickmanHeistPlayerRadius + 0.05);
      final muzzleY = player.y +
          math.sin(angle) * (kStickmanHeistPlayerRadius + 0.05);
      final id = 'proj-${_nextProjectileId++}';
      final proj = StickmanHeistProjectile(
        id: id,
        x: muzzleX,
        y: muzzleY,
        vx: math.cos(angle) * speed,
        vy: math.sin(angle) * speed,
        ownerId: player.userId,
        ownerIdx: player.idx,
        damage: player.weapon.damage,
        lifeMs: kStickmanHeistProjectileLifeMs,
      );
      _board.projectiles.add(proj);
      _projectileBodies[id] = _createProjectileBody(proj);
    }
    // Auto-reload when the mag runs dry.
    if (player.ammo == 0 && !player.isReloading) {
      player.isReloading = true;
      player.reloadStartedAtMs = now;
    }
  }

  void _removeProjectile(String id) {
    final body = _projectileBodies.remove(id);
    if (body != null) {
      try {
        _world.destroyBody(body);
      } catch (_) {}
    }
    _board.projectiles.removeWhere((p) => p.id == id);
  }

  // ── Collision checks ───────────────────────────────────────────────

  /// Run all collision checks (bullet hits, treasure, escape zones,
  /// weapon/powerup pickups, respawns). Call once per step.
  void checkCollisions() {
    if (!_isInitialized) return;
    _checkProjectileHits();
    _checkTreasurePickup();
    _checkEscapeZone();
    _checkWeaponPickups();
    _checkPowerupPickups();
    _respawnDeadPlayers();
  }

  void _checkProjectileHits() {
    if (_board.projectiles.isEmpty) return;
    final toRemove = <String>[];
    for (final proj in _board.projectiles) {
      // Hit-test against every alive player except the owner.
      for (final player in _board.players) {
        if (!player.isAlive) continue;
        if (player.idx == proj.ownerIdx) continue;
        final r = kStickmanHeistPlayerRadius + kStickmanHeistBulletRadius;
        final dx = player.x - proj.x;
        final dy = player.y - proj.y;
        if (dx * dx + dy * dy <= r * r) {
          // Hit!
          _applyDamage(player, proj.damage, proj.ownerIdx);
          toRemove.add(proj.id);
          break;
        }
      }
    }
    for (final id in toRemove) {
      _removeProjectile(id);
    }
  }

  void _applyDamage(
      StickmanHeistPlayer target, int damage, int attackerIdx) {
    final now = DateTime.now().millisecondsSinceEpoch;
    var remaining = damage;
    if (target.shieldActive) {
      // Shield absorbs up to 50 damage then breaks.
      const shieldAbsorb = 50;
      if (remaining <= shieldAbsorb) {
        // Shield holds; no health damage.
        return;
      }
      remaining -= shieldAbsorb;
      target.shieldActive = false;
    }
    target.health = math.max(0, target.health - remaining);
    if (target.health == 0) {
      target.isAlive = false;
      target.deaths += 1;
      target.respawnAt = _board.respawnsEnabled
          ? now + kStickmanHeistRespawnSeconds * 1000
          : 0;
      // Attribute kill.
      final attacker = _board.players
          .where((p) => p.idx == attackerIdx)
          .firstOrNull;
      if (attacker != null) {
        attacker.kills += 1;
      }
      // Treasure drop.
      if (target.hasTreasure) {
        target.hasTreasure = false;
        _board.treasure
          ..carrierIdx = -1
          ..x = target.x
          ..y = target.y
          ..collected = false;
        _board.phase = StickmanHeistPhase.searching;
        for (final z in _board.escapeZones) {
          z.active = false;
        }
        // Move the treasure body back to the drop point.
        if (_treasureBody != null) {
          _treasureBody!.setTransform(
              Vector2(target.x, target.y), 0);
        }
        _board.events.insert(
            0,
            StickmanHeistEvent(
                kind: 'drop',
                text: '${target.name} dropped the treasure!',
                atMs: now,
                color: 0xFFEF4444));
      }
      _board.events.insert(
          0,
          StickmanHeistEvent(
              kind: 'kill',
              text:
                  '${attacker?.name ?? 'A player'} eliminated ${target.name}',
              atMs: now,
              color: 0xFFEF4444));
    }
  }

  void _checkTreasurePickup() {
    if (!_board.treasure.isOnGround) return;
    for (final player in _board.players) {
      if (!player.isAlive) continue;
      final r = kStickmanHeistPlayerRadius + 0.4;
      final dx = player.x - _board.treasure.x;
      final dy = player.y - _board.treasure.y;
      if (dx * dx + dy * dy <= r * r) {
        // Pick up!
        player.hasTreasure = true;
        _board.treasure
          ..carrierIdx = player.idx
          ..collected = true;
        _board.phase = StickmanHeistPhase.carrierActive;
        for (final z in _board.escapeZones) {
          z.active = true;
        }
        final now = DateTime.now().millisecondsSinceEpoch;
        _board.events.insert(
            0,
            StickmanHeistEvent(
                kind: 'pickup',
                text: '${player.name} grabbed the treasure!',
                atMs: now,
                color: 0xFFF59E0B));
        break;
      }
    }
  }

  void _checkEscapeZone() {
    final carrier = _board.carrier;
    if (carrier == null || !carrier.isAlive) return;
    for (final zone in _board.escapeZones) {
      if (!zone.active) continue;
      final r = zone.radius + kStickmanHeistPlayerRadius;
      final dx = carrier.x - zone.x;
      final dy = carrier.y - zone.y;
      if (dx * dx + dy * dy <= r * r) {
        // Escape!
        _board.phase = StickmanHeistPhase.completed;
        _board.status = 'completed';
        _board.winnerIdx = carrier.idx;
        final now = DateTime.now().millisecondsSinceEpoch;
        _board.events.insert(
            0,
            StickmanHeistEvent(
                kind: 'win',
                text:
                    '${carrier.name} escaped with the treasure! Victory!',
                atMs: now,
                color: 0xFF10B981));
        return;
      }
    }
  }

  void _checkWeaponPickups() {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final player in _board.players) {
      if (!player.isAlive) continue;
      final input = _inputs[player.idx];
      if (input?.swapWeaponRequested != true) continue;
      for (final spawn in _weaponSpawns) {
        if (spawn.taken && now < spawn.respawnAtMs) continue;
        final r = kStickmanHeistPlayerRadius + 0.4;
        final dx = player.x - spawn.x;
        final dy = player.y - spawn.y;
        if (dx * dx + dy * dy <= r * r) {
          // Swap weapon. We don't drop the old weapon — keep it simple.
          player.weapon = spawn.weapon;
          player.maxAmmo = spawn.weapon.magSize;
          player.ammo = spawn.weapon.magSize;
          player.isReloading = false;
          // Mark spawn as taken; schedule respawn in 15s.
          spawn.taken = true;
          spawn.respawnAtMs = now + 15000;
          // Also update the board's copy.
          final boardSpawn = _board.weaponSpawns
              .where((w) => w.x == spawn.x && w.y == spawn.y)
              .firstOrNull;
          if (boardSpawn != null) {
            boardSpawn.taken = true;
            boardSpawn.respawnAtMs = spawn.respawnAtMs;
          }
          break;
        }
      }
    }
    // Respawn weapons whose cooldown elapsed.
    for (final spawn in _board.weaponSpawns) {
      if (spawn.taken && now >= spawn.respawnAtMs) {
        spawn.taken = false;
        spawn.respawnAtMs = 0;
      }
    }
  }

  void _checkPowerupPickups() {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final player in _board.players) {
      if (!player.isAlive) continue;
      for (final spawn in _powerupSpawns) {
        if (spawn.taken && now < spawn.respawnAtMs) continue;
        final r = kStickmanHeistPlayerRadius + 0.4;
        final dx = player.x - spawn.x;
        final dy = player.y - spawn.y;
        if (dx * dx + dy * dy <= r * r) {
          _applyPowerup(player, spawn.type);
          spawn.taken = true;
          spawn.respawnAtMs = now + 20000;
          final boardSpawn = _board.powerupSpawns
              .where((p) => p.x == spawn.x && p.y == spawn.y)
              .firstOrNull;
          if (boardSpawn != null) {
            boardSpawn.taken = true;
            boardSpawn.respawnAtMs = spawn.respawnAtMs;
          }
          break;
        }
      }
    }
    for (final spawn in _board.powerupSpawns) {
      if (spawn.taken && now >= spawn.respawnAtMs) {
        spawn.taken = false;
        spawn.respawnAtMs = 0;
      }
    }
  }

  void _applyPowerup(
      StickmanHeistPlayer player, StickmanHeistPowerupType type) {
    final now = DateTime.now().millisecondsSinceEpoch;
    switch (type) {
      case StickmanHeistPowerupType.health:
        player.health =
            math.min(player.maxHealth, player.health + 50);
        break;
      case StickmanHeistPowerupType.ammo:
        player.ammo = player.maxAmmo;
        player.isReloading = false;
        break;
      case StickmanHeistPowerupType.shield:
        player.shieldActive = true;
        break;
      case StickmanHeistPowerupType.speed:
        player.speedBoostUntil = now + 5000;
        break;
    }
  }

  void _respawnDeadPlayers() {
    if (!_board.respawnsEnabled) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final map = StickmanHeistMap.byId(_board.mapId);
    for (final player in _board.players) {
      if (player.isAlive) continue;
      if (player.respawnAt == 0) continue;
      if (now < player.respawnAt) continue;
      // Respawn at a random spawn point away from the treasure.
      final candidates = <(double, double)>[];
      for (final sp in map.spawnPoints) {
        final dx = sp.$1 - _board.treasure.x;
        final dy = sp.$2 - _board.treasure.y;
        if (dx * dx + dy * dy > 9) candidates.add(sp);
      }
      if (candidates.isEmpty) candidates.addAll(map.spawnPoints);
      final pick = candidates[_rng.nextInt(candidates.length)];
      player.isAlive = true;
      player.health = player.maxHealth;
      player.ammo = player.maxAmmo;
      player.isReloading = false;
      player.shieldActive = false;
      player.speedBoostUntil = 0;
      player.respawnAt = 0;
      player.x = pick.$1;
      player.y = pick.$2;
      final body = _playerBodies[player.idx];
      if (body != null) {
        body.setTransform(Vector2(pick.$1, pick.$2), 0);
        body.linearVelocity = Vector2.zero();
      }
    }
  }

  // ── Read state ─────────────────────────────────────────────────────

  /// Returns the current board state (mutated in place during steps).
  /// The host serializes this and broadcasts it.
  StickmanHeistBoardState readState() => _board;

  // ── Spawn a single projectile (manual — used by host for one-shots) ─

  /// Manually spawn a projectile from a player at [angle] using
  /// [weapon]'s stats. Used for power-shot powerups or testing.
  void spawnProjectile(
      int ownerIdx, double angle, StickmanHeistWeapon weapon) {
    final player = _board.players
        .where((p) => p.idx == ownerIdx)
        .firstOrNull;
    if (player == null) return;
    final id = 'proj-${_nextProjectileId++}';
    final muzzleX = player.x +
        math.cos(angle) * (kStickmanHeistPlayerRadius + 0.05);
    final muzzleY = player.y +
        math.sin(angle) * (kStickmanHeistPlayerRadius + 0.05);
    final speed = weapon.bulletSpeed;
    final proj = StickmanHeistProjectile(
      id: id,
      x: muzzleX,
      y: muzzleY,
      vx: math.cos(angle) * speed,
      vy: math.sin(angle) * speed,
      ownerId: player.userId,
      ownerIdx: ownerIdx,
      damage: weapon.damage,
      lifeMs: kStickmanHeistProjectileLifeMs,
    );
    _board.projectiles.add(proj);
    _projectileBodies[id] = _createProjectileBody(proj);
  }

  // ── Convenience wrappers used by the host loop ─────────────────────

  void checkTreasurePickup() => _checkTreasurePickup();
  void checkEscapeZone() => _checkEscapeZone();
  void respawnDeadPlayers() => _respawnDeadPlayers();

  // ── Teardown ───────────────────────────────────────────────────────

  void dispose() {
    _playerBodies.clear();
    _projectileBodies.clear();
    _escapeBodies.clear();
    _treasureBody = null;
    _weaponSpawns.clear();
    _powerupSpawns.clear();
    _inputs.clear();
    _isInitialized = false;
  }
}

/// Internal per-player input frame.
class _PlayerInput {
  const _PlayerInput({
    required this.moveX,
    required this.moveY,
    required this.aimAngle,
    required this.shooting,
    required this.reloadRequested,
    required this.swapWeaponRequested,
  });

  final double moveX;
  final double moveY;
  final double aimAngle;
  final bool shooting;
  final bool reloadRequested;
  final bool swapWeaponRequested;
}

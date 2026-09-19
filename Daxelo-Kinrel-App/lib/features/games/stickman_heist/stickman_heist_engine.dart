// lib/features/games/stickman_heist/stickman_heist_engine.dart
//
// Stickman Heist — pure Dart game logic (no Flutter, fully testable).
//
// Real-time 2-8 player top-down treasure-hunt shooter. Players spawn on
// a map. A treasure spawns randomly. The first player to find it becomes
// the "carrier" (revealed to all). The carrier must reach an escape zone
// to win. Other players hunt the carrier. If the carrier is killed, the
// treasure drops and anyone can pick it up. Match time limit (default 3
// minutes).
//
// This file is the RULES + STATE layer. Physics (collision, movement,
// projectile integration) is handled by stickman_heist_physics.dart
// using Forge2D — but the engine owns the canonical board state and the
// phase transitions.
//
// Match phases:
//   searching     → treasure on the ground, no carrier yet
//   carrierActive → a player picked up the treasure; escape zones armed
//   escapePhase   → carrier has 30s to reach an escape zone (escape
//                   zones pulse). Sub-phase of carrierActive really,
//                   but separated for the HUD banner.
//   completed     → match over (carrier escaped, time out, or walkover)
//
// Host-authoritative model: the host runs this engine + Forge2D physics
// at 60fps, broadcasting the full board state ~10Hz via Supabase RPC
// fn_stickmanheist_broadcast_state. Non-host clients only render the
// state they receive and send their inputs.

import 'dart:math' as math;

// ── Constants ────────────────────────────────────────────────────────

/// Minimum players to start a match.
const int kStickmanHeistMinPlayers = 2;

/// Maximum players in a single match.
const int kStickmanHeistMaxPlayers = 8;

/// Player body radius in physics units (meters).
const double kStickmanHeistPlayerRadius = 0.35;

/// Bullet body radius in physics units.
const double kStickmanHeistBulletRadius = 0.06;

/// Map half-width (the playable area spans X ∈ [-10, +10]).
const double kStickmanHeistMapHalfWidth = 10.0;

/// Map half-height (the playable area spans Y ∈ [-10, +10]).
const double kStickmanHeistMapHalfHeight = 10.0;

/// Player movement speed in physics units / second.
const double kStickmanHeistPlayerSpeed = 5.0;

/// Carrier moves 10% slower than everyone else (encumbrance).
const double kStickmanHeistCarrierSpeedMultiplier = 0.9;

/// Host broadcasts full state every 100ms (10Hz).
const int kStickmanHeistBroadcastIntervalMs = 100;

/// Host polls the inputs table every 50ms (20Hz).
const int kStickmanHeistInputPollIntervalMs = 50;

/// Respawn delay in seconds after death.
const int kStickmanHeistRespawnSeconds = 5;

/// Projectile lifetime in milliseconds — bullets auto-despawn after this.
const int kStickmanHeistProjectileLifeMs = 1500;

/// Player health and max health at spawn.
const int kStickmanHeistDefaultHealth = 100;

// ── Enums ────────────────────────────────────────────────────────────

/// Match phase — drives HUD banner and which escape zones are armed.
enum StickmanHeistPhase {
  searching,
  carrierActive,
  escapePhase,
  completed,
}

extension StickmanHeistPhaseX on StickmanHeistPhase {
  String get wire {
    switch (this) {
      case StickmanHeistPhase.searching:
        return 'searching';
      case StickmanHeistPhase.carrierActive:
        return 'carrierActive';
      case StickmanHeistPhase.escapePhase:
        return 'escapePhase';
      case StickmanHeistPhase.completed:
        return 'completed';
    }
  }

  static StickmanHeistPhase fromString(String? s) {
    switch (s) {
      case 'carrierActive':
        return StickmanHeistPhase.carrierActive;
      case 'escapePhase':
        return StickmanHeistPhase.escapePhase;
      case 'completed':
        return StickmanHeistPhase.completed;
      case 'searching':
      default:
        return StickmanHeistPhase.searching;
    }
  }

  String get label {
    switch (this) {
      case StickmanHeistPhase.searching:
        return 'Searching';
      case StickmanHeistPhase.carrierActive:
        return 'Carrier Identified';
      case StickmanHeistPhase.escapePhase:
        return 'Escape!';
      case StickmanHeistPhase.completed:
        return 'Match Over';
    }
  }
}

/// Weapon archetypes. Each has its own damage, fire rate, spread, etc.
enum StickmanHeistWeapon {
  pistol,
  shotgun,
  smg,
  sniper,
}

extension StickmanHeistWeaponX on StickmanHeistWeapon {
  String get wire {
    switch (this) {
      case StickmanHeistWeapon.pistol:
        return 'pistol';
      case StickmanHeistWeapon.shotgun:
        return 'shotgun';
      case StickmanHeistWeapon.smg:
        return 'smg';
      case StickmanHeistWeapon.sniper:
        return 'sniper';
    }
  }

  static StickmanHeistWeapon fromString(String? s) {
    switch (s) {
      case 'shotgun':
        return StickmanHeistWeapon.shotgun;
      case 'smg':
        return StickmanHeistWeapon.smg;
      case 'sniper':
        return StickmanHeistWeapon.sniper;
      case 'pistol':
      default:
        return StickmanHeistWeapon.pistol;
    }
  }

  String get label {
    switch (this) {
      case StickmanHeistWeapon.pistol:
        return 'Pistol';
      case StickmanHeistWeapon.shotgun:
        return 'Shotgun';
      case StickmanHeistWeapon.smg:
        return 'SMG';
      case StickmanHeistWeapon.sniper:
        return 'Sniper';
    }
  }

  /// Per-hit damage (before shield).
  int get damage {
    switch (this) {
      case StickmanHeistWeapon.pistol:
        return 18;
      case StickmanHeistWeapon.shotgun:
        return 14; // per pellet — shotgun fires 5 pellets
      case StickmanHeistWeapon.smg:
        return 12;
      case StickmanHeistWeapon.sniper:
        return 80;
    }
  }

  /// Minimum ms between shots.
  int get fireRateMs {
    switch (this) {
      case StickmanHeistWeapon.pistol:
        return 250;
      case StickmanHeistWeapon.shotgun:
        return 800;
      case StickmanHeistWeapon.smg:
        return 90;
      case StickmanHeistWeapon.sniper:
        return 1200;
    }
  }

  /// Bullet speed in physics units / second.
  double get bulletSpeed {
    switch (this) {
      case StickmanHeistWeapon.pistol:
        return 22.0;
      case StickmanHeistWeapon.shotgun:
        return 16.0;
      case StickmanHeistWeapon.smg:
        return 20.0;
      case StickmanHeistWeapon.sniper:
        return 40.0;
    }
  }

  /// Magazine size (shots per reload).
  int get magSize {
    switch (this) {
      case StickmanHeistWeapon.pistol:
        return 12;
      case StickmanHeistWeapon.shotgun:
        return 6;
      case StickmanHeistWeapon.smg:
        return 30;
      case StickmanHeistWeapon.sniper:
        return 5;
    }
  }

  /// Reload time in ms.
  int get reloadMs {
    switch (this) {
      case StickmanHeistWeapon.pistol:
        return 1100;
      case StickmanHeistWeapon.shotgun:
        return 1800;
      case StickmanHeistWeapon.smg:
        return 1500;
      case StickmanHeistWeapon.sniper:
        return 2200;
    }
  }

  /// Bullet spread in radians (±). 0 = perfectly accurate.
  double get spread {
    switch (this) {
      case StickmanHeistWeapon.pistol:
        return 0.03;
      case StickmanHeistWeapon.shotgun:
        return 0.18;
      case StickmanHeistWeapon.smg:
        return 0.08;
      case StickmanHeistWeapon.sniper:
        return 0.0;
    }
  }

  /// Number of pellets fired per shot (shotgun = 5, others = 1).
  int get pelletsPerShot {
    switch (this) {
      case StickmanHeistWeapon.shotgun:
        return 5;
      case StickmanHeistWeapon.pistol:
      case StickmanHeistWeapon.smg:
      case StickmanHeistWeapon.sniper:
        return 1;
    }
  }

  /// Accent color used by the HUD and the map painter for spawn icons.
  int get accentArgb {
    switch (this) {
      case StickmanHeistWeapon.pistol:
        return 0xFF94A3B8; // slate
      case StickmanHeistWeapon.shotgun:
        return 0xFFEF4444; // red
      case StickmanHeistWeapon.smg:
        return 0xFF22D3EE; // cyan
      case StickmanHeistWeapon.sniper:
        return 0xFFA855F7; // purple
    }
  }
}

/// Powerup types that can spawn on the map.
enum StickmanHeistPowerupType {
  health,
  ammo,
  shield,
  speed,
}

extension StickmanHeistPowerupTypeX on StickmanHeistPowerupType {
  String get wire {
    switch (this) {
      case StickmanHeistPowerupType.health:
        return 'health';
      case StickmanHeistPowerupType.ammo:
        return 'ammo';
      case StickmanHeistPowerupType.shield:
        return 'shield';
      case StickmanHeistPowerupType.speed:
        return 'speed';
    }
  }

  static StickmanHeistPowerupType fromString(String? s) {
    switch (s) {
      case 'ammo':
        return StickmanHeistPowerupType.ammo;
      case 'shield':
        return StickmanHeistPowerupType.shield;
      case 'speed':
        return StickmanHeistPowerupType.speed;
      case 'health':
      default:
        return StickmanHeistPowerupType.health;
    }
  }

  String get label {
    switch (this) {
      case StickmanHeistPowerupType.health:
        return 'Health';
      case StickmanHeistPowerupType.ammo:
        return 'Ammo';
      case StickmanHeistPowerupType.shield:
        return 'Shield';
      case StickmanHeistPowerupType.speed:
        return 'Speed';
    }
  }

  /// Accent color used by the painter for spawn icons.
  int get accentArgb {
    switch (this) {
      case StickmanHeistPowerupType.health:
        return 0xFF10B981; // emerald
      case StickmanHeistPowerupType.ammo:
        return 0xFFF59E0B; // amber
      case StickmanHeistPowerupType.shield:
        return 0xFF3B82F6; // blue
      case StickmanHeistPowerupType.speed:
        return 0xFFEC4899; // pink
    }
  }
}

// ── Map ──────────────────────────────────────────────────────────────

/// A rectangular wall segment in physics coordinates.
class StickmanHeistWall {
  const StickmanHeistWall({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
  });

  final double x1;
  final double y1;
  final double x2;
  final double y2;

  Map<String, dynamic> toJson() => {
        'x1': x1,
        'y1': y1,
        'x2': x2,
        'y2': y2,
      };

  factory StickmanHeistWall.fromJson(Map<String, dynamic> json) =>
      StickmanHeistWall(
        x1: (json['x1'] as num?)?.toDouble() ?? 0,
        y1: (json['y1'] as num?)?.toDouble() ?? 0,
        x2: (json['x2'] as num?)?.toDouble() ?? 0,
        y2: (json['y2'] as num?)?.toDouble() ?? 0,
      );
}

/// A map definition — id, name, walls (obstacles), spawn points, escape
/// zone label prefix. Three maps ship in v1: bank, museum, warehouse.
class StickmanHeistMap {
  const StickmanHeistMap({
    required this.id,
    required this.name,
    required this.walls,
    required this.spawnPoints,
    required this.escapeZoneLabel,
  });

  final String id;
  final String name;
  final List<StickmanHeistWall> walls;
  final List<(double, double)> spawnPoints;
  final String escapeZoneLabel;

  static const bank = StickmanHeistMap(
    id: 'bank',
    name: 'Bank Vault',
    escapeZoneLabel: 'EXIT',
    walls: [
      // Outer perimeter is implicit (physics adds it); these are
      // interior cover walls — a vault layout with central pillars and
      // a safe-room in the middle.
      StickmanHeistWall(x1: -6, y1: -6, x2: -6, y2: -2),
      StickmanHeistWall(x1: -6, y1: -2, x2: -2, y2: -2),
      StickmanHeistWall(x1: 2, y1: -6, x2: 6, y2: -6),
      StickmanHeistWall(x1: 6, y1: -6, x2: 6, y2: -2),
      StickmanHeistWall(x1: -6, y1: 2, x2: -6, y2: 6),
      StickmanHeistWall(x1: -6, y1: 2, x2: -2, y2: 2),
      StickmanHeistWall(x1: 2, y1: 6, x2: 6, y2: 6),
      StickmanHeistWall(x1: 6, y1: 2, x2: 6, y2: 6),
      // Central vault — small box in the middle for cover.
      StickmanHeistWall(x1: -1.5, y1: -1.5, x2: 1.5, y2: -1.5),
      StickmanHeistWall(x1: 1.5, y1: -1.5, x2: 1.5, y2: 1.5),
      StickmanHeistWall(x1: -1.5, y1: 1.5, x2: 1.5, y2: 1.5),
      StickmanHeistWall(x1: -1.5, y1: -1.5, x2: -1.5, y2: 1.5),
    ],
    spawnPoints: [
      (-8, -8),
      (8, -8),
      (-8, 8),
      (8, 8),
      (-4, 0),
      (4, 0),
      (0, -4),
      (0, 4),
    ],
  );

  static const museum = StickmanHeistMap(
    id: 'museum',
    name: 'Museum',
    escapeZoneLabel: 'EXIT',
    walls: [
      // Museum layout — long gallery walls with exhibit nooks.
      StickmanHeistWall(x1: -8, y1: -3, x2: -3, y2: -3),
      StickmanHeistWall(x1: 3, y1: -3, x2: 8, y2: -3),
      StickmanHeistWall(x1: -8, y1: 3, x2: -3, y2: 3),
      StickmanHeistWall(x1: 3, y1: 3, x2: 8, y2: 3),
      StickmanHeistWall(x1: -3, y1: -3, x2: -3, y2: -8),
      StickmanHeistWall(x1: 3, y1: -3, x2: 3, y2: -8),
      StickmanHeistWall(x1: -3, y1: 3, x2: -3, y2: 8),
      StickmanHeistWall(x1: 3, y1: 3, x2: 3, y2: 8),
      // Two central exhibit pedestals (small cover).
      StickmanHeistWall(x1: -2, y1: -0.5, x2: -0.5, y2: -0.5),
      StickmanHeistWall(x1: -0.5, y1: -0.5, x2: -0.5, y2: 0.5),
      StickmanHeistWall(x1: -0.5, y1: 0.5, x2: -2, y2: 0.5),
      StickmanHeistWall(x1: -2, y1: 0.5, x2: -2, y2: -0.5),
      StickmanHeistWall(x1: 0.5, y1: -0.5, x2: 2, y2: -0.5),
      StickmanHeistWall(x1: 2, y1: -0.5, x2: 2, y2: 0.5),
      StickmanHeistWall(x1: 2, y1: 0.5, x2: 0.5, y2: 0.5),
      StickmanHeistWall(x1: 0.5, y1: 0.5, x2: 0.5, y2: -0.5),
    ],
    spawnPoints: [
      (-8, -8),
      (8, -8),
      (-8, 8),
      (8, 8),
      (0, -8),
      (0, 8),
      (-8, 0),
      (8, 0),
    ],
  );

  static const warehouse = StickmanHeistMap(
    id: 'warehouse',
    name: 'Warehouse',
    escapeZoneLabel: 'EXIT',
    walls: [
      // Warehouse — large crates (boxes) scattered for cover.
      StickmanHeistWall(x1: -7, y1: -7, x2: -5, y2: -7),
      StickmanHeistWall(x1: -5, y1: -7, x2: -5, y2: -5),
      StickmanHeistWall(x1: -5, y1: -5, x2: -7, y2: -5),
      StickmanHeistWall(x1: -7, y1: -5, x2: -7, y2: -7),
      StickmanHeistWall(x1: 5, y1: -7, x2: 7, y2: -7),
      StickmanHeistWall(x1: 7, y1: -7, x2: 7, y2: -5),
      StickmanHeistWall(x1: 7, y1: -5, x2: 5, y2: -5),
      StickmanHeistWall(x1: 5, y1: -5, x2: 5, y2: -7),
      StickmanHeistWall(x1: -7, y1: 5, x2: -5, y2: 5),
      StickmanHeistWall(x1: -5, y1: 5, x2: -5, y2: 7),
      StickmanHeistWall(x1: -5, y1: 7, x2: -7, y2: 7),
      StickmanHeistWall(x1: -7, y1: 7, x2: -7, y2: 5),
      StickmanHeistWall(x1: 5, y1: 5, x2: 7, y2: 5),
      StickmanHeistWall(x1: 7, y1: 5, x2: 7, y2: 7),
      StickmanHeistWall(x1: 7, y1: 7, x2: 5, y2: 7),
      StickmanHeistWall(x1: 5, y1: 7, x2: 5, y2: 5),
      // Long crate in the middle
      StickmanHeistWall(x1: -3, y1: -0.75, x2: 3, y2: -0.75),
      StickmanHeistWall(x1: 3, y1: -0.75, x2: 3, y2: 0.75),
      StickmanHeistWall(x1: 3, y1: 0.75, x2: -3, y2: 0.75),
      StickmanHeistWall(x1: -3, y1: 0.75, x2: -3, y2: -0.75),
    ],
    spawnPoints: [
      (-8, -8),
      (8, -8),
      (-8, 8),
      (8, 8),
      (-3, -3),
      (3, 3),
      (3, -3),
      (-3, 3),
    ],
  );

  static const List<StickmanHeistMap> all = [bank, museum, warehouse];

  static StickmanHeistMap byId(String? id) {
    switch (id) {
      case 'museum':
        return museum;
      case 'warehouse':
        return warehouse;
      case 'bank':
      default:
        return bank;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'walls': walls.map((w) => w.toJson()).toList(),
        'spawnPoints':
            spawnPoints.map((p) => {'x': p.$1, 'y': p.$2}).toList(),
        'escapeZoneLabel': escapeZoneLabel,
      };
}

// ── Player ───────────────────────────────────────────────────────────

/// One player's full state. Mirrors the JSON shape produced by
/// fn_stickmanheist_start (server) and updated by the host's local sim.
class StickmanHeistPlayer {
  StickmanHeistPlayer({
    required this.idx,
    required this.userId,
    required this.name,
    required this.x,
    required this.y,
    required this.angle,
    required this.health,
    required this.maxHealth,
    required this.isAlive,
    required this.weapon,
    required this.ammo,
    required this.maxAmmo,
    required this.isReloading,
    required this.hasTreasure,
    required this.kills,
    required this.deaths,
    required this.respawnAt,
    required this.shieldActive,
    required this.speedBoostUntil,
    this.lastShotAtMs = 0,
    this.reloadStartedAtMs = 0,
  });

  /// Slot index 0..N-1 in the player order.
  int idx;

  String userId;
  String name;

  double x;
  double y;

  /// Facing angle in radians (0 = +x axis).
  double angle;

  int health;
  int maxHealth;
  bool isAlive;

  StickmanHeistWeapon weapon;
  int ammo;
  int maxAmmo;
  bool isReloading;

  bool hasTreasure;

  int kills;
  int deaths;

  /// Epoch ms when this player respawns. 0 = no respawn pending.
  int respawnAt;

  /// True while shield powerup is active (absorbs next 50 damage).
  bool shieldActive;

  /// Epoch ms when speed boost expires. 0 = no speed boost.
  int speedBoostUntil;

  /// Last time this player fired (epoch ms) — rate limit.
  int lastShotAtMs;

  /// When the current reload started (epoch ms).
  int reloadStartedAtMs;

  bool get hasSpeedBoost =>
      speedBoostUntil > 0 &&
      DateTime.now().millisecondsSinceEpoch < speedBoostUntil;

  StickmanHeistPlayer copyWith({
    int? idx,
    String? userId,
    String? name,
    double? x,
    double? y,
    double? angle,
    int? health,
    int? maxHealth,
    bool? isAlive,
    StickmanHeistWeapon? weapon,
    int? ammo,
    int? maxAmmo,
    bool? isReloading,
    bool? hasTreasure,
    int? kills,
    int? deaths,
    int? respawnAt,
    bool? shieldActive,
    int? speedBoostUntil,
    int? lastShotAtMs,
    int? reloadStartedAtMs,
  }) =>
      StickmanHeistPlayer(
        idx: idx ?? this.idx,
        userId: userId ?? this.userId,
        name: name ?? this.name,
        x: x ?? this.x,
        y: y ?? this.y,
        angle: angle ?? this.angle,
        health: health ?? this.health,
        maxHealth: maxHealth ?? this.maxHealth,
        isAlive: isAlive ?? this.isAlive,
        weapon: weapon ?? this.weapon,
        ammo: ammo ?? this.ammo,
        maxAmmo: maxAmmo ?? this.maxAmmo,
        isReloading: isReloading ?? this.isReloading,
        hasTreasure: hasTreasure ?? this.hasTreasure,
        kills: kills ?? this.kills,
        deaths: deaths ?? this.deaths,
        respawnAt: respawnAt ?? this.respawnAt,
        shieldActive: shieldActive ?? this.shieldActive,
        speedBoostUntil: speedBoostUntil ?? this.speedBoostUntil,
        lastShotAtMs: lastShotAtMs ?? this.lastShotAtMs,
        reloadStartedAtMs:
            reloadStartedAtMs ?? this.reloadStartedAtMs,
      );

  Map<String, dynamic> toJson() => {
        'idx': idx,
        'userId': userId,
        'name': name,
        'x': x,
        'y': y,
        'angle': angle,
        'health': health,
        'maxHealth': maxHealth,
        'isAlive': isAlive,
        'weapon': weapon.wire,
        'ammo': ammo,
        'maxAmmo': maxAmmo,
        'isReloading': isReloading,
        'hasTreasure': hasTreasure,
        'kills': kills,
        'deaths': deaths,
        'respawnAt': respawnAt == 0 ? null : respawnAt,
        'shieldActive': shieldActive,
        'speedBoostUntil': speedBoostUntil,
      };

  factory StickmanHeistPlayer.fromJson(Map<String, dynamic> json) {
    return StickmanHeistPlayer(
      idx: (json['idx'] as num?)?.toInt() ?? 0,
      userId: (json['userId'] ?? '') as String,
      name: (json['name'] ?? 'Player') as String,
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      angle: (json['angle'] as num?)?.toDouble() ?? 0,
      health: (json['health'] as num?)?.toInt() ??
          kStickmanHeistDefaultHealth,
      maxHealth: (json['maxHealth'] as num?)?.toInt() ??
          kStickmanHeistDefaultHealth,
      isAlive: (json['isAlive'] as bool?) ?? true,
      weapon: StickmanHeistWeaponX.fromString(json['weapon'] as String?),
      ammo: (json['ammo'] as num?)?.toInt() ?? 12,
      maxAmmo: (json['maxAmmo'] as num?)?.toInt() ?? 12,
      isReloading: (json['isReloading'] as bool?) ?? false,
      hasTreasure: (json['hasTreasure'] as bool?) ?? false,
      kills: (json['kills'] as num?)?.toInt() ?? 0,
      deaths: (json['deaths'] as num?)?.toInt() ?? 0,
      respawnAt: (json['respawnAt'] as num?)?.toInt() ?? 0,
      shieldActive: (json['shieldActive'] as bool?) ?? false,
      speedBoostUntil:
          (json['speedBoostUntil'] as num?)?.toInt() ?? 0,
      lastShotAtMs: (json['lastShotAtMs'] as num?)?.toInt() ?? 0,
      reloadStartedAtMs:
          (json['reloadStartedAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

// ── Projectile ───────────────────────────────────────────────────────

/// A bullet in flight. Owner idx identifies who fired it (so we don't
/// hit the shooter and we can attribute kills).
class StickmanHeistProjectile {
  StickmanHeistProjectile({
    required this.id,
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.ownerId,
    required this.ownerIdx,
    required this.damage,
    required this.lifeMs,
  });

  final String id;
  double x;
  double y;
  double vx;
  double vy;
  final String ownerId;
  final int ownerIdx;
  final int damage;

  /// Remaining lifetime in ms. When this hits 0, the bullet despawns.
  int lifeMs;

  Map<String, dynamic> toJson() => {
        'id': id,
        'x': x,
        'y': y,
        'vx': vx,
        'vy': vy,
        'ownerId': ownerId,
        'ownerIdx': ownerIdx,
        'damage': damage,
        'lifeMs': lifeMs,
      };

  factory StickmanHeistProjectile.fromJson(Map<String, dynamic> json) =>
      StickmanHeistProjectile(
        id: (json['id'] ?? '') as String,
        x: (json['x'] as num?)?.toDouble() ?? 0,
        y: (json['y'] as num?)?.toDouble() ?? 0,
        vx: (json['vx'] as num?)?.toDouble() ?? 0,
        vy: (json['vy'] as num?)?.toDouble() ?? 0,
        ownerId: (json['ownerId'] ?? '') as String,
        ownerIdx: (json['ownerIdx'] as num?)?.toInt() ?? -1,
        damage: (json['damage'] as num?)?.toInt() ?? 10,
        lifeMs: (json['lifeMs'] as num?)?.toInt() ??
            kStickmanHeistProjectileLifeMs,
      );
}

// ── Treasure ─────────────────────────────────────────────────────────

/// The treasure. carrierIdx = -1 when on the ground; otherwise the idx
/// of the player carrying it.
class StickmanHeistTreasure {
  StickmanHeistTreasure({
    required this.x,
    required this.y,
    required this.carrierIdx,
    required this.collected,
  });

  double x;
  double y;
  int carrierIdx;
  bool collected;

  bool get isOnGround => carrierIdx < 0 && !collected;

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'carrierIdx': carrierIdx,
        'collected': collected,
      };

  factory StickmanHeistTreasure.fromJson(Map<String, dynamic> json) =>
      StickmanHeistTreasure(
        x: (json['x'] as num?)?.toDouble() ?? 0,
        y: (json['y'] as num?)?.toDouble() ?? 0,
        carrierIdx: (json['carrierIdx'] as num?)?.toInt() ?? -1,
        collected: (json['collected'] as bool?) ?? false,
      );
}

// ── Escape Zone ──────────────────────────────────────────────────────

/// One of 4 escape zones at the corners of the map. Only active when a
/// carrier exists.
class StickmanHeistEscapeZone {
  StickmanHeistEscapeZone({
    required this.x,
    required this.y,
    required this.radius,
    required this.active,
    required this.label,
  });

  double x;
  double y;
  double radius;
  bool active;
  String label;

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'radius': radius,
        'active': active,
        'label': label,
      };

  factory StickmanHeistEscapeZone.fromJson(Map<String, dynamic> json) =>
      StickmanHeistEscapeZone(
        x: (json['x'] as num?)?.toDouble() ?? 0,
        y: (json['y'] as num?)?.toDouble() ?? 0,
        radius: (json['radius'] as num?)?.toDouble() ?? 1.5,
        active: (json['active'] as bool?) ?? false,
        label: (json['label'] ?? 'EXIT') as String,
      );
}

// ── Weapon / Powerup Spawns ──────────────────────────────────────────

/// A weapon pickup on the map. taken = true while on cooldown.
class StickmanHeistWeaponSpawn {
  StickmanHeistWeaponSpawn({
    required this.x,
    required this.y,
    required this.weapon,
    required this.taken,
    this.respawnAtMs = 0,
  });

  double x;
  double y;
  StickmanHeistWeapon weapon;
  bool taken;

  /// Epoch ms when the weapon respawns. 0 = available now.
  int respawnAtMs;

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'weapon': weapon.wire,
        'taken': taken,
        'respawnAtMs': respawnAtMs,
      };

  factory StickmanHeistWeaponSpawn.fromJson(Map<String, dynamic> json) =>
      StickmanHeistWeaponSpawn(
        x: (json['x'] as num?)?.toDouble() ?? 0,
        y: (json['y'] as num?)?.toDouble() ?? 0,
        weapon:
            StickmanHeistWeaponX.fromString(json['weapon'] as String?),
        taken: (json['taken'] as bool?) ?? false,
        respawnAtMs: (json['respawnAtMs'] as num?)?.toInt() ?? 0,
      );
}

/// A powerup pickup on the map.
class StickmanHeistPowerupSpawn {
  StickmanHeistPowerupSpawn({
    required this.x,
    required this.y,
    required this.type,
    required this.taken,
    this.respawnAtMs = 0,
  });

  double x;
  double y;
  StickmanHeistPowerupType type;
  bool taken;
  int respawnAtMs;

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'type': type.wire,
        'taken': taken,
        'respawnAtMs': respawnAtMs,
      };

  factory StickmanHeistPowerupSpawn.fromJson(Map<String, dynamic> json) =>
      StickmanHeistPowerupSpawn(
        x: (json['x'] as num?)?.toDouble() ?? 0,
        y: (json['y'] as num?)?.toDouble() ?? 0,
        type: StickmanHeistPowerupTypeX.fromString(
            json['type'] as String?),
        taken: (json['taken'] as bool?) ?? false,
        respawnAtMs: (json['respawnAtMs'] as num?)?.toInt() ?? 0,
      );
}

// ── Game Event (kill / pickup / escape notification) ─────────────────

/// A short-lived event the HUD shows as a banner (e.g. "Manish picked
/// up the treasure!", "Priya was eliminated"). The host appends events
/// during the sim and they fade client-side after ~3s.
class StickmanHeistEvent {
  StickmanHeistEvent({
    required this.kind,
    required this.text,
    required this.atMs,
    this.color = 0xFFFFFFFF,
  });

  final String kind; // 'pickup', 'kill', 'escape', 'drop', 'win'
  final String text;
  final int atMs;
  final int color;

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'text': text,
        'atMs': atMs,
        'color': color,
      };

  factory StickmanHeistEvent.fromJson(Map<String, dynamic> json) =>
      StickmanHeistEvent(
        kind: (json['kind'] ?? '') as String,
        text: (json['text'] ?? '') as String,
        atMs: (json['atMs'] as num?)?.toInt() ?? 0,
        color: (json['color'] as num?)?.toInt() ?? 0xFFFFFFFF,
      );
}

// ── Board State ──────────────────────────────────────────────────────

/// The full state of an in-progress match. This is what the host
/// serializes and broadcasts every 100ms.
class StickmanHeistBoardState {
  StickmanHeistBoardState({
    required this.playerCount,
    required this.mapId,
    required this.respawnsEnabled,
    required this.matchSeconds,
    required this.matchTimeRemaining,
    required this.phase,
    required this.treasure,
    required this.escapeZones,
    required this.weaponSpawns,
    required this.powerupSpawns,
    required this.projectiles,
    required this.events,
    required this.players,
    required this.status,
    required this.winnerIdx,
    required this.matchStartTime,
  });

  int playerCount;
  String mapId;
  bool respawnsEnabled;
  int matchSeconds;
  int matchTimeRemaining;

  StickmanHeistPhase phase;

  StickmanHeistTreasure treasure;
  List<StickmanHeistEscapeZone> escapeZones;
  List<StickmanHeistWeaponSpawn> weaponSpawns;
  List<StickmanHeistPowerupSpawn> powerupSpawns;
  List<StickmanHeistProjectile> projectiles;
  List<StickmanHeistEvent> events;
  List<StickmanHeistPlayer> players;

  /// 'in_progress' or 'completed' — set to 'completed' when carrier
  /// escapes or time runs out.
  String status;

  /// -1 while match ongoing, otherwise the idx of the winning player.
  int winnerIdx;

  /// Epoch ms when the match started.
  int matchStartTime;

  /// Convenience: the carrier, or null if none.
  StickmanHeistPlayer? get carrier => treasure.carrierIdx >= 0
      ? players
          .where((p) => p.idx == treasure.carrierIdx)
          .firstOrNull
      : null;

  StickmanHeistBoardState copyWith({
    int? playerCount,
    String? mapId,
    bool? respawnsEnabled,
    int? matchSeconds,
    int? matchTimeRemaining,
    StickmanHeistPhase? phase,
    StickmanHeistTreasure? treasure,
    List<StickmanHeistEscapeZone>? escapeZones,
    List<StickmanHeistWeaponSpawn>? weaponSpawns,
    List<StickmanHeistPowerupSpawn>? powerupSpawns,
    List<StickmanHeistProjectile>? projectiles,
    List<StickmanHeistEvent>? events,
    List<StickmanHeistPlayer>? players,
    String? status,
    int? winnerIdx,
    int? matchStartTime,
  }) =>
      StickmanHeistBoardState(
        playerCount: playerCount ?? this.playerCount,
        mapId: mapId ?? this.mapId,
        respawnsEnabled: respawnsEnabled ?? this.respawnsEnabled,
        matchSeconds: matchSeconds ?? this.matchSeconds,
        matchTimeRemaining:
            matchTimeRemaining ?? this.matchTimeRemaining,
        phase: phase ?? this.phase,
        treasure: treasure ?? this.treasure,
        escapeZones: escapeZones ?? this.escapeZones,
        weaponSpawns: weaponSpawns ?? this.weaponSpawns,
        powerupSpawns: powerupSpawns ?? this.powerupSpawns,
        projectiles: projectiles ?? this.projectiles,
        events: events ?? this.events,
        players: players ?? this.players,
        status: status ?? this.status,
        winnerIdx: winnerIdx ?? this.winnerIdx,
        matchStartTime: matchStartTime ?? this.matchStartTime,
      );

  Map<String, dynamic> toJson() => {
        'playerCount': playerCount,
        'mapId': mapId,
        'respawnsEnabled': respawnsEnabled,
        'matchSeconds': matchSeconds,
        'matchTimeRemaining': matchTimeRemaining,
        'phase': phase.wire,
        'treasure': treasure.toJson(),
        'escapeZones':
            escapeZones.map((e) => e.toJson()).toList(),
        'weaponSpawns':
            weaponSpawns.map((w) => w.toJson()).toList(),
        'powerupSpawns':
            powerupSpawns.map((p) => p.toJson()).toList(),
        'projectiles':
            projectiles.map((p) => p.toJson()).toList(),
        'events': events.map((e) => e.toJson()).toList(),
        'players': players.map((p) => p.toJson()).toList(),
        'status': status,
        'winnerIdx': winnerIdx,
        'matchStartTime': matchStartTime,
      };

  factory StickmanHeistBoardState.fromJson(Map<String, dynamic> json) {
    final zonesRaw = json['escapeZones'];
    final zones = <StickmanHeistEscapeZone>[];
    if (zonesRaw is List) {
      for (final z in zonesRaw) {
        if (z is Map) {
          zones.add(StickmanHeistEscapeZone.fromJson(
              Map<String, dynamic>.from(z)));
        }
      }
    }
    final weaponsRaw = json['weaponSpawns'];
    final weapons = <StickmanHeistWeaponSpawn>[];
    if (weaponsRaw is List) {
      for (final w in weaponsRaw) {
        if (w is Map) {
          weapons.add(StickmanHeistWeaponSpawn.fromJson(
              Map<String, dynamic>.from(w)));
        }
      }
    }
    final powerupsRaw = json['powerupSpawns'];
    final powerups = <StickmanHeistPowerupSpawn>[];
    if (powerupsRaw is List) {
      for (final p in powerupsRaw) {
        if (p is Map) {
          powerups.add(StickmanHeistPowerupSpawn.fromJson(
              Map<String, dynamic>.from(p)));
        }
      }
    }
    final projectilesRaw = json['projectiles'];
    final projectiles = <StickmanHeistProjectile>[];
    if (projectilesRaw is List) {
      for (final p in projectilesRaw) {
        if (p is Map) {
          projectiles.add(StickmanHeistProjectile.fromJson(
              Map<String, dynamic>.from(p)));
        }
      }
    }
    final eventsRaw = json['events'];
    final events = <StickmanHeistEvent>[];
    if (eventsRaw is List) {
      for (final e in eventsRaw) {
        if (e is Map) {
          events.add(StickmanHeistEvent.fromJson(
              Map<String, dynamic>.from(e)));
        }
      }
    }
    final playersRaw = json['players'];
    final players = <StickmanHeistPlayer>[];
    if (playersRaw is List) {
      for (final p in playersRaw) {
        if (p is Map) {
          players.add(StickmanHeistPlayer.fromJson(
              Map<String, dynamic>.from(p)));
        }
      }
    }
    final treasureRaw = json['treasure'];
    final treasure = treasureRaw is Map
        ? StickmanHeistTreasure.fromJson(
            Map<String, dynamic>.from(treasureRaw))
        : StickmanHeistTreasure(x: 0, y: 0, carrierIdx: -1, collected: false);
    return StickmanHeistBoardState(
      playerCount: (json['playerCount'] as num?)?.toInt() ?? 0,
      mapId: (json['mapId'] ?? 'bank') as String,
      respawnsEnabled: (json['respawnsEnabled'] as bool?) ?? true,
      matchSeconds: (json['matchSeconds'] as num?)?.toInt() ?? 180,
      matchTimeRemaining:
          (json['matchTimeRemaining'] as num?)?.toInt() ?? 180,
      phase: StickmanHeistPhaseX.fromString(json['phase'] as String?),
      treasure: treasure,
      escapeZones: zones,
      weaponSpawns: weapons,
      powerupSpawns: powerups,
      projectiles: projectiles,
      events: events,
      players: players,
      status: (json['status'] ?? 'in_progress') as String,
      winnerIdx: (json['winnerIdx'] as num?)?.toInt() ?? -1,
      // QA fix 2026-09-19: fn_stickmanheist_start stores matchStartTime
      // as epoch SECONDS (extract(epoch from now())::bigint), but the
      // physics step() compares it against epoch MILLISECONDS
      // (DateTime.now().millisecondsSinceEpoch) — the mismatch made
      // `elapsed` ~56 years, so matchTimeRemaining hit 0 on the first
      // tick and EVERY match ended in an instant "Time out — no one
      // escaped" (verified live E2E twice). Normalize by magnitude so
      // both sources work: the server's seconds (~1.7e9) and the host
      // re-broadcast's already-milliseconds value (~1.7e12, e.g. after
      // a host reconnect re-parses its own boardState).
      matchStartTime: _epochSecondsOrMillis(
          (json['matchStartTime'] as num?)?.toInt() ?? 0),
    );
  }
}

// ── Helpers ──────────────────────────────────────────────────────────

/// Normalizes an epoch timestamp to MILLISECONDS. The server RPC writes
/// matchStartTime as epoch seconds (~1.7e9) while the physics engine's
/// clock is epoch milliseconds (~1.7e12); values already in milliseconds
/// (a host re-broadcast) pass through unchanged. See the QA fix note at
/// the fromJson site.
int _epochSecondsOrMillis(int v) =>
    v > 0 && v < 1000000000000 ? v * 1000 : v;

/// Distance between two points. Used by the physics engine and the
/// painter's overlap checks.
double stickmanHeistDist(double x1, double y1, double x2, double y2) {
  final dx = x2 - x1;
  final dy = y2 - y1;
  return math.sqrt(dx * dx + dy * dy);
}

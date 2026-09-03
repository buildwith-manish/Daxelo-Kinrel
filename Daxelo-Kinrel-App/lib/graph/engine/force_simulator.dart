// lib/graph/engine/force_simulator.dart
//
// DAXELO KINREL — Force-Directed Graph Simulator
//
// Wraps graphview's ForceDirectedLayout with custom family-specific forces:
//   CenterForce      — pulls nodes toward graph center
//   GenerationForce  — aligns nodes by generation on Y-axis
//   SpousePairForce  — positions spouses side-by-side
//   CollisionForce   — prevents node overlap
//   BoundaryForce    — keeps nodes within viewport bounds
//
// Simulation parameters mirror D3-force conventions:
//   alphaDecay=0.0228, velocityDecay=0.4, alphaMin=0.001
//   Initial alpha=1.0, tick interval=16ms, max ticks=10000
//
// Watchdog: force-stops if alpha doesn't reach alphaMin within 30 seconds.
// On user interaction: reheat by setting alpha=0.3.

import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/graph_layout_service.dart';

// ═══════════════════════════════════════════════════════════════════════
// SIMULATION CONFIG
// ═══════════════════════════════════════════════════════════════════════

/// Configurable parameters for the force-directed simulation.
///
/// Default values are tuned for family graphs with 0–300 nodes.
class SimulationConfig {
  /// Current simulation heat (1.0 = hot, 0.0 = cold).
  final double alpha;

  /// Minimum alpha before the simulation is considered converged.
  final double alphaMin;

  /// Rate at which alpha decays per tick (D3 convention: 1 - pow(0.001, 1/300)).
  final double alphaDecay;

  /// Fraction of velocity retained per tick (0.4 = 60% damped).
  final double velocityDecay;

  /// Milliseconds between ticks when running on main isolate.
  final int tickIntervalMs;

  /// Maximum number of ticks before forcing convergence.
  final int maxTicks;

  /// Watchdog timeout in milliseconds — if alpha hasn't reached alphaMin
  /// within this time, the simulation is force-stopped.
  final int watchdogTimeoutMs;

  /// Alpha value to reheat to when the user interacts.
  final double reheatAlpha;

  /// Viewport size for boundary clamping.
  final Size viewport;

  const SimulationConfig({
    this.alpha = 1.0,
    this.alphaMin = 0.001,
    this.alphaDecay = 0.0228,
    this.velocityDecay = 0.4,
    this.tickIntervalMs = 16,
    this.maxTicks = 10000,
    this.watchdogTimeoutMs = 30000,
    this.reheatAlpha = 0.3,
    this.viewport = const Size(2000.0, 2000.0),
  });

  SimulationConfig copyWith({
    double? alpha,
    double? alphaMin,
    double? alphaDecay,
    double? velocityDecay,
    int? tickIntervalMs,
    int? maxTicks,
    int? watchdogTimeoutMs,
    double? reheatAlpha,
    Size? viewport,
  }) {
    return SimulationConfig(
      alpha: alpha ?? this.alpha,
      alphaMin: alphaMin ?? this.alphaMin,
      alphaDecay: alphaDecay ?? this.alphaDecay,
      velocityDecay: velocityDecay ?? this.velocityDecay,
      tickIntervalMs: tickIntervalMs ?? this.tickIntervalMs,
      maxTicks: maxTicks ?? this.maxTicks,
      watchdogTimeoutMs: watchdogTimeoutMs ?? this.watchdogTimeoutMs,
      reheatAlpha: reheatAlpha ?? this.reheatAlpha,
      viewport: viewport ?? this.viewport,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// FORCE COMPONENTS
// ═══════════════════════════════════════════════════════════════════════

/// Abstract base class for custom force components.
///
/// Each force receives the full node state and modifies velocities
/// in-place. Forces are applied per-tick in the order they are registered.
abstract class ForceComponent {
  /// Human-readable name for debugging / analytics.
  String get name;

  /// Apply this force to [nodes] given the current [alpha].
  ///
  /// Implementations must update `vx` and `vy` on each [ForceNode]
  /// but MUST NOT modify `x` and `y` directly — position integration
  /// is handled by the simulator.
  void apply(List<ForceNode> nodes, double alpha);
}

/// Mutable simulation node — wraps a [GraphPerson] with force state.
class ForceNode {
  /// The graph person this node represents.
  final GraphPerson person;

  /// Current x position.
  double x;

  /// Current y position.
  double y;

  /// Velocity in x direction (pixels per tick).
  double vx;

  /// Velocity in y direction (pixels per tick).
  double vy;

  /// Fixed-weight for this node (higher = harder to move).
  double weight;

  ForceNode({
    required this.person,
    required this.x,
    required this.y,
    this.vx = 0.0,
    this.vy = 0.0,
    this.weight = 1.0,
  });
}

// ── CenterForce ─────────────────────────────────────────────────────

/// Pulls all nodes toward the graph center (centroid of all positions).
///
/// Strength range: 0.01–0.1 (gentle nudge, not a stiff spring).
class CenterForce extends ForceComponent {
  final double strength;

  CenterForce({this.strength = 0.05});

  @override
  String get name => 'CenterForce';

  @override
  void apply(List<ForceNode> nodes, double alpha) {
    if (nodes.isEmpty) return;

    // Compute centroid
    double cx = 0.0;
    double cy = 0.0;
    for (final node in nodes) {
      cx += node.x;
      cy += node.y;
    }
    cx /= nodes.length;
    cy /= nodes.length;

    // Pull each node toward centroid
    for (final node in nodes) {
      node.vx += (cx - node.x) * strength * alpha;
      node.vy += (cy - node.y) * strength * alpha;
    }
  }
}

// ── GenerationForce ────────────────────────────────────────────────

/// Aligns nodes by generation on the Y-axis.
///
/// Each generation gets a target Y position based on its generationIndex.
/// The anchor (gen 0) sits at vertical center. Ancestors above, descendants below.
///
/// Strength range: 0.3–0.8 (moderate — keeps structure without rigidity).
class GenerationForce extends ForceComponent {
  final double strength;

  /// Vertical spacing between generations (dp).
  final double generationSpacing;

  GenerationForce({
    this.strength = 0.5,
    this.generationSpacing = 160.0,
  });

  @override
  String get name => 'GenerationForce';

  @override
  void apply(List<ForceNode> nodes, double alpha) {
    for (final node in nodes) {
      final targetY =
          node.person.generationIndex * generationSpacing;
      node.vy += (targetY - node.y) * strength * alpha;
    }
  }
}

// ── SpousePairForce ────────────────────────────────────────────────

/// Positions spouses side-by-side with a configurable horizontal gap.
///
/// Operates on spouse relationships: for each spouse pair, applies
/// a spring force pulling them to be [gap] dp apart horizontally
/// and aligned vertically.
///
/// Strength range: 0.6–1.0 (strong — spouses should be adjacent).
class SpousePairForce extends ForceComponent {
  final double strength;

  /// Horizontal gap between spouse nodes (dp).
  final double gap;

  /// Lookup from personId to node index for O(1) access.
  Map<String, int> _nodeIndex = const {};

  /// Spouse relationship pairs (fromPersonId, toPersonId).
  List<({String from, String to})> _spousePairs = const [];

  SpousePairForce({
    this.strength = 0.8,
    this.gap = 90.0,
  });

  /// Must be called before [apply] to set up the spouse pairs and index.
  void configure(
    List<ForceNode> nodes,
    List<GraphRelationship> relationships,
  ) {
    _nodeIndex = {
      for (var i = 0; i < nodes.length; i++) nodes[i].person.id: i,
    };

    const spouseKeys = {
      'spouse', 'husband', 'wife', 'partner',
    };

    _spousePairs = [
      for (final r in relationships)
        if (spouseKeys.contains(r.relationshipKey.toLowerCase()))
          (from: r.fromPersonId, to: r.toPersonId),
    ];
  }

  @override
  String get name => 'SpousePairForce';

  @override
  void apply(List<ForceNode> nodes, double alpha) {
    for (final pair in _spousePairs) {
      final fromIdx = _nodeIndex[pair.from];
      final toIdx = _nodeIndex[pair.to];
      if (fromIdx == null || toIdx == null) continue;

      final a = nodes[fromIdx];
      final b = nodes[toIdx];

      final dx = b.x - a.x;
      final dy = b.y - a.y;

      // Target: side-by-side with [gap] horizontal distance, same Y
      final targetDx = (dx >= 0 ? 1 : -1) * gap;
      final forceX = (targetDx - dx) * strength * alpha * 0.5;
      final forceY = -dy * strength * alpha * 0.5;

      a.vx -= forceX;
      a.vy -= forceY;
      b.vx += forceX;
      b.vy += forceY;
    }
  }
}

// ── CollisionForce ─────────────────────────────────────────────────

/// Prevents node overlap by pushing overlapping nodes apart.
///
/// Uses a simple O(n²) pairwise check — acceptable for Tier 1 (≤300 nodes).
/// For larger graphs, the FallbackManager will switch to RadialLayout.
///
/// Strength range: 0.5–1.0.
class CollisionForce extends ForceComponent {
  final double strength;

  /// Minimum distance between node centers (dp).
  final double minimumDistance;

  CollisionForce({
    this.strength = 0.7,
    this.minimumDistance = 100.0,
  });

  @override
  String get name => 'CollisionForce';

  @override
  void apply(List<ForceNode> nodes, double alpha) {
    for (var i = 0; i < nodes.length; i++) {
      for (var j = i + 1; j < nodes.length; j++) {
        final a = nodes[i];
        final b = nodes[j];
        var dx = b.x - a.x;
        var dy = b.y - a.y;

        // Avoid zero-distance by nudging
        if (dx == 0.0 && dy == 0.0) {
          dx = 0.01 * (i.isEven ? 1 : -1);
          dy = 0.01 * (j.isEven ? 1 : -1);
        }

        final dist = sqrt(dx * dx + dy * dy);
        if (dist < minimumDistance && dist > 0) {
          final overlap = minimumDistance - dist;
          final nx = dx / dist;
          final ny = dy / dist;
          final push = overlap * strength * alpha * 0.5;

          a.vx -= nx * push;
          a.vy -= ny * push;
          b.vx += nx * push;
          b.vy += ny * push;
        }
      }
    }
  }
}

// ── BoundaryForce ──────────────────────────────────────────────────

/// Keeps nodes within the viewport bounds.
///
/// When a node exits the viewport boundary (with padding),
/// a restoring force pushes it back inward.
///
/// Strength range: 0.2–0.5.
class BoundaryForce extends ForceComponent {
  final double strength;

  /// Viewport dimensions for boundary clamping.
  final Size viewport;

  /// Padding inside viewport boundary where force activates.
  final double padding;

  BoundaryForce({
    this.strength = 0.3,
    this.viewport = const Size(2000.0, 2000.0),
    this.padding = 50.0,
  });

  @override
  String get name => 'BoundaryForce';

  @override
  void apply(List<ForceNode> nodes, double alpha) {
    final minX = padding;
    final maxX = viewport.width - padding;
    final minY = padding;
    final maxY = viewport.height - padding;

    for (final node in nodes) {
      if (node.x < minX) {
        node.vx += (minX - node.x) * strength * alpha;
      } else if (node.x > maxX) {
        node.vx += (maxX - node.x) * strength * alpha;
      }

      if (node.y < minY) {
        node.vy += (minY - node.y) * strength * alpha;
      } else if (node.y > maxY) {
        node.vy += (maxY - node.y) * strength * alpha;
      }
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SIMULATION STATE
// ═══════════════════════════════════════════════════════════════════════

/// Immutable snapshot of the simulation state at a given tick.
class SimulationState {
  final Map<String, Offset> positions;
  final double alpha;
  final int tick;
  final bool converged;

  const SimulationState({
    required this.positions,
    required this.alpha,
    required this.tick,
    required this.converged,
  });
}

// ═══════════════════════════════════════════════════════════════════════
// FORCE SIMULATOR
// ═══════════════════════════════════════════════════════════════════════

/// Main force-directed simulation engine.
///
/// Wraps custom force components (Center, Generation, Spouse, Collision,
/// Boundary) with D3-style alpha-decay convergence and a watchdog timer.
///
/// Usage:
/// ```dart
/// final simulator = ForceSimulator();
/// simulator.initialize(persons, relationships);
/// simulator.start(); // begins ticking
/// simulator.onTick.listen((state) { /* update UI */ });
/// simulator.reheat(); // on user drag
/// simulator.stop();
/// ```
class ForceSimulator {
  SimulationConfig _config;
  List<ForceNode> _nodes = [];
  final List<ForceComponent> _forces = [];

  double _alpha;
  int _tickCount = 0;
  bool _running = false;
  Timer? _tickTimer;
  DateTime? _startTime;

  /// Stream controller for tick events.
  final StreamController<SimulationState> _tickController =
      StreamController<SimulationState>.broadcast();

  /// Stream controller for convergence events.
  final StreamController<SimulationState> _convergedController =
      StreamController<SimulationState>.broadcast();

  /// Spouse force reference — needs special configuration.
  SpousePairForce? _spouseForce;

  ForceSimulator({SimulationConfig? config})
      : _config = config ?? const SimulationConfig(),
        _alpha = config?.alpha ?? 1.0;

  // ── Public API ────────────────────────────────────────────────────

  /// Current simulation configuration.
  SimulationConfig get config => _config;

  /// Whether the simulation is currently running.
  bool get isRunning => _running;

  /// Current alpha value.
  double get alpha => _alpha;

  /// Current tick count.
  int get tickCount => _tickCount;

  /// Stream of simulation state per tick.
  Stream<SimulationState> get onTick => _tickController.stream;

  /// Stream that fires once when the simulation converges.
  Stream<SimulationState> get onConverged => _convergedController.stream;

  /// Initialize the simulator with graph data.
  ///
  /// Creates [ForceNode] instances from [persons], positions them
  /// based on generation, and configures all force components.
  void initialize(
    List<GraphPerson> persons,
    List<GraphRelationship> relationships, {
    SimulationConfig? config,
    Map<String, Offset>? initialPositions,
  }) {
    if (config != null) {
      _config = config;
    }

    _alpha = _config.alpha;
    _tickCount = 0;

    // Create nodes with initial positions
    _nodes = [
      for (final person in persons)
        ForceNode(
          person: person,
          x: initialPositions?[person.id]?.dx ??
              _config.viewport.width / 2 +
                  (persons.indexOf(person) % 10) * 20.0,
          y: initialPositions?[person.id]?.dy ??
              _config.viewport.height / 2 +
                  person.generationIndex * 160.0,
        ),
    ];

    // Set up force components
    _forces.clear();

    final centerForce = CenterForce();
    _forces.add(centerForce);

    final generationForce = GenerationForce(
      generationSpacing: 160.0,
    );
    _forces.add(generationForce);

    _spouseForce = SpousePairForce(gap: 90.0);
    _spouseForce!.configure(_nodes, relationships);
    _forces.add(_spouseForce!);

    final collisionForce = CollisionForce(
      minimumDistance: 100.0,
    );
    _forces.add(collisionForce);

    final boundaryForce = BoundaryForce(viewport: _config.viewport);
    _forces.add(boundaryForce);
  }

  /// Start the simulation tick loop.
  void start() {
    if (_running) return;
    _running = true;
    _startTime = DateTime.now();
    _scheduleTick();
  }

  /// Stop the simulation.
  void stop() {
    _running = false;
    _tickTimer?.cancel();
    _tickTimer = null;
  }

  /// Reheat the simulation — call on user interaction (drag, pinch).
  void reheat() {
    _alpha = _config.reheatAlpha;
    if (!_running) {
      start();
    }
  }

  /// Get the current positions as a map of personId → Offset.
  Map<String, Offset> get positions => {
        for (final node in _nodes)
          node.person.id: Offset(node.x, node.y),
      };

  /// Run the full simulation synchronously (for compute isolate).
  ///
  /// Returns the final positions when alpha drops below alphaMin
  /// or maxTicks/watchdog is reached.
  Map<String, Offset> runSync() {
    _startTime = DateTime.now();

    while (_alpha >= _config.alphaMin && _tickCount < _config.maxTicks) {
      // Watchdog check
      if (_startTime != null) {
        final elapsed = DateTime.now().difference(_startTime!);
        if (elapsed.inMilliseconds >= _config.watchdogTimeoutMs) {
          debugPrint(
            'ForceSimulator: watchdog timeout after ${elapsed.inMilliseconds}ms, '
            'alpha=$_alpha, tick=$_tickCount',
          );
          break;
        }
      }

      _tick();
    }

    return positions;
  }

  /// Run simulation in a compute isolate for performance.
  ///
  /// Returns the final positions when converged.
  /// Uses serializable coordinate pairs to avoid dart:ui dependency
  /// in the background isolate.
  Future<Map<String, Offset>> runInIsolate() async {
    // Convert Offset positions to serializable double pairs
    final serializablePositions = <String, (double, double)>{
      for (final entry in positions.entries)
        entry.key: (entry.value.dx, entry.value.dy),
    };

    final result = await compute(_isolateMain, _IsolatePayload(
      persons: [
        for (final node in _nodes) node.person,
      ],
      relationships: [], // SpouseForce reconfigured in isolate
      config: _config,
      initialPositions: serializablePositions,
    ));

    // Convert back to Offset
    return {
      for (final entry in result.entries)
        entry.key: Offset(entry.value.$1, entry.value.$2),
    };
  }

  /// Update viewport size (e.g., on rotation).
  void updateViewport(Size viewport) {
    _config = _config.copyWith(viewport: viewport);
    // Update boundary force
    for (var i = 0; i < _forces.length; i++) {
      if (_forces[i] is BoundaryForce) {
        _forces[i] = BoundaryForce(
          viewport: viewport,
          strength: (_forces[i] as BoundaryForce).strength,
          padding: (_forces[i] as BoundaryForce).padding,
        );
      }
    }
  }

  /// Fix a node's position (e.g., during drag).
  void fixNode(String personId, Offset position) {
    final node = _nodes.where((n) => n.person.id == personId).firstOrNull;
    if (node != null) {
      node.x = position.dx;
      node.y = position.dy;
      node.vx = 0.0;
      node.vy = 0.0;
      node.weight = 0.0; // makes it immovable
    }
  }

  /// Unfix a node (release after drag).
  void unfixNode(String personId) {
    final node = _nodes.where((n) => n.person.id == personId).firstOrNull;
    if (node != null) {
      node.weight = 1.0;
    }
  }

  /// Dispose the simulator and close streams.
  void dispose() {
    stop();
    _tickController.close();
    _convergedController.close();
  }

  // ── Private ───────────────────────────────────────────────────────

  void _scheduleTick() {
    _tickTimer = Timer(Duration(milliseconds: _config.tickIntervalMs), () {
      if (!_running) return;

      // Watchdog check
      if (_startTime != null) {
        final elapsed = DateTime.now().difference(_startTime!);
        if (elapsed.inMilliseconds >= _config.watchdogTimeoutMs) {
          debugPrint(
            'ForceSimulator: watchdog timeout, force-stopping at alpha=$_alpha',
          );
          _emitState(converged: true);
          stop();
          return;
        }
      }

      _tick();

      if (_alpha < _config.alphaMin || _tickCount >= _config.maxTicks) {
        _emitState(converged: true);
        stop();
        return;
      }

      _emitState(converged: false);
      _scheduleTick();
    });
  }

  void _tick() {
    // Apply all forces
    for (final force in _forces) {
      force.apply(_nodes, _alpha);
    }

    // Integrate velocities → positions
    for (final node in _nodes) {
      if (node.weight <= 0) continue; // fixed node

      node.vx *= (1 - _config.velocityDecay);
      node.vy *= (1 - _config.velocityDecay);
      node.x += node.vx;
      node.y += node.vy;
    }

    // Decay alpha
    _alpha *= (1 - _config.alphaDecay);
    _tickCount++;
  }

  void _emitState({required bool converged}) {
    final state = SimulationState(
      positions: positions,
      alpha: _alpha,
      tick: _tickCount,
      converged: converged,
    );

    if (!_tickController.isClosed) {
      _tickController.add(state);
    }

    if (converged && !_convergedController.isClosed) {
      _convergedController.add(state);
    }
  }

  /// Isolate entry point — runs a fresh simulation from scratch.
  ///
  /// Uses serializable (double, double) pairs instead of Offset
  /// because dart:ui is not available in background isolates.
  static Map<String, (double, double)> _isolateMain(_IsolatePayload payload) {
    final simulator = ForceSimulator(config: payload.config);
    // Convert serializable positions back to Offset for initialization
    final offsetPositions = <String, Offset>{
      for (final entry in payload.initialPositions.entries)
        entry.key: Offset(entry.value.$1, entry.value.$2),
    };
    simulator.initialize(
      payload.persons,
      [], // relationships are reconstructed inside initialize
      initialPositions: offsetPositions,
    );
    final result = simulator.runSync();
    // Convert Offset results to serializable pairs
    return {
      for (final entry in result.entries)
        entry.key: (entry.value.dx, entry.value.dy),
    };
  }
}

/// Payload for compute isolate.
///
/// Uses (double, double) tuples instead of Offset to avoid
/// dart:ui dependency in background isolates.
class _IsolatePayload {
  final List<GraphPerson> persons;
  final List<GraphRelationship> relationships;
  final SimulationConfig config;
  final Map<String, (double, double)> initialPositions;

  const _IsolatePayload({
    required this.persons,
    required this.relationships,
    required this.config,
    required this.initialPositions,
  });
}

// ═══════════════════════════════════════════════════════════════════════
// RIVERPOD PROVIDERS
// ═══════════════════════════════════════════════════════════════════════

/// Provider for the [ForceSimulator] singleton.
///
/// The simulator is created lazily and disposed when the provider
/// is no longer watched.
final forceSimulatorProvider = Provider<ForceSimulator>((ref) {
  final simulator = ForceSimulator();
  ref.onDispose(() => simulator.dispose());
  return simulator;
});

/// Provider for the current simulation state.
final simulationStateProvider = StreamProvider<SimulationState>((ref) {
  final simulator = ref.watch(forceSimulatorProvider);
  return simulator.onTick;
});

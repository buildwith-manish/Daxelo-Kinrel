// lib/graph/engine/fallback_manager.dart
//
// DAXELO KINREL — Fallback Manager
//
// Automatic engine switching based on node count and performance.
// Monitors active node count continuously and selects the optimal
// layout engine tier to maintain target frame rates.
//
// Tier system:
//   Tier 1 (Force):        0–300 nodes,    60 FPS target
//   Tier 2 (Hybrid):       300–1,000 nodes, 45 FPS target
//   Tier 3 (Radial):       1,000–3,000 nodes, 30 FPS target
//   Tier 4 (Hierarchical): 3,000–5,000 nodes, 30 FPS target
//   Tier 5 (Emergency):    5,000+ nodes,    list-based fallback, 60 FPS
//
// Features:
//   - 2-second debounce before switching (prevents oscillation)
//   - 500ms crossfade animation blending old positions into new
//   - Performance-triggered downgrade if tick > 4ms or frame > 16.67ms
//   - User notification on downgrade
//   - Manual override from Settings
//   - All switches logged to AnalyticsService

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/graph_layout_service.dart';
import '../../core/services/analytics_service.dart';
import 'force_simulator.dart';
import 'radial_layout.dart';
import 'hierarchical_layout.dart';

// ═══════════════════════════════════════════════════════════════════════
// ENGINE TIER
// ═══════════════════════════════════════════════════════════════════════

/// Layout engine tier levels, ordered from most feature-rich to most performant.
enum EngineTier {
  /// Force-directed simulation — best visual quality, O(n²) complexity.
  force,

  /// Simplified force with Barnes-Hut approximation (theta=0.9).
  hybrid,

  /// Algebraic radial layout — no simulation, concentric rings.
  radial,

  /// Traditional top-down tree — maximum readability at scale.
  hierarchical,

  /// List-based fallback for extreme node counts (>5,000).
  emergency,
}

/// Human-readable names for each engine tier.
extension EngineTierLabel on EngineTier {
  String get label => switch (this) {
        EngineTier.force => 'Force-Directed',
        EngineTier.hybrid => 'Hybrid (Barnes-Hut)',
        EngineTier.radial => 'Radial',
        EngineTier.hierarchical => 'Hierarchical',
        EngineTier.emergency => 'Emergency (List)',
      };

  /// Target FPS for this tier.
  int get targetFps => switch (this) {
        EngineTier.force => 60,
        EngineTier.hybrid => 45,
        EngineTier.radial => 30,
        EngineTier.hierarchical => 30,
        EngineTier.emergency => 60,
      };

  /// Maximum node count for this tier.
  int get maxNodes => switch (this) {
        EngineTier.force => 300,
        EngineTier.hybrid => 1000,
        EngineTier.radial => 3000,
        EngineTier.hierarchical => 5000,
        // Use 999999999 instead of max int to avoid JS precision issues on web
        EngineTier.emergency => 999999999,
      };
}

// ═══════════════════════════════════════════════════════════════════════
// TIER THRESHOLDS
// ═══════════════════════════════════════════════════════════════════════

/// Threshold configuration for tier switching.
class TierThresholds {
  final int forceMax;
  final int hybridMax;
  final int radialMax;
  final int hierarchicalMax;

  /// Maximum tick duration before triggering downgrade (ms).
  final double maxTickDurationMs;

  /// Maximum frame duration before triggering downgrade (ms).
  final double maxFrameDurationMs;

  /// Debounce duration before switching (ms).
  final int debounceMs;

  /// Crossfade animation duration (ms).
  final int crossfadeMs;

  const TierThresholds({
    this.forceMax = 300,
    this.hybridMax = 1000,
    this.radialMax = 3000,
    this.hierarchicalMax = 5000,
    this.maxTickDurationMs = 4.0,
    this.maxFrameDurationMs = 16.67,
    this.debounceMs = 2000,
    this.crossfadeMs = 500,
  });
}

// ═══════════════════════════════════════════════════════════════════════
// FALLBACK STATE
// ═══════════════════════════════════════════════════════════════════════

/// Immutable state snapshot for the fallback manager.
class FallbackState {
  /// Currently active engine tier.
  final EngineTier currentTier;

  /// Recommended tier based on node count (before debounce).
  final EngineTier recommendedTier;

  /// Number of active nodes being rendered.
  final int nodeCount;

  /// Whether a tier switch is pending (in debounce window).
  final bool switchPending;

  /// Whether the user has manually overridden the tier.
  final bool userOverride;

  /// Last tick duration in milliseconds (for performance monitoring).
  final double lastTickDurationMs;

  /// Last frame duration in milliseconds.
  final double lastFrameDurationMs;

  /// Human-readable notification message (null if no notification).
  final String? notificationMessage;

  /// Crossfade progress (0.0 = old positions, 1.0 = new positions).
  final double crossfadeProgress;

  /// Old positions before the switch (for crossfade).
  final Map<String, Offset>? oldPositions;

  /// New positions after the switch.
  final Map<String, Offset>? newPositions;

  const FallbackState({
    this.currentTier = EngineTier.force,
    this.recommendedTier = EngineTier.force,
    this.nodeCount = 0,
    this.switchPending = false,
    this.userOverride = false,
    this.lastTickDurationMs = 0.0,
    this.lastFrameDurationMs = 0.0,
    this.notificationMessage,
    this.crossfadeProgress = 1.0,
    this.oldPositions,
    this.newPositions,
  });

  FallbackState copyWith({
    EngineTier? currentTier,
    EngineTier? recommendedTier,
    int? nodeCount,
    bool? switchPending,
    bool? userOverride,
    double? lastTickDurationMs,
    double? lastFrameDurationMs,
    String? notificationMessage,
    double? crossfadeProgress,
    Map<String, Offset>? oldPositions,
    Map<String, Offset>? newPositions,
  }) {
    return FallbackState(
      currentTier: currentTier ?? this.currentTier,
      recommendedTier: recommendedTier ?? this.recommendedTier,
      nodeCount: nodeCount ?? this.nodeCount,
      switchPending: switchPending ?? this.switchPending,
      userOverride: userOverride ?? this.userOverride,
      lastTickDurationMs: lastTickDurationMs ?? this.lastTickDurationMs,
      lastFrameDurationMs: lastFrameDurationMs ?? this.lastFrameDurationMs,
      notificationMessage: notificationMessage ?? this.notificationMessage,
      crossfadeProgress: crossfadeProgress ?? this.crossfadeProgress,
      oldPositions: oldPositions ?? this.oldPositions,
      newPositions: newPositions ?? this.newPositions,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// FALLBACK MANAGER
// ═══════════════════════════════════════════════════════════════════════

/// Manages automatic engine tier switching based on node count and performance.
///
/// Implements Riverpod [StateNotifier] for reactive state management.
/// Monitors node count and frame performance, switching between layout
/// engines to maintain target FPS.
///
/// Switching logic:
///   1. Compute recommended tier from node count
///   2. If recommended != current → start debounce timer
///   3. After debounce → switch tier with crossfade animation
///   4. Performance monitoring: if tick/frame exceeds threshold → downgrade
///   5. All switches logged to [AnalyticsService]
///
/// Usage:
/// ```dart
/// // In a Riverpod widget:
/// final state = ref.watch(fallbackManagerProvider);
/// // Update node count:
/// ref.read(fallbackManagerProvider.notifier).updateNodeCount(1500);
/// // Manual override:
/// ref.read(fallbackManagerProvider.notifier).setUserOverride(EngineTier.radial);
/// ```
class FallbackManager extends StateNotifier<FallbackState> {
  final TierThresholds _thresholds;
  Timer? _debounceTimer;
  Timer? _crossfadeTimer;

  /// Performance history for trending analysis.
  final List<double> _tickHistory = [];
  final List<double> _frameHistory = [];

  /// Maximum performance samples to keep.
  static const int _maxHistorySize = 60;

  FallbackManager({
    TierThresholds? thresholds,
  })  : _thresholds = thresholds ?? const TierThresholds(),
        super(const FallbackState());

  // ── Public API ────────────────────────────────────────────────────

  /// Update the active node count.
  ///
  /// This triggers tier evaluation. If the recommended tier changes,
  /// a debounce timer starts before the actual switch.
  void updateNodeCount(int count) {
    final recommended = _computeRecommendedTier(count);

    state = state.copyWith(
      nodeCount: count,
      recommendedTier: recommended,
    );

    _evaluateSwitch(recommended);
  }

  /// Report a tick duration for performance monitoring.
  ///
  /// If the tick exceeds [TierThresholds.maxTickDurationMs],
  /// the manager may trigger a tier downgrade.
  void reportTickDuration(double durationMs) {
    _tickHistory.add(durationMs);
    if (_tickHistory.length > _maxHistorySize) {
      _tickHistory.removeAt(0);
    }

    state = state.copyWith(lastTickDurationMs: durationMs);

    // Performance-triggered downgrade
    if (durationMs > _thresholds.maxTickDurationMs) {
      _considerPerformanceDowngrade('tick_exceeded');
    }
  }

  /// Report a total frame duration for performance monitoring.
  void reportFrameDuration(double durationMs) {
    _frameHistory.add(durationMs);
    if (_frameHistory.length > _maxHistorySize) {
      _frameHistory.removeAt(0);
    }

    state = state.copyWith(lastFrameDurationMs: durationMs);

    // Performance-triggered downgrade
    if (durationMs > _thresholds.maxFrameDurationMs) {
      _considerPerformanceDowngrade('frame_exceeded');
    }
  }

  /// Set a manual user override for the engine tier.
  ///
  /// When set, the manager will not automatically switch away from
  /// the user's chosen tier. Call [clearUserOverride] to resume
  /// automatic management.
  void setUserOverride(EngineTier tier) {
    _debounceTimer?.cancel();

    state = state.copyWith(
      currentTier: tier,
      recommendedTier: tier,
      userOverride: true,
      switchPending: false,
      notificationMessage: 'Layout set to ${tier.label}',
    );

    _logTierSwitch(tier, reason: 'user_override');
  }

  /// Clear the user override and resume automatic tier management.
  void clearUserOverride() {
    state = state.copyWith(
      userOverride: false,
      notificationMessage: null,
    );

    // Re-evaluate with current node count
    updateNodeCount(state.nodeCount);
  }

  /// Compute layout using the current tier's engine.
  ///
  /// Delegates to the appropriate layout engine based on the current tier.
  GraphLayoutResult computeLayout({
    required List<GraphPerson> persons,
    required List<GraphRelationship> relationships,
    String? anchorPersonId,
  }) {
    return switch (state.currentTier) {
      EngineTier.force => _computeForceLayout(
          persons, relationships, anchorPersonId),
      EngineTier.hybrid => _computeHybridLayout(
          persons, relationships, anchorPersonId),
      EngineTier.radial => _computeRadialLayout(
          persons, relationships, anchorPersonId),
      EngineTier.hierarchical => _computeHierarchicalLayout(
          persons, relationships, anchorPersonId),
      EngineTier.emergency => _computeEmergencyLayout(
          persons, relationships, anchorPersonId),
    };
  }

  /// Get the interpolated positions during crossfade.
  ///
  /// Returns blended positions between old and new based on
  /// [FallbackState.crossfadeProgress].
  Map<String, Offset> getInterpolatedPositions() {
    final old = state.oldPositions;
    final newPositions = state.newPositions;

    if (old == null || newPositions == null) {
      return newPositions ?? old ?? {};
    }

    final progress = state.crossfadeProgress;
    final result = <String, Offset>{};

    // All person IDs from both maps
    final allIds = <String>{...old.keys, ...newPositions.keys};

    for (final id in allIds) {
      final oldPos = old[id];
      final newPos = newPositions[id];

      if (oldPos != null && newPos != null) {
        result[id] = Offset(
          oldPos.dx + (newPos.dx - oldPos.dx) * progress,
          oldPos.dy + (newPos.dy - oldPos.dy) * progress,
        );
      } else if (newPos != null) {
        result[id] = newPos;
      } else if (oldPos != null) {
        result[id] = oldPos;
      }
    }

    return result;
  }

  /// Get the average tick duration over the last N samples.
  double get averageTickDuration {
    if (_tickHistory.isEmpty) return 0.0;
    return _tickHistory.reduce((a, b) => a + b) / _tickHistory.length;
  }

  /// Get the average frame duration over the last N samples.
  double get averageFrameDuration {
    if (_frameHistory.isEmpty) return 0.0;
    return _frameHistory.reduce((a, b) => a + b) / _frameHistory.length;
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _crossfadeTimer?.cancel();
    super.dispose();
  }

  // ── Private ───────────────────────────────────────────────────────

  /// Compute the recommended tier for a given node count.
  EngineTier _computeRecommendedTier(int nodeCount) {
    if (nodeCount <= _thresholds.forceMax) return EngineTier.force;
    if (nodeCount <= _thresholds.hybridMax) return EngineTier.hybrid;
    if (nodeCount <= _thresholds.radialMax) return EngineTier.radial;
    if (nodeCount <= _thresholds.hierarchicalMax) return EngineTier.hierarchical;
    return EngineTier.emergency;
  }

  /// Evaluate whether a tier switch should occur.
  void _evaluateSwitch(EngineTier recommended) {
    if (state.userOverride) return;
    if (recommended == state.currentTier) {
      // Cancel pending switch if recommended is back to current
      if (state.switchPending) {
        _debounceTimer?.cancel();
        state = state.copyWith(
          switchPending: false,
          notificationMessage: null,
        );
      }
      return;
    }

    // Start debounce timer
    state = state.copyWith(switchPending: true);

    _debounceTimer?.cancel();
    _debounceTimer = Timer(
      Duration(milliseconds: _thresholds.debounceMs),
      () => _executeSwitch(recommended),
    );
  }

  /// Execute a tier switch with crossfade animation.
  void _executeSwitch(EngineTier newTier) {
    final isDowngrade = newTier.index > state.currentTier.index;

    final notification = isDowngrade
        ? 'Switched to ${newTier.label} layout for performance'
        : 'Switched to ${newTier.label} layout';

    state = state.copyWith(
      currentTier: newTier,
      switchPending: false,
      notificationMessage: notification,
      crossfadeProgress: 0.0,
    );

    _logTierSwitch(newTier, reason: 'auto_node_count');

    // Animate crossfade
    _startCrossfade();
  }

  /// Start the crossfade animation between old and new positions.
  void _startCrossfade() {
    _crossfadeTimer?.cancel();
    const steps = 30;
    final stepDuration = _thresholds.crossfadeMs ~/ steps;
    var step = 0;

    _crossfadeTimer = Timer.periodic(
      Duration(milliseconds: stepDuration),
      (timer) {
        step++;
        final progress = (step / steps).clamp(0.0, 1.0);
        state = state.copyWith(crossfadeProgress: progress);

        if (step >= steps) {
          timer.cancel();
          state = state.copyWith(
            crossfadeProgress: 1.0,
            oldPositions: null,
          );
        }
      },
    );
  }

  /// Consider a performance-triggered downgrade.
  void _considerPerformanceDowngrade(String reason) {
    if (state.userOverride) return;

    // Only downgrade, never upgrade from performance triggers
    final nextTier = EngineTier.values.where(
      (t) => t.index > state.currentTier.index,
    ).firstOrNull;

    if (nextTier == null) return;

    // Check if average performance is also bad (avoid single-frame spikes)
    final avgTick = averageTickDuration;
    final avgFrame = averageFrameDuration;

    if (avgTick > _thresholds.maxTickDurationMs ||
        avgFrame > _thresholds.maxFrameDurationMs) {
      _debounceTimer?.cancel();
      _executeSwitch(nextTier);
      _logTierSwitch(nextTier, reason: reason);
    }
  }

  /// Log a tier switch event to analytics.
  void _logTierSwitch(EngineTier newTier, {required String reason}) {
    try {
      final analytics = AnalyticsService.instance;
      analytics.logEvent('graph_engine_switch', <String, Object>{
        'new_tier': newTier.name,
        'node_count': state.nodeCount,
        'reason': reason,
        'avg_tick_ms': averageTickDuration.toStringAsFixed(2),
        'avg_frame_ms': averageFrameDuration.toStringAsFixed(2),
      });
    } catch (_) {
      // Analytics failure must not crash the layout engine
    }
  }

  // ── Layout computation delegates ──────────────────────────────────

  GraphLayoutResult _computeForceLayout(
    List<GraphPerson> persons,
    List<GraphRelationship> relationships,
    String? anchorPersonId,
  ) {
    final simulator = ForceSimulator();
    simulator.initialize(persons, relationships);
    final positions = simulator.runSync();
    simulator.dispose();

    double maxX = 0.0;
    double maxY = 0.0;
    for (final pos in positions.values) {
      if (pos.dx > maxX) maxX = pos.dx;
      if (pos.dy > maxY) maxY = pos.dy;
    }

    return GraphLayoutResult(
      positions: positions,
      canvasWidth: maxX + 200,
      canvasHeight: maxY + 200,
    );
  }

  GraphLayoutResult _computeHybridLayout(
    List<GraphPerson> persons,
    List<GraphRelationship> relationships,
    String? anchorPersonId,
  ) {
    // Hybrid: simplified force with fewer iterations
    final simulator = ForceSimulator(
      config: const SimulationConfig(
        alphaDecay: 0.05, // faster decay
        velocityDecay: 0.5, // more damping
        maxTicks: 2000, // fewer iterations
      ),
    );
    simulator.initialize(persons, relationships);
    final positions = simulator.runSync();
    simulator.dispose();

    double maxX = 0.0;
    double maxY = 0.0;
    for (final pos in positions.values) {
      if (pos.dx > maxX) maxX = pos.dx;
      if (pos.dy > maxY) maxY = pos.dy;
    }

    return GraphLayoutResult(
      positions: positions,
      canvasWidth: maxX + 200,
      canvasHeight: maxY + 200,
    );
  }

  GraphLayoutResult _computeRadialLayout(
    List<GraphPerson> persons,
    List<GraphRelationship> relationships,
    String? anchorPersonId,
  ) {
    final layout = RadialLayout();
    return layout.compute(
      persons: persons,
      relationships: relationships,
      anchorPersonId: anchorPersonId,
    );
  }

  GraphLayoutResult _computeHierarchicalLayout(
    List<GraphPerson> persons,
    List<GraphRelationship> relationships,
    String? anchorPersonId,
  ) {
    final layout = HierarchicalLayout();
    return layout.compute(
      persons: persons,
      relationships: relationships,
      anchorPersonId: anchorPersonId,
    );
  }

  GraphLayoutResult _computeEmergencyLayout(
    List<GraphPerson> persons,
    List<GraphRelationship> relationships,
    String? anchorPersonId,
  ) {
    // Emergency: list-based fallback — positions nodes in a simple grid
    final columns = sqrt(persons.length).ceil();
    final positions = <String, Offset>{};
    const cellWidth = 140.0;
    const cellHeight = 160.0;

    for (var i = 0; i < persons.length; i++) {
      final row = i ~/ columns;
      final col = i % columns;
      positions[persons[i].id] = Offset(
        col * cellWidth + 50.0,
        row * cellHeight + 50.0,
      );
    }

    return GraphLayoutResult(
      positions: positions,
      canvasWidth: columns * cellWidth + 100.0,
      canvasHeight: (persons.length ~/ columns + 1) * cellHeight + 100.0,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// RIVERPOD PROVIDERS
// ═══════════════════════════════════════════════════════════════════════

/// Provider for the [FallbackManager] StateNotifier.
final fallbackManagerProvider =
    StateNotifierProvider<FallbackManager, FallbackState>((ref) {
  final manager = FallbackManager();
  ref.onDispose(() => manager.dispose());
  return manager;
});

/// Provider for the current engine tier.
final currentEngineTierProvider = Provider<EngineTier>((ref) {
  return ref.watch(fallbackManagerProvider).currentTier;
});

/// Provider for the interpolated (crossfaded) positions.
final interpolatedPositionsProvider = Provider<Map<String, Offset>>((ref) {
  final manager = ref.read(fallbackManagerProvider.notifier);
  return manager.getInterpolatedPositions();
});

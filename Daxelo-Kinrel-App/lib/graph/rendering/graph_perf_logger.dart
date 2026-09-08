// lib/graph/rendering/graph_perf_logger.dart
//
// DAXELO KINREL — Graph Performance Logger (v5.143)
//
// Lightweight timing logger for the graph pipeline. Records wall-clock
// durations for each stage of the build and only logs when a stage
// exceeds its threshold OR when the total build exceeds the frame
// budget (16.67 ms at 60 FPS).
//
// DESIGN
// ──────
// • Zero allocation in release builds — the Stopwatch is created but
//   never started, and all log methods are no-ops when kReleaseMode.
// • Per-stage thresholds filter out noise — a 0.2 ms filtering stage
//   won't spam the logs, but a 12 ms layout stage will.
// • The logger is a stateful object (not a global) so each _buildCanvas
//   call gets its own. The final summary is emitted in `finish()`.
//
// USAGE
// ─────
// ```dart
// final perf = GraphPerfLogger();
// perf.start('filter');
// final filtered = buildFilteredGraph(...);
// perf.end('filter');
//
// perf.start('layout');
// final layout = computeLayout(...);
// perf.end('layout');
//
// perf.start('paint');
// _buildCanvas(...);
// perf.end('paint');
//
// perf.finish();  // logs the summary if any stage exceeded threshold
// ```
//
// OUTPUT FORMAT
// ─────────────
// ```
// [GRAPH PERF] build=18.2ms JANK | filter=0.3ms | layout=0.0ms | edges=2.1ms | paint=15.5ms | nodes=50 | edges=120 | total=700
// ```
// Stages that didn't run are omitted. Stages under threshold are
// included in the summary only if the total exceeded the frame budget.

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kReleaseMode, debugPrint;

/// Logs timing for graph pipeline stages. See file header.
class GraphPerfLogger {
  GraphPerfLogger();

  /// Whether logging is enabled. Always false in release builds.
  static bool get enabled => !kReleaseMode;

  /// Per-stage thresholds in milliseconds. Stages under their threshold
  /// are omitted from the log UNLESS the total build exceeded the frame
  /// budget (16.67 ms).
  static const Map<String, double> _thresholds = {
    'filter': 1.0,
    'layout': 2.0,
    'edges': 2.0,
    'paint': 5.0,
    'pan': 4.0,
    'zoom': 4.0,
    'cull': 1.0,
    'collapse': 2.0,
    'pathfocus': 1.0,
  };

  /// The frame budget in milliseconds (60 FPS = 16.67 ms).
  static const double kFrameBudgetMs = 16.67;

  final Map<String, Stopwatch> _stopwatches = {};
  final Map<String, int> _counts = {};

  /// Start timing a stage. Safe to call multiple times — the second
  /// call is a no-op if the stopwatch is already running.
  void start(String stage) {
    if (!enabled) return;
    final sw = _stopwatches.putIfAbsent(stage, () => Stopwatch());
    if (!sw.isRunning) sw.start();
  }

  /// Stop timing a stage. Records the elapsed milliseconds.
  void end(String stage) {
    if (!enabled) return;
    final sw = _stopwatches[stage];
    if (sw == null || !sw.isRunning) return;
    sw.stop();
  }

  /// Record a count for a stage (e.g. node count, edge count).
  /// Used in the summary line.
  void count(String name, int value) {
    if (!enabled) return;
    _counts[name] = value;
  }

  /// Emit the summary log line if any stage exceeded its threshold OR
  /// the total build exceeded the frame budget. Called once at the end
  /// of _buildCanvas.
  void finish({String label = 'build'}) {
    if (!enabled) return;

    double totalMs = 0;
    final stageParts = <String>[];
    bool anyStageOverThreshold = false;

    for (final entry in _stopwatches.entries) {
      final stage = entry.key;
      final sw = entry.value;
      final ms = sw.elapsedMilliseconds + sw.elapsedMicroseconds % 1000 / 1000.0;
      totalMs += ms;

      final threshold = _thresholds[stage] ?? 1.0;
      if (ms > threshold) {
        anyStageOverThreshold = true;
        stageParts.add('$stage=${ms.toStringAsFixed(1)}ms');
      }
    }

    final isJank = totalMs > kFrameBudgetMs;

    // Only log if something is interesting:
    // • Total exceeded frame budget (jank), OR
    // • Any individual stage exceeded its threshold
    if (!isJank && !anyStageOverThreshold) return;

    final countParts = <String>[];
    for (final entry in _counts.entries) {
      countParts.add('${entry.key}=${entry.value}');
    }

    final jankMarker = isJank ? ' JANK' : '';
    final allParts = [
      '$label=${totalMs.toStringAsFixed(1)}ms$jankMarker',
      ...stageParts,
      ...countParts,
    ];

    debugPrint('[GRAPH PERF] ${allParts.join(' | ')}');
  }

  /// Reset all stages for reuse. Call at the start of _buildCanvas.
  void reset() {
    for (final sw in _stopwatches.values) {
      sw.reset();
    }
    _counts.clear();
  }
}

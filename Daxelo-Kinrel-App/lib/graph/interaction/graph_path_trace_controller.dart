// lib/graph/interaction/graph_path_trace_controller.dart
//
// DAXELO KINREL — Sequential Path Trace (v92, 2026-07-12)
//
// FINAL 10/10 COMPLETION PASS — Part 15.
//
// One graph-level state machine that drives a sequential one-shot
// light-sweep along the ordered edges of a resolved kinship path.
//
// ARCHITECTURE
// ─────────────
// • ONE AnimationController (ticker provided by the consumer widget
//   via TickerProvider). No per-edge controllers.
// • The trace walks the path edges in order. At each tick the
//   controller exposes:
//     - currentTraceEdgeId   — the edge currently being swept
//     - completedEdgeIds     — edges already swept (remain statically
//                              focused)
//     - traceProgress        — 0..1 progress along the CURRENT edge
//     - traceActive          — true while the trace is running
// • The edge painter reads these values and draws:
//     - completed edges: normal path-focus state (slightly brighter)
//     - current edge:    the moving sweep highlight (reuses the
//                         existing sweep paint pass from v91)
//     - future edges:    normal path-focus state
// • After the last edge completes, the controller stops and exposes
//   the full path as `completedEdgeIds` so the painter keeps the
//   static focus.
// • If a new target is selected mid-trace, the consumer calls
//   `startTrace(...)` again — the controller cancels the in-flight
//   trace cleanly and begins a new one.
// • If reduced motion is active, the consumer calls `revealAll()`
//   instead — every edge becomes "completed" with no animation.
//
// TIMING RULES (per spec)
// ───────────────────────
//   1–5 edges:    ~320 ms per edge
//   6–10 edges:   ~250 ms per edge
//   >10 edges:    ~180 ms per edge, capped at ~2200 ms total
//
// No continuous animation. No repeat. No per-edge ticker.

import 'package:flutter/foundation.dart';
import 'package:flutter/animation.dart';

import 'haptic_language.dart' show GraphHaptics;

/// State machine for the sequential path trace.
enum GraphPathTracePhase {
  /// No trace active. Either no path has been focused yet, or a
  /// trace completed and the static focus remains.
  idle,

  /// A trace is currently running.
  tracing,

  /// Reduced motion is active — the entire path was revealed
  /// statically without animation.
  revealedStatically,
}

/// Immutable snapshot of the trace state, consumed by the edge painter.
@immutable
class GraphPathTraceState {
  const GraphPathTraceState({
    this.phase = GraphPathTracePhase.idle,
    this.currentEdgeId,
    this.completedEdgeIds = const <String>{},
    this.traceProgress = 0.0,
    this.traceActive = false,
  });

  final GraphPathTracePhase phase;

  /// The edge currently being swept. Null when phase is idle or
  /// revealedStatically.
  final String? currentEdgeId;

  /// Edges that have already been swept and should remain statically
  /// focused.
  final Set<String> completedEdgeIds;

  /// 0..1 progress along the current edge.
  final double traceProgress;

  /// True while the trace is running.
  final bool traceActive;

  static const GraphPathTraceState empty = GraphPathTraceState();

  GraphPathTraceState copyWith({
    GraphPathTracePhase? phase,
    String? currentEdgeId,
    Set<String>? completedEdgeIds,
    double? traceProgress,
    bool? traceActive,
  }) {
    return GraphPathTraceState(
      phase: phase ?? this.phase,
      currentEdgeId: currentEdgeId ?? this.currentEdgeId,
      completedEdgeIds: completedEdgeIds ?? this.completedEdgeIds,
      traceProgress: traceProgress ?? this.traceProgress,
      traceActive: traceActive ?? this.traceActive,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GraphPathTraceState &&
          other.phase == phase &&
          other.currentEdgeId == currentEdgeId &&
          other.traceActive == traceActive &&
          other.traceProgress == traceProgress &&
          _setEquals(other.completedEdgeIds, completedEdgeIds);

  static bool _setEquals(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }

  @override
  int get hashCode => Object.hash(
      phase, currentEdgeId, traceActive, traceProgress, completedEdgeIds.length);

  @override
  String toString() =>
      'GraphPathTraceState(phase=$phase, current=$currentEdgeId, '
      'completed=${completedEdgeIds.length}, progress=$traceProgress, active=$traceActive)';
}

/// Controller for the sequential path trace.
///
/// Lifecycle:
///   1. Consumer calls `attach(vsync)` once when the host widget
///      becomes mounted.
///   2. Consumer calls `startTrace(orderedEdgeIds)` whenever a new
///      path is resolved (or when the user re-triggers the trace).
///   3. Consumer calls `revealAll(orderedEdgeIds)` when reduced motion
///      is active — skips the animation entirely.
///   4. Consumer calls `detach()` when the host widget disposes.
///
/// The controller does NOT own a TickerProvider — the consumer widget
/// provides it via `attach(vsync)`. This keeps the controller testable
/// and avoids creating a second ticker source.
class GraphPathTraceController extends ChangeNotifier {
  GraphPathTraceController();

  GraphPathTraceState _state = GraphPathTraceState.empty;
  GraphPathTraceState get state => _state;

  AnimationController? _controller;
  VoidCallback? _controllerListener;
  List<String> _orderedEdgeIds = const [];
  int _currentIndex = 0;

  /// v5.93: Optional per-edge pixel lengths for the connect-on-open
  /// animation. When non-null, each edge's duration is computed
  /// individually via [_connectOnOpenDurationMs] so all edges appear
  /// to draw at the same visual speed (proportional to pixel length).
  /// When null, the existing [_perEdgeDurationMs] bucket timing is
  /// used (same duration for all edges in the sequence).
  Map<String, double>? _orderedEdgeLengths;

  /// P3.2: Reduced-motion flag. When true, the controller suppresses
  /// haptic feedback on each edge completion. The consumer should
  /// also call `revealAll()` instead of `startTrace()` when this is
  /// true (so `_onTick` never fires) — this flag is a defensive
  /// backstop in case `startTrace` is called while reduced motion is
  /// active.
  ///
  /// Default false. The consumer sets this via [reducedMotion] when
  /// the MediaQuery flag changes.
  bool _reducedMotion = false;
  bool get reducedMotion => _reducedMotion;
  set reducedMotion(bool value) {
    _reducedMotion = value;
  }

  /// Wire the controller to a TickerProvider (typically the
  /// `_EdgeSelectionWrapperState` which already has
  /// `SingleTickerProviderStateMixin`). Must be called before
  /// `startTrace` / `revealAll`.
  ///
  /// The consumer must call `detach()` when its widget disposes.
  void attach(TickerProvider vsync) {
    if (_controller != null) return; // idempotent
    _controller = AnimationController(
      vsync: vsync,
      duration: Duration(milliseconds: _perEdgeDurationMs(1)),
    );
    _controllerListener = _onTick;
    _controller!.addListener(_controllerListener!);
  }

  /// Disconnect the controller from its ticker. Safe to call multiple
  /// times.
  void detach() {
    _controller?.removeListener(_controllerListener!);
    _controller?.dispose();
    _controller = null;
    _controllerListener = null;
    _state = GraphPathTraceState.empty;
    _orderedEdgeIds = const [];
    _orderedEdgeLengths = null;
    _currentIndex = 0;
  }

  /// Begin a sequential one-shot trace along [orderedEdgeIds].
  ///
  /// If a trace is already running it is cancelled cleanly — the
  /// previously completed edges remain in `completedEdgeIds` only if
  /// they are also in the new [orderedEdgeIds]. Otherwise the
  /// completed set is reset.
  ///
  /// If [orderedEdgeIds] is empty, the controller goes idle.
  ///
  /// Per-edge duration is chosen by `_perEdgeDurationMs(edgeCount)`:
  ///   1–5 edges: 320 ms
  ///   6–10 edges: 250 ms
  ///   >10 edges: 180 ms (capped at ~2200 ms total)
  ///
  /// v5.93: When [edgeLengths] is non-null (connect-on-open mode),
  /// each edge's duration is computed individually via
  /// [_connectOnOpenDurationMs] based on that edge's pixel length, so
  /// all edges appear to draw at the same visual speed. This mode is
  /// slower (1.0–3.0 seconds per edge) and is ONLY used by
  /// connect-on-open — the kinship path-focus trace never passes
  /// [edgeLengths] and keeps the existing fast bucket timing.
  void startTrace(
    List<String> orderedEdgeIds, {
    Map<String, double>? edgeLengths,
  }) {
    if (_controller == null) {
      // Not attached — fall back to revealAll behaviour.
      revealAll(orderedEdgeIds);
      return;
    }
    if (orderedEdgeIds.isEmpty) {
      _resetToIdle();
      return;
    }

    // Preserve completion only for edges still in the new path.
    final preserved = _state.completedEdgeIds
        .intersection(orderedEdgeIds.toSet());

    _orderedEdgeIds = List.unmodifiable(orderedEdgeIds);
    _orderedEdgeLengths = edgeLengths;
    _currentIndex = 0;
    _state = GraphPathTraceState(
      phase: GraphPathTracePhase.tracing,
      currentEdgeId: _orderedEdgeIds[0],
      completedEdgeIds: preserved,
      traceProgress: 0.0,
      traceActive: true,
    );
    notifyListeners();

    // Configure per-edge duration and start.
    // v5.93: When edgeLengths is provided (connect-on-open), use the
    // length-proportional duration for the FIRST edge. Subsequent
    // edges get their own duration in _onTick when advancing.
    final int firstEdgeDurationMs;
    if (edgeLengths != null) {
      final firstEdgeId = _orderedEdgeIds[0];
      final firstLen = edgeLengths[firstEdgeId] ?? 400.0;
      firstEdgeDurationMs = _connectOnOpenDurationMs(firstLen);
    } else {
      firstEdgeDurationMs = _perEdgeDurationMs(_orderedEdgeIds.length);
    }
    _controller!.duration = Duration(milliseconds: firstEdgeDurationMs);
    _controller!.forward(from: 0.0);
  }

  /// Reveal the entire path statically without animation. Used when
  /// reduced motion is active.
  void revealAll(List<String> orderedEdgeIds) {
    _controller?.stop();
    _orderedEdgeIds = List.unmodifiable(orderedEdgeIds);
    _currentIndex = orderedEdgeIds.length;
    _state = GraphPathTraceState(
      phase: orderedEdgeIds.isEmpty
          ? GraphPathTracePhase.idle
          : GraphPathTracePhase.revealedStatically,
      currentEdgeId: null,
      completedEdgeIds: orderedEdgeIds.toSet(),
      traceProgress: 0.0,
      traceActive: false,
    );
    notifyListeners();
  }

  /// Reset to idle — clears all trace state. Called when the path
  /// focus is cleared.
  void reset() {
    _controller?.stop();
    _resetToIdle();
  }

  void _resetToIdle() {
    _orderedEdgeIds = const [];
    _orderedEdgeLengths = null;
    _currentIndex = 0;
    _state = GraphPathTraceState.empty;
    notifyListeners();
  }

  void _onTick() {
    if (_controller == null || _currentIndex >= _orderedEdgeIds.length) {
      return;
    }
    final progress = _controller!.value;
    if (progress >= 1.0) {
      // Current edge finished — add to completed and advance.
      final newCompleted =
          Set<String>.from(_state.completedEdgeIds)
            ..add(_orderedEdgeIds[_currentIndex]);
      // P3.2: rhythmic footsteps haptic on each edge completion.
      // Suppressed when reduced motion is active.
      GraphHaptics.pathTraceStep(reducedMotion: _reducedMotion);
      _currentIndex += 1;

      if (_currentIndex >= _orderedEdgeIds.length) {
        // Trace complete.
        _state = GraphPathTraceState(
          phase: GraphPathTracePhase.idle,
          currentEdgeId: null,
          completedEdgeIds: newCompleted,
          traceProgress: 0.0,
          traceActive: false,
        );
        notifyListeners();
        return;
      }

      // Advance to next edge.
      _state = GraphPathTraceState(
        phase: GraphPathTracePhase.tracing,
        currentEdgeId: _orderedEdgeIds[_currentIndex],
        completedEdgeIds: newCompleted,
        traceProgress: 0.0,
        traceActive: true,
      );
      notifyListeners();
      // v5.93: When edgeLengths is provided (connect-on-open), set
      // the duration fresh for the NEXT edge based on its own pixel
      // length. When null, the existing bucket timing (already set
      // in startTrace) is reused for all edges.
      if (_orderedEdgeLengths != null) {
        final nextEdgeId = _orderedEdgeIds[_currentIndex];
        final nextLen = _orderedEdgeLengths![nextEdgeId] ?? 400.0;
        _controller!.duration =
            Duration(milliseconds: _connectOnOpenDurationMs(nextLen));
      }
      _controller!.forward(from: 0.0);
    } else {
      // Mid-edge — update progress.
      _state = _state.copyWith(
        traceProgress: progress,
        traceActive: true,
      );
      notifyListeners();
    }
  }

  /// Choose per-edge duration based on path length, per spec.
  ///   1–5 edges: 320 ms
  ///   6–10 edges: 250 ms
  ///   >10 edges: 180 ms
  /// Total capped at ~2200 ms for very long paths.
  int _perEdgeDurationMs(int edgeCount) {
    if (edgeCount <= 0) return 0;
    if (edgeCount <= 5) return 320;
    if (edgeCount <= 10) return 250;
    // >10 edges — 180 ms per edge, but cap total at ~2200 ms.
    final total = 180 * edgeCount;
    if (total <= 2200) return 180;
    // Spread the cap evenly across edges.
    return (2200 / edgeCount).round();
  }

  /// v5.93: Connect-on-open per-edge duration: proportional to the
  /// edge's pixel length so all edges appear to draw at the same
  /// visual speed, clamped to a 1.0–3.0 second range per edge.
  ///
  /// This is ONLY used by connect-on-open (when [edgeLengths] is
  /// passed to [startTrace]). The kinship path-focus trace never
  /// passes [edgeLengths] and keeps the existing fast bucket timing
  /// from [_perEdgeDurationMs].
  int _connectOnOpenDurationMs(double edgeLength) {
    const double pxPerSecond = 220.0; // tune for desired feel
    final double seconds = (edgeLength / pxPerSecond).clamp(1.0, 3.0);
    return (seconds * 1000).round();
  }
}

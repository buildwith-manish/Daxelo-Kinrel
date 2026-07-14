// lib/features/family_map/data/family_map_lifecycle.dart
//
// Authoritative Family Map lifecycle state machine.
//
// Replaces the fragile multi-boolean lifecycle (`_styleLoaded` +
// `_loadState.phase` + `_buildingsAdded` + `_entranceAnimationDone`)
// with a single enum that the screen watches. Every initialization
// attempt MUST end in a terminal state (ready / empty / failed) —
// never in an intermediate state forever.
//
// INVARIANTS:
//   • `initializing` → terminal: the style JSON is being read from
//     rootBundle. Bounded by `_loadStyleJson`'s 10-second timeout +
//     try/catch fallback. Cannot hang.
//   • `loadingStyle` → terminal: MapLibreMap widget is rendered and
//     waiting for `onStyleLoaded`. A bounded watchdog (8 seconds)
//     forces this to `ready`/`empty` even if the callback never
//     fires (maplibre 0.3.5 web plugin has a known bug where
//     `onStyleLoaded` is not invoked for inline JSON styles).
//   • `preparingLayers` → terminal: optional premium layers (family
//     buildings, relationship paths, avatar overlay probes) are
//     being attached. Any failure is logged and skipped — the base
//     map is already usable.
//   • `ready`: map is interactive, family data exists.
//   • `empty`: map is interactive, no family data (0 located
//     members). Still shows the base map + a compact empty-state
//     overlay. NOT a loading state.
//   • `failed`: a REQUIRED initialization step failed (style JSON
//     could not be loaded even with the inline fallback). Shows a
//     retry button.
//
// The loading indicator (MapSkeleton / "Loading family map…") is
// ONLY shown during `initializing` and `loadingStyle`. Once the
// lifecycle reaches `preparingLayers`, `ready`, `empty`, or
// `failed`, the base map is visible and the loader is gone.
//
// Race-condition protection: each initialization attempt increments
// `_attempt`. Stale callbacks check `if (attempt != _attempt) return;`
// before mutating state, so a Retry cannot be overwritten by the
// previous attempt's late callback.

import 'package:flutter/foundation.dart';

/// Authoritative lifecycle of the Family Map screen.
enum FamilyMapLifecycle {
  /// Style JSON is being read from rootBundle (bounded by 10s timeout).
  initializing,

  /// Style JSON loaded; MapLibreMap widget is rendered and waiting for
  /// `onStyleLoaded`. Bounded by an 8-second watchdog.
  loadingStyle,

  /// Style loaded (or watchdog fired); optional premium layers are being
  /// attached. The base map is already visible + interactive.
  preparingLayers,

  /// Map is fully ready and family data is displayed.
  ready,

  /// Map is fully ready but no family data (0 located members). The
  /// base map is interactive; an empty-state overlay is shown.
  empty,

  /// A REQUIRED initialization step failed. Show retry UI.
  failed,
}

/// Extension with convenience helpers for [FamilyMapLifecycle].
extension FamilyMapLifecycleX on FamilyMapLifecycle {
  /// True when the loading overlay (skeleton) should be visible.
  ///
  /// The overlay is shown ONLY during `initializing` and `loadingStyle`.
  /// Once `preparingLayers` is reached, the base map is visible and the
  /// overlay is removed — premium layers attach progressively on top.
  bool get showLoadingOverlay {
    switch (this) {
      case FamilyMapLifecycle.initializing:
      case FamilyMapLifecycle.loadingStyle:
        return true;
      case FamilyMapLifecycle.preparingLayers:
      case FamilyMapLifecycle.ready:
      case FamilyMapLifecycle.empty:
      case FamilyMapLifecycle.failed:
        return false;
    }
  }

  /// True when the map is in a terminal state (no further lifecycle
  /// transitions will occur for this attempt).
  bool get isTerminal {
    switch (this) {
      case FamilyMapLifecycle.ready:
      case FamilyMapLifecycle.empty:
      case FamilyMapLifecycle.failed:
        return true;
      case FamilyMapLifecycle.initializing:
      case FamilyMapLifecycle.loadingStyle:
      case FamilyMapLifecycle.preparingLayers:
        return false;
    }
  }

  /// True when the map widget should be rendered (i.e., the style JSON
  /// has been resolved and the MapLibreMap widget can be mounted).
  bool get shouldRenderMap {
    switch (this) {
      case FamilyMapLifecycle.initializing:
        return false;
      case FamilyMapLifecycle.loadingStyle:
      case FamilyMapLifecycle.preparingLayers:
      case FamilyMapLifecycle.ready:
      case FamilyMapLifecycle.empty:
      case FamilyMapLifecycle.failed:
        return true;
    }
  }

  /// User-facing loading message for the skeleton. Returns null when
  /// no message should be shown (terminal states).
  String? get loadingMessage {
    switch (this) {
      case FamilyMapLifecycle.initializing:
        return 'Loading family map…';
      case FamilyMapLifecycle.loadingStyle:
        return 'Loading family map…';
      case FamilyMapLifecycle.preparingLayers:
        // PreparingLayers is a brief, non-blocking phase. The base map
        // is already visible; we don't show a separate message.
        return null;
      case FamilyMapLifecycle.ready:
      case FamilyMapLifecycle.empty:
      case FamilyMapLifecycle.failed:
        return null;
    }
  }
}

/// Notifier that owns the [FamilyMapLifecycle] state.
///
/// Race-condition protection: every transition method takes an
/// `attempt` parameter. If `attempt != _currentAttempt`, the
/// transition is silently dropped — a stale callback from a previous
/// initialization attempt cannot overwrite the current state.
class FamilyMapLifecycleController extends ChangeNotifier {
  FamilyMapLifecycle _state = FamilyMapLifecycle.initializing;

  /// Monotonically increasing attempt ID. Incremented on every
  /// `reset()`. Stale callbacks compare against this to bail out.
  int _currentAttempt = 0;

  FamilyMapLifecycle get state => _state;

  /// The current attempt ID. Callbacks capture this value when they
  /// start and bail out if it changes before they complete.
  int get currentAttempt => _currentAttempt;

  /// Resets the lifecycle to `initializing` and increments the attempt
  /// ID, invalidating all in-flight callbacks from the previous attempt.
  void reset() {
    _currentAttempt++;
    _state = FamilyMapLifecycle.initializing;
    notifyListeners();
  }

  /// Transitions to [next] if [attempt] matches the current attempt.
  /// Stale attempts are silently dropped.
  void transition(FamilyMapLifecycle next, {required int attempt}) {
    if (attempt != _currentAttempt) {
      debugPrint('FamilyMapLifecycle: dropping stale transition to '
          '$next (attempt=$attempt, current=$_currentAttempt)');
      return;
    }
    if (_state == next) return;
    // Once terminal, no further transitions are allowed (a new attempt
    // must call reset() first).
    if (_state.isTerminal) {
      debugPrint('FamilyMapLifecycle: ignoring transition to $next '
          'from terminal state $_state');
      return;
    }
    debugPrint('FamilyMapLifecycle: $_state → $next (attempt=$attempt)');
    _state = next;
    notifyListeners();
  }

  @override
  String toString() => 'FamilyMapLifecycle($_state, attempt=$_currentAttempt)';
}

// lib/features/ambient_orbit/providers/ambient_orbit_provider.dart
//
// P9.2h — Ambient idle orbit.
//
// A slow, optional background motion shown when the app is idle on a
// screen that opts in (e.g. the family-graph canvas). This provider
// only holds the *state* (active/inactive, phase, reduced-motion
// preference); the painter reads from it. There is no engagement
// payload — the orbit is decorative and respects the user's
// reduced-motion setting.
//
// Constitution / Copy-Audit: no "stay in the app" framing, no rewards
// for idle time, no analytics on idle duration.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class AmbientOrbitState {
  const AmbientOrbitState({
    this.isActive = false,
    this.reducedMotion = false,
    /// 0..1 phase around the orbit, advanced by the painter's ticker.
    this.phase = 0.0,
    this.lastActivatedAt,
  });

  final bool isActive;
  final bool reducedMotion;
  final double phase;
  final DateTime? lastActivatedAt;

  /// When reduced motion is on, the orbit is frozen at phase 0 and only
  /// a static motif is shown — no animation, no ticker.
  bool get rendersMotion => isActive && !reducedMotion;

  AmbientOrbitState copyWith({
    bool? isActive,
    bool? reducedMotion,
    double? phase,
    DateTime? lastActivatedAt,
    bool clearLastActivated = false,
  }) {
    return AmbientOrbitState(
      isActive: isActive ?? this.isActive,
      reducedMotion: reducedMotion ?? this.reducedMotion,
      phase: phase ?? this.phase,
      lastActivatedAt:
          clearLastActivated ? null : (lastActivatedAt ?? this.lastActivatedAt),
    );
  }
}

class AmbientOrbitNotifier extends StateNotifier<AmbientOrbitState> {
  AmbientOrbitNotifier() : super(const AmbientOrbitState());

  /// Turns the orbit on. When reduced motion is set, this still marks the
  /// overlay active (so the static motif shows) but `rendersMotion` stays
  /// false.
  void activate() {
    state = state.copyWith(
      isActive: true,
      lastActivatedAt: DateTime.now(),
    );
  }

  void deactivate() => state = state.copyWith(isActive: false);

  void toggle() {
    if (state.isActive) {
      deactivate();
    } else {
      activate();
    }
  }

  /// Sets the user's reduced-motion preference. When turned on, the
  /// phase is reset to 0 so any frozen frame is the canonical one.
  void setReducedMotion(bool value) {
    state = state.copyWith(
      reducedMotion: value,
      phase: value ? 0.0 : state.phase,
    );
  }

  /// Advances the orbit phase by [delta] (clamped to [0,1)). Called by
  /// the painter's ticker; ignored entirely under reduced motion.
  void advance(double delta) {
    if (!state.rendersMotion) return;
    var next = (state.phase + delta) % 1.0;
    if (next < 0) next += 1.0;
    state = state.copyWith(phase: next);
  }

  void reset() => state = const AmbientOrbitState();
}

final ambientOrbitProvider =
    StateNotifierProvider<AmbientOrbitNotifier, AmbientOrbitState>(
  (ref) => AmbientOrbitNotifier(),
);

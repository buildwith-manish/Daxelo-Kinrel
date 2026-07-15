// lib/features/family_map/data/progressive_loading.dart
//
// P10.8 — Progressive Loading state machine.
//
// The map loads in 8 ordered phases. Each phase shows content as
// soon as its data arrives — phases are MAXIMUM thresholds, not
// fixed delays. The user sees content earlier and the perceived
// latency drops.
//
//   Phase 1: skeleton (dark map background + "Loading family map…" text)
//   Phase 2: cached viewport (from previous session, P10.9)
//   Phase 3: map tiles (MapLibre handles this)
//   Phase 4: roads + buildings (from tile data)
//   Phase 5: family places (P10.2 buildings)
//   Phase 6: relationship paths (P10.5)
//   Phase 7: markers (P10.3 avatars)
//   Phase 8: start animations (P10.5 flow, P10.6 focus)
//
// Rule 13: nothing in this file is performance-sensitive. The screen
// sets the phase on each data arrival; this enum is just a label.
//
// Rule 15: phases 5-8 work offline (cached data). Phases 3-4 (tiles)
// may be unavailable offline — the screen shows cached tiles or a
// dark background + a subtle "Offline" indicator.

import 'package:flutter/foundation.dart';

/// The 8 phases of progressive map loading.
enum MapLoadPhase {
  /// Dark background + "Loading family map…" text.
  skeleton,

  /// Cached viewport from the previous session (P10.9).
  cachedViewport,

  /// Map tiles have started arriving.
  tiles,

  /// Roads + buildings are visible.
  roadsAndBuildings,

  /// Family places (P10.2) are rendered.
  familyPlaces,

  /// Relationship paths (P10.5) are rendered.
  relationshipPaths,

  /// Avatar markers (P10.3) are rendered.
  markers,

  /// All animations have started (P10.5 flow, P10.6 focus).
  animations,

  /// All phases complete. Steady state.
  complete,
}

/// Progression helper for [MapLoadPhase].
extension MapLoadPhaseX on MapLoadPhase {
  /// The next phase in the progression.
  MapLoadPhase? get next {
    final i = MapLoadPhase.values.indexOf(this);
    if (i + 1 >= MapLoadPhase.values.length) return null;
    return MapLoadPhase.values[i + 1];
  }

  /// True when this phase is at or beyond [other].
  bool isAtLeast(MapLoadPhase other) =>
      MapLoadPhase.values.indexOf(this) >= MapLoadPhase.values.indexOf(other);
}

/// Tracks the current load phase + a short human-readable label.
@immutable
class MapLoadState {
  const MapLoadState({
    this.phase = MapLoadPhase.skeleton,
    this.isOffline = false,
    this.takingTooLong = false,
  });

  final MapLoadPhase phase;
  final bool isOffline;
  final bool takingTooLong;

  /// User-facing message for the current phase.
  String get message {
    if (isOffline && phase.index < MapLoadPhase.familyPlaces.index) {
      return 'Offline — showing cached data';
    }
    switch (phase) {
      case MapLoadPhase.skeleton:
        return 'Loading family map…';
      case MapLoadPhase.cachedViewport:
        return 'Restoring your view…';
      case MapLoadPhase.tiles:
        return 'Loading map…';
      case MapLoadPhase.roadsAndBuildings:
        return 'Loading landmarks…';
      case MapLoadPhase.familyPlaces:
        return 'Loading family places…';
      case MapLoadPhase.relationshipPaths:
        return 'Loading connections…';
      case MapLoadPhase.markers:
        return 'Loading family members…';
      case MapLoadPhase.animations:
        return 'Almost there…';
      case MapLoadPhase.complete:
        return '';
    }
  }

  MapLoadState copyWith({
    MapLoadPhase? phase,
    bool? isOffline,
    bool? takingTooLong,
  }) {
    return MapLoadState(
      phase: phase ?? this.phase,
      isOffline: isOffline ?? this.isOffline,
      takingTooLong: takingTooLong ?? this.takingTooLong,
    );
  }
}

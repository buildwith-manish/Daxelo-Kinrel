// lib/features/cameo/style/cameo_camera_rules.dart
//
// KINREL CAMEO — Camera Rules
//
// Deterministic camera framing, field-of-view, orbit limits, and
// responsive framing rules for every Cameo surface (V2 §30).
//
// INVARIANTS:
//   • Portrait framing (head + shoulders) is the default for dense
//     surfaces (Map markers, Graph nodes, Chat avatars).
//   • Bust framing (head + upper torso) is for Profile hero and Studio.
//   • Full framing is for Journey cinematic ONLY.
//   • Camera FOV is 28° (portrait lens) — never wide-angle distortion.
//   • Orbit is constrained to ±35° yaw, ±12° pitch — no under-chin,
//     no top-down. Dignified framing always.
//   • No accidental zoom: pinch-zoom is capped to [0.8×, 1.4×].
//   • No viewport forcing: the Cameo fits its container with letter-
//     boxing if aspect ratios mismatch; it NEVER crops the face.

import 'package:flutter/material.dart';

import 'cameo_pose_catalog.dart';

/// Deterministic camera configuration for a Cameo surface.
@immutable
class CameoCameraRules {
  const CameoCameraRules({
    required this.surfaceId,
    required this.frame,
    required this.fovDegrees,
    required this.yawRangeDegrees,
    required this.pitchRangeDegrees,
    required this.zoomRange,
    required this.eyeHeightFraction,
    required this.allowOrbit,
    required this.allowZoom,
  });

  /// Which surface this config applies to (e.g. 'studio', 'profile_hero').
  final String surfaceId;

  /// The framing (portrait / bust / full).
  final CameoCameraFrame frame;

  /// Field of view in degrees. Portrait lens = 28°.
  final double fovDegrees;

  /// (min, max) yaw in degrees. Negative = camera-left.
  final (double, double) yawRangeDegrees;

  /// (min, max) pitch in degrees. Negative = down.
  final (double, double) pitchRangeDegrees;

  /// (min, max) pinch-zoom multiplier.
  final (double, double) zoomRange;

  /// Vertical position of the eye-line as a fraction of the frame
  /// height (0 = top, 1 = bottom). Rule of thirds → 0.40.
  final double eyeHeightFraction;

  /// Whether the user can orbit (drag to rotate). Off on dense surfaces.
  final bool allowOrbit;

  /// Whether the user can pinch-zoom. Off on Map/Graph nodes.
  final bool allowZoom;

  /// Clamp a yaw value to this camera's allowed range.
  double clampYaw(double yaw) {
    return yaw.clamp(yawRangeDegrees.$1, yawRangeDegrees.$2);
  }

  /// Clamp a pitch value to this camera's allowed range.
  double clampPitch(double pitch) {
    return pitch.clamp(pitchRangeDegrees.$1, pitchRangeDegrees.$2);
  }

  /// Clamp a zoom value to this camera's allowed range.
  double clampZoom(double zoom) {
    return zoom.clamp(zoomRange.$1, zoomRange.$2);
  }
}

/// The deterministic library of approved camera configurations.
@immutable
class CameoCameraPresets {
  const CameoCameraPresets._();

  /// Studio — bust framing, full orbit, full zoom (V2 §30.2, §34.2).
  static const CameoCameraRules studio = CameoCameraRules(
    surfaceId: 'studio',
    frame: CameoCameraFrame.bust,
    fovDegrees: 28,
    yawRangeDegrees: (-180, 180),
    pitchRangeDegrees: (-12, 12),
    zoomRange: (0.5, 2.0),
    eyeHeightFraction: 0.40,
    allowOrbit: true,
    allowZoom: true,
  );

  /// Profile hero — bust framing, limited orbit, no zoom (V2 §37.2).
  static const CameoCameraRules profileHero = CameoCameraRules(
    surfaceId: 'profile_hero',
    frame: CameoCameraFrame.bust,
    fovDegrees: 28,
    yawRangeDegrees: (-35, 35),
    pitchRangeDegrees: (-8, 8),
    zoomRange: (1.0, 1.0),
    eyeHeightFraction: 0.42,
    allowOrbit: true,
    allowZoom: false,
  );

  /// Family Map marker — portrait framing, no orbit, no zoom (V2 §38).
  static const CameoCameraRules mapMarker = CameoCameraRules(
    surfaceId: 'map_marker',
    frame: CameoCameraFrame.portrait,
    fovDegrees: 28,
    yawRangeDegrees: (0, 0),
    pitchRangeDegrees: (0, 0),
    zoomRange: (1.0, 1.0),
    eyeHeightFraction: 0.40,
    allowOrbit: false,
    allowZoom: false,
  );

  /// Family Graph node — portrait framing, no orbit, no zoom (V2 §39).
  static const CameoCameraRules graphNode = CameoCameraRules(
    surfaceId: 'graph_node',
    frame: CameoCameraFrame.portrait,
    fovDegrees: 28,
    yawRangeDegrees: (0, 0),
    pitchRangeDegrees: (0, 0),
    zoomRange: (1.0, 1.0),
    eyeHeightFraction: 0.40,
    allowOrbit: false,
    allowZoom: false,
  );

  /// Chat avatar — tight portrait, no orbit, no zoom (V2 §43).
  static const CameoCameraRules chatAvatar = CameoCameraRules(
    surfaceId: 'chat_avatar',
    frame: CameoCameraFrame.portrait,
    fovDegrees: 28,
    yawRangeDegrees: (0, 0),
    pitchRangeDegrees: (0, 0),
    zoomRange: (1.0, 1.0),
    eyeHeightFraction: 0.38,
    allowOrbit: false,
    allowZoom: false,
  );

  /// Journey cinematic — full framing, orbit scripted, no user zoom (V2 §40).
  static const CameoCameraRules journey = CameoCameraRules(
    surfaceId: 'journey',
    frame: CameoCameraFrame.full,
    fovDegrees: 32,
    yawRangeDegrees: (-45, 45),
    pitchRangeDegrees: (-10, 10),
    zoomRange: (1.0, 1.0),
    eyeHeightFraction: 0.45,
    allowOrbit: true,
    allowZoom: false,
  );

  /// Timeline card — portrait framing, no orbit, no zoom (V2 §41).
  static const CameoCameraRules timelineCard = CameoCameraRules(
    surfaceId: 'timeline_card',
    frame: CameoCameraFrame.portrait,
    fovDegrees: 28,
    yawRangeDegrees: (0, 0),
    pitchRangeDegrees: (0, 0),
    zoomRange: (1.0, 1.0),
    eyeHeightFraction: 0.40,
    allowOrbit: false,
    allowZoom: false,
  );

  /// All approved camera presets.
  static const List<CameoCameraRules> all = <CameoCameraRules>[
    studio,
    profileHero,
    mapMarker,
    graphNode,
    chatAvatar,
    journey,
    timelineCard,
  ];

  /// Look up a preset by surface id. Returns [studio] as the safe default.
  static CameoCameraRules byId(String surfaceId) {
    for (final c in all) {
      if (c.surfaceId == surfaceId) return c;
    }
    return studio;
  }
}

// lib/features/cameo/style/cameo_animation_curves.dart
//
// KINREL CAMEO — Animation Curves & Tuning
//
// Deterministic animation parameters for every Cameo surface (V2 §32,
// §67). Premium, subtle, restrained motion ONLY:
//   • Breathing: 4s sine wave, 0.6px chest rise at UI size. Period
//     never shorter than 3.5s (no panting).
//   • Blink: 110ms close + 220ms open. Random interval 3.2–6.0s.
//     Never shorter than 3.0s (no fluttering).
//   • Saccades: 80ms micro-move, random interval 1.6–3.4s. Offset
//     magnitude capped at 0.6mm at UI size.
//   • Head sway: 8s sine wave, 0.4° amplitude. Never more.
//   • Camera idle drift: 60s orbit, 1.2° amplitude. Off on dense
//     surfaces.
//
// UNDER REDUCED MOTION (V2 §67, §66):
//   • Breathing → static.
//   • Blink → static (eyes open).
//   • Saccades → static.
//   • Head sway → static.
//   • Camera idle drift → static.
//   • State transitions → instant snap (no 260ms easeOutCubic).
//   • Trait change crossfade → instant.
//   • Real 3D rendering stays (character is still 3D, just static).
//
// WHAT IS FORBIDDEN (V2 §1, request "no excessive bouncing, looping
// game-idle behavior, uncanny facial movement"):
//   • No bounce / overshoot curves on the character.
//   • No game-idle weight-shift loops.
//   • No "look at camera then look away" head animation loops.
//   • No lip-sync without audio.
//   • No procedural fidgeting.

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Deterministic animation tuning for a Cameo surface.
@immutable
class CameoAnimationCurves {
  const CameoAnimationCurves({
    required this.surfaceId,
    required this.breathingPeriod,
    required this.breathingAmplitudePx,
    required this.blinkCloseMs,
    required this.blinkOpenMs,
    required this.blinkIntervalMinS,
    required this.blinkIntervalMaxS,
    required this.saccadeDurationMs,
    required this.saccadeIntervalMinS,
    required this.saccadeIntervalMaxS,
    required this.saccadeMagnitudeMm,
    required this.headSwayPeriod,
    required this.headSwayAmplitudeDeg,
    required this.cameraIdleDriftPeriod,
    required this.cameraIdleDriftAmplitudeDeg,
    required this.stateTransitionDuration,
    required this.stateTransitionCurve,
    required this.traitChangeCrossfadeMs,
    required this.allowBreathing,
    required this.allowBlink,
    required this.allowSaccades,
    required this.allowHeadSway,
    required this.allowCameraIdleDrift,
  });

  final String surfaceId;

  // Breathing
  final Duration breathingPeriod;
  final double breathingAmplitudePx;

  // Blink
  final int blinkCloseMs;
  final int blinkOpenMs;
  final double blinkIntervalMinS;
  final double blinkIntervalMaxS;

  // Saccades
  final int saccadeDurationMs;
  final double saccadeIntervalMinS;
  final double saccadeIntervalMaxS;
  final double saccadeMagnitudeMm;

  // Head sway
  final Duration headSwayPeriod;
  final double headSwayAmplitudeDeg;

  // Camera idle drift
  final Duration cameraIdleDriftPeriod;
  final double cameraIdleDriftAmplitudeDeg;

  // Transitions
  final Duration stateTransitionDuration;
  final Curve stateTransitionCurve;
  final int traitChangeCrossfadeMs;

  // Feature flags (dense surfaces disable most motion)
  final bool allowBreathing;
  final bool allowBlink;
  final bool allowSaccades;
  final bool allowHeadSway;
  final bool allowCameraIdleDrift;

  /// Returns a reduced-motion copy of this config (V2 §67).
  /// All motion is stopped; transitions snap instantly.
  CameoAnimationCurves asReducedMotion() {
    return CameoAnimationCurves(
      surfaceId: surfaceId,
      breathingPeriod: breathingPeriod,
      breathingAmplitudePx: 0,
      blinkCloseMs: blinkCloseMs,
      blinkOpenMs: blinkOpenMs,
      blinkIntervalMinS: double.infinity,
      blinkIntervalMaxS: double.infinity,
      saccadeDurationMs: saccadeDurationMs,
      saccadeIntervalMinS: double.infinity,
      saccadeIntervalMaxS: double.infinity,
      saccadeMagnitudeMm: 0,
      headSwayPeriod: headSwayPeriod,
      headSwayAmplitudeDeg: 0,
      cameraIdleDriftPeriod: cameraIdleDriftPeriod,
      cameraIdleDriftAmplitudeDeg: 0,
      stateTransitionDuration: Duration.zero,
      stateTransitionCurve: stateTransitionCurve,
      traitChangeCrossfadeMs: 0,
      allowBreathing: false,
      allowBlink: false,
      allowSaccades: false,
      allowHeadSway: false,
      allowCameraIdleDrift: false,
    );
  }

  /// Returns a low-tier-device copy: disables camera idle drift and
  /// saccades (the two most GPU-sensitive micro-motions). Breathing
  /// and blink stay (they're cheap and they're the soul of the Cameo).
  CameoAnimationCurves asLowTier() {
    return copyWith(
      allowCameraIdleDrift: false,
      allowSaccades: false,
      cameraIdleDriftAmplitudeDeg: 0,
      saccadeMagnitudeMm: 0,
    );
  }

  /// Generic copy-with.
  CameoAnimationCurves copyWith({
    String? surfaceId,
    bool? allowBreathing,
    bool? allowBlink,
    bool? allowSaccades,
    bool? allowHeadSway,
    bool? allowCameraIdleDrift,
    double? breathingAmplitudePx,
    double? cameraIdleDriftAmplitudeDeg,
    double? saccadeMagnitudeMm,
    Duration? stateTransitionDuration,
    int? traitChangeCrossfadeMs,
  }) {
    return CameoAnimationCurves(
      surfaceId: surfaceId ?? this.surfaceId,
      breathingPeriod: breathingPeriod,
      breathingAmplitudePx: breathingAmplitudePx ?? this.breathingAmplitudePx,
      blinkCloseMs: blinkCloseMs,
      blinkOpenMs: blinkOpenMs,
      blinkIntervalMinS: blinkIntervalMinS,
      blinkIntervalMaxS: blinkIntervalMaxS,
      saccadeDurationMs: saccadeDurationMs,
      saccadeIntervalMinS: saccadeIntervalMinS,
      saccadeIntervalMaxS: saccadeIntervalMaxS,
      saccadeMagnitudeMm: saccadeMagnitudeMm ?? this.saccadeMagnitudeMm,
      headSwayPeriod: headSwayPeriod,
      headSwayAmplitudeDeg: headSwayAmplitudeDeg,
      cameraIdleDriftPeriod: cameraIdleDriftPeriod,
      cameraIdleDriftAmplitudeDeg:
          cameraIdleDriftAmplitudeDeg ?? this.cameraIdleDriftAmplitudeDeg,
      stateTransitionDuration:
          stateTransitionDuration ?? this.stateTransitionDuration,
      stateTransitionCurve: stateTransitionCurve,
      traitChangeCrossfadeMs:
          traitChangeCrossfadeMs ?? this.traitChangeCrossfadeMs,
      allowBreathing: allowBreathing ?? this.allowBreathing,
      allowBlink: allowBlink ?? this.allowBlink,
      allowSaccades: allowSaccades ?? this.allowSaccades,
      allowHeadSway: allowHeadSway ?? this.allowHeadSway,
      allowCameraIdleDrift: allowCameraIdleDrift ?? this.allowCameraIdleDrift,
    );
  }
}

/// The deterministic library of approved animation configs.
@immutable
class CameoAnimationPresets {
  const CameoAnimationPresets._();

  /// Studio — full subtle motion. The richest surface.
  static const CameoAnimationCurves studio = CameoAnimationCurves(
    surfaceId: 'studio',
    breathingPeriod: Duration(seconds: 4),
    breathingAmplitudePx: 0.6,
    blinkCloseMs: 110,
    blinkOpenMs: 220,
    blinkIntervalMinS: 3.2,
    blinkIntervalMaxS: 6.0,
    saccadeDurationMs: 80,
    saccadeIntervalMinS: 1.6,
    saccadeIntervalMaxS: 3.4,
    saccadeMagnitudeMm: 0.6,
    headSwayPeriod: Duration(seconds: 8),
    headSwayAmplitudeDeg: 0.4,
    cameraIdleDriftPeriod: Duration(seconds: 60),
    cameraIdleDriftAmplitudeDeg: 1.2,
    stateTransitionDuration: Duration(milliseconds: 260),
    stateTransitionCurve: Curves.easeOutCubic,
    traitChangeCrossfadeMs: 200,
    allowBreathing: true,
    allowBlink: true,
    allowSaccades: true,
    allowHeadSway: true,
    allowCameraIdleDrift: true,
  );

  /// Profile hero — same as Studio minus camera idle drift.
  static const CameoAnimationCurves profileHero = CameoAnimationCurves(
    surfaceId: 'profile_hero',
    breathingPeriod: Duration(seconds: 4),
    breathingAmplitudePx: 0.6,
    blinkCloseMs: 110,
    blinkOpenMs: 220,
    blinkIntervalMinS: 3.2,
    blinkIntervalMaxS: 6.0,
    saccadeDurationMs: 80,
    saccadeIntervalMinS: 1.6,
    saccadeIntervalMaxS: 3.4,
    saccadeMagnitudeMm: 0.6,
    headSwayPeriod: Duration(seconds: 8),
    headSwayAmplitudeDeg: 0.4,
    cameraIdleDriftPeriod: Duration(seconds: 60),
    cameraIdleDriftAmplitudeDeg: 0,
    stateTransitionDuration: Duration(milliseconds: 260),
    stateTransitionCurve: Curves.easeOutCubic,
    traitChangeCrossfadeMs: 200,
    allowBreathing: true,
    allowBlink: true,
    allowSaccades: true,
    allowHeadSway: true,
    allowCameraIdleDrift: false,
  );

  /// Family Map marker — derived PNG. No motion (it's a static image).
  static const CameoAnimationCurves mapMarker = CameoAnimationCurves(
    surfaceId: 'map_marker',
    breathingPeriod: Duration(seconds: 4),
    breathingAmplitudePx: 0,
    blinkCloseMs: 110,
    blinkOpenMs: 220,
    blinkIntervalMinS: double.infinity,
    blinkIntervalMaxS: double.infinity,
    saccadeDurationMs: 80,
    saccadeIntervalMinS: double.infinity,
    saccadeIntervalMaxS: double.infinity,
    saccadeMagnitudeMm: 0,
    headSwayPeriod: Duration(seconds: 8),
    headSwayAmplitudeDeg: 0,
    cameraIdleDriftPeriod: Duration(seconds: 60),
    cameraIdleDriftAmplitudeDeg: 0,
    stateTransitionDuration: Duration(milliseconds: 200),
    stateTransitionCurve: Curves.easeOutCubic,
    traitChangeCrossfadeMs: 0,
    allowBreathing: false,
    allowBlink: false,
    allowSaccades: false,
    allowHeadSway: false,
    allowCameraIdleDrift: false,
  );

  /// Family Graph node — same as Map marker (derived PNG).
  static final CameoAnimationCurves graphNode = mapMarker.copyWith(
    surfaceId: 'graph_node',
  );

  /// Chat avatar — same as Map marker.
  static final CameoAnimationCurves chatAvatar = mapMarker.copyWith(
    surfaceId: 'chat_avatar',
  );

  /// Timeline card — same as Map marker.
  static final CameoAnimationCurves timelineCard = mapMarker.copyWith(
    surfaceId: 'timeline_card',
  );

  /// Journey cinematic — full motion + scripted camera (V2 §40).
  static const CameoAnimationCurves journey = CameoAnimationCurves(
    surfaceId: 'journey',
    breathingPeriod: Duration(seconds: 4),
    breathingAmplitudePx: 0.8,
    blinkCloseMs: 110,
    blinkOpenMs: 220,
    blinkIntervalMinS: 3.2,
    blinkIntervalMaxS: 6.0,
    saccadeDurationMs: 80,
    saccadeIntervalMinS: 1.6,
    saccadeIntervalMaxS: 3.4,
    saccadeMagnitudeMm: 0.6,
    headSwayPeriod: Duration(seconds: 8),
    headSwayAmplitudeDeg: 0.5,
    cameraIdleDriftPeriod: Duration(seconds: 45),
    cameraIdleDriftAmplitudeDeg: 2.0,
    stateTransitionDuration: Duration(milliseconds: 320),
    stateTransitionCurve: Curves.easeOutCubic,
    traitChangeCrossfadeMs: 200,
    allowBreathing: true,
    allowBlink: true,
    allowSaccades: true,
    allowHeadSway: true,
    allowCameraIdleDrift: true,
  );

  /// All approved animation presets.
  static final List<CameoAnimationCurves> all = <CameoAnimationCurves>[
    studio,
    profileHero,
    mapMarker,
    graphNode,
    chatAvatar,
    timelineCard,
    journey,
  ];

  /// Look up by surface id. Returns [studio] as the safe default.
  static CameoAnimationCurves byId(String surfaceId) {
    for (final a in all) {
      if (a.surfaceId == surfaceId) return a;
    }
    return studio;
  }

  /// Resolve the effective animation config given platform accessibility
  /// flags. This is the SINGLE entry point that all Cameo animation
  /// controllers MUST use — never read a preset directly.
  static CameoAnimationCurves resolve({
    required String surfaceId,
    required bool reduceMotion,
    bool isLowTierDevice = false,
  }) {
    var config = byId(surfaceId);
    if (isLowTierDevice) {
      config = config.asLowTier();
    }
    if (reduceMotion) {
      config = config.asReducedMotion();
    }
    return config;
  }
}

/// A provider-agnostic accessor that mirrors the platform's
/// `MediaQuery.disableAnimationsOf` + the user's SharedPreferences
/// reduced-motion flag. Widgets should call this from `build` so the
/// resolve() above gets the right boolean without coupling to
/// SharedPreferences here.
///
/// Returns `true` if motion should be reduced. Implementations:
///   • Default: reads `MediaQuery.disableAnimationsOf(context)` only.
///   • App-level: combine with `SharedPreferences.getBool('reduced_motion')`.
bool cameoShouldReduceMotion(BuildContext context) {
  return MediaQuery.disableAnimationsOf(context);
}

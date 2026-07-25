// lib/features/cameo/style/cameo_camera_rules.dart
import 'package:flutter/material.dart';

enum CameoCameraFrame { portrait, bust, full }

@immutable
class CameoCameraRules {
  const CameoCameraRules({
    required this.surfaceId, required this.frame, required this.fovDegrees,
    required this.yawRangeDegrees, required this.pitchRangeDegrees,
    required this.zoomRange, required this.eyeHeightFraction,
    required this.allowOrbit, required this.allowZoom,
  });
  final String surfaceId;
  final CameoCameraFrame frame;
  final double fovDegrees;
  final (double, double) yawRangeDegrees;
  final (double, double) pitchRangeDegrees;
  final (double, double) zoomRange;
  final double eyeHeightFraction;
  final bool allowOrbit;
  final bool allowZoom;

  /// Clamps a yaw value (in degrees) to the allowed yawRangeDegrees.
  double clampYaw(double yaw) {
    return yaw.clamp(yawRangeDegrees.$1, yawRangeDegrees.$2);
  }

  /// Clamps a pitch value (in degrees) to the allowed pitchRangeDegrees.
  double clampPitch(double pitch) {
    return pitch.clamp(pitchRangeDegrees.$1, pitchRangeDegrees.$2);
  }
}

/// Plural wrapper with static presets + lookup methods.
/// Used by cameo_style_system.dart and cameo_quality_gates.dart.
class CameoCameraPresets {
  static const studio = CameoCameraRules(
    surfaceId: 'studio', frame: CameoCameraFrame.bust,
    fovDegrees: 28.0, yawRangeDegrees: (-35, 35), pitchRangeDegrees: (-12, 12),
    zoomRange: (0.8, 1.4), eyeHeightFraction: 0.95, allowOrbit: true, allowZoom: true,
  );

  static const profileHero = CameoCameraRules(
    surfaceId: 'profile_hero', frame: CameoCameraFrame.portrait,
    fovDegrees: 28.0, yawRangeDegrees: (-20, 20), pitchRangeDegrees: (-8, 8),
    zoomRange: (0.9, 1.3), eyeHeightFraction: 1.0, allowOrbit: true, allowZoom: true,
  );

  static const mapMarker = CameoCameraRules(
    surfaceId: 'map_marker', frame: CameoCameraFrame.portrait,
    fovDegrees: 32.0, yawRangeDegrees: (-15, 15), pitchRangeDegrees: (-5, 5),
    zoomRange: (1.0, 1.2), eyeHeightFraction: 1.0, allowOrbit: false, allowZoom: false,
  );

  static const graphNode = CameoCameraRules(
    surfaceId: 'graph_node', frame: CameoCameraFrame.portrait,
    fovDegrees: 30.0, yawRangeDegrees: (-25, 25), pitchRangeDegrees: (-10, 10),
    zoomRange: (0.95, 1.25), eyeHeightFraction: 1.0, allowOrbit: true, allowZoom: false,
  );

  static const chatAvatar = CameoCameraRules(
    surfaceId: 'chat_avatar', frame: CameoCameraFrame.portrait,
    fovDegrees: 28.0, yawRangeDegrees: (-10, 10), pitchRangeDegrees: (-5, 5),
    zoomRange: (1.0, 1.1), eyeHeightFraction: 1.0, allowOrbit: false, allowZoom: false,
  );

  static const journey = CameoCameraRules(
    surfaceId: 'journey', frame: CameoCameraFrame.full,
    fovDegrees: 35.0, yawRangeDegrees: (-45, 45), pitchRangeDegrees: (-15, 15),
    zoomRange: (0.7, 1.5), eyeHeightFraction: 0.9, allowOrbit: true, allowZoom: true,
  );

  static const all = [studio, profileHero, mapMarker, graphNode, chatAvatar, journey];

  /// Look up a camera preset by surface ID. Falls back to studio.
  static CameoCameraRules byId(String surfaceId) {
    return all.where((c) => c.surfaceId == surfaceId).firstOrNull ?? studio;
  }
}

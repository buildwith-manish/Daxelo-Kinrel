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
}

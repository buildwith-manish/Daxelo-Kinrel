// lib/features/cameo/style/cameo_pose_catalog.dart
//
// KINREL CAMEO — Pose Catalog
//
// Deterministic body pose presets for every Cameo. V2 §5.5 — pose and
// framing. Poses are restrained, dignified, and read at UI size:
//   • Shoulders turned 8° (not flat-on, not 3/4 profile).
//   • Head level or tilted 2–4° — never craned.
//   • Hands implied, not featured (Cameo is bust/portrait framing).
//   • Weight on the back hip for adults; centered for children.
//
// A pose is defined as a Bone Rotation Map (BRM): bone name → rotation
// in degrees (Euler XYZ). The 3D runtime applies these to the skeleton;
// the fallback painter picks a silhouette template per pose.

import 'package:flutter/material.dart';

import 'cameo_shape_language.dart' show CameoAgeBand;

/// A single body pose, defined as bone rotations in degrees.
@immutable
class CameoPose {
  const CameoPose({
    required this.id,
    required this.displayName,
    required this.boneRotations,
    required this.headTiltDegrees,
    required this.shoulderTurnDegrees,
    required this.cameraFrame,
  });

  final String id;
  final String displayName;

  /// Map from bone name → (x, y, z) rotation in degrees.
  final Map<String, Vector3Degrees> boneRotations;

  /// Head tilt around the forward axis (z). Negative = left tilt.
  final double headTiltDegrees;

  /// Shoulder turn around the up axis (y). Positive = camera-left.
  final double shoulderTurnDegrees;

  /// The camera framing this pose is designed for.
  final CameoCameraFrame cameraFrame;

  /// Returns the default pose for an age band.
  /// Children are centered and upright; adults gain a slight turn;
  /// elders gain a subtle stoop (V2 §15.7 — posture softens with age).
  static CameoPose defaultForAgeBand(CameoAgeBand band) {
    switch (band) {
      case CameoAgeBand.baby:
      case CameoAgeBand.child:
        return centered;
      case CameoAgeBand.teenager:
      case CameoAgeBand.youngAdult:
        return threeQuarter;
      case CameoAgeBand.adult:
      case CameoAgeBand.middleAged:
        return dignified;
      case CameoAgeBand.senior:
      case CameoAgeBand.elder:
        return dignifiedStooped;
    }
  }
}

/// A simple 3-axis rotation in degrees (Euler XYZ).
@immutable
class Vector3Degrees {
  const Vector3Degrees(this.x, this.y, this.z);
  final double x;
  final double y;
  final double z;

  static const Vector3Degrees zero = Vector3Degrees(0, 0, 0);
}

/// Camera framing options (V2 §30.1).
enum CameoCameraFrame {
  /// Head + shoulders. The default for portraits and graph nodes.
  portrait,

  /// Head + upper torso. For Profile hero and Studio.
  bust,

  /// Full body. For Journey cinematic only (V2 §1.9).
  full,
}

/// The deterministic library of approved Cameo poses.
@immutable
class CameoPoseCatalog {
  const CameoPoseCatalog._();

  /// Centered — shoulders flat, head level. For children and babies.
  static const CameoPose centered = CameoPose(
    id: 'centered',
    displayName: 'Centered',
    boneRotations: <String, Vector3Degrees>{
      'spine_01': Vector3Degrees(0, 0, 0),
      'neck': Vector3Degrees(0, 0, 0),
      'head': Vector3Degrees(0, 0, 0),
    },
    headTiltDegrees: 0,
    shoulderTurnDegrees: 0,
    cameraFrame: CameoCameraFrame.portrait,
  );

  /// Three-quarter — shoulders turned 8°, head turned 4° toward camera.
  /// The default Kinrel adult pose. Reads as natural and warm.
  static const CameoPose threeQuarter = CameoPose(
    id: 'three_quarter',
    displayName: 'Three-Quarter',
    boneRotations: <String, Vector3Degrees>{
      'spine_01': Vector3Degrees(0, -8, 0),
      'neck': Vector3Degrees(0, 4, 0),
      'head': Vector3Degrees(0, 0, 1),
    },
    headTiltDegrees: 1,
    shoulderTurnDegrees: -8,
    cameraFrame: CameoCameraFrame.bust,
  );

  /// Dignified — shoulders turned 6°, head level, slight chin lift.
  /// For middle-aged and senior adults.
  static const CameoPose dignified = CameoPose(
    id: 'dignified',
    displayName: 'Dignified',
    boneRotations: <String, Vector3Degrees>{
      'spine_01': Vector3Degrees(0, -6, 0),
      'neck': Vector3Degrees(-2, 2, 0),
      'head': Vector3Degrees(-1, 0, 0),
    },
    headTiltDegrees: 0,
    shoulderTurnDegrees: -6,
    cameraFrame: CameoCameraFrame.bust,
  );

  /// Dignified stooped — for elders (V2 §15.7). Posture droop applied.
  static const CameoPose dignifiedStooped = CameoPose(
    id: 'dignified_stooped',
    displayName: 'Dignified (Stooped)',
    boneRotations: <String, Vector3Degrees>{
      'spine_01': Vector3Degrees(6, -6, 0),
      'spine_02': Vector3Degrees(4, 0, 0),
      'neck': Vector3Degrees(-3, 2, 0),
      'head': Vector3Degrees(-2, 0, 0),
    },
    headTiltDegrees: 0,
    shoulderTurnDegrees: -6,
    cameraFrame: CameoCameraFrame.bust,
  );

  /// Journey walk — for the Journey cinematic (V2 §40). Full body.
  static const CameoPose journeyWalk = CameoPose(
    id: 'journey_walk',
    displayName: 'Journey Walk',
    boneRotations: <String, Vector3Degrees>{
      'spine_01': Vector3Degrees(0, -4, 0),
      'neck': Vector3Degrees(0, 2, 0),
      'head': Vector3Degrees(0, 0, 0),
      'thigh_l': Vector3Degrees(-12, 0, 0),
      'thigh_r': Vector3Degrees(12, 0, 0),
    },
    headTiltDegrees: 0,
    shoulderTurnDegrees: -4,
    cameraFrame: CameoCameraFrame.full,
  );

  /// All approved poses in deterministic order.
  static const List<CameoPose> all = <CameoPose>[
    centered, threeQuarter, dignified, dignifiedStooped, journeyWalk,
  ];

  /// Look up a pose by id. Returns [threeQuarter] as the safe default.
  static CameoPose byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return threeQuarter;
  }
}

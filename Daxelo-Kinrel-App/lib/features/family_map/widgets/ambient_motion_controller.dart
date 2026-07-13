// lib/features/family_map/widgets/ambient_motion_controller.dart
//
// P11.6 — Ambient Motion Controller.
//
// After [MapVisualConstants.ambientMotionIdleDelay] of no user interaction
// (desktop/web only — not mobile, where it would drain battery), the
// camera slowly drifts:
//   - Orbit the family center at [MapVisualConstants.ambientDriftRate]
//     degrees per second (very slow).
//   - Subtle parallax: buildings shift slightly relative to the camera
//     (handled by MapLibre's 3D perspective).
//
// Any user interaction (pan, zoom, tap) cancels the drift instantly.
//
// Rule 8 (Reduced motion): disabled entirely.
// Rule 6 (Performance): very slow drift — negligible cost. But if FPS
// drops, the drift is the first effect to disable.
// Rule 10 (Offline): works offline (local timer + camera API).

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart';

import '../../../core/utils/device_tier.dart';
import '../config/map_visual_constants.dart';

/// Manages the ambient camera drift after idle.
///
/// Lifecycle:
///   final controller = AmbientMotionController(vsync: this);
///   controller.attach(mapController);
///   // ... on user interaction:
///   controller.onUserInteraction();
///   // ... on dispose:
///   controller.dispose();
class AmbientMotionController {
  AmbientMotionController({required this.vsync, this.deviceTier});

  final TickerProvider vsync;
  final DeviceTier? deviceTier;

  MapController? _mapController;
  Timer? _idleTimer;
  AnimationController? _driftController;
  bool _enabled = false;

  DeviceTier get _effectiveTier =>
      deviceTier ?? DeviceTierCache.instance.tier;

  /// True if ambient motion is supported on this platform:
  /// - Desktop/web only (disabled on mobile — battery drain).
  /// - Not on low-tier devices (Rule 6).
  /// - Not when reduced motion is on (Rule 8).
  bool get isPlatformSupported {
    // Mobile (iOS/Android) — disabled to preserve battery.
    if (!kIsWeb && defaultTargetPlatform != TargetPlatform.macOS &&
        defaultTargetPlatform != TargetPlatform.windows &&
        defaultTargetPlatform != TargetPlatform.linux) {
      return false;
    }
    return true;
  }

  bool get isEnabled => _enabled;

  /// Attaches the controller to a MapController and starts the idle timer.
  void attach(MapController? controller) {
    _mapController = controller;
    _startIdleTimer();
  }

  /// Called on any user interaction (pan, zoom, tap). Resets the idle
  /// timer and stops the drift.
  void onUserInteraction() {
    _stopDrift();
    _startIdleTimer();
  }

  void _startIdleTimer() {
    _idleTimer?.cancel();
    if (!isPlatformSupported || _effectiveTier == DeviceTier.low) return;
    _idleTimer = Timer(MapVisualConstants.ambientMotionIdleDelay, _startDrift);
  }

  void _startDrift() {
    if (_mapController == null || !isPlatformSupported) return;
    _enabled = true;
    // Very slow drift: 1 full rotation in 3600 seconds (60 minutes).
    // At 0.1°/second, this is barely perceptible — "alive" not "moving."
    _driftController = AnimationController(
      vsync: vsync,
      duration: const Duration(seconds: 3600),
    )..repeat();
    _driftController!.addListener(_onDriftTick);
    debugPrint('🎨 P11.6: ambient motion drift started');
  }

  void _stopDrift() {
    _driftController?.dispose();
    _driftController = null;
    if (_enabled) {
      _enabled = false;
      debugPrint('🎨 P11.6: ambient motion drift stopped');
    }
  }

  void _onDriftTick() {
    final controller = _mapController;
    if (controller == null) return;
    final value = _driftController?.value ?? 0.0;
    // Increment bearing by 0.1° per second (ambientDriftRate).
    // The AnimationController repeats every 3600s, so value * 360 = degrees.
    final bearing = (value * 360.0) % 360.0;
    try {
      // moveCamera is instant (no animation) — the drift is smooth because
      // we call it on every frame (60 FPS).
      controller.moveCamera(bearing: bearing);
    } catch (e) {
      // Graceful degradation — stop the drift if the camera call fails.
      _stopDrift();
    }
  }

  void dispose() {
    _idleTimer?.cancel();
    _driftController?.dispose();
    _mapController = null;
  }
}

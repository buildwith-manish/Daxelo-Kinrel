// lib/core/utils/device_tier.dart
//
// DAXELO KINREL — Device Tier Detection & Adaptation Helpers
//
// Detects the device's capability tier based on screen metrics
// and provides helpers for adaptive UI (animations, shimmer, lottie).
//
// Detection logic (called once at startup, cached):
//   low:  screenWidth < 360 OR pixelRatio < 2.0
//   mid:  screenWidth 360–414 AND pixelRatio 2.0–2.9
//   high: screenWidth > 414 OR pixelRatio >= 3.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

// ── DeviceTier Enum ──────────────────────────────────────────────────

/// Represents the capability tier of the current device.
enum DeviceTier {
  /// Low-end: small screen or low pixel ratio.
  /// - Disable lottie animations (use static images)
  /// - Set flutter_animate durations to Duration.zero
  /// - Replace shimmer with static grey containers
  low,

  /// Mid-range: standard screens and pixel ratios.
  /// - Keep lottie animations
  /// - Keep original animation durations
  /// - Keep shimmer effects
  mid,

  /// High-end: large screens or high pixel ratios.
  /// - Keep lottie animations
  /// - Keep original animation durations
  /// - Keep shimmer effects
  high,
}

// ── DeviceTierCache (Singleton) ──────────────────────────────────────

/// Global cache for the detected device tier.
///
/// This is set once at startup and remains constant for the
/// app's lifecycle. It allows access from anywhere without
/// needing a Riverpod ref or BuildContext.
class DeviceTierCache {
  DeviceTierCache._();

  static final DeviceTierCache instance = DeviceTierCache._();

  DeviceTier _tier = DeviceTier.mid;
  bool _initialized = false;

  /// The detected device tier. Defaults to [DeviceTier.mid]
  /// until [initialize] is called.
  DeviceTier get tier => _tier;

  /// Whether the cache has been initialized.
  bool get isInitialized => _initialized;

  /// Detect and cache the device tier from screen metrics.
  void initialize(double screenWidth, double pixelRatio) {
    if (_initialized) return; // Only set once

    if (screenWidth < 360 || pixelRatio < 2.0) {
      _tier = DeviceTier.low;
    } else if (screenWidth > 414 || pixelRatio >= 3.0) {
      _tier = DeviceTier.high;
    } else {
      _tier = DeviceTier.mid;
    }

    _initialized = true;
    debugPrint('🔧 DeviceTier detected: $_tier '
        '(screenWidth: ${screenWidth.toStringAsFixed(1)}, '
        'pixelRatio: ${pixelRatio.toStringAsFixed(2)})');
  }

  // ── Adaptation Helpers ──────────────────────────────────────────

  /// Whether lottie animations should be used.
  /// Returns `true` for mid/high tier, `false` for low tier.
  bool get shouldUseLottie => _tier != DeviceTier.low;

  /// Whether flutter_animate animations should play.
  /// Returns `true` for mid/high tier, `false` for low tier.
  bool get shouldAnimate => _tier != DeviceTier.low;

  /// Whether shimmer loading animations should play.
  /// Returns `true` for mid/high tier, `false` for low tier.
  bool get shouldShimmer => _tier != DeviceTier.low;
}

// ── Riverpod Provider ────────────────────────────────────────────────

/// Provider that computes and caches the [DeviceTier].
///
/// Uses the first available [MediaQuery] data to detect screen metrics.
/// If no context is available (e.g., during early init), falls back
/// to the [DeviceTierCache] which may be initialized manually.
final deviceTierProvider = Provider<DeviceTier>((ref) {
  return DeviceTierCache.instance.tier;
});

// ── Tier-aware Duration Helpers ──────────────────────────────────────

/// Returns [Duration.zero] on low-tier devices, otherwise [original].
/// Use for flutter_animate effect durations.
Duration tierDuration(Duration original) {
  return DeviceTierCache.instance.shouldAnimate ? original : Duration.zero;
}

/// Returns [Duration.zero] on low-tier devices, otherwise [original].
/// Use for flutter_animate delay durations.
Duration tierDelay(Duration original) {
  return DeviceTierCache.instance.shouldAnimate ? original : Duration.zero;
}

// ── Widget Extension for Conditional Animation ───────────────────────

/// Extension on [Widget] that provides a drop-in replacement for
/// `.animate()` that respects device tier.
///
/// On low-tier devices:
///   - `autoPlay` is forced to `false` so animations don't run
///   - `value` is set to `1.0` so widgets show their final state
///   - `onPlay` is suppressed to prevent repeat animations
///   - Effects (fadeIn, slideY, etc.) are still applied but render
///     instantly at their completed state
///
/// On mid/high-tier devices, all parameters pass through unchanged.
///
/// Usage — replace `.animate(` with `.maybeAnimate(`:
/// ```dart
/// // Before:
/// MyWidget().animate().fadeIn(duration: 400.ms)
///
/// // After:
/// MyWidget().maybeAnimate().fadeIn(duration: 400.ms)
///
/// // With onPlay:
/// MyWidget().maybeAnimate(onPlay: (c) => c.forward()).fadeIn()
/// ```
extension TierAnimateExtension on Widget {
  /// Drop-in replacement for `.animate()` that adapts to device tier.
  ///
  /// Has the same signature as `AnimateWidgetExtensions.animate()`
  /// so it can be used as a direct replacement.
  Animate maybeAnimate({
    Key? key,
    List<Effect>? effects,
    AnimateCallback? onInit,
    AnimateCallback? onPlay,
    AnimateCallback? onComplete,
    bool? autoPlay,
    Duration? delay,
    AnimationController? controller,
    Adapter? adapter,
    double? target,
    double? value,
  }) {
    if (!DeviceTierCache.instance.shouldAnimate) {
      // Low-tier: disable animation, show final state instantly
      return Animate(
        key: key,
        effects: effects,
        onInit: onInit,
        // Don't call onPlay on low-tier (prevents repeat animations)
        onComplete: onComplete,
        autoPlay: false,
        delay: Duration.zero,
        controller: controller,
        adapter: adapter,
        target: target,
        value: 1.0, // Jump to completed state
        child: this,
      );
    }

    // Mid/high-tier: pass everything through unchanged
    return Animate(
      key: key,
      effects: effects,
      onInit: onInit,
      onPlay: onPlay,
      onComplete: onComplete,
      autoPlay: autoPlay,
      delay: delay,
      controller: controller,
      adapter: adapter,
      target: target,
      value: value,
      child: this,
    );
  }
}

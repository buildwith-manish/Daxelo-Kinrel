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
///
/// Part 1 fix — this is now a [ChangeNotifier] so widgets that depend
/// on the tier (e.g., MapControlStack reading `supports3DBuildings`)
/// can rebuild when the tier is finalized. This fixes the timing race
/// on web where `physicalSize` is `Size.zero` at the time `main()`
/// calls `initialize()` (before the first frame is laid out), causing
/// the tier to be wrongly detected as `low` (screenWidth=0 < 360).
/// The fix: `initialize()` detects the `Size.zero` case, defers to
/// `initializeFromView()` (called from the first frame's post-frame
/// callback), and notifies listeners when the tier is finalized.
class DeviceTierCache extends ChangeNotifier {
  DeviceTierCache._();
  static final DeviceTierCache instance = DeviceTierCache._();

  DeviceTier _tier = DeviceTier.mid;
  bool _initialized = false;

  /// The detected device tier. Defaults to [DeviceTier.mid]
  /// until [initialize] is called and resolves a non-zero screen size.
  DeviceTier get tier => _tier;

  /// Whether the cache has been initialized with a non-deferred tier
  /// detection. Returns false if `initialize()` was called with
  /// `Size.zero` (web before first frame) and the deferred
  /// `initializeFromView()` has not yet run.
  bool get isInitialized => _initialized;

  /// Detect and cache the device tier from screen metrics.
  ///
  /// If [screenWidth] is 0 or [pixelRatio] is 0 (which happens on web
  /// before the first frame is laid out — `view.physicalSize` is
  /// `Size.zero`), this method does NOT commit a tier. Instead it
  /// leaves `_initialized = false` and returns `false`. The caller
  /// (typically `main()`) should then schedule a post-frame callback
  /// to call [initializeFromView] once the view has a real size.
  ///
  /// Returns `true` if the tier was successfully detected and committed,
  /// `false` if the detection was deferred (caller must retry after the
  /// first frame).
  bool initialize(double screenWidth, double pixelRatio) {
    if (_initialized) return true; // Already set

    // ── Guard against Size.zero (web before first frame) ──────────
    // On web, `view.physicalSize` is `Size.zero` at the time `main()`
    // runs (before the first frame is laid out). If we naively computed
    // `screenWidth = 0 / pixelRatio = 0`, the `screenWidth < 360` check
    // would wrongly classify the device as `low` — hiding the 3D
    // Buildings toggle and forcing 2D mode on devices that should
    // support 3D.
    //
    // Fix: detect the zero-size case and defer. The caller schedules a
    // post-frame callback that calls `initializeFromView()` once the
    // view has a real size.
    if (screenWidth <= 0 || pixelRatio <= 0) {
      debugPrint('🔧 DeviceTier: deferring detection '
          '(screenWidth=$screenWidth, pixelRatio=$pixelRatio — '
          'view not yet laid out, likely web before first frame)');
      return false;
    }

    _commitTier(screenWidth, pixelRatio);
    return true;
  }

  /// Detect and cache the device tier from the current FlutterView.
  ///
  /// Intended to be called from a post-frame callback after the first
  /// frame is laid out (when `view.physicalSize` is no longer
  /// `Size.zero`). Idempotent — safe to call multiple times; once the
  /// tier is committed, subsequent calls are no-ops.
  void initializeFromView() {
    if (_initialized) return;
    try {
      final binding = WidgetsFlutterBinding.instance;
      final view = binding.platformDispatcher.views.first;
      final physicalSize = view.physicalSize;
      final pixelRatio = view.devicePixelRatio;
      final screenWidth = physicalSize.width / pixelRatio;
      if (screenWidth <= 0 || pixelRatio <= 0) {
        // Still no size — schedule another retry on the next frame.
        debugPrint('🔧 DeviceTier: still no view size, will retry next frame');
        return;
      }
      _commitTier(screenWidth, pixelRatio);
    } catch (e) {
      debugPrint('⚠️ DeviceTier: initializeFromView failed: $e');
    }
  }

  void _commitTier(double screenWidth, double pixelRatio) {
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
    // Notify any widgets that are waiting for the tier to resolve so
    // they can rebuild with the correct tier-dependent UI (e.g., the
    // 3D Buildings toggle in MapControlStack).
    notifyListeners();
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
/// Usage — replace `.animate(` with `.animate(`:
/// ```dart
/// // Before:
/// MyWidget().animate().fadeIn(duration: 400.ms)
///
/// // After:
/// MyWidget().animate().fadeIn(duration: 400.ms)
///
/// // With onPlay:
/// MyWidget().animate(onPlay: (c) => c.forward()).fadeIn()
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

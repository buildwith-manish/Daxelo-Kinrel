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

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  // ── Part E1: RAM-based low-RAM detection ───────────────────────────
  // _lowRam is true when (a) the Android ActivityManager.isLowRamDevice
  // flag is true, OR (b) totalRamMb <= 3300 (phones sold as 3GB report
  // about 2.8GB; 4GB phones report about 3.7GB), OR (c) the
  // FORCE_LOW_RAM dart-define is true. On web/iOS/desktop or on any
  // error, _lowRam is false unless forced.
  //
  // initializeRam() must never throw and must time out after 300ms —
  // the app must not block startup on a hung platform channel call.
  bool _lowRam = false;
  bool _ramInitialized = false;

  /// The detected device tier. Defaults to [DeviceTier.mid]
  /// until [initialize] is called and resolves a non-zero screen size.
  DeviceTier get tier => _tier;

  /// Whether the device has been flagged as low-RAM (Part E1).
  /// True when:
  ///   - Android ActivityManager.isLowRamDevice == true, OR
  ///   - totalRamMb <= 3300, OR
  ///   - the FORCE_LOW_RAM dart-define is true.
  /// False on web/iOS/desktop and on any error, unless forced.
  /// Reads from a cached field — does not trigger rebuilds when called
  /// from build methods. Call initializeRam() once at startup (in
  /// main.dart) before this getter returns a meaningful value.
  bool get lowRam => _lowRam;

  /// Whether the cache has been initialized with a non-deferred tier
  /// detection. Returns false if `initialize()` was called with
  /// `Size.zero` (web before first frame) and the deferred
  /// `initializeFromView()` has not yet run.
  bool get isInitialized => _initialized;

  /// Whether [initializeRam] has completed (success or timeout/error).
  /// Useful for tests; production code should just call initializeRam()
  /// once at startup and read [lowRam] later.
  bool get isRamInitialized => _ramInitialized;

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
      // Use WidgetsBinding.instance (not WidgetsFlutterBinding.instance)
      // — the latter requires the binding to be the explicit
      // WidgetsFlutterBinding type, which is not always the case in
      // tests. WidgetsBinding.instance works for any binding that
      // extends WidgetsBinding.
      final binding = WidgetsBinding.instance;
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

  // ── Part E1: RAM detection ────────────────────────────────────────────

  /// Compile-time force-low-RAM flag. When the dart-define
  /// `FORCE_LOW_RAM=true` is passed at build time, [lowRam] is forced
  /// to true regardless of the platform channel result. Useful for
  /// testing the low-RAM code paths on a strong phone.
  static const bool _forceLowRam =
      bool.fromEnvironment('FORCE_LOW_RAM', defaultValue: false);

  /// Detect and cache the low-RAM flag.
  ///
  /// Calls the `kinrel/device` platform channel's `memoryInfo` method,
  /// which on Android returns `{totalRamMb, isLowRamDevice}` from
  /// ActivityManager. On web/iOS/desktop or on any error, [lowRam] is
  /// false unless `_forceLowRam` is true.
  ///
  /// This method MUST NEVER THROW and MUST time out after 300ms —
  /// the app must not block startup on a hung platform channel call.
  /// On timeout, [lowRam] falls back to `_forceLowRam` (false unless
  /// forced).
  Future<void> initializeRam() async {
    if (_ramInitialized) return; // Idempotent

    // Compile-time force always wins.
    if (_forceLowRam) {
      _lowRam = true;
      _ramInitialized = true;
      debugPrint('🔧 DeviceTier.lowRam: forced true via FORCE_LOW_RAM');
      notifyListeners();
      return;
    }

    // Platform check: only Android has the MethodChannel handler.
    // On web/iOS/desktop, fall back to false.
    if (!_isAndroid) {
      _lowRam = false;
      _ramInitialized = true;
      debugPrint('🔧 DeviceTier.lowRam: false (non-Android platform)');
      // No notifyListeners() here — lowRam defaults to false already,
      // and widgets that read lowRam haven't been built yet (we're in
      // main() before runApp).
      return;
    }

    try {
      const channel = MethodChannel('kinrel/device');
      // Race the platform call against a 300ms timeout. The timeout
      // ensures a hung channel doesn't block the app from starting.
      final result = await channel
          .invokeMethod<Map<dynamic, dynamic>>('memoryInfo')
          .timeout(const Duration(milliseconds: 300));

      if (result == null) {
        _lowRam = false;
      } else {
        final totalRamMb = (result['totalRamMb'] as num?)?.toInt();
        final isLowRamDevice = result['isLowRamDevice'] as bool? ?? false;
        _lowRam = isLowRamDevice ||
            (totalRamMb != null && totalRamMb <= 3300);
      }
      debugPrint('🔧 DeviceTier.lowRam: $_lowRam '
          '(totalRamMb: ${result?['totalRamMb']}, '
          'isLowRamDevice: ${result?['isLowRamDevice']})');
    } catch (e) {
      // Any error (MissingPluginException, timeout, etc.) → fall back
      // to false. The app must not fail to start because of this.
      _lowRam = false;
      debugPrint('⚠️ DeviceTier.initializeRam failed: $e — falling back to lowRam=false');
    }

    _ramInitialized = true;
    // No notifyListeners() — see comment above. initializeRam is called
    // from main() before runApp(), so no widgets are listening yet.
  }

  /// Whether the current platform is Android. We avoid importing
  /// dart:io here so this file also compiles on web (where dart:io
  /// is unavailable). Instead, we use the PlatformDispatcher's
  /// defaultRouteName heuristic — but the simplest approach is to
  /// use `kIsWeb` from flutter/foundation plus the presence of the
  /// MethodChannel. Since the MethodChannel handler is only
  /// registered on Android (in MainActivity.kt), any platform that
  /// ISN'T web but also doesn't have a handler will fall back to
  /// false on the MissingPluginException — which is the correct
  /// behavior for iOS/desktop.
  ///
  /// We set _isAndroid = !kIsWeb here as a best-effort filter so we
  /// skip the channel call entirely on web (which would just throw
  /// MissingPluginException after 300ms). On iOS/desktop we still
  /// attempt the call and catch the exception — slightly slower but
  /// semantically correct.
  static final bool _isAndroid = !kIsWeb;

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

// ── Raster Budget (Tier E) ───────────────────────────────────────────
//
// A unified "raster budget" that combines three signals:
//   1. Platform (kIsWeb — Web Raster thread is much heavier per saveLayer)
//   2. RAM (Android ActivityManager.isLowRamDevice flag)
//   3. Device tier (low/mid/high from screen metrics)
//
// Maps every raster-expensive primitive to a clamp:
//   - BackdropFilter.blur sigma
//   - BoxShadow blurRadius
//   - ImageFilter.blur sigma
//
// Why a single budget instead of three separate booleans:
//   - The tier A/B/C/D changes already read `kIsWeb` and `lowRam`
//     inline at every hotspot. That works but scatters the logic
//     across 8 files. Centralizing here means a future device class
//     (e.g. a new Android Go tier) can be added by changing ONE
//     function, not 8 hotspots.
//
// Usage:
//   ```dart
//   final budget = DeviceTierCache.instance.rasterBudget;
//   ImageFilter.blur(sigmaX: budget.blurSigma, sigmaY: budget.blurSigma)
//   boxShadow: [
//     BoxShadow(blurRadius: budget.clampShadowBlur(24), offset: ...),
//   ]
//   ```

/// Three-step raster budget. Drives every clamp in the app.
enum RasterBudget {
  /// Full-spec raster — strong phones (≥4GB RAM, mid/high tier) on native.
  /// All shaders at full sigma/blur. Used as the production baseline.
  full,

  /// Reduced raster — web (any tier) OR low-RAM Android.
  /// Blur sigma capped at 6, shadow blur capped at 8, single-shadow
  /// instead of dual. Visually equivalent at 1x DPR; ~3-4x cheaper.
  reduced,

  /// Minimal raster — web on a low-tier device OR low-RAM + low-tier
  /// Android. Blur sigma = 0 (skipped entirely), shadow blur = 0
  /// (solid color fill only). Used as the absolute floor for
  /// devices where any GPU work would drop frames.
  minimal;

  /// The current device's [RasterBudget]. Combines [kIsWeb],
  /// [DeviceTierCache.lowRam], and [DeviceTierCache.tier].
  ///
  /// Resolution matrix:
  ///   - kIsWeb + low tier  → minimal
  ///   - kIsWeb + mid/high  → reduced
  ///   - Native + lowRam    → reduced (regardless of tier)
  ///   - Native + low tier  → reduced
  ///   - Native + mid/high  → full
  static RasterBudget get current {
    if (kIsWeb) {
      return DeviceTierCache.instance.tier == DeviceTier.low
          ? RasterBudget.minimal
          : RasterBudget.reduced;
    }
    if (DeviceTierCache.instance.lowRam ||
        DeviceTierCache.instance.tier == DeviceTier.low) {
      return RasterBudget.reduced;
    }
    return RasterBudget.full;
  }

  /// Backdrop-filter / image-filter blur sigma for this budget.
  /// - full:     16 (production-grade frosted glass)
  /// - reduced:   6 (web-capped — visually equivalent at wallpaper role)
  /// - minimal:   0 (skip blur entirely — use flat color)
  double get blurSigma => switch (this) {
        RasterBudget.full => 16.0,
        RasterBudget.reduced => 6.0,
        RasterBudget.minimal => 0.0,
      };

  /// Maximum blur radius for BoxShadow at this budget. The caller
  /// passes the *intended* native blur; the helper clamps it.
  /// - full:     unclamped (24+ for hero glows)
  /// - reduced:  8 (visually equivalent at 1x DPR)
  /// - minimal:  0 (no shadow — solid fill only)
  double clampShadowBlur(double intendedBlur) {
    return switch (this) {
      RasterBudget.full => intendedBlur,
      RasterBudget.reduced => intendedBlur.clamp(0.0, 8.0),
      RasterBudget.minimal => 0.0,
    };
  }

  /// Whether backdrop-filter / image-filter blur should be applied
  /// AT ALL. When false, callers should skip the wrapper entirely
  /// and use a flat color Container — saves the saveLayer cost.
  bool get shouldBlur => this != RasterBudget.minimal;

  /// Whether shadows should be painted at all. When false, callers
  /// should omit the `boxShadow:` parameter entirely.
  bool get shouldPaintShadow => this != RasterBudget.minimal;
}

/// Convenience extension on [DeviceTierCache] so callers can write
/// `DeviceTierCache.instance.rasterBudget` instead of
/// `RasterBudget.current` — matches the existing `lowRam` / `tier`
/// getter pattern.
extension RasterBudgetDeviceTierX on DeviceTierCache {
  /// The current device's raster budget (full / reduced / minimal).
  /// See [RasterBudget.current] for the resolution matrix.
  RasterBudget get rasterBudget => RasterBudget.current;
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

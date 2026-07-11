// lib/features/family_map/providers/graphics_tier_provider.dart
//
// DAXELO KINREL — Family Map Adaptive Graphics Tier System
//
// Monitors actual map/frame performance and dynamically selects the
// best rendering tier: HIGH, BALANCED, or LOW.
//
// Tiers:
//   HIGH     — full glow effects, smooth animations, premium pin shadows,
//              higher tile quality, animated relationship line pulses
//   BALANCED — reduced glow opacity, simpler pin shadows, standard tiles,
//              static relationship lines
//   LOW      — no glow, flat pins, minimal shadows, no animations,
//              basic tiles. Preserves family pins, live locations,
//              and relationship lines — just without the premium effects.
//
// Auto mode: monitors FPS over a rolling 3-second window. If sustained
// FPS drops below 45 for 2 consecutive windows, downgrades one tier.
// If FPS stays above 55 for 5 consecutive windows, upgrades one tier.
//
// Manual mode: user picks a fixed tier in Settings → Map Graphics.
//
// The system NEVER allows 3D/effects to make the map unusable on
// low-end devices — LOW tier is always available as a floor.

import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════════════
// GRAPHICS TIER ENUM
// ═══════════════════════════════════════════════════════════════════════

/// Rendering quality tier for the Family Map.
enum GraphicsTier {
  /// Full glow effects, smooth animations, premium shadows, high-quality tiles.
  high,

  /// Reduced glow, simpler shadows, standard tiles, static lines.
  balanced,

  /// No glow, flat pins, minimal shadows, no animations, basic tiles.
  /// Preserves pins, live locations, and relationship lines.
  low,
}

/// User preference: Auto lets the system adapt; the others are fixed.
enum GraphicsTierPreference {
  auto,
  high,
  balanced,
  low,
}

// ═══════════════════════════════════════════════════════════════════════
// TIER CONFIGURATION
// ═══════════════════════════════════════════════════════════════════════

/// Visual parameters for each tier. The map screen reads these to
/// decide glow opacity, shadow blur, animation enabled, tile URL, etc.
class TierConfig {
  const TierConfig({
    required this.tier,
    required this.glowOpacity,
    required this.pinShadowBlur,
    required this.pinShadowAlpha,
    required this.lineGlowEnabled,
    required this.animationsEnabled,
    required this.tileUrl,
    required this.maxTileZoom,
    required this.pulseAnimations,
  });

  final GraphicsTier tier;

  /// Opacity of the orange glow behind each pin (0.0–1.0).
  final double glowOpacity;

  /// Blur radius for the pin drop shadow.
  final double pinShadowBlur;

  /// Alpha for the pin drop shadow (0.0–1.0).
  final double pinShadowAlpha;

  /// Whether relationship lines have a glow layer.
  final bool lineGlowEnabled;

  /// Whether premium animations (pulse, shimmer) are enabled.
  final bool animationsEnabled;

  /// Tile server URL template.
  final String tileUrl;

  /// Maximum tile zoom level (higher = more detail but more data).
  final int maxTileZoom;

  /// Whether live pins pulse.
  final bool pulseAnimations;

  static const _high = TierConfig(
    tier: GraphicsTier.high,
    glowOpacity: 0.35,
    pinShadowBlur: 12,
    pinShadowAlpha: 0.5,
    lineGlowEnabled: true,
    animationsEnabled: true,
    tileUrl: 'https://cartodb-basemaps-a.global.ssl.fastly.net/dark_all/{z}/{x}/{y}.png',
    maxTileZoom: 20,
    pulseAnimations: true,
  );

  static const _balanced = TierConfig(
    tier: GraphicsTier.balanced,
    glowOpacity: 0.15,
    pinShadowBlur: 6,
    pinShadowAlpha: 0.3,
    lineGlowEnabled: false,
    animationsEnabled: true,
    tileUrl: 'https://cartodb-basemaps-a.global.ssl.fastly.net/dark_all/{z}/{x}/{y}.png',
    maxTileZoom: 16,
    pulseAnimations: false,
  );

  static const _low = TierConfig(
    tier: GraphicsTier.low,
    glowOpacity: 0.0,
    pinShadowBlur: 0,
    pinShadowAlpha: 0.0,
    lineGlowEnabled: false,
    animationsEnabled: false,
    tileUrl: 'https://cartodb-basemaps-a.global.ssl.fastly.net/dark_nolabels/{z}/{x}/{y}.png',
    maxTileZoom: 14,
    pulseAnimations: false,
  );

  static TierConfig forTier(GraphicsTier tier) {
    switch (tier) {
      case GraphicsTier.high:
        return _high;
      case GraphicsTier.balanced:
        return _balanced;
      case GraphicsTier.low:
        return _low;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// FPS MONITOR
// ═══════════════════════════════════════════════════════════════════════

/// Lightweight FPS monitor using Flutter's frame callback.
/// Tracks a rolling window of frame times and exposes the average FPS.
class FpsMonitor {
  FpsMonitor({this.windowSize = 180}) : _frameTimes = []; // ~3s at 60fps

  final int windowSize;
  final List<Duration> _frameTimes;
  DateTime? _lastFrameTime;
  TickerCallback? _callback;
  Ticker? _ticker;

  /// Start monitoring. Call from a State that has access to TickerProvider.
  void start(TickerProvider vsync, VoidCallback onFpsUpdated) {
    stop();
    _callback = (elapsed) {
      final now = DateTime.now();
      if (_lastFrameTime != null) {
        final delta = now.difference(_lastFrameTime!);
        _frameTimes.add(delta);
        if (_frameTimes.length > windowSize) {
          _frameTimes.removeAt(0);
        }
      }
      _lastFrameTime = now;
      onFpsUpdated();
    };
    _ticker = Ticker(_callback!);
    _ticker!.start();
  }

  /// Stop monitoring.
  void stop() {
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;
    _callback = null;
    _lastFrameTime = null;
    _frameTimes.clear();
  }

  /// Current average FPS over the rolling window. Returns 60 if no data.
  double get currentFps {
    if (_frameTimes.isEmpty) return 60.0;
    final avgMicro = _frameTimes
            .map((d) => d.inMicroseconds)
            .reduce((a, b) => a + b) /
        _frameTimes.length;
    if (avgMicro == 0) return 60.0;
    return 1000000.0 / avgMicro;
  }

  /// Whether the monitor has enough data to be reliable (at least 30 frames).
  bool get hasEnoughData => _frameTimes.length >= 30;
}

// ═══════════════════════════════════════════════════════════════════════
// GRAPHICS TIER STATE
// ═══════════════════════════════════════════════════════════════════════

class GraphicsTierState {
  const GraphicsTierState({
    required this.preference,
    required this.activeTier,
    required this.currentFps,
    required this.config,
  });

  /// User's chosen preference (Auto or a fixed tier).
  final GraphicsTierPreference preference;

  /// The tier currently active (either user's choice or auto-selected).
  final GraphicsTier activeTier;

  /// Latest FPS reading (60.0 if not monitoring).
  final double currentFps;

  /// The visual config for [activeTier].
  final TierConfig config;

  GraphicsTierState copyWith({
    GraphicsTierPreference? preference,
    GraphicsTier? activeTier,
    double? currentFps,
    TierConfig? config,
  }) =>
      GraphicsTierState(
        preference: preference ?? this.preference,
        activeTier: activeTier ?? this.activeTier,
        currentFps: currentFps ?? this.currentFps,
        config: config ?? this.config,
      );
}

// ═══════════════════════════════════════════════════════════════════════
// GRAPHICS TIER NOTIFIER
// ═══════════════════════════════════════════════════════════════════════

class GraphicsTierNotifier extends StateNotifier<GraphicsTierState> {
  GraphicsTierNotifier(this._ref) : super(_initialState);

  final Ref _ref;

  final FpsMonitor _fpsMonitor = FpsMonitor();
  int _lowFpsWindows = 0; // consecutive windows with FPS < 45
  int _highFpsWindows = 0; // consecutive windows with FPS > 55
  Timer? _evalTimer;

  static GraphicsTierState get _initialState => GraphicsTierState(
        preference: GraphicsTierPreference.auto,
        activeTier: GraphicsTier.high,
        currentFps: 60.0,
        config: TierConfig.forTier(GraphicsTier.high),
      );

  /// Start FPS monitoring + auto-tier evaluation. Call from the map
  /// screen's initState with the screen's TickerProvider.
  void startMonitoring(TickerProvider vsync) {
    if (state.preference != GraphicsTierPreference.auto) return;

    _fpsMonitor.start(vsync, _onFpsSample);

    // Evaluate FPS every 3 seconds.
    _evalTimer?.cancel();
    _evalTimer = Timer.periodic(const Duration(seconds: 3), (_) => _evaluateTier());
  }

  /// Stop monitoring. Call from dispose.
  void stopMonitoring() {
    _fpsMonitor.stop();
    _evalTimer?.cancel();
    _evalTimer = null;
  }

  void _onFpsSample() {
    if (!mounted) return;
    state = state.copyWith(currentFps: _fpsMonitor.currentFps);
  }

  void _evaluateTier() {
    if (!mounted || state.preference != GraphicsTierPreference.auto) return;
    if (!_fpsMonitor.hasEnoughData) return;

    final fps = _fpsMonitor.currentFps;

    if (fps < 45) {
      _lowFpsWindows++;
      _highFpsWindows = 0;
      // Sustained low FPS for 2 windows (~6s) → downgrade one tier
      if (_lowFpsWindows >= 2 && state.activeTier != GraphicsTier.low) {
        final newTier = _downgrade(state.activeTier);
        _applyTier(newTier);
        _lowFpsWindows = 0;
      }
    } else if (fps > 55) {
      _highFpsWindows++;
      _lowFpsWindows = 0;
      // Sustained high FPS for 5 windows (~15s) → upgrade one tier
      if (_highFpsWindows >= 5 && state.activeTier != GraphicsTier.high) {
        final newTier = _upgrade(state.activeTier);
        _applyTier(newTier);
        _highFpsWindows = 0;
      }
    } else {
      // FPS in the 45-55 "balanced" zone — reset counters
      _lowFpsWindows = 0;
      _highFpsWindows = 0;
    }
  }

  GraphicsTier _downgrade(GraphicsTier current) {
    switch (current) {
      case GraphicsTier.high:
        return GraphicsTier.balanced;
      case GraphicsTier.balanced:
        return GraphicsTier.low;
      case GraphicsTier.low:
        return GraphicsTier.low;
    }
  }

  GraphicsTier _upgrade(GraphicsTier current) {
    switch (current) {
      case GraphicsTier.high:
        return GraphicsTier.high;
      case GraphicsTier.balanced:
        return GraphicsTier.high;
      case GraphicsTier.low:
        return GraphicsTier.balanced;
    }
  }

  void _applyTier(GraphicsTier tier) {
    if (!mounted) return;
    state = state.copyWith(
      activeTier: tier,
      config: TierConfig.forTier(tier),
    );
    debugPrint('🎮 Graphics tier → $tier (FPS: ${state.currentFps.toStringAsFixed(1)})');
  }

  /// Set the user's graphics preference. If set to a fixed tier, the
  /// FPS monitor is stopped and that tier is used immediately.
  Future<void> setPreference(GraphicsTierPreference pref) async {
    final tier = switch (pref) {
      GraphicsTierPreference.auto => GraphicsTier.high, // auto starts high and adapts down
      GraphicsTierPreference.high => GraphicsTier.high,
      GraphicsTierPreference.balanced => GraphicsTier.balanced,
      GraphicsTierPreference.low => GraphicsTier.low,
    };

    state = GraphicsTierState(
      preference: pref,
      activeTier: tier,
      currentFps: state.currentFps,
      config: TierConfig.forTier(tier),
    );

    // Persist preference
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('map_graphics_preference', pref.name);
    } catch (e) {
      debugPrint('⚠️ Failed to persist graphics preference: $e');
    }

    if (pref != GraphicsTierPreference.auto) {
      stopMonitoring();
    }
  }

  /// Load persisted preference on app start.
  Future<void> loadPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString('map_graphics_preference');
      if (name != null) {
        final pref = GraphicsTierPreference.values.firstWhere(
          (p) => p.name == name,
          orElse: () => GraphicsTierPreference.auto,
        );
        await setPreference(pref);
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load graphics preference: $e');
    }
  }

  @override
  void dispose() {
    stopMonitoring();
    super.dispose();
  }
}

// ═══════════════════════════════════════════════════════════════════════
// PROVIDER
// ═══════════════════════════════════════════════════════════════════════

final graphicsTierProvider =
    StateNotifierProvider.autoDispose<GraphicsTierNotifier, GraphicsTierState>(
  (ref) => GraphicsTierNotifier(ref),
);

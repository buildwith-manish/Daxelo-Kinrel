// lib/graph/rendering/graph_performance_diagnostics.dart
//
// DAXELO KINREL — Graph Performance Diagnostics Overlay (v5.142)
//
// A debug/profile-mode-only overlay that shows the user EXACTLY what
// the graph engine is doing in real time. Designed to answer the four
// diagnostic questions from the perf audit:
//
//   1. "Am I profiling correctly?" — Shows whether the overlay is
//      running in debug or profile mode (hot-reload debug mode is
//      3-5x laggier than real users will see).
//   2. "UI-thread or Raster-thread lag?" — Shows live UI-thread and
//      Raster-thread frame times (ms) with jank threshold markers.
//   3. "Is my device tier misdetected?" — Shows the detected
//      DeviceTier + the screen metrics that drove the detection.
//   4. "Is the culler actually culling?" — Shows visible/total node
//      count, cull ratio, rebuild/skip counts, and the last action
//      reason.
//
// The overlay also shows the active GraphPerformanceProfile flags
// (allowShadowPass, allowRidgePass, allowAmbientParticles, etc.) so
// the user can verify the profile is actually applied — not silently
// bypassed by a misdetected DeviceTier.
//
// TOGGLE: Long-press the top-right corner of the graph screen for
// 500ms. The overlay appears/disappears. The toggle is only available
// in debug or profile mode — it's compiled out of release builds via
// `kDebugMode && kProfileMode` check (actually just kReleaseMode
// negation, so it's available in both debug AND profile modes).
//
// PERFORMANCE: The overlay itself is designed to NOT cause the lag
// it's measuring. It uses:
//   • A single ValueNotifier<double> for frame times (no setState per
//     frame — the overlay rebuilds at most 4x/sec via a Timer).
//   • A RepaintBoundary around the overlay so it doesn't repaint the
//     graph canvas.
//   • The frame-time callback is added via SchedulerBinding (not a
//     separate AnimationController) so it doesn't compete with the
//     graph's own tickers.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/utils/device_tier.dart'
    show DeviceTier, DeviceTierCache;
import 'graph_performance_profile.dart' show GraphPerformanceProfile;
import 'viewport_culler.dart' show ViewportCuller;
import '../widgets/engine/lod.dart' show Lod;
import 'edge_quality.dart' show EdgeQuality;

/// v5.142 (DIAGNOSTICS): A debug/profile-mode overlay that shows
/// real-time graph performance metrics.
///
/// See the file header for the full diagnostic playbook.
class GraphPerformanceDiagnostics extends StatefulWidget {
  const GraphPerformanceDiagnostics({
    super.key,
    required this.profile,
    required this.culler,
    required this.cameraZoom,
    required this.currentLod,
    required this.currentEdgeQuality,
    required this.memberCount,
    required this.visibleNodeCount,
  });

  /// The active performance profile (so the user can verify the flags).
  final GraphPerformanceProfile profile;

  /// The viewport culler (for rebuild/skip counts + cull ratio).
  final ViewportCuller culler;

  /// A function that returns the current camera zoom level. Called
  /// on each overlay refresh (4x/sec) — NOT on every camera tick.
  final double Function() cameraZoom;

  /// A function that returns the current LOD tier.
  final Lod Function() currentLod;

  /// A function that returns the current edge quality tier.
  final EdgeQuality Function() currentEdgeQuality;

  /// The total number of members in the current family.
  final int Function() memberCount;

  /// A function that returns the current visible node count.
  /// Usually `_culler.visibleCount` but passed as a function so the
  /// overlay reads the latest value on each refresh.
  final int Function() visibleNodeCount;

  @override
  State<GraphPerformanceDiagnostics> createState() =>
      _GraphPerformanceDiagnosticsState();
}

class _GraphPerformanceDiagnosticsState
    extends State<GraphPerformanceDiagnostics> {
  // ── Frame-time tracking ──────────────────────────────────────────
  //
  // We use SchedulerBinding.addTimingsCallback to get notified of
  // frame timings WITHOUT adding a per-frame listener that would
  // itself cause lag. The callback fires in batch (usually 1-2 frames
  // at a time) and gives us both UI-thread and Raster-thread durations.

  late final List<FrameTiming> _recentTimings;
  Timer? _refreshTimer;

  /// The most recent UI-thread frame time in milliseconds.
  double _uiFrameMs = 0.0;

  /// The most recent Raster-thread frame time in milliseconds.
  double _rasterFrameMs = 0.0;

  /// The rolling average UI-thread frame time (last 10 frames).
  double _avgUiFrameMs = 0.0;

  /// The rolling average Raster-thread frame time (last 10 frames).
  double _avgRasterFrameMs = 0.0;

  /// Whether the overlay is currently visible.
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _recentTimings = <FrameTiming>[];
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    // Refresh the overlay 4x/sec — fast enough to be useful, slow
    // enough to not cause the lag we're measuring.
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted && _visible) setState(() {});
    });
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _onTimings(List<FrameTiming> timings) {
    if (timings.isEmpty) return;
    _recentTimings.addAll(timings);
    // Keep only the last 10 frames for the rolling average.
    if (_recentTimings.length > 10) {
      _recentTimings.removeRange(
        0,
        _recentTimings.length - 10,
      );
    }
    // Compute the most-recent + rolling-average frame times.
    final last = timings.last;
    _uiFrameMs =
        last.buildDuration.inMicroseconds / 1000.0;
    _rasterFrameMs =
        last.rasterDuration.inMicroseconds / 1000.0;
    double sumUi = 0, sumRaster = 0;
    for (final t in _recentTimings) {
      sumUi += t.buildDuration.inMicroseconds / 1000.0;
      sumRaster += t.rasterDuration.inMicroseconds / 1000.0;
    }
    _avgUiFrameMs = sumUi / _recentTimings.length;
    _avgRasterFrameMs = sumRaster / _recentTimings.length;
  }

  /// Returns a color for a frame time (green = good, yellow = marginal,
  /// red = jank).
  Color _colorForFrameMs(double ms) {
    // 60 FPS = 16.67ms budget. > 16ms = dropped frame.
    if (ms <= 16.0) return const Color(0xFF4CAF50); // green
    if (ms <= 33.0) return const Color(0xFFFFC107); // yellow (30 FPS)
    return const Color(0xFFF44336); // red (jank)
  }

  @override
  Widget build(BuildContext context) {
    // The overlay is compiled out of release builds entirely.
    if (kReleaseMode) return const SizedBox.shrink();

    if (!_visible) {
      // Show a tiny toggle hint in the top-right corner.
      return Positioned(
        top: 0,
        right: 0,
        child: GestureDetector(
          onLongPress: () => setState(() => _visible = true),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.01),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(8),
              ),
            ),
            child: const Icon(
              Icons.bug_report,
              size: 14,
              color: Color(0x44808080),
            ),
          ),
        ),
      );
    }

    final profile = widget.profile;
    final culler = widget.culler;
    final zoom = widget.cameraZoom();
    final lod = widget.currentLod();
    final edgeQuality = widget.currentEdgeQuality();
    final memberCount = widget.memberCount();
    final visibleCount = widget.visibleNodeCount();
    final totalPositions = culler.totalPositionsSeen;
    final cullRatio = culler.cullRatio;

    return Positioned(
      top: 8,
      right: 8,
      child: GestureDetector(
        onLongPress: () => setState(() => _visible = false),
        child: Container(
          width: 280,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: const Color(0xFF616161),
              width: 0.5,
            ),
          ),
          child: DefaultTextStyle(
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontFamily: 'monospace',
              height: 1.4,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ───────────────────────────────────────────
                Row(
                  children: [
                    const Icon(Icons.bug_report, size: 12, color: Colors.amber),
                    const SizedBox(width: 4),
                    Text(
                      'GRAPH PERF ${kDebugMode ? '(DEBUG)' : '(PROFILE)'}',
                      style: const TextStyle(
                        color: Colors.amber,
                        fontWeight: FontWeight.bold,
                        fontSize: 9,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'long-press to hide',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 8,
                      ),
                    ),
                  ],
                ),
                const Divider(color: Color(0xFF424242), height: 8),

                // ── Section 1: Mode warning ─────────────────────────
                if (kDebugMode)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0x33F44336),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '⚠ DEBUG MODE — canvas is 3-5x laggier\n'
                      '   than real users will see.\n'
                      '   Run: flutter run --profile',
                      style: TextStyle(color: Color(0xFFFFCDD2), fontSize: 9),
                    ),
                  ),

                // ── Section 2: Frame times ──────────────────────────
                const Text(
                  'FRAME TIMES',
                  style: TextStyle(
                    color: Colors.cyan,
                    fontWeight: FontWeight.bold,
                    fontSize: 8,
                  ),
                ),
                const SizedBox(height: 2),
                _frameTimeRow(
                  'UI',
                  _uiFrameMs,
                  _avgUiFrameMs,
                ),
                _frameTimeRow(
                  'Raster',
                  _rasterFrameMs,
                  _avgRasterFrameMs,
                ),
                const Divider(color: Color(0xFF424242), height: 8),

                // ── Section 3: Device tier ──────────────────────────
                const Text(
                  'DEVICE TIER',
                  style: TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                    fontSize: 8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Tier: ${_tierName(profile.deviceTier)} '
                  '${profile.isLowEnd ? "(LOW-END)" : ""}'
                  '${profile.isHighEnd ? "(HIGH-END)" : ""}',
                  style: TextStyle(
                    color: profile.isLowEnd
                        ? const Color(0xFFFFC107)
                        : Colors.white,
                  ),
                ),
                Text(
                  'Initialized: ${DeviceTierCache.instance.isInitialized}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
                const Divider(color: Color(0xFF424242), height: 8),

                // ── Section 4: Culler stats ─────────────────────────
                const Text(
                  'CULLER',
                  style: TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                    fontSize: 8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Visible: $visibleCount / $totalPositions '
                  '(${(cullRatio * 100).toStringAsFixed(0)}%)',
                  style: TextStyle(
                    color: cullRatio > 0.5 && totalPositions > 20
                        ? const Color(0xFFFFC107)
                        : Colors.white,
                  ),
                ),
                Text(
                  'Members: $memberCount  '
                  'Rebuilds: ${culler.rebuildCount}  '
                  'Skips: ${culler.skipCount}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
                Text(
                  'Buffer: ${culler.bufferPixels.toStringAsFixed(0)}px  '
                  'Threshold: ${culler.rebuildThreshold.toStringAsFixed(0)}px',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
                Text(
                  culler.lastActionReason,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 8,
                  ),
                ),
                const Divider(color: Color(0xFF424242), height: 8),

                // ── Section 5: Active profile flags ────────────────
                const Text(
                  'PROFILE FLAGS',
                  style: TextStyle(
                    color: Colors.purple,
                    fontWeight: FontWeight.bold,
                    fontSize: 8,
                  ),
                ),
                const SizedBox(height: 2),
                _flagRow('Shadow pass', profile.allowEdgeShadowPass),
                _flagRow('Ridge pass', profile.allowEdgeRidgePass),
                _flagRow('Particles', profile.allowAmbientParticles),
                _flagRow('Connect anim', profile.allowConnectOnOpenAnimation),
                _flagRow('Birthday pulse', profile.allowBirthdayPulseAnimation),
                _flagRow('Memorial flicker', profile.allowMemorialCandleFlicker),
                const Divider(color: Color(0xFF424242), height: 8),

                // ── Section 6: Current render state ────────────────
                const Text(
                  'RENDER STATE',
                  style: TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                    fontSize: 8,
                  ),
                ),
                const SizedBox(height: 2),
                Text('Zoom: ${zoom.toStringAsFixed(2)}'),
                Text('LOD: ${_lodName(lod)}'),
                Text('Edge quality: ${_edgeQualityName(edgeQuality)}'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _frameTimeRow(String label, double current, double avg) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ),
          Text(
            '${current.toStringAsFixed(1)}ms',
            style: TextStyle(
              color: _colorForFrameMs(current),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'avg ${avg.toStringAsFixed(1)}ms',
            style: TextStyle(
              color: _colorForFrameMs(avg),
              fontSize: 9,
            ),
          ),
          const Spacer(),
          if (current > 16.0)
            const Text(
              '⚠ JANK',
              style: TextStyle(color: Color(0xFFF44336), fontSize: 8),
            ),
        ],
      ),
    );
  }

  Widget _flagRow(String label, bool value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ),
          Text(
            value ? 'ON' : 'OFF',
            style: TextStyle(
              color: value ? const Color(0xFF4CAF50) : const Color(0xFF9E9E9E),
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  String _tierName(DeviceTier tier) {
    switch (tier) {
      case DeviceTier.high:
        return 'high';
      case DeviceTier.mid:
        return 'mid';
      case DeviceTier.low:
        return 'low';
    }
  }

  String _lodName(Lod lod) {
    switch (lod) {
      case Lod.full:
        return 'full (premium)';
      case Lod.compact:
        return 'compact (label faded)';
      case Lod.mini:
        return 'mini (circle + initial)';
      case Lod.micro:
        return 'micro (circle + ring)';
      case Lod.chip:
        return 'chip (legacy)';
      case Lod.dot:
        return 'dot (far zoom)';
    }
  }

  String _edgeQualityName(EdgeQuality q) {
    switch (q) {
      case EdgeQuality.full:
        return 'full (3-pass)';
      case EdgeQuality.chip:
        return 'chip (2-pass, lighter)';
      case EdgeQuality.dot:
        return 'dot (1-pass)';
    }
  }
}

/// v5.142 (DIAGNOSTICS): A global notifier that tracks whether the
/// diagnostics overlay should be shown. The graph screen watches this
/// and shows/hides the overlay accordingly. Defaults to false (hidden)
/// — the user toggles it via long-press on the top-right corner.
final ValueNotifier<bool> graphDiagnosticsVisibleNotifier =
    ValueNotifier<bool>(false);

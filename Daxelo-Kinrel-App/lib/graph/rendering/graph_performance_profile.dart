// lib/graph/rendering/graph_performance_profile.dart
//
// DAXELO KINREL — Graph Performance Profile (v5.141)
//
// Centralizes ALL tier-aware performance decisions for the graph engine
// so that low-end, mid, and high-end devices each get an experience
// tuned for their capability. Previously the graph applied the SAME
// heavy rendering pipeline (Lod.full at every zoom, 3-pass physical
// edge threads, ambient particles, connect-on-open animation) to every
// device — which is why low-end devices with 2–4 GB RAM stuttered
// even with 30 visible nodes.
//
// The profile is computed ONCE at graph-screen mount from
// [DeviceTierCache] and remains constant for the screen's lifetime.
// All tier-aware code paths read from a single instance of this
// profile, so the decisions are consistent across the canvas, edge
// layer, node layer, particle layer, and camera culler.
//
// DESIGN PRINCIPLE: Graceful degradation, never broken visuals.
//   • Low-end devices still get a beautiful graph — just with fewer
//     simultaneous effects. Nodes remain recognizable (initials +
//     names + colors), edges remain visible (single-pass body), the
//     anchor still has its gold border + larger size.
//   • Mid devices get the full premium experience at near zoom but
//     degrade to compact (faded labels) when zoomed out, instead of
//     forcing Lod.full everywhere.
//   • High-end devices keep the existing v5.140 behavior (Lod.full
//     always, full 3-pass edges, ambient particles, connect-on-open
//     animation).
//
// This is a PURE data class — no Riverpod. The graph screen constructs
// one instance and passes it down. Tests can construct profiles
// directly without a device.

import 'package:flutter/foundation.dart' show immutable;

import '../widgets/engine/lod.dart' show Lod;
import 'edge_quality.dart' show EdgeQuality;
import '../../core/utils/device_tier.dart' show DeviceTier, DeviceTierCache;

/// A frozen set of performance decisions for the graph engine.
///
/// Construct via [GraphPerformanceProfile.forCurrentDevice] at graph
/// screen mount. All fields are `final` — the profile does not change
/// for the screen's lifetime.
@immutable
class GraphPerformanceProfile {
  const GraphPerformanceProfile({
    required this.deviceTier,
    required this.allowAmbientParticles,
    required this.allowConnectOnOpenAnimation,
    required this.allowEdgeShadowPass,
    required this.allowEdgeRidgePass,
    required this.allowBirthdayPulseAnimation,
    required this.allowMemorialCandleFlicker,
    required this.cullerRebuildThresholdPixels,
    required this.cullerBufferPixels,
    required this.lodForZoom,
    required this.edgeQualityForLod,
    required this.maxImageCacheBytes,
    required this.maxVisibleNodesBeforeForceMini,
  });

  /// The device tier this profile was built for.
  final DeviceTier deviceTier;

  // ── Decorative animation toggles ────────────────────────────────

  /// Whether the ambient gold-mote particle layer should be built at
  /// all. On low-end devices this is false — the motes are purely
  /// decorative and cost ~25 drawCircle calls per frame + a 6-second
  /// repeating AnimationController.
  final bool allowAmbientParticles;

  /// Whether the connect-on-open edge draw-in animation should play.
  /// On low-end devices this is false — the graph instead calls
  /// `revealAll()` so all edges appear instantly at full alpha. The
  /// animation previously caused 1–3s of degraded pan/zoom on first
  /// load because each tick repainted the edge layer.
  final bool allowConnectOnOpenAnimation;

  /// Whether the birthday glow ring should pulse (alpha 0.3..0.6).
  /// On low-end devices this is false — the ring is drawn at a static
  /// 0.45 alpha (the mid-pulse value). The ring itself is still
  /// visible, just not animated.
  final bool allowBirthdayPulseAnimation;

  /// Whether the memorial candle for deceased nodes should flicker.
  /// On low-end devices this is false — the candle is drawn at a
  /// static 0.75 alpha. The candle itself is still visible.
  final bool allowMemorialCandleFlicker;

  // ── Edge rendering toggles ──────────────────────────────────────

  /// Whether the edge contact-shadow pass (PASS 1 of the 3-pass
  /// physical thread) should be drawn. On low-end devices this is
  /// false — the shadow uses MaskFilter.blur which is the single most
  /// expensive paint operation. Dropping it halves the edge paint cost.
  final bool allowEdgeShadowPass;

  /// Whether the edge directional light ridge (PASS 3) should be
  /// drawn. On low-end devices this is false — the ridge is a subtle
  /// top-left highlight that's barely visible at phone scale anyway.
  final bool allowEdgeRidgePass;

  // ── Culler throttling ───────────────────────────────────────────

  /// The minimum pan/zoom displacement (in graph-space pixels) that
  /// triggers a culler rebuild. Higher = fewer rebuilds during pan =
  /// smoother on low-end devices, at the cost of nodes popping in
  /// slightly later when entering the viewport.
  ///
  /// High-end: 50px (current default — snappy).
  /// Mid: 75px.
  /// Low-end: 120px (almost half the rebuild frequency).
  final double cullerRebuildThresholdPixels;

  /// The buffer zone around the viewport (in graph-space pixels).
  /// Nodes inside viewport + buffer are built. Lower = fewer nodes
  /// built = less memory + faster rebuilds, at the cost of nodes
  /// popping in at the viewport edge.
  ///
  /// High-end: 200px (current default — generous).
  /// Mid: 150px.
  /// Low-end: 100px.
  final double cullerBufferPixels;

  // ── LOD + edge quality ──────────────────────────────────────────

  /// Function that returns the LOD tier for a given zoom level. On
  /// high-end devices this always returns [Lod.full] (per the user's
  /// v5.112 request). On mid devices it returns [Lod.compact] for
  /// zoomed-out states (still premium, just faded labels). On low-end
  /// devices it returns [Lod.compact] for moderate zoom-out and
  /// [Lod.mini] (circle + initial) for extreme zoom-out.
  final Lod Function(double zoom) lodForZoom;

  /// Function that returns the edge quality for a given LOD tier.
  /// On low-end devices, even at [Lod.full] the edge quality is
  /// downgraded to [EdgeQuality.chip] (lighter shadow sigma, reduced
  /// ridge alpha) to reduce per-edge paint cost.
  final EdgeQuality Function(Lod lod) edgeQualityForLod;

  // ── Memory ──────────────────────────────────────────────────────

  /// Maximum in-memory image cache size in bytes. The graph loads
  /// one avatar per visible node (up to ~100 at once on a large
  /// family). Each decoded avatar is ~50–200 KB. On low-end devices
  /// with 2–4 GB RAM, a 100 MB cache competes with the OS + other
  /// apps and triggers GC pressure that stutters the UI thread.
  ///
  /// High-end: 100 MB (current default).
  /// Mid: 60 MB.
  /// Low-end: 40 MB.
  final int maxImageCacheBytes;

  /// When the visible node count exceeds this threshold, the graph
  /// FORCES [Lod.mini] (single-painter circle + initial) regardless
  /// of zoom. This prevents the culler from juggling 100+ premium
  /// GraphNode widgets (each with 5 AnimationControllers) on devices
  /// that can't handle it.
  ///
  /// High-end: null (never force — the culler + RepaintBoundary
  ///           handle large families fine).
  /// Mid: 120 (force mini above 120 visible nodes).
  /// Low-end: 60 (force mini above 60 visible nodes — a typical
  ///         low-end device can handle ~60 premium nodes comfortably).
  final int? maxVisibleNodesBeforeForceMini;

  // ── Convenience predicates ──────────────────────────────────────

  /// True when this profile is for a low-end device.
  bool get isLowEnd => deviceTier == DeviceTier.low;

  /// True when this profile is for a mid-range device.
  bool get isMidRange => deviceTier == DeviceTier.mid;

  /// True when this profile is for a high-end device.
  bool get isHighEnd => deviceTier == DeviceTier.high;

  // ── Factory ─────────────────────────────────────────────────────

  /// Builds a profile for the current device using [DeviceTierCache].
  /// Call this ONCE at graph screen mount and pass the result down.
  /// Falls back to mid-range if the device tier hasn't been
  /// initialized yet (e.g. web before first frame).
  factory GraphPerformanceProfile.forCurrentDevice() {
    return GraphPerformanceProfile._forTier(
      DeviceTierCache.instance.tier,
    );
  }

  /// Internal constructor that maps a [DeviceTier] to a profile.
  factory GraphPerformanceProfile._forTier(DeviceTier tier) {
    switch (tier) {
      case DeviceTier.high:
        return GraphPerformanceProfile._highEnd;
      case DeviceTier.mid:
        return GraphPerformanceProfile._midRange;
      case DeviceTier.low:
        return GraphPerformanceProfile._lowEnd;
    }
  }

  // ── Pre-built profiles ──────────────────────────────────────────

  /// High-end profile — full premium experience, no degradation.
  /// Matches the v5.140 behavior on 12 GB RAM devices.
  static const GraphPerformanceProfile _highEnd = GraphPerformanceProfile(
    deviceTier: DeviceTier.high,
    allowAmbientParticles: true,
    allowConnectOnOpenAnimation: true,
    allowEdgeShadowPass: true,
    allowEdgeRidgePass: true,
    allowBirthdayPulseAnimation: true,
    allowMemorialCandleFlicker: true,
    cullerRebuildThresholdPixels: 50.0,
    cullerBufferPixels: 200.0,
    lodForZoom: _alwaysFull,
    edgeQualityForLod: _fullQualityForFullLod,
    maxImageCacheBytes: 100 * 1024 * 1024, // 100 MB
    maxVisibleNodesBeforeForceMini: null, // never force
  );

  /// Mid-range profile — premium at near zoom, compact at far zoom.
  static const GraphPerformanceProfile _midRange = GraphPerformanceProfile(
    deviceTier: DeviceTier.mid,
    allowAmbientParticles: true,
    allowConnectOnOpenAnimation: true,
    allowEdgeShadowPass: true,
    allowEdgeRidgePass: true,
    allowBirthdayPulseAnimation: true,
    allowMemorialCandleFlicker: true,
    cullerRebuildThresholdPixels: 75.0,
    cullerBufferPixels: 150.0,
    // Mid: degrade to compact when zoomed out (< 0.50). Compact is
    // still a full GraphNode — just with the relation label faded.
    // The user explicitly said "no dots" — compact respects that.
    lodForZoom: _midRangeLod,
    edgeQualityForLod: _fullQualityForFullLod,
    maxImageCacheBytes: 60 * 1024 * 1024, // 60 MB
    maxVisibleNodesBeforeForceMini: 120,
  );

  /// Low-end profile — graceful degradation, still beautiful.
  static const GraphPerformanceProfile _lowEnd = GraphPerformanceProfile(
    deviceTier: DeviceTier.low,
    // Low-end: disable decorative particles entirely. The anchor node
    // still has its gold border + larger size + always-visible "You"
    // label, so it remains visually distinct without the mote cloud.
    allowAmbientParticles: false,
    // Low-end: skip the 1–3s connect-on-open animation. Edges appear
    // instantly at full alpha via revealAll(). This eliminates the
    // worst-case pan/zoom degradation window on first load.
    allowConnectOnOpenAnimation: false,
    // Low-end: drop the edge shadow pass (MaskFilter.blur is the
    // most expensive paint op). The edge body + ridge still convey
    // the physical-thread look, just without the soft shadow.
    allowEdgeShadowPass: false,
    // Low-end: drop the ridge pass too. Two passes per edge instead
    // of three — 33% less edge paint work.
    allowEdgeRidgePass: false,
    // Low-end: static birthday glow (0.45 alpha, no pulse). The ring
    // is still visible, just not animated.
    allowBirthdayPulseAnimation: false,
    // Low-end: static memorial candle (0.75 alpha, no flicker).
    allowMemorialCandleFlicker: false,
    // Low-end: 120px rebuild threshold (vs 50px on high-end). Almost
    // half the rebuild frequency during pan = much smoother drag.
    cullerRebuildThresholdPixels: 120.0,
    // Low-end: 100px buffer (vs 200px on high-end). Fewer nodes built
    // = less memory + faster rebuilds. Nodes pop in slightly later at
    // the viewport edge but the buffer is still generous enough that
    // fast pans don't show empty space.
    cullerBufferPixels: 100.0,
    // Low-end: degrade to compact at < 0.65 zoom, mini at < 0.30.
    // Compact is still a full GraphNode (label faded). Mini is a
    // circle + initial — still recognizable, NOT anonymous dots.
    lodForZoom: _lowEndLod,
    // Low-end: even at Lod.full, use chip-quality edges (lighter
    // shadow sigma, reduced ridge). This compounds with the
    // allowEdgeShadowPass / allowEdgeRidgePass flags above.
    edgeQualityForLod: _chipQualityForAllLods,
    // Low-end: 40 MB image cache (vs 100 MB on high-end). Prevents
    // GC pressure on 2–4 GB RAM devices.
    maxImageCacheBytes: 40 * 1024 * 1024, // 40 MB
    // Low-end: force mini when > 60 visible nodes. 60 premium
    // GraphNodes is the comfortable ceiling for a low-end device;
    // beyond that the culler + widget tree become the bottleneck.
    maxVisibleNodesBeforeForceMini: 60,
  );

  // ── LOD functions ───────────────────────────────────────────────

  /// High-end: always Lod.full (per user v5.112 request).
  static Lod _alwaysFull(double zoom) => Lod.full;

  /// Mid-range: Lod.full for zoom >= 0.70, Lod.compact for 0.45–0.70,
  /// Lod.mini (single CustomPaint) below 0.45.
  ///
  /// v5.149 (TIER 3G): Mid-range now drops to Lod.mini (single-painter
  /// circle + initial) at < 0.45 zoom instead of staying at compact.
  /// This gives mid-range devices the single-painter benefit (one
  /// CustomPaint call for ALL nodes vs one GraphNode widget per node)
  /// when zoomed out — the exact scenario where pan/zoom is most
  /// expensive because more nodes are visible.
  ///
  /// The trade-off: at < 0.45 zoom, nodes lose their avatars + full
  /// names + decorations and show as circles + initials. But at that
  /// zoom level, avatars are too small to see anyway (~15px), so the
  /// visual loss is minimal. The perf gain is significant: 1 paint
  /// call vs 22 widget builds + 22 paint calls.
  static Lod _midRangeLod(double zoom) {
    if (zoom >= 0.70) return Lod.full;
    if (zoom >= 0.45) return Lod.compact;
    return Lod.mini;
  }

  /// Low-end: Lod.full for zoom >= 0.80, Lod.compact for 0.45–0.80,
  /// Lod.mini (single CustomPaint) below 0.45.
  ///
  /// v5.149 (TIER 3G): Low-end now uses Lod.full only at near-zoom
  /// (>= 0.80, was 0.65) and drops to mini sooner (at 0.45, was 0.30).
  /// This means low-end devices spend most of their zoom range in the
  /// single-painter tier, getting near-WhatsApp smoothness at the cost
  /// of avatars (which are too small to see at those zoom levels
  /// anyway).
  static Lod _lowEndLod(double zoom) {
    if (zoom >= 0.80) return Lod.full;
    if (zoom >= 0.45) return Lod.compact;
    return Lod.mini;
  }

  // ── Edge quality functions ──────────────────────────────────────

  /// High/mid: full edge quality at Lod.full/compact, chip at mini,
  /// dot at dot.
  static EdgeQuality _fullQualityForFullLod(Lod lod) {
    switch (lod) {
      case Lod.full:
      case Lod.compact:
        return EdgeQuality.full;
      case Lod.mini:
      case Lod.micro:
      case Lod.chip:
        return EdgeQuality.chip;
      case Lod.dot:
        return EdgeQuality.dot;
    }
  }

  /// Low-end: chip edge quality at every LOD tier. Chip has lighter
  /// shadow sigma (1.6 vs 2.8) and reduced ridge alpha (0.14 vs 0.26).
  /// Combined with allowEdgeShadowPass=false and allowEdgeRidgePass=false,
  /// this means low-end edges are a single body pass — the cheapest
  /// possible visible edge.
  static EdgeQuality _chipQualityForAllLods(Lod lod) {
    switch (lod) {
      case Lod.full:
      case Lod.compact:
      case Lod.mini:
      case Lod.micro:
      case Lod.chip:
        return EdgeQuality.chip;
      case Lod.dot:
        return EdgeQuality.dot;
    }
  }
}

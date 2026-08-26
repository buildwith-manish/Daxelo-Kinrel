// lib/graph/rendering/lod_render_metrics.dart
//
// DAXELO KINREL — LOD Render Metrics (v97 + v5.111)
//
// Centralizes ALL zoom-aware sizing calculations so that culling,
// chip rendering, overview painting, hit testing, and edge rendering
// all use the SAME formulas. No duplication of zoom math.
//
// The camera Transform scales the entire graph Stack by `zoom`.
// A value of X in graph space appears as X*zoom on screen.
// To achieve a desired SCREEN-SPACE size S, the graph-space value
// must be S / zoom.
//
// v5.111: Added 'compact', 'mini', 'micro' tiers for the new 5-tier
// semantic zoom system. MINI and MICRO use SCREEN-SPACE CLAMPED sizes
// (they do NOT shrink as zoom decreases — the graph-space value grows
// to compensate). This is the KEY change that prevents nodes from
// collapsing into anonymous colored dots.

import 'dart:ui' show Size;

/// Centralized render metrics for a given LOD tier + zoom level.
///
/// All sizes are in GRAPH SPACE unless prefixed with `screen`.
/// The parent camera Transform multiplies graph-space values by
/// `zoom` to produce screen-space values.
class LodRenderMetrics {
  const LodRenderMetrics({
    required this.zoom,
    required this.tier,
    required this.cullSize,
    required this.graphNodeRadius,
    required this.graphStrokeWidth,
    required this.graphHitRadius,
    required this.screenNodeRadius,
    required this.screenStrokeWidth,
  });

  final double zoom;
  final String tier;
  final Size cullSize;
  final double graphNodeRadius;
  final double graphStrokeWidth;
  final double graphHitRadius;
  final double screenNodeRadius;
  final double screenStrokeWidth;

  @override
  String toString() =>
      'LodRenderMetrics(zoom=$zoom, tier=$tier, '
      'screenNodeR=$screenNodeRadius, screenStroke=$screenStrokeWidth, '
      'cullSize=$cullSize)';
}

/// Computes render metrics for the given LOD tier + zoom.
///
/// v5.111: Added 'compact', 'mini', 'micro' tiers.
///
/// Tier → screen-space target sizes:
///   • full     — 72dp graph-space (geometric scaling, no clamp)
///   • compact  — 72dp graph-space (geometric scaling, no clamp)
///   • mini     — 22px screen-space (CLAMPED — graph-space = 22/zoom)
///   • micro    — 16px screen-space (CLAMPED — graph-space = 16/zoom)
///   • overview — 14px normal / 20px emphasised screen-space (CLAMPED)
///   • chip     — 8px screen-space (legacy — kept for backward compat)
LodRenderMetrics computeLodMetrics({
  required String tier,
  required double zoom,
}) {
  // Guard against malformed zoom (NaN, zero, negative).
  final safeZoom = (zoom > 0.001 && zoom.isFinite) ? zoom : 1.0;

  switch (tier) {
    case 'full':
      // FULL LOD: full GraphNode widgets (72dp diameter).
      return LodRenderMetrics(
        zoom: safeZoom,
        tier: 'full',
        cullSize: const Size(140, 176),
        graphNodeRadius: 36.0, // 72 / 2
        graphStrokeWidth: 2.5,
        graphHitRadius: 44.0,
        screenNodeRadius: 36.0 * safeZoom,
        screenStrokeWidth: 2.5 * safeZoom,
      );

    case 'compact':
      // COMPACT LOD (v5.111): same 72dp GraphNode widget as FULL, but
      // the relation label is faded out (driven by the existing
      // relationLabelOpacityFor function — at zoom 0.50-0.85 it's
      // already faded to 0). All sizing is IDENTICAL to FULL so the
      // transition NEAR↔COMPACT is invisible (no visual jump).
      return LodRenderMetrics(
        zoom: safeZoom,
        tier: 'compact',
        cullSize: const Size(140, 176),
        graphNodeRadius: 36.0,
        graphStrokeWidth: 2.5,
        graphHitRadius: 44.0,
        screenNodeRadius: 36.0 * safeZoom,
        screenStrokeWidth: 2.5 * safeZoom,
      );

    case 'mini':
      // MINI LOD (v5.111): circle + border + initial letter.
      // SCREEN-SPACE CLAMPED — node does NOT shrink as zoom decreases.
      //   normal radius: 11px (22px diameter)
      //   emphasised radius: 15px (30px diameter)
      //   border stroke: 1.5px screen-space
      //   hit radius: 22px screen-space (generous tap target)
      const screenNormalR = 11.0;
      const screenEmphasisR = 15.0;
      const screenStrokeMin = 1.5;
      const screenHitRadius = 22.0;
      final graphNormalR = screenNormalR / safeZoom;
      final graphStroke = screenStrokeMin / safeZoom;
      final graphHit = screenHitRadius / safeZoom;
      // Cull size: mini footprint (30px screen diameter + label none).
      final cullD = 30.0 / safeZoom;
      return LodRenderMetrics(
        zoom: safeZoom,
        tier: 'mini',
        cullSize: Size(cullD, cullD),
        graphNodeRadius: graphNormalR,
        graphStrokeWidth: graphStroke,
        graphHitRadius: graphHit,
        screenNodeRadius: screenNormalR,
        screenStrokeWidth: screenStrokeMin,
      );

    case 'micro':
      // MICRO LOD (v5.111): colored circle + accent ring (no letter).
      // SCREEN-SPACE CLAMPED — smaller than MINI but still visible.
      //   normal radius: 8px (16px diameter)
      //   emphasised radius: 11px (22px diameter)
      //   ring stroke: 1.5px screen-space
      //   hit radius: 18px screen-space
      const screenNormalR = 8.0;
      const screenEmphasisR = 11.0;
      const screenStrokeMin = 1.5;
      const screenHitRadius = 18.0;
      final graphNormalR = screenNormalR / safeZoom;
      final graphStroke = screenStrokeMin / safeZoom;
      final graphHit = screenHitRadius / safeZoom;
      final cullD = 22.0 / safeZoom;
      return LodRenderMetrics(
        zoom: safeZoom,
        tier: 'micro',
        cullSize: Size(cullD, cullD),
        graphNodeRadius: graphNormalR,
        graphStrokeWidth: graphStroke,
        graphHitRadius: graphHit,
        screenNodeRadius: screenNormalR,
        screenStrokeWidth: screenStrokeMin,
      );

    case 'chip':
      // CHIP LOD (legacy MEDIUM tier — kept for focus-mode fallback).
      // v5.111: Raised marker from 8px to 12px for better visibility.
      const screenMarkerRadius = 6.0; // 12px diameter (was 4.0 / 8px)
      const screenStrokeMin = 1.5;
      const screenHitRadius = 24.0;
      final graphMarkerR = screenMarkerRadius / safeZoom;
      final graphStroke = screenStrokeMin / safeZoom;
      final graphHit = screenHitRadius / safeZoom;
      final cullW = 80.0 / safeZoom;
      final cullH = 40.0 / safeZoom;
      return LodRenderMetrics(
        zoom: safeZoom,
        tier: 'chip',
        cullSize: Size(cullW, cullH),
        graphNodeRadius: graphMarkerR,
        graphStrokeWidth: graphStroke,
        graphHitRadius: graphHit,
        screenNodeRadius: screenMarkerRadius,
        screenStrokeWidth: screenStrokeMin,
      );

    case 'overview':
      // OVERVIEW LOD (FAR tier): single painter, no widgets.
      // v5.111: Raised minimum screen radii for better visibility.
      //   normal marker radius: 14px (was 10px) → 28px diameter
      //   emphasised marker radius: 20px (was 14px) → 40px diameter
      //   edge stroke: 1.5px screen-space minimum
      //   hit radius: 24px screen-space minimum (was 22px)
      const screenNormalR = 14.0;
      const screenEmphasisR = 20.0;
      const screenStrokeMin = 1.5;
      const screenHitRadius = 24.0;
      final graphNormalR = screenNormalR / safeZoom;
      final graphEmphasisR = screenEmphasisR / safeZoom;
      final graphStroke = screenStrokeMin / safeZoom;
      final graphHit = screenHitRadius / safeZoom;
      final cullD = 28.0 / safeZoom;
      return LodRenderMetrics(
        zoom: safeZoom,
        tier: 'overview',
        cullSize: Size(cullD, cullD),
        graphNodeRadius: graphNormalR,
        graphStrokeWidth: graphStroke,
        graphHitRadius: graphHit,
        screenNodeRadius: screenNormalR,
        screenStrokeWidth: screenStrokeMin,
      );

    default:
      // Fallback to full.
      return computeLodMetrics(tier: 'full', zoom: zoom);
  }
}

/// Returns the graph-space radius for an overview marker, accounting
/// for emphasis (focused/selected/path/search nodes).
/// v5.111: Increased from 10.0/14.0 to 14.0/20.0.
double overviewGraphRadius({
  required double zoom,
  required bool isEmphasised,
}) {
  final safeZoom = (zoom > 0.001 && zoom.isFinite) ? zoom : 1.0;
  const screenNormalR = 14.0;
  const screenEmphasisR = 20.0;
  final screenR = isEmphasised ? screenEmphasisR : screenNormalR;
  return screenR / safeZoom;
}

/// Returns the graph-space radius for a MINI marker (v5.111).
/// Screen-space clamped: 11px normal, 15px emphasised.
double miniGraphRadius({
  required double zoom,
  required bool isEmphasised,
}) {
  final safeZoom = (zoom > 0.001 && zoom.isFinite) ? zoom : 1.0;
  const screenNormalR = 11.0;
  const screenEmphasisR = 15.0;
  final screenR = isEmphasised ? screenEmphasisR : screenNormalR;
  return screenR / safeZoom;
}

/// Returns the graph-space radius for a MICRO marker (v5.111).
/// Screen-space clamped: 8px normal, 11px emphasised.
double microGraphRadius({
  required double zoom,
  required bool isEmphasised,
}) {
  final safeZoom = (zoom > 0.001 && zoom.isFinite) ? zoom : 1.0;
  const screenNormalR = 8.0;
  const screenEmphasisR = 11.0;
  final screenR = isEmphasised ? screenEmphasisR : screenNormalR;
  return screenR / safeZoom;
}

/// Returns the graph-space stroke width for an overview emphasised
/// ring.
double overviewGraphRingStroke(double zoom) {
  final safeZoom = (zoom > 0.001 && zoom.isFinite) ? zoom : 1.0;
  return 2.0 / safeZoom;
}

/// Returns the graph-space stroke width for an edge, ensuring a
/// minimum screen-space width.
double graphStrokeForScreenStroke({
  required double zoom,
  required double baseGraphStroke,
  required double minScreenStroke,
}) {
  final safeZoom = (zoom > 0.001 && zoom.isFinite) ? zoom : 1.0;
  final minGraph = minScreenStroke / safeZoom;
  return baseGraphStroke < minGraph ? minGraph : baseGraphStroke;
}

/// Converts a desired screen-space radius to graph-space.
double graphRadiusForScreenRadius(double screenRadius, double zoom) {
  final safeZoom = (zoom > 0.001 && zoom.isFinite) ? zoom : 1.0;
  return screenRadius / safeZoom;
}

/// Converts a desired screen-space hit radius to graph-space.
double graphHitRadiusForScreenHitRadius(double screenHitRadius, double zoom) {
  final safeZoom = (zoom > 0.001 && zoom.isFinite) ? zoom : 1.0;
  return screenHitRadius / safeZoom;
}

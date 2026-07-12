// lib/graph/rendering/lod_render_metrics.dart
//
// DAXELO KINREL — LOD Render Metrics (v97)
//
// Centralizes ALL zoom-aware sizing calculations so that culling,
// chip rendering, overview painting, hit testing, and edge rendering
// all use the SAME formulas. No duplication of zoom math.
//
// The camera Transform scales the entire graph Stack by `zoom`.
// A value of X in graph space appears as X*zoom on screen.
// To achieve a desired SCREEN-SPACE size S, the graph-space value
// must be S / zoom.

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

  /// The camera zoom level these metrics were computed for.
  final double zoom;

  /// The LOD tier: 'full', 'chip', or 'overview'.
  final String tier;

  /// The graph-space bounding-box size used for viewport culling.
  /// Nodes whose graph-space center is within this distance of the
  /// viewport edge should remain visible.
  final Size cullSize;

  /// The graph-space radius for drawing node markers (overview/dot
  /// painter). The parent Transform produces screenNodeRadius on screen.
  final double graphNodeRadius;

  /// The graph-space stroke width for edges at this LOD.
  final double graphStrokeWidth;

  /// The graph-space hit-test radius for node tapping.
  final double graphHitRadius;

  /// The resulting screen-space node radius (graphNodeRadius * zoom).
  final double screenNodeRadius;

  /// The resulting screen-space stroke width (graphStrokeWidth * zoom).
  final double screenStrokeWidth;

  @override
  String toString() =>
      'LodRenderMetrics(zoom=$zoom, tier=$tier, '
      'screenNodeR=$screenNodeRadius, screenStroke=$screenStrokeWidth, '
      'cullSize=$cullSize)';
}

/// Computes render metrics for the given LOD tier + zoom.
///
/// This is the SINGLE ENTRY POINT for all zoom-aware sizing.
/// Culling, chip rendering, overview painting, hit testing, and edge
/// rendering all call this function — no duplicate zoom math.
///
/// [tier] — 'full', 'chip', or 'overview'.
/// [zoom] — the current camera zoom level.
LodRenderMetrics computeLodMetrics({
  required String tier,
  required double zoom,
}) {
  // Guard against malformed zoom (NaN, zero, negative).
  final safeZoom = (zoom > 0.001 && zoom.isFinite) ? zoom : 1.0;

  switch (tier) {
    case 'full':
      // FULL LOD: full GraphNode widgets (72dp diameter).
      // Culling uses the full node box size.
      // Edges use the existing premium widths (2.2–4.5 graph-space).
      return LodRenderMetrics(
        zoom: safeZoom,
        tier: 'full',
        cullSize: const Size(140, 176),
        graphNodeRadius: 36.0, // 72 / 2
        graphStrokeWidth: 2.5, // existing premium width
        graphHitRadius: 44.0, // generous tap target
        screenNodeRadius: 36.0 * safeZoom,
        screenStrokeWidth: 2.5 * safeZoom,
      );

    case 'chip':
      // CHIP LOD: lightweight chips with zoom-aware geometry.
      // Desired screen targets:
      //   chip marker diameter: 8px
      //   chip font size: 11px
      //   chip total height: ~30px
      //   edge stroke: 1.5px screen-space minimum
      const screenMarkerRadius = 4.0; // 8px diameter
      const screenStrokeMin = 1.5;
      const screenHitRadius = 24.0; // generous touch target
      // Graph-space values (divided by zoom so Transform restores them).
      final graphMarkerR = screenMarkerRadius / safeZoom;
      final graphStroke = screenStrokeMin / safeZoom;
      final graphHit = screenHitRadius / safeZoom;
      // Cull size: chip footprint in graph space (~80×40 screen).
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
      // OVERVIEW LOD (formerly DOT): single painter, no widgets.
      // Desired screen targets:
      //   normal marker radius: 5–8px (clamped)
      //   emphasised marker radius: 7–11px (clamped)
      //   edge stroke: 1.0px screen-space minimum
      //   hit radius: 20px screen-space minimum
      const screenNormalR = 6.0;
      const screenEmphasisR = 9.0;
      const screenStrokeMin = 1.0;
      const screenHitRadius = 20.0;
      final graphNormalR = screenNormalR / safeZoom;
      final graphEmphasisR = screenEmphasisR / safeZoom;
      final graphStroke = screenStrokeMin / safeZoom;
      final graphHit = screenHitRadius / safeZoom;
      // Cull size: overview marker footprint (12px screen diameter).
      final cullD = 12.0 / safeZoom;
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
double overviewGraphRadius({
  required double zoom,
  required bool isEmphasised,
}) {
  final safeZoom = (zoom > 0.001 && zoom.isFinite) ? zoom : 1.0;
  const screenNormalR = 6.0;
  const screenEmphasisR = 9.0;
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

// lib/graph/widgets/engine/engine_edge_painter.dart
// P0.4: Extracted from family_graph_engine_view.dart.
//
// The V2.1 edge painter — renders all relationship edges in a single
// CustomPainter call (no per-edge widgets). Handles:
//   - Solid/dashed bezier paths per kinship category
//   - Couple-union junctions (parent→child edges route through union midpoint)
//   - Selected/sweep/trace edge animations
//   - Path-focus dimming (unrelated edges dim when a kinship path is focused)
//   - LOD-derived edge quality (stroke width, alpha, midpoint symbols)

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/kinship/kinship_edge_style.dart';
import '../../../core/kinship/kinship_category_map.dart';
import '../../../core/kinship/heart_shape.dart' show HeartShape;
import '../../engine/edge_dedup.dart' show DedupedEdge;
import '../../interaction/couple_union_model.dart'
    show CoupleUnion, resolveEffectiveEdgeEndpoints;
import '../../rendering/edge_path_cache.dart' show EdgePathCache;
import '../../rendering/edge_quality.dart' show EdgeQuality, EdgeQualityX;
import '../../rendering/graph_lighting.dart' show GraphLighting;
import '../../rendering/lod_render_metrics.dart'
    show LodRenderMetrics;
import '../../rendering/emphasis_priority.dart'
    show EmphasisLevel, computeEmphasisLevel;
import '../../../core/constants/brand_colors.dart' show KinrelColors;
import '../../data/graph_data_models.dart' show GraphEdgeData;
import '../../rendering/semantic_zoom.dart'
    show
        SemanticTier,
        shouldRenderText,
        farTierExcludesPremiumEffects;

class EngineEdgePainter extends CustomPainter {
  /// v5.98: Static cache of pre-rendered midpoint bead images.
  /// Keyed by a signature string of (radius, color, isDimmed, isSelected,
  /// edgeQuality). On first use, the bead is rendered once via
  /// PictureRecorder → picture.toImage(), then blitted on subsequent
  /// paints via canvas.drawImageRect — no gradient shader or blur
  /// recomputation per edge per frame.
  static final Map<String, ui.Image> _midpointImageCache = {};

  /// Clear the midpoint image cache. Call when theme or DPI changes.
  static void clearMidpointCache() {
    _midpointImageCache.clear();
  }

  EngineEdgePainter({
    required this.positions,
    required this.edges,
    required this.edgeCategories,
    required this.edgeCustomColors,
    required this.coupleUnions,
    required this.cache,
    required this.edgeQuality,
    required this.graphRevision,
    required this.layoutRevision,
    required this.edgeVisualRevision,
    this.selectedEdgeId,
    this.dimmedEdgeIds,
    this.sweepEdgeId,
    this.sweepProgress = 0.0,
    this.sweepActive = false,
    this.pathFocusedEdgeIds,
    this.pathFocusActive = false,
    this.traceEdgeId,
    this.traceProgress = 0.0,
    this.traceActive = false,
    this.completedTraceEdgeIds,
    this.edgeWaypoints = const {},
    this.connectOnOpenActive = false,
    this.connectOnOpenCurrentEdgeId,
    this.connectOnOpenProgress = 0.0,
    this.connectOnOpenRevealedEdgeIds = const <String>{},
    this.connectOnOpenCurrentEdgeIds = const <String>{},
    this.zoom = 1.0,
  });

  final Map<String, Offset> positions;
  final List<DedupedEdge> edges;
  final Map<String, KinshipEdgeCategory> edgeCategories;
  final Map<String, Map<String, dynamic>> edgeCustomColors;

  /// Phase 6: Couple unions used to redirect parent→child edges to the
  /// union midpoint. Passed through unchanged from the build method via
  /// `_EdgeSelectionWrapper`. The painter NEVER recomputes unions — it
  /// reads from this list, which is the SAME list the hit-tester reads
  /// via `_currentCoupleUnions`. See `resolveEffectiveEdgeEndpoints`.
  final List<CoupleUnion> coupleUnions;

  final EdgePathCache cache;
  final EdgeQuality edgeQuality;

  /// Revision counters — see PART 11. The painter compares these in
  /// `shouldRepaint` instead of deep-comparing maps every frame.
  final int graphRevision;
  final int layoutRevision;
  final int edgeVisualRevision;

  final String? selectedEdgeId;
  final Set<String>? dimmedEdgeIds;

  /// Edge ID the sweep is currently travelling along. Null when no
  /// sweep is active. May differ from `selectedEdgeId` if selection
  /// changed mid-sweep (the sweep completes on the original edge).
  final String? sweepEdgeId;
  final double sweepProgress;
  final bool sweepActive;

  /// v92 (PART 14): Edges in the focused viewer→target kinship path.
  /// These retain full clarity while unrelated edges dim.
  final Set<String>? pathFocusedEdgeIds;

  /// v92 (PART 14): True when a path focus is active.
  final bool pathFocusActive;

  /// v92 (PART 15): Edge currently being traced by the sequential
  /// path trace. Null when no trace is active.
  final String? traceEdgeId;
  final double traceProgress;
  final bool traceActive;

  /// v92 (PART 15): Edges already traced by the sequential trace.
  /// These remain statically focused after their sweep completes.
  final Set<String>? completedTraceEdgeIds;

  /// v5.22 (PART 2): Personal RELATIVE edge midpoint bow offsets,
  /// keyed by relationshipId. When an override exists for an edge,
  /// the painter bows the bezier's middle control point(s) by this
  /// delta (relative to the true t=0.5 midpoint). When no override
  /// exists (the normal case), the painter uses the existing
  /// `_bezier` + PathMetric t=0.5 midpoint calculation unchanged.
  ///
  /// HARD CONSTRAINT: this map is the ONLY way a relationship line's
  /// visual geometry can be modified by user drag. The drag handler
  /// must never call createRelationship/updateRelationship/
  /// deleteRelationship — see _handleRearrangeDragUpdate assertion.
  final Map<String, Offset> edgeWaypoints;

  /// v5.27 Task 2: Connect-on-open animation state. While true, the
  /// painter HIDES non-revealed edges (alpha=0) instead of dimming
  /// them. The current edge fades in over its time slot using
  /// [connectOnOpenProgress]. Revealed edges (in
  /// [connectOnOpenRevealedEdgeIds]) are drawn at full alpha.
  ///
  /// Reuses the EXISTING GraphPathTraceController's state shape —
  /// the painter interprets these with fade-in semantics instead of
  /// the existing sweep semantics when [connectOnOpenActive] is true.
  final bool connectOnOpenActive;
  final String? connectOnOpenCurrentEdgeId;
  final double connectOnOpenProgress;
  final Set<String> connectOnOpenRevealedEdgeIds;

  /// v5.97: When non-empty, ALL edges in this set are animating
  /// simultaneously (parallel mode). The painter applies the same
  /// progressive-draw treatment to every edge in this set. When empty,
  /// the painter falls back to checking [connectOnOpenCurrentEdgeId]
  /// (sequential mode).
  final Set<String> connectOnOpenCurrentEdgeIds;

  /// v5.107: Current camera zoom level. Used to compute a zoom-aware
  /// minimum stroke width so edges remain visible at low zoom (where
  /// the graph-space stroke would otherwise render at <1 screen pixel).
  /// Defaults to 1.0 (no zoom adjustment).
  final double zoom;

  // ── Path construction ─────────────────────────────────────────────────

  /// Builds a bezier curve path between two node centers.
  ///
  /// The curve is designed to:
  ///   1. Start and end at the EXACT center of each node (no offset)
  ///   2. Use a smooth S-curve when nodes are vertically aligned
  ///   3. Use a gentle arc when nodes are horizontally offset
  ///   4. Avoid overlapping with other edges by using directional
  ///      control points that spread curves apart
  ///
  /// v64 (BUG-2 FIX): [lateralOffset] shifts the curve sideways so that
  /// parallel edges between the same node pair (e.g. parent + spouse)
  /// don't stack on top of each other. 0.0 for solo edges.
  ///
  /// v5.22 (PART 2): [waypointDelta] is a RELATIVE offset from the
  /// true t=0.5 bezier midpoint. When non-zero, both middle control
  /// points are shifted by this delta so the bowed curve passes
  /// through (or near) the dragged point. A RELATIVE offset is
  /// used (not absolute) so the override stays meaningful if the
  /// endpoints get repositioned — see the storage contract on
  /// `LayoutOverridesService.saveEdgeWaypoint`.
  ///
  /// When [waypointDelta] is Offset.zero (the normal case — no
  /// saved override for this edge), the curve is IDENTICAL to the
  /// pre-v5.22 behaviour. This is the regression-guard for PART 2.5
  /// ("default midpoint must stay mathematically correct").
  static Path _bezier(Offset s, Offset t,
      {double lateralOffset = 0.0, Offset waypointDelta = Offset.zero}) {
    final double dy = t.dy - s.dy;
    final double dx = t.dx - s.dx;
    final double distance = (s - t).distance;

    // v5.45: NO straight-line fallback. ALL edges get a visible curve.
    // Even very short edges get a minimum bow of 15px.
    // The only exception is when source == target (distance == 0).
    if (distance < 1.0) {
      return Path()..moveTo(s.dx, s.dy);
    }

    // v5.45: Compute the perpendicular direction to the connecting line.
    // This is used to bow the curve away from the straight line.
    final double angle = (t - s).direction;
    final double perpAngle = angle + math.pi / 2;
    final Offset perp = Offset(math.cos(perpAngle), math.sin(perpAngle));

    // v5.45: Bow magnitude — aggressive and unmistakably visible.
    // 25% of the distance, clamped to [15, 100]. This guarantees a
    // clearly visible curve at any zoom level and any distance.
    // The lateralOffset (for parallel edges) adds extra separation.
    final double bowMagnitude =
        (distance * 0.25).clamp(15.0, 100.0) + lateralOffset.abs();
    // Bow direction: solo edges bow in +perp; parallel edges alternate.
    final Offset bow = perp * (lateralOffset >= 0 ? bowMagnitude : -bowMagnitude);

    // v5.62: If the user dragged the midpoint, use a CUBIC bezier
    // whose t=0.5 point is EXACTLY at (linearMid + waypointDelta).
    //
    // This is critical for drag/hit-test parity: the dot/heart marker
    // is rendered at the PathMetric t=0.5 position of the rendered
    // curve (see _paintMidpoint). For the marker to appear exactly
    // where the user's finger is, the curve's t=0.5 must equal
    // (linearMid + waypointDelta) — which is the position the drag
    // handler stores the delta relative to (see
    // _handleRearrangeDragUpdate: `delta = graphPos - linearMid`).
    //
    // Math: for a cubic bezier B(t) = (1-t)³s + 3(1-t)²t·cp1 +
    // 3(1-t)t²·cp2 + t³·t, the parameter-t=0.5 point is
    // (s + 3·cp1 + 3·cp2 + t) / 8. Setting cp1 = s + (1/3)(t-s) +
    // (4/3)·delta and cp2 = s + (2/3)(t-s) + (4/3)·delta yields
    // B(0.5) = (s+t)/2 + delta = linearMid + delta. The curve is
    // symmetric around linearMid + (4/3)·delta (the midpoint of cp1
    // and cp2), so arc-length t=0.5 == parameter t=0.5 — the
    // PathMetric midpoint is also exactly linearMid + delta.
    //
    // v5.58 used a QUADRATIC bezier with control point at
    // (linearMid + delta). That made the curve's t=0.5 point land at
    // linearMid + delta/2 — i.e. the marker appeared only HALF as far
    // from the linear midpoint as the user's finger. The hit-test
    // checked linearMid + delta (the full delta), so the marker and
    // the tap target were always offset by delta/2 — which is why
    // dragging stopped working after zooming in (the 48px hit radius
    // shrinks in graph space at high zoom, eventually failing to
    // cover the delta/2 gap).
    if (waypointDelta != Offset.zero) {
      final midX = s.dx + dx * 0.5;
      final midY = s.dy + dy * 0.5;
      // The user's intended marker position.
      final Offset targetMid = Offset(
        midX + waypointDelta.dx,
        midY + waypointDelta.dy,
      );

      // v5.58: Check if the target midpoint is collinear (or nearly
      // collinear) with the start and end points. If so, render a
      // straight line — a curve through a collinear point is visually
      // indistinguishable from a straight line anyway, and rendering
      // it as straight avoids sub-pixel rendering artifacts.
      //
      // Collinearity test: the cross product of (t-s) and (target-s)
      // should be near zero. We use a tolerance of 2px (the cross
      // product magnitude equals the perpendicular distance from
      // target to line st).
      final double crossProduct =
          (t.dx - s.dx) * (targetMid.dy - s.dy) -
          (t.dy - s.dy) * (targetMid.dx - s.dx);
      final double perpDistance = crossProduct.abs() / distance;

      if (perpDistance < 2.0) {
        // Target midpoint is (nearly) on the line → render straight.
        return Path()
          ..moveTo(s.dx, s.dy)
          ..lineTo(t.dx, t.dy);
      }

      // v5.62: Cubic bezier with cp1/cp2 placed so B(0.5) == targetMid.
      // See the math derivation in the comment above.
      final double cpBiasX = waypointDelta.dx * 4.0 / 3.0;
      final double cpBiasY = waypointDelta.dy * 4.0 / 3.0;
      final Offset cp1 = Offset(
        s.dx + dx * (1.0 / 3.0) + cpBiasX,
        s.dy + dy * (1.0 / 3.0) + cpBiasY,
      );
      final Offset cp2 = Offset(
        s.dx + dx * (2.0 / 3.0) + cpBiasX,
        s.dy + dy * (2.0 / 3.0) + cpBiasY,
      );
      return Path()
        ..moveTo(s.dx, s.dy)
        ..cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, t.dx, t.dy);
    }

    // v5.45: Default perpendicular-bow cubic bezier for ALL edges.
    // Control points at 1/3 and 2/3 along the connecting line,
    // shifted perpendicular by `bow`. This produces a smooth, natural
    // curve that is ALWAYS visible — no straight lines anywhere.
    final Offset cp1 = Offset(
      s.dx + dx * 0.33 + bow.dx,
      s.dy + dy * 0.33 + bow.dy,
    );
    final Offset cp2 = Offset(
      s.dx + dx * 0.67 + bow.dx,
      s.dy + dy * 0.67 + bow.dy,
    );
    return Path()
      ..moveTo(s.dx, s.dy)
      ..cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, t.dx, t.dy);
  }

  /// v5.62: SINGLE SOURCE OF TRUTH for the edge midpoint marker
  /// position. Returns the visual midpoint of the rendered bezier
  /// curve — i.e. the position where _paintMidpoint renders the
  /// dot/heart marker.
  ///
  /// This is computed as the PathMetric t=0.5 (arc-length midpoint)
  /// of the path returned by [_bezier] for the same (s, t,
  /// lateralOffset, waypointDelta) inputs. Because [s] and [t] are
  /// already the EFFECTIVE endpoints (post couple-union redirect —
  /// see `resolveEffectiveEdgeEndpoints`), the caller MUST pass the
  /// SAME effective endpoints the painter passes to [_bezier].
  ///
  /// Why this exists: the marker (dot/heart) is rendered at the
  /// PathMetric t=0.5 of the rendered curve, but the hit-tester
  /// previously checked `linearMid + waypointDelta` — a DIFFERENT
  /// position. For the default perpendicular-bow curve, the visual
  /// midpoint is `linearMid + 0.75·bow` (not `linearMid`), and for
  /// the dragged case the visual midpoint is exactly `linearMid +
  /// waypointDelta` (only because v5.62 changed the dragged curve
  /// from a quadratic to a cubic specifically so this holds). The
  /// hit-tester MUST call this same helper to compute the tap
  /// target, otherwise the marker and the tap target silently drift
  /// apart — which is the root cause of the "lines undraggable
  /// after zoom" bug (the 48px hit radius shrinks in graph space at
  /// high zoom, eventually failing to cover the drift).
  ///
  /// Performance: PathMetric computation is O(path length) — cheap
  /// for a single edge, called once per edge per hit-test. The
  /// painter calls this once per edge per frame (via _paintMidpoint);
  /// the hit-tester calls it once per edge per tap. Both are
  /// acceptable for graphs with up to ~hundreds of edges.
  static Offset computeVisualMidpoint(
    Offset s,
    Offset t, {
    double lateralOffset = 0.0,
    Offset waypointDelta = Offset.zero,
  }) {
    final path = _bezier(
      s,
      t,
      lateralOffset: lateralOffset,
      waypointDelta: waypointDelta,
    );
    for (final metric in path.computeMetrics()) {
      if (metric.length > 0) {
        final tangent = metric.getTangentForOffset(metric.length * 0.5);
        if (tangent != null) {
          return tangent.position;
        }
      }
    }
    // PathMetric failed (degenerate path) — fall back to linear midpoint.
    return Offset((s.dx + t.dx) / 2, (s.dy + t.dy) / 2);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // v2.2 Fix 6: Null/empty guards — skip painting entirely if there
    // are no edges or no positions. This prevents crashes and wasted
    // CPU when the graph is empty or still loading.
    if (edges.isEmpty) return;
    if (positions.isEmpty) return;

    // Pre-resolve a few per-frame constants from the lighting contract.
    final bool isDot = edgeQuality == EdgeQuality.dot;
    final double shadowSigma = edgeQuality.shadowSigma;
    final double ridgeAlpha = edgeQuality.ridgeAlpha;

    // Relationship-focus dimming factor (PART 13). Edges in
    // `dimmedEdgeIds` get this alpha multiplier so unrelated threads
    // recede gently when a node is selected. The selected edge and
    // any sweep edge are never dimmed.
    //
    // v5.65 (ISOLATE CONNECTIONS): Reduced from 0.85 to 0.18 for a
    // much stronger fade. The user wants the "Isolate connections"
    // feature to clearly de-emphasize non-related edges (fading them
    // to ~18% opacity) so the focused person's direct relationships
    // stand out. The previous 0.85 (15% reduction) was too subtle —
    // users couldn't tell the isolation was active. At 0.18, dimmed
    // edges are barely visible, preserving spatial context without
    // competing for attention.
    //
    // NOTE: This dimAlpha applies to ALL dimmed edges — both the
    // selection-based fallback (v91) and the focus-based isolation
    // (v5.65). The selection fallback only dims when a node is
    // selected without focus being active, which is a short-lived
    // state (selection usually leads to opening the info sheet).
    // The stronger 0.18 alpha is acceptable for both cases.
    const double dimAlpha = 0.18; // v5.65: strong fade for isolation (was 0.85)

    for (final DedupedEdge deduped in edges) {
      final GraphEdgeData e = deduped.edge;
      final Offset? s = positions[e.sourceId];
      final Offset? t = positions[e.targetId];
      if (s == null || t == null) {
        continue;
      }
      // Phase 6 (hit-test parity): Apply the couple-union redirect to
      // get the EFFECTIVE endpoints for the rendered curve. For a
      // parent→child edge that belongs to a confirmed couple pairing,
      // the source becomes the union midpoint (and symmetrically for
      // child→parent edges). This is the SAME call the hit-tester
      // makes — see `resolveEffectiveEdgeEndpoints`.
      //
      // v100 had this redirect inlined here; the hit-tester did NOT
      // have a matching redirect, so the rendered curve and the tap
      // target drifted apart. The fix extracts the logic into a
      // shared helper (in couple_union_model.dart) called from BOTH
      // sites — they can never diverge again.
      //
      // The cache key (cacheEdgeId below) is unchanged, but the cached
      // Path is keyed by quantized source/target positions, so a
      // redirect that moves the source from the parent's raw position
      // to the union midpoint produces a DIFFERENT cache entry than
      // the pre-redirect curve. This is correct: the rendered curve
      // really did change shape.
      final resolved = resolveEffectiveEdgeEndpoints(
        sourceId: e.sourceId,
        targetId: e.targetId,
        rawSource: s,
        rawTarget: t,
        coupleUnions: coupleUnions,
        positionOf: (id) => positions[id],
      );
      final Offset effectiveSource = resolved.source;
      final Offset effectiveTarget = resolved.target;
      // v64 (BUG-2 FIX): Pass the lateral offset so parallel edges
      // (e.g. parent + spouse between the same pair) are visually
      // separated instead of stacked on top of each other.
      //
      // v67 (BUG-11 FIX): Append the lateral offset to the edge ID
      // passed to the cache, so parallel edges between the same pair
      // (which may share the same base edge ID after dedup) get
      // SEPARATE cache entries. Without this, the second parallel edge
      // would hit the cache and get the FIRST edge's path (wrong curve).
      final cacheEdgeId = deduped.lateralOffset != 0.0
          ? '${e.id}__offset_${deduped.lateralOffset.toStringAsFixed(1)}'
          : e.id;
      // v5.22 (PART 2): Look up the per-viewer RELATIVE midpoint
      // bow override for this edge. When non-zero, the path factory
      // bows the curve through (linear_mid + delta). The cache key
      // is augmented with the quantized delta so an adjusted edge
      // doesn't reuse the un-adjusted cache entry (and vice versa).
      final waypointDelta = edgeWaypoints[e.id] ?? Offset.zero;
      final waypointKey = (waypointDelta.dx.abs() >= 0.01 ||
              waypointDelta.dy.abs() >= 0.01)
          ? '__wp_${waypointDelta.dx.toStringAsFixed(1)}'
              '_${waypointDelta.dy.toStringAsFixed(1)}'
          : '';
      final fullCacheId = '$cacheEdgeId$waypointKey';
      final Path path = cache.getOrCreate(
        edgeId: fullCacheId,
        sourceId: e.sourceId,
        targetId: e.targetId,
        sourcePos: effectiveSource,
        targetPos: effectiveTarget,
        pathFactory: (Offset ss, Offset tt) =>
            _bezier(ss, tt,
                lateralOffset: deduped.lateralOffset,
                waypointDelta: waypointDelta),
      );

      final bool isSelected = e.id == selectedEdgeId;
      final bool isSweep = sweepActive && e.id == sweepEdgeId;
      // v92 (PART 14): path-focus state. A path-focused edge retains
      // normal clarity (the dimAlpha does NOT apply to it). The
      // selected edge and sweep edge are always treated as
      // path-focused for dim purposes.
      final bool isPathFocused = pathFocusActive &&
          pathFocusedEdgeIds != null &&
          pathFocusedEdgeIds!.contains(e.id);
      // v92 (PART 15): sequential trace state.
      final bool isTrace = traceActive && e.id == traceEdgeId;
      final bool isCompletedTrace = completedTraceEdgeIds != null &&
          completedTraceEdgeIds!.contains(e.id);
      final bool isDimmed = !isSelected &&
          !isSweep &&
          !isPathFocused &&
          !isTrace &&
          !isCompletedTrace &&
          dimmedEdgeIds != null &&
          dimmedEdgeIds!.contains(e.id);

      // v69: Resolve the edge style from the AUTHORITATIVE category —
      // no lossy string round-trip. If edgeCategories has this edge,
      // use styleForCategory() (always correct, never grey for known
      // relationships). Fall back to styleFor(key) only when no category
      // is available (e.g. edges between two non-anchor nodes).
      //
      // v83: If edgeCustomColors has this edge, override with custom colors.
      final customColors = edgeCustomColors[e.id];
      final KinshipEdgeCategory? edgeCat = edgeCategories[e.id];
      final style = edgeCat != null
          ? KinshipEdgeStyleResolver.styleForCategory(edgeCat)
          : KinshipEdgeStyleResolver.styleFor(e.relationshipKey);

      // v83: Apply custom colors if available
      final Color edgeColor;
      final double edgeAlpha;
      final List<double> dashPattern;
      final KinshipMidpointSymbol midpointSymbol;

      if (customColors != null) {
        edgeColor = Color(customColors['lineColor'] as int? ?? style.color?.value ?? 0xFF888888);
        edgeAlpha = 1.0;
        dashPattern = customColors['lineType'] == 'dashed' ? [6.0, 4.0] : [];
        final dotType = customColors['dotType'] as String? ?? 'dot';
        midpointSymbol = dotType == 'heart'
            ? KinshipMidpointSymbol.heart
            : dotType == 'none'
                ? KinshipMidpointSymbol.none
                : KinshipMidpointSymbol.dot;
      } else {
        edgeColor = style.color ?? const Color(0xFF888888);
        edgeAlpha = style.defaultAlpha.clamp(0.3, 1.0);
        dashPattern = style.dashPattern;
        midpointSymbol = style.midpointSymbol;
      }

      // v5.107: Zoom-aware stroke width. At low zoom, the graph-space
      // stroke (2.2–4.5px) renders at <1 screen pixel, making edges
      // invisible. We floor the graph-space width so the on-screen
      // width never drops below the per-tier minimum:
      //   full = 2.0px, chip = 1.5px, dot = 1.0px screen.
      final double minScreenStroke = switch (edgeQuality) {
        EdgeQuality.full => 2.0,
        EdgeQuality.chip => 1.5,
        EdgeQuality.dot => 1.0,
      };
      final double safeZoom = zoom > 0.01 ? zoom : 0.01;
      final double minGraphWidth = minScreenStroke / safeZoom;
      final double bodyWidth = math.max(
        GraphLighting.clampBodyWidth(style.strokeWidth),
        minGraphWidth,
      );

      // v92 (PART 14): Path-focused edges get a subtle clarity boost
      // (~10% alpha lift, capped at 1.0). They retain their
      // relationship category colour — orange is NOT applied here.
      final double pathFocusBoost =
          (isPathFocused || isCompletedTrace) ? 0.10 : 0.0;

      // v5.27 Task 2: Connect-on-open animation.
      //
      // While connectOnOpenActive is true, the painter HIDES non-revealed
      // edges (alpha=0) instead of dimming them. The current edge is
      // progressively DRAWN (path-draw) from its BFS-arrival endpoint
      // toward the new endpoint using connectOnOpenProgress (0..1).
      // Revealed edges (in connectOnOpenRevealedEdgeIds) are drawn at
      // their full effectiveAlpha.
      //
      // v5.92: Changed from alpha fade-in to progressive path-draw.
      // The current edge's alpha stays at full effectiveAlpha, but the
      // drawn Path is truncated via PathMetric.extractPath so the line
      // visibly grows from the already-revealed node toward the new
      // node. The midpoint symbol (heart/dot) is skipped until
      // progress >= 1.0 so it doesn't appear before the line reaches it.
      // v5.98: Replaced progressive path-draw with fade+scale reveal.
      // Instead of truncating the path via PathMetric (expensive per-frame
      // geometry recomputation), we draw the FULL bezier path immediately
      // and animate only opacity (0→1) and strokeWidth (60%→100%).
      // This removes ALL PathMetric calls from the connect-on-open path.
      double connectOnOpenAlpha = 1.0;
      double connectOnOpenWidthScale = 1.0; // v5.98: width scale for "settling" feel
      bool skipMidpointForConnectOnOpen = false;
      if (connectOnOpenActive) {
        if (connectOnOpenRevealedEdgeIds.contains(e.id)) {
          // Already revealed — full alpha, full width, midpoint shown.
          connectOnOpenAlpha = 1.0;
          connectOnOpenWidthScale = 1.0;
        } else if (connectOnOpenCurrentEdgeIds.contains(e.id) ||
            e.id == connectOnOpenCurrentEdgeId) {
          // v5.98: Currently animating — fade in opacity + scale width.
          // No PathMetric calls — just alpha/width interpolation.
          final progress = connectOnOpenProgress.clamp(0.0, 1.0);
          connectOnOpenAlpha = progress;
          // Width eases from 60% → 100% for a subtle "settling" feel
          connectOnOpenWidthScale = 0.6 + 0.4 * progress;
          // Skip midpoint until fully revealed
          skipMidpointForConnectOnOpen = progress < 1.0;
        } else {
          // Not yet started — completely hidden.
          connectOnOpenAlpha = 0.0;
        }
      }

      // Final alpha after relationship-focus dimming + path-focus boost
      // + connect-on-open fade-in multiplier.
      final double effectiveAlpha = connectOnOpenAlpha == 0.0
          ? 0.0
          : ((isDimmed
                  ? (edgeAlpha * dimAlpha).clamp(0.0, 1.0)
                  : (edgeAlpha + pathFocusBoost).clamp(0.0, 1.0)) *
              connectOnOpenAlpha).clamp(0.0, 1.0);

      // v5.98: Apply width scale for the connect-on-open "settling" feel.
      // The full path is drawn (no PathMetric truncation) — only alpha
      // and width change per frame.
      final double effectiveBodyWidth =
          bodyWidth * connectOnOpenWidthScale;

      // ── DOT LOD: minimal stroke only ──────────────────────────────
      // No blur, no ridge, no sweep. Selected edges get a slightly
      // thicker stroke + a subtle orange aura so focus is still
      // legible at the cheapest tier.
      //
      // v105 (MIDPOINT ALWAYS VISIBLE): The midpoint symbol (dot/heart)
      // IS still painted at DOT LOD — see the block after the stroke
      // passes below. Previously it was skipped here (the old `continue`
      // jumped past the midpoint block), which caused the heart to
      // disappear when zoomed out. The midpoint is now painted BEFORE
      // the `continue` so it stays visible at every zoom level.
      if (isDot) {
        if (isSelected) {
          // PASS D — orange interaction aura (cheap, no blur)
          final dotAuraPaint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = effectiveBodyWidth + 2.0
            ..color = KinrelColors.orange
                .withValues(alpha: GraphLighting.selectedAuraAlpha)
            ..strokeCap = StrokeCap.round
            ..isAntiAlias = true;
          canvas.drawPath(path, dotAuraPaint);
        }
        final dotBodyPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSelected ? effectiveBodyWidth + 0.6 : effectiveBodyWidth
          ..color = edgeColor.withValues(alpha: effectiveAlpha)
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true;
        canvas.drawPath(path, dotBodyPaint);

        // v105: paint the midpoint (simplified) at DOT LOD too, so
        // the heart / dot stays visible when zoomed out. _paintMidpoint
        // handles the DOT-LOD simplification internally (single filled
        // circle, no pseudo-3D passes).
        //
        // v5.62: lateralOffset + waypointDelta are now required so the
        // marker is rendered at the SAME position the hit-tester checks.
        //
        // v5.92: Skip the midpoint for the connect-on-open current edge
        // until progress >= 1.0, so the symbol doesn't appear before
        // the line reaches it.
        if (midpointSymbol != KinshipMidpointSymbol.none &&
            !skipMidpointForConnectOnOpen) {
          _paintMidpoint(
            canvas: canvas,
            path: path,
            s: effectiveSource,
            t: effectiveTarget,
            midpointSymbol: midpointSymbol,
            customColors: customColors,
            style: style,
            edgeColor: edgeColor,
            effectiveStrokeWidth: effectiveBodyWidth,
            isSelected: isSelected,
            isDimmed: isDimmed,
            dimAlpha: dimAlpha,
            lateralOffset: deduped.lateralOffset,
            waypointDelta: waypointDelta,
          );
        }
        continue;
      }

      // ── FULL / CHIP LOD: physical 3-pass thread ───────────────────
      //
      // For dashed edges we apply the SAME 3 passes to each visible
      // dash segment (no continuous glow underneath). For solid edges
      // we apply the 3 passes to the whole Path.

      if (isSelected) {
        _paintSelectedEdge(
          canvas: canvas,
          path: path,
          edgeColor: edgeColor,
          bodyWidth: effectiveBodyWidth,
          edgeAlpha: edgeAlpha,
          dashPattern: dashPattern,
          shadowSigma: shadowSigma,
          ridgeAlpha: ridgeAlpha,
        );
      } else if (dashPattern.isNotEmpty && dashPattern.length >= 2) {
        _paintDashedPhysical(
          canvas: canvas,
          path: path,
          edgeColor: edgeColor,
          bodyWidth: effectiveBodyWidth,
          edgeAlpha: effectiveAlpha,
          dashPattern: dashPattern,
          shadowSigma: shadowSigma,
          ridgeAlpha: ridgeAlpha,
        );
      } else {
        _paintSolidPhysical(
          canvas: canvas,
          path: path,
          edgeColor: edgeColor,
          bodyWidth: effectiveBodyWidth,
          edgeAlpha: effectiveAlpha,
          shadowSigma: shadowSigma,
          ridgeAlpha: ridgeAlpha,
        );
      }

      // ── ONE-SHOT SWEEP ────────────────────────────────────────────
      // Drawn ABOVE the selected-edge passes. A short near-white
      // highlight segment travels once along the cached Path.
      if (isSweep) {
        _paintSweepSegment(
          canvas: canvas,
          path: path,
          progress: sweepProgress,
          edgeColor: edgeColor,
          bodyWidth: effectiveBodyWidth,
        );
      }

      // v92 (PART 15): SEQUENTIAL TRACE SWEEP — drawn ABOVE the
      // path-focus state. Reuses the same `_paintSweepSegment` pass
      // as the selected-edge sweep, but driven by `traceProgress`
      // along the current trace edge. Completed trace edges remain
      // statically focused via the `isCompletedTrace` alpha boost
      // applied above — no extra paint pass needed for them.
      if (isTrace) {
        _paintSweepSegment(
          canvas: canvas,
          path: path,
          progress: traceProgress,
          edgeColor: edgeColor,
          bodyWidth: effectiveBodyWidth,
        );
      }

      // ── MIDPOINT SYMBOL ───────────────────────────────────────────
      // v105 (MIDPOINT ALWAYS VISIBLE): The midpoint symbol (dot ● for
      // normal relationships, heart ♥ for spouse/partner) is the ONLY
      // edge-center marker and MUST remain visible at EVERY zoom level
      // and in EVERY graph state. Previously it was skipped at DOT LOD
      // and when the edge was dimmed (focus mode) — causing the heart
      // to disappear when the user zoomed out or selected a node. The
      // user requirement is that the heart "must always remain visible
      // at every zoom level and in every graph state. It should never
      // disappear due to zooming, panning, scaling, or rendering
      // updates."
      //
      // Implementation:
      //   • The midpoint is ALWAYS painted when the edge has a non-none
      //     midpoint symbol, regardless of LOD tier or dim state.
      //   • At DOT LOD (zoomed out far), a SIMPLIFIED midpoint is
      //     painted (a single filled circle — no pseudo-3D shadow /
      //     rim / gradient / specular) so it stays cheap while remaining
      //     visible. The symbol shape (heart vs dot) is preserved so a
      //     spouse edge still shows a heart even at FAR zoom.
      //   • When the edge is dimmed (focus mode), the midpoint is
      //     painted at reduced alpha (dimAlpha) so it stays visible but
      //     recedes — matching the dimmed edge body. It is NEVER fully
      //     hidden.
      //   • The midpoint position is computed from the SAME cached
      //     Path the line uses (via PathMetrics), so the line and the
      //     midpoint are PERFECTLY ALIGNED by construction at every
      //     zoom and pan position.
      //
      // No persistent kinship text is ever rendered on edges — the
      // relationship data remains available for accessibility, path
      // tracing, and the relationship info sheet (tap interaction).
      //
      // v5.62: lateralOffset + waypointDelta are now required so the
      // marker is rendered at the SAME position the hit-tester checks.
      //
      // v5.92: Skip the midpoint for the connect-on-open current edge
      // until progress >= 1.0, so the symbol doesn't appear before
      // the line reaches it.
      if (midpointSymbol != KinshipMidpointSymbol.none &&
          !skipMidpointForConnectOnOpen) {
        _paintMidpoint(
          canvas: canvas,
          path: path,
          // Phase 6: pass the EFFECTIVE (post-redirect) endpoints so the
          // midpoint fallback (used only if PathMetrics fails) matches
          // the rendered curve. The primary computation uses path
          // metrics along the cached Path, which was itself built from
          // these effective endpoints — so they agree by construction.
          s: effectiveSource,
          t: effectiveTarget,
          midpointSymbol: midpointSymbol,
          customColors: customColors,
          style: style,
          edgeColor: edgeColor,
          effectiveStrokeWidth: bodyWidth,
          isSelected: isSelected,
          isDimmed: isDimmed,
          dimAlpha: dimAlpha,
          lateralOffset: deduped.lateralOffset,
          waypointDelta: waypointDelta,
        );
      }
    }

    // v5.62 (BUG 1 FIX): The separate union-junction orange dot has
    // been REMOVED. Previously _paintUnionJunctions drew a small
    // filled orange circle at the LINEAR midpoint between confirmed
    // partners — but the heart on the spouse edge is rendered at the
    // curve's t=0.5 (which bows AWAY from the linear midpoint), so
    // the two markers were at DIFFERENT positions, creating the
    // "orphaned dot floating in empty space" the user reported.
    //
    // The heart on the spouse edge is now the SOLE visual marker for
    // a couple connection. It is also the draggable control point
    // (its hit area is the 48px radius enforced by _hitTestEdge using
    // the same computeVisualMidpoint helper the painter uses). For
    // non-spouse edges, the existing dot bead (rendered by
    // _paintMidpoint with midpointSymbol == dot) is unchanged.
    //
    // Note: the couple-union ROUTING logic (parent→child edges
    // redirecting through the union midpoint) is unchanged — only the
    // visual glyph is removed. resolveEffectiveEdgeEndpoints continues
    // to handle the routing in both the painter and the hit-tester.
  }

  // ── Physical paint helpers ───────────────────────────────────────────

  /// PASS 1 + 2 + 3 for a solid (non-dashed) relationship thread.
  ///
  ///   PASS 1: contact shadow — neutral black, offset down-right,
  ///           slightly wider than the body, blurred.
  ///   PASS 2: relationship body — category colour (or custom colour),
  ///           clamped to the lighting contract width range.
  ///   PASS 3: directional light ridge — thin top-left highlight,
  ///           translated by `GraphLighting.highlightOffset`.
  void _paintSolidPhysical({
    required Canvas canvas,
    required Path path,
    required Color edgeColor,
    required double bodyWidth,
    required double edgeAlpha,
    required double shadowSigma,
    required double ridgeAlpha,
  }) {
    // PASS 1 — contact shadow (only when blur is allowed — never at DOT).
    if (shadowSigma > 0) {
      canvas.save();
      canvas.translate(GraphLighting.shadowOffset.dx, GraphLighting.shadowOffset.dy);
      final shadowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = bodyWidth + 2.4
        ..color = Colors.black.withValues(alpha: GraphLighting.shadowAlpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, shadowSigma)
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true;
      canvas.drawPath(path, shadowPaint);
      canvas.restore();
    }

    // PASS 2 — relationship body.
    final bodyPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = bodyWidth
      ..color = edgeColor.withValues(alpha: edgeAlpha)
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawPath(path, bodyPaint);

    // PASS 3 — directional light ridge (top-left highlight).
    if (ridgeAlpha > 0) {
      canvas.save();
      canvas.translate(GraphLighting.highlightOffset.dx, GraphLighting.highlightOffset.dy);
      final ridgePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (bodyWidth * 0.32).clamp(0.6, 1.0)
        ..color = GraphLighting.ridgeColor(edgeColor)
            .withValues(alpha: ridgeAlpha)
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true;
      canvas.drawPath(path, ridgePaint);
      canvas.restore();
    }
  }

  /// Per-dash 3-pass physical rendering for dashed relationship threads.
  ///
  /// Obtains the PathMetric ONCE, extracts all visible dash segments
  /// ONCE, and reuses those segments for shadow / body / ridge — so we
  /// never recompute dash geometry across the three passes.
  ///
  /// Gaps remain real: no continuous coloured glow is painted
  /// underneath the dashed edge (PART 4).
  void _paintDashedPhysical({
    required Canvas canvas,
    required Path path,
    required Color edgeColor,
    required double bodyWidth,
    required double edgeAlpha,
    required List<double> dashPattern,
    required double shadowSigma,
    required double ridgeAlpha,
  }) {
    final dashWidth = dashPattern[0];
    final dashGap = dashPattern[1];

    // Collect dash segments ONCE for all 3 passes.
    final segments = <Path>[];
    for (final metric in path.computeMetrics()) {
      double pos = 0;
      while (pos < metric.length) {
        final segEnd = (pos + dashWidth).clamp(0.0, metric.length);
        segments.add(metric.extractPath(pos, segEnd));
        pos += dashWidth + dashGap;
      }
    }

    // PASS 1 — per-dash contact shadow.
    if (shadowSigma > 0) {
      canvas.save();
      canvas.translate(GraphLighting.shadowOffset.dx, GraphLighting.shadowOffset.dy);
      final shadowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = bodyWidth + 2.0
        ..color = Colors.black.withValues(alpha: GraphLighting.shadowAlpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, shadowSigma)
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true;
      for (final seg in segments) {
        canvas.drawPath(seg, shadowPaint);
      }
      canvas.restore();
    }

    // PASS 2 — per-dash relationship body.
    final bodyPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = bodyWidth
      ..color = edgeColor.withValues(alpha: edgeAlpha)
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    for (final seg in segments) {
      canvas.drawPath(seg, bodyPaint);
    }

    // PASS 3 — per-dash directional light ridge.
    if (ridgeAlpha > 0) {
      canvas.save();
      canvas.translate(GraphLighting.highlightOffset.dx, GraphLighting.highlightOffset.dy);
      final ridgePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (bodyWidth * 0.32).clamp(0.6, 1.0)
        ..color = GraphLighting.ridgeColor(edgeColor)
            .withValues(alpha: ridgeAlpha)
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true;
      for (final seg in segments) {
        canvas.drawPath(seg, ridgePaint);
      }
      canvas.restore();
    }
  }

  /// 4-pass premium treatment for the SELECTED edge (PART 7).
  ///
  ///   PASS A: stronger neutral contact shadow
  ///   PASS B: ORIGINAL relationship-coloured body (identity preserved)
  ///   PASS C: brighter top-left ridge
  ///   PASS D: subtle Kinrel-orange interaction aura
  ///
  /// The orange is an INTERACTION accent only — it never replaces the
  /// relationship category colour.
  void _paintSelectedEdge({
    required Canvas canvas,
    required Path path,
    required Color edgeColor,
    required double bodyWidth,
    required double edgeAlpha,
    required List<double> dashPattern,
    required double shadowSigma,
    required double ridgeAlpha,
  }) {
    // For dashed selected edges, fall back to per-dash physical
    // rendering for the body + ridge (so dash semantics survive
    // selection), then add the orange aura as a continuous underneath
    // pass. The aura is the only continuous pass; it is subtle and
    // does NOT obscure the dashes.
    final bool dashed = dashPattern.isNotEmpty && dashPattern.length >= 2;

    // PASS D — Kinrel orange interaction aura (drawn FIRST so it sits
    // underneath the body). Continuous even for dashed edges, but very
    // subtle so dash gaps still read.
    if (shadowSigma > 0) {
      final auraPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = bodyWidth + GraphLighting.selectedAuraWidthDelta
        ..color = KinrelColors.orange
            .withValues(alpha: GraphLighting.selectedAuraAlpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, GraphLighting.selectedAuraSigma)
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true;
      canvas.drawPath(path, auraPaint);
    }

    // PASS A — stronger neutral contact shadow.
    if (shadowSigma > 0) {
      canvas.save();
      canvas.translate(GraphLighting.shadowOffset.dx, GraphLighting.shadowOffset.dy);
      final shadowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = bodyWidth + 2.8
        ..color = Colors.black
            .withValues(alpha: GraphLighting.selectedShadowAlpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, shadowSigma)
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true;
      canvas.drawPath(path, shadowPaint);
      canvas.restore();
    }

    if (dashed) {
      // PASS B + C per dash segment.
      final dashWidth = dashPattern[0];
      final dashGap = dashPattern[1];
      final segments = <Path>[];
      for (final metric in path.computeMetrics()) {
        double pos = 0;
        while (pos < metric.length) {
          final segEnd = (pos + dashWidth).clamp(0.0, metric.length);
          segments.add(metric.extractPath(pos, segEnd));
          pos += dashWidth + dashGap;
        }
      }

      // PASS B — relationship-coloured body per dash.
      final bodyPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = bodyWidth
        ..color = edgeColor.withValues(alpha: edgeAlpha)
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true;
      for (final seg in segments) {
        canvas.drawPath(seg, bodyPaint);
      }

      // PASS C — brighter top-left ridge per dash.
      if (ridgeAlpha > 0) {
        canvas.save();
        canvas.translate(GraphLighting.highlightOffset.dx, GraphLighting.highlightOffset.dy);
        final ridgePaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (bodyWidth * 0.36).clamp(0.6, 1.2)
          ..color = GraphLighting.ridgeColor(edgeColor, t: 0.65)
              .withValues(alpha: (ridgeAlpha + 0.10).clamp(0.0, 1.0))
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true;
        for (final seg in segments) {
          canvas.drawPath(seg, ridgePaint);
        }
        canvas.restore();
      }
    } else {
      // PASS B — relationship-coloured body (continuous).
      final bodyPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = bodyWidth
        ..color = edgeColor.withValues(alpha: edgeAlpha)
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true;
      canvas.drawPath(path, bodyPaint);

      // PASS C — brighter top-left ridge.
      if (ridgeAlpha > 0) {
        canvas.save();
        canvas.translate(GraphLighting.highlightOffset.dx, GraphLighting.highlightOffset.dy);
        final ridgePaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (bodyWidth * 0.36).clamp(0.6, 1.2)
          ..color = GraphLighting.ridgeColor(edgeColor, t: 0.65)
              .withValues(alpha: (ridgeAlpha + 0.10).clamp(0.0, 1.0))
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true;
        canvas.drawPath(path, ridgePaint);
        canvas.restore();
      }
    }
  }

  /// ONE-SHOT sweep (PART 8). A short near-white highlight segment
  /// travels ONCE along the selected edge's cached Path. The painter
  /// does NOT own the AnimationController — it receives `progress`
  /// (0..1) and extracts the segment at that position.
  void _paintSweepSegment({
    required Canvas canvas,
    required Path path,
    required double progress,
    required Color edgeColor,
    required double bodyWidth,
  }) {
    final metrics = path.computeMetrics();
    if (metrics.isEmpty) return;
    final metric = metrics.first;
    if (metric.length <= 0) return;

    final double center = (metric.length * progress).clamp(0.0, metric.length);
    final double segLen =
        (metric.length * GraphLighting.sweepSegmentFraction)
            .clamp(8.0, metric.length);
    final double start = (center - segLen / 2).clamp(0.0, metric.length);
    final double end = (center + segLen / 2).clamp(0.0, metric.length);
    if (end <= start) return;

    final Path sweepPath = metric.extractPath(start, end);

    // Soft near-white tinted-with-relationship-colour highlight.
    final sweepPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = bodyWidth + 1.2
      ..color = GraphLighting.ridgeColor(edgeColor, t: 0.75)
          .withValues(alpha: 0.55)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.4)
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawPath(sweepPath, sweepPaint);

    // Crisp inner core for a premium "polished filament" read.
    final corePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = (bodyWidth * 0.5).clamp(0.8, 1.6)
      ..color = Colors.white.withValues(alpha: 0.70)
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawPath(sweepPath, corePaint);
  }

  /// Midpoint bead / heart (PART 6). Branches on `midpointSymbol`:
  ///   • heart → HeartShape.drawHeart (spouse pink, or custom-heart pink)
  ///   • dot   → pseudo-3D obsidian bead with effective midpoint colour
  ///
  /// v5.62: The marker position is computed via [computeVisualMidpoint]
  /// — the SAME helper the hit-tester uses. This eliminates the
  /// marker-vs-tap-target drift that caused "lines undraggable after
  /// zoom" (the marker was rendered at PathMetric t=0.5 of the bowed
  /// curve, but the hit-tester checked the linear midpoint, so at high
  /// zoom the 48px hit radius couldn't cover the drift).
  ///
  /// v5.62: [lateralOffset] and [waypointDelta] are now required
  /// parameters — the marker position depends on them (the curve
  /// bows sideways by lateralOffset, and shifts by waypointDelta when
  /// the user has dragged the midpoint). Passing them here ensures
  /// the marker is rendered at the SAME position the curve passes
  /// through, regardless of bow direction or drag state.
  void _paintMidpoint({
    required Canvas canvas,
    required Path path,
    required Offset s,
    required Offset t,
    required KinshipMidpointSymbol midpointSymbol,
    required Map<String, dynamic>? customColors,
    required KinshipEdgeStyle style,
    required Color edgeColor,
    required double effectiveStrokeWidth,
    required bool isSelected,
    required bool isDimmed,
    required double dimAlpha,
    required double lateralOffset,
    required Offset waypointDelta,
  }) {
    // v5.62: Use the shared helper so the marker position is IDENTICAL
    // to the position the hit-tester checks. This is the single source
    // of truth — never recompute the midpoint inline.
    final Offset midPoint =
        computeVisualMidpoint(s, t, lateralOffset: lateralOffset, waypointDelta: waypointDelta);

    // Resolve the effective midpoint color.
    //   • Default relationship → style.midpointColor (pink for spouse,
    //     edge colour for every other category).
    //   • Custom relationship + heart → force pink (hearts are always
    //     pink in Kinrel's design language).
    //   • Custom relationship + dot   → use the custom edge colour so
    //     the bead inherits the user's chosen relationship identity.
    final Color effectiveMidpointColor;
    if (customColors != null) {
      if (midpointSymbol == KinshipMidpointSymbol.heart) {
        effectiveMidpointColor = KinshipEdgeColors.spouseHeart;
      } else {
        effectiveMidpointColor = edgeColor;
      }
    } else {
      effectiveMidpointColor = style.midpointColor;
    }

    // v105 (MIDPOINT ALWAYS VISIBLE): Apply dim alpha when the edge is
    // dimmed (focus mode). The midpoint is NEVER fully hidden — it
    // stays visible at reduced alpha so the user can always see where
    // the connection is, even when focusing on a different subgraph.
    // Selected edges are never dimmed, so their midpoints stay full.
    final double midpointAlpha =
        isDimmed ? dimAlpha.clamp(0.0, 1.0) : 1.0;

    // v105: At DOT LOD (zoomed out far), paint a SIMPLIFIED midpoint
    // — a single filled circle for both dot and heart symbols. This
    // keeps the midpoint visible at every zoom level (the user
    // requirement) without the expensive pseudo-3D shadow / rim /
    // gradient / specular passes that would be invisible at that
    // scale anyway. The heart shape is still distinguished from the
    // dot at DOT LOD via a slightly larger radius + the spouse pink
    // colour, so a spouse connection is still recognisable when
    // zoomed out.
    //
    // v105.1 (TUNING KNOBS): The DOT-tier midpoint size + alpha are
    // extracted into named constants below so they're easy to find
    // and tune. Sizes are in GRAPH SPACE (the parent camera Transform
    // scales them to screen space, so at zoom 0.4 a 7px graph-space
    // radius renders at ~2.8px on screen — small but visible against
    // the dot-tier node markers which are themselves ~6px screen).
    if (edgeQuality == EdgeQuality.dot) {
      // v5.26 (Task 3): Skip the DOT LOD simplification for
      // spouse/heart-symbol edges — fall through to the real
      // HeartShape.drawHeart code below so spouse connections always
      // render the actual heart shape at any zoom level (instead of a
      // slightly-larger-but-still-circle dot).
      //
      // The original v105 simplification drew a CIRCLE for both hearts
      // and dots at DOT LOD (just with a larger radius for hearts).
      // That kept hearts "present" at low zoom but not visually
      // legible as hearts — zooming all the way out on a tree with
      // several spouse pairs reduced them all to indistinguishable
      // circles. The real heart shape stays visually legible at any
      // zoom because the heart silhouette is recognisable even at
      // ~5px screen size.
      //
      // Non-heart midpoint symbols (regular relationship dots) still
      // use the DOT LOD simplification below — they have no special
      // silhouette to preserve, so a circle is fine.
      if (midpointSymbol == KinshipMidpointSymbol.heart) {
        // Fall through to the real heart-drawing code at line
        // `if (midpointSymbol == KinshipMidpointSymbol.heart)` below.
        // DO NOT early-return here.
      } else {
        // ── DOT-tier midpoint tuning knobs ──────────────────────────
        // Bead radius (graph space) for non-spouse edges.
        const double kDotBeadRadius = 4.5;
        // v5.65 (ISOLATE CONNECTIONS): Floor lowered from 0.5 to 0.18
        // so dimmed midpoint dots at DOT LOD fade consistently with
        // the new stronger isolation dimming. At 0.18, the dot is
        // barely visible — matching the edge body's 0.18 alpha — so
        // the isolation effect is uniform across all LOD tiers.
        // (Previously 0.5, which kept dimmed dots too bright and
        // undermined the isolation visual.)
        const double kDotDimAlphaFloor = 0.18;

        // v105.1: floor the dim alpha so the DOT-tier midpoint never
        // drops below kDotDimAlphaFloor — at small scale a very low
        // alpha would make it invisible.
        final double dotAlpha = isDimmed
            ? (midpointAlpha * (1.0 - kDotDimAlphaFloor) + kDotDimAlphaFloor)
                .clamp(0.0, 1.0)
            : 1.0;
        canvas.drawCircle(
          midPoint,
          kDotBeadRadius,
          Paint()
            ..color =
                effectiveMidpointColor.withValues(alpha: dotAlpha)
            ..style = PaintingStyle.fill,
        );
        return;
      }
    }

    if (midpointSymbol == KinshipMidpointSymbol.heart) {
      // ── HEART (spouse only by default) ───────────────────────
      final double heartSize =
          GraphLighting.heartSizeFor(effectiveStrokeWidth);
      // v105: apply dim alpha via a colour lerp toward the background
      // so the heart stays visible but recedes when dimmed. Using
      // withValues(alpha:) on the heart colour would not work for the
      // HeartShape helper (it draws opaque fills), so we lerp the
      // colour toward transparent black by (1 - midpointAlpha).
      final Color heartColor = isDimmed
          ? Color.lerp(effectiveMidpointColor, Colors.transparent,
              1.0 - midpointAlpha)!
          : effectiveMidpointColor;
      HeartShape.drawHeart(
        canvas: canvas,
        center: midPoint,
        size: heartSize,
        color: heartColor,
        compact: edgeQuality != EdgeQuality.full,
      );
    } else {
      // ── PSEUDO-3D DOT BEAD (cached as pre-rendered image) ──
      // v5.98: The bead (shadow + rim arc + radial gradient + specular)
      // is now rendered ONCE per unique (radius, color, isDimmed,
      // isSelected, edgeQuality) signature via PictureRecorder, then
      // cached as a ui.Image. Subsequent paints just blit the cached
      // image via drawImageRect — no gradient shader or blur recomputation
      // per edge per frame. This is a major perf win for graphs with
      // many edges (500+ nodes → 500+ midpoint beads per frame).
      final double beadR =
          GraphLighting.beadRadiusFor(effectiveStrokeWidth);
      final double shadowAlpha = isSelected
          ? GraphLighting.selectedShadowAlpha
          : GraphLighting.shadowAlpha;
      final double blurSigma =
          edgeQuality == EdgeQuality.full ? 2.0 : 1.4;

      // Build cache key. Quantize radius to 0.5px steps to limit
      // cache entries (beadR varies continuously with zoom/LOD).
      final String cacheKey =
          '${beadR.roundToDouble()}_${effectiveMidpointColor.value}_'
          '${isDimmed}_${isSelected}_${edgeQuality.name}';

      ui.Image? cachedImage = _midpointImageCache[cacheKey];

      // Cache miss — render the bead once and store it.
      if (cachedImage == null) {
        final double pad = beadR * 2.5; // padding for shadow blur
        final int imgSize = ((beadR + pad) * 2).ceil();
        final recorder = ui.PictureRecorder();
        final canvas2 = ui.Canvas(recorder);
        final center = Offset(imgSize / 2, imgSize / 2);

        // Shadow — down-right per global lighting contract.
        if (!isDimmed) {
          canvas2.drawCircle(
            center + GraphLighting.shadowOffset,
            beadR,
            Paint()
              ..color = Colors.black.withValues(alpha: shadowAlpha)
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma),
          );
        }

        // Dark rim (bottom) — adds convex depth reading.
        canvas2.drawArc(
          Rect.fromCircle(
              center: center + const Offset(0, 1.5), radius: beadR),
          0.0,
          math.pi,
          false,
          Paint()
            ..color = isDimmed
                ? effectiveMidpointColor
                    .withValues(alpha: midpointAlpha * 0.5)
                : Color.lerp(effectiveMidpointColor, Colors.black, 0.5)!,
        );

        // Face gradient — upper-left light, darker bottom-right.
        canvas2.drawCircle(
          center,
          beadR,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(-0.3, -0.4),
              radius: 0.8,
              colors: isDimmed
                  ? [
                      effectiveMidpointColor
                          .withValues(alpha: midpointAlpha),
                      effectiveMidpointColor
                          .withValues(alpha: midpointAlpha * 0.8),
                      effectiveMidpointColor
                          .withValues(alpha: midpointAlpha * 0.6),
                    ]
                  : [
                      Color.lerp(effectiveMidpointColor, Colors.white, 0.3)!,
                      effectiveMidpointColor,
                      Color.lerp(effectiveMidpointColor, Colors.black, 0.3)!,
                    ],
              stops: const [0.0, 0.5, 1.0],
            ).createShader(Rect.fromCircle(center: center, radius: beadR)),
        );

        // Specular highlight — tiny, upper-left.
        if (!isDimmed) {
          canvas2.drawOval(
            Rect.fromCenter(
              center: Offset(
                  center.dx - beadR * 0.25, center.dy - beadR * 0.3),
              width: beadR * 0.5,
              height: beadR * 0.3,
            ),
            Paint()..color = Colors.white.withValues(alpha: 0.15),
          );
        }

        final picture = recorder.endRecording();
        // toImage is async, but we can use the sync variant via
        // picture.toImageSync (Flutter 3.7+). Fall back to a
        // synchronous approach using PictureRecorder.
        // Actually, toImage is the only way — but it returns a Future.
        // Since CustomPainter.paint is sync, we use toImageSync if
        // available, otherwise fall back to drawing directly (no cache).
        try {
          // toImageSync is available in Flutter 3.7+
          cachedImage = picture.toImageSync(imgSize, imgSize);
          _midpointImageCache[cacheKey] = cachedImage;
        } catch (_) {
          // Fallback: draw directly (no caching) if toImageSync fails
          cachedImage = null;
        }
      }

      if (cachedImage != null) {
        // Blit the cached bead image at the midpoint position.
        final src = Rect.fromLTWH(
          0, 0,
          cachedImage.width.toDouble(), cachedImage.height.toDouble(),
        );
        final double pad = beadR * 2.5;
        final dst = Rect.fromCircle(
          center: midPoint,
          radius: beadR + pad,
        );
        canvas.drawImageRect(cachedImage, src, dst, Paint());
      } else {
        // Fallback: draw directly (same code as before caching)
        final beadRect =
            Rect.fromCircle(center: midPoint, radius: beadR);
        if (!isDimmed) {
          canvas.drawCircle(
            midPoint + GraphLighting.shadowOffset,
            beadR,
            Paint()
              ..color = Colors.black.withValues(alpha: shadowAlpha)
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma),
          );
        }
        canvas.drawArc(
          Rect.fromCircle(
              center: midPoint + const Offset(0, 1.5), radius: beadR),
          0.0,
          math.pi,
          false,
          Paint()
            ..color = isDimmed
                ? effectiveMidpointColor
                    .withValues(alpha: midpointAlpha * 0.5)
                : Color.lerp(effectiveMidpointColor, Colors.black, 0.5)!,
        );
        canvas.drawCircle(
          midPoint,
          beadR,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(-0.3, -0.4),
              radius: 0.8,
              colors: isDimmed
                  ? [
                      effectiveMidpointColor
                          .withValues(alpha: midpointAlpha),
                      effectiveMidpointColor
                          .withValues(alpha: midpointAlpha * 0.8),
                      effectiveMidpointColor
                          .withValues(alpha: midpointAlpha * 0.6),
                    ]
                  : [
                      Color.lerp(effectiveMidpointColor, Colors.white, 0.3)!,
                      effectiveMidpointColor,
                      Color.lerp(effectiveMidpointColor, Colors.black, 0.3)!,
                    ],
              stops: const [0.0, 0.5, 1.0],
            ).createShader(beadRect),
        );
        if (!isDimmed) {
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(
                  midPoint.dx - beadR * 0.25, midPoint.dy - beadR * 0.3),
              width: beadR * 0.5,
              height: beadR * 0.3,
            ),
            Paint()..color = Colors.white.withValues(alpha: 0.15),
          );
        }
      }
    }
  }

  // v5.62 (BUG 1 FIX): _paintUnionJunctions has been REMOVED.
  //
  // It previously drew a separate orange dot at the LINEAR midpoint
  // between confirmed partners. This competed with the heart on the
  // spouse edge (which is rendered at the curve's t=0.5, a DIFFERENT
  // position when the curve is bowed), creating the "orphaned dot
  // floating in empty space" the user reported.
  //
  // For spouse relationships, the heart on the spouse edge is now the
  // SOLE visual marker for the couple connection AND the draggable
  // control point. For non-spouse edges, the existing dot bead (from
  // _paintMidpoint with midpointSymbol == dot) is unchanged.
  //
  // The couple-union ROUTING logic (parent→child edges redirecting
  // through the union midpoint via resolveEffectiveEdgeEndpoints) is
  // UNCHANGED — only the visual glyph is removed.

  @override
  bool shouldRepaint(covariant EngineEdgePainter old) {
    // v91 (PART 11): Revision-based repaint correctness.
    //
    // The old implementation compared only collection LENGTHS, which
    // missed content changes where:
    //   • edge count is unchanged but a category changed
    //   • position count is unchanged but coordinates changed
    //   • custom colours changed without changing edge count
    //
    // The new implementation compares lightweight revision counters
    // that are bumped by the data layer whenever the corresponding
    // data mutation happens. This avoids deep-comparing thousands of
    // map entries on every animation frame (which would be O(N) per
    // tick) while still repainting on every real content change.
    //
    // We also repaint on:
    //   • selectedEdgeId change (selected-edge premium treatment)
    //   • sweepActive / sweepProgress change (one-shot sweep ticks)
    //   • edgeQuality change (LOD transition)
    //   • dimmedEdgeIds presence change (relationship focus mode)
    //   • pathFocusActive / pathFocusedEdgeIds change (PART 14)
    //   • traceActive / traceProgress / traceEdgeId change (PART 15)
    //   • completedTraceEdgeIds change (PART 15)
    //
    // We intentionally do NOT use `identical()` — on Flutter Web
    // (dart2js) it is unreliable across widget rebuilds.
    return old.graphRevision != graphRevision ||
        old.layoutRevision != layoutRevision ||
        old.edgeVisualRevision != edgeVisualRevision ||
        old.selectedEdgeId != selectedEdgeId ||
        old.edgeQuality != edgeQuality ||
        old.sweepActive != sweepActive ||
        (sweepActive && old.sweepProgress != sweepProgress) ||
        !_sameDimmedSet(old.dimmedEdgeIds) ||
        // v92 (PART 14): path-focus changes
        old.pathFocusActive != pathFocusActive ||
        !_sameSet(old.pathFocusedEdgeIds, pathFocusedEdgeIds) ||
        // v92 (PART 15): trace changes
        old.traceActive != traceActive ||
        old.traceEdgeId != traceEdgeId ||
        (traceActive && old.traceProgress != traceProgress) ||
        !_sameSet(old.completedTraceEdgeIds, completedTraceEdgeIds) ||
        // v5.27 Task 2: connect-on-open animation changes
        old.connectOnOpenActive != connectOnOpenActive ||
        old.connectOnOpenCurrentEdgeId != connectOnOpenCurrentEdgeId ||
        (connectOnOpenActive &&
            old.connectOnOpenProgress != connectOnOpenProgress) ||
        !_sameSet(old.connectOnOpenRevealedEdgeIds,
            connectOnOpenRevealedEdgeIds) ||
        !_sameSet(old.connectOnOpenCurrentEdgeIds,
            connectOnOpenCurrentEdgeIds) ||
        // v5.107: Repaint when zoom changes (stroke width is zoom-dependent)
        old.zoom != zoom;
  }

  /// Lightweight dimmed-set comparison. We do NOT deep-compare element
  /// by element on every frame — we compare length + identity first,
  /// and only fall back to a containsAll check when lengths match but
  /// identities differ. This is O(N) only on actual focus-mode
  /// transitions, not on every animation tick.
  bool _sameDimmedSet(Set<String>? other) =>
      _sameSet(dimmedEdgeIds, other);

  /// v92: Generic lightweight set comparison used for dimmedEdgeIds,
  /// pathFocusedEdgeIds, and completedTraceEdgeIds.
  bool _sameSet(Set<String>? a, Set<String>? b) {
    if (identical(a, b)) return true;
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }
}

// ═══════════════════════════════════════════════════════════════════════
// v92 (PART 19) — +N COLLAPSED BRANCH AFFORDANCE
// ═══════════════════════════════════════════════════════════════════════

/// A small "+N" chip overlaid on a node that has [count] hidden
/// descendants. Tapping the chip reveals the branch via the existing
/// ExpandCollapseController.
///
/// Visual design (per PART 19 spec):
///   • dark Kinrel surface (#1A1F2B)
///   • subtle border (orange @ 0.4 alpha)
///   • restrained orange interaction accent
///   • minimum accessible hit target (44×44)
///   • visual element remains compact (the chip itself is small, but
///     the hit area extends to 44px)

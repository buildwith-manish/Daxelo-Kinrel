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

import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/kinship/kinship_edge_style.dart';
import '../../../core/kinship/kinship_category_map.dart';
import '../../../core/kinship/heart_shape.dart' show HeartShape;
import '../../engine/edge_dedup.dart' show DedupedEdge;
import '../../interaction/couple_union_model.dart'
    show CoupleUnion, unionMidpoint, resolveEffectiveEdgeEndpoints;
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
  static Path _bezier(Offset s, Offset t, {double lateralOffset = 0.0}) {
    final double dy = t.dy - s.dy;
    final double dx = t.dx - s.dx;
    final double distance = (s - t).distance;

    // For very short distances, use a simple line to avoid weird curves.
    // We still apply the lateral offset so parallel short edges separate.
    if (distance < 20.0) {
      return Path()
        ..moveTo(s.dx + lateralOffset, s.dy)
        ..lineTo(t.dx + lateralOffset, t.dy);
    }

    // Control point offset — scales with distance for smooth curves
    // at any zoom level. Clamped to prevent extreme curves.
    final double cpOffset = (distance * 0.3).clamp(30.0, 120.0);

    if (dx.abs() < 10.0) {
      // Vertically aligned nodes: S-curve with lateral offset.
      // Add the parallel offset to the lateral shift so parallel
      // edges bow in different directions.
      final double lateral =
          (dx >= 0 ? cpOffset * 0.5 : -cpOffset * 0.5) + lateralOffset;
      final cp1 = Offset(s.dx + lateral, s.dy + dy * 0.35);
      final cp2 = Offset(t.dx + lateral, t.dy - dy * 0.35);
      return Path()
        ..moveTo(s.dx, s.dy)
        ..cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, t.dx, t.dy);
    }

    // Horizontally offset nodes: gentle vertical bezier.
    // Control points are placed along the vertical midpoint to create
    // a smooth, non-overlapping curve. Apply the parallel offset to
    // the Y axis of the control points so parallel edges separate
    // vertically when nodes are side-by-side.
    final midY = s.dy + dy * 0.5 + lateralOffset;
    final cp1 = Offset(s.dx + dx * 0.25, midY);
    final cp2 = Offset(t.dx - dx * 0.25, midY);
    return Path()
      ..moveTo(s.dx, s.dy)
      ..cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, t.dx, t.dy);
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
    // Premium visual: reduced dimming from 0.70 to 0.85.
    // Non-focused edges now retain 85% clarity instead of 70%, making
    // the graph feel brighter and more connected. Focused edges still
    // stand out via the boost below.
    const double dimAlpha = 0.85; // ~15% reduction (was 30%)

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
      final Path path = cache.getOrCreate(
        edgeId: cacheEdgeId,
        sourceId: e.sourceId,
        targetId: e.targetId,
        sourcePos: effectiveSource,
        targetPos: effectiveTarget,
        pathFactory: (Offset ss, Offset tt) =>
            _bezier(ss, tt, lateralOffset: deduped.lateralOffset),
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

      // Effective stroke width clamped to the lighting contract range.
      final double bodyWidth = GraphLighting.clampBodyWidth(style.strokeWidth);

      // v92 (PART 14): Path-focused edges get a subtle clarity boost
      // (~10% alpha lift, capped at 1.0). They retain their
      // relationship category colour — orange is NOT applied here.
      final double pathFocusBoost =
          (isPathFocused || isCompletedTrace) ? 0.10 : 0.0;

      // Final alpha after relationship-focus dimming + path-focus boost.
      final double effectiveAlpha = isDimmed
          ? (edgeAlpha * dimAlpha).clamp(0.0, 1.0)
          : (edgeAlpha + pathFocusBoost).clamp(0.0, 1.0);

      // ── DOT LOD: minimal stroke only ──────────────────────────────
      // No blur, no ridge, no midpoint, no sweep. Selected edges get
      // a slightly thicker stroke + a subtle orange aura so focus is
      // still legible at the cheapest tier.
      if (isDot) {
        if (isSelected) {
          // PASS D — orange interaction aura (cheap, no blur)
          final dotAuraPaint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = bodyWidth + 2.0
            ..color = KinrelColors.orange
                .withValues(alpha: GraphLighting.selectedAuraAlpha)
            ..strokeCap = StrokeCap.round
            ..isAntiAlias = true;
          canvas.drawPath(path, dotAuraPaint);
        }
        final dotBodyPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSelected ? bodyWidth + 0.6 : bodyWidth
          ..color = edgeColor.withValues(alpha: effectiveAlpha)
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true;
        canvas.drawPath(path, dotBodyPaint);
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
          bodyWidth: bodyWidth,
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
          bodyWidth: bodyWidth,
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
          bodyWidth: bodyWidth,
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
          bodyWidth: bodyWidth,
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
          bodyWidth: bodyWidth,
        );
      }

      // ── MIDPOINT SYMBOL ───────────────────────────────────────────
      // Bead / heart only at FULL or CHIP LOD (PART 10). Skipped at
      // DOT LOD and skipped when the edge is dimmed (focus mode).
      //
      // This is the ONLY edge-center marker. Normal relationship edges
      // render a small dot (●); spouse/partner edges render a heart (♥).
      // No persistent kinship text is ever rendered on edges — the
      // relationship data remains available for accessibility, path
      // tracing, and the relationship info sheet (tap interaction).
      if (edgeQuality.allowsMidpoint &&
          midpointSymbol != KinshipMidpointSymbol.none &&
          !isDimmed) {
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
        );
      }
    }

    // v99 (Phase 6): Paint union junction glyphs AFTER all edges +
    // midpoints. These are subtle visual markers at the midpoint
    // between confirmed partners, showing where a couple connects.
    _paintUnionJunctions(canvas);
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
  }) {
    Offset midPoint = Offset((s.dx + t.dx) / 2, (s.dy + t.dy) / 2);
    for (final metric in path.computeMetrics()) {
      if (metric.length > 0) {
        final tangent = metric.getTangentForOffset(metric.length * 0.5);
        if (tangent != null) {
          midPoint = tangent.position;
          break;
        }
      }
    }

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

    if (midpointSymbol == KinshipMidpointSymbol.heart) {
      // ── HEART (spouse only by default) ───────────────────────
      final double heartSize =
          GraphLighting.heartSizeFor(effectiveStrokeWidth);
      HeartShape.drawHeart(
        canvas: canvas,
        center: midPoint,
        size: heartSize,
        color: effectiveMidpointColor,
        compact: edgeQuality != EdgeQuality.full,
      );
    } else {
      // ── PSEUDO-3D DOT BEAD ───────────────────────────────────
      final double beadR =
          GraphLighting.beadRadiusFor(effectiveStrokeWidth);
      final beadRect = Rect.fromCircle(center: midPoint, radius: beadR);

      // Shadow — down-right per global lighting contract.
      canvas.drawCircle(
        midPoint + GraphLighting.shadowOffset,
        beadR,
        Paint()
          ..color = Colors.black
              .withValues(alpha: isSelected
                  ? GraphLighting.selectedShadowAlpha
                  : GraphLighting.shadowAlpha)
          ..maskFilter = MaskFilter.blur(
              BlurStyle.normal,
              edgeQuality == EdgeQuality.full
                  ? 2.0
                  : 1.4),
      );

      // Dark rim (bottom) — adds convex depth reading.
      canvas.drawArc(
        Rect.fromCircle(
            center: midPoint + const Offset(0, 1.5), radius: beadR),
        0.0,
        pi,
        false,
        Paint()
          ..color =
              Color.lerp(effectiveMidpointColor, Colors.black, 0.5)!,
      );

      // Face gradient — upper-left light, darker bottom-right.
      canvas.drawCircle(
        midPoint,
        beadR,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.3, -0.4),
            radius: 0.8,
            colors: [
              Color.lerp(effectiveMidpointColor, Colors.white, 0.3)!,
              effectiveMidpointColor,
              Color.lerp(effectiveMidpointColor, Colors.black, 0.3)!,
            ],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(beadRect),
      );

      // Specular highlight — tiny, upper-left.
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

  /// v99 (Phase 6): Paints union junction glyphs at the midpoint
  /// between partners for each derived CoupleUnion.
  ///
  /// The glyph is a small filled circle — subtle, NOT competing with
  /// person nodes. It visually marks where a couple connects and
  /// where children descend from. The glyph reuses the relationship
  /// edge colour (spouse orange) for visual consistency.
  ///
  /// Only painted at FULL and CHIP LOD — skipped at DOT (overview)
  /// for performance.
  void _paintUnionJunctions(Canvas canvas) {
    if (coupleUnions.isEmpty) return;
    // Skip at DOT LOD — too small to be meaningful.
    if (edgeQuality == EdgeQuality.dot) return;

    for (final union in coupleUnions) {
      final posA = positions[union.partnerAId];
      final posB = positions[union.partnerBId];
      if (posA == null || posB == null) continue;

      final mid = unionMidpoint(posA, posB);

      // Small filled circle — the junction glyph.
      // Radius scales slightly with zoom to maintain screen-space
      // visibility (same pattern as the overview dot painter).
      final zoom = 1.0; // positions are already in graph space
      const screenJunctionR = 4.0;
      final graphR = screenJunctionR; // graph-space (parent Transform scales)

      // Use the spouse edge colour (orange) for visual consistency.
      const junctionColor = Color(0xFFF97316); // KinshipEdgeColors.spouseEdge

      // Outer ring (subtle).
      canvas.drawCircle(
        mid,
        graphR + 2,
        Paint()
          ..color = junctionColor.withValues(alpha: 0.25)
          ..style = PaintingStyle.fill,
      );

      // Inner dot.
      canvas.drawCircle(
        mid,
        graphR,
        Paint()
          ..color = junctionColor.withValues(alpha: 0.6)
          ..style = PaintingStyle.fill,
      );
    }
  }

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
        !_sameSet(old.completedTraceEdgeIds, completedTraceEdgeIds);
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

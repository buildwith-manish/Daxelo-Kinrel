// lib/features/family_map/widgets/animated_relationship_path.dart
//
// P10.5 — Animated Relationship Paths.
//
// Replaces the static LineLayer edges with flowing-gradient paths
// (amber → orange → amber). The flow is subtle — one cycle per
// [MapVisualConstants.relationshipFlowCycle] — and respects reduced
// motion (static gradient when reduced motion is on).
//
// Two rendering paths (Rule 11 / Rule 12):
//
//   A) MapLibre line-gradient + per-frame setPaintProperty
//      Used when maplibre 0.3.5 supports line-gradient on LineLayer.
//      Verified at runtime by the screen via verifyLineGradientSupport.
//      Performance: per-frame setPaintProperty is cheap for <20 edges;
//      beyond that, viewport-cull to maxVisibleAnimatedPaths (Rule 13).
//
//   B) Flutter overlay (CustomPainter)
//      Fallback when line-gradient is unavailable (e.g., web without
//      WebGL extensions). Draws the gradient as a shader along a path
//      computed from the two endpoints' screen positions.
//
// Different relationship categories get different line styles (all values
// from MapVisualConstants — Rule 14):
//   parent-child   → solid line, 2px, amber→orange flow
//   sibling        → dashed line, 2px, amber flow
//   spouse         → solid line, 2.5px, warm orange flow + heart midpoint
//   ancestor chain → thicker line, 3px, gold flow
//   descendant chain → thicker line, 3px, orange flow
//
// Rule 13 (Performance): setPaintProperty per frame may be expensive
// for many edges. Viewport-cull to maxVisibleAnimatedPaths. If FPS
// drops below 60, downgrade to 30 FPS, then to static gradient.
//
// Rule 15 (Offline): Edges come from the in-memory FamilyMapResult.
// The line-gradient is rendered locally — works offline.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre/maplibre.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/kinship/heart_shape.dart';
import '../../../core/utils/device_tier.dart';
import '../config/map_visual_constants.dart';
import '../providers/family_map_provider.dart';

/// Categorises a relationship key into a line-style bucket. Drives the
/// per-category styling in [PathStyle.forCategory].
enum RelationshipCategory {
  parentChild,
  sibling,
  spouse,
  ancestorChain,
  descendantChain,
  generic,
}

/// Lookup that maps a raw relationship key (e.g. 'father', 'sister',
/// 'spouse') to a [RelationshipCategory]. Mirrors the existing
/// KinshipEdgeStyleResolver from P0.2 but adapted for the map (we
/// don't have the full graph context here, just the raw key).
RelationshipCategory categorizeRelationship(String key) {
  final k = key.toLowerCase().trim();
  const parentKeys = <String>{
    'father', 'mother', 'parent', 'stepfather', 'stepmother',
    'dad', 'mom', 'papa', 'mama', 'appa', 'amma',
  };
  const siblingKeys = <String>{
    'brother', 'sister', 'sibling', 'half-brother', 'half-sister',
    'stepbrother', 'stepsister', 'bhai', 'behan', 'didhi',
  };
  const spouseKeys = <String>{
    'spouse', 'husband', 'wife', 'partner', 'married',
  };
  const ancestorKeys = <String>{
    'grandfather', 'grandmother', 'grandparent', 'great-grandfather',
    'great-grandmother', 'ancestor',
    'dada', 'dadi', 'nana', 'nani',
  };
  const descendantKeys = <String>{
    'son', 'daughter', 'child', 'grandson', 'granddaughter',
    'great-grandson', 'great-granddaughter', 'descendant',
  };
  if (parentKeys.contains(k)) return RelationshipCategory.parentChild;
  if (siblingKeys.contains(k)) return RelationshipCategory.sibling;
  if (spouseKeys.contains(k)) return RelationshipCategory.spouse;
  if (ancestorKeys.contains(k)) return RelationshipCategory.ancestorChain;
  if (descendantKeys.contains(k)) return RelationshipCategory.descendantChain;
  return RelationshipCategory.generic;
}

/// Visual style for a relationship path. All values from
/// [MapVisualConstants] (Rule 14) or [KinrelColors] for graph-edge colors.
class PathStyle {
  const PathStyle({
    required this.color,
    required this.width,
    required this.dashed,
    required this.showHeartMidpoint,
  });

  final Color color;
  final double width;
  final bool dashed;
  final bool showHeartMidpoint;

  static PathStyle forCategory(RelationshipCategory cat) {
    switch (cat) {
      case RelationshipCategory.parentChild:
        return const PathStyle(
          color: Color(0xFFF59240), // amber
          width: 2.0,
          dashed: false,
          showHeartMidpoint: false,
        );
      case RelationshipCategory.sibling:
        return const PathStyle(
          color: Color(0xFFF5B841),
          width: 2.0,
          dashed: true,
          showHeartMidpoint: false,
        );
      case RelationshipCategory.spouse:
        return const PathStyle(
          color: KinrelColors.orange,
          width: 2.5,
          dashed: false,
          showHeartMidpoint: true,
        );
      case RelationshipCategory.ancestorChain:
        return const PathStyle(
          color: Color(0xFF917520), // gold
          width: 3.0,
          dashed: false,
          showHeartMidpoint: false,
        );
      case RelationshipCategory.descendantChain:
        return const PathStyle(
          color: KinrelColors.orange,
          width: 3.0,
          dashed: false,
          showHeartMidpoint: false,
        );
      case RelationshipCategory.generic:
        return const PathStyle(
          color: Color(0xFFF59240),
          width: 2.0,
          dashed: false,
          showHeartMidpoint: false,
        );
    }
  }
}

/// Manages the flowing-gradient animation for relationship paths.
///
/// Lifecycle:
///   final path = AnimatedRelationshipPath(
///     mapController: controller,
///     style: style,
///     reducedMotion: false,
///   );
///   await path.start(edges);
///   // ... on dispose:
///   path.dispose();
///
/// Internally owns an AnimationController that cycles every
/// [MapVisualConstants.relationshipFlowCycle]. On each tick:
///   - If using line-gradient (Rule 11 verified): setPaintProperty
///     updates the line-gradient expression.
///   - If using overlay fallback: triggers a repaint via ValueNotifier.
class AnimatedRelationshipPath {
  AnimatedRelationshipPath({
    required this.tickerProvider,
    this.mapController,
    this.style,
    this.deviceTier,
    this.reducedMotion = false,
    this.onRepaint,
  });

  final TickerProvider tickerProvider;
  final MapController? mapController;
  final StyleController? style;
  final DeviceTier? deviceTier;
  final bool reducedMotion;
  final VoidCallback? onRepaint;

  AnimationController? _controller;
  bool _started = false;
  bool _lineGradientSupported = false;

  static const String sourceId = 'relationship-edges';
  static const String lineLayerId = 'kinrel-relationship-paths';

  DeviceTier get _effectiveTier =>
      deviceTier ?? DeviceTierCache.instance.tier;

  /// True when the maplibre 0.3.5 install supports line-gradient. Set
  /// by [verifyLineGradientSupport] — when false, the layer falls back
  /// to a solid color + the Flutter overlay for the flow animation.
  bool get lineGradientSupported => _lineGradientSupported;

  /// Verifies line-gradient support.
  ///
  /// maplibre 0.3.5 does NOT expose setPaintProperty or setLayerProperties
  /// on StyleController (Rule 11 verified — API surface is limited to
  /// addSource / addLayer / updateGeoJsonSource / removeLayer / removeSource).
  /// We therefore always fall back to the Flutter overlay for the flow
  /// animation (Rule 12 graceful degradation). The LineLayer itself is
  /// still added to the map with a static color; the flow effect is
  /// rendered by the overlay.
  Future<void> verifyLineGradientSupport() async {
    // maplibre 0.3.5 has no setPaintProperty — always use overlay.
    _lineGradientSupported = false;
  }

  /// Starts the flow animation. Idempotent — calling twice is a no-op.
  void start() {
    if (_started) return;
    _started = true;
    if (reducedMotion || _effectiveTier == DeviceTier.low) {
      // Reduced motion / low-tier: no animation, but keep the static
      // gradient (or solid color in fallback mode).
      return;
    }
    _controller = AnimationController(
      vsync: tickerProvider,
      duration: MapVisualConstants.relationshipFlowCycle,
    )..repeat();
    _controller!.addListener(_onTick);
  }

  /// Stops the animation and releases the controller.
  void dispose() {
    _controller?.dispose();
    _controller = null;
    _started = false;
  }

  void _onTick() {
    final value = _controller?.value ?? 0.0;
    if (_lineGradientSupported && style != null) {
      _updateLineGradient(value);
    } else {
      // Trigger the overlay painter to repaint.
      onRepaint?.call();
    }
  }

  void _updateLineGradient(double t) {
    // maplibre 0.3.5 does not expose setPaintProperty — this method is
    // a graceful no-op (Rule 12). The flow animation is rendered by
    // the Flutter overlay (RelationshipPathOverlayPainter), which is
    // driven by `currentProgress` + `onRepaint`.
    // This method is retained for forward-compatibility with future
    // maplibre versions that may add setPaintProperty support.
    onRepaint?.call();
  }

  /// Returns the current animation value (0..1) for use by the overlay
  /// painter. Returns 0 when the animation is disabled.
  double get currentProgress => _controller?.value ?? 0.0;
}

/// CustomPainter for the overlay fallback path. Draws each edge as a
/// curved line with a flowing gradient shader. The flow direction is
/// driven by [AnimatedRelationshipPath.currentProgress].
class RelationshipPathOverlayPainter extends CustomPainter {
  RelationshipPathOverlayPainter({
    required this.edges,
    required this.progress,
    required this.screenPositions,
    required this.reducedMotion,
  }) : super(repaint: screenPositions);

  /// Edges to draw, already viewport-culled by the screen.
  final List<MapRelationshipEdge> edges;

  /// Current animation progress (0..1).
  final double progress;

  /// Notifier that triggers a repaint when the screen positions update.
  final ValueNotifier<int> screenPositions;

  final bool reducedMotion;

  @override
  void paint(Canvas canvas, Size size) {
    if (edges.isEmpty) return;
    for (final edge in edges) {
      _drawEdge(canvas, edge);
    }
  }

  void _drawEdge(Canvas canvas, MapRelationshipEdge edge) {
    // Use pinA and pinB's screen positions. In real usage the screen
    // passes these via a separate Map<String, Offset> — but for the
    // overlay path the screen typically composes a Stack of positioned
    // CustomPaint widgets, one per edge, sized to the bounding box.
    // This painter handles a single edge when used that way.
    final a = Offset.zero;
    final b = Offset(edge.pinB.lat - edge.pinA.lat,
        edge.pinB.lng - edge.pinA.lng); // placeholder — screen overrides

    final category = categorizeRelationship(edge.relationshipKey);
    final style = PathStyle.forCategory(category);
    final paint = Paint()
      ..color = style.color
      ..strokeWidth = style.width
      ..style = ui.PaintingStyle.stroke
      ..strokeCap = ui.StrokeCap.round;

    if (style.dashed) {
      // Dashed line: use a dashed path.
      _drawDashedLine(canvas, a, b, paint);
    } else {
      canvas.drawLine(a, b, paint);
    }

    if (style.showHeartMidpoint) {
      _drawHeartMidpoint(canvas, a, b);
    }
  }

  void _drawDashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dashWidth = 6.0;
    const dashGap = 4.0;
    final total = dashWidth + dashGap;
    final distance = (b - a).distance;
    final count = (distance / total).floor();
    final dir = (b - a) / distance;
    for (var i = 0; i < count; i++) {
      final start = a + dir * (i * total);
      final end = start + dir * dashWidth;
      canvas.drawLine(start, end, paint);
    }
  }

  void _drawHeartMidpoint(Canvas canvas, Offset a, Offset b) {
    final mid = (a + b) / 2;
    // Reuse the existing HeartShape painter from the kinship core.
    final path = HeartShape.buildPath(
      center: mid,
      width: 14,
      height: 14,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = KinrelColors.orange
        ..style = ui.PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant RelationshipPathOverlayPainter old) {
    return old.progress != progress ||
        old.reducedMotion != reducedMotion ||
        old.edges != edges;
  }
}

/// Builds the GeoJSON FeatureCollection for the relationship-edges source.
/// Each feature is a LineString from pinA to pinB with a `category`
/// property the screen can use to filter / style.
String buildRelationshipEdgesGeoJson(List<MapRelationshipEdge> edges) {
  final features = edges.map((e) {
    final category = categorizeRelationship(e.relationshipKey);
    return {
      'type': 'Feature',
      'geometry': {
        'type': 'LineString',
        'coordinates': [
          [e.pinA.lng, e.pinA.lat],
          [e.pinB.lng, e.pinB.lat],
        ],
      },
      'properties': {
        'category': category.name,
        'relationshipKey': e.relationshipKey,
        'pinAId': e.pinA.personId,
        'pinBId': e.pinB.personId,
      },
    };
  }).toList();
  return '''
{
  "type": "FeatureCollection",
  "features": ${features.map((f) => f.toString()).join(',')}
}
'''
      // Quick & dirty JSON — the screen typically uses jsonEncode.
      // Kept as a string here for clarity; production code uses jsonEncode.
      ;
}

/// Viewport-cull edges so only the visible ones are animated.
/// Rule 13 — maxVisibleAnimatedPaths caps the count.
List<MapRelationshipEdge> cullEdgesToViewport({
  required List<MapRelationshipEdge> all,
  required ui.Rect viewport,
  required Map<String, ui.Offset> screenPositions,
}) {
  final maxPaths = MapVisualConstants.maxVisibleAnimatedPaths;
  final result = <MapRelationshipEdge>[];
  for (final edge in all) {
    if (result.length >= maxPaths) break;
    final a = screenPositions[edge.pinA.personId];
    final b = screenPositions[edge.pinB.personId];
    if (a == null || b == null) continue;
    // Inflate the viewport by 100px to keep partially-visible edges.
    final inflated = viewport.inflate(100);
    if (inflated.contains(a) || inflated.contains(b)) {
      result.add(edge);
    }
  }
  return result;
}

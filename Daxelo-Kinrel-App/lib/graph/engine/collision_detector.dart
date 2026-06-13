// lib/graph/engine/collision_detector.dart
//
// DAXELO KINREL — Collision Detector
//
// Post-simulation overlap resolution using a 5-pass algorithm.
// Runs after any layout engine (force, radial, hierarchical) to
// ensure nodes don't overlap regardless of the layout method.
//
// 5-Pass Resolution Algorithm:
//   Pass 1: For each node pair, compute center-to-center distance
//   Pass 2: If distance < (radius_a + radius_b + minimum_gap), compute overlap vector
//   Pass 3: Push both nodes apart along overlap vector, distributing displacement 50/50
//   Pass 4: Clamp displaced positions to viewport boundaries
//   Pass 5: Repeat up to 3 iterations until all overlaps resolved OR budget exhausted
//
// Parameters:
//   Minimum gap (low zoom):  4pt
//   Minimum gap (high zoom): 12pt
//   Dynamic gap based on zoom level and node density
//   Max iterations: 3
//   Budget exhausted: log warning, show "Simplify layout" suggestion

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ═══════════════════════════════════════════════════════════════════════
// COLLISION DETECTOR CONFIG
// ═══════════════════════════════════════════════════════════════════════

/// Configuration for the [CollisionDetector].
class CollisionDetectorConfig {
  /// Minimum gap between nodes at low zoom levels (pt).
  final double minGapLowZoom;

  /// Minimum gap between nodes at high zoom levels (pt).
  final double minGapHighZoom;

  /// Maximum number of resolution iterations.
  final int maxIterations;

  /// Default node radius when not provided in nodeRadii map.
  final double defaultNodeRadius;

  /// Viewport padding for boundary clamping.
  final double viewportPadding;

  /// Zoom level threshold for switching between low/high gap.
  /// Below this threshold → low zoom gap, above → high zoom gap.
  final double zoomThreshold;

  const CollisionDetectorConfig({
    this.minGapLowZoom = 4.0,
    this.minGapHighZoom = 12.0,
    this.maxIterations = 3,
    this.defaultNodeRadius = 40.0,
    this.viewportPadding = 20.0,
    this.zoomThreshold = 1.0,
  });

  CollisionDetectorConfig copyWith({
    double? minGapLowZoom,
    double? minGapHighZoom,
    int? maxIterations,
    double? defaultNodeRadius,
    double? viewportPadding,
    double? zoomThreshold,
  }) {
    return CollisionDetectorConfig(
      minGapLowZoom: minGapLowZoom ?? this.minGapLowZoom,
      minGapHighZoom: minGapHighZoom ?? this.minGapHighZoom,
      maxIterations: maxIterations ?? this.maxIterations,
      defaultNodeRadius: defaultNodeRadius ?? this.defaultNodeRadius,
      viewportPadding: viewportPadding ?? this.viewportPadding,
      zoomThreshold: zoomThreshold ?? this.zoomThreshold,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// COLLISION RESULT
// ═══════════════════════════════════════════════════════════════════════

/// Result of collision detection and resolution.
class CollisionResult {
  /// Adjusted positions after overlap resolution.
  final Map<String, Offset> positions;

  /// Number of overlapping pairs found in the initial pass.
  final int initialOverlapCount;

  /// Number of overlapping pairs remaining after resolution.
  final int remainingOverlapCount;

  /// Number of iterations performed.
  final int iterationsPerformed;

  /// Whether the resolution budget was exhausted.
  final bool budgetExhausted;

  /// Warning message to display if budget was exhausted.
  final String? warningMessage;

  const CollisionResult({
    required this.positions,
    this.initialOverlapCount = 0,
    this.remainingOverlapCount = 0,
    this.iterationsPerformed = 0,
    this.budgetExhausted = false,
    this.warningMessage,
  });

  /// Whether all overlaps were successfully resolved.
  bool get allResolved => remainingOverlapCount == 0;
}

// ═══════════════════════════════════════════════════════════════════════
// COLLISION DETECTOR
// ═══════════════════════════════════════════════════════════════════════

/// Post-simulation overlap resolution engine.
///
/// Takes a map of node positions and radii, detects overlapping nodes,
/// and pushes them apart using a multi-pass iterative algorithm.
///
/// The minimum gap between nodes is dynamic, based on:
///   - Zoom level: higher zoom = larger gap
///   - Node density: denser areas = slightly larger gap to prevent clutter
///
/// Usage:
/// ```dart
/// final detector = CollisionDetector();
/// final result = detector.resolve(
///   positions: layoutPositions,
///   nodeRadii: {personId: 40.0, ...},
///   zoomLevel: 1.5,
///   viewport: Size(2000, 2000),
/// );
/// if (result.budgetExhausted) {
///   showSuggestion('Simplify layout for better results');
/// }
/// ```
class CollisionDetector {
  CollisionDetectorConfig _config;

  CollisionDetector({CollisionDetectorConfig? config})
      : _config = config ?? const CollisionDetectorConfig();

  /// Current configuration.
  CollisionDetectorConfig get config => _config;

  // ── Public API ────────────────────────────────────────────────────

  /// Resolve overlapping nodes in the given positions.
  ///
  /// Parameters:
  ///   [positions]     — Current node positions (personId → Offset)
  ///   [nodeRadii]     — Visual radius of each node (personId → radius)
  ///   [zoomLevel]     — Current zoom level (1.0 = default)
  ///   [viewport]      — Viewport dimensions for boundary clamping
  ///
  /// Returns a [CollisionResult] with adjusted positions and diagnostics.
  CollisionResult resolve({
    required Map<String, Offset> positions,
    required Map<String, double> nodeRadii,
    required double zoomLevel,
    required Size viewport,
  }) {
    if (positions.isEmpty) {
      return const CollisionResult(positions: {});
    }

    // Compute dynamic minimum gap based on zoom and density
    final density = _computeDensity(positions, viewport);
    final minGap = _computeMinGap(zoomLevel, density);

    // Working copy of positions
    final adjusted = Map<String, Offset>.from(positions);
    final ids = adjusted.keys.toList();

    // Pass 1: Count initial overlaps
    final initialOverlaps = _countOverlaps(adjusted, nodeRadii, ids, minGap);

    var remainingOverlaps = initialOverlaps;
    var iteration = 0;

    // Iterate up to maxIterations (Passes 2-5)
    while (remainingOverlaps > 0 && iteration < _config.maxIterations) {
      iteration++;

      // Pass 1-2: Detect overlaps and compute overlap vectors
      final overlapVectors = _computeOverlapVectors(
        adjusted, nodeRadii, ids, minGap,
      );

      // Pass 3: Push nodes apart (50/50 displacement)
      for (final vector in overlapVectors) {
        final posA = adjusted[vector.idA];
        final posB = adjusted[vector.idB];
        if (posA == null || posB == null) continue;

        final halfDx = vector.overlapDx * 0.5;
        final halfDy = vector.overlapDy * 0.5;

        adjusted[vector.idA] = Offset(posA.dx - halfDx, posA.dy - halfDy);
        adjusted[vector.idB] = Offset(posB.dx + halfDx, posB.dy + halfDy);
      }

      // Pass 4: Clamp to viewport boundaries
      _clampToViewport(adjusted, viewport);

      // Pass 5: Recount overlaps
      remainingOverlaps = _countOverlaps(adjusted, nodeRadii, ids, minGap);
    }

    // Check budget exhaustion
    final budgetExhausted = remainingOverlaps > 0 &&
        iteration >= _config.maxIterations;

    String? warning;
    if (budgetExhausted) {
      warning = 'Simplify layout for better results';
      debugPrint(
        'CollisionDetector: budget exhausted after $iteration iterations, '
        '$remainingOverlaps overlaps remaining',
      );
    }

    return CollisionResult(
      positions: adjusted,
      initialOverlapCount: initialOverlaps,
      remainingOverlapCount: remainingOverlaps,
      iterationsPerformed: iteration,
      budgetExhausted: budgetExhausted,
      warningMessage: warning,
    );
  }

  /// Quick check: count overlapping pairs without resolution.
  ///
  /// Useful for diagnostics and deciding whether resolution is needed.
  int countOverlaps({
    required Map<String, Offset> positions,
    required Map<String, double> nodeRadii,
    required double zoomLevel,
    required Size viewport,
  }) {
    if (positions.isEmpty) return 0;
    final density = _computeDensity(positions, viewport);
    final minGap = _computeMinGap(zoomLevel, density);
    final ids = positions.keys.toList();
    return _countOverlaps(positions, nodeRadii, ids, minGap);
  }

  // ── Private helpers ───────────────────────────────────────────────

  /// Compute node density (nodes per square viewport unit).
  double _computeDensity(Map<String, Offset> positions, Size viewport) {
    if (viewport.width <= 0 || viewport.height <= 0) return 0.0;
    return positions.length / (viewport.width * viewport.height);
  }

  /// Compute the dynamic minimum gap based on zoom level and density.
  double _computeMinGap(double zoomLevel, double density) {
    // Interpolate between low-zoom and high-zoom gaps
    final t = (zoomLevel / _config.zoomThreshold).clamp(0.0, 1.0);
    var gap = _config.minGapLowZoom +
        (_config.minGapHighZoom - _config.minGapLowZoom) * t;

    // Add density bonus: denser areas get slightly larger gap
    // density is typically very small (e.g., 0.001 for 2000 nodes in 2000x2000)
    final densityBonus = (density * 1000000).clamp(0.0, 8.0);
    gap += densityBonus;

    return gap;
  }

  /// Count the number of overlapping node pairs.
  int _countOverlaps(
    Map<String, Offset> positions,
    Map<String, double> nodeRadii,
    List<String> ids,
    double minGap,
  ) {
    var count = 0;
    for (var i = 0; i < ids.length; i++) {
      final posA = positions[ids[i]];
      if (posA == null) continue;
      final radiusA = nodeRadii[ids[i]] ?? _config.defaultNodeRadius;

      for (var j = i + 1; j < ids.length; j++) {
        final posB = positions[ids[j]];
        if (posB == null) continue;
        final radiusB = nodeRadii[ids[j]] ?? _config.defaultNodeRadius;

        final dx = posB.dx - posA.dx;
        final dy = posB.dy - posA.dy;
        final dist = sqrt(dx * dx + dy * dy);
        final minDist = radiusA + radiusB + minGap;

        if (dist < minDist) {
          count++;
        }
      }
    }
    return count;
  }

  /// Compute overlap vectors for all overlapping pairs.
  List<_OverlapVector> _computeOverlapVectors(
    Map<String, Offset> positions,
    Map<String, double> nodeRadii,
    List<String> ids,
    double minGap,
  ) {
    final vectors = <_OverlapVector>[];

    for (var i = 0; i < ids.length; i++) {
      final posA = positions[ids[i]];
      if (posA == null) continue;
      final radiusA = nodeRadii[ids[i]] ?? _config.defaultNodeRadius;

      for (var j = i + 1; j < ids.length; j++) {
        final posB = positions[ids[j]];
        if (posB == null) continue;
        final radiusB = nodeRadii[ids[j]] ?? _config.defaultNodeRadius;

        var dx = posB.dx - posA.dx;
        var dy = posB.dy - posA.dy;
        final dist = sqrt(dx * dx + dy * dy);
        final minDist = radiusA + radiusB + minGap;

        if (dist < minDist) {
          // Normalize direction vector
          if (dist > 0) {
            dx /= dist;
            dy /= dist;
          } else {
            // Coincident nodes — nudge apart
            dx = 1.0;
            dy = 0.0;
          }

          final overlap = minDist - dist;
          vectors.add(_OverlapVector(
            idA: ids[i],
            idB: ids[j],
            overlapDx: dx * overlap,
            overlapDy: dy * overlap,
          ));
        }
      }
    }

    return vectors;
  }

  /// Clamp all positions to viewport boundaries.
  void _clampToViewport(Map<String, Offset> positions, Size viewport) {
    final padding = _config.viewportPadding;
    final minX = padding;
    final maxX = viewport.width - padding;
    final minY = padding;
    final maxY = viewport.height - padding;

    for (final id in positions.keys) {
      final pos = positions[id]!;
      positions[id] = Offset(
        pos.dx.clamp(minX, maxX),
        pos.dy.clamp(minY, maxY),
      );
    }
  }
}

// ── Internal overlap vector ────────────────────────────────────────

/// Represents the displacement needed to resolve an overlap between two nodes.
class _OverlapVector {
  /// ID of the first node.
  final String idA;

  /// ID of the second node.
  final String idB;

  /// X component of the overlap displacement (direction from A to B).
  final double overlapDx;

  /// Y component of the overlap displacement (direction from A to B).
  final double overlapDy;

  const _OverlapVector({
    required this.idA,
    required this.idB,
    required this.overlapDx,
    required this.overlapDy,
  });
}

// ═══════════════════════════════════════════════════════════════════════
// RIVERPOD PROVIDERS
// ═══════════════════════════════════════════════════════════════════════

/// Provider for the [CollisionDetector] instance.
final collisionDetectorProvider = Provider<CollisionDetector>((ref) {
  return CollisionDetector();
});

/// Provider for collision resolution result.
///
/// Input: positions, nodeRadii, zoomLevel, viewport.
/// Output: CollisionResult with adjusted positions.
final collisionResultProvider = Provider.family<CollisionResult,
    ({Map<String, Offset> positions, Map<String, double> nodeRadii, double zoom, Size viewport})>(
  (ref, params) {
    final detector = ref.watch(collisionDetectorProvider);
    return detector.resolve(
      positions: params.positions,
      nodeRadii: params.nodeRadii,
      zoomLevel: params.zoom,
      viewport: params.viewport,
    );
  },
);

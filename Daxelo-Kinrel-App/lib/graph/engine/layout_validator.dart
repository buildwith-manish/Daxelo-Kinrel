// lib/graph/engine/layout_validator.dart
//
// DAXELO KINREL — v5.165 Layout Validation Pass
//
// Runs after every expand/collapse to verify the layout output meets
// the user's explicit requirements:
//
//   ✓ No overlapping nodes (180px H / 220px V minimum)
//   ✓ No disconnected visible nodes (every visible node with visible
//     relatives has at least one drawable edge)
//   ✓ No descendant above parent
//   ✓ No ancestor below child
//   ✓ No hidden edge endpoints (every edge's endpoints have positions)
//   ✓ No edge-node intersections (edges don't cross unrelated nodes)
//
// When violations are found, the validator logs a warning. The caller
// can optionally use the validation results to trigger a reroute or
// spacing increase for the affected subtree.
//
// This is a DIAGNOSTIC pass — it does NOT mutate the layout. The
// de-overlap pass in radial_layout.dart handles resolution; this pass
// verifies the resolution succeeded and catches edge cases the
// de-overlap missed.

import 'dart:math';
import 'package:flutter/material.dart' show Offset;
import 'package:flutter/foundation.dart' show debugPrint;

/// Result of a layout validation pass.
class LayoutValidationResult {
  /// True when all checks pass — the layout is valid.
  final bool isValid;

  /// Number of overlapping node pairs found.
  final int overlapCount;

  /// IDs of visible nodes that have NO drawable edges (disconnected).
  final List<String> disconnectedNodeIds;

  /// Number of edges where one or both endpoints have no position.
  final int hiddenEndpointCount;

  /// Number of descendant-above-parent violations.
  final int generationViolationCount;

  /// Number of edge-node intersections (edges crossing unrelated nodes).
  final int edgeNodeIntersectionCount;

  /// Human-readable warning message (null when valid).
  final String? warningMessage;

  const LayoutValidationResult({
    required this.isValid,
    this.overlapCount = 0,
    this.disconnectedNodeIds = const [],
    this.hiddenEndpointCount = 0,
    this.generationViolationCount = 0,
    this.edgeNodeIntersectionCount = 0,
    this.warningMessage,
  });

  @override
  String toString() =>
      'LayoutValidationResult(valid=$isValid, overlaps=$overlapCount, '
      'disconnected=${disconnectedNodeIds.length}, '
      'hiddenEndpoints=$hiddenEndpointCount, '
      'genViolations=$generationViolationCount, '
      'edgeNodeIntersections=$edgeNodeIntersectionCount)';
}

/// A simple edge representation for validation — just sourceId + targetId.
typedef ValidationEdge = ({String sourceId, String targetId});

/// Validates a layout output against the user's spacing + connectivity
/// + hierarchy requirements.
///
/// Usage:
/// ```dart
/// final result = LayoutValidator.validate(
///   positions: layout.positions,
///   visibleIds: visibleIds,
///   edges: edges,
///   parentOf: parentOf, // childId → parentId
/// );
/// if (!result.isValid) {
///   debugPrint('[LayoutValidator] ${result.warningMessage}');
/// }
/// ```
class LayoutValidator {
  /// Minimum horizontal spacing (must match radial_layout.dart's minHorizontal).
  static const double minHorizontal = 180.0;

  /// Minimum vertical spacing (must match radial_layout.dart's minVertical).
  static const double minVertical = 220.0;

  /// Run all validation checks on the given layout.
  ///
  /// [positions] — the layout's position map (personId → Offset).
  /// [visibleIds] — the set of visible node IDs (from proximity state).
  /// [edges] — list of edges as (sourceId, targetId) pairs.
  /// [parentOf] — optional: map of childId → parentId (for generation
  ///   direction checks). When null, generation checks are skipped.
  static LayoutValidationResult validate({
    required Map<String, Offset> positions,
    required Set<String> visibleIds,
    required List<ValidationEdge> edges,
    Map<String, String>? parentOf,
  }) {
    var overlapCount = 0;
    var hiddenEndpointCount = 0;
    var generationViolationCount = 0;
    var edgeNodeIntersectionCount = 0;
    final disconnectedNodeIds = <String>[];

    // ── Check 1: No overlapping nodes ──
    final positionedIds = positions.keys.toList();
    for (var i = 0; i < positionedIds.length; i++) {
      for (var j = i + 1; j < positionedIds.length; j++) {
        final a = positions[positionedIds[i]]!;
        final b = positions[positionedIds[j]]!;
        final dx = (b.dx - a.dx).abs();
        final dy = (b.dy - a.dy).abs();
        if (dx < minHorizontal && dy < minVertical) {
          overlapCount++;
        }
      }
    }

    // ── Check 2: No disconnected visible nodes ──
    // A visible node is "disconnected" if it has a position but NONE
    // of its edges are drawable (the other endpoint has no position).
    final nodesWithDrawableEdges = <String>{};
    for (final e in edges) {
      final s = e.sourceId;
      final t = e.targetId;
      if (positions.containsKey(s) && positions.containsKey(t)) {
        nodesWithDrawableEdges.add(s);
        nodesWithDrawableEdges.add(t);
      } else {
        // ── Check 3: No hidden edge endpoints ──
        hiddenEndpointCount++;
      }
    }
    for (final id in visibleIds) {
      if (positions.containsKey(id) && !nodesWithDrawableEdges.contains(id)) {
        disconnectedNodeIds.add(id);
      }
    }

    // ── Check 4: No descendant above parent ──
    if (parentOf != null) {
      for (final entry in parentOf.entries) {
        final childId = entry.key;
        final parentId = entry.value;
        final childPos = positions[childId];
        final parentPos = positions[parentId];
        if (childPos != null && parentPos != null) {
          // Descendant must be BELOW parent (Y_child > Y_parent in
          // Flutter's coordinate system where +Y is down).
          if (childPos.dy < parentPos.dy - 5.0) {
            // Allow 5px tolerance for rounding.
            generationViolationCount++;
          }
        }
      }
    }

    // ── Check 5: No edge-node intersections (lightweight check) ──
    // Only checks edges that are significantly longer than the direct
    // distance between their endpoints (indicating they curve through
    // other nodes). A full edge-node intersection test is O(E×N) and
    // too expensive for every frame — this is a sampling heuristic.
    // Skip for large graphs (>200 nodes) to avoid perf impact.
    if (positions.length <= 200) {
      for (final e in edges) {
        final s = positions[e.sourceId];
        final t = positions[e.targetId];
        if (s == null || t == null) continue;
        final edgeLength = (t - s).distance;
        // Only check long edges (short edges can't cross nodes).
        if (edgeLength < minHorizontal * 2) continue;
        // Sample 3 points along the edge and check if any is inside
        // an unrelated node's bounding box.
        for (var k = 1; k <= 3; k++) {
          final frac = k / 4.0;
          final px = s.dx + (t.dx - s.dx) * frac;
          final py = s.dy + (t.dy - s.dy) * frac;
          for (final id in positionedIds) {
            if (id == e.sourceId || id == e.targetId) continue;
            final np = positions[id]!;
            if ((px - np.dx).abs() < 36 && (py - np.dy).abs() < 36) {
              edgeNodeIntersectionCount++;
              break;
            }
          }
        }
      }
    }

    final isValid = overlapCount == 0 &&
        disconnectedNodeIds.isEmpty &&
        hiddenEndpointCount == 0 &&
        generationViolationCount == 0 &&
        edgeNodeIntersectionCount == 0;

    String? warning;
    if (!isValid) {
      final parts = <String>[];
      if (overlapCount > 0) parts.add('$overlapCount overlaps');
      if (disconnectedNodeIds.isNotEmpty) {
        parts.add('${disconnectedNodeIds.length} disconnected');
      }
      if (hiddenEndpointCount > 0) parts.add('$hiddenEndpointCount hidden endpoints');
      if (generationViolationCount > 0) parts.add('$generationViolationCount gen violations');
      if (edgeNodeIntersectionCount > 0) parts.add('$edgeNodeIntersectionCount edge-node intersections');
      warning = 'Layout validation failed: ${parts.join(', ')}';
      debugPrint('[LayoutValidator] $warning');
      if (disconnectedNodeIds.isNotEmpty) {
        debugPrint('[LayoutValidator] Disconnected nodes: $disconnectedNodeIds');
      }
    }

    return LayoutValidationResult(
      isValid: isValid,
      overlapCount: overlapCount,
      disconnectedNodeIds: disconnectedNodeIds,
      hiddenEndpointCount: hiddenEndpointCount,
      generationViolationCount: generationViolationCount,
      edgeNodeIntersectionCount: edgeNodeIntersectionCount,
      warningMessage: warning,
    );
  }
}

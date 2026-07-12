// lib/graph/data/data_validator.dart
//
// DAXELO KINREL — Data Validator (V2.1 Blueprint §18)
//
// Validates GraphData coming from Supabase or cache before it enters
// the engine. On validation failure: logs to AnalyticsTracker, skips
// bad record, shows "error node" in UI for missing members.
//
// Validation checks:
//   Check 1: No null required fields (id, display_name, relationship_type)
//   Check 2: No duplicate node IDs
//   Check 3: No broken foreign keys (relationship references non-existent member)
//   Check 4: No circular relationships (cycle detection — DFS, max 20 hops)
//   Check 5: No kinship chains > 20 hops deep

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../analytics/analytics_tracker.dart';
import 'graph_data_models.dart';

// ═══════════════════════════════════════════════════════════════════════
// DATA VALIDATION RESULT
// ═══════════════════════════════════════════════════════════════════════

/// Result of validating graph data.
///
/// Contains the cleaned data with bad records removed, plus lists of
/// orphaned nodes (shown as ghost "Unknown" nodes) and circular edges
/// (shown as dashed-red edges), and validation errors for analytics.
class DataValidationResult {
  /// Creates a validation result.
  const DataValidationResult({
    required this.cleanData,
    this.orphanedNodeIds = const [],
    this.circularEdgeIds = const [],
    this.errors = const [],
  });

  /// Graph data with bad records removed.
  final GraphData cleanData;

  /// Node IDs that reference non-existent members.
  /// Shown as ghost "Unknown" nodes in the UI.
  final List<String> orphanedNodeIds;

  /// Edge IDs that form circular relationships.
  /// Shown as dashed-red edges in the UI.
  final List<String> circularEdgeIds;

  /// Validation error messages, logged to analytics.
  final List<String> errors;

  /// Whether any validation issues were found.
  bool get hasIssues =>
      orphanedNodeIds.isNotEmpty ||
      circularEdgeIds.isNotEmpty ||
      errors.isNotEmpty;
}

// ═══════════════════════════════════════════════════════════════════════
// DATA VALIDATOR
// ═══════════════════════════════════════════════════════════════════════

/// Validates GraphData before it enters the layout engine.
///
/// Performs five validation checks:
///   1. No null required fields
///   2. No duplicate node IDs
///   3. No broken foreign keys
///   4. No circular relationships (DFS, max 20 hops)
///   5. No kinship chains > 20 hops deep
///
/// On failure: logs to analytics, skips bad record, and provides
/// metadata for the UI to show error indicators.
class DataValidator {
  /// Creates a data validator.
  DataValidator({AnalyticsTracker? analyticsTracker})
      : _analyticsTracker = analyticsTracker;

  /// Optional analytics tracker for logging validation errors.
  final AnalyticsTracker? _analyticsTracker;

  /// Maximum allowed hops for cycle detection.
  static const int _maxHops = 20;

  /// Validates [data] and returns a [DataValidationResult].
  DataValidationResult validate(GraphData data) {
    final errors = <String>[];
    final orphanedNodeIds = <String>[];
    final circularEdgeIds = <String>[];

    // ── Check 1: No null required fields ──────────────────────────────
    final validNodes = <GraphNodeData>[];
    for (final node in data.nodes) {
      if (node.id.isEmpty) {
        errors.add('Node with empty ID found — skipping');
        _logError('null_required_field', 'Node ID is empty');
        continue;
      }
      if (node.name.isEmpty && !node.isAnchor) {
        // Name can be empty for anonymous nodes, but log it
        errors.add('Node ${node.id} has empty name');
      }
      validNodes.add(node);
    }

    final validEdges = <GraphEdgeData>[];
    for (final edge in data.edges) {
      if (edge.id.isEmpty) {
        errors.add('Edge with empty ID found — skipping');
        _logError('null_required_field', 'Edge ID is empty');
        continue;
      }
      if (edge.sourceId.isEmpty || edge.targetId.isEmpty) {
        errors.add('Edge ${edge.id} has empty source/target — skipping');
        _logError('null_required_field', 'Edge ${edge.id} missing endpoints');
        continue;
      }
      if (edge.relationshipKey.isEmpty) {
        errors.add('Edge ${edge.id} has empty relationship key — skipping');
        _logError('null_required_field', 'Edge ${edge.id} missing key');
        continue;
      }
      validEdges.add(edge);
    }

    // ── Check 2: No duplicate node IDs ────────────────────────────────
    final seenIds = <String>{};
    final dedupedNodes = <GraphNodeData>[];
    for (final node in validNodes) {
      if (seenIds.contains(node.id)) {
        errors.add('Duplicate node ID: ${node.id} — keeping first');
        _logError('duplicate_node_id', node.id);
        continue;
      }
      seenIds.add(node.id);
      dedupedNodes.add(node);
    }

    // ── Check 3: No broken foreign keys ───────────────────────────────
    final nodeIds = dedupedNodes.map((n) => n.id).toSet();
    final validEdgesAfterFk = <GraphEdgeData>[];
    for (final edge in validEdges) {
      final sourceExists = nodeIds.contains(edge.sourceId);
      final targetExists = nodeIds.contains(edge.targetId);

      if (!sourceExists && !targetExists) {
        errors.add('Edge ${edge.id} references two non-existent nodes — skipping');
        _logError('broken_foreign_key', edge.id);
        continue;
      }

      if (!sourceExists) {
        orphanedNodeIds.add(edge.sourceId);
        errors.add('Edge ${edge.id} source ${edge.sourceId} not found');
        _logError('broken_foreign_key', '${edge.id}: source ${edge.sourceId}');
      }
      if (!targetExists) {
        orphanedNodeIds.add(edge.targetId);
        errors.add('Edge ${edge.id} target ${edge.targetId} not found');
        _logError('broken_foreign_key', '${edge.id}: target ${edge.targetId}');
      }

      // Keep edge even with one broken endpoint — UI will show ghost node
      validEdgesAfterFk.add(edge);
    }

    // ── Check 4: No circular relationships (DFS, max 20 hops) ─────────
    final circularEdges = _detectCycles(dedupedNodes, validEdgesAfterFk);
    for (final edgeId in circularEdges) {
      circularEdgeIds.add(edgeId);
      errors.add('Circular relationship detected at edge: $edgeId');
      _logError('circular_relationship', edgeId);
    }

    // ── Check 5: No kinship chains > 20 hops deep ─────────────────────
    final deepChains = _detectDeepChains(dedupedNodes, validEdgesAfterFk);
    for (final chainError in deepChains) {
      errors.add(chainError);
      _logError('deep_chain', chainError);
    }

    // Build clean data with bad records removed
    final cleanData = GraphData(
      nodes: dedupedNodes,
      edges: validEdgesAfterFk,
      isTruncated: data.isTruncated,
      totalCount: data.totalCount,
    );

    return DataValidationResult(
      cleanData: cleanData,
      orphanedNodeIds: orphanedNodeIds.toSet().toList(),
      circularEdgeIds: circularEdgeIds,
      errors: errors,
    );
  }

  // ── Cycle Detection (DFS) ───────────────────────────────────────────

  /// Detects circular relationships using DFS with max 20 hops.
  List<String> _detectCycles(
    List<GraphNodeData> nodes,
    List<GraphEdgeData> edges,
  ) {
    final circularEdgeIds = <String>[];
    final adjacency = <String, List<(String, String)>>{}; // nodeId → [(edgeId, targetId)]

    for (final edge in edges) {
      adjacency.putIfAbsent(edge.sourceId, () => []).add((edge.id, edge.targetId));
    }

    final visited = <String>{};
    final recursionStack = <String>{};
    final path = <String>[];

    bool dfs(String nodeId) {
      visited.add(nodeId);
      recursionStack.add(nodeId);
      path.add(nodeId);

      if (path.length > _maxHops) {
        // Chain too deep — flag the last edge
        return true;
      }

      final neighbors = adjacency[nodeId] ?? [];
      for (final (edgeId, targetId) in neighbors) {
        if (!visited.contains(targetId)) {
          if (dfs(targetId)) {
            circularEdgeIds.add(edgeId);
          }
        } else if (recursionStack.contains(targetId)) {
          // Found a cycle
          circularEdgeIds.add(edgeId);
        }
      }

      recursionStack.remove(nodeId);
      path.removeLast();
      return false;
    }

    for (final node in nodes) {
      if (!visited.contains(node.id)) {
        dfs(node.id);
      }
    }

    return circularEdgeIds.toSet().toList();
  }

  // ── Deep Chain Detection ────────────────────────────────────────────

  /// Detects kinship chains deeper than 20 hops.
  List<String> _detectDeepChains(
    List<GraphNodeData> nodes,
    List<GraphEdgeData> edges,
  ) {
    final errors = <String>[];
    final adjacency = <String, List<String>>{};

    for (final edge in edges) {
      adjacency.putIfAbsent(edge.sourceId, () => []).add(edge.targetId);
    }

    final depths = <String, int>{};

    int computeDepth(String nodeId, Set<String> visited) {
      if (depths.containsKey(nodeId)) return depths[nodeId]!;
      if (visited.contains(nodeId)) return 0; // Cycle

      visited.add(nodeId);
      final neighbors = adjacency[nodeId] ?? [];
      if (neighbors.isEmpty) {
        depths[nodeId] = 0;
        return 0;
      }

      int maxDepth = 0;
      for (final neighbor in neighbors) {
        final depth = computeDepth(neighbor, visited) + 1;
        if (depth > maxDepth) maxDepth = depth;
      }

      depths[nodeId] = maxDepth;
      visited.remove(nodeId);

      if (maxDepth > _maxHops) {
        errors.add('Kinship chain from $nodeId exceeds $_maxHops hops '
            '(${depths[nodeId]} hops deep)');
      }

      return maxDepth;
    }

    for (final node in nodes) {
      computeDepth(node.id, {});
    }

    return errors;
  }

  // ── Analytics Logging ───────────────────────────────────────────────

  void _logError(String errorType, String detail) {
    debugPrint('[DataValidator] $errorType: $detail');
    // Analytics tracker is optional; log to debug if not available
    _analyticsTracker?.trackGraphCrash(
      'DataValidationError',
      '$errorType: $detail',
      0,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// RIVERPOD PROVIDER
// ═══════════════════════════════════════════════════════════════════════

/// Provider for the [DataValidator].
final dataValidatorProvider = Provider<DataValidator>((ref) {
  final analyticsTracker = ref.read(analyticsTrackerProvider);
  return DataValidator(analyticsTracker: analyticsTracker);
});

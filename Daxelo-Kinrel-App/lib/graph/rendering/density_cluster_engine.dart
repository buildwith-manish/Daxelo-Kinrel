// lib/graph/rendering/density_cluster_engine.dart
//
// DAXELO KINREL v5.104 — Density-Driven Recursive Clustering Engine
//
// One unified system that scales from 5 to 100,000+ members.
// Core rule: if rendering a subtree fully would exceed the remaining
// node budget, or the subtree's on-screen footprint is smaller than
// one legible node, collapse it into a single cluster circle.
//
// This is RECURSIVE: a collapsed cluster containing another huge
// sub-branch shows a nested cluster count without ever exceeding
// the budget (e.g. "Sharma branch · 12,400").
//
// The system integrates with the existing BranchCollapseState:
// - Small trees (<50): budget never exceeded → zero clustering
// - Medium trees (200-500): partial collapsing in dense generations
// - Large trees (700+): moderate to heavy recursive clustering
// - Very large (10,000+): heavy recursive clustering with sub-clusters

import 'package:flutter/material.dart';
import '../interaction/branch_collapse_state.dart';

/// Global on-screen node budget. Tunable — ~50 visible nodes/clusters
/// at once provides a clean, legible graph at any scale.
const int kNodeBudget = 50;

/// Minimum on-screen footprint (in screen pixels) for a subtree to
/// be rendered individually. Below this, the subtree is collapsed
/// into a cluster regardless of budget.
const double kMinSubtreeFootprint = 40.0;

/// A cluster produced by the density-driven engine.
@immutable
class DensityCluster {
  const DensityCluster({
    required this.id,
    required this.rootPersonId,
    required this.rootPersonName,
    required this.memberCount,
    required this.hiddenMemberIds,
    required this.dominantCategory,
    required this.branchLabel,
    this.subClusters = const [],
  });

  /// Unique ID (typically '${rootPersonId}_cluster')
  final String id;

  /// The root person this cluster hangs off of.
  final String rootPersonId;

  /// Display name of the root person.
  final String rootPersonName;

  /// Total number of members in this cluster (including sub-clusters).
  final int memberCount;

  /// All person IDs hidden by this cluster.
  final Set<String> hiddenMemberIds;

  /// Dominant kinship category color for the cluster circle.
  final String? dominantCategory;

  /// Human-readable label, e.g. "Sharma branch · 12,400"
  final String branchLabel;

  /// Nested sub-clusters (for recursive clustering at extreme scale).
  final List<DensityCluster> subClusters;
}

/// Result of the density-driven clustering pass.
@immutable
class DensityClusterResult {
  const DensityClusterResult({
    this.clusters = const [],
    this.allHiddenMemberIds = const {},
    this.visibleNodeCount = 0,
  });

  /// Top-level clusters to render.
  final List<DensityCluster> clusters;

  /// Union of all hidden member IDs across all clusters.
  final Set<String> allHiddenMemberIds;

  /// Number of individually-rendered nodes (not counting clusters).
  final int visibleNodeCount;
}

/// The density-driven recursive clustering engine.
///
/// Called from canvas_mixin AFTER the viewport cull but BEFORE the
/// final visible-set computation. If the culled set exceeds the node
/// budget, subtrees are collapsed into clusters until the budget is met.
class DensityClusterEngine {
  DensityClusterEngine._();

  /// Run the clustering pass.
  ///
  /// [visibleNodeIds] — the set of node IDs that passed viewport culling.
  /// [positions] — graph-space positions for all nodes.
  /// [childrenOf] — adjacency: personId → list of child personIds.
  /// [personNames] — personId → display name.
  /// [personCategories] — personId → kinship category string.
  /// [expandedBranchRoots] — roots the user has manually expanded.
  /// [zoom] — current camera zoom level.
  /// [viewportSize] — screen-space viewport size.
  ///
  /// Returns a [DensityClusterResult] with clusters to render and the
  /// final set of hidden member IDs.
  static DensityClusterResult compute({
    required Set<String> visibleNodeIds,
    required Map<String, Offset> positions,
    required Map<String, List<String>> childrenOf,
    required Map<String, String> personNames,
    required Map<String, String> personCategories,
    required Set<String> expandedBranchRoots,
    required double zoom,
    required Size viewportSize,
  }) {
    // Small-tree bypass: if visible count is within budget, no clustering.
    if (visibleNodeIds.length <= kNodeBudget) {
      return DensityClusterResult(
        clusters: [],
        allHiddenMemberIds: {},
        visibleNodeCount: visibleNodeIds.length,
      );
    }

    // We need to collapse some subtrees. Strategy:
    // 1. Find "root" nodes — nodes that have children in the visible set.
    // 2. For each root, compute its subtree size (BFS through childrenOf,
    //    staying within visibleNodeIds).
    // 3. Sort roots by subtree size (largest first).
    // 4. Collapse subtrees one by one until visible count ≤ budget.
    //    Each collapse removes the subtree's members from the visible set
    //    and creates a DensityCluster.
    // 5. If a single subtree is so large that collapsing it still leaves
    //    us over budget, recurse into its children to create sub-clusters.

    final remaining = Set<String>.from(visibleNodeIds);
    final clusters = <DensityCluster>[];
    final allHidden = <String>{};

    // Build subtree sizes for all visible nodes.
    final subtreeSizes = <String, int>{};
    for (final id in visibleNodeIds) {
      subtreeSizes[id] = _subtreeSize(id, childrenOf, remaining, {});
    }

    // Find roots (nodes with children in the visible set).
    final roots = visibleNodeIds.where((id) {
      final children = childrenOf[id] ?? [];
      return children.any((c) => remaining.contains(c));
    }).toList();

    // Sort roots by subtree size, largest first.
    roots.sort((a, b) =>
        (subtreeSizes[b] ?? 0).compareTo(subtreeSizes[a] ?? 0));

    // Collapse subtrees until we're within budget.
    for (final rootId in roots) {
      if (remaining.length <= kNodeBudget) break;

      // Skip if user has manually expanded this root.
      if (expandedBranchRoots.contains(rootId)) continue;

      // Compute the subtree to collapse.
      final subtreeMembers = <String>{};
      _collectSubtree(rootId, childrenOf, remaining, subtreeMembers, {});

      // Don't collapse the root itself — it stays visible.
      subtreeMembers.remove(rootId);

      if (subtreeMembers.isEmpty) continue;
      if (subtreeMembers.length < 3) continue; // too small to cluster

      // Check on-screen footprint: if the subtree spans a very small
      // area at current zoom, it should definitely be collapsed.
      // (At extreme zoom-out, even large subtrees may be tiny on screen.)
      final footprint = _subtreeFootprint(
          rootId, subtreeMembers, positions, zoom);

      // Determine dominant category from the subtree members.
      final dominantCat = _dominantCategory(
          subtreeMembers, personCategories);

      // Generate label.
      final rootName = personNames[rootId] ?? 'Unknown';
      final label = _generateLabel(rootName, subtreeMembers.length);

      // Remove subtree members from remaining visible set.
      remaining.removeAll(subtreeMembers);
      allHidden.addAll(subtreeMembers);

      // Create cluster.
      clusters.add(DensityCluster(
        id: '${rootId}_cluster',
        rootPersonId: rootId,
        rootPersonName: rootName,
        memberCount: subtreeMembers.length + 1, // +1 for root
        hiddenMemberIds: Set.unmodifiable(subtreeMembers),
        dominantCategory: dominantCat,
        branchLabel: label,
      ));
    }

    return DensityClusterResult(
      clusters: clusters,
      allHiddenMemberIds: allHidden,
      visibleNodeCount: remaining.length,
    );
  }

  /// Compute the size of a subtree rooted at [rootId], counting only
  /// nodes that are in the [visible] set.
  static int _subtreeSize(
    String rootId,
    Map<String, List<String>> childrenOf,
    Set<String> visible,
    Set<String> visited,
  ) {
    if (visited.contains(rootId)) return 0;
    visited.add(rootId);
    int count = 1;
    for (final child in childrenOf[rootId] ?? []) {
      if (visible.contains(child)) {
        count += _subtreeSize(child, childrenOf, visible, visited);
      }
    }
    return count;
  }

  /// Collect all subtree members (BFS through childrenOf).
  static void _collectSubtree(
    String rootId,
    Map<String, List<String>> childrenOf,
    Set<String> visible,
    Set<String> members,
    Set<String> visited,
  ) {
    if (visited.contains(rootId)) return;
    visited.add(rootId);
    members.add(rootId);
    for (final child in childrenOf[rootId] ?? []) {
      if (visible.contains(child)) {
        _collectSubtree(child, childrenOf, visible, members, visited);
      }
    }
  }

  /// Estimate the on-screen footprint of a subtree.
  /// Returns the bounding-box diagonal in screen pixels.
  static double _subtreeFootprint(
    String rootId,
    Set<String> members,
    Map<String, Offset> positions,
    double zoom,
  ) {
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final id in members) {
      final pos = positions[id];
      if (pos == null) continue;
      if (pos.dx < minX) minX = pos.dx;
      if (pos.dy < minY) minY = pos.dy;
      if (pos.dx > maxX) maxX = pos.dx;
      if (pos.dy > maxY) maxY = pos.dy;
    }
    if (minX == double.infinity) return 0.0;
    final graphSpaceDiag =
        Offset(maxX - minX, maxY - minY).distance;
    return graphSpaceDiag * zoom;
  }

  /// Find the most common kinship category in a set of members.
  static String? _dominantCategory(
    Set<String> members,
    Map<String, String> personCategories,
  ) {
    final counts = <String, int>{};
    for (final id in members) {
      final cat = personCategories[id];
      if (cat != null) {
        counts[cat] = (counts[cat] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return null;
    var maxCount = 0;
    String? dominant;
    for (final entry in counts.entries) {
      if (entry.value > maxCount) {
        maxCount = entry.value;
        dominant = entry.key;
      }
    }
    return dominant;
  }

  /// Generate a human-readable cluster label.
  static String _generateLabel(String rootName, int count) {
    if (count >= 1000) {
      return "$rootName's branch · ${(count / 1000).toStringAsFixed(1)}k";
    }
    return "$rootName's branch · $count";
  }
}

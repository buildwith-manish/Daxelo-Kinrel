// lib/graph/engine/edge_dedup.dart
//
// DAXELO KINREL — Edge Deduplication & Multi-Relationship Resolution
//
// v64 (BUG-2 FIX): Centralized edge deduplication used by both
// family_graph.dart and family_graph_engine_view.dart.
//
// PROBLEM:
//   The Supabase `Relationship` table stores BOTH directions of every
//   relationship (A→B "father" AND B→A "child"). When the graph widget
//   iterates `flat.relationships` and draws one edge per row, the same
//   node pair gets TWO edges stacked directly on top of each other —
//   appearing as a single thick line or causing z-fighting on the
//   midpoint dot.
//
//   Worse, when a pair has multiple DISTINCT conceptual relationships
//   (e.g. a person who is BOTH a parent AND a spouse of the same
//   partner — rare but possible in blended families), the old dedup
//   picked whichever row came first from the DB, which could be the
//   wrong category.
//
// SOLUTION:
//   1. Group all edges by sorted node-pair key (so A→B and B→A land
//      in the same group).
//   2. Within each group, classify each edge by its KinshipEdgeCategory.
//   3. Pick the STRONGEST category (blood relations win over marriage,
//      marriage wins over extended). This is the "primary" edge.
//   4. If the group has multiple DISTINCT categories (e.g. parent AND
//      spouse), keep them as separate edges and tag each with a
//      `lateralOffset` so the painter can visually separate them.
//      Duplicate categories (e.g. two "father" rows from A→B and B→A
//      inverse) are collapsed into ONE edge — no offset needed.
//
// USAGE:
//   final deduped = EdgeDeduplicator.deduplicate(edges);
//   for (final entry in deduped) {
//     final path = _bezier(s, t, lateralOffset: entry.lateralOffset);
//     canvas.drawPath(path, paint);
//   }

import '../data/family_graph_repository.dart' show GraphEdgeData;
import '../../core/kinship/kinship_edge_style.dart';

/// A deduplicated edge entry. Carries the original [GraphEdgeData] plus
/// a [lateralOffset] that the painter should apply to separate this
/// edge from any other edges between the same node pair.
class DedupedEdge {
  const DedupedEdge({
    required this.edge,
    required this.lateralOffset,
    required this.parallelCount,
  });

  /// The primary edge data to render.
  final GraphEdgeData edge;

  /// Lateral offset (in dp) to apply to the bezier control points.
  /// 0.0 for solo edges (the only edge between this pair).
  /// Non-zero for edges that share a node pair with another edge —
  /// the painter shifts the curve sideways so both are visible.
  final double lateralOffset;

  /// How many edges share this node pair (including this one).
  /// 1 = solo, 2 = one other parallel edge, etc.
  final int parallelCount;

  /// Whether this edge shares its node pair with another rendered edge.
  bool get hasParallelEdge => parallelCount > 1;
}

/// Static helper that deduplicates a list of [GraphEdgeData].
class EdgeDeduplicator {
  EdgeDeduplicator._();

  /// Lateral offset (in dp) applied to parallel edges so they don't
  /// stack on top of each other. 18dp is enough to make two curves
  /// visually distinct without making either one hard to follow.
  static const double _parallelOffset = 18.0;

  /// Deduplicates [edges] by sorted node-pair, picking the strongest
  /// category for each pair and applying lateral offsets when a pair
  /// has multiple distinct conceptual relationships.
  ///
  /// Returns a list of [DedupedEdge] in the same order as the input
  /// (first occurrence of each pair wins the primary slot).
  static List<DedupedEdge> deduplicate(List<GraphEdgeData> edges) {
    if (edges.isEmpty) return const [];

    // ── Step 1: Group edges by sorted node-pair key ───────────────
    //
    // Each group contains all edges between the same two nodes,
    // regardless of direction (A→B and B→A land in the same group).
    final groups = <String, List<GraphEdgeData>>{};
    final groupOrder = <String>[]; // preserves first-seen order

    for (final edge in edges) {
      final pairKey = _pairKey(edge.sourceId, edge.targetId);
      if (!groups.containsKey(pairKey)) {
        groups[pairKey] = <GraphEdgeData>[];
        groupOrder.add(pairKey);
      }
      groups[pairKey]!.add(edge);
    }

    // ── Step 2: For each group, pick the strongest edge per category ──
    //
    // A group may contain:
    //   - Duplicate rows (A→B "father" + B→A "child") → both are
    //     "parent/child" category → collapse to ONE edge (the strongest).
    //   - Distinct categories (A→B "father" + A→B "spouse") → keep BOTH
    //     as separate edges, apply lateral offsets so both are visible.
    final result = <DedupedEdge>[];

    for (final pairKey in groupOrder) {
      final groupEdges = groups[pairKey]!;
      if (groupEdges.length == 1) {
        // Solo edge — no dedup or offset needed.
        result.add(DedupedEdge(
          edge: groupEdges.first,
          lateralOffset: 0.0,
          parallelCount: 1,
        ));
        continue;
      }

      // Group edges by category. We use the first edge per category
      // (in case the same category appears twice via A→B and B→A
      // inverse rows — those collapse into one).
      final categoryToEdge = <KinshipEdgeCategory, GraphEdgeData>{};
      for (final edge in groupEdges) {
        final cat = KinshipEdgeClassifier.classify(edge.relationshipKey);
        // Only keep the FIRST edge per category. The first row from the
        // DB is the user's original (forward) direction; subsequent
        // rows are usually the auto-created inverse and would render
        // the same curve in the opposite direction.
        if (!categoryToEdge.containsKey(cat)) {
          categoryToEdge[cat] = edge;
        }
      }

      // Sort the distinct categories by strength (strongest first).
      // Blood relations (parent/child/sibling) win over marriage
      // (spouse/inLaw), which wins over extended/indirect.
      final sortedCategories = categoryToEdge.keys.toList()
        ..sort(_compareCategoryStrength);

      final parallelCount = sortedCategories.length;
      final isParallel = parallelCount > 1;

      // Compute lateral offsets. For 2 parallel edges, offsets are
      // -_parallelOffset and +_parallelOffset (symmetric around 0).
      // For 3+, spread them evenly.
      for (var i = 0; i < sortedCategories.length; i++) {
        final cat = sortedCategories[i];
        final edge = categoryToEdge[cat]!;
        final offset = isParallel ? _offsetForIndex(i, parallelCount) : 0.0;
        result.add(DedupedEdge(
          edge: edge,
          lateralOffset: offset,
          parallelCount: parallelCount,
        ));
      }
    }

    return result;
  }

  /// Builds a sorted, direction-agnostic pair key for [a] and [b].
  /// `'A_B'` and `'B_A'` both produce `'A_B'` (assuming A < B lexically).
  static String _pairKey(String a, String b) {
    final ids = [a, b]..sort();
    return '${ids[0]}_${ids[1]}';
  }

  /// Computes the lateral offset for the [i]-th edge in a group of
  /// [total] parallel edges. Symmetric around 0.
  ///
  /// Examples:
  ///   total=2, i=0 → -_parallelOffset
  ///   total=2, i=1 → +_parallelOffset
  ///   total=3, i=0 → -_parallelOffset
  ///   total=3, i=1 → 0
  ///   total=3, i=2 → +_parallelOffset
  static double _offsetForIndex(int i, int total) {
    if (total <= 1) return 0.0;
    // Spread evenly across [-1, +1] then scale.
    final normalized = (i / (total - 1)) * 2 - 1; // -1..+1
    return normalized * _parallelOffset;
  }

  /// Strength comparator for [KinshipEdgeCategory].
  ///
  /// Stronger categories (closer blood relations) sort FIRST.
  /// Used to pick the "primary" edge when multiple categories share
  /// a node pair — the strongest one wins the centerline, weaker ones
  /// get lateral offsets.
  ///
  /// Strength order (high → low):
  ///   1. parent, child         (direct line of descent)
  ///   2. sibling               (same generation, blood)
  ///   3. grandparent           (line of descent, 2 hops)
  ///   4. auntUncle, cousin     (collateral blood)
  ///   5. spouse                (marriage, not blood)
  ///   6. inLaw                 (marriage-adjacent)
  ///   7. self                  (ego — rarely appears on edges)
  ///   8. extended              (step / god / guru — weakest)
  ///   9. indirect              (blocked-member path — weakest)
  static int _compareCategoryStrength(
    KinshipEdgeCategory a,
    KinshipEdgeCategory b,
  ) {
    return _categoryStrength(a).compareTo(_categoryStrength(b));
  }

  static int _categoryStrength(KinshipEdgeCategory cat) {
    switch (cat) {
      case KinshipEdgeCategory.parent:
      case KinshipEdgeCategory.child:
        return 100;
      case KinshipEdgeCategory.sibling:
        return 90;
      case KinshipEdgeCategory.grandparent:
        return 80;
      case KinshipEdgeCategory.auntUncle:
        return 70;
      case KinshipEdgeCategory.cousin:
        return 60;
      case KinshipEdgeCategory.spouse:
        return 50;
      case KinshipEdgeCategory.inLaw:
        return 40;
      case KinshipEdgeCategory.self:
        return 30;
      case KinshipEdgeCategory.extended:
        return 20;
      case KinshipEdgeCategory.indirect:
        return 10;
    }
  }
}

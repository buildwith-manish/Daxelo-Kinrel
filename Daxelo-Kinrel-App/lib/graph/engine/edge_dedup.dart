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
// v101 (BUG-1 FIX): Parent/child inverse pairs now collapse to ONE edge.
//   Previously, `classify('father')` → `KinshipEdgeCategory.parent` and
//   `classify('child')` → `KinshipEdgeCategory.child` were treated as
//   two DISTINCT categories (because they're different enum values),
//   so A→B "father" + B→A "child" rendered as TWO laterally-offset
//   curves instead of one straight line. Every parent/child pair in
//   the app was double-drawn.
//
//   The fix recognizes that `parent` and `child` are inverse wordings
//   of the SAME underlying relationship (the only asymmetric pair in
//   the category enum — sibling/spouse/grandparent inverses all
//   converge to the same category, but parent/child don't). When a
//   group has both `parent` and `child` categories AND the underlying
//   relationship keys are inverses of each other (e.g. 'father' ↔
//   'child', 'mother' ↔ 'child', 'son' ↔ 'parent'), they collapse
//   into ONE edge — keeping the parent-direction edge as primary
//   (matching the existing "first-seen wins" behavior, since the DB
//   typically stores the forward direction first).
//
//   A genuine second distinct relationship between the same pair
//   (e.g. parent AND spouse — a real blended-family case) still gets
//   a lateral offset and renders as two edges. The collapse only
//   applies when the two edges are inverses of the same relationship.
//
// USAGE:
//   final deduped = EdgeDeduplicator.deduplicate(edges);
//   for (final entry of deduped) {
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
      //
      // v101 (BUG-1 FIX): parent and child are inverse wordings of the
      // SAME underlying relationship, but classify() returns DIFFERENT
      // enum values for them (KinshipEdgeCategory.parent vs .child).
      // Without special handling, A→B "father" + B→A "child" would be
      // treated as two distinct categories and render as two parallel
      // edges — which is wrong; they are ONE relationship seen from
      // two sides. The same applies to 'mother'↔'child', 'son'↔'parent',
      // 'daughter'↔'parent', etc.
      //
      // We detect this case by checking, for each new edge, whether its
      // category is the inverse-pair counterpart of an already-present
      // category AND its relationship key is the inverse of the
      // already-present edge's key. If so, we collapse: keep the
      // parent-direction edge as primary (matching the "first-seen wins"
      // behavior the DB typically gives us — the forward direction is
      // usually inserted first by createRelationshipBetween).
      //
      // If the keys are NOT inverses (e.g. someone manually added both
      // 'father' AND 'mother' between the same pair, which is unusual
      // but not impossible), we do NOT collapse — both stay as distinct
      // edges. This is the conservative path: only collapse when we're
      // confident the two edges are the same relationship from two
      // perspectives.
      final categoryToEdge = <KinshipEdgeCategory, GraphEdgeData>{};
      for (final edge in groupEdges) {
        final cat = KinshipEdgeClassifier.classify(edge.relationshipKey);
        // Only keep the FIRST edge per category. The first row from the
        // DB is the user's original (forward) direction; subsequent
        // rows are usually the auto-created inverse and would render
        // the same curve in the opposite direction.
        if (!categoryToEdge.containsKey(cat)) {
          // v101 (BUG-1 FIX): Check if this edge is the inverse-pair
          // counterpart of an edge we already kept. If so, this is a
          // parent/child inverse pair (the only asymmetric category
          // pair). We collapse them into ONE entry — keeping the
          // parent-direction edge as primary (per the spec: "prefer the
          // parent direction edge as primary").
          final inverseCat = _inverseCategory(cat);
          if (inverseCat != null && categoryToEdge.containsKey(inverseCat)) {
            final existingEdge = categoryToEdge[inverseCat]!;
            if (_areInverseKeys(
              existingEdge.relationshipKey,
              edge.relationshipKey,
            )) {
              // Inverse pair detected. Prefer the parent-direction edge
              // as primary: if the new edge is parent-direction and
              // the existing one is child-direction, REPLACE it.
              // Otherwise keep the existing (already-parent) edge.
              if (cat == KinshipEdgeCategory.parent &&
                  inverseCat == KinshipEdgeCategory.child) {
                categoryToEdge.remove(inverseCat);
                categoryToEdge[cat] = edge;
              }
              // If the existing edge is already parent-direction, do
              // nothing — keep it as primary, skip this child-direction
              // edge.
              continue;
            }
          }
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

  /// v101 (BUG-1 FIX): Returns the inverse-pair counterpart of a
  /// [KinshipEdgeCategory], or null if the category is its own inverse.
  ///
  /// The only asymmetric pair in the enum is `parent` ↔ `child`.
  /// All other inverse relationship wordings converge to the SAME
  /// category (e.g. 'brother'/'sister'/'sibling' all → sibling;
  /// 'husband'/'wife' → spouse; 'grandfather'/'grandchild' → grandparent),
  /// so they collapse via the existing same-category dedup path and
  /// don't need this special handling.
  ///
  /// Returns:
  ///   - `KinshipEdgeCategory.child` for `KinshipEdgeCategory.parent`
  ///   - `KinshipEdgeCategory.parent` for `KinshipEdgeCategory.child`
  ///   - `null` for every other category (they're self-inverse)
  static KinshipEdgeCategory? _inverseCategory(KinshipEdgeCategory cat) {
    switch (cat) {
      case KinshipEdgeCategory.parent:
        return KinshipEdgeCategory.child;
      case KinshipEdgeCategory.child:
        return KinshipEdgeCategory.parent;
      case KinshipEdgeCategory.self:
      case KinshipEdgeCategory.sibling:
      case KinshipEdgeCategory.spouse:
      case KinshipEdgeCategory.grandparent:
      case KinshipEdgeCategory.auntUncle:
      case KinshipEdgeCategory.cousin:
      case KinshipEdgeCategory.inLaw:
      case KinshipEdgeCategory.extended:
      case KinshipEdgeCategory.indirect:
        return null;
    }
  }

  /// v101 (BUG-1 FIX): Returns true if [keyA] and [keyB] are inverse
  /// wordings of the same underlying relationship.
  ///
  /// This is a LOCAL inverse map covering the parent/child axis (the
  /// only asymmetric category pair). We do NOT import the full
  /// `_relationshipInverseMap` from `family_provider.dart` because:
  ///   1. `edge_dedup.dart` is a pure graph-layer module — it should
  ///      not depend on the family feature layer.
  ///   2. We only need to detect the parent↔child inverse direction
  ///      here; the other categories collapse via the existing
  ///      same-category path.
  ///
  /// The map covers all keys that classify() routes to `parent` or
  /// `child` (see `kinship_edge_style.dart`):
  ///   parent: 'father', 'mother', 'parent'
  ///   child:  'son', 'daughter', 'child',
  ///           'sons_wife', 'sons_husband', 'daughters_husband',
  ///           'daughters_wife', 'sons_partner', 'daughters_partner'
  ///
  /// Note: the children's-spouses keys ('sons_wife' etc.) classify as
  /// `child` but their semantic inverse is 'parent_in_law' (an in-law),
  /// NOT 'father'/'mother'. We deliberately do NOT list those here —
  /// they will NOT collapse with a 'father' edge even though both
  /// classify as parent/child, because their keys are not inverses.
  /// This is correct: a 'sons_wife' edge and a 'father' edge between
  /// the same pair are genuinely different relationships
  /// (daughter-in-law vs father), not the same relationship from two
  /// sides.
  static const Map<String, String> _parentChildInverseKeys = {
    'father': 'child',
    'mother': 'child',
    'parent': 'child',
    'child': 'parent',
    'son': 'parent',
    'daughter': 'parent',
  };

  /// Returns true if [keyA] and [keyB] are inverse wordings of the
  /// same parent/child relationship. Both keys must normalize via
  /// [_parentChildInverseKeys] and each must be the other's inverse.
  static bool _areInverseKeys(String keyA, String keyB) {
    final a = keyA.toLowerCase().trim();
    final b = keyB.toLowerCase().trim();
    final inverseOfA = _parentChildInverseKeys[a];
    return inverseOfA != null && inverseOfA == b;
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
  ///
  /// v102 (BUG-1 FIX): The comparator previously returned
  /// `_categoryStrength(a).compareTo(_categoryStrength(b))` which sorts
  /// in ASCENDING order — putting the WEAKEST category first (e.g.
  /// 'related' before 'father'). Dart's `List.sort()` is ascending by
  /// default. To sort strongest FIRST (descending), we reverse the
  /// comparison: `_categoryStrength(b).compareTo(_categoryStrength(a))`.
  static int _compareCategoryStrength(
    KinshipEdgeCategory a,
    KinshipEdgeCategory b,
  ) {
    // Reversed: strongest first (descending order).
    return _categoryStrength(b).compareTo(_categoryStrength(a));
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

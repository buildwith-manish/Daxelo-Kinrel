// lib/graph/interaction/indirect_relation_provider.dart
//
// DAXELO KINREL — v5.85: Viewer-Relative Indirect Relationship Detection
//
// Determines which nodes in the graph have an INDIRECT relationship to
// the current viewer (i.e., reachable through other people but NOT
// directly connected by a relationship line).
//
// Nodes with a direct relationship to the viewer (spouse, parent, child,
// sibling) do NOT get the badge. Nodes that are only reachable through
// 2+ hops (in-laws, aunts/uncles by marriage, etc.) DO get the badge.
//
// The badge is a VISUAL INDICATOR ONLY — tapping the node opens the
// existing relationship detail sheet which shows the computed term.

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Maximum relationship hops from the viewer for the indirect badge to
/// appear. Nodes beyond this distance show no badge.
///
/// - Hop 1 = direct relationship (spouse, parent, child, sibling) → NO badge
/// - Hop 2 = indirect (in-law, grandparent, aunt/uncle) → badge
/// - Hop 3 = further indirect (cousin, grand-aunt) → badge
/// - Hop 4+ = too distant → NO badge
const int kMaxIndirectBadgeDistance = 3;

/// Provider that computes the set of node IDs that have an INDIRECT
/// relationship to the current viewer (within kMaxIndirectBadgeDistance
/// hops, excluding direct/hop-1 connections).
///
/// Returns an empty set when:
/// - No viewer is resolved (viewerPersonId is null)
/// - The graph data is not yet loaded
/// - All nodes are either the viewer itself or directly connected
final indirectRelationIdsProvider =
    Provider.family<Set<String>, String>((ref, familyId) {
  // Watch the graph data + viewer ID so this recomputes when either changes
  final graphAsync = ref.watch(familyGraphProvider(familyId));
  final viewerPersonId =
      ref.watch(viewerPersonIdProvider(familyId)).valueOrNull;

  final graph = graphAsync.valueOrNull;
  if (graph == null || viewerPersonId == null) {
    return <String>{};
  }

  // Build adjacency list from the graph's relationships
  final adjacency = <String, Set<String>>{};
  for (final r in graph.relationships) {
    final isActive = r['isActive'] as bool? ?? true;
    if (!isActive) continue;
    final from = r['fromPersonId']?.toString();
    final to = r['toPersonId']?.toString();
    if (from != null && from.isNotEmpty && to != null && to.isNotEmpty) {
      adjacency.putIfAbsent(from, () => <String>{}).add(to);
      adjacency.putIfAbsent(to, () => <String>{}).add(from);
    }
  }

  // BFS from the viewer to find all reachable nodes + their distances
  final distances = <String, int>{};
  final queue = <String>[viewerPersonId];
  distances[viewerPersonId] = 0;

  while (queue.isNotEmpty) {
    final current = queue.removeAt(0);
    final currentDist = distances[current]!;
    if (currentDist >= kMaxIndirectBadgeDistance) continue;

    final neighbors = adjacency[current];
    if (neighbors == null) continue;
    for (final neighbor in neighbors) {
      if (!distances.containsKey(neighbor)) {
        distances[neighbor] = currentDist + 1;
        queue.add(neighbor);
      }
    }
  }

  // Indirect = distance >= 2 (not the viewer, not directly connected)
  // AND distance <= kMaxIndirectBadgeDistance
  final indirect = <String>{};
  for (final entry in distances.entries) {
    if (entry.key == viewerPersonId) continue;
    if (entry.value >= 2 && entry.value <= kMaxIndirectBadgeDistance) {
      indirect.add(entry.key);
    }
  }

  return indirect;
});

/// Provider for the one-time coach-mark flag. Tracks whether the user
/// has ever seen the indirect-relation badge coach-mark.
/// Stored in Supabase user metadata (persists across sessions/devices).
final hasSeenIndirectBadgeProvider = StateProvider<bool>((ref) {
  // Default: not seen. The app checks Supabase user metadata on init
  // and updates this. For now, default to false so the coach-mark
  // appears on first encounter.
  return false;
});

// lib/core/kinship/v3/path_canonicalizer.dart
//
// DAXELO KINREL — Deterministic Kinship Engine v3.0
// Path Canonicalizer
//
// Normalizes BFS paths before signature generation:
// 1. Remove cycles (never traverse the same node twice)
// 2. Remove backtracking (UP_PARENT followed by DOWN_CHILD on same node)
// 3. Normalize equivalent paths to one canonical form
// 4. Produce the shortest valid path

import 'kinship_signature.dart';

class PathCanonicalizer {
  PathCanonicalizer._();

  /// Canonicalizes a path: removes cycles, backtracking, and produces
  /// the shortest valid path.
  ///
  /// [path] is the list of TraversePrimitives from the BFS.
  /// [visitedNodes] is the list of node IDs visited at each step
  /// (parallel to path, with one extra entry for the starting node).
  static List<TraversePrimitive> canonicalize(
    List<TraversePrimitive> path,
    List<String> visitedNodes,
  ) {
    if (path.isEmpty) return path;

    // Step 1: Remove cycles — if the same node appears twice,
    // remove the sub-path between the two visits.
    final cycleRemoved = _removeCycles(path, visitedNodes);

    // Step 2: Remove backtracking — UP_PARENT immediately followed
    // by DOWN_CHILD (or vice versa) on the same node means we went
    // up to a parent then immediately back down to the same child.
    final backtrackRemoved = _removeBacktracking(cycleRemoved);

    return backtrackRemoved;
  }

  /// Removes cycle sub-paths. A cycle occurs when the same node ID
  /// appears more than once in [visitedNodes].
  ///
  /// When a cycle is found (e.g. A → B → C → B), the sub-path between
  /// the two visits is removed (keeping A → B, dropping B → C → B,
  /// and continuing from B onward).
  ///
  /// BFS already uses a visited set so cycles shouldn't occur, but
  /// this is a safety net for edge cases.
  static List<TraversePrimitive> _removeCycles(
    List<TraversePrimitive> path,
    List<String> visitedNodes,
  ) {
    if (path.length + 1 != visitedNodes.length) {
      return path; // Mismatch — return as-is
    }

    final seen = <String, int>{};
    for (int i = 0; i < visitedNodes.length; i++) {
      final node = visitedNodes[i];
      if (seen.containsKey(node)) {
        // Cycle detected: visitedNodes[seen[node]] == visitedNodes[i]
        // Remove edges from seen[node] to i-1 (the cycle edges).
        // Keep edges 0..seen[node]-1 (before the cycle)
        // and edges i..path.length-1 (after returning to the cycle node).
        final cycleStart = seen[node]!;
        final before = path.sublist(0, cycleStart);
        final after = path.sublist(i);
        final cleanPath = [...before, ...after];
        // Recursively check for more cycles
        final cleanVisited = [...visitedNodes.sublist(0, cycleStart + 1), ...visitedNodes.sublist(i + 1)];
        return _removeCycles(cleanPath, cleanVisited);
      }
      seen[node] = i;
    }

    return path; // No cycles found
  }

  /// Removes backtracking: UP_PARENT immediately followed by DOWN_CHILD
  /// (or vice versa) cancels out. Also SPOUSE followed by SPOUSE cancels.
  static List<TraversePrimitive> _removeBacktracking(
    List<TraversePrimitive> path,
  ) {
    if (path.length < 2) return path;

    final result = <TraversePrimitive>[];
    for (int i = 0; i < path.length; i++) {
      if (result.isNotEmpty) {
        final prev = result.last;
        final curr = path[i];

        // UP_PARENT + DOWN_CHILD = backtrack (went to parent, came back)
        if (prev == TraversePrimitive.upParent &&
            curr == TraversePrimitive.downChild) {
          result.removeLast();
          continue;
        }
        // DOWN_CHILD + UP_PARENT = backtrack (went to child, came back)
        if (prev == TraversePrimitive.downChild &&
            curr == TraversePrimitive.upParent) {
          result.removeLast();
          continue;
        }
        // SPOUSE + SPOUSE = went to spouse, came back
        if (prev == TraversePrimitive.spouse &&
            curr == TraversePrimitive.spouse) {
          result.removeLast();
          continue;
        }
      }
      result.add(path[i]);
    }

    return result;
  }
}

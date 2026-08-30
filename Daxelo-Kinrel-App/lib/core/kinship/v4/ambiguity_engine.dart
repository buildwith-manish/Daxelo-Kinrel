// lib/core/kinship/v4/ambiguity_engine.dart
//
// DAXELO-KINREL — v4.0 Ambiguity Engine (Phase 9)
//
// Detects when multiple valid kinship paths exist between two persons.
// When ambiguity exists, shows all valid paths + explanations so the
// user can confirm. Never silently chooses.

import '../v3/kinship_signature.dart';
import '../../../core/services/graph_layout_service.dart' show GraphPerson;

/// The result of an ambiguity check.
class AmbiguityResult {
  final bool isAmbiguous;
  final List<AmbiguityPath> paths;

  const AmbiguityResult({
    required this.isAmbiguous,
    required this.paths,
  });

  static const AmbiguityResult empty = AmbiguityResult(isAmbiguous: false, paths: []);
}

/// A single valid path through the graph.
class AmbiguityPath {
  final List<TraversePrimitive> path;
  final List<String> visitedNodes;
  final String pathPattern;
  final String description;

  const AmbiguityPath({
    required this.path,
    required this.visitedNodes,
    required this.pathPattern,
    required this.description,
  });
}

class AmbiguityEngine {
  AmbiguityEngine._();

  /// Checks if multiple valid shortest paths exist between [fromId] and [toId].
  /// Returns all paths of the minimum length.
  static AmbiguityResult check({
    required String fromId,
    required String toId,
    required List<GraphPerson> persons,
    required List<({String fromId, String toId, String type})> relationships,
    int maxDepth = 8,
  }) {
    if (fromId == toId) return AmbiguityResult.empty;

    // Build adjacency list
    final adjacency = _buildAdjacency(persons, relationships);
    if (adjacency.isEmpty) return AmbiguityResult.empty;

    // Find ALL shortest paths using modified BFS
    final allPaths = _findAllShortestPaths(fromId, toId, adjacency, maxDepth);

    if (allPaths.length <= 1) {
      return AmbiguityResult(isAmbiguous: false, paths: []);
    }

    // Multiple paths exist — build descriptions
    final ambiguityPaths = allPaths.map((result) {
      final pathPattern = KinshipSignature.buildPattern(result.path);
      final description = _describePath(result.path, result.visited, persons);
      return AmbiguityPath(
        path: result.path,
        visitedNodes: result.visited,
        pathPattern: pathPattern,
        description: description,
      );
    }).toList();

    return AmbiguityResult(isAmbiguous: true, paths: ambiguityPaths);
  }

  /// Finds ALL shortest paths between two nodes.
  static List<_PathResult> _findAllShortestPaths(
    String fromId,
    String toId,
    Map<String, List<_AdjEntry>> adjacency,
    int maxDepth,
  ) {
    // BFS level by level, collecting all paths that reach the target
    // at the same (minimum) depth.
    var currentLevel = [_PathResult(path: [], visited: [fromId])];
    final visited = {fromId};

    for (int depth = 0; depth < maxDepth; depth++) {
      final nextLevel = <_PathResult>[];
      final levelVisited = <String>{};

      for (final state in currentLevel) {
        final neighbors = adjacency[state.visited.last] ?? [];
        for (final n in neighbors) {
          if (n.nodeId == toId) {
            // Found a path to target!
            nextLevel.add(_PathResult(
              path: [...state.path, n.primitive],
              visited: [...state.visited, n.nodeId],
            ));
          } else if (!visited.contains(n.nodeId) && !state.visited.contains(n.nodeId)) {
            levelVisited.add(n.nodeId);
            nextLevel.add(_PathResult(
              path: [...state.path, n.primitive],
              visited: [...state.visited, n.nodeId],
            ));
          }
        }
      }

      // Check if any path reached the target
      final reachingPaths = nextLevel
          .where((p) => p.visited.last == toId)
          .toList();

      if (reachingPaths.isNotEmpty) {
        return reachingPaths;
      }

      visited.addAll(levelVisited);
      currentLevel = nextLevel;
    }

    return []; // No path found
  }

  static Map<String, List<_AdjEntry>> _buildAdjacency(
    List<GraphPerson> persons,
    List<({String fromId, String toId, String type})> relationships,
  ) {
    final adjacency = <String, List<_AdjEntry>>{};

    for (final rel in relationships) {
      final type = rel.type.toLowerCase();
      TraversePrimitive? forward, reverse;

      switch (type) {
        case 'parent': case 'father': case 'mother':
          forward = TraversePrimitive.upParent;
          reverse = TraversePrimitive.downChild;
          break;
        case 'spouse': case 'husband': case 'wife':
          forward = TraversePrimitive.spouse;
          reverse = TraversePrimitive.spouse;
          break;
        case 'adoptive_parent':
          forward = TraversePrimitive.upAdoptiveParent;
          reverse = TraversePrimitive.downChild;
          break;
        case 'step_parent': case 'step_father': case 'step_mother':
        case 'stepfather': case 'stepmother':
          forward = TraversePrimitive.upStepParent;
          reverse = TraversePrimitive.downChild;
          break;
        case 'child': case 'son': case 'daughter':
          forward = TraversePrimitive.downChild;
          reverse = TraversePrimitive.upParent;
          break;
        default:
          continue;
      }

      adjacency.putIfAbsent(rel.fromId, () => []);
      adjacency[rel.fromId]!.add(_AdjEntry(nodeId: rel.toId, primitive: forward));
      adjacency.putIfAbsent(rel.toId, () => []);
      adjacency[rel.toId]!.add(_AdjEntry(nodeId: rel.fromId, primitive: reverse));
    }

    return adjacency;
  }

  static String _describePath(
    List<TraversePrimitive> path,
    List<String> visited,
    List<GraphPerson> persons,
  ) {
    final parts = <String>[];
    for (int i = 0; i < path.length; i++) {
      final nextId = i + 1 < visited.length ? visited[i + 1] : '';
      final person = persons.where((p) => p.id == nextId).firstOrNull;
      final name = person?.name ?? '?';
      parts.add('${_primitiveLabel(path[i])} → $name');
    }
    return parts.join(' → ');
  }

  static String _primitiveLabel(TraversePrimitive p) {
    switch (p) {
      case TraversePrimitive.upParent: return 'Parent';
      case TraversePrimitive.downChild: return 'Child';
      case TraversePrimitive.spouse: return 'Spouse';
      case TraversePrimitive.upAdoptiveParent: return 'Adoptive Parent';
      case TraversePrimitive.upStepParent: return 'Step Parent';
    }
  }
}

class _AdjEntry {
  final String nodeId;
  final TraversePrimitive primitive;
  const _AdjEntry({required this.nodeId, required this.primitive});
}

class _PathResult {
  final List<TraversePrimitive> path;
  final List<String> visited;
  const _PathResult({required this.path, required this.visited});
}

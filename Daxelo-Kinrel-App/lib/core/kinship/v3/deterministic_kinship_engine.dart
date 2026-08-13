// lib/core/kinship/v3/deterministic_kinship_engine.dart
//
// DAXELO KINREL — Deterministic Kinship Engine v3.0
//
// A genealogy-grade deterministic kinship engine that derives all
// 5,396+ kinship terms from only FOUR fundamental relationship edges:
//   parent, spouse, adoptive_parent, step_parent
//
// Architecture:
//   1. BFS finds the shortest path between Person A and Person B
//   2. Path Canonicalizer removes cycles + backtracking
//   3. Kinship Signature Builder creates a runtime-only structured representation
//   4. Vocabulary Mapper translates the signature to a human-readable term
//
// 100% deterministic: same graph + same Person A + same Person B =
// same result. Always. No ML, no AI, no confidence scores, no guessing.
//
// Max traversal depth: 8 (covers great-great-great-grandparents,
// third cousins, and removed cousins).

import '../../../core/services/graph_layout_service.dart' show GraphPerson;
import 'kinship_signature.dart';
import 'path_canonicalizer.dart';
import 'vocabulary_mapper.dart';

/// A neighbor entry in the adjacency list.
typedef AdjacencyEntry = ({String nodeId, TraversePrimitive primitive});

/// A single step in the BFS traversal path.
class BfsStep {
  final String nodeId;
  final TraversePrimitive primitive;

  const BfsStep({required this.nodeId, required this.primitive});
}

/// The result of a kinship resolution.
class KinshipResult {
  final String term;           // Human-readable term (e.g. "Grandfather")
  final String? fundamentalEdge; // The edge to store (e.g. "parent") or null if derived
  final KinshipSignature signature;
  final bool isDerived;        // True if the term is derived (not a fundamental edge)

  const KinshipResult({
    required this.term,
    this.fundamentalEdge,
    required this.signature,
    required this.isDerived,
  });
}

class DeterministicKinshipEngine {
  DeterministicKinshipEngine._();
  static final DeterministicKinshipEngine instance =
      DeterministicKinshipEngine._();

  static const int _maxDepth = 8;

  /// Session-only signature cache. Never persisted.
  /// Key: "familyId:personAId:personBId"
  final Map<String, KinshipSignature> _cache = {};

  /// Resolves the kinship between [fromPersonId] and [toPersonId]
  /// using the family graph.
  ///
  /// Returns null if:
  /// - fromPersonId == toPersonId (self)
  /// - No path exists within max depth 8
  KinshipResult? resolve({
    required String fromPersonId,
    required String toPersonId,
    required List<GraphPerson> persons,
    required List<({String fromId, String toId, String type})> relationships,
  }) {
    // Self — no resolution needed
    if (fromPersonId == toPersonId) return null;

    // Check cache
    final cacheKey = '${fromPersonId}_$toPersonId';
    if (_cache.containsKey(cacheKey)) {
      final sig = _cache[cacheKey]!;
      return _buildResult(sig, toPersonId, persons);
    }

    // Build adjacency list from fundamental edges only
    // (parent, spouse, adoptive_parent, step_parent — ignore derived keys)
    final adjacency = _buildAdjacencyList(persons, relationships);

    // BFS to find shortest path
    final bfsResult = _bfs(fromPersonId, toPersonId, adjacency);
    if (bfsResult == null) return null; // No path found

    // Canonicalize the path
    final canonicalPath = PathCanonicalizer.canonicalize(
      bfsResult.path,
      bfsResult.visitedNodes,
    );

    if (canonicalPath.isEmpty) return null;

    // Build kinship signature
    final signature = _buildSignature(
      canonicalPath,
      fromPersonId,
      toPersonId,
      persons,
      adjacency,
    );

    // Cache the signature
    _cache[cacheKey] = signature;

    return _buildResult(signature, toPersonId, persons);
  }

  /// Builds an adjacency list from the stored relationships.
  /// Only processes fundamental edge types:
  ///   parent, spouse, adoptive_parent, step_parent
  ///
  /// For each stored edge, creates TWO traversal entries:
  ///   - Forward (e.g. parent A→B means B is A's parent → UP_PARENT from A)
  ///   - Reverse (e.g. parent A→B means A is B's child → DOWN_CHILD from B)
  Map<String, List<AdjacencyEntry>> _buildAdjacencyList(
    List<GraphPerson> persons,
    List<({String fromId, String toId, String type})> relationships,
  ) {
    final adjacency = <String, List<({String nodeId, TraversePrimitive primitive})>>{};

    for (final rel in relationships) {
      final type = rel.type.toLowerCase();

      TraversePrimitive? forwardPrim;
      TraversePrimitive? reversePrim;

      // Determine primitives based on edge type
      // Stored: from=A, to=B, type=X means "A's X is B"
      // e.g. parent: A's parent is B → from A, go UP_PARENT to B
      //                 from B, go DOWN_CHILD to A
      switch (type) {
        case 'parent':
        case 'father':
        case 'mother':
          forwardPrim = TraversePrimitive.upParent;    // A → B (up to parent)
          reversePrim = TraversePrimitive.downChild;    // B → A (down to child)
          break;
        case 'spouse':
        case 'husband':
        case 'wife':
          forwardPrim = TraversePrimitive.spouse;       // A → B (spouse)
          reversePrim = TraversePrimitive.spouse;       // B → A (spouse)
          break;
        case 'adoptive_parent':
        case 'adoptive_father':
        case 'adoptive_mother':
          forwardPrim = TraversePrimitive.upAdoptiveParent;
          reversePrim = TraversePrimitive.downChild; // treat as child for traversal
          break;
        case 'step_parent':
        case 'step_father':
        case 'step_mother':
        case 'stepfather':
        case 'stepmother':
          forwardPrim = TraversePrimitive.upStepParent;
          reversePrim = TraversePrimitive.downChild; // treat as child for traversal
          break;
        // Child edges (inverse of parent — some older data may store these)
        case 'child':
        case 'son':
        case 'daughter':
          forwardPrim = TraversePrimitive.downChild;   // A → B (down to child)
          reversePrim = TraversePrimitive.upParent;     // B → A (up to parent)
          break;
        default:
          // Skip non-fundamental types (uncle, cousin, etc.)
          // These are DERIVED and should not be used for traversal.
          continue;
      }

      // Add forward edge: from → to
      adjacency.putIfAbsent(rel.fromId, () => []);
      adjacency[rel.fromId]!.add((nodeId: rel.toId, primitive: forwardPrim));

      // Add reverse edge: to → from
      adjacency.putIfAbsent(rel.toId, () => []);
      adjacency[rel.toId]!.add((nodeId: rel.fromId, primitive: reversePrim));
    }

    return adjacency;
  }

  /// BFS to find the shortest path between [fromId] and [toId].
  /// Returns the path (list of primitives) + visited nodes.
  _BfsResult? _bfs(
    String fromId,
    String toId,
    Map<String, List<AdjacencyEntry>> adjacency,
  ) {
    final queue = <_BfsState>[
      _BfsState(nodeId: fromId, path: [], visited: [fromId]),
    ];
    final visited = {fromId};

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);

      if (current.nodeId == toId && current.path.isNotEmpty) {
        return _BfsResult(path: current.path, visitedNodes: current.visited);
      }

      if (current.path.length >= _maxDepth) continue;

      final neighbors = adjacency[current.nodeId] ?? [];
      for (final n in neighbors) {
        if (visited.contains(n.nodeId)) continue;
        visited.add(n.nodeId);
        queue.add(_BfsState(
          nodeId: n.nodeId,
          path: [...current.path, n.primitive],
          visited: [...current.visited, n.nodeId],
        ));
      }
    }

    return null; // No path found
  }

  /// Builds a KinshipSignature from the canonical path.
  KinshipSignature _buildSignature(
    List<TraversePrimitive> path,
    String fromPersonId,
    String toPersonId,
    List<GraphPerson> persons,
    Map<String, List<AdjacencyEntry>> adjacency,
  ) {
    // Calculate generation delta
    int upCount = 0;
    int downCount = 0;
    int spouseCount = 0;

    for (final p in path) {
      switch (p) {
        case TraversePrimitive.upParent:
        case TraversePrimitive.upAdoptiveParent:
        case TraversePrimitive.upStepParent:
          upCount++;
          break;
        case TraversePrimitive.downChild:
          downCount++;
          break;
        case TraversePrimitive.spouse:
          spouseCount++;
          break;
      }
    }

    final generationDelta = downCount - upCount;

    // Determine path pattern
    final pathPattern = KinshipSignature.buildPattern(path);

    // Determine side (paternal/maternal/none)
    final side = _detectSide(path, fromPersonId, persons, adjacency);

    // Determine consanguinity
    final consanguinity = _detectConsanguinity(path, fromPersonId, toPersonId, persons, adjacency);

    // Determine gender of target person
    final target = persons.where((p) => p.id == toPersonId).firstOrNull;
    final gender = target?.gender?.toLowerCase() == 'female' ? 'female' : 'male';

    // Determine seniority (placeholder — requires birth date comparison)
    final seniority = 'none';

    // Determine removal (for cousins)
    int removal = 0;
    if (upCount > 0 && downCount > 0) {
      removal = (upCount - downCount).abs();
    }

    // Determine double kinship (multiple valid paths exist)
    final doubleKinship = false; // Simplified — would need multi-path analysis

    return KinshipSignature(
      generationDelta: generationDelta,
      pathPattern: pathPattern,
      side: side,
      consanguinity: consanguinity,
      genderAnchor: gender,
      seniority: seniority,
      removal: removal,
      doubleKinship: doubleKinship,
    );
  }

  /// Detects which side of the family the relationship belongs to.
  /// Based on the first UP_PARENT link from the starting person.
  FamilySide _detectSide(
    List<TraversePrimitive> path,
    String fromPersonId,
    List<GraphPerson> persons,
    Map<String, List<({String nodeId, TraversePrimitive primitive})}> adjacency,
  ) {
    // Find the first UP_PARENT in the path
    // Then check if that parent is male (paternal) or female (maternal)
    // For simplicity, if the path starts with SPOUSE, side = none

    if (path.isEmpty) return FamilySide.none;
    if (path.first == TraversePrimitive.spouse) return FamilySide.none;

    // Walk the path to find the first parent
    String currentNode = fromPersonId;
    for (final prim in path) {
      if (prim == TraversePrimitive.upParent ||
          prim == TraversePrimitive.upAdoptiveParent ||
          prim == TraversePrimitive.upStepParent) {
        // Find the parent node
        final neighbors = adjacency[currentNode] ?? [];
        final parentEntry = neighbors.firstWhere(
          (n) => n.primitive == prim,
          orElse: () => (nodeId: '', primitive: prim),
        );
        if (parentEntry.nodeId.isNotEmpty) {
          final parent = persons.where((p) => p.id == parentEntry.nodeId).firstOrNull;
          if (parent?.gender?.toLowerCase() == 'female') {
            return FamilySide.maternal;
          }
          return FamilySide.paternal;
        }
        break;
      }
      // Move to next node
      final neighbors = adjacency[currentNode] ?? [];
      final entry = neighbors.firstWhere(
        (n) => n.primitive == prim,
        orElse: () => (nodeId: '', primitive: prim),
      );
      if (entry.nodeId.isEmpty) break;
      currentNode = entry.nodeId;
    }

    return FamilySide.none;
  }

  /// Detects consanguinity type (blood/half/step/adoptive/inLaw).
  Consanguinity _detectConsanguinity(
    List<TraversePrimitive> path,
    String fromPersonId,
    String toPersonId,
    List<GraphPerson> persons,
    Map<String, List<({String nodeId, TraversePrimitive primitive})}> adjacency,
  ) {
    // If path starts with SPOUSE → inLaw (for in-law relationships)
    if (path.isNotEmpty && path.first == TraversePrimitive.spouse) {
      // Check if the rest of the path is just SPOUSE (direct spouse)
      if (path.length == 1 && path[0] == TraversePrimitive.spouse) {
        return Consanguinity.blood; // Spouse is not "blood" but not inLaw either
      }
      return Consanguinity.inLaw;
    }

    // Check for step/adoptive in the path
    if (path.any((p) => p == TraversePrimitive.upStepParent)) {
      return Consanguinity.step;
    }
    if (path.any((p) => p == TraversePrimitive.upAdoptiveParent)) {
      return Consanguinity.adoptive;
    }

    // For sibling detection (UP_PARENT_DOWN_CHILD), check shared parents
    if (path.length == 2 &&
        path[0] == TraversePrimitive.upParent &&
        path[1] == TraversePrimitive.downChild) {
      // Count shared parents
      final parentsOfA = _getParents(fromPersonId, adjacency);
      final parentsOfB = _getParents(toPersonId, adjacency);
      final shared = parentsOfA.intersection(parentsOfB);

      if (shared.length >= 2) return Consanguinity.blood;
      if (shared.length == 1) return Consanguinity.half;
      return Consanguinity.step;
    }

    return Consanguinity.blood; // Default for blood relationships
  }

  /// Gets the set of parent IDs for [personId].
  Set<String> _getParents(
    String personId,
    Map<String, List<AdjacencyEntry>> adjacency,
  ) {
    final parents = <String>{};
    final neighbors = adjacency[personId] ?? [];
    for (final n in neighbors) {
      if (n.primitive == TraversePrimitive.upParent ||
          n.primitive == TraversePrimitive.upAdoptiveParent ||
          n.primitive == TraversePrimitive.upStepParent) {
        parents.add(n.nodeId);
      }
    }
    return parents;
  }

  /// Builds the final KinshipResult from a signature.
  KinshipResult _buildResult(
    KinshipSignature signature,
    String toPersonId,
    List<GraphPerson> persons,
  ) {
    final term = VocabularyMapper.resolve(signature);

    // Determine if this is a fundamental edge or derived
    final isDerived = signature.pathPattern != 'UP_PARENT' &&
        signature.pathPattern != 'SPOUSE' &&
        signature.pathPattern != 'UP_ADOPTIVE_PARENT' &&
        signature.pathPattern != 'UP_STEP_PARENT' &&
        signature.pathPattern != 'DOWN_CHILD';

    // For fundamental edges, determine the edge type to store
    String? fundamentalEdge;
    if (!isDerived) {
      if (signature.pathPattern == 'UP_PARENT' ||
          signature.pathPattern == 'DOWN_CHILD') {
        fundamentalEdge = 'parent';
      } else if (signature.pathPattern == 'SPOUSE') {
        fundamentalEdge = 'spouse';
      } else if (signature.pathPattern == 'UP_ADOPTIVE_PARENT') {
        fundamentalEdge = 'adoptive_parent';
      } else if (signature.pathPattern == 'UP_STEP_PARENT') {
        fundamentalEdge = 'step_parent';
      }
    }

    return KinshipResult(
      term: term,
      fundamentalEdge: fundamentalEdge,
      signature: signature,
      isDerived: isDerived,
    );
  }

  /// Invalidates cache entries containing [personId].
  void invalidatePerson(String personId) {
    _cache.removeWhere((key, _) => key.contains(personId));
  }

  /// Clears the entire cache.
  void clearCache() {
    _cache.clear();
  }
}

/// Internal BFS state.
class _BfsState {
  final String nodeId;
  final List<TraversePrimitive> path;
  final List<String> visited;

  const _BfsState({
    required this.nodeId,
    required this.path,
    required this.visited,
  });
}

/// Internal BFS result.
class _BfsResult {
  final List<TraversePrimitive> path;
  final List<String> visitedNodes;

  const _BfsResult({required this.path, required this.visitedNodes});
}

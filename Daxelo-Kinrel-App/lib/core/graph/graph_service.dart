import 'dart:convert';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import '../kinship/kinship_service.dart';
import '../database/isar_database.dart';
import '../database/app_database.dart';

/// Person node in the family graph
class GraphPerson {
  const GraphPerson({
    required this.id,
    required this.name,
    this.relationship,
    required this.generation,
    this.isDeceased = false,
    this.deletedAt,
  });

  final String id;
  final String name;
  final String? relationship;
  final int generation;
  final bool isDeceased;
  final String? deletedAt;
}

/// Tree node for hierarchical family display
class TreeNode {
  const TreeNode({
    required this.person,
    this.spouse,
    this.children = const [],
    this.isCollapsed = false,
  });

  final GraphPerson person;
  final GraphPerson? spouse;
  final List<TreeNode> children;
  final bool isCollapsed;

  /// Create a copy with modified collapse state
  TreeNode copyWith({bool? isCollapsed, List<TreeNode>? children}) {
    return TreeNode(
      person: person,
      spouse: spouse,
      children: children ?? this.children,
      isCollapsed: isCollapsed ?? this.isCollapsed,
    );
  }
}

/// Path step in a relationship path
class PathStep {
  const PathStep({
    required this.personId,
    required this.personName,
    required this.type,
    required this.direction,
  });

  final String personId;
  final String personName;
  final String type;
  final String direction;

  Map<String, dynamic> toJson() => {
        'personId': personId,
        'personName': personName,
        'type': type,
        'direction': direction,
      };

  factory PathStep.fromJson(Map<String, dynamic> json) {
    return PathStep(
      personId: json['personId'] as String? ?? '',
      personName: json['personName'] as String? ?? '',
      type: json['type'] as String? ?? '',
      direction: json['direction'] as String? ?? '',
    );
  }
}

/// Result of a path search
class PathResult {
  const PathResult({
    required this.path,
    required this.length,
    required this.relationshipDescription,
    this.localizedDescription,
    this.composedKinshipTerm,
  });

  final List<PathStep> path;
  final int length;
  final String relationshipDescription;
  final String? localizedDescription;
  final String? composedKinshipTerm;
}

/// Edge in the adjacency list
class Edge {
  Edge(this.targetId, this.type, this.direction);

  final String targetId;
  final String type;
  final String direction;
}

/// Inverse relationship type mapping
const Map<String, String> inverseTypeMap = {
  'father': 'child',
  'mother': 'child',
  'child': 'parent',
  'son': 'parent',
  'daughter': 'parent',
  'brother': 'sibling',
  'sister': 'sibling',
  'spouse': 'spouse',
  'husband': 'wife',
  'wife': 'husband',
  'grandfather': 'grandchild',
  'grandmother': 'grandchild',
  'grandchild': 'grandparent',
  'uncle': 'nephew_or_niece',
  'aunt': 'nephew_or_niece',
  'nephew': 'uncle_or_aunt',
  'niece': 'uncle_or_aunt',
  'cousin': 'cousin',
  'father_in_law': 'child_in_law',
  'mother_in_law': 'child_in_law',
  'son_in_law': 'parent_in_law',
  'daughter_in_law': 'parent_in_law',
  'brother_in_law': 'sibling_in_law',
  'sister_in_law': 'sibling_in_law',
  'step_father': 'step_child',
  'step_mother': 'step_child',
  'step_brother': 'step_sibling',
  'step_sister': 'step_sibling',
};

/// Kinship term mapping for relationship composition.
/// Maps single-step relationship types to their kinship terms.
const Map<String, String> kinshipTermMap = {
  'father': 'father',
  'mother': 'mother',
  'parent': 'parent',
  'child': 'child',
  'son': 'son',
  'daughter': 'daughter',
  'brother': 'brother',
  'sister': 'sister',
  'sibling': 'sibling',
  'spouse': 'spouse',
  'husband': 'husband',
  'wife': 'wife',
  'grandfather': 'grandfather',
  'grandmother': 'grandmother',
  'grandparent': 'grandparent',
  'grandchild': 'grandchild',
  'uncle': 'uncle',
  'aunt': 'aunt',
  'nephew': 'nephew',
  'niece': 'niece',
  'cousin': 'cousin',
  'father_in_law': 'father-in-law',
  'mother_in_law': 'mother-in-law',
  'son_in_law': 'son-in-law',
  'daughter_in_law': 'daughter-in-law',
  'brother_in_law': 'brother-in-law',
  'sister_in_law': 'sister-in-law',
  'step_father': 'step-father',
  'step_mother': 'step-mother',
  'step_brother': 'step-brother',
  'step_sister': 'step-sister',
};

/// Family graph traversal service
class GraphService {
  GraphService(this._kinshipService);

  final KinshipService _kinshipService;

  /// Get inverse relationship type
  String inverseType(String type) => inverseTypeMap[type] ?? type;

  /// Build adjacency list from relationships
  Map<String, List<Edge>> buildAdjacencyList(
    List<GraphPerson> persons,
    List<({String fromId, String toId, String type})> relationships,
  ) {
    final activePersonIds = persons
        .where((p) => p.deletedAt == null)
        .map((p) => p.id)
        .toSet();

    final adjacency = <String, List<Edge>>{};

    for (final person in persons) {
      if (person.deletedAt != null) continue;
      adjacency[person.id] = [];
    }

    for (final rel in relationships) {
      if (!activePersonIds.contains(rel.fromId) ||
          !activePersonIds.contains(rel.toId)) {
        continue;
      }

      adjacency[rel.fromId]?.add(Edge(rel.toId, rel.type, 'from'));
      adjacency[rel.toId]?.add(Edge(rel.fromId, inverseType(rel.type), 'to'));
    }

    return adjacency;
  }

  // ── Tree Building ────────────────────────────────────────────────

  /// Convert flat graph data into a hierarchical [TreeNode] structure.
  ///
  /// The algorithm:
  /// 1. Find spouse of root person
  /// 2. Find children of root + spouse
  /// 3. Recursively build subtrees for each child
  /// 4. Handle cycles (visited set)
  /// 5. Return TreeNode with person, spouse, and children
  TreeNode? buildTree({
    required List<GraphPerson> persons,
    required List<({String fromId, String toId, String type})> relationships,
    required String rootPersonId,
  }) {
    final personMap = {for (final p in persons) p.id: p};
    if (!personMap.containsKey(rootPersonId)) return null;

    final adjacency = buildAdjacencyList(persons, relationships);
    final visited = <String>{};

    TreeNode buildNode(String personId) {
      visited.add(personId);
      final person = personMap[personId]!;

      // Find spouse
      GraphPerson? spouse;
      final spouseEdges = adjacency[personId]?.where((e) =>
          e.type == 'spouse' ||
          e.type == 'husband' ||
          e.type == 'wife');
      if (spouseEdges != null && spouseEdges.isNotEmpty) {
        final spouseId = spouseEdges.first.targetId;
        if (!visited.contains(spouseId) && personMap.containsKey(spouseId)) {
          visited.add(spouseId);
          spouse = personMap[spouseId];
        }
      }

      // Find children — children are edges with type child/son/daughter
      // going FROM parent TO child, or edges with type parent/father/mother
      // going TO this person (meaning this person is the child of that edge)
      final childIds = <String>{};

      // Direct child edges from this person
      for (final edge in adjacency[personId] ?? []) {
        if (['child', 'son', 'daughter'].contains(edge.type) &&
            !visited.contains(edge.targetId) &&
            personMap.containsKey(edge.targetId)) {
          childIds.add(edge.targetId);
        }
      }

      // Also check from spouse's edges for shared children
      if (spouse != null) {
        for (final edge in adjacency[spouse.id] ?? []) {
          if (['child', 'son', 'daughter'].contains(edge.type) &&
              !visited.contains(edge.targetId) &&
              personMap.containsKey(edge.targetId)) {
            childIds.add(edge.targetId);
          }
        }
      }

      // Build child subtrees
      final children = <TreeNode>[];
      for (final childId in childIds) {
        if (!visited.contains(childId)) {
          children.add(buildNode(childId));
        }
      }

      return TreeNode(
        person: person,
        spouse: spouse,
        children: children,
      );
    }

    return buildNode(rootPersonId);
  }

  // ── Path Caching ─────────────────────────────────────────────────

  /// Cache a path result in Drift's CachedRelationshipPaths table.
  Future<void> _cachePathResult({
    required String familyId,
    required String fromPersonId,
    required String toPersonId,
    required PathResult result,
  }) async {
    if (!IsarDatabase.isInitialized) return;
    try {
      final db = IsarDatabase.instance;
      final pathJson = jsonEncode(result.path.map((s) => s.toJson()).toList());
      final now = DateTime.now();
      final expiresAt = now.add(const Duration(hours: 1));

      await db.upsertRelationshipPath(
        CachedRelationshipPathsCompanion.insert(
          familyId: familyId,
          fromPersonId: fromPersonId,
          toPersonId: toPersonId,
          path: pathJson,
          kinshipTerm: Value(result.composedKinshipTerm),
          distance: Value(result.length),
          computedAt: Value(now),
          expiresAt: Value(expiresAt),
        ),
      );
    } catch (e) {
      debugPrint('⚠️ Path cache write error: $e');
    }
  }

  /// Check if a cached path exists and is still valid (< 1 hour old).
  Future<PathResult?> _getCachedPath({
    required String familyId,
    required String fromPersonId,
    required String toPersonId,
  }) async {
    if (!IsarDatabase.isInitialized) return null;
    try {
      final db = IsarDatabase.instance;
      final cached = await db.getRelationshipPath(
        familyId,
        fromPersonId,
        toPersonId,
      );
      if (cached == null) return null;

      // Check if cache is expired
      if (DateTime.now().isAfter(cached.expiresAt)) return null;

      // Reconstruct the PathResult from cached data
      final pathList = (jsonDecode(cached.path) as List<dynamic>)
          .map((step) => PathStep.fromJson(step as Map<String, dynamic>))
          .toList();

      return PathResult(
        path: pathList,
        length: cached.distance,
        relationshipDescription: pathList.map((step) {
          final formattedType = step.type.replaceAll('_', ' ');
          final prefix = step.direction == 'to' ? '← ' : '';
          final suffix = step.direction == 'to' ? '' : ' →';
          return '$prefix$formattedType$suffix';
        }).join(' '),
        composedKinshipTerm: cached.kinshipTerm,
      );
    } catch (e) {
      debugPrint('⚠️ Path cache read error: $e');
      return null;
    }
  }

  // ── Find Path (BFS with caching) ─────────────────────────────────

  /// Find shortest path between two persons using BFS.
  /// Checks Drift cache first (valid for 1 hour), then falls back to BFS.
  /// On success, caches the result.
  PathResult? findPath({
    required List<GraphPerson> persons,
    required List<({String fromId, String toId, String type})> relationships,
    required String fromPersonId,
    required String toPersonId,
    String familyId = '',
    String locale = 'en',
  }) {
    if (fromPersonId == toPersonId) return null;

    // ── Check cache first (synchronous check via Future not possible
    //    in sync method — cache check is done in findPathAsync) ───
    // The synchronous findPath still does BFS directly.
    // For cached paths, use findPathAsync.

    final adjacency = buildAdjacencyList(persons, relationships);
    final personMap = {for (final p in persons) p.id: p};

    // BFS
    final visited = <String>{};
    final queue = <BFSNode>[];
    visited.add(fromPersonId);
    queue.add(BFSNode(fromPersonId, []));

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);

      for (final edge in adjacency[current.personId] ?? []) {
        if (visited.contains(edge.targetId)) continue;
        visited.add(edge.targetId);

        final neighbor = personMap[edge.targetId];
        final newStep = PathStep(
          personId: edge.targetId,
          personName: neighbor?.name ?? 'Unknown',
          type: edge.type,
          direction: edge.direction,
        );
        final newPath = [...current.path, newStep];

        if (edge.targetId == toPersonId) {
          return _buildPathResult(newPath, locale);
        }

        queue.add(BFSNode(edge.targetId, newPath));
      }
    }

    return null; // No path found
  }

  /// Async version of findPath that checks cache first and caches results.
  Future<PathResult?> findPathAsync({
    required List<GraphPerson> persons,
    required List<({String fromId, String toId, String type})> relationships,
    required String fromPersonId,
    required String toPersonId,
    required String familyId,
    String locale = 'en',
  }) async {
    if (fromPersonId == toPersonId) return null;

    // ── Check cache first ───────────────────────────────────────
    final cached = await _getCachedPath(
      familyId: familyId,
      fromPersonId: fromPersonId,
      toPersonId: toPersonId,
    );
    if (cached != null) return cached;

    // ── Fall back to BFS ────────────────────────────────────────
    final result = findPath(
      persons: persons,
      relationships: relationships,
      fromPersonId: fromPersonId,
      toPersonId: toPersonId,
      familyId: familyId,
      locale: locale,
    );

    // ── Cache the result if found ───────────────────────────────
    if (result != null && familyId.isNotEmpty) {
      await _cachePathResult(
        familyId: familyId,
        fromPersonId: fromPersonId,
        toPersonId: toPersonId,
        result: result,
      );
    }

    return result;
  }

  PathResult _buildPathResult(List<PathStep> path, String locale) {
    final parts = path.map((step) {
      final formattedType = step.type.replaceAll('_', ' ');
      final prefix = step.direction == 'to' ? '← ' : '';
      final suffix = step.direction == 'to' ? '' : ' →';
      return '$prefix$formattedType$suffix';
    }).toList();

    final description = parts.join(' ');

    // Try composed kinship term
    final composed = composeKinshipTerm(path.map((s) => s.type).toList());

    String? localized;
    if (path.length == 1 && locale != 'en') {
      final step = path.first;
      localized = _kinshipService.getKinshipTermByLocale(step.type, locale);
    }

    return PathResult(
      path: path,
      length: path.length,
      relationshipDescription: description,
      localizedDescription: localized,
      composedKinshipTerm: composed,
    );
  }

  // ── Relationship Composition ─────────────────────────────────────

  /// Compose a kinship term from a path of relationship types.
  ///
  /// For paths of length 1, uses the direct kinship mapping.
  /// For paths of length 2+, composes the terms using underscores
  /// (e.g., ["father", "sister"] → "father's sister" / "fathers_sister").
  ///
  /// This mirrors the backend GraphEngineService composition logic.
  String? composeKinshipTerm(List<String> path) {
    if (path.isEmpty) return null;

    if (path.length == 1) {
      // Direct kinship term
      return kinshipTermMap[path.first] ?? path.first.replaceAll('_', ' ');
    }

    // For compound paths, try to look up the composed key in the kinship service
    // e.g., ["father", "brother"] → "fathers_brother" → try lookup
    final composedKey = path.map((s) {
      // Handle possessive: "father" → "fathers", "mother" → "mothers"
      if (s == 'child') return 'childs';
      if (s.endsWith('s')) return s;
      if (s.endsWith('y')) return '${s.substring(0, s.length - 1)}ies';
      return '${s}s';
    }).join('_');

    // Try to resolve via kinship service
    final resolved = _kinshipService.resolvePathToKey(path);
    if (resolved != null) {
      return resolved.englishTerm;
    }

    // Fallback: compose a human-readable string
    final parts = <String>[];
    for (int i = 0; i < path.length; i++) {
      final term = kinshipTermMap[path[i]] ?? path[i].replaceAll('_', ' ');
      if (i < path.length - 1) {
        parts.add("$term's");
      } else {
        parts.add(term);
      }
    }
    return parts.join(' ');
  }

  /// Get ancestors of a person (traverse upward)
  List<GraphPerson> getAncestors({
    required List<GraphPerson> persons,
    required List<({String fromId, String toId, String type})> relationships,
    required String personId,
    int maxDepth = 5,
  }) {
    final adjacency = buildAdjacencyList(persons, relationships);
    final personMap = {for (final p in persons) p.id: p};
    final result = <GraphPerson>[];
    final visited = <String>{personId};

    void traverse(String id, int depth) {
      if (depth >= maxDepth) return;
      for (final edge in adjacency[id] ?? []) {
        if (visited.contains(edge.targetId)) continue;
        if (['parent', 'father', 'mother'].contains(edge.type)) {
          visited.add(edge.targetId);
          final person = personMap[edge.targetId];
          if (person != null) result.add(person);
          traverse(edge.targetId, depth + 1);
        }
      }
    }

    traverse(personId, 0);
    return result;
  }

  /// Get descendants of a person (traverse downward)
  List<GraphPerson> getDescendants({
    required List<GraphPerson> persons,
    required List<({String fromId, String toId, String type})> relationships,
    required String personId,
    int maxDepth = 5,
  }) {
    final adjacency = buildAdjacencyList(persons, relationships);
    final personMap = {for (final p in persons) p.id: p};
    final result = <GraphPerson>[];
    final visited = <String>{personId};

    void traverse(String id, int depth) {
      if (depth >= maxDepth) return;
      for (final edge in adjacency[id] ?? []) {
        if (visited.contains(edge.targetId)) continue;
        if (['child', 'son', 'daughter'].contains(edge.type)) {
          visited.add(edge.targetId);
          final person = personMap[edge.targetId];
          if (person != null) result.add(person);
          traverse(edge.targetId, depth + 1);
        }
      }
    }

    traverse(personId, 0);
    return result;
  }
}

/// Helper for BFS path tracking
class BFSNode {
  BFSNode(this.personId, this.path);

  final List<PathStep> path;

  final String personId;
}

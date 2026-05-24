import '../kinship/kinship_service.dart';

/// Person node in the family graph
class GraphPerson {
  final String id;
  final String name;
  final String? relationship;
  final int generation;
  final bool isDeceased;
  final String? deletedAt;

  const GraphPerson({
    required this.id,
    required this.name,
    this.relationship,
    required this.generation,
    this.isDeceased = false,
    this.deletedAt,
  });
}

/// Tree node for hierarchical family display
class TreeNode {
  final GraphPerson person;
  final GraphPerson? spouse;
  final List<TreeNode> children;

  const TreeNode({
    required this.person,
    this.spouse,
    this.children = const [],
  });
}

/// Path step in a relationship path
class PathStep {
  final String personId;
  final String personName;
  final String type;
  final String direction;

  const PathStep({
    required this.personId,
    required this.personName,
    required this.type,
    required this.direction,
  });
}

/// Result of a path search
class PathResult {
  final List<PathStep> path;
  final int length;
  final String relationshipDescription;
  final String? localizedDescription;

  const PathResult({
    required this.path,
    required this.length,
    required this.relationshipDescription,
    this.localizedDescription,
  });
}

/// Edge in the adjacency list
class _Edge {
  final String targetId;
  final String type;
  final String direction;

  const _Edge(this.targetId, this.type, this.direction);
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

/// Family graph traversal service
class GraphService {
  final KinshipService _kinshipService;

  GraphService(this._kinshipService);

  /// Get inverse relationship type
  String inverseType(String type) => inverseTypeMap[type] ?? type;

  /// Build adjacency list from relationships
  Map<String, List<_Edge>> buildAdjacencyList(
    List<GraphPerson> persons,
    List<({String fromId, String toId, String type})> relationships,
  ) {
    final activePersonIds = persons
        .where((p) => p.deletedAt == null)
        .map((p) => p.id)
        .toSet();

    final adjacency = <String, List<_Edge>>{};

    for (final person in persons) {
      if (person.deletedAt != null) continue;
      adjacency[person.id] = [];
    }

    for (final rel in relationships) {
      if (!activePersonIds.contains(rel.fromId) ||
          !activePersonIds.contains(rel.toId)) continue;

      adjacency[rel.fromId]?.add(_Edge(rel.toId, rel.type, 'from'));
      adjacency[rel.toId]?.add(_Edge(rel.fromId, inverseType(rel.type), 'to'));
    }

    return adjacency;
  }

  /// Find shortest path between two persons using BFS
  PathResult? findPath({
    required List<GraphPerson> persons,
    required List<({String fromId, String toId, String type})> relationships,
    required String fromPersonId,
    required String toPersonId,
    String locale = 'en',
  }) {
    if (fromPersonId == toPersonId) return null;

    final adjacency = buildAdjacencyList(persons, relationships);
    final personMap = {for (final p in persons) p.id: p};

    // BFS
    final visited = <String>{};
    final queue = <_BFSNode>[];
    visited.add(fromPersonId);
    queue.add(_BFSNode(fromPersonId, []));

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

        queue.add(_BFSNode(edge.targetId, newPath));
      }
    }

    return null; // No path found
  }

  PathResult _buildPathResult(List<PathStep> path, String locale) {
    final parts = path.map((step) {
      final formattedType = step.type.replaceAll('_', ' ');
      final prefix = step.direction == 'to' ? '← ' : '';
      final suffix = step.direction == 'to' ? '' : ' →';
      return '$prefix$formattedType$suffix';
    }).toList();

    final description = parts.join(' ');

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
    );
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
class _BFSNode {
  final String personId;
  final List<PathStep> path;

  const _BFSNode(this.personId, this.path);
}

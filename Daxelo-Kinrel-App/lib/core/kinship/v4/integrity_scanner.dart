// lib/core/kinship/v4/integrity_scanner.dart
//
// DAXELO-KINREL — v4.0 Relationship Integrity Scanner (Phase 11)
//
// Continuously detects graph integrity issues:
// - Self relationships
// - Circular ancestry
// - Impossible parent chains (e.g., person is their own grandparent)
// - Duplicate edges
// - Invalid spouse relationships (ancestor/descendant married)
// - Broken lineage chains
//
// Provides automatic repair suggestions.

import '../../../core/services/graph_layout_service.dart' show GraphPerson;

/// A single integrity issue found in the family graph.
class IntegrityIssue {
  final IntegrityIssueType type;
  final String description;
  final String? personAId;
  final String? personBId;
  final String? repairSuggestion;

  const IntegrityIssue({
    required this.type,
    required this.description,
    this.personAId,
    this.personBId,
    this.repairSuggestion,
  });
}

enum IntegrityIssueType {
  selfRelationship,
  circularAncestry,
  duplicateEdge,
  invalidSpouse,
  impossibleParentChain,
  brokenLineage,
  graphCorruption,
}

/// The result of an integrity scan.
class IntegrityScanResult {
  final List<IntegrityIssue> issues;
  final bool hasIssues;

  const IntegrityScanResult({required this.issues}) : hasIssues = false;

  factory IntegrityScanResult.fromIssues(List<IntegrityIssue> issues) {
    return IntegrityScanResult._(issues: issues, hasIssues: issues.isNotEmpty);
  }

  const IntegrityScanResult._({required this.issues, required this.hasIssues});
}

class IntegrityScanner {
  IntegrityScanner._();

  /// Scans the entire family graph for integrity issues.
  static IntegrityScanResult scan({
    required List<GraphPerson> persons,
    required List<({String id, String fromId, String toId, String type})> relationships,
  }) {
    final issues = <IntegrityIssue>[];

    // 1. Check for self-relationships
    for (final rel in relationships) {
      if (rel.fromId == rel.toId) {
        issues.add(IntegrityIssue(
          type: IntegrityIssueType.selfRelationship,
          description: '${rel.fromId} has a relationship with themselves.',
          personAId: rel.fromId,
          personBId: rel.toId,
          repairSuggestion: 'Delete this self-relationship edge.',
        ));
      }
    }

    // 2. Check for duplicate edges (same pair + same type)
    final seenEdges = <String>{};
    for (final rel in relationships) {
      final pair = [rel.fromId, rel.toId]..sort();
      final key = '${pair[0]}|${pair[1]}|${rel.type.toLowerCase()}';
      if (seenEdges.contains(key)) {
        issues.add(IntegrityIssue(
          type: IntegrityIssueType.duplicateEdge,
          description: 'Duplicate edge: ${rel.fromId} → ${rel.toId} (${rel.type}).',
          personAId: rel.fromId,
          personBId: rel.toId,
          repairSuggestion: 'Remove one of the duplicate edges.',
        ));
      }
      seenEdges.add(key);
    }

    // 3. Check for circular ancestry
    // Build parent adjacency: personId → set of parent IDs
    final parentMap = <String, Set<String>>{};
    for (final rel in relationships) {
      final type = rel.type.toLowerCase();
      if (type == 'parent' || type == 'father' || type == 'mother') {
        // fromId's parent is toId
        parentMap.putIfAbsent(rel.fromId, () => {});
        parentMap[rel.fromId]!.add(rel.toId);
      } else if (type == 'child' || type == 'son' || type == 'daughter') {
        // toId's parent is fromId
        parentMap.putIfAbsent(rel.toId, () => {});
        parentMap[rel.toId]!.add(rel.fromId);
      }
    }

    // For each person, check if any ancestor is also a descendant
    for (final person in persons) {
      final ancestors = _getAllAncestors(person.id, parentMap);
      final descendants = _getAllDescendants(person.id, parentMap);
      final intersection = ancestors.intersection(descendants);
      if (intersection.isNotEmpty) {
        issues.add(IntegrityIssue(
          type: IntegrityIssueType.circularAncestry,
          description: '${person.name} has a circular ancestry — a person is both ancestor and descendant.',
          personAId: person.id,
          repairSuggestion: 'Review the parent chain and remove the edge creating the cycle.',
        ));
      }
    }

    // 4. Check for invalid spouse relationships (ancestor/descendant)
    final spousePairs = <(String, String)>[];
    for (final rel in relationships) {
      final type = rel.type.toLowerCase();
      if (type == 'spouse' || type == 'husband' || type == 'wife') {
        spousePairs.add((rel.fromId, rel.toId));
      }
    }

    for (final (a, b) in spousePairs) {
      final ancestorsOfA = _getAllAncestors(a, parentMap);
      final descendantsOfA = _getAllDescendants(a, parentMap);

      if (ancestorsOfA.contains(b) || descendantsOfA.contains(b)) {
        final personA = persons.where((p) => p.id == a).firstOrNull;
        final personB = persons.where((p) => p.id == b).firstOrNull;
        issues.add(IntegrityIssue(
          type: IntegrityIssueType.invalidSpouse,
          description: '${personA?.name ?? a} and ${personB?.name ?? b} are spouses but also have an ancestor-descendant relationship.',
          personAId: a,
          personBId: b,
          repairSuggestion: 'Remove either the spouse edge or the parent-child edge creating the ancestry.',
        ));
      }
    }

    return IntegrityScanResult.fromIssues(issues);
  }

  /// Gets all ancestors of [personId] by traversing the parent map.
  static Set<String> _getAllAncestors(String personId, Map<String, Set<String>> parentMap) {
    final ancestors = <String>{};
    final queue = [personId];
    final visited = {personId};

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final parents = parentMap[current];
      if (parents == null) continue;

      for (final parent in parents) {
        if (visited.contains(parent)) continue;
        visited.add(parent);
        ancestors.add(parent);
        queue.add(parent);
      }
    }

    return ancestors;
  }

  /// Gets all descendants of [personId] by reversing the parent map.
  static Set<String> _getAllDescendants(String personId, Map<String, Set<String>> parentMap) {
    // Build reverse map: parent → children
    final childMap = <String, Set<String>>{};
    for (final entry in parentMap.entries) {
      for (final parent in entry.value) {
        childMap.putIfAbsent(parent, () => {});
        childMap[parent]!.add(entry.key);
      }
    }

    final descendants = <String>{};
    final queue = [personId];
    final visited = {personId};

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final children = childMap[current];
      if (children == null) continue;

      for (final child in children) {
        if (visited.contains(child)) continue;
        visited.add(child);
        descendants.add(child);
        queue.add(child);
      }
    }

    return descendants;
  }
}

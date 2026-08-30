// lib/core/kinship/v4/spouse_inference_engine.dart
//
// DAXELO-KINREL — v4.0 Spouse Inference Engine (Phase 10)
//
// Detects when two persons are both parents of the same child and
// suggests a spouse relationship. NEVER silently creates — always
// asks the user to confirm.
//
// Workflow: Detect → Suggest → User confirms → Create spouse edge
// UI: Dashed line for inferred, solid for confirmed

import '../../../core/services/graph_layout_service.dart' show GraphPerson;

/// Result of a spouse inference check.
class SpouseInference {
  final String personAId;
  final String personAName;
  final String personBId;
  final String personBName;
  final List<String> sharedChildIds;
  final bool alreadySpouse;

  const SpouseInference({
    required this.personAId,
    required this.personAName,
    required this.personBId,
    required this.personBName,
    required this.sharedChildIds,
    required this.alreadySpouse,
  });
}

class SpouseInferenceEngine {
  SpouseInferenceEngine._();

  /// Checks if [personAId] and [personBId] share at least one child
  /// and are NOT already spouses. Returns a [SpouseInference] if a
  /// suggestion should be shown, or null if no inference is needed.
  static SpouseInference? check({
    required String personAId,
    required String personBId,
    required List<GraphPerson> persons,
    required List<({String fromId, String toId, String type})> relationships,
  }) {
    // Find all children of personA (edges where personA is the parent)
    final childrenOfA = <String>{};
    for (final rel in relationships) {
      final type = rel.type.toLowerCase();
      if ((type == 'parent' || type == 'father' || type == 'mother') &&
          rel.toId == personAId) {
        // rel.fromId is a child of personA (fromId's parent is personA)
        childrenOfA.add(rel.fromId);
      } else if ((type == 'child' || type == 'son' || type == 'daughter') &&
          rel.fromId == personAId) {
        // rel.toId is a child of personA
        childrenOfA.add(rel.toId);
      }
    }

    // Find all children of personB
    final childrenOfB = <String>{};
    for (final rel in relationships) {
      final type = rel.type.toLowerCase();
      if ((type == 'parent' || type == 'father' || type == 'mother') &&
          rel.toId == personBId) {
        childrenOfB.add(rel.fromId);
      } else if ((type == 'child' || type == 'son' || type == 'daughter') &&
          rel.fromId == personBId) {
        childrenOfB.add(rel.toId);
      }
    }

    // Find shared children
    final shared = childrenOfA.intersection(childrenOfB);
    if (shared.isEmpty) return null;

    // Check if already spouses
    bool alreadySpouse = false;
    for (final rel in relationships) {
      final type = rel.type.toLowerCase();
      if (type == 'spouse' || type == 'husband' || type == 'wife') {
        if ((rel.fromId == personAId && rel.toId == personBId) ||
            (rel.fromId == personBId && rel.toId == personAId)) {
          alreadySpouse = true;
          break;
        }
      }
    }

    if (alreadySpouse) return null; // Already spouses — no inference needed

    // Get names
    final personA = persons.where((p) => p.id == personAId).firstOrNull;
    final personB = persons.where((p) => p.id == personBId).firstOrNull;

    return SpouseInference(
      personAId: personAId,
      personAName: personA?.name ?? 'Person A',
      personBId: personBId,
      personBName: personB?.name ?? 'Person B',
      sharedChildIds: shared.toList(),
      alreadySpouse: false,
    );
  }

  /// Scans the entire family for ALL spouse inference candidates.
  /// Returns a list of all pairs that share children but aren't spouses.
  static List<SpouseInference> scanFamily({
    required List<GraphPerson> persons,
    required List<({String fromId, String toId, String type})> relationships,
  }) {
    // Build child → parents map
    final childToParents = <String, Set<String>>{};
    for (final rel in relationships) {
      final type = rel.type.toLowerCase();
      String? childId;
      String? parentId;

      if (type == 'parent' || type == 'father' || type == 'mother') {
        childId = rel.fromId;
        parentId = rel.toId;
      } else if (type == 'child' || type == 'son' || type == 'daughter') {
        childId = rel.toId;
        parentId = rel.fromId;
      }

      if (childId != null && parentId != null) {
        childToParents.putIfAbsent(childId, () => {});
        childToParents[childId]!.add(parentId);
      }
    }

    // Build spouse set for quick lookup
    final spousePairs = <String>{};
    for (final rel in relationships) {
      final type = rel.type.toLowerCase();
      if (type == 'spouse' || type == 'husband' || type == 'wife') {
        final pair = [rel.fromId, rel.toId]..sort();
        spousePairs.add('${pair[0]}|${pair[1]}');
      }
    }

    // Find all pairs of parents who share a child
    final candidates = <SpouseInference>[];
    final seenPairs = <String>{};

    for (final entry in childToParents.entries) {
      final parents = entry.value.toList();
      if (parents.length < 2) continue;

      for (int i = 0; i < parents.length; i++) {
        for (int j = i + 1; j < parents.length; j++) {
          final pair = [parents[i], parents[j]]..sort();
          final pairKey = '${pair[0]}|${pair[1]}';

          if (seenPairs.contains(pairKey)) continue;
          if (spousePairs.contains(pairKey)) continue; // Already spouses

          seenPairs.add(pairKey);

          final personA = persons.where((p) => p.id == parents[i]).firstOrNull;
          final personB = persons.where((p) => p.id == parents[j]).firstOrNull;

          candidates.add(SpouseInference(
            personAId: parents[i],
            personAName: personA?.name ?? 'Person',
            personBId: parents[j],
            personBName: personB?.name ?? 'Person',
            sharedChildIds: [entry.key],
            alreadySpouse: false,
          ));
        }
      }
    }

    return candidates;
  }
}

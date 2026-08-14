// lib/core/kinship/v4/explanation_engine.dart
//
// DAXELO-KINREL — v4.0 Explanation Engine (Phase 8)
//
// Every relationship must be explainable. This engine takes a BFS path
// and produces a human-readable explanation of how the kinship was derived.
//
// Example:
//   Path: UP_PARENT_UP_PARENT_DOWN_CHILD
//   Explanation: "You → Father → Grandfather → Grandfather's Son (Uncle)"
//   Term: "Uncle (Paternal)"

import '../v3/kinship_signature.dart';
import '../../../core/services/graph_layout_service.dart' show GraphPerson;

class ExplanationEngine {
  ExplanationEngine._();

  /// Produces a human-readable explanation of the kinship path.
  static KinshipExplanation explain({
    required String fromPersonName,
    required String toPersonName,
    required String resolvedTerm,
    required List<TraversePrimitive> path,
    required List<String> visitedNodeIds,
    required List<GraphPerson> persons,
    required KinshipSignature signature,
    String? locale,
  }) {
    final steps = <ExplanationStep>[];
    String currentNode = fromPersonName;

    for (int i = 0; i < path.length; i++) {
      final primitive = path[i];
      final nextNodeId = i + 1 < visitedNodeIds.length ? visitedNodeIds[i + 1] : null;
      final nextPerson = nextNodeId != null
          ? persons.where((p) => p.id == nextNodeId).firstOrNull
          : null;
      final nextName = nextPerson?.name ?? 'Unknown';

      final stepLabel = _primitiveToLabel(primitive, nextPerson?.gender);
      final relationshipLabel = _primitiveToRelationship(primitive);

      steps.add(ExplanationStep(
        fromNode: currentNode,
        toNode: nextName,
        traversalPrimitive: _primitiveToString(primitive),
        relationshipLabel: relationshipLabel,
        stepLabel: stepLabel,
      ));

      currentNode = nextName;
    }

    return KinshipExplanation(
      fromPerson: fromPersonName,
      toPerson: toPersonName,
      resolvedTerm: resolvedTerm,
      steps: steps,
      signature: signature,
      pathPattern: signature.pathPattern,
      generationDelta: signature.generationDelta,
      side: signature.side,
      consanguinity: signature.consanguinity,
    );
  }

  static String _primitiveToLabel(TraversePrimitive p, String? gender) {
    switch (p) {
      case TraversePrimitive.upParent:
        return gender?.toLowerCase() == 'female' ? 'Mother' : 'Father';
      case TraversePrimitive.downChild:
        return gender?.toLowerCase() == 'female' ? 'Daughter' : 'Son';
      case TraversePrimitive.spouse:
        return gender?.toLowerCase() == 'female' ? 'Wife' : 'Husband';
      case TraversePrimitive.upAdoptiveParent:
        return gender?.toLowerCase() == 'female' ? 'Adoptive Mother' : 'Adoptive Father';
      case TraversePrimitive.upStepParent:
        return gender?.toLowerCase() == 'female' ? 'Step Mother' : 'Step Father';
    }
  }

  static String _primitiveToRelationship(TraversePrimitive p) {
    switch (p) {
      case TraversePrimitive.upParent:
        return 'parent of';
      case TraversePrimitive.downChild:
        return 'child of';
      case TraversePrimitive.spouse:
        return 'spouse of';
      case TraversePrimitive.upAdoptiveParent:
        return 'adoptive parent of';
      case TraversePrimitive.upStepParent:
        return 'step-parent of';
    }
  }

  static String _primitiveToString(TraversePrimitive p) {
    switch (p) {
      case TraversePrimitive.upParent: return 'UP_PARENT';
      case TraversePrimitive.downChild: return 'DOWN_CHILD';
      case TraversePrimitive.spouse: return 'SPOUSE';
      case TraversePrimitive.upAdoptiveParent: return 'UP_ADOPTIVE_PARENT';
      case TraversePrimitive.upStepParent: return 'UP_STEP_PARENT';
    }
  }
}

/// A single step in the explanation path.
class ExplanationStep {
  final String fromNode;
  final String toNode;
  final String traversalPrimitive;
  final String relationshipLabel;
  final String stepLabel;

  const ExplanationStep({
    required this.fromNode,
    required this.toNode,
    required this.traversalPrimitive,
    required this.relationshipLabel,
    required this.stepLabel,
  });

  @override
  String toString() => '$fromNode → $stepLabel → $toNode';
}

/// The full explanation of a kinship resolution.
class KinshipExplanation {
  final String fromPerson;
  final String toPerson;
  final String resolvedTerm;
  final List<ExplanationStep> steps;
  final KinshipSignature signature;
  final String pathPattern;
  final int generationDelta;
  final FamilySide side;
  final Consanguinity consanguinity;

  const KinshipExplanation({
    required this.fromPerson,
    required this.toPerson,
    required this.resolvedTerm,
    required this.steps,
    required this.signature,
    required this.pathPattern,
    required this.generationDelta,
    required this.side,
    required this.consanguinity,
  });

  /// Produces a human-readable summary string.
  String get summary {
    final pathStr = steps.map((s) => s.stepLabel).join(' → ');
    return '$fromPerson → $pathStr → $toPerson\n'
           'Result: $resolvedTerm\n'
           'Path: $pathPattern | Gen: $generationDelta | Side: $side | Consanguinity: $consanguinity';
  }
}

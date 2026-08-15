// lib/graph/interaction/relationship_validation.dart
//
// DAXELO KINREL — Safe Relationship Editing and Undo (Phase 7)
//
// Validates relationship mutations before persistence and provides a
// bounded undo stack for supported graph edits.
//
// VALIDATION separates ERRORS (cannot save) from WARNINGS (user may
// confirm). It does NOT reject legitimate unusual family structures
// merely because they are uncommon.
//
// UNDO supports: add relationship, remove relationship, change
// relationship. Each undo command contains enough canonical
// information to perform the inverse operation.

import 'dart:ui' show Offset;
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Severity of a validation result.
enum ValidationSeverity {
  /// Cannot save — blocks the mutation entirely.
  error,

  /// User may confirm — the mutation is suspicious but not impossible.
  warning,
}

/// v102 (BUG-3 FIX): A typed exception carrying both the human-readable
/// [message] AND the machine-readable [code] from a
/// [RelationshipValidationResult].
///
/// Previously, `createRelationship` in `family_provider.dart` threw a
/// plain `Exception(validation.message)` and then tried to detect
/// validation errors in the catch block by string-matching
/// `e.toString().contains('self_relationship')` etc. But
/// `e.toString()` returns the MESSAGE (e.g. "A person cannot have a
/// relationship with themselves."), not the CODE — so the code-slug
/// check could NEVER match, and every validation error silently fell
/// through to the non-blocking debugPrint path. The relationship write
/// proceeded even when validation correctly flagged it as invalid.
///
/// This typed exception fixes the bug structurally: the catch block
/// now does a TYPE CHECK (`e is RelationshipValidationException`)
/// instead of a fragile string match. The [code] is preserved for
/// callers that want to handle specific error types differently
/// (e.g. show a different UI for self-relationship vs duplicate).
class RelationshipValidationException implements Exception {
  const RelationshipValidationException(this.message, this.code);

  /// Human-readable error message (e.g. "A person cannot have a
  /// relationship with themselves.").
  final String message;

  /// Machine-readable error code (e.g. 'self_relationship',
  /// 'duplicate_relationship', 'circular_parentage', 'duplicate_parent').
  final String code;

  @override
  String toString() => message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RelationshipValidationException &&
          other.code == code &&
          other.message == message;

  @override
  int get hashCode => Object.hash(code, message);
}

/// The result of validating a relationship mutation.
@immutable
class RelationshipValidationResult {
  const RelationshipValidationResult({
    required this.severity,
    required this.message,
    this.code,
  });

  final ValidationSeverity severity;
  final String message;
  final String? code;

  bool get isError => severity == ValidationSeverity.error;
  bool get isWarning => severity == ValidationSeverity.warning;
  bool get isOk => severity == ValidationSeverity.error && message.isEmpty;

  /// A passing validation result (no issues found).
  static const ok = RelationshipValidationResult(
    severity: ValidationSeverity.error,
    message: '',
  );

  @override
  String toString() =>
      'RelationshipValidationResult($severity, "$message", code=$code)';
}

/// Validates a proposed relationship between [fromPersonId] and
/// [toPersonId] with [relationshipKey].
///
/// [existingEdges] — all current canonical edges as (fromId, toId,
/// edgeId, relationshipKey) tuples. Used to detect duplicates +
/// cycles.
/// [ancestorMap] — optional map of personId → set of ancestor IDs.
/// Used for circular parent ancestry detection. If null, cycle
/// detection is skipped (the caller should build this from BFS if
/// available).
RelationshipValidationResult validateRelationship({
  required String fromPersonId,
  required String toPersonId,
  required String relationshipKey,
  required List<({String fromId, String toId, String edgeId, String relationshipKey})> existingEdges,
  Map<String, Set<String>>? ancestorMap,
}) {
  // ── ERROR: Self-relationship ──
  if (fromPersonId == toPersonId) {
    return const RelationshipValidationResult(
      severity: ValidationSeverity.error,
      message: 'A person cannot have a relationship with themselves.',
      code: 'self_relationship',
    );
  }

  // ── ERROR: Duplicate relationship ──
  // v5.0: Canonicalized duplicate detection — checks both the SAME
  // key and its INVERSE on the same pair. e.g. if A→B "father" exists,
  // then B→A "child" is also a duplicate (same canonical relationship).
  // Without this, the user could "create" the same family link twice
  // by selecting the inverse direction in the picker.
  final pair = [fromPersonId, toPersonId]..sort();
  final canonicalPair = '${pair[0]}|${pair[1]}';
  final key = relationshipKey.toLowerCase();
  // v5.0: Fundamental-key family groups. Keys within the same group
  // represent the SAME edge from a different perspective — they are
  // duplicates of each other when applied to the same pair.
  const parentFamily = {'father', 'mother', 'parent'};
  const childFamily = {'son', 'daughter', 'child'};
  const spouseFamily = {'husband', 'wife', 'spouse'};
  const siblingFamily = {'brother', 'sister', 'sibling'};

  bool sameFamily(String a, String b) {
    if (a == b) return true;
    if (parentFamily.contains(a) && parentFamily.contains(b)) return false;
    if (childFamily.contains(a) && childFamily.contains(b)) return false;
    if (spouseFamily.contains(a) && spouseFamily.contains(b)) return false;
    if (siblingFamily.contains(a) && siblingFamily.contains(b)) return false;
    // Parent ↔ Child are inverses (same canonical edge)
    if (parentFamily.contains(a) && childFamily.contains(b)) return true;
    if (childFamily.contains(a) && parentFamily.contains(b)) return true;
    return false;
  }

  for (final e in existingEdges) {
    final existingPair = [e.fromId, e.toId]..sort();
    if ('${existingPair[0]}|${existingPair[1]}' == canonicalPair) {
      // Same pair — check if it's the same key (or inverse key).
      if (sameFamily(e.relationshipKey.toLowerCase(), key)) {
        return const RelationshipValidationResult(
          severity: ValidationSeverity.error,
          message: 'This relationship already exists.',
          code: 'duplicate_relationship',
        );
      }
      // Different family on same pair — that's OK (e.g. parent + spouse
      // between the same two people, which is unusual but not
      // impossible in extended families).
    }
  }

  // ── ERROR: Circular parent ancestry ──
  // If the relationship is a parent→child edge, check that the child
  // is not an ancestor of the parent (which would create a cycle).
  // v5.0: `key` is already declared above (in the duplicate check).
  const parentKeys = {'father', 'mother', 'parent'};
  const childKeys = {'son', 'daughter', 'child'};

  if (ancestorMap != null) {
    if (parentKeys.contains(key)) {
      // from IS the parent, to IS the child.
      // Check: is fromPersonId a descendant of toPersonId?
      // (i.e. does toPersonId's ancestor set contain fromPersonId?)
      final ancestorsOfTo = ancestorMap[toPersonId] ?? {};
      if (ancestorsOfTo.contains(fromPersonId)) {
        return const RelationshipValidationResult(
          severity: ValidationSeverity.error,
          message: 'This would create a circular ancestry — a person '
              'cannot be their own ancestor.',
          code: 'circular_parentage',
        );
      }
    } else if (childKeys.contains(key)) {
      // from IS the child, to IS the parent.
      // Check: is toPersonId a descendant of fromPersonId?
      final ancestorsOfFrom = ancestorMap[fromPersonId] ?? {};
      if (ancestorsOfFrom.contains(toPersonId)) {
        return const RelationshipValidationResult(
          severity: ValidationSeverity.error,
          message: 'This would create a circular ancestry — a person '
              'cannot be their own ancestor.',
          code: 'circular_parentage',
        );
      }
    }
  }

  // ── ERROR: Duplicate parent relationship ──
  // v5.0: A person should not have two parents of the SAME gender.
  // Father + mother (standard biological family) is ALLOWED. Father +
  // father, mother + mother, or any third parent is BLOCKED.
  //
  // Storage convention: `from=A, to=B, key=X` means "A's X is B".
  // So `from=A, to=B, key=father` means B is A's father → A is the
  // CHILD, B is the FATHER.
  //
  // Forward direction (key in {father, mother, parent}):
  //   childId = fromPersonId (A in the example above).
  //   Block when: existing edge points to the same child with the SAME
  //   gender-specific parent key (father + father, mother + mother).
  //   'parent' (gender-neutral) is treated as conflicting with EITHER
  //   father or mother.
  //
  // Inverse direction (key in {son, daughter, child}):
  //   childId = toPersonId. Block when ANY existing edge establishes a
  //   parent of the same gender (since we can't tell which gender from
  //   a 'son' edge, we conservatively block — the user must remove the
  //   existing edge first).
  //
  // The previous check used `e.toId == toPersonId` (the new parent),
  // which incorrectly checked if the NEW PARENT already had a parent
  // — completely missing the actual duplicate-parent case.
  if (key == 'father' || key == 'mother' || key == 'parent') {
    // Forward direction: from=A (child), to=B (parent).
    // childId = fromPersonId (A).
    // We block when an EXISTING edge also makes A the child of some
    // parent. That existing edge can be in either direction:
    //   (a) `from=A, to=X, key in {father, mother, parent}` — A's
    //       parent is X (forward parent-edge).
    //   (b) `from=X, to=A, key in {son, daughter, child}` — X's child
    //       is A (inverse child-edge).
    final childId = fromPersonId;
    for (final e in existingEdges) {
      final existingKey = e.relationshipKey.toLowerCase();
      // Case (a): existing forward parent-edge where A is the child.
      if (e.fromId == childId &&
          (existingKey == 'father' || existingKey == 'mother' || existingKey == 'parent')) {
        // Allow father + mother (opposite genders).
        final sameGender = existingKey == key;
        final hasNeutral = key == 'parent' || existingKey == 'parent';
        if (sameGender || hasNeutral) {
          return RelationshipValidationResult(
            severity: ValidationSeverity.error,
            message: 'This person already has a $key. Remove the existing '
                'one before adding a new one.',
            code: 'duplicate_parent',
          );
        }
      }
      // Case (b): existing inverse child-edge where A is the child.
      // We can't tell the parent's gender from {son, daughter, child},
      // so conservatively block (the user must remove the existing
      // edge first).
      if (e.toId == childId &&
          (existingKey == 'son' || existingKey == 'daughter' || existingKey == 'child')) {
        return RelationshipValidationResult(
          severity: ValidationSeverity.error,
          message: 'This person already has a parent. Remove the existing '
              'one before adding a new one.',
          code: 'duplicate_parent',
        );
      }
    }
  } else if (key == 'son' || key == 'daughter' || key == 'child') {
    // Inverse direction: from=A (parent), to=B (child).
    // childId = toPersonId (B).
    // Block when B already has a parent — either:
    //   (a) `from=B, to=X, key in {father, mother, parent}` — B's
    //       parent is X (forward parent-edge).
    //   (b) `from=X, to=B, key in {son, daughter, child}` — X's child
    //       is B (inverse child-edge).
    final childId = toPersonId;
    for (final e in existingEdges) {
      final existingKey = e.relationshipKey.toLowerCase();
      // Case (a): existing forward parent-edge where B is the child.
      if (e.fromId == childId &&
          (existingKey == 'father' || existingKey == 'mother' || existingKey == 'parent')) {
        final sameGender = existingKey == key;
        final hasNeutral = key == 'child' || existingKey == 'parent';
        if (sameGender || hasNeutral) {
          return RelationshipValidationResult(
            severity: ValidationSeverity.error,
            message: 'This person already has a parent. Remove the existing '
                'one before adding a new one.',
            code: 'duplicate_parent',
          );
        }
      }
      // Case (b): existing inverse child-edge where B is the child.
      if (e.toId == childId &&
          (existingKey == 'son' || existingKey == 'daughter' || existingKey == 'child')) {
        return RelationshipValidationResult(
          severity: ValidationSeverity.error,
          message: 'This person already has a parent. Remove the existing '
              'one before adding a new one.',
          code: 'duplicate_parent',
        );
      }
    }
  }

  // ── WARNING: Incompatible inverse relationship ──
  // If A is already B's father, adding A as B's son is incompatible.
  final inverseMap = <String, String>{
    'father': 'child',
    'mother': 'child',
    'parent': 'child',
    'child': 'parent',
    'son': 'parent',
    'daughter': 'parent',
    'husband': 'wife',
    'wife': 'husband',
    'spouse': 'spouse',
    'brother': 'sibling',
    'sister': 'sibling',
    'sibling': 'sibling',
  };

  final expectedInverse = inverseMap[key];
  if (expectedInverse != null) {
    for (final e in existingEdges) {
      if (e.fromId == toPersonId && e.toId == fromPersonId) {
        final existingKey = e.relationshipKey.toLowerCase();
        final existingInverse = inverseMap[existingKey];
        // If the existing edge's inverse doesn't match the new key,
        // there may be an incompatibility.
        if (existingInverse != null && existingInverse != key && expectedInverse != existingKey) {
          return RelationshipValidationResult(
            severity: ValidationSeverity.warning,
            message: 'An existing relationship between these members '
                'may be incompatible with the new one. Please verify.',
            code: 'incompatible_inverse',
          );
        }
      }
    }
  }

  // ── All checks passed ──
  return RelationshipValidationResult.ok;
}

// ═══════════════════════════════════════════════════════════════════════
// UNDO STACK
// ═══════════════════════════════════════════════════════════════════════

/// The type of graph edit operation that can be undone.
enum GraphEditType {
  addRelationship,
  removeRelationship,
  changeRelationship,
}

/// A single undoable graph edit command.
///
/// Contains enough canonical information to perform the inverse
/// operation without re-deriving anything from the graph.
@immutable
class GraphEditCommand {
  const GraphEditCommand({
    required this.type,
    required this.familyId,
    required this.fromPersonId,
    required this.toPersonId,
    required this.relationshipKey,
    this.previousRelationshipKey,
    this.edgeId,
    this.description,
  });

  final GraphEditType type;
  final String familyId;
  final String fromPersonId;
  final String toPersonId;
  final String relationshipKey;
  final String? previousRelationshipKey;
  final String? edgeId;
  final String? description;

  /// Returns a human-readable description for the undo snackbar.
  String get undoDescription {
    switch (type) {
      case GraphEditType.addRelationship:
        return 'Undo: remove $relationshipKey relationship';
      case GraphEditType.removeRelationship:
        return 'Undo: restore $relationshipKey relationship';
      case GraphEditType.changeRelationship:
        return 'Undo: restore $previousRelationshipKey relationship';
    }
  }

  @override
  String toString() =>
      'GraphEditCommand($type, $fromPersonId → $toPersonId, '
      'key=$relationshipKey, prevKey=$previousRelationshipKey)';
}

/// The state of the undo stack.
@immutable
class GraphUndoState {
  const GraphUndoState({
    this.commands = const <GraphEditCommand>[],
    this.revision = 0,
  });

  /// Bounded undo stack (most recent last). Max 20 entries.
  final List<GraphEditCommand> commands;

  /// Bumped whenever the stack changes.
  final int revision;

  /// True if there are commands that can be undone.
  bool get canUndo => commands.isNotEmpty;

  /// The most recent command, or null if the stack is empty.
  GraphEditCommand? get lastCommand =>
      commands.isEmpty ? null : commands.last;

  static const GraphUndoState empty = GraphUndoState();

  GraphUndoState copyWith({
    List<GraphEditCommand>? commands,
    int? revision,
  }) {
    return GraphUndoState(
      commands: commands ?? this.commands,
      revision: revision ?? this.revision,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GraphUndoState && other.revision == revision;

  @override
  int get hashCode => revision.hashCode;
}

/// StateNotifier that owns the undo stack.
class GraphUndoNotifier extends StateNotifier<GraphUndoState> {
  GraphUndoNotifier() : super(GraphUndoState.empty);

  static const int _maxStack = 20;

  /// Push a new edit command onto the undo stack.
  void push(GraphEditCommand command) {
    final newCommands = [...state.commands, command];
    // Bound to _maxStack (keep the most recent).
    if (newCommands.length > _maxStack) {
      newCommands.removeRange(0, newCommands.length - _maxStack);
    }
    state = GraphUndoState(
      commands: newCommands,
      revision: state.revision + 1,
    );
  }

  /// Pop the most recent command (for undo). Returns the command to
  /// undo, or null if the stack is empty.
  GraphEditCommand? pop() {
    if (state.commands.isEmpty) return null;
    final newCommands = List<GraphEditCommand>.from(state.commands);
    final command = newCommands.removeLast();
    state = GraphUndoState(
      commands: newCommands,
      revision: state.revision + 1,
    );
    return command;
  }

  /// Clear the undo stack (e.g. on family switch).
  void clearAll() {
    if (state == GraphUndoState.empty) return;
    state = GraphUndoState.empty;
  }
}

/// Riverpod provider for the graph edit undo stack.
final graphUndoProvider =
    StateNotifierProvider<GraphUndoNotifier, GraphUndoState>(
  (ref) => GraphUndoNotifier(),
);

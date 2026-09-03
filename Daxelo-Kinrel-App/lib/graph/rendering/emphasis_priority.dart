// lib/graph/rendering/emphasis_priority.dart
//
// DAXELO KINREL — Emphasis Priority Composition (Phase 10)
//
// One explicit emphasis priority that composes all graph emphasis
// sources into a single value per node. This prevents multiple
// independent opacity systems from multiplying blindly until nodes
// become invisible.
//
// PRIORITY (highest to lowest):
//   1. active path endpoint
//   2. focused person
//   3. active path node
//   4. selected person
//   5. search match
//   6. immediate relative (first-degree of focus)
//   7. normal member
//   8. dimmed unrelated member
//
// Each level has a target opacity + visual treatment. The painter
// reads the composed EmphasisLevel for each node and applies the
// corresponding treatment — no independent opacity multiplication.

import 'package:flutter/foundation.dart' show immutable;

/// The composed emphasis level for a single node.
///
/// Higher levels have stronger visual emphasis. The painter applies
/// exactly ONE level per node — no stacking.
@immutable
class EmphasisLevel {
  const EmphasisLevel._(this.priority, this.opacity, this.label);

  /// Numeric priority (higher = more important). Used for comparison.
  final int priority;

  /// Target opacity for this level (0.0–1.0). The painter applies
  /// this directly — no multiplication with other sources.
  final double opacity;

  /// Human-readable label for debugging.
  final String label;

  // ── Level constants (highest priority first) ──

  /// Active path endpoint — the viewer + target of the relationship path.
  static const pathEndpoint = EmphasisLevel._(8, 1.0, 'pathEndpoint');

  /// Focused person — the person currently defining graph context.
  static const focused = EmphasisLevel._(7, 1.0, 'focused');

  /// Active path node — any node on the resolved relationship path.
  static const pathNode = EmphasisLevel._(6, 1.0, 'pathNode');

  /// Selected person — the currently selected node (tap target).
  static const selected = EmphasisLevel._(5, 1.0, 'selected');

  /// Search match — a node matching the current search query.
  static const searchMatch = EmphasisLevel._(4, 0.95, 'searchMatch');

  /// Immediate relative — first-degree neighbour of the focused person.
  static const immediateRelative = EmphasisLevel._(3, 0.90, 'immediateRelative');

  /// Normal member — default, no special emphasis.
  static const normal = EmphasisLevel._(2, 0.80, 'normal');

  /// Dimmed unrelated — a node that is neither focused, selected, on
  /// the path, a search match, nor an immediate relative.
  static const dimmed = EmphasisLevel._(1, 0.40, 'dimmed');

  /// Returns the higher of two emphasis levels.
  EmphasisLevel max(EmphasisLevel other) =>
      priority >= other.priority ? this : other;

  @override
  String toString() => 'EmphasisLevel($label, priority=$priority, opacity=$opacity)';
}

/// Computes the composed emphasis level for a single node.
///
/// This is the SINGLE ENTRY POINT for emphasis composition. The
/// painter calls this once per node and applies the resulting
/// [EmphasisLevel.opacity] — no independent opacity multiplication.
///
/// Parameters:
/// - [nodeId]: the person ID being evaluated.
/// - [focusedPersonId]: the focused person (Phase 1).
/// - [selectedPersonId]: the selected person (tap).
/// - [pathNodeIds]: set of person IDs on the active relationship path.
/// - [pathEndpointIds]: set of {viewer, target} — the path endpoints.
/// - [searchMatchIds]: set of person IDs matching the current search.
/// - [firstDegreeIds]: first-degree neighbours of the focused person.
/// - [searchActive]: whether search is currently active.
/// - [focusActive]: whether focus mode is currently active.
EmphasisLevel computeEmphasisLevel({
  required String nodeId,
  String? focusedPersonId,
  String? selectedPersonId,
  Set<String>? pathNodeIds,
  Set<String>? pathEndpointIds,
  Set<String>? searchMatchIds,
  Set<String>? firstDegreeIds,
  bool searchActive = false,
  bool focusActive = false,
}) {
  // v5.x (tap-highlight fix): also dim unrelated nodes when a plain
  // tap selection is active (selectedPersonId != null) — not just
  // when focus/search is active. This creates the three-tier visual
  // hierarchy on tap: selected (1.0), direct connections (0.90),
  // everyone else (0.40).
  final bool tapActive = selectedPersonId != null && !focusActive && !searchActive;

  // Start at the lowest level.
  var level = EmphasisLevel.normal;

  // If focus, search, or tap is active, a non-emphasised node is dimmed.
  if (focusActive || searchActive || tapActive) {
    level = EmphasisLevel.dimmed;
  }

  // Immediate relative (first-degree of focus).
  if (firstDegreeIds != null && firstDegreeIds.contains(nodeId)) {
    level = level.max(EmphasisLevel.immediateRelative);
  }

  // Search match.
  if (searchActive && searchMatchIds != null && searchMatchIds.contains(nodeId)) {
    level = level.max(EmphasisLevel.searchMatch);
  }

  // Selected person.
  if (nodeId == selectedPersonId) {
    level = level.max(EmphasisLevel.selected);
  }

  // Active path node.
  if (pathNodeIds != null && pathNodeIds.contains(nodeId)) {
    level = level.max(EmphasisLevel.pathNode);
  }

  // Focused person.
  if (nodeId == focusedPersonId) {
    level = level.max(EmphasisLevel.focused);
  }

  // Active path endpoint (viewer + target).
  if (pathEndpointIds != null && pathEndpointIds.contains(nodeId)) {
    level = level.max(EmphasisLevel.pathEndpoint);
  }

  return level;
}

// lib/graph/interaction/relationship_linking_state.dart
//
// DAXELO KINREL — Relationship Creation Mode (v148)
//
// A dedicated focused mode for creating relationships between graph nodes.
// When active, the graph transforms into a relationship-building workspace:
//   - All floating controls are hidden
//   - An instruction banner appears at the top
//   - Nodes are dimmed/highlighted to show what's selectable
//   - The user taps two nodes (first + second) directly on the graph
//   - The kinship picker opens after the second node is selected
//   - A cancel button exits the mode and restores normal controls
//
// Two-phase selection:
//   Phase 1 (awaitingFirst): "Select a family member to start"
//   Phase 2 (awaitingSecond): "Select another member to connect with"
//
// v148 redesign: renamed from "Linking Mode" to "Creation Mode" with
// improved UX — instruction banner, dim/highlight visuals, cancel button,
// human-friendly error messages, success feedback.

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The phases of the relationship creation flow.
enum CreationPhase {
  /// Not in creation mode — normal graph interaction.
  idle,

  /// Waiting for the user to tap the FIRST node.
  awaitingFirst,

  /// First node selected, waiting for the SECOND node.
  awaitingSecond,
}

/// State for the relationship creation mode.
class RelationshipCreationState {
  const RelationshipCreationState({
    this.phase = CreationPhase.idle,
    this.firstPersonId,
    this.firstPersonName,
    this.invalidIds = const {},
  });

  /// Current phase of the creation flow.
  final CreationPhase phase;

  /// The person ID of the first selected node (set after phase 1).
  final String? firstPersonId;

  /// Display name of the first person (for the instruction banner).
  final String? firstPersonName;

  /// Set of person IDs that CANNOT be selected:
  ///   - the first person themselves (in phase 2)
  ///   - anyone already directly related to the first person
  /// Only populated in phase 2.
  final Set<String> invalidIds;

  bool get isActive => phase != CreationPhase.idle;

  RelationshipCreationState copyWith({
    CreationPhase? phase,
    String? firstPersonId,
    String? firstPersonName,
    Set<String>? invalidIds,
    bool clearFirst = false,
    bool clearInvalid = false,
  }) {
    return RelationshipCreationState(
      phase: phase ?? this.phase,
      firstPersonId:
          clearFirst ? null : (firstPersonId ?? this.firstPersonId),
      firstPersonName: clearFirst
          ? null
          : (firstPersonName ?? this.firstPersonName),
      invalidIds: clearInvalid ? const {} : (invalidIds ?? this.invalidIds),
    );
  }
}

/// Riverpod state notifier for relationship creation mode.
class RelationshipCreationNotifier
    extends StateNotifier<RelationshipCreationState> {
  RelationshipCreationNotifier() : super(const RelationshipCreationState());

  /// Enter creation mode. The user will be prompted to tap the first node.
  void startCreation() {
    state = const RelationshipCreationState(
      phase: CreationPhase.awaitingFirst,
    );
  }

  /// Set the first selected node. Transitions to awaitingSecond.
  void setFirstNode({
    required String personId,
    required String personName,
    required Set<String> invalidIds,
  }) {
    state = RelationshipCreationState(
      phase: CreationPhase.awaitingSecond,
      firstPersonId: personId,
      firstPersonName: personName,
      invalidIds: invalidIds,
    );
  }

  /// Check if [personId] is a valid selection for the current phase.
  bool isValidSelection(String personId) {
    if (!state.isActive) return false;
    if (state.phase == CreationPhase.awaitingSecond) {
      if (personId == state.firstPersonId) return false;
      if (state.invalidIds.contains(personId)) return false;
    }
    return true;
  }

  /// Exit creation mode (cancel or after relationship creation).
  void stopCreation() {
    state = const RelationshipCreationState();
  }
}

/// Provider for the relationship creation state.
final relationshipCreationProvider = StateNotifierProvider<
    RelationshipCreationNotifier, RelationshipCreationState>(
  (ref) => RelationshipCreationNotifier(),
);

// Backward-compatible alias for code that still references the old name.
// v148 renamed LinkingPhase → CreationPhase but kept the old provider
// name so existing imports don't break.
final relationshipLinkingProvider = relationshipCreationProvider;
typedef LinkingPhase = CreationPhase;
typedef RelationshipLinkingState = RelationshipCreationState;
typedef RelationshipLinkingNotifier = RelationshipCreationNotifier;

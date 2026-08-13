// lib/graph/interaction/relationship_linking_state.dart
//
// DAXELO KINREL — Relationship Linking Mode (v147)
//
// When the user taps "Relate to another person" from the long-press
// menu, the graph enters Relationship Linking Mode. Instead of showing
// a person-picker bottom sheet, the graph canvas itself becomes the
// selector:
//   1. The source node glows brightly
//   2. Valid target nodes pulse subtly
//   3. Invalid nodes (self, already-related) appear dimmed
//   4. An instruction bar appears at the top: "Tap another person to
//      create a relationship"
//   5. The user taps a target node directly on the graph
//   6. An animated connection line grows from source to target
//   7. The existing RelationshipPickerSheet opens
//   8. After kinship selection, createRelationship() creates the edge
//
// This file defines the state for that mode. It's a simple Riverpod
// state notifier — the interaction_mixin checks this state in
// _handleNodeTapDown and intercepts the tap if linking mode is active.

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The phases of the relationship linking flow.
enum LinkingPhase {
  /// Not in linking mode — normal graph interaction.
  idle,

  /// Waiting for the user to tap a target node.
  /// [sourcePersonId] is set; the user needs to tap another node.
  awaitingTarget,
}

/// State for the relationship linking mode.
class RelationshipLinkingState {
  const RelationshipLinkingState({
    this.phase = LinkingPhase.idle,
    this.sourcePersonId,
    this.sourcePersonName,
    this.invalidTargetIds = const {},
  });

  /// Current phase of the linking flow.
  final LinkingPhase phase;

  /// The person ID of the source node (the one the user long-pressed
  /// and selected "Relate to another person" from).
  final String? sourcePersonId;

  /// Display name of the source person (for the instruction bar).
  final String? sourcePersonName;

  /// Set of person IDs that CANNOT be selected as targets:
  ///   - the source person themselves
  ///   - anyone already directly related to the source person
  final Set<String> invalidTargetIds;

  bool get isActive => phase != LinkingPhase.idle;

  RelationshipLinkingState copyWith({
    LinkingPhase? phase,
    String? sourcePersonId,
    String? sourcePersonName,
    Set<String>? invalidTargetIds,
    bool clearSource = false,
    bool clearInvalid = false,
  }) {
    return RelationshipLinkingState(
      phase: phase ?? this.phase,
      sourcePersonId:
          clearSource ? null : (sourcePersonId ?? this.sourcePersonId),
      sourcePersonName: clearSource
          ? null
          : (sourcePersonName ?? this.sourcePersonName),
      invalidTargetIds:
          clearInvalid ? const {} : (invalidTargetIds ?? this.invalidTargetIds),
    );
  }
}

/// Riverpod state notifier for relationship linking mode.
class RelationshipLinkingNotifier
    extends StateNotifier<RelationshipLinkingState> {
  RelationshipLinkingNotifier() : super(const RelationshipLinkingState());

  /// Enter linking mode. [sourcePersonId] is the node the user long-pressed.
  /// [invalidTargetIds] is the set of person IDs that cannot be targets
  /// (self + already directly related).
  void startLinking({
    required String sourcePersonId,
    required String sourcePersonName,
    required Set<String> invalidTargetIds,
  }) {
    state = RelationshipLinkingState(
      phase: LinkingPhase.awaitingTarget,
      sourcePersonId: sourcePersonId,
      sourcePersonName: sourcePersonName,
      invalidTargetIds: invalidTargetIds,
    );
  }

  /// Exit linking mode (cancel or after relationship creation).
  void stopLinking() {
    state = const RelationshipLinkingState();
  }

  /// Check if [personId] is a valid target for linking.
  bool isValidTarget(String personId) {
    if (!state.isActive) return false;
    if (personId == state.sourcePersonId) return false;
    if (state.invalidTargetIds.contains(personId)) return false;
    return true;
  }
}

/// Provider for the relationship linking state.
final relationshipLinkingProvider =
    StateNotifierProvider<RelationshipLinkingNotifier, RelationshipLinkingState>(
  (ref) => RelationshipLinkingNotifier(),
);

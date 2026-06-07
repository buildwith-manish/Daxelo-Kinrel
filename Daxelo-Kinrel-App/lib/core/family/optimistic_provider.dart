// lib/core/family/optimistic_provider.dart
//
// DAXELO KINREL — Optimistic UI Providers
//
// Provides an optimistic layer on top of the real data providers.
// Pending (optimistic) members are shown immediately in the UI
// while the API call is in-flight, and are replaced or removed
// once the server confirms success or failure.
//
// Pattern: WhatsApp-style "show first, confirm later"

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'family_provider.dart';

// ════════════════════════════════════════════════════════════════════
// OPTIMISTIC PERSON MODEL
// ════════════════════════════════════════════════════════════════════

/// A [Person] subclass that carries an `isPending` flag.
/// When `isPending` is true, the UI shows a subtle indicator
/// (reduced opacity, pending badge) to signal the server
/// hasn't confirmed this entry yet.
class OptimisticPerson extends Person {
  const OptimisticPerson({
    required super.id,
    required super.familyId,
    required super.name,
    super.gender,
    super.dateOfBirth,
    super.city,
    super.gotra,
    super.isDeceased = false,
    super.deletedAt,
    super.createdAt,
    super.birthYear,
    super.occupation,
    super.privacyLevel,
    super.notes,
    super.sideOfFamily,
    super.generationIndex = 0,
    super.isAnchor = false,
    super.photoUrl,
    super.username,
    this.isPending = false,
  });

  /// Whether this person is still pending server confirmation.
  final bool isPending;

  @override
  String toString() =>
      'OptimisticPerson(id: $id, name: $name, isPending: $isPending)';
}

// ════════════════════════════════════════════════════════════════════
// PENDING MEMBERS NOTIFIER
// ════════════════════════════════════════════════════════════════════

/// Tracks pending (optimistic) members per family.
/// Key = familyId, Value = list of optimistic persons awaiting confirmation.
class PendingMembersNotifier
    extends StateNotifier<Map<String, List<OptimisticPerson>>> {
  PendingMembersNotifier() : super({});

  /// Add a pending member to the given family.
  void addPending(String familyId, OptimisticPerson person) {
    final current = state[familyId] ?? [];
    state = {
      ...state,
      familyId: [...current, person],
    };
  }

  /// Remove a pending member from the given family by person ID.
  void removePending(String familyId, String personId) {
    final current = state[familyId] ?? [];
    state = {
      ...state,
      familyId: current.where((p) => p.id != personId).toList(),
    };
  }

  /// Clear all pending members for a given family.
  void clearPending(String familyId) {
    state = {
      ...state,
      familyId: [],
    };
  }
}

/// Provider for pending (optimistic) members.
final pendingMembersProvider = StateNotifierProvider<PendingMembersNotifier,
    Map<String, List<OptimisticPerson>>>((ref) {
  return PendingMembersNotifier();
});

// ════════════════════════════════════════════════════════════════════
// COMBINED PROVIDERS
// ════════════════════════════════════════════════════════════════════

/// Combined members list: real members from [familyMembersProvider]
/// + pending members from [pendingMembersProvider].
///
/// Pending members are appended at the end of the list.
/// The UI can differentiate them via `is OptimisticPerson`.
final combinedMembersProvider =
    Provider.family<List<Person>, String>((ref, familyId) {
  final asyncMembers = ref.watch(familyMembersProvider(familyId));
  final pendingMembers = ref.watch(pendingMembersProvider)[familyId] ?? [];

  final realMembers = asyncMembers.valueOrNull ?? [];
  return [...realMembers, ...pendingMembers];
});

/// Combined member count (real + pending).
final combinedMemberCountProvider =
    Provider.family<int, String>((ref, familyId) {
  return ref.watch(combinedMembersProvider(familyId)).length;
});

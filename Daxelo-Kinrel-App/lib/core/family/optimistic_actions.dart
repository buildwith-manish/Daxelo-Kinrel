// lib/core/family/optimistic_actions.dart
//
// DAXELO KINREL — Optimistic UI Action Functions
//
// WhatsApp-style "show first, confirm later" actions.
// Each function immediately updates local state, then fires
// the real API call in the background. On failure, the
// optimistic state is rolled back.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'family_provider.dart';
import 'optimistic_provider.dart';
import '../../features/events/providers/events_provider.dart';

// ════════════════════════════════════════════════════════════════════
// OPTIMISTIC ADD MEMBER
// ════════════════════════════════════════════════════════════════════

/// Optimistic add member — shows in list immediately, confirms with server.
///
/// Flow:
/// 1. Generate a temp ID and create an [OptimisticPerson] with `isPending: true`
/// 2. Add to [pendingMembersProvider] (shows immediately in UI)
/// 3. Fire the real [createPerson] API call in the background
/// 4. On success: remove pending entry (provider already invalidated by createPerson)
/// 5. On failure: remove pending entry + rethrow so caller can show error snackbar
Future<Person> addMemberOptimistic({
  required WidgetRef ref,
  required String familyId,
  required String name,
  String? gender,
  String? dateOfBirth,
  String? city,
  String? gotra,
  bool isDeceased = false,
  int? birthYear,
  bool isAnchor = false,
}) async {
  // 1. Generate a temp ID for the optimistic entry
  final tempId = 'pending_${DateTime.now().millisecondsSinceEpoch}';

  final optimisticPerson = OptimisticPerson(
    id: tempId,
    familyId: familyId,
    name: name,
    gender: gender,
    dateOfBirth: dateOfBirth,
    city: city,
    gotra: gotra,
    isDeceased: isDeceased,
    birthYear: birthYear,
    isAnchor: isAnchor,
    isPending: true,
    privacyLevel: 'family',
    createdAt: DateTime.now(),
  );

  // 2. Add to pending members (shows immediately in UI)
  ref.read(pendingMembersProvider.notifier).addPending(familyId, optimisticPerson);

  // 3. Fire API call in background
  try {
    final realPerson = await createPerson(
      ref: ref,
      familyId: familyId,
      name: name,
      gender: gender,
      dateOfBirth: dateOfBirth,
      city: city,
      gotra: gotra,
      isDeceased: isDeceased,
      birthYear: birthYear,
      isAnchor: isAnchor,
    );

    // 4. On success: remove pending entry.
    // createPerson already invalidates familyMembersProvider,
    // so the real data will be fetched automatically.
    ref.read(pendingMembersProvider.notifier).removePending(familyId, tempId);

    return realPerson;
  } catch (e) {
    // 5. On failure: remove pending entry + rethrow
    ref.read(pendingMembersProvider.notifier).removePending(familyId, tempId);
    rethrow;
  }
}

// ════════════════════════════════════════════════════════════════════
// OPTIMISTIC ADD EVENT
// ════════════════════════════════════════════════════════════════════

/// Optimistic add family event — shows in list immediately.
///
/// Since events are currently demo/local-only, the "confirm with server"
/// step is a placeholder. The event is added immediately to the
/// [eventsProvider] state. When a real API is connected, the
/// [onConfirm] callback can fire the API call and remove the
/// event on failure.
///
/// Flow:
/// 1. Create an [EventModel] with a temp ID
/// 2. Add to events list immediately
/// 3. On failure (future): remove the event by temp ID
Future<EventModel> addEventOptimistic({
  required WidgetRef ref,
  required EventModel event,
}) async {
  // 1. Create with a pending ID if not already set
  final pendingId = event.id.isEmpty
      ? 'pending_event_${DateTime.now().millisecondsSinceEpoch}'
      : event.id;
  final optimisticEvent = event.copyWith(id: pendingId);

  // 2. Add to events list immediately
  ref.read(eventsProvider.notifier).addEvent(optimisticEvent);

  // 3. Return the optimistic event (caller can track it for rollback)
  // When a real API is connected, wrap the API call here:
  //   try { await apiCall(); ref.read(eventsProvider.notifier).replaceEvent(pendingId, realEvent); }
  //   catch (e) { ref.read(eventsProvider.notifier).removeEvent(pendingId); rethrow; }
  return optimisticEvent;
}

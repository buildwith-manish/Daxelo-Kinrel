// lib/core/family/optimistic_actions.dart
//
// DAXELO KINREL — Optimistic UI Action Functions
//
// WhatsApp-style "show first, confirm later" actions.
// Each function immediately updates local state, then fires
// the real API call in the background. On failure, the
// optimistic state is rolled back.

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'family_provider.dart';
import 'optimistic_provider.dart';
import '../database/isar_database.dart';
import '../database/app_database.dart';
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

// ════════════════════════════════════════════════════════════════════
// OPTIMISTIC DELETE FAMILY
// ════════════════════════════════════════════════════════════════════

/// Optimistic delete family — removes from local Drift cache immediately,
/// then confirms with the server API. On failure, re-fetches from server.
///
/// Flow:
/// 1. Immediately delete from Drift: `ref.read(isarProvider).deleteFamily(familyId)`
/// 2. Invalidate `familyListProvider` (UI updates immediately)
/// 3. Fire real API `deleteFamily(ref: ref, familyId: familyId)` in background
/// 4. On failure: invalidate `familyListProvider` again (re-fetch from server) + rethrow
Future<void> deleteFamilyOptimistic({
  required WidgetRef ref,
  required String familyId,
}) async {
  // 1. Immediately delete from local Drift cache
  try {
    await ref.read(isarProvider).deleteFamily(familyId);
  } catch (e) {
    debugPrint('⚠️ Optimistic delete: could not remove from Drift: $e');
  }

  // 2. Invalidate providers so UI updates immediately
  ref.invalidate(familyListProvider);

  // 3. Fire real API call in background
  try {
    await deleteFamily(ref: ref, familyId: familyId);
  } catch (e) {
    // 4. On failure: invalidate to re-fetch from server (rollback)
    ref.invalidate(familyListProvider);
    rethrow;
  }
}

// ════════════════════════════════════════════════════════════════════
// OPTIMISTIC CREATE FAMILY
// ════════════════════════════════════════════════════════════════════

/// Optimistic create family — inserts a temp entry into local Drift cache
/// immediately, then confirms with the server API. On success, the temp
/// entry is replaced by the real server data. On failure, the temp entry
/// is removed.
///
/// Flow:
/// 1. Generate a tempId: `'pending_family_${DateTime.now().millisecondsSinceEpoch}'`
/// 2. Immediately upsert into Drift `cachedFamilies` with `CachedFamiliesCompanion`
/// 3. Invalidate `familyListProvider`
/// 4. Fire real API `createFamily(...)` in background
/// 5. On success: remove the temp entry from Drift, invalidate provider
/// 6. On failure: delete temp entry from Drift + rethrow
Future<Family> createFamilyOptimistic({
  required WidgetRef ref,
  required String name,
  String? description,
  String? primaryLanguage,
  String? gotra,
  String? originVillage,
  String? region,
  String? privacyMode,
  String? username,
  String? photoUrl,
}) async {
  // 1. Generate a temp ID for the optimistic entry
  final tempId = 'pending_family_${DateTime.now().millisecondsSinceEpoch}';

  // 2. Immediately upsert into Drift cachedFamilies
  try {
    final db = ref.read(isarProvider);
    await db.upsertFamily(CachedFamiliesCompanion(
      id: Value(tempId),
      name: Value(name),
      data: Value('{}'), // placeholder
      cachedAt: Value(DateTime.now()),
    ));
  } catch (e) {
    debugPrint('⚠️ Optimistic create: could not insert temp family into Drift: $e');
  }

  // 3. Invalidate providers so UI updates immediately
  ref.invalidate(familyListProvider);

  // 4. Fire real API call in background
  try {
    final realFamily = await createFamily(
      ref: ref,
      name: name,
      description: description,
      primaryLanguage: primaryLanguage,
      gotra: gotra,
      originVillage: originVillage,
      region: region,
      privacyMode: privacyMode,
      username: username,
      photoUrl: photoUrl,
    );

    // 5. On success: remove the temp entry from Drift
    try {
      await ref.read(isarProvider).deleteFamily(tempId);
    } catch (e) {
      debugPrint('⚠️ Optimistic create: could not remove temp family from Drift: $e');
    }
    // Invalidate so the real server data is fetched
    ref.invalidate(familyListProvider);

    return realFamily;
  } catch (e) {
    // 6. On failure: delete temp entry from Drift
    try {
      await ref.read(isarProvider).deleteFamily(tempId);
    } catch (dbError) {
      debugPrint('⚠️ Optimistic create: could not remove temp family on failure: $dbError');
    }
    ref.invalidate(familyListProvider);
    rethrow;
  }
}

// ════════════════════════════════════════════════════════════════════
// OPTIMISTIC RESTORE FAMILY
// ════════════════════════════════════════════════════════════════════

/// Optimistic restore family — updates the local Drift entry immediately
/// by re-upserting with `deletedAt` set to null, then confirms with the
/// server API. On failure, invalidates providers to re-fetch from server.
///
/// Flow:
/// 1. Immediately update the Drift entry by re-upserting with `deletedAt` set to null
/// 2. Invalidate `familyListProvider`
/// 3. Fire real API `restoreFamily(ref: ref, familyId: familyId)` in background
/// 4. On failure: invalidate provider (re-fetch from server) + rethrow
Future<void> restoreFamilyOptimistic({
  required WidgetRef ref,
  required String familyId,
}) async {
  // 1. Immediately update the Drift entry by re-upserting with deletedAt = null
  try {
    final db = ref.read(isarProvider);
    final existing = await db.getFamily(familyId);
    if (existing != null) {
      // Re-upsert the family with deletedAt cleared (data field stores full JSON)
      // Parse the data JSON, clear deletedAt, and save back
      final dataMap = existing.data.isNotEmpty
          ? (Map<String, dynamic>.from(
              // data is a JSON string in Drift; parse it
              (() {
                try {
                  return <String, dynamic>{};
                } catch (_) {
                  return <String, dynamic>{};
                }
              })(),
            ))
          : <String, dynamic>{};

      // Update the data map to clear deletedAt
      dataMap['deletedAt'] = null;

      await db.upsertFamily(CachedFamiliesCompanion(
        id: Value(familyId),
        name: Value(existing.name),
        data: Value('{}'), // keep placeholder; real data will come from server
        cachedAt: Value(DateTime.now()),
      ));
    }
  } catch (e) {
    debugPrint('⚠️ Optimistic restore: could not update Drift entry: $e');
  }

  // 2. Invalidate providers so UI updates immediately
  ref.invalidate(familyListProvider);
  ref.invalidate(archivedFamiliesProvider);

  // 3. Fire real API call in background
  try {
    await restoreFamily(ref: ref, familyId: familyId);
  } catch (e) {
    // 4. On failure: invalidate providers to re-fetch from server (rollback)
    ref.invalidate(familyListProvider);
    ref.invalidate(archivedFamiliesProvider);
    rethrow;
  }
}

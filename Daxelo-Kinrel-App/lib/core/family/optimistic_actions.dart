// lib/core/family/optimistic_actions.dart
//
// DAXELO KINREL — Complete Optimistic UI Action Functions
//
// WhatsApp-style "show first, confirm later" actions for ALL mutations.
// Each function immediately updates local Drift state, then fires
// the real API call in the background. On failure, the optimistic
// state is rolled back using a previous snapshot.
//
// Pattern:
//   1. Generate tempId if needed: 'pending_${DateTime.now().millisecondsSinceEpoch}'
//   2. Snapshot previous Drift state (for rollback)
//   3. Write to Drift immediately (upsertOnConflictUpdate)
//   4. Invalidate Riverpod provider -> UI rebuilds from Drift in <16ms
//   5. Fire Supabase API in background (no await on UI path)
//   6. On success -> replace tempId with real server ID in Drift, invalidate
//   7. On failure -> revert Drift to previous snapshot + show SnackBar

import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;

import 'family_provider.dart';
import 'optimistic_provider.dart';
import '../database/isar_database.dart';
import '../database/app_database.dart';
import '../../features/events/providers/events_provider.dart';

// ════════════════════════════════════════════════════════════════════
// DEBOUNCE UTILITY
// ════════════════════════════════════════════════════════════════════

/// Debounce timers for update mutations.
/// Key = '${entityType}_${entityId}', Value = active Timer.
final Map<String, Timer> _debounceTimers = {};

/// Debounce a callback by [duration]. If called again within the
/// duration, the previous call is cancelled and the timer restarts.
void _debounce(String key, Duration duration, VoidCallback callback) {
  _debounceTimers[key]?.cancel();
  _debounceTimers[key] = Timer(duration, callback);
}

/// Cancel a pending debounce timer (call after the debounced action fires).
void _cancelDebounce(String key) {
  _debounceTimers[key]?.cancel();
  _debounceTimers.remove(key);
}

// ════════════════════════════════════════════════════════════════════
// SNAPSHOT HELPERS (for rollback on failure)
// ════════════════════════════════════════════════════════════════════

/// Snapshot a CachedFamily row from Drift (for rollback).
/// Returns null if the row doesn't exist (e.g. new entry).
Future<CachedFamily?> _snapshotFamily(AppDatabase db, String id) async {
  try {
    return await db.getFamily(id);
  } catch (_) {
    return null;
  }
}

/// Snapshot a CachedPerson row from Drift (for rollback).
/// Returns null if the row doesn't exist.
Future<CachedPerson?> _snapshotPerson(AppDatabase db, String id) async {
  try {
    return await db.getPerson(id);
  } catch (_) {
    return null;
  }
}

/// Restore a CachedFamily snapshot (rollback helper).
Future<void> _restoreFamilySnapshot(
    AppDatabase db, CachedFamily? snapshot) async {
  if (snapshot == null) return;
  try {
    await db.upsertFamily(CachedFamiliesCompanion(
      id: Value(snapshot.id),
      name: Value(snapshot.name),
      data: Value(snapshot.data),
      kinFamilyId: Value(snapshot.kinFamilyId),
      username: Value(snapshot.username),
      cachedAt: Value(snapshot.cachedAt),
    ));
  } catch (e) {
    debugPrint('⚠️ Failed to restore family snapshot: $e');
  }
}

/// Restore a CachedPerson snapshot (rollback helper).
Future<void> _restorePersonSnapshot(
    AppDatabase db, CachedPerson? snapshot) async {
  if (snapshot == null) return;
  try {
    await db.upsertPerson(CachedPersonsCompanion(
      id: Value(snapshot.id),
      familyId: Value(snapshot.familyId),
      name: Value(snapshot.name),
      data: Value(snapshot.data),
      bloodGroup: Value(snapshot.bloodGroup),
      education: Value(snapshot.education),
      biography: Value(snapshot.biography),
      email: Value(snapshot.email),
      phone: Value(snapshot.phone),
      anniversaryDate: Value(snapshot.anniversaryDate),
      relationshipType: Value(snapshot.relationshipType),
      username: Value(snapshot.username),
      cachedAt: Value(snapshot.cachedAt),
    ));
  } catch (e) {
    debugPrint('⚠️ Failed to restore person snapshot: $e');
  }
}

/// JSON encode helper.
String _jsonEncode(Map<String, dynamic> data) => json.encode(data);

// ════════════════════════════════════════════════════════════════════
// 1. CREATE FAMILY OPTIMISTIC
// ════════════════════════════════════════════════════════════════════

/// Optimistic create family — inserts a temp entry into local Drift cache
/// immediately, then confirms with the server API.
///
/// Flow:
/// 1. Generate tempId: `'pending_family_${ts}'`
/// 2. Snapshot: nothing to snapshot (entry doesn't exist yet)
/// 3. Upsert into Drift cachedFamilies with full JSON data
/// 4. Invalidate familyListProvider -> UI rebuilds immediately
/// 5. Fire real API `createFamily(...)` in background
/// 6. On success: remove temp entry from Drift, invalidate provider
/// 7. On failure: remove temp entry from Drift, invalidate provider
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
  // 1. Generate temp ID
  final tempId = 'pending_family_${DateTime.now().millisecondsSinceEpoch}';

  // 2. Build the optimistic Family object
  final now = DateTime.now();
  final optimisticFamily = Family(
    id: tempId,
    name: name,
    description: description,
    primaryLanguage: primaryLanguage,
    gotra: gotra,
    originVillage: originVillage,
    region: region,
    privacyMode: privacyMode,
    avatarUrl: photoUrl,
    username: username,
    createdAt: now,
    memberCount: 0,
    generationCount: 1,
    isOnboarded: false,
  );

  // 3. Immediately upsert into Drift cachedFamilies
  try {
    final db = ref.read(isarProvider);
    await db.upsertFamily(CachedFamiliesCompanion(
      id: Value(tempId),
      name: Value(name),
      data: Value(_jsonEncode(optimisticFamily.toJson())),
      kinFamilyId: Value(null),
      username: Value(username),
      cachedAt: Value(now),
    ));
  } catch (e) {
    debugPrint('⚠️ Optimistic create family: could not insert into Drift: $e');
  }

  // 4. Invalidate providers so UI updates immediately
  ref.invalidate(familyListProvider);

  // 5. Fire real API call in background
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

    // 6. On success: remove the temp entry from Drift
    try {
      await ref.read(isarProvider).deleteFamily(tempId);
    } catch (e) {
      debugPrint(
          '⚠️ Optimistic create family: could not remove temp entry: $e');
    }
    // Invalidate so the real server data is fetched
    ref.invalidate(familyListProvider);

    return realFamily;
  } catch (e) {
    // 7. On failure: remove temp entry from Drift (rollback)
    try {
      await ref.read(isarProvider).deleteFamily(tempId);
    } catch (dbError) {
      debugPrint(
          '⚠️ Optimistic create family: could not remove temp on failure: $dbError');
    }
    ref.invalidate(familyListProvider);
    rethrow;
  }
}

// ════════════════════════════════════════════════════════════════════
// 2. DELETE FAMILY OPTIMISTIC
// ════════════════════════════════════════════════════════════════════

/// Optimistic delete family — removes from local Drift cache immediately,
/// then confirms with the server API. On failure, restores the snapshot.
///
/// Flow:
/// 1. Snapshot the current Drift row (for rollback)
/// 2. Delete from Drift cachedFamilies
/// 3. Invalidate familyListProvider
/// 4. Fire real API `deleteFamily(...)` in background
/// 5. On success: invalidate archivedFamiliesProvider
/// 6. On failure: restore snapshot, invalidate providers
Future<void> deleteFamilyOptimistic({
  required ProviderContainer container,
  required String familyId,
}) async {
  final db = container.read(isarProvider);

  // 0. Add to pending deletes FIRST — client-side guard against race condition
  //    where Supabase returns stale data before the soft-delete transaction commits.
  container.read(pendingDeleteFamilyIdsProvider.notifier).update(
        (ids) => {...ids, familyId},
      );

  // 1. Snapshot the current Drift row for rollback
  final snapshot = await _snapshotFamily(db, familyId);

  // 2. FIXED: Instead of deleting the row from Drift, mark the family as
  //    archived (set deletedAt in the JSON data). This way
  //    archivedFamiliesProvider can find it immediately in the Drift cache.
  //    Previously, db.deleteFamily() removed the row entirely, causing only
  //    the first archived family to appear (the rest were missing from Drift).
  if (snapshot != null) {
    try {
      final dataMap = snapshot.data.isNotEmpty
          ? Map<String, dynamic>.from(
              json.decode(snapshot.data) as Map<String, dynamic>)
          : <String, dynamic>{};
      dataMap['deletedAt'] = DateTime.now().toIso8601String();
      await db.upsertFamily(CachedFamiliesCompanion(
        id: Value(familyId),
        name: Value(snapshot.name),
        data: Value(json.encode(dataMap)),
        kinFamilyId: Value(snapshot.kinFamilyId),
        username: Value(snapshot.username),
        cachedAt: Value(DateTime.now()),
      ));
    } catch (e) {
      debugPrint(
          '⚠️ Optimistic delete family: could not mark archived in Drift: $e');
    }
  }

  // 3. Invalidate providers so UI updates immediately
  //    familyListProvider filters out deletedAt != null families, so the
  //    family disappears from the active list immediately.
  //    archivedFamiliesProvider will now find the family in Drift.
  container.invalidate(familyListProvider);
  container.invalidate(archivedFamiliesProvider);

  // 4. Fire real API call in background
  try {
    await deleteFamily(container: container, familyId: familyId);

    // FIXED: Wait for NestJS transaction to propagate to Supabase
    // before invalidating familyListProvider. Without this delay,
    // the Supabase query may return stale data (family not yet soft-deleted),
    // causing deleted families to briefly reappear.
    await Future.delayed(const Duration(milliseconds: 800));

    // On success: remove from pending deletes
    container.read(pendingDeleteFamilyIdsProvider.notifier).update(
          (ids) => ids.difference({familyId}),
        );
  } catch (e) {
    // On failure: remove from pending deletes and restore snapshot
    container.read(pendingDeleteFamilyIdsProvider.notifier).update(
          (ids) => ids.difference({familyId}),
        );

    // Restore the family in Drift (clear deletedAt)
    await _restoreFamilySnapshot(db, snapshot);
    container.invalidate(familyListProvider);
    container.invalidate(archivedFamiliesProvider);
    rethrow;
  }
}

// ════════════════════════════════════════════════════════════════════
// 3. RESTORE FAMILY OPTIMISTIC
// ════════════════════════════════════════════════════════════════════

/// Optimistic restore family — re-upserts the Drift entry with
/// deletedAt cleared, then confirms with the server API.
///
/// Flow:
/// 1. Snapshot current Drift state (for rollback)
/// 2. Re-upsert family with deletedAt = null in Drift data JSON
/// 3. Invalidate providers
/// 4. Fire real API `restoreFamily(...)` in background
/// 5. On failure: restore snapshot, invalidate providers
Future<void> restoreFamilyOptimistic({
  required ProviderContainer container,
  required String familyId,
}) async {
  // Mark this family as "restoring" for per-card loading spinner
  container.read(restoringFamilyIdsProvider.notifier).update(
        (ids) => {...ids, familyId},
      );

  final db = container.read(isarProvider);

  // 1. Snapshot current Drift row for rollback
  final snapshot = await _snapshotFamily(db, familyId);

  // 2. Re-upsert with deletedAt cleared
  try {
    final existing = snapshot;
    if (existing != null) {
      // Parse the data JSON, clear deletedAt, save back
      final dataMap = existing.data.isNotEmpty
          ? Map<String, dynamic>.from(
              json.decode(existing.data) as Map<String, dynamic>)
          : <String, dynamic>{};
      dataMap['deletedAt'] = null;
      dataMap['lastActivityAt'] = DateTime.now().toIso8601String();

      await db.upsertFamily(CachedFamiliesCompanion(
        id: Value(familyId),
        name: Value(existing.name),
        data: Value(_jsonEncode(dataMap)),
        kinFamilyId: Value(existing.kinFamilyId),
        username: Value(existing.username),
        cachedAt: Value(DateTime.now()),
      ));
    }
  } catch (e) {
    debugPrint('⚠️ Optimistic restore family: could not update Drift: $e');
  }

  // 3. Invalidate providers
  container.invalidate(familyListProvider);
  container.invalidate(archivedFamiliesProvider);

  // 4. Fire real API call in background
  try {
    await restoreFamily(container: container, familyId: familyId);
  } catch (e) {
    // 5. On failure: restore snapshot
    await _restoreFamilySnapshot(db, snapshot);
    container.invalidate(familyListProvider);
    container.invalidate(archivedFamiliesProvider);
    rethrow;
  } finally {
    // Always remove from restoring set
    container.read(restoringFamilyIdsProvider.notifier).update(
          (ids) => ids.difference({familyId}),
        );
  }
}

// ════════════════════════════════════════════════════════════════════
// 4. UPDATE FAMILY OPTIMISTIC
// ════════════════════════════════════════════════════════════════════

/// Optimistic update family — applies field changes to local Drift cache
/// immediately, then confirms with the server API. Debounced by 300ms
/// to prevent double-tap issues.
///
/// Flow:
/// 1. Snapshot current Drift row (for rollback)
/// 2. Merge updated fields into the data JSON
/// 3. Upsert updated row into Drift
/// 4. Invalidate familyListProvider
/// 5. Debounce 300ms, then fire API call
/// 6. On success: invalidate provider (server data replaces local)
/// 7. On failure: restore snapshot, invalidate provider
Future<void> updateFamilyOptimistic({
  required WidgetRef ref,
  required String familyId,
  String? name,
  String? description,
  String? primaryLanguage,
  String? gotra,
  String? originVillage,
  String? region,
  String? privacyMode,
  String? username,
  String? avatarUrl,
}) async {
  final db = ref.read(isarProvider);
  final debounceKey = 'update_family_$familyId';

  // 1. Snapshot current Drift row for rollback
  final snapshot = await _snapshotFamily(db, familyId);

  // 2. Merge updated fields into the existing data JSON
  try {
    final existing = snapshot;
    if (existing != null) {
      final dataMap = existing.data.isNotEmpty
          ? Map<String, dynamic>.from(
              json.decode(existing.data) as Map<String, dynamic>)
          : <String, dynamic>{};

      // Apply only the fields that are explicitly provided (non-null)
      if (name != null) dataMap['name'] = name;
      if (description != null) dataMap['description'] = description;
      if (primaryLanguage != null) dataMap['primaryLanguage'] = primaryLanguage;
      if (gotra != null) dataMap['gotra'] = gotra;
      if (originVillage != null) dataMap['originVillage'] = originVillage;
      if (region != null) dataMap['region'] = region;
      if (privacyMode != null) dataMap['privacyMode'] = privacyMode;
      if (username != null) dataMap['username'] = username;
      if (avatarUrl != null) dataMap['avatarUrl'] = avatarUrl;
      dataMap['updatedAt'] = DateTime.now().toIso8601String();

      // Determine the display name for the Drift name column
      final displayName = name ?? existing.name;

      // 3. Upsert updated row into Drift
      await db.upsertFamily(CachedFamiliesCompanion(
        id: Value(familyId),
        name: Value(displayName),
        data: Value(_jsonEncode(dataMap)),
        kinFamilyId: Value(existing.kinFamilyId),
        username: Value(username ?? existing.username),
        cachedAt: Value(DateTime.now()),
      ));
    }
  } catch (e) {
    debugPrint('⚠️ Optimistic update family: could not update Drift: $e');
  }

  // 4. Invalidate providers so UI updates immediately
  ref.invalidate(familyListProvider);
  ref.invalidate(familyDetailProvider(familyId));

  // 5. Debounce the API call by 300ms
  _debounce(debounceKey, const Duration(milliseconds: 300), () async {
    try {
      await updateFamily(
        ref: ref,
        familyId: familyId,
        name: name,
        description: description,
        primaryLanguage: primaryLanguage,
        gotra: gotra,
        originVillage: originVillage,
        region: region,
        privacyMode: privacyMode,
        username: username,
        avatarUrl: avatarUrl,
      );

      // 6. On success: invalidate provider (server data replaces local)
      ref.invalidate(familyListProvider);
      ref.invalidate(familyDetailProvider(familyId));
    } catch (e) {
      // 7. On failure: restore snapshot
      await _restoreFamilySnapshot(db, snapshot);
      ref.invalidate(familyListProvider);
      ref.invalidate(familyDetailProvider(familyId));
      debugPrint('⚠️ Optimistic update family failed, rolled back: $e');
    }
    _cancelDebounce(debounceKey);
  });
}

// ════════════════════════════════════════════════════════════════════
// 5. CREATE PERSON OPTIMISTIC
// ════════════════════════════════════════════════════════════════════

/// Optimistic create person — inserts a temp entry into local Drift cache
/// immediately, then confirms with the server API.
///
/// Also adds the person to `pendingMembersProvider` for the combined
/// members view, giving a double guarantee the person appears instantly.
///
/// Flow:
/// 1. Generate tempId: `'pending_person_${ts}'`
/// 2. Insert into Drift cachedPersons with full JSON data
/// 3. Invalidate familyMembersProvider -> UI rebuilds immediately
/// 4. Fire real API `createPerson(...)` in background
/// 5. On success: remove temp entry from Drift, invalidate provider
/// 6. On failure: remove temp entry from Drift, invalidate provider
Future<Person> createPersonOptimistic({
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
  // 1. Generate temp ID
  final tempId = 'pending_person_${DateTime.now().millisecondsSinceEpoch}';
  final now = DateTime.now();

  // Build the optimistic Person object
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
    createdAt: now,
  );

  // 2. Add to pending members provider (shows immediately in UI)
  ref
      .read(pendingMembersProvider.notifier)
      .addPending(familyId, optimisticPerson);

  // Also insert into Drift cache for offline persistence
  try {
    final db = ref.read(isarProvider);
    await db.upsertPerson(CachedPersonsCompanion(
      id: Value(tempId),
      familyId: Value(familyId),
      name: Value(name),
      data: Value(_jsonEncode(optimisticPerson.toJson())),
      cachedAt: Value(now),
    ));
  } catch (e) {
    debugPrint('⚠️ Optimistic create person: could not insert into Drift: $e');
  }

  // 3. Invalidate providers so UI updates immediately
  ref.invalidate(familyMembersProvider(familyId));
  ref.invalidate(familyDetailProvider(familyId));

  // 4. Fire real API call in background
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

    // 5. On success: remove pending entry and temp Drift row
    ref.read(pendingMembersProvider.notifier).removePending(familyId, tempId);
    try {
      await ref.read(isarProvider).deletePerson(tempId);
    } catch (e) {
      debugPrint(
          '⚠️ Optimistic create person: could not remove temp Drift entry: $e');
    }
    // createPerson already invalidates familyMembersProvider
    return realPerson;
  } catch (e) {
    // 6. On failure: remove pending entry and temp Drift row
    ref.read(pendingMembersProvider.notifier).removePending(familyId, tempId);
    try {
      await ref.read(isarProvider).deletePerson(tempId);
    } catch (dbError) {
      debugPrint(
          '⚠️ Optimistic create person: could not remove temp on failure: $dbError');
    }
    ref.invalidate(familyMembersProvider(familyId));
    ref.invalidate(familyDetailProvider(familyId));
    rethrow;
  }
}

// ════════════════════════════════════════════════════════════════════
// 6. UPDATE PERSON OPTIMISTIC
// ════════════════════════════════════════════════════════════════════

/// Optimistic update person — applies field changes to local Drift cache
/// immediately, then confirms with the server API. Debounced by 300ms
/// to prevent double-tap issues.
///
/// Flow:
/// 1. Snapshot current Drift row (for rollback)
/// 2. Merge updated fields into the data JSON
/// 3. Upsert updated row into Drift
/// 4. Invalidate familyMembersProvider
/// 5. Debounce 300ms, then fire API call
/// 6. On success: invalidate provider (server data replaces local)
/// 7. On failure: restore snapshot, invalidate provider
Future<void> updatePersonOptimistic({
  required WidgetRef ref,
  required String personId,
  required String familyId,
  String? name,
  String? gender,
  String? dateOfBirth,
  String? city,
  String? gotra,
  bool? isDeceased,
  int? birthYear,
  bool? isAnchor,
}) async {
  final db = ref.read(isarProvider);
  final debounceKey = 'update_person_$personId';

  // 1. Snapshot current Drift row for rollback
  final snapshot = await _snapshotPerson(db, personId);

  // 2. Merge updated fields into the existing data JSON
  try {
    final existing = snapshot;
    if (existing != null) {
      final dataMap = existing.data.isNotEmpty
          ? Map<String, dynamic>.from(
              json.decode(existing.data) as Map<String, dynamic>)
          : <String, dynamic>{};

      // Apply only the fields that are explicitly provided
      if (name != null) dataMap['name'] = name;
      if (gender != null) dataMap['gender'] = gender;
      if (dateOfBirth != null) dataMap['dateOfBirth'] = dateOfBirth;
      if (city != null) dataMap['city'] = city;
      if (gotra != null) dataMap['gotra'] = gotra;
      if (isDeceased != null) dataMap['isDeceased'] = isDeceased;
      if (birthYear != null) dataMap['birthYear'] = birthYear;
      if (isAnchor != null) dataMap['isAnchor'] = isAnchor;
      dataMap['updatedAt'] = DateTime.now().toIso8601String();

      // Determine the display name for the Drift name column
      final displayName = name ?? existing.name;

      // 3. Upsert updated row into Drift
      await db.upsertPerson(CachedPersonsCompanion(
        id: Value(personId),
        familyId: Value(existing.familyId),
        name: Value(displayName),
        data: Value(_jsonEncode(dataMap)),
        bloodGroup: Value(existing.bloodGroup),
        education: Value(existing.education),
        biography: Value(existing.biography),
        email: Value(existing.email),
        phone: Value(existing.phone),
        anniversaryDate: Value(existing.anniversaryDate),
        relationshipType: Value(existing.relationshipType),
        username: Value(existing.username),
        cachedAt: Value(DateTime.now()),
      ));
    }
  } catch (e) {
    debugPrint('⚠️ Optimistic update person: could not update Drift: $e');
  }

  // 4. Invalidate providers so UI updates immediately
  ref.invalidate(familyMembersProvider(familyId));
  ref.invalidate(familyDetailProvider(familyId));

  // 5. Debounce the API call by 300ms
  _debounce(debounceKey, const Duration(milliseconds: 300), () async {
    try {
      await updatePerson(
        ref: ref,
        personId: personId,
        familyId: familyId,
        name: name ?? snapshot?.name ?? '',
        gender: gender,
        dateOfBirth: dateOfBirth,
        city: city,
        gotra: gotra,
        isDeceased: isDeceased ?? false,
        birthYear: birthYear,
        isAnchor: isAnchor ?? false,
      );

      // 6. On success: invalidate provider (server data replaces local)
      ref.invalidate(familyMembersProvider(familyId));
      ref.invalidate(familyDetailProvider(familyId));
    } catch (e) {
      // 7. On failure: restore snapshot
      await _restorePersonSnapshot(db, snapshot);
      ref.invalidate(familyMembersProvider(familyId));
      ref.invalidate(familyDetailProvider(familyId));
      debugPrint('⚠️ Optimistic update person failed, rolled back: $e');
    }
    _cancelDebounce(debounceKey);
  });
}

// ════════════════════════════════════════════════════════════════════
// 7. DELETE PERSON OPTIMISTIC
// ════════════════════════════════════════════════════════════════════

/// Optimistic delete person — removes from local Drift cache immediately,
/// then confirms with the server API. On failure, restores the snapshot.
///
/// Flow:
/// 1. Snapshot current Drift row (for rollback)
/// 2. Delete from Drift cachedPersons
/// 3. Invalidate familyMembersProvider
/// 4. Fire real API `deletePerson(...)` in background
/// 5. On success: invalidate provider
/// 6. On failure: restore snapshot, invalidate provider
Future<void> deletePersonOptimistic({
  required WidgetRef ref,
  required String personId,
  required String familyId,
}) async {
  final db = ref.read(isarProvider);

  // 1. Snapshot current Drift row for rollback
  final snapshot = await _snapshotPerson(db, personId);

  // 2. Immediately delete from local Drift cache
  try {
    await db.deletePerson(personId);
  } catch (e) {
    debugPrint('⚠️ Optimistic delete person: could not remove from Drift: $e');
  }

  // 3. Invalidate providers so UI updates immediately
  ref.invalidate(familyMembersProvider(familyId));
  ref.invalidate(familyDetailProvider(familyId));

  // 4. Fire real API call in background
  try {
    await deletePerson(ref: ref, personId: personId, familyId: familyId);
    // deletePerson already invalidates familyMembersProvider
  } catch (e) {
    // 5. On failure: restore snapshot
    await _restorePersonSnapshot(db, snapshot);
    ref.invalidate(familyMembersProvider(familyId));
    ref.invalidate(familyDetailProvider(familyId));
    rethrow;
  }
}

// ════════════════════════════════════════════════════════════════════
// 8. ADD RELATIONSHIP OPTIMISTIC
// ════════════════════════════════════════════════════════════════════

/// Optimistic add relationship — inserts temp forward + inverse relationship
/// entries into local Drift cache immediately, then confirms with the
/// server API. On failure, removes the temp entries.
///
/// Flow:
/// 1. Generate tempIds for forward and inverse relationships
/// 2. Insert both into Drift cachedRelationships
/// 3. Invalidate familyRelationshipsProvider
/// 4. Fire real API `createRelationship(...)` in background
/// 5. On success: remove temp entries from Drift, invalidate provider
/// 6. On failure: remove temp entries from Drift, invalidate provider
Future<FamilyRelationship> addRelationshipOptimistic({
  required WidgetRef ref,
  required String familyId,
  required String fromPersonId,
  required String toPersonId,
  required String relationshipKey,
}) async {
  final db = ref.read(isarProvider);
  final ts = DateTime.now().millisecondsSinceEpoch;

  // 1. Generate temp IDs
  final tempForwardId = 'pending_rel_fwd_$ts';
  final tempInverseId = 'pending_rel_inv_$ts';
  final now = DateTime.now();

  // Look up the inverse relationship key
  final inverseKey = getInverseRelationshipType(relationshipKey);

  // Build optimistic relationship objects
  final forwardRel = FamilyRelationship(
    id: tempForwardId,
    familyId: familyId,
    fromPersonId: fromPersonId,
    toPersonId: toPersonId,
    relationshipKey: relationshipKey,
    direction: 'from',
    isActive: true,
    createdAt: now,
  );

  final inverseRel = FamilyRelationship(
    id: tempInverseId,
    familyId: familyId,
    fromPersonId: toPersonId,
    toPersonId: fromPersonId,
    relationshipKey: inverseKey,
    direction: 'from',
    isActive: true,
    createdAt: now,
  );

  // 2. Insert both into Drift cachedRelationships
  try {
    await db.upsertRelationship(CachedRelationshipsCompanion(
      id: Value(tempForwardId),
      familyId: Value(familyId),
      fromId: Value(fromPersonId),
      toId: Value(toPersonId),
      relationshipType: Value(relationshipKey),
      data: Value(_jsonEncode(forwardRel.toJson())),
      cachedAt: Value(now),
    ));
    await db.upsertRelationship(CachedRelationshipsCompanion(
      id: Value(tempInverseId),
      familyId: Value(familyId),
      fromId: Value(toPersonId),
      toId: Value(fromPersonId),
      relationshipType: Value(inverseKey),
      data: Value(_jsonEncode(inverseRel.toJson())),
      cachedAt: Value(now),
    ));
  } catch (e) {
    debugPrint(
        '⚠️ Optimistic add relationship: could not insert into Drift: $e');
  }

  // 3. Invalidate providers so UI updates immediately
  ref.invalidate(familyRelationshipsProvider(familyId));
  ref.invalidate(familyDetailProvider(familyId));

  // 4. Fire real API call in background
  try {
    final realRel = await createRelationship(
      ref: ref,
      familyId: familyId,
      fromPersonId: fromPersonId,
      toPersonId: toPersonId,
      relationshipKey: relationshipKey,
    );

    // 5. On success: remove temp entries from Drift
    try {
      await db.deleteRelationship(tempForwardId);
      await db.deleteRelationship(tempInverseId);
    } catch (e) {
      debugPrint(
          '⚠️ Optimistic add relationship: could not remove temp entries: $e');
    }
    // createRelationship already invalidates familyRelationshipsProvider
    return realRel;
  } catch (e) {
    // 6. On failure: remove temp entries from Drift (rollback)
    try {
      await db.deleteRelationship(tempForwardId);
      await db.deleteRelationship(tempInverseId);
    } catch (dbError) {
      debugPrint(
          '⚠️ Optimistic add relationship: could not remove temp on failure: $dbError');
    }
    ref.invalidate(familyRelationshipsProvider(familyId));
    ref.invalidate(familyDetailProvider(familyId));
    rethrow;
  }
}

// ════════════════════════════════════════════════════════════════════
// 9. DELETE RELATIONSHIP OPTIMISTIC
// ════════════════════════════════════════════════════════════════════

/// Optimistic delete relationship — removes from local Drift cache
/// immediately (both forward and inverse), then confirms with the
/// server API. On failure, invalidates providers to re-fetch from server.
///
/// Note: The `CachedRelationships` Drift table now has a `familyId` column
/// (v4 migration). The `watchRelationshipsByFamily()` stream uses this
/// column for correct family-scoped queries, with a fallback to fromId/toId
/// for rows written before the migration.
///
/// Flow:
/// 1. Find target + inverse relationship from provider data
/// 2. Delete the relationship AND its inverse from Drift by ID
/// 3. Invalidate familyRelationshipsProvider
/// 4. Fire real API `deleteRelationship(...)` in background
/// 5. On failure: invalidate providers to re-fetch from server (rollback)
Future<void> deleteRelationshipOptimistic({
  required WidgetRef ref,
  required String relationshipId,
  required String familyId,
}) async {
  final db = ref.read(isarProvider);

  // 1. Find the target and inverse relationships from provider data
  //    (CachedRelationships table lacks familyId, so we can't query by family)
  final relationshipsAsync = ref.read(familyRelationshipsProvider(familyId));
  final relationships = relationshipsAsync.valueOrNull ?? [];

  final target = relationships.where((r) => r.id == relationshipId).firstOrNull;
  final inverseRel = target != null
      ? relationships
          .where((r) =>
              r.fromPersonId == target.toPersonId &&
              r.toPersonId == target.fromPersonId &&
              r.id != target.id)
          .firstOrNull
      : null;

  // 2. Delete the relationship and its inverse from Drift
  try {
    await db.deleteRelationship(relationshipId);
    if (inverseRel != null) {
      await db.deleteRelationship(inverseRel.id);
    }
  } catch (e) {
    debugPrint(
        '⚠️ Optimistic delete relationship: could not remove from Drift: $e');
  }

  // 3. Invalidate providers so UI updates immediately
  ref.invalidate(familyRelationshipsProvider(familyId));
  ref.invalidate(familyDetailProvider(familyId));

  // 4. Fire real API call in background
  try {
    await deleteRelationship(
      ref: ref,
      relationshipId: relationshipId,
      familyId: familyId,
    );
    // deleteRelationship already invalidates providers
  } catch (e) {
    // 5. On failure: invalidate providers to re-fetch from server (rollback)
    // Since Drift snapshot may be incomplete, the safest rollback is to
    // invalidate the provider which triggers a fresh fetch from Supabase.
    ref.invalidate(familyRelationshipsProvider(familyId));
    ref.invalidate(familyDetailProvider(familyId));
    rethrow;
  }
}

// ════════════════════════════════════════════════════════════════════
// LEGACY: OPTIMISTIC ADD MEMBER (backward compatible)
// ════════════════════════════════════════════════════════════════════

/// Optimistic add member — shows in list immediately, confirms with server.
///
/// This is the original add-member function kept for backward compatibility.
/// Prefer [createPersonOptimistic] for new code, which uses the same
/// pattern as all other optimistic actions.
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
// LEGACY: OPTIMISTIC ADD EVENT (local-only, placeholder API)
// ════════════════════════════════════════════════════════════════════

/// Optimistic add family event — shows in list immediately.
///
/// Since events are currently demo/local-only, the "confirm with server"
/// step is a placeholder. The event is added immediately to the
/// [eventsProvider] state. When a real API is connected, the
/// [onConfirm] callback can fire the API call and remove the
/// event on failure.
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
  return optimisticEvent;
}

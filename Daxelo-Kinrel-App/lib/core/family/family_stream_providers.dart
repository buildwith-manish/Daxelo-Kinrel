// lib/core/family/family_stream_providers.dart
//
// DAXELO KINREL — StreamProviders for Boot-from-Drift-Cache Pattern
//
// These providers replace the one-shot FutureProvider pattern with a
// reactive stream that:
//   1. Emits Drift cache data FIRST (instant, <100ms)
//   2. Schedules a background Supabase fetch on first emission
//   3. The network result writes back to Drift, causing a new emission
//   4. UI never shows a loading spinner if cache exists
//
// Architecture:
//   Drift watch stream → decode JSON → filter soft-deleted → emit to UI
//                            ↓ (first emission only)
//                    invalidate FutureProvider
//                            ↓
//                    Supabase fetch → write to Drift → new stream emission

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;

import '../database/isar_database.dart';
import '../database/app_database.dart';
import 'family_provider.dart';

// ═══════════════════════════════════════════════════════════════════════
// FAMILY LIST STREAM PROVIDER
// ═══════════════════════════════════════════════════════════════════════

/// Reactive stream of all non-deleted families from Drift cache.
///
/// On first emission, schedules a background refresh by invalidating
/// [familyListProvider]. When the network fetch completes and writes
/// back to Drift, this stream automatically emits the updated list.
///
/// Falls back to an empty stream if [IsarDatabase] is not initialized.
final familyListStreamProvider = StreamProvider<List<Family>>((ref) {
  if (!IsarDatabase.isInitialized) {
    debugPrint('📦 familyListStreamProvider: IsarDatabase not initialized, '
        'returning empty stream');
    return Stream.value(<Family>[]);
  }

  final db = ref.read(isarProvider);
  bool hasScheduledRefresh = false;

  return db.watchAllFamilies().map((rows) {
    // Schedule a background Supabase refresh on the very first emission.
    // Using Future.microtask avoids blocking the stream and prevents
    // re-entrancy issues with Riverpod's ref.invalidate.
    if (!hasScheduledRefresh) {
      hasScheduledRefresh = true;
      Future.microtask(() {
        try {
          ref.invalidate(familyListProvider);
          debugPrint('🔄 familyListStreamProvider: scheduled background refresh');
        } catch (e) {
          debugPrint('⚠️ familyListStreamProvider: refresh schedule failed: $e');
        }
      });
    }

    // Decode each row's `data` JSON into a Family, filtering out
    // soft-deleted entries (deletedAt != null).
    final families = <Family>[];
    for (final row in rows) {
      if (row.data.isEmpty) continue;
      try {
        final dataMap = json.decode(row.data) as Map<String, dynamic>;
        // Skip soft-deleted families
        if (dataMap['deletedAt'] != null) continue;
        families.add(Family.fromJson(dataMap));
      } catch (e) {
        debugPrint('⚠️ familyListStreamProvider: failed to decode family '
            '${row.id}: $e');
      }
    }
    return families;
  });
});

// ═══════════════════════════════════════════════════════════════════════
// FAMILY MEMBERS STREAM PROVIDER
// ═══════════════════════════════════════════════════════════════════════

/// Reactive stream of non-deleted persons in a specific family from
/// Drift cache.
///
/// On first emission, schedules a background refresh by invalidating
/// [familyMembersProvider] for the given [familyId].
///
/// Falls back to an empty stream if [IsarDatabase] is not initialized.
final familyMembersStreamProvider =
    StreamProvider.family<List<Person>, String>((ref, familyId) {
  if (!IsarDatabase.isInitialized) {
    debugPrint('📦 familyMembersStreamProvider: IsarDatabase not initialized, '
        'returning empty stream for family $familyId');
    return Stream.value(<Person>[]);
  }

  final db = ref.read(isarProvider);
  bool hasScheduledRefresh = false;

  return db.watchPersonsByFamily(familyId).map((rows) {
    // Schedule background refresh on first emission
    if (!hasScheduledRefresh) {
      hasScheduledRefresh = true;
      Future.microtask(() {
        try {
          ref.invalidate(familyMembersProvider(familyId));
          debugPrint('🔄 familyMembersStreamProvider: scheduled background '
              'refresh for family $familyId');
        } catch (e) {
          debugPrint('⚠️ familyMembersStreamProvider: refresh schedule failed '
              'for family $familyId: $e');
        }
      });
    }

    // Decode each row's `data` JSON into a Person, filtering out
    // soft-deleted entries (deletedAt != null).
    final persons = <Person>[];
    for (final row in rows) {
      if (row.data.isEmpty) continue;
      try {
        final dataMap = json.decode(row.data) as Map<String, dynamic>;
        // Skip soft-deleted persons
        if (dataMap['deletedAt'] != null) continue;
        persons.add(Person.fromJson(dataMap));
      } catch (e) {
        debugPrint('⚠️ familyMembersStreamProvider: failed to decode person '
            '${row.id}: $e');
      }
    }
    return persons;
  });
});

// ═══════════════════════════════════════════════════════════════════════
// FAMILY RELATIONSHIPS STREAM PROVIDER
// ═══════════════════════════════════════════════════════════════════════

/// Reactive stream of relationships for a specific family from Drift cache.
///
/// Uses the `familyId` column in [CachedRelationships] to efficiently filter
/// relationships by family. On first emission, schedules a background refresh
/// by invalidating [familyRelationshipsProvider] for the given [familyId].
///
/// Falls back to an empty stream if [IsarDatabase] is not initialized.
final familyRelationshipsStreamProvider =
    StreamProvider.family<List<FamilyRelationship>, String>((ref, familyId) {
  if (!IsarDatabase.isInitialized) {
    debugPrint('📦 familyRelationshipsStreamProvider: IsarDatabase not '
        'initialized, returning empty stream for family $familyId');
    return Stream.value(<FamilyRelationship>[]);
  }

  final db = ref.read(isarProvider);
  bool hasScheduledRefresh = false;

  // Use watchRelationshipsByFamily() for efficient per-family stream
  return db.watchRelationshipsByFamily(familyId).map((rows) {
    // Schedule background refresh on first emission
    if (!hasScheduledRefresh) {
      hasScheduledRefresh = true;
      Future.microtask(() {
        try {
          ref.invalidate(familyRelationshipsProvider(familyId));
          debugPrint('🔄 familyRelationshipsStreamProvider: scheduled '
              'background refresh for family $familyId');
        } catch (e) {
          debugPrint('⚠️ familyRelationshipsStreamProvider: refresh schedule '
              'failed for family $familyId: $e');
        }
      });
    }

    // Decode each row's `data` JSON into a FamilyRelationship.
    // No need to filter by familyId since the stream already filters.
    final relationships = <FamilyRelationship>[];
    for (final row in rows) {
      if (row.data.isEmpty) continue;
      try {
        final dataMap = json.decode(row.data) as Map<String, dynamic>;
        relationships.add(FamilyRelationship.fromJson(dataMap));
      } catch (e) {
        debugPrint('⚠️ familyRelationshipsStreamProvider: failed to decode '
            'relationship ${row.id}: $e');
      }
    }
    return relationships;
  });
});

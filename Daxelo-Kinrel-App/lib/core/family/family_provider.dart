import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../networking/dio_client.dart';
import '../services/supabase_service.dart';
import '../config/auth_config.dart';
import '../services/analytics_service.dart';
import '../graph/graph_service.dart';
import '../database/isar_database.dart';
import '../database/repositories/offline_family_repository.dart';
import '../database/sync/cache_invalidation.dart';
import '../../features/profile/data/profile_provider.dart';

// ── Table name constants (matching Prisma schema PascalCase) ────────
const _kFamilyTable = 'Family';
const _kPersonTable = 'Person';
const _kRelationshipTable = 'Relationship';
const _kFamilyMemberTable = 'FamilyMember';

/// Generate a CUID-like ID for database inserts.
/// Since we use Supabase client directly (not Prisma), we must generate IDs ourselves.
/// Uses Random to avoid duplicate IDs when generating in a tight loop
/// (DateTime.now().microsecond doesn't change between iterations).
String _generateId() {
  final timestamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final random = Random();
  final rand = List.generate(
    16,
    (_) => random.nextInt(36),
  ).map((v) => v.toRadixString(36)).join();
  return 'c$timestamp$rand'.substring(0, 25);
}

// ── Data Models ────────────────────────────────────────────────

class Family {
  const Family({
    required this.id,
    required this.name,
    this.description,
    this.primaryLanguage,
    this.gotra,
    this.originVillage,
    this.createdBy,
    this.createdAt,
    this.familyCode,
    this.avatarUrl,
    this.region,
    this.privacyMode,
    this.isOnboarded = false,
    this.anchorPersonId,
    this.memberCount = 0,
    this.generationCount = 1,
    this.lastActivityAt,
    this.username,
    this.kinFamilyId,
    this.deletedAt,
  });

  factory Family.fromJson(Map<String, dynamic> json) {
    return Family(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? 'Unnamed Family',
      description: json['description'] as String?,
      primaryLanguage: json['primaryLanguage'] as String?,
      gotra: json['gotra'] as String?,
      originVillage: json['originVillage'] as String?,
      createdBy: json['createdBy'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
      familyCode: json['familyCode'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      region: json['region'] as String?,
      privacyMode: json['privacyMode'] as String?,
      isOnboarded: json['isOnboarded'] as bool? ?? false,
      anchorPersonId: json['anchorPersonId'] as String?,
      memberCount: json['memberCount'] as int? ?? 0,
      generationCount: json['generationCount'] as int? ?? 1,
      lastActivityAt: json['lastActivityAt'] != null
          ? DateTime.tryParse(json['lastActivityAt'].toString())
          : null,
      username: json['username'] as String?,
      kinFamilyId: json['kinFamilyId'] as String?,
      deletedAt: json['deletedAt'] != null
          ? DateTime.tryParse(json['deletedAt'].toString())
          : null,
    );
  }

  final String id;
  final String name;
  final String? description;
  final String? primaryLanguage;
  final String? gotra;
  final String? originVillage;
  final String? createdBy;
  final DateTime? createdAt;

  // Graph-First Redesign Fields
  final String? familyCode;
  final String? avatarUrl;
  final String? region;
  final String? privacyMode;
  final bool isOnboarded;
  final String? anchorPersonId;
  final int memberCount;
  final int generationCount;
  final DateTime? lastActivityAt;

  // Username system
  final String? username;

  // KIN Family ID system
  final String? kinFamilyId;

  // Soft-delete support
  final DateTime? deletedAt;

  /// Display-friendly username with @ prefix
  String get displayUsername => username != null ? '@$username' : '';

  /// Convert to JSON map for serialization/caching.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'primaryLanguage': primaryLanguage,
        'gotra': gotra,
        'originVillage': originVillage,
        'createdBy': createdBy,
        'createdAt': createdAt?.toIso8601String(),
        'familyCode': familyCode,
        'avatarUrl': avatarUrl,
        'region': region,
        'privacyMode': privacyMode,
        'isOnboarded': isOnboarded,
        'anchorPersonId': anchorPersonId,
        'memberCount': memberCount,
        'generationCount': generationCount,
        'lastActivityAt': lastActivityAt?.toIso8601String(),
        'username': username,
        'kinFamilyId': kinFamilyId,
        'deletedAt': deletedAt?.toIso8601String(),
      };
}

class Person {
  const Person({
    required this.id,
    required this.familyId,
    required this.name,
    this.gender,
    this.dateOfBirth,
    this.city,
    this.gotra,
    this.isDeceased = false,
    this.deletedAt,
    this.createdAt,
    this.birthYear,
    this.occupation,
    this.privacyLevel,
    this.notes,
    this.sideOfFamily,
    this.generationIndex = 0,
    this.isAnchor = false,
    this.photoUrl,
    this.username,
  });

  factory Person.fromJson(Map<String, dynamic> json) {
    return Person(
      id: json['id']?.toString() ?? '',
      familyId: json['familyId']?.toString() ?? '',
      name: json['name'] as String? ?? 'Unknown',
      gender: json['gender'] as String?,
      dateOfBirth: json['dateOfBirth']?.toString(),
      city: json['city'] as String?,
      gotra: json['gotra'] as String?,
      isDeceased: json['isDeceased'] as bool? ?? false,
      deletedAt: json['deletedAt']?.toString(),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
      birthYear: json['birthYear'] as int?,
      occupation: json['occupation'] as String?,
      privacyLevel: json['privacyLevel'] as String?,
      notes: json['notes'] as String?,
      sideOfFamily: json['sideOfFamily'] as String?,
      generationIndex: json['generationIndex'] as int? ?? 0,
      isAnchor: json['isAnchor'] as bool? ?? false,
      photoUrl: json['photoUrl'] as String?,
      username: json['username'] as String?,
    );
  }

  final String id;
  final String familyId;
  final String name;
  final String? gender;
  final String? dateOfBirth;
  final String? city;
  final String? gotra;
  final bool isDeceased;
  final String? deletedAt;
  final DateTime? createdAt;

  // Graph-First Redesign Fields
  final int? birthYear;
  final String? occupation;
  final String? privacyLevel;
  final String? notes;
  final String? sideOfFamily;
  final int generationIndex;
  final bool isAnchor;
  final String? photoUrl;

  // Username system
  final String? username;

  /// Display-friendly username with @ prefix
  String get displayUsername => username != null ? '@$username' : '';

  /// Convert to JSON map for serialization/caching.
  Map<String, dynamic> toJson() => {
        'id': id,
        'familyId': familyId,
        'name': name,
        'gender': gender,
        'dateOfBirth': dateOfBirth,
        'city': city,
        'gotra': gotra,
        'isDeceased': isDeceased,
        'deletedAt': deletedAt,
        'createdAt': createdAt?.toIso8601String(),
        'birthYear': birthYear,
        'occupation': occupation,
        'privacyLevel': privacyLevel,
        'notes': notes,
        'sideOfFamily': sideOfFamily,
        'generationIndex': generationIndex,
        'isAnchor': isAnchor,
        'photoUrl': photoUrl,
        'username': username,
      };

  /// Convert to GraphPerson for graph visualization.
  /// Uses the first relationship as the relationship label.
  GraphPerson toGraphPerson() {
    return GraphPerson(
      id: id,
      name: name,
      relationship:
          null, // Relationship is on the Relationship table, not Person
      generation: generationIndex,
      isDeceased: isDeceased,
      deletedAt: deletedAt,
    );
  }
}

class FamilyRelationship {
  const FamilyRelationship({
    required this.id,
    required this.familyId,
    required this.fromPersonId,
    required this.toPersonId,
    required this.relationshipKey,
    this.direction = 'from',
    this.isActive = true,
    this.label,
    this.createdAt,
  });

  factory FamilyRelationship.fromJson(Map<String, dynamic> json) {
    return FamilyRelationship(
      id: json['id']?.toString() ?? '',
      familyId: json['familyId']?.toString() ?? '',
      fromPersonId: json['fromPersonId']?.toString() ?? '',
      toPersonId: json['toPersonId']?.toString() ?? '',
      relationshipKey: json['relationshipKey'] as String? ?? '',
      direction: json['direction'] as String? ?? 'from',
      isActive: json['isActive'] as bool? ?? true,
      label: json['label'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
    );
  }

  final String id;
  final String familyId;
  final String fromPersonId;
  final String toPersonId;
  final String relationshipKey;
  final String direction;
  final bool isActive;
  final String? label;
  final DateTime? createdAt;

  ({String fromId, String toId, String type}) toGraphEdge() {
    return (fromId: fromPersonId, toId: toPersonId, type: relationshipKey);
  }

  /// Convert to JSON map for serialization/caching.
  Map<String, dynamic> toJson() => {
        'id': id,
        'familyId': familyId,
        'fromPersonId': fromPersonId,
        'toPersonId': toPersonId,
        'relationshipKey': relationshipKey,
        'direction': direction,
        'isActive': isActive,
        'label': label,
        'createdAt': createdAt?.toIso8601String(),
      };
}

class FamilyDetail {
  const FamilyDetail({
    required this.family,
    required this.members,
    required this.relationships,
  });

  final Family family;
  final List<Person> members;
  final List<FamilyRelationship> relationships;
}

/// Archived family with days-remaining info from the NestJS backend.
class ArchivedFamily {
  const ArchivedFamily({
    required this.family,
    required this.daysRemaining,
  });

  factory ArchivedFamily.fromJson(Map<String, dynamic> json) {
    return ArchivedFamily(
      family: Family.fromJson(json['family'] as Map<String, dynamic>? ?? json),
      daysRemaining: json['daysRemaining'] as int? ?? 30,
    );
  }

  final Family family;
  final int daysRemaining;

  /// The date the family was archived.
  DateTime? get archivedAt => family.deletedAt;
}

// ── Archived Families Provider ─────────────────────────────────────

/// Fetches archived (soft-deleted) families for the current user.
/// Calls `GET /api/families/archived` on the NestJS backend.
final archivedFamiliesProvider =
    FutureProvider<List<ArchivedFamily>>((ref) async {
  try {
    final dio = ref.read(dioProvider);
    final response = await dio.get('/api/families/archived');

    if (response.data is List) {
      return (response.data as List)
          .map((json) =>
              ArchivedFamily.fromJson(json as Map<String, dynamic>))
          .toList();
    }
    return [];
  } on DioException catch (e) {
    debugPrint('⚠️ archivedFamiliesProvider error: ${e.message}');
    return [];
  } catch (e) {
    debugPrint('⚠️ archivedFamiliesProvider error: $e');
    return [];
  }
});

// ── Providers ──────────────────────────────────────────────────

/// Fetches all families the current user has access to.
/// Uses FamilyMember join table to find families, with createdBy fallback.
///
/// With offline-first: Returns cached data immediately if available,
/// then refreshes from Supabase in the background.
final familyListProvider = FutureProvider<List<Family>>((ref) async {
  final isReady = ref.watch(isSupabaseReadyProvider);
  if (!isReady) {
    // Even when Supabase isn't ready, try Isar cache for offline access
    if (IsarDatabase.isInitialized) {
      try {
        final repo = ref.read(offlineFamilyRepositoryProvider);
        final cached = await repo.getFamilies();
        // ✅ FIX (BUG-01): Filter out soft-deleted families from Isar cache
        final filtered = cached.where((f) => f.deletedAt == null).toList();
        if (filtered.isNotEmpty) return filtered;
      } catch (_) {}
    }
    return [];
  }

  try {
    // Use offline-first repository if Isar is initialized
    if (IsarDatabase.isInitialized) {
      try {
        final repo = ref.read(offlineFamilyRepositoryProvider);
        final cached = await repo.getFamilies();
        // ✅ FIX (BUG-01): Filter out soft-deleted families from Isar cache
        final filtered = cached.where((f) => f.deletedAt == null).toList();
        if (filtered.isNotEmpty) return filtered;
      } catch (e) {
        debugPrint('⚠️ Offline repo getFamilies failed, falling back: $e');
        // Fall through to Supabase direct query
      }
    }

    // Fallback to direct Supabase query (original behavior)
    final client = ref.read(supabaseProvider);
    if (client == null) return [];

    // Guard against no valid session — RLS will deny queries
    // When kAuthDisabled, use MockUser.id so the query can proceed
    final userId = client.auth.currentUser?.id ??
        (kAuthDisabled ? MockUser.id : null);
    if (userId == null) {
      debugPrint('⏭️ familyListProvider skipped — no auth session');
      return [];
    }

    // 1. Get family IDs from FamilyMember join table
    final familyIds = <String>{};
    try {
      final memberEntries = await client
          .from(_kFamilyMemberTable)
          .select('familyId')
          .eq('userId', userId);
      for (final row in (memberEntries as List)) {
        familyIds.add(row['familyId'] as String);
      }
    } catch (e) {
      debugPrint('⚠️ FamilyMember lookup failed, using createdBy fallback: $e');
    }

    // 2. Also find families where user is the creator (fallback for missing FamilyMember entries)
    try {
      final createdFamilies = await client
          .from(_kFamilyTable)
          .select('id')
          .eq('createdBy', userId);
      for (final row in (createdFamilies as List)) {
        familyIds.add(row['id'] as String);
      }
    } catch (e) {
      debugPrint('⚠️ createdBy lookup failed: $e');
    }

    if (familyIds.isEmpty) return [];

    // 3. Fetch all families by IDs (deduplicated)
    // ✅ FIX (BUG-01): Filter out soft-deleted families so they don't
    // reappear after app restart
    final response = await client
        .from(_kFamilyTable)
        .select()
        .inFilter('id', familyIds.toList())
        .filter('deletedAt', 'is', null)
        .order('createdAt', ascending: false);

    final list = response as List;
    if (list.length > 20) {
      return compute(_parseFamilyList, list);
    }
    return list
        .map((json) => Family.fromJson(json as Map<String, dynamic>))
        .toList();
  } catch (e) {
    debugPrint('⚠️ familyListProvider error: $e');

    // On network error, try Isar cache as last resort
    if (IsarDatabase.isInitialized) {
      try {
        final repo = ref.read(offlineFamilyRepositoryProvider);
        final cached = await repo.getFamilies();
        // ✅ FIX (BUG-01): Filter out soft-deleted families from Isar cache
        final filtered = cached.where((f) => f.deletedAt == null).toList();
        if (filtered.isNotEmpty) return filtered;
      } catch (_) {}
    }

    return [];
  }
});

/// Fetches a single family with its members.
///
/// Composes data from familyListProvider (already fetched) + members +
/// relationships, avoiding a redundant API call that caused cascading
/// rebuild loops when familyMembersProvider or familyRelationshipsProvider
/// changed state (loading→data) and triggered a re-fetch of the family.
///
/// If the family is not found in the list (e.g., list hasn't loaded yet
/// or user navigated directly via deep link), falls back to a direct
/// Supabase query for that specific family ID.
final familyDetailProvider = FutureProvider.family<FamilyDetail?, String>((
  ref,
  familyId,
) async {
  final isReady = ref.watch(isSupabaseReadyProvider);
  if (!isReady) return null;

  try {
    final client = ref.read(supabaseProvider);
    if (client == null) return null;
    // When kAuthDisabled, allow access even without a session
    if (client.auth.currentSession == null && !kAuthDisabled) return null;

    // Try to get family from familyListProvider first (fast path).
    // Use ref.read to prevent cascading rebuilds — familyDetailProvider
    // only needs the current family data, not a rebuild every time the
    // family list changes.
    final familiesAsync = ref.read(familyListProvider);
    Family? family = familiesAsync.valueOrNull?.firstWhere(
      (f) => f.id == familyId,
    );

    // Fallback: if family not in the list (list still loading, or user
    // navigated directly via deep link / notification), fetch it directly.
    if (family == null) {
      debugPrint('🔍 familyDetailProvider: family not in list, fetching directly for ID=$familyId');
      try {
        final response = await client
            .from(_kFamilyTable)
            .select()
            .eq('id', familyId)
            .maybeSingle();
        if (response != null) {
          family = Family.fromJson(response);
        }
      } catch (e) {
        debugPrint('⚠️ familyDetailProvider direct fetch failed: $e');
      }
    }

    if (family == null) return null;

    // Await the future directly so members are always loaded before returning.
    // Using ref.read(...).valueOrNull causes a race condition: it reads the
    // provider before it finishes loading, gets null, and returns empty members.
    // The graph then shows "No Members Yet" even when members exist.
    final members = await ref
        .read(familyMembersProvider(familyId).future)
        .catchError((_) => <Person>[]);

    final relationships = await ref
        .read(familyRelationshipsProvider(familyId).future)
        .catchError((_) => <FamilyRelationship>[]);

    return FamilyDetail(
      family: family,
      members: members,
      relationships: relationships,
    );
  } catch (e) {
    debugPrint('⚠️ familyDetailProvider error: $e');
    return null;
  }
});

/// Fetches persons in a family
///
/// With offline-first: Returns cached data immediately if available,
/// then refreshes from Supabase in the background.
final familyMembersProvider = FutureProvider.family<List<Person>, String>((
  ref,
  familyId,
) async {
  final isReady = ref.watch(isSupabaseReadyProvider);
  if (!isReady) {
    // Try Isar cache for offline access
    if (IsarDatabase.isInitialized) {
      try {
        final repo = ref.read(offlineFamilyRepositoryProvider);
        final cached = await repo.getFamilyMembers(familyId);
        if (cached.isNotEmpty) return cached;
      } catch (_) {}
    }
    return [];
  }

  try {
    // Use offline-first repository if Isar is initialized
    if (IsarDatabase.isInitialized) {
      try {
        final repo = ref.read(offlineFamilyRepositoryProvider);
        return repo.getFamilyMembers(familyId);
      } catch (e) {
        debugPrint('⚠️ Offline repo getFamilyMembers failed, falling back: $e');
        // Fall through to Supabase direct query
      }
    }

    // Fallback to direct Supabase query (original behavior)
    final client = ref.read(supabaseProvider);
    if (client == null) return [];

    // Guard against no valid session — RLS will deny queries
    // When kAuthDisabled, allow access even without a session
    if (client.auth.currentSession == null && !kAuthDisabled) return [];

    final response = await client
        .from(_kPersonTable)
        .select()
        .eq('familyId', familyId)
        .filter('deletedAt', 'is', null)
        .order('createdAt', ascending: true);

    final list = response as List;
    if (list.length > 20) {
      return compute(_parsePersonList, list);
    }
    return list
        .map((json) => Person.fromJson(json as Map<String, dynamic>))
        .toList();
  } catch (e) {
    debugPrint('⚠️ familyMembersProvider error: $e');

    // On network error, try Isar cache
    if (IsarDatabase.isInitialized) {
      try {
        final repo = ref.read(offlineFamilyRepositoryProvider);
        final cached = await repo.getFamilyMembers(familyId);
        if (cached.isNotEmpty) return cached;
      } catch (_) {}
    }

    return [];
  }
});

/// Fetches relationships in a family
///
/// With offline-first: Returns cached data immediately if available,
/// then refreshes from Supabase in the background.
final familyRelationshipsProvider =
    FutureProvider.family<List<FamilyRelationship>, String>((
      ref,
      familyId,
    ) async {
      final isReady = ref.watch(isSupabaseReadyProvider);
      if (!isReady) {
        // Try Isar cache for offline access
        if (IsarDatabase.isInitialized) {
          try {
            final repo = ref.read(offlineFamilyRepositoryProvider);
            final cached = await repo.getFamilyRelationships(familyId);
            if (cached.isNotEmpty) return cached;
          } catch (_) {}
        }
        return [];
      }

      try {
        // Use offline-first repository if Isar is initialized
        if (IsarDatabase.isInitialized) {
          try {
            final repo = ref.read(offlineFamilyRepositoryProvider);
            return repo.getFamilyRelationships(familyId);
          } catch (e) {
            debugPrint('⚠️ Offline repo getFamilyRelationships failed, falling back: $e');
            // Fall through to Supabase direct query
          }
        }

        // Fallback to direct Supabase query (original behavior)
        final client = ref.read(supabaseProvider);
        if (client == null) return [];

        // Guard against no valid session — RLS will deny queries
        // When kAuthDisabled, allow access even without a session
        if (client.auth.currentSession == null && !kAuthDisabled) return [];

        // ✅ FIX: Filter by isActive = true to match NestJS backend behavior
        // The backend's RelationshipsService.findAll() filters by isActive: true
        final response = await client
            .from(_kRelationshipTable)
            .select()
            .eq('familyId', familyId)
            .eq('isActive', true)
            .order('createdAt', ascending: true);

        final list = response as List;
        if (list.length > 20) {
          return compute(_parseRelationshipList, list);
        }
        return list
            .map(
              (json) =>
                  FamilyRelationship.fromJson(json as Map<String, dynamic>),
            )
            .toList();
      } catch (e) {
        debugPrint('⚠️ familyRelationshipsProvider error: $e');

        // On network error, try Isar cache
        if (IsarDatabase.isInitialized) {
          try {
            final repo = ref.read(offlineFamilyRepositoryProvider);
            final cached = await repo.getFamilyRelationships(familyId);
            if (cached.isNotEmpty) return cached;
          } catch (_) {}
        }

        return [];
      }
    });

/// Family member count provider
/// Uses ref.read instead of ref.watch to prevent cascading rebuilds when
/// familyMembersProvider is invalidated by socket events. With ref.watch,
/// every invalidation of familyMembersProvider(id) triggers a rebuild of
/// familyMemberCountProvider(id), which can cascade into UI rebuilds that
/// re-read familyMembersProvider, creating an infinite loop on the main thread.
/// With ref.read, the count only updates when this provider's dependencies
/// (familyDetailProvider or familyListProvider) rebuild, not on every
/// individual member invalidation from socket events.
final familyMemberCountProvider = Provider.family<int, String>((ref, familyId) {
  final membersAsync = ref.read(familyMembersProvider(familyId));
  return membersAsync.valueOrNull?.length ?? 0;
});

// ── Computed Providers (Zero Rebuild Optimizations) ────────────────

/// Computed: family list count — widgets showing count don't rebuild on item update
final familyListCountProvider = Provider<AsyncValue<int>>((ref) {
  return ref.watch(familyListProvider).whenData((list) => list.length);
});

/// Computed: whether family list is loading
final familyListIsLoadingProvider = Provider<bool>((ref) {
  return ref.watch(familyListProvider).isLoading;
});

/// Computed: whether family list has error
final familyListErrorProvider = Provider<Object?>((ref) {
  return ref.watch(familyListProvider).error;
});

/// Create family in Supabase with retry for cold starts
Future<Family> createFamily({
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
  final client = ref.read(supabaseProvider);
  if (client == null) {
    throw Exception(
      'Database is not connected. Please restart the app and try again.',
    );
  }
  final userId = client.auth.currentUser?.id ??
      (kAuthDisabled ? MockUser.id : null);
  if (userId == null) {
    throw Exception('You must be signed in to create a family.');
  }

  // 1. Create the family
  final now = DateTime.now().toIso8601String();
  final familyId = _generateId();
  
  // Retry on familyCode uniqueness conflict (23505)
  Map<String, dynamic>? response;
  String effectiveUsername = username ?? '';
  for (int attempt = 0; attempt < 3; attempt++) {
    try {
      final random = Random();
      final suffix = attempt == 0 ? '' : '-${List.generate(4, (_) => random.nextInt(36).toRadixString(36)).join()}';
      final usernameWithSuffix = effectiveUsername.isNotEmpty ? '$effectiveUsername$suffix' : null;
      response = await withRetry(
        () => client
            .from(_kFamilyTable)
            .insert({
              'id': familyId,
              'name': name,
              if (description != null) 'description': description,
              'primaryLanguage': primaryLanguage ?? 'en',
              if (gotra != null) 'gotra': gotra,
              if (originVillage != null) 'originVillage': originVillage,
              if (region != null) 'region': region,
              'privacyMode': privacyMode ?? 'private',
              if (photoUrl != null) 'photoUrl': photoUrl,
              if (usernameWithSuffix != null) 'username': usernameWithSuffix,
              if (usernameWithSuffix != null) 'familyCode': usernameWithSuffix,
              'isOnboarded': false,
              'memberCount': 0,
              'generationCount': 1,
              'lastActivityAt': now,
              'createdBy': userId,
              'createdAt': now,
              'updatedAt': now,
            })
            .select()
            .maybeSingle(),
        operationName: 'Create family',
      );
      break; // success
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      if ((errStr.contains('23505') || errStr.contains('duplicate') || errStr.contains('conflict'))
          && attempt < 2) {
        continue; // retry with new suffix
      }
      rethrow;
    }
  }

  if (response == null) {
    throw Exception('Failed to create family — no data returned from server.');
  }

  final family = Family.fromJson(response);

  // 2. Add the creator as an admin FamilyMember
  try {
    await withRetry(
      () => client.from(_kFamilyMemberTable).insert({
        'id': _generateId(),
        'familyId': family.id,
        'userId': userId,
        'role': 'admin',
        'joinedAt': DateTime.now().toIso8601String(),
      }),
      operationName: 'Add creator as family member',
    );
  } catch (e) {
    // Best-effort — if FamilyMember table doesn't support this yet,
    // the family is still created. The creator can still access it via createdBy.
    debugPrint('⚠️ Could not add creator as FamilyMember: $e');
  }

  ref.invalidate(familyListProvider);

  // Invalidate the Isar cache for the family list
  if (IsarDatabase.isInitialized) {
    try {
      await CacheInvalidation.invalidateFamilyList();
    } catch (_) {}
  }

  // ✅ FIX: Refresh profile stats after family creation
  // Without this, the profile screen still shows 0 Family Trees
  try {
    await ref.read(profileProvider.notifier).loadStats();
  } catch (_) {}

  // P5-F1: Track family creation
  AnalyticsService.instance.logFamilyCreated();

  return family;
}

/// Create person in Supabase with retry for cold starts
Future<Person> createPerson({
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
  final client = ref.read(supabaseProvider);
  if (client == null) {
    throw Exception(
      'Database is not connected. Please restart the app and try again.',
    );
  }

  final personId = _generateId();
  final now = DateTime.now().toIso8601String();
  final response = await withRetry(
    () => client
        .from(_kPersonTable)
        .insert({
          'id': personId,
          'familyId': familyId,
          'name': name,
          if (gender != null) 'gender': gender,
          if (dateOfBirth != null) 'dateOfBirth': dateOfBirth,
          if (city != null) 'city': city,
          if (gotra != null) 'gotra': gotra,
          'isDeceased': isDeceased,
          'privacyLevel': 'family',
          if (birthYear != null) 'birthYear': birthYear,
          'isAnchor': isAnchor,
          'createdAt': now,
          'updatedAt': now,
        })
        .select()
        .maybeSingle(),
    operationName: 'Create person',
  );

  if (response == null) {
    throw Exception('Failed to create person — no data returned from server.');
  }
  ref.invalidate(familyMembersProvider(familyId));
  // familyDetailProvider auto-rebuilds via ref.watch on familyMembersProvider

  // ✅ FIX: Increment Family.memberCount in Supabase
  // The NestJS backend does memberCount: { increment: 1 } when adding a person.
  // We must do the same when creating via Flutter direct Supabase writes.
  try {
    await withRetry(
      () => client
          .from(_kFamilyTable)
          .update({
            'memberCount': { 'increment': 1 },
            'lastActivityAt': DateTime.now().toIso8601String(),
            'updatedAt': DateTime.now().toIso8601String(),
          })
          .eq('id', familyId),
      operationName: 'Increment memberCount',
    );
  } catch (e) {
    debugPrint('⚠️ Could not increment memberCount: $e');
  }

  // Invalidate the Isar cache for this family
  if (IsarDatabase.isInitialized) {
    try {
      await CacheInvalidation.invalidateFamily(familyId);
    } catch (_) {}
  }

  // ✅ FIX: Refresh profile stats after member addition
  // Without this, the profile screen still shows old Members Added count
  try {
    await ref.read(profileProvider.notifier).loadStats();
  } catch (_) {}

  // P5-F1: Track member addition
  AnalyticsService.instance.logMemberAdded(gender ?? 'unknown');

  // P5-F4: Record member added for retention tracking
  try {
    final prefs = await SharedPreferences.getInstance();
    final count = prefs.getInt('members_added') ?? 0;
    await prefs.setInt('members_added', count + 1);
  } catch (_) {}

  return Person.fromJson(response);
}

/// Update person in Supabase with retry for cold starts
Future<Person> updatePerson({
  required WidgetRef ref,
  required String personId,
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
  final client = ref.read(supabaseProvider);
  if (client == null) {
    throw Exception(
      'Database is not connected. Please restart the app and try again.',
    );
  }

  final response = await withRetry(
    () => client
        .from(_kPersonTable)
        .update({
          'name': name,
          if (gender != null) 'gender': gender,
          if (dateOfBirth != null) 'dateOfBirth': dateOfBirth,
          if (city != null) 'city': city,
          if (gotra != null) 'gotra': gotra,
          'isDeceased': isDeceased,
          if (birthYear != null) 'birthYear': birthYear,
          'isAnchor': isAnchor,
          'updatedAt': DateTime.now().toIso8601String(),
        })
        .eq('id', personId)
        .select()
        .maybeSingle(),
    operationName: 'Update person',
  );

  if (response == null) {
    throw Exception('Failed to update person — no data returned from server.');
  }
  ref.invalidate(familyMembersProvider(familyId));
  // familyDetailProvider auto-rebuilds via ref.watch on familyMembersProvider

  // Invalidate the Isar cache for this family
  if (IsarDatabase.isInitialized) {
    try {
      await CacheInvalidation.invalidateFamily(familyId);
    } catch (_) {}
  }

  // ✅ FIX: Refresh profile stats after person update
  try {
    await ref.read(profileProvider.notifier).loadStats();
  } catch (_) {}

  return Person.fromJson(response);
}

/// Archive (soft-delete) a family for 30 days.
///
/// Calls `DELETE /api/families/:familyId` on the NestJS backend,
/// which now archives the family instead of permanently deleting it.
/// The family can be restored within 30 days before it is
/// permanently deleted.
///
/// Throws an exception if the API call fails.
Future<void> deleteFamily({
  required WidgetRef ref,
  required String familyId,
}) async {
  try {
    final dio = ref.read(dioProvider);
    await dio.delete('/api/families/$familyId');
  } on DioException catch (e) {
    final message = e.response?.data?['message'] ?? e.message ?? 'Unknown error';
    throw Exception('Failed to archive family: $message');
  } catch (e) {
    throw Exception('Failed to archive family: $e');
  }

  // Invalidate providers to refresh UI
  ref.invalidate(familyListProvider);
  ref.invalidate(familyMembersProvider(familyId));
  ref.invalidate(familyRelationshipsProvider(familyId));
  ref.invalidate(archivedFamiliesProvider);
  // familyDetailProvider auto-rebuilds via ref.watch on above providers

  // Invalidate the Isar cache
  if (IsarDatabase.isInitialized) {
    try {
      await CacheInvalidation.invalidateFamily(familyId);
      await CacheInvalidation.invalidateFamilyList();
      // Force a fresh fetch — do NOT use cached data after archive
      await ref.read(familyListProvider.future);
    } catch (_) {}
  }

  // Refresh profile stats after family archival
  try {
    await ref.read(profileProvider.notifier).loadStats();
  } catch (_) {}
}

/// Restore an archived family.
///
/// Calls `POST /api/families/:familyId/restore` on the NestJS backend.
/// The family will reappear in the active family list.
///
/// Throws an exception if the API call fails.
Future<void> restoreFamily({
  required WidgetRef ref,
  required String familyId,
}) async {
  try {
    final dio = ref.read(dioProvider);
    await dio.post('/api/families/$familyId/restore');
  } on DioException catch (e) {
    final message = e.response?.data?['message'] ?? e.message ?? 'Unknown error';
    throw Exception('Failed to restore family: $message');
  } catch (e) {
    throw Exception('Failed to restore family: $e');
  }

  // Invalidate providers to refresh UI
  ref.invalidate(familyListProvider);
  ref.invalidate(familyMembersProvider(familyId));
  ref.invalidate(familyRelationshipsProvider(familyId));
  ref.invalidate(archivedFamiliesProvider);

  // Invalidate the Isar cache
  if (IsarDatabase.isInitialized) {
    try {
      await CacheInvalidation.invalidateFamily(familyId);
      await CacheInvalidation.invalidateFamilyList();
    } catch (_) {}
  }

  // Refresh profile stats
  try {
    await ref.read(profileProvider.notifier).loadStats();
  } catch (_) {}
}

/// Permanently delete an archived family.
///
/// Calls `DELETE /api/families/:familyId/permanent` on the NestJS backend.
/// This action **cannot be undone** — the family and all its data
/// will be permanently removed.
///
/// Throws an exception if the API call fails.
Future<void> permanentDeleteFamily({
  required WidgetRef ref,
  required String familyId,
}) async {
  try {
    final dio = ref.read(dioProvider);
    await dio.delete('/api/families/$familyId/permanent');
  } on DioException catch (e) {
    final message = e.response?.data?['message'] ?? e.message ?? 'Unknown error';
    throw Exception('Failed to permanently delete family: $message');
  } catch (e) {
    throw Exception('Failed to permanently delete family: $e');
  }

  // Invalidate providers to refresh UI
  ref.invalidate(familyListProvider);
  ref.invalidate(familyMembersProvider(familyId));
  ref.invalidate(familyRelationshipsProvider(familyId));
  ref.invalidate(archivedFamiliesProvider);

  // Invalidate the Isar cache
  if (IsarDatabase.isInitialized) {
    try {
      await CacheInvalidation.invalidateFamily(familyId);
      await CacheInvalidation.invalidateFamilyList();
    } catch (_) {}
  }

  // Refresh profile stats
  try {
    await ref.read(profileProvider.notifier).loadStats();
  } catch (_) {}
}

/// Delete person (soft delete) in Supabase with retry for cold starts
Future<void> deletePerson({
  required WidgetRef ref,
  required String personId,
  required String familyId,
}) async {
  final client = ref.read(supabaseProvider);
  if (client == null) {
    throw Exception(
      'Database is not connected. Please restart the app and try again.',
    );
  }

  final now = DateTime.now().toIso8601String();
  await withRetry(
    () => client
        .from(_kPersonTable)
        .update({'deletedAt': now, 'updatedAt': now})
        .eq('id', personId),
    operationName: 'Delete person',
  );

  ref.invalidate(familyMembersProvider(familyId));
  // familyDetailProvider auto-rebuilds via ref.watch on familyMembersProvider

  // ✅ FIX: Decrement Family.memberCount in Supabase
  // The NestJS backend decrements memberCount when a person is deleted.
  // We must do the same when deleting via Flutter direct Supabase writes.
  try {
    await withRetry(
      () => client
          .from(_kFamilyTable)
          .update({
            'memberCount': { 'decrement': 1 },
            'lastActivityAt': DateTime.now().toIso8601String(),
            'updatedAt': DateTime.now().toIso8601String(),
          })
          .eq('id', familyId),
      operationName: 'Decrement memberCount',
    );
  } catch (e) {
    debugPrint('⚠️ Could not decrement memberCount: $e');
  }

  // Invalidate the Isar cache for this family
  if (IsarDatabase.isInitialized) {
    try {
      await CacheInvalidation.invalidateFamily(familyId);
    } catch (_) {}
  }

  // ✅ FIX: Refresh profile stats after person deletion
  try {
    await ref.read(profileProvider.notifier).loadStats();
  } catch (_) {}
}

/// Create relationship in Supabase with retry for cold starts.
///
/// ✅ FIX: Now creates BIDIRECTIONAL relationships — both the forward
/// relationship (A is father of B) AND the inverse relationship
/// (B is child of A). The NestJS backend does the same. Previously,
/// only the forward direction was created, causing:
/// - Incomplete relationship graph (half the edges missing)
/// - Relationship count showing half the expected value
/// - Path finding failing between some persons
Future<FamilyRelationship> createRelationship({
  required WidgetRef ref,
  required String familyId,
  required String fromPersonId,
  required String toPersonId,
  required String relationshipKey,
}) async {
  final client = ref.read(supabaseProvider);
  if (client == null) {
    throw Exception(
      'Database is not connected. Please restart the app and try again.',
    );
  }

  final forwardRelId = _generateId();
  final inverseRelId = _generateId();
  final now = DateTime.now().toIso8601String();

  // ✅ FIX: Look up the inverse relationship key
  // e.g., "father" → "child", "husband" → "wife", "brother" → "sibling"
  final inverseKey = _relationshipInverseMap[relationshipKey] ?? relationshipKey;

  // 1. Create the forward relationship
  final response = await withRetry(
    () => client
        .from(_kRelationshipTable)
        .insert({
          'id': forwardRelId,
          'familyId': familyId,
          'fromPersonId': fromPersonId,
          'toPersonId': toPersonId,
          'relationshipKey': relationshipKey,
          'direction': 'from',
          'isActive': true,
          'createdAt': now,
          'updatedAt': now,
        })
        .select()
        .maybeSingle(),
    operationName: 'Create forward relationship',
  );

  if (response == null) {
    throw Exception(
      'Failed to create relationship — no data returned from server.',
    );
  }

  // 2. Create the inverse relationship (best-effort)
  // The NestJS backend creates both in a transaction. We do best-effort
  // since Supabase client doesn't support transactions easily.
  try {
    await withRetry(
      () => client.from(_kRelationshipTable).insert({
        'id': inverseRelId,
        'familyId': familyId,
        'fromPersonId': toPersonId,
        'toPersonId': fromPersonId,
        'relationshipKey': inverseKey,
        'direction': 'from',
        'isActive': true,
        'createdAt': now,
        'updatedAt': now,
      }),
      operationName: 'Create inverse relationship',
    );
  } catch (e) {
    // Best-effort — inverse creation failure shouldn't block the user
    debugPrint('⚠️ Could not create inverse relationship: $e');
  }

  // 3. Update Family.lastActivityAt
  try {
    await withRetry(
      () => client
          .from(_kFamilyTable)
          .update({
            'lastActivityAt': now,
            'updatedAt': now,
          })
          .eq('id', familyId),
      operationName: 'Update family activity timestamp',
    );
  } catch (e) {
    debugPrint('⚠️ Could not update family activity: $e');
  }

  ref.invalidate(familyRelationshipsProvider(familyId));
  // familyDetailProvider auto-rebuilds via ref.watch on familyRelationshipsProvider

  // Invalidate the Isar cache for this family
  if (IsarDatabase.isInitialized) {
    try {
      await CacheInvalidation.invalidateFamily(familyId);
    } catch (_) {}
  }

  // ✅ FIX: Refresh profile stats after relationship creation
  // Without this, the profile screen still shows old Relations count
  try {
    await ref.read(profileProvider.notifier).loadStats();
  } catch (_) {}

  return FamilyRelationship.fromJson(response);
}

// ── Extended Relationship Functions ────────────────────────────────

/// Inverse relationship mapping for creating bidirectional links.
/// When "A is father of B", we also need "B is child of A".
const Map<String, String> _relationshipInverseMap = {
  'father': 'child',
  'mother': 'child',
  'parent': 'child',
  'child': 'parent',
  'son': 'parent',
  'daughter': 'parent',
  'brother': 'sibling',
  'sister': 'sibling',
  'sibling': 'sibling',
  'elder_brother': 'younger_sibling',
  'younger_brother': 'elder_sibling',
  'elder_sister': 'younger_sibling',
  'younger_sister': 'elder_sibling',
  'spouse': 'spouse',
  'husband': 'wife',
  'wife': 'husband',
  'grandfather': 'grandchild',
  'grandmother': 'grandchild',
  'grandparent': 'grandchild',
  'grandchild': 'grandparent',
  'grandson': 'grandparent',
  'granddaughter': 'grandparent',
  'uncle': 'nephew_or_niece',
  'aunt': 'nephew_or_niece',
  'nephew': 'uncle_or_aunt',
  'niece': 'uncle_or_aunt',
  'cousin': 'cousin',
  'father_in_law': 'child_in_law',
  'mother_in_law': 'child_in_law',
  'son_in_law': 'parent_in_law',
  'daughter_in_law': 'parent_in_law',
  'brother_in_law': 'sibling_in_law',
  'sister_in_law': 'sibling_in_law',
  'step_father': 'step_child',
  'step_mother': 'step_child',
  'step_brother': 'step_sibling',
  'step_sister': 'step_sibling',
  'stepfather': 'stepchild',
  'stepmother': 'stepchild',
  // Compound relationships (father's side)
  'fathers_brother': 'nephew_or_niece',
  'fathers_sister': 'nephew_or_niece',
  'fathers_younger_brother': 'nephew_or_niece',
  'fathers_elder_brother': 'nephew_or_niece',
  'fathers_younger_brothers_wife': 'nephew_or_nieces_spouse',
  'fathers_elder_brothers_wife': 'nephew_or_nieces_spouse',
  'fathers_younger_brothers_son': 'cousin',
  'fathers_younger_brothers_daughter': 'cousin',
  'fathers_elder_brothers_son': 'cousin',
  'fathers_elder_brothers_daughter': 'cousin',
  'paternal_grandfather': 'grandchild',
  'paternal_grandmother': 'grandchild',
  // Compound relationships (mother's side)
  'mothers_brother': 'nephew_or_niece',
  'mothers_sister': 'nephew_or_niece',
  'mothers_brothers_wife': 'nephew_or_nieces_spouse',
  'mothers_brothers_son': 'cousin',
  'mothers_brothers_daughter': 'cousin',
  'mothers_sisters_husband': 'nephew_or_nieces_spouse',
  'mothers_sisters_son': 'cousin',
  'mothers_sisters_daughter': 'cousin',
  'maternal_grandfather': 'grandchild',
  'maternal_grandmother': 'grandchild',
  // In-laws
  'husbands_father': 'child_in_law',
  'husbands_mother': 'child_in_law',
  'husbands_elder_brother': 'sibling_in_law',
  'husbands_elder_brothers_wife': 'sibling_in_law',
  'husbands_younger_brother': 'sibling_in_law',
  'husbands_younger_brothers_wife': 'sibling_in_law',
  'husbands_sister': 'sibling_in_law',
  'wives_father': 'child_in_law',
  'wives_mother': 'child_in_law',
  'wives_brother': 'sibling_in_law',
  'wives_sister': 'sibling_in_law',
  // Grandchildren
  'sons_son': 'grandparent',
  'sons_daughter': 'grandparent',
  'daughters_son': 'grandparent',
  'daughters_daughter': 'grandparent',
  // Nephew/Niece
  'brothers_son': 'uncle_or_aunt',
  'brothers_daughter': 'uncle_or_aunt',
  'sisters_son': 'uncle_or_aunt',
  'sisters_daughter': 'uncle_or_aunt',
};

/// Get the inverse relationship type.
/// E.g., "father" → "child", "wife" → "husband"
String getInverseRelationshipType(String relationshipType) {
  final normalized = relationshipType.toLowerCase().trim();
  return _relationshipInverseMap[normalized] ?? normalized;
}

/// Create a bidirectional relationship between two persons.
///
/// When Person A has relationship X to Person B, this also creates
/// the inverse relationship from Person B to Person A.
///
/// E.g., If B is "father" of A, then A is "child" of B.
Future<FamilyRelationship> createRelationshipBetween({
  required WidgetRef ref,
  required String familyId,
  required String fromPersonId,
  required String toPersonId,
  required String relationshipKey,
}) async {
  // 1. Create the primary relationship (fromPerson → toPerson)
  final primary = await createRelationship(
    ref: ref,
    familyId: familyId,
    fromPersonId: fromPersonId,
    toPersonId: toPersonId,
    relationshipKey: relationshipKey,
  );

  // 2. Create the inverse relationship (toPerson → fromPerson)
  final inverseType = getInverseRelationshipType(relationshipKey);
  if (inverseType != relationshipKey ||
      relationshipKey == 'spouse' ||
      relationshipKey == 'cousin' ||
      relationshipKey == 'sibling') {
    try {
      await createRelationship(
        ref: ref,
        familyId: familyId,
        fromPersonId: toPersonId,
        toPersonId: fromPersonId,
        relationshipKey: inverseType,
      );
    } catch (e) {
      // If inverse creation fails, the primary is still valid.
      debugPrint('⚠️ Failed to create inverse relationship: $e');
    }
  }

  // 3. Return the primary relationship
  return primary;
}

/// Get relationship suggestions for a person based on their
/// existing relationships. Suggests common ones they're missing.
List<String> getSuggestedRelationships(
  Person person,
  List<Person> existingMembers,
) {
  final existing = <String>{};

  final suggestions = <String>[];

  const commonRelationships = [
    'father',
    'mother',
    'brother',
    'sister',
    'husband',
    'wife',
    'son',
    'daughter',
    'grandfather',
    'grandmother',
    'uncle',
    'aunt',
    'cousin',
  ];

  for (final rel in commonRelationships) {
    if (!existing.contains(rel)) {
      suggestions.add(rel);
    }
  }

  return suggestions;
}

/// Join a family by its shareable family code.
///
/// 1. Looks up the family by familyCode
/// 2. Adds the current user as a FamilyMember
/// 3. Returns the family
Future<Family> joinFamilyByCode(WidgetRef ref, String familyCode) async {
  final client = ref.read(supabaseProvider);
  if (client == null) {
    throw Exception(
      'Database is not connected. Please restart the app and try again.',
    );
  }
  final userId = client.auth.currentUser?.id;
  if (userId == null) {
    throw Exception('You must be signed in to join a family.');
  }

  // 1. Look up family by code
  final familyResponse = await withRetry(
    () => client
        .from(_kFamilyTable)
        .select()
        .eq('familyCode', familyCode)
        .maybeSingle(),
    operationName: 'Lookup family by code',
  );

  if (familyResponse == null) {
    throw Exception('Family not found. Please check the code and try again.');
  }

  final family = Family.fromJson(familyResponse);

  // 2. Check if already a member
  if (family.createdBy == userId) {
    return family; // Already a member (creator)
  }

  // 3. Add user as a family member
  try {
    await withRetry(
      () => client.from(_kFamilyMemberTable).insert({
        'id': _generateId(),
        'familyId': family.id,
        'userId': userId,
        'role': 'member',
        'joinedAt': DateTime.now().toIso8601String(),
      }),
      operationName: 'Join family',
    );
  } catch (e) {
    final errStr = e.toString();
    if (!errStr.contains('duplicate') && !errStr.contains('already exists')) {
      rethrow;
    }
  }

  ref.invalidate(familyListProvider);

  // Invalidate the Isar cache for the family list
  if (IsarDatabase.isInitialized) {
    try {
      await CacheInvalidation.invalidateFamilyList();
    } catch (_) {}
  }

  // P5-F1: Track family join
  AnalyticsService.instance.logFamilyJoined('invite_code');

  return family;
}

// ── Top-level parsing functions for compute() ──────────────────────
// These must be top-level functions (not closures or class methods)
// because Dart's compute() requires them for spawning isolates.

/// Parse a list of JSON objects into [Family] objects.
/// Used by [familyListProvider] via compute() for large lists (> 20 items).
List<Family> _parseFamilyList(List<dynamic> jsonList) {
  return jsonList
      .map((json) => Family.fromJson(json as Map<String, dynamic>))
      .toList();
}

/// Parse a list of JSON objects into [Person] objects.
/// Used by [familyMembersProvider] via compute() for large lists (> 20 items).
List<Person> _parsePersonList(List<dynamic> jsonList) {
  return jsonList
      .map((json) => Person.fromJson(json as Map<String, dynamic>))
      .toList();
}

/// Parse a list of JSON objects into [FamilyRelationship] objects.
/// Used by [familyRelationshipsProvider] via compute() for large lists (> 20 items).
List<FamilyRelationship> _parseRelationshipList(List<dynamic> jsonList) {
  return jsonList
      .map((json) => FamilyRelationship.fromJson(json as Map<String, dynamic>))
      .toList();
}

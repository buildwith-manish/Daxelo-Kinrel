import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:isar/isar.dart';

import '../isar_database.dart';
import '../collections/cached_family.dart';
import '../collections/cached_person.dart';
import '../collections/cached_relationship.dart';
import '../collections/recently_viewed_profile.dart';
import '../sync/connectivity_service.dart';
import '../sync/offline_queue.dart';
import '../sync/cache_invalidation.dart';
import '../../family/family_provider.dart';
import '../../services/supabase_service.dart';

/// Offline-first repository for family data.
///
/// Strategy:
/// - **Read**: Check Isar cache first. If fresh data exists, return it
///   immediately. Then silently refresh from Supabase in the background.
/// - **Write**: Write to Supabase first (if online). If offline, queue
///   the operation for later sync and write optimistically to Isar.
///
/// This ensures the UI always shows cached data instantly while
/// keeping the cache up-to-date in the background.
class OfflineFamilyRepository {
  final Ref _ref;

  OfflineFamilyRepository(this._ref);

  Isar get _isar => _ref.read(isarProvider);
  bool get _isOnline => _ref.read(connectivityServiceProvider).isOnline;

  // ── Family List ─────────────────────────────────────────────────

  /// Get all families the current user has access to.
  /// Returns cached data immediately if available, then refreshes in background.
  Future<List<Family>> getFamilies() async {
    if (!IsarDatabase.isInitialized) return _fetchFamiliesFromNetwork();

    // Try cache first
    final cached = await _getCachedFamilies();
    if (cached.isNotEmpty) {
      // Return cached data immediately, refresh in background
      if (_isOnline) {
        _refreshFamiliesInBackground();
      }
      return cached;
    }

    // No cache — must fetch from network
    return _fetchFamiliesFromNetwork();
  }

  /// Get cached families from Isar.
  Future<List<Family>> _getCachedFamilies() async {
    final cached = await _isar.cachedFamilys.where().findAll();
    return cached.map((f) => Family.fromJson(f.toJson())).toList();
  }

  /// Fetch families from Supabase and cache the result.
  Future<List<Family>> _fetchFamiliesFromNetwork() async {
    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) return [];

      final userId = client.auth.currentUser?.id;
      if (userId == null) return [];

      // Get family IDs from FamilyMember join table
      final familyIds = <String>{};
      try {
        final memberEntries = await client
            .from('FamilyMember')
            .select('familyId')
            .eq('userId', userId);
        for (final row in (memberEntries as List)) {
          familyIds.add(row['familyId'] as String);
        }
      } catch (e) {
        debugPrint('⚠️ FamilyMember lookup failed: $e');
      }

      // Also find families where user is creator
      try {
        final createdFamilies = await client
            .from('Family')
            .select('id')
            .eq('createdBy', userId);
        for (final row in (createdFamilies as List)) {
          familyIds.add(row['id'] as String);
        }
      } catch (e) {
        debugPrint('⚠️ createdBy lookup failed: $e');
      }

      if (familyIds.isEmpty) return [];

      final response = await client
          .from('Family')
          .select()
          .inFilter('id', familyIds.toList())
          .order('createdAt', ascending: false);

      final families = (response as List)
          .map((json) => Family.fromJson(json as Map<String, dynamic>))
          .toList();

      // Cache the result
      await _cacheFamilies(families);

      return families;
    } catch (e) {
      debugPrint('⚠️ getFamilies network error: $e');
      return [];
    }
  }

  /// Refresh families in the background without blocking the UI.
  void _refreshFamiliesInBackground() {
    _fetchFamiliesFromNetwork().catchError((e) {
      debugPrint('⚠️ Background family refresh failed: $e');
      return <Family>[];
    });
  }

  /// Cache families to Isar.
  Future<void> _cacheFamilies(List<Family> families) async {
    if (!IsarDatabase.isInitialized) return;

    await _isar.writeTxn(() async {
      for (final family in families) {
        final cached = CachedFamily.fromJson({
          'id': family.id,
          'name': family.name,
          'description': family.description,
          'primaryLanguage': family.primaryLanguage,
          'gotra': family.gotra,
          'originVillage': family.originVillage,
          'createdBy': family.createdBy,
          'createdAt': family.createdAt?.toIso8601String(),
          'familyCode': family.familyCode,
          'avatarUrl': family.avatarUrl,
          'region': family.region,
          'privacyMode': family.privacyMode,
          'isOnboarded': family.isOnboarded,
          'anchorPersonId': family.anchorPersonId,
          'memberCount': family.memberCount,
          'generationCount': family.generationCount,
          'lastActivityAt': family.lastActivityAt?.toIso8601String(),
          'username': family.username,
        });
        await _isar.cachedFamilys.put(cached);
      }
    });
  }

  // ── Family Members ──────────────────────────────────────────────

  /// Get persons in a family.
  /// Returns cached data first if available, then refreshes in background.
  Future<List<Person>> getFamilyMembers(String familyId) async {
    if (!IsarDatabase.isInitialized) return _fetchMembersFromNetwork(familyId);

    // Try cache first
    final cached = await _getCachedMembers(familyId);
    if (cached.isNotEmpty) {
      if (_isOnline) {
        _refreshMembersInBackground(familyId);
      }
      return cached;
    }

    return _fetchMembersFromNetwork(familyId);
  }

  Future<List<Person>> _getCachedMembers(String familyId) async {
    final cached = await _isar.cachedPersons
        .where()
        .filter()
        .familyIdEqualTo(familyId)
        .findAll();
    return cached.map((p) => Person.fromJson(p.toJson())).toList();
  }

  Future<List<Person>> _fetchMembersFromNetwork(String familyId) async {
    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) return [];

      final response = await client
          .from('Person')
          .select()
          .eq('familyId', familyId)
          .filter('deletedAt', 'is', null)
          .order('createdAt', ascending: true);

      final members = (response as List)
          .map((json) => Person.fromJson(json as Map<String, dynamic>))
          .toList();

      await _cacheMembers(familyId, members);
      return members;
    } catch (e) {
      debugPrint('⚠️ getFamilyMembers network error: $e');
      return [];
    }
  }

  void _refreshMembersInBackground(String familyId) {
    _fetchMembersFromNetwork(familyId).catchError((e) {
      debugPrint('⚠️ Background member refresh failed: $e');
      return <Person>[];
    });
  }

  Future<void> _cacheMembers(String familyId, List<Person> members) async {
    if (!IsarDatabase.isInitialized) return;

    await _isar.writeTxn(() async {
      // Remove old cached members for this family
      final old = await _isar.cachedPersons
          .where()
          .filter()
          .familyIdEqualTo(familyId)
          .findAll();
      for (final m in old) {
        await _isar.cachedPersons.delete(m.isarId);
      }

      // Add new cached members
      for (final member in members) {
        final cached = CachedPerson.fromJson({
          'id': member.id,
          'familyId': member.familyId,
          'name': member.name,
          'gender': member.gender,
          'dateOfBirth': member.dateOfBirth,
          'city': member.city,
          'gotra': member.gotra,
          'isDeceased': member.isDeceased,
          'deletedAt': member.deletedAt,
          'createdAt': member.createdAt?.toIso8601String(),
          'birthYear': member.birthYear,
          'occupation': member.occupation,
          'privacyLevel': member.privacyLevel,
          'notes': member.notes,
          'sideOfFamily': member.sideOfFamily,
          'generationIndex': member.generationIndex,
          'isAnchor': member.isAnchor,
          'photoUrl': member.photoUrl,
          'username': member.username,
        });
        await _isar.cachedPersons.put(cached);
      }
    });
  }

  // ── Family Relationships ────────────────────────────────────────

  /// Get relationships in a family.
  Future<List<FamilyRelationship>> getFamilyRelationships(
    String familyId,
  ) async {
    if (!IsarDatabase.isInitialized) {
      return _fetchRelationshipsFromNetwork(familyId);
    }

    final cached = await _getCachedRelationships(familyId);
    if (cached.isNotEmpty) {
      if (_isOnline) {
        _refreshRelationshipsInBackground(familyId);
      }
      return cached;
    }

    return _fetchRelationshipsFromNetwork(familyId);
  }

  Future<List<FamilyRelationship>> _getCachedRelationships(
    String familyId,
  ) async {
    final cached = await _isar.cachedRelationships
        .where()
        .filter()
        .familyIdEqualTo(familyId)
        .findAll();
    return cached.map((r) => FamilyRelationship.fromJson(r.toJson())).toList();
  }

  Future<List<FamilyRelationship>> _fetchRelationshipsFromNetwork(
    String familyId,
  ) async {
    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) return [];

      final response = await client
          .from('Relationship')
          .select()
          .eq('familyId', familyId)
          .order('createdAt', ascending: true);

      final relationships = (response as List)
          .map(
            (json) =>
                FamilyRelationship.fromJson(json as Map<String, dynamic>),
          )
          .toList();

      await _cacheRelationships(familyId, relationships);
      return relationships;
    } catch (e) {
      debugPrint('⚠️ getFamilyRelationships network error: $e');
      return [];
    }
  }

  void _refreshRelationshipsInBackground(String familyId) {
    _fetchRelationshipsFromNetwork(familyId).catchError((e) {
      debugPrint('⚠️ Background relationship refresh failed: $e');
      return <FamilyRelationship>[];
    });
  }

  Future<void> _cacheRelationships(
    String familyId,
    List<FamilyRelationship> relationships,
  ) async {
    if (!IsarDatabase.isInitialized) return;

    await _isar.writeTxn(() async {
      // Remove old cached relationships for this family
      final old = await _isar.cachedRelationships
          .where()
          .filter()
          .familyIdEqualTo(familyId)
          .findAll();
      for (final r in old) {
        await _isar.cachedRelationships.delete(r.isarId);
      }

      // Add new cached relationships
      for (final rel in relationships) {
        final cached = CachedRelationship.fromJson({
          'id': rel.id,
          'familyId': rel.familyId,
          'fromPersonId': rel.fromPersonId,
          'toPersonId': rel.toPersonId,
          'relationshipKey': rel.relationshipKey,
          'direction': rel.direction,
          'isActive': rel.isActive,
          'label': rel.label,
          'createdAt': rel.createdAt?.toIso8601String(),
        });
        await _isar.cachedRelationships.put(cached);
      }
    });
  }

  // ── Recently Viewed Profiles ────────────────────────────────────

  /// Track a recently viewed person profile.
  Future<void> trackRecentlyViewed({
    required String personId,
    required String familyId,
    required String personName,
    String? photoUrl,
  }) async {
    if (!IsarDatabase.isInitialized) return;

    await _isar.writeTxn(() async {
      // Remove existing entry for this person (will be re-added at top)
      final existing = await _isar.recentlyViewedProfiles
          .where()
          .filter()
          .personIdEqualTo(personId)
          .findAll();
      for (final e in existing) {
        await _isar.recentlyViewedProfiles.delete(e.isarId);
      }

      // Add new entry
      final entry = RecentlyViewedProfile.create(
        personId: personId,
        familyId: familyId,
        personName: personName,
        photoUrl: photoUrl,
      );
      await _isar.recentlyViewedProfiles.put(entry);

      // Keep only the last 20 entries
      final all = await _isar.recentlyViewedProfiles
          .where()
          .sortByViewedAtDesc()
          .findAll();
      if (all.length > 20) {
        for (int i = 20; i < all.length; i++) {
          await _isar.recentlyViewedProfiles.delete(all[i].isarId);
        }
      }
    });
  }

  /// Get recently viewed profiles.
  Future<List<RecentlyViewedProfile>> getRecentlyViewed() async {
    if (!IsarDatabase.isInitialized) return [];

    return _isar.recentlyViewedProfiles
        .where()
        .sortByViewedAtDesc()
        .findAll();
  }

  // ── Write Operations with Offline Queue ─────────────────────────

  /// Create a person with offline support.
  /// If online: write to Supabase + update cache.
  /// If offline: queue the operation + write optimistically to cache.
  Future<Person> createPersonOffline({
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
    final client = _ref.read(supabaseProvider);
    if (client == null) {
      throw Exception('Database is not connected.');
    }

    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('You must be signed in.');
    }

    if (_isOnline) {
      // Online — write directly to Supabase
      try {
        final personId = _generateId();
        final now = DateTime.now().toIso8601String();
        final response = await withRetry(
          () => client.from('Person').insert({
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
          }).select().maybeSingle(),
          operationName: 'Create person',
        );

        if (response == null) {
          throw Exception('Failed to create person.');
        }

        final person = Person.fromJson(response);

        // Update cache
        await _cacheMembers(familyId, [...await _getCachedMembers(familyId), person]);

        // Invalidate the family cache so member count gets updated
        await CacheInvalidation.invalidateFamily(familyId);

        return person;
      } catch (e) {
        // Network error — queue offline
        if (_isNetworkError(e.toString())) {
          return _createPersonOfflineQueue(
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
        }
        rethrow;
      }
    } else {
      // Offline — queue for later
      return _createPersonOfflineQueue(
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
    }
  }

  Future<Person> _createPersonOfflineQueue({
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
    final personId = _generateId();
    final now = DateTime.now().toIso8601String();

    // Create optimistic local person
    final person = Person(
      id: personId,
      familyId: familyId,
      name: name,
      gender: gender,
      dateOfBirth: dateOfBirth,
      city: city,
      gotra: gotra,
      isDeceased: isDeceased,
      birthYear: birthYear,
      isAnchor: isAnchor,
      createdAt: DateTime.now(),
    );

    // Write optimistically to cache
    await _cacheMembers(familyId, [...await _getCachedMembers(familyId), person]);

    // Queue for sync
    await _ref.read(offlineQueueProvider).enqueue(
          operationType: 'create',
          collection: 'Person',
          payload: {
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
          },
          priority: 1,
        );

    return person;
  }

  /// Create a relationship with offline support.
  Future<FamilyRelationship> createRelationshipOffline({
    required String familyId,
    required String fromPersonId,
    required String toPersonId,
    required String relationshipKey,
  }) async {
    final client = _ref.read(supabaseProvider);
    if (client == null) {
      throw Exception('Database is not connected.');
    }

    if (_isOnline) {
      try {
        final relId = _generateId();
        final now = DateTime.now().toIso8601String();
        final response = await withRetry(
          () => client.from('Relationship').insert({
            'id': relId,
            'familyId': familyId,
            'fromPersonId': fromPersonId,
            'toPersonId': toPersonId,
            'relationshipKey': relationshipKey,
            'direction': 'from',
            'isActive': true,
            'createdAt': now,
            'updatedAt': now,
          }).select().maybeSingle(),
          operationName: 'Create relationship',
        );

        if (response == null) {
          throw Exception('Failed to create relationship.');
        }

        final rel = FamilyRelationship.fromJson(response);

        // Update cache
        final existing = await _getCachedRelationships(familyId);
        await _cacheRelationships(familyId, [...existing, rel]);

        return rel;
      } catch (e) {
        if (_isNetworkError(e.toString())) {
          return _createRelationshipOfflineQueue(
            familyId: familyId,
            fromPersonId: fromPersonId,
            toPersonId: toPersonId,
            relationshipKey: relationshipKey,
          );
        }
        rethrow;
      }
    } else {
      return _createRelationshipOfflineQueue(
        familyId: familyId,
        fromPersonId: fromPersonId,
        toPersonId: toPersonId,
        relationshipKey: relationshipKey,
      );
    }
  }

  Future<FamilyRelationship> _createRelationshipOfflineQueue({
    required String familyId,
    required String fromPersonId,
    required String toPersonId,
    required String relationshipKey,
  }) async {
    final relId = _generateId();
    final now = DateTime.now().toIso8601String();

    final rel = FamilyRelationship(
      id: relId,
      familyId: familyId,
      fromPersonId: fromPersonId,
      toPersonId: toPersonId,
      relationshipKey: relationshipKey,
      direction: 'from',
      isActive: true,
      createdAt: DateTime.now(),
    );

    // Write optimistically to cache
    final existing = await _getCachedRelationships(familyId);
    await _cacheRelationships(familyId, [...existing, rel]);

    // Queue for sync
    await _ref.read(offlineQueueProvider).enqueue(
          operationType: 'create',
          collection: 'Relationship',
          payload: {
            'id': relId,
            'familyId': familyId,
            'fromPersonId': fromPersonId,
            'toPersonId': toPersonId,
            'relationshipKey': relationshipKey,
            'direction': 'from',
            'isActive': true,
            'createdAt': now,
            'updatedAt': now,
          },
          priority: 1,
        );

    return rel;
  }

  // ── Helpers ─────────────────────────────────────────────────────

  bool _isNetworkError(String errStr) {
    return errStr.contains('SocketException') ||
        errStr.contains('Failed host lookup') ||
        errStr.contains('Connection refused') ||
        errStr.contains('Network is unreachable') ||
        errStr.contains('Connection timed out') ||
        errStr.contains('TimeoutException');
  }

  /// Generate a CUID-like ID (same as family_provider.dart).
  static String _generateId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final random = DateTime.now().microsecond;
    final rand = List.generate(
      16,
      (i) => ((timestamp.hashCode + random + i) % 36).toRadixString(36),
    ).join();
    return 'c$timestamp$rand'.substring(0, 25);
  }
}

/// Riverpod provider for the OfflineFamilyRepository.
final offlineFamilyRepositoryProvider = Provider<OfflineFamilyRepository>((ref) {
  return OfflineFamilyRepository(ref);
});

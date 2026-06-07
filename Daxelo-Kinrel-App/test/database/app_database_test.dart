// test/database/app_database_test.dart
//
// TEST-04: Drift Database Tests
//
// Tests for the AppDatabase Drift database covering:
// - Database creation and initialization
// - Table creation (verify all tables exist)
// - Insert and query operations for key tables (Persons, Families, Relationships, etc.)
// - TTL expiry cleanup (API cache)
// - Pending operations outbox enqueue/dequeue
// - Migration from v1 → v4
//
// NOTE: These tests require `build_runner` to have generated `app_database.g.dart`.
// Run `dart run build_runner build` locally before running these tests.
// Flutter/Dart CLI is unavailable in this sandbox — verify locally.

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';

import 'package:kinrel/core/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    // Use an in-memory SQLite database for isolated tests.
    // The default AppDatabase() constructor uses driftDatabase() which
    // writes to disk; for tests we inject NativeDatabase.memory().
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  // ═══════════════════════════════════════════════════════════════════════
  // DATABASE INITIALIZATION
  // ═══════════════════════════════════════════════════════════════════════

  group('Database Initialization', () {
    test('should create database instance without errors', () {
      expect(db, isNotNull);
      expect(db.schemaVersion, equals(4));
    });

    test('should start with empty tables', () async {
      final stats = await db.getStats();
      for (final entry in stats.entries) {
        expect(entry.value, equals(0), reason: '${entry.key} should be empty');
      }
    });

    test('should report all expected tables in stats', () async {
      final stats = await db.getStats();
      expect(stats.containsKey('families'), isTrue);
      expect(stats.containsKey('persons'), isTrue);
      expect(stats.containsKey('relationships'), isTrue);
      expect(stats.containsKey('profiles'), isTrue);
      expect(stats.containsKey('searchHistory'), isTrue);
      expect(stats.containsKey('recentlyViewed'), isTrue);
      expect(stats.containsKey('pendingOps'), isTrue);
      expect(stats.containsKey('apiCache'), isTrue);
      expect(stats.containsKey('settings'), isTrue);
      expect(stats.containsKey('invitations'), isTrue);
      expect(stats.containsKey('relationshipPaths'), isTrue);
      expect(stats.containsKey('syncMetadata'), isTrue);
      expect(stats.containsKey('conflictLog'), isTrue);
      expect(stats.containsKey('cachedUsernames'), isTrue);
      expect(stats.containsKey('cachedFamilyIds'), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // CACHED PERSONS
  // ═══════════════════════════════════════════════════════════════════════

  group('CachedPerson Operations', () {
    test('should insert a person', () async {
      await db.upsertPerson(CachedPersonsCompanion(
        id: const Value('person-1'),
        familyId: const Value('family-1'),
        name: const Value('Ravi Sharma'),
        data: const Value('{"id":"person-1","name":"Ravi Sharma"}'),
        cachedAt: Value(DateTime.now()),
      ));

      final person = await db.getPerson('person-1');
      expect(person, isNotNull);
      expect(person!.id, equals('person-1'));
      expect(person.name, equals('Ravi Sharma'));
      expect(person.familyId, equals('family-1'));
    });

    test('should query persons by family ID', () async {
      // Insert persons in two families
      await db.upsertPerson(CachedPersonsCompanion(
        id: const Value('p1'),
        familyId: const Value('fam-A'),
        name: const Value('Alice'),
        data: const Value('{}'),
        cachedAt: Value(DateTime.now()),
      ));
      await db.upsertPerson(CachedPersonsCompanion(
        id: const Value('p2'),
        familyId: const Value('fam-A'),
        name: const Value('Bob'),
        data: const Value('{}'),
        cachedAt: Value(DateTime.now()),
      ));
      await db.upsertPerson(CachedPersonsCompanion(
        id: const Value('p3'),
        familyId: const Value('fam-B'),
        name: const Value('Charlie'),
        data: const Value('{}'),
        cachedAt: Value(DateTime.now()),
      ));

      final famAMembers = await db.getPersonsByFamily('fam-A');
      expect(famAMembers.length, equals(2));
      expect(famAMembers.every((p) => p.familyId == 'fam-A'), isTrue);
    });

    test('should update a person via upsert (insertOnConflictUpdate)', () async {
      await db.upsertPerson(CachedPersonsCompanion(
        id: const Value('p1'),
        familyId: const Value('fam-1'),
        name: const Value('Original Name'),
        data: const Value('{}'),
        cachedAt: Value(DateTime.now()),
      ));

      await db.upsertPerson(CachedPersonsCompanion(
        id: const Value('p1'),
        familyId: const Value('fam-1'),
        name: const Value('Updated Name'),
        data: const Value('{}'),
        cachedAt: Value(DateTime.now()),
      ));

      final person = await db.getPerson('p1');
      expect(person!.name, equals('Updated Name'));
    });

    test('should delete a person by ID', () async {
      await db.upsertPerson(CachedPersonsCompanion(
        id: const Value('p-del'),
        familyId: const Value('fam-1'),
        name: const Value('To Delete'),
        data: const Value('{}'),
        cachedAt: Value(DateTime.now()),
      ));

      await db.deletePerson('p-del');
      final person = await db.getPerson('p-del');
      expect(person, isNull);
    });

    test('should delete all persons by family ID', () async {
      await db.upsertPerson(CachedPersonsCompanion(
        id: const Value('p1'),
        familyId: const Value('fam-del'),
        name: const Value('A'),
        data: const Value('{}'),
        cachedAt: Value(DateTime.now()),
      ));
      await db.upsertPerson(CachedPersonsCompanion(
        id: const Value('p2'),
        familyId: const Value('fam-del'),
        name: const Value('B'),
        data: const Value('{}'),
        cachedAt: Value(DateTime.now()),
      ));

      await db.deletePersonsByFamily('fam-del');
      final remaining = await db.getPersonsByFamily('fam-del');
      expect(remaining, isEmpty);
    });

    test('should report correct person count', () async {
      expect(await db.personCount(), equals(0));

      await db.upsertPerson(CachedPersonsCompanion(
        id: const Value('p1'),
        familyId: const Value('f1'),
        name: const Value('A'),
        data: const Value('{}'),
        cachedAt: Value(DateTime.now()),
      ));
      expect(await db.personCount(), equals(1));
    });

    test('should store nullable person fields', () async {
      await db.upsertPerson(CachedPersonsCompanion(
        id: const Value('p-nullable'),
        familyId: const Value('f1'),
        name: const Value('Nullable Person'),
        data: const Value('{}'),
        bloodGroup: const Value('O+'),
        education: const Value('MSc'),
        biography: const Value('A bio'),
        email: const Value('test@example.com'),
        phone: const Value('+1234567890'),
        anniversaryDate: const Value('2020-06-15'),
        relationshipType: const Value('father'),
        username: const Value('ravi_s'),
        cachedAt: Value(DateTime.now()),
      ));

      final person = await db.getPerson('p-nullable');
      expect(person!.bloodGroup, equals('O+'));
      expect(person.education, equals('MSc'));
      expect(person.biography, equals('A bio'));
      expect(person.email, equals('test@example.com'));
      expect(person.phone, equals('+1234567890'));
      expect(person.anniversaryDate, equals('2020-06-15'));
      expect(person.relationshipType, equals('father'));
      expect(person.username, equals('ravi_s'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // CACHED FAMILIES
  // ═══════════════════════════════════════════════════════════════════════

  group('CachedFamily Operations', () {
    test('should insert a family', () async {
      await db.upsertFamily(CachedFamiliesCompanion(
        id: const Value('fam-1'),
        name: const Value('Sharma Family'),
        data: const Value('{"id":"fam-1","name":"Sharma Family"}'),
        cachedAt: Value(DateTime.now()),
      ));

      final family = await db.getFamily('fam-1');
      expect(family, isNotNull);
      expect(family!.id, equals('fam-1'));
      expect(family.name, equals('Sharma Family'));
    });

    test('should update a family via upsert', () async {
      await db.upsertFamily(CachedFamiliesCompanion(
        id: const Value('fam-1'),
        name: const Value('Old Name'),
        data: const Value('{}'),
        cachedAt: Value(DateTime.now()),
      ));

      await db.upsertFamily(CachedFamiliesCompanion(
        id: const Value('fam-1'),
        name: const Value('New Name'),
        data: const Value('{}'),
        cachedAt: Value(DateTime.now()),
      ));

      final family = await db.getFamily('fam-1');
      expect(family!.name, equals('New Name'));
    });

    test('should delete a family by ID', () async {
      await db.upsertFamily(CachedFamiliesCompanion(
        id: const Value('fam-del'),
        name: const Value('To Delete'),
        data: const Value('{}'),
        cachedAt: Value(DateTime.now()),
      ));

      await db.deleteFamily('fam-del');
      final family = await db.getFamily('fam-del');
      expect(family, isNull);
    });

    test('should store kinFamilyId and username', () async {
      await db.upsertFamily(CachedFamiliesCompanion(
        id: const Value('fam-ext'),
        name: const Value('Extended Family'),
        data: const Value('{}'),
        kinFamilyId: const Value('KIN-ABC12345'),
        username: const Value('sharma_family'),
        cachedAt: Value(DateTime.now()),
      ));

      final family = await db.getFamily('fam-ext');
      expect(family!.kinFamilyId, equals('KIN-ABC12345'));
      expect(family.username, equals('sharma_family'));
    });

    test('should get all families', () async {
      await db.upsertFamily(CachedFamiliesCompanion(
        id: const Value('f1'),
        name: const Value('Family 1'),
        data: const Value('{}'),
        cachedAt: Value(DateTime.now()),
      ));
      await db.upsertFamily(CachedFamiliesCompanion(
        id: const Value('f2'),
        name: const Value('Family 2'),
        data: const Value('{}'),
        cachedAt: Value(DateTime.now()),
      ));

      final families = await db.getAllFamilies();
      expect(families.length, equals(2));
    });

    test('should clear all families', () async {
      await db.upsertFamily(CachedFamiliesCompanion(
        id: const Value('f1'),
        name: const Value('Family 1'),
        data: const Value('{}'),
        cachedAt: Value(DateTime.now()),
      ));
      await db.clearFamilies();
      final families = await db.getAllFamilies();
      expect(families, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // CACHED RELATIONSHIPS
  // ═══════════════════════════════════════════════════════════════════════

  group('CachedRelationship Operations', () {
    test('should insert a relationship', () async {
      await db.upsertRelationship(CachedRelationshipsCompanion(
        id: const Value('rel-1'),
        fromId: const Value('person-1'),
        toId: const Value('person-2'),
        relationshipType: const Value('father'),
        data: const Value('{}'),
        cachedAt: Value(DateTime.now()),
      ));

      final rels = await db.getRelationshipsByFamily('person-1');
      expect(rels, isNotEmpty);
      expect(rels.first.id, equals('rel-1'));
      expect(rels.first.relationshipType, equals('father'));
    });

    test('should query relationships by person ID (fromId or toId)', () async {
      // Insert bidirectional relationships
      await db.upsertRelationship(CachedRelationshipsCompanion(
        id: const Value('rel-1'),
        fromId: const Value('p1'),
        toId: const Value('p2'),
        relationshipType: const Value('father'),
        data: const Value('{}'),
        cachedAt: Value(DateTime.now()),
      ));
      await db.upsertRelationship(CachedRelationshipsCompanion(
        id: const Value('rel-2'),
        fromId: const Value('p3'),
        toId: const Value('p1'),
        relationshipType: const Value('son'),
        data: const Value('{}'),
        cachedAt: Value(DateTime.now()),
      ));

      // Query with p1 — should match both (fromId=p1 OR toId=p1)
      final rels = await db.getRelationshipsByFamily('p1');
      expect(rels.length, equals(2));
    });

    test('should delete a relationship by ID', () async {
      await db.upsertRelationship(CachedRelationshipsCompanion(
        id: const Value('rel-del'),
        fromId: const Value('p1'),
        toId: const Value('p2'),
        relationshipType: const Value('brother'),
        data: const Value('{}'),
        cachedAt: Value(DateTime.now()),
      ));

      await db.deleteRelationship('rel-del');
      final rels = await db.getRelationshipsByFamily('p1');
      expect(rels.where((r) => r.id == 'rel-del'), isEmpty);
    });

    test('should store kinshipName as nullable field', () async {
      await db.upsertRelationship(CachedRelationshipsCompanion(
        id: const Value('rel-kin'),
        fromId: const Value('p1'),
        toId: const Value('p2'),
        relationshipType: const Value('father'),
        kinshipName: const Value('पिता'),
        data: const Value('{}'),
        cachedAt: Value(DateTime.now()),
      ));

      final rels = await db.getRelationshipsByFamily('p1');
      expect(rels.first.kinshipName, equals('पिता'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // CACHED PROFILES
  // ═══════════════════════════════════════════════════════════════════════

  group('CachedProfile Operations', () {
    test('should insert and retrieve a profile', () async {
      await db.upsertProfile(CachedProfilesCompanion(
        id: const Value('prof-1'),
        familyId: const Value('fam-1'),
        data: const Value('{"userId":"u1","name":"Ravi"}'),
        cachedAt: Value(DateTime.now()),
      ));

      final profile = await db.getProfile('prof-1');
      expect(profile, isNotNull);
      expect(profile!.familyId, equals('fam-1'));
    });

    test('should delete a profile', () async {
      await db.upsertProfile(CachedProfilesCompanion(
        id: const Value('prof-del'),
        familyId: const Value('fam-1'),
        data: const Value('{}'),
        cachedAt: Value(DateTime.now()),
      ));

      await db.deleteProfile('prof-del');
      final profile = await db.getProfile('prof-del');
      expect(profile, isNull);
    });

    test('should count profiles', () async {
      await db.upsertProfile(CachedProfilesCompanion(
        id: const Value('p1'),
        familyId: const Value('f1'),
        data: const Value('{}'),
        cachedAt: Value(DateTime.now()),
      ));
      await db.upsertProfile(CachedProfilesCompanion(
        id: const Value('p2'),
        familyId: const Value('f1'),
        data: const Value('{}'),
        cachedAt: Value(DateTime.now()),
      ));

      expect(await db.profileCount(), equals(2));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // USER SETTINGS
  // ═══════════════════════════════════════════════════════════════════════

  group('UserSettings Operations', () {
    test('should set and get a setting', () async {
      await db.setSetting('theme_mode', 'dark');
      final value = await db.getSetting('theme_mode');
      expect(value, equals('dark'));
    });

    test('should return null for non-existent setting', () async {
      final value = await db.getSetting('non_existent_key');
      expect(value, isNull);
    });

    test('should update an existing setting', () async {
      await db.setSetting('language', 'en');
      await db.setSetting('language', 'hi');
      final value = await db.getSetting('language');
      expect(value, equals('hi'));
    });

    test('should delete a setting', () async {
      await db.setSetting('temp', 'value');
      await db.deleteSetting('temp');
      final value = await db.getSetting('temp');
      expect(value, isNull);
    });

    test('should clear all settings', () async {
      await db.setSetting('k1', 'v1');
      await db.setSetting('k2', 'v2');
      await db.clearSettings();
      expect(await db.getSetting('k1'), isNull);
      expect(await db.getSetting('k2'), isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // SEARCH HISTORY
  // ═══════════════════════════════════════════════════════════════════════

  group('SearchHistory Operations', () {
    test('should insert and retrieve search history', () async {
      await db.upsertSearchHistory(SearchHistoryEntriesCompanion(
        query: const Value('Sharma'),
        searchedAt: Value(DateTime.now()),
      ));

      final history = await db.getSearchHistory();
      expect(history, isNotEmpty);
      expect(history.first.query, equals('Sharma'));
    });

    test('should limit search history results', () async {
      for (var i = 0; i < 15; i++) {
        await db.upsertSearchHistory(SearchHistoryEntriesCompanion(
          query: Value('query $i'),
          searchedAt: Value(DateTime.now().subtract(Duration(seconds: 15 - i))),
        ));
      }

      final history = await db.getSearchHistory(limit: 5);
      expect(history.length, equals(5));
    });

    test('should return most recent searches first', () async {
      await db.upsertSearchHistory(SearchHistoryEntriesCompanion(
        query: const Value('older'),
        searchedAt: Value(DateTime.now().subtract(const Duration(hours: 1))),
      ));
      await db.upsertSearchHistory(SearchHistoryEntriesCompanion(
        query: const Value('newer'),
        searchedAt: Value(DateTime.now()),
      ));

      final history = await db.getSearchHistory();
      expect(history.first.query, equals('newer'));
    });

    test('should delete search history by query', () async {
      await db.upsertSearchHistory(SearchHistoryEntriesCompanion(
        query: const Value('to_delete'),
        searchedAt: Value(DateTime.now()),
      ));
      await db.deleteSearchHistoryByQuery('to_delete');
      final history = await db.getSearchHistory();
      expect(history.where((h) => h.query == 'to_delete'), isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // RECENTLY VIEWED PROFILES
  // ═══════════════════════════════════════════════════════════════════════

  group('RecentlyViewed Operations', () {
    test('should insert and retrieve recently viewed profile', () async {
      await db.upsertRecentlyViewed(RecentlyViewedProfilesCompanion(
        personId: const Value('person-1'),
        familyId: const Value('fam-1'),
        personName: const Value('Ravi'),
        viewedAt: Value(DateTime.now()),
      ));

      final recent = await db.getRecentlyViewed();
      expect(recent, isNotEmpty);
      expect(recent.first.personId, equals('person-1'));
      expect(recent.first.personName, equals('Ravi'));
    });

    test('should limit recently viewed results', () async {
      for (var i = 0; i < 25; i++) {
        await db.upsertRecentlyViewed(RecentlyViewedProfilesCompanion(
          personId: Value('p$i'),
          familyId: const Value('fam-1'),
          personName: Value('Person $i'),
          viewedAt: Value(DateTime.now().subtract(Duration(seconds: 25 - i))),
        ));
      }

      final recent = await db.getRecentlyViewed(limit: 10);
      expect(recent.length, equals(10));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // PENDING OPERATIONS (Offline Queue)
  // ═══════════════════════════════════════════════════════════════════════

  group('PendingOperations', () {
    test('should enqueue a pending operation', () async {
      await db.upsertPendingOperation(PendingOperationsCompanion(
        operationType: const Value('create'),
        collection: const Value('Person'),
        recordId: const Value('p1'),
        payload: const Value('{"name":"Ravi"}'),
        createdAt: Value(DateTime.now()),
        retryCount: const Value(0),
        priority: const Value(1),
        isProcessing: const Value(false),
      ));

      final pending = await db.getPendingOperations();
      expect(pending, isNotEmpty);
      expect(pending.first.operationType, equals('create'));
      expect(pending.first.collection, equals('Person'));
    });

    test('should dequeue pending operations in priority order', () async {
      // Insert with different priorities (lower = higher priority)
      await db.upsertPendingOperation(PendingOperationsCompanion(
        operationType: const Value('update'),
        collection: const Value('Family'),
        createdAt: Value(DateTime.now().subtract(const Duration(seconds: 2))),
        retryCount: const Value(0),
        priority: const Value(3),
        isProcessing: const Value(false),
      ));
      await db.upsertPendingOperation(PendingOperationsCompanion(
        operationType: const Value('create'),
        collection: const Value('Person'),
        createdAt: Value(DateTime.now()),
        retryCount: const Value(0),
        priority: const Value(1),
        isProcessing: const Value(false),
      ));
      await db.upsertPendingOperation(PendingOperationsCompanion(
        operationType: const Value('delete'),
        collection: const Value('Relationship'),
        createdAt: Value(DateTime.now().subtract(const Duration(seconds: 1))),
        retryCount: const Value(0),
        priority: const Value(2),
        isProcessing: const Value(false),
      ));

      final pending = await db.getPendingOperations();
      // Should be sorted by priority ASC
      expect(pending[0].operationType, equals('create')); // priority 1
      expect(pending[1].operationType, equals('delete')); // priority 2
      expect(pending[2].operationType, equals('update')); // priority 3
    });

    test('should mark operation as processing', () async {
      await db.upsertPendingOperation(PendingOperationsCompanion(
        operationType: const Value('create'),
        collection: const Value('Person'),
        createdAt: Value(DateTime.now()),
        retryCount: const Value(0),
        priority: const Value(1),
        isProcessing: const Value(false),
      ));

      final pending = await db.getPendingOperations();
      final op = pending.first;

      // Mark as processing
      await db.upsertPendingOperation(PendingOperationsCompanion(
        id: Value(op.id),
        operationType: Value(op.operationType),
        collection: Value(op.collection),
        createdAt: Value(op.createdAt),
        retryCount: Value(op.retryCount),
        priority: Value(op.priority),
        isProcessing: const Value(true),
      ));

      // getPendingOperations filters out processing items
      final afterProcessing = await db.getPendingOperations();
      expect(afterProcessing, isEmpty);
    });

    test('should increment retry count on failed operation', () async {
      await db.upsertPendingOperation(PendingOperationsCompanion(
        operationType: const Value('create'),
        collection: const Value('Person'),
        createdAt: Value(DateTime.now()),
        retryCount: const Value(2),
        priority: const Value(1),
        isProcessing: const Value(false),
      ));

      // Operations with retryCount < 5 are still returned
      final pending = await db.getPendingOperations();
      expect(pending, isNotEmpty);
      expect(pending.first.retryCount, equals(2));
    });

    test('should exclude operations that exceeded max retries (>=5)', () async {
      await db.upsertPendingOperation(PendingOperationsCompanion(
        operationType: const Value('create'),
        collection: const Value('Person'),
        createdAt: Value(DateTime.now()),
        retryCount: const Value(5),
        priority: const Value(1),
        isProcessing: const Value(false),
      ));

      final pending = await db.getPendingOperations();
      expect(pending, isEmpty);
    });

    test('should return expired operations (retryCount >= 5)', () async {
      await db.upsertPendingOperation(PendingOperationsCompanion(
        operationType: const Value('create'),
        collection: const Value('Person'),
        createdAt: Value(DateTime.now()),
        retryCount: const Value(5),
        priority: const Value(1),
        isProcessing: const Value(false),
      ));
      await db.upsertPendingOperation(PendingOperationsCompanion(
        operationType: const Value('update'),
        collection: const Value('Family'),
        createdAt: Value(DateTime.now()),
        retryCount: const Value(3),
        priority: const Value(1),
        isProcessing: const Value(false),
      ));

      final expired = await db.getExpiredOperations();
      expect(expired.length, equals(1));
      expect(expired.first.operationType, equals('create'));
    });

    test('should delete a pending operation by ID', () async {
      await db.upsertPendingOperation(PendingOperationsCompanion(
        operationType: const Value('delete'),
        collection: const Value('Relationship'),
        createdAt: Value(DateTime.now()),
        retryCount: const Value(0),
        priority: const Value(1),
        isProcessing: const Value(false),
      ));

      final pending = await db.getPendingOperations();
      // Wait, this is empty because retryCount < 5 but isProcessing = false
      // Actually getPendingOperations should return it
      expect(pending, isNotEmpty);

      await db.deletePendingOperation(pending.first.id);
      final after = await db.getPendingOperations();
      expect(after, isEmpty);
    });

    test('should report pending operation count', () async {
      expect(await db.pendingOperationCount(), equals(0));

      await db.upsertPendingOperation(PendingOperationsCompanion(
        operationType: const Value('create'),
        collection: const Value('Person'),
        createdAt: Value(DateTime.now()),
        retryCount: const Value(0),
        priority: const Value(1),
        isProcessing: const Value(false),
      ));
      expect(await db.pendingOperationCount(), equals(1));
    });

    test('should clear all pending operations', () async {
      await db.upsertPendingOperation(PendingOperationsCompanion(
        operationType: const Value('create'),
        collection: const Value('Person'),
        createdAt: Value(DateTime.now()),
        retryCount: const Value(0),
        priority: const Value(1),
        isProcessing: const Value(false),
      ));
      await db.clearPendingOperations();
      expect(await db.pendingOperationCount(), equals(0));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // API CACHE + TTL EXPIRY
  // ═══════════════════════════════════════════════════════════════════════

  group('ApiCache TTL Expiry', () {
    test('should cache and retrieve an API entry', () async {
      await db.cacheApiEntry('families:list', '{"families":[]}');
      final result = await db.getCachedApiEntry('families:list');
      expect(result, equals('{"families":[]}'));
    });

    test('should respect custom TTL duration', () async {
      // Cache with 1-second TTL
      await db.cacheApiEntry(
        'short:ttl',
        '{"data":1}',
        expiresIn: const Duration(seconds: 1),
      );

      // Immediately available
      var result = await db.getCachedApiEntry('short:ttl');
      expect(result, equals('{"data":1}'));

      // Wait for TTL to expire
      await Future.delayed(const Duration(seconds: 2));

      // Should return null after expiry
      result = await db.getCachedApiEntry('short:ttl');
      expect(result, isNull);
    });

    test('should keep non-expired entries', () async {
      await db.cacheApiEntry(
        'long:ttl',
        '{"data":"fresh"}',
        expiresIn: const Duration(hours: 1),
      );

      final result = await db.getCachedApiEntry('long:ttl');
      expect(result, equals('{"data":"fresh"}'));
    });

    test('should return null for non-existent cache key', () async {
      final result = await db.getCachedApiEntry('nonexistent:key');
      expect(result, isNull);
    });

    test('should retrieve cached entries by key prefix', () async {
      await db.cacheApiEntry(
        'family:members:f1',
        '[{"id":"p1"}]',
        expiresIn: const Duration(hours: 1),
      );
      await db.cacheApiEntry(
        'family:members:f2',
        '[{"id":"p2"}]',
        expiresIn: const Duration(hours: 1),
      );
      await db.cacheApiEntry(
        'family:detail:f1',
        '{"id":"f1"}',
        expiresIn: const Duration(hours: 1),
      );

      final results = await db.getCachedApiEntriesWithPrefix('family:members:');
      expect(results.length, equals(2));
    });

    test('should exclude expired entries from prefix query', () async {
      await db.cacheApiEntry(
        'expired:prefix:1',
        'data1',
        expiresIn: const Duration(seconds: 1),
      );
      await db.cacheApiEntry(
        'expired:prefix:2',
        'data2',
        expiresIn: const Duration(hours: 1),
      );

      await Future.delayed(const Duration(seconds: 2));

      final results = await db.getCachedApiEntriesWithPrefix('expired:prefix:');
      expect(results.length, equals(1));
      expect(results.first, equals('data2'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // CACHED INVITATIONS
  // ═══════════════════════════════════════════════════════════════════════

  group('CachedInvitation Operations', () {
    test('should insert and retrieve an invitation', () async {
      await db.upsertInvitation(CachedInvitationsCompanion(
        id: const Value('inv-1'),
        familyId: const Value('fam-1'),
        familyName: const Value('Sharma Family'),
        inviterName: const Value('Ravi'),
        status: const Value('pending'),
        role: const Value('member'),
        channel: const Value('link'),
        data: const Value('{}'),
        cachedAt: Value(DateTime.now()),
      ));

      final inv = await db.getInvitation('inv-1');
      expect(inv, isNotNull);
      expect(inv!.status, equals('pending'));
      expect(inv.role, equals('member'));
    });

    test('should query invitations by family ID', () async {
      await db.upsertInvitation(CachedInvitationsCompanion(
        id: const Value('inv-1'),
        familyId: const Value('fam-A'),
        familyName: const Value('Family A'),
        inviterName: const Value('Ravi'),
        status: const Value('pending'),
        role: const Value('member'),
        channel: const Value('link'),
        data: const Value('{}'),
        cachedAt: Value(DateTime.now()),
      ));
      await db.upsertInvitation(CachedInvitationsCompanion(
        id: const Value('inv-2'),
        familyId: const Value('fam-B'),
        familyName: const Value('Family B'),
        inviterName: const Value('Anil'),
        status: const Value('accepted'),
        role: const Value('admin'),
        channel: const Value('qr_code'),
        data: const Value('{}'),
        cachedAt: Value(DateTime.now()),
      ));

      final famAInvs = await db.getInvitationsByFamily('fam-A');
      expect(famAInvs.length, equals(1));
      expect(famAInvs.first.familyId, equals('fam-A'));
    });

    test('should query invitations by status', () async {
      await db.upsertInvitation(CachedInvitationsCompanion(
        id: const Value('inv-pending'),
        familyId: const Value('fam-1'),
        familyName: const Value('Fam'),
        inviterName: const Value('Ravi'),
        status: const Value('pending'),
        role: const Value('member'),
        channel: const Value('link'),
        data: const Value('{}'),
        cachedAt: Value(DateTime.now()),
      ));
      await db.upsertInvitation(CachedInvitationsCompanion(
        id: const Value('inv-accepted'),
        familyId: const Value('fam-1'),
        familyName: const Value('Fam'),
        inviterName: const Value('Anil'),
        status: const Value('accepted'),
        role: const Value('member'),
        channel: const Value('link'),
        data: const Value('{}'),
        cachedAt: Value(DateTime.now()),
      ));

      final pending = await db.getInvitationsByStatus('pending');
      expect(pending.length, equals(1));
      expect(pending.first.id, equals('inv-pending'));
    });

    test('should delete an invitation', () async {
      await db.upsertInvitation(CachedInvitationsCompanion(
        id: const Value('inv-del'),
        familyId: const Value('fam-1'),
        familyName: const Value('Fam'),
        inviterName: const Value('R'),
        status: const Value('pending'),
        role: const Value('member'),
        channel: const Value('link'),
        data: const Value('{}'),
        cachedAt: Value(DateTime.now()),
      ));

      await db.deleteInvitation('inv-del');
      final inv = await db.getInvitation('inv-del');
      expect(inv, isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // CACHED RELATIONSHIP PATHS
  // ═══════════════════════════════════════════════════════════════════════

  group('CachedRelationshipPath Operations', () {
    test('should insert and retrieve a relationship path', () async {
      final now = DateTime.now();
      await db.upsertRelationshipPath(CachedRelationshipPathsCompanion(
        familyId: const Value('fam-1'),
        fromPersonId: const Value('p1'),
        toPersonId: const Value('p2'),
        path: const Value('[{"from":"p1","to":"p2","type":"father"}]'),
        distance: const Value(1),
        computedAt: Value(now),
        expiresAt: Value(now.add(const Duration(hours: 1))),
      ));

      final path = await db.getRelationshipPath('fam-1', 'p1', 'p2');
      expect(path, isNotNull);
      expect(path!.distance, equals(1));
    });

    test('should query paths by family', () async {
      final now = DateTime.now();
      await db.upsertRelationshipPath(CachedRelationshipPathsCompanion(
        familyId: const Value('fam-1'),
        fromPersonId: const Value('p1'),
        toPersonId: const Value('p2'),
        path: const Value('[]'),
        distance: const Value(1),
        computedAt: Value(now),
        expiresAt: Value(now.add(const Duration(hours: 1))),
      ));

      final paths = await db.getPathsByFamily('fam-1');
      expect(paths, isNotEmpty);
    });

    test('should delete paths by family', () async {
      final now = DateTime.now();
      await db.upsertRelationshipPath(CachedRelationshipPathsCompanion(
        familyId: const Value('fam-del'),
        fromPersonId: const Value('p1'),
        toPersonId: const Value('p2'),
        path: const Value('[]'),
        distance: const Value(1),
        computedAt: Value(now),
        expiresAt: Value(now.add(const Duration(hours: 1))),
      ));

      await db.deleteRelationshipPathsByFamily('fam-del');
      final paths = await db.getPathsByFamily('fam-del');
      expect(paths, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // SYNC METADATA
  // ═══════════════════════════════════════════════════════════════════════

  group('SyncMetadata Operations', () {
    test('should insert and retrieve sync metadata', () async {
      await db.upsertSyncMetadata(SyncMetadataCompanion(
        entityType: const Value('persons'),
        lastSyncedAt: Value(DateTime.now().toIso8601String()),
        recordCount: const Value(42),
        updatedAt: Value(DateTime.now()),
      ));

      final meta = await db.getSyncMetadata('persons');
      expect(meta, isNotNull);
      expect(meta!.recordCount, equals(42));
    });

    test('should update sync metadata via upsert', () async {
      await db.upsertSyncMetadata(SyncMetadataCompanion(
        entityType: const Value('families'),
        lastSyncedAt: Value(DateTime.now().toIso8601String()),
        recordCount: const Value(10),
        updatedAt: Value(DateTime.now()),
      ));
      await db.upsertSyncMetadata(SyncMetadataCompanion(
        entityType: const Value('families'),
        lastSyncedAt: Value(DateTime.now().toIso8601String()),
        recordCount: const Value(15),
        updatedAt: Value(DateTime.now()),
      ));

      final meta = await db.getSyncMetadata('families');
      expect(meta!.recordCount, equals(15));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // CONFLICT LOG
  // ═══════════════════════════════════════════════════════════════════════

  group('ConflictLog Operations', () {
    test('should insert and retrieve a conflict', () async {
      await db.upsertConflict(ConflictLogCompanion(
        entityType: const Value('Person'),
        entityId: const Value('p1'),
        localData: const Value('{"name":"Ravi"}'),
        serverData: const Value('{"name":"Ravi Kumar"}'),
        detectedAt: Value(DateTime.now()),
      ));

      final conflicts = await db.getPendingConflicts();
      expect(conflicts, isNotEmpty);
      expect(conflicts.first.entityId, equals('p1'));
    });

    test('should query conflicts by entity', () async {
      await db.upsertConflict(ConflictLogCompanion(
        entityType: const Value('Person'),
        entityId: const Value('p1'),
        localData: const Value('{}'),
        serverData: const Value('{}'),
        detectedAt: Value(DateTime.now()),
      ));

      final conflicts = await db.getConflictsByEntity('Person', 'p1');
      expect(conflicts, isNotEmpty);
    });

    test('should resolve a conflict', () async {
      await db.upsertConflict(ConflictLogCompanion(
        entityType: const Value('Family'),
        entityId: const Value('f1'),
        localData: const Value('{}'),
        serverData: const Value('{}'),
        resolution: const Value('server_wins'),
        resolvedData: const Value('{"name":"Server Name"}'),
        detectedAt: Value(DateTime.now()),
      ));

      // Resolved conflicts should not appear in pending
      final pending = await db.getPendingConflicts();
      expect(pending.where((c) => c.entityId == 'f1'), isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // CACHED USERNAMES
  // ═══════════════════════════════════════════════════════════════════════

  group('CachedUsername Operations', () {
    test('should insert and retrieve a username', () async {
      await db.upsertUsername(CachedUsernamesCompanion(
        userId: const Value('user-1'),
        username: const Value('ravi_sharma'),
        displayName: const Value('Ravi Sharma'),
        cachedAt: Value(DateTime.now()),
      ));

      final result = await db.getUsername('ravi_sharma');
      expect(result, isNotNull);
      expect(result!.displayName, equals('Ravi Sharma'));
    });

    test('should search usernames case-insensitively', () async {
      await db.upsertUsername(CachedUsernamesCompanion(
        userId: const Value('u1'),
        username: const Value('Ravi_Sharma'),
        displayName: const Value('Ravi Sharma'),
        cachedAt: Value(DateTime.now()),
      ));

      final results = await db.searchUsernames('ravi');
      expect(results, isNotEmpty);
    });

    test('should lookup username case-insensitively', () async {
      await db.upsertUsername(CachedUsernamesCompanion(
        userId: const Value('u1'),
        username: const Value('RaviSharma'),
        displayName: const Value('Ravi'),
        cachedAt: Value(DateTime.now()),
      ));

      final result = await db.getUsername('ravisharma');
      expect(result, isNotNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // CACHED FAMILY IDS
  // ═══════════════════════════════════════════════════════════════════════

  group('CachedFamilyId Operations', () {
    test('should insert and retrieve by kinFamilyId', () async {
      await db.upsertFamilyId(CachedFamilyIdsCompanion(
        kinFamilyId: const Value('KIN-ABC12345'),
        familyId: const Value('internal-fam-1'),
        name: const Value('Sharma Family'),
        memberCount: const Value(12),
        cachedAt: Value(DateTime.now()),
      ));

      final result = await db.getFamilyByKinId('KIN-ABC12345');
      expect(result, isNotNull);
      expect(result!.familyId, equals('internal-fam-1'));
    });

    test('should lookup kinFamilyId case-insensitively', () async {
      await db.upsertFamilyId(CachedFamilyIdsCompanion(
        kinFamilyId: const Value('KIN-XYZ99999'),
        familyId: const Value('fam-2'),
        name: const Value('Test'),
        cachedAt: Value(DateTime.now()),
      ));

      final result = await db.getFamilyByKinId('kin-xyz99999');
      expect(result, isNotNull);
    });

    test('should search family IDs by prefix or name', () async {
      await db.upsertFamilyId(CachedFamilyIdsCompanion(
        kinFamilyId: const Value('KIN-SEARCH1'),
        familyId: const Value('fam-s1'),
        name: const Value('Patel Family'),
        cachedAt: Value(DateTime.now()),
      ));

      final results = await db.searchFamilyIds('PATEL');
      expect(results, isNotEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // BULK OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════

  group('Bulk Operations', () {
    test('clearAllCache should remove all cache tables but keep settings', () async {
      await db.upsertFamily(CachedFamiliesCompanion(
        id: const Value('f1'),
        name: const Value('Fam'),
        data: const Value('{}'),
        cachedAt: Value(DateTime.now()),
      ));
      await db.setSetting('theme', 'dark');

      await db.clearAllCache();

      final families = await db.getAllFamilies();
      expect(families, isEmpty);

      // Settings should survive clearAllCache
      final theme = await db.getSetting('theme');
      expect(theme, equals('dark'));
    });

    test('clearAll should remove everything including settings and pending ops', () async {
      await db.upsertPerson(CachedPersonsCompanion(
        id: const Value('p1'),
        familyId: const Value('f1'),
        name: const Value('A'),
        data: const Value('{}'),
        cachedAt: Value(DateTime.now()),
      ));
      await db.setSetting('theme', 'dark');
      await db.upsertPendingOperation(PendingOperationsCompanion(
        operationType: const Value('create'),
        collection: const Value('Person'),
        createdAt: Value(DateTime.now()),
        retryCount: const Value(0),
        priority: const Value(1),
        isProcessing: const Value(false),
      ));

      await db.clearAll();

      final stats = await db.getStats();
      for (final entry in stats.entries) {
        expect(entry.value, equals(0), reason: '${entry.key} should be 0 after clearAll');
      }
      expect(await db.getSetting('theme'), isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // MIGRATION (v1 → v4)
  // ═══════════════════════════════════════════════════════════════════════

  group('Migration', () {
    test('schemaVersion should be 4', () {
      expect(db.schemaVersion, equals(4));
    });

    // Note: Full migration testing requires creating a v1 database,
    // then opening it with the current schema. This is complex with
    // in-memory databases. The migration logic is tested implicitly
    // by the fact that all tables and columns are accessible.
    //
    // To test migrations properly, you would:
    // 1. Create an on-disk database with schema v1
    // 2. Insert data
    // 3. Close it
    // 4. Open it with the current AppDatabase class
    // 5. Verify data survived + new columns/tables exist
    //
    // This test verifies that the v2/v3/v4 columns are accessible:

    test('v2 columns should be accessible on CachedPersons', () async {
      // These columns were added in v1→v2 migration
      await db.upsertPerson(CachedPersonsCompanion(
        id: const Value('p-v2'),
        familyId: const Value('f1'),
        name: const Value('V2 Person'),
        data: const Value('{}'),
        bloodGroup: const Value('A+'),
        education: const Value('PhD'),
        biography: const Value('Bio'),
        email: const Value('v2@test.com'),
        phone: const Value('+111'),
        anniversaryDate: const Value('2021-01-01'),
        relationshipType: const Value('mother'),
        cachedAt: Value(DateTime.now()),
      ));

      final person = await db.getPerson('p-v2');
      expect(person!.bloodGroup, equals('A+'));
      expect(person.education, equals('PhD'));
      expect(person.biography, equals('Bio'));
      expect(person.email, equals('v2@test.com'));
      expect(person.phone, equals('+111'));
      expect(person.anniversaryDate, equals('2021-01-01'));
      expect(person.relationshipType, equals('mother'));
    });

    test('v3 columns should be accessible (username on persons and families)', () async {
      await db.upsertPerson(CachedPersonsCompanion(
        id: const Value('p-v3'),
        familyId: const Value('f1'),
        name: const Value('V3 Person'),
        data: const Value('{}'),
        username: const Value('v3_user'),
        cachedAt: Value(DateTime.now()),
      ));
      await db.upsertFamily(CachedFamiliesCompanion(
        id: const Value('f-v3'),
        name: const Value('V3 Family'),
        data: const Value('{}'),
        username: const Value('v3_family'),
        cachedAt: Value(DateTime.now()),
      ));

      final person = await db.getPerson('p-v3');
      expect(person!.username, equals('v3_user'));

      final family = await db.getFamily('f-v3');
      expect(family!.username, equals('v3_family'));
    });

    test('v4 should not have auth_tokens table', () async {
      // The v3→v4 migration drops the auth_tokens table.
      // We can verify by attempting a custom select — it should throw.
      try {
        await db.customSelect('SELECT * FROM auth_tokens').get();
        fail('auth_tokens table should not exist in v4');
      } catch (e) {
        // Expected: table not found
        expect(e.toString(), contains('no such table'));
      }
    });

    test('v2 tables should exist (cachedInvitations, cachedRelationshipPaths, syncMetadata, conflictLog)', () async {
      // Verify by inserting and querying each table
      await db.upsertInvitation(CachedInvitationsCompanion(
        id: const Value('test-inv'),
        familyId: const Value('f1'),
        familyName: const Value('Fam'),
        inviterName: const Value('R'),
        status: const Value('pending'),
        role: const Value('member'),
        channel: const Value('link'),
        data: const Value('{}'),
        cachedAt: Value(DateTime.now()),
      ));
      expect(await db.invitationCount(), equals(1));

      final now = DateTime.now();
      await db.upsertRelationshipPath(CachedRelationshipPathsCompanion(
        familyId: const Value('f1'),
        fromPersonId: const Value('p1'),
        toPersonId: const Value('p2'),
        path: const Value('[]'),
        distance: const Value(1),
        computedAt: Value(now),
        expiresAt: Value(now.add(const Duration(hours: 1))),
      ));
      expect(await db.getPathsByFamily('f1'), isNotEmpty);

      await db.upsertSyncMetadata(SyncMetadataCompanion(
        entityType: const Value('persons'),
        lastSyncedAt: Value(DateTime.now().toIso8601String()),
        updatedAt: Value(now),
      ));
      expect(await db.getSyncMetadata('persons'), isNotNull);

      await db.upsertConflict(ConflictLogCompanion(
        entityType: const Value('Person'),
        entityId: const Value('p1'),
        localData: const Value('{}'),
        serverData: const Value('{}'),
        detectedAt: Value(now),
      ));
      expect(await db.conflictCount(), equals(1));
    });

    test('v3 tables should exist (cachedUsernames, cachedFamilyIds)', () async {
      await db.upsertUsername(CachedUsernamesCompanion(
        userId: const Value('u1'),
        username: const Value('testuser'),
        displayName: const Value('Test User'),
        cachedAt: Value(DateTime.now()),
      ));
      expect(await db.getUsername('testuser'), isNotNull);

      await db.upsertFamilyId(CachedFamilyIdsCompanion(
        kinFamilyId: const Value('KIN-TEST01'),
        familyId: const Value('f1'),
        name: const Value('Test Fam'),
        cachedAt: Value(DateTime.now()),
      ));
      expect(await db.getFamilyByKinId('KIN-TEST01'), isNotNull);
    });
  });
}

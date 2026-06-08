// test/database/app_database_test.dart
//
// Drift Database Tests
//
// Tests for the AppDatabase Drift database covering:
// - Database creation and initialization
// - Table creation (verify all tables exist)
// - Insert and query operations for key tables
// - TTL expiry cleanup (API cache)
// - Pending operations outbox enqueue/dequeue
//
// NOTE: These tests require `build_runner` to have generated `app_database.g.dart`.
// Run `dart run build_runner build` locally before running these tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';

import 'package:kinrel/core/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
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

    test('should update a person via upsert', () async {
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

    test('should query relationships by person ID', () async {
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
        kinshipName: const Value('\u092A\u093F\u0924\u093E'),
        data: const Value('{}'),
        cachedAt: Value(DateTime.now()),
      ));

      final rels = await db.getRelationshipsByFamily('p1');
      expect(rels.first.kinshipName, equals('\u092A\u093F\u0924\u093E'));
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
      expect(pending[0].operationType, equals('create'));
      expect(pending[1].operationType, equals('delete'));
      expect(pending[2].operationType, equals('update'));
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

      await db.upsertPendingOperation(PendingOperationsCompanion(
        id: Value(op.id),
        operationType: Value(op.operationType),
        collection: Value(op.collection),
        createdAt: Value(op.createdAt),
        retryCount: Value(op.retryCount),
        priority: Value(op.priority),
        isProcessing: const Value(true),
      ));

      final afterProcessing = await db.getPendingOperations();
      expect(afterProcessing, isEmpty);
    });

    test('should exclude operations that exceeded max retries', () async {
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

    test('should return expired operations', () async {
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
      await db.cacheApiEntry(
        'short:ttl',
        '{"data":1}',
        expiresIn: const Duration(seconds: 1),
      );

      var result = await db.getCachedApiEntry('short:ttl');
      expect(result, equals('{"data":1}'));

      await Future.delayed(const Duration(seconds: 2));

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

    test('should delete sync metadata', () async {
      await db.upsertSyncMetadata(SyncMetadataCompanion(
        entityType: const Value('to_delete'),
        lastSyncedAt: Value(DateTime.now().toIso8601String()),
        updatedAt: Value(DateTime.now()),
      ));

      await db.deleteSyncMetadata('to_delete');
      final meta = await db.getSyncMetadata('to_delete');
      expect(meta, isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // CONFLICT LOG
  // ═══════════════════════════════════════════════════════════════════════

  group('ConflictLog Operations', () {
    test('should insert and retrieve a conflict', () async {
      await db.upsertConflict(ConflictLogCompanion(
        entityType: const Value('persons'),
        entityId: const Value('p1'),
        localData: const Value('{"name":"local"}'),
        serverData: const Value('{"name":"server"}'),
        detectedAt: Value(DateTime.now()),
      ));

      final conflicts = await db.getPendingConflicts();
      expect(conflicts, isNotEmpty);
      expect(conflicts.first.entityType, equals('persons'));
    });

    test('should count conflicts', () async {
      await db.upsertConflict(ConflictLogCompanion(
        entityType: const Value('persons'),
        entityId: const Value('p1'),
        localData: const Value('{}'),
        serverData: const Value('{}'),
        detectedAt: Value(DateTime.now()),
      ));

      expect(await db.conflictCount(), equals(1));
    });

    test('should clear conflict log', () async {
      await db.upsertConflict(ConflictLogCompanion(
        entityType: const Value('persons'),
        entityId: const Value('p1'),
        localData: const Value('{}'),
        serverData: const Value('{}'),
        detectedAt: Value(DateTime.now()),
      ));
      await db.clearConflictLog();
      expect(await db.conflictCount(), equals(0));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // CACHED USERNAMES
  // ═══════════════════════════════════════════════════════════════════════

  group('CachedUsernames Operations', () {
    test('should insert and retrieve a username', () async {
      await db.upsertUsername(CachedUsernamesCompanion(
        userId: const Value('u1'),
        username: const Value('ravi_s'),
        displayName: const Value('Ravi Sharma'),
        cachedAt: Value(DateTime.now()),
      ));

      final user = await db.getUsername('ravi_s');
      expect(user, isNotNull);
      expect(user!.displayName, equals('Ravi Sharma'));
    });

    test('should search usernames by query', () async {
      await db.upsertUsername(CachedUsernamesCompanion(
        userId: const Value('u1'),
        username: const Value('ravi_sharma'),
        displayName: const Value('Ravi Sharma'),
        cachedAt: Value(DateTime.now()),
      ));
      await db.upsertUsername(CachedUsernamesCompanion(
        userId: const Value('u2'),
        username: const Value('ravi_patel'),
        displayName: const Value('Ravi Patel'),
        cachedAt: Value(DateTime.now()),
      ));

      final results = await db.searchUsernames('ravi');
      expect(results.length, equals(2));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // CACHED FAMILY IDS
  // ═══════════════════════════════════════════════════════════════════════

  group('CachedFamilyIds Operations', () {
    test('should insert and retrieve a family ID', () async {
      await db.upsertFamilyId(CachedFamilyIdsCompanion(
        familyId: const Value('f1'),
        kinFamilyId: const Value('KIN-ABC123'),
        name: const Value('Sharma Family'),
        cachedAt: Value(DateTime.now()),
      ));

      final family = await db.getFamilyByKinId('KIN-ABC123');
      expect(family, isNotNull);
      expect(family!.name, equals('Sharma Family'));
    });

    test('should search family IDs by query', () async {
      await db.upsertFamilyId(CachedFamilyIdsCompanion(
        familyId: const Value('f1'),
        kinFamilyId: const Value('KIN-SHARMA'),
        name: const Value('Sharma Family'),
        cachedAt: Value(DateTime.now()),
      ));

      final results = await db.searchFamilyIds('SHARMA');
      expect(results, isNotEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // BULK OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════

  group('Bulk Operations', () {
    test('should clear all cache', () async {
      await db.upsertFamily(CachedFamiliesCompanion(
        id: const Value('f1'),
        name: const Value('Family 1'),
        data: const Value('{}'),
        cachedAt: Value(DateTime.now()),
      ));
      await db.upsertPerson(CachedPersonsCompanion(
        id: const Value('p1'),
        familyId: const Value('f1'),
        name: const Value('Person 1'),
        data: const Value('{}'),
        cachedAt: Value(DateTime.now()),
      ));

      await db.clearAllCache();
      final stats = await db.getStats();
      expect(stats['families'], equals(0));
      expect(stats['persons'], equals(0));
    });

    test('should clear all including settings and pending ops', () async {
      await db.setSetting('key1', 'val1');
      await db.upsertPendingOperation(PendingOperationsCompanion(
        operationType: const Value('create'),
        collection: const Value('Person'),
        createdAt: Value(DateTime.now()),
        retryCount: const Value(0),
        priority: const Value(1),
        isProcessing: const Value(false),
      ));

      await db.clearAll();
      expect(await db.getSetting('key1'), isNull);
      expect(await db.pendingOperationCount(), equals(0));
    });
  });
}

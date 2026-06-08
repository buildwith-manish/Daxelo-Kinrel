// GENERATED — app_database.dart
// ignore_for_file: type=lint
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

// ═══════════════════════════════════════════════════════════════════════
// TABLE DEFINITIONS
// ═══════════════════════════════════════════════════════════════════════

class CachedProfiles extends Table {
  TextColumn get id => text()();
  TextColumn get familyId => text()();
  TextColumn get data => text()();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class CachedRelationships extends Table {
  TextColumn get id => text()();
  TextColumn get fromId => text()();
  TextColumn get toId => text()();
  TextColumn get relationshipType => text()();
  TextColumn get kinshipName => text().nullable()();
  TextColumn get data => text()();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class CachedFamilies extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get data => text()();
  TextColumn get kinFamilyId => text().nullable()();
  TextColumn get username => text().nullable()();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class CachedPersons extends Table {
  TextColumn get id => text()();
  TextColumn get familyId => text()();
  TextColumn get name => text()();
  TextColumn get data => text()();
  TextColumn get bloodGroup => text().nullable()();
  TextColumn get education => text().nullable()();
  TextColumn get biography => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get anniversaryDate => text().nullable()();
  TextColumn get relationshipType => text().nullable()();
  TextColumn get username => text().nullable()();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

// AuthTokens table REMOVED in v4 — tokens now stored exclusively in
// flutter_secure_storage (SecureStorageService). SQLite is not a secure
// token store. See BUG-09 / Phase 0.9.

class UserSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

class SearchHistoryEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get query => text()();
  DateTimeColumn get searchedAt => dateTime()();
  TextColumn get filterType => text().withDefault(const Constant('all'))();
  IntColumn get resultCount => integer().withDefault(const Constant(0))();
}

class RecentlyViewedProfiles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get personId => text()();
  TextColumn get familyId => text()();
  TextColumn get personName => text()();
  TextColumn get photoUrl => text().nullable()();
  DateTimeColumn get viewedAt => dateTime()();
}

class PendingOperations extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get operationType => text()();
  TextColumn get collection => text()();
  TextColumn get recordId => text().nullable()();
  TextColumn get payload => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastRetryAt => dateTime().nullable()();
  IntColumn get priority => integer().withDefault(const Constant(1))();
  BoolColumn get isProcessing => boolean().withDefault(const Constant(false))();
}

class ApiCacheEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get key => text()();
  TextColumn get responseBody => text()();
  DateTimeColumn get cachedAt => dateTime()();
  IntColumn get ttlSeconds => integer()();
  TextColumn get eTag => text().nullable()();
}

// ═══════════════════════════════════════════════════════════════════════
// NEW TABLE DEFINITIONS (v2)
// ═══════════════════════════════════════════════════════════════════════

class CachedInvitations extends Table {
  TextColumn get id => text()();
  TextColumn get familyId => text()();
  TextColumn get familyName => text()();
  TextColumn get inviterName => text()();
  TextColumn get status => text()(); // pending, accepted, rejected, expired
  TextColumn get role => text()();
  TextColumn get channel => text()(); // family_id, qr_code, link
  TextColumn get inviteCode => text().nullable()();
  DateTimeColumn get expiresAt => dateTime().nullable()();
  DateTimeColumn get acceptedAt => dateTime().nullable()();
  TextColumn get data => text()(); // Full JSON for additional fields
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class CachedRelationshipPaths extends Table {
  TextColumn get familyId => text()();
  TextColumn get fromPersonId => text()();
  TextColumn get toPersonId => text()();
  TextColumn get path => text()(); // JSON array of steps
  TextColumn get kinshipTerm => text().nullable()();
  TextColumn get kinshipTermHindi => text().nullable()();
  IntColumn get distance => integer()();
  DateTimeColumn get computedAt => dateTime()();
  DateTimeColumn get expiresAt => dateTime()();

  @override
  Set<Column> get primaryKey => {familyId, fromPersonId, toPersonId};
}

class SyncMetadata extends Table {
  TextColumn get entityType => text()(); // families, persons, relationships, invitations
  TextColumn get lastSyncedAt => text()(); // ISO 8601 timestamp
  TextColumn get checksum => text().nullable()(); // Hash of last synced data
  IntColumn get recordCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {entityType};
}

class ConflictLog extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get localData => text()(); // JSON
  TextColumn get serverData => text()(); // JSON
  TextColumn get resolution => text().withDefault(const Constant('pending'))(); // pending, local_wins, server_wins, merged
  TextColumn get resolvedData => text().nullable()(); // JSON after merge
  DateTimeColumn get detectedAt => dateTime()();
  DateTimeColumn get resolvedAt => dateTime().nullable()();
}

class CachedUsernames extends Table {
  TextColumn get userId => text()();
  TextColumn get username => text()();
  TextColumn get displayName => text()();
  TextColumn get avatarUrl => text().nullable()();
  TextColumn get bio => text().nullable()();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {userId};
}

class CachedFamilyIds extends Table {
  TextColumn get familyId => text()(); // Internal family ID
  TextColumn get kinFamilyId => text()(); // KIN-XXXXXXXX
  TextColumn get name => text()();
  TextColumn get avatarUrl => text().nullable()();
  IntColumn get memberCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {kinFamilyId};
}

// ═══════════════════════════════════════════════════════════════════════
// DATABASE CLASS
// ═══════════════════════════════════════════════════════════════════════

@DriftDatabase(tables: [
  CachedProfiles,
  CachedRelationships,
  CachedFamilies,
  CachedPersons,
  UserSettings,
  SearchHistoryEntries,
  RecentlyViewedProfiles,
  PendingOperations,
  ApiCacheEntries,
  CachedInvitations,
  CachedRelationshipPaths,
  SyncMetadata,
  ConflictLog,
  CachedUsernames,
  CachedFamilyIds,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Constructor for testing — inject a custom QueryExecutor
  /// (e.g., NativeDatabase.memory() for isolated in-memory tests).
  AppDatabase.forTesting(QueryExecutor executor) : super(executor);

  @override
  int get schemaVersion => 4;

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'daxelo_kinrel_db');
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (migrator, from, to) async {
          if (from < 2) {
            // ── v1 → v2: Add new columns to existing tables ──────────
            await migrator.addColumn(
              cachedFamilies,
              cachedFamilies.kinFamilyId,
            );
            await migrator.addColumn(
              cachedPersons,
              cachedPersons.bloodGroup,
            );
            await migrator.addColumn(
              cachedPersons,
              cachedPersons.education,
            );
            await migrator.addColumn(
              cachedPersons,
              cachedPersons.biography,
            );
            await migrator.addColumn(
              cachedPersons,
              cachedPersons.email,
            );
            await migrator.addColumn(
              cachedPersons,
              cachedPersons.phone,
            );
            await migrator.addColumn(
              cachedPersons,
              cachedPersons.anniversaryDate,
            );
            await migrator.addColumn(
              cachedPersons,
              cachedPersons.relationshipType,
            );

            // ── v1 → v2: Create new tables ───────────────────────────
            await migrator.createTable(cachedInvitations);
            await migrator.createTable(cachedRelationshipPaths);
            await migrator.createTable(syncMetadata);
            await migrator.createTable(conflictLog);
          }
          if (from < 3) {
            // v2 → v3: Add username columns + new cache tables
            await migrator.addColumn(cachedPersons, cachedPersons.username);
            await migrator.addColumn(cachedFamilies, cachedFamilies.username);
            await migrator.createTable(cachedUsernames);
            await migrator.createTable(cachedFamilyIds);
          }
          if (from < 4) {
            // v3 → v4: Remove AuthTokens table — tokens now in SecureStorage only
            // Drift doesn't have a migrator.dropTable, so use custom SQL
            await customStatement('DROP TABLE IF EXISTS auth_tokens');
          }
        },
      );

  // ── Profiles ──────────────────────────────────────────────────────

  Future<List<CachedProfile>> getAllProfiles() =>
      select(cachedProfiles).get();

  Future<CachedProfile?> getProfile(String id) =>
      (select(cachedProfiles)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<void> upsertProfile(CachedProfilesCompanion profile) =>
      into(cachedProfiles).insertOnConflictUpdate(profile);

  Future<void> deleteProfile(String id) =>
      (delete(cachedProfiles)..where((t) => t.id.equals(id))).go();

  Future<void> clearProfiles() => delete(cachedProfiles).go();

  Future<int> profileCount() =>
      cachedProfiles.count().getSingle();

  // ── Families ──────────────────────────────────────────────────────

  Future<List<CachedFamily>> getAllFamilies() =>
      select(cachedFamilies).get();

  Future<CachedFamily?> getFamily(String id) =>
      (select(cachedFamilies)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<void> upsertFamily(CachedFamiliesCompanion family) =>
      into(cachedFamilies).insertOnConflictUpdate(family);

  Future<void> deleteFamily(String id) =>
      (delete(cachedFamilies)..where((t) => t.id.equals(id))).go();

  Future<void> clearFamilies() => delete(cachedFamilies).go();

  Future<CachedFamily?> getFamilyByCode(String familyCode) =>
      (select(cachedFamilies)
            ..where((t) => t.data.like('%$familyCode%')))
          .getSingleOrNull();

  // ── Persons ───────────────────────────────────────────────────────

  Future<List<CachedPerson>> getPersonsByFamily(String familyId) =>
      (select(cachedPersons)..where((t) => t.familyId.equals(familyId)))
          .get();

  Future<CachedPerson?> getPerson(String id) =>
      (select(cachedPersons)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<void> upsertPerson(CachedPersonsCompanion person) =>
      into(cachedPersons).insertOnConflictUpdate(person);

  Future<void> deletePersonsByFamily(String familyId) =>
      (delete(cachedPersons)..where((t) => t.familyId.equals(familyId))).go();

  Future<void> deletePerson(String id) =>
      (delete(cachedPersons)..where((t) => t.id.equals(id))).go();

  Future<void> clearPersons() => delete(cachedPersons).go();

  Future<int> personCount() =>
      cachedPersons.count().getSingle();

  // ── Relationships ─────────────────────────────────────────────────

  Future<List<CachedRelationship>> getRelationshipsByFamily(
          String familyId) =>
      (select(cachedRelationships)
            ..where((t) => t.fromId.equals(familyId) | t.toId.equals(familyId)))
          .get();

  Future<void> upsertRelationship(
          CachedRelationshipsCompanion relationship) =>
      into(cachedRelationships).insertOnConflictUpdate(relationship);

  Future<void> deleteRelationshipsByFamily(String familyId) =>
      (delete(cachedRelationships)
            ..where((t) => t.fromId.equals(familyId) | t.toId.equals(familyId)))
          .go();

  Future<void> deleteRelationship(String id) =>
      (delete(cachedRelationships)..where((t) => t.id.equals(id))).go();

  Future<void> clearRelationships() => delete(cachedRelationships).go();

  // ── Auth Tokens ───────────────────────────────────────────────────
  // REMOVED: Auth tokens are now stored exclusively in SecureStorageService.
  // The auth_tokens Drift table was removed in schema v4.
  // Use SecureStorageService.saveAuthTokens / clearAuthTokens instead.

  // ── User Settings ─────────────────────────────────────────────────

  Future<String?> getSetting(String key) async {
    final row = await (select(userSettings)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> setSetting(String key, String value) =>
      into(userSettings).insertOnConflictUpdate(
        UserSettingsCompanion(
          key: Value(key),
          value: Value(value),
        ),
      );

  Future<void> deleteSetting(String key) =>
      (delete(userSettings)..where((t) => t.key.equals(key))).go();

  Future<void> clearSettings() => delete(userSettings).go();

  // ── Search History ────────────────────────────────────────────────

  Future<List<SearchHistoryEntry>> getSearchHistory({int limit = 10}) =>
      (select(searchHistoryEntries)
            ..orderBy([(t) => OrderingTerm.desc(t.searchedAt)])
            ..limit(limit))
          .get();

  Future<void> upsertSearchHistory(SearchHistoryEntriesCompanion entry) =>
      into(searchHistoryEntries).insertOnConflictUpdate(entry);

  Future<void> deleteSearchHistoryByQuery(String query) =>
      (delete(searchHistoryEntries)..where((t) => t.query.equals(query)))
          .go();

  Future<void> clearSearchHistory() => delete(searchHistoryEntries).go();

  // ── Recently Viewed ──────────────────────────────────────────────

  Future<List<RecentlyViewedProfile>> getRecentlyViewed({int limit = 20}) =>
      (select(recentlyViewedProfiles)
            ..orderBy([(t) => OrderingTerm.desc(t.viewedAt)])
            ..limit(limit))
          .get();

  Future<void> upsertRecentlyViewed(
          RecentlyViewedProfilesCompanion entry) =>
      into(recentlyViewedProfiles).insertOnConflictUpdate(entry);

  Future<void> deleteRecentlyViewedByPerson(String personId) =>
      (delete(recentlyViewedProfiles)
            ..where((t) => t.personId.equals(personId)))
          .go();

  Future<void> clearRecentlyViewed() => delete(recentlyViewedProfiles).go();

  // ── Pending Operations ────────────────────────────────────────────

  Future<List<PendingOperation>> getPendingOperations() =>
      (select(pendingOperations)
            ..where((t) => t.isProcessing.equals(false) & t.retryCount.isSmallerThanValue(5))
            ..orderBy([
              (t) => OrderingTerm.asc(t.priority),
              (t) => OrderingTerm.asc(t.createdAt),
            ]))
          .get();

  Future<void> upsertPendingOperation(PendingOperationsCompanion op) =>
      into(pendingOperations).insertOnConflictUpdate(op);

  Future<void> deletePendingOperation(int id) =>
      (delete(pendingOperations)..where((t) => t.id.equals(id))).go();

  Future<void> clearPendingOperations() => delete(pendingOperations).go();

  Future<int> pendingOperationCount() =>
      (pendingOperations.count()).getSingle();

  Future<List<PendingOperation>> getExpiredOperations() =>
      (select(pendingOperations)
            ..where((t) => t.retryCount.isBiggerOrEqualValue(5)))
          .get();

  // ── API Cache ─────────────────────────────────────────────────────

  Future<ApiCacheEntry?> getApiCacheEntry(String key) =>
      (select(apiCacheEntries)..where((t) => t.key.equals(key)))
          .getSingleOrNull();

  Future<void> upsertApiCacheEntry(ApiCacheEntriesCompanion entry) =>
      into(apiCacheEntries).insertOnConflictUpdate(entry);

  Future<void> deleteApiCacheEntry(int id) =>
      (delete(apiCacheEntries)..where((t) => t.id.equals(id))).go();

  Future<void> clearApiCache() => delete(apiCacheEntries).go();

  Future<List<ApiCacheEntry>> getAllApiCacheEntries() =>
      select(apiCacheEntries).get();

  // ── Cached Invitations ────────────────────────────────────────────

  Future<List<CachedInvitation>> getInvitationsByFamily(String familyId) =>
      (select(cachedInvitations)..where((t) => t.familyId.equals(familyId)))
          .get();

  Future<List<CachedInvitation>> getInvitationsByStatus(String status) =>
      (select(cachedInvitations)..where((t) => t.status.equals(status)))
          .get();

  Future<CachedInvitation?> getInvitation(String id) =>
      (select(cachedInvitations)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<void> upsertInvitation(CachedInvitationsCompanion invitation) =>
      into(cachedInvitations).insertOnConflictUpdate(invitation);

  Future<void> deleteInvitation(String id) =>
      (delete(cachedInvitations)..where((t) => t.id.equals(id))).go();

  Future<void> clearInvitations() => delete(cachedInvitations).go();

  Future<int> invitationCount() =>
      cachedInvitations.count().getSingle();

  // ── Cached Relationship Paths ─────────────────────────────────────

  Future<CachedRelationshipPath?> getRelationshipPath(
    String familyId,
    String fromPersonId,
    String toPersonId,
  ) =>
      (select(cachedRelationshipPaths)
            ..where((t) =>
                t.familyId.equals(familyId) &
                t.fromPersonId.equals(fromPersonId) &
                t.toPersonId.equals(toPersonId)))
          .getSingleOrNull();

  Future<List<CachedRelationshipPath>> getPathsByFamily(String familyId) =>
      (select(cachedRelationshipPaths)
            ..where((t) => t.familyId.equals(familyId)))
          .get();

  Future<void> upsertRelationshipPath(
          CachedRelationshipPathsCompanion path) =>
      into(cachedRelationshipPaths).insertOnConflictUpdate(path);

  Future<void> deleteRelationshipPathsByFamily(String familyId) =>
      (delete(cachedRelationshipPaths)
            ..where((t) => t.familyId.equals(familyId)))
          .go();

  Future<void> clearRelationshipPaths() =>
      delete(cachedRelationshipPaths).go();

  // ── Sync Metadata ─────────────────────────────────────────────────

  Future<SyncMetadataData?> getSyncMetadata(String entityType) =>
      (select(syncMetadata)..where((t) => t.entityType.equals(entityType)))
          .getSingleOrNull();

  Future<List<SyncMetadataData>> getAllSyncMetadata() =>
      select(syncMetadata).get();

  Future<void> upsertSyncMetadata(SyncMetadataCompanion metadata) =>
      into(syncMetadata).insertOnConflictUpdate(metadata);

  Future<void> deleteSyncMetadata(String entityType) =>
      (delete(syncMetadata)..where((t) => t.entityType.equals(entityType)))
          .go();

  Future<void> clearSyncMetadata() => delete(syncMetadata).go();

  // ── Conflict Log ──────────────────────────────────────────────────

  Future<List<ConflictLogData>> getPendingConflicts() =>
      (select(conflictLog)..where((t) => t.resolution.equals('pending')))
          .get();

  Future<List<ConflictLogData>> getConflictsByEntity(
          String entityType, String entityId) =>
      (select(conflictLog)
            ..where((t) =>
                t.entityType.equals(entityType) &
                t.entityId.equals(entityId)))
          .get();

  Future<ConflictLogData?> getConflict(int id) =>
      (select(conflictLog)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<void> upsertConflict(ConflictLogCompanion conflict) =>
      into(conflictLog).insertOnConflictUpdate(conflict);

  Future<void> deleteConflict(int id) =>
      (delete(conflictLog)..where((t) => t.id.equals(id))).go();

  Future<void> clearConflictLog() => delete(conflictLog).go();

  Future<int> conflictCount() =>
      conflictLog.count().getSingle();

  // ── Bulk Operations ──────────────────────────────────────────────

  Future<void> clearAllCache() async {
    await delete(cachedProfiles).go();
    await delete(cachedFamilies).go();
    await delete(cachedPersons).go();
    await delete(cachedRelationships).go();
    await delete(apiCacheEntries).go();
    await delete(searchHistoryEntries).go();
    await delete(recentlyViewedProfiles).go();
    await delete(cachedInvitations).go();
    await delete(cachedRelationshipPaths).go();
    await delete(syncMetadata).go();
    await delete(conflictLog).go();
    await delete(cachedUsernames).go();
    await delete(cachedFamilyIds).go();
  }

  Future<void> clearAll() async {
    await transaction(() async {
      await clearAllCache();
      await delete(pendingOperations).go();
      await delete(userSettings).go();
      // auth_tokens table removed in v4 — tokens in SecureStorage only
    });
  }

  /// Collect table row counts in a single UNION ALL query instead of
  /// issuing 15 separate COUNT(*) queries.
  Future<Map<String, int>> getStats() async {
    final rows = await customSelect(
      '''
      SELECT 'families' AS tbl, COUNT(*) AS cnt FROM cached_families
      UNION ALL SELECT 'persons', COUNT(*) FROM cached_persons
      UNION ALL SELECT 'relationships', COUNT(*) FROM cached_relationships
      UNION ALL SELECT 'profiles', COUNT(*) FROM cached_profiles
      UNION ALL SELECT 'searchHistory', COUNT(*) FROM search_history_entries
      UNION ALL SELECT 'recentlyViewed', COUNT(*) FROM recently_viewed_profiles
      UNION ALL SELECT 'pendingOps', COUNT(*) FROM pending_operations
      UNION ALL SELECT 'apiCache', COUNT(*) FROM api_cache_entries
      UNION ALL SELECT 'settings', COUNT(*) FROM user_settings
      UNION ALL SELECT 'invitations', COUNT(*) FROM cached_invitations
      UNION ALL SELECT 'relationshipPaths', COUNT(*) FROM cached_relationship_paths
      UNION ALL SELECT 'syncMetadata', COUNT(*) FROM sync_metadata
      UNION ALL SELECT 'conflictLog', COUNT(*) FROM conflict_log
      UNION ALL SELECT 'cachedUsernames', COUNT(*) FROM cached_usernames
      UNION ALL SELECT 'cachedFamilyIds', COUNT(*) FROM cached_family_ids
      ''',
    ).get();
    return {
      for (final row in rows) row.read<String>('tbl'): row.read<int>('cnt'),
    };
  }

  // ── Cached Usernames ──────────────────────────────────────────────

  Future<CachedUsername?> getUsername(String username) =>
      (select(cachedUsernames)..where((t) => t.username.equals(username.toLowerCase())))
          .getSingleOrNull();

  Future<List<CachedUsername>> searchUsernames(String query) =>
      (select(cachedUsernames)..where((t) => t.username.like('%${query.toLowerCase()}%') | t.displayName.like('%${query.toLowerCase()}%')))
          .get();

  Future<void> upsertUsername(CachedUsernamesCompanion entry) =>
      into(cachedUsernames).insertOnConflictUpdate(entry);

  Future<void> clearUsernames() => delete(cachedUsernames).go();

  // ── Cached Family IDs ──────────────────────────────────────────────

  Future<CachedFamilyId?> getFamilyByKinId(String kinFamilyId) =>
      (select(cachedFamilyIds)..where((t) => t.kinFamilyId.equals(kinFamilyId.toUpperCase())))
          .getSingleOrNull();

  Future<List<CachedFamilyId>> searchFamilyIds(String query) =>
      (select(cachedFamilyIds)..where((t) => t.kinFamilyId.like('%${query.toUpperCase()}%') | t.name.like('%${query.toLowerCase()}%')))
          .get();

  Future<void> upsertFamilyId(CachedFamilyIdsCompanion entry) =>
      into(cachedFamilyIds).insertOnConflictUpdate(entry);

  Future<void> clearFamilyIds() => delete(cachedFamilyIds).go();

  Future<List<CachedFamilyId>> getAllCachedFamilyIds() =>
      select(cachedFamilyIds).get();

  // ── API Cache Convenience Methods ──────────────────────────────────

  /// Cache an API response by key with optional TTL.
  /// If [expiresIn] is provided, sets ttlSeconds accordingly.
  Future<void> cacheApiEntry(String key, String responseBody, {Duration? expiresIn}) {
    final ttl = expiresIn != null ? expiresIn.inSeconds : 3600; // default 1 hour
    return upsertApiCacheEntry(ApiCacheEntriesCompanion(
      key: Value(key),
      responseBody: Value(responseBody),
      cachedAt: Value(DateTime.now()),
      ttlSeconds: Value(ttl),
    ));
  }

  /// Get a cached API entry by key, checking TTL.
  /// Returns null if entry doesn't exist or has expired.
  Future<String?> getCachedApiEntry(String key) async {
    final entry = await getApiCacheEntry(key);
    if (entry == null) return null;
    // Check if expired
    final expiresAt = entry.cachedAt.add(Duration(seconds: entry.ttlSeconds));
    if (DateTime.now().isAfter(expiresAt)) {
      await deleteApiCacheEntry(entry.id);
      return null;
    }
    return entry.responseBody;
  }

  /// Get all cached API entries matching a key prefix.
  /// Uses a SQL LIKE clause to filter at the DB level instead of loading
  /// all entries and filtering in Dart. Only returns non-expired entries.
  Future<List<String>> getCachedApiEntriesWithPrefix(String prefix) async {
    final results = await customSelect(
      "SELECT response_body FROM api_cache_entries WHERE key LIKE ? AND datetime(cached_at, '+' || ttl_seconds || ' seconds') >= datetime('now')",
      variables: [Variable.withString(prefix + '%')],
    ).get();
    return results.map((row) => row.read<String>('response_body')).toList();
  }
}

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
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class CachedPersons extends Table {
  TextColumn get id => text()();
  TextColumn get familyId => text()();
  TextColumn get name => text()();
  TextColumn get data => text()();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class AuthTokens extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get accessToken => text()();
  TextColumn get refreshToken => text()();
  DateTimeColumn get expiresAt => dateTime()();
  DateTimeColumn get savedAt => dateTime()();
}

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
// DATABASE CLASS
// ═══════════════════════════════════════════════════════════════════════

@DriftDatabase(tables: [
  CachedProfiles,
  CachedRelationships,
  CachedFamilies,
  CachedPersons,
  AuthTokens,
  UserSettings,
  SearchHistoryEntries,
  RecentlyViewedProfiles,
  PendingOperations,
  ApiCacheEntries,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'daxelo_kinrel_db');
  }

  // ── Profiles ──────────────────────────────────────────────────────

  Future<List<CachedProfile>> getAllProfiles() =>
      select(cachedProfiles).get();

  Future<CachedProfile?> getProfile(String id) =>
      (select(cachedProfiles)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<void> upsertProfile(CachedProfilesCompanion profile) =>
      into(cachedProfiles).insertOnConflictUpdate(profile);

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

  Future<AuthToken?> getLatestToken() =>
      (select(authTokens)
            ..orderBy([(t) => OrderingTerm.desc(t.savedAt)])
            ..limit(1))
          .getSingleOrNull();

  Future<void> saveToken(AuthTokensCompanion token) async {
    await delete(authTokens).go();
    await into(authTokens).insert(token);
  }

  Future<void> clearTokens() => delete(authTokens).go();

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

  // ── Bulk Operations ──────────────────────────────────────────────

  Future<void> clearAllCache() async {
    await delete(cachedProfiles).go();
    await delete(cachedFamilies).go();
    await delete(cachedPersons).go();
    await delete(cachedRelationships).go();
    await delete(apiCacheEntries).go();
    await delete(searchHistoryEntries).go();
    await delete(recentlyViewedProfiles).go();
  }

  Future<void> clearAll() async {
    await clearAllCache();
    await delete(pendingOperations).go();
    await delete(userSettings).go();
    await delete(authTokens).go();
  }

  Future<Map<String, int>> getStats() async {
    return {
      'families': await cachedFamilies.count().getSingle(),
      'persons': await cachedPersons.count().getSingle(),
      'relationships': await cachedRelationships.count().getSingle(),
      'profiles': await cachedProfiles.count().getSingle(),
      'searchHistory': await searchHistoryEntries.count().getSingle(),
      'recentlyViewed': await recentlyViewedProfiles.count().getSingle(),
      'pendingOps': await pendingOperations.count().getSingle(),
      'apiCache': await apiCacheEntries.count().getSingle(),
      'settings': await userSettings.count().getSingle(),
    };
  }
}

import 'dart:convert';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;

import '../../core/family/family_provider.dart';
import '../../core/networking/dio_client.dart';
import '../../core/database/isar_database.dart';
import '../../core/database/app_database.dart';

// ── Display ID Helpers ────────────────────────────────────────────

/// Generate a stable 5-digit display number from an ID using its hash.
int _stableIndex(String id) {
  int hash = 0;
  for (int i = 0; i < id.length; i++) {
    hash = (hash * 31 + id.codeUnitAt(i)) & 0x7FFFFFFF;
  }
  return hash % 100000; // 0..99999
}

/// Format a person ID for display, e.g. "DK-P-00234".
String personDisplayId(String personId) {
  final index = _stableIndex(personId);
  return 'DK-P-${index.toString().padLeft(5, '0')}';
}

/// Format a family ID for display, e.g. "DK-F-00234".
String familyDisplayId(String familyId) {
  final index = _stableIndex(familyId);
  return 'DK-F-${index.toString().padLeft(5, '0')}';
}

// ── Search Filter ─────────────────────────────────────────────────

enum SearchFilter { all, people, families }

// ── Search Results ────────────────────────────────────────────────

class SearchResults {
  const SearchResults({
    this.people = const [],
    this.families = const [],
    this.totalCount = 0,
    this.hasMore = false,
    this.isFromServer = false,
  });

  final List<Person> people;
  final List<Family> families;
  final int totalCount;
  final bool hasMore;
  final bool isFromServer;

  bool get isEmpty => people.isEmpty && families.isEmpty;
  bool get isNotEmpty => !isEmpty;

  int get totalResults => people.length + families.length;

  /// Merge this result set with another (for combining local + server results).
  SearchResults merge(SearchResults other) {
    // Deduplicate by ID — prefer server results
    final personIds = <String>{};
    final mergedPeople = <Person>[];

    // Add server results first (preferred)
    for (final p in other.people) {
      if (!personIds.contains(p.id)) {
        personIds.add(p.id);
        mergedPeople.add(p);
      }
    }
    // Add local results that aren't already included
    for (final p in people) {
      if (!personIds.contains(p.id)) {
        personIds.add(p.id);
        mergedPeople.add(p);
      }
    }

    final familyIds = <String>{};
    final mergedFamilies = <Family>[];

    for (final f in other.families) {
      if (!familyIds.contains(f.id)) {
        familyIds.add(f.id);
        mergedFamilies.add(f);
      }
    }
    for (final f in families) {
      if (!familyIds.contains(f.id)) {
        familyIds.add(f.id);
        mergedFamilies.add(f);
      }
    }

    return SearchResults(
      people: mergedPeople,
      families: mergedFamilies,
      totalCount: other.totalCount > 0 ? other.totalCount : totalCount,
      hasMore: other.hasMore || hasMore,
      isFromServer: other.isFromServer || isFromServer,
    );
  }
}

// ── Levenshtein Distance (for offline typo tolerance) ─────────────

/// Compute Levenshtein distance between two strings.
int _levenshteinDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  final matrix = List.generate(
    a.length + 1,
    (i) => List.generate(b.length + 1, (j) => 0),
  );

  for (int i = 0; i <= a.length; i++) {
    matrix[i][0] = i;
  }
  for (int j = 0; j <= b.length; j++) {
    matrix[0][j] = j;
  }

  for (int i = 1; i <= a.length; i++) {
    for (int j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      matrix[i][j] = [
        matrix[i - 1][j] + 1,
        matrix[i][j - 1] + 1,
        matrix[i - 1][j - 1] + cost,
      ].reduce((curr, next) => curr < next ? curr : next);
    }
  }

  return matrix[a.length][b.length];
}

// ── Trigram Fuzzy Matching ─────────────────────────────────────────

/// Generate trigrams (3-character substrings) from a string.
Set<String> _generateTrigrams(String text) {
  final normalized = text.toLowerCase().trim();
  if (normalized.length < 3) return {normalized};

  final trigrams = <String>{};
  for (int i = 0; i <= normalized.length - 3; i++) {
    trigrams.add(normalized.substring(i, i + 3));
  }
  return trigrams;
}

/// Compute trigram similarity between query and target.
/// Returns a value between 0.0 and 1.0.
double trigramSimilarity(String query, String target) {
  if (query.isEmpty || target.isEmpty) return 0.0;
  if (query.toLowerCase() == target.toLowerCase()) return 1.0;

  final queryTrigrams = _generateTrigrams(query);
  final targetTrigrams = _generateTrigrams(target);

  if (queryTrigrams.isEmpty || targetTrigrams.isEmpty) return 0.0;

  final intersection = queryTrigrams.intersection(targetTrigrams).length;
  final union = queryTrigrams.union(targetTrigrams).length;

  return union == 0 ? 0.0 : intersection / union;
}

// ── Search Repository ─────────────────────────────────────────────

class SearchRepository {
  SearchRepository(this._ref);

  final Ref _ref;

  /// Search across people and families based on [query] and [filter].
  ///
  /// Uses the existing cached data from [familyListProvider] and
  /// [familyMembersProvider] rather than issuing direct Supabase queries.
  SearchResults searchAll(String query, SearchFilter filter) {
    if (query.trim().isEmpty) {
      return const SearchResults();
    }

    final normalizedQuery = query.trim().toLowerCase();

    // Read cached family list (synchronous — uses already-fetched data)
    final families = _ref.read(familyListProvider).value ?? <Family>[];

    final List<Person> matchedPeople = [];
    final List<Family> matchedFamilies = [];

    // ── Search Families ──────────────────────────────────────────
    if (filter == SearchFilter.all || filter == SearchFilter.families) {
      for (final family in families) {
        if (_matchesFamily(family, normalizedQuery)) {
          matchedFamilies.add(family);
        }
      }
    }

    // ── Search People ────────────────────────────────────────────
    if (filter == SearchFilter.all || filter == SearchFilter.people) {
      for (final family in families) {
        final members =
            _ref.read(familyMembersProvider(family.id)).value ?? <Person>[];
        for (final person in members) {
          if (_matchesPerson(person, normalizedQuery)) {
            matchedPeople.add(person);
          }
        }
      }
    }

    return SearchResults(people: matchedPeople, families: matchedFamilies);
  }

  /// Fuzzy search using trigram matching and Levenshtein distance.
  /// If exact matching fails, falls back to fuzzy matching with
  /// trigram similarity ≥ 0.3 or Levenshtein distance ≤ 2.
  SearchResults searchFuzzy(String query, SearchFilter filter) {
    if (query.trim().isEmpty) {
      return const SearchResults();
    }

    final normalizedQuery = query.trim().toLowerCase();

    // First try exact search
    final exactResults = searchAll(query, filter);
    if (exactResults.isNotEmpty) return exactResults;

    // Fall back to fuzzy matching
    final families = _ref.read(familyListProvider).value ?? <Family>[];
    final List<Person> matchedPeople = [];
    final List<Family> matchedFamilies = [];

    if (filter == SearchFilter.all || filter == SearchFilter.families) {
      for (final family in families) {
        if (_fuzzyMatchesFamily(family, normalizedQuery)) {
          matchedFamilies.add(family);
        }
      }
    }

    if (filter == SearchFilter.all || filter == SearchFilter.people) {
      for (final family in families) {
        final members =
            _ref.read(familyMembersProvider(family.id)).value ?? <Person>[];
        for (final person in members) {
          if (_fuzzyMatchesPerson(person, normalizedQuery)) {
            matchedPeople.add(person);
          }
        }
      }
    }

    return SearchResults(people: matchedPeople, families: matchedFamilies);
  }

  /// Server-side search via `GET /api/search?q=query&type=all|users|families&limit=20&offset=0`.
  /// Merges results with local cache.
  Future<SearchResults> searchServerSide(
    String query, {
    String type = 'all',
    int limit = 20,
    int offset = 0,
  }) async {
    if (query.trim().isEmpty) {
      return const SearchResults();
    }

    try {
      // ── Check API cache first ──────────────────────────────────
      final cachedResults = await _getCachedSearchResults(
        query: query,
        type: type,
        limit: limit,
        offset: offset,
      );
      if (cachedResults != null) return cachedResults;

      final dio = _ref.read(dioProvider);
      final response = await dio.get(
        '/api/search',
        queryParameters: {
          'q': query.trim(),
          'type': type,
          'limit': limit,
          'offset': offset,
        },
      );

      final data = response.data as Map<String, dynamic>;
      final usersList = data['users'] as List<dynamic>? ?? [];
      final familiesList = data['families'] as List<dynamic>? ?? [];
      final total = data['total'] as int? ?? 0;

      final people = usersList
          .map((u) => Person.fromJson(u as Map<String, dynamic>))
          .toList();
      final families = familiesList
          .map((f) => Family.fromJson(f as Map<String, dynamic>))
          .toList();

      final results = SearchResults(
        people: people,
        families: families,
        totalCount: total,
        hasMore: (offset + people.length + families.length) < total,
        isFromServer: true,
      );

      // ── Cache the results ──────────────────────────────────────
      await _cacheSearchResults(
        query: query,
        type: type,
        limit: limit,
        offset: offset,
        results: results,
      );

      return results;
    } catch (e) {
      debugPrint('⚠️ Server-side search error: $e');
      // Fall back to local search
      return searchAll(query, _typeToFilter(type));
    }
  }

  // ── Search Result Caching ────────────────────────────────────────

  static const _searchCachePrefix = 'search_results:';

  Future<SearchResults?> _getCachedSearchResults({
    required String query,
    required String type,
    required int limit,
    required int offset,
  }) async {
    if (!IsarDatabase.isInitialized) return null;
    try {
      final db = IsarDatabase.instance;
      final key = '$_searchCachePrefix${query.toLowerCase()}:$type:$limit:$offset';
      final entry = await db.getApiCacheEntry(key);
      if (entry == null) return null;

      // Check TTL (2 minutes for search results)
      final age = DateTime.now().difference(entry.cachedAt).inSeconds;
      if (age > entry.ttlSeconds) return null;

      final data = jsonDecode(entry.responseBody) as Map<String, dynamic>;
      final usersList = data['users'] as List<dynamic>? ?? [];
      final familiesList = data['families'] as List<dynamic>? ?? [];
      final total = data['total'] as int? ?? 0;

      return SearchResults(
        people: usersList
            .map((u) => Person.fromJson(u as Map<String, dynamic>))
            .toList(),
        families: familiesList
            .map((f) => Family.fromJson(f as Map<String, dynamic>))
            .toList(),
        totalCount: total,
        isFromServer: true,
      );
    } catch (e) {
      debugPrint('⚠️ Search cache read error: $e');
      return null;
    }
  }

  Future<void> _cacheSearchResults({
    required String query,
    required String type,
    required int limit,
    required int offset,
    required SearchResults results,
  }) async {
    if (!IsarDatabase.isInitialized) return;
    try {
      final db = IsarDatabase.instance;
      final key = '$_searchCachePrefix${query.toLowerCase()}:$type:$limit:$offset';
      await db.upsertApiCacheEntry(
        ApiCacheEntriesCompanion.insert(
          key: key,
          responseBody: jsonEncode({
            'users': results.people.map((p) => p.toJson()).toList(),
            'families': results.families.map((f) => f.toJson()).toList(),
            'total': results.totalCount,
          }),
          cachedAt: Value(DateTime.now()),
          ttlSeconds: const Value(120), // 2 minutes
        ),
      );
    } catch (e) {
      debugPrint('⚠️ Search cache write error: $e');
    }
  }

  // ── Helper: Type string to SearchFilter ──────────────────────────

  SearchFilter _typeToFilter(String type) {
    switch (type) {
      case 'users':
        return SearchFilter.people;
      case 'families':
        return SearchFilter.families;
      default:
        return SearchFilter.all;
    }
  }

  // ── Exact Matching ───────────────────────────────────────────────

  /// Check if a [Person] matches the normalized query.
  ///
  /// Matches by:
  /// - name (contains, case-insensitive)
  /// - username (without @ prefix)
  /// - formatted display ID (e.g. "DK-P-00234")
  /// - actual person ID (exact match)
  /// - familyId (exact match)
  bool _matchesPerson(Person person, String normalizedQuery) {
    // Name match (case-insensitive contains)
    if (person.name.toLowerCase().contains(normalizedQuery)) {
      return true;
    }

    // Username match (without @ prefix)
    final queryWithoutAt = normalizedQuery.startsWith('@')
        ? normalizedQuery.substring(1)
        : normalizedQuery;
    if (person.username != null &&
        person.username!.toLowerCase().contains(queryWithoutAt)) {
      return true;
    }

    // Display ID match (e.g. "DK-P-00234")
    final displayId = personDisplayId(person.id).toLowerCase();
    if (displayId.contains(normalizedQuery)) {
      return true;
    }

    // Actual ID match
    if (person.id.toLowerCase() == normalizedQuery) {
      return true;
    }

    // Family ID match
    if (person.familyId.toLowerCase() == normalizedQuery) {
      return true;
    }

    return false;
  }

  /// Check if a [Family] matches the normalized query.
  ///
  /// Matches by:
  /// - name (contains, case-insensitive)
  /// - KIN Family ID (e.g. KIN-AB12CD34)
  /// - username (without @ prefix)
  /// - familyCode (contains, case-insensitive)
  /// - formatted display ID (e.g. "DK-F-00234")
  /// - actual family ID (exact match)
  bool _matchesFamily(Family family, String normalizedQuery) {
    // Name match (case-insensitive contains)
    if (family.name.toLowerCase().contains(normalizedQuery)) {
      return true;
    }

    // KIN Family ID match (e.g. KIN-AB12CD34)
    if (family.kinFamilyId != null &&
        family.kinFamilyId!.toUpperCase().contains(normalizedQuery.toUpperCase())) {
      return true;
    }

    // Family username match (without @ prefix)
    final queryWithoutAt = normalizedQuery.startsWith('@')
        ? normalizedQuery.substring(1)
        : normalizedQuery;
    if (family.username != null &&
        family.username!.toLowerCase().contains(queryWithoutAt)) {
      return true;
    }

    // Family code match (case-insensitive contains)
    if (family.familyCode != null &&
        family.familyCode!.toLowerCase().contains(normalizedQuery)) {
      return true;
    }

    // Display ID match (e.g. "DK-F-00234")
    final displayId = familyDisplayId(family.id).toLowerCase();
    if (displayId.contains(normalizedQuery)) {
      return true;
    }

    // Actual ID match
    if (family.id.toLowerCase() == normalizedQuery) {
      return true;
    }

    return false;
  }

  // ── Fuzzy Matching ───────────────────────────────────────────────

  /// Fuzzy match a person using trigram similarity and Levenshtein distance.
  bool _fuzzyMatchesPerson(Person person, String normalizedQuery) {
    // Trigram similarity on name
    final nameSimilarity = trigramSimilarity(normalizedQuery, person.name);
    if (nameSimilarity >= 0.3) return true;

    // Levenshtein distance on name (for short queries)
    if (normalizedQuery.length >= 3) {
      final nameWords = person.name.toLowerCase().split(RegExp(r'\s+'));
      for (final word in nameWords) {
        if (_levenshteinDistance(normalizedQuery, word) <= 2) {
          return true;
        }
      }
    }

    // Username fuzzy match
    if (person.username != null) {
      final queryWithoutAt = normalizedQuery.startsWith('@')
          ? normalizedQuery.substring(1)
          : normalizedQuery;
      if (_levenshteinDistance(queryWithoutAt, person.username!.toLowerCase()) <= 2) {
        return true;
      }
    }

    return false;
  }

  /// Fuzzy match a family using trigram similarity and Levenshtein distance.
  bool _fuzzyMatchesFamily(Family family, String normalizedQuery) {
    // Trigram similarity on name
    final nameSimilarity = trigramSimilarity(normalizedQuery, family.name);
    if (nameSimilarity >= 0.3) return true;

    // Levenshtein distance on name (for short queries)
    if (normalizedQuery.length >= 3) {
      final nameWords = family.name.toLowerCase().split(RegExp(r'\s+'));
      for (final word in nameWords) {
        if (_levenshteinDistance(normalizedQuery, word) <= 2) {
          return true;
        }
      }
    }

    // Username fuzzy match
    if (family.username != null) {
      final queryWithoutAt = normalizedQuery.startsWith('@')
          ? normalizedQuery.substring(1)
          : normalizedQuery;
      if (_levenshteinDistance(queryWithoutAt, family.username!.toLowerCase()) <= 2) {
        return true;
      }
    }

    return false;
  }
}

// ── Provider ──────────────────────────────────────────────────────

final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  return SearchRepository(ref);
});

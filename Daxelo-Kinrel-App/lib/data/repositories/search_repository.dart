import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;

import '../../core/family/family_provider.dart';

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
  const SearchResults({this.people = const [], this.families = const []});

  final List<Person> people;
  final List<Family> families;

  bool get isEmpty => people.isEmpty && families.isEmpty;
  bool get isNotEmpty => !isEmpty;

  int get totalResults => people.length + families.length;
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
}

// ── Provider ──────────────────────────────────────────────────────

final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  return SearchRepository(ref);
});

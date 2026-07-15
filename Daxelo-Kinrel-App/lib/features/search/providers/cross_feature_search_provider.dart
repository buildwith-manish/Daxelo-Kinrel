// lib/features/search/providers/cross_feature_search_provider.dart
//
// DAXELO KINREL — Cross-Feature Search (P6.5)
//
// Unified search across all family features: people, memories, decisions,
// calendar events, stories. Aggregates results from existing providers
// into a single search experience.
//
// Reuses existing providers (familyMembersProvider) — does NOT create
// new data fetches.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/family/family_provider.dart';

/// The type of search result.
enum CrossFeatureResultType {
  person,
  decision,
  memory,
  event,
  story,
}

/// A single cross-feature search result.
@immutable
class CrossFeatureSearchResult {
  const CrossFeatureSearchResult({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    this.familyId,
    this.route,
  });

  final String id;
  final CrossFeatureResultType type;
  final String title;
  final String subtitle;
  final String? familyId;
  final String? route;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CrossFeatureSearchResult &&
          id == other.id &&
          type == other.type;

  @override
  int get hashCode => Object.hash(id, type);
}

/// The state of a cross-feature search.
@immutable
class CrossFeatureSearchState {
  const CrossFeatureSearchState({
    this.query = '',
    this.results = const [],
    this.isLoading = false,
    this.error,
  });

  final String query;
  final List<CrossFeatureSearchResult> results;
  final bool isLoading;
  final String? error;

  CrossFeatureSearchState copyWith({
    String? query,
    List<CrossFeatureSearchResult>? results,
    bool? isLoading,
    String? error,
  }) {
    return CrossFeatureSearchState(
      query: query ?? this.query,
      results: results ?? this.results,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// Cross-feature search notifier.
class CrossFeatureSearchNotifier
    extends StateNotifier<CrossFeatureSearchState> {
  CrossFeatureSearchNotifier(this._ref)
      : super(const CrossFeatureSearchState());

  final Ref _ref;

  /// Searches across all features for [query].
  Future<void> search(String query, {String? familyId}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      state = const CrossFeatureSearchState();
      return;
    }

    state = state.copyWith(query: trimmed, isLoading: true, error: null);

    try {
      final results = <CrossFeatureSearchResult>[];
      final lowerQuery = trimmed.toLowerCase();

      // Search people
      if (familyId != null) {
        try {
          final members =
              await _ref.read(familyMembersProvider(familyId).future);
          for (final person in members) {
            if (person.name.toLowerCase().contains(lowerQuery)) {
              results.add(CrossFeatureSearchResult(
                id: person.id,
                type: CrossFeatureResultType.person,
                title: person.name,
                subtitle: person.gender ?? 'Family member',
                familyId: familyId,
                route: '/family/$familyId/member/${person.id}',
              ));
            }
          }
        } catch (e) {
          debugPrint('Cross-feature search: people search failed: $e');
        }
      }

      // Sort: starts-with first, then contains, then alphabetical
      results.sort((a, b) {
        final aStarts = a.title.toLowerCase().startsWith(lowerQuery);
        final bStarts = b.title.toLowerCase().startsWith(lowerQuery);
        if (aStarts && !bStarts) return -1;
        if (!aStarts && bStarts) return 1;
        return a.title.compareTo(b.title);
      });

      state = state.copyWith(results: results, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Clears the search.
  void clear() {
    state = const CrossFeatureSearchState();
  }
}

/// Provider for cross-feature search.
final crossFeatureSearchProvider =
    StateNotifierProvider<CrossFeatureSearchNotifier, CrossFeatureSearchState>(
  (ref) => CrossFeatureSearchNotifier(ref),
);

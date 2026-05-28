import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/local_cache.dart';
import '../../core/database/isar_database.dart';
import '../../core/database/repositories/offline_profile_repository.dart';
import '../../data/repositories/search_repository.dart';

// ── Search State ──────────────────────────────────────────────────

class SearchState {
  const SearchState({
    this.query = '',
    this.filter = SearchFilter.all,
    this.results = const SearchResults(),
    this.isLoading = false,
    this.error,
    this.recentSearches = const [],
  });

  final String query;
  final SearchFilter filter;
  final SearchResults results;
  final bool isLoading;
  final String? error;
  final List<String> recentSearches;

  SearchState copyWith({
    String? query,
    SearchFilter? filter,
    SearchResults? results,
    bool? isLoading,
    String? error,
    List<String>? recentSearches,
  }) {
    return SearchState(
      query: query ?? this.query,
      filter: filter ?? this.filter,
      results: results ?? this.results,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      recentSearches: recentSearches ?? this.recentSearches,
    );
  }
}

// ── Search Notifier ───────────────────────────────────────────────

class SearchNotifier extends StateNotifier<SearchState> {
  SearchNotifier(this._repository, this._localCache, this._ref)
    : super(const SearchState());

  final SearchRepository _repository;
  final LocalCacheService _localCache;
  final Ref _ref;
  Timer? _debounce;

  /// Update the search query with 300ms debounce.
  void updateQuery(String query) {
    state = state.copyWith(query: query, isLoading: true, error: null);

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch();
    });
  }

  /// Update the search filter. Triggers a search if query is non-empty.
  void updateFilter(SearchFilter filter) {
    state = state.copyWith(filter: filter);

    if (state.query.trim().isNotEmpty) {
      _debounce?.cancel();
      _performSearch();
    }
  }

  /// Clear the search state entirely.
  void clearSearch() {
    _debounce?.cancel();
    state = const SearchState();
    loadRecentSearches();
  }

  /// Perform the actual search using the repository.
  void _performSearch() {
    try {
      final results = _repository.searchAll(state.query, state.filter);
      state = state.copyWith(results: results, isLoading: false, error: null);

      // Save to recent searches if we got results
      if (results.isNotEmpty && state.query.trim().isNotEmpty) {
        saveRecentSearch(state.query.trim());
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Load recent searches from Isar (if available) or Hive.
  void loadRecentSearches() {
    // Try Isar first
    if (IsarDatabase.isInitialized) {
      try {
        final repo = _ref.read(offlineProfileRepositoryProvider);
        repo.getSearchHistory().then((searches) {
          if (mounted && searches.isNotEmpty) {
            state = state.copyWith(recentSearches: searches);
          }
        }).catchError((_) {
          // Fallback to Hive
          _loadRecentSearchesFromHive();
        });
        return;
      } catch (_) {}
    }

    // Fallback to Hive
    _loadRecentSearchesFromHive();
  }

  void _loadRecentSearchesFromHive() {
    try {
      final searches = _localCache.getRecentSearches();
      state = state.copyWith(recentSearches: searches);
    } catch (_) {
      // Ignore cache read errors
    }
  }

  /// Save a recent search query.
  Future<void> saveRecentSearch(String query) async {
    // Save to Isar (if available)
    if (IsarDatabase.isInitialized) {
      try {
        final repo = _ref.read(offlineProfileRepositoryProvider);
        await repo.saveSearchHistory(query: query);
        loadRecentSearches();
        return;
      } catch (_) {}
    }

    // Fallback to Hive
    try {
      await _localCache.saveRecentSearch(query);
      loadRecentSearches();
    } catch (_) {
      // Ignore cache write errors
    }
  }

  /// Remove a single item from recent searches.
  Future<void> removeRecentSearch(String query) async {
    try {
      await _localCache.removeRecentSearch(query);
      loadRecentSearches();
    } catch (_) {
      // Ignore cache write errors
    }
  }

  /// Clear all recent searches.
  Future<void> clearRecentSearches() async {
    // Clear from Isar (if available)
    if (IsarDatabase.isInitialized) {
      try {
        final repo = _ref.read(offlineProfileRepositoryProvider);
        await repo.clearSearchHistory();
      } catch (_) {}
    }

    try {
      await _localCache.clearRecentSearches();
    } catch (_) {}

    state = state.copyWith(recentSearches: []);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

// ── Provider ──────────────────────────────────────────────────────

final searchProvider = StateNotifierProvider<SearchNotifier, SearchState>((
  ref,
) {
  final repository = ref.watch(searchRepositoryProvider);
  final localCache = ref.watch(localCacheProvider);
  final notifier = SearchNotifier(repository, localCache, ref);
  // Load recent searches on initialization
  notifier.loadRecentSearches();
  return notifier;
});

// ── Computed Providers (Zero Rebuild Optimizations) ────────────────

/// Computed: search query only
final searchQueryProvider = Provider<String>((ref) {
  return ref.watch(searchProvider).query;
});

/// Computed: search is loading
final searchIsLoadingProvider = Provider<bool>((ref) {
  return ref.watch(searchProvider).isLoading;
});

/// Computed: search filter only
final searchFilterProvider = Provider<SearchFilter>((ref) {
  return ref.watch(searchProvider).filter;
});

/// Computed: search results
final searchResultsProvider = Provider<SearchResults>((ref) {
  return ref.watch(searchProvider).results;
});

/// Computed: recent searches
final recentSearchesProvider = Provider<List<String>>((ref) {
  return ref.watch(searchProvider).recentSearches;
});

/// Computed: search error
final searchErrorProvider = Provider<String?>((ref) {
  return ref.watch(searchProvider).error;
});

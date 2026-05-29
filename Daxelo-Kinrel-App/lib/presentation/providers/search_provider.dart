import 'dart:async';

import 'package:flutter/foundation.dart';
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
    this.isLoadingMore = false,
    this.error,
    this.recentSearches = const [],
    this.currentPage = 0,
    this.hasMore = true,
    this.isServerSearch = false,
  });

  final String query;
  final SearchFilter filter;
  final SearchResults results;
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;
  final List<String> recentSearches;
  final int currentPage;
  final bool hasMore;
  final bool isServerSearch;

  SearchState copyWith({
    String? query,
    SearchFilter? filter,
    SearchResults? results,
    bool? isLoading,
    bool? isLoadingMore,
    String? error,
    List<String>? recentSearches,
    int? currentPage,
    bool? hasMore,
    bool? isServerSearch,
  }) {
    return SearchState(
      query: query ?? this.query,
      filter: filter ?? this.filter,
      results: results ?? this.results,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: error,
      recentSearches: recentSearches ?? this.recentSearches,
      currentPage: currentPage ?? this.currentPage,
      hasMore: hasMore ?? this.hasMore,
      isServerSearch: isServerSearch ?? this.isServerSearch,
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
  /// First shows local results immediately, then fetches from server.
  void updateQuery(String query) {
    state = state.copyWith(
      query: query,
      isLoading: true,
      error: null,
      currentPage: 0,
      hasMore: true,
    );

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _performSearchWithServerFallback();
    });
  }

  /// Update the search filter. Triggers a search if query is non-empty.
  void updateFilter(SearchFilter filter) {
    state = state.copyWith(filter: filter, currentPage: 0, hasMore: true);

    if (state.query.trim().isNotEmpty) {
      _debounce?.cancel();
      _performSearchWithServerFallback();
    }
  }

  /// Clear the search state entirely.
  void clearSearch() {
    _debounce?.cancel();
    state = const SearchState();
    loadRecentSearches();
  }

  /// Perform the search using both local and server-side data.
  /// Shows local results immediately, then merges with server results.
  Future<void> _performSearchWithServerFallback() async {
    // ── Step 1: Show local results immediately ───────────────────
    try {
      // First try exact local search
      var localResults = _repository.searchAll(state.query, state.filter);

      // If no exact matches, try fuzzy search
      if (localResults.isEmpty) {
        localResults = _repository.searchFuzzy(state.query, state.filter);
      }

      state = state.copyWith(
        results: localResults,
        isLoading: false,
        error: null,
      );

      // Save to recent searches if we got results
      if (localResults.isNotEmpty && state.query.trim().isNotEmpty) {
        saveRecentSearch(state.query.trim());
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }

    // ── Step 2: Fetch from server and merge ──────────────────────
    try {
      final serverResults = await _repository.searchServerSide(
        state.query,
        type: _filterToType(state.filter),
        limit: 20,
        offset: 0,
      );

      if (mounted) {
        // Merge server results with local results
        final merged = state.results.merge(serverResults);
        state = state.copyWith(
          results: merged,
          isServerSearch: serverResults.isFromServer,
          hasMore: serverResults.hasMore,
          currentPage: 0,
        );

        // Save to recent searches
        if (merged.isNotEmpty && state.query.trim().isNotEmpty) {
          saveRecentSearch(state.query.trim());
        }
      }
    } catch (e) {
      debugPrint('⚠️ Server search fallback error: $e');
      // Local results are already shown — no need to update state
    }
  }

  /// Load more results (pagination).
  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore || state.query.trim().isEmpty) {
      return;
    }

    state = state.copyWith(isLoadingMore: true);

    try {
      final nextOffset = (state.currentPage + 1) * 20;
      final serverResults = await _repository.searchServerSide(
        state.query,
        type: _filterToType(state.filter),
        limit: 20,
        offset: nextOffset,
      );

      if (mounted) {
        // Append to existing results
        final allPeople = [...state.results.people, ...serverResults.people];
        final allFamilies = [...state.results.families, ...serverResults.families];

        state = state.copyWith(
          results: SearchResults(
            people: allPeople,
            families: allFamilies,
            totalCount: serverResults.totalCount,
            hasMore: serverResults.hasMore,
            isFromServer: true,
          ),
          isLoadingMore: false,
          currentPage: state.currentPage + 1,
        );
      }
    } catch (e) {
      debugPrint('⚠️ Load more error: $e');
      state = state.copyWith(isLoadingMore: false);
    }
  }

  /// Convert SearchFilter to API type parameter.
  String _filterToType(SearchFilter filter) {
    switch (filter) {
      case SearchFilter.people:
        return 'users';
      case SearchFilter.families:
        return 'families';
      case SearchFilter.all:
        return 'all';
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

  Future<void> _loadRecentSearchesFromHive() async {
    try {
      final searches = await _localCache.getRecentSearches();
      if (mounted) {
        state = state.copyWith(recentSearches: searches);
      }
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

/// Computed: has more results for pagination
final searchHasMoreProvider = Provider<bool>((ref) {
  return ref.watch(searchProvider).hasMore;
});

/// Computed: is loading more (pagination)
final searchIsLoadingMoreProvider = Provider<bool>((ref) {
  return ref.watch(searchProvider).isLoadingMore;
});

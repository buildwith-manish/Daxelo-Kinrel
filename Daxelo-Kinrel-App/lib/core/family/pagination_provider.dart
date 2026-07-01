// lib/core/family/pagination_provider.dart
//
// DAXELO KINREL — Cursor-Based Pagination for Family List
//
// Provides paginated access to families using cursor-based pagination
// with `createdAt` descending order and configurable page size.
//
// Key design:
// - Cursor = last item's `createdAt` timestamp (not offset-based)
// - Page size = 20 (configurable)
// - Scroll-triggered loadMore via `loadMoreFamilies()`
// - Merges new pages into existing list (no flicker)
// - Works with Drift cache (hybrid approach)
// - Family members and relationships are NOT paginated (families are
//   usually small enough to load entirely)

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:drift/drift.dart';

import 'family_provider.dart';
import '../database/isar_database.dart';
import '../database/app_database.dart';
import '../services/supabase_service.dart';

// ════════════════════════════════════════════════════════════════════
// PAGINATION STATE
// ════════════════════════════════════════════════════════════════════

/// State for paginated family list.
class PaginatedFamilyState {
  const PaginatedFamilyState({
    this.families = const [],
    this.isLoadingFirst = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.cursor,
    this.error,
  });

  /// Current list of families (accumulated across pages).
  final List<Family> families;

  /// Whether the first page is loading.
  final bool isLoadingFirst;

  /// Whether a subsequent page is loading.
  final bool isLoadingMore;

  /// Whether there are more pages to load.
  final bool hasMore;

  /// Cursor for the next page (createdAt of the last item).
  final DateTime? cursor;

  /// Error message, if any.
  final String? error;

  PaginatedFamilyState copyWith({
    List<Family>? families,
    bool? isLoadingFirst,
    bool? isLoadingMore,
    bool? hasMore,
    DateTime? cursor,
    String? error,
  }) {
    return PaginatedFamilyState(
      families: families ?? this.families,
      isLoadingFirst: isLoadingFirst ?? this.isLoadingFirst,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      cursor: cursor ?? this.cursor,
      error: error,
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// PAGINATED FAMILY NOTIFIER
// ════════════════════════════════════════════════════════════════════

/// Default page size for family list pagination.
const kFamilyPageSize = 20;

class PaginatedFamilyNotifier
    extends StateNotifier<PaginatedFamilyState> {
  PaginatedFamilyNotifier(this._ref)
      : super(const PaginatedFamilyState());

  final Ref _ref;

  /// Load the first page of families.
  /// Returns cached data instantly if available, then fetches from server.
  Future<void> loadFirstPage() async {
    if (state.isLoadingFirst) return;

    state = state.copyWith(isLoadingFirst: true, error: null);

    try {
      // Try Drift cache first for instant rendering
      List<Family> cachedFamilies = [];
      if (IsarDatabase.isInitialized) {
        try {
          final db = _ref.read(isarProvider);
          final cached = await db.getAllFamilies();
          for (final row in cached) {
            if (row.data.isEmpty) continue;
            try {
              final dataMap =
                  Map<String, dynamic>.from(
                      jsonDecode(row.data) as Map);
              if (dataMap['deletedAt'] != null) continue;
              cachedFamilies.add(Family.fromJson(dataMap));
            } catch (_) {}
          }
          // Sort by createdAt descending
          cachedFamilies.sort((a, b) =>
              (b.createdAt ?? DateTime(1970))
                  .compareTo(a.createdAt ?? DateTime(1970)));
        } catch (_) {}
      }

      // If we have cache, show it immediately and then fetch page 1
      if (cachedFamilies.isNotEmpty) {
        state = state.copyWith(
          families: cachedFamilies,
          isLoadingFirst: false,
          // Still try to fetch from server for fresh data
        );
      }

      // Fetch from Supabase with cursor-based pagination
      final families = await _fetchPage(cursor: null);

      if (families.isNotEmpty) {
        final hasMore = families.length >= kFamilyPageSize;
        final lastFamily = families.last;
        state = state.copyWith(
          families: families,
          isLoadingFirst: false,
          hasMore: hasMore,
          cursor: lastFamily.createdAt,
        );

        // Cache to Drift
        _cacheFamilies(families);
      } else {
        state = state.copyWith(
          isLoadingFirst: false,
          hasMore: false,
        );
      }
    } catch (e) {
      debugPrint('⚠️ PaginatedFamilyNotifier.loadFirstPage: $e');

      // On error, try to use cached data
      if (state.families.isNotEmpty) {
        state = state.copyWith(
          isLoadingFirst: false,
          error: e.toString(),
        );
      } else {
        state = state.copyWith(
          isLoadingFirst: false,
          error: e.toString(),
        );
      }
    }
  }

  /// Load the next page of families.
  /// Called when the user scrolls near the bottom of the list.
  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;

    state = state.copyWith(isLoadingMore: true);

    try {
      final newFamilies = await _fetchPage(cursor: state.cursor);

      if (newFamilies.isNotEmpty) {
        final allFamilies = [...state.families, ...newFamilies];
        final hasMore = newFamilies.length >= kFamilyPageSize;
        final lastFamily = newFamilies.last;

        state = state.copyWith(
          families: allFamilies,
          isLoadingMore: false,
          hasMore: hasMore,
          cursor: lastFamily.createdAt,
        );

        // Cache new families to Drift
        _cacheFamilies(newFamilies);
      } else {
        state = state.copyWith(
          isLoadingMore: false,
          hasMore: false,
        );
      }
    } catch (e) {
      debugPrint('⚠️ PaginatedFamilyNotifier.loadMore: $e');
      state = state.copyWith(
        isLoadingMore: false,
        error: e.toString(),
      );
    }
  }

  /// Refresh the list (pull-to-refresh or after mutation).
  /// Preserves existing data while fetching fresh from server.
  Future<void> refresh() async {
    state = const PaginatedFamilyState();
    await loadFirstPage();
  }

  /// Insert or update a family in the local list (for optimistic UI).
  void upsertLocal(Family family) {
    final idx = state.families.indexWhere((f) => f.id == family.id);
    if (idx >= 0) {
      final updated = [...state.families];
      updated[idx] = family;
      state = state.copyWith(families: updated);
    } else {
      // New family — insert at the beginning (newest first)
      state = state.copyWith(
        families: [family, ...state.families],
      );
    }
  }

  /// Remove a family from the local list (for optimistic delete).
  void removeLocal(String familyId) {
    state = state.copyWith(
      families:
          state.families.where((f) => f.id != familyId).toList(),
    );
  }

  // ── Private Helpers ─────────────────────────────────────────────

  /// Fetch a page of families from Supabase using cursor-based pagination.
  /// Cursor = createdAt of the last item on the previous page.
  Future<List<Family>> _fetchPage({DateTime? cursor}) async {
    final client = _ref.read(supabaseProvider);
    if (client == null) return [];

    final userId = client.auth.currentUser?.id;
    if (userId == null) return [];

    // Get family IDs the user has access to
    final familyIds = <String>{};

    // From FamilyMember table
    try {
      final memberEntries = await client
          .from('FamilyMember')
          .select('familyId')
          .eq('userId', userId);
      for (final row in (memberEntries as List)) {
        familyIds.add(row['familyId'] as String);
      }
    } catch (_) {}

    // From createdBy fallback
    try {
      final createdFamilies = await client
          .from('Family')
          .select('id')
          .eq('createdBy', userId);
      for (final row in (createdFamilies as List)) {
        familyIds.add(row['id'] as String);
      }
    } catch (_) {}

    if (familyIds.isEmpty) return [];

    // Build cursor-based query
    // NOTE: .lt() is a filter method (PostgrestFilterBuilder) and must be
    // called before .order()/.limit() which return PostgrestTransformBuilder.
    // We build the filter part first, then apply ordering and limiting.
    final filterBuilder = client
        .from('Family')
        .select()
        .inFilter('id', familyIds.toList())
        .filter('deletedAt', 'is', null);

    // Apply cursor filter if we have one, then order + limit
    final transformBuilder = cursor != null
        ? filterBuilder
            .lt('createdAt', cursor.toIso8601String())
            .order('createdAt', ascending: false)
            .limit(kFamilyPageSize)
        : filterBuilder
            .order('createdAt', ascending: false)
            .limit(kFamilyPageSize);

    final response = await transformBuilder;

    return (response as List)
        .map((json) => Family.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Cache families to Drift for offline access.
  void _cacheFamilies(List<Family> families) {
    if (!IsarDatabase.isInitialized) return;
    try {
      final db = _ref.read(isarProvider);
      for (final family in families) {
        db.upsertFamily(CachedFamiliesCompanion(
          id: Value(family.id),
          name: Value(family.name),
          data: Value(jsonEncode(family.toJson())),
          kinFamilyId: Value(family.kinFamilyId),
          username: Value(family.username),
          cachedAt: Value(DateTime.now()),
        )).catchError((_) {});
      }
    } catch (_) {}
  }
}

// ════════════════════════════════════════════════════════════════════
// RIVERPOD PROVIDERS
// ════════════════════════════════════════════════════════════════════

/// Provider for the paginated family list notifier.
final paginatedFamilyProvider =
    StateNotifierProvider<PaginatedFamilyNotifier, PaginatedFamilyState>(
        (ref) {
  return PaginatedFamilyNotifier(ref);
});

/// Whether more families are available to load.
final hasMoreFamiliesProvider = Provider<bool>((ref) {
  return ref.watch(paginatedFamilyProvider).hasMore;
});

/// Whether the family list is currently loading more.
final isLoadingMoreFamiliesProvider = Provider<bool>((ref) {
  return ref.watch(paginatedFamilyProvider).isLoadingMore;
});

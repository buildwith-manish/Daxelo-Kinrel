// lib/core/family/paginated_members_provider.dart
//
// DAXELO KINREL — Cursor-based Pagination for Family Members
//
// Replaces the all-at-once `familyMembersProvider` for large families.
// Loads members page-by-page (20 per page) using a `createdAt` cursor
// so that families with 100+ members render quickly without holding
// the entire list in memory up front.
//
// Strategy:
//   loadInitial() → Drift cache (instant) → Supabase first page (replace)
//   loadMore()    → Supabase next page (append)
//   refresh()     → reset + loadInitial()

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;

import 'family_provider.dart';
import '../database/isar_database.dart';
import '../database/app_database.dart';
import '../services/supabase_service.dart';

// ── Table name constant (matching Prisma schema PascalCase) ──────────
const _kPersonTable = 'Person';

// ── PaginatedMembersState ────────────────────────────────────────────

/// Immutable state for the paginated family-members list.
class PaginatedMembersState {
  /// Currently loaded members (may span multiple pages).
  final List<Person> members;

  /// Cursor = `createdAt` of the last item in [members].
  /// `null` means there are no more pages to fetch.
  final String? cursor;

  /// Whether a `loadMore()` call is in flight.
  final bool isLoadingMore;

  /// Whether the server may have additional pages beyond [cursor].
  final bool hasMore;

  /// Non-null when the last page-fetch failed.
  final String? error;

  const PaginatedMembersState({
    this.members = const [],
    this.cursor,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
  });

  /// Sentinel value so `copyWith(cursor: null)` actually sets cursor to null
  /// instead of falling back to the current value.
  static const _unset = Object();

  PaginatedMembersState copyWith({
    List<Person>? members,
    Object? cursor = _unset,
    bool? isLoadingMore,
    bool? hasMore,
    Object? error = _unset,
  }) {
    return PaginatedMembersState(
      members: members ?? this.members,
      cursor: identical(cursor, _unset) ? this.cursor : cursor as String?,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: identical(error, _unset) ? this.error : error as String?,
    );
  }
}

// ── PaginatedMembersNotifier ─────────────────────────────────────────

class PaginatedMembersNotifier extends StateNotifier<PaginatedMembersState> {
  PaginatedMembersNotifier(this._ref, this._familyId)
      : super(const PaginatedMembersState());

  final Ref _ref;
  final String _familyId;

  /// Number of items to request per page (fetch 21 to detect `hasMore`).
  static const int _pageSize = 20;

  // ── loadInitial ────────────────────────────────────────────────────

  /// Load the initial page.
  ///
  /// 1. If Drift cache is available, emit ALL cached members instantly
  ///    (no pagination on cache — it's local and fast).
  /// 2. Then fetch the first page from Supabase (LIMIT 21, newest first)
  ///    and replace the cached data with server data.
  /// 3. Cache the server results to Drift in the background.
  Future<void> loadInitial() async {
    // ── Step 1: Try Drift cache ────────────────────────────────────
    if (IsarDatabase.isInitialized) {
      try {
        final db = _ref.read(isarProvider);
        final cachedRows = await db.getPersonsByFamily(_familyId);

        if (cachedRows.isNotEmpty) {
          final cachedMembers = cachedRows.map((row) {
            final data = json.decode(row.data) as Map<String, dynamic>;
            return Person.fromJson(data);
          }).toList();

          // Sort newest-first to match our pagination order
          cachedMembers.sort((a, b) {
            final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bTime.compareTo(aTime);
          });

          // Emit cached data immediately (all of it, no pagination on cache)
          final lastCreated = cachedMembers.last.createdAt;
          state = state.copyWith(
            members: cachedMembers,
            cursor: lastCreated?.toIso8601String(),
            hasMore: true, // We don't know yet — will be corrected by network
            error: null,
          );
        }
      } catch (e) {
        debugPrint('⚠️ PaginatedMembers: Drift cache read error: $e');
      }
    }

    // ── Step 2: Fetch first page from Supabase ─────────────────────
    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) {
        // No client — if we already have cache data that's fine;
        // otherwise mark the empty state.
        if (state.members.isEmpty) {
          state = state.copyWith(hasMore: false);
        }
        return;
      }

      // v2.2: Real auth only — guard against no session.
      if (client.auth.currentSession == null) {
        if (state.members.isEmpty) {
          state = state.copyWith(hasMore: false);
        }
        return;
      }

      // Fetch LIMIT 21 to detect whether a next page exists
      final response = await client
          .from(_kPersonTable)
          .select()
          .eq('familyId', _familyId)
          .filter('deletedAt', 'is', null)
          .order('createdAt', ascending: false)
          .limit(_pageSize + 1);

      final list = response as List;
      final hasMorePages = list.length > _pageSize;

      // If we got 21, trim to 20 for display
      final trimmed = hasMorePages
          ? list.sublist(0, _pageSize)
          : list;

      final members = trimmed
          .map((json) => Person.fromJson(json as Map<String, dynamic>))
          .toList();

      // Compute new cursor from the last item's createdAt
      final newCursor = members.isNotEmpty
          ? members.last.createdAt?.toIso8601String()
          : null;

      state = state.copyWith(
        members: members,
        cursor: newCursor,
        hasMore: hasMorePages,
        error: null,
      );

      // ── Step 3: Cache results to Drift in background ────────────
      _cacheMembersToDrift(members);
    } catch (e) {
      debugPrint('⚠️ PaginatedMembers: Supabase fetch error: $e');

      // If we already have cached data, just set the error — don't wipe it.
      // If we have no data at all, set the error state.
      state = state.copyWith(
        error: e.toString(),
        // If cache gave us data, we still allow loadMore to try later
        hasMore: state.members.isNotEmpty ? true : false,
      );
    }
  }

  // ── loadMore ────────────────────────────────────────────────────────

  /// Load the next page (triggered by scroll).
  Future<void> loadMore() async {
    // Guard: already loading or no more items
    if (state.isLoadingMore || !state.hasMore) return;

    final currentCursor = state.cursor;
    if (currentCursor == null) return;

    state = state.copyWith(isLoadingMore: true);

    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) {
        state = state.copyWith(isLoadingMore: false);
        return;
      }

      if (client.auth.currentSession == null) {
        state = state.copyWith(isLoadingMore: false);
        return;
      }

      // Fetch next page: items older than cursor
      final response = await client
          .from(_kPersonTable)
          .select()
          .eq('familyId', _familyId)
          .filter('deletedAt', 'is', null)
          .lt('createdAt', currentCursor)
          .order('createdAt', ascending: false)
          .limit(_pageSize + 1);

      final list = response as List;
      final hasMorePages = list.length > _pageSize;

      final trimmed = hasMorePages
          ? list.sublist(0, _pageSize)
          : list;

      final newMembers = trimmed
          .map((json) => Person.fromJson(json as Map<String, dynamic>))
          .toList();

      // Append to existing members
      final allMembers = [...state.members, ...newMembers];

      // Compute new cursor from the last item
      final newCursor = allMembers.isNotEmpty
          ? allMembers.last.createdAt?.toIso8601String()
          : null;

      state = state.copyWith(
        members: allMembers,
        cursor: newCursor,
        isLoadingMore: false,
        hasMore: hasMorePages,
        error: null,
      );

      // Cache the new page to Drift in background
      _cacheMembersToDrift(newMembers);
    } catch (e) {
      debugPrint('⚠️ PaginatedMembers: loadMore error: $e');
      state = state.copyWith(
        isLoadingMore: false,
        error: e.toString(),
      );
    }
  }

  // ── refresh ─────────────────────────────────────────────────────────

  /// Refresh from network — resets to initial state and reloads.
  Future<void> refresh() async {
    state = const PaginatedMembersState();
    await loadInitial();
  }

  // ── Private helpers ─────────────────────────────────────────────────

  /// Cache a list of members to Drift in the background (fire-and-forget).
  void _cacheMembersToDrift(List<Person> members) {
    if (!IsarDatabase.isInitialized) return;

    // Fire-and-forget: don't await, don't block the UI
    Future(() async {
      try {
        final db = _ref.read(isarProvider);
        for (final member in members) {
          final json = member.toJson();
          await db.upsertPerson(CachedPersonsCompanion(
            id: Value(member.id),
            familyId: Value(member.familyId),
            name: Value(member.name),
            data: Value(jsonEncode(json)),
            cachedAt: Value(DateTime.now()),
          ));
        }
      } catch (e) {
        debugPrint('⚠️ PaginatedMembers: Drift cache write error: $e');
      }
    });
  }
}

// ── paginatedMembersProvider ─────────────────────────────────────────

/// Family-scoped provider for paginated member access.
///
/// Usage:
/// ```dart
/// final state = ref.watch(paginatedMembersProvider(familyId));
/// ref.read(paginatedMembersProvider(familyId).notifier).loadMore();
/// ```
final paginatedMembersProvider = StateNotifierProvider.family<
    PaginatedMembersNotifier, PaginatedMembersState, String>(
  (ref, familyId) {
    final notifier = PaginatedMembersNotifier(ref, familyId);
    // Auto-load initial data when the provider is first created.
    notifier.loadInitial();
    return notifier;
  },
);

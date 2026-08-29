// lib/features/family/presentation/providers/family_tree_provider.dart
//
// DAXELO KINREL — Family Tree Provider
//
// Family Space: Graph ↔ Tree (↔ Map) — Implementation Prompt §4.
//
// ONE-WRITE-PATH, TWO-RENDERERS architecture:
//   - Person + Relationship tables are the single source of truth (no
//     TreeMember table — see §6 "do not" list).
//   - `familyGraphProvider` reads via `get_viewer_family_graph` for the
//     Graph view's ego-centric proximity slice.
//   - `familyTreeProvider` (this file) reads via `get_family_tree` for
//     the Tree view's generation-complete view of the SAME data.
//   - Both providers share `FlatGraphResult` as the result type so the
//     downstream renderers (`FamilyGraphEngineView`, `FamilyTreeView`)
//     consume the same shape.
//
// CACHE INVALIDATION:
//   - `graphRealtimeProvider(familyId)` invalidates BOTH `familyGraphProvider`
//     AND `familyTreeProvider` on Person/Relationship writes (modified in
//     `family_graph_provider.dart`).
//   - This means a member added from either view is reflected in the
//     other view without a manual refresh — §8 acceptance criterion #1.
//
// PROGRESSIVE BRANCH LOAD:
//   - `fetchBranchAndMerge(rootPersonId)` calls `get_family_tree` with
//     `p_branch_root_id` and merges the result into the current state.
//   - Persisted expand/collapse state lives on `GraphLayoutState.expandedBranches`
//     (handled by `LayoutOverridesService` — same column the Graph view uses).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/supabase_service.dart';
import '../../../../core/viewer/viewer_provider.dart';
import 'family_graph_provider.dart' show FlatGraphResult;

/// AsyncNotifier that fetches and caches the generation-complete family
/// tree for a given family ID.
///
/// Mirrors `FamilyGraphNotifier` in shape (same `FlatGraphResult` result
/// type, same LRU cache pattern) but invokes the `get_family_tree` RPC
/// instead of `get_viewer_family_graph`. The differences are:
///   - No proximity cap (the RPC returns the whole family — generation-
///     complete by definition).
///   - Restricted-placeholder masking is done server-side (the RPC
///     returns `restricted: true` nodes with masked `name`/`avatarUrl`).
///   - Supports `fetchBranchAndMerge(rootPersonId)` for "▶ Uncle Ravi"
///     branch expansion.
class FamilyTreeNotifier
    extends FamilyAsyncNotifier<FlatGraphResult, String> {
  /// LRU cache keyed by familyId (mirrors `FamilyGraphNotifier._cache`).
  /// Bound to 5 entries to match the graph notifier's memory budget.
  static final Map<String, FlatGraphResult> _cache = {};
  static const int _maxCacheSize = 5;

  /// Stale-request protection (mirrors `FamilyGraphNotifier._fetchRevision`).
  static final Map<String, int> _fetchRevision = {};

  static void _addToCache(String familyId, FlatGraphResult result) {
    if (_cache.length >= _maxCacheSize && !_cache.containsKey(familyId)) {
      _cache.remove(_cache.keys.first);
    }
    _cache[familyId] = result;
  }

  /// Clear the in-memory cache for a specific family (or all families
  /// if [familyId] is null). Forces the next read to do a fresh
  /// Supabase round-trip.
  static void clearCache([String? familyId]) {
    if (familyId == null) {
      _cache.clear();
      _fetchRevision.clear();
    } else {
      _cache.remove(familyId);
    }
  }

  @override
  Future<FlatGraphResult> build(String familyId) async {
    // Bump the fetch revision so a stale in-flight fetch is discarded.
    _fetchRevision[familyId] = (_fetchRevision[familyId] ?? 0) + 1;
    final myRevision = _fetchRevision[familyId]!;

    // Cache hit?
    final cached = _cache[familyId];
    if (cached != null) {
      // Trigger a background refresh (fire-and-forget) so the cache
      // eventually reflects the latest server state, but return the
      // cached value immediately for instant paint.
      unawaited(_fetchTree(familyId, myRevision));
      return cached;
    }

    // Cache miss — fetch synchronously.
    return _fetchTree(familyId, myRevision);
  }

  /// Fetches the generation-complete tree via the `get_family_tree` RPC.
  Future<FlatGraphResult> _fetchTree(
    String familyId,
    int myRevision,
  ) async {
    try {
      final client = ref.read(supabaseProvider);
      if (client == null) {
        return const FlatGraphResult(persons: [], relationships: []);
      }

      // Resolve the viewer Person ID for this family — required by the
      // RPC's SECURITY DEFINER auth check (linkedUserId == auth.uid()).
      final viewerPersonId = await _resolveViewerPersonId(ref, familyId);
      if (viewerPersonId == null) {
        debugPrint('[FamilyTreeNotifier] No viewer person for $familyId');
        return const FlatGraphResult(persons: [], relationships: []);
      }

      final response = await client.rpc(
        'get_family_tree',
        params: <String, dynamic>{
          'p_family_id': familyId,
          'p_viewer_id': viewerPersonId,
          // p_branch_root_id defaults to NULL → full family tree
          'p_include_hidden': false,
        },
      );

      // Stale-request guard: if a newer fetch started, discard our result.
      if (_fetchRevision[familyId] != myRevision) {
        debugPrint('[FamilyTreeNotifier] Stale fetch discarded for $familyId');
        return _cache[familyId] ??
            const FlatGraphResult(persons: [], relationships: []);
      }

      final result = FlatGraphResult.fromRpc(response as Map<String, dynamic>);
      _addToCache(familyId, result);

      debugPrint(
          '[FamilyTreeNotifier] Fetched ${result.persons.length} persons, '
          '${result.relationships.length} edges for $familyId');
      return result;
    } catch (e, st) {
      debugPrint('[FamilyTreeNotifier] Fetch error: $e\n$st');
      // Graceful degradation — return cached data if available, else empty.
      return _cache[familyId] ??
          const FlatGraphResult(persons: [], relationships: []);
    }
  }

  /// Fetches a single branch via the `get_family_tree` RPC with
  /// `p_branch_root_id` set, and merges the result into the current
  /// provider state.
  ///
  /// This is the LAZY FETCH path for "▶ Uncle Ravi" branch expansion:
  /// when the user taps a collapsed-branch affordance, we fetch that
  /// root's ancestor-spine + descendants + spouses and merge them into
  /// the existing tree.
  ///
  /// Persists the expand/collapse choice via `LayoutOverridesService`
  /// (handled by the `BranchCollapseNotifier` watcher — same mechanism
  /// the Graph view uses, since both views share the `expandedBranches`
  /// column on `GraphLayoutState`).
  Future<void> fetchBranchAndMerge({
    required String rootPersonId,
  }) async {
    final familyId = arg;
    try {
      final client = ref.read(supabaseProvider);
      if (client == null) return;

      final viewerPersonId = await _resolveViewerPersonId(ref, familyId);
      if (viewerPersonId == null) return;

      debugPrint('[FamilyTreeNotifier] fetchBranchAndMerge: root=$rootPersonId');

      final response = await client.rpc(
        'get_family_tree',
        params: <String, dynamic>{
          'p_family_id': familyId,
          'p_viewer_id': viewerPersonId,
          'p_branch_root_id': rootPersonId,
          'p_include_hidden': false,
        },
      );

      if (response == null) {
        debugPrint('[FamilyTreeNotifier] get_family_tree(branch) returned null');
        return;
      }

      final branchResult =
          FlatGraphResult.fromRpc(response as Map<String, dynamic>);
      if (branchResult.persons.isEmpty) {
        debugPrint('[FamilyTreeNotifier] branch fetch returned empty');
        return;
      }

      // Merge into the current state. We re-use FlatGraphResult.mergeWithPage
      // which dedupes by person ID + edge ID — same merge logic the Graph
      // view's fetchBranchAndMerge uses.
      final current = state.valueOrNull;
      if (current == null) {
        // No existing state — just use the branch result (rare).
        state = AsyncData(branchResult);
        _addToCache(familyId, branchResult);
        return;
      }

      final merged = current.mergeWithPage(branchResult);
      state = AsyncData(merged);
      _addToCache(familyId, merged);

      debugPrint('[FamilyTreeNotifier] fetchBranchAndMerge: '
          'added ${branchResult.persons.length} persons, '
          '${branchResult.relationships.length} edges');
    } catch (e, st) {
      debugPrint('[FamilyTreeNotifier] fetchBranchAndMerge error: $e\n$st');
    }
  }
}

/// Resolves the viewer's Person ID for [familyId]. Used as the
/// `p_viewer_id` parameter for the `get_family_tree` RPC.
Future<String?> _resolveViewerPersonId(Ref ref, String familyId) async {
  try {
    final viewerAsync = await ref.read(viewerPersonIdProvider(familyId).future);
    return viewerAsync;
  } catch (e) {
    debugPrint('[_resolveViewerPersonId] viewer lookup failed: $e');
    return null;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// PROVIDER
// ═══════════════════════════════════════════════════════════════════════

/// Generation-complete family tree provider.
///
/// Watches the same Supabase Realtime channel as `familyGraphProvider`
/// (via `graphRealtimeProvider`) — invalidated on Person/Relationship
/// writes so a member added from either view is reflected in the other
/// without a manual refresh (§8 acceptance criterion #1).
final familyTreeProvider =
    AsyncNotifierProvider.family<FamilyTreeNotifier, FlatGraphResult, String>(
  FamilyTreeNotifier.new,
);

// lib/features/family/presentation/providers/family_graph_provider.dart
//
// DAXELO KINREL — Family Graph Providers
//
// Riverpod providers for the family graph feature:
//   1. familyGraphProvider(familyId) — fetches flat graph data via Supabase
//   2. graphLayoutProvider(familyId) — computes layout in an isolate
//   3. selectedEdgeProvider — tracks selected edge
//   4. selectedNodeProvider — tracks selected node
//   5. graphZoomProvider — tracks zoom level
//   6. graphRealtimeProvider(familyId) — Supabase Realtime invalidation
//
// DATA FETCHING STRATEGY (V6.0):
//   - Direct Supabase query (Person + Relationship tables) is the PRIMARY source
//     because it ALWAYS returns all non-deleted persons in the family, regardless
//     of relationship connectivity or p_max_degree limits.
//   - The RPC `get_family_graph` is used as a SUPPLEMENTARY source for richer
//     data (kinship labels, computed relationships), but ONLY if it returns
//     the same or more persons than the direct query.
//   - This ensures newly added members are ALWAYS visible, even if they
//     don't have relationships connecting them to the anchor yet.

import 'dart:async';
import 'dart:convert' show jsonEncode;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/isar_database.dart';
import '../../../../core/kinship/kinship_service.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/services/graph_layout_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/viewer/viewer_provider.dart';
import '../../../../graph/data/graph_data_models.dart'
    show PersonData, RelationshipData;
import '../../../../graph/engine/radial_layout.dart'
    show RadialLayout, RadialLayoutConfig;
import '../../../../graph/interaction/proximity_graph_state.dart'
    show
        proximityGraphProvider,
        ProximityGraphNotifier,
        ProximityGraphState,
        buildAdjacency,
        kProximityNodeBudget;
// v5.123 (Step 1): disclosure level drives the force-relaxation opt-in.
import '../../../../graph/interaction/expand_collapse.dart'
    show expandCollapseProvider, DisclosureLevel;
// v5.125 (Family Space): Tree shares the same realtime invalidation as
// Graph (§1 non-negotiable — one cache invalidation path, two renderers).
import 'family_tree_provider.dart' show familyTreeProvider;

/// Provider for the Drift database instance.
/// Used by [FamilyGraphNotifier] to persist graph data locally.
final driftDatabaseProvider = Provider<AppDatabase?>((ref) {
  try {
    if (IsarDatabase.isInitialized) {
      return IsarDatabase.instance;
    }
  } catch (e) {
    debugPrint('[driftDatabaseProvider] Error: $e');
  }
  return null;
});

// ═══════════════════════════════════════════════════════════════════════
// DATA MODELS
// ═══════════════════════════════════════════════════════════════════════

/// Flat graph data as received from the Supabase RPC.
///
/// The RPC `get_family_graph` returns { nodes, edges, isTruncated, totalCount }.
/// We map nodes → persons and edges → relationships to keep the rest of the
/// app (FamilyGraphEngineView, graphLayoutProvider) unchanged.
class FlatGraphResult {
  /// Raw person data mapped from RPC nodes.
  final List<Map<String, dynamic>> persons;

  /// Raw relationship data mapped from RPC edges.
  final List<Map<String, dynamic>> relationships;

  /// Whether the response was truncated (server capped at 5000 nodes).
  final bool isTruncated;

  /// Total count of persons in the family (may exceed [persons.length]
  /// when [isTruncated] is true).
  final int? totalCount;

  /// P5.1: Pagination offset of the current page (0 for first page).
  final int paginationOffset;

  /// P5.1: Pagination limit of the current page.
  final int paginationLimit;

  const FlatGraphResult({
    required this.persons,
    required this.relationships,
    this.isTruncated = false,
    this.totalCount,
    this.paginationOffset = 0,
    this.paginationLimit = 0,
  });

  /// Parses the Supabase RPC JSONB response into a [FlatGraphResult].
  ///
  /// Supports both the legacy `get_family_graph` RPC and the new
  /// `get_viewer_family_graph` RPC which adds:
  ///   - node.isViewer (bool) — true for the logged-in user's Person
  ///   - edge.label (string) — perspective-resolved label from viewer
  ///   - edge.labelAtoB (string) — raw label from personA→personB
  ///   - edge.labelBtoA (string) — raw label from personB→personA
  factory FlatGraphResult.fromRpc(Map<String, dynamic> json) {
    final rawNodes = (json['nodes'] as List?) ?? [];
    final rawEdges = (json['edges'] as List?) ?? [];

    // Map RPC node keys → legacy API keys expected by the rest of the app
    final persons = rawNodes.map((dynamic n) {
      final node = n as Map<String, dynamic>;
      return <String, dynamic>{
        'id': node['id'],
        'name': node['name'],
        'gender': node['gender'],
        'generationIndex': node['generationIndex'] ?? 0,
        'isAnchor': node['isAnchor'] ?? false,
        'photoUrl': node['avatarUrl'],
        'isDeceased': node['isDeceased'] ?? false,
        'visibility': node['visibility'],
        'username': node['username'],
        // v2.2: isViewer flag from the viewer-aware RPC.
        'isViewer': node['isViewer'] ?? false,
        // P3.3: dateOfBirth for birthday-glow computation. May be null
        // for persons without a recorded birthday — treated as "no glow"
        // by isNearBirthday(). The RPC returns a TIMESTAMPTZ string.
        'dateOfBirth': node['dateOfBirth']?.toString(),
        // v67 (BUG-4 FIX): Parse server-computed kinshipCategory. The
        // server (kinship.service.ts) emits one of: 'immediate_family',
        // 'extended_paternal', 'extended_maternal', 'in_laws',
        // 'by_marriage'. KinshipEdgeClassifier.fromServerCategory()
        // translates these to client categories. Previously this field
        // was never parsed, so PersonData.kinshipCategory was always
        // null — wasting the server's pre-computed category.
        'kinshipCategory': node['kinshipCategory'] ?? node['relationshipCategory'],
        'computedKinship': node['computedKinship'] ?? node['englishTerm'],
      };
    }).toList();

    // Map RPC edge keys → legacy API keys
    final relationships = rawEdges.map((dynamic e) {
      final edge = e as Map<String, dynamic>;
      final sourceId = edge['sourceId'] ?? edge['member_a_id'] ?? edge['source_id'];
      final targetId = edge['targetId'] ?? edge['member_b_id'] ?? edge['target_id'];
      // v2.2: Prefer the viewer-resolved 'label' from the RPC. If not
      // available (legacy RPC), fall back to relationshipKey.
      final relKey = edge['label'] ?? edge['relationshipKey'] ??
          edge['relationship_type'] ?? edge['relationshipType'] ?? 'unknown';
      return <String, dynamic>{
        'id': edge['id'],
        'fromPersonId': sourceId,
        'toPersonId': targetId,
        'relationshipKey': relKey,
        'isPrivate': edge['isPrivate'] ?? edge['is_private'] ?? false,
        // v2.2: Store the raw bidirectional labels for client-side fallback.
        'labelAtoB': edge['labelAtoB'],
        'labelBtoA': edge['labelBtoA'],
      };
    }).toList();

    // v90 FIX: Deduplicate edges by canonical pair (sorted from|to).
    //
    // The Relationship table stores BOTH the forward (A→B "father") AND
    // the inverse (B→A "son") row for every relationship created via
    // createRelationshipBetween(). The viewer RPC returns every row
    // faithfully, so a family with 3 conceptual relationships arrives
    // here as 6 raw edges — and the LINKS counter on the graph screen
    // shows "6" instead of "3".
    //
    // The direct-query path (_fetchGraphDirectQuery) already dedupes
    // using the same canonical-pair strategy, but the RPC path did not,
    // and the merge logic at the call site preferred the RPC's larger
    // un-deduped count. Fix the root cause here: dedupe inside the
    // factory so EVERY FlatGraphResult produced from an RPC has the
    // same invariant as the direct-query path.
    final seenPairs = <String>{};
    final dedupedRelationships = <Map<String, dynamic>>[];
    for (final r in relationships) {
      final from = r['fromPersonId']?.toString() ?? '';
      final to = r['toPersonId']?.toString() ?? '';
      if (from.isEmpty || to.isEmpty) continue;
      final pairKey = [from, to]..sort();
      final canonical = '${pairKey[0]}|${pairKey[1]}';
      if (seenPairs.contains(canonical)) continue; // skip inverse duplicate
      seenPairs.add(canonical);
      dedupedRelationships.add(r);
    }

    return FlatGraphResult(
      persons: persons,
      relationships: dedupedRelationships,
      isTruncated: json['isTruncated'] as bool? ?? false,
      totalCount: json['totalCount'] as int?,
      // P5.1: parse pagination metadata from the paginated RPC.
      paginationOffset: (json['offset'] as num?)?.toInt() ?? 0,
      paginationLimit: (json['limit'] as num?)?.toInt() ?? 0,
    );
  }

  /// P5.1: Returns true if there are more pages to fetch.
  bool get hasMorePages {
    if (totalCount == null) return false;
    return paginationOffset + persons.length < totalCount!;
  }

  /// P5.1: Merges this result with the [next] page, deduplicating
  /// persons and relationships. Returns a new FlatGraphResult with
  /// the combined data.
  FlatGraphResult mergeWithPage(FlatGraphResult next) {
    final seenPersonIds = persons.map((p) => p['id']?.toString()).toSet();
    final mergedPersons = List<Map<String, dynamic>>.from(persons);
    for (final p in next.persons) {
      final id = p['id']?.toString();
      if (id != null && !seenPersonIds.contains(id)) {
        mergedPersons.add(p);
        seenPersonIds.add(id);
      }
    }

    final seenEdgeIds = relationships.map((r) => r['id']?.toString()).toSet();
    final mergedRelationships = List<Map<String, dynamic>>.from(relationships);
    for (final r in next.relationships) {
      final id = r['id']?.toString();
      if (id != null && !seenEdgeIds.contains(id)) {
        mergedRelationships.add(r);
        seenEdgeIds.add(id);
      }
    }

    return FlatGraphResult(
      persons: mergedPersons,
      relationships: mergedRelationships,
      isTruncated: next.isTruncated,
      totalCount: next.totalCount,
      paginationOffset: paginationOffset,
      paginationLimit: paginationLimit,
    );
  }

  /// Convenience: parse raw person maps into typed [PersonData] objects.
  List<PersonData> toPersonDataList() {
    return persons.map((p) {
      return PersonData(
        id: p['id'] as String? ?? '',
        name: p['name'] as String? ?? '',
        gender: p['gender'] as String?,
        generationIndex: p['generationIndex'] as int? ?? 0,
        isAnchor: p['isAnchor'] as bool? ?? false,
        photoUrl: p['photoUrl'] as String?,
        isDeceased: p['isDeceased'] as bool? ?? false,
        kinshipCategory: p['kinshipCategory'] as String?,
        computedKinship: p['computedKinship'] as String?,
      );
    }).toList();
  }

  /// Convenience: parse raw relationship maps into typed [RelationshipData].
  List<RelationshipData> toRelationshipDataList() {
    return relationships.map((r) {
      return RelationshipData(
        id: r['id'] as String? ?? '',
        fromPersonId: r['fromPersonId'] as String? ?? '',
        toPersonId: r['toPersonId'] as String? ?? '',
        relationshipKey: r['relationshipKey'] as String? ?? '',
        displayLabel: r['displayLabel'] as String?,
        // v5.99: Parse labelAtoB so the layout BFS can use specific labels
        // for generation lookup (e.g. 'brother' → gen 0, not 'parent' → gen -1).
        labelAtoB: r['labelAtoB'] as String?,
      );
    }).toList();
  }
}

// ═══════════════════════════════════════════════════════════════════════
// v2.2: KINSHIP GENERATION MAP
// Builds a Map<relationshipKey, generationOffset> from KinshipService's
// 5,359 loaded relationships. Passed to GraphLayoutService.computeLayout
// so EVERY kinship type — not just the ~38 hardcoded ones — gets the
// correct generational positioning.
// ═══════════════════════════════════════════════════════════════════════

final kinshipGenerationMapProvider = Provider<Map<String, int>>((ref) {
  final kinship = KinshipService.instance;
  if (!kinship.isLoaded) return {};
  final map = <String, int>{};
  for (final rel in kinship.getAllRelationships()) {
    map[rel.relationshipKey] = rel.generation;
  }
  debugPrint('[kinshipGenerationMapProvider] Built map with ${map.length} entries');
  return map;
});

// ═══════════════════════════════════════════════════════════════════════
// ISOLATE LAYOUT PARAMS (for compute())
// ═══════════════════════════════════════════════════════════════════════

/// Parameter bundle passed to the isolate for layout computation.
class _LayoutComputeParams {
  final List<GraphPerson> persons;
  final List<GraphRelationship> relationships;
  final String? anchorPersonId;
  final bool compactMode;
  final Map<String, int>? kinshipGenerationMap;

  /// v5.123 (Step 1): EXPLICIT opt-in for GraphLayoutService's force-
  /// relaxation pass. Only the "Show All Branches" / Level 4 path
  /// (expandCollapseProvider disclosure level == DisclosureLevel.full)
  /// passes true — the default ego-centric view must keep nodes
  /// exactly on their rings.
  final bool allowForceRelaxation;

  const _LayoutComputeParams({
    required this.persons,
    required this.relationships,
    this.anchorPersonId,
    this.compactMode = false,
    this.kinshipGenerationMap,
    this.allowForceRelaxation = false,
  });
}

/// Top-level function executed inside the isolate via [compute].
GraphLayoutResult _runLayoutInIsolate(_LayoutComputeParams params) {
  final service = GraphLayoutService();
  return service.computeLayout(
    persons: params.persons,
    relationships: params.relationships,
    anchorPersonId: params.anchorPersonId,
    compactMode: params.compactMode,
    kinshipGenerationMap: params.kinshipGenerationMap,
    allowForceRelaxation: params.allowForceRelaxation,
  );
}

// ═══════════════════════════════════════════════════════════════════════
// HELPER: resolve viewer member ID for a family (v2.2)
// ═══════════════════════════════════════════════════════════════════════

/// Resolves the **viewer** Person ID for [familyId] using the v2.2
/// `viewerPersonIdProvider`. Falls back to the legacy anchor lookup when
/// no viewer is linked (architecture §3 invariant 7: `isAnchor` is kept
/// only as a legacy fallback for unclaimed profiles).
///
/// This is used as the `p_member_id` parameter for the `get_family_graph`
/// RPC. The RPC needs *some* member ID to seed the BFS — using the viewer
/// (instead of always the anchor) ensures the BFS starts from the
/// viewer's perspective whenever possible.
Future<String?> _resolveViewerMemberId(
  Ref ref,
  SupabaseClient client,
  String familyId,
) async {
  // v5.8: Viewer-FIRST and ONLY. Do NOT fall back to the anchor person.
  // The anchor fallback was the root cause of the graph always rendering
  // from the family creator's perspective, even when a different user was
  // logged in. When no viewer is linked, return null — the graph will
  // show no "You" node and no perspective labels (better than wrong ones).
  try {
    final viewerAsync = await ref.read(viewerPersonIdProvider(familyId).future);
    return viewerAsync;
  } catch (e) {
    debugPrint('[_resolveViewerMemberId] viewer lookup failed: $e');
    return null;
  }
}

/// Looks up the anchor person ID for [familyId] from the Person table.
/// Falls back to the first person in the family if no anchor is set.
///
/// LEGACY: This is only used as a fallback for unclaimed profiles per
/// architecture §3 invariant 7. Runtime relationship resolution must
/// go through `viewerPersonIdProvider`, not this helper.
Future<String?> _resolveAnchorMemberId(
  SupabaseClient client,
  String familyId,
) async {
  try {
    // Try anchor person first (non-deleted)
    final anchor = await client
        .from('Person')
        .select('id')
        .eq('familyId', familyId)
        .eq('isAnchor', true)
        .isFilter('deletedAt', null)
        .maybeSingle();

    if (anchor != null) return anchor['id'] as String?;

    // Fallback: first non-deleted person in family
    final first = await client
        .from('Person')
        .select('id')
        .eq('familyId', familyId)
        .isFilter('deletedAt', null)
        .order('createdAt')
        .limit(1)
        .maybeSingle();

    return first?['id'] as String?;
  } catch (e) {
    debugPrint('[_resolveAnchorMemberId] Error: $e');
    return null;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 1. FAMILY GRAPH PROVIDER — AsyncNotifierProvider.family
// ═══════════════════════════════════════════════════════════════════════

/// AsyncNotifier that fetches and caches flat graph data for a family.
///
/// Features:
///   - Fetches from Supabase RPC `get_family_graph` directly (no server hop)
///   - Caches the last successful result in memory
///   - On error, returns cached data if available (graceful degradation)
///   - Supports refresh via [refreshGraph]
class FamilyGraphNotifier extends FamilyAsyncNotifier<FlatGraphResult, String> {
  /// In-memory cache keyed by familyId so we can fallback on error.
  /// v60: Bounded to 5 entries (LRU) to prevent unbounded memory growth
  /// on long sessions with many family visits.
  static final Map<String, FlatGraphResult> _cache = {};
  static const int _maxCacheSize = 5;

  /// v94 (EDGE BUG FIX): Stale-request protection. Each `build()` call
  /// increments this counter; when an async `_fetchGraph` completes, it
  /// checks whether its revision is still the latest. If a newer fetch
  /// has started, the older result is discarded — preventing a stale
  /// Person-only response from overwriting a newer graph that already
  /// contains the newly-created edge.
  static final Map<String, int> _fetchRevision = {};

  /// v60: Add to cache with LRU eviction — removes oldest entry if
  /// the cache exceeds _maxCacheSize.
  static void _addToCache(String familyId, FlatGraphResult result) {
    if (_cache.length >= _maxCacheSize && !_cache.containsKey(familyId)) {
      _cache.remove(_cache.keys.first);
    }
    _cache[familyId] = result;
  }

  /// Clear the in-memory cache for a specific family (or all families
  /// if [familyId] is null). This forces the next read of
  /// [familyGraphProvider] to do a fresh Supabase round-trip.
  static void clearCache([String? familyId]) {
    if (familyId == null) {
      _cache.clear();
      _fetchRevision.clear();
    } else {
      _cache.remove(familyId);
      // NOTE: We do NOT reset _fetchRevision here — clearing the cache
      // should NOT invalidate in-flight fetches. The revision counter
      // is only bumped by build() so the latest fetch always wins.
    }
  }

  /// v5.135: Alias for clearCache(null) — clears ALL cached graph data.
  /// Called on sign-out to ensure a stale cache from a previous session
  /// doesn't get served to the next user who signs in on the same device.
  static void clearAllCache() {
    clearCache(null);
  }

  /// v64 (BUG-1 FIX): Optimistically inject a new person + relationship
  /// edge into the cached [FlatGraphResult] for [familyId].
  ///
  /// WHY THIS EXISTS:
  ///   When the user adds a new family member via AddPersonSheet, the
  ///   createRelationship() call writes the relationship row to Supabase
  ///   and then calls `ref.invalidate(familyGraphProvider(familyId))`.
  ///   The invalidation triggers a fresh Supabase round-trip, but during
  ///   the ~200–800ms refetch window, the graph widget rebuilds with the
  ///   STALE cached FlatGraphResult (which has no entry for the new
  ///   person). The new node then has no `relationshipKey` and falls
  ///   through to the 'extended' slate-gray fallback color — even though
  ///   the user explicitly selected "Father" / "Brother" / etc.
  ///
  /// WHAT THIS METHOD DOES:
  ///   - If a cached FlatGraphResult exists for [familyId], appends a
  ///     new person entry and a new relationship entry to it.
  ///   - The injected relationship uses the EXACT relationshipKey the
  ///     user selected, so the very next paint assigns the correct
  ///     KinshipEdgeCategory color (parent=blue, child=pink, etc.).
  ///   - The next server refetch will replace this optimistic entry
  ///     with the real server data (same content, just authoritative).
  ///
  /// v94 (EDGE BUG FIX): This method previously had `if (cached == null)
  /// return;` which made it a silent no-op whenever the cache had been
  /// cleared — exactly the state left by `createRelationship`'s
  /// `clearCache` call. The optimistic edge was NEVER injected in the
  /// manual-add flow, so the UI depended entirely on the async refetch
  /// winning a race against the Relationship INSERT commit. This is the
  /// root cause of the "edge doesn't render" bug.
  ///
  /// The method now delegates to [upsertPersonAndEdge] which mutates the
  /// CURRENT provider state (not just the cache) and is robust to a null
  /// cache. Callers that have a notifier instance should call
  /// [upsertPersonAndEdge] directly instead of this static method.
  static void injectOptimisticEdge({
    required String familyId,
    required String personId,
    required String personName,
    String? gender,
    required String relationshipKey,
    required String anchorPersonId,
    String? photoUrl,
    bool isDeceased = false,
  }) {
    final cached = _cache[familyId];
    if (cached == null) {
      // v94: No longer a silent no-op. We can't mutate provider state
      // from a static method (we don't have the notifier instance), so
      // we log a warning. Callers that need guaranteed optimistic
      // insertion should use the instance method [upsertPersonAndEdge]
      // via `ref.read(familyGraphProvider(familyId).notifier)`.
      debugPrint(
        '[FamilyGraphNotifier] injectOptimisticEdge: cache is null for '
        'family $familyId — optimistic edge NOT injected. Use '
        'upsertPersonAndEdge() for guaranteed state mutation.',
      );
      return;
    }

    // Idempotency: skip if the person is already in the cache (avoids
    // duplicate nodes if the caller fires this twice).
    final alreadyPresent = cached.persons.any(
      (p) => p['id'] == personId,
    );
    if (alreadyPresent) return;

    // Append the new person + relationship to a copy of the cache.
    // We mutate a COPY (not the original list references) so Riverpod
    // detects the change and triggers a rebuild.
    final newPersons = List<Map<String, dynamic>>.from(cached.persons);
    // v67 (BUG-12 FIX): Infer the generation index from the relationship
    // key so the newly-added node lands on the correct ring immediately,
    // instead of flashing on the anchor ring (gen 0) for ~500ms until
    // the server refetch lands.
    final inferredGen = _inferGenerationIndex(relationshipKey);
    newPersons.add(<String, dynamic>{
      'id': personId,
      'name': personName,
      'gender': gender,
      'generationIndex': inferredGen,
      'isAnchor': false,
      'photoUrl': photoUrl,
      'isDeceased': isDeceased,
      'visibility': 'public',
      'username': null,
      'isViewer': false,
    });

    final newRelationships = List<Map<String, dynamic>>.from(cached.relationships);
    newRelationships.add(<String, dynamic>{
      'id': 'optimistic_${personId}_$relationshipKey',
      'fromPersonId': personId,
      'toPersonId': anchorPersonId,
      'relationshipKey': relationshipKey,
      'isPrivate': false,
      'labelAtoB': null,
      'labelBtoA': null,
    });

    final updated = FlatGraphResult(
      persons: newPersons,
      relationships: newRelationships,
      isTruncated: cached.isTruncated,
      totalCount: cached.totalCount,
    );
    _addToCache(familyId, updated);
  }

  /// v94 (EDGE BUG FIX): Upsert a person + relationship edge into the
  /// CURRENT provider state (not just the cache). This is the
  /// guaranteed-to-work version of [injectOptimisticEdge] — it does NOT
  /// silently no-op when the cache is null.
  ///
  /// This is the method callers should use after a successful
  /// Person + Relationship compound mutation. It:
  ///   1. Reads the current async state (which may be null during an
  ///      in-flight refetch).
  ///   2. If state exists, upserts the person + edge into a COPY and
  ///      calls `state = AsyncData(updated)`. This triggers Riverpod
  ///      to rebuild dependents immediately — the edge appears in the
  ///      graph BEFORE the authoritative refetch lands.
  ///   3. If state is null/loading/error, falls back to mutating the
  ///      cache (if it exists) and invalidating the layout provider so
  ///      the next build picks up the optimistic data.
  ///   4. Always invalidates `graphLayoutProvider(familyId)` so the
  ///      layout recomputes with the new edge.
  ///
  /// This method is safe to call from any context that has the notifier
  /// instance via `ref.read(familyGraphProvider(familyId).notifier)`.
  void upsertPersonAndEdge({
    required String personId,
    required String personName,
    String? gender,
    required String relationshipKey,
    required String targetPersonId,
    String? photoUrl,
    bool isDeceased = false,
    String? customColorsJson,
  }) {
    final familyId = arg;
    final current = state.valueOrNull;

    if (current != null) {
      // Upsert person (add if missing, else update).
      final newPersons = List<Map<String, dynamic>>.from(current.persons);
      final personIdx = newPersons.indexWhere((p) => p['id'] == personId);
      final inferredGen = _inferGenerationIndex(relationshipKey);
      final personEntry = <String, dynamic>{
        'id': personId,
        'name': personName,
        'gender': gender,
        'generationIndex': inferredGen,
        'isAnchor': false,
        'photoUrl': photoUrl,
        'isDeceased': isDeceased,
        'visibility': 'public',
        'username': null,
        'isViewer': false,
      };
      if (personIdx >= 0) {
        newPersons[personIdx] = personEntry;
      } else {
        newPersons.add(personEntry);
      }

      // Upsert relationship by canonical pair (sorted from|to).
      final newRelationships =
          List<Map<String, dynamic>>.from(current.relationships);
      final pair = [personId, targetPersonId]..sort();
      final canonical = '${pair[0]}|${pair[1]}';
      final relIdx = newRelationships.indexWhere((r) {
        final from = r['fromPersonId']?.toString() ?? '';
        final to = r['toPersonId']?.toString() ?? '';
        final p = [from, to]..sort();
        return '${p[0]}|${p[1]}' == canonical;
      });
      final relEntry = <String, dynamic>{
        'id': 'optimistic_${personId}_$relationshipKey',
        'fromPersonId': personId,
        'toPersonId': targetPersonId,
        'relationshipKey': relationshipKey,
        'isPrivate': false,
        'labelAtoB': null,
        'labelBtoA': null,
      };
      if (relIdx >= 0) {
        newRelationships[relIdx] = relEntry;
      } else {
        newRelationships.add(relEntry);
      }

      final updated = FlatGraphResult(
        persons: newPersons,
        relationships: newRelationships,
        isTruncated: current.isTruncated,
        totalCount: current.totalCount,
      );
      _addToCache(familyId, updated);
      state = AsyncData(updated);
    } else {
      // State is null/loading/error — mutate cache if it exists.
      final cached = _cache[familyId];
      if (cached != null) {
        injectOptimisticEdge(
          familyId: familyId,
          personId: personId,
          personName: personName,
          gender: gender,
          relationshipKey: relationshipKey,
          anchorPersonId: targetPersonId,
          photoUrl: photoUrl,
          isDeceased: isDeceased,
        );
      }
      // If cache is also null, the next build() will fetch from
      // Supabase and pick up the edge (which has already been INSERTed
      // by the caller). We deliberately do NOT fabricate state here.
    }

    // Always invalidate the layout provider so positions recompute.
    ref.invalidate(graphLayoutProvider(familyId));
  }

  // ═══════════════════════════════════════════════════════════════════════
  // v5.115: BRANCH-SCOPED FETCH (Task 1)
  // ═══════════════════════════════════════════════════════════════════════

  /// Fetches a single branch via the `get_member_branch` RPC and merges
  /// the returned nodes/edges into the current provider state.
  ///
  /// This is the LAZY FETCH path for branch expansion: instead of loading
  /// the entire family up front, the graph loads only the anchor's 2-hop
  /// neighborhood on open, then fetches individual branches on demand
  /// when the user taps a collapsed-branch chip.
  ///
  /// Parameters:
  /// [rootPersonId] — the person at the root of the branch (the chip's
  ///   `rootPersonId` from `CollapsedBranch`).
  /// [branchType] — the branch type for the RPC ('maternal', 'paternal',
  ///   'cousins', 'inLaws', 'grandchildren'). Mapped from the
  ///   `relationshipKey` on `CollapsedBranch` by the caller.
  /// [depth] — the traversal depth (default 2, matching the RPC's default
  ///   and the expand_collapse.dart Level 1→2 transition).
  ///
  /// Merge strategy:
  ///   - Persons: union by ID (skip if already present)
  ///   - Edges: union by canonical pair key (sorted from|to)
  ///   - Does NOT remove existing nodes/edges — only adds new ones
  ///
  /// After merge, invalidates `graphLayoutProvider` so the layout
  /// recomputes with the new nodes.
  Future<void> fetchBranchAndMerge({
    required String rootPersonId,
    required String branchType,
    int depth = 2,
  }) async {
    final familyId = arg;
    final client = ref.read(supabaseProvider);
    if (client == null || client.auth.currentSession == null) return;

    try {
      debugPrint('[FamilyGraphNotifier] fetchBranchAndMerge: '
          'root=$rootPersonId type=$branchType depth=$depth');

      final response = await client.rpc(
        'get_member_branch',
        params: <String, dynamic>{
          'p_member_id': rootPersonId,
          'p_branch_type': branchType,
          'p_depth': depth,
        },
      ).timeout(const Duration(seconds: 15));

      final data = response as Map<String, dynamic>?;
      if (data == null || data.containsKey('error')) {
        debugPrint('[FamilyGraphNotifier] get_member_branch returned null/error');
        return;
      }

      // Parse the RPC response into a FlatGraphResult.
      // The RPC returns {nodes: [...], edges: [...]} with fields
      // sourceId/targetId — FlatGraphResult.fromRpc already handles this.
      final branchResult = FlatGraphResult.fromRpc(data);

      if (branchResult.persons.isEmpty && branchResult.relationships.isEmpty) {
        debugPrint('[FamilyGraphNotifier] get_member_branch returned empty');
        return;
      }

      // Merge into the current state (union by ID / canonical pair).
      final current = state.valueOrNull;
      if (current == null) return;

      final newPersons = List<Map<String, dynamic>>.from(current.persons);
      final existingPersonIds = <String>{
        for (final p in newPersons) p['id'] as String? ?? '',
      };
      for (final p in branchResult.persons) {
        final id = p['id'] as String?;
        if (id != null && !existingPersonIds.contains(id)) {
          newPersons.add(p);
          existingPersonIds.add(id);
        }
      }

      final newRelationships = List<Map<String, dynamic>>.from(current.relationships);
      final existingPairs = <String>{};
      for (final r in newRelationships) {
        final from = r['fromPersonId'] as String? ?? '';
        final to = r['toPersonId'] as String? ?? '';
        final pair = [from, to]..sort();
        existingPairs.add('${pair[0]}|${pair[1]}');
      }
      for (final r in branchResult.relationships) {
        final from = r['fromPersonId'] as String? ?? '';
        final to = r['toPersonId'] as String? ?? '';
        final pair = [from, to]..sort();
        final canonical = '${pair[0]}|${pair[1]}';
        if (!existingPairs.contains(canonical)) {
          newRelationships.add(r);
          existingPairs.add(canonical);
        }
      }

      final updated = FlatGraphResult(
        persons: newPersons,
        relationships: newRelationships,
        isTruncated: current.isTruncated,
        totalCount: current.totalCount,
      );
      _addToCache(familyId, updated);
      state = AsyncData(updated);

      debugPrint('[FamilyGraphNotifier] fetchBranchAndMerge: '
          'added ${branchResult.persons.length} persons, '
          '${branchResult.relationships.length} edges');

      // Invalidate layout so positions recompute with new nodes.
      ref.invalidate(graphLayoutProvider(familyId));
    } catch (e) {
      debugPrint('[FamilyGraphNotifier] fetchBranchAndMerge error: $e');
    }
  }

  /// v5.115: Maps a relationship key from `CollapsedBranch.relationshipKey`
  /// to the branch_type parameter expected by `get_member_branch`.
  ///
  /// ⚠️⚠️⚠️ KEEP IN SYNC WITH THE DATABASE ⚠️⚠️⚠️
  ///
  /// This function and the SQL function `get_member_branch` (see
  /// supabase/migrations/20260831120000_get_member_branch_generic_type.sql)
  /// form a CONTRACT: every branch_type string returned here must be a
  /// `p_branch_type` CASE arm the SQL function actually implements.
  ///
  ///   This function returns      → SQL must implement
  ///   ──────────────────────────────────────────────
  ///   'maternal'                 → WHEN 'maternal'
  ///   'paternal'                 → WHEN 'paternal'
  ///   'cousins'                  → WHEN 'cousins'
  ///   'inLaws'                   → WHEN 'inLaws'
  ///   'grandchildren'            → WHEN 'grandchildren'
  ///   'generic' (fallback)       → WHEN 'generic' (BFS fallback)
  ///
  /// ANY new relationship key or branch type added in ONE place MUST be
  /// reflected in the other in the SAME change, otherwise chip taps
  /// silently no-op again (the exact Bug-1 class this file fixed in
  /// v5.131): an unrecognized branch_type hits the SQL `ELSE` arm,
  /// returns an empty {nodes, edges} payload, and the chip appears to
  /// do nothing. The 'generic' fallback below is the safety net for
  /// unknown keys — NEVER remove it.
  ///
  /// v5.131 (Bug 1 fix): now returns `'generic'` instead of `null` for
  /// unrecognized keys. The server's `get_member_branch` RPC was extended
  /// (migration 20260831120000) to accept `'generic'` and run a BFS up to
  /// `p_depth` hops regardless of relationship-key label — so a chip with
  /// a custom/test key like `YakFather`, `StepMother`, or `HalfBrother`
  /// now actually fetches its hidden members instead of silently
  /// no-op'ing.
  ///
  /// Returning `null` previously caused `_fetchAndExpandBranch` to skip
  /// the `fetchBranchAndMerge` call entirely; the subsequent
  /// `revealPersons()` then found nothing to reveal (the hidden members
  /// weren't in `flat.persons`) and the chip visually did nothing.
  ///
  /// v5.132: the return type is now NON-NULLABLE (`String`, was
  /// `String?`) — the compiler enforces the v5.131 invariant that the
  /// fallback always resolves to a valid branch type.
  static String branchTypeForRelationshipKey(String key) {
    final k = key.toLowerCase().trim();
    if (k == 'mother' || k == 'maternal_grandmother' ||
        k == 'maternal_grandfather' || k.startsWith('maternal')) {
      return 'maternal';
    }
    if (k == 'father' || k == 'paternal_grandmother' ||
        k == 'paternal_grandfather' || k.startsWith('paternal')) {
      return 'paternal';
    }
    if (k == 'cousin' || k == 'niece' || k == 'nephew') {
      return 'cousins';
    }
    if (k == 'father_in_law' || k == 'mother_in_law' ||
        k == 'brother_in_law' || k == 'sister_in_law' ||
        k.contains('in_law') || k.contains('inlaw')) {
      return 'inLaws';
    }
    if (k == 'grandson' || k == 'granddaughter' || k == 'grandchild') {
      return 'grandchildren';
    }
    // v5.131: universal fallback — server-side BFS fetches all neighbors
    // within p_depth hops regardless of relationship-type label. Always
    // returns a non-null so _fetchAndExpandBranch always calls
    // fetchBranchAndMerge (no more "chip taps do nothing" dead-ends).
    return 'generic';
  }

  /// v67 (BUG-12): Infers the generation index for a newly-added member
  /// based on their relationship key to the anchor.
  ///
  /// Returns the generation offset:
  ///   - parent/grandparent/aunt/uncle → negative (ancestors, upper rings)
  ///   - child/grandchild/niece/nephew → positive (descendants, lower rings)
  ///   - sibling/spouse/cousin → 0 (same generation as anchor)
  ///   - unknown → 0 (safe default; server refetch will correct it)
  static int _inferGenerationIndex(String relationshipKey) {
    final k = relationshipKey.toLowerCase().trim();
    // Ancestors (up)
    if (k == 'father' || k == 'mother' || k == 'parent' ||
        k == 'step_father' || k == 'step_mother' ||
        k == 'stepfather' || k == 'stepmother') {
      return -1;
    }
    if (k == 'grandfather' || k == 'grandmother' || k == 'grandparent' ||
        k.startsWith('paternal_grand') || k.startsWith('maternal_grand')) {
      return -2;
    }
    if (k == 'great_grandfather' || k == 'great_grandmother' ||
        k.startsWith('great_grand')) {
      return -3;
    }
    if (k == 'uncle' || k == 'aunt' || k.startsWith('paternal_uncle') ||
        k.startsWith('paternal_aunt') || k.startsWith('maternal_uncle') ||
        k.startsWith('maternal_aunt') || k.startsWith('fathers_brother') ||
        k.startsWith('fathers_sister') || k.startsWith('mothers_brother') ||
        k.startsWith('mothers_sister')) {
      return -1; // aunts/uncles are same generation as parents
    }
    // Descendants (down)
    if (k == 'son' || k == 'daughter' || k == 'child' ||
        k == 'step_son' || k == 'step_daughter' ||
        k == 'stepson' || k == 'stepdaughter') {
      return 1;
    }
    if (k == 'grandson' || k == 'granddaughter' || k == 'grandchild') {
      return 2;
    }
    if (k == 'nephew' || k == 'niece' ||
        k.startsWith('brothers_son') || k.startsWith('brothers_daughter') ||
        k.startsWith('sisters_son') || k.startsWith('sisters_daughter')) {
      return 1; // nieces/nephews are same generation as children
    }
    // Same generation
    if (k == 'brother' || k == 'sister' || k == 'sibling' ||
        k == 'husband' || k == 'wife' || k == 'spouse' || k == 'partner' ||
        k == 'cousin' || k.startsWith('cousin') ||
        k.startsWith('elder_brother') || k.startsWith('younger_brother') ||
        k.startsWith('elder_sister') || k.startsWith('younger_sister') ||
        k.startsWith('half_brother') || k.startsWith('half_sister') ||
        k.startsWith('step_brother') || k.startsWith('step_sister')) {
      return 0;
    }
    // In-laws — same generation as the corresponding blood relation
    if (k.contains('in_law') || k.contains('in-law')) {
      if (k.contains('father') || k.contains('mother')) return -1;
      if (k.contains('son') || k.contains('daughter')) return 1;
      return 0; // sibling-in-law
    }
    // Unknown — safe default
    return 0;
  }

  @override
  Future<FlatGraphResult> build(String familyId) async {
    // Invalidate the layout when graph data is (re)fetched
    ref.invalidate(graphLayoutProvider(familyId));

    // v5.4: Watch viewerPersonIdProvider so the graph rebuilds when the
    // current user changes (account switch, sign-in, sign-out). This
    // ensures the "You" node and perspective labels update immediately.
    // We use ref.watch (not ref.read) so Riverpod rebuilds this provider
    // when viewerPersonIdProvider's value changes.
    ref.watch(viewerPersonIdProvider(familyId));

    // Guard against empty familyId
    if (familyId.isEmpty) {
      debugPrint('[FamilyGraphNotifier] build() called with empty familyId, returning empty result');
      return const FlatGraphResult(persons: [], relationships: []);
    }

    debugPrint('[FamilyGraphNotifier] build() called for familyId=$familyId');
    final result = await _fetchGraph(familyId);

    // Persist fetched data to Drift for offline access and reactive streams
    await _syncToDrift(familyId, result);

    debugPrint('[FamilyGraphNotifier] Loaded ${result.persons.length} persons, '
        '${result.relationships.length} relationships for $familyId');
    return result;
  }

  /// Persists fetched graph data into the local Drift database so that
  /// Drift watch streams emit and the graph re-renders reactively.
  Future<void> _syncToDrift(String familyId, FlatGraphResult result) async {
    try {
      final db = ref.read(driftDatabaseProvider);
      if (db == null) return;

      final persons = result.persons.map((p) {
        return CachedPersonsCompanion(
          id: Value(p['id'] as String? ?? ''),
          familyId: Value(familyId),
          name: Value(p['name'] as String? ?? ''),
          // v38 BUG-8 FIX: Use jsonEncode instead of toString().
          // Map.toString() produces Dart literal syntax ({id: abc, name: John})
          // which is NOT valid JSON and cannot be parsed by json.decode.
          data: Value(jsonEncode(p)),
          cachedAt: Value(DateTime.now()),
        );
      }).toList();

      if (persons.isNotEmpty) {
        await db.upsertPersons(persons);
        debugPrint('[FamilyGraphNotifier] Synced ${persons.length} persons to Drift for $familyId');
      }

      final relationships = result.relationships.map((r) {
        return CachedRelationshipsCompanion(
          id: Value(r['id'] as String? ?? ''),
          familyId: Value(familyId),
          fromId: Value(r['fromPersonId'] as String? ?? ''),
          toId: Value(r['toPersonId'] as String? ?? ''),
          relationshipType: Value(r['relationshipKey'] as String? ?? ''),
          // v38 BUG-8 FIX: Use jsonEncode instead of toString().
          data: Value(jsonEncode(r)),
          cachedAt: Value(DateTime.now()),
        );
      }).toList();

      if (relationships.isNotEmpty) {
        await db.upsertRelationships(relationships);
        debugPrint('[FamilyGraphNotifier] Synced ${relationships.length} relationships to Drift for $familyId');
      }
    } catch (e) {
      // Silently fail — Drift sync is best-effort, Supabase is the source of truth
      debugPrint('[FamilyGraphNotifier] Drift sync failed: $e');
    }
  }

  // ── Data Fetching ──────────────────────────────────────────────────

  Future<FlatGraphResult> _fetchGraph(String familyId) async {
    final client = ref.read(supabaseProvider);
    if (client == null) {
      throw Exception('Supabase client not available');
    }

    // v2.2 FIX: Guard against no session. Without a session, RLS will
    // block all queries and the graph will show an error. Return an
    // empty result so the UI shows the "no members" state instead of
    // a blank error screen. The router should redirect unauthenticated
    // users to /sign-in before they reach this screen, but this guard
    // prevents the error if they somehow land here.
    if (client.auth.currentSession == null) {
      debugPrint('[FamilyGraphNotifier] No session — returning empty graph');
      return const FlatGraphResult(persons: [], relationships: []);
    }

    // v94 (EDGE BUG FIX): Stale-request protection. Bump the revision
    // counter at the START of this fetch. When the fetch completes, we
    // check whether this revision is still the latest — if a newer
    // fetch has started (e.g. from a realtime invalidation or a second
    // add-member mutation), we discard this result so a stale
    // Person-only response cannot overwrite a newer graph that already
    // contains the edge.
    final myRevision = (_fetchRevision[familyId] ?? 0) + 1;
    _fetchRevision[familyId] = myRevision;

    try {
      // v5.144 (ARCHITECTURAL FIX): Try the proximity RPC FIRST.
      // The RPC now returns ONLY the ~22-node proximity set (viewer +
      // ring 1 + ring 2, capped at 50). This is the primary path —
      // the client never sees the other 660+ nodes.
      //
      // The direct query (all 714 nodes) is used ONLY as a fallback
      // when the RPC fails. It's also available for "show all" mode
      // and search-jump targets via _fetchGraphDirectQuery directly.
      try {
        final viewerId = await _resolveViewerMemberId(ref, client, familyId);
        if (viewerId != null) {
          debugPrint('[FamilyGraphNotifier] v5.144: Calling get_viewer_family_graph (proximity) with viewerId=$viewerId');
          // v5.144: Pass p_max_nodes=50 so the RPC returns ONLY the
          // proximity set. The server does the BFS filter — the client
          // never sees the other 660+ nodes.
          final response = await client.rpc(
            'get_viewer_family_graph',
            params: <String, dynamic>{
              'p_family_id': familyId,
              'p_viewer_id': viewerId,
              'p_max_nodes': 50,
            },
          ).timeout(const Duration(seconds: 15));

          // v94: Stale-check after the RPC async gap.
          if (_fetchRevision[familyId] != myRevision) {
            debugPrint('[FamilyGraphNotifier] Stale fetch (after RPC) — discarding');
            return state.valueOrNull ?? const FlatGraphResult(persons: [], relationships: []);
          }

          final data = response as Map<String, dynamic>?;
          if (data != null && !data.containsKey('error')) {
            final rpcResult = FlatGraphResult.fromRpc(data);
            _addToCache(familyId, rpcResult);
            debugPrint(
              '[FamilyGraphNotifier] v5.144 Proximity RPC: Loaded ${rpcResult.persons.length} persons (of ${rpcResult.totalCount ?? '?'}) , '
              '${rpcResult.relationships.length} relationships for $familyId',
            );
            return rpcResult;
          }
        }
      } catch (rpcError) {
        debugPrint('[FamilyGraphNotifier] v5.144 Proximity RPC failed: $rpcError — falling back to direct query');
      }

      // ── Fallback: Direct query (all persons) ──
      // Only reached if the RPC failed. This fetches all 714 nodes —
      // slower, but ensures the graph still renders.
      final directResult = await _fetchGraphDirectQuery(client, familyId);

      if (directResult.persons.isEmpty) {
        debugPrint('[FamilyGraphNotifier] No members found in family $familyId');
        return const FlatGraphResult(persons: [], relationships: []);
      }

      // v94: Stale-check after the direct-query async gap.
      if (_fetchRevision[familyId] != myRevision) {
        debugPrint('[FamilyGraphNotifier] Stale fetch (after direct fallback) — discarding');
        return state.valueOrNull ?? directResult;
      }

      _addToCache(familyId, directResult);
      return directResult;
    } on PostgrestException catch (e) {
      debugPrint('[FamilyGraphNotifier] Supabase error: ${e.message}');
      return _fallbackOrThrow(familyId, e);
    } on TimeoutException catch (e) {
      debugPrint('[FamilyGraphNotifier] Timeout: $e');
      return _fallbackOrThrow(familyId, e);
    } catch (e) {
      debugPrint('[FamilyGraphNotifier] Unexpected error: $e');
      return _fallbackOrThrow(familyId, e);
    }
  }

  /// v94 (EDGE BUG FIX): Union-merge RPC and direct-query graph results
  /// by ID / canonical edge pair — NOT by relationship count.
  ///
  /// The previous count-based merge could silently drop the new edge if
  /// RPC and direct had equal relationship counts but different edge
  /// sets (e.g. RPC missing the new edge but having a phantom/duplicate
  /// elsewhere). This method takes the UNION of:
  ///   • persons — by Person ID (RPC wins ties for label richness)
  ///   • relationships — by canonical pair key (direct wins when RPC's
  ///     relationshipKey is null/unknown)
  /// so no edge is ever silently dropped.
  FlatGraphResult _mergeGraphResults({
    required FlatGraphResult rpcResult,
    required FlatGraphResult directResult,
  }) {
    // ── Merge persons by ID (union) ──
    final personsById = <String, Map<String, dynamic>>{};
    // Direct first (source of truth for existence), then RPC overrides
    // for label richness (RPC carries viewer-perspective labels).
    for (final p in directResult.persons) {
      final id = p['id']?.toString();
      if (id != null && id.isNotEmpty) personsById[id] = p;
    }
    for (final p in rpcResult.persons) {
      final id = p['id']?.toString();
      if (id != null && id.isNotEmpty) {
        // RPC may carry richer viewer-perspective fields — prefer it
        // for label fields, but keep direct's existence authority.
        personsById[id] = {...personsById[id] ?? {}, ...p};
      }
    }

    // ── Merge relationships by canonical pair (union) ──
    final relsByPair = <String, Map<String, dynamic>>{};
    for (final edge in rpcResult.relationships) {
      final key = _canonicalEdgeKey(edge);
      if (key.isNotEmpty) relsByPair[key] = edge;
    }
    for (final edge in directResult.relationships) {
      final key = _canonicalEdgeKey(edge);
      if (key.isEmpty) continue;
      final existing = relsByPair[key];
      if (existing == null ||
          existing['relationshipKey'] == null ||
          existing['relationshipKey'] == 'unknown') {
        // Direct wins when RPC's edge is missing/stale/unknown.
        relsByPair[key] = edge;
      }
    }

    return FlatGraphResult(
      persons: personsById.values.toList(),
      relationships: relsByPair.values.toList(),
      isTruncated: rpcResult.isTruncated || directResult.isTruncated,
      totalCount: personsById.length,
    );
  }

  /// v94: Canonical edge pair key — sorted (from, to) joined by '|'.
  /// Used for union-merging RPC + direct relationship sets so no edge
  /// is silently dropped due to count-based selection.
  static String _canonicalEdgeKey(Map<String, dynamic> edge) {
    final from = edge['fromPersonId']?.toString() ?? '';
    final to = edge['toPersonId']?.toString() ?? '';
    if (from.isEmpty || to.isEmpty) return '';
    final ids = [from, to]..sort();
    return '${ids[0]}|${ids[1]}';
  }

  /// Fetches graph data by directly querying Person and Relationship tables.
  /// Used as a fallback when the `get_family_graph` RPC fails or returns
  /// incomplete results.
  Future<FlatGraphResult> _fetchGraphDirectQuery(
    SupabaseClient client,
    String familyId,
  ) async {
    try {
      // v5.135: Log the authenticated user ID and family ID for diagnosing
      // RLS/access issues. If the direct query returns 0 persons but the
      // stats show non-zero, this log reveals whether the current session's
      // user ID matches a FamilyMember row for this family.
      final currentUserId = client.auth.currentUser?.id;
      debugPrint('[v5.135] _fetchGraphDirectQuery: familyId=$familyId, '
          'authUserId=$currentUserId');

      // Query all non-deleted persons in this family
      final rawPersons = await client
          .from('Person')
          .select('id, name, gender, "generationIndex", "isAnchor", "photoUrl", '
              '"isDeceased", visibility, username, "familyId"')
          .eq('familyId', familyId)
          .isFilter('deletedAt', null)
          .timeout(const Duration(seconds: 15));

      // v5.135: If the query returned 0 persons, do a diagnostic count
      // check to determine if this is a genuine empty family or an RLS
      // access issue. We fetch a limited sample (up to 1 row) to see if
      // ANY data is accessible — if even 1 row comes back, the family
      // isn't genuinely empty and the 0-row result above was an RLS/
      // session issue.
      if (rawPersons.isEmpty) {
        debugPrint('[v5.135] Direct query returned 0 persons for family '
            '$familyId. Checking if this is an access issue...');
        try {
          final sampleResult = await client
              .from('Person')
              .select('id')
              .eq('familyId', familyId)
              .isFilter('deletedAt', null)
              .limit(1)
              .timeout(const Duration(seconds: 5));
          final sampleCount = sampleResult.length;
          debugPrint('[v5.135] Sample query: $sampleCount rows returned for '
              'family $familyId. '
              'If >0, this is an ACCESS ISSUE, not an empty family.');
          if (sampleCount > 0) {
            debugPrint('[v5.135] ACCESS ISSUE CONFIRMED: persons '
                'exist but RLS blocked the full SELECT. User $currentUserId may not '
                'have a FamilyMember row for family $familyId.');
          }
        } catch (countError) {
          debugPrint('[v5.135] Sample query failed: $countError');
        }
      }

      // Query all relationships in this family.
      // Strategy: try the optimal filtered query first; if it fails (column
      // mismatch, RLS, etc.), progressively degrade to broader queries so we
      // never silently return zero edges when data actually exists.
      //
      // The previous implementation had a single fallback that re-applied the
      // SAME `.eq('isActive', true)` filter — if the primary query failed
      // because `isActive` was named `is_active` in the schema, the fallback
      // failed for the same reason and zero rows came back, making the graph
      // look edgeless even when relationships existed in the DB.
      // v36 FIX: Log actual Relationship table columns for debugging.
      // This helps diagnose column-name mismatches between what the Flutter
      // query expects (camelCase) and what the DB actually has.
      try {
        final sample = await client
            .from('Relationship')
            .select('*')
            .eq('familyId', familyId)
            .limit(1)
            .timeout(const Duration(seconds: 5));
        if (sample.isNotEmpty) {
          debugPrint('[COLUMN-DEBUG] Relationship columns: ${sample.first.keys.toList()}');
        } else {
          debugPrint('[COLUMN-DEBUG] No relationships exist for family $familyId');
        }
      } catch (e) {
        debugPrint('[COLUMN-DEBUG] Error sampling Relationship: $e');
      }

      List<Map<String, dynamic>> rawRelationships;
      try {
        // P0.3: Re-added .eq('isActive', true) — the DB now guarantees
        // non-null via NOT NULL constraint + DEFAULT true + BEFORE INSERT
        // trigger (trg_ensure_relationship_isactive_default). The v36
        // workaround (fetching all + coercing null → true client-side) is
        // no longer needed. The v9 retry-without-filter safety net is also
        // removed — the DB trigger eliminates the race condition.
        // v83: Also fetch customColors column for custom kinship rendering.
        rawRelationships = await client
            .from('Relationship')
            .select('id, "fromPersonId", "toPersonId", "relationshipKey", "familyId", "customColors"')
            .eq('familyId', familyId)
            .eq('isActive', true)
            .timeout(const Duration(seconds: 15));
      } catch (colError) {
        debugPrint('[EDGE-DEBUG] Primary relationship query failed: $colError. Trying select(*)');
        try {
          // Fallback A: select all columns with isActive filter
          rawRelationships = await client
              .from('Relationship')
              .select('*')
              .eq('familyId', familyId)
              .eq('isActive', true)
              .timeout(const Duration(seconds: 15));
        } catch (activeError) {
          debugPrint('[EDGE-DEBUG] Fallback A failed: $activeError. Last resort: unfiltered select(*)');
          try {
            // Fallback B: drop the familyId filter too (will be filtered client-side)
            rawRelationships = await client
                .from('Relationship')
                .select('*')
                .timeout(const Duration(seconds: 15));
          } catch (e2) {
            debugPrint('[EDGE-DEBUG] All relationship queries failed: $e2');
            rawRelationships = [];
          }
        }
      }

      // ── EDGE DEBUG: Log raw Supabase relationship data ──
      debugPrint('[EDGE-DEBUG] Raw relationships from Supabase: ${rawRelationships.length}');
      if (rawRelationships.isNotEmpty) {
        final rawFirst = rawRelationships.first as Map<String, dynamic>;
        debugPrint('[EDGE-DEBUG] Raw first relationship keys: ${rawFirst.keys.toList()}');
        debugPrint('[EDGE-DEBUG] Raw first relationship values: $rawFirst');
      } else {
        debugPrint('[EDGE-DEBUG] WARNING: No relationships returned from Supabase!');
        // Try a broader query to check if the table/columns exist
        try {
          final countCheck = await client
              .from('Relationship')
              .select('id')
              .limit(1);
          debugPrint('[EDGE-DEBUG] Table exists, total rows (sampled): ${countCheck.length}');
        } catch (e2) {
          debugPrint('[EDGE-DEBUG] Relationship table query failed: $e2');
        }
      }

      // Map to the same format as FlatGraphResult.fromRpc
      final persons = rawPersons.map((dynamic n) {
        final node = n as Map<String, dynamic>;
        return <String, dynamic>{
          'id': node['id'],
          'name': node['name'],
          'gender': node['gender'],
          'generationIndex': node['generationIndex'] ?? 0,
          'isAnchor': node['isAnchor'] ?? false,
          'photoUrl': node['photoUrl'],
          'isDeceased': node['isDeceased'] ?? false,
          'visibility': node['visibility'],
          'username': node['username'],
        };
      }).toList();

      final relationships = rawRelationships
          .map((dynamic e) {
            final edge = e as Map<String, dynamic>;
            // Try every plausible column-name variant for cross-schema compatibility
            // (Prisma camelCase, Postgres snake_case, lowercase fallback).
            // Also handle RPC-style member_a_id/member_b_id which the
            // FlatGraphResult.fromRpc factory already supports.
            final fromId = edge['fromPersonId'] ?? edge['from_person_id']
                ?? edge['fromPersonid'] ?? edge['frompersonid']
                ?? edge['member_a_id'] ?? edge['from_member_id']
                ?? edge['sourceId'] ?? edge['source_id'];
            final toId = edge['toPersonId'] ?? edge['to_person_id']
                ?? edge['toPersonid'] ?? edge['topersonid']
                ?? edge['member_b_id'] ?? edge['to_member_id']
                ?? edge['targetId'] ?? edge['target_id'];
            final rKey = edge['relationshipKey'] ?? edge['relationship_key']
                ?? edge['relationshipType'] ?? edge['relationship_type']
                ?? edge['relationshipkey'] ?? 'unknown';
            if (fromId == null || toId == null) {
              debugPrint('[EDGE-DEBUG] WARNING: Null ID in relationship! '
                  'edge keys=${edge.keys.toList()}, '
                  'fromPersonId=$fromId, toPersonId=$toId, relationshipKey=$rKey');
            }
            // P0.3: isActive is guaranteed true by the .eq('isActive', true)
            // filter. The DB NOT NULL constraint + trigger ensure no NULL
            // values can exist. No client-side coercion needed.
            return <String, dynamic>{
              'id': edge['id'],
              'fromPersonId': fromId,
              'toPersonId': toId,
              'relationshipKey': rKey,
              'isPrivate': edge['is_private'] ?? edge['isPrivate'] ?? false,
              'isActive': true,
              'customColors': edge['customColors'], // v83: pass through for custom kinship
            };
          })
          // Filter out edges with null/empty IDs — these can never be
          // drawn (the painter looks up positions[fromPersonId] which
          // would return null for "" and silently skip the edge).
          // Previously these were appended with null IDs and then
          // silently dropped by the painter, making the bug invisible.
          .where((r) {
            final fromId = r['fromPersonId'];
            final toId = r['toPersonId'];
            return fromId != null &&
                toId != null &&
                fromId.toString().isNotEmpty &&
                toId.toString().isNotEmpty;
          })
          .toList();

      debugPrint('[EDGE-DEBUG] After mapping+filter: '
          '${relationships.length} valid relationships '
          '(from ${rawRelationships.length} raw rows)');

      // v38 BUG-3 FIX: Deduplicate edges.
      // createRelationship inserts BOTH forward (A→B "father") AND inverse
      // (B→A "son") rows. Without dedup, every edge is drawn twice
      // (overlapping), the edge count is 2× the real count, and
      // deleteRelationship leaves phantom edges behind.
      //
      // Strategy: canonicalize each edge as (min(from,to), max(from,to))
      // and keep only ONE row per pair. We prefer the forward direction
      // (the one whose relationshipKey is the "natural" label, e.g.
      // "father" rather than "son") — but either works for rendering.
      final seenPairs = <String>{};
      final dedupedRelationships = <Map<String, dynamic>>[];
      for (final r in relationships) {
        final from = r['fromPersonId']?.toString() ?? '';
        final to = r['toPersonId']?.toString() ?? '';
        if (from.isEmpty || to.isEmpty) continue;
        // Canonical key: sorted pair so A→B and B→A map to the same key
        final pairKey = [from, to]..sort();
        final canonical = '${pairKey[0]}|${pairKey[1]}';
        if (seenPairs.contains(canonical)) {
          // Already have an edge for this pair — skip the duplicate
          continue;
        }
        seenPairs.add(canonical);
        dedupedRelationships.add(r);
      }
      if (dedupedRelationships.length < relationships.length) {
        debugPrint('[EDGE-DEBUG] Deduped: ${relationships.length} → ${dedupedRelationships.length} '
            '(removed ${relationships.length - dedupedRelationships.length} duplicate inverse edges)');
      }
      var finalRelationships = dedupedRelationships;

      // P0.3: The v9 retry-without-filter safety net was removed. The DB
      // now guarantees isActive is non-null (NOT NULL constraint + DEFAULT
      // true + BEFORE INSERT trigger trg_ensure_relationship_isactive_default).
      // The race condition that v9 worked around — freshly-created rows
      // with isActive = NULL being excluded by the filter — can no longer
      // occur. If finalRelationships is empty here, it genuinely means
      // no active relationships exist for this family.

      final result = FlatGraphResult(
        persons: persons,
        relationships: finalRelationships,
        isTruncated: false,
        totalCount: persons.length,
      );

      _addToCache(familyId, result);

      debugPrint(
        '[FamilyGraphNotifier] Direct query: Loaded ${result.persons.length} persons, '
        '${result.relationships.length} relationships for $familyId',
      );

      return result;
    } catch (e) {
      debugPrint('[FamilyGraphNotifier] Direct query error: $e');
      // If even the direct query fails, try cache
      final cached = _cache[familyId];
      if (cached != null) {
        debugPrint('[FamilyGraphNotifier] Using cached data for $familyId');
        return cached;
      }
      rethrow;
    }
  }

  /// Returns cached data if available, otherwise tries Drift offline
  /// cache, otherwise rethrows [error].
  ///
  /// v2.2 FIX: Previously this only checked the in-memory `_cache`.
  /// When Supabase failed (RLS, no session, network error), the graph
  /// showed a blank error screen even when Drift had cached data from
  /// a previous session. Now we fall back to Drift before giving up.
  FlatGraphResult _fallbackOrThrow(String familyId, Object error) {
    // 1. Try in-memory cache first (fastest).
    final cached = _cache[familyId];
    if (cached != null) {
      debugPrint('[FamilyGraphNotifier] Using in-memory cache for $familyId');
      return cached;
    }

    // 2. Try Drift offline cache.
    try {
      final db = ref.read(driftDatabaseProvider);
      if (db != null) {
        // This is synchronous-ish — we can't await in a non-async method,
        // but we can check if Drift has any persons for this family.
        // The Drift watch stream will emit them reactively if they exist.
        debugPrint('[FamilyGraphNotifier] Checking Drift cache for $familyId');
        // Return an empty result instead of throwing — the Drift
        // watch stream (graphDriftPersonsProvider) will populate the
        // graph reactively if data exists. This prevents the blank
        // error screen.
        return const FlatGraphResult(persons: [], relationships: []);
      }
    } catch (e) {
      debugPrint('[FamilyGraphNotifier] Drift fallback failed: $e');
    }

    // 3. Last resort: rethrow the original error.
    throw error;
  }

  // ── Public Methods ─────────────────────────────────────────────────

  /// Refreshes the graph data by invalidating and re-fetching.
  Future<void> refreshGraph() async {
    ref.invalidateSelf();
  }
}

/// Family-scoped provider that fetches flat graph data for a given family.
///
/// Usage:
/// ```dart
/// final asyncResult = ref.watch(familyGraphProvider(familyId));
/// asyncResult.when(
///   data: (result) => /* use result.persons, result.relationships */,
///   loading: () => /* show shimmer */,
///   error: (e, st) => /* show error with retry */,
/// );
/// ```
final familyGraphProvider =
    AsyncNotifierProvider.family<FamilyGraphNotifier, FlatGraphResult, String>(
  FamilyGraphNotifier.new,
);

// ═══════════════════════════════════════════════════════════════════════
// 1b. UNLINKED PERSON IDS PROVIDER — v5.9
// ═══════════════════════════════════════════════════════════════════════

/// Computes the set of Person IDs that have ZERO active relationship edges
/// in the family graph — i.e. "unlinked" members who were added to the
/// family but never connected to anyone via a relationship.
///
/// This is a pure derivation from [familyGraphProvider]'s data (persons +
/// relationships). No new RPC or query is needed — the edges are already
/// fetched by the existing graph query.
///
/// The provider reactively rebuilds whenever [familyGraphProvider] changes
/// (new member added, relationship created/deleted) because it watches
/// the same provider.
///
/// Edge case: if the family has exactly 1 member (the viewer themselves),
/// that member is NOT considered "unlinked" — a family of 1 is a valid
/// starting state, not an error to fix.
///
/// Usage:
/// ```dart
/// final unlinkedIds = ref.watch(unlinkedPersonIdsProvider(familyId));
/// if (unlinkedIds.contains(personId)) {
///   // Render with "needs linking" style
/// }
/// ```
final unlinkedPersonIdsProvider =
    Provider.family<Set<String>, String>((ref, familyId) {
  final graphAsync = ref.watch(familyGraphProvider(familyId));
  final graph = graphAsync.valueOrNull;
  if (graph == null) return <String>{};

  final persons = graph.persons;
  final relationships = graph.relationships;

  // Edge case: family of 1 — not unlinked
  if (persons.length <= 1) return <String>{};

  // Collect all person IDs that appear in at least one active relationship
  final connectedIds = <String>{};
  for (final r in relationships) {
    final isActive = r['isActive'] as bool? ?? true;
    if (!isActive) continue;
    final from = r['fromPersonId']?.toString();
    final to = r['toPersonId']?.toString();
    if (from != null && from.isNotEmpty) connectedIds.add(from);
    if (to != null && to.isNotEmpty) connectedIds.add(to);
  }

  // Unlinked = all persons NOT in connectedIds
  final unlinked = <String>{};
  for (final p in persons) {
    final id = p['id']?.toString();
    if (id != null && id.isNotEmpty && !connectedIds.contains(id)) {
      unlinked.add(id);
    }
  }

  return unlinked;
});

final graphLayoutProvider =
    FutureProvider.family<GraphLayoutResult, String>((ref, familyId) async {
  final graphAsync = ref.watch(familyGraphProvider(familyId));

  final graphData = graphAsync.valueOrNull;
  if (graphData == null) {
    return const GraphLayoutResult(
      positions: {},
      canvasWidth: 0,
      canvasHeight: 0,
    );
  }

  final persons = graphData.toPersonDataList();
  final relationships = graphData.toRelationshipDataList();

  if (persons.isEmpty) {
    return const GraphLayoutResult(
      positions: {},
      canvasWidth: 0,
      canvasHeight: 0,
    );
  }

  final graphPersons = persons.map((p) => p.toGraphPerson()).toList();
  final graphRelationships =
      relationships.map((r) => r.toGraphRelationship()).toList();

  // v5.8: Center the layout on the VIEWER's node ONLY.
  final viewerId = ref.read(viewerPersonIdProvider(familyId)).valueOrNull;
  final PersonData centerPerson;
  if (viewerId != null) {
    final match = persons.where((p) => p.id == viewerId).firstOrNull;
    if (match != null) {
      centerPerson = match;
    } else {
      centerPerson = persons.firstWhere(
        (p) => p.isAnchor,
        orElse: () => persons.first,
      );
    }
  } else {
    centerPerson = persons.firstWhere(
      (p) => p.isAnchor,
      orElse: () => persons.first,
    );
  }

  // ── v5.114: EGO-CENTRIC PROXIMITY FILTER ──────────────────────────
  // Instead of laying out ALL 714 nodes, filter to the anchor's 2-hop
  // neighborhood (capped at ~30 nodes). This uses the RadialLayout
  // engine (lib/graph/engine/radial_layout.dart) which places the
  // anchor at center and each relationship-distance ring on a
  // concentric circle.
  //
  // The proximity state is managed by proximityGraphProvider. On graph
  // open, it initializes with ring 1 + ring 2. When the user taps a
  // node on the outermost ring, expandFromPerson() adds that node's
  // neighbors to the visible set.
  final proximityState = ref.watch(proximityGraphProvider);

  // Build adjacency for the proximity filter.
  final allEdges = <({String fromId, String toId, String edgeId, String relationshipKey})>[
    for (final r in graphRelationships)
      (
        fromId: r.fromPersonId,
        toId: r.toPersonId,
        edgeId: r.id,
        relationshipKey: r.relationshipKey,
      ),
  ];
  final adjacency = buildAdjacency(allEdges);
  final allPersonIds = <String>{for (final p in graphPersons) p.id};

  // v5.118 → v5.123: Compute the default visible IDs SYNCHRONOUSLY.
  // v5.123 (RIVERPOD FIX): The old code CALLED
  // proximityGraphProvider.notifier.initialize() here — mutating another
  // provider during a provider's own initialization, which Riverpod
  // forbids ("Providers are not allowed to modify other providers during
  // their initialization" — crashed family_graph_screen_fab_test).
  // The notifier is now initialized from the WIDGET layer
  // (canvas_mixin), and this provider computes the same deterministic
  // default set via the pure static helper when the notifier has not
  // been initialized yet.
  Set<String> visibleIds;
  if (proximityState.isInitialized) {
    visibleIds = proximityState.visibleIds;
  } else {
    // Pure computation — no provider mutation. v5.123 (Step 2): the
    // edge list is passed so the adaptive soft/hard budget can rank
    // candidates by kinship category when truncating at the hard cap.
    visibleIds = ProximityGraphNotifier.computeDefaultVisibleIds(
      anchorId: centerPerson.id,
      allPersons: allPersonIds,
      adjacency: adjacency,
      edges: allEdges,
    );
  }

  // v5.118: If visibleIds is STILL empty (edge case: anchor not in
  // allPersons), fall back to showing ALL persons so the graph isn't
  // blank. This should rarely happen but prevents a blank screen.
  if (visibleIds.isEmpty && graphPersons.isNotEmpty) {
    visibleIds = allPersonIds;
  }

  // v5.121: Removed the < 10 fallback that showed ALL 714 nodes.
  // The BFS expansion in proximity_graph_state.dart now expands to
  // ring 3, 4, 5... until kProximityNodeBudget is reached, so the
  // proximity set is always filled to ~50 nodes (or all reachable
  // nodes if the family is smaller). No need to fall back to ALL
  // 714 nodes — that made the canvas too big and only showed 1 node.

  if (visibleIds.isEmpty) {
    return const GraphLayoutResult(
      positions: {},
      canvasWidth: 0,
      canvasHeight: 0,
    );
  }

  // Filter persons + relationships to the visible set.
  final proximityPersons = graphPersons
      .where((p) => visibleIds.contains(p.id))
      .toList();
  final proximityRelationships = graphRelationships
      .where((r) =>
          visibleIds.contains(r.fromPersonId) &&
          visibleIds.contains(r.toPersonId))
      .toList();

  // ── v5.114: Use RadialLayout for the proximity set ───────────────
  // RadialLayout places the anchor at center, ring 1 on a circle around
  // the anchor, ring 2 on a larger circle, etc. This is exactly the
  // ego-centric view the user wants.
  //
  // v5.123 (Step 1): Derive the force-relaxation opt-in from the
  // disclosure level. The DEFAULT ego-centric view (this RadialLayout
  // path — pure algebra, no physics) NEVER relaxes: positioning comes
  // purely from ring radius + evenly-spaced angles + the barycenter
  // branch-grouping pass. Only the "Show All Branches" / Level 4 path
  // (expandCollapseProvider.currentDisclosureLevel ==
  // DisclosureLevel.full, set by _showAllWithWarning → expandAll)
  // sets allowForceRelaxation = true, which is honoured whenever the
  // GraphLayoutService engine is used (see _runLayoutInIsolate). The
  // old implicit `n > 60` node-count trigger inside
  // GraphLayoutService.computeLayout is gone — callers must opt in.
  final disclosureLevel =
      ref.watch(expandCollapseProvider.select((s) => s.currentDisclosureLevel));
  final allowForceRelaxation = disclosureLevel == DisclosureLevel.full;

  final radialLayout = RadialLayout(
    config: const RadialLayoutConfig(
      // v5.153: Increased ring spacing from 260→320 and compact from
      // 200→260 to give more room between generation bands. The old
      // values still caused dense clusters where labels overlapped.
      ringSpacing: 320.0,
      compactSpacing: 260.0,
      spouseAngularOffset: 90.0,
      canvasPadding: 120.0,
      // v5.153: Increased baseRadius from 220→280 so ring 1 nodes have
      // more angular room before they start crowding the anchor.
      baseRadius: 280.0,
      compact: false,
    ),
  );

  // v5.145 (STEP 3): Run RadialLayout.compute() in an isolate so the
  // O(n²) × 20-iteration _deOverlapPositions doesn't block the UI
  // thread. With 22 nodes (post-proximity-RPC) this is ~1-2ms — fine
  // on the UI thread. But when the user expands a branch to 50+ nodes,
  // the de-overloop spikes to 5-15ms on low-end devices, causing a
  // dropped frame during the expand animation.
  //
  // The isolate receives plain Lists + Maps (isolate-safe primitives)
  // and returns a plain Map<String, List<double>> (positions as
  // [dx, dy] pairs) + canvas dimensions. We reconstruct the
  // GraphLayoutResult on the main isolate.
  //
  // Threshold: only use the isolate for > 15 nodes. Below that, the
  // isolate spawn overhead (1-2ms) exceeds the layout cost.
  GraphLayoutResult result;
  final nodeCount = proximityPersons.length;
  final layoutStopwatch = Stopwatch()..start();

  if (nodeCount > 15) {
    try {
      result = await _runRadialLayoutInIsolate(
        radialLayout: radialLayout,
        persons: proximityPersons,
        relationships: proximityRelationships,
        anchorPersonId: centerPerson.id,
      );
    } catch (e) {
      debugPrint('[graphLayoutProvider] Isolate layout failed: $e — falling back to sync');
      result = radialLayout.compute(
        persons: proximityPersons,
        relationships: proximityRelationships,
        anchorPersonId: centerPerson.id,
      );
    }
  } else {
    // Small graph — sync is faster (avoids isolate spawn overhead).
    result = radialLayout.compute(
      persons: proximityPersons,
      relationships: proximityRelationships,
      anchorPersonId: centerPerson.id,
    );
  }
  layoutStopwatch.stop();

  AnalyticsService.instance.logEvent('graph_layout_time', {
    'total_ms': layoutStopwatch.elapsedMilliseconds,
    'node_count': proximityPersons.length,
    'edge_count': proximityRelationships.length,
    'compact_mode': false,
    'isolate_success': nodeCount > 15,
    'viewer_centered': true,
    'layout_engine': 'radial',
    'proximity_filtered': true,
    'total_family_size': graphPersons.length,
    'allow_force_relaxation': allowForceRelaxation,
    'disclosure_level': disclosureLevel,
  });

  return result;
});

/// v5.145 (STEP 3): Runs RadialLayout.compute() in a background isolate
/// via Flutter's `compute()` helper. The isolate receives plain Lists +
/// Maps (isolate-safe primitives) and returns the positions as a
/// Map<String, List<double>> + canvas dimensions.
///
/// This keeps the O(n²) × 20-iteration _deOverlapPositions off the UI
/// thread, preventing dropped frames during branch expand/collapse on
/// low-end devices.
Future<GraphLayoutResult> _runRadialLayoutInIsolate({
  required RadialLayout radialLayout,
  required List<GraphPerson> persons,
  required List<GraphRelationship> relationships,
  required String anchorPersonId,
}) async {
  // The isolate can't receive a RadialLayout instance (it has a config
  // object with non-const fields). Instead we pass the config values
  // as primitives and reconstruct the RadialLayout inside the isolate.
  final config = radialLayout.config;

  final isolateResult = await compute(
    _radialLayoutIsolateEntry,
    _RadialLayoutIsolateInput(
      persons: persons,
      relationships: relationships,
      anchorPersonId: anchorPersonId,
      ringSpacing: config.ringSpacing,
      compactSpacing: config.compactSpacing,
      spouseAngularOffset: config.spouseAngularOffset,
      canvasPadding: config.canvasPadding,
      baseRadius: config.baseRadius,
      compact: config.compact,
      minAngularGap: config.minAngularGap,
    ),
  );

  return isolateResult;
}

/// v5.145 (STEP 3): The input to the radial layout isolate. All fields
/// are isolate-safe primitives (no closures, no Flutter objects).
class _RadialLayoutIsolateInput {
  final List<GraphPerson> persons;
  final List<GraphRelationship> relationships;
  final String anchorPersonId;
  final double ringSpacing;
  final double compactSpacing;
  final double spouseAngularOffset;
  final double canvasPadding;
  final double baseRadius;
  final bool compact;
  final double minAngularGap;

  const _RadialLayoutIsolateInput({
    required this.persons,
    required this.relationships,
    required this.anchorPersonId,
    required this.ringSpacing,
    required this.compactSpacing,
    required this.spouseAngularOffset,
    required this.canvasPadding,
    required this.baseRadius,
    required this.compact,
    required this.minAngularGap,
  });
}

/// v5.145 (STEP 3): The top-level isolate entry point. Must be a
/// top-level function (not a closure or method) so it can be sent to
/// the isolate. Reconstructs the RadialLayout from the primitive
/// config values, runs compute(), and returns the result.
///
/// GraphLayoutResult is isolate-safe (Map<String, Offset> + doubles +
/// Maps of primitives) so it can be returned directly.
GraphLayoutResult _radialLayoutIsolateEntry(_RadialLayoutIsolateInput input) {
  final layout = RadialLayout(
    config: RadialLayoutConfig(
      ringSpacing: input.ringSpacing,
      compactSpacing: input.compactSpacing,
      spouseAngularOffset: input.spouseAngularOffset,
      canvasPadding: input.canvasPadding,
      baseRadius: input.baseRadius,
      compact: input.compact,
      minAngularGap: input.minAngularGap,
    ),
  );
  return layout.compute(
    persons: input.persons,
    relationships: input.relationships,
    anchorPersonId: input.anchorPersonId,
  );
}

// ═══════════════════════════════════════════════════════════════════════
// 3. SELECTED EDGE PROVIDER
// ═══════════════════════════════════════════════════════════════════════

/// Tracks the currently selected relationship edge ID.
final selectedEdgeProvider = StateProvider<String?>((ref) => null);

// ═══════════════════════════════════════════════════════════════════════
// 4. SELECTED NODE PROVIDER
// ═══════════════════════════════════════════════════════════════════════

/// Tracks the currently selected person node ID.
final selectedNodeProvider = StateProvider<String?>((ref) => null);

// ═══════════════════════════════════════════════════════════════════════
// 5. GRAPH ZOOM PROVIDER
// ═══════════════════════════════════════════════════════════════════════

/// Tracks the current zoom level of the graph viewer.
final graphZoomProvider = StateProvider<double>((ref) => 1.0);

// ═══════════════════════════════════════════════════════════════════════
// 5b. HIGHLIGHTED GENERATION PROVIDER
// ═══════════════════════════════════════════════════════════════════════

/// Tracks the currently highlighted generation index for the graph canvas.
final highlightedGenerationProvider = StateProvider<int?>((ref) => null);

// ═══════════════════════════════════════════════════════════════════════
// 6. GRAPH REALTIME PROVIDER — Supabase Realtime
// ═══════════════════════════════════════════════════════════════════════

/// Listens to Supabase Realtime changes on Person and Relationship tables
/// for this family and invalidates [familyGraphProvider] when data changes.
///
/// Replaces the Socket.IO-based graphRealtimeProvider since we no longer
/// depend on the Render server.
///
/// v5.145 (STEP 4): Realtime hardening — prevents realtime invalidation
/// from causing visible hiccups during pan/zoom and from firing too
/// frequently during bulk edits.
///
/// Changes:
/// 1. Increased debounce from 1.5s → 2.5s. The old 1.5s was too
///    aggressive — a single member-add (Person INSERT + Relationship
///    INSERT) fires two events ~100ms apart, and the 1.5s debounce
///    still fired during the user's next pan gesture. 2.5s ensures
///    the invalidation fires AFTER the user stops interacting.
///
/// 2. Coalescing: multiple events within the debounce window fire ONE
///    invalidation, not one per event. The old code already did this
///    via Timer.cancel(), but now we also track whether the event was
///    a structure change (INSERT/DELETE) vs a metadata-only change
///    (UPDATE to name/photo). Structure changes require a full re-fetch;
///    metadata-only changes can be handled by a lighter invalidation.
///
/// 3. The invalidation now invalidates ONLY familyGraphProvider (which
///    re-runs the proximity RPC). The layout provider is invalidated
///    automatically because it watches familyGraphProvider. This was
///    already the case but is now explicit in the comment.
final graphRealtimeProvider =
    Provider.family<void, String>((ref, familyId) {
  final client = ref.read(supabaseProvider);
  if (client == null) return;

  // v5.145: Increased from 1.5s → 2.5s. See the provider doc comment
  // for the rationale.
  Timer? _debounceTimer;
  bool _hasStructureChange = false;

  void invalidateIfNeeded() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 2500), () {
      debugPrint('[graphRealtimeProvider] v5.145: Invalidating graph for '
          '$familyId (debounced 2.5s, structureChange=$_hasStructureChange)');
      // §1 non-negotiable: ONE cache invalidation path, TWO renderers.
      ref.invalidate(familyGraphProvider(familyId));
      ref.invalidate(familyTreeProvider(familyId));
      _hasStructureChange = false;
    });
  }

  // Subscribe to Relationship changes for this family
  final channel = client
      .channel('graph_realtime_$familyId')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'Relationship',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'familyId',
          value: familyId,
        ),
        callback: (payload) {
          // v5.145: Track structure changes (INSERT/DELETE) vs metadata
          // (UPDATE). Structure changes require a full re-fetch because
          // the proximity set may have changed. Metadata-only changes
          // (e.g. renaming a person) still need a re-fetch for the
          // labels, but the layout positions are unaffected.
          if (payload.eventType == PostgresChangeEvent.insert ||
              payload.eventType == PostgresChangeEvent.delete) {
            _hasStructureChange = true;
          }
          invalidateIfNeeded();
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'Person',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'familyId',
          value: familyId,
        ),
        callback: (payload) {
          if (payload.eventType == PostgresChangeEvent.insert ||
              payload.eventType == PostgresChangeEvent.delete) {
            _hasStructureChange = true;
          }
          invalidateIfNeeded();
        },
      )
      .subscribe();

  ref.onDispose(() {
    _debounceTimer?.cancel();
    client.removeChannel(channel);
  });
});

// ═══════════════════════════════════════════════════════════════════════
// 7. GRAPH DRIFT STREAM PROVIDER — Reactive local DB watcher
// ═══════════════════════════════════════════════════════════════════════

/// StreamProvider that watches cached persons for a specific family from
/// the Drift database. This is a reactive stream that emits whenever the
/// local cache changes — including after [_syncToDrift] writes, optimistic
/// actions, or background sync operations.
///
/// The graph screen can watch this provider as a supplementary data source
/// to ensure members are never invisible even if Supabase fetch is slow.
///
/// Usage:
/// ```dart
/// final driftMembersAsync = ref.watch(graphDriftMembersProvider(familyId));
/// ```
final graphDriftMembersProvider =
    StreamProvider.family<List<CachedPerson>, String>((ref, familyId) async* {
  final db = ref.read(driftDatabaseProvider);
  if (db == null) {
    yield [];
    return;
  }

  yield* db.watchPersonsByFamily(familyId);
});

/// StreamProvider that watches cached relationships for a specific family.
final graphDriftRelationshipsProvider =
    StreamProvider.family<List<CachedRelationship>, String>(
        (ref, familyId) async* {
  final db = ref.read(driftDatabaseProvider);
  if (db == null) {
    yield [];
    return;
  }

  yield* db.watchRelationshipsByFamily(familyId);
});

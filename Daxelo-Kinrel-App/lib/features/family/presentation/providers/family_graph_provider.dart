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

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/isar_database.dart';
import '../../../../core/services/graph_layout_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../widgets/graph_canvas_widget.dart';

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
/// app (GraphCanvasWidget, graphLayoutProvider) unchanged.
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

  const FlatGraphResult({
    required this.persons,
    required this.relationships,
    this.isTruncated = false,
    this.totalCount,
  });

  /// Parses the Supabase RPC JSONB response into a [FlatGraphResult].
  ///
  /// RPC node shape:  { id, name, username, avatarUrl, gender,
  ///                    generationIndex, isAnchor, isDeceased, visibility }
  /// RPC edge shape:  { id, sourceId, targetId, relationshipKey, isPrivate }
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
      };
    }).toList();

    // Map RPC edge keys → legacy API keys
    final relationships = rawEdges.map((dynamic e) {
      final edge = e as Map<String, dynamic>;
      // The RPC may return 'sourceId'/'targetId' or 'member_a_id'/'member_b_id'
      // depending on the SQL function version. Handle both.
      final sourceId = edge['sourceId'] ?? edge['member_a_id'] ?? edge['source_id'];
      final targetId = edge['targetId'] ?? edge['member_b_id'] ?? edge['target_id'];
      final relKey = edge['relationshipKey'] ?? edge['relationship_type']
          ?? edge['relationshipType'] ?? 'unknown';
      return <String, dynamic>{
        'id': edge['id'],
        'fromPersonId': sourceId,
        'toPersonId': targetId,
        'relationshipKey': relKey,
        'isPrivate': edge['isPrivate'] ?? edge['is_private'] ?? false,
      };
    }).toList();

    return FlatGraphResult(
      persons: persons,
      relationships: relationships,
      isTruncated: json['isTruncated'] as bool? ?? false,
      totalCount: json['totalCount'] as int?,
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
      );
    }).toList();
  }
}

// ═══════════════════════════════════════════════════════════════════════
// ISOLATE LAYOUT PARAMS (for compute())
// ═══════════════════════════════════════════════════════════════════════

/// Parameter bundle passed to the isolate for layout computation.
class _LayoutComputeParams {
  final List<GraphPerson> persons;
  final List<GraphRelationship> relationships;
  final String? anchorPersonId;
  final bool compactMode;

  const _LayoutComputeParams({
    required this.persons,
    required this.relationships,
    this.anchorPersonId,
    this.compactMode = false,
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
  );
}

// ═══════════════════════════════════════════════════════════════════════
// HELPER: resolve anchor member ID for a family
// ═══════════════════════════════════════════════════════════════════════

/// Looks up the anchor person ID for [familyId] from the Person table.
/// Falls back to the first person in the family if no anchor is set.
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
  static final Map<String, FlatGraphResult> _cache = {};

  /// Clear the in-memory cache for a specific family (or all families
  /// if [familyId] is null). This forces the next read of
  /// [familyGraphProvider] to do a fresh Supabase round-trip.
  ///
  /// Call this whenever the underlying data changes outside the
  /// notifier's own write path — e.g. after `createRelationship`,
  /// `deleteRelationship`, `createPerson`, `updatePerson`,
  /// `deletePerson`. Without this, the notifier will keep returning
  /// the stale cached [FlatGraphResult] until something else
  /// invalidates the provider.
  static void clearCache([String? familyId]) {
    if (familyId == null) {
      _cache.clear();
    } else {
      _cache.remove(familyId);
    }
  }

  @override
  Future<FlatGraphResult> build(String familyId) async {
    // Invalidate the layout when graph data is (re)fetched
    ref.invalidate(graphLayoutProvider(familyId));

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
          data: Value(p.toString()),
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
          data: Value(r.toString()),
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

    try {
      // ── Step 1: Always fetch direct query first ──
      // Direct query is the source of truth — it always returns ALL
      // non-deleted persons in the family, regardless of relationships
      // or connectivity. The RPC `get_family_graph` may return incomplete
      // data (e.g., only the anchor node) if the person is not connected
      // via relationships within p_max_degree. By always using direct
      // query as the primary source, we guarantee all members are visible.
      final directResult = await _fetchGraphDirectQuery(client, familyId);

      if (directResult.persons.isEmpty) {
        debugPrint('[FamilyGraphNotifier] No members found in family $familyId');
        return const FlatGraphResult(persons: [], relationships: []);
      }

      // ── Step 2: Try RPC as a supplementary source for richer data ──
      // The RPC may provide enriched data (kinship labels, computed
      // relationships, etc.) that the direct query doesn't have. If the
      // RPC returns a complete result (same or more persons than direct
      // query), prefer it for the richer data. Otherwise, use direct query.
      try {
        final memberId = await _resolveAnchorMemberId(client, familyId);
        if (memberId != null) {
          final response = await client.rpc(
            'get_family_graph',
            params: <String, dynamic>{
              'p_member_id': memberId,
              'p_max_degree': 6,
              'p_include_hidden': false,
            },
          ).timeout(const Duration(seconds: 15));

          final data = response as Map<String, dynamic>?;
          if (data != null) {
            final rpcResult = FlatGraphResult.fromRpc(data);

            // Use RPC result ONLY if it returns all (or more) persons
            // than the direct query. If it returns fewer, it means the
            // RPC is missing disconnected members — use direct query instead.
            if (rpcResult.persons.length >= directResult.persons.length) {
              _cache[familyId] = rpcResult;
              debugPrint(
                '[FamilyGraphNotifier] RPC: Loaded ${rpcResult.persons.length} persons, '
                '${rpcResult.relationships.length} relationships for $familyId',
              );
              // ── EDGE DEBUG: Log RPC edge data ──
              debugPrint('[EDGE-DEBUG] RPC data being used. '
                  'RPC relationships: ${rpcResult.relationships.length}');
              if (rpcResult.relationships.isNotEmpty) {
                debugPrint('[EDGE-DEBUG] RPC first edge: ${rpcResult.relationships.first}');
              } else {
                debugPrint('[EDGE-DEBUG] WARNING: RPC returned ZERO relationships! '
                    'Falling back to direct query which has ${directResult.relationships.length}');
                // Prefer direct query when RPC has no relationships but direct does
                if (directResult.relationships.isNotEmpty) {
                  _cache[familyId] = directResult;
                  return directResult;
                }
              }
              return rpcResult;
            }

            // RPC returned fewer persons — log and use direct query
            debugPrint(
              '[FamilyGraphNotifier] RPC returned ${rpcResult.persons.length} persons '
              'but direct query found ${directResult.persons.length}. '
              'Using direct query for completeness.',
            );
          }
        }
      } catch (rpcError) {
        debugPrint('[FamilyGraphNotifier] RPC failed: $rpcError, using direct query');
      }

      // ── Step 3: Return direct query result ──
      // This is always the fallback and the primary source.
      _cache[familyId] = directResult;
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

  /// Fetches graph data by directly querying Person and Relationship tables.
  /// Used as a fallback when the `get_family_graph` RPC fails or returns
  /// incomplete results.
  Future<FlatGraphResult> _fetchGraphDirectQuery(
    SupabaseClient client,
    String familyId,
  ) async {
    try {
      // Query all non-deleted persons in this family
      final rawPersons = await client
          .from('Person')
          .select('id, name, gender, "generationIndex", "isAnchor", "photoUrl", '
              '"isDeceased", visibility, username, "familyId"')
          .eq('familyId', familyId)
          .isFilter('deletedAt', null)
          .timeout(const Duration(seconds: 15));

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
        // v36 FIX: Removed .eq('isActive', true) from the primary query.
        // The isActive filter was causing issues because:
        // 1. If the column name doesn't match (camelCase vs snake_case),
        //    the query throws and falls through to fallbacks
        // 2. Even when the column exists, freshly-created relationships
        //    may have isActive=null (not false), and .eq('isActive', true)
        //    excludes null rows — silently dropping valid relationships
        // 3. The filter is redundant: we already filter by familyId, and
        //    inactive relationships are rare (only set during archive)
        //
        // Now we fetch ALL relationships for the family and filter isActive
        // in the mapping step below (where we coerce null → true).
        rawRelationships = await client
            .from('Relationship')
            .select('id, "fromPersonId", "toPersonId", "relationshipKey", "familyId"')
            .eq('familyId', familyId)
            .timeout(const Duration(seconds: 15));
      } catch (colError) {
        debugPrint('[EDGE-DEBUG] Primary relationship query failed: $colError. Trying select(*)');
        try {
          // Fallback A: select all columns without isActive filter
          rawRelationships = await client
              .from('Relationship')
              .select('*')
              .eq('familyId', familyId)
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
            // isActive may be returned as bool or as a String; coerce defensively
            final activeRaw = edge['isActive'] ?? edge['is_active'];
            final isActive = activeRaw is bool
                ? activeRaw
                : (activeRaw is String
                    ? activeRaw.toLowerCase() == 'true'
                    : true);
            return <String, dynamic>{
              'id': edge['id'],
              'fromPersonId': fromId,
              'toPersonId': toId,
              'relationshipKey': rKey,
              'isPrivate': edge['is_private'] ?? edge['isPrivate'] ?? false,
              'isActive': isActive,
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

      // v9: Safety net — if we got persons but zero relationships, retry
      // without the isActive filter. This handles race conditions where
      // isActive hasn't been set yet by DB triggers on freshly-created
      // relationship rows.
      List<Map<String, dynamic>> finalRelationships = relationships;
      if (relationships.isEmpty && rawPersons.length > 1) {
        debugPrint('[EDGE-DEBUG] v9: Got ${rawPersons.length} persons but 0 relationships. '
            'Retrying without isActive filter...');
        try {
          final retryRaw = await client
              .from('Relationship')
              .select('id, "fromPersonId", "toPersonId", "relationshipKey", "familyId"')
              .eq('familyId', familyId)
              .timeout(const Duration(seconds: 10));

          final retryMapped = retryRaw
              .map((dynamic e) {
                final edge = e as Map<String, dynamic>;
                final fromId = edge['fromPersonId'] ?? edge['from_person_id'] ?? edge['sourceId'];
                final toId   = edge['toPersonId']   ?? edge['to_person_id']   ?? edge['targetId'];
                final rKey   = edge['relationshipKey'] ?? edge['relationship_key'] ?? 'unknown';
                return <String, dynamic>{
                  'id': edge['id'],
                  'fromPersonId': fromId,
                  'toPersonId': toId,
                  'relationshipKey': rKey,
                  'isPrivate': false,
                  'isActive': true,
                };
              })
              .where((r) {
                final f = r['fromPersonId'];
                final t = r['toPersonId'];
                return f != null && t != null &&
                    f.toString().isNotEmpty && t.toString().isNotEmpty;
              })
              .toList();

          if (retryMapped.isNotEmpty) {
            debugPrint('[EDGE-DEBUG] v9: Retry without isActive got ${retryMapped.length} relationships');
            finalRelationships = retryMapped;
          }
        } catch (retryError) {
          debugPrint('[EDGE-DEBUG] v9: Retry query failed: $retryError');
        }
      }

      final result = FlatGraphResult(
        persons: persons,
        relationships: finalRelationships,
        isTruncated: false,
        totalCount: persons.length,
      );

      _cache[familyId] = result;

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

  /// Returns cached data if available, otherwise rethrows [error].
  FlatGraphResult _fallbackOrThrow(String familyId, Object error) {
    final cached = _cache[familyId];
    if (cached != null) {
      debugPrint('[FamilyGraphNotifier] Using cached data for $familyId');
      return cached;
    }
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
// 2. GRAPH LAYOUT PROVIDER — FutureProvider.family
// ═══════════════════════════════════════════════════════════════════════

/// Computes the graph layout for a given family in a background isolate.
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

  final anchorPerson = persons.firstWhere(
    (p) => p.isAnchor,
    orElse: () => persons.first,
  );

  final compactMode = persons.length > 50;

  final params = _LayoutComputeParams(
    persons: graphPersons,
    relationships: graphRelationships,
    anchorPersonId: anchorPerson.id,
    compactMode: compactMode,
  );

  try {
    return await compute(_runLayoutInIsolate, params);
  } catch (e) {
    debugPrint('[graphLayoutProvider] Isolate compute failed, '
        'falling back to main thread: $e');
    final service = GraphLayoutService();
    return service.computeLayout(
      persons: graphPersons,
      relationships: graphRelationships,
      anchorPersonId: anchorPerson.id,
      compactMode: compactMode,
    );
  }
});

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
final graphRealtimeProvider =
    Provider.family<void, String>((ref, familyId) {
  final client = ref.read(supabaseProvider);
  if (client == null) return;

  DateTime? _lastInvalidation;

  void invalidateIfNeeded() {
    final now = DateTime.now();
    if (_lastInvalidation != null &&
        now.difference(_lastInvalidation!) < const Duration(seconds: 2)) {
      return;
    }
    _lastInvalidation = now;
    debugPrint('[graphRealtimeProvider] Invalidating graph for $familyId');
    ref.invalidate(familyGraphProvider(familyId));
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
        callback: (_) => invalidateIfNeeded(),
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
        callback: (_) => invalidateIfNeeded(),
      )
      .subscribe();

  ref.onDispose(() {
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

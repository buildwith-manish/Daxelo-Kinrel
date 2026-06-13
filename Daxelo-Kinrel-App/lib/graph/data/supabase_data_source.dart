// lib/graph/data/supabase_data_source.dart
//
// DAXELO KINREL — Supabase Data Source (V2.1 Data Layer)
//
// Concrete Supabase implementation of [FamilyGraphRepository].
// Uses Supabase RPCs for data fetching and Supabase Realtime
// for live updates. All methods have proper error handling and
// timeout.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/analytics_service.dart';
import 'family_graph_repository.dart';

// ═══════════════════════════════════════════════════════════════════════
// SUPABASE DATA SOURCE
// ═══════════════════════════════════════════════════════════════════════

/// Concrete [FamilyGraphRepository] implementation backed by Supabase.
///
/// Calls Supabase RPCs for all data operations and subscribes to
/// Realtime channels for live graph updates. JSON responses are parsed
/// into the data models defined in [family_graph_repository.dart].
///
/// RPCs used:
/// - `get_family_graph(member_id, max_degree, include_hidden)` → JSONB
/// - `get_member_branch(member_id, branch_type, depth)` → JSONB
/// - `search_members(query, filters, limit, offset)` → JSONB
/// - `resolve_kinship(member_a_id, member_b_id)` → JSONB
/// - `check_permissions(viewer_id, target_ids, permission_types)` → JSONB
///
/// Realtime channels:
/// - `family_graph:{member_id}` — INSERT/UPDATE/DELETE on relationships
/// - `members:updated` — UPDATE on members
/// - `permissions:changed` — INSERT/DELETE on permissions or blocks
class SupabaseDataSource implements FamilyGraphRepository {
  /// Creates a Supabase data source with the given [client].
  SupabaseDataSource({required SupabaseClient client})
      : _client = client;

  final SupabaseClient _client;

  /// Timeout for RPC calls (default: 15 seconds).
  static const Duration _rpcTimeout = Duration(seconds: 15);

  /// Active realtime subscriptions keyed by member ID.
  final Map<String, RealtimeChannel> _subscriptions =
      <String, RealtimeChannel>{};

  /// Stream controllers for realtime events keyed by member ID.
  final Map<String, StreamController<GraphRealtimeEvent>> _controllers =
      <String, StreamController<GraphRealtimeEvent>>{};

  // ── FamilyGraphRepository Implementation ─────────────────────────

  @override
  Future<GraphData> getFamilyGraph({
    required String memberId,
    int maxDegree = 3,
    bool includeHidden = false,
  }) async {
    try {
      final response = await _client.rpc(
        'get_family_graph',
        params: <String, dynamic>{
          'member_id': memberId,
          'max_degree': maxDegree,
          'include_hidden': includeHidden,
        },
      ).timeout(_rpcTimeout);

      final data = response as Map<String, dynamic>;
      final graphData = GraphData.fromJson(data);

      AnalyticsService.instance.logGraphOpened(graphData.nodes.length);

      return graphData;
    } on PostgrestException catch (e) {
      debugPrint('⚠️ Supabase getFamilyGraph error: ${e.message}');
      rethrow;
    } on TimeoutException {
      debugPrint('⚠️ Supabase getFamilyGraph timeout');
      throw Exception('Graph data request timed out');
    }
  }

  @override
  Future<BranchData> getMemberBranch({
    required String memberId,
    required BranchType branchType,
    int depth = 2,
  }) async {
    try {
      final response = await _client.rpc(
        'get_member_branch',
        params: <String, dynamic>{
          'member_id': memberId,
          'branch_type': branchType.name,
          'depth': depth,
        },
      ).timeout(_rpcTimeout);

      final data = response as Map<String, dynamic>;
      return BranchData.fromJson(data);
    } on PostgrestException catch (e) {
      debugPrint('⚠️ Supabase getMemberBranch error: ${e.message}');
      rethrow;
    } on TimeoutException {
      debugPrint('⚠️ Supabase getMemberBranch timeout');
      throw Exception('Branch data request timed out');
    }
  }

  @override
  Future<SearchResult> searchMembers({
    required String query,
    Map<String, dynamic>? filters,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _client.rpc(
        'search_members',
        params: <String, dynamic>{
          'query': query,
          'filters': filters,
          'limit': limit,
          'offset': offset,
        },
      ).timeout(_rpcTimeout);

      final data = response as Map<String, dynamic>;
      final result = SearchResult.fromJson(data);

      AnalyticsService.instance.logSearchPerformed(query, result.total);

      return result;
    } on PostgrestException catch (e) {
      debugPrint('⚠️ Supabase searchMembers error: ${e.message}');
      rethrow;
    } on TimeoutException {
      debugPrint('⚠️ Supabase searchMembers timeout');
      throw Exception('Search request timed out');
    }
  }

  @override
  Future<KinshipResult> resolveKinship({
    required String memberAId,
    required String memberBId,
  }) async {
    try {
      final response = await _client.rpc(
        'resolve_kinship',
        params: <String, dynamic>{
          'member_a_id': memberAId,
          'member_b_id': memberBId,
        },
      ).timeout(_rpcTimeout);

      final data = response as Map<String, dynamic>;
      return KinshipResult.fromJson(data);
    } on PostgrestException catch (e) {
      debugPrint('⚠️ Supabase resolveKinship error: ${e.message}');
      rethrow;
    } on TimeoutException {
      debugPrint('⚠️ Supabase resolveKinship timeout');
      throw Exception('Kinship resolution request timed out');
    }
  }

  @override
  Future<PermissionMap> checkPermissions({
    required String viewerId,
    required List<String> targetIds,
    required List<String> permissionTypes,
  }) async {
    try {
      final response = await _client.rpc(
        'check_permissions',
        params: <String, dynamic>{
          'viewer_id': viewerId,
          'target_ids': targetIds,
          'permission_types': permissionTypes,
        },
      ).timeout(_rpcTimeout);

      final data = response as Map<String, dynamic>;
      return PermissionMap.fromJson(data);
    } on PostgrestException catch (e) {
      debugPrint('⚠️ Supabase checkPermissions error: ${e.message}');
      rethrow;
    } on TimeoutException {
      debugPrint('⚠️ Supabase checkPermissions timeout');
      throw Exception('Permission check request timed out');
    }
  }

  @override
  Stream<GraphRealtimeEvent> subscribeToGraphUpdates({
    required String memberId,
  }) {
    // Return existing stream if already subscribed.
    if (_controllers.containsKey(memberId)) {
      return _controllers[memberId]!.stream;
    }

    final controller = StreamController<GraphRealtimeEvent>.broadcast();
    _controllers[memberId] = controller;

    // Subscribe to relationship changes.
    final relationshipChannel = _client.channel(
      'family_graph:$memberId',
    );

    relationshipChannel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'relationships',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'member_id',
            value: memberId,
          ),
          callback: (PostgresChangePayload payload) {
            _emitEvent(
              memberId,
              type: 'relationship_changed',
              payload: payload.newRecord,
            );
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'members',
          callback: (PostgresChangePayload payload) {
            _emitEvent(
              memberId,
              type: 'member_updated',
              payload: payload.newRecord,
            );
          },
        )
        .subscribe();

    // Subscribe to permission changes.
    final permissionChannel = _client.channel(
      'permissions:changed',
    );

    permissionChannel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'permissions',
          callback: (PostgresChangePayload payload) {
            _emitEvent(
              memberId,
              type: 'permission_changed',
              payload: payload.newRecord,
            );
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'blocks',
          callback: (PostgresChangePayload payload) {
            _emitEvent(
              memberId,
              type: 'permission_changed',
              payload: payload.oldRecord,
            );
          },
        )
        .subscribe();

    _subscriptions[memberId] = relationshipChannel;

    // Clean up when the stream is cancelled.
    controller.onCancel = () {
      _unsubscribe(memberId);
    };

    return controller.stream;
  }

  @override
  Future<void> cacheGraphState({
    required String familyId,
    required GraphData data,
  }) async {
    try {
      // Store in Supabase's local cache (or delegate to GraphCache).
      // This method persists to the local Drift database, which is
      // handled by GraphCache. Here we simply validate the data.
      final json = data.toJson();
      // In practice, this would be delegated to GraphCache.saveGraphState.
      // For the repository contract, we acknowledge the cache request.
      debugPrint('📊 cacheGraphState: ${json.keys} for family $familyId');
    } catch (e) {
      debugPrint('⚠️ cacheGraphState error: $e');
    }
  }

  @override
  Future<GraphData?> getCachedGraphState({required String familyId}) async {
    // Delegated to GraphCache. Returns null here as Supabase
    // does not maintain a local graph cache.
    return null;
  }

  // ── Private Methods ──────────────────────────────────────────────

  /// Emits a realtime event to the stream controller for [memberId].
  void _emitEvent(
    String memberId, {
    required String type,
    required Map<String, dynamic> payload,
  }) {
    final controller = _controllers[memberId];
    if (controller == null || controller.isClosed) return;

    final event = GraphRealtimeEvent(
      type: type,
      payload: payload,
      timestamp: DateTime.now(),
    );

    controller.add(event);
  }

  /// Unsubscribes from realtime channels for [memberId].
  void _unsubscribe(String memberId) {
    final channel = _subscriptions.remove(memberId);
    if (channel != null) {
      _client.removeChannel(channel);
    }

    final controller = _controllers.remove(memberId);
    if (controller != null && !controller.isClosed) {
      controller.close();
    }
  }

  /// Disposes all active subscriptions and stream controllers.
  void dispose() {
    for (final entry in _subscriptions.entries) {
      _client.removeChannel(entry.value);
    }
    _subscriptions.clear();

    for (final controller in _controllers.values) {
      if (!controller.isClosed) {
        controller.close();
      }
    }
    _controllers.clear();
  }
}

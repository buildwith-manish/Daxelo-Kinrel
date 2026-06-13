// lib/graph/security/permission_validator.dart
//
// DAXELO KINREL — Permission Validator
//
// Cached permission checks for graph visibility and access control.
//
// Security model:
//   - Dual-layer: Supabase RLS (server-authoritative) + client-side filtering
//   - Hidden members: shown as ANONYMOUS nodes (gray, no avatar, no name)
//     to maintain structural integrity of the graph
//   - Blocked members: COMPLETELY EXCLUDED from graph; their relationships
//     are NOT rendered
//   - Indirect connection: if a blocked member is the only connection between
//     two visible members → dashed "indirect connection" line
//   - Inference prevention: count of blocked members is NEVER revealed
//   - Private relationships: invisible to non-participants; if the user IS
//     a participant → show with lock icon
//   - Realtime permission updates: via Supabase Realtime, fade in/out over 300ms
//   - Offline cache encryption: local cache encrypted, no plaintext PII in SQLite
//
// Permission checks (all cached 30 min):
//   Can view member profile: user is family member OR member has public profile
//   Can view relationship: both members are visible to user
//   Can expand branch: user has view permission on at least one member in branch
//   Can edit relationship: user is one of two relationship members OR is family admin

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/family_graph_repository.dart' show GraphNodeData, GraphEdgeData, GraphRealtimeEvent;

// ═══════════════════════════════════════════════════════════════════════
// DATA MODELS
// ═══════════════════════════════════════════════════════════════════════

/// Result of filtering graph nodes by permission.
///
/// - [visible]: nodes the viewer can see normally
/// - [anonymous]: nodes the viewer cannot identify (shown as gray placeholders)
/// - [blockedIds]: IDs of completely excluded members (never revealed to UI;
///   used internally for indirect connection detection)
class VisibilityResult {
  /// Nodes visible to the viewer with full details.
  final List<GraphNodeData> visible;

  /// Nodes shown as anonymous placeholders (gray, no avatar, no name)
  /// to maintain structural integrity.
  final List<GraphNodeData> anonymous;

  /// IDs of completely blocked/excluded members. Used internally only;
  /// count is NEVER exposed to prevent inference attacks.
  final Set<String> blockedIds;

  const VisibilityResult({
    required this.visible,
    required this.anonymous,
    required this.blockedIds,
  });
}

// GraphRealtimeEvent imported from family_graph_repository.dart

// ═══════════════════════════════════════════════════════════════════════
// CACHE ENTRY
// ═══════════════════════════════════════════════════════════════════════

/// A single cached permission check result with timestamp.
class _CacheEntry {
  final bool allowed;
  final DateTime cachedAt;

  const _CacheEntry({required this.allowed, required this.cachedAt});

  /// Whether this cache entry is still valid (within 30-minute TTL).
  bool get isValid {
    final elapsed = DateTime.now().difference(cachedAt);
    return elapsed.inMinutes < 30;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// PERMISSION VALIDATOR
// ═══════════════════════════════════════════════════════════════════════

/// Validates graph visibility and access control with cached permission checks.
///
/// Security principles:
///   1. Server-authoritative: Supabase RLS is the ground truth
///   2. Client caching: 30-minute TTL to reduce RPC calls
///   3. Inference prevention: blocked member counts never revealed
///   4. Structural integrity: hidden members shown as anonymous nodes
///   5. Realtime updates: permissions can change live via Supabase Realtime
class PermissionValidator {
  PermissionValidator(this._supabase);

  final SupabaseClient _supabase;

  /// Permission cache: Map<viewerId, Map<cacheKey, CacheEntry>>
  final Map<String, Map<String, _CacheEntry>> _cache = {};

  /// Stream controller for realtime permission change notifications.
  final StreamController<GraphRealtimeEvent> _realtimeController =
      StreamController<GraphRealtimeEvent>.broadcast();

  /// Stream of realtime permission change events.
  Stream<GraphRealtimeEvent> get permissionChangedStream =>
      _realtimeController.stream;

  /// Active Supabase Realtime subscription, if any.
  RealtimeChannel? _realtimeChannel;

  // ── Cache TTL ──────────────────────────────────────────────────────

  /// Cache time-to-live in minutes.
  static const int _cacheTtlMinutes = 30;

  // ── Permission Checks ──────────────────────────────────────────────

  /// Whether [viewerId] can view [targetId]'s profile.
  ///
  /// Allowed when:
  ///   - viewer is a family member of target, OR
  ///   - target has a public profile
  Future<bool> canViewMember(String viewerId, String targetId) async {
    final cacheKey = 'view_member:$targetId';
    final cached = _getCached(viewerId, cacheKey);
    if (cached != null) return cached;

    try {
      final result = await _supabase.rpc(
        'check_permissions',
        params: {
          'viewer_id': viewerId,
          'target_id': targetId,
          'action': 'view_member',
        },
      );

      final allowed = (result as bool?) ?? false;
      _setCache(viewerId, cacheKey, allowed);
      return allowed;
    } catch (e) {
      debugPrint('[PermissionValidator] canViewMember RPC failed: $e');
      // Fail-closed: deny access on error
      return false;
    }
  }

  /// Whether [viewerId] can view the relationship between [sourceId] and [targetId].
  ///
  /// Allowed when:
  ///   - both members are visible to the viewer
  Future<bool> canViewRelationship(
    String viewerId,
    String sourceId,
    String targetId,
  ) async {
    final cacheKey = 'view_rel:$sourceId:$targetId';
    final cached = _getCached(viewerId, cacheKey);
    if (cached != null) return cached;

    try {
      final result = await _supabase.rpc(
        'check_permissions',
        params: {
          'viewer_id': viewerId,
          'source_id': sourceId,
          'target_id': targetId,
          'action': 'view_relationship',
        },
      );

      final allowed = (result as bool?) ?? false;
      _setCache(viewerId, cacheKey, allowed);
      return allowed;
    } catch (e) {
      debugPrint('[PermissionValidator] canViewRelationship RPC failed: $e');
      return false;
    }
  }

  /// Whether [viewerId] can expand the branch containing [branchMemberId].
  ///
  /// Allowed when:
  ///   - viewer has view permission on at least one member in the branch
  Future<bool> canExpandBranch(
    String viewerId,
    String branchMemberId,
  ) async {
    final cacheKey = 'expand_branch:$branchMemberId';
    final cached = _getCached(viewerId, cacheKey);
    if (cached != null) return cached;

    try {
      final result = await _supabase.rpc(
        'check_permissions',
        params: {
          'viewer_id': viewerId,
          'target_id': branchMemberId,
          'action': 'expand_branch',
        },
      );

      final allowed = (result as bool?) ?? false;
      _setCache(viewerId, cacheKey, allowed);
      return allowed;
    } catch (e) {
      debugPrint('[PermissionValidator] canExpandBranch RPC failed: $e');
      return false;
    }
  }

  /// Whether [viewerId] can edit the relationship between [sourceId] and [targetId].
  ///
  /// Allowed when:
  ///   - viewer is one of the two relationship members, OR
  ///   - viewer is a family admin
  Future<bool> canEditRelationship(
    String viewerId,
    String sourceId,
    String targetId,
  ) async {
    final cacheKey = 'edit_rel:$sourceId:$targetId';
    final cached = _getCached(viewerId, cacheKey);
    if (cached != null) return cached;

    try {
      final result = await _supabase.rpc(
        'check_permissions',
        params: {
          'viewer_id': viewerId,
          'source_id': sourceId,
          'target_id': targetId,
          'action': 'edit_relationship',
        },
      );

      final allowed = (result as bool?) ?? false;
      _setCache(viewerId, cacheKey, allowed);
      return allowed;
    } catch (e) {
      debugPrint('[PermissionValidator] canEditRelationship RPC failed: $e');
      return false;
    }
  }

  // ── Bulk Filtering ─────────────────────────────────────────────────

  /// Filters [nodes] by visibility, returning a [VisibilityResult].
  ///
  /// - Visible nodes: viewer can see full details
  /// - Anonymous nodes: viewer can see structural position but no PII
  ///   (gray circle, no avatar, no name, placeholder ID)
  /// - Blocked nodes: completely excluded (IDs returned internally only)
  ///
  /// Inference prevention: the count of blocked IDs is never exposed
  /// to the UI layer. The [blockedIds] set is only used internally
  /// for indirect connection detection in [filterGraphEdges].
  Future<VisibilityResult> filterGraphNodes(
    String viewerId,
    List<GraphNodeData> nodes,
  ) async {
    final visible = <GraphNodeData>[];
    final anonymous = <GraphNodeData>[];
    final blockedIds = <String>{};

    for (final node in nodes) {
      final canView = await canViewMember(viewerId, node.id);

      if (canView) {
        visible.add(node);
      } else {
        // Determine if this is a "hidden" (show anonymous) or "blocked"
        // (completely exclude) member via server check.
        try {
          final visibility = await _supabase.rpc(
            'check_permissions',
            params: {
              'viewer_id': viewerId,
              'target_id': node.id,
              'action': 'check_visibility',
            },
          );

          final visibilityStr = visibility as String? ?? 'hidden';

          if (visibilityStr == 'blocked') {
            // Completely excluded — do not render, do not reveal count
            blockedIds.add(node.id);
          } else {
            // Hidden — show as anonymous node to maintain structural integrity
            anonymous.add(GraphNodeData(
              id: node.id,
              name: '',
              avatarUrl: null,
              generationIndex: node.generationIndex,
              isAnchor: false,
              isDeceased: false,
              gender: null,
            ));
          }
        } catch (e) {
          debugPrint('[PermissionValidator] visibility check failed: $e');
          // Fail-closed: treat as hidden (anonymous) on error
          anonymous.add(GraphNodeData(
            id: node.id,
            name: '',
            avatarUrl: null,
            generationIndex: node.generationIndex,
            isAnchor: false,
            isDeceased: false,
            gender: null,
          ));
        }
      }
    }

    return VisibilityResult(
      visible: visible,
      anonymous: anonymous,
      blockedIds: blockedIds,
    );
  }

  /// Filters [edges] based on visibility of their endpoints.
  ///
  /// - Edges where both endpoints are visible: included normally
  /// - Edges where one or both endpoints are anonymous: included but
  ///   marked for anonymous rendering
  /// - Edges where either endpoint is blocked: EXCLUDED entirely
  /// - Indirect connections: if a blocked member was the only path between
  ///   two visible members, a dashed "indirect connection" line is added
  Future<List<GraphEdgeData>> filterGraphEdges(
    String viewerId,
    List<GraphEdgeData> edges,
    Set<String> visibleNodeIds,
  ) async {
    final filtered = <GraphEdgeData>[];

    for (final edge in edges) {
      final sourceVisible = visibleNodeIds.contains(edge.sourceId);
      final targetVisible = visibleNodeIds.contains(edge.targetId);

      if (sourceVisible && targetVisible) {
        // Both endpoints visible — check relationship visibility
        final canViewRel = await canViewRelationship(
          viewerId,
          edge.sourceId,
          edge.targetId,
        );

        if (canViewRel) {
          filtered.add(edge);
        } else if (edge.isPrivate) {
          // Private relationship: only visible to participants
          final isParticipant = edge.sourceId == viewerId ||
              edge.targetId == viewerId;
          if (isParticipant) {
            // Show with lock indicator (mark in the edge data)
            filtered.add(GraphEdgeData(
              id: edge.id,
              sourceId: edge.sourceId,
              targetId: edge.targetId,
              relationshipKey: edge.relationshipKey,
              isPrivate: true,
            ));
          }
          // Non-participants: completely invisible
        }
      }
      // If either endpoint is blocked or not visible, skip the edge entirely.
      // Indirect connections are detected separately below.
    }

    return filtered;
  }

  /// Detects indirect connections caused by blocked members.
  ///
  /// When a blocked member was the only path between two visible members,
  /// returns a list of [GraphEdgeData] representing indirect connections
  /// that should be rendered as dashed gray lines with "indirect" labels.
  Future<List<GraphEdgeData>> detectIndirectConnections(
    String viewerId,
    List<GraphEdgeData> allEdges,
    Set<String> visibleNodeIds,
    Set<String> blockedIds,
  ) async {
    if (blockedIds.isEmpty) return [];

    final indirectConnections = <GraphEdgeData>[];

    // Build adjacency from all edges, then look for pairs of visible
    // nodes that are only connected through blocked members.
    final adjacency = <String, Set<String>>{};
    for (final edge in allEdges) {
      adjacency.putIfAbsent(edge.sourceId, () => {}).add(edge.targetId);
      adjacency.putIfAbsent(edge.targetId, () => {}).add(edge.sourceId);
    }

    // For each blocked member, find visible neighbors connected through it
    for (final blockedId in blockedIds) {
      final neighbors = adjacency[blockedId] ?? {};
      final visibleNeighbors =
          neighbors.where((id) => visibleNodeIds.contains(id)).toList();

      // If 2+ visible neighbors share this blocked member as
      // their only connection, create indirect edges
      for (int i = 0; i < visibleNeighbors.length; i++) {
        for (int j = i + 1; j < visibleNeighbors.length; j++) {
          final sourceId = visibleNeighbors[i];
          final targetId = visibleNeighbors[j];

          // Check if there is already a direct edge between these two
          final hasDirectEdge = allEdges.any(
            (e) =>
                (e.sourceId == sourceId && e.targetId == targetId) ||
                (e.sourceId == targetId && e.targetId == sourceId),
          );

          if (!hasDirectEdge) {
            indirectConnections.add(GraphEdgeData(
              id: 'indirect:$sourceId:$targetId',
              sourceId: sourceId,
              targetId: targetId,
              relationshipKey: 'indirect_connection',
              isPrivate: false,
            ));
          }
        }
      }
    }

    return indirectConnections;
  }

  // ── Cache Management ───────────────────────────────────────────────

  /// Retrieves a cached permission result, or null if not cached/expired.
  bool? _getCached(String viewerId, String cacheKey) {
    final viewerCache = _cache[viewerId];
    if (viewerCache == null) return null;

    final entry = viewerCache[cacheKey];
    if (entry == null) return null;

    if (!entry.isValid) {
      viewerCache.remove(cacheKey);
      return null;
    }

    return entry.allowed;
  }

  /// Stores a permission result in the cache.
  void _setCache(String viewerId, String cacheKey, bool allowed) {
    _cache.putIfAbsent(viewerId, () => <String, _CacheEntry>{});
    _cache[viewerId]![cacheKey] = _CacheEntry(
      allowed: allowed,
      cachedAt: DateTime.now(),
    );
  }

  /// Invalidates cached permission entries.
  ///
  /// If [targetId] is provided, only invalidates entries related to that
  /// target. Otherwise, clears the entire cache for all viewers.
  void invalidateCache({String? targetId}) {
    if (targetId == null) {
      _cache.clear();
      return;
    }

    // Remove all cache entries that reference the targetId
    for (final viewerCache in _cache.values) {
      viewerCache.removeWhere(
        (key, _) => key.contains(targetId),
      );
    }
  }

  /// Handles a realtime permission change event from Supabase.
  ///
  /// Invalidates relevant cache entries and notifies listeners so
  /// the UI can fade nodes/edges in/out over 300ms.
  void onPermissionChanged(GraphRealtimeEvent event) {
    // Extract targetId from event payload if available
    final targetId = event.payload['target_id'] as String? ??
        event.payload['grantor_id'] as String?;
    invalidateCache(targetId: targetId);

    // Notify listeners (UI will animate fade in/out over 300ms)
    if (!_realtimeController.isClosed) {
      _realtimeController.add(event);
    }
  }

  /// Subscribes to Supabase Realtime channel for permission changes
  /// on a specific family.
  void subscribeToFamilyPermissions(String familyId) {
    _realtimeChannel?.unsubscribe();

    _realtimeChannel = _supabase.channel('permissions:$familyId');

    _realtimeChannel!.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'permissions',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'grantor_id',
        value: familyId,
      ),
      callback: (PostgresChangePayload payload) {
        final newRecord = payload.newRecord;
        final grantorId = newRecord['grantor_id'] as String? ?? '';
        final granteeId = newRecord['grantee_id'] as String? ?? '';

        onPermissionChanged(GraphRealtimeEvent(
          type: payload.eventType.name,
          payload: {
            'grantor_id': grantorId,
            'grantee_id': granteeId,
            'family_id': familyId,
            'target_id': grantorId,
          },
          timestamp: DateTime.now(),
        ));
      },
    ).subscribe();
  }

  /// Unsubscribes from the realtime channel.
  void unsubscribeFromFamilyPermissions() {
    _realtimeChannel?.unsubscribe();
    _realtimeChannel = null;
  }

  /// Disposes resources: closes the stream controller and unsubscribes.
  void dispose() {
    unsubscribeFromFamilyPermissions();
    _cache.clear();
    _realtimeController.close();
  }
}

// ═══════════════════════════════════════════════════════════════════════
// RIVERPOD PROVIDER
// ═══════════════════════════════════════════════════════════════════════

/// Riverpod provider for the [PermissionValidator].
///
/// Depends on the Supabase client provider for RPC calls.
final permissionValidatorProvider = Provider<PermissionValidator>((ref) {
  final supabase = Supabase.instance.client;
  final validator = PermissionValidator(supabase);

  ref.onDispose(() {
    validator.dispose();
  });

  return validator;
});

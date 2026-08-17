// lib/graph/rearrange/layout_overrides_service.dart
//
// DAXELO KINREL — v5.22 Personal Layout Overrides Service
//
// Persistence layer for the per-viewer graph layout customizations:
//   • nodePositions   — personal node position overrides (PART 1)
//   • edgeWaypoints   — personal edge midpoint bow offsets (PART 2)
//
// Both are stored on the SAME GraphLayoutState row keyed by
// (familyId, auth.uid()), which is already personal-only by table
// design and protected by row-level security (only the owner can
// read/write their own row). See migration
// 20260603055302_production_sync_2025_03_04.sql (~line 1525) for
// the table + 20260608182557_fix_rls_tables_with_missing_policies.sql
// for the RLS policies.
//
// This service is the SINGLE write-path for v5.22 — no other code
// in the client writes to GraphLayoutState. The graph engine view
// reads via `personalLayoutOverridesProvider` (see below) and
// applies the overrides on top of the auto-computed layout.

import 'dart:convert';

import 'package:flutter/material.dart' show Offset;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/supabase_service.dart';

// ────────────────────────────────────────────────────────────────────
// Data models
// ────────────────────────────────────────────────────────────────────

/// Personal layout overrides for one (familyId, viewer) pair.
///
/// `nodePositions` is keyed by personId and stores an absolute canvas
/// position. `edgeWaypoints` is keyed by relationshipId and stores a
/// RELATIVE offset from the true bezier t=0.5 midpoint (not absolute
/// canvas coordinates) so the override stays meaningful if endpoints
/// move.
///
/// Both maps default to empty when the viewer has no saved overrides.
class PersonalLayoutOverrides {
  final Map<String, Offset> nodePositions;
  final Map<String, Offset> edgeWaypoints;

  const PersonalLayoutOverrides({
    this.nodePositions = const {},
    this.edgeWaypoints = const {},
  });

  static const empty = PersonalLayoutOverrides();

  bool get isEmpty =>
      nodePositions.isEmpty && edgeWaypoints.isEmpty;

  /// Apply saved node position overrides on top of the auto-layout
  /// positions. Saved overrides take precedence; auto-layout fills
  /// in everything else. This is the function the engine view calls
  /// before rendering to ensure saved nodes appear where the viewer
  /// last dragged them.
  Map<String, Offset> applyTo(Map<String, Offset> autoLayoutPositions) {
    if (nodePositions.isEmpty) return autoLayoutPositions;
    return {...autoLayoutPositions, ...nodePositions};
  }

  @override
  String toString() =>
      'PersonalLayoutOverrides(nodes=${nodePositions.length}, '
      'edges=${edgeWaypoints.length})';
}

// ────────────────────────────────────────────────────────────────────
// Provider
// ────────────────────────────────────────────────────────────────────

/// Loads the current viewer's saved personal layout overrides for the
/// given family. Returns [PersonalLayoutOverrides.empty] when the
/// viewer has no saved row (the normal case — most viewers never
/// customize their graph layout, and that's fine).
///
/// The provider is invalidated:
///   • On family switch (it's family-scoped)
///   • After any write via the LayoutOverridesService (so the
///     engine view re-reads the fresh row)
final personalLayoutOverridesProvider =
    FutureProvider.family<PersonalLayoutOverrides, String>(
        (ref, familyId) async {
  final client = ref.watch(supabaseProvider);
  if (client == null) return PersonalLayoutOverrides.empty;

  final auth = client.auth.currentUser;
  if (auth == null) return PersonalLayoutOverrides.empty;

  try {
    // RLS automatically restricts this SELECT to the viewer's own row.
    // If no row exists, returns empty list → we coalesce to empty overrides.
    final rows = await client
        .from('GraphLayoutState')
        .select('nodePositions, edgeWaypoints')
        .eq('familyId', familyId)
        .eq('userId', auth.id)
        .limit(1);

    final rowsList = rows is List ? rows : const [];
    if (rowsList.isEmpty) {
      return PersonalLayoutOverrides.empty;
    }

    final row = rowsList.first as Map<String, dynamic>;
    return PersonalLayoutOverrides(
      nodePositions: _parseNodePositions(row['nodePositions']),
      edgeWaypoints: _parseEdgeWaypoints(row['edgeWaypoints']),
    );
  } catch (e) {
    // Fail soft — graph still renders from auto-layout.
    return PersonalLayoutOverrides.empty;
  }
});

// ────────────────────────────────────────────────────────────────────
// JSON parsers (defensive — DB column is JSONB, but Postgrest returns
// it as already-parsed JSON. We tolerate both shapes.)
// ────────────────────────────────────────────────────────────────────

Map<String, Offset> _parseNodePositions(dynamic raw) {
  if (raw == null) return const {};
  // Postgrest usually returns a Map; if it's a String, decode it.
  Map<String, dynamic> map;
  if (raw is Map) {
    map = raw.cast<String, dynamic>();
  } else if (raw is String) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        map = decoded.cast<String, dynamic>();
      } else {
        return const {};
      }
    } catch (_) {
      return const {};
    }
  } else {
    return const {};
  }

  final out = <String, Offset>{};
  for (final entry in map.entries) {
    final v = entry.value;
    double? x, y;
    if (v is Map) {
      x = (v['x'] as num?)?.toDouble();
      y = (v['y'] as num?)?.toDouble();
    } else if (v is List && v.length == 2) {
      x = (v[0] as num?)?.toDouble();
      y = (v[1] as num?)?.toDouble();
    }
    if (x != null && y != null) {
      out[entry.key] = Offset(x, y);
    }
  }
  return out;
}

Map<String, Offset> _parseEdgeWaypoints(dynamic raw) {
  if (raw == null) return const {};
  Map<String, dynamic> map;
  if (raw is Map) {
    map = raw.cast<String, dynamic>();
  } else if (raw is String) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        map = decoded.cast<String, dynamic>();
      } else {
        return const {};
      }
    } catch (_) {
      return const {};
    }
  } else {
    return const {};
  }

  final out = <String, Offset>{};
  for (final entry in map.entries) {
    final v = entry.value;
    double? dx, dy;
    if (v is Map) {
      dx = (v['dx'] as num?)?.toDouble();
      dy = (v['dy'] as num?)?.toDouble();
    } else if (v is List && v.length == 2) {
      dx = (v[0] as num?)?.toDouble();
      dy = (v[1] as num?)?.toDouble();
    }
    if (dx != null && dy != null) {
      out[entry.key] = Offset(dx, dy);
    }
  }
  return out;
}

// ────────────────────────────────────────────────────────────────────
// Service — write API (single source of truth for v5.22 mutations)
// ────────────────────────────────────────────────────────────────────

/// Write API for personal layout overrides. All mutations go through
/// an upsert on the (familyId, auth.uid()) unique key already defined
/// on GraphLayoutState. RLS guarantees no other user's row is ever
/// touched (the policy explicitly compares userId = auth.uid()::text).
class LayoutOverridesService {
  LayoutOverridesService._();

  // ── PART 1 — node position overrides ───────────────────────────

  /// Persist (or update) a single node's position override for the
  /// current viewer + family. Read-modify-writes the JSONB map so
  /// other saved overrides for the same family are preserved.
  static Future<void> saveNodeOverride(
    Ref ref,
    String familyId,
    String personId,
    Offset position,
  ) async {
    final client = ref.read(supabaseProvider);
    if (client == null) return;
    final auth = client.auth.currentUser;
    if (auth == null) return;

    // Read current row (RLS guarantees only the viewer's own row is
    // visible). Coalesce to empty if no row yet.
    final existing = await _readRow(client, familyId, auth.id);
    final nodes =
        Map<String, dynamic>.from(existing?['nodePositions'] as Map? ?? const {});
    nodes[personId] = {'x': position.dx, 'y': position.dy};

    await client.from('GraphLayoutState').upsert({
      'familyId': familyId,
      'userId': auth.id,
      'nodePositions': nodes,
      // Preserve the other columns on the row if it existed.
      if (existing != null) ..._preserveOtherColumns(existing),
    }, onConflict: 'familyId, userId');

    ref.invalidate(personalLayoutOverridesProvider(familyId));
  }

  /// Remove a single node's saved override and let it fall back to
  /// auto-layout. Read-modify-writes the JSONB.
  static Future<void> removeNodeOverride(
    Ref ref,
    String familyId,
    String personId,
  ) async {
    final client = ref.read(supabaseProvider);
    if (client == null) return;
    final auth = client.auth.currentUser;
    if (auth == null) return;

    final existing = await _readRow(client, familyId, auth.id);
    if (existing == null) return; // nothing to remove from
    final nodes =
        Map<String, dynamic>.from(existing['nodePositions'] as Map? ?? const {});
    if (nodes.remove(personId) == null) {
      // No override for this person — nothing to do.
      return;
    }
    await client.from('GraphLayoutState').upsert({
      'familyId': familyId,
      'userId': auth.id,
      'nodePositions': nodes,
      ..._preserveOtherColumns(existing),
    }, onConflict: 'familyId, userId');

    ref.invalidate(personalLayoutOverridesProvider(familyId));
  }

  // ── PART 2 — edge midpoint waypoint overrides ──────────────────

  /// Persist a single edge's RELATIVE midpoint offset for the current
  /// viewer + family. Stored as `{dx, dy}` displacement from the
  /// computed t=0.5 bezier midpoint — NOT an absolute coordinate —
  /// so the offset stays meaningful if the endpoints get repositioned.
  static Future<void> saveEdgeWaypoint(
    Ref ref,
    String familyId,
    String relationshipId,
    Offset delta,
  ) async {
    final client = ref.read(supabaseProvider);
    if (client == null) return;
    final auth = client.auth.currentUser;
    if (auth == null) return;

    final existing = await _readRow(client, familyId, auth.id);
    final edges =
        Map<String, dynamic>.from(existing?['edgeWaypoints'] as Map? ?? const {});
    edges[relationshipId] = {'dx': delta.dx, 'dy': delta.dy};

    await client.from('GraphLayoutState').upsert({
      'familyId': familyId,
      'userId': auth.id,
      'edgeWaypoints': edges,
      if (existing != null) ..._preserveOtherColumns(existing),
    }, onConflict: 'familyId, userId');

    ref.invalidate(personalLayoutOverridesProvider(familyId));
  }

  /// Remove a single edge's saved midpoint offset — the dot snaps
  /// back to the true computed t=0.5 bezier midpoint.
  static Future<void> removeEdgeWaypoint(
    Ref ref,
    String familyId,
    String relationshipId,
  ) async {
    final client = ref.read(supabaseProvider);
    if (client == null) return;
    final auth = client.auth.currentUser;
    if (auth == null) return;

    final existing = await _readRow(client, familyId, auth.id);
    if (existing == null) return;
    final edges =
        Map<String, dynamic>.from(existing['edgeWaypoints'] as Map? ?? const {});
    if (edges.remove(relationshipId) == null) return;

    await client.from('GraphLayoutState').upsert({
      'familyId': familyId,
      'userId': auth.id,
      'edgeWaypoints': edges,
      ..._preserveOtherColumns(existing),
    }, onConflict: 'familyId, userId');

    ref.invalidate(personalLayoutOverridesProvider(familyId));
  }

  // ── Helpers ─────────────────────────────────────────────────────

  /// Read the viewer's own GraphLayoutState row. Returns null when no
  /// row exists yet. RLS guarantees we cannot accidentally read
  /// another user's row.
  static Future<Map<String, dynamic>?> _readRow(
    dynamic client,
    String familyId,
    String userId,
  ) async {
    final rows = await client
        .from('GraphLayoutState')
        .select(
            'nodePositions, edgeWaypoints, layoutMode, collapsedNodes, '
            'hiddenNodes, zoomLevel, panOffset, filters')
        .eq('familyId', familyId)
        .eq('userId', userId)
        .limit(1);
    final rowsList = rows is List ? rows : const [];
    if (rowsList.isEmpty) return null;
    return rowsList.first as Map<String, dynamic>;
  }

  /// Columns to preserve when upserting so we don't clobber the other
  /// saved state on the row (zoom, pan, filters, etc.).
  static Map<String, dynamic> _preserveOtherColumns(Map<String, dynamic> row) {
    final out = <String, dynamic>{};
    for (final entry in row.entries) {
      // Skip the two columns the caller is already setting.
      if (entry.key == 'nodePositions' || entry.key == 'edgeWaypoints') continue;
      out[entry.key] = entry.value;
    }
    return out;
  }
}

// ────────────────────────────────────────────────────────────────────
// Rearrange-mode toggle — explicit user intent
// ────────────────────────────────────────────────────────────────────

/// Whether the graph is in "Rearrange" mode. While true:
///   • Long-press-drag on a node repositions it (PART 1).
///   • Long-press-drag on a midpoint dot bows the curve (PART 2).
///   • The existing compare-drag no-op is left wired (it's already
///     a guaranteed no-op because `_compareDragFromId` is never set
///     outside Rearrange mode — see interaction_mixin.dart), and
///     the existing long-press-opens-info-sheet behaviour is
///     SUSPENDED for the duration of Rearrange mode.
///
/// Outside Rearrange mode, the canvas behaves exactly as before —
/// no existing gesture is overloaded.
final rearrangeModeProvider = StateProvider<bool>((ref) => false);

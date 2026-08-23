// lib/core/viewer/viewer_provider.dart
//
// DAXELO KINREL v2.2 — Viewer-Driven Relationship Engine
//
// Resolves the current viewer's Person ID from the authenticated user.
// Every logged-in member sees the family graph from THEIR OWN perspective.
//
// Resolution chain:
//   1. Query Person where linkedUserId = currentUser.id AND familyId = familyId
//   2. If not found → query Person where isAnchor = true AND familyId = familyId
//   3. If not found → return null (prompt user to claim a profile)
//
// Falls back to isAnchor for legacy/unclaimed profiles.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/isar_database.dart';
import '../services/supabase_service.dart';

/// Resolves the current viewer's Person ID for a given family.
///
/// The viewer is the authenticated user's linked Person node.
/// If no link exists, falls back to the family's anchor person.
/// If neither exists, returns null (user should be prompted to claim).
///
/// Usage:
// ═══════════════════════════════════════════════════════════════════════
// v5.16: PURE RESOLUTION LOGIC (extracted for testability)
// ═══════════════════════════════════════════════════════════════════════

/// The result of querying for a linked Person and an anchor Person.
/// Used by [resolveViewerPersonId] to make a decision without I/O.
class ViewerQueryResult {
  const ViewerQueryResult({
    this.linkedPersonId,
    this.anchorPersonId,
    this.anchorLinkedUserId,
  });

  /// The Person.id where linkedUserId == current auth user (or null if not found).
  final String? linkedPersonId;

  /// The Person.id where isAnchor == true (or null if not found).
  final String? anchorPersonId;

  /// The linkedUserId of the anchor person (null if anchor has no link,
  /// or if the anchor check itself failed).
  final String? anchorLinkedUserId;
}

/// Pure function that decides which Person ID to use as the viewer,
/// given already-fetched query results. NO I/O — fully testable.
///
/// Resolution chain (identical to the pre-v5.16 behavior):
///   1. If [result.linkedPersonId] is non-null → return it (fast path)
///   2. If [result.anchorPersonId] is non-null AND
///      [result.anchorLinkedUserId] matches [currentUserId] → return it
///      (anchor IS the current user — safe fallback)
///   3. Otherwise → return null (don't show wrong person as "You")
///
/// [currentUserId] — the auth user's ID (from Supabase auth).
///   Null means no authenticated user.
String? resolveViewerPersonId({
  required ViewerQueryResult result,
  required String? currentUserId,
}) {
  // Step 1: Linked person found — use it directly
  if (result.linkedPersonId != null && result.linkedPersonId!.isNotEmpty) {
    return result.linkedPersonId;
  }

  // Step 3: Anchor fallback — only if the anchor IS the current user
  if (result.anchorPersonId != null && result.anchorPersonId!.isNotEmpty) {
    if (currentUserId != null && result.anchorLinkedUserId == currentUserId) {
      return result.anchorPersonId;
    }
    // Anchor is a different user (or we can't tell) — don't fall back
    return null;
  }

  return null;
}

/// Pure function: determines whether the viewer is "linked" (has an
/// explicit linkedUserId on their Person node) vs falling back to anchor.
///
/// Returns true if [viewerPersonId] is non-null (the viewer resolved
/// to a real Person), false otherwise. This is the single source of
/// truth for isViewerLinkedProvider — no separate API call needed.
bool isViewerLinked(String? viewerPersonId) {
  return viewerPersonId != null && viewerPersonId.isNotEmpty;
}
///     // Use viewerId as the center of the graph
///   }
final viewerPersonIdProvider =
    FutureProvider.autoDispose.family<String?, String>(
  (ref, familyId) async {
    // v5.6: Watch currentUserProvider so this provider REBUILDS when the
    // auth user changes (sign-in, sign-out, account switch). Without this,
    // the provider caches the OLD user's viewerPersonId and never updates
    // — causing the graph to show the previous user's "You" node.
    final currentUser = ref.watch(currentUserProvider);
    final userId = currentUser?.id;

    final client = ref.read(supabaseProvider);
    if (client == null) {
      // Supabase not ready — try offline cache
      return _resolveFromCache(familyId);
    }

    if (userId == null) {
      // v5.77 (VIEWER FIX): Do NOT fall back to the anchor person when
      // userId is null. Previously, this returned _resolveAnchorPerson
      // which returns the anchor Person ID regardless of who owns it.
      // This caused the graph to show the anchor (e.g. Manish) as "You"
      // even when a DIFFERENT user (e.g. Yakshitha) was logged in —
      // because during the brief window when the auth state hasn't
      // initialized yet, the provider returned the anchor's Person ID.
      //
      // Now we return null — the graph shows no "You" node until the
      // auth state is properly initialized. Once currentUserProvider
      // fires with the real user, this provider rebuilds and Step 1
      // finds the correct Person.
      //
      // Also clear the stale cache so a previous user's cached
      // viewerPersonId isn't used.
      invalidateViewerCache(familyId);
      return null;
    }

    // Step 1: Query Person where linkedUserId = userId AND familyId = familyId
    try {
      final response = await client
          .from('Person')
          .select('id')
          .eq('familyId', familyId)
          .eq('linkedUserId', userId)
          .filter('deletedAt', 'is', null)
          .limit(1)
          .timeout(const Duration(seconds: 10));

      if (response.isNotEmpty) {
        final viewerId = response[0]['id'] as String?;
        if (viewerId != null) {
          // Cache for offline use
          _cacheViewerPersonId(familyId, viewerId);
          return viewerId;
        }
      }
    } catch (e) {
      // linkedUserId column might not exist yet — fall through to anchor
      debugPrint('⚠️ viewerPersonIdProvider: linkedUserId query failed: $e');
    }

    // v5.75 (VIEWER FIX): Step 2 (email/name auto-link) has been REMOVED.
    //
    // Previously, if Step 1 didn't find a linked Person, Step 2 tried to
    // match the user's email name-part against Person names using loose
    // `contains()` matching. On match, it AUTO-WROTE linkedUserId to the
    // DB. This was dangerous because:
    //   - "yakshitha" in the email could match a Person named "Yakshitha"
    //     in the WRONG family, silently linking the user to the wrong node.
    //   - Once the bad link was written, Step 1 would keep returning the
    //     wrong Person on every subsequent load.
    //   - The `contains()` matching was too loose (e.g. "man" in
    //     "manishnkotian11@gmail.com" would match any Person named "Man",
    //     "Manish", "Manuela", etc.)
    //
    // With the v5.73 fix (dropping the global unique index on
    // Person.linkedUserId), users can now have Person nodes in multiple
    // families. The fn_accept_family_invite RPC correctly creates a
    // Person with linkedUserId set when a user accepts an invite. So
    // Step 1 should always find the correct Person if the user has
    // properly joined the family.
    //
    // If Step 1 fails (no linked Person), we now go straight to Step 3
    // (anchor fallback) which only returns the anchor if the anchor's
    // linkedUserId matches the current user. If neither matches,
    // viewerPersonId is null — the graph shows no "You" node, which is
    // correct (the user hasn't been linked to a Person in this family).

    // Step 3: Fall back to anchor person (legacy)
    // v5.16: Use the pure resolution function for the decision logic.
    final anchorId = await _resolveAnchorPerson(client, familyId);
    String? anchorLinkedUserId;
    if (anchorId != null) {
      try {
        final anchorData = await client
            .from('Person')
            .select('linkedUserId')
            .eq('id', anchorId)
            .maybeSingle()
            .timeout(const Duration(seconds: 5));
        anchorLinkedUserId = anchorData?['linkedUserId'] as String?;
      } catch (e) {
        debugPrint('⚠️ viewerPersonIdProvider: anchor link check failed: $e');
      }
    }

    final resolvedId = resolveViewerPersonId(
      result: ViewerQueryResult(
        linkedPersonId: null, // Already checked above — null means not found
        anchorPersonId: anchorId,
        anchorLinkedUserId: anchorLinkedUserId,
      ),
      currentUserId: userId,
    );

    if (resolvedId != null) {
      _cacheViewerPersonId(familyId, resolvedId);
    }
    return resolvedId;
  },
);

/// Queries the anchor person for a family.
Future<String?> _resolveAnchorPerson(client, String familyId) async {
  try {
    // Query the family's anchor person (legacy fallback).
    final response = await client
        .from('Person')
        .select('id')
        .eq('familyId', familyId)
        .eq('isAnchor', true)
        .filter('deletedAt', 'is', null)
        .limit(1)
        .timeout(const Duration(seconds: 10));

    if (response.isNotEmpty) {
      return response[0]['id'] as String?;
    }
  } catch (e) {
    debugPrint('⚠️ viewerPersonIdProvider: anchor query failed: $e');
  }

  // Step 3: No viewer found
  return null;
}

/// In-memory cache for offline viewer resolution.
/// Keyed by familyId, valued by viewerPersonId.
final Map<String, String> _viewerCache = {};

void _cacheViewerPersonId(String familyId, String viewerPersonId) {
  _viewerCache[familyId] = viewerPersonId;
  // v2.2 (architecture §13): also persist to Drift so the cache
  // survives app restart. Fire-and-forget — Drift write failures must
  // not break the in-memory cache hit.
  try {
    final db = IsarDatabase.instance;
    db.upsertCachedViewer(familyId, viewerPersonId).catchError((_) {});
  } catch (_) {
    // Drift not initialized yet — fine, in-memory cache is enough.
  }
}

String? _resolveFromCache(String familyId) {
  return _viewerCache[familyId];
}

/// Clears the viewer cache for a specific family (or all if null).
void invalidateViewerCache([String? familyId]) {
  if (familyId != null) {
    _viewerCache.remove(familyId);
    try {
      final db = IsarDatabase.instance;
      db.deleteCachedViewer(familyId).catchError((_) {});
    } catch (_) {
      // Drift not initialized — fine.
    }
  } else {
    _viewerCache.clear();
    // Note: we don't bulk-clear the Drift table here because the
    // per-family delete is the safer pattern (sign-out flow only
    // needs to clear the current family).
  }
}

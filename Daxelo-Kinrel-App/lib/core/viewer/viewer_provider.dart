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
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

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

/// v5.216: FULL pure resolution chain INCLUDING the v5.177.1 creator
/// fallback — the EXACT chain [viewerPersonIdProvider] applies. This is
/// THE canonical "which Person does this user see as their own node"
/// rule, extracted so every surface that needs per-viewer relationships
/// (the family graph, the group-chat kinship labels, future features)
/// resolves the viewer with ONE shared function — never a parallel
/// per-feature rule.
///
/// Chain (first match wins):
///   1. [result.linkedPersonId] non-empty → it (fast path)
///   2. [result.anchorPersonId] non-empty AND its linkedUserId == the
///      given user → the anchor (anchor IS the user)
///   3. [result.anchorPersonId] non-empty AND its linkedUserId is
///      null/empty AND [familyCreatedBy] == the given user → the anchor
///      (v5.177.1: the family creator viewing their own unlinked anchor
///      node — e.g. they already had a Person in another family, so the
///      creation trigger left the anchor without linkedUserId)
///   4. Otherwise → null (don't show the wrong person as "You")
///
/// [currentUserId] — the auth user's ID (viewer side).
/// [familyCreatedBy] — Family.createdBy for the family being viewed.
String? resolveViewerPersonIdWithCreatorFallback({
  required ViewerQueryResult result,
  String? familyCreatedBy,
  required String? currentUserId,
}) {
  // Steps 1–2 via the existing pure function (reuse, no duplication).
  final linkedOrAnchor = resolveViewerPersonId(
    result: result,
    currentUserId: currentUserId,
  );
  if (linkedOrAnchor != null) return linkedOrAnchor;

  // Step 3: creator fallback (v5.177.1).
  final anchorId = result.anchorPersonId;
  final anchorUnlinked =
      result.anchorLinkedUserId == null || result.anchorLinkedUserId!.isEmpty;
  if (anchorId != null && anchorId.isNotEmpty && anchorUnlinked) {
    if (currentUserId != null &&
        currentUserId.isNotEmpty &&
        familyCreatedBy != null &&
        familyCreatedBy == currentUserId) {
      return anchorId;
    }
  }
  return null;
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

    // v5.180 (BUG #1 DEBUG): Log the current auth user for debugging
    // "wrong You" issues. If the wrong user appears here, the bug is in
    // the auth state, not the viewer resolution.
    debugPrint('[viewerPersonIdProvider] familyId=$familyId, '
        'authUserId=${userId ?? 'NULL'}, '
        'authUserEmail=${currentUser?.email ?? 'NULL'}');

    final client = ref.read(supabaseProvider);
    if (client == null) {
      // Supabase not ready — try offline cache
      final cached = _resolveFromCache(familyId);
      debugPrint('[viewerPersonIdProvider] Supabase not ready — '
          'cache returned: ${cached ?? 'NULL'}');
      return cached;
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
      debugPrint('[viewerPersonIdProvider] userId is NULL — '
          'cleared cache, returning null');
      return null;
    }

    // Step 1: Query Person where linkedUserId = userId AND familyId = familyId
    try {
      final response = await client
          .from('Person')
          .select('id, name, isAnchor')
          .eq('familyId', familyId)
          .eq('linkedUserId', userId)
          .filter('deletedAt', 'is', null)
          .limit(1)
          .timeout(const Duration(seconds: 10));

      if (response.isNotEmpty) {
        final viewerId = response[0]['id'] as String?;
        final viewerName = response[0]['name'] as String?;
        if (viewerId != null) {
          // Cache for offline use
          _cacheViewerPersonId(familyId, viewerId);
          debugPrint('[viewerPersonIdProvider] ✓ Step 1 resolved: '
              'viewerId=$viewerId, name=$viewerName');
          return viewerId;
        }
      }
      debugPrint('[viewerPersonIdProvider] Step 1 found no linked Person '
          'for userId=$userId in family=$familyId');
    } catch (e) {
      // linkedUserId column might not exist yet — fall through to anchor
      debugPrint('[viewerPersonIdProvider] Step 1 query failed: $e');
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

    // v5.216: Steps 1–3 now run through the SHARED pure resolution chain
    // (resolveViewerPersonIdWithCreatorFallback) so the family graph and
    // every other per-viewer surface (group-chat kinship labels) apply
    // EXACTLY the same rules. Behavior is identical to the previous
    // inline v5.177.1 logic.
    //
    // The creator fallback can only help when the anchor exists but is
    // unlinked — that's the only case where Family.createdBy is queried
    // (preserving the previous query count for every other path).
    final anchorUnlinked = anchorLinkedUserId == null;
    final resolvedId = resolveViewerPersonIdWithCreatorFallback(
      result: ViewerQueryResult(
        linkedPersonId: null, // Already checked above — null means not found
        anchorPersonId: anchorId,
        anchorLinkedUserId: anchorLinkedUserId,
      ),
      familyCreatedBy: await _familyCreatedBy(
        client,
        familyId,
        needed: anchorId != null && anchorUnlinked,
      ),
      currentUserId: userId,
    );

    // v5.216 DEBUG parity: keep the previous resolution logging.
    if (resolvedId != null) {
      _cacheViewerPersonId(familyId, resolvedId);
      debugPrint('[viewerPersonIdProvider] ✓ Final resolution: '
          'viewerId=$resolvedId (via anchor/creator fallback)');
    } else {
      debugPrint('[viewerPersonIdProvider] ✗ Could not resolve viewer — '
          'no linked Person, no anchor match, not family creator. '
          'Graph will show no "You" node.');
    }
    return resolvedId;
  },
);

/// v5.216: Queries Family.createdBy for the creator fallback (Step 3).
/// Only called when [needed] is true (anchor exists but is unlinked) to
/// preserve the pre-v5.216 query count; returns null otherwise or on
/// failure (treated as "not the creator" by the pure resolver).
Future<String?> _familyCreatedBy(client, String familyId,
    {required bool needed}) async {
  if (!needed) return null;
  try {
    final familyData = await client
        .from('Family')
        .select('createdBy')
        .eq('id', familyId)
        .maybeSingle()
        .timeout(const Duration(seconds: 5));
    return familyData?['createdBy'] as String?;
  } catch (e) {
    debugPrint('⚠️ viewerPersonIdProvider: creator check failed: $e');
    return null;
  }
}

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
/// v5.180 (BUG #1 FIX): Keyed by (userId, familyId) — NOT just familyId.
/// Previously, when Manish signed out and Rakshitha signed in, the cache
/// still contained Manish's viewerPersonId for any family he had opened.
/// When Rakshitha opened the same family, the cache returned Manish's ID,
/// causing the wrong node to be marked as "You".
///
/// Now the cache is scoped by userId, so each user has their own cache
/// namespace. On sign-out, invalidateViewerCache() clears ALL entries
/// (no userId filter) to free memory.
final Map<String, String> _viewerCache = {}; // key: "$userId:$familyId"

void _cacheViewerPersonId(String familyId, String viewerPersonId) {
  // v5.180: Scope cache by userId so account switches don't leak.
  final userId = _currentUserIdForCache();
  final cacheKey = _cacheKey(userId, familyId);
  if (cacheKey != null) {
    _viewerCache[cacheKey] = viewerPersonId;
  } else {
    // userId unknown — use legacy familyId-only key (best-effort).
    _viewerCache[familyId] = viewerPersonId;
  }
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
  // v5.180: Prefer the userId-scoped key. If not found, fall back to
  // the legacy familyId-only key (for backward compat with entries
  // written by older code paths).
  final userId = _currentUserIdForCache();
  final scopedKey = _cacheKey(userId, familyId);
  if (scopedKey != null && _viewerCache.containsKey(scopedKey)) {
    return _viewerCache[scopedKey];
  }
  return _viewerCache[familyId]; // legacy fallback
}

/// Gets the current authenticated user's ID for cache scoping.
/// Uses Supabase.instance.client.auth.currentUser — NOT Riverpod —
/// because the cache functions are called from non-widget contexts
/// (e.g. the viewerPersonIdProvider body itself).
String? _currentUserIdForCache() {
  try {
    return Supabase.instance.client.auth.currentUser?.id;
  } catch (_) {
    return null;
  }
}

/// Builds a cache key scoped by (userId, familyId).
String? _cacheKey(String? userId, String familyId) {
  if (userId == null || userId.isEmpty) return null;
  return '$userId:$familyId';
}

/// Clears the viewer cache for a specific family (or all if null).
/// v5.180: When familyId is null (sign-out), clears ALL entries.
/// When familyId is non-null, clears both the scoped and legacy keys
/// for that family across ALL users (safe — the provider will re-resolve).
void invalidateViewerCache([String? familyId]) {
  if (familyId != null) {
    // Clear scoped entries for this family across all users
    _viewerCache.removeWhere((key, _) =>
        key == familyId || key.endsWith(':$familyId'));
    try {
      final db = IsarDatabase.instance;
      db.deleteCachedViewer(familyId).catchError((_) {});
    } catch (_) {
      // Drift not initialized — fine.
    }
  } else {
    // v5.180: Clear ALL entries (sign-out / account switch).
    // This is critical — without this, the previous user's viewerPersonId
    // persists in memory and gets returned for the new user's family.
    _viewerCache.clear();
    // Note: we don't bulk-clear the Drift table here because the
    // per-family delete is the safer pattern (sign-out flow only
    // needs to clear the current family). But the in-memory cache
    // is fully cleared to prevent account-switch leaks.
  }
}

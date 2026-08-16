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
      // No authenticated user — fall back to anchor (legacy / unclaimed)
      return _resolveAnchorPerson(client, familyId);
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

    // v5.5: Step 2 — Try to find a Person by matching the user's email.
    // This handles the case where a Person was added manually (e.g.
    // "Yakshiii") but hasn't been linked to the auth user yet. We match
    // the email from the auth user's metadata against the Person's
    // linkedUserId or any email field.
    // This is a BEST-EFFORT match — if it fails, we fall through to
    // the anchor fallback.
    try {
      final userEmail = currentUser?.email;
      if (userEmail != null && userEmail.isNotEmpty) {
        // Extract the name part of the email (before @) and try to
        // find a Person with that name in this family.
        final namePart = userEmail.split('@').first.toLowerCase();
        // Try exact name match (case-insensitive)
        final nameMatch = await client
            .from('Person')
            .select('id, name')
            .eq('familyId', familyId)
            .filter('deletedAt', 'is', null)
            .timeout(const Duration(seconds: 10));

        for (final p in nameMatch as List) {
          final personName = (p['name'] as String?)?.toLowerCase() ?? '';
          // Check if the person's name matches the email name part
          if (personName == namePart ||
              personName.contains(namePart) ||
              namePart.contains(personName)) {
            final personId = p['id'] as String?;
            if (personId != null) {
              debugPrint('🔍 viewerPersonIdProvider: matched Person by email/name: $personName → $personId');
              // Auto-link this Person to the current user so future
              // resolutions use the fast path (Step 1).
              try {
                await client
                    .from('Person')
                    .update({'linkedUserId': userId})
                    .eq('id', personId);
                debugPrint('✅ Auto-linked Person $personId to user $userId');
              } catch (e) {
                debugPrint('⚠️ Auto-link failed (non-fatal): $e');
              }
              _cacheViewerPersonId(familyId, personId);
              return personId;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ viewerPersonIdProvider: email/name match failed: $e');
    }

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

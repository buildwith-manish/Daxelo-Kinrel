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
// When kAuthDisabled=true (debug mode), the debug user is auto-linked to
// all anchor persons they created. So step 1 finds the anchor person
// directly (once the linkedUserId column is populated).
//
// Falls back to isAnchor for legacy/unclaimed profiles.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/auth_config.dart';
import '../database/isar_database.dart';
import '../services/supabase_service.dart';

/// Resolves the current viewer's Person ID for a given family.
///
/// The viewer is the authenticated user's linked Person node.
/// If no link exists, falls back to the family's anchor person.
/// If neither exists, returns null (user should be prompted to claim).
///
/// Usage:
///   final viewerId = ref.watch(viewerPersonIdProvider(familyId));
///   if (viewerId.valueOrNull != null) {
///     // Use viewerId as the center of the graph
///   }
final viewerPersonIdProvider =
    FutureProvider.autoDispose.family<String?, String>(
  (ref, familyId) async {
    final client = ref.read(supabaseProvider);
    if (client == null) {
      // Supabase not ready — try offline cache
      return _resolveFromCache(familyId);
    }

    // v62.5: Auto sign-in if kAuthDisabled and no session
    if (kAuthDisabled && client.auth.currentSession == null) {
      try {
        await client.auth
            .signInWithPassword(
              email: MockUser.email,
              password: 'Debug@123456',
            )
            .timeout(const Duration(seconds: 8));
      } catch (e) {
        debugPrint('⚠️ viewerPersonIdProvider: auto sign-in failed: $e');
      }
    }

    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      // No authenticated user — fall back to anchor
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

      if (response is List && response.isNotEmpty) {
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

    // Step 2: Fall back to anchor person (legacy)
    return _resolveAnchorPerson(client, familyId);
  },
);

/// Queries the anchor person for a family.
Future<String?> _resolveAnchorPerson(client, String familyId) async {
  try {
    // When kAuthDisabled, query ALL families (no userId filter)
    final response = await client
        .from('Person')
        .select('id')
        .eq('familyId', familyId)
        .eq('isAnchor', true)
        .filter('deletedAt', 'is', null)
        .limit(1)
        .timeout(const Duration(seconds: 10));

    if (response is List && response.isNotEmpty) {
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
}

String? _resolveFromCache(String familyId) {
  if (IsarDatabase.isInitialized) {
    return _viewerCache[familyId];
  }
  return _viewerCache[familyId];
}

/// Clears the viewer cache for a specific family (or all if null).
void invalidateViewerCache([String? familyId]) {
  if (familyId != null) {
    _viewerCache.remove(familyId);
  } else {
    _viewerCache.clear();
  }
}

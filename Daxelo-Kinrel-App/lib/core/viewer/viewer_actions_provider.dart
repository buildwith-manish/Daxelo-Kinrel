// lib/core/viewer/viewer_actions_provider.dart
//
// DAXELO KINREL v2.2 — Viewer Actions Provider
//
// Wraps the [ViewerApiClient] so the UI can call claim / unlink / invite
// / accept-invite with a single method, and have all relevant Riverpod
// providers invalidated automatically after a successful operation.
//
// Usage:
//   await ref.read(viewerActionsProvider).claimPerson(
//     familyId: 'fam-1',
//     personId: 'p-1',
//   );
//   // viewerPersonIdProvider + familyGraphProvider are now invalidated;
//   // the next read will re-fetch from the new viewer's perspective.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/supabase_service.dart' show supabaseProvider;
import '../../features/family/presentation/providers/family_graph_provider.dart'
    show familyGraphProvider;
import 'viewer_api_client.dart';
import 'viewer_provider.dart' show invalidateViewerCache, viewerPersonIdProvider;

/// Provider for the [ViewerActions] service.
final viewerActionsProvider = Provider<ViewerActions>((ref) {
  return ViewerActions(ref);
});

/// High-level actions that mutate the viewer state.
///
/// Every method:
///   1. Calls the corresponding NestJS endpoint via [ViewerApiClient].
///   2. On success, invalidates the local caches and Riverpod providers
///      so the UI re-fetches from the new viewer's perspective.
///   3. Re-throws [ViewerApiException] on failure (no silent swallows).
class ViewerActions {
  ViewerActions(this._ref);
  final Ref _ref;

  /// Claims a Person node for the authenticated user.
  ///
  /// After success:
  ///   - Invalidates the in-memory + Drift viewer cache for this family.
  ///   - Invalidates `viewerPersonIdProvider(familyId)` so the next read
  ///     re-resolves to the newly-linked Person.
  ///   - Invalidates `familyGraphProvider(familyId)` so the graph
  ///     re-renders centered on the new viewer.
  Future<PersonLinkResult> claimPerson({
    required String familyId,
    required String personId,
  }) async {
    final client = _ref.read(viewerApiClientProvider);
    final result = await client.claimPerson(
      familyId: familyId,
      personId: personId,
    );
    _invalidateAfterLinkChange(familyId);
    debugPrint(
      'ViewerActions.claimPerson: linked user ${result.linkedUserId} '
      'to Person ${result.personId} in family $familyId',
    );
    return result;
  }

  /// Removes the link between the authenticated user and a Person node.
  ///
  /// After success: same invalidations as [claimPerson] so the UI
  /// falls back to the anchor (legacy) viewer or prompts the user to
  /// claim a different profile.
  Future<UnlinkResult> unlinkPerson({
    required String familyId,
    required String personId,
  }) async {
    final client = _ref.read(viewerApiClientProvider);
    final result = await client.unlinkPerson(
      familyId: familyId,
      personId: personId,
    );
    _invalidateAfterLinkChange(familyId);
    debugPrint(
      'ViewerActions.unlinkPerson: unlinked Person $personId in family $familyId',
    );
    return result;
  }

  /// Creates a one-time invitation for a Person node.
  ///
  /// Does NOT invalidate any providers — the invitation doesn't take
  /// effect until the recipient accepts it. The caller is responsible
  /// for displaying the returned [InvitationResult.invitationCode] to
  /// the user (or sending it via email/SMS through a separate channel).
  Future<InvitationResult> invitePerson({
    required String familyId,
    required String personId,
    String? recipientName,
    String? recipientEmail,
    String? recipientPhone,
    String? role,
  }) async {
    final client = _ref.read(viewerApiClientProvider);
    return client.invitePerson(
      familyId: familyId,
      personId: personId,
      recipientName: recipientName,
      recipientEmail: recipientEmail,
      recipientPhone: recipientPhone,
      role: role,
    );
  }

  /// Accepts a pending person-link invitation.
  ///
  /// After success: same invalidations as [claimPerson] so the graph
  /// re-renders from the new viewer's perspective.
  Future<PersonLinkResult> acceptInvitation({
    required String familyId,
    required String code,
  }) async {
    final client = _ref.read(viewerApiClientProvider);
    final result = await client.acceptInvitation(
      familyId: familyId,
      code: code,
    );
    _invalidateAfterLinkChange(familyId);
    debugPrint(
      'ViewerActions.acceptInvitation: accepted code $code, '
      'linked to Person ${result.personId}',
    );
    return result;
  }

  // ── Internal helpers ──────────────────────────────────────────────

  void _invalidateAfterLinkChange(String familyId) {
    // 1. Clear the in-memory + Drift viewer cache for this family.
    invalidateViewerCache(familyId);

    // 2. Invalidate the viewerPersonIdProvider so the next read
    //    re-resolves (viewerPersonIdProvider is autoDispose, so this
    //    forces a fresh Supabase round-trip).
    _ref.invalidate(viewerPersonIdProvider(familyId));

    // 3. Invalidate the familyGraphProvider so the graph re-fetches
    //    with the new viewer as the BFS seed.
    _ref.invalidate(familyGraphProvider(familyId));

    // 4. Touch the Supabase client to make sure we have a session —
    //    if the user just signed in, this ensures the auth state is
    //    propagated before the next read.
    _ref.read(supabaseProvider);
  }
}

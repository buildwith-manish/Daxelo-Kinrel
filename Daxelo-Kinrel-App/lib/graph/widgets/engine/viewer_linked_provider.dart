// lib/graph/widgets/engine/viewer_linked_provider.dart
// P0.4: Extracted from family_graph_engine_view.dart.
// v5.11: Rewritten to derive from viewerPersonIdProvider (single source of truth).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/viewer/viewer_provider.dart' show viewerPersonIdProvider;

/// Returns true if the current user has an explicit `linkedUserId` link
/// to their Person node in this family.
///
/// v5.11: SINGLE SOURCE OF TRUTH. This provider now DERIVES from
/// [viewerPersonIdProvider] instead of making a separate API call to
/// `viewerApiClientProvider.resolveViewer`. The old approach had TWO
/// separate systems checking "is this viewer linked?" and they could
/// disagree — causing the ClaimProfileBanner to contradict the graph
/// (graph shows "You" on the correct node, but the banner still says
/// "claim your profile").
///
/// The new approach: viewerPersonIdProvider already queries
/// Person.linkedUserId == auth.currentUser.id. If it resolves to a
/// non-null Person ID, the user IS linked. If it resolves to null,
/// the user is NOT linked (and the banner should show).
///
/// This provider returns `true` (linked) when:
///   - viewerPersonIdProvider has resolved to a non-null Person ID
///
/// It returns `false` (not linked) when:
///   - viewerPersonIdProvider has resolved to null
///
/// It returns `true` (assume linked) when:
///   - viewerPersonIdProvider is still loading (don't show banner prematurely)
///   - viewerPersonIdProvider has an error (don't block the graph UI)
final isViewerLinkedProvider =
    Provider.family<bool, String>((ref, familyId) {
  final viewerAsync = ref.watch(viewerPersonIdProvider(familyId));

  // Loading → assume linked (don't show banner prematurely)
  if (viewerAsync.isLoading) return true;

  // Error → assume linked (don't show banner on transient errors)
  if (viewerAsync.hasError) return true;

  // Resolved → linked if non-null, not linked if null
  final viewerId = viewerAsync.valueOrNull;
  return viewerId != null && viewerId.isNotEmpty;
});

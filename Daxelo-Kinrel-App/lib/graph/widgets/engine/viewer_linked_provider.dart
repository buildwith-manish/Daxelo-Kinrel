// lib/graph/widgets/engine/viewer_linked_provider.dart
// P0.4: Extracted from family_graph_engine_view.dart.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/viewer/viewer_api_client.dart'
    show viewerApiClientProvider;

/// Returns true if the current user has an explicit `linkedUserId` link
/// to their Person node in this family (as opposed to falling back to
/// `isAnchor` via [viewerPersonIdProvider]).
///
/// GAP 3 FIX: Used by [FamilyGraphEngineView] to decide whether to show
/// the "_ClaimProfileBanner". When the authenticated user has not yet
/// claimed a Person node, the viewer silently resolves to the anchor —
/// the graph renders but from the wrong perspective. This provider
/// surfaces that state so the UI can prompt the user to claim.
///
/// Returns `true` on error so we never show a false-positive banner —
/// the graph stays usable even if the viewer-resolution endpoint fails.
final isViewerLinkedProvider =
    FutureProvider.autoDispose.family<bool, String>((ref, familyId) async {
  try {
    final client = ref.read(viewerApiClientProvider);
    final resolution = await client.resolveViewer(familyId);
    return resolution.isLinked;
  } catch (_) {
    // Assume linked on error — don't show banner unnecessarily
    return true;
  }
});

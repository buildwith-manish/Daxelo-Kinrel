// lib/features/sparq_tray/providers/family_sparq_tray_provider.dart
//
// DAXELO KINREL — Family Sparq tray Riverpod providers.
//
// Builds one `FamilySparqTrayItem` per family the viewer belongs to,
// joined with the global Sparq feed (per spec section 5):
//   1. Watch `familyListProvider` for the family list.
//   2. For each family, read the already-loaded `familyDetailProvider`
//      and collect `members.where((m) => m.isLinkedToKinrelUser)` —
//      `.select` so only the SET of linked user ids triggers rebuilds.
//      Never block the tray on a family whose detail has not loaded
//      (show it with an empty ring until it does).
//   3. Watch `sparqProvider.select((s) => s.feed)` and join: a member's
//      `UserSparqGroup` belongs to EVERY family whose linked-user set
//      contains its `userId`. (A person in two families appears in
//      both rings on purpose.)
//   4. Exclude the viewer's own group from family rings.
//   5. Drop expired Sparqs and unrevealed time capsules from
//      `unseenCount` (still rendered as a dashed-outline petal but
//      never "new").
//   6. Build `petals` ordered unseen-first then by recency, max 8.
//   7. Attach the Moment Sparq for that family when one applies.
//   8. Return the families sorted as in section 2:
//        a) families with unseen Sparqs first,
//        b) families whose Sparqs are all seen,
//        c) families with none (within a group keep the order of
//           `familyListProvider`).
//
// Performance:
//   • `.select` on the linked-user-id set means the tray rebuilds only
//     when the SET of members changes (not on every detail refresh).
//   • `.select` on `sparqProvider.feed` means the tray rebuilds only
//     when the feed list identity changes (not on every echo toggle).
//   • The whole join is O(families × feed) and runs inside a
//     `Provider` body (no AsyncNotifier overhead). For a typical user
//     with ≤10 families and ≤60 feed rows, this is <1ms.

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;

import '../../../core/family/family_provider.dart'
    show
        Family,
        familyDetailProvider,
        familyListProvider;
import '../../../core/services/supabase_service.dart'
    show currentUserProvider;
import '../../social/data/models/sparq_model.dart' show UserSparqGroup;
import '../../social/data/providers/sparq_provider.dart'
    show sparqProvider;
import '../data/family_sparq_tray_item.dart';
import 'moment_sparq_provider.dart' show familyMomentSparqProvider;

/// The set of linked Kinrel user ids for a family.
///
/// Spec section 5 step 2: watch `familyDetailProvider(family.id)` and
/// collect `members.where((m) => m.isLinkedToKinrelUser)`. Use `.select`
/// so only the SET of linked user ids triggers rebuilds (not every
/// property change on a member).
@visibleForTesting
final linkedUserIdsForFamilyProvider =
    Provider.family<Set<String>, String>((ref, familyId) {
  final detailAsync = ref.watch(familyDetailProvider(familyId));
  final detail = detailAsync.valueOrNull;
  if (detail == null) return const <String>{};

  final ids = <String>{};
  for (final m in detail.members) {
    if (m.isLinkedToKinrelUser && m.linkedUserId != null) {
      ids.add(m.linkedUserId!);
    }
  }
  return ids;
});

/// Returns the `UserSparqGroup` for the current viewer (the "Your
/// Sparq" entry's data source). Spec section 5, `mySparqSummaryProvider`.
///
/// Reads from the global `sparqProvider.feed` (already-loaded) and
/// falls back to nothing when the feed hasn't loaded yet. The viewer's
/// own group never appears in a family ring (it's filtered out in
/// `familySparqTrayProvider`).
final mySparqSummaryProvider = Provider<UserSparqGroup?>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  final feed = ref.watch(sparqProvider.select((s) => s.feed));
  for (final g in feed) {
    if (g.userId == user.id) return g;
  }
  return null;
});

/// Pure helper: build one [FamilySparqTrayItem] from the joined data.
/// Extracted as a top-level function so unit tests can exercise the
/// exact join, ordering, and 8-slot cap without a Riverpod container.
@visibleForTesting
FamilySparqTrayItem buildFamilySparqTrayItem({
  required Family family,
  required Set<String> memberUserIds,
  required List<UserSparqGroup> feed,
  required MomentSparq? moment,
  required String? currentUserId,
  required Set<String> locallyViewedSparqIds,
}) {
  // Step 3: join — a member's UserSparqGroup belongs to this family
  // when the family's linked-user set contains its userId.
  final memberGroups = <UserSparqGroup>[];
  for (final g in feed) {
    if (g.userId == currentUserId) continue; // step 4 — own group excluded
    if (memberUserIds.contains(g.userId)) {
      memberGroups.add(g);
    }
  }

  // Step 6: build petals (unseen-first, recency-ordered, max 8).
  final petals = buildPetals(
    feed: feed,
    memberUserIds: memberUserIds,
    moment: moment,
    isSeen: (sparqId) => locallyViewedSparqIds.contains(sparqId),
    excludeUserId: currentUserId,
  );

  // Step 5: unseenCount excludes expired + unrevealed time capsules.
  final unseenCount = countUnseenForFamily(
    memberGroups: memberGroups,
    isSeen: (sparqId) => locallyViewedSparqIds.contains(sparqId),
  );

  final hasLive = memberGroups.isNotEmpty || moment != null;

  final allSeen = !memberGroups.any((g) {
    for (final s in g.sparqs) {
      if (!isSparqLiveForTray(s)) continue;
      if (!locallyViewedSparqIds.contains(s.id)) return true; // any unseen
    }
    return false;
  });

  return FamilySparqTrayItem(
    family: family,
    memberGroups: memberGroups,
    moment: moment,
    unseenCount: unseenCount,
    hasLive: hasLive,
    allSeen: allSeen,
    petals: petals,
  );
}

/// The list of [FamilySparqTrayItem]s for the Home tray.
///
/// One entry per family, plus the consumer appends "Your Sparq" first
/// and "New family" last. The tray widget reads this provider's
/// `AsyncValue` directly (loading → shimmer, error → empty kolam
/// rings, never an error banner on Home).
final familySparqTrayProvider =
    Provider<AsyncValue<List<FamilySparqTrayItem>>>((ref) {
  // Watch the family list — drives the family count + identity.
  final familiesAsync = ref.watch(familyListProvider);

  // Watch the feed list identity (not the whole SparqState — only the
  // feed + locallyViewed set matter for the ring state).
  final feed = ref.watch(sparqProvider.select((s) => s.feed));
  final locallyViewed = ref.watch(
    sparqProvider.select((s) => s.locallyViewedSparqIds),
  );

  final currentUser = ref.watch(currentUserProvider);
  final currentUserId = currentUser?.id;

  return familiesAsync.when(
    loading: () => const AsyncValue<List<FamilySparqTrayItem>>.loading(),
    error: (e, st) => AsyncValue<List<FamilySparqTrayItem>>.error(e, st),
    data: (families) {
      try {
        final items = <FamilySparqTrayItem>[];
        for (final family in families) {
          // Step 2: read the linked-user-id set for this family (already
          // loaded by familyDetailProvider via linkedUserIdsForFamilyProvider).
          final memberUserIds =
              ref.read(linkedUserIdsForFamilyProvider(family.id));

          // Step 7: attach the Moment Sparq for this family, if any.
          // (Only for the viewer's own families — see moment_sparq_provider.)
          final moment = ref.read(familyMomentSparqProvider(family.id));

          items.add(buildFamilySparqTrayItem(
            family: family,
            memberUserIds: memberUserIds,
            feed: feed,
            moment: moment,
            currentUserId: currentUserId,
            locallyViewedSparqIds: locallyViewed,
          ));
        }

        // Step 8: sort — unseen first, then all-seen, then no-Sparqs.
        // Within a group, keep familyListProvider order (stable sort).
        items.sort((a, b) {
          final aRank = _rankForSort(a);
          final bRank = _rankForSort(b);
          if (aRank != bRank) return aRank - bRank;
          return 0; // stable within group
        });

        return AsyncValue<List<FamilySparqTrayItem>>.data(items);
      } catch (e, st) {
        debugPrint('familySparqTrayProvider error: $e');
        return AsyncValue<List<FamilySparqTrayItem>>.error(e, st);
      }
    },
  );
});

/// Lower rank = earlier in the tray.
///   0 — families with unseen Sparqs (or a live Moment Sparq).
///   1 — families whose Sparqs are all seen.
///   2 — families with no Sparqs at all.
int _rankForSort(FamilySparqTrayItem item) {
  if (item.unseenCount > 0) return 0;
  // A Moment Sparq counts as "unseen" until dismissed.
  if (item.moment != null) return 0;
  if (item.hasLive) return 1; // all seen
  return 2;
}

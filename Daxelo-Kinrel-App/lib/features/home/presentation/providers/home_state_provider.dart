// lib/features/home/presentation/providers/home_state_provider.dart
//
// DAXELO KINREL — HomeState provider.
//
// Computes a single HomeState enum from real data so the Home
// screen can branch cleanly into three explicit layouts:
//
//   newUser   — viewer has no relatives yet (only themselves).
//   growing   — has relatives, but no posts or Sparqs in the
//               last 14 days.
//   active    — has recent posts or Sparqs.
//
// All inputs are watched via ref.watch so Riverpod auto-rebuilds
// the state when any of them change. The state is computed ONCE
// per family — not per frame — and cached by Riverpod's
// FutureProvider.family cache.
//
// Why 14 days for "recent":
//   • Long enough to cover a normal family-events cadence
//     (birthdays, festivals, occasional shares).
//   • Short enough that a stale family (no posts in 2+ weeks)
//     surfaces the "growing" state with its Next Step card +
//     compact prompt row — nudging the user back into action
//     without being annoying.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/kinship/kinship_term_providers.dart';
import '../../../../core/viewer/viewer_provider.dart' show viewerPersonIdProvider;
import '../../../family/presentation/providers/family_graph_provider.dart'
    show familyGraphProvider;
import '../../../feed/providers/feed_provider.dart' show homeFeedProvider;
import '../../../social/data/providers/sparq_provider.dart' show sparqProvider;

/// The three explicit Home screen states.
enum HomeState {
  /// Viewer has no relatives yet (only themselves on the family
  /// graph). Show the Next Step card + a quiet line. No ring row,
  /// no feed header, no TodaysQuestionCard.
  newUser,

  /// Viewer has relatives but no posts AND no Sparqs in the last
  /// 14 days. Show the ring row + Next Step card + a compact
  /// "Share a photo / Record a voice note" prompt row + a quiet
  /// line. No "Home Feed" header.
  growing,

  /// Viewer has at least one post OR Sparq in the last 14 days.
  /// Show the ring row + TodaysQuestionCard + the feed with the
  /// "Family moments" heading.
  active,
}

/// Number of days to look back when deciding whether the family
/// is "active" (has recent posts or Sparqs) vs "growing" (has
/// relatives but is quiet).
const int kHomeRecentWindowDays = 14;

/// Computes the HomeState for the given family. Watches:
///   - viewerPersonIdProvider(familyId)  — the viewer's Person.id
///   - familyGraphProvider(familyId)     — the flat graph
///   - kinshipTermsForFamilyProvider(familyId) — resolved kinship terms
///   - homeFeedProvider                  — recent feed posts
///   - sparqProvider                     — recent Sparqs
///
/// The watch chain means a state flip (e.g., user records their
/// first Sparq → active) is reflected immediately on the next
/// Home rebuild — no manual invalidation needed.
final homeStateProvider = FutureProvider.family<HomeState, String>(
  (ref, familyId) async {
    final viewerAsync = ref.watch(viewerPersonIdProvider(familyId));
    final viewerPersonId = viewerAsync.valueOrNull;
    final graphAsync = ref.watch(familyGraphProvider(familyId));
    final graph = graphAsync.valueOrNull;
    final termsAsync = ref.watch(kinshipTermsForFamilyProvider(familyId));
    final terms = termsAsync.valueOrNull ?? const <String, dynamic>{};
    final feedState = ref.watch(homeFeedProvider);
    final sparqState = ref.watch(sparqProvider);

    // ── newUser: graph not loaded OR graph has only the viewer ────
    // When the graph is still loading, we default to newUser so
    // the Next Step card surfaces immediately (better to show a
    // helpful nudge than a blank screen during the brief loading
    // window).
    if (graph == null || graph.persons.isEmpty) {
      return HomeState.newUser;
    }

    // Count reachable relatives (persons with a kinship term
    // resolved, excluding the viewer themselves).
    final relativeCount = graph.persons.where((p) {
      final id = p['id']?.toString();
      if (id == null || id.isEmpty) return false;
      if (id == viewerPersonId) return false;
      // The terms map excludes the viewer (resolveClassification
      // returns null for self). A non-null entry means the person
      // is reachable from the viewer.
      return terms.containsKey(id);
    }).length;

    if (relativeCount == 0) {
      return HomeState.newUser;
    }

    // ── active: at least one post OR Sparq in the recent window ──
    final cutoff =
        DateTime.now().subtract(const Duration(days: kHomeRecentWindowDays));

    final hasRecentPost = feedState.posts.any((p) {
      final created = p.createdAt;
      return created != null && created.isAfter(cutoff);
    });

    final hasRecentSparq = sparqState.feed.any((group) {
      return group.sparqs.any((sparq) {
        return sparq.createdAt.isAfter(cutoff);
      });
    });

    if (hasRecentPost || hasRecentSparq) {
      return HomeState.active;
    }

    // Relatives exist but no recent activity.
    return HomeState.growing;
  },
  name: 'homeStateProvider',
);

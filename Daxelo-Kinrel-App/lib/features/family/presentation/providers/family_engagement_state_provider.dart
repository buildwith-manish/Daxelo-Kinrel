// lib/features/family/presentation/providers/family_engagement_state_provider.dart
//
// DAXELO KINREL — Family Engagement State Provider
//
// A single Riverpod provider that derives the family's "engagement state"
// from data ALREADY being fetched for other parts of the Family Space
// detail screen (member count, recent relationships, Prediction Battle
// history, active games, cross-feature moments). It does NOT issue any
// new expensive query — it composes existing providers' results into a
// three-state enum that the Family Space detail screen uses to drive
// its content-section ordering.
//
// The three states (per the design brief):
//
//   newSmall
//     - Member count < 3
//     - The family is brand new or has only the creator + one other
//       person. The screen's primary job is to help the user GROW the
//       family, so Invite Family Member renders as the FIRST content
//       section.
//
//   establishedLowActivity
//     - Member count >= 3, AND
//     - No game / Prediction Battle / Family Pulse activity event in
//       the last 7 days
//     - The family exists but has gone quiet. The screen's primary job
//       is to remind the user what's been happening and nudge
//       re-engagement, so Family Pulse (Recent Activity) renders as
//       the FIRST content section.
//
//   establishedActive
//     - Member count >= 3, AND
//     - At least one game / Prediction Battle / Family Pulse activity
//       event in the last 7 days
//     - The family is genuinely engaged. Time-sensitive "come back
//       today" content earns top placement, so Prediction Battle
//       renders as the FIRST content section.
//
// "Activity in the last 7 days" is computed from the EXISTING data the
// Family Space screen already loads:
//   - familyDetailProvider     → relationships + members (their createdAt)
//   - pbV1HistoryProvider      → revealed Prediction Battle rounds
//                                (their revealAt timestamp)
//   - familyActiveGamesProvider→ active games (their createdAt)
//   - crossFeatureMomentsProvider→ oral history / memory vault / quiz
//                                completions (their createdAt)
//
// If any of those providers return data with a timestamp within the
// last 7 days, the family is "active". This intentionally reuses data
// already in flight rather than issuing a separate recency query.
//
// DESIGN INVARIANT: the Family Space screen's content sections must
// always render Invite Family Member within the first 1–2 screen
// scrolls regardless of state. Only its EXACT position (first vs.
// second/third) changes by state. The ordering function in this file
// encodes that invariant — see [sectionOrderFor].

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/family/family_provider.dart';
import '../../../games/shared/widgets/active_games_provider.dart';
import '../../../prediction_battle_v1/pb_v1_history_provider.dart';
import '../../../pulse/providers/cross_feature_moments_provider.dart';

/// The three family engagement states used by the Family Space detail
/// screen to drive dynamic content-section ordering.
enum FamilyEngagementState {
  /// Member count < 3. Invite renders first.
  newSmall,

  /// Member count >= 3, no activity in last 7 days. Family Pulse
  /// (Recent Activity) renders first.
  establishedLowActivity,

  /// Member count >= 3, with activity in last 7 days. Prediction
  /// Battle renders first.
  establishedActive,
}

/// The set of content sections the Family Space detail screen renders,
/// in the abstract. The actual widget order is produced by
/// [sectionOrderFor] from this set.
///
/// Note: Invite is intentionally NOT in this enum. The Invite action
/// was moved out of the body feed into the AppBar as a compact icon
/// (next to Settings) to reduce visual clutter on the home screen.
/// The full Invite experience is still available inside the Members
/// section. See `_openInviteFlow` in family_detail_screen.dart.
enum FamilySection {
  /// Thinking of You ring (time-of-day greeting + tappable avatar).
  thinkingOfYou,

  /// Time-sensitive Prediction Battle card (includes its own Coin Pool
  /// progress strip — no separate Coin Pool section needed).
  predictionBattle,

  /// Family Pulse (recent activity + nudges).
  familyPulse,

  /// Cross-feature recent moments (oral history / memory vault / quiz).
  recentMoments,

  /// Premium Insights paywall (locked preview + "Unlock" CTA).
  premiumInsights,
}

/// Provider that derives the family's engagement state from existing
/// providers' data. Watches:
///   - familyDetailProvider(familyId)         → member count + relationship timestamps
///   - pbV1HistoryProvider(familyId)          → recent Prediction Battle rounds
///   - familyActiveGamesProvider(familyId)    → active games' createdAt
///   - crossFeatureMomentsProvider(familyId)  → recent cross-feature moments
///
/// All of these are already fetched by other sections of the Family
/// Space detail screen, so this provider introduces NO new network
/// round-trip. It composes the existing AsyncValues into a single
/// enum.
///
/// Returns [FamilyEngagementState.newSmall] while data is still loading
/// — the safe default for a fresh family. Once any data resolves, the
/// state is recomputed and the screen rebuilds with the correct order.
final familyEngagementStateProvider =
    Provider.family<FamilyEngagementState, String>((ref, familyId) {
  // ── Member count + relationship recency (from familyDetailProvider) ──
  final detailAsync = ref.watch(familyDetailProvider(familyId));
  final detail = detailAsync.valueOrNull;

  // While the family detail is loading, default to newSmall — the
  // safe ordering that promotes Invite (the only action that's always
  // meaningful for a family we know nothing about yet).
  if (detail == null) {
    return FamilyEngagementState.newSmall;
  }

  final activeMembers =
      detail.members.where((p) => p.deletedAt == null).toList();
  final memberCount = activeMembers.length;

  // ── Rule 1: New / small family ──────────────────────────────────────
  if (memberCount < 3) {
    return FamilyEngagementState.newSmall;
  }

  // ── Rule 2 / 3: Established family — check 7-day activity ──────────
  final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));

  // 2a. Any relationship created in the last 7 days?
  for (final rel in detail.relationships) {
    if (rel.createdAt != null && rel.createdAt!.isAfter(sevenDaysAgo)) {
      return FamilyEngagementState.establishedActive;
    }
  }

  // 2b. Any member joined in the last 7 days? (counts as Family Pulse
  //     activity — the pulse feed itself surfaces member joins.)
  for (final member in activeMembers) {
    if (member.createdAt != null && member.createdAt!.isAfter(sevenDaysAgo)) {
      return FamilyEngagementState.establishedActive;
    }
  }

  // 2c. Any Prediction Battle round revealed in the last 7 days?
  //     pbV1HistoryProvider is autoDispose + family — already loaded
  //     for the Family Space's Prediction Battle card.
  final pbHistoryState = ref.watch(pbV1HistoryProvider(familyId));
  final pbHistory = pbHistoryState.history;
  if (pbHistory != null) {
    for (final round in pbHistory.rounds) {
      if (round.revealAt.isAfter(sevenDaysAgo)) {
        return FamilyEngagementState.establishedActive;
      }
    }
  }

  // 2d. Any active game created in the last 7 days?
  final activeGamesAsync = ref.watch(familyActiveGamesProvider(familyId));
  final activeGames = activeGamesAsync.valueOrNull ?? const <ActiveGameInfo>[];
  for (final game in activeGames) {
    final created = DateTime.tryParse(game.createdAt);
    if (created != null && created.isAfter(sevenDaysAgo)) {
      return FamilyEngagementState.establishedActive;
    }
  }

  // 2e. Any cross-feature moment (oral history / memory vault / quiz)
  //     created in the last 7 days?
  final momentsAsync = ref.watch(crossFeatureMomentsProvider(familyId));
  final moments = momentsAsync.valueOrNull ?? const <CrossFeatureMoment>[];
  for (final moment in moments) {
    if (moment.createdAt.isAfter(sevenDaysAgo)) {
      return FamilyEngagementState.establishedActive;
    }
  }

  // No activity in any of the watched sources within the last 7 days.
  return FamilyEngagementState.establishedLowActivity;
});

/// Returns the ordered list of content sections for the Family Space
/// detail screen. This is the SINGLE source of truth for the screen's
/// content order — the screen maps each enum value to its widget and
/// renders them in this order.
///
/// FIXED ORDER (per the invite-UX refinement):
/// The order is no longer dynamic. The full order is:
///
///   1. Prediction Battle — drives interaction (first content card,
///      includes its own Coin Pool progress strip)
///   2. Thinking of You — reinforces family connection (emotional
///      warmth immediately after the engaging PB card)
///   3. Family Pulse — provides updates and activity history
///   4. Premium Insights — paywall, after all free-value content
///   5. Recent Moments — remaining content
///
/// The flow is: PB (engagement) → Thinking of You (emotion) → Pulse
/// (updates) → Insights (premium) → Recent Moments. This creates a
/// better emotional + engagement cadence than the prior PB → Pulse →
/// Insights ordering: the warm "Thinking of You" gesture sits between
/// the high-energy PB card and the informational Pulse feed, so the
/// user experiences interaction → connection → updates rather than
/// interaction → updates → connection.
///
/// INVARIANTS enforced by this function:
///   1. Prediction Battle is ALWAYS first — the most engaging feature
///      earns top placement regardless of family state.
///   2. Thinking of You is ALWAYS second — directly below PB, above
///      Family Pulse.
///   3. Premium Insights renders AFTER Family Pulse (free-value
///      content comes before the paywall).
///   4. No standalone Coin Pool section (the Coin Pool is part of the
///      Prediction Battle card).
///   5. No standalone Family Graph preview card (the Graph is
///      accessible from the hero's flanking Graph icon).
///   6. No standalone Invite section — Invite lives in the AppBar as
///      a compact icon next to Settings, and the full experience is
///      also available inside the Members section.
///
/// The [state] parameter is accepted for API continuity but does not
/// affect the order — the order is fixed. The engagement state is
/// still computed by [familyEngagementStateProvider] for analytics
/// and future use, but the layout is now deterministic.
List<FamilySection> sectionOrderFor(FamilyEngagementState state) {
  // Fixed order — the same for all engagement states.
  return const [
    FamilySection.predictionBattle,
    FamilySection.thinkingOfYou,
    FamilySection.familyPulse,
    FamilySection.premiumInsights,
    FamilySection.recentMoments,
  ];
}

/// Pure helper used by widget tests. Computes the engagement state from
/// the raw inputs without going through Riverpod — lets us test the
/// classification logic in isolation, independent of provider wiring.
@visibleForTesting
FamilyEngagementState classifyEngagementState({
  required int memberCount,
  required Iterable<DateTime> recentActivityTimestamps,
  DateTime? now,
}) {
  final referenceNow = now ?? DateTime.now();

  if (memberCount < 3) {
    return FamilyEngagementState.newSmall;
  }

  final sevenDaysAgo = referenceNow.subtract(const Duration(days: 7));
  for (final ts in recentActivityTimestamps) {
    if (ts.isAfter(sevenDaysAgo)) {
      return FamilyEngagementState.establishedActive;
    }
  }

  return FamilyEngagementState.establishedLowActivity;
}

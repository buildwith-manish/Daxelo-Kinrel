// lib/features/sparq_tray/data/family_sparq_tray_item.dart
//
// DAXELO KINREL — Family Sparq Tray data models.
//
// Pure immutable value types for the Home family row → Family Sparq
// tray. The grouping helpers (`buildPetals`, `countUnseenForFamily`,
// `isSparqLiveForTray`, `isSparqUnseenForTray`) are pure functions
// with no Riverpod or Supabase dependency, so they are unit-tested in
// test/features/sparq_tray/family_sparq_tray_item_test.dart. The
// `Color` type (re-exported from `dart:ui` by material.dart) is the
// same type `SparqModel.moodColor` already returns — both models
// share the Flutter color surface, and the tests run under
// `flutter test` (which initialises the binding).
//
// Naming rule (spec section 0): the word "story" appears nowhere in
// this file or any other new file. The feature is called Sparq.

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/material.dart' show Color;

import '../../../core/family/family_provider.dart' show Family;
import '../../social/data/models/sparq_model.dart'
    show SparqModel, UserSparqGroup;

/// A single petal in the Family Sparq tray's 8-slot Petal ring.
///
/// One petal represents one member (or a Moment Sparq) that currently
/// has a live Sparq for this family. Empty slots are NOT represented
/// here — the painter fills them with kolam dots. Up to 8 petals per
/// ring (most recent first).
@immutable
class PetalSpec {
  const PetalSpec({
    required this.color,
    required this.intensity,
    required this.seen,
    required this.isCapsule,
    required this.isMoment,
    this.userId,
  }) : assert(
          intensity == 'calm' || intensity == 'warm' || intensity == 'fire',
          'intensity must be calm|warm|fire, got "$intensity"',
        );

  /// Mood color of this member's most recent live Sparq. For a Moment
  /// Sparq this is gold (#D4AF37).
  final Color color;

  /// Intensity of the underlying Sparq — drives the glow strength of
  /// the petal (calm = none, warm = soft, fire = strong + breathing).
  final String intensity;

  /// Whether the viewer has already seen this Sparq. Seen petals are
  /// drawn as outline-only (35% alpha, 1.5dp stroke) — the difference
  /// between unseen and seen must be in FILL not only color, for
  /// color-blind accessibility.
  final bool seen;

  /// Whether this petal is an unrevealed Time Capsule. Drawn as a
  /// dashed outline with a tiny lock glyph. Never counts as "new".
  final bool isCapsule;

  /// Whether this petal is the Moment Sparq for this family. Drawn
  /// at slot 0 in gold. Moment Sparqs are local-only and their seen
  /// state is persisted in SharedPreferences (not server views).
  final bool isMoment;

  /// The Kinrel user id this petal represents. Used by the run screen
  /// to know which user to play first. Null for a Moment petal.
  final String? userId;

  /// Whether the petal counts toward the family's "new" unread badge.
  /// Time capsules (unrevealed) and seen Sparqs do NOT count.
  bool get countsAsUnseen => !seen && !isCapsule;

  PetalSpec copyWith({
    Color? color,
    String? intensity,
    bool? seen,
    bool? isCapsule,
    bool? isMoment,
    String? userId,
  }) =>
      PetalSpec(
        color: color ?? this.color,
        intensity: intensity ?? this.intensity,
        seen: seen ?? this.seen,
        isCapsule: isCapsule ?? this.isCapsule,
        isMoment: isMoment ?? this.isMoment,
        userId: userId ?? this.userId,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PetalSpec &&
          other.color == color &&
          other.intensity == intensity &&
          other.seen == seen &&
          other.isCapsule == isCapsule &&
          other.isMoment == isMoment &&
          other.userId == userId;

  @override
  int get hashCode => Object.hash(
        color,
        intensity,
        seen,
        isCapsule,
        isMoment,
        userId,
      );
}

/// A Moment Sparq card to play at the head of a family's run.
///
/// Moment Sparqs are client-generated (no server row, no view count).
/// Sources, in priority order: birthday today (or within 3 days),
/// anniversary today, festival today, "on this day" memory.
@immutable
class MomentSparq {
  const MomentSparq({
    required this.id,
    required this.familyId,
    required this.headline,
    required this.relationLine,
    required this.eventType,
    required this.date,
    this.subtitle,
    this.deepLink,
  });

  /// Stable id for seen-state persistence (see
  /// `sparq_moment_seen_{id}_{yyyyMMdd}` in SharedPreferences).
  final String id;

  /// The family this Moment belongs to.
  final String familyId;

  /// Large headline shown above the action button, e.g.
  /// "Dadi turns 78 today".
  final String headline;

  /// Relation line from the viewer's perspective, e.g.
  /// "Your Dadi · Papa's mother". Empty when no relation could be
  /// resolved (the Moment Sparq still shows but without the relation
  /// line).
  final String relationLine;

  /// Event type — drives quick-reply copy ("Pranam", "Happy birthday",
  /// "Voice blessing" are birthday/anniversary-flavored; festivals
  /// reuse the same set with adapted copy).
  final MomentEventType eventType;

  /// Calendar date this Moment refers to (used for the seen-state
  /// key suffix `yyyyMMdd` so a Moment becomes "unseen" again the
  /// next day).
  final DateTime date;

  /// Optional subtitle (e.g. the person's photo URL hint).
  final String? subtitle;

  /// Optional deep link for the primary CTA.
  final String? deepLink;

  /// SharedPreferences key suffix for the seen flag.
  String get seenKeySuffix {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '${id}_$y$m$d';
  }
}

/// Event type for a Moment Sparq — drives quick-reply copy.
enum MomentEventType {
  birthday,
  anniversary,
  festival,
  onThisDay,
}

/// A single family's row in the Family Sparq tray.
///
/// Built by [familySparqTrayProvider] for each family the viewer
/// belongs to. The tray widget reads this to render the Petal ring,
/// the family name + status line, and to know what to do on tap.
@immutable
class FamilySparqTrayItem {
  const FamilySparqTrayItem({
    required this.family,
    required this.memberGroups,
    required this.moment,
    required this.unseenCount,
    required this.hasLive,
    required this.allSeen,
    required this.petals,
  });

  /// The family this row represents.
  final Family family;

  /// All of this family's members who currently have live Sparqs in
  /// the feed, as `UserSparqGroup`s (already joined to this family).
  /// The viewer's own group is NEVER here — they see themselves only
  /// in the "Your Sparq" entry.
  final List<UserSparqGroup> memberGroups;

  /// The Moment Sparq for this family for today, if any. Local-only.
  final MomentSparq? moment;

  /// Count of unseen Sparqs across all member groups (time-capsule
  /// and seen Sparqs excluded). Drives the "{n} new" label.
  final int unseenCount;

  /// Whether the family has ANY live Sparqs to play (members or
  /// Moment). Tapping opens `/sparq/family/:id` when true, else
  /// `/family/:id`.
  final bool hasLive;

  /// Whether every member Sparq in this family has been seen by the
  /// viewer. Drives the family-name styling (semibold when there are
  /// unseen Sparqs, muted otherwise).
  final bool allSeen;

  /// The 8-slot petal ring specs, ordered: Moment petal first (slot 0
  /// when present), then unseen member petals (most recent first),
  /// then seen member petals, capped at 8. The painter fills the
  /// remaining slots with kolam dots.
  final List<PetalSpec> petals;

  /// Number of members beyond the 8 petals shown — used to render
  /// the "+N" hint in the second label line.
  int get overflowCount =>
      memberGroups.length > 8 ? memberGroups.length - 8 : 0;

  FamilySparqTrayItem copyWith({
    Family? family,
    List<UserSparqGroup>? memberGroups,
    MomentSparq? moment,
    int? unseenCount,
    bool? hasLive,
    bool? allSeen,
    List<PetalSpec>? petals,
  }) =>
      FamilySparqTrayItem(
        family: family ?? this.family,
        memberGroups: memberGroups ?? this.memberGroups,
        moment: moment ?? this.moment,
        unseenCount: unseenCount ?? this.unseenCount,
        hasLive: hasLive ?? this.hasLive,
        allSeen: allSeen ?? this.allSeen,
        petals: petals ?? this.petals,
      );
}

// ── Pure grouping helpers (unit-testable, no Riverpod) ────────────────
//
// Kept in this file (next to the models) so the unit tests in
// test/features/sparq_tray/family_sparq_tray_item_test.dart can import
// them without touching a Riverpod ProviderContainer.

/// Drops Sparqs that should NOT appear in a family's tray ring:
///   • expired (SparqModel.isExpired)
///   • unrevealed Time Capsules (`isTimeCapsule && !isRevealed`)
///     — they live as a dashed-outline petal but never as a "new"
///     Sparq that contributes to unseenCount.
bool isSparqLiveForTray(SparqModel s) {
  if (s.isExpired) return false;
  if (s.isTimeCapsule && !s.isRevealed) return false;
  return true;
}

/// Whether a Sparq should count toward a member's "unseen" total.
/// Locked time capsules are never "new". Expired ones already
/// dropped upstream.
bool isSparqUnseenForTray(SparqModel s, bool isSeenLocally) {
  if (s.isTimeCapsule && !s.isRevealed) return false;
  return !isSeenLocally;
}

/// Build a sorted [PetalSpec] list for one family.
///
/// Contract (spec section 5, point 6):
///   1. Moment petal at slot 0 when one applies (gold, full color).
///   2. Unseen member petals (most recent first).
///   3. Seen member petals (most recent first).
///   4. Cap at [maxSlots] (default 8).
///
/// [memberGroupForUser] returns the [UserSparqGroup] for a given
/// userId, or null when no Sparqs exist for that user (in which case
/// the member is silently skipped — they don't get a petal).
///
/// [isSeen] returns whether the viewer has seen a given Sparq id
/// (used by the SparqState-local `_viewedSparqIds` set).
///
/// [excludeUserId] is the viewer's own user id — they appear in the
/// "Your Sparq" entry only, never in a family ring.
List<PetalSpec> buildPetals({
  required List<UserSparqGroup> feed,
  required Iterable<String> memberUserIds,
  required MomentSparq? moment,
  required bool Function(String sparqId) isSeen,
  String? excludeUserId,
  int maxSlots = 8,
}) {
  final seenMemberUserIds = <String>{...memberUserIds}
    ..removeWhere((id) => excludeUserId != null && id == excludeUserId);

  // Resolve each member to their latest LIVE Sparq (most recent first
  // across the group; we sort by createdAt descending afterwards).
  final latestPerMember = <_MemberLatest>[];
  for (final group in feed) {
    if (!seenMemberUserIds.contains(group.userId)) continue;
    SparqModel? latest;
    for (final s in group.sparqs) {
      if (!isSparqLiveForTray(s)) continue;
      if (latest == null || s.createdAt.isAfter(latest.createdAt)) {
        latest = s;
      }
    }
    if (latest == null) continue;
    latestPerMember.add(_MemberLatest(group.userId, latest));
  }
  latestPerMember.sort((a, b) => b.latest.createdAt.compareTo(a.latest.createdAt));

  final momentPetal = moment == null
      ? null
      : const PetalSpec(
          color: Color(0xFFD4AF37),
          intensity: 'warm',
          seen: false,
          isCapsule: false,
          isMoment: true,
          userId: null,
        );

  // Split member petals into unseen / seen (preserving the recency
  // sort within each bucket).
  final unseen = <PetalSpec>[];
  final seen = <PetalSpec>[];
  for (final entry in latestPerMember) {
    final seenLocally = isSeen(entry.latest.id);
    final petal = PetalSpec(
      color: entry.latest.moodColor,
      intensity: entry.latest.intensity,
      seen: seenLocally,
      isCapsule: false,
      isMoment: false,
      userId: entry.userId,
    );
    if (petal.countsAsUnseen) {
      unseen.add(petal);
    } else {
      seen.add(petal);
    }
  }

  final out = <PetalSpec>[];
  if (momentPetal != null) out.add(momentPetal);
  out.addAll(unseen);
  out.addAll(seen);
  if (out.length > maxSlots) {
    out.removeRange(maxSlots, out.length);
  }
  return out;
}

/// Tiny carrier for "user id + their latest live Sparq" used by
/// [buildPetals]. Private — only lives in this file.
class _MemberLatest {
  const _MemberLatest(this.userId, this.latest);
  final String userId;
  final SparqModel latest;
}

/// Count unseen Sparqs across a family's member groups (Moment Sparq
/// excluded — it's local-only and tracked separately).
///
/// Honours `isSparqUnseenForTray`: locked time capsules don't count,
/// and the [isSeen] gate excludes Sparqs the viewer has already seen
/// (locally-tracked in `SparqState._viewedSparqIds`).
int countUnseenForFamily({
  required List<UserSparqGroup> memberGroups,
  required bool Function(String sparqId) isSeen,
}) {
  var n = 0;
  for (final g in memberGroups) {
    for (final s in g.sparqs) {
      if (!isSparqLiveForTray(s)) continue;
      if (isSparqUnseenForTray(s, isSeen(s.id))) n++;
    }
  }
  return n;
}

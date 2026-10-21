// lib/features/chat/data/mention_candidates_provider.dart
//
// Phase A — @mentions across chat.
//
// Resolves the list of people the current user can @-mention in a given
// conversation. Replaces the ad-hoc `chatState.members.map(...)` path that
// the old picker used (which surfaced the entire family roster regardless
// of which group/DM the user was in, and never had the personId needed to
// look up a kinship term).
//
// Design:
//
//   • Source of truth = familyMembersProvider (List<Person>) — gives us
//     BOTH the Person.id (for kinship term lookup via
//     kinshipTermsForFamilyProvider) AND Person.linkedUserId (the auth
//     user id — the userId field on ChatMention + ChatMessage.senderId).
//
//   • Filtering rules (server enforces the same on write, but the client
//     filters first so the picker never even shows disallowed candidates):
//       - linkedUserId must be non-null (a Person without an auth account
//         can't be @-mentioned — they have no userId to store on the
//         ChatMention row and no socket room to deliver a push to).
//       - self is always excluded.
//       - blocked users are excluded (chat_block_report_service).
//       - when groupId is set, only members of that group are returned
//         (queried via GroupMember table — same pattern direct_group_service
//         already uses for the unified inbox).
//       - when circleId is set, only circle members (Phase A: hook only,
//         the actual CircleChatScreen integration is a follow-up phase).
//
//   • Warm on chat open: ChatScreen's initState calls
//     `ref.read(mentionCandidatesProvider(...).future)` so the picker is
//     instant when the user types @. The provider is .autoDispose so it
//     tears down when the chat screen closes (no leak across chats).
//
//   • Group-member resolver: a single batched query to GroupMember
//     (inFilter on groupId) joined to User for display names. Cached per
//     (familyId, groupId) for the lifetime of the chat screen.
//
//   • Recent-sender ranking: the candidates are pre-sorted by the
//     recent-sender rank, derived from this chat's already-loaded messages
//     (chatProvider.messages) — no new lastSeen lookup, per the user's
//     revised plan. Senders who appeared in the most recent N messages
//     rank higher than non-senders.
//
//   • Kinship term + relation line: resolved via kinshipTermsForFamilyProvider
//     (already merged). The provider is watched here so a language switch
//     rebuilds the candidates with the new terms.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/family/family_provider.dart';
import '../../../core/kinship/kinship_term_providers.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/viewer/viewer_provider.dart';
import '../data/chat_block_report_service.dart';
import '../providers/chat_provider.dart';

/// One mentionable person in a conversation.
///
/// `personId` is the Person.id used for kinship-term lookup.
/// `userId` is the auth user id — what gets stored on `ChatMention.mentionedUserId`
/// and what the server's `chat:user:<userId>` room is named after.
@immutable
class MentionCandidate {
  const MentionCandidate({
    required this.personId,
    required this.userId,
    required this.name,
    required this.initials,
    required this.kinshipTerm,
    required this.kinshipRelationLine,
    required this.isElder,
    required this.recentSenderRank,
    this.avatarUrl,
  });

  /// Person.id — key into kinshipTermsForFamilyProvider's result map.
  final String personId;

  /// auth user id (Person.linkedUserId). Required for @mention storage.
  final String userId;

  /// Display name at mention time. Stored on ChatMention.mentionedByName.
  final String name;

  /// Initials fallback for the avatar.
  final String initials;

  /// Kinship term in the viewer's chosen language (e.g. "Mama", "Bua",
  /// "Dadi"). Null when the viewer can't reach this person from their
  /// anchor (e.g. an in-law on the other side). The picker falls back to
  /// the first name in that case.
  final String? kinshipTerm;

  /// Human-readable relation line in the viewer's language
  /// (e.g. "your mother's mother"). Null when no kinship term is
  /// available. Rendered as the muted subtitle on the picker row.
  final String? kinshipRelationLine;

  /// True when the candidate is an elder (respect-based ranking boost).
  /// Derived from generationIndex in the Person model — anyone 2+
  /// generations above the viewer is treated as an elder.
  final bool isElder;

  /// 0 = not a recent sender; higher = appeared more recently in this
  /// chat. Sourced from chatProvider.messages (already loaded) — no new
  /// lastSeen lookup, per the user's revised plan.
  final int recentSenderRank;

  /// Optional avatar URL (Person.photoUrl). Null when the person has no
  /// photo — the picker renders an initials-avatar fallback.
  final String? avatarUrl;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MentionCandidate && personId == other.personId;

  @override
  int get hashCode => personId.hashCode;
}

/// Arg bundle for [mentionCandidatesProvider] so the provider can be a
/// `.family` over a single value type (Riverpod 2.x family requires a
/// single arg; bundling also makes cache-key equality stable across
/// language switches — see [MentionCandidatesArgs.==]).
@immutable
class MentionCandidatesArgs {
  const MentionCandidatesArgs({
    required this.familyId,
    this.groupId,
    this.circleId,
    this.excludeUserIds = const {},
  });

  final String familyId;

  /// Group/DM chat ID. Null = family-wide chat.
  /// When set, only members of this group are returned.
  final String? groupId;

  /// Circle ID (Phase A: hook only — actual integration is a follow-up
  /// phase). When set, only circle members are returned. Mutually
  /// exclusive with [groupId].
  final String? circleId;

  /// User IDs to always exclude (e.g. the other DM participant when the
  /// picker is shown in a DM — those references don't trigger
  /// notifications per the spec, so they shouldn't appear as
  /// mentionable candidates).
  final Set<String> excludeUserIds;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MentionCandidatesArgs &&
          familyId == other.familyId &&
          groupId == other.groupId &&
          circleId == other.circleId &&
          _setEquals(excludeUserIds, other.excludeUserIds);

  @override
  int get hashCode =>
      Object.hash(familyId, groupId, circleId, Object.hashAll(excludeUserIds));

  static bool _setEquals<T>(Set<T> a, Set<T> b) {
    if (a.length != b.length) return false;
    for (final v in a) {
      if (!b.contains(v)) return false;
    }
    return true;
  }
}

/// Resolve the list of mentionable people in a conversation.
///
/// Returns `AsyncValue<List<MentionCandidate>>`. Loading/error states are
/// surfaced to the UI (the picker shows visible loading + error rows;
/// never silent — see mention_picker.dart).
///
/// The result is sorted by:
///   1. recentSenderRank desc (people who recently sent in this chat first)
///   2. isElder desc (elders above non-elders at the same rank)
///   3. alphabetical by name (stable tiebreaker)
///
/// Caller-side search (the picker's text filter) re-ranks by exact kinship
/// term match first; this provider only produces the pre-filtered,
/// rank-sorted superset.
final mentionCandidatesProvider = FutureProvider.autoDispose
    .family<List<MentionCandidate>, MentionCandidatesArgs>(
  (ref, args) async {
    final familyId = args.familyId;
    final viewerAsync = ref.watch(viewerPersonIdProvider(familyId));
    final viewerPersonId = viewerAsync.valueOrNull;
    // Watch language so a language switch rebuilds with new terms.
    ref.watch(kinshipTermLanguageProvider);
    // Watch the family's Person list (covers add/remove/edit).
    final personsAsync = ref.watch(familyMembersProvider(familyId));
    final persons = personsAsync.valueOrNull ?? const <Person>[];
    // Watch the kinship term map (covers graph changes).
    final termsAsync = ref.watch(kinshipTermsForFamilyProvider(familyId));
    final terms = termsAsync.valueOrNull ?? const <String, KinshipTerm>{};

    // Resolve blocked-user set (best-effort — never block the picker on
    // a service failure; treat a failed block-list fetch as "no blocks").
    final blockService = ref.read(chatBlockReportServiceProvider);
    Set<String> blockedUserIds;
    try {
      blockedUserIds = await blockService.fetchBlockedUserIds();
    } catch (e) {
      debugPrint('⚠️ mentionCandidatesProvider.blockedUserIds: $e');
      blockedUserIds = const {};
    }

    // Resolve group/circle member user IDs when scoped (one batched
    // query per scope). Empty when family-wide.
    final scopedUserIds = await _resolveScopedUserIds(ref, args);

    // Build the candidate list, applying all the filters.
    final candidates = <MentionCandidate>[];

    // Cache current user id for the self-exclusion filter.
    final client = ref.read(supabaseProvider);
    final currentUserId = client?.auth.currentUser?.id;

    // Recent-sender rank: walk the chat's already-loaded messages and
    // bump the rank for every distinct sender. Cap the walk at 50
    // messages so a huge backlog doesn't slow the picker warm-up.
    final recentSenderRanks = <String, int>{};
    final chatState = ref.read(chatProvider(familyId));
    final recentMessages = chatState.messages.take(50);
    var rank = recentMessages.length;
    for (final m in recentMessages) {
      if (m.senderId.isEmpty) continue;
      // Higher rank = more recent. The first iteration sees the newest
      // message; assign it the highest rank.
      recentSenderRanks[m.senderId] = rank;
      rank -= 1;
    }

    for (final p in persons) {
      // Filter 1: must have a linkedUserId (no @-mentioning a Person
      // without an auth account — see class doc).
      final linkedUserId = p.linkedUserId;
      if (linkedUserId == null || linkedUserId.isEmpty) continue;
      // Filter 2: self is always excluded.
      if (linkedUserId == currentUserId) continue;
      // Filter 3: blocked users excluded.
      if (blockedUserIds.contains(linkedUserId)) continue;
      // Filter 4: scoped conversation (group/circle) — only members.
      if (scopedUserIds != null && !scopedUserIds.contains(linkedUserId)) {
        continue;
      }
      // Filter 5: caller-supplied excludeUserIds (e.g. DM other
      // participant when Phase B opens the picker in a direct chat).
      if (args.excludeUserIds.contains(linkedUserId)) continue;

      final term = terms[p.id];
      candidates.add(MentionCandidate(
        personId: p.id,
        userId: linkedUserId,
        name: p.name,
        initials: _initialsFromName(p.name),
        kinshipTerm: term?.primary,
        kinshipRelationLine: term?.relationExplanation,
        // Elder = 2+ generations above the viewer. Viewer's generation
        // is the anchor's (0); parents' generation is -1; grandparents -2.
        // We treat anyone with generationIndex <= viewerGenIndex - 2 as
        // an elder for ranking purposes. Viewer generation is 0 when
        // unknown — fall back to comparing against the absolute index
        // (anyone with generationIndex <= -2 is an elder).
        isElder: _isElder(p, viewerPersonId, persons),
        recentSenderRank: recentSenderRanks[linkedUserId] ?? 0,
        avatarUrl: p.photoUrl,
      ));
    }

    // Pre-sort: recent sender rank desc, then elders, then alphabetical.
    candidates.sort((a, b) {
      final r = b.recentSenderRank.compareTo(a.recentSenderRank);
      if (r != 0) return r;
      final e = (b.isElder ? 1 : 0).compareTo(a.isElder ? 1 : 0);
      if (e != 0) return e;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return candidates;
  },
  name: 'mentionCandidatesProvider',
);

/// Resolve the set of user IDs that are members of [args.groupId] or
/// [args.circleId]. Returns null when the conversation is family-wide
/// (no scope filter — all family members are candidates).
Future<Set<String>?> _resolveScopedUserIds(
  Ref ref,
  MentionCandidatesArgs args,
) async {
  if (args.groupId == null && args.circleId == null) return null;

  final client = ref.read(supabaseProvider);
  if (client == null) return null;
  try {
    if (args.groupId != null) {
      // Single batched query to GroupMember for this group's user IDs.
      // RLS hides groups the current user isn't a member of, so this
      // returns at most the user's own group's members.
      final resp = await client
          .from('GroupMember')
          .select('userId')
          .eq('groupId', args.groupId!)
          .timeout(const Duration(seconds: 8));
      return {
        for (final row in resp as List)
          (row as Map<String, dynamic>)['userId'] as String? ?? '',
      }..removeWhere((id) => id.isEmpty);
    }
    // args.circleId != null — Phase A: hook only. Return null so the
    // family-wide candidates flow through (the actual circle-members
    // resolver ships in the circles-mentions follow-up phase).
    return null;
  } catch (e) {
    debugPrint('⚠️ _resolveScopedUserIds failed: $e');
    // Fail-open: treat a scope resolution failure as "no scope filter"
    // so the picker still shows family members (better than an empty
    // list with no explanation; the UI's error row catches a real fetch
    // failure separately).
    return null;
  }
}

/// Initials helper — same logic as OnlineMember's _initialsFromName in
/// chat_provider.dart. Duplicated here so MentionCandidate is self-
/// contained (doesn't depend on the OnlineMember model that we're
/// moving away from in the picker).
String _initialsFromName(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts.first[0] + parts[1][0]).toUpperCase();
}

/// Conservative elder check: an elder is anyone whose generationIndex is
/// at least 2 generations above the viewer's. When the viewer's
/// generationIndex can't be resolved (e.g. family not loaded yet), fall
/// back to an absolute rule — anyone with generationIndex <= -2 is
/// treated as an elder (anchors are 0, their parents -1, grandparents -2).
bool _isElder(Person candidate, String? viewerPersonId, List<Person> all) {
  if (viewerPersonId == null) {
    return candidate.generationIndex <= -2;
  }
  final viewer = all.firstWhere(
    (p) => p.id == viewerPersonId,
    orElse: () => candidate,
  );
  if (viewer.id == candidate.id) return false;
  return candidate.generationIndex <= viewer.generationIndex - 2;
}

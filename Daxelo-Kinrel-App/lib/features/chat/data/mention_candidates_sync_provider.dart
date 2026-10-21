// lib/features/chat/data/mention_candidates_sync_provider.dart
//
// Phase A+B follow-up — instant @mention picker (no loading state).
//
// Replaces the async mentionCandidatesProvider with a SYNCHRONOUS
// keep-alive provider that builds the candidate list from whatever
// data is already in memory. The picker never shows a spinner, never
// shows "Loading…", and never waits for the network.
//
// Key design decisions (per the user's spec):
//   • Keep-alive (not autoDispose): the candidate list persists
//     across chat screen open/close cycles, so it's warm when the
//     user opens a chat and types @.
//   • Synchronous (Provider, not FutureProvider): the value is
//     computed from familyMembersProvider.valueOrNull +
//     kinshipTermsForFamilyProvider.valueOrNull. If those upstream
//     providers haven't loaded yet, the list is empty (the overlay
//     stays hidden — no spinner). When they resolve, the list
//     updates + the overlay shows.
//   • Blocked-user set + group-member set: cached in background via
//     keep-alive FutureProvider.family. The first read returns
//     whatever is cached (empty set = filter nothing for blocked;
//     null = filter nothing for group). Failures are silent — the
//     list keeps the last known state.
//   • Recent-sender rank: read as a SNAPSHOT via ref.read (not
//     ref.watch) so the list does NOT rebuild when new messages
//     arrive (only when family members / viewer / language change).

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/family/family_provider.dart';
import '../../../core/kinship/kinship_term_providers.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/viewer/viewer_provider.dart';
import '../data/chat_block_report_service.dart';
import '../data/mention_candidates_provider.dart' show MentionCandidate, MentionCandidatesArgs;
import '../providers/chat_provider.dart';

// ═══════════════════════════════════════════════════════════════════════
// Background caches (keep-alive FutureProvider.family — refreshed in
// background, never on the critical path).
// ═══════════════════════════════════════════════════════════════════════

/// Cached blocked-user set per family. Refreshed in the background.
/// First read returns empty set (filter nothing). Failures are silent
/// — the list keeps the last known state.
///
/// NOT autoDispose: the cache persists across chat screen open/close
/// cycles so it's warm when the user opens a chat and types @.
final mentionBlockedUsersProvider =
    FutureProvider.family<Set<String>, String>(
  (ref, familyId) async {
    try {
      final blockService = ref.read(chatBlockReportServiceProvider);
      return await blockService.fetchBlockedUserIds();
    } catch (e) {
      debugPrint('⚠️ mentionBlockedUsersProvider: $e (returning empty set)');
      return const <String>{};
    }
  },
  name: 'mentionBlockedUsersProvider',
);

/// Cached group-member set per group. Refreshed in the background with
/// a 2s timeout. First read returns null (filter nothing — show all
/// family members). Failures are silent.
///
/// NOT autoDispose: persists across chat screen open/close cycles.
final mentionGroupMembersProvider =
    FutureProvider.family<Set<String>?, String>(
  (ref, groupId) async {
    try {
      final client = ref.read(supabaseProvider);
      if (client == null) return null;
      final resp = await client
          .from('GroupMember')
          .select('userId')
          .eq('groupId', groupId)
          .timeout(const Duration(seconds: 2));
      return {
        for (final row in resp as List)
          (row as Map<String, dynamic>)['userId'] as String? ?? '',
      }..removeWhere((id) => id.isEmpty);
    } catch (e) {
      debugPrint('⚠️ mentionGroupMembersProvider: $e (returning null = filter nothing)');
      return null;
    }
  },
  name: 'mentionGroupMembersProvider',
);

// ═══════════════════════════════════════════════════════════════════════
// Synchronous candidate list (keep-alive Provider.family — never
// awaits network).
// ═══════════════════════════════════════════════════════════════════════

/// The mentionable candidates for a conversation, computed
/// SYNCHRONOUSLY from whatever data is already in memory.
///
/// Returns a plain `List<MentionCandidate>` (never AsyncValue). If
/// the upstream data (familyMembersProvider, kinshipTermsForFamilyProvider)
/// hasn't loaded yet, the list is empty (the overlay stays hidden —
/// no spinner). When the data resolves, the list updates + the
/// overlay shows on the next frame.
///
/// The blocked-user set + group-member set are read from the
/// background-cache providers. If those caches haven't resolved yet,
/// the list shows ALL family members (filter nothing) — the user
/// sees candidates immediately, and blocked/non-group members are
/// silently filtered out when the cache resolves.
///
/// Invalidated when: family members, the viewer, or the language
/// change. NEVER when a chat message arrives (the recent-sender
/// rank is a snapshot via ref.read, not ref.watch).
final mentionCandidatesSyncProvider =
    Provider.family<List<MentionCandidate>, MentionCandidatesArgs>(
  (ref, args) {
    final familyId = args.familyId;

    // Watch family members (in-memory if loaded). This is the ONLY
    // upstream that causes the list to be empty on first open —
    // once it resolves, the picker shows.
    final personsAsync = ref.watch(familyMembersProvider(familyId));
    final persons = personsAsync.valueOrNull ?? const <Person>[];

    // Watch kinship terms (in-memory if loaded). Fill in when
    // available; never wait. Candidates without terms still show
    // (with name only — the kinship term + relation line are null).
    final termsAsync = ref.watch(kinshipTermsForFamilyProvider(familyId));
    final terms = termsAsync.valueOrNull ?? const <String, KinshipTerm>{};

    // Watch language so a language switch rebuilds with new terms.
    ref.watch(kinshipTermLanguageProvider);

    // Read viewer (snapshot, not watched — the viewer rarely changes
    // during a chat session; when it does, familyMembersProvider
    // rebuilds which triggers this provider to rebuild too).
    final viewerPersonId = ref.read(viewerPersonIdProvider(familyId)).valueOrNull;

    // Read blocked-user set from the background cache. valueOrNull
    // returns null if the cache hasn't resolved — in that case,
    // filter nothing (show all family members). When the cache
    // resolves, this provider rebuilds + blocked users are filtered.
    final blockedAsync = ref.watch(mentionBlockedUsersProvider(familyId));
    final blockedUserIds = blockedAsync.valueOrNull ?? const <String>{};

    // Read group-member set from the background cache (when scoped).
    // valueOrNull returns null if the cache hasn't resolved — filter
    // nothing. When it resolves, non-group members are filtered.
    Set<String>? scopedUserIds;
    if (args.groupId != null) {
      final groupAsync =
          ref.watch(mentionGroupMembersProvider(args.groupId!));
      scopedUserIds = groupAsync.valueOrNull;
    }

    // Cache current user id for the self-exclusion filter.
    final client = ref.read(supabaseProvider);
    final currentUserId = client?.auth.currentUser?.id;

    // Recent-sender rank: SNAPSHOT via ref.read (not ref.watch) so
    // the list does NOT rebuild when new messages arrive. This is
    // per the user's spec: "Invalidate the keep-alive list only when
    // family members, the viewer or the language change. Never
    // because a chat message arrived."
    final recentSenderRanks = <String, int>{};
    final chatState = ref.read(chatProvider(familyId));
    final recentMessages = chatState.messages.take(50);
    var rank = recentMessages.length;
    for (final m in recentMessages) {
      if (m.senderId.isEmpty) continue;
      recentSenderRanks[m.senderId] = rank;
      rank -= 1;
    }

    // Build candidates synchronously.
    final candidates = <MentionCandidate>[];
    for (final p in persons) {
      final linkedUserId = p.linkedUserId;
      if (linkedUserId == null || linkedUserId.isEmpty) continue;
      if (linkedUserId == currentUserId) continue;
      if (blockedUserIds.contains(linkedUserId)) continue;
      if (args.excludeUserIds.contains(linkedUserId)) continue;
      if (scopedUserIds != null && !scopedUserIds.contains(linkedUserId)) {
        continue;
      }

      final term = terms[p.id];
      candidates.add(MentionCandidate(
        personId: p.id,
        userId: linkedUserId,
        name: p.name,
        initials: _initialsFromName(p.name),
        kinshipTerm: term?.primary,
        kinshipRelationLine: term?.relationExplanation,
        isElder: _isElder(p, viewerPersonId, persons),
        recentSenderRank: recentSenderRanks[linkedUserId] ?? 0,
        avatarUrl: p.photoUrl,
      ));
    }

    // Pre-sort: recent sender rank desc, then elders, then
    // alphabetical. The picker's search index re-ranks by kinship
    // term match on top of this ordering.
    candidates.sort((a, b) {
      final r = b.recentSenderRank.compareTo(a.recentSenderRank);
      if (r != 0) return r;
      final e = (b.isElder ? 1 : 0).compareTo(a.isElder ? 1 : 0);
      if (e != 0) return e;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return candidates;
  },
  name: 'mentionCandidatesSyncProvider',
);

/// Initials helper — same logic as the old mentionCandidatesProvider.
String _initialsFromName(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts.first[0] + parts[1][0]).toUpperCase();
}

/// Conservative elder check: an elder is anyone whose generationIndex
/// is at least 2 generations above the viewer's. When the viewer's
/// generationIndex can't be resolved, fall back to an absolute rule
/// — anyone with generationIndex <= -2 is treated as an elder.
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

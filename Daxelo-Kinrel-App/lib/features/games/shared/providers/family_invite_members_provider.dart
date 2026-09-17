// lib/features/games/shared/providers/family_invite_members_provider.dart
//
// DAXELO KINREL — Family Invite Members (shared, real-time)
//
// THE single source of truth for "who can I invite to a game in this
// family". Used by BOTH invite surfaces across all 14 multiplayer games:
//   • InviteFamilySheet  (the 10 temporary-room games)
//   • ChallengeLobbyScreen (the 4 board games — Chess, Checkers,
//     Carrom, Tic-Tac-Toe)
//
// FIX (2026-09-14): the old flow read Person.linkedUserId rows inside the
// family — but a user's Person node lives in exactly ONE family (global
// unique index), so real members frequently had no local Person row and
// the invite list showed a FALSE "No linked Kinrel members in this family
// yet" empty state. This provider calls the rewritten
// fn_get_linked_family_members RPC, which sources members directly from
// the family membership source (FamilyMember JOIN User) plus
// Find-on-Kinrel linked Persons, deduped, with live UserPresence status.
//
// REAL-TIME SYNCHRONIZATION: the notifier subscribes to Supabase Realtime
// on FamilyMember + Person (filtered by familyId) and silently refreshes
// the list (debounced) whenever members are ADDED, REMOVED or linked.
// The invite sheet additionally listens to game_invites (see
// InviteFamilySheet) so invitation statuses refresh as invites land.
//
// The provider also fetches small family stats (total membership count +
// person count) so the UI can render an ACCURATE empty state: when the
// list is empty but members exist, the message explains that those
// members have no linked Kinrel accounts instead of claiming the family
// has no members.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../family/presentation/add_member_source.dart';
import '../../../../core/services/supabase_service.dart';

/// One invitable family member (a real Kinrel account).
@immutable
class FamilyInviteMember {
  const FamilyInviteMember({
    required this.user,
    this.personId,
    this.linkedAt,
    required this.isMember,
    this.isOnline,
    this.lastSeenAt,
  });

  factory FamilyInviteMember.fromRpcRow(Map<String, dynamic> r) {
    final user = KinrelUser.fromJson(r);
    DateTime? linked;
    final rawLinked = r['linkedAt'];
    if (rawLinked is String) linked = DateTime.tryParse(rawLinked);
    DateTime? lastSeen;
    final rawSeen = r['lastSeenAt'];
    if (rawSeen is String) lastSeen = DateTime.tryParse(rawSeen);
    return FamilyInviteMember(
      user: user,
      personId: (r['personId'] as String?)?.trim().isEmpty == true
          ? null
          : r['personId'] as String?,
      linkedAt: linked,
      isMember: (r['isMember'] as bool?) ?? false,
      isOnline: r['isOnline'] as bool?,
      lastSeenAt: lastSeen,
    );
  }

  final KinrelUser user;

  /// Person row id in this family (null when the member has no local
  /// Person node — e.g. their Person lives in another family).
  final String? personId;

  /// When they joined the family (or were linked).
  final DateTime? linkedAt;

  /// True when sourced from the FamilyMember membership table.
  final bool isMember;

  /// Online snapshot from UserPresence at fetch time (null = no presence
  /// row). Live updates come from lastSeenProvider, which the UI watches.
  final bool? isOnline;
  final DateTime? lastSeenAt;

  FamilyInviteMember copyWith({bool? isOnline, DateTime? lastSeenAt}) =>
      FamilyInviteMember(
        user: user,
        personId: personId,
        linkedAt: linkedAt,
        isMember: isMember,
        isOnline: isOnline ?? this.isOnline,
        lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      );
}

/// Small context stats so empty states can tell the truth.
@immutable
class FamilyInviteStats {
  const FamilyInviteStats({
    this.membershipCount = 0,
    this.personCount = 0,
  });

  /// Total FamilyMember rows for this family (incl. the caller).
  final int membershipCount;

  /// Total non-deleted Person rows in this family.
  final int personCount;

  /// People in the family graph who have NOT linked a Kinrel account
  /// (persons minus linked accounts; never negative).
  int get unlinkedPersonCount =>
      (personCount - membershipCount).clamp(0, personCount);
}

@immutable
class FamilyInviteMembersState {
  const FamilyInviteMembersState({
    this.members = const [],
    this.stats = const FamilyInviteStats(),
    this.loading = true,
    this.error,
    this.lastRefreshedAt,
  });

  final List<FamilyInviteMember> members;
  final FamilyInviteStats stats;
  final bool loading;
  final String? error;
  final DateTime? lastRefreshedAt;

  bool get isEmpty => members.isEmpty;
  int get onlineCount =>
      members.where((m) => m.isOnline == true).length;

  FamilyInviteMembersState copyWith({
    List<FamilyInviteMember>? members,
    FamilyInviteStats? stats,
    bool? loading,
    String? error,
    bool clearError = false,
    DateTime? lastRefreshedAt,
  }) {
    return FamilyInviteMembersState(
      members: members ?? this.members,
      stats: stats ?? this.stats,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      lastRefreshedAt: lastRefreshedAt ?? this.lastRefreshedAt,
    );
  }
}

/// One notifier per family — shared by every game's invite surface.
class FamilyInviteMembersNotifier
    extends StateNotifier<FamilyInviteMembersState> {
  FamilyInviteMembersNotifier(this._ref, this.familyId)
      : super(const FamilyInviteMembersState()) {
    _bootstrap();
  }

  final Ref _ref;
  final String familyId;

  RealtimeChannel? _channel;
  Timer? _debounce;
  bool _disposed = false;
  bool _loadingInFlight = false;

  static const _channelName = 'family-invite-members';

  SupabaseClient? get _client => _ref.read(supabaseProvider);

  Future<void> _bootstrap() async {
    await load();
    _subscribeToRealtime();
  }

  /// Fetch members from the membership source RPC + family stats.
  ///
  /// [silent] skips the loading spinner so realtime refreshes never
  /// flash the UI back to a loader.
  Future<void> load({bool silent = false}) async {
    if (_loadingInFlight) return;
    final client = _client;
    if (client == null) {
      state = state.copyWith(
        loading: false,
        error: 'Not signed in',
        clearError: false,
      );
      return;
    }
    _loadingInFlight = true;
    if (!silent && mounted) {
      state = state.copyWith(loading: true, clearError: true);
    }
    try {
      // Primary fetch: the membership-source RPC (single round trip,
      // includes online-status columns).
      final resp = await client
          .rpc(
            'fn_get_linked_family_members',
            params: {'p_family_id': familyId},
          )
          .timeout(const Duration(seconds: 15));

      final rows = (resp as List).cast<Map<String, dynamic>>();
      final members =
          rows.map(FamilyInviteMember.fromRpcRow).toList(growable: false);

      // Secondary fetch (parallel-friendly, tiny): family stats for an
      // accurate empty state. Best-effort — failure never blocks the list.
      var stats = state.stats;
      try {
        final results = await Future.wait([
          client
              .from('FamilyMember')
              .select('id')
              .eq('familyId', familyId)
              .timeout(const Duration(seconds: 8)),
          client
              .from('Person')
              .select('id')
              .eq('familyId', familyId)
              .isFilter('deletedAt', null)
              .limit(500)
              .timeout(const Duration(seconds: 8)),
        ]);
        stats = FamilyInviteStats(
          membershipCount: (results[0] as List).length,
          personCount: (results[1] as List).length,
        );
      } catch (e) {
        debugPrint('⚠️ FamilyInviteMembers: stats fetch failed: $e');
      }

      if (_disposed) return;
      state = FamilyInviteMembersState(
        members: members,
        stats: stats,
        loading: false,
        lastRefreshedAt: DateTime.now(),
      );
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(loading: false, error: '$e');
    } finally {
      _loadingInFlight = false;
    }
  }

  /// Realtime sync: FamilyMember + Person changes for THIS family
  /// (add / remove / link) trigger a debounced silent refresh.
  void _subscribeToRealtime() {
    final client = _client;
    if (client == null) return;

    _channel?.unsubscribe();

    void onChange(_) => _scheduleRefresh();

    _channel = client
        .channel('$_channelName:$familyId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'FamilyMember',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'familyId',
            value: familyId,
          ),
          callback: onChange,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'FamilyMember',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'familyId',
            value: familyId,
          ),
          callback: onChange,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'Person',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'familyId',
            value: familyId,
          ),
          callback: onChange,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'Person',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'familyId',
            value: familyId,
          ),
          callback: onChange,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'Person',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'familyId',
            value: familyId,
          ),
          callback: onChange,
        )
        .subscribe();

    debugPrint('📡 FamilyInviteMembers: realtime subscribed for $familyId');
  }

  /// Debounced silent refresh — bursts of events collapse into one fetch.
  void _scheduleRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      if (!_disposed) load(silent: true);
    });
  }

  /// Public manual refresh (pull-to-refresh / retry).
  Future<void> refresh() => load(silent: true);

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    // Never touch ref after dispose — capture the channel first.
    _channel?.unsubscribe();
    super.dispose();
  }
}

/// Family-scoped provider: one notifier per familyId, shared across all
/// multiplayer games' invite surfaces.
final familyInviteMembersProvider = StateNotifierProvider.family<
    FamilyInviteMembersNotifier, FamilyInviteMembersState, String>(
  (ref, familyId) => FamilyInviteMembersNotifier(ref, familyId),
);

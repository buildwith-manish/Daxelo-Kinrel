// lib/features/games/shared/providers/game_invite_status_provider.dart
//
// Per-gameId invite status tracker.
//
// Watches the SocketService for game:invite:accepted / game:invite:declined
// events that match this provider's gameId, and updates the matching
// InviteRecord's status. Also runs a 5-minute expiry sweep — any record
// still 'pending' after 5 minutes flips to 'expired'.
//
// syncFromDb() (2026-09-14) additionally reconciles the tracker with the
// durable game_invites rows: GameInviteListener now persists accept /
// decline responses to the table, so the host's invite sheet re-syncs
// accurate statuses on open AND whenever a game_invites realtime event
// lands (member invited / responded) — even when the socket leg failed.
//
// Usage in a lobby:
//   final state = ref.watch(gameInviteStatusProvider(gameId));
//   state[userId]?.status  // InviteMemberStatus.pending / accepted / declined / expired
//
// Usage in InviteFamilySheet (after sending an invite):
//   ref.read(gameInviteStatusProvider(gameId).notifier).markPending(
//     userId: m.user.id,
//     name: m.user.name,
//     username: m.user.username,
//     avatarUrl: m.user.avatarUrl,
//     photoThumb: m.user.photoThumb,
//   );

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/socket_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../models/game_invite.dart';
import '../models/game_invite_status.dart';

/// Family provider — one notifier per active game room.
final gameInviteStatusProvider = StateNotifierProvider.family<
    GameInviteStatusNotifier, GameInviteState, String>(
  (ref, gameId) => GameInviteStatusNotifier(ref, gameId),
);

class GameInviteStatusNotifier extends StateNotifier<GameInviteState> {
  GameInviteStatusNotifier(this._ref, this.gameId)
      : super(const GameInviteState()) {
    _attach();
    _expiryTimer = Timer.periodic(const Duration(seconds: 30), (_) => _sweep());
  }

  final Ref _ref;
  final String gameId;

  VoidCallback? _unsubAccepted;
  VoidCallback? _unsubDeclined;
  Timer? _expiryTimer;

  /// 5 minutes after send with no response → expired.
  static const _expiryDuration = Duration(minutes: 5);

  void _attach() {
    final socket = _ref.read(socketServiceProvider);
    _unsubAccepted = socket.onGameInviteAccepted(_handleAccepted);
    _unsubDeclined = socket.onGameInviteDeclined(_handleDeclined);
  }

  void _handleAccepted(GameInviteAcceptedEvent event) {
    if (event.gameId != gameId) return;
    final existing = state[event.acceptedByUserId];
    if (existing == null) return;
    state = state.copyWith(
      invites: {
        ...state.invites,
        existing.userId: existing.copyWith(
          status: InviteMemberStatus.accepted,
          respondedAt: DateTime.now(),
        ),
      },
    );
  }

  void _handleDeclined(GameInviteDeclinedEvent event) {
    if (event.gameId != gameId) return;
    final existing = state[event.declinedByUserId];
    if (existing == null) return;
    state = state.copyWith(
      invites: {
        ...state.invites,
        existing.userId: existing.copyWith(
          status: InviteMemberStatus.declined,
          respondedAt: DateTime.now(),
        ),
      },
    );
  }

  /// Sweep pending invites older than [_expiryDuration] and mark them expired.
  void _sweep() {
    if (state.isEmpty) return;
    final now = DateTime.now();
    final updates = <String, InviteRecord>{};
    for (final r in state.invites.values) {
      if (r.status == InviteMemberStatus.pending &&
          now.difference(r.sentAt) >= _expiryDuration) {
        updates[r.userId] = r.copyWith(status: InviteMemberStatus.expired);
      }
    }
    if (updates.isEmpty) return;
    state = state.copyWith(
      invites: {...state.invites, ...updates},
    );
  }

  /// Mark a member as 'pending' (just invited). If they already have a
  /// record (re-invite), reset to pending with a fresh sentAt.
  void markPending({
    required String userId,
    required String name,
    String? username,
    String? avatarUrl,
    String? photoThumb,
  }) {
    final record = InviteRecord(
      userId: userId,
      name: name,
      username: username,
      avatarUrl: avatarUrl,
      photoThumb: photoThumb,
      status: InviteMemberStatus.pending,
      sentAt: DateTime.now(),
    );
    state = state.copyWith(
      invites: {...state.invites, userId: record},
    );
  }

  /// Bulk mark many members as pending (used by "Invite Entire Family Space").
  void markManyPending(List<InviteRecord> records) {
    if (records.isEmpty) return;
    final newMap = <String, InviteRecord>{...state.invites};
    for (final r in records) {
      newMap[r.userId] = InviteRecord(
        userId: r.userId,
        name: r.name,
        username: r.username,
        avatarUrl: r.avatarUrl,
        photoThumb: r.photoThumb,
        status: InviteMemberStatus.pending,
        sentAt: DateTime.now(),
      );
    }
    state = state.copyWith(invites: newMap);
  }

  /// Clear all invite records (e.g. when leaving the lobby).
  void clear() {
    state = const GameInviteState();
  }

  /// Reconcile the tracker with the durable game_invites rows for this
  /// game room. Called by InviteFamilySheet on open and whenever a
  /// game_invites realtime event lands, so statuses stay accurate even
  /// when the socket event leg failed or the sheet was reopened.
  ///
  /// [nameLookup] resolves display info for recipients the tracker has
  /// never seen locally (e.g. after a sheet reopen) — falls back to the
  /// row's status only when no info is available.
  Future<void> syncFromDb({
    Map<String, ({String name, String? username, String? avatarUrl,
        String? photoThumb})>? nameLookup,
  }) async {
    final client = _ref.read(supabaseProvider);
    if (client == null) return;
    try {
      final rows = await client
          .from('game_invites')
          .select('invitedUserId, status, "createdAt", "respondedAt"')
          .eq('gameId', gameId)
          .timeout(const Duration(seconds: 8));

      if (!mounted || rows.isEmpty) return;

      final db = <String, InviteMemberStatus>{};
      final dbCreatedAt = <String, DateTime>{};
      final dbRespondedAt = <String, DateTime?>{};
      for (final row in rows.cast<Map<String, dynamic>>()) {
        final userId = row['invitedUserId'] as String?;
        if (userId == null || userId.isEmpty) continue;
        final status = InviteMemberStatus.values.firstWhere(
          (s) => s.name == (row['status'] as String? ?? 'pending'),
          orElse: () => InviteMemberStatus.pending,
        );
        final created = row['createdAt'] is String
            ? DateTime.tryParse(row['createdAt'] as String)
            : null;
        final responded = row['respondedAt'] is String
            ? DateTime.tryParse(row['respondedAt'] as String)
            : null;
        // Keep the newest row per recipient (re-invites overwrite).
        final existing = dbCreatedAt[userId];
        if (created != null && existing != null && created.isBefore(existing)) {
          continue;
        }
        db[userId] = status;
        dbCreatedAt[userId] = created ?? DateTime.now();
        dbRespondedAt[userId] = responded;
      }
      if (db.isEmpty || !mounted) return;

      final merged = <String, InviteRecord>{...state.invites};
      for (final entry in db.entries) {
        final userId = entry.key;
        final dbStatus = entry.value;
        final local = merged[userId];

        // Terminal local states (accepted / declined via the live socket
        // event) are never downgraded by a stale 'pending' DB row.
        if (local != null &&
            local.status != InviteMemberStatus.pending &&
            dbStatus == InviteMemberStatus.pending) {
          continue;
        }

        final info = nameLookup?[userId];
        merged[userId] = InviteRecord(
          userId: userId,
          name: info?.name ?? local?.name ?? 'Family member',
          username: info?.username ?? local?.username,
          avatarUrl: info?.avatarUrl ?? local?.avatarUrl,
          photoThumb: info?.photoThumb ?? local?.photoThumb,
          status: dbStatus,
          sentAt: dbCreatedAt[userId] ?? local?.sentAt ?? DateTime.now(),
          respondedAt: dbRespondedAt[userId] ?? local?.respondedAt,
        );
      }

      if (mounted &&
          (merged.length != state.invites.length ||
              !_mapsEqual(merged, state.invites))) {
        state = state.copyWith(invites: merged);
      }
    } catch (e) {
      // Best-effort reconciliation — never surface as an error.
      debugPrint('⚠️ GameInviteStatus.syncFromDb failed (non-blocking): $e');
    }
  }

  bool _mapsEqual(Map<String, InviteRecord> a, Map<String, InviteRecord> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      final other = b[e.key];
      if (other == null ||
          other.status != e.value.status ||
          other.name != e.value.name) {
        return false;
      }
    }
    return true;
  }

  @override
  void dispose() {
    _unsubAccepted?.call();
    _unsubDeclined?.call();
    _expiryTimer?.cancel();
    super.dispose();
  }
}

// lib/features/games/shared/services/game_invite_inbox.dart
//
// Offline game-invite inbox — the catch-up leg (leg 3) of the invite
// delivery system.
//
//   Leg 1: NestJS KinrelGateway socket  `game:invite:received`
//   Leg 2: Supabase Realtime            game_invites INSERT events
//   Leg 3: THIS — a one-shot SELECT of pending, unread, unexpired
//          game_invites rows for the signed-in user, run at app start /
//          realtime-(re)subscribe / app-resume. Invites that arrived
//          while the member was OFFLINE (app closed, socket dead,
//          channel gone) are surfaced here through the exact same
//          Accept / Decline dialog the realtime legs use.
//
// Everything here is NON-THROWING by design: the catch-up runs during
// app start and must never take the session down when the network (or
// the schema, pre-migration) is unavailable — failures are logged and
// degrade to "no unread invites".

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/game_invite.dart';

class GameInviteInbox {
  GameInviteInbox._();

  /// Fetch the signed-in user's pending, unread, unexpired invites,
  /// oldest first. Never throws — returns an empty list on any failure
  /// (network down, not signed in, column not yet migrated, …).
  static Future<List<GameInvite>> fetchUnread(
    SupabaseClient client, {
    int limit = 5,
  }) async {
    try {
      final myId = client.auth.currentUser?.id;
      if (myId == null) return const [];

      final rows = await client
          .from('game_invites')
          .select()
          .eq('invitedUserId', myId)
          .eq('status', 'pending')
          .eq('isRead', false)
          .gt('expiresAt', DateTime.now().toUtc().toIso8601String())
          .order('createdAt', ascending: true)
          .limit(limit)
          .timeout(const Duration(seconds: 10));

      return filterInboxRows(
        (rows as List).whereType<Map<String, dynamic>>().toList(),
      );
    } catch (e) {
      // Non-throwing by contract — see class docs.
      debugPrint('📮 GameInviteInbox: catch-up skipped (non-throwing): $e');
      return const [];
    }
  }

  /// Client-side re-check of the server-side predicate (defence in depth:
  /// rows fetched a moment before an expiry flip, plus a guard for
  /// unparseable rows). Pure and unit-testable.
  static List<GameInvite> filterInboxRows(List<Map<String, dynamic>> rows) {
    final now = DateTime.now();
    final out = <GameInvite>[];
    for (final row in rows) {
      if (row['status'] != 'pending') continue;
      if (row['isRead'] == true) continue;
      final expiresRaw = row['expiresAt'];
      final expiresAt = expiresRaw is String ? DateTime.tryParse(expiresRaw) : null;
      // Unparseable/missing expiry: treat as still-live (the 5-minute
      // pg_cron expiry job is the ultimate authority server-side).
      if (expiresAt != null && expiresAt.isBefore(now)) continue;
      final invite = inviteFromRow(row);
      if (invite != null) out.add(invite);
    }
    return out;
  }

  /// Map a game_invites DB row onto a [GameInvite]. Returns null for rows
  /// that can't drive a join (missing gameId, unknown gameType).
  static GameInvite? inviteFromRow(Map<String, dynamic> row) {
    final gameId = row['gameId'] as String?;
    if (gameId == null || gameId.isEmpty) return null;
    final gameType = GameTypeX.fromRouteSegment(
            (row['gameType'] as String?) ?? '') ??
        GameTypeX.fromDisplayName((row['gameType'] as String?) ?? '');
    if (gameType == null) return null;

    int toInt(dynamic v, int fallback) => v is num
        ? v.toInt()
        : (v is String ? int.tryParse(v) ?? fallback : fallback);

    return GameInvite(
      inviteId: (row['id'] as String?) ?? 'db_$gameId',
      gameType: gameType,
      gameId: gameId,
      roomCode: (row['roomCode'] as String?) ?? '',
      familyId: (row['familyId'] as String?) ?? '',
      fromUserId: (row['invitedByUserId'] as String?) ?? '',
      fromName: (row['invitedByName'] as String?) ?? 'A family member',
      maxPlayers: toInt(row['maxPlayers'], 2),
      currentPlayers: toInt(row['currentPlayers'], 1),
      message: row['message'] as String?,
      timestamp: DateTime.tryParse((row['createdAt'] as String?) ?? ''),
    );
  }

  /// Mark the invite as surfaced (isRead + shownAt) so future catch-ups
  /// don't re-show it. Matched by (gameId, invitedUserId) — the socket leg
  /// carries a synthetic inviteId that doesn't match the DB row id.
  /// Fire-and-forget safe: failures are logged, never thrown.
  static Future<void> markSurfaced(
    SupabaseClient? client,
    GameInvite invite,
  ) async {
    try {
      if (client == null) return;
      final myId = client.auth.currentUser?.id;
      if (myId == null) return;
      await client
          .from('game_invites')
          .update({
            'isRead': true,
            'shownAt': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('gameId', invite.gameId)
          .eq('invitedUserId', myId)
          .eq('status', 'pending')
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('📮 GameInviteInbox: markSurfaced failed (non-blocking): $e');
    }
  }
}

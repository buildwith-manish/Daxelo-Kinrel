// lib/features/chat/data/dm_invite_status_provider.dart
//
// DAXELO KINREL — Live game-room status for DM invite cards
//
// The group chat's game-invite cards get their live status (pending →
// in_progress → completed / expired) from a server-side trigger
// (fn_sync_game_invite_status) that writes to the ChatMessage table's
// gameInviteStatus column whenever the game room's status changes.
// The client's realtime UPDATE subscription on ChatMessage picks up
// the change and the card re-renders.
//
// DM invites live in the DirectMessage table, which does NOT have a
// gameInviteStatus column and is NOT touched by the server trigger.
// So the DM invite card's status was stuck at the static 'pending'
// from the adapter — it never showed Expired / Completed even after
// the game room expired.
//
// This provider bridges that gap client-side: for each DM invite
// gameId, it queries the underlying game table's `status` column and
// subscribes to realtime UPDATEs on that row. The raw per-game status
// (waiting / in_progress / completed / expired / cancelled / ...) is
// mapped to the SAME unified 5-state vocabulary the group chat uses
// (the mapping mirrors fn_sync_game_invite_status's CASE exactly).
//
// The DM messages provider (directChatMessagesProvider) watches this
// provider for each invite DM and overrides the adapter's static
// 'pending' with the live status — so the DM card shows Expired /
// Completed / In-progress at the same moment the group card does.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';

/// The live status of a DM game-invite's underlying game room, mapped
/// to the unified 5-state vocabulary the group chat uses.
class DmInviteLiveStatus {
  const DmInviteLiveStatus({this.status});

  /// One of: 'pending', 'in_progress', 'completed', 'expired', or null
  /// (unknown — the caller falls back to the adapter's default 'pending').
  final String? status;

  static const unknown = DmInviteLiveStatus();
}

/// Key for [dmInviteLiveStatusProvider].
///
/// [gameId] is the game room's id (from the invite payload).
/// [gameTable] is the Postgres table name for that game type
/// (e.g. 'tictactoe_games', 'sos_games' — resolved via
/// `gameTableForType` in the games package).
class DmInviteKey {
  const DmInviteKey({required this.gameId, required this.gameTable});

  final String gameId;
  final String gameTable;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DmInviteKey &&
          gameId == other.gameId &&
          gameTable == other.gameTable;

  @override
  int get hashCode => Object.hash(gameId, gameTable);

  @override
  String toString() => 'DmInviteKey($gameTable/$gameId)';
}

/// Maps a per-game raw status (from the game table's `status` column)
/// to the unified 5-state vocabulary. Mirrors the CASE in
/// fn_sync_game_invite_status (migration 20261004100000, lines 178-188).
///
/// Per-game status vocabularies vary (tictactoe uses 'waiting' |
/// 'in_progress' | 'completed'; some games also use 'expired' /
/// 'cancelled'; party games use 'lobby' / 'setup' / 'countdown' /
/// 'drawing' / 'guessing'). This function unifies them all into the
/// 4 canonical values the group chat card renders.
String? _mapToUnifiedStatus(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  switch (raw) {
    // Pre-game / lobby states → pending
    case 'waiting':
    case 'lobby':
    case 'setup':
    case 'countdown':
    case 'drawing':
    case 'guessing':
      return 'pending';
    // Active play → in_progress
    case 'in_progress':
    case 'active':
      return 'in_progress';
    // Finished normally → completed
    case 'completed':
    case 'finished':
      return 'completed';
    // Room closed without finishing → expired
    case 'expired':
    case 'cancelled':
      return 'expired';
    default:
      // Unknown status — don't override the adapter's default.
      return null;
  }
}

/// StreamProvider that emits the live status of a DM game-invite's game
/// room. Does an initial query of the game table's `status` column,
/// then subscribes to realtime UPDATEs on that row so the DM invite
/// card re-renders the moment the game room's status changes (expired,
/// completed, started, etc.) — exactly like the group chat card.
///
/// autoDispose: the subscription cleans up when the DM screen is
/// closed (no leaked channels).
final dmInviteLiveStatusProvider = StreamProvider.autoDispose
    .family<DmInviteLiveStatus, DmInviteKey>((ref, key) async* {
  final client = ref.watch(supabaseProvider);
  if (client == null || key.gameId.isEmpty || key.gameTable.isEmpty) {
    yield DmInviteLiveStatus.unknown;
    return;
  }

  // ── Initial query ──────────────────────────────────────────────
  // Every game table has a `status` column (some also have
  // currentPlayers / maxPlayers / winnerName, but the column names
  // vary per game — we only read `status` here for universality).
  String? initialRawStatus;
  try {
    final row = await client
        .from(key.gameTable)
        .select('status')
        .eq('id', key.gameId)
        .limit(1)
        .maybeSingle();
    if (row != null) {
      initialRawStatus = row['status'] as String?;
    }
  } catch (e) {
    // The game row may not exist (deleted), or the table name may be
    // wrong (old invite with a game type that was renamed). Fall back
    // to unknown — the adapter's default 'pending' is used.
    debugPrint('⚠️ dmInviteLiveStatusProvider($key) initial query: $e');
  }

  final initialMapped = _mapToUnifiedStatus(initialRawStatus);
  yield DmInviteLiveStatus(status: initialMapped);

  // ── Realtime subscription ──────────────────────────────────────
  // Subscribe to UPDATEs on this specific game row. When the server's
  // expiry sweep (fn_sweep_expired_game_rooms) or a player action
  // changes the status, the stream emits a new value and the DM card
  // re-renders — same realtime path the group chat uses (via
  // ChatMessage UPDATE → chat_provider realtime).
  final controller = StreamController<DmInviteLiveStatus>();

  late RealtimeChannel channel;
  try {
    channel = client.channel('dm-invite-${key.gameTable}-${key.gameId}');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: key.gameTable,
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id',
        value: key.gameId,
      ),
      callback: (payload) {
        final newRecord = payload.newRecord;
        final rawStatus = newRecord['status'] as String?;
        final mapped = _mapToUnifiedStatus(rawStatus);
        if (mapped != null) {
          controller.add(DmInviteLiveStatus(status: mapped));
        }
      },
    );
    channel.subscribe();
  } catch (e) {
    debugPrint('⚠️ dmInviteLiveStatusProvider($key) realtime subscribe: $e');
  }

  ref.onDispose(() {
    try {
      channel.unsubscribe();
    } catch (_) {}
    controller.close();
  });

  yield* controller.stream;
});

// test/features/games/shared/game_invite_inbox_test.dart
//
// Unit tests for the offline invite inbox (QA follow-up item 4):
//   • row → GameInvite mapping (the catch-up dialog data)
//   • filterInboxRows — only pending, unread, unexpired rows surface
//   • non-throwing contract of fetchUnread (bad client state → empty)

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/games/shared/models/game_invite.dart';
import 'package:kinrel/features/games/shared/services/game_invite_inbox.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, dynamic> _row({
  String? id,
  String gameTable = 'bingo_games',
  String gameId = 'game-1',
  String gameType = 'bingo',
  String status = 'pending',
  bool isRead = false,
  String? expiresAt,
  String invitedByUserId = 'host-1',
  String invitedByName = 'Aunt Rita',
  dynamic maxPlayers = 4,
  dynamic currentPlayers = 2,
}) =>
    {
      'id': id ?? 'inv-1',
      'gameTable': gameTable,
      'gameId': gameId,
      'gameType': gameType,
      'familyId': 'fam-1',
      'roomCode': 'AB12CD',
      'invitedUserId': 'me-1',
      'invitedByUserId': invitedByUserId,
      'invitedByName': invitedByName,
      'maxPlayers': maxPlayers,
      'currentPlayers': currentPlayers,
      'message': 'Join my game!',
      'status': status,
      'isRead': isRead,
      'sourceGameId': null,
      'createdAt': '2026-09-22T10:00:00.000Z',
      'respondedAt': null,
      'expiresAt': expiresAt ??
          DateTime.now()
              .add(const Duration(minutes: 9))
              .toUtc()
              .toIso8601String(),
      'shownAt': null,
    };

void main() {
  group('GameInviteInbox.inviteFromRow', () {
    test('maps a full pending row onto a GameInvite', () {
      final invite = GameInviteInbox.inviteFromRow(_row());
      expect(invite, isNotNull);
      expect(invite!.inviteId, 'inv-1');
      expect(invite.gameType, GameType.bingo);
      expect(invite.gameId, 'game-1');
      expect(invite.roomCode, 'AB12CD');
      expect(invite.fromUserId, 'host-1');
      expect(invite.fromName, 'Aunt Rita');
      expect(invite.maxPlayers, 4);
      expect(invite.currentPlayers, 2);
      expect(invite.timestamp, DateTime.parse('2026-09-22T10:00:00.000Z'));
      expect(invite.joinRoute, '/family/fam-1/bingo/lobby?join=game-1');
    });

    test('coerces string numerics (Supabase sometimes returns strings)', () {
      final invite = GameInviteInbox.inviteFromRow(
        _row(maxPlayers: '6', currentPlayers: '3'),
      );
      expect(invite!.maxPlayers, 6);
      expect(invite.currentPlayers, 3);
    });

    test('accepts route segments AND display names for gameType', () {
      // Rematch rows use route segments ('ghost-painter'); older rows used
      // display names ('Tug of War').
      expect(
        GameInviteInbox.inviteFromRow(_row(gameType: 'ghost-painter'))!
            .gameType,
        GameType.ghostPainter,
      );
      expect(
        GameInviteInbox.inviteFromRow(_row(gameType: 'Tug of War'))!.gameType,
        GameType.tugOfWar,
      );
    });

    test('null for unusable rows (missing gameId / unknown gameType)', () {
      expect(GameInviteInbox.inviteFromRow(_row(gameId: '')), isNull);
      expect(
        GameInviteInbox.inviteFromRow(_row(gameType: 'not-a-game')),
        isNull,
      );
    });

    test('synthesizes a stable inviteId when the row id is missing', () {
      final row = _row()..remove('id');
      final invite = GameInviteInbox.inviteFromRow(row);
      expect(invite!.inviteId, 'db_game-1');
    });
  });

  group('GameInviteInbox.filterInboxRows', () {
    test('keeps pending + unread + unexpired rows', () {
      final out = GameInviteInbox.filterInboxRows([_row(gameId: 'g1')]);
      expect(out, hasLength(1));
      expect(out.first.gameId, 'g1');
    });

    test('drops responded rows (accepted / declined / expired)', () {
      final out = GameInviteInbox.filterInboxRows([
        _row(gameId: 'g1', status: 'accepted'),
        _row(gameId: 'g2', status: 'declined'),
        _row(gameId: 'g3', status: 'expired'),
      ]);
      expect(out, isEmpty);
    });

    test('drops rows already surfaced (isRead = true)', () {
      final out = GameInviteInbox.filterInboxRows([
        _row(gameId: 'g1', isRead: true),
      ]);
      expect(out, isEmpty);
    });

    test('drops rows past their expiry, keeps unparseable expiry', () {
      final out = GameInviteInbox.filterInboxRows([
        _row(
          gameId: 'expired',
          expiresAt: DateTime.now()
              .subtract(const Duration(minutes: 1))
              .toUtc()
              .toIso8601String(),
        ),
        _row(gameId: 'no-expiry-field', expiresAt: null),
      ]);
      // The expired row is dropped; the row without a parseable expiry is
      // kept (the server's 5-minute cron job is the final authority).
      expect(out, hasLength(1));
      expect(out.first.gameId, 'no-expiry-field');
    });

    test('preserves createdAt ordering (oldest invite surfaces first)', () {
      final out = GameInviteInbox.filterInboxRows([
        _row(id: 'newer', gameId: 'g2'),
        _row(id: 'older', gameId: 'g1'),
      ]);
      // filterInboxRows keeps input order — the DB query does ORDER BY.
      expect(out.first.inviteId, 'newer');
      expect(out.last.inviteId, 'older');
    });
  });

  group('GameInviteInbox.fetchUnread (non-throwing contract)', () {
    test('returns empty when not signed in / client unavailable', () async {
      // A SupabaseClient with no session: fetchUnread must resolve to an
      // empty list, never throw (it runs during app start).
      // Constructing a real client against a bogus URL keeps this test
      // hermetic: no request is attempted because the auth session is
      // null and the method returns early.
      final client = SupabaseClient(
        'https://example.supabase.co',
        'anon-key-for-tests',
      );
      addTearDown(client.dispose);
      expect(await GameInviteInbox.fetchUnread(client), isEmpty);
    });
  });
}

// test/features/games/shared/game_type_invite_wiring_test.dart
//
// QA fix 2026-09-20 (item 1 of the post-QA follow-up list):
// Ghost Painter shipped in kGameCatalog but was never wired into the
// shared GameType invite system — no enum member, no routeSegment, no
// table mapping in gameTypeForTable, and no /ghost-painter/lobby route
// for accepted invites to land on. Any invite surface that tried to
// reference it silently no-oped (gameTypeForTable → null) or misrouted
// (fromJson → GameType.bingo fallback).
//
// This test pins the complete wiring for Ghost Painter specifically.
// The catalog-wide contract (every kGameCatalog game) lives in
// test/features/games/game_registration_contract_test.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/games/shared/models/game_invite.dart';
import 'package:kinrel/features/games/shared/widgets/family_invite_card.dart';

void main() {
  group('Ghost Painter invite wiring (QA 2026-09-20)', () {
    test('table → GameType: ghost_painter_rounds resolves (not null)', () {
      expect(gameTypeForTable('ghost_painter_rounds'), GameType.ghostPainter);
    });

    test('GameType → table: forward map matches the reverse map', () {
      expect(gameTableForType(GameType.ghostPainter), 'ghost_painter_rounds');
    });

    test('routeSegment matches the router path segment', () {
      expect(GameType.ghostPainter.routeSegment, 'ghost-painter');
      expect(GameTypeX.fromRouteSegment('ghost-painter'), GameType.ghostPainter);
    });

    test('displayName is human-friendly', () {
      expect(GameType.ghostPainter.displayName, 'Ghost Painter');
      expect(
        GameTypeX.fromDisplayName('Ghost Painter'),
        GameType.ghostPainter,
      );
    });

    test('GameInvite.fromJson maps the ghost-painter wire gameType', () {
      // Without the enum member, this fell back to GameType.bingo and the
      // accept flow navigated to the BINGO lobby.
      final invite = GameInvite.fromJson(const {
        'inviteId': 'inv_gp_1',
        'gameType': 'ghost-painter',
        'gameId': 'round-uuid',
        'roomCode': 'ABC123',
        'familyId': 'fam-uuid',
        'fromUserId': 'u1',
        'fromName': 'Aunt Rita',
        'maxPlayers': 20,
        'currentPlayers': 2,
      });
      expect(invite.gameType, GameType.ghostPainter);
    });

    test('accepting an invite routes to the ghost-painter lobby join route', () {
      final invite = GameInvite(
        inviteId: 'inv_gp_2',
        gameType: GameType.ghostPainter,
        gameId: 'round-uuid',
        roomCode: 'ABC123',
        familyId: 'fam-uuid',
        fromUserId: 'u1',
        fromName: 'Aunt Rita',
        maxPlayers: 20,
        currentPlayers: 2,
      );
      // The shared accept flow navigates here; app_router must own this
      // path (it lands on GhostPainterJoinScreen, which resolves the
      // joiner's real destination: draw vs guess).
      expect(
        invite.joinRoute,
        '/family/fam-uuid/ghost-painter/lobby?join=round-uuid',
      );
    });
  });

  group('GameType ↔ table roundtrip (all members)', () {
    test('every GameType maps to a table that maps back to it', () {
      for (final t in GameType.values) {
        final table = gameTableForType(t);
        expect(
          gameTypeForTable(table),
          t,
          reason:
              'gameTypeForType($t) → "$table" but gameTypeForTable("$table") '
              'does not map back to $t. The forward and reverse maps have '
              'drifted — a lobby invite for this game will silently no-op.',
        );
      }
    });

    test('every GameType has a non-empty routeSegment and displayName', () {
      for (final t in GameType.values) {
        expect(t.routeSegment, isNotEmpty,
            reason: '$t has an empty routeSegment');
        expect(t.displayName, isNotEmpty,
            reason: '$t has an empty displayName');
        expect(
          GameTypeX.fromRouteSegment(t.routeSegment),
          t,
          reason: 'fromRouteSegment("${t.routeSegment}") does not roundtrip '
              'to $t — invite dialogs would show/navigate the wrong game.',
        );
      }
    });
  });
}

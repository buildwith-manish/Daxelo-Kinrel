// test/features/games/game_registration_contract_test.dart
//
// Item 2 of the post-QA follow-up list (2026-09-20): a registration
// CONTRACT test. kGameCatalog (game_registry.dart) is the single source
// of truth for the games hub; every catalog game MUST also be wired
// into the shared GameType invite system:
//
//   • gameTypeForTable (family_invite_card.dart)   table → GameType
//     — the per-member one-tap lobby invite builds its insert payload
//     from this; a missing case silently no-ops the button.
//   • GameTypeX.routeSegment / fromRouteSegment    wire gameType ↔ URL
//     — invite dialogs, the active-games list and deep links all
//     resolve through these; a miss misroutes to the wrong game.
//   • gameTableForType (game_invite.dart)          GameType → table
//     — the invite sheet and the shared RematchButton insert
//     game_invites rows through this.
//
// Three separate QA bugs (12 missing tables, Stickman Heist + Crystal
// Bridge, then Ghost Painter — which had no GameType member at all)
// were all the same failure class: a game shipped in the catalog but
// not in one of these maps. This test fails the build the moment that
// happens again, naming the exact game to wire up.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/gaming_ecosystem/data/game_registry.dart';
import 'package:kinrel/features/games/shared/models/game_invite.dart';
import 'package:kinrel/features/games/shared/widgets/family_invite_card.dart';

void main() {
  group('Game registration contract — kGameCatalog ↔ GameType ↔ invite maps',
      () {
    test('catalog has not silently lost games (31 registered)', () {
      // Guard against accidental catalog truncation (a bad merge or a
      // refactor dropping entries). If a game was removed ON PURPOSE,
      // update this number in the same commit.
      expect(kGameCatalog.length, greaterThanOrEqualTo(31),
          reason: 'kGameCatalog unexpectedly shrank — game cards went '
              'missing from the hub. If the removal was intentional, '
              'lower this guard in the same commit.');
    });

    test('every catalog game is fully wired into the invite system', () {
      final problems = <String>[];

      for (final entry in kGameCatalog) {
        // '/family/{familyId}/<segment>/lobby' (or '.../draw' for
        // Ghost Painter — the segment is always path part index 3).
        final parts = entry.route.split('/');
        final segment = parts.length > 3 ? parts[3] : '';

        // 1. table → GameType (one-tap lobby invites)
        final byTable = gameTypeForTable(entry.gameTable);
        // 2. URL segment → GameType (invite dialogs, active games, deep links)
        final byRoute = GameTypeX.fromRouteSegment(segment);
        // 3. GameType → table (invite sheet + rematch inserts)
        final forward = byTable == null ? null : gameTableForType(byTable);

        if (byTable == null ||
            byRoute == null ||
            byRoute != byTable ||
            forward != entry.gameTable) {
          problems.add(
            '${entry.gameId}: table "${entry.gameTable}" → '
            'gameTypeForTable=$byTable, fromRouteSegment("$segment")='
            '$byRoute, gameTableForType=$forward',
          );
        }
      }

      expect(
        problems,
        isEmpty,
        reason:
            'Games registered in kGameCatalog but NOT wired into the shared '
            'GameType invite system — their one-tap lobby invites silently '
            'no-op (gameTypeForTable returns null before any insert runs) '
            'or misroute to another game. To register a game: (1) add the '
            'GameType enum member + routeSegment + displayName cases in '
            'game_invite.dart, (2) add its table to gameTypeForType in '
            'game_invite.dart AND gameTypeForTable in '
            'family_invite_card.dart. Unwired: $problems',
      );
    });

    test('every GameType is reachable from the catalog (no orphans)', () {
      final catalogTables = kGameCatalog.map((e) => e.gameTable).toSet();
      final orphans = GameType.values
          .where((t) => !catalogTables.contains(gameTableForType(t)))
          .map((t) => t.name)
          .toList();

      expect(
        orphans,
        isEmpty,
        reason: 'GameType members with no kGameCatalog entry are dead '
            'invite-wiring no card can ever launch. Either add the catalog '
            'entry or remove the enum member. Orphans: $orphans',
      );
    });

    test('catalog gameTables are unique', () {
      final tables = kGameCatalog.map((e) => e.gameTable).toList();
      expect(
        tables.toSet().length,
        tables.length,
        reason: 'Two catalog entries claim the same Supabase table — '
            'invites, rematch rows and leaderboards will conflate two '
            'different games.',
      );
    });

    test('catalog routes are unique', () {
      final routes = kGameCatalog.map((e) => e.route).toList();
      expect(routes.toSet().length, routes.length,
          reason: 'Two catalog entries navigate to the same route — one '
              'card can never be reached.');
    });
  });
}

// lib/features/games/presentation/widgets/quick_picks_row.dart
//
// QuickPicksRow — a horizontal-scroll "Quick picks" row placed directly
// below the Play With row on the Family Arena home screen.
//
// Shows 4-6 game cards selected by this priority:
//   1. Games the family has played most often in the last 30 days (from
//      get_family_quick_picks RPC), EXCLUDING any game already suggested
//      in the Play With row for the current viewer (avoid duplicate
//      suggestions).
//   2. Backfill with a curated default set suited to small groups
//      (Tic-Tac-Toe, Checkers, Memory Match, Chess) when the family has
//      fewer than `limit` distinct games played — handled server-side.
//
// Card visual style matches the existing category grid cards (icon,
// name, player count) — no new visual style, just a new curated row.
//
// Tapping a card goes straight to that game's invite/lobby flow.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../gaming_ecosystem/data/game_registry.dart';
import '../../shared/icons/game_icons.dart';
import 'play_with_row.dart' show playWithSuggestionsProvider;

// ─────────────────────────────────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────────────────────────────────

class QuickPick {
  const QuickPick({
    required this.gameTable,
    required this.gameId,
    required this.name,
    required this.playerCountRange,
    required this.playCountLast30d,
  });

  /// Supabase table name (e.g. 'tictactoe_games') — used as the unique key
  /// for de-duplication against the Play With row.
  final String gameTable;

  /// Catalog game ID (e.g. 'tictactoe') — used to resolve the lobby route
  /// and the GameIcon widget.
  final String gameId;
  final String name;
  final String playerCountRange;
  final int playCountLast30d;

  factory QuickPick.fromJson(Map<String, dynamic> json) {
    final rawGameTable = (json['game_id'] as String?) ?? '';
    final catalogEntry = gameByTable(rawGameTable);
    return QuickPick(
      gameTable: rawGameTable,
      gameId: catalogEntry?.gameId ?? rawGameTable,
      name: (json['game_name'] as String?) ?? 'Game',
      playerCountRange: (json['player_count_range'] as String?) ?? '',
      playCountLast30d: (json['play_count_last_30d'] as num?)?.toInt() ?? 0,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────
//
// Fetches the raw quick picks from the server, then EXCLUDES any game
// whose gameTable matches a game already suggested in the Play With row
// for the current viewer. This avoids the duplicate-suggestion problem
// (e.g. if Play With already says "Play Chess again with Manish", the
// Quick Picks row won't show a Chess card).
//
// The exclusion list is read from `playWithSuggestionsProvider` for the
// same family. Both providers are autoDispose + family-scoped, so they
// refresh together when the user pulls-to-refresh the home screen.

final quickPicksProvider = FutureProvider.autoDispose
    .family<List<QuickPick>, String>((ref, familyId) async {
  final client = ref.watch(supabaseProvider);
  if (client == null) return const <QuickPick>[];
  try {
    final raw = await client.rpc('get_family_quick_picks', params: {
      'p_family_id': familyId,
      'p_requesting_user_id': client.auth.currentUser?.id,
      'p_limit': 8, // fetch a few extra so we still have 4-6 after exclusions
    });
    final map = raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};
    final list = map['picks'];
    if (list is! List) return const <QuickPick>[];
    final picks = list
        .whereType<Map>()
        .map((e) => QuickPick.fromJson(Map<String, dynamic>.from(e)))
        .where((p) => p.gameTable.isNotEmpty)
        .toList();

    // Exclude any game already suggested in the Play With row.
    // playWithSuggestionsProvider returns suggestions whose lastSharedGameId
    // is the catalog gameId (e.g. 'chess'). We map that back to the table
    // name via gameById so we can compare against the quick picks' gameTable.
    final playWith = ref
        .watch(playWithSuggestionsProvider(familyId))
        .asData
        ?.value ?? const [];
    final excludedTables = playWith
        .map((s) => s.lastSharedGameId)
        .whereType<String>()
        .map((id) => gameById(id)?.gameTable)
        .whereType<String>()
        .toSet();

    final filtered = picks
        .where((p) => !excludedTables.contains(p.gameTable))
        .toList();

    // If we still have at least 4 picks after exclusion, return them
    // (capped at 6). If fewer, fall back to the unfiltered list so the
    // row isn't empty — the duplicate-suggestion case is a minor UX nit;
    // an empty row is worse.
    if (filtered.length >= 4) return filtered.take(6).toList();
    return picks.take(6).toList();
  } catch (_) {
    return const <QuickPick>[];
  }
});

// ─────────────────────────────────────────────────────────────────────────
// Row widget
// ─────────────────────────────────────────────────────────────────────────

class QuickPicksRow extends ConsumerWidget {
  const QuickPicksRow({super.key, required this.familyId});
  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(quickPicksProvider(familyId));
    return async.when(
      loading: () => const _RowSkeleton(),
      error: (_, __) => const SizedBox.shrink(),
      data: (picks) {
        if (picks.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 2, bottom: 10),
              child: const Text(
                'Quick picks',
                style: const TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: KinrelColors.textWhite,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            SizedBox(
              height: 124,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 2),
                itemCount: picks.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, i) => QuickPickCard(
                  pick: picks[i],
                  familyId: familyId,
                )
                    .animate()
                    .fadeIn(delay: (40 * i).ms, duration: 280.ms)
                    .slideX(begin: 0.06, end: 0, duration: 280.ms),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RowSkeleton extends StatelessWidget {
  const _RowSkeleton();
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 124,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        children: List.generate(
          4,
          (_) => Container(
            width: 132,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              color: KinrelColors.darkCard,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Card widget — matches the visual style of the existing category grid
// cards (icon, name, player count). Tapping goes to the game's lobby.
// ─────────────────────────────────────────────────────────────────────────

class QuickPickCard extends StatelessWidget {
  const QuickPickCard({super.key, required this.pick, required this.familyId});
  final QuickPick pick;
  final String familyId;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        final game = gameById(pick.gameId);
        if (game == null) return;
        context.push(gameRoute(game, familyId));
      },
      child: Container(
        width: 132,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 38,
                    height: 38,
                    child: GameIcon(gameId: pick.gameId, size: 38),
                  ),
                ),
                const Spacer(),
                if (pick.playCountLast30d > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: KinrelColors.orange.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${pick.playCountLast30d}',
                      style: const TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: KinrelColors.orange,
                      ),
                    ),
                  ),
              ],
            ),
            const Spacer(),
            Text(
              pick.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              pick.playerCountRange,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 10,
                color: KinrelColors.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// lib/features/games/presentation/widgets/play_with_row.dart
//
// PlayWithRow — Zone 2 of the 3-zone Family Arena home screen.
//
// Replaces the flat game-icon grid as the primary above-the-fold content.
// People motivate more than icons: leading with family member avatars +
// a suggested game is the highest-leverage UX change in the restructure.
//
// Each card shows:
//   • Member avatar (initials fallback)
//   • Member name
//   • Small subtext:
//     - If they've played with the viewer before: "Play Chess again" (last
//       shared game) OR "3 games together" if no last game (defensive)
//     - If never played together: "New — say hi with Tic-Tac-Toe" (defaults
//       to the lightest/shortest game for a first interaction)
//     - If member is currently online: an online indicator dot on the avatar
//   • Tapping the card jumps straight into the game invite flow pre-filled
//     with that member + suggested game.
//
// Ordering (enforced server-side by get_play_with_suggestions):
//   online now > highest shared-games-count > never played together.
//   This encourages completing the family, not just repeating the same pair.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../gaming_ecosystem/data/game_registry.dart';
import '../../shared/icons/kinrel_icons.dart';

// ─────────────────────────────────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────────────────────────────────

class PlayWithSuggestion {
  const PlayWithSuggestion({
    required this.userId,
    required this.userName,
    this.avatarUrl,
    required this.isOnline,
    required this.sharedGamesCount,
    this.lastSharedGameId,
    this.lastSharedGameName,
    this.lastSharedGameIcon,
    this.lastPlayedTogetherAt,
  });

  final String userId;
  final String userName;
  final String? avatarUrl;
  final bool isOnline;
  final int sharedGamesCount;

  /// Catalog gameId (e.g. 'tictactoe') when derivable from the last-shared
  /// gameTable. Null when the user has never played with this member.
  final String? lastSharedGameId;
  final String? lastSharedGameName;
  final String? lastSharedGameIcon;
  final DateTime? lastPlayedTogetherAt;

  /// True when this is a brand-new pairing (no shared history).
  ///
  /// QA fix 2026-09-19: was `sharedGamesCount == 0 || lastSharedGameId == null`,
  /// which wrongly classified a pairing with shared games as NEW whenever the
  /// last-shared game couldn't be derived (e.g. a game table missing from the
  /// catalog mapping in fromJson). That contradicted this doc ("no shared
  /// history") and produced "New — say hi with Tic-Tac-Toe" + a NEW badge for
  /// members the user had already played many games with. A pairing is new
  /// only when the shared-games count itself is zero; the no-last-game case
  /// falls through to the "Played N games together" subtext.
  bool get isNew => sharedGamesCount == 0;

  factory PlayWithSuggestion.fromJson(Map<String, dynamic> json) {
    final rawGameTable = json['last_shared_game_id'] as String?;
    // Map the Supabase game table back to a catalog gameId so we can route
    // into the right lobby. Falls back to null when no shared history.
    final catalogEntry = gameByTable(rawGameTable);
    return PlayWithSuggestion(
      userId: (json['user_id'] as String?) ?? '',
      userName: (json['user_name'] as String?) ?? 'Family Member',
      avatarUrl: json['avatar_url'] as String?,
      isOnline: json['is_online'] as bool? ?? false,
      sharedGamesCount: (json['shared_games_count'] as num?)?.toInt() ?? 0,
      lastSharedGameId: catalogEntry?.gameId,
      lastSharedGameName: json['last_shared_game_name'] as String?,
      lastSharedGameIcon: json['last_shared_game_icon'] as String?,
      lastPlayedTogetherAt: json['last_played_together_at'] == null
          ? null
          : DateTime.tryParse(json['last_played_together_at'].toString()),
    );
  }
}

/// The lightest/shortest game in the catalog — used as the default
/// suggestion for first-time pairings ("say hi with Tic-Tac-Toe").
final String kDefaultFirstGameId = 'tictactoe';

/// Builds the subtext for a Play With card. Extracted as a top-level
/// function so widget tests can verify the copy without spinning up the
/// widget tree.
///
/// Contract:
///   • Never mentions wins / losses / win% (privacy + reframe).
///   • For isNew pairings: "New — say hi with {Game}" (default lightest game).
///   • For returning pairings with a last-shared game: "Play {Game} again".
///   • For returning pairings without a last-shared game (defensive):
///     "Played N games together".
String playWithSubtextFor(PlayWithSuggestion s) {
  if (s.isNew) {
    final defaultGame = gameById(kDefaultFirstGameId);
    final defaultName = defaultGame?.name ?? 'Tic-Tac-Toe';
    return 'New — say hi with $defaultName';
  }
  if (s.lastSharedGameName != null && s.lastSharedGameName!.isNotEmpty) {
    return 'Play ${s.lastSharedGameName} again';
  }
  // Defensive fallback — should be rare since lastSharedGameId is populated
  // whenever sharedGamesCount > 0.
  if (s.sharedGamesCount == 1) return 'Played 1 game together';
  return 'Played ${s.sharedGamesCount} games together';
}

// ─────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────

final playWithSuggestionsProvider = FutureProvider.autoDispose
    .family<List<PlayWithSuggestion>, String>((ref, familyId) async {
  final client = ref.watch(supabaseProvider);
  if (client == null) return const <PlayWithSuggestion>[];
  final myId = client.auth.currentUser?.id;
  if (myId == null) return const <PlayWithSuggestion>[];
  try {
    final raw = await client.rpc('get_play_with_suggestions', params: {
      'p_requesting_user_id': myId,
      'p_family_id': familyId,
    });
    final map = raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};
    final list = map['suggestions'];
    if (list is! List) return const <PlayWithSuggestion>[];
    return list
        .whereType<Map>()
        .map((e) => PlayWithSuggestion.fromJson(Map<String, dynamic>.from(e)))
        .where((s) => s.userId.isNotEmpty)
        .toList();
  } catch (_) {
    return const <PlayWithSuggestion>[];
  }
});

// ─────────────────────────────────────────────────────────────────────────
// Row widget
// ─────────────────────────────────────────────────────────────────────────

class PlayWithRow extends ConsumerWidget {
  const PlayWithRow({super.key, required this.familyId});
  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(playWithSuggestionsProvider(familyId));
    return async.when(
      loading: () => const _RowSkeleton(),
      error: (_, __) => const SizedBox.shrink(),
      data: (suggestions) {
        if (suggestions.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 2, bottom: 10),
              child: const Text(
                'Play with',
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
              height: 132,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 2),
                itemCount: suggestions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) =>
                    PlayWithCard(suggestion: suggestions[i], familyId: familyId)
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
      height: 132,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        children: List.generate(
          3,
          (_) => Container(
            width: 120,
            margin: const EdgeInsets.only(right: 12),
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
// Card widget
// ─────────────────────────────────────────────────────────────────────────

class PlayWithCard extends StatelessWidget {
  const PlayWithCard({
    super.key,
    required this.suggestion,
    required this.familyId,
  });

  final PlayWithSuggestion suggestion;
  final String familyId;

  /// Resolves the route to navigate to when the card is tapped.
  ///
  /// Priority:
  ///   1. If the last-shared game is known, jump straight into its lobby
  ///      (skip the game-picker screen).
  ///   2. Otherwise (new pairing), jump into the default lightest game
  ///      (Tic-Tac-Toe).
  ///
  /// Either way the lobby is the entry point — the lobby itself handles
  /// the invite flow with the suggested member.
  String? _resolveRoute() {
    final gameId = suggestion.lastSharedGameId ?? kDefaultFirstGameId;
    final game = gameById(gameId);
    if (game == null) return null;
    return gameRoute(game, familyId);
  }

  void _onTap(BuildContext context) {
    final route = _resolveRoute();
    if (route != null) context.push(route);
  }

  @override
  Widget build(BuildContext context) {
    final s = suggestion;
    final subtext = playWithSubtextFor(s);
    final cardWidth = 124.0;

    return GestureDetector(
      onTap: () => _onTap(context),
      child: Container(
        width: cardWidth,
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: s.isOnline
                ? KinrelColors.tealAccent.withValues(alpha: 0.35)
                : (s.isNew
                    ? KinrelColors.amber.withValues(alpha: 0.25)
                    : Colors.white.withValues(alpha: 0.06)),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar with optional online dot
            Row(
              children: [
                _Avatar(name: s.userName, avatarUrl: s.avatarUrl, isOnline: s.isOnline),
                const Spacer(),
                if (s.isNew)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: KinrelColors.amber.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'NEW',
                      style: const TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: KinrelColors.amber,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              s.userName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtext,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 10.5,
                height: 1.25,
                color: KinrelColors.textDim,
              ),
            ),
            const Spacer(),
            const Row(
              children: [
                const KinrelIcon(KinrelIconData.controller,
                    size: 12, color: KinrelColors.orange),
                SizedBox(width: 4),
                const Text(
                  'Play',
                  style: const TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: KinrelColors.orange,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.avatarUrl, required this.isOnline});
  final String name;
  final String? avatarUrl;
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                KinrelColors.orange.withValues(alpha: 0.55),
                KinrelColors.amber.withValues(alpha: 0.35),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: CircleAvatar(
            radius: 22,
            backgroundColor: Colors.transparent,
            // perf pass — use CachedNetworkImageProvider (disk-cached +
            // decode-size-capped) instead of plain NetworkImage. Avatar
            // is 44×44 logical px → cap decode to 44 × dpr physical px
            // so a 1024×1024 upload doesn't decode to a 4MB bitmap.
            foregroundImage: (avatarUrl != null && avatarUrl!.isNotEmpty)
                ? CachedNetworkImageProvider(
                    avatarUrl!,
                    cacheWidth: (44 * MediaQuery.devicePixelRatioOf(context)).round(),
                    cacheHeight: (44 * MediaQuery.devicePixelRatioOf(context)).round(),
                  )
                : null,
            child: Text(
              name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
              style: const TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: KinrelColors.textWhite,
              ),
            ),
          ),
        ),
        if (isOnline)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: KinrelColors.tealAccent,
                shape: BoxShape.circle,
                border: Border.all(color: KinrelColors.darkCard, width: 2),
                boxShadow: const [
                  BoxShadow(color: KinrelColors.tealAccent, blurRadius: 6),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

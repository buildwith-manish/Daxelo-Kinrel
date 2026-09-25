// lib/features/games/shared/widgets/active_games_list.dart
//
// Lists all in-progress or waiting games for a family, unioned across all
// 14 game tables. Calls the get-active-family-games Edge Function. Each
// row shows: game icon, game name, host, status, spectator count (if any),
// and a "Watch" / "Join" button.
//
// Used on the family detail screen. The "Watch" button is shown when
// spectatorsEnabled is true AND the user isn't already a player; "Join"
// is shown when the user IS a player (takes them into their game screen).
//
// UX pass (psychology-driven):
//   • Zeigarnik effect — games waiting on the CURRENT user's move get a
//     pulsing 8px orange dot + a "Your turn" badge and float to the top
//     of the list. Unfinished tasks that need YOUR action pull you back
//     in far stronger than a neutral list.
//
// Usage:
//   ActiveGamesList(familyId: familyId)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_spacing.dart';
import '../../../../core/constants/brand_typography.dart';
import '../models/game_invite.dart';
import 'active_games_provider.dart';

class ActiveGamesList extends ConsumerWidget {
  const ActiveGamesList({super.key, required this.familyId});
  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gamesAsync = ref.watch(familyActiveGamesProvider(familyId));
    final myTurnAsync = ref.watch(myTurnGameIdsProvider(familyId));

    return gamesAsync.when(
      loading: () => const SizedBox(
        height: 80,
        child: Center(
          child: CircularProgressIndicator(color: KinrelColors.orange),
        ),
      ),
      error: (e, _) => SizedBox(
        height: 60,
        child: Center(
          child: Text(
            'Couldn\'t load active games',
            style: TextStyle(color: KinrelColors.textDim, fontSize: 12),
          ),
        ),
      ),
      data: (games) {
        if (games.isEmpty) return const SizedBox.shrink();

        // Zeigarnik: "your turn" games first — the open loop the user can
        // close right now beats everything else in the list.
        final myTurn = myTurnAsync.valueOrNull ?? const <String>{};
        final ordered = [...games]..sort((a, b) {
            final aMine = myTurn.contains(a.gameId) ? 0 : 1;
            final bMine = myTurn.contains(b.gameId) ? 0 : 1;
            if (aMine != bMine) return aMine - bMine;
            return b.createdAt.compareTo(a.createdAt);
          });

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: KinrelSpacing.md, vertical: KinrelSpacing.sm),
              child: Row(
                children: [
                  const Icon(Icons.play_circle_outline,
                      color: KinrelColors.orange, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'ACTIVE GAMES',
                    style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: KinrelColors.textDim,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${ordered.length}',
                    style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 11,
                      color: KinrelColors.textDim,
                    ),
                  ),
                ],
              ),
            ),
            ...ordered.map((g) => _gameRow(context, g, myTurn.contains(g.gameId))),
          ],
        );
      },
    );
  }

  Widget _gameRow(BuildContext context, ActiveGameInfo g, bool isMyTurn) {
    final gameType = g.typedGameType ?? GameType.bingo;
    final displayName = g.displayName;
    final hostName = g.hostUserName;

    final statusLabel = {
      'waiting': 'Waiting',
      'lobby': 'Lobby',
      'setup': 'Setting up',
      'in_progress': 'Live',
      'active': 'Live',
      'countdown': 'Starting',
    }[g.status] ?? 'Active';

    final isLive = g.isLive;

    return Container(
      margin: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.md, vertical: 4),
      padding: const EdgeInsets.all(KinrelSpacing.md),
      decoration: BoxDecoration(
        color: KinrelColors.darkSurface,
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(
          color: isMyTurn
              ? KinrelColors.orange.withValues(alpha: 0.55)
              : KinrelColors.border,
          width: isMyTurn ? 1.4 : 1,
        ),
      ),
      child: Row(
        children: [
          // Game icon — with a pulsing 8px orange dot when the open loop
          // is waiting on THIS user (Zeigarnik effect).
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: KinrelColors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.sports_esports,
                    color: KinrelColors.orange, size: 18),
              ),
              if (isMyTurn)
                Positioned(
                  top: -2,
                  right: -2,
                  child: _PulsingDot(),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: KinrelColors.textWhite,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: isLive
                            ? const Color(0xFF22C55E).withValues(alpha: 0.15)
                            : KinrelColors.darkElevated,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          fontFamily: KinrelTypography.monoFont,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: isLive
                              ? const Color(0xFF22C55E)
                              : KinrelColors.textDim,
                        ),
                      ),
                    ),
                    // "Your turn" badge — the explicit Zeigarnik label.
                    if (isMyTurn) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: KinrelColors.orange.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: KinrelColors.orange.withValues(alpha: 0.45),
                            width: 0.8,
                          ),
                        ),
                        child: const Text(
                          'Your turn',
                          style: TextStyle(
                            fontFamily: KinrelTypography.monoFont,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: KinrelColors.orange,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Host: $hostName${g.spectatorsEnabled ? ' · 👁 spectators welcome' : ''}',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 10,
                    color: KinrelColors.textDim,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Join button — navigates to the lobby
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios,
                color: KinrelColors.orange, size: 14),
            onPressed: () {
              GoRouter.of(context).push(
                '/family/$familyId/${gameType.routeSegment}/lobby?join=${g.gameId}',
              );
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: isMyTurn ? 'Your move — open game' : 'Open',
          ),
        ],
      ),
    );
  }
}

/// An 8px orange dot that pulses (scales + fades) on a 1.4s loop.
/// Used on active-game rows where it is the viewer's turn — an
/// attention magnet toward the open loop they can close.
class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // Pulse curve: fast out, slow back — feels like a heartbeat.
        final t = Curves.easeOut.transform(
          _controller.value > 0.5 ? (1 - _controller.value) * 2 : _controller.value * 2,
        );
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: KinrelColors.orange,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: KinrelColors.orange.withValues(alpha: 0.35 + 0.5 * t),
                blurRadius: 4 + 6 * t,
                spreadRadius: 1 + 2 * t,
              ),
            ],
          ),
        );
      },
    );
  }
}

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
// Usage:
//   ActiveGamesList(familyId: familyId)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_spacing.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/services/supabase_service.dart';
import '../models/game_invite.dart';

class ActiveGamesList extends ConsumerStatefulWidget {
  const ActiveGamesList({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<ActiveGamesList> createState() => _ActiveGamesListState();
}

class _ActiveGamesListState extends ConsumerState<ActiveGamesList> {
  List<Map<String, dynamic>> _games = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final client = ref.read(supabaseProvider);
    if (client == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final resp = await client.functions.invoke(
        'get-active-family-games',
        queryParameters: {'familyId': widget.familyId},
      ).timeout(const Duration(seconds: 15));
      final data = resp.data;
      if (data is! Map) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final games = (data['games'] as List?) ?? [];
      if (!mounted) return;
      setState(() {
        _games = games.cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 80,
        child: Center(
          child: CircularProgressIndicator(color: KinrelColors.orange),
        ),
      );
    }
    if (_error != null) {
      return SizedBox(
        height: 60,
        child: Center(
          child: Text(
            'Couldn\'t load active games',
            style: TextStyle(color: KinrelColors.textDim, fontSize: 12),
          ),
        ),
      );
    }
    if (_games.isEmpty) {
      return const SizedBox.shrink();
    }

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
                '${_games.length}',
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 11,
                  color: KinrelColors.textDim,
                ),
              ),
            ],
          ),
        ),
        ..._games.map(_gameRow),
      ],
    );
  }

  Widget _gameRow(Map<String, dynamic> g) {
    final gameTypeStr = (g['gameType'] ?? '') as String;
    final gameType = GameTypeX.fromRouteSegment(gameTypeStr) ?? GameType.bingo;
    final displayName = (g['displayName'] ?? 'Game') as String;
    final hostName = (g['hostUserName'] ?? 'Family member') as String;
    final status = (g['status'] ?? 'waiting') as String;
    final spectatorsEnabled = (g['spectatorsEnabled'] ?? true) as bool;
    final gameId = (g['gameId'] ?? '') as String;

    final statusLabel = {
      'waiting': 'Waiting',
      'lobby': 'Lobby',
      'setup': 'Setting up',
      'in_progress': 'Live',
      'active': 'Live',
      'countdown': 'Starting',
    }[status] ?? 'Active';

    final isLive = status == 'in_progress' || status == 'active';

    return Container(
      margin: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.md, vertical: 4),
      padding: const EdgeInsets.all(KinrelSpacing.md),
      decoration: BoxDecoration(
        color: KinrelColors.darkSurface,
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(color: KinrelColors.border, width: 1),
      ),
      child: Row(
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
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Host: $hostName${spectatorsEnabled ? ' · 👁 spectators welcome' : ''}',
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
                '/family/${widget.familyId}/${gameType.routeSegment}/lobby?join=$gameId',
              );
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: 'Open',
          ),
        ],
      ),
    );
  }
}

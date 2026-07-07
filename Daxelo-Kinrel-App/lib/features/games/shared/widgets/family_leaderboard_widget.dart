// lib/features/games/shared/widgets/family_leaderboard_widget.dart
//
// Shows per-family leaderboard for games. Watches fn_get_family_leaderboard
// RPC. Two display modes:
//   1. Overall (p_game_table = null): aggregates across all game types
//   2. Per-game (p_game_table = 'bingo_games'): filtered to one game type
//
// Renders as a compact list of (rank, avatar, name, W/L/D, winRate) rows.
// Used by the family detail screen's Leaderboard tab.
//
// Usage:
//   FamilyLeaderboardWidget(familyId: familyId)  // overall
//   FamilyLeaderboardWidget(familyId: familyId, gameTable: 'bingo_games')

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_spacing.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/services/supabase_service.dart';

class FamilyLeaderboardWidget extends ConsumerStatefulWidget {
  const FamilyLeaderboardWidget({
    super.key,
    required this.familyId,
    this.gameTable,
    this.maxRows = 20,
  });

  final String familyId;
  final String? gameTable; // null = overall across all games
  final int maxRows;

  @override
  ConsumerState<FamilyLeaderboardWidget> createState() =>
      _FamilyLeaderboardWidgetState();
}

class _FamilyLeaderboardWidgetState
    extends ConsumerState<FamilyLeaderboardWidget> {
  List<Map<String, dynamic>> _rows = [];
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
      final resp = await client.rpc(
        'fn_get_family_leaderboard',
        params: {
          'p_family_id': widget.familyId,
          'p_game_table': widget.gameTable,
        },
      ).timeout(const Duration(seconds: 10));
      final rows = (resp as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _rows = rows;
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
      return const Center(
        child: CircularProgressIndicator(color: KinrelColors.orange),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Couldn\'t load leaderboard: $_error',
          style: TextStyle(color: KinrelColors.error, fontSize: 12),
        ),
      );
    }
    if (_rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(KinrelSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.emoji_events_outlined,
                  color: KinrelColors.textDim, size: 48),
              const SizedBox(height: 12),
              Text(
                'No games completed yet',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Play a few games — winners will appear here.',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 11,
                  color: KinrelColors.textDim,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _rows.length > widget.maxRows ? widget.maxRows : _rows.length,
      separatorBuilder: (_, __) => const Divider(
          color: KinrelColors.border, height: 1, indent: 48),
      itemBuilder: (context, i) => _row(_rows[i], i + 1),
    );
  }

  Widget _row(Map<String, dynamic> r, int rank) {
    final wins = (r['wins'] ?? 0) as int;
    final losses = (r['losses'] ?? 0) as int;
    final draws = (r['draws'] ?? 0) as int;
    final gamesPlayed = (r['gamesPlayed'] ?? 0) as int;
    final winRate = ((r['winRate'] ?? 0) as num).toDouble();
    final name = (r['userName'] ?? 'Family member') as String;

    final medal = rank == 1 ? '🥇' : (rank == 2 ? '🥈' : (rank == 3 ? '🥉' : null));

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.md, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: medal != null
                ? Text(medal, style: const TextStyle(fontSize: 18))
                : Text(
                    '$rank',
                    style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: KinrelColors.textDim,
                    ),
                  ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: KinrelColors.orange.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.orange,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.textWhite,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$gamesPlayed games · $wins W · $losses L${draws > 0 ? ' · $draws D' : ''}',
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: winRate >= 0.5
                  ? const Color(0xFF22C55E).withValues(alpha: 0.15)
                  : KinrelColors.darkElevated,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${(winRate * 100).round()}%',
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: winRate >= 0.5
                    ? const Color(0xFF22C55E)
                    : KinrelColors.textDim,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

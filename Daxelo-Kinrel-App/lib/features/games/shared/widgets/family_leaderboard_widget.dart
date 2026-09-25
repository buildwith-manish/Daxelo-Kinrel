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
// UX pass — Loss Aversion (Kahneman & Tversky): ranks feel far more
// urgent when a small gap is framed as something the viewer can LOSE.
// When the player directly below is within 2 wins, the current user's
// row shows "⚠ {name} is {N} wins behind you"; when the player above
// is within 2 wins it shows "{N} wins to pass {name}". Both notices
// appear only on the viewer's own row.
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
import '../../../../core/widgets/person_avatar.dart';

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

    // Loss Aversion: only the viewer's own row carries gap notices.
    final notices = _lossAversionNotices(r, rank);

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.md, vertical: 10),
      child: Row(
        crossAxisAlignment: notices.isEmpty
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
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
                PersonAvatar.initialsFor(name),
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
                // Loss Aversion notices — chaser below / catchable above.
                ...notices,
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

  // ─────────────────────────────────────────────────────────────────
  // Loss Aversion helpers
  // ─────────────────────────────────────────────────────────────────

  /// Builds gap notices for the CURRENT USER's row only. Returns an
  /// empty list for everyone else.
  ///
  /// Two framings, both loss-scented:
  ///   • Chaser below within 2 wins  → "⚠ {name} is {N} wins behind you"
  ///     (your rank is at risk — the strongest loss-aversion trigger)
  ///   • Target above within 2 wins  → "{N} wins to pass {name}"
  ///     (a rank you're about to slip away from NOT winning)
  List<Widget> _lossAversionNotices(Map<String, dynamic> row, int rank) {
    final client = ref.read(supabaseProvider);
    final myId = client?.auth.currentUser?.id;
    if (myId == null) return const [];
    if ((row['userId'] ?? '') != myId) return const [];

    final myWins = (row['wins'] ?? 0) as int;
    final myIndex = rank - 1;
    final notices = <Widget>[];

    // Chaser directly below (only if that row is visible in _rows).
    if (myIndex + 1 < _rows.length) {
      final below = _rows[myIndex + 1];
      final gap = myWins - ((below['wins'] ?? 0) as int);
      if (gap >= 0 && gap <= 2) {
        final belowName = (below['userName'] ?? 'Family member') as String;
        final label = gap == 0
            ? '⚠ $belowName is tied with you — play now to stay ahead'
            : '⚠ $belowName is '
                '${gap == 1 ? '1 win' : '$gap wins'} behind you';
        notices.add(_gapNotice(label, KinrelColors.amber));
      }
    }

    // Catchable target directly above.
    if (myIndex - 1 >= 0) {
      final above = _rows[myIndex - 1];
      final gap = ((above['wins'] ?? 0) as int) - myWins;
      if (gap >= 0 && gap <= 2) {
        final aboveName = (above['userName'] ?? 'Family member') as String;
        final label = gap == 0
            ? 'Tied with $aboveName — one win takes the spot'
            : 'Only ${gap == 1 ? '1 win' : '$gap wins'} to pass $aboveName';
        notices.add(_gapNotice(label, KinrelColors.tealAccent));
      }
    }

    return notices;
  }

  Widget _gapNotice(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

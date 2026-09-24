// lib/features/prediction_battle_v1/pb_v1_recent_rounds_strip.dart
//
// Compact "Recent rounds" strip on the family hub — shows the top 3
// most-recently-revealed rounds for the family so users don't have
// to dig into the history screen to see recent activity. Each row
// is a single-line summary: date + question (truncated) + outcome
// pill (WON/PLAYED/MISSED). Tap → history screen.
//
// Why this matters
//   Before: 3 taps to reach the history screen (hub → card → "View
//   history"). After: 1 tap on any row. The strip surfaces the
//   engagement loop's payoff ("I won 2 days ago, missed yesterday")
//   without leaving the hub.
//
// The strip is hidden if there are no revealed rounds yet (e.g., a
// brand-new family). It does NOT load the history itself — it
// watches the existing pbV1HistoryProvider (which the history screen
// or the leaderboard may have already loaded). If neither has
// loaded yet, the strip shows a subtle "Loading recent rounds..."
// placeholder until the provider loads.
//
// The strip uses the SAME provider as the history screen so there's
// no duplicate RPC. The cost of rendering 3 rows on the hub is
// negligible; the cost of one extra history RPC (if no one else has
// triggered it yet) is acceptable since the user is on the hub
// anyway and the data will be reused when they tap into history.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/utils/app_time.dart';
import 'pb_v1_history_models.dart';
import 'pb_v1_history_provider.dart';

class PredictionBattleRecentRoundsStrip extends ConsumerStatefulWidget {
  const PredictionBattleRecentRoundsStrip({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<PredictionBattleRecentRoundsStrip> createState() =>
      _PredictionBattleRecentRoundsStripState();
}

class _PredictionBattleRecentRoundsStripState
    extends ConsumerState<PredictionBattleRecentRoundsStrip> {
  @override
  void initState() {
    super.initState();
    // Trigger the history load if it hasn't been triggered yet.
    // The provider's load() is idempotent — if it's already loaded,
    // the call is a no-op. This way the strip is useful even on
    // cold-start where the user hasn't opened the history screen
    // yet.
    Future.microtask(() =>
        ref.read(pbV1HistoryProvider(widget.familyId).notifier).load());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pbV1HistoryProvider(widget.familyId));

    // Hidden while loading AND no cache (avoids flicker on cold-start).
    if (state.isLoading && state.history == null) {
      return const SizedBox.shrink();
    }

    final rounds = state.history?.rounds ?? const [];
    if (rounds.isEmpty) {
      // No revealed rounds yet — hide the strip entirely. The hub
      // doesn't need to advertise an empty history.
      return const SizedBox.shrink();
    }

    // Show top 3.
    final top3 = rounds.take(3).toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: KinrelColors.border, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              const Icon(Icons.history, size: 14, color: KinrelColors.orange),
              const SizedBox(width: 6),
              Text(
                'RECENT ROUNDS',
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: KinrelColors.orange,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () =>
                    context.push('/family/${widget.familyId}/prediction-battle-v1/history'),
                child: Text(
                  'See all →',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.orange,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Rows
          for (final round in top3)
            _RecentRoundRow(round: round, familyId: widget.familyId),
        ],
      ),
    );
  }
}

class _RecentRoundRow extends StatelessWidget {
  const _RecentRoundRow({required this.round, required this.familyId});
  final PBv1HistoryRound round;
  final String familyId;

  @override
  Widget build(BuildContext context) {
    final (label, color) = round.myGuess == null
        ? ('MISSED', KinrelColors.textDim)
        : round.won
            ? ('WON', KinrelColors.brightGold)
            : ('PLAYED', KinrelColors.orange);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        // If the round is revealed (which it always is here, since
        // we're showing history), deep-link to the reveal screen for
        // this specific round.
        context.push('/family/$familyId/prediction-battle-v1/reveal/${round.roundId}');
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            // Date — short format "Sep 22"
            SizedBox(
              width: 44,
              child: Text(
                _formatDate(round.revealAt),
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 10,
                  color: KinrelColors.textDim,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Question — truncated to one line
            Expanded(
              child: Text(
                round.questionText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  color: KinrelColors.textSilver,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Outcome pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withValues(alpha: 0.30), width: 0.6),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime utc) {
    final ist = AppTime.toLocalDisplay(utc);
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[ist.month - 1]} ${ist.day}';
  }
}

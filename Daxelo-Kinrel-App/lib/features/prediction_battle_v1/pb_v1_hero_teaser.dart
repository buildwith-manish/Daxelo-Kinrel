// lib/features/prediction_battle_v1/pb_v1_hero_teaser.dart
//
// Small persistent teaser shown in the family hub Hero section. Sits
// in the slot that used to be occupied by the Truth Streak threshold
// teaser (removed in Phase 3). Drives engagement to the v1 Prediction
// Battle by surfacing a one-line state-of-the-round hint + a tiny
// progress bar.
//
// State mapping (mirrors pbV1Provider's state machine):
//
//   ┌──────────────────────┬─────────────────────────────────────────┐
//   │ Round state          │ Teaser text                              │
//   ├──────────────────────┼─────────────────────────────────────────┤
//   │ loading / no round   │ (hidden — returns SizedBox.shrink)       │
//   │ open + no guess       │ "Submit your prediction · 4h 23m left"   │
//   │ open + guess locked   │ "Guess locked · reveal in 4h 23m"       │
//   │ revealed + winner    │ "You won! 🎯 See the reveal →"          │
//   │ revealed + not won   │ "Reveal is in · See how close you got →"│
//   │ revealed + no guess  │ "Missed today's round · See who won →"  │
//   └──────────────────────┴─────────────────────────────────────────┘
//
// The teaser:
//   - Does NOT trigger the realtime WS subscription on its own (it just
//     reads the state). The card on the family hub below already does
//     that — when the card is scrolled into view, the provider's WS
//     channel opens and the teaser re-builds automatically.
//   - Does NOT call `load()` — it relies on whoever else has loaded
//     the provider for this family (the card or the reveal screen).
//     If neither has loaded yet, the teaser is hidden until they do.
//   - Is intentionally small (≤ 40 logical px tall) so it fits in the
//     hero's secondary text slot without crowding the family name.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import 'pb_v1_models.dart';
import 'pb_v1_provider.dart';

class PredictionBattleHeroTeaser extends ConsumerWidget {
  const PredictionBattleHeroTeaser({super.key, required this.familyId});

  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pbV1Provider(familyId));
    final countdown = ref.read(pbV1Provider(familyId).notifier).revealCountdown;
    final copy = TeaserCopy.forState(state, countdown);
    if (copy == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () => _onTap(context, state),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _bgColor(state).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _bgColor(state).withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_icon(state), style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                copy,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: _bgColor(state),
                ),
              ),
            ),
            if (state.revealed) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 12, color: _bgColor(state)),
            ],
          ],
        ),
      ),
    );
  }

  // ── Visual helpers (kept on the widget since they touch brand colors) ──

  String _icon(PBv1State state) {
    if (state.revealed) {
      final isWinner = state.myGuess != null && state.winnerUserIds.contains(state.myGuess!.userId);
      if (state.myGuess == null) return '👀';
      return isWinner ? '🎯' : '📊';
    }
    return state.myGuess == null ? '🔮' : '⏳';
  }

  Color _bgColor(PBv1State state) {
    if (state.revealed) {
      final isWinner = state.myGuess != null && state.winnerUserIds.contains(state.myGuess!.userId);
      return isWinner ? KinrelColors.brightGold : KinrelColors.orange;
    }
    return state.myGuess == null ? KinrelColors.orange : KinrelColors.amber;
  }

  void _onTap(BuildContext context, PBv1State state) {
    // If revealed, deep-link to the reveal screen; otherwise just
    // navigate to the family hub (which surfaces the card).
    final round = state.round;
    if (state.revealed && round != null) {
      context.push('/family/$familyId/prediction-battle-v1/reveal/${round.id}');
    }
    // No-op if not revealed — the user is already on the family hub,
    // so a tap just dismisses the row's hit-test affordance.
  }
}

/// Pure state → copy mapping for the hero teaser. Extracted as a
/// static method so it can be unit-tested without a widget tree.
///
/// The mapping is documented above in the file header. Returns null
/// when the teaser should be hidden (loading, no round, or empty
/// countdown with no guess yet).
class TeaserCopy {
  TeaserCopy._();

  static String? forState(PBv1State state, String countdown) {
    if (state.isLoading || state.round == null) return null;

    if (!state.revealed) {
      if (state.myGuess == null) {
        if (countdown.isEmpty) return null;
        return 'Submit your prediction · $countdown left';
      }
      // If the countdown is empty (e.g., reveal imminent), still
      // show "Guess locked · reveal imminent" — the user wants to
      // know they're locked in.
      return 'Guess locked · reveal in ${countdown.isEmpty ? 'imminent' : countdown}';
    }

    final isWinner = state.myGuess != null && state.winnerUserIds.contains(state.myGuess!.userId);
    if (state.myGuess == null) {
      return 'Missed today’s round · See who won';
    }
    if (isWinner) {
      return 'You won today’s prediction!';
    }
    return 'Reveal is in · See how close you got';
  }
}

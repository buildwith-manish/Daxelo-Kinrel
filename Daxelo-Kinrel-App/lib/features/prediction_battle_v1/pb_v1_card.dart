// lib/features/prediction_battle_v1/pb_v1_card.dart
//
// Prediction Battle v1 — the inline card on the family space-detail
// screen. Replaces the old "Truth Streak" card position.
//
// Card states:
//   1. OPEN, no guess: question + numeric input + Submit button
//   2. OPEN, guess locked in: "Guess locked in — reveal at {time}" + countdown
//   3. REVEALED: compact reveal summary (winner, your result, See full reveal link)
//
// ─────────────────────────────────────────────────────────────────────
// Phase 1.1 — visibility-gated realtime subscription
// ─────────────────────────────────────────────────────────────────────
// The card is wrapped in a VisibilityDetector that reports when at
// least 30% of the card is on-screen. The provider's realtime WS
// subscription is only opened while the card is visible, freeing a
// WebSocket connection while the user is scrolled above or below
// the card. On low-end devices this matters — Supabase bills per
// concurrent realtime channel, and most users never scroll down to
// the prediction section in a given session.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/utils/app_time.dart';
import 'pb_v1_models.dart';
import 'pb_v1_provider.dart';

class PredictionBattleV1Card extends ConsumerStatefulWidget {
  const PredictionBattleV1Card({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<PredictionBattleV1Card> createState() => _PredictionBattleV1CardState();
}

class _PredictionBattleV1CardState extends ConsumerState<PredictionBattleV1Card> {
  final _controller = TextEditingController();
  bool _submitting = false;
  // Unique key for VisibilityDetector — must be stable per widget instance.
  final _visibilityKey = ValueKey('pb_v1_card_${IdentityHash.next()}');

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(pbV1Provider(widget.familyId).notifier).load());
  }

  @override
  void dispose() {
    // Mark inactive so the provider tears down the WS channel even if
    // we never get an `onVisibilityChanged(false)` callback (e.g., the
    // user navigates away by pressing back).
    ref.read(pbV1Provider(widget.familyId).notifier).setActive(false);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final value = double.tryParse(_controller.text.trim());
    if (value == null) return;
    setState(() => _submitting = true);
    final ok = await ref.read(pbV1Provider(widget.familyId).notifier).submitGuess(value);
    if (mounted) {
      setState(() => _submitting = false);
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not submit — try again'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pbV1Provider(widget.familyId));
    final child = state.isLoading
        ? const _PBCardSkeleton()
        : (state.round == null || state.question == null
            ? const SizedBox.shrink()
            : _buildCard(context, state));

    // Wrap in VisibilityDetector so the provider can gate its realtime
    // WS subscription by whether the card is actually on-screen. 30%
    // threshold avoids flicker on partial scroll overshoots.
    return VisibilityDetector(
      key: _visibilityKey,
      child: child,
      onVisibilityChanged: (info) {
        final active = info.visibleFraction > 0.30;
        ref.read(pbV1Provider(widget.familyId).notifier).setActive(active);
      },
    );
  }

  Widget _buildCard(BuildContext context, PBv1State state) {
    final round = state.round!;
    final question = state.question!;
    final hasGuess = state.myGuess != null;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [const Color(0xFF241208), const Color(0xFF1A0E05), KinrelColors.darkCard],
        ),
        border: Border.all(color: KinrelColors.orange.withValues(alpha: 0.3), width: 1),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6)),
          BoxShadow(color: KinrelColors.orange.withValues(alpha: 0.15), blurRadius: 20, spreadRadius: 1),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: icon + title + status pill
            Row(
              children: [
                const Icon(Icons.gps_fixed, size: 24, color: KinrelColors.orange),
                const SizedBox(width: 8),
                Text('PREDICTION BATTLE', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 1.3, color: KinrelColors.textWhite)),
                const Spacer(),
                _StatusPill(status: round.status, revealed: state.revealed),
              ],
            ),
            const SizedBox(height: 12),
            // Question text
            Text(
              question.questionText,
              style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 16, fontWeight: FontWeight.w700, color: KinrelColors.textWhite, height: 1.3),
            ),
            if (question.unitLabel.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('(in ${question.unitLabel})', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim)),
            ],
            const SizedBox(height: 14),

            // State-specific content
            if (!state.revealed && !hasGuess) ...[
              // State 1: OPEN, no guess — show input
              TextField(
                controller: _controller,
                keyboardType: TextInputType.number,
                style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 18, color: KinrelColors.textWhite),
                decoration: InputDecoration(
                  hintText: 'Enter your guess...',
                  hintStyle: TextStyle(color: KinrelColors.textDim),
                  filled: true,
                  fillColor: KinrelColors.darkCard,
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: KinrelColors.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: KinrelColors.orange, width: 1.4)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(backgroundColor: KinrelColors.orange, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 12)),
                  child: _submitting
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Submit Guess', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Reveal at ${_formatRevealTime(round.revealAt)} · ${ref.read(pbV1Provider(widget.familyId).notifier).revealCountdown}',
                style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 11, color: KinrelColors.textDim),
              ),
            ] else if (!state.revealed && hasGuess) ...[
              // State 2: OPEN, guess locked in
              Row(
                children: [
                  const Icon(Icons.lock, size: 16, color: KinrelColors.amber),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Guess locked in — ${state.myGuess!.guessValue.toStringAsFixed(state.myGuess!.guessValue == state.myGuess!.guessValue.roundToDouble() ? 0 : 1)} ${question.unitLabel}',
                      style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, fontWeight: FontWeight.w600, color: KinrelColors.textWhite),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Reveal in ${ref.read(pbV1Provider(widget.familyId).notifier).revealCountdown}',
                style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.amber),
              ),
            ] else if (state.revealed) ...[
              // State 3: REVEALED — compact summary
              _RevealSummary(state: state, question: question, familyId: widget.familyId),
            ],
          ],
        ),
      ),
    );
  }

  String _formatRevealTime(DateTime utc) {
    final ist = AppTime.toLocalDisplay(utc);
    final hour = ist.hour > 12 ? ist.hour - 12 : (ist.hour == 0 ? 12 : ist.hour);
    final minute = ist.minute.toString().padLeft(2, '0');
    final ampm = ist.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $ampm IST';
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status, required this.revealed});
  final String status;
  final bool revealed;

  @override
  Widget build(BuildContext context) {
    final label = revealed ? 'REVEALED' : 'LIVE NOW';
    final color = revealed ? KinrelColors.orange : KinrelColors.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withValues(alpha: 0.40), width: 0.8)),
      child: Text(label, style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: color)),
    );
  }
}

class _RevealSummary extends StatelessWidget {
  const _RevealSummary({required this.state, required this.question, required this.familyId});
  final PBv1State state;
  final PBv1Question question;
  final String familyId;

  @override
  Widget build(BuildContext context) {
    final isWinner = state.myGuess != null && state.winnerUserIds.contains(state.myGuess!.userId);
    final myDistance = state.myGuess != null ? PBv1Scoring.distance(state.myGuess!.guessValue, question.correctAnswer) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Correct answer
        Text(
          'Answer: ${question.correctAnswer.toStringAsFixed(question.correctAnswer == question.correctAnswer.roundToDouble() ? 0 : 1)} ${question.unitLabel}',
          style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 18, fontWeight: FontWeight.w800, color: KinrelColors.brightGold),
        ),
        const SizedBox(height: 6),
        if (state.myGuess != null) ...[
          Row(
            children: [
              Icon(isWinner ? Icons.emoji_events : Icons.gps_fixed, size: 16, color: isWinner ? KinrelColors.brightGold : KinrelColors.textSilver),
              const SizedBox(width: 6),
              Text(
                isWinner ? 'You won! 🎯' : 'You guessed ${state.myGuess!.guessValue.toStringAsFixed(state.myGuess!.guessValue == state.myGuess!.guessValue.roundToDouble() ? 0 : 1)} — off by ${myDistance!.toStringAsFixed(question.correctAnswer > 1000 ? 1 : 0)}${question.correctAnswer > 1000 ? '%' : ''}',
                style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, fontWeight: FontWeight.w600, color: isWinner ? KinrelColors.brightGold : KinrelColors.textSilver),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => context.push('/family/$familyId/prediction-battle-v1/reveal/${state.round!.id}'),
          child: Text('See full reveal →', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, fontWeight: FontWeight.w700, color: KinrelColors.orange)),
        ),
      ],
    );
  }
}

class _PBCardSkeleton extends StatelessWidget {
  const _PBCardSkeleton();
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      height: 140,
      decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(20)),
      child: Center(child: CircularProgressIndicator(color: KinrelColors.orange.withValues(alpha: 0.5))),
    );
  }
}

/// Tiny process-wide counter so each card instance gets a unique key
/// for `VisibilityDetector`. `VisibilityDetector` requires unique keys
/// across the whole app — a familyId alone is not enough because the
/// card may be mounted in multiple places (e.g., main hub + a debug
/// route) at the same time.
class IdentityHash {
  static int _counter = 0;
  static int next() => _counter++;
}

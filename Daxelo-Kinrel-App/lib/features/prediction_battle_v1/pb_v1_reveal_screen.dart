// lib/features/prediction_battle_v1/pb_v1_reveal_screen.dart
//
// Full reveal view — all guesses sorted by proximity, correct answer,
// fun fact, winner highlight, coins awarded. Reachable via "See full
// reveal →" link from the card.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../family/providers/family_member_names_provider.dart';
import 'pb_v1_history_provider.dart';
import 'pb_v1_models.dart';
import 'pb_v1_provider.dart';
import 'pb_v1_rank_badge.dart';

class PBv1RevealScreen extends ConsumerStatefulWidget {
  const PBv1RevealScreen({super.key, required this.familyId, required this.roundId});
  final String familyId;
  final String roundId;

  @override
  ConsumerState<PBv1RevealScreen> createState() => _PBv1RevealScreenState();
}

class _PBv1RevealScreenState extends ConsumerState<PBv1RevealScreen> {
  @override
  void initState() {
    super.initState();
    // The reveal screen is a full-screen route — once we're here, the
    // card is NOT visible (it's behind the route stack), so we mark
    // the provider active to keep the WS subscription open for the
    // reveal transition.
    Future.microtask(() {
      ref.read(pbV1Provider(widget.familyId).notifier).load();
      ref.read(pbV1Provider(widget.familyId).notifier).setActive(true);
      // Phase 3.20 — use the shared family-member-names provider
      // (cache-first) instead of fetching names inline. This means
      // the ranked-guess list renders with real names on cold open
      // (from the LocalCacheService cache) instead of UUID prefixes
      // for ~500ms while the lookup completes.
      ref.read(familyMemberNamesProvider(widget.familyId).notifier).load();
    });
  }

  @override
  void dispose() {
    // On exit, mark inactive so the WS subscription gets torn down.
    // The card on the family hub will re-activate when the user scrolls
    // back to it.
    ref.read(pbV1Provider(widget.familyId).notifier).setActive(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pbV1Provider(widget.familyId));

    return Scaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        title: const Text('Prediction Reveal', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w700)),
        backgroundColor: KinrelColors.darkCard,
        foregroundColor: KinrelColors.textWhite,
        elevation: 0,
        actions: [
          // Phase 3.8 — Share reveal button. Lets the user share a
          // text summary of today's result to WhatsApp / SMS / etc.
          // Only shown after reveal (before reveal, there's nothing
          // to share).
          if (state.revealed && state.round != null && state.question != null)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Share result',
              onPressed: () => _shareResult(state),
            ),
        ],
      ),
      body: state.isLoading || state.round == null
          ? const Center(child: CircularProgressIndicator(color: KinrelColors.orange))
          : !state.revealed
              ? const Center(child: Text('Reveal has not happened yet', style: TextStyle(color: KinrelColors.textDim)))
              : _RevealBody(
                  state: state,
                  userNames: ref.watch(familyMemberNamesProvider(widget.familyId)).names,
                ),
    );
  }

  /// Phase 3.8 — Share today's result via the system share sheet.
  /// Builds a short text summary that works well in WhatsApp / SMS:
  ///
  ///   "I won today's Prediction Battle! 🎯
  ///    Question: How many X?
  ///    My guess: 42 (off by 0)
  ///    Current streak: 5 days
  ///    — Daxelo Kinrel"
  ///
  /// For non-winners, the copy is:
  ///   "Today's Prediction Battle: How many X?
  ///    Answer: 42. I guessed 45 — off by 3.
  ///    — Daxelo Kinrel"
  ///
  /// We intentionally DON'T include other family members' guesses
  /// in the shared text — privacy. The reveal screen itself shows
  /// the full ranked list, but the share text is just the user's
  /// own result.
  Future<void> _shareResult(PBv1State state) async {
    final question = state.question;
    final myGuess = state.myGuess;
    if (question == null) return;

    final isWinner = myGuess != null && state.winnerUserIds.contains(myGuess.userId);
    final answerStr = question.correctAnswer == question.correctAnswer.roundToDouble()
        ? question.correctAnswer.toInt().toString()
        : question.correctAnswer.toStringAsFixed(1);

    final buffer = StringBuffer();
    if (isWinner) {
      buffer.writeln('I won today\'s Prediction Battle! 🎯');
    } else {
      buffer.writeln('Today\'s Prediction Battle result:');
    }
    buffer.writeln('Question: ${question.questionText}');
    buffer.writeln('Answer: $answerStr ${question.unitLabel}');
    if (myGuess != null) {
      final guessStr = myGuess.guessValue == myGuess.guessValue.roundToDouble()
          ? myGuess.guessValue.toInt().toString()
          : myGuess.guessValue.toStringAsFixed(1);
      // Compute distance for the share text. Use the same logic as
      // PBv1Scoring.distance so the number matches what the user
      // sees on the screen.
      final distance = question.correctAnswer > 1000
          ? (myGuess.guessValue - question.correctAnswer).abs() / question.correctAnswer * 100
          : (myGuess.guessValue - question.correctAnswer).abs();
      final distanceStr = question.correctAnswer > 1000
          ? '${distance.toStringAsFixed(1)}%'
          : (distance == distance.roundToDouble() ? distance.toInt().toString() : distance.toStringAsFixed(1));
      buffer.writeln('My guess: $guessStr (off by $distanceStr)');
      if (isWinner) {
        // Pull the current streak from the history provider if it's
        // loaded — but don't block on it. If the history isn't loaded
        // yet, skip the streak line.
        try {
          final historyState = ref.read(pbV1HistoryProvider(widget.familyId));
          final streak = historyState.history?.streak.currentStreak;
          if (streak != null && streak > 0) {
            buffer.writeln('Current streak: $streak day${streak == 1 ? '' : 's'}');
          }
        } catch (_) {}
      }
    }
    buffer.writeln('— Daxelo Kinrel');

    await Share.share(buffer.toString().trim());
  }
}

class _RevealBody extends StatelessWidget {
  const _RevealBody({required this.state, required this.userNames});
  final PBv1State state;
  final Map<String, String> userNames;

  @override
  Widget build(BuildContext context) {
    final question = state.question!;
    final ranked = PBv1Scoring.rankGuesses(state.allGuesses, question.correctAnswer);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Question
        Text(question.questionText, style: const TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 18, fontWeight: FontWeight.w700, color: KinrelColors.textWhite)),
        const SizedBox(height: 8),
        // Correct answer
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: KinrelColors.brightGold.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: KinrelColors.brightGold.withValues(alpha: 0.3))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('CORRECT ANSWER', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: KinrelColors.brightGold)),
              const SizedBox(height: 6),
              Text(
                '${question.correctAnswer.toStringAsFixed(question.correctAnswer == question.correctAnswer.roundToDouble() ? 0 : 1)} ${question.unitLabel}',
                style: const TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 28, fontWeight: FontWeight.w800, color: KinrelColors.textWhite),
              ),
            ],
          ),
        ),
        // Fun fact
        if (question.funFactText.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: [
                const Icon(Icons.lightbulb_outline, size: 16, color: KinrelColors.amber),
                const SizedBox(width: 8),
                Expanded(child: Text(question.funFactText, style: const TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textSilver))),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        // Ranked guesses
        Text('Family Guesses', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 16, fontWeight: FontWeight.w700, color: KinrelColors.textWhite)),
        const SizedBox(height: 8),
        for (var i = 0; i < ranked.length; i++)
          _RankedGuessRow(
            rank: i + 1,
            guess: ranked[i]['guess'] as PBv1Guess,
            distance: ranked[i]['distance'] as double,
            isWinner: state.winnerUserIds.contains((ranked[i]['guess'] as PBv1Guess).userId),
            correctAnswer: question.correctAnswer,
            displayName: userNames[(ranked[i]['guess'] as PBv1Guess).userId] ??
                (ranked[i]['guess'] as PBv1Guess).userId.substring(0, 8),
          ),
      ],
    );
  }
}

class _RankedGuessRow extends StatelessWidget {
  const _RankedGuessRow({
    required this.rank,
    required this.guess,
    required this.distance,
    required this.isWinner,
    required this.correctAnswer,
    required this.displayName,
  });

  final int rank;
  final PBv1Guess guess;
  final double distance;
  final bool isWinner;
  final double correctAnswer;
  final String displayName;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isWinner ? KinrelColors.brightGold.withValues(alpha: 0.10) : KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isWinner ? KinrelColors.brightGold.withValues(alpha: 0.30) : KinrelColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          PBv1RankBadge(rank: rank),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              displayName,
              style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, fontWeight: isWinner ? FontWeight.w700 : FontWeight.w500, color: isWinner ? KinrelColors.textWhite : KinrelColors.textSilver),
            ),
          ),
          Text(
            guess.guessValue.toStringAsFixed(guess.guessValue == guess.guessValue.roundToDouble() ? 0 : 1),
            style: const TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 14, fontWeight: FontWeight.w800, color: KinrelColors.textWhite),
          ),
          const SizedBox(width: 8),
          Text(
            correctAnswer > 1000 ? '${distance.toStringAsFixed(1)}%' : distance.toStringAsFixed(distance == distance.roundToDouble() ? 0 : 1),
            style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 11, fontWeight: FontWeight.w700, color: isWinner ? KinrelColors.brightGold : KinrelColors.textDim),
          ),
        ],
      ),
    );
  }
}

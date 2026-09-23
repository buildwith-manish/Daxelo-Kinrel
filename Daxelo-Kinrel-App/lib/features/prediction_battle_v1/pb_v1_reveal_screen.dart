// lib/features/prediction_battle_v1/pb_v1_reveal_screen.dart
//
// Full reveal view — all guesses sorted by proximity, correct answer,
// fun fact, winner highlight, coins awarded. Reachable via "See full
// reveal →" link from the card.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/services/supabase_service.dart';
import 'pb_v1_models.dart';
import 'pb_v1_provider.dart';

class PBv1RevealScreen extends ConsumerStatefulWidget {
  const PBv1RevealScreen({super.key, required this.familyId, required this.roundId});
  final String familyId;
  final String roundId;

  @override
  ConsumerState<PBv1RevealScreen> createState() => _PBv1RevealScreenState();
}

class _PBv1RevealScreenState extends ConsumerState<PBv1RevealScreen> {
  // userId → display name. Filled once on screen open from the
  // FamilyMember table joined with User. We store the full map in
  // state so the rebuild on realtime update doesn't refetch.
  Map<String, String> _userNames = const {};

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
      _loadUserNames();
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

  Future<void> _loadUserNames() async {
    final client = ref.read(supabaseProvider);
    if (client == null) return;
    try {
      // Join FamilyMember → User to get a userId → name map for the
      // family that this round belongs to. We use a single select with
      // the nested User relation so it's one round-trip.
      final rows = await client
          .from('FamilyMember')
          .select('userId, user:User(name)')
          .eq('familyId', widget.familyId);
      if (!mounted) return;
      final map = <String, String>{};
      for (final r in (rows as List)) {
        final row = r as Map<String, dynamic>;
        final uid = (row['userId'] ?? '') as String;
        if (uid.isEmpty) continue;
        final user = row['user'];
        String name = uid.substring(0, 8); // fallback to UUID prefix
        if (user is Map && user['name'] is String && (user['name'] as String).isNotEmpty) {
          name = user['name'] as String;
        }
        map[uid] = name;
      }
      setState(() => _userNames = map);
    } catch (e) {
      // Best-effort — keep the UUID prefix fallback if this fails.
      debugPrint('[PBv1] _loadUserNames: $e');
    }
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
      ),
      body: state.isLoading || state.round == null
          ? const Center(child: CircularProgressIndicator(color: KinrelColors.orange))
          : !state.revealed
              ? const Center(child: Text('Reveal has not happened yet', style: TextStyle(color: KinrelColors.textDim)))
              : _RevealBody(state: state, userNames: _userNames),
    );
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
    const medals = ['🥇', '🥈', '🥉'];
    final medal = rank <= 3 ? medals[rank - 1] : '#$rank';
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
          SizedBox(width: 28, child: Text(medal, style: const TextStyle(fontSize: 14))),
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

// lib/features/games/twotruths/twotruths_results_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/dk_components.dart';
import '../game_motion_tokens.dart';
import 'twotruths_models.dart';
import 'twotruths_provider.dart';

class TtResultsScreen extends ConsumerStatefulWidget {
  const TtResultsScreen({super.key, required this.familyId, required this.gameId}); final String familyId; final String gameId;
  @override
  ConsumerState<TtResultsScreen> createState() => _TtResultsScreenState();
}
class _TtResultsScreenState extends ConsumerState<TtResultsScreen> {
  @override
  void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) { if (ref.read(ttProvider(widget.familyId)).game == null) ref.read(ttProvider(widget.familyId).notifier).joinGame(widget.gameId); }); }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ttProvider(widget.familyId)); final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final game = state.game;

    if (game == null) return DKScaffold(backgroundColor: KinrelColors.darkSurface, body: const Center(child: CircularProgressIndicator(color: KinrelColors.orange)));
    if (game.isCompleted) return _finalResultsView(state, myId);
    // If round not resolved yet, wait
    if (!game.roundResolved) return DKScaffold(backgroundColor: KinrelColors.darkSurface, body: const Center(child: CircularProgressIndicator(color: KinrelColors.orange)));

    final round = state.currentRound;
    if (round == null) return DKScaffold(backgroundColor: KinrelColors.darkSurface, body: const Center(child: CircularProgressIndicator(color: KinrelColors.orange)));

    final statements = [round.statement1, round.statement2, round.statement3];
    final lieIdx = round.lieIndex; // 1-based

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () { ref.read(ttProvider(widget.familyId).notifier).leaveGame(); if (context.canPop()) { context.pop(); } else { context.go('/family/${widget.familyId}'); } }),
        title: Text('Round ${game.currentRound} Results', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
        backgroundColor: KinrelColors.darkCard, foregroundColor: KinrelColors.textWhite, elevation: 0,
      ),
      body: ListView(padding: const EdgeInsets.all(KinrelSpacing.base), children: [
        // Statements with lie revealed
        ...statements.asMap().entries.map((entry) {
          final i = entry.key; final text = entry.value; final isLie = (i + 1) == lieIdx;
          return Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isLie ? KinrelColors.error : KinrelColors.success, width: isLie ? 2 : 1)),
            child: Row(children: [
              Container(width: 28, height: 28, decoration: BoxDecoration(shape: BoxShape.circle, color: isLie ? KinrelColors.error : KinrelColors.success),
                child: Center(child: Icon(isLie ? Icons.close : Icons.check, size: 16, color: Colors.white))),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, fontWeight: FontWeight.w600, color: KinrelColors.textWhite))),
              if (isLie) Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: KinrelColors.error, borderRadius: BorderRadius.circular(4)),
                child: Text('LIE', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white))),
            ]),
          ).animate().fadeIn(duration: 300.ms, delay: (i * 200).ms).slideY(begin: 0.1, end: 0, duration: 300.ms);
        }),

        const SizedBox(height: 20),
        // Guesses
        if (state.guesses.isNotEmpty) ...[
          Text('GUESSES', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 11, fontWeight: FontWeight.w700, color: KinrelColors.textDim, letterSpacing: 1.5)),
          const SizedBox(height: 8),
          ...state.guesses.map((g) {
            final isCorrect = g.isCorrect ?? false;
            return Container(margin: const EdgeInsets.only(bottom: 4), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(8), border: Border.all(color: KinrelColors.border)),
              child: Row(children: [
                DKAvatar(initials: g.guesserName.isNotEmpty ? g.guesserName[0].toUpperCase() : '?'),
                const SizedBox(width: 8),
                Expanded(child: Text(g.guesserName, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, fontWeight: FontWeight.w600, color: KinrelColors.textWhite))),
                Text('guessed #${g.guessedLieIndex}', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 11, color: KinrelColors.textDim)),
                const SizedBox(width: 6),
                Icon(isCorrect ? Icons.check_circle : Icons.cancel, size: 16, color: isCorrect ? KinrelColors.success : KinrelColors.error),
              ]));
          }),
        ],

        const SizedBox(height: 20),
        // Scores
        Text('TOTAL SCORES', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 11, fontWeight: FontWeight.w700, color: KinrelColors.textDim, letterSpacing: 1.5)),
        const SizedBox(height: 8),
        ...state.players.map((p) => Container(margin: const EdgeInsets.only(bottom: 4), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.userId == myId ? KinrelColors.orange : KinrelColors.border)),
          child: Row(children: [
            DKAvatar(initials: p.userName.isNotEmpty ? p.userName[0].toUpperCase() : '?'),
            const SizedBox(width: 8),
            Expanded(child: Text(p.userId == myId ? '${p.userName} (You)' : p.userName, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, fontWeight: FontWeight.w600, color: KinrelColors.textWhite))),
            Text('${p.totalScore}', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 14, fontWeight: FontWeight.w800, color: KinrelColors.orange)),
          ]))),

        const SizedBox(height: 24),
        DKButton(label: game.currentRound >= game.totalRounds ? 'See Final Results' : 'Next Round',
          variant: DKButtonVariant.gradient, fullWidth: true, icon: game.currentRound >= game.totalRounds ? Icons.emoji_events : Icons.arrow_forward,
          onPressed: () => ref.read(ttProvider(widget.familyId).notifier).advanceOrEnd()),
      ]),
    );
  }

  Widget _finalResultsView(TtState state, String? myId) {
    final game = state.game!; final winners = game.winnerUserIds ?? []; final winnerNames = game.winnerNames ?? [];
    final isMyWin = winners.contains(myId); final sorted = List<TtPlayer>.from(state.players)..sort((a, b) => b.totalScore.compareTo(a.totalScore));
    return DKScaffold(
      gradient: isMyWin ? KinrelGradients.deepFireGradient : null,
      backgroundColor: isMyWin ? null : KinrelColors.darkSurface,
      appBar: AppBar(automaticallyImplyLeading: false,
        title: Text('Final Results', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
        backgroundColor: Colors.transparent, foregroundColor: KinrelColors.textWhite, elevation: 0),
      body: ListView(padding: const EdgeInsets.all(KinrelSpacing.base), children: [
        const SizedBox(height: KinrelSpacing.lg),
        Column(children: [
          Text('🏆', style: TextStyle(fontSize: 64)).animate(onPlay: (c) => c.forward()).fadeIn(duration: 500.ms).scale(begin: const Offset(0.5, 0.5), end: const Offset(1.0, 1.0), duration: 500.ms, curve: Curves.elasticOut),
          const SizedBox(height: KinrelSpacing.sm),
          Text(isMyWin ? (winners.length > 1 ? 'Joint Winners!' : 'You Won!') : (winners.length > 1 ? 'Joint Winners!' : 'Winner!'),
            style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 28, fontWeight: FontWeight.w800, color: KinrelColors.textWhite, letterSpacing: 2)),
          const SizedBox(height: KinrelSpacing.sm),
          Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center,
            children: winnerNames.map((n) => Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: KinrelColors.orange.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(14), border: Border.all(color: KinrelColors.orange)),
              child: Text(n, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, fontWeight: FontWeight.w700, color: KinrelColors.orange)))).toList()),
        ]).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.92, 0.92), end: const Offset(1.0, 1.0), duration: 400.ms, curve: Curves.easeOutBack),
        const SizedBox(height: KinrelSpacing.xl),
        ...sorted.asMap().entries.map((entry) {
          final rank = entry.key + 1; final p = entry.value;
          final medal = rank == 1 ? '🥇' : rank == 2 ? '🥈' : rank == 3 ? '🥉' : '$rank';
          return Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.userId == myId ? KinrelColors.orange : KinrelColors.border, width: p.userId == myId ? 2 : 1)),
            child: Row(children: [SizedBox(width: 28, child: Text(medal, style: TextStyle(fontSize: 16))), DKAvatar(initials: p.userName.isNotEmpty ? p.userName[0].toUpperCase() : '?'),
              const SizedBox(width: 8), Expanded(child: Text(p.userId == myId ? '${p.userName} (You)' : p.userName, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, fontWeight: FontWeight.w600, color: KinrelColors.textWhite))),
              Text('${p.totalScore}', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 16, fontWeight: FontWeight.w800, color: KinrelColors.orange))]));
        }),
        const SizedBox(height: KinrelSpacing.xxl),
        DKButton(label: 'Play Again', variant: DKButtonVariant.gradient, fullWidth: true, icon: Icons.refresh_rounded,
          onPressed: () { ref.read(ttProvider(widget.familyId).notifier).leaveGame(); if (context.mounted) context.pushReplacement('/family/${widget.familyId}/twotruths/lobby'); }),
        const SizedBox(height: 8),
        DKButton(label: 'Back to Hub', variant: DKButtonVariant.secondary, fullWidth: true,
          onPressed: () { ref.read(ttProvider(widget.familyId).notifier).leaveGame(); if (context.mounted) context.go('/games?familyId=${widget.familyId}'); }),
      ]),
    );
  }
}

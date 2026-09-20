import '../../../core/widgets/person_avatar.dart';
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
import '../shared/icons/kinrel_icons.dart';
import '../shared/widgets/game_board_shell.dart';
import '../shared/models/game_invite.dart';
import '../shared/widgets/game_confetti.dart';
import '../shared/widgets/rematch_button.dart';
import 'twotruths_models.dart';
import 'twotruths_provider.dart';
import '../../gaming_ecosystem/presentation/match_ecosystem_summary.dart';

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
    // Round in flight (started but not resolved) — route players instead
    // of spinning forever.
    if (!game.roundResolved) return _roundInFlightView(state, myId);

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
          return _revealCard(i, text, isLie)
            .animate().fadeIn(duration: 300.ms, delay: (i * 200).ms).slideY(begin: 0.1, end: 0, duration: 300.ms)
            .scale(begin: const Offset(0.92, 0.92), end: const Offset(1.0, 1.0), duration: 350.ms, curve: Curves.easeOutBack);
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
                DKAvatar(initials: PersonAvatar.initialsFor(g.guesserName)),
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
          decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.userId == myId ? KinrelColors.orange.withValues(alpha: 0.6) : KinrelColors.border)),
          child: Row(children: [
            DKAvatar(initials: PersonAvatar.initialsFor(p.userName)),
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

  /// Round in flight (started but not yet resolved). If the current
  /// round's statements are already in, everyone moves on to guessing;
  /// otherwise the new submitter gets a "write your statements" prompt
  /// and the rest wait on them — fixes the round-2+ dead-end where the
  /// results screen spun forever and nobody routed back to the submit
  /// flow.
  Widget _roundInFlightView(TtState state, String? myId) {
    final game = state.game!;
    final round = state.currentRound;
    final statementsIn = round != null && round.roundNumber == game.currentRound;
    if (statementsIn && mounted) { WidgetsBinding.instance.addPostFrameCallback((_) => context.pushReplacement('/family/${widget.familyId}/twotruths/guess/${widget.gameId}')); }
    final amSubmitter = game.currentSubmitterId == myId;
    final submitterName = state.players.where((p) => p.userId == game.currentSubmitterId).firstOrNull?.userName ?? 'Player';
    return DKScaffold(backgroundColor: KinrelColors.darkSurface, body: Center(child: Padding(padding: const EdgeInsets.all(KinrelSpacing.base), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      if (amSubmitter) ...[
        Icon(Icons.edit_note_rounded, size: 52, color: KinrelColors.orange),
        const SizedBox(height: 16),
        Text("You're up — write your two truths!", textAlign: TextAlign.center, style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 20, fontWeight: FontWeight.w800, color: KinrelColors.textWhite)),
        const SizedBox(height: 6),
        Text('Round ${game.currentRound}/${game.totalRounds}', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 12, fontWeight: FontWeight.w700, color: KinrelColors.textDim)),
        const SizedBox(height: 24),
        DKButton(label: 'Write Your Statements', variant: DKButtonVariant.gradient, fullWidth: true, icon: Icons.edit_rounded, onPressed: () => context.pushReplacement('/family/${widget.familyId}/twotruths/submit/${widget.gameId}')),
      ] else
        GameTurnPill(label: 'Waiting for $submitterName to write their statements…', color: KinrelColors.orange, active: true, trailing: const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: KinrelColors.orange))),
    ]))));
  }

  /// Premium reveal card — layered dark surface with an accent glow in
  /// the top-left corner, numbered chip and tinted border. Truths get a
  /// success tint + check badge; the lie gets a coral tint + LIE badge.
  Widget _revealCard(int i, String text, bool isLie) {
    final accent = isLie ? KinrelColors.coral : KinrelColors.success;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Color.lerp(KinrelColors.darkCard, accent, 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: isLie ? 0.75 : 0.5), width: isLie ? 1.5 : 1),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.32), blurRadius: 10, offset: const Offset(0, 4)),
          BoxShadow(color: accent.withValues(alpha: 0.12), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(children: [
          // Subtle accent glow in the top-left corner.
          Positioned(top: -36, left: -36, child: Container(width: 130, height: 130, decoration: BoxDecoration(shape: BoxShape.circle,
            gradient: RadialGradient(colors: [accent.withValues(alpha: 0.14), accent.withValues(alpha: 0.0)])))),
          Padding(padding: const EdgeInsets.all(14), child: Row(children: [
            Container(width: 28, height: 28, alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: accent.withValues(alpha: 0.18), border: Border.all(color: accent.withValues(alpha: 0.7))),
              child: Icon(isLie ? Icons.close : Icons.check, size: 15, color: accent)),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, fontWeight: FontWeight.w600, color: KinrelColors.textWhite))),
            const SizedBox(width: 8),
            Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: accent.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(4)),
              child: Text(isLie ? 'LIE' : '0${i + 1}', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white))),
          ])),
        ]),
      ),
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
      body: Stack(children: [
        ListView(padding: const EdgeInsets.all(KinrelSpacing.base), children: [
        const SizedBox(height: KinrelSpacing.lg),
        Column(children: [
          KinrelIcon(KinrelIconData.trophy, size: 64, color: KinrelColors.brightGold).animate(onPlay: (c) => c.forward()).fadeIn(duration: 500.ms).scale(begin: const Offset(0.5, 0.5), end: const Offset(1.0, 1.0), duration: 500.ms, curve: Curves.elasticOut),
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
            child: Row(children: [SizedBox(width: 28, child: Text(medal, style: TextStyle(fontSize: 16))), DKAvatar(initials: PersonAvatar.initialsFor(p.userName)),
              const SizedBox(width: 8), Expanded(child: Text(p.userId == myId ? '${p.userName} (You)' : p.userName, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, fontWeight: FontWeight.w600, color: KinrelColors.textWhite))),
              Text('${p.totalScore}', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 16, fontWeight: FontWeight.w800, color: KinrelColors.orange))]));
        }),
        MatchEcosystemSummary(
          gameTable: 'twotruths_games',
          gameId: widget.gameId,
          familyId: widget.familyId,
        ),
        const SizedBox(height: KinrelSpacing.xxl),
        // Host: one-tap rematch — same mode/rounds/timer, invites everyone.
        if (game.hostUserId == myId)
          RematchButton(
            familyId: widget.familyId,
            gameType: GameType.twotruths,
            previousGameId: game.id,
            participantUserIds:
                state.players.map((p) => p.userId).toList(),
            maxPlayers: 8,
            onCreateNewGame: () => ref
                .read(ttProvider(widget.familyId).notifier)
                .createGame(
                  mode: game.mode,
                  totalRounds: game.totalRounds,
                  roundTimerSeconds: game.roundTimerSeconds,
                ),
          )
        else
          DKButton(label: 'Play Again', variant: DKButtonVariant.gradient, fullWidth: true, icon: Icons.refresh_rounded,
            onPressed: () { ref.read(ttProvider(widget.familyId).notifier).leaveGame(); if (context.mounted) context.pushReplacement('/family/${widget.familyId}/twotruths/lobby'); }),
        const SizedBox(height: 8),
        DKButton(label: 'Back to Hub', variant: DKButtonVariant.secondary, fullWidth: true,
          onPressed: () { ref.read(ttProvider(widget.familyId).notifier).leaveGame(); if (context.mounted) context.go('/games?familyId=${widget.familyId}'); }),
        ]),
        // Winner celebration — the player with the most correct guesses.
        if (isMyWin)
          const Positioned.fill(
            child: IgnorePointer(child: GameConfetti(burstCount: 2, density: 2)),
          ),
      ]),
    );
  }
}

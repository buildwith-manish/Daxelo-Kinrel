import '../../../core/widgets/person_avatar.dart';
// lib/features/games/nameplace/nameplace_results_screen.dart
// Route: /family/$familyId/nameplace/results/:gameId
//
// Shows round results (answers side by side with points) and
// final game results with confetti if game is over.

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
import 'nameplace_provider.dart';

class NameplaceResultsScreen extends ConsumerStatefulWidget {
  const NameplaceResultsScreen({super.key, required this.familyId, required this.gameId});
  final String familyId;
  final String gameId;
  @override
  ConsumerState<NameplaceResultsScreen> createState() => _NameplaceResultsScreenState();
}

class _NameplaceResultsScreenState extends ConsumerState<NameplaceResultsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(nameplaceProvider(widget.familyId));
      if (state.game == null) ref.read(nameplaceProvider(widget.familyId).notifier).joinGame(widget.gameId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(nameplaceProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final game = state.game;

    if (game == null) {
      return DKScaffold(backgroundColor: KinrelColors.darkSurface, body: const Center(child: CircularProgressIndicator(color: KinrelColors.orange)));
    }

    // If game completed → show final results
    if (game.isCompleted) {
      return _finalResultsView(state, myId);
    }

    // If next round is starting → navigate to letter pick
    if (!game.roundScoringDone && game.currentLetter == null && game.isInProgress) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.pushReplacement('/family/${widget.familyId}/nameplace/letter/${widget.gameId}');
      });
    }

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () { ref.read(nameplaceProvider(widget.familyId).notifier).leaveGame(); if (context.canPop()) { context.pop(); } else { context.go('/family/${widget.familyId}'); } }),
        title: Text('Round ${game.currentRound} Results', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
        backgroundColor: KinrelColors.darkCard, foregroundColor: KinrelColors.textWhite, elevation: 0,
      ),
      body: state.isLoading
        ? const Center(child: CircularProgressIndicator(color: KinrelColors.orange))
        : _roundResultsView(state, game),
    );
  }

  Widget _roundResultsView(state, game) {
    final answers = state.answers;
    final categories = game.categories;
    final players = state.players;

    return ListView(padding: const EdgeInsets.all(KinrelSpacing.base), children: [
      // Letter display
      Center(child: Text('Letter: ${game.currentLetter}', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 24, fontWeight: FontWeight.w800, color: KinrelColors.orange))),
      const SizedBox(height: KinrelSpacing.lg),

      // Per-category results
      ...categories.map((cat) {
        final catAnswers = answers.where((a) => a.category == cat).toList();
        return Container(
          margin: const EdgeInsets.only(bottom: KinrelSpacing.md),
          padding: const EdgeInsets.all(KinrelSpacing.md),
          decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(KinrelRadius.lg), border: Border.all(color: KinrelColors.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(cat.toUpperCase(), style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 12, fontWeight: FontWeight.w700, color: KinrelColors.orange, letterSpacing: 1)),
            const SizedBox(height: 6),
            ...catAnswers.map((a) {
              final points = a.pointsAwarded ?? 0;
              final isUnique = points == 10;
              final isDuplicate = points == 5;
              final isDash = a.answerText.trim() == '-';
              final isMe = a.playerId == ref.read(supabaseProvider)?.auth.currentUser?.id;
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  Expanded(child: Text(
                    isDash ? '—' : a.answerText,
                    style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13,
                      color: isDash ? KinrelColors.textDim : (isMe ? KinrelColors.textWhite : KinrelColors.textSilver),
                      fontWeight: isMe ? FontWeight.w700 : FontWeight.w400,
                      decoration: isDash ? TextDecoration.lineThrough : null),
                  )),
                  if (isMe) Text('(You) ', style: TextStyle(fontSize: 10, color: KinrelColors.orange)),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: isUnique ? KinrelColors.success.withValues(alpha: 0.2) : (isDuplicate ? KinrelColors.warning.withValues(alpha: 0.2) : KinrelColors.darkElevated),
                      borderRadius: BorderRadius.circular(4)),
                    child: Text('${points}pt', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 11, fontWeight: FontWeight.w700,
                      color: isUnique ? KinrelColors.success : (isDuplicate ? KinrelColors.warning : KinrelColors.textDim))),
                  ),
                ]),
              );
            }),
          ]),
        )
          .animate().fadeIn(duration: 300.ms).slideY(begin: 0.05, end: 0, duration: 300.ms);
      }),

      const SizedBox(height: KinrelSpacing.lg),
      // Running totals
      _sectionLabel('Total Scores'),
      const SizedBox(height: KinrelSpacing.sm),
      ...players.map((p) => Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.md, vertical: KinrelSpacing.sm),
        decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.userId == ref.read(supabaseProvider)?.auth.currentUser?.id ? KinrelColors.orange : KinrelColors.border)),
        child: Row(children: [
          DKAvatar(initials: PersonAvatar.initialsFor(p.userName)?'),
          const SizedBox(width: KinrelSpacing.sm),
          Expanded(child: Text(p.userId == ref.read(supabaseProvider)?.auth.currentUser?.id ? '${p.userName} (You)' : p.userName,
            style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, color: KinrelColors.textWhite, fontWeight: FontWeight.w600))),
          Text('${p.totalScore}', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 16, fontWeight: FontWeight.w800, color: KinrelColors.orange)),
        ]),
      )),
      const SizedBox(height: KinrelSpacing.xl),
      if (game.hostUserId == ref.read(supabaseProvider)?.auth.currentUser?.id && game.currentRound < game.totalRounds)
        Text('Next round starting automatically...', textAlign: TextAlign.center, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim))
      else
        Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: KinrelColors.orange))),
    ]);
  }

  Widget _finalResultsView(state, String? myId) {
    final game = state.game!;
    final winners = game.winnerUserIds ?? [];
    final winnerNames = game.winnerNames ?? [];
    final isMyWin = winners.contains(myId);
    final sortedPlayers = List.from(state.players)..sort((a, b) => b.totalScore.compareTo(a.totalScore));

    return DKScaffold(
      gradient: isMyWin ? KinrelGradients.deepFireGradient : null,
      backgroundColor: isMyWin ? null : KinrelColors.darkSurface,
      appBar: AppBar(automaticallyImplyLeading: false,
        title: Text('Final Results', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
        backgroundColor: Colors.transparent, foregroundColor: KinrelColors.textWhite, elevation: 0),
      body: ListView(padding: const EdgeInsets.all(KinrelSpacing.base), children: [
        const SizedBox(height: KinrelSpacing.lg),
        Column(children: [
          Text(winners.length > 1 ? '🏆' : '🏆', style: TextStyle(fontSize: 64))
            .animate(onPlay: (c) => c.forward()).fadeIn(duration: 500.ms).scale(begin: const Offset(0.5, 0.5), end: const Offset(1.0, 1.0), duration: 500.ms, curve: Curves.elasticOut),
          const SizedBox(height: KinrelSpacing.sm),
          Text(isMyWin ? (winners.length > 1 ? 'Joint Winners!' : 'You Won!') : (winners.length > 1 ? 'Joint Winners!' : 'Winner!'),
            style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 28, fontWeight: FontWeight.w800, color: KinrelColors.textWhite, letterSpacing: 2)),
          const SizedBox(height: KinrelSpacing.sm),
          Wrap(spacing: KinrelSpacing.sm, runSpacing: KinrelSpacing.sm, alignment: WrapAlignment.center,
            children: winnerNames.map((name) => Container(padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.md, vertical: KinrelSpacing.sm),
              decoration: BoxDecoration(color: KinrelColors.orange.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(KinrelRadius.lg), border: Border.all(color: KinrelColors.orange)),
              child: Text(name, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, fontWeight: FontWeight.w700, color: KinrelColors.orange)))).toList(),
          ),
        ]).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.92, 0.92), end: const Offset(1.0, 1.0), duration: 400.ms, curve: Curves.easeOutBack),
        const SizedBox(height: KinrelSpacing.xl),
        // Final standings
        ...sortedPlayers.asMap().entries.map((entry) {
          final rank = entry.key + 1;
          final p = entry.value;
          final medal = rank == 1 ? '🥇' : rank == 2 ? '🥈' : rank == 3 ? '🥉' : '$rank';
          return Container(margin: const EdgeInsets.only(bottom: KinrelSpacing.sm), padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.md, vertical: KinrelSpacing.md),
            decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(KinrelRadius.lg), border: Border.all(color: p.userId == myId ? KinrelColors.orange : KinrelColors.border, width: p.userId == myId ? 2 : 1)),
            child: Row(children: [
              SizedBox(width: 30, child: Text(medal, style: TextStyle(fontSize: 16))),
              DKAvatar(initials: PersonAvatar.initialsFor(p.userName)?'),
              const SizedBox(width: KinrelSpacing.sm),
              Expanded(child: Text(p.userId == myId ? '${p.userName} (You)' : p.userName, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, fontWeight: FontWeight.w600, color: KinrelColors.textWhite))),
              Text('${p.totalScore} pts', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 16, fontWeight: FontWeight.w800, color: KinrelColors.orange)),
            ]),
          );
        }),
        const SizedBox(height: KinrelSpacing.xxl),
        DKButton(label: 'Play Again', variant: DKButtonVariant.gradient, fullWidth: true, icon: Icons.refresh_rounded,
          onPressed: () { ref.read(nameplaceProvider(widget.familyId).notifier).leaveGame(); if (context.mounted) context.pushReplacement('/family/${widget.familyId}/nameplace/lobby'); }),
        const SizedBox(height: KinrelSpacing.sm),
        DKButton(label: 'Back to Hub', variant: DKButtonVariant.secondary, fullWidth: true,
          onPressed: () { ref.read(nameplaceProvider(widget.familyId).notifier).leaveGame(); if (context.mounted) context.go('/games?familyId=${widget.familyId}'); }),
      ]),
    );
  }

  Widget _sectionLabel(String text) => Text(text, style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 13, fontWeight: FontWeight.w600, color: KinrelColors.textDim, letterSpacing: 0.5));
}

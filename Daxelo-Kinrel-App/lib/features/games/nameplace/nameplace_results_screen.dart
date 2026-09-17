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
import '../shared/icons/kinrel_icons.dart';
import '../shared/widgets/game_confetti.dart';
import 'nameplace_provider.dart';
import '../../gaming_ecosystem/presentation/match_ecosystem_summary.dart';

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
    final maxScore = players.fold<int>(1, (m, p) => p.totalScore > m ? p.totalScore : m);

    return ListView(padding: const EdgeInsets.all(KinrelSpacing.base), children: [
      // Letter display
      Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('LETTER', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 11, fontWeight: FontWeight.w700, color: KinrelColors.textDim, letterSpacing: 1.5)),
        const SizedBox(width: 10),
        Container(width: 40, height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const RadialGradient(center: Alignment(-0.4, -0.4), radius: 1.25, colors: [Color(0xFFFFFDF6), Color(0xFFE7E0D4)]),
            border: Border.all(color: const Color(0xFFD9D3C7)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 8, offset: const Offset(0, 3))],
          ),
          child: Center(child: Text(game.currentLetter ?? '?', style: const TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF2A2118)))),
        ),
      ])),
      const SizedBox(height: KinrelSpacing.lg),

      // Per-category results
      ...categories.map((cat) {
        final catAnswers = answers.where((a) => a.category == cat).toList();
        final (catAccent, catIcon) = _categoryStyle(cat);
        return Container(
          margin: const EdgeInsets.only(bottom: KinrelSpacing.md),
          padding: const EdgeInsets.all(KinrelSpacing.md),
          decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(KinrelRadius.lg), border: Border.all(color: KinrelColors.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 26, height: 26, decoration: BoxDecoration(shape: BoxShape.circle, color: catAccent.withValues(alpha: 0.14), border: Border.all(color: catAccent.withValues(alpha: 0.45))),
                child: Center(child: Icon(catIcon, size: 14, color: catAccent))),
              const SizedBox(width: 8),
              Text(cat.toUpperCase(), style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 12, fontWeight: FontWeight.w700, color: catAccent, letterSpacing: 1)),
            ]),
            const SizedBox(height: 8),
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
      ...players.asMap().entries.map((entry) => _scoreCard(entry.value, entry.key, maxScore,
        isMe: entry.value.userId == ref.read(supabaseProvider)?.auth.currentUser?.id)),
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
    final maxScore = sortedPlayers.fold<int>(1, (m, p) => p.totalScore > m ? p.totalScore : m);

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
          KinrelIcon(KinrelIconData.trophy, size: 64, color: KinrelColors.orange)
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
          final isWinnerRow = rank == 1;
          final accent = _playerAccent(entry.key);
          return Container(margin: const EdgeInsets.only(bottom: KinrelSpacing.sm), padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.md, vertical: KinrelSpacing.md),
            decoration: BoxDecoration(
              color: isWinnerRow ? Color.lerp(KinrelColors.darkCard, KinrelColors.gold, 0.10) : KinrelColors.darkCard,
              borderRadius: BorderRadius.circular(KinrelRadius.lg),
              border: Border.all(color: isWinnerRow ? KinrelColors.gold.withValues(alpha: 0.8) : (p.userId == myId ? KinrelColors.orange.withValues(alpha: 0.6) : KinrelColors.border), width: isWinnerRow ? 1.5 : 1),
              boxShadow: isWinnerRow ? [BoxShadow(color: KinrelColors.gold.withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 4))] : null,
            ),
            child: Column(children: [
              Row(children: [
                SizedBox(width: 30, child: Text(medal, style: TextStyle(fontSize: 16))),
                DKAvatar(initials: PersonAvatar.initialsFor(p.userName)),
                const SizedBox(width: KinrelSpacing.sm),
                Expanded(child: Text(p.userId == myId ? '${p.userName} (You)' : p.userName, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, fontWeight: FontWeight.w600, color: KinrelColors.textWhite))),
                Text('${p.totalScore} pts', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 16, fontWeight: FontWeight.w800, color: isWinnerRow ? KinrelColors.gold : KinrelColors.orange)),
              ]),
              const SizedBox(height: KinrelSpacing.sm),
              _scoreBar(accent, p.totalScore / maxScore),
            ]),
          );
        }),
        MatchEcosystemSummary(
          gameTable: 'nameplace_games',
          gameId: widget.gameId,
          familyId: widget.familyId,
        ),
        const SizedBox(height: KinrelSpacing.xxl),
        DKButton(label: 'Play Again', variant: DKButtonVariant.gradient, fullWidth: true, icon: Icons.refresh_rounded,
          onPressed: () { ref.read(nameplaceProvider(widget.familyId).notifier).leaveGame(); if (context.mounted) context.pushReplacement('/family/${widget.familyId}/nameplace/lobby'); }),
        const SizedBox(height: KinrelSpacing.sm),
        DKButton(label: 'Back to Hub', variant: DKButtonVariant.secondary, fullWidth: true,
          onPressed: () { ref.read(nameplaceProvider(widget.familyId).notifier).leaveGame(); if (context.mounted) context.go('/games?familyId=${widget.familyId}'); }),
        ]),
        // Winner celebration — fires once on results mount.
        if (isMyWin)
          const Positioned.fill(
            child: IgnorePointer(child: GameConfetti(burstCount: 2, density: 2)),
          ),
      ]),
    );
  }

  /// Per-player accent palette for the score bars.
  Color _playerAccent(int index) {
    const accents = [KinrelColors.orange, KinrelColors.tealAccent, KinrelColors.extendedPurple, KinrelColors.amber, KinrelColors.blue, KinrelColors.coral];
    return accents[index % accents.length];
  }

  /// Player score card — avatar, name, score and an animated bar whose
  /// width tracks the score in the player's accent color.
  Widget _scoreCard(dynamic p, int index, int maxScore, {required bool isMe}) {
    final accent = _playerAccent(index);
    return Container(
      margin: const EdgeInsets.only(bottom: KinrelSpacing.sm),
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.md, vertical: KinrelSpacing.sm),
      decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(10), border: Border.all(color: isMe ? KinrelColors.orange.withValues(alpha: 0.6) : KinrelColors.border)),
      child: Column(children: [
        Row(children: [
          DKAvatar(initials: PersonAvatar.initialsFor(p.userName)),
          const SizedBox(width: KinrelSpacing.sm),
          Expanded(child: Text(isMe ? '${p.userName} (You)' : p.userName,
            style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, color: KinrelColors.textWhite, fontWeight: FontWeight.w600))),
          Text('${p.totalScore}', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 16, fontWeight: FontWeight.w800, color: accent)),
        ]),
        const SizedBox(height: 6),
        _scoreBar(accent, p.totalScore / maxScore),
      ]),
    );
  }

  /// Thin score bar — AnimatedContainer width by score fraction.
  Widget _scoreBar(Color accent, double fraction) {
    final clamped = fraction.clamp(0.0, 1.0);
    return LayoutBuilder(builder: (context, constraints) {
      return ClipRRect(borderRadius: BorderRadius.circular(3), child: SizedBox(height: 5, child: Stack(children: [
        Container(color: KinrelColors.darkElevated),
        Align(alignment: Alignment.centerLeft, child: AnimatedContainer(
          duration: GameMotionTokens.normal,
          curve: GameMotionTokens.smooth,
          width: constraints.maxWidth * clamped,
          height: 5,
          decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(3)),
        )),
      ])));
    });
  }

  /// Per-category accent tint + icon (matches the answer screen chips).
  (Color, IconData) _categoryStyle(String category) {
    switch (category.toLowerCase()) {
      case 'name': return (KinrelColors.info, Icons.person_rounded);
      case 'place': return (KinrelColors.tealAccent, Icons.place_rounded);
      case 'animal': return (KinrelColors.success, Icons.pets_rounded);
      case 'thing': return (KinrelColors.amber, Icons.edit_rounded);
      default: return (KinrelColors.orange, Icons.style_rounded);
    }
  }

  Widget _sectionLabel(String text) => Text(text, style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 13, fontWeight: FontWeight.w600, color: KinrelColors.textDim, letterSpacing: 0.5));
}

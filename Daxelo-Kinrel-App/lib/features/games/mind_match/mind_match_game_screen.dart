// lib/features/games/mind_match/mind_match_game_screen.dart
//
// Mind Match — main match screen.
//
// Layout (round flow):
//   ┌──────────────────────────────────────┐
//   │  Round 3/10  ·  Timer 0:18           │  ← Top HUD
//   ├──────────────────────────────────────┤
//   │  [Category badge]                    │
//   │                                       │
//   │  Name a fruit.                       │  ← Question (large)
//   │                                       │
//   │  ┌──────────────────────────────┐   │  ← Answer input
//   │  │ Type your answer...           │   │
//   │  └──────────────────────────────┘   │
//   │  [Lock in answer]                    │
//   │                                       │
//   │  3/5 answers submitted                │
//   ├──────────────────────────────────────┤
//  OR (revealing phase):
//   │  Round 3 Results                     │
//   │                                       │
//   │  🥭 Mango (3)                        │  ← Answer groups
//   │     Manish, Ravi, Anjali  +15 pts    │
//   │                                       │
//   │  🍎 Apple (1)                        │
//   │     Akash  +2 pts                    │
//   │                                       │
//   │  🍌 Banana (1)                       │
//   │     Priya  +2 pts                    │
//   │                                       │
//   │  [Next Round →]                      │
//   └──────────────────────────────────────┘

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../gaming_ecosystem/presentation/match_ecosystem_summary.dart';
import '../../gaming_ecosystem/presentation/widgets/gaming_kit.dart';
import '../shared/icons/kinrel_icons.dart';
import '../shared/widgets/game_confetti.dart';
import '../shared/widgets/leave_game_dialog.dart';
import '../shared/widgets/reactions_bar.dart';
import 'mind_match_engine.dart';
import 'mind_match_models.dart';
import 'mind_match_provider.dart';

class MindMatchGameScreen extends ConsumerStatefulWidget {
  const MindMatchGameScreen({
    super.key,
    required this.familyId,
    required this.gameId,
  });
  final String familyId;
  final String gameId;

  @override
  ConsumerState<MindMatchGameScreen> createState() =>
      _MindMatchGameScreenState();
}

class _MindMatchGameScreenState
    extends ConsumerState<MindMatchGameScreen> {
  Timer? _clockTimer;
  final _answerController = TextEditingController();
  bool _submitted = false;
  int _lastSeenRound = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(mindMatchProvider(widget.familyId).notifier)
          .loadGame(widget.gameId);
    });
    _clockTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _answerController.dispose();
    super.dispose();
  }

  Future<void> _confirmLeave() async {
    final state = ref.read(mindMatchProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final shouldLeave = await LeaveGameDialog.show(
      context,
      isHost: state.game?.hostUserId == myId &&
          state.game?.isWaiting == true,
      gameName: 'Mind Match',
    );
    if (shouldLeave == true) {
      await ref
          .read(mindMatchProvider(widget.familyId).notifier)
          .leaveGame();
      if (mounted) {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/family/${widget.familyId}');
        }
      }
    }
  }

  void _handleSubmit() {
    final answer = _answerController.text.trim();
    if (answer.isEmpty) return;
    final validation = MindMatchEngine.validateAnswer(answer);
    if (validation != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(validation),
          backgroundColor: KinrelColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    ref
        .read(mindMatchProvider(widget.familyId).notifier)
        .submitAnswer(answer);
    setState(() => _submitted = true);
  }

  void _resetSubmit() {
    setState(() {
      _submitted = false;
      _answerController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(mindMatchProvider(widget.familyId));
    final game = state.game;

    if (state.isLoading && game == null) {
      return DKScaffold(
        backgroundColor: KinrelColors.darkSurface,
        appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back), onPressed: _confirmLeave),
          title: const Text('Mind Match'),
          backgroundColor: KinrelColors.darkCard,
          foregroundColor: KinrelColors.textWhite,
        ),
        body: const Center(
          child: CircularProgressIndicator(color: KinrelColors.orange),
        ),
      );
    }

    if (game == null) {
      return DKScaffold(
        backgroundColor: KinrelColors.darkSurface,
        appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/family/${widget.familyId}')),
          title: const Text('Mind Match'),
          backgroundColor: KinrelColors.darkCard,
          foregroundColor: KinrelColors.textWhite,
        ),
        body: Center(
          child: GamingEmptyCard(
            emoji: '🧠',
            title: 'Game not found',
            message: 'This match may have ended.',
          ),
        ),
      );
    }

    // New round → unlock the answer form for this round.
    final roundNumber = game.boardState?.currentRoundNumber;
    if (roundNumber != null && roundNumber != _lastSeenRound) {
      final isNewRound = _lastSeenRound != 0;
      _lastSeenRound = roundNumber;
      if (isNewRound) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _resetSubmit();
        });
      }
    }

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.arrow_back), onPressed: _confirmLeave),
        title: Text(
          game.roomName?.isNotEmpty == true ? game.roomName! : 'Mind Match',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontWeight: FontWeight.w600,
            color: KinrelColors.textWhite,
          ),
        ),
        backgroundColor: KinrelColors.darkCard,
        foregroundColor: KinrelColors.textWhite,
        elevation: 0,
        actions: [
          if (game.isInProgress)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(child: _RoundInfo(game: game)),
            ),
          if (game.hostUserId ==
                  ref.read(supabaseProvider)?.auth.currentUser?.id &&
              game.isInProgress)
            IconButton(
              tooltip: 'Leave',
              icon: const Icon(Icons.logout, size: 20),
              onPressed: _confirmLeave,
            ),
        ],
      ),
      body: game.isCompleted
          ? _ResultsView(
              game: game,
              familyId: widget.familyId,
              players: state.players,
              onRematch: () => ref
                  .read(mindMatchProvider(widget.familyId).notifier)
                  .rematch(),
              onExit: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/family/${widget.familyId}');
                }
              },
            )
          : _GameView(
              state: state,
              game: game,
              familyId: widget.familyId,
              answerController: _answerController,
              submitted: _submitted,
              onSubmit: _handleSubmit,
              onAdvance: () => ref
                  .read(mindMatchProvider(widget.familyId).notifier)
                  .advancePhase(),
              onResetSubmit: _resetSubmit,
            ),
    );
  }
}

class _RoundInfo extends StatelessWidget {
  const _RoundInfo({required this.game});
  final MindMatchGame game;

  @override
  Widget build(BuildContext context) {
    final board = game.boardState;
    final round = board?.currentRoundNumber ?? 1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF472B6).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'R$round/${game.totalRounds}',
        style: TextStyle(
            fontFamily: KinrelTypography.monoFont,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: const Color(0xFFF472B6)),
      ),
    );
  }
}

class _GameView extends ConsumerWidget {
  const _GameView({
    required this.state,
    required this.game,
    required this.familyId,
    required this.answerController,
    required this.submitted,
    required this.onSubmit,
    required this.onAdvance,
    required this.onResetSubmit,
  });

  final MindMatchState_ state;
  final MindMatchGame game;
  final String familyId;
  final TextEditingController answerController;
  final bool submitted;
  final VoidCallback onSubmit;
  final VoidCallback onAdvance;
  final VoidCallback onResetSubmit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = game.boardState;
    if (board == null) {
      return const Center(
          child: CircularProgressIndicator(color: KinrelColors.orange));
    }
    final round = board.currentRound;
    if (round == null) return const SizedBox.shrink();

    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final hasSubmitted = state.myAnswer != null || submitted;

    return Column(
      children: [
        _TopHud(game: game, board: board),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(KinrelSpacing.md),
            child: Column(
              children: [
                if (round.phase == MindMatchPhase.answering) ...[
                  _QuestionCard(round: round),
                  const SizedBox(height: 14),
                  if (!hasSubmitted)
                    _AnswerInputCard(
                      controller: answerController,
                      lockedCount: round.lockedCount,
                      playerCount: board.playerCount,
                      secondsLeft: game.turnSecondsRemaining ?? 0,
                      isSubmitting: state.isSubmitting,
                      onSubmit: onSubmit,
                    )
                  else
                    _SubmittedCard(
                      lockedCount: round.lockedCount,
                      playerCount: board.playerCount,
                      myAnswer: state.myAnswer?.answer ?? '',
                    ),
                  const SizedBox(height: 14),
                  _Leaderboard(players: board.players, myUserId: myId),
                ] else if (round.phase == MindMatchPhase.revealing) ...[
                  _RevealView(
                    round: round,
                    board: board,
                    players: state.players,
                    onAdvance: onAdvance,
                    isLastRound:
                        board.currentRoundNumber >= board.totalRounds,
                  ),
                  const SizedBox(height: 14),
                  _Leaderboard(players: board.players, myUserId: myId),
                ] else if (round.phase == MindMatchPhase.resolving) ...[
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: CircularProgressIndicator(
                          color: KinrelColors.orange),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (state.amSpectator)
          ReactionsBar(
            gameTable: 'mind_match_games',
            gameId: game.id,
            familyId: familyId,
          ),
      ],
    );
  }
}

class _TopHud extends StatelessWidget {
  const _TopHud({required this.game, required this.board});
  final MindMatchGame game;
  final MindMatchBoardState board;

  @override
  Widget build(BuildContext context) {
    final seconds = game.turnSecondsRemaining ?? 0;
    final timerColor =
        seconds <= 5 ? KinrelColors.error : KinrelColors.textWhite;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        border: Border(bottom: BorderSide(color: KinrelColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Round ${board.currentRoundNumber}/${board.totalRounds}',
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: const Color(0xFFF472B6),
              ),
            ),
          ),
          if (game.isInProgress)
            Row(
              children: [
                Icon(Icons.timer_outlined, size: 14, color: timerColor),
                const SizedBox(width: 4),
                Text('${seconds}s',
                    style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: timerColor)),
              ],
            ),
        ],
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.round});
  final MindMatchRound round;

  @override
  Widget build(BuildContext context) {
    final cat = round.category;
    final accent = Color(cat.accentArgb);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.18),
            const Color(0xFF1A1C2E),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: accent.withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(cat.glyph, style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 6),
                Text(cat.label.toUpperCase(),
                    style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                        color: accent)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            round.questionPrompt,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: KinrelColors.textWhite,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnswerInputCard extends StatelessWidget {
  const _AnswerInputCard({
    required this.controller,
    required this.lockedCount,
    required this.playerCount,
    required this.secondsLeft,
    required this.isSubmitting,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final int lockedCount;
  final int playerCount;
  final int secondsLeft;
  final bool isSubmitting;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: const Color(0xFFF472B6).withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your answer',
              style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite)),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            maxLength: kMindMatchMaxAnswerLength,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 16,
                color: KinrelColors.textWhite),
            decoration: InputDecoration(
              counterText: '',
              hintText: 'Type your answer...',
              hintStyle: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 16,
                  color: KinrelColors.textDim.withValues(alpha: 0.6)),
              filled: true,
              fillColor: KinrelColors.darkElevated,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(KinrelRadius.md),
                borderSide: BorderSide(color: KinrelColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(KinrelRadius.md),
                borderSide: const BorderSide(
                    color: Color(0xFFF472B6), width: 1.4),
              ),
            ),
            onSubmitted: (_) => onSubmit(),
          ),
          const SizedBox(height: 12),
          DKButton(
            label: 'Lock in answer',
            variant: DKButtonVariant.primary,
            fullWidth: true,
            isLoading: isSubmitting,
            onPressed: onSubmit,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.lock_outline,
                  size: 12, color: KinrelColors.textDim),
              const SizedBox(width: 6),
              Text(
                '$lockedCount / $playerCount answers submitted',
                style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 11,
                    color: KinrelColors.textDim),
              ),
              const Spacer(),
              if (secondsLeft <= 10 && secondsLeft > 0)
                Text(
                  '${secondsLeft}s left',
                  style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: secondsLeft <= 5
                          ? KinrelColors.error
                          : KinrelColors.amber),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SubmittedCard extends StatelessWidget {
  const _SubmittedCard({
    required this.lockedCount,
    required this.playerCount,
    required this.myAnswer,
  });
  final int lockedCount;
  final int playerCount;
  final String myAnswer;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: KinrelColors.success.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          const Icon(Icons.lock_outline,
              color: KinrelColors.success, size: 28),
          const SizedBox(height: 8),
          Text('Answer locked in!',
              style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite)),
          const SizedBox(height: 6),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF472B6).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color(0xFFF472B6).withValues(alpha: 0.4)),
            ),
            child: Text(
              myAnswer,
              style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFF472B6)),
            ),
          ),
          const SizedBox(height: 12),
          Text(
              'Waiting for other players... ($lockedCount/$playerCount submitted)',
              style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  color: KinrelColors.textDim)),
        ],
      ),
    );
  }
}

class _Leaderboard extends StatelessWidget {
  const _Leaderboard({required this.players, required this.myUserId});
  final List<MindMatchPlayer> players;
  final String? myUserId;

  @override
  Widget build(BuildContext context) {
    final sorted = List<MindMatchPlayer>.from(players)
      ..sort((a, b) => b.score.compareTo(a.score));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GamingSectionHeader(
            title: 'Standings', icon: Icons.leaderboard_outlined),
        for (final p in sorted)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _PlayerRow(player: p, isMe: p.userId == myUserId),
          ),
      ],
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({required this.player, required this.isMe});
  final MindMatchPlayer player;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: isMe
                ? const Color(0xFFF472B6).withValues(alpha: 0.4)
                : Colors.transparent),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Text(player.name,
                    style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isMe
                            ? const Color(0xFFF472B6)
                            : KinrelColors.textWhite)),
                if (isMe) ...[
                  const SizedBox(width: 6),
                  Text('YOU',
                      style: TextStyle(
                          fontFamily: KinrelTypography.monoFont,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFFF472B6))),
                ],
                if (player.streak >= 2) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: KinrelColors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('🔥${player.streak}',
                        style: TextStyle(
                            fontFamily: KinrelTypography.monoFont,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: KinrelColors.amber)),
                  ),
                ],
              ],
            ),
          ),
          Text('${player.score}',
              style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: KinrelColors.amber)),
        ],
      ),
    );
  }
}

class _RevealView extends StatelessWidget {
  const _RevealView({
    required this.round,
    required this.board,
    required this.players,
    required this.onAdvance,
    required this.isLastRound,
  });
  final MindMatchRound round;
  final MindMatchBoardState board;
  final List<MindMatchPlayerWire> players;
  final VoidCallback onAdvance;
  final bool isLastRound;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: const Color(0xFFF472B6).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology_outlined,
                  size: 22, color: Color(0xFFF472B6)),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Round ${round.roundNumber} Results',
                    style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFFF472B6))),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // The question
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: KinrelColors.darkElevated,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Text(round.category.glyph,
                    style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(round.questionPrompt,
                      style: TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: KinrelColors.textWhite)),
                ),
              ],
            ),
          ),
          // Perfect match banner
          if (round.perfectMatch) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: KinrelColors.brightGold.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: KinrelColors.brightGold
                        .withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.celebration_rounded,
                      size: 18, color: KinrelColors.brightGold),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('PERFECT MATCH! Everyone said the same thing! +20 bonus',
                        style: TextStyle(
                            fontFamily: KinrelTypography.displayFont,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: KinrelColors.brightGold)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          // Answer groups
          Text('Answers',
              style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite)),
          const SizedBox(height: 8),
          for (var i = 0; i < round.answerGroups.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _AnswerGroupRow(
                group: round.answerGroups[i],
                isCrowdFavorite:
                    round.crowdFavorite == round.answerGroups[i].answer,
                isPerfect: round.perfectMatch,
              ),
            ),
          const SizedBox(height: 14),
          DKButton(
            label: isLastRound ? 'See Final Results' : 'Next Round →',
            variant: DKButtonVariant.primary,
            fullWidth: true,
            onPressed: onAdvance,
          ),
        ],
      ),
    );
  }
}

class _AnswerGroupRow extends StatelessWidget {
  const _AnswerGroupRow({
    required this.group,
    required this.isCrowdFavorite,
    required this.isPerfect,
  });
  final MindMatchAnswerGroup group;
  final bool isCrowdFavorite;
  final bool isPerfect;

  @override
  Widget build(BuildContext context) {
    final isMatched = group.isMatched;
    final accent = isMatched
        ? (isCrowdFavorite
            ? KinrelColors.brightGold
            : const Color(0xFFF472B6))
        : KinrelColors.textDim;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isMatched ? 0.12 : 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: accent.withValues(alpha: isMatched ? 0.4 : 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  group.answer,
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: isMatched
                        ? accent
                        : KinrelColors.textSilver,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${group.size}',
                  style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: accent),
                ),
              ),
              if (isCrowdFavorite) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: KinrelColors.brightGold
                        .withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('CROWD FAV',
                      style: TextStyle(
                          fontFamily: KinrelTypography.monoFont,
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          color: KinrelColors.brightGold)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final name in group.userNames)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: KinrelColors.darkElevated,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(name,
                      style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: KinrelColors.textSilver)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            isPerfect
                ? '+${group.basePoints + 20} pts each (perfect match bonus)'
                : isCrowdFavorite
                    ? '+${group.basePoints + 5} pts each (crowd favorite bonus)'
                    : '+${group.basePoints} pts each',
            style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: accent),
          ),
        ],
      ),
    );
  }
}

class _ResultsView extends StatelessWidget {
  const _ResultsView({
    required this.game,
    required this.familyId,
    required this.players,
    required this.onRematch,
    required this.onExit,
  });
  final MindMatchGame game;
  final String familyId;
  final List<MindMatchPlayerWire> players;
  final Future<String?> Function() onRematch;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final board = game.boardState;
    final winnerIds = game.winnerUserIds;
    final winnerName = winnerIds.isNotEmpty
        ? players
            .where((p) => winnerIds.contains(p.userId))
            .map((p) => p.userName)
            .join(', ')
        : '';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(KinrelSpacing.lg),
      child: Column(
        children: [
          if (winnerIds.isNotEmpty) const GameConfetti(),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFF472B6).withValues(alpha: 0.18),
                  const Color(0xFF1C1410),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: const Color(0xFFF472B6).withValues(alpha: 0.45)),
            ),
            child: Column(
              children: [
                const KinrelIcon(KinrelIconData.trophy,
                    size: 40, color: KinrelColors.brightGold),
                const SizedBox(height: 8),
                Text(
                  winnerName.isNotEmpty
                      ? '$winnerName wins!'
                      : 'Match Complete',
                  style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: KinrelColors.brightGold),
                ),
                const SizedBox(height: 4),
                Text('Thinker-who-matched-most wins!',
                    style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        color: KinrelColors.textSilver)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (board != null) ...[
            GamingSectionHeader(
                title: 'Final Standings', icon: Icons.leaderboard_outlined),
            for (final p in board.players
                .toList()
              ..sort((a, b) => b.score.compareTo(a.score)))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: KinrelColors.darkCard,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Text(
                        winnerIds.contains(p.userId) ? '🏆' : '🏅',
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.name,
                                style: TextStyle(
                                    fontFamily: KinrelTypography.bodyFont,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: KinrelColors.textWhite)),
                            Text(
                                '${p.perfectMatches} perfect · best streak ${p.streak}',
                                style: TextStyle(
                                    fontFamily: KinrelTypography.bodyFont,
                                    fontSize: 10,
                                    color: KinrelColors.textDim)),
                          ],
                        ),
                      ),
                      Text('${p.score} pts',
                          style: TextStyle(
                              fontFamily: KinrelTypography.monoFont,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFFF472B6))),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 18),
            // Match stats
            GamingSectionHeader(
                title: 'Match Stats', icon: Icons.insights_outlined),
            _StatRow(
                label: 'Total rounds',
                value: '${board.rounds.length}'),
            _StatRow(
                label: 'Perfect matches',
                value: '${board.totalPerfectMatches}'),
            _StatRow(
                label: 'Longest streak',
                value: '${board.longestStreak} rounds'),
            _StatRow(
                label: 'Best group size',
                value:
                    '${MindMatchEngine.bestMatchSize(board.rounds)} players'),
            const SizedBox(height: 18),
          ],
          MatchEcosystemSummary(
            gameTable: 'mind_match_games',
            gameId: game.id,
            familyId: familyId,
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: DKButton(
                  label: 'Exit',
                  variant: DKButtonVariant.secondary,
                  fullWidth: true,
                  onPressed: onExit,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DKButton(
                  label: 'Rematch',
                  variant: DKButtonVariant.primary,
                  fullWidth: true,
                  onPressed: () async {
                    final newId = await onRematch();
                    if (newId != null && context.mounted) {
                      context.pushReplacement(
                        '/family/$familyId/mind-match/game/$newId',
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      color: KinrelColors.textDim)),
            ),
            Text(value,
                style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite)),
          ],
        ),
      ),
    );
  }
}

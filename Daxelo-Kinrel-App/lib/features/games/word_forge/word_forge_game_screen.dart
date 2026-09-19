// lib/features/games/word_forge/word_forge_game_screen.dart
//
// Word Forge — main match screen.
//
// Layout (round flow):
//   ┌──────────────────────────────────────┐
//   │  Round 3/10  ·  Timer 1:18           │  ← Top HUD
//   ├──────────────────────────────────────┤
//   │  [📖 OBSCURE WORD]                   │
//   │                                       │
//   │  floccinaucinihilipilification       │  ← The obscure word (large)
//   │                                       │
//   │  ┌──────────────────────────────┐   │  ← Definition input
//   │  │ Write a fake definition...    │   │
//   │  └──────────────────────────────┘   │
//   │  [Lock in definition]                │
//   │                                       │
//   │  3/5 definitions submitted            │
//   ├──────────────────────────────────────┤
//  OR (revealing/voting phase):
//   │  Round 3 · Vote                      │
//   │                                       │
//   │  Which is the REAL definition?       │
//   │                                       │
//   │  ① A rare coin from ancient Rome     │  ← Shuffled definitions
//   │  ② The act of estimating something   │
//   │     as worthless                     │
//   │  ③ ...                               │
//   │                                       │
//   │  [Vote for #2]                       │
//   ├──────────────────────────────────────┤
//  OR (results phase):
//   │  Round 3 Results                     │
//   │                                       │
//   │  ✅ The act of estimating something  │  ← Real definition highlighted
//   │     as worthless                      │
//   │     Manish guessed right!  +10        │
//   │                                       │
//   │  ❌ A rare coin from ancient Rome    │  ← Fake definitions
//   │     by Priya — fooled 2 people  +10   │
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
import 'word_forge_engine.dart';
import 'word_forge_models.dart';
import 'word_forge_provider.dart';

/// Premium purple accent — used throughout the Word Forge UI.
const Color _kWordForgeAccent = Color(0xFF8B5CF6);

class WordForgeGameScreen extends ConsumerStatefulWidget {
  const WordForgeGameScreen({
    super.key,
    required this.familyId,
    required this.gameId,
  });
  final String familyId;
  final String gameId;

  @override
  ConsumerState<WordForgeGameScreen> createState() =>
      _WordForgeGameScreenState();
}

class _WordForgeGameScreenState
    extends ConsumerState<WordForgeGameScreen> {
  Timer? _clockTimer;
  final _definitionController = TextEditingController();
  bool _submitted = false;
  bool _voted = false;
  int _lastSeenRound = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(wordForgeProvider(widget.familyId).notifier)
          .loadGame(widget.gameId);
    });
    _clockTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _definitionController.dispose();
    super.dispose();
  }

  Future<void> _confirmLeave() async {
    final state = ref.read(wordForgeProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final shouldLeave = await LeaveGameDialog.show(
      context,
      isHost: state.game?.hostUserId == myId &&
          state.game?.isWaiting == true,
      gameName: 'Word Forge',
    );
    if (shouldLeave == true) {
      await ref
          .read(wordForgeProvider(widget.familyId).notifier)
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
    final definition = _definitionController.text.trim();
    if (definition.isEmpty) return;
    final validation = WordForgeEngine.validateDefinition(definition);
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
        .read(wordForgeProvider(widget.familyId).notifier)
        .submitDefinition(definition);
    setState(() => _submitted = true);
  }

  void _handleVote(String targetUserId) {
    ref
        .read(wordForgeProvider(widget.familyId).notifier)
        .vote(targetUserId);
    setState(() => _voted = true);
  }

  void _resetSubmit() {
    setState(() {
      _submitted = false;
      _definitionController.clear();
    });
  }

  void _resetVote() {
    setState(() => _voted = false);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(wordForgeProvider(widget.familyId));
    final game = state.game;

    if (state.isLoading && game == null) {
      return DKScaffold(
        backgroundColor: KinrelColors.darkSurface,
        appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back), onPressed: _confirmLeave),
          title: const Text('Word Forge'),
          backgroundColor: KinrelColors.darkCard,
          foregroundColor: KinrelColors.textWhite,
        ),
        body: const Center(
          child: CircularProgressIndicator(color: _kWordForgeAccent),
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
          title: const Text('Word Forge'),
          backgroundColor: KinrelColors.darkCard,
          foregroundColor: KinrelColors.textWhite,
        ),
        body: Center(
          child: GamingEmptyCard(
            emoji: '📖',
            title: 'Game not found',
            message: 'This match may have ended.',
          ),
        ),
      );
    }

    // New round → unlock the writing + voting forms for this round.
    final roundNumber = game.boardState?.currentRoundNumber;
    if (roundNumber != null && roundNumber != _lastSeenRound) {
      final isNewRound = _lastSeenRound != 0;
      _lastSeenRound = roundNumber;
      if (isNewRound) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _resetSubmit();
            _resetVote();
          }
        });
      }
    }

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.arrow_back), onPressed: _confirmLeave),
        title: Text(
          game.roomName?.isNotEmpty == true ? game.roomName! : 'Word Forge',
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
          ? _FinalResultsView(
              game: game,
              familyId: widget.familyId,
              players: state.players,
              onRematch: () => ref
                  .read(wordForgeProvider(widget.familyId).notifier)
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
              definitionController: _definitionController,
              submitted: _submitted,
              voted: _voted,
              onSubmit: _handleSubmit,
              onVote: _handleVote,
              onAdvance: () => ref
                  .read(wordForgeProvider(widget.familyId).notifier)
                  .advancePhase(),
              onResetSubmit: _resetSubmit,
              onResetVote: _resetVote,
            ),
    );
  }
}

class _RoundInfo extends StatelessWidget {
  const _RoundInfo({required this.game});
  final WordForgeGame game;

  @override
  Widget build(BuildContext context) {
    final board = game.boardState;
    final round = board?.currentRoundNumber ?? 1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _kWordForgeAccent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'R$round/${game.totalRounds}',
        style: const TextStyle(
            fontFamily: KinrelTypography.monoFont,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: _kWordForgeAccent),
      ),
    );
  }
}

class _GameView extends ConsumerWidget {
  const _GameView({
    required this.state,
    required this.game,
    required this.familyId,
    required this.definitionController,
    required this.submitted,
    required this.voted,
    required this.onSubmit,
    required this.onVote,
    required this.onAdvance,
    required this.onResetSubmit,
    required this.onResetVote,
  });

  final WordForgeState_ state;
  final WordForgeGame game;
  final String familyId;
  final TextEditingController definitionController;
  final bool submitted;
  final bool voted;
  final VoidCallback onSubmit;
  final void Function(String) onVote;
  final VoidCallback onAdvance;
  final VoidCallback onResetSubmit;
  final VoidCallback onResetVote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = game.boardState;
    if (board == null) {
      return const Center(
          child: CircularProgressIndicator(color: _kWordForgeAccent));
    }
    final round = board.currentRound;
    if (round == null) return const SizedBox.shrink();

    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final hasSubmitted = state.myDefinition != null || submitted;
    final hasVoted = state.myVote != null || voted;

    return Column(
      children: [
        _TopHud(game: game, board: board),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(KinrelSpacing.md),
            child: Column(
              children: [
                if (round.phase == WordForgePhase.writing) ...[
                  _WordCard(round: round),
                  const SizedBox(height: 14),
                  if (!hasSubmitted)
                    _DefinitionInputCard(
                      controller: definitionController,
                      lockedCount: round.submittedCount,
                      playerCount: board.playerCount,
                      secondsLeft: game.turnSecondsRemaining ?? 0,
                      isSubmitting: state.isSubmitting,
                      onSubmit: onSubmit,
                    )
                  else
                    _SubmittedCard(
                      lockedCount: round.submittedCount,
                      playerCount: board.playerCount,
                      myDefinition: state.myDefinition?.definition ??
                          definitionController.text,
                    ),
                  const SizedBox(height: 14),
                  _Leaderboard(players: board.players, myUserId: myId),
                ] else if (round.phase ==
                    WordForgePhase.revealing) ...[
                  _RevealCard(round: round),
                  const SizedBox(height: 14),
                  if (game.hostUserId == myId)
                    DKButton(
                      label: 'Start Voting',
                      variant: DKButtonVariant.primary,
                      fullWidth: true,
                      icon: Icons.how_to_vote_outlined,
                      onPressed: onAdvance,
                    ),
                ] else if (round.phase == WordForgePhase.voting) ...[
                  _VotingView(
                    round: round,
                    board: board,
                    myUserId: myId,
                    hasVoted: hasVoted,
                    myVoteUserId: state.myVote?.votedForUserId ?? '',
                    isSubmitting: state.isSubmitting,
                    onVote: onVote,
                    onAdvance: onAdvance,
                    isHost: game.hostUserId == myId,
                  ),
                  const SizedBox(height: 14),
                  _Leaderboard(players: board.players, myUserId: myId),
                ] else if (round.phase == WordForgePhase.results) ...[
                  _RoundResultsView(
                    round: round,
                    board: board,
                    players: state.players,
                    myUserId: myId,
                    onAdvance: onAdvance,
                    isLastRound:
                        board.currentRoundNumber >= board.totalRounds,
                    isHost: game.hostUserId == myId,
                  ),
                  const SizedBox(height: 14),
                  _Leaderboard(players: board.players, myUserId: myId),
                ],
              ],
            ),
          ),
        ),
        if (state.amSpectator)
          ReactionsBar(
            gameTable: 'word_forge_games',
            gameId: game.id,
            familyId: familyId,
          ),
      ],
    );
  }
}

class _TopHud extends StatelessWidget {
  const _TopHud({required this.game, required this.board});
  final WordForgeGame game;
  final WordForgeBoardState board;

  @override
  Widget build(BuildContext context) {
    final seconds = game.turnSecondsRemaining ?? 0;
    final timerColor =
        seconds <= 5 ? KinrelColors.error : KinrelColors.textWhite;
    final round = board.currentRound;
    final phaseLabel = round?.phase.label ?? 'Writing';
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
              'Round ${board.currentRoundNumber}/${board.totalRounds} · $phaseLabel',
              style: const TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: _kWordForgeAccent,
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

class _WordCard extends StatelessWidget {
  const _WordCard({required this.round});
  final WordForgeRound round;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _kWordForgeAccent.withValues(alpha: 0.18),
            const Color(0xFF1A1C2E),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kWordForgeAccent.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _kWordForgeAccent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: _kWordForgeAccent.withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('📖', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 6),
                Text('OBSCURE WORD',
                    style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                        color: _kWordForgeAccent)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            round.word,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: _wordFontSize(round.word),
              fontWeight: FontWeight.w800,
              color: KinrelColors.textWhite,
              height: 1.25,
              letterSpacing: -0.5,
            ),
          ),
          if (round.category.isNotEmpty &&
              round.category != 'obscure') ...[
            const SizedBox(height: 8),
            Text(
              round.category.toUpperCase(),
              style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textDim,
                  letterSpacing: 1),
            ),
          ],
        ],
      ),
    );
  }

  double _wordFontSize(String word) {
    if (word.length > 24) return 18;
    if (word.length > 18) return 22;
    if (word.length > 12) return 26;
    return 30;
  }
}

class _DefinitionInputCard extends StatelessWidget {
  const _DefinitionInputCard({
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
            color: _kWordForgeAccent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.edit_note, size: 18, color: _kWordForgeAccent),
              const SizedBox(width: 6),
              Text('Your fake definition',
                  style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: KinrelColors.textWhite)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Write a convincing definition for this word. Make it sound real!',
            style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 11,
                color: KinrelColors.textDim),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            maxLength: kWordForgeMaxDefinitionLength,
            maxLines: 3,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 15,
                color: KinrelColors.textWhite),
            decoration: InputDecoration(
              counterText: '',
              hintText: 'e.g. A rare coin from ancient Rome used in trade...',
              hintStyle: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
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
                    color: _kWordForgeAccent, width: 1.4),
              ),
            ),
            onSubmitted: (_) => onSubmit(),
          ),
          const SizedBox(height: 12),
          DKButton(
            label: 'Lock in definition',
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
                '$lockedCount / $playerCount definitions submitted',
                style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 11,
                    color: KinrelColors.textDim),
              ),
              const Spacer(),
              if (secondsLeft <= 15 && secondsLeft > 0)
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
    required this.myDefinition,
  });
  final int lockedCount;
  final int playerCount;
  final String myDefinition;

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
          Text('Definition locked in!',
              style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite)),
          const SizedBox(height: 6),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _kWordForgeAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: _kWordForgeAccent.withValues(alpha: 0.4)),
            ),
            child: Text(
              '"$myDefinition"',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  color: _kWordForgeAccent),
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
  final List<WordForgePlayer> players;
  final String? myUserId;

  @override
  Widget build(BuildContext context) {
    final sorted = List<WordForgePlayer>.from(players)
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
  final WordForgePlayer player;
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
                ? _kWordForgeAccent.withValues(alpha: 0.4)
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
                            ? _kWordForgeAccent
                            : KinrelColors.textWhite)),
                if (isMe) ...[
                  const SizedBox(width: 6),
                  Text('YOU',
                      style: TextStyle(
                          fontFamily: KinrelTypography.monoFont,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: _kWordForgeAccent)),
                ],
                if (player.foolCount > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: KinrelColors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('🎭${player.foolCount}',
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

class _RevealCard extends StatelessWidget {
  const _RevealCard({required this.round});
  final WordForgeRound round;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: _kWordForgeAccent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_stories,
                  size: 22, color: _kWordForgeAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Definitions Revealed',
                    style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _kWordForgeAccent)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: KinrelColors.darkElevated,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Text('📖', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(round.word,
                      style: TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: KinrelColors.textWhite)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'All definitions are shuffled and ready. Get ready to vote!',
            style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: KinrelColors.textDim),
          ),
        ],
      ),
    );
  }
}

class _VotingView extends StatelessWidget {
  const _VotingView({
    required this.round,
    required this.board,
    required this.myUserId,
    required this.hasVoted,
    required this.myVoteUserId,
    required this.isSubmitting,
    required this.onVote,
    required this.onAdvance,
    required this.isHost,
  });

  final WordForgeRound round;
  final WordForgeBoardState board;
  final String? myUserId;
  final bool hasVoted;
  final String myVoteUserId;
  final bool isSubmitting;
  final void Function(String) onVote;
  final VoidCallback onAdvance;
  final bool isHost;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: _kWordForgeAccent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.how_to_vote_outlined,
                  size: 22, color: _kWordForgeAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Vote for the Real Definition',
                    style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _kWordForgeAccent)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Which definition do you think is the real one? You can\'t vote for your own.',
            style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: KinrelColors.textDim),
          ),
          const SizedBox(height: 14),
          // Word reminder
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: KinrelColors.darkElevated,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Text('📖', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                Text(round.word,
                    style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: KinrelColors.textWhite)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          for (final def in round.definitions)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _VotingDefinitionRow(
                definition: def,
                isMine: def.userId == myUserId && !def.isReal,
                hasVoted: hasVoted,
                isSelected: hasVoted &&
                    ((def.isReal && myVoteUserId.isEmpty) ||
                        def.userId == myVoteUserId),
                isSubmitting: isSubmitting,
                onVote: () => onVote(def.isReal ? '' : def.userId),
              ),
            ),
          const SizedBox(height: 8),
          if (hasVoted)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: KinrelColors.success.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: KinrelColors.success.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle,
                      size: 18, color: KinrelColors.success),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        'Vote locked in! Waiting for others (${round.voteCount}/${board.playerCount} voted).',
                        style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: KinrelColors.success)),
                  ),
                ],
              ),
            ),
          if (isHost && hasVoted)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: DKButton(
                label: 'Reveal Results',
                variant: DKButtonVariant.primary,
                fullWidth: true,
                onPressed: onAdvance,
              ),
            ),
        ],
      ),
    );
  }
}

class _VotingDefinitionRow extends StatelessWidget {
  const _VotingDefinitionRow({
    required this.definition,
    required this.isMine,
    required this.hasVoted,
    required this.isSelected,
    required this.isSubmitting,
    required this.onVote,
  });

  final WordForgeDefinition definition;
  final bool isMine;
  final bool hasVoted;
  final bool isSelected;
  final bool isSubmitting;
  final VoidCallback onVote;

  @override
  Widget build(BuildContext context) {
    final accent = isSelected
        ? _kWordForgeAccent
        : (isMine ? KinrelColors.amber : KinrelColors.textDim);
    return Opacity(
      opacity: isMine && !hasVoted ? 0.5 : 1.0,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? accent.withValues(alpha: 0.15)
              : KinrelColors.darkElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isSelected
                  ? accent.withValues(alpha: 0.6)
                  : KinrelColors.border,
              width: isSelected ? 1.6 : 1.0),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: (isMine || hasVoted || isSubmitting) ? null : onVote,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: accent.withValues(alpha: 0.6)),
                  ),
                  child: Center(
                    child: Text(
                      '${definition.displayIndex}',
                      style: TextStyle(
                          fontFamily: KinrelTypography.monoFont,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: accent),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        definition.definition,
                        style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 14,
                            color: KinrelColors.textWhite,
                            height: 1.35),
                      ),
                      if (isMine) ...[
                        const SizedBox(height: 4),
                        Text('YOUR DEFINITION (can\'t vote for your own)',
                            style: TextStyle(
                                fontFamily: KinrelTypography.monoFont,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: KinrelColors.amber)),
                      ],
                    ],
                  ),
                ),
                if (hasVoted && isSelected)
                  const Padding(
                    padding: EdgeInsets.only(left: 8, top: 2),
                    child: Icon(Icons.check_circle,
                        size: 18, color: _kWordForgeAccent),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundResultsView extends StatelessWidget {
  const _RoundResultsView({
    required this.round,
    required this.board,
    required this.players,
    required this.myUserId,
    required this.onAdvance,
    required this.isLastRound,
    required this.isHost,
  });

  final WordForgeRound round;
  final WordForgeBoardState board;
  final List<WordForgePlayerWire> players;
  final String? myUserId;
  final VoidCallback onAdvance;
  final bool isLastRound;
  final bool isHost;

  @override
  Widget build(BuildContext context) {
    // Sort definitions: real one first, then by vote count desc, then by index
    final sortedDefs = List<WordForgeDefinition>.from(round.definitions)
      ..sort((a, b) {
        if (a.isReal && !b.isReal) return -1;
        if (!a.isReal && b.isReal) return 1;
        final c = b.voteCount.compareTo(a.voteCount);
        if (c != 0) return c;
        return a.displayIndex.compareTo(b.displayIndex);
      });

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: _kWordForgeAccent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_events_outlined,
                  size: 22, color: _kWordForgeAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Round ${round.roundNumber} Results',
                    style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _kWordForgeAccent)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Word reminder
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: KinrelColors.darkElevated,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Text('📖', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(round.word,
                          style: TextStyle(
                              fontFamily: KinrelTypography.displayFont,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: KinrelColors.textWhite)),
                      const SizedBox(height: 2),
                      Text(
                        round.realDefinition,
                        style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: KinrelColors.textSilver),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text('Definitions & Votes',
              style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite)),
          const SizedBox(height: 8),
          for (final def in sortedDefs)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ResultDefinitionRow(
                definition: def,
                isMine: def.userId == myUserId && !def.isReal,
              ),
            ),
          const SizedBox(height: 10),
          // Per-player points breakdown
          if (round.pointsAwarded.isNotEmpty) ...[
            Text('Points This Round',
                style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite)),
            const SizedBox(height: 8),
            for (final pa in round.pointsAwarded)
              if (pa.playerIndex >= 0 &&
                  pa.playerIndex < board.players.length)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _PointsRow(
                    player: board.players[pa.playerIndex],
                    points: pa,
                    isMe: board.players[pa.playerIndex].userId == myUserId,
                  ),
                ),
          ],
          const SizedBox(height: 14),
          if (isHost)
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

class _ResultDefinitionRow extends StatelessWidget {
  const _ResultDefinitionRow({
    required this.definition,
    required this.isMine,
  });
  final WordForgeDefinition definition;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final accent = definition.isReal
        ? KinrelColors.success
        : (isMine ? KinrelColors.amber : KinrelColors.textDim);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: definition.isReal ? 0.12 : 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: accent.withValues(alpha: definition.isReal ? 0.5 : 0.2),
            width: definition.isReal ? 1.6 : 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (definition.isReal)
                const Icon(Icons.check_circle,
                    size: 18, color: KinrelColors.success)
              else
                Icon(Icons.cancel_outlined,
                    size: 18, color: isMine ? KinrelColors.amber : KinrelColors.textDim),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  definition.isReal
                      ? 'REAL DEFINITION'
                      : (isMine ? 'YOUR FAKE DEF' : 'BY ${definition.userName}'),
                  style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: accent),
                ),
              ),
              if (definition.voteCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${definition.voteCount} vote${definition.voteCount == 1 ? '' : 's'}',
                    style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: accent),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            definition.definition,
            style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: KinrelColors.textWhite,
                height: 1.35),
          ),
          if (!definition.isReal && definition.voteCount > 0) ...[
            const SizedBox(height: 4),
            Text(
              '+${definition.authorPoints} pts to ${definition.userName}',
              style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: accent),
            ),
          ],
        ],
      ),
    );
  }
}

class _PointsRow extends StatelessWidget {
  const _PointsRow({
    required this.player,
    required this.points,
    required this.isMe,
  });
  final WordForgePlayer player;
  final WordForgePointsAwarded points;
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
                ? _kWordForgeAccent.withValues(alpha: 0.4)
                : Colors.transparent),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(player.name,
                        style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isMe
                                ? _kWordForgeAccent
                                : KinrelColors.textWhite)),
                    if (isMe) ...[
                      const SizedBox(width: 6),
                      Text('YOU',
                          style: TextStyle(
                              fontFamily: KinrelTypography.monoFont,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: _kWordForgeAccent)),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  children: [
                    if (points.guessedReal)
                      _PointsChip(
                          '✓ Real guess +10', KinrelColors.success),
                    if (points.foolCount > 0)
                      _PointsChip(
                          '🎭 Fooled ${points.foolCount} +${points.foolCount * 5}',
                          KinrelColors.amber),
                    if (points.closeBonus)
                      _PointsChip(
                          '✨ Close match +15',
                          _kWordForgeAccent),
                    if (!points.guessedReal &&
                        points.foolCount == 0 &&
                        !points.closeBonus)
                      _PointsChip(
                          'No points this round', KinrelColors.textDim),
                  ],
                ),
              ],
            ),
          ),
          Text(
            '+${points.points}',
            style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: points.points > 0
                    ? KinrelColors.amber
                    : KinrelColors.textDim),
          ),
        ],
      ),
    );
  }
}

class _PointsChip extends StatelessWidget {
  const _PointsChip(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color)),
    );
  }
}

class _FinalResultsView extends StatelessWidget {
  const _FinalResultsView({
    required this.game,
    required this.familyId,
    required this.players,
    required this.onRematch,
    required this.onExit,
  });
  final WordForgeGame game;
  final String familyId;
  final List<WordForgePlayerWire> players;
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
                  _kWordForgeAccent.withValues(alpha: 0.18),
                  const Color(0xFF1C1428),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: _kWordForgeAccent.withValues(alpha: 0.45)),
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
                Text('Wordsmith-who-fuled-the-most wins!',
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
                                '${p.correctGuesses} correct · ${p.foolCount} fooled',
                                style: TextStyle(
                                    fontFamily: KinrelTypography.bodyFont,
                                    fontSize: 10,
                                    color: KinrelColors.textDim)),
                          ],
                        ),
                      ),
                      Text('${p.score} pts',
                          style: const TextStyle(
                              fontFamily: KinrelTypography.monoFont,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: _kWordForgeAccent)),
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
                label: 'Total fooled votes',
                value: '${board.totalFoolCount}'),
            _StatRow(
                label: 'Total correct guesses',
                value: '${board.totalCorrectGuesses}'),
            _StatRow(
                label: 'Best fool count (one round)',
                value:
                    '${WordForgeEngine.bestFoolCount(board.rounds)} votes'),
            const SizedBox(height: 18),
          ],
          MatchEcosystemSummary(
            gameTable: 'word_forge_games',
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
                        '/family/$familyId/word-forge/game/$newId',
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

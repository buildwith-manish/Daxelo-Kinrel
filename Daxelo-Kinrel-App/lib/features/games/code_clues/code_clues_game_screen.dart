// lib/features/games/code_clues/code_clues_game_screen.dart
//
// Code Clues — main match screen.
//
// Layout (turn flow):
//   ┌──────────────────────────────────────┐
//   │  [Team Red's turn] · Timer 0:45      │  ← Top HUD
//   ├──────────────────────────────────────┤
//   │  Clue: OCEAN · 2   guesses left: 2   │  ← Clue banner
//   ├──────────────────────────────────────┤
//   │   ┌─────┐┌─────┐┌─────┐┌─────┐┌─────┐│
//   │   │APPLE││BREAD││CLOCK││DANCE││EAGLE││  ← 5×5 word grid
//   │   └─────┘└─────┘└─────┘└─────┘└─────┘│     (spymaster sees colors,
//   │   … (4 more rows)                    │      field agents see only
//   │                                       │      revealed cells)
//   ├──────────────────────────────────────┤
//   │  [Spymaster: enter clue + number]    │  ← Action panel
//   │  OR [Pass turn]                       │
//   ├──────────────────────────────────────┤
//   │  📜 Log: Manish gave OCEAN 2          │  ← Game log
//   │        Ravi guessed APPLE (Team 1)    │
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
import '../shared/widgets/game_confetti.dart';
import '../shared/widgets/leave_game_dialog.dart';
import '../shared/widgets/reactions_bar.dart';
import 'code_clues_models.dart';
import 'code_clues_provider.dart';

/// Team color tokens (re-exported from lobby screen for use here).
Color _teamColor(int team) =>
    team == 2 ? const Color(0xFF3B82F6) : KinrelColors.orange;

class CodeCluesGameScreen extends ConsumerStatefulWidget {
  const CodeCluesGameScreen({
    super.key,
    required this.familyId,
    required this.gameId,
  });
  final String familyId;
  final String gameId;

  @override
  ConsumerState<CodeCluesGameScreen> createState() =>
      _CodeCluesGameScreenState();
}

class _CodeCluesGameScreenState extends ConsumerState<CodeCluesGameScreen> {
  Timer? _clockTimer;
  final _clueController = TextEditingController();
  int _clueNumber = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(codeCluesProvider(widget.familyId).notifier)
          .loadGame(widget.gameId);
    });
    _clockTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _clueController.dispose();
    super.dispose();
  }

  Future<void> _confirmLeave() async {
    final state = ref.read(codeCluesProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final shouldLeave = await LeaveGameDialog.show(
      context,
      isHost: state.game?.hostUserId == myId &&
          state.game?.isWaiting == true,
      gameName: 'Code Clues',
    );
    if (shouldLeave == true) {
      await ref
          .read(codeCluesProvider(widget.familyId).notifier)
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

  void _handleGiveClue() {
    final clue = _clueController.text.trim();
    if (clue.isEmpty) return;
    final error = CodeCluesEngine.validateClue(clue);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: KinrelColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    ref
        .read(codeCluesProvider(widget.familyId).notifier)
        .giveClue(clue, _clueNumber);
    _clueController.clear();
    setState(() => _clueNumber = 1);
  }

  void _handleGuess(int wordIndex) {
    ref
        .read(codeCluesProvider(widget.familyId).notifier)
        .guess(wordIndex);
  }

  void _handlePass() {
    ref
        .read(codeCluesProvider(widget.familyId).notifier)
        .passTurn();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(codeCluesProvider(widget.familyId));
    final game = state.game;

    if (state.isLoading && game == null) {
      return DKScaffold(
        backgroundColor: KinrelColors.darkSurface,
        appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back), onPressed: _confirmLeave),
          title: const Text('Code Clues'),
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
          title: const Text('Code Clues'),
          backgroundColor: KinrelColors.darkCard,
          foregroundColor: KinrelColors.textWhite,
        ),
        body: Center(
          child: GamingEmptyCard(
            emoji: '🔐',
            title: 'Game not found',
            message: 'This match may have ended.',
          ),
        ),
      );
    }

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.arrow_back), onPressed: _confirmLeave),
        title: Text(
          game.roomName?.isNotEmpty == true ? game.roomName! : 'Code Clues',
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
              child: Center(child: _TurnInfo(game: game)),
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
                  .read(codeCluesProvider(widget.familyId).notifier)
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
              clueController: _clueController,
              clueNumber: _clueNumber,
              onClueNumberChanged: (v) =>
                  setState(() => _clueNumber = v),
              onGiveClue: _handleGiveClue,
              onGuess: _handleGuess,
              onPass: _handlePass,
            ),
    );
  }
}

class _TurnInfo extends StatelessWidget {
  const _TurnInfo({required this.game});
  final CodeCluesGame game;

  @override
  Widget build(BuildContext context) {
    final board = game.boardState;
    final team = board?.currentTurnTeam ?? game.currentTurnTeam;
    final color = _teamColor(team);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        team == 1 ? 'RED' : 'BLUE',
        style: TextStyle(
            fontFamily: KinrelTypography.monoFont,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color),
      ),
    );
  }
}

class _GameView extends ConsumerWidget {
  const _GameView({
    required this.state,
    required this.game,
    required this.familyId,
    required this.clueController,
    required this.clueNumber,
    required this.onClueNumberChanged,
    required this.onGiveClue,
    required this.onGuess,
    required this.onPass,
  });

  final CodeCluesState_ state;
  final CodeCluesGame game;
  final String familyId;
  final TextEditingController clueController;
  final int clueNumber;
  final void Function(int) onClueNumberChanged;
  final VoidCallback onGiveClue;
  final void Function(int) onGuess;
  final VoidCallback onPass;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = game.boardState;
    if (board == null) {
      return const Center(
          child: CircularProgressIndicator(color: KinrelColors.orange));
    }
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final myPlayer = state.playerFor(myId);
    final isSpymaster = myPlayer?.isSpymaster ?? false;
    final myTeam = myPlayer?.team ?? 0;
    final amSpectator = state.amSpectator || myPlayer == null;
    // Spymaster of either team always sees assignments; field agents see
    // only their own team's revealed cells (and all revealed cells).
    final canSeeAssignments = isSpymaster || amSpectator;

    return Column(
      children: [
        _TopHud(game: game, board: board),
        if (board.phase == CodeCluesPhase.guessing &&
            board.clue != null)
          _ClueBanner(board: board),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(KinrelSpacing.md),
            child: Column(
              children: [
                _WordGrid(
                  board: board,
                  canSeeAssignments: canSeeAssignments,
                  myTeam: myTeam,
                  canGuess: !amSpectator &&
                      myTeam == board.currentTurnTeam &&
                      !isSpymaster &&
                      board.phase == CodeCluesPhase.guessing &&
                      !state.isSubmitting,
                  onGuess: onGuess,
                ),
                const SizedBox(height: 14),
                _ActionPanel(
                  board: board,
                  state: state,
                  isSpymaster: isSpymaster,
                  myTeam: myTeam,
                  amSpectator: amSpectator,
                  clueController: clueController,
                  clueNumber: clueNumber,
                  onClueNumberChanged: onClueNumberChanged,
                  onGiveClue: onGiveClue,
                  onPass: onPass,
                ),
                const SizedBox(height: 14),
                _TeamProgress(board: board),
                const SizedBox(height: 14),
                _GameLog(board: board),
              ],
            ),
          ),
        ),
        if (state.amSpectator)
          ReactionsBar(
            gameTable: 'code_clues_games',
            gameId: game.id,
            familyId: familyId,
          ),
      ],
    );
  }
}

class _TopHud extends StatelessWidget {
  const _TopHud({required this.game, required this.board});
  final CodeCluesGame game;
  final CodeCluesBoardState board;

  @override
  Widget build(BuildContext context) {
    final seconds = game.turnSecondsRemaining ?? 0;
    final timerColor =
        seconds <= 5 ? KinrelColors.error : KinrelColors.textWhite;
    final teamColor = _teamColor(board.currentTurnTeam);
    final phaseLabel = board.phase == CodeCluesPhase.clueing
        ? 'Clueing'
        : board.phase == CodeCluesPhase.guessing
            ? 'Guessing'
            : 'Finished';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        border: Border(bottom: BorderSide(color: KinrelColors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration:
                BoxDecoration(color: teamColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${CodeCluesEngine.teamLabel(board.currentTurnTeam)} · $phaseLabel',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: teamColor,
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

class _ClueBanner extends StatelessWidget {
  const _ClueBanner({required this.board});
  final CodeCluesBoardState board;

  @override
  Widget build(BuildContext context) {
    final teamColor = _teamColor(board.currentTurnTeam);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: teamColor.withValues(alpha: 0.12),
        border: Border(bottom: BorderSide(color: teamColor.withValues(alpha: 0.3))),
      ),
      child: Row(
        children: [
          Icon(Icons.lightbulb_outline, size: 16, color: teamColor),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  color: KinrelColors.textSilver,
                ),
                children: [
                  const TextSpan(text: 'Clue '),
                  TextSpan(
                    text: board.clue?.toUpperCase() ?? '',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: teamColor,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const TextSpan(text: '  ·  '),
                  TextSpan(
                    text: '${board.clueNumber ?? 0}',
                    style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: teamColor,
                    ),
                  ),
                  if (board.clueGiverName != null) ...[
                    const TextSpan(text: '   from '),
                    TextSpan(
                      text: board.clueGiverName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: KinrelColors.textWhite),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: teamColor.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${board.guessesLeft} left',
              style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: teamColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _WordGrid extends StatelessWidget {
  const _WordGrid({
    required this.board,
    required this.canSeeAssignments,
    required this.myTeam,
    required this.canGuess,
    required this.onGuess,
  });

  final CodeCluesBoardState board;
  final bool canSeeAssignments;
  final int myTeam;
  final bool canGuess;
  final void Function(int) onGuess;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 0.92,
      ),
      itemCount: kCodeCluesGridSize,
      itemBuilder: (context, i) {
        final word = board.words[i];
        final revealed = board.revealed[i];
        final assignment = board.assignments[i];
        // Spymasters see assignments always; field agents see assignments
        // only for revealed cells.
        final showAssignment = canSeeAssignments || revealed;
        return _WordCell(
          word: word,
          assignment: assignment,
          revealed: revealed,
          showAssignment: showAssignment,
          isMyTeamWord: assignment == myTeam,
          canTap: canGuess && !revealed,
          onTap: () => onGuess(i),
        );
      },
    );
  }
}

class _WordCell extends StatelessWidget {
  const _WordCell({
    required this.word,
    required this.assignment,
    required this.revealed,
    required this.showAssignment,
    required this.isMyTeamWord,
    required this.canTap,
    required this.onTap,
  });

  final String word;
  final int assignment;
  final bool revealed;
  final bool showAssignment;
  final bool isMyTeamWord;
  final bool canTap;
  final VoidCallback onTap;

  Color get _assignmentColor {
    switch (assignment) {
      case CodeCluesAssignment.team1:
        return KinrelColors.orange;
      case CodeCluesAssignment.team2:
        return const Color(0xFF3B82F6);
      case CodeCluesAssignment.assassin:
        return const Color(0xFF1A1A1A);
      case CodeCluesAssignment.neutral:
      default:
        return const Color(0xFFA89B8C);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _assignmentColor;
    final isAssassin = assignment == CodeCluesAssignment.assassin;
    final isRevealedOrShown = revealed || showAssignment;

    Color bgColor;
    Color borderColor;
    Color textColor;
    if (isRevealedOrShown) {
      bgColor = color;
      borderColor = color;
      textColor = Colors.white;
    } else {
      bgColor = KinrelColors.darkCard;
      borderColor =
          canTap ? KinrelColors.amber.withValues(alpha: 0.6) : KinrelColors.border;
      textColor = KinrelColors.textWhite;
    }

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(KinrelRadius.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(KinrelRadius.sm),
        onTap: canTap ? onTap : null,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(KinrelRadius.sm),
            border: Border.all(color: borderColor, width: 1.2),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
          alignment: Alignment.center,
          child: Stack(
            children: [
              Center(
                child: Text(
                  word,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                    height: 1.1,
                  ),
                ),
              ),
              // Assassin marker for the spymaster's eye only.
              if (showAssignment && isAssassin && !revealed)
                Positioned(
                  top: 2,
                  right: 2,
                  child: Icon(Icons.close,
                      size: 10, color: Colors.white.withValues(alpha: 0.7)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionPanel extends StatelessWidget {
  const _ActionPanel({
    required this.board,
    required this.state,
    required this.isSpymaster,
    required this.myTeam,
    required this.amSpectator,
    required this.clueController,
    required this.clueNumber,
    required this.onClueNumberChanged,
    required this.onGiveClue,
    required this.onPass,
  });

  final CodeCluesBoardState board;
  final CodeCluesState_ state;
  final bool isSpymaster;
  final int myTeam;
  final bool amSpectator;
  final TextEditingController clueController;
  final int clueNumber;
  final void Function(int) onClueNumberChanged;
  final VoidCallback onGiveClue;
  final VoidCallback onPass;

  @override
  Widget build(BuildContext context) {
    if (amSpectator) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          border: Border.all(color: KinrelColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.visibility_outlined,
                size: 18, color: KinrelColors.textDim),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'You\'re spectating. Watch the spymasters battle it out!',
                style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    color: KinrelColors.textDim),
              ),
            ),
          ],
        ),
      );
    }

    // Spymaster of current team during clueing phase.
    if (board.phase == CodeCluesPhase.clueing &&
        isSpymaster &&
        myTeam == board.currentTurnTeam) {
      return _ClueInputCard(
        controller: clueController,
        number: clueNumber,
        onNumberChanged: onClueNumberChanged,
        isSubmitting: state.isSubmitting,
        onSubmit: onGiveClue,
      );
    }

    // Spymaster of current team during guessing phase — must wait.
    if (board.phase == CodeCluesPhase.guessing &&
        isSpymaster &&
        myTeam == board.currentTurnTeam) {
      return _WaitingCard(
        label: 'Field agents are guessing...',
        icon: Icons.hourglass_top_outlined,
      );
    }

    // Field agent of current team during guessing phase.
    if (board.phase == CodeCluesPhase.guessing &&
        !isSpymaster &&
        myTeam == board.currentTurnTeam) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          border: Border.all(
              color: _teamColor(board.currentTurnTeam)
                  .withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.touch_app_outlined,
                    size: 16, color: _teamColor(board.currentTurnTeam)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tap a word to guess it. Find your team\'s words!',
                    style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        color: KinrelColors.textSilver),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            DKButton(
              label: 'Pass turn',
              variant: DKButtonVariant.secondary,
              fullWidth: true,
              isLoading: state.isSubmitting,
              onPressed: onPass,
            ),
          ],
        ),
      );
    }

    // Anyone else (other team, or field agent of current team during
    // clueing phase) — just wait.
    return _WaitingCard(
      label: board.phase == CodeCluesPhase.clueing
          ? '${CodeCluesEngine.teamLabel(board.currentTurnTeam)} Spymaster is composing a clue...'
          : 'Waiting for ${CodeCluesEngine.teamLabel(board.currentTurnTeam)} to finish guessing...',
      icon: Icons.hourglass_top_outlined,
    );
  }
}

class _ClueInputCard extends StatelessWidget {
  const _ClueInputCard({
    required this.controller,
    required this.number,
    required this.onNumberChanged,
    required this.isSubmitting,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final int number;
  final void Function(int) onNumberChanged;
  final bool isSubmitting;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(
            color: KinrelColors.amber.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lightbulb_outlined,
                  size: 16, color: KinrelColors.amber),
              const SizedBox(width: 8),
              Text('Give your clue',
                  style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: KinrelColors.amber)),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            maxLength: kCodeCluesMaxClueLength,
            textCapitalization: TextCapitalization.characters,
            style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: KinrelColors.textWhite,
                letterSpacing: 1.0),
            decoration: InputDecoration(
              counterText: '',
              hintText: 'ONE WORD (e.g. OCEAN)',
              hintStyle: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 14,
                  color: KinrelColors.textDim.withValues(alpha: 0.6)),
              filled: true,
              fillColor: KinrelColors.darkElevated,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(KinrelRadius.md),
                borderSide: BorderSide(color: KinrelColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(KinrelRadius.md),
                borderSide: const BorderSide(
                    color: KinrelColors.amber, width: 1.4),
              ),
            ),
            onSubmitted: (_) => onSubmit(),
          ),
          const SizedBox(height: 10),
          Text('Number of related words (0–9)',
              style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 11,
                  color: KinrelColors.textDim)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var n = 0; n <= kCodeCluesMaxClueNumber; n++)
                _NumberPill(
                  value: n,
                  isSelected: n == number,
                  onTap: () => onNumberChanged(n),
                ),
            ],
          ),
          const SizedBox(height: 12),
          DKButton(
            label: 'Send clue',
            variant: DKButtonVariant.primary,
            fullWidth: true,
            isLoading: isSubmitting,
            onPressed: onSubmit,
          ),
        ],
      ),
    );
  }
}

class _NumberPill extends StatelessWidget {
  const _NumberPill({
    required this.value,
    required this.isSelected,
    required this.onTap,
  });

  final int value;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? KinrelColors.amber
          : KinrelColors.darkElevated,
      borderRadius: BorderRadius.circular(KinrelRadius.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(KinrelRadius.sm),
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(KinrelRadius.sm),
            border: Border.all(
                color: isSelected
                    ? KinrelColors.amber
                    : KinrelColors.border),
          ),
          child: Text(
            '$value',
            style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: isSelected
                    ? Colors.white
                    : KinrelColors.textSilver),
          ),
        ),
      ),
    );
  }
}

class _WaitingCard extends StatelessWidget {
  const _WaitingCard({required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(color: KinrelColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: KinrelColors.textDim),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    color: KinrelColors.textDim)),
          ),
        ],
      ),
    );
  }
}

class _TeamProgress extends StatelessWidget {
  const _TeamProgress({required this.board});
  final CodeCluesBoardState board;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(color: KinrelColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TeamProgressColumn(
              label: 'RED',
              color: KinrelColors.orange,
              found: board.team1Found,
              total: board.team1Total,
            ),
          ),
          Container(
              width: 1,
              height: 32,
              color: KinrelColors.border),
          Expanded(
            child: _TeamProgressColumn(
              label: 'BLUE',
              color: const Color(0xFF3B82F6),
              found: board.team2Found,
              total: board.team2Total,
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamProgressColumn extends StatelessWidget {
  const _TeamProgressColumn({
    required this.label,
    required this.color,
    required this.found,
    required this.total,
  });

  final String label;
  final Color color;
  final int found;
  final int total;

  @override
  Widget build(BuildContext context) {
    final remaining = total - found;
    return Column(
      children: [
        Text(label,
            style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: color)),
        const SizedBox(height: 4),
        Text('$found / $total',
            style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: KinrelColors.textWhite)),
        const SizedBox(height: 4),
        Text(remaining == 0 ? 'COMPLETE' : '$remaining left',
            style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 10,
                color: KinrelColors.textDim)),
      ],
    );
  }
}

class _GameLog extends StatelessWidget {
  const _GameLog({required this.board});
  final CodeCluesBoardState board;

  @override
  Widget build(BuildContext context) {
    final entries = board.log.reversed.take(8).toList();
    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(color: KinrelColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_outlined,
                  size: 14, color: KinrelColors.textDim),
              const SizedBox(width: 6),
              Text('LOG',
                  style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: KinrelColors.textDim)),
            ],
          ),
          const SizedBox(height: 8),
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _LogEntryRow(entry: e),
            ),
        ],
      ),
    );
  }
}

class _LogEntryRow extends StatelessWidget {
  const _LogEntryRow({required this.entry});
  final CodeCluesLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final teamColor = entry.team != null ? _teamColor(entry.team!) : KinrelColors.textDim;
    String text;
    IconData icon;
    Color color = KinrelColors.textSilver;
    switch (entry.type) {
      case 'clue':
        text =
            '${entry.user ?? 'Spymaster'} gave "${entry.clue?.toUpperCase()}" ${entry.number}';
        icon = Icons.lightbulb_outline;
        color = teamColor;
        break;
      case 'guess':
        final assignLabel = entry.assignment != null
            ? wordAssignmentLabel(entry.assignment!)
            : '';
        text =
            '${entry.user ?? 'Agent'} guessed "${entry.word}" ($assignLabel)';
        icon = Icons.touch_app_outlined;
        color = entry.assignment != null && entry.assignment! > 0
            ? _teamColor(entry.assignment!)
            : KinrelColors.textSilver;
        break;
      case 'pass':
        text = '${CodeCluesEngine.teamLabel(entry.team ?? 0)} passed';
        icon = Icons.flag_outlined;
        color = teamColor;
        break;
      case 'timeout':
        text =
            '${CodeCluesEngine.teamLabel(entry.team ?? 0)} timed out (${entry.word ?? 'turn'})';
        icon = Icons.timer_off_outlined;
        color = KinrelColors.error;
        break;
      case 'assassin':
        text = '${CodeCluesEngine.teamLabel(entry.team ?? 0)} hit the assassin!';
        icon = Icons.dangerous_outlined;
        color = KinrelColors.error;
        break;
      default:
        text = entry.type;
        icon = Icons.circle_outlined;
    }
    return Row(
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text,
              style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 11,
                  color: color)),
        ),
      ],
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

  final CodeCluesGame game;
  final String familyId;
  final List<CodeCluesPlayerWire> players;
  final Future<String?> Function() onRematch;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final board = game.boardState;
    final winningTeam = game.winningTeam ??
        (board?.winnerIndex != null && board!.winnerIndex > 0
            ? board.winnerIndex
            : null);
    final winnerColor = winningTeam == 2
        ? const Color(0xFF3B82F6)
        : KinrelColors.orange;
    final winnerName = winningTeam == 1
        ? 'Team Red'
        : winningTeam == 2
            ? 'Team Blue'
            : 'Match Complete';
    final isAssassinWin = game.endReason == 'assassin';
    final winnerPlayers = players
        .where((p) =>
            winningTeam != null &&
            p.team == winningTeam &&
            p.isActive)
        .toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(KinrelSpacing.lg),
      child: Column(
        children: [
          if (winningTeam != null)
            GameConfetti(colors: [winnerColor, KinrelColors.brightGold]),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  winnerColor.withValues(alpha: 0.18),
                  const Color(0xFF1C1410),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border:
                  Border.all(color: winnerColor.withValues(alpha: 0.45)),
            ),
            child: Column(
              children: [
                Icon(
                  isAssassinWin
                      ? Icons.dangerous_outlined
                      : Icons.emoji_events_outlined,
                  size: 40,
                  color: isAssassinWin
                      ? KinrelColors.error
                      : KinrelColors.brightGold,
                ),
                const SizedBox(height: 8),
                Text(
                  '$winnerName wins!',
                  style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: winnerColor),
                ),
                const SizedBox(height: 4),
                Text(
                  isAssassinWin
                      ? 'The other team hit the assassin — instant loss!'
                      : game.endReason == 'walkover'
                          ? 'The other team left the game.'
                          : 'All agents found!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      color: KinrelColors.textSilver),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (board != null) ...[
            GamingSectionHeader(
                title: 'Final Grid', icon: Icons.grid_on_outlined),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: KinrelColors.darkCard,
                borderRadius: BorderRadius.circular(KinrelRadius.md),
                border: Border.all(color: KinrelColors.border),
              ),
              child: _WordGrid(
                board: board,
                canSeeAssignments: true,
                myTeam: 0,
                canGuess: false,
                onGuess: (_) {},
              ),
            ),
            const SizedBox(height: 18),
            GamingSectionHeader(
                title: 'Winning Team', icon: Icons.people_alt_outlined),
            if (winnerPlayers.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('No active players on the winning team.',
                    style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        color: KinrelColors.textDim)),
              )
            else
              for (final p in winnerPlayers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: KinrelColors.darkCard,
                      borderRadius: BorderRadius.circular(KinrelRadius.md),
                      border: Border.all(
                          color: winnerColor.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        Text(
                            p.isSpymaster ? '🕵️' : '🎖️',
                            style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(p.userName,
                              style: TextStyle(
                                  fontFamily: KinrelTypography.bodyFont,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: KinrelColors.textWhite)),
                        ),
                        Text(
                            p.isSpymaster ? 'Spymaster' : 'Field Agent',
                            style: TextStyle(
                                fontFamily: KinrelTypography.monoFont,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: winnerColor)),
                      ],
                    ),
                  ),
                ),
            const SizedBox(height: 18),
          ],
          MatchEcosystemSummary(
            gameTable: 'code_clues_games',
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
                        '/family/$familyId/code-clues/game/$newId',
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

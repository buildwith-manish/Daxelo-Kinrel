// lib/features/games/sos/sos_board_screen.dart
//
// SOS Game — main board screen with the grid, letter placement,
// turn indicator, and live scores.
// Route: /family/$familyId/sos/game/$gameId

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
import 'sos_models.dart';
import 'sos_provider.dart';

class SosBoardScreen extends ConsumerStatefulWidget {
  const SosBoardScreen({
    super.key,
    required this.familyId,
    required this.gameId,
  });
  final String familyId;
  final String gameId;

  @override
  ConsumerState<SosBoardScreen> createState() => _SosBoardScreenState();
}

class _SosBoardScreenState extends ConsumerState<SosBoardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(sosProvider(widget.familyId));
      if (state.game == null) {
        ref.read(sosProvider(widget.familyId).notifier).joinGame(widget.gameId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sosProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;

    // Auto-navigate to results when game finishes
    ref.listen<SosState>(sosProvider(widget.familyId), (previous, next) {
      if (next.isFinished &&
          !(previous?.isFinished ?? false) &&
          mounted) {
        context.pushReplacement(
          '/family/${widget.familyId}/sos/results/${widget.gameId}',
        );
      }
    });

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () {
            ref.read(sosProvider(widget.familyId).notifier).leaveGame();
            Navigator.of(context).pop();
          },
        ),
        title: Text(
          'SOS',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontWeight: FontWeight.w600,
            color: KinrelColors.textWhite,
          ),
        ),
        backgroundColor: KinrelColors.darkCard,
        foregroundColor: KinrelColors.textWhite,
        elevation: 0,
      ),
      body: state.isLoading && state.game == null
          ? const Center(
              child: CircularProgressIndicator(color: KinrelColors.orange),
            )
          : state.error != null && state.game == null
          ? DKErrorState(
              message: state.error!,
              onRetry: () => ref
                  .read(sosProvider(widget.familyId).notifier)
                  .joinGame(widget.gameId),
            )
          : state.isLobby
              ? _waitingRoom(state, myId)
              : _gameView(state, myId),
    );
  }

  Widget _waitingRoom(SosState state, String? myId) {
    final game = state.game;
    if (game == null) return const SizedBox.shrink();
    final isHost = game.hostUserId == myId;
    final canStart = state.players.length >= game.mode.minPlayers;
    final code = game.id.replaceAll('-', '').substring(0, 6).toUpperCase();

    return ListView(
      padding: const EdgeInsets.all(KinrelSpacing.base),
      children: [
        Container(
          padding: const EdgeInsets.all(KinrelSpacing.lg),
          decoration: BoxDecoration(
            gradient: KinrelGradients.igniteGradient,
            borderRadius: BorderRadius.circular(KinrelRadius.lg),
          ),
          child: Column(
            children: [
              Text(
                'Share Code',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.9),
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: KinrelSpacing.sm),
              Text(
                code,
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 8,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                game.mode == SosMode.fourPlayerTeams
                    ? 'Waiting for ${game.mode.minPlayers - state.players.length} more players'
                    : 'Waiting for ${game.mode.minPlayers - state.players.length} more player',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: KinrelSpacing.lg),
        Text(
          'Players (${state.players.length}/${game.mode.maxPlayers})',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: KinrelColors.textDim,
          ),
        ),
        const SizedBox(height: KinrelSpacing.sm),
        ...state.players.map((p) => Container(
              margin: const EdgeInsets.only(bottom: KinrelSpacing.sm),
              padding: const EdgeInsets.symmetric(
                horizontal: KinrelSpacing.md,
                vertical: KinrelSpacing.md,
              ),
              decoration: BoxDecoration(
                color: KinrelColors.darkCard,
                borderRadius: BorderRadius.circular(KinrelRadius.lg),
                border: Border.all(
                  color: p.team != null
                      ? Color(p.team!.colorValue)
                      : KinrelColors.border,
                  width: p.userId == myId ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  DKAvatar(
                    initials: p.userName.isNotEmpty
                        ? p.userName[0].toUpperCase()
                        : '?',
                  ),
                  const SizedBox(width: KinrelSpacing.md),
                  Expanded(
                    child: Text(
                      p.userId == myId ? '${p.userName} (You)' : p.userName,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.textWhite,
                      ),
                    ),
                  ),
                  if (p.team != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: Color(p.team!.colorValue).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        p.team!.name,
                        style: TextStyle(
                          fontFamily: KinrelTypography.monoFont,
                          fontSize: 10,
                          color: Color(p.team!.colorValue),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            )),
        const SizedBox(height: KinrelSpacing.xl),
        if (isHost)
          DKButton(
            label: canStart
                ? 'Start Game'
                : 'Waiting for ${game.mode.minPlayers - state.players.length} more…',
            variant: DKButtonVariant.gradient,
            fullWidth: true,
            onPressed: canStart
                ? () => ref
                    .read(sosProvider(widget.familyId).notifier)
                    .startGame()
                : null,
          )
        else
          Container(
            padding: const EdgeInsets.all(KinrelSpacing.lg),
            decoration: BoxDecoration(
              color: KinrelColors.darkCard,
              borderRadius: BorderRadius.circular(KinrelRadius.lg),
              border: Border.all(color: KinrelColors.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: KinrelColors.orange,
                  ),
                ),
                const SizedBox(width: KinrelSpacing.sm),
                Text(
                  'Waiting for host to start the game…',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    color: KinrelColors.textDim,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _gameView(SosState state, String? myId) {
    final game = state.game;
    if (game == null) return const SizedBox.shrink();
    final gridSize = game.gridSize;
    final grid = state.grid;
    final currentPlayer = state.currentPlayer;
    final isMyTurn = state.isMyTurn;

    // Determine my letter (4-player team mode)
    SosLetter? myLetter;
    if (game.mode == SosMode.fourPlayerTeams && state.myTeam != null) {
      myLetter = state.myTeam == SosTeam.s ? SosLetter.s : SosLetter.o;
    }

    return SafeArea(
      child: Column(
        children: [
          // Score bar
          _scoreBar(state, myId),
          // Turn indicator
          _turnIndicator(state, currentPlayer, isMyTurn, myId),
          const SizedBox(height: KinrelSpacing.sm),
          // Grid
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1.0,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  child: GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: gridSize,
                      mainAxisSpacing: 3,
                      crossAxisSpacing: 3,
                    ),
                    itemCount: gridSize * gridSize,
                    itemBuilder: (context, index) {
                      final row = index ~/ gridSize;
                      final col = index % gridSize;
                      return _cell(
                        context,
                        row: row,
                        col: col,
                        letter: grid[row][col],
                        state: state,
                        isMyTurn: isMyTurn,
                        myLetter: myLetter,
                        myId: myId,
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: KinrelSpacing.base),
          // Letter choice (2-player mode only)
          if (game.mode == SosMode.twoPlayer && isMyTurn)
            _letterChoiceRow(state, myId)
          else if (game.mode == SosMode.fourPlayerTeams && state.myTeam != null)
            _teamIndicator(state.myTeam!),
          const SizedBox(height: KinrelSpacing.base),
        ],
      ),
    );
  }

  Widget _scoreBar(SosState state, String? myId) {
    final game = state.game;
    if (game == null) return const SizedBox.shrink();

    if (game.mode == SosMode.twoPlayer) {
      // Show per-player scores
      final sorted = List<SosPlayer>.from(state.players)
        ..sort((a, b) => a.turnOrder.compareTo(b.turnOrder));
      return Container(
        margin: const EdgeInsets.all(KinrelSpacing.base),
        padding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.md,
          vertical: KinrelSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
          border: Border.all(color: KinrelColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: sorted.map((p) {
            final isMe = p.userId == myId;
            return _scoreChip(
              label: isMe ? '${p.userName} (You)' : p.userName,
              score: p.score,
              color: KinrelColors.orange,
              isActive: state.currentPlayer?.userId == p.userId,
            );
          }).toList(),
        ),
      );
    }

    // 4-player team mode: show team scores
    final teamScores = state.teamScores;
    return Container(
      margin: const EdgeInsets.all(KinrelSpacing.base),
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.md,
        vertical: KinrelSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(color: KinrelColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _scoreChip(
            label: SosTeam.s.label,
            score: teamScores[SosTeam.s] ?? 0,
            color: Color(SosTeam.s.colorValue),
            isActive: state.currentPlayer?.team == SosTeam.s,
          ),
          Container(
            width: 1,
            height: 32,
            color: KinrelColors.border,
          ),
          _scoreChip(
            label: SosTeam.o.label,
            score: teamScores[SosTeam.o] ?? 0,
            color: Color(SosTeam.o.colorValue),
            isActive: state.currentPlayer?.team == SosTeam.o,
          ),
        ],
      ),
    );
  }

  Widget _scoreChip({
    required String label,
    required int score,
    required Color color,
    required bool isActive,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 11,
            color: isActive ? color : KinrelColors.textDim,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(
            '$score',
            key: ValueKey(score),
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: isActive ? color : KinrelColors.textWhite,
            ),
          ),
        ),
      ],
    );
  }

  Widget _turnIndicator(
    SosState state,
    SosPlayer? currentPlayer,
    bool isMyTurn,
    String? myId,
  ) {
    if (currentPlayer == null) return const SizedBox.shrink();
    final isMe = currentPlayer.userId == myId;
    final teamColor = currentPlayer.team != null
        ? Color(currentPlayer.team!.colorValue)
        : KinrelColors.orange;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.md,
        vertical: KinrelSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: teamColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(color: teamColor, width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (isMyTurn)
            const Icon(Icons.pan_tool_rounded, size: 16, color: Colors.white)
          else
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: teamColor,
              ),
            ),
          const SizedBox(width: KinrelSpacing.sm),
          Text(
            isMe
                ? (state.game?.mode == SosMode.fourPlayerTeams
                    ? 'Your turn — Team ${state.myTeam?.name ?? ""}'
                    : 'Your turn')
                : (currentPlayer.team != null
                    ? "${currentPlayer.userName}'s turn (Team ${currentPlayer.team!.name})"
                    : "${currentPlayer.userName}'s turn"),
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              color: KinrelColors.textWhite,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(
    BuildContext context, {
    required int row,
    required int col,
    required String? letter,
    required SosState state,
    required bool isMyTurn,
    SosLetter? myLetter,
    String? myId,
  }) {
    final game = state.game!;
    final isOccupied = letter != null;
    final move = state.moves
        .where((m) => m.rowIdx == row && m.colIdx == col)
        .firstOrNull;
    final cellTeam = move?.team;
    final cellColor = cellTeam != null
        ? Color(cellTeam.colorValue)
        : (isOccupied ? KinrelColors.textWhite : KinrelColors.darkElevated);
    final isPartOfSequence = state.sequences.any(
      (seq) => seq.cells.any((c) => c.$1 == row && c.$2 == col),
    );

    final canPlace = !isOccupied && isMyTurn && state.game!.isActive;
    final onTap = canPlace
        ? () => _onCellTap(row, col, state, myLetter)
        : null;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isPartOfSequence
              ? cellColor.withValues(alpha: 0.3)
              : (isOccupied
                    ? cellColor.withValues(alpha: 0.15)
                    : KinrelColors.darkCard),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isPartOfSequence
                ? cellColor
                : (canPlace
                      ? KinrelColors.orange.withValues(alpha: 0.4)
                      : KinrelColors.border),
            width: isPartOfSequence ? 2 : 1,
          ),
        ),
        child: Center(
          child: Text(
            letter ?? '',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: cellColor,
            ),
          ),
        ),
      )
          .animate(target: isOccupied ? 1 : 0)
          .scale(
            begin: const Offset(0.5, 0.5),
            end: const Offset(1.0, 1.0),
            duration: 200.ms,
            curve: Curves.elasticOut,
          ),
    );
  }

  void _onCellTap(
    int row,
    int col,
    SosState state,
    SosLetter? myLetter,
  ) {
    final game = state.game;
    if (game == null) return;

    if (game.mode == SosMode.fourPlayerTeams) {
      // Letter is fixed by team — no popup needed
      if (myLetter == null) return;
      ref.read(sosProvider(widget.familyId).notifier).placeLetter(
        row: row,
        col: col,
        letter: myLetter,
      );
      return;
    }

    // 2-player mode: show letter choice popup
    _showLetterChoicePopup(row, col);
  }

  void _showLetterChoicePopup(int row, int col) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(KinrelRadius.lg)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(KinrelSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Choose a letter',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: KinrelSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _letterOption(ctx, SosLetter.s, row, col),
                _letterOption(ctx, SosLetter.o, row, col),
              ],
            ),
            const SizedBox(height: KinrelSpacing.lg),
          ],
        ),
      ),
    );
  }

  Widget _letterOption(
    BuildContext ctx,
    SosLetter letter,
    int row,
    int col,
  ) {
    return GestureDetector(
      onTap: () {
        Navigator.of(ctx).pop();
        ref.read(sosProvider(widget.familyId).notifier).placeLetter(
          row: row,
          col: col,
          letter: letter,
        );
      },
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: KinrelColors.darkElevated,
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
          border: Border.all(color: KinrelColors.orange, width: 2),
        ),
        child: Center(
          child: Text(
            letter.char,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 40,
              fontWeight: FontWeight.w800,
              color: KinrelColors.orange,
            ),
          ),
        ),
      ),
    );
  }

  Widget _letterChoiceRow(SosState state, String? myId) {
    // Fallback — usually we use the popup, but this shows a hint
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: Text(
        'Tap an empty cell to place S or O',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 12,
          color: KinrelColors.textDim,
        ),
      ),
    );
  }

  Widget _teamIndicator(SosTeam team) {
    final color = Color(team.colorValue);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.md,
        vertical: KinrelSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(color: color, width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'You are ',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              color: KinrelColors.textWhite,
            ),
          ),
          Text(
            team.label,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          Text(
            ' — placing ${team.name}',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              color: KinrelColors.textWhite,
            ),
          ),
        ],
      ),
    );
  }
}

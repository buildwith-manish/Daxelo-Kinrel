// lib/features/games/connect4/connect4_game_screen.dart
//
// Connect 4 — the board.
//
// Layout (portrait-first):
//   ┌──────────────────────────────────────┐
//   │  ←  Connect 4               ⟳ 30    │ top bar (game name + turn timer)
//   │  🔴 Manish's Turn — drop a disc!     │ turn banner
//   ├──────────────────────────────────────┤
//   │                                      │
//   │   ●  ●  ●  ●  ●  ●  ●               │ 7×6 board grid
//   │   ●  ●  ●  ●  ●  ●  ●               │ tap a column to drop
//   │   ●  ●  ●  ●  ●  ●  ●               │ discs animate falling
//   │   ●  ●  ●  ●  ●  ●  ●               │ winning line highlights
//   │   ●  ●  ●  ●  ●  ●  ●               │
//   │   ●  ●  ●  ●  ●  ●  ●               │
//   │                                      │
//   ├──────────────────────────────────────┤
//   │  (spectators: ❤️ 🔥 👏 bar)          │
//   └──────────────────────────────────────┘
//
// Completed → inline results: winner banner, placements, ecosystem
// rewards, rematch.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
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
import '../shared/icons/kinrel_icons.dart';
import '../shared/widgets/reactions_bar.dart';
import 'connect4_engine.dart';
import 'connect4_models.dart';
import 'connect4_provider.dart';

/// Player colors: Red (player 0) and Yellow (player 1).
class Connect4Colors {
  Connect4Colors._();
  static const Color red = Color(0xFFEF4444);
  static const Color yellow = Color(0xFFF59E0B);
  static const Color empty = Color(0xFF1A1B26);
  static const Color board = Color(0xFF2563EB); // classic blue board

  static Color forPlayer(int playerIndex) =>
      playerIndex == 0 ? red : yellow;
}

class Connect4GameScreen extends ConsumerStatefulWidget {
  const Connect4GameScreen({
    super.key,
    required this.familyId,
    required this.gameId,
  });

  final String familyId;
  final String gameId;

  @override
  ConsumerState<Connect4GameScreen> createState() =>
      _Connect4GameScreenState();
}

class _Connect4GameScreenState extends ConsumerState<Connect4GameScreen> {
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(connect4Provider(widget.familyId).notifier)
          .loadGame(widget.gameId);
    });
    _clockTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _confirmLeave() async {
    final state = ref.read(connect4Provider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final shouldLeave = await LeaveGameDialog.show(
      context,
      isHost: state.game?.hostUserId == myId && state.game?.isWaiting == true,
      gameName: 'Connect 4',
    );
    if (shouldLeave == true) {
      await ref
          .read(connect4Provider(widget.familyId).notifier)
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(connect4Provider(widget.familyId));
    final game = state.game;

    if (state.isLoading && game == null) {
      return DKScaffold(
        backgroundColor: KinrelColors.darkSurface,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _confirmLeave,
          ),
          title: const Text('Connect 4'),
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
            onPressed: () => context.go('/family/${widget.familyId}'),
          ),
          title: const Text('Connect 4'),
          backgroundColor: KinrelColors.darkCard,
          foregroundColor: KinrelColors.textWhite,
        ),
        body: Center(
          child: GamingEmptyCard(
            emoji: '🔴',
            title: 'Game not found',
            message: 'This game may have ended or been cancelled.',
          ),
        ),
      );
    }

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: _buildAppBar(game),
      body: game.isCompleted
          ? _ResultsView(
              game: game,
              familyId: widget.familyId,
              players: state.players,
              onRematch: () => ref
                  .read(connect4Provider(widget.familyId).notifier)
                  .rematch(),
              onExit: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/family/${widget.familyId}');
                }
              },
            )
          : _BoardView(
              state: state,
              familyId: widget.familyId,
              onDrop: (col) => ref
                  .read(connect4Provider(widget.familyId).notifier)
                  .dropDisc(col),
            ),
    );
  }

  PreferredSizeWidget _buildAppBar(Connect4Game game) {
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final turnSeconds = game.turnSecondsRemaining;
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: _confirmLeave,
      ),
      title: Text(
        game.roomName?.isNotEmpty == true ? game.roomName! : 'Connect 4',
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
        if (game.isInProgress && turnSeconds != null)
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(child: _TurnTimer(seconds: turnSeconds)),
          ),
        if (game.hostUserId == myId && game.isInProgress)
          IconButton(
            tooltip: 'Leave game',
            icon: const Icon(Icons.logout, size: 20),
            onPressed: _confirmLeave,
          ),
      ],
    );
  }
}

class _TurnTimer extends StatelessWidget {
  const _TurnTimer({required this.seconds});
  final int seconds;

  @override
  Widget build(BuildContext context) {
    final isUrgent = seconds <= 5;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (isUrgent ? KinrelColors.error : KinrelColors.orange)
            .withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined,
              size: 14,
              color: isUrgent ? KinrelColors.error : KinrelColors.orange),
          const SizedBox(width: 4),
          Text(
            '${seconds}s',
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isUrgent ? KinrelColors.error : KinrelColors.orange,
            ),
          ),
        ],
      ),
    );
  }
}

class _BoardView extends ConsumerWidget {
  const _BoardView({
    required this.state,
    required this.familyId,
    required this.onDrop,
  });

  final Connect4State state;
  final String familyId;
  final void Function(int column) onDrop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = state.game!;
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final boardState = game.boardState;
    final isMyTurn = game.currentPlayerId == myId;

    final currentPlayerName = state.players
        .where((p) => p.userId == game.currentPlayerId)
        .map((p) => p.userName)
        .firstWhere((_) => true, orElse: () => 'Player');

    return Column(
      children: [
        _TurnBanner(
          game: game,
          isMyTurn: isMyTurn,
          currentPlayerName: currentPlayerName,
          currentPlayerIndex:
              state.players.indexWhere((p) => p.userId == game.currentPlayerId),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(KinrelSpacing.md),
              child: boardState == null
                  ? const SizedBox(
                      height: 300,
                      child: Center(
                        child: CircularProgressIndicator(
                            color: KinrelColors.orange),
                      ),
                    )
                  : Connect4Board(
                      boardState: boardState,
                      isMyTurn: isMyTurn,
                      onDrop: onDrop,
                      winningCells: boardState.winner.winningCells,
                    ),
            ),
          ),
        ),
        if (state.amSpectator)
          ReactionsBar(
            gameTable: 'connect4_games',
            gameId: game.id,
            familyId: familyId,
          ),
      ],
    );
  }
}

class _TurnBanner extends StatelessWidget {
  const _TurnBanner({
    required this.game,
    required this.isMyTurn,
    required this.currentPlayerName,
    required this.currentPlayerIndex,
  });

  final Connect4Game game;
  final bool isMyTurn;
  final String currentPlayerName;
  final int currentPlayerIndex;

  @override
  Widget build(BuildContext context) {
    final color = currentPlayerIndex >= 0
        ? Connect4Colors.forPlayer(currentPlayerIndex)
        : Connect4Colors.red;

    final message = isMyTurn
        ? 'Your turn — tap a column to drop!'
        : "$currentPlayerName's turn — waiting...";

    return Container(
      margin: const EdgeInsets.fromLTRB(
          KinrelSpacing.md, KinrelSpacing.sm, KinrelSpacing.md, KinrelSpacing.sm),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: color, blurRadius: 6)],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// The board — 7×6 grid of tappable columns
// ─────────────────────────────────────────────────────────────────────────

class Connect4Board extends StatelessWidget {
  const Connect4Board({
    super.key,
    required this.boardState,
    required this.isMyTurn,
    required this.onDrop,
    required this.winningCells,
  });

  final Connect4GameState boardState;
  final bool isMyTurn;
  final void Function(int column) onDrop;
  final List<(int, int)> winningCells;

  @override
  Widget build(BuildContext context) {
    final validColumns = Connect4Engine.getValidColumns(boardState);
    final winningSet = winningCells.toSet();

    return Center(
      child: AspectRatio(
        aspectRatio: kConnect4Columns / kConnect4Rows,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Connect4Colors.board,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Connect4Colors.board.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            children: [
              for (var row = 0; row < kConnect4Rows; row++)
                Expanded(
                  child: Row(
                    children: [
                      for (var col = 0; col < kConnect4Columns; col++)
                        Expanded(
                          child: _Cell(
                            value: boardState.board[row][col],
                            isWinning: winningSet.contains((row, col)),
                            canDrop: isMyTurn && validColumns.contains(col),
                            onTap: () => onDrop(col),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.value,
    required this.isWinning,
    required this.canDrop,
    required this.onTap,
  });

  final int value; // -1 = empty, 0 = red, 1 = yellow
  final bool isWinning;
  final bool canDrop;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final discColor = value == 0
        ? Connect4Colors.red
        : value == 1
            ? Connect4Colors.yellow
            : Connect4Colors.empty;

    return GestureDetector(
      onTap: canDrop ? onTap : null,
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: discColor,
          border: isWinning
              ? Border.all(color: Colors.white, width: 3)
              : null,
          boxShadow: isWinning
              ? [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.5),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ]
              : (value >= 0
                  ? [
                      BoxShadow(
                        color: discColor.withValues(alpha: 0.4),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null),
        ),
        child: canDrop && value == -1
            ? Center(
                child: Icon(
                  Icons.arrow_drop_down,
                  size: 20,
                  color: Colors.white.withValues(alpha: 0.2),
                ),
              )
            : null,
      ),
    )
        .animate(target: value >= 0 ? 1 : 0)
        .scale(
          begin: const Offset(0.7, 0.7),
          end: const Offset(1, 1),
          duration: 200.ms,
          curve: Curves.easeOutBack,
        );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Results view
// ─────────────────────────────────────────────────────────────────────────

class _ResultsView extends StatelessWidget {
  const _ResultsView({
    required this.game,
    required this.familyId,
    required this.players,
    required this.onRematch,
    required this.onExit,
  });

  final Connect4Game game;
  final String familyId;
  final List<Connect4Player> players;
  final Future<String?> Function() onRematch;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final winnerIds = game.winnerUserIds;
    final isDraw = game.endReason == 'draw';

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
          if (winnerIds.isNotEmpty)
            const GameConfetti(),

          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2A1A0E), Color(0xFF1C1410)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: KinrelColors.brightGold.withValues(alpha: 0.4)),
            ),
            child: Column(
              children: [
                KinrelIcon(
                  isDraw ? KinrelIconData.handshake : KinrelIconData.trophy,
                  size: 40,
                  color: isDraw
                      ? KinrelColors.textSilver
                      : KinrelColors.brightGold,
                ),
                const SizedBox(height: 8),
                Text(
                  isDraw
                      ? 'It\'s a Draw!'
                      : '$winnerName wins!',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: isDraw
                        ? KinrelColors.textSilver
                        : KinrelColors.brightGold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  game.endReasonLabel,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    color: KinrelColors.textSilver,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // Show the final board if available
          if (game.boardState != null) ...[
            GamingSectionHeader(
              title: 'Final Board',
              icon: Icons.grid_view_outlined,
            ),
            Connect4Board(
              boardState: game.boardState!,
              isMyTurn: false,
              onDrop: (_) {},
              winningCells: game.boardState!.winner.winningCells,
            ),
            const SizedBox(height: 18),
          ],

          MatchEcosystemSummary(
            gameTable: 'connect4_games',
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
                        '/family/$familyId/connect4/game/$newId',
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

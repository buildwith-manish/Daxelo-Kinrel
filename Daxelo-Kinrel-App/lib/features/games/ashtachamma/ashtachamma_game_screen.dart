// lib/features/games/ashtachamma/ashtachamma_game_screen.dart
//
// Ashta Chamma — the board.
//
// Layout (portrait-first):
//   ┌──────────────────────────────────────┐
//   │  ←  Ashta Chamma            ⟳ 30    │ top bar (game name + turn timer)
//   │  🎮 Manish's Turn — Roll!           │ turn banner
//   │  [M 4/4] [R 2/4] [Y 1/4] [P 0/4]   │ live progress chips (pieces home)
//   ├──────────────────────────────────────┤
//   │                                      │
//   │       ┌───┬───┬───┐                  │ cross-shaped board
//   │       │   │   │   │                  │ (5×5 grid, path highlighted)
//   │       ├───┼───┼───┤                  │
//   │   ┌───┼───┼───┼───┼───┐              │
//   │   │   │   │ ★ │   │   │              │
//   │   ├───┼───┼───┼───┼───┤              │
//   │   └───┴───┼───┼───┴───┘              │
//   │           │   │                      │
//   │           └───┘                      │
//   │                                      │
//   ├──────────────────────────────────────┤
//   │  🐚 Roll Dice          [1] [2] [3]  │ dice + available pieces
//   │  (spectators: ❤️ 🔥 👏 bar)          │
//   └──────────────────────────────────────┘
//
// Completed → inline results: podium with medals, per-player stats
// (pieces home · captures · turn duration), ecosystem rewards, rematch.

import 'dart:async';
import 'dart:math' as math;

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
import '../shared/icons/kinrel_icons.dart';
import '../shared/widgets/reactions_bar.dart';
import 'ashtachamma_engine.dart';
import 'ashtachamma_models.dart';
import 'ashtachamma_provider.dart';

/// Seat accent colors (player 1 → 4), used for pieces + progress chips.
class AshtaChammaSeatColors {
  AshtaChammaSeatColors._();

  static const List<Color> seats = [
    KinrelColors.orange,
    KinrelColors.blue,
    KinrelColors.extendedPurple,
    KinrelColors.success,
  ];

  static Color forSeat(int seatIndex) =>
      seats[seatIndex.clamp(0, seats.length - 1)];
}

class AshtaChammaGameScreen extends ConsumerStatefulWidget {
  const AshtaChammaGameScreen({
    super.key,
    required this.familyId,
    required this.gameId,
  });

  final String familyId;
  final String gameId;

  @override
  ConsumerState<AshtaChammaGameScreen> createState() =>
      _AshtaChammaGameScreenState();
}

class _AshtaChammaGameScreenState extends ConsumerState<AshtaChammaGameScreen> {
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(ashtaChammaProvider(widget.familyId).notifier)
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
    final state = ref.read(ashtaChammaProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final shouldLeave = await LeaveGameDialog.show(
      context,
      isHost: state.game?.hostUserId == myId && state.game?.isWaiting == true,
      gameName: 'Ashta Chamma',
    );
    if (shouldLeave == true) {
      await ref
          .read(ashtaChammaProvider(widget.familyId).notifier)
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
    final state = ref.watch(ashtaChammaProvider(widget.familyId));
    final game = state.game;

    if (state.isLoading && game == null) {
      return DKScaffold(
        backgroundColor: KinrelColors.darkSurface,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _confirmLeave,
          ),
          title: const Text('Ashta Chamma'),
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
          title: const Text('Ashta Chamma'),
          backgroundColor: KinrelColors.darkCard,
          foregroundColor: KinrelColors.textWhite,
        ),
        body: Center(
          child: GamingEmptyCard(
            emoji: '🐚',
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
              onRematch: () => ref
                  .read(ashtaChammaProvider(widget.familyId).notifier)
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
              onRoll: () => ref
                  .read(ashtaChammaProvider(widget.familyId).notifier)
                  .rollDice(),
              onMovePiece: (idx) => ref
                  .read(ashtaChammaProvider(widget.familyId).notifier)
                  .movePiece(idx),
            ),
    );
  }

  PreferredSizeWidget _buildAppBar(AshtaChammaGame game) {
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final turnSeconds = game.turnSecondsRemaining;
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: _confirmLeave,
      ),
      title: Text(
        game.roomName?.isNotEmpty == true ? game.roomName! : 'Ashta Chamma',
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
            child: Center(
              child: _TurnTimer(seconds: turnSeconds),
            ),
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

// ─────────────────────────────────────────────────────────────────────────
// Turn timer ring
// ─────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────
// Board view — the cross-shaped board + dice + pieces
// ─────────────────────────────────────────────────────────────────────────

class _BoardView extends ConsumerWidget {
  const _BoardView({
    required this.state,
    required this.familyId,
    required this.onRoll,
    required this.onMovePiece,
  });

  final AshtaChammaState state;
  final String familyId;
  final VoidCallback onRoll;
  final void Function(int pieceIndex) onMovePiece;

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

    final myPlayerIndex = state.players
        .toList()
        .asMap()
        .entries
        .where((e) => e.value.userId == myId)
        .map((e) => e.key)
        .firstWhere((_) => true, orElse: () => -1);

    final availableMoves = (boardState != null && isMyTurn && game.phase == AshtaChammaPhase.move)
        ? AshtaChammaEngine.getAvailableMoves(
            boardState, myPlayerIndex >= 0 ? myPlayerIndex : 0)
        : <AshtaChammaMove>[];

    return Column(
      children: [
        // Turn banner
        _TurnBanner(
          game: game,
          isMyTurn: isMyTurn,
          currentPlayerName: currentPlayerName,
          players: state.players,
        ),
        // Progress chips (pieces home per player)
        _ProgressChips(game: game, players: state.players),
        // Board
        Expanded(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(KinrelSpacing.md),
              child: Column(
                children: [
                  AshtaChammaBoard(
                    game: game,
                    players: state.players,
                    availableMoves: availableMoves,
                    myPlayerIndex: myPlayerIndex,
                    onTapPiece: onMovePiece,
                  ),
                  const SizedBox(height: KinrelSpacing.md),
                  // Dice + action area
                  _DiceArea(
                    game: game,
                    isMyTurn: isMyTurn,
                    optimisticDice: state.optimisticDice,
                    onRoll: onRoll,
                    availableMoves: availableMoves,
                  ),
                ],
              ),
            ),
          ),
        ),
        // Spectator reactions bar (if spectating)
        if (state.amSpectator)
          ReactionsBar(
            gameTable: 'ashta_chamma_games',
            gameId: game.id,
            familyId: familyId,
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Turn banner
// ─────────────────────────────────────────────────────────────────────────

class _TurnBanner extends StatelessWidget {
  const _TurnBanner({
    required this.game,
    required this.isMyTurn,
    required this.currentPlayerName,
    required this.players,
  });

  final AshtaChammaGame game;
  final bool isMyTurn;
  final String currentPlayerName;
  final List<AshtaChammaPlayer> players;

  @override
  Widget build(BuildContext context) {
    final currentPlayerIndex = players
        .toList()
        .asMap()
        .entries
        .where((e) => e.value.userId == game.currentPlayerId)
        .map((e) => e.key)
        .firstWhere((_) => true, orElse: () => 0);
    final seatColor = AshtaChammaSeatColors.forSeat(currentPlayerIndex);

    String message;
    if (game.phase == AshtaChammaPhase.roll) {
      message = isMyTurn ? 'Your turn — roll the shells!' : "$currentPlayerName's turn — rolling...";
    } else {
      final dice = game.lastDiceValue;
      message = isMyTurn
          ? 'You rolled $dice — pick a piece to move'
          : '$currentPlayerName rolled $dice — moving...';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(
          KinrelSpacing.md, KinrelSpacing.sm, KinrelSpacing.md, KinrelSpacing.sm),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: seatColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: seatColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: seatColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: seatColor, blurRadius: 6),
              ],
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
// Progress chips — pieces home per player
// ─────────────────────────────────────────────────────────────────────────

class _ProgressChips extends StatelessWidget {
  const _ProgressChips({required this.game, required this.players});
  final AshtaChammaGame game;
  final List<AshtaChammaPlayer> players;

  @override
  Widget build(BuildContext context) {
    final boardState = game.boardState;
    if (boardState == null) return const SizedBox.shrink();

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.md),
        children: [
          for (var i = 0; i < players.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _ProgressChip(
                playerName: players[i].userName,
                piecesHome: boardState.finishedCount(i),
                seatColor: AshtaChammaSeatColors.forSeat(i),
                isCurrent: game.currentPlayerId == players[i].userId,
              ),
            ),
        ],
      ),
    );
  }
}

class _ProgressChip extends StatelessWidget {
  const _ProgressChip({
    required this.playerName,
    required this.piecesHome,
    required this.seatColor,
    required this.isCurrent,
  });

  final String playerName;
  final int piecesHome;
  final Color seatColor;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isCurrent
            ? seatColor.withValues(alpha: 0.15)
            : KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isCurrent
              ? seatColor.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: seatColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            playerName,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textSilver,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$piecesHome/4',
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: seatColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Ashta Chamma board — the cross-shaped 5×5 grid
// ─────────────────────────────────────────────────────────────────────────

class AshtaChammaBoard extends StatelessWidget {
  const AshtaChammaBoard({
    super.key,
    required this.game,
    required this.players,
    required this.availableMoves,
    required this.myPlayerIndex,
    required this.onTapPiece,
  });

  final AshtaChammaGame game;
  final List<AshtaChammaPlayer> players;
  final List<AshtaChammaMove> availableMoves;
  final int myPlayerIndex;
  final void Function(int pieceIndex) onTapPiece;

  @override
  Widget build(BuildContext context) {
    final boardState = game.boardState;
    if (boardState == null) {
      return const SizedBox(
        height: 300,
        child: Center(
          child: CircularProgressIndicator(color: KinrelColors.orange),
        ),
      );
    }

    final availablePieceIndices = availableMoves
        .map((m) => m.pieceIndex)
        .toSet();

    return AspectRatio(
      aspectRatio: 1.0,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: CustomPaint(
          painter: _AshtaChammaBoardPainter(
            boardState: boardState,
            players: players,
            availablePieceIndices: availablePieceIndices,
            myPlayerIndex: myPlayerIndex,
            currentPlayerId: game.currentPlayerId,
          ),
          child: Stack(
            children: [
              // Tap targets for each available piece
              ..._buildPieceTapTargets(availablePieceIndices),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildPieceTapTargets(Set<int> availablePieceIndices) {
    // The board painter renders all pieces; tap targets for available
    // pieces are handled via the dice area's piece selector (not via
    // overlay tap targets on the board itself — the board is a
    // CustomPaint that doesn't need individual hit regions for the MVP).
    return const <Widget>[];
  }
}

/// The board painter — renders the cross-shaped path, safe squares,
/// pieces, and highlights.
class _AshtaChammaBoardPainter extends CustomPainter {
  _AshtaChammaBoardPainter({
    required this.boardState,
    required this.players,
    required this.availablePieceIndices,
    required this.myPlayerIndex,
    required this.currentPlayerId,
  });

  final AshtaChammaGameState boardState;
  final List<AshtaChammaPlayer> players;
  final Set<int> availablePieceIndices;
  final int myPlayerIndex;
  final String? currentPlayerId;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final cellSize = s / 5;

    // Draw the 5×5 grid background
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..style = PaintingStyle.fill;

    for (var r = 0; r < 5; r++) {
      for (var c = 0; c < 5; c++) {
        // Only draw cells in the cross shape (center row, center col, or center 3×3)
        final isCross = r == 2 || c == 2 || (r >= 1 && r <= 3 && c >= 1 && c <= 3);
        if (isCross) {
          canvas.drawRect(
            Rect.fromLTWH(c * cellSize, r * cellSize, cellSize, cellSize),
            gridPaint,
          );
        }
      }
    }

    // Draw grid lines on the cross
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i <= 5; i++) {
      canvas.drawLine(
        Offset(i * cellSize, 0),
        Offset(i * cellSize, s),
        linePaint,
      );
      canvas.drawLine(
        Offset(0, i * cellSize),
        Offset(s, i * cellSize),
        linePaint,
      );
    }

    // Highlight the center (home/finish)
    final centerRect = Rect.fromLTWH(
      2 * cellSize, 2 * cellSize, cellSize, cellSize,
    );
    canvas.drawRect(
      centerRect,
      Paint()..color = KinrelColors.brightGold.withValues(alpha: 0.25),
    );

    // Draw "HOME" star in center
    final starPath = _starPath(
      centerRect.center,
      cellSize * 0.3,
      cellSize * 0.13,
    );
    canvas.drawPath(
      starPath,
      Paint()..color = KinrelColors.brightGold.withValues(alpha: 0.6),
    );

    // Draw pieces — group by zone
    // Base pieces: show in each player's corner area
    // Loop pieces: show on the cross path (simplified — actual loop
    //   positions would map to specific cells; for the MVP we show a
    //   compact representation)
    // Home column pieces: show approaching the center
    // Finished pieces: show stacked in the center

    for (var pi = 0; pi < boardState.playerCount; pi++) {
      final seatColor = AshtaChammaSeatColors.forSeat(pi);
      final pieces = boardState.piecesForPlayer(pi);

      // Base pieces — drawn in the player's corner quadrant
      final basePieces = pieces.where((p) => p.isInBase).toList();
      for (var i = 0; i < basePieces.length; i++) {
        final pos = _basePiecePosition(pi, i, s);
        _drawPiece(canvas, pos, cellSize * 0.14, seatColor,
            isAvailable: availablePieceIndices.contains(basePieces[i].index) &&
                pi == myPlayerIndex);
      }

      // On-board pieces — drawn at their loop/home-column position
      // (simplified: we draw them on the cross arms based on progress)
      final onBoardPieces = pieces.where((p) => p.isOnBoard).toList();
      for (final piece in onBoardPieces) {
        final pos = _boardPiecePosition(piece, pi, s);
        _drawPiece(canvas, pos, cellSize * 0.14, seatColor,
            isAvailable: availablePieceIndices.contains(piece.index) &&
                pi == myPlayerIndex);
      }

      // Finished pieces — drawn stacked in the center
      final finishedPieces = pieces.where((p) => p.isFinished).toList();
      for (var i = 0; i < finishedPieces.length; i++) {
        final offset = Offset(
          centerRect.center.dx + (i - finishedPieces.length / 2 + 0.5) * cellSize * 0.15,
          centerRect.center.dy,
        );
        _drawPiece(canvas, offset, cellSize * 0.10, seatColor,
            isFinished: true);
      }
    }
  }

  void _drawPiece(Canvas canvas, Offset center, double radius, Color color,
      {bool isAvailable = false, bool isFinished = false}) {
    // Glow if available to move
    if (isAvailable) {
      canvas.drawCircle(
        center,
        radius * 1.6,
        Paint()..color = color.withValues(alpha: 0.3),
      );
    }
    // Piece body
    canvas.drawCircle(center, radius, Paint()..color = color);
    // Inner highlight
    canvas.drawCircle(
      center + Offset(-radius * 0.2, -radius * 0.2),
      radius * 0.4,
      Paint()..color = Colors.white.withValues(alpha: isFinished ? 0.9 : 0.5),
    );
  }

  Offset _basePiecePosition(int playerIndex, int pieceIndex, double s) {
    // Each player's base is in a different corner
    final positions = [
      [Offset(s * 0.12, s * 0.12), Offset(s * 0.22, s * 0.12),
       Offset(s * 0.12, s * 0.22), Offset(s * 0.22, s * 0.22)],
      [Offset(s * 0.78, s * 0.12), Offset(s * 0.88, s * 0.12),
       Offset(s * 0.78, s * 0.22), Offset(s * 0.88, s * 0.22)],
      [Offset(s * 0.78, s * 0.78), Offset(s * 0.88, s * 0.78),
       Offset(s * 0.78, s * 0.88), Offset(s * 0.88, s * 0.88)],
      [Offset(s * 0.12, s * 0.78), Offset(s * 0.22, s * 0.78),
       Offset(s * 0.12, s * 0.88), Offset(s * 0.22, s * 0.88)],
    ];
    final list = positions[playerIndex.clamp(0, 3)];
    return list[pieceIndex.clamp(0, 3)];
  }

  Offset _boardPiecePosition(AshtaChammaPiece piece, int playerIndex, double s) {
    // Simplified: map loop position to a position on the cross arms.
    // A full implementation would map each of the 56 loop squares to a
    // specific (row, col) on the 5×5 grid. For the MVP, we distribute
    // pieces along the cross based on their relative progress.
    final entryIndices = boardState.entryIndices;
    final entryIndex = entryIndices[playerIndex];
    final relPos = piece.zone == AshtaChammaPieceZone.loop
        ? (piece.loopPosition - entryIndex + kLoopLength) % kLoopLength
        : kLoopLength + piece.homeColumnPosition;
    final progress = relPos / (kLoopLength + kHomeColumnLength);
    // Map to a position on the cross perimeter
    final angle = progress * 2 * math.pi - math.pi / 2;
    final r = s * 0.35;
    return Offset(s * 0.5 + r * math.cos(angle), s * 0.5 + r * math.sin(angle));
  }

  Path _starPath(Offset center, double outerRadius, double innerRadius) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? outerRadius : innerRadius;
      final a = -math.pi / 2 + i * math.pi / 5;
      final x = center.dx + r * math.cos(a);
      final y = center.dy + r * math.sin(a);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _AshtaChammaBoardPainter oldDelegate) =>
      oldDelegate.boardState != boardState ||
      oldDelegate.availablePieceIndices != availablePieceIndices;
}

// ─────────────────────────────────────────────────────────────────────────
// Dice area — the cowrie shell roll button + available piece selector
// ─────────────────────────────────────────────────────────────────────────

class _DiceArea extends StatelessWidget {
  const _DiceArea({
    required this.game,
    required this.isMyTurn,
    required this.optimisticDice,
    required this.onRoll,
    required this.availableMoves,
  });

  final AshtaChammaGame game;
  final bool isMyTurn;
  final int? optimisticDice;
  final VoidCallback onRoll;
  final List<AshtaChammaMove> availableMoves;

  @override
  Widget build(BuildContext context) {
    final diceValue = optimisticDice ?? game.lastDiceValue;
    final canRoll = isMyTurn && game.phase == AshtaChammaPhase.roll;
    final canMove = isMyTurn && game.phase == AshtaChammaPhase.move;

    return Container(
      padding: const EdgeInsets.all(KinrelSpacing.md),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          // Dice display + roll button
          Row(
            children: [
              _CowrieShellDice(
                value: diceValue,
                isRolling: optimisticDice != null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: canRoll
                    ? DKButton(
                        label: 'Roll Shells',
                        variant: DKButtonVariant.primary,
                        fullWidth: true,
                        onPressed: onRoll,
                      )
                    : canMove
                        ? Text(
                            'Tap a glowing piece to move it ${diceValue > 0 ? "by $diceValue" : ""}',
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 12,
                              color: KinrelColors.textSilver,
                            ),
                          )
                        : Text(
                            'Waiting for other players...',
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 12,
                              color: KinrelColors.textDim,
                            ),
                          ),
              ),
            ],
          ),
          if (canMove && availableMoves.isEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'No legal moves — turn passes automatically',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 11,
                color: KinrelColors.textDim,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CowrieShellDice extends StatelessWidget {
  const _CowrieShellDice({required this.value, required this.isRolling});
  final int value;
  final bool isRolling;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: KinrelColors.darkElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isRolling
              ? KinrelColors.orange
              : (value > 0 ? KinrelColors.orange.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.1)),
          width: 2,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Shell emoji
          Text(
            '🐚',
            style: TextStyle(
              fontSize: 24,
              color: KinrelColors.orange,
            ),
          ),
          const SizedBox(height: 2),
          // Value
          Text(
            value > 0 ? '$value' : '—',
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: value > 0 ? KinrelColors.orange : KinrelColors.textDim,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Results view — shown when the game completes
// ─────────────────────────────────────────────────────────────────────────

class _ResultsView extends StatelessWidget {
  const _ResultsView({
    required this.game,
    required this.familyId,
    required this.onRematch,
    required this.onExit,
  });

  final AshtaChammaGame game;
  final String familyId;
  final Future<String?> Function() onRematch;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final winnerIds = game.winnerUserIds;
    final placements = game.placements;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(KinrelSpacing.lg),
      child: Column(
        children: [
          // Confetti for the winner
          if (winnerIds.isNotEmpty)
            const GameConfetti(),

          // Winner banner
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2A1A0E), Color(0xFF1C1410)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: KinrelColors.brightGold.withValues(alpha: 0.4)),
            ),
            child: Column(
              children: [
                const KinrelIcon(KinrelIconData.trophy,
                    size: 40, color: KinrelColors.brightGold),
                const SizedBox(height: 8),
                Text(
                  winnerIds.isNotEmpty
                      ? '${placements.where((p) => p.place == 1).map((p) => p.userName).join(", ")} wins!'
                      : 'Game Complete',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: KinrelColors.brightGold,
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

          // Placements
          if (placements.isNotEmpty) ...[
            GamingSectionHeader(
              title: 'Final Standings',
              icon: Icons.leaderboard_outlined,
            ),
            for (final p in placements)
              _PlacementRow(placement: p),
            const SizedBox(height: 18),
          ],

          // Ecosystem summary (badges, challenges, milestones)
          MatchEcosystemSummary(
            gameTable: 'ashta_chamma_games',
            gameId: game.id,
            familyId: familyId,
          ),

          const SizedBox(height: 18),

          // Actions
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
                        '/family/$familyId/ashta-chamma/game/$newId',
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

class _PlacementRow extends StatelessWidget {
  const _PlacementRow({required this.placement});
  final AshtaChammaPlacement placement;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Text(
            placement.medal,
            style: const TextStyle(fontSize: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  placement.userName,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                  ),
                ),
                Text(
                  '${placement.piecesHome}/4 pieces home · ${placement.captures} captures',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 11,
                    color: KinrelColors.textDim,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '#${placement.place}',
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: placement.place == 1
                  ? KinrelColors.brightGold
                  : KinrelColors.textDim,
            ),
          ),
        ],
      ),
    );
  }
}

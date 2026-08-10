// lib/features/games/tictactoe/tictactoe_board_screen.dart
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
import 'tictactoe_game_logic.dart';
import 'tictactoe_models.dart';
import 'tictactoe_provider.dart';

class TttBoardScreen extends ConsumerStatefulWidget {
  const TttBoardScreen({super.key, required this.familyId, required this.gameId});
  final String familyId; final String gameId;
  @override
  ConsumerState<TttBoardScreen> createState() => _TttBoardScreenState();
}

class _TttBoardScreenState extends ConsumerState<TttBoardScreen> {
  @override
  void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) { if (ref.read(tttProvider(widget.familyId)).game == null) ref.read(tttProvider(widget.familyId).notifier).loadGame(widget.gameId); }); }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tttProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;

    if (state.isCompleted) return _resultsView(state, myId);

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () { ref.read(tttProvider(widget.familyId).notifier).leaveGame(); if (context.canPop()) { context.pop(); } else { context.go('/family/${widget.familyId}'); } }),
        title: Text('Tic-Tac-Toe', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
        backgroundColor: KinrelColors.darkCard, foregroundColor: KinrelColors.textWhite, elevation: 0,
      ),
      body: state.isLoading && state.game == null ? const Center(child: CircularProgressIndicator(color: KinrelColors.orange))
        : state.game == null ? const Center(child: CircularProgressIndicator(color: KinrelColors.orange))
        : _gameView(state, myId),
    );
  }

  Widget _gameView(TttState state, String? myId) {
    final game = state.game!;
    final isMyTurn = game.isMyTurn(myId);
    final myMark = game.markForPlayer(myId);
    final opponentName = myMark == Mark.x ? game.playerOName : game.playerXName;
    final board = state.currentBoard;
    final winLine = state.winningLine;
    final roundResult = state.currentRound?.result;

    return SafeArea(child: Column(children: [
      // Score bar
      _scoreBar(game, myId),
      // Turn indicator
      _turnIndicator(game, isMyTurn, opponentName, myMark, roundResult),
      // Board
      Expanded(child: Center(child: AspectRatio(aspectRatio: 1.0, child: Padding(padding: const EdgeInsets.all(20), child: _board(state, board, winLine, isMyTurn, myMark))))),
      const SizedBox(height: KinrelSpacing.base),
    ]));
  }

  Widget _scoreBar(TttGame game, String? myId) {
    final myMark = game.markForPlayer(myId);
    final myScore = myMark == Mark.x ? game.roundsWonX : game.roundsWonO;
    final oppScore = myMark == Mark.x ? game.roundsWonO : game.roundsWonX;
    final oppName = myMark == Mark.x ? game.playerOName : game.playerXName;
    return Container(margin: const EdgeInsets.all(KinrelSpacing.base), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: KinrelColors.border)),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _scoreChip('You', myScore, KinrelColors.orange),
        Text('Round ${game.currentRound}/${game.bestOf}', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 12, color: KinrelColors.textDim, fontWeight: FontWeight.w700)),
        _scoreChip(oppName, oppScore, const Color(0xFF8B5CF6)),
      ]));
  }

  Widget _scoreChip(String name, int score, Color color) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(name, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 11, color: KinrelColors.textDim)),
      Text('$score', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 20, fontWeight: FontWeight.w800, color: color)),
    ]);
  }

  Widget _turnIndicator(TttGame game, bool isMyTurn, String opponentName, Mark? myMark, RoundResult? result) {
    String text; Color color;
    if (result != null && result != RoundResult.ongoing) {
      if (result == RoundResult.draw) { text = 'Draw!'; color = KinrelColors.warning; }
      else { final winnerMark = result == RoundResult.xWin ? Mark.x : Mark.o; final won = winnerMark == myMark; text = won ? 'You won this round!' : '${game.nameForMark(winnerMark)} won the round'; color = won ? KinrelColors.success : KinrelColors.error; }
    } else {
      text = isMyTurn ? 'Your turn' : '$opponentName\'s turn…'; color = isMyTurn ? KinrelColors.orange : KinrelColors.textDim;
    }
    return Container(margin: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10), border: Border.all(color: color, width: 1)),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (isMyTurn && result == null) const Icon(Icons.pan_tool_rounded, size: 14, color: Colors.white)
        else if (result == null) SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: color)),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600)),
      ]));
  }

  Widget _board(TttState state, List<String?> board, List<int>? winLine, bool isMyTurn, Mark? myMark) {
    return Container(
      decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(20), border: Border.all(color: KinrelColors.orange.withValues(alpha: 0.3), width: 2),
        boxShadow: [BoxShadow(color: KinrelColors.orangeGlowSubtle, blurRadius: 12)]),
      child: ClipRRect(borderRadius: BorderRadius.circular(18), child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3),
        itemCount: 9,
        itemBuilder: (context, index) => _cell(index, board, winLine, isMyTurn, myMark),
      )),
    );
  }

  Widget _cell(int index, List<String?> board, List<int>? winLine, bool isMyTurn, Mark? myMark) {
    final value = board[index];
    final isWinCell = winLine?.contains(index) ?? false;
    final canTap = value == null && isMyTurn && winLine == null;

    // Original piece design: X = orange diamond, O = purple circle
    return GestureDetector(
      onTap: canTap ? () => ref.read(tttProvider(widget.familyId).notifier).placeMark(index) : null,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: KinrelColors.border.withValues(alpha: 0.3), width: 0.5),
          color: isWinCell ? KinrelColors.success.withValues(alpha: 0.2) : (canTap ? KinrelColors.orange.withValues(alpha: 0.05) : null),
        ),
        child: Center(child: _pieceWidget(value, isWinCell)),
      ),
    );
  }

  Widget _pieceWidget(String? value, bool isWin) {
    if (value == null) return const SizedBox.shrink();
    final isX = value == 'X';
    final color = isX ? KinrelColors.orange : const Color(0xFF8B5CF6);

    // Original design: X = cross shape with two rotated bars, O = ring
    if (isX) {
      return SizedBox(width: 40, height: 40, child: Stack(alignment: Alignment.center, children: [
        Transform.rotate(angle: 0.785, child: Container(width: 36, height: 6, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3), boxShadow: isWin ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8)] : null))),
        Transform.rotate(angle: -0.785, child: Container(width: 36, height: 6, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3), boxShadow: isWin ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8)] : null))),
      ])).animate().scale(begin: const Offset(0.3, 0.3), end: const Offset(1.0, 1.0), duration: 300.ms, curve: Curves.elasticOut);
    } else {
      return Container(width: 34, height: 34,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: 5),
          boxShadow: isWin ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8)] : null),
      ).animate().scale(begin: const Offset(0.3, 0.3), end: const Offset(1.0, 1.0), duration: 300.ms, curve: Curves.elasticOut);
    }
  }

  Widget _resultsView(TttState state, String? myId) {
    final game = state.game!;
    final isWinner = game.overallWinnerId == myId;
    final winnerName = game.overallWinnerName ?? 'Player';
    return DKScaffold(
      gradient: isWinner ? KinrelGradients.deepFireGradient : null,
      backgroundColor: isWinner ? null : KinrelColors.darkSurface,
      appBar: AppBar(automaticallyImplyLeading: false,
        title: Text('Results', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
        backgroundColor: Colors.transparent, foregroundColor: KinrelColors.textWhite, elevation: 0),
      body: ListView(padding: const EdgeInsets.all(KinrelSpacing.base), children: [
        const SizedBox(height: KinrelSpacing.lg),
        Column(children: [
          Text('🏆', style: TextStyle(fontSize: 64)).animate(onPlay: (c) => c.forward()).fadeIn(duration: 500.ms).scale(begin: const Offset(0.5, 0.5), end: const Offset(1.0, 1.0), duration: 500.ms, curve: Curves.elasticOut),
          const SizedBox(height: KinrelSpacing.sm),
          Text(isWinner ? 'You Won!' : 'Winner!', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 32, fontWeight: FontWeight.w800, color: KinrelColors.textWhite, letterSpacing: 2)),
          const SizedBox(height: 4),
          Text(isWinner ? '$winnerName (You)' : winnerName, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 22, fontWeight: FontWeight.w600, color: KinrelColors.orange)),
          const SizedBox(height: KinrelSpacing.sm),
          Text('${game.roundsWonX} — ${game.roundsWonO}', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 16, color: KinrelColors.textDim)),
        ]).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.92, 0.92), end: const Offset(1.0, 1.0), duration: 400.ms, curve: Curves.easeOutBack),
        const SizedBox(height: KinrelSpacing.xxl),
        DKButton(label: 'Play Again', variant: DKButtonVariant.gradient, fullWidth: true, icon: Icons.refresh_rounded,
          onPressed: () { ref.read(tttProvider(widget.familyId).notifier).leaveGame(); if (context.mounted) context.pushReplacement('/family/${widget.familyId}/tictactoe/lobby'); }),
        const SizedBox(height: KinrelSpacing.sm),
        DKButton(label: 'Back to Hub', variant: DKButtonVariant.secondary, fullWidth: true,
          onPressed: () { ref.read(tttProvider(widget.familyId).notifier).leaveGame(); if (context.mounted) context.go('/games?familyId=${widget.familyId}'); }),
      ]),
    );
  }
}

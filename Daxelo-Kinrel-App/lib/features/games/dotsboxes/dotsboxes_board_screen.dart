// lib/features/games/dotsboxes/dotsboxes_board_screen.dart
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
import 'dotsboxes_game_logic.dart';
import 'dotsboxes_models.dart';
import 'dotsboxes_provider.dart';

class DotsboxesBoardScreen extends ConsumerStatefulWidget {
  const DotsboxesBoardScreen({super.key, required this.familyId, required this.gameId});
  final String familyId; final String gameId;
  @override
  ConsumerState<DotsboxesBoardScreen> createState() => _DotsboxesBoardScreenState();
}

class _DotsboxesBoardScreenState extends ConsumerState<DotsboxesBoardScreen> {
  @override
  void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) { if (ref.read(dbProvider(widget.familyId)).game == null) ref.read(dbProvider(widget.familyId).notifier).joinGame(widget.gameId); }); }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dbProvider(widget.familyId)); final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final game = state.game;

    if (game != null && game.isCompleted) return _resultsView(state, myId);

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () { ref.read(dbProvider(widget.familyId).notifier).leaveGame(); Navigator.of(context).pop(); }),
        title: Text('Dots & Boxes', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
        backgroundColor: KinrelColors.darkCard, foregroundColor: KinrelColors.textWhite, elevation: 0,
      ),
      body: state.isLoading && game == null ? const Center(child: CircularProgressIndicator(color: KinrelColors.orange))
        : game == null ? const Center(child: CircularProgressIndicator(color: KinrelColors.orange))
        : SafeArea(child: Column(children: [
          _scoreBar(state, myId),
          _turnIndicator(game, state, myId),
          Expanded(child: Center(child: Padding(padding: const EdgeInsets.all(8), child: _board(state, game, myId)))),
        ])),
    );
  }

  Widget _scoreBar(DbState state, String? myId) {
    final colors = [KinrelColors.orange, KinrelColors.blue, KinrelColors.tealAccent, KinrelColors.gold];
    return Container(margin: const EdgeInsets.all(KinrelSpacing.base), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: KinrelColors.border)),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: state.players.map((p) {
        final color = colors[p.playerColor % 4];
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: color)), const SizedBox(width: 4),
            Text(p.userId == myId ? 'You' : p.userName.split(' ').first, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 10, color: KinrelColors.textDim))]),
          Text('${p.boxesCaptured}', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 18, fontWeight: FontWeight.w800, color: color)),
        ]);
      }).toList()));
  }

  Widget _turnIndicator(DbGame game, DbState state, String? myId) {
    final isMyTurn = game.currentTurnPlayerId == myId;
    final currentPlayer = state.players.where((p) => p.userId == game.currentTurnPlayerId).firstOrNull;
    final colors = [KinrelColors.orange, KinrelColors.blue, KinrelColors.tealAccent, KinrelColors.gold];
    final turnColor = currentPlayer != null ? colors[currentPlayer.playerColor % 4] : KinrelColors.orange;
    return Container(margin: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: turnColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10), border: Border.all(color: turnColor, width: 1)),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (isMyTurn) const Icon(Icons.pan_tool_rounded, size: 14, color: Colors.white)
        else SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: turnColor)),
        const SizedBox(width: 6),
        Text(isMyTurn ? (game.bonusTurn ? 'Bonus turn — draw again!' : 'Your turn — draw a line!') : '${currentPlayer?.userName ?? 'Player'}\'s turn…',
          style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600)),
      ]));
  }

  Widget _board(DbState state, DbGame game, String? myId) {
    final gridSize = game.gridSize;
    final dotsCount = gridSize + 1;
    final drawnLines = state.drawnLineKeys;
    final isMyTurn = game.currentTurnPlayerId == myId;

    return LayoutBuilder(builder: (context, constraints) {
      final maxW = constraints.maxWidth;
      final cellSize = maxW / dotsCount;
      final dotRadius = cellSize * 0.08;

      return Stack(children: [
        // Grid: draw dots, lines, boxes
        CustomPaint(size: Size(maxW, maxW), painter: _DotsBoardPainter(
          dotsCount: dotsCount, cellSize: cellSize, dotRadius: dotRadius,
          drawnLines: drawnLines, boxes: state.boxes, players: state.players,
          lastCapture: state.lastCapture,
        )),
        // Tappable line areas
        ..._buildTappableAreas(state, game, myId, cellSize, dotsCount, isMyTurn),
      ]);
    });
  }

  List<Widget> _buildTappableAreas(DbState state, DbGame game, String? myId, double cellSize, int dotsCount, bool isMyTurn) {
    final areas = <Widget>[];
    final drawn = state.drawnLineKeys;
    final gridSize = game.gridSize;

    // Horizontal lines
    for (int r = 0; r <= gridSize; r++) {
      for (int c = 0; c < gridSize; c++) {
        final line = DotsLine(type: LineType.horizontal, row: r, col: c);
        if (drawn.contains(line.key)) continue;
        areas.add(Positioned(
          left: c * cellSize, top: r * cellSize - cellSize * 0.15,
          width: cellSize, height: cellSize * 0.3,
          child: GestureDetector(onTap: isMyTurn ? () => ref.read(dbProvider(widget.familyId).notifier).drawLine(LineType.horizontal, r, c) : null,
            child: Container(color: Colors.transparent))),
        );
      }
    }
    // Vertical lines
    for (int r = 0; r < gridSize; r++) {
      for (int c = 0; c <= gridSize; c++) {
        final line = DotsLine(type: LineType.vertical, row: r, col: c);
        if (drawn.contains(line.key)) continue;
        areas.add(Positioned(
          left: c * cellSize - cellSize * 0.15, top: r * cellSize,
          width: cellSize * 0.3, height: cellSize,
          child: GestureDetector(onTap: isMyTurn ? () => ref.read(dbProvider(widget.familyId).notifier).drawLine(LineType.vertical, r, c) : null,
            child: Container(color: Colors.transparent))),
        );
      }
    }
    return areas;
  }

  Widget _resultsView(DbState state, String? myId) {
    final game = state.game!; final winners = game.winnerUserIds ?? []; final winnerNames = game.winnerNames ?? [];
    final isMyWin = winners.contains(myId); final sorted = List<DbPlayer>.from(state.players)..sort((a, b) => b.boxesCaptured.compareTo(a.boxesCaptured));
    final colors = [KinrelColors.orange, KinrelColors.blue, KinrelColors.tealAccent, KinrelColors.gold];
    return DKScaffold(
      gradient: isMyWin ? KinrelGradients.deepFireGradient : null,
      backgroundColor: isMyWin ? null : KinrelColors.darkSurface,
      appBar: AppBar(automaticallyImplyLeading: false,
        title: Text('Results', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
        backgroundColor: Colors.transparent, foregroundColor: KinrelColors.textWhite, elevation: 0),
      body: ListView(padding: const EdgeInsets.all(KinrelSpacing.base), children: [
        const SizedBox(height: KinrelSpacing.lg),
        Column(children: [
          Text('🏆', style: TextStyle(fontSize: 64)).animate(onPlay: (c) => c.forward()).fadeIn(duration: 500.ms).scale(begin: const Offset(0.5, 0.5), end: const Offset(1.0, 1.0), duration: 500.ms, curve: Curves.elasticOut),
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
          final rank = entry.key + 1; final p = entry.value; final color = colors[p.playerColor % 4];
          final medal = rank == 1 ? '🥇' : rank == 2 ? '🥈' : rank == 3 ? '🥉' : '$rank';
          return Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.userId == myId ? KinrelColors.orange : KinrelColors.border, width: p.userId == myId ? 2 : 1)),
            child: Row(children: [SizedBox(width: 28, child: Text(medal, style: TextStyle(fontSize: 16))),
              Container(width: 16, height: 16, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
              const SizedBox(width: 8),
              Expanded(child: Text(p.userId == myId ? '${p.userName} (You)' : p.userName, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, fontWeight: FontWeight.w600, color: KinrelColors.textWhite))),
              Text('${p.boxesCaptured} boxes', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 14, fontWeight: FontWeight.w800, color: color))]));
        }),
        const SizedBox(height: KinrelSpacing.xxl),
        DKButton(label: 'Play Again', variant: DKButtonVariant.gradient, fullWidth: true, icon: Icons.refresh_rounded,
          onPressed: () { ref.read(dbProvider(widget.familyId).notifier).leaveGame(); if (context.mounted) context.pushReplacement('/family/${widget.familyId}/dotsboxes/lobby'); }),
        const SizedBox(height: 8),
        DKButton(label: 'Back to Hub', variant: DKButtonVariant.secondary, fullWidth: true,
          onPressed: () { ref.read(dbProvider(widget.familyId).notifier).leaveGame(); if (context.mounted) context.go('/games?familyId=${widget.familyId}'); }),
      ]),
    );
  }
}

class _DotsBoardPainter extends CustomPainter {
  _DotsBoardPainter({required this.dotsCount, required this.cellSize, required this.dotRadius, required this.drawnLines, required this.boxes, required this.players, this.lastCapture});
  final int dotsCount; final double cellSize; final double dotRadius;
  final Set<String> drawnLines; final List<DbBoxRecord> boxes; final List<DbPlayer> players; final List<(int,int)>? lastCapture;

  @override
  void paint(Canvas canvas, Size size) {
    final colors = [const Color(0xFFE8612A), const Color(0xFF3B82F6), const Color(0xFF2DD4BF), const Color(0xFFD4AF37)];
    final dotPaint = Paint()..color = const Color(0xFFC9B4A8)..style = PaintingStyle.fill;
    final linePaint = Paint()..color = const Color(0xFFF5F0EE)..strokeWidth = 3..strokeCap = StrokeCap.round;

    // Draw captured boxes
    for (final box in boxes) {
      if (!box.isCaptured) continue;
      final player = players.where((p) => p.userId == box.capturedByPlayerId).firstOrNull;
      final color = player != null ? colors[player.playerColor % 4] : KinrelColors.orange;
      final paint = Paint()..color = color.withValues(alpha: 0.25);
      canvas.drawRect(Rect.fromLTWH(box.boxCol * cellSize, box.boxRow * cellSize, cellSize, cellSize), paint);
      // Draw initial
      final tp = TextPainter(text: TextSpan(text: (player?.userName.isNotEmpty == true ? player!.userName[0] : '?'), style: TextStyle(color: color, fontSize: cellSize * 0.4, fontWeight: FontWeight.w800)), textDirection: TextDirection.ltr);
      tp.layout(); tp.paint(canvas, Offset(box.boxCol * cellSize + (cellSize - tp.width) / 2, box.boxRow * cellSize + (cellSize - tp.height) / 2));
    }

    // Draw lines
    for (final key in drawnLines) {
      final parts = key.split('_');
      final type = parts[0] == 'horizontal' ? LineType.horizontal : LineType.vertical;
      final row = int.parse(parts[1]); final col = int.parse(parts[2]);
      if (type == LineType.horizontal) {
        canvas.drawLine(Offset(col * cellSize, row * cellSize), Offset((col + 1) * cellSize, row * cellSize), linePaint);
      } else {
        canvas.drawLine(Offset(col * cellSize, row * cellSize), Offset(col * cellSize, (row + 1) * cellSize), linePaint);
      }
    }

    // Draw dots
    for (int r = 0; r < dotsCount; r++) {
      for (int c = 0; c < dotsCount; c++) {
        canvas.drawCircle(Offset(c * cellSize, r * cellSize), dotRadius, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotsBoardPainter oldDelegate) => true;
}

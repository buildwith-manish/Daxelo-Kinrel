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
import '../shared/widgets/leave_game_dialog.dart';
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
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () async {
            final state = ref.read(dbProvider(widget.familyId));
            final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
            final shouldLeave = await LeaveGameDialog.show(
              context,
              isHost: (state.game?.hostUserId == myId),
              gameName: 'Dots & Boxes',
            );
            if (shouldLeave != true) return;
            if (!context.mounted) return;
            ref.read(dbProvider(widget.familyId).notifier).leaveGame();
            if (state.game?.id != null) {
              ref.read(temporaryRoomServiceProvider).endGame(
                    gameTable: 'dotsboxes_games',
                    gameId: state.game!.id,
                  );
            }
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/family/${widget.familyId}');
            }
          },
        ),
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

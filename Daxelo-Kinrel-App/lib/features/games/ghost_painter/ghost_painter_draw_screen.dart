// lib/features/games/ghost_painter/ghost_painter_draw_screen.dart

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/services/supabase_service.dart';
import '../game_motion_tokens.dart';
import 'ghost_painter_models.dart';
import 'ghost_painter_provider.dart';

class GhostPainterDrawScreen extends ConsumerStatefulWidget {
  const GhostPainterDrawScreen({super.key, required this.familyId});
  final String familyId;
  @override
  ConsumerState<GhostPainterDrawScreen> createState() => _GhostPainterDrawScreenState();
}

class _GhostPainterDrawScreenState extends ConsumerState<GhostPainterDrawScreen> {
  final List<Offset> _currentStroke = [];
  final List<List<Offset>> _allStrokes = [];
  int _strokeSequence = 0;
  bool _roundStarted = false;

  String? get _myId => ref.read(supabaseProvider)?.auth.currentUser?.id;
  String get _myName => ref.read(supabaseProvider)?.auth.currentUser?.userMetadata?['name'] as String? ?? 'Member';

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(ghostPainterProvider(widget.familyId).notifier).load());
  }

  Future<void> _startRound() async {
    final myId = _myId;
    if (myId == null) return;
    final success = await ref.read(ghostPainterProvider(widget.familyId).notifier).startRound(myId, _myName);
    if (success && mounted) setState(() => _roundStarted = true);
  }

  Future<void> _doneDrawing() async {
    GameMotionTokens.tap();
    await ref.read(ghostPainterProvider(widget.familyId).notifier).transitionToGuessing();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ghostPainterProvider(widget.familyId));
    final round = state.activeRound;

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () async {
          await ref.read(ghostPainterProvider(widget.familyId).notifier).endRound();
          if (context.mounted) Navigator.of(context).pop();
        }),
        title: Text('Ghost Painter', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFF1A1A2E), foregroundColor: Colors.white, elevation: 0,
        actions: [
          if (round != null && round.status == 'drawing')
            TextButton(
              onPressed: _doneDrawing,
              child: Text('Done', style: TextStyle(color: const Color(0xFFEC4899), fontWeight: FontWeight.w700, fontSize: 16)),
            ),
        ],
      ),
      body: round == null || !round.isActive
        ? _buildStartScreen()
        : round.status == 'drawing'
          ? _buildDrawCanvas(state, round)
          : _buildWaitingForGuesses(state, round),
    );
  }

  Widget _buildStartScreen() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.brush_outlined, size: 56, color: const Color(0xFFEC4899).withValues(alpha: 0.5)),
      const SizedBox(height: 16),
      Text('Start Drawing', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
      const SizedBox(height: 8),
      Text('Draw a word and let your family guess!', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, color: KinrelColors.textDim)),
      const SizedBox(height: 24),
      FilledButton.icon(onPressed: _startRound, icon: Icon(Icons.play_arrow), label: Text('Start Round'),
        style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEC4899), padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14))),
    ]));
  }

  Widget _buildDrawCanvas(state, round) {
    final remaining = ref.read(ghostPainterProvider(widget.familyId).notifier).remainingSeconds;
    final totalDuration = round.endsAt != null
        ? round.endsAt!.difference(round.startedAt).inSeconds
        : 90;
    final progress = totalDuration > 0 ? remaining / totalDuration : 0.0;

    return Column(children: [
      // Top bar: prompt chip + countdown ring
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Row(children: [
        // Prompt word chip
        Expanded(child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(color: const Color(0xFFEC4899).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFEC4899).withValues(alpha: 0.4))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.visibility_off_outlined, size: 16, color: const Color(0xFFEC4899)),
            const SizedBox(width: 8),
            Flexible(child: Text('Draw: ${round.promptWord}', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white), overflow: TextOverflow.ellipsis)),
          ]))),
        const SizedBox(width: 12),
        // Countdown ring
        _CountdownRing(remaining: remaining, progress: progress),
      ])),
      // Canvas
      Expanded(child: GestureDetector(
        onPanStart: (_) { _currentStroke.clear(); },
        onPanUpdate: (details) { setState(() { _currentStroke.add(details.localPosition); }); },
        onPanEnd: (_) {
          if (_currentStroke.isNotEmpty) {
            _allStrokes.add(List.from(_currentStroke));
            final points = _currentStroke.map((p) => OffsetPoint(x: p.dx, y: p.dy)).toList();
            ref.read(ghostPainterProvider(widget.familyId).notifier).queueStroke(points, _strokeSequence++);
            GameMotionTokens.tap();
            _currentStroke.clear();
          }
        },
        child: CustomPaint(painter: _DrawPainter(strokes: _allStrokes, currentStroke: _currentStroke), size: Size.infinite),
      )),
      // "I'm Done Drawing" button
      Padding(padding: const EdgeInsets.all(16), child: SizedBox(width: double.infinity,
        child: FilledButton.icon(
          onPressed: _doneDrawing,
          icon: Icon(Icons.check_rounded),
          label: Text('I\'m Done Drawing', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEC4899), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        ))),
      // Guesses live feed
      if (state.guesses.isNotEmpty)
        Container(height: 50, padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ListView(scrollDirection: Axis.horizontal, children: state.guesses.map((g) =>
            Container(margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: g.isCorrect ? KinrelColors.success.withValues(alpha: 0.15) : KinrelColors.darkCard, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Text(g.userName, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: g.isCorrect ? KinrelColors.success : Colors.white70)),
                const SizedBox(width: 6),
                Text(g.guessText, style: TextStyle(fontSize: 12, color: g.isCorrect ? KinrelColors.success : Colors.white54)),
              ]))).toList())),
    ]);
  }

  Widget _buildWaitingForGuesses(state, round) {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.hourglass_top_rounded, size: 48, color: const Color(0xFFEC4899).withValues(alpha: 0.5)),
      const SizedBox(height: 16),
      Text('Waiting for guesses...', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
      const SizedBox(height: 8),
      Text('The word was: ${round.promptWord}', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, color: KinrelColors.textDim)),
      const SizedBox(height: 16),
      if (state.guesses.isEmpty)
        Text('No guesses yet', style: TextStyle(fontSize: 14, color: KinrelColors.textDim))
      else ...[
        Text('${state.guesses.length} ${state.guesses.length == 1 ? "guess" : "guesses"}', style: TextStyle(fontSize: 14, color: const Color(0xFFEC4899), fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        ...state.guesses.map((g) => Padding(padding: const EdgeInsets.only(bottom: 4),
          child: Text('${g.userName}: ${g.guessText} ${g.isCorrect ? "✓" : ""}', style: TextStyle(fontSize: 14, color: g.isCorrect ? KinrelColors.success : Colors.white54)))),
      ],
    ]));
  }
}

/// Animated circular countdown ring with number in center.
class _CountdownRing extends StatelessWidget {
  const _CountdownRing({required this.remaining, required this.progress});
  final int remaining;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final color = remaining <= 10 ? Colors.red : const Color(0xFFEC4899);
    return SizedBox(width: 44, height: 44, child: Stack(alignment: Alignment.center, children: [
      CircularProgressIndicator(
        value: progress,
        strokeWidth: 3,
        backgroundColor: Colors.white.withValues(alpha: 0.1),
        valueColor: AlwaysStoppedAnimation(color),
      ),
      Text('$remaining', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
    ]));
  }
}

class _DrawPainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final List<Offset> currentStroke;
  _DrawPainter({required this.strokes, required this.currentStroke});

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        colors: [const Color(0xFF1A1A2E), const Color(0xFF0D0D1A)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final strokePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);

    for (final stroke in strokes) {
      _drawStroke(canvas, stroke, strokePaint);
    }
    if (currentStroke.isNotEmpty) _drawStroke(canvas, currentStroke, strokePaint);
  }

  void _drawStroke(Canvas canvas, List<Offset> points, Paint paint) {
    if (points.length < 2) {
      if (points.length == 1) canvas.drawPoints(ui.PointMode.points, points, paint);
      return;
    }
    canvas.drawPath(Path()..addPolygon(points, false), paint);
  }

  @override
  bool shouldRepaint(covariant _DrawPainter old) => true;
}

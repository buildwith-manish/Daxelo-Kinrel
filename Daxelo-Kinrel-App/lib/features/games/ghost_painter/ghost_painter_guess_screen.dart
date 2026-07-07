// lib/features/games/ghost_painter/ghost_painter_guess_screen.dart

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../game_motion_tokens.dart';
import 'ghost_painter_models.dart';
import 'ghost_painter_provider.dart';

class GhostPainterGuessScreen extends ConsumerStatefulWidget {
  const GhostPainterGuessScreen({super.key, required this.familyId});
  final String familyId;
  @override
  ConsumerState<GhostPainterGuessScreen> createState() => _GhostPainterGuessScreenState();
}

class _GhostPainterGuessScreenState extends ConsumerState<GhostPainterGuessScreen> {
  final _guessController = TextEditingController();
  bool _shake = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(ghostPainterProvider(widget.familyId).notifier).load());
  }

  @override
  void dispose() { _guessController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ghostPainterProvider(widget.familyId));
    final round = state.activeRound;

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).pop()),
        title: Text('Ghost Painter', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFF1A1A2E), foregroundColor: Colors.white, elevation: 0,
      ),
      body: round == null
        ? Center(child: Text('No active round', style: TextStyle(color: KinrelColors.textDim)))
        : round.isCompleted
          ? _buildRoundComplete(state, round)
          : _buildGuessView(state, round),
    );
  }

  Widget _buildGuessView(state, round) {
    return Column(children: [
      // Drawer info
      Padding(padding: const EdgeInsets.all(16), child: Row(children: [
        Icon(Icons.brush_outlined, size: 18, color: const Color(0xFFEC4899)),
        const SizedBox(width: 8),
        Text('${round.drawerPersonName} is drawing...', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
        const Spacer(),
        // Live guessing count
        Text('${state.guesses.length} guessing', style: TextStyle(fontSize: 12, color: KinrelColors.textDim)),
      ])),
      // Canvas showing live strokes
      Expanded(child: CustomPaint(painter: _GuessPainter(strokes: state.strokes), size: Size.infinite)),
      // Guesses feed
      if (state.guesses.isNotEmpty)
        Container(height: 50, padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ListView(scrollDirection: Axis.horizontal, children: state.guesses.map((g) =>
            Container(margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: g.isCorrect ? KinrelColors.success.withValues(alpha: 0.15) : KinrelColors.darkCard, borderRadius: BorderRadius.circular(10)),
              child: Text('${g.userName}: ${g.guessText}', style: TextStyle(fontSize: 12, color: g.isCorrect ? KinrelColors.success : Colors.white54)))).toList())),
      // Guess input
      if (!state.hasGuessed)
        Padding(padding: const EdgeInsets.all(16), child: AnimatedContainer(
          duration: GameMotionTokens.fast,
          transform: _shake ? (Matrix4.identity()..translate(10.0)) : Matrix4.identity(),
          child: TextField(controller: _guessController, style: TextStyle(color: Colors.white, fontSize: 16),
            decoration: InputDecoration(hintText: 'Type your guess...', hintStyle: TextStyle(color: KinrelColors.textDim),
              filled: true, fillColor: KinrelColors.darkElevated, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              suffixIcon: IconButton(icon: Icon(Icons.send, color: const Color(0xFFEC4899)), onPressed: () => _submitGuess())),
            onSubmitted: (_) => _submitGuess()),
        )),
      if (state.hasGuessed && !state.myGuess!.isCorrect)
        Padding(padding: const EdgeInsets.all(16), child: Text('Wrong! Keep trying...', style: TextStyle(color: KinrelColors.textDim, fontSize: 14))),
    ]);
  }

  Future<void> _submitGuess() async {
    final text = _guessController.text.trim();
    if (text.isEmpty) return;
    final wasCorrect = await ref.read(ghostPainterProvider(widget.familyId).notifier).submitGuess(text);
    if (wasCorrect) {
      GameMotionTokens.celebrate();
    } else {
      GameMotionTokens.error();
      setState(() { _shake = true; });
      Future.delayed(const Duration(milliseconds: 300), () => setState(() => _shake = false));
    }
    _guessController.clear();
  }

  Widget _buildRoundComplete(state, round) {
    final correctGuessers = state.guesses.where((g) => g.isCorrect).toList();
    return Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.celebration_rounded, size: 48, color: const Color(0xFFEC4899)),
      const SizedBox(height: 16),
      Text('Round Complete!', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
      const SizedBox(height: 8),
      Text('The word was: ${round.promptWord}', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 16, color: const Color(0xFFEC4899), fontWeight: FontWeight.w600)),
      const SizedBox(height: 16),
      if (correctGuessers.isNotEmpty) ...[
        Text('Correct Guessers:', style: TextStyle(fontSize: 14, color: KinrelColors.textDim)),
        const SizedBox(height: 8),
        ...correctGuessers.map((g) => Padding(padding: const EdgeInsets.only(bottom: 4),
          child: Text(g.userName, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: KinrelColors.success)))),
      ] else
        Text('Nobody guessed it!', style: TextStyle(fontSize: 14, color: KinrelColors.textDim)),
    ])));
  }
}

class _GuessPainter extends CustomPainter {
  final List<GhostPainterStroke> strokes;
  _GuessPainter({required this.strokes});

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFF1A1A2E);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);

    for (final stroke in strokes) {
      final points = stroke.points.map((p) => Offset(p.x, p.y)).toList();
      if (points.length >= 2) {
        canvas.drawPath(Path()..addPolygon(points, false), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GuessPainter old) => true;
}

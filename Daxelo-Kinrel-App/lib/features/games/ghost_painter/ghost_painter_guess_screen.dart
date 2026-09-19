// lib/features/games/ghost_painter/ghost_painter_guess_screen.dart
//
// Ghost Painter — the guesser's gallery:
//   • Drawer medallion + live guess tally
//   • Neon canvas mirroring the drawer's strokes in realtime
//   • Glass guess field with glowing send button + shake on miss
//   • Round complete: confetti, word reveal card, winner chips,
//     ecosystem rewards banner + sportsmanship

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../gaming_ecosystem/presentation/match_ecosystem_summary.dart';
import '../game_motion_tokens.dart';
import '../shared/widgets/game_confetti.dart';
import 'ghost_painter_canvas.dart';
import 'ghost_painter_models.dart';
import 'ghost_painter_provider.dart';

class GhostPainterGuessScreen extends ConsumerStatefulWidget {
  const GhostPainterGuessScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<GhostPainterGuessScreen> createState() =>
      _GhostPainterGuessScreenState();
}

class _GhostPainterGuessScreenState
    extends ConsumerState<GhostPainterGuessScreen> {
  final _guessController = TextEditingController();
  final _focusNode = FocusNode();
  bool _shake = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(ghostPainterProvider(widget.familyId).notifier).load(),
    );
    _focusNode.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _guessController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ghostPainterProvider(widget.familyId));
    final round = state.activeRound;

    return Scaffold(
      backgroundColor: const Color(0xFF12122A),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/family/${widget.familyId}');
            }
          },
        ),
        title: Text(
          'Ghost Painter',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: const Color(0xFF12122A),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: round == null
          ? Center(
              child: Text(
                'No active round',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  color: KinrelColors.textDim,
                ),
              ),
            )
          : round.isCompleted
          ? _buildRoundComplete(state, round)
          : _buildGuessView(state, round),
    );
  }

  // ── Live guessing ────────────────────────────────────────────────

  Widget _buildGuessView(GhostPainterState state, GhostPainterRound round) {
    return Column(
      children: [
        // Drawer medallion + tally.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: GhostGlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                GhostMedallion(emoji: '🖌️', size: 38),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${round.drawerPersonName} is drawing…',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Watch the glowing ink and name it first!',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 11,
                          color: KinrelColors.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: kGhostAccent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: kGhostAccent.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    '${state.guesses.length}',
                    style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: kGhostAccent,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Neon canvas mirroring the drawer.
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: GhostPainterCanvas(
                strokes: state.strokes
                    .map((s) => s.points.map((p) => Offset(p.x, p.y)).toList())
                    .toList(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Guess feed.
        if (state.guesses.isNotEmpty)
          Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: state.guesses
                  .map<GhostGuessBubble>(
                    (g) => GhostGuessBubble(
                      userName: g.userName,
                      guessText: g.guessText,
                      isCorrect: g.isCorrect,
                    ),
                  )
                  .toList(),
            ),
          ),
        // Guess input — stays available until the LATEST guess is
        // correct (a wrong guess must never lock the guesser out).
        if (state.myGuess?.isCorrect != true)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: AnimatedContainer(
              duration: GameMotionTokens.fast,
              transform: _shake
                  ? (Matrix4.identity()..translateByDouble(10.0, 0.0, 0.0, 1.0))
                  : Matrix4.identity(),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: (_focusNode.hasFocus ? kGhostAccent : Colors.black)
                          .withValues(alpha: 0.30),
                      blurRadius: 16,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _guessController,
                  focusNode: _focusNode,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Type your guess…',
                    hintStyle: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      color: KinrelColors.textDim,
                    ),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: _focusNode.hasFocus
                            ? kGhostAccent.withValues(alpha: 0.65)
                            : Colors.white.withValues(alpha: 0.10),
                        width: 1.4,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.10),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: kGhostAccent.withValues(alpha: 0.75),
                        width: 1.6,
                      ),
                    ),
                    suffixIcon: Container(
                      margin: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFEC4899), Color(0xFFB14DB8)],
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(
                          Icons.send_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                        onPressed: () => _submitGuess(),
                      ),
                    ),
                  ),
                  onSubmitted: (_) => _submitGuess(),
                ),
              ),
            ),
          ),
        if (state.myGuess?.isCorrect == false)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.close_rounded, size: 14, color: KinrelColors.error),
                const SizedBox(width: 6),
                Text(
                  'Not it — keep watching the ink and try again!',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    color: KinrelColors.textDim,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _submitGuess() async {
    final text = _guessController.text.trim();
    if (text.isEmpty) return;
    final wasCorrect = await ref
        .read(ghostPainterProvider(widget.familyId).notifier)
        .submitGuess(text);
    if (wasCorrect) {
      GameMotionTokens.celebrate();
    } else {
      GameMotionTokens.error();
      setState(() {
        _shake = true;
      });
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(() {
            _shake = false;
          });
        }
      });
    }
    _guessController.clear();
  }

  // ── Round complete ───────────────────────────────────────────────

  Widget _buildRoundComplete(GhostPainterState state, GhostPainterRound round) {
    final correctGuessers = state.guesses.where((g) => g.isCorrect).toList();
    final iWon = state.myGuess?.isCorrect ?? false;
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          children: [
            Center(
              child: GhostMedallion(
                emoji: iWon ? '🎉' : '🎨',
                size: 84,
                accent: iWon ? KinrelColors.success : kGhostAccent,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              iWon ? 'You Guessed It!' : 'Round Complete!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 14),
            GhostGlassCard(
              child: Column(
                children: [
                  Text(
                    'THE WORD WAS',
                    style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 9,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w800,
                      color: kGhostAccent,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    round.promptWord,
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: kGhostAccent,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (correctGuessers.isNotEmpty) ...[
              Text(
                'SHARPEST EYES',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 9,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w800,
                  color: KinrelColors.success,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < correctGuessers.length; i++)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: KinrelColors.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: KinrelColors.success.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            i == 0
                                ? '🥇'
                                : i == 1
                                ? '🥈'
                                : i == 2
                                ? '🥉'
                                : '✨',
                            style: const TextStyle(fontSize: 14),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            correctGuessers[i].userName,
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: KinrelColors.success,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ] else
              GhostGlassCard(
                accent: KinrelColors.amber,
                child: Text(
                  'Nobody guessed it this time — the ghost keeps its secret! 🤫',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    height: 1.4,
                    color: KinrelColors.textSilver,
                  ),
                ),
              ),
            // ── Family Gaming Ecosystem: rewards + sportsmanship ──
            MatchEcosystemSummary(
              gameTable: 'ghost_painter_rounds',
              gameId: round.id,
              familyId: widget.familyId,
              padding: const EdgeInsets.only(top: 24),
            ),
            const SizedBox(height: 24),
          ],
        ),
        if (correctGuessers.isNotEmpty)
          GameConfetti(
            colors: [
              kGhostAccent,
              const Color(0xFFB14DB8),
              KinrelColors.success,
              const Color(0xFFFDF4FF),
            ],
          ),
      ],
    );
  }
}

// lib/features/games/ghost_painter/ghost_painter_draw_screen.dart
//
// Ghost Painter — the drawer's studio:
//   • Start: floating ghost medallion + glowing CTA
//   • Draw: neon canvas (GhostPainterCanvas), glass prompt chip,
//     glowing countdown ring, live guess bubbles, gradient Done CTA
//   • Guessing: word reveal card + live guess tally
//   • Complete: confetti, word card, correct-guesser podium chips,
//     ecosystem rewards banner + sportsmanship

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/services/supabase_service.dart';
import '../../gaming_ecosystem/presentation/match_ecosystem_summary.dart';
import '../game_motion_tokens.dart';
import '../shared/models/game_invite.dart';
import '../shared/widgets/game_confetti.dart';
import '../shared/widgets/rematch_button.dart';
import 'ghost_painter_canvas.dart';
import 'ghost_painter_models.dart';
import 'ghost_painter_provider.dart';

class GhostPainterDrawScreen extends ConsumerStatefulWidget {
  const GhostPainterDrawScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<GhostPainterDrawScreen> createState() =>
      _GhostPainterDrawScreenState();
}

class _GhostPainterDrawScreenState
    extends ConsumerState<GhostPainterDrawScreen> {
  final List<Offset> _currentStroke = [];
  final List<List<Offset>> _allStrokes = [];
  int _strokeSequence = 0;
  bool _bouncedToGuess = false;

  String? get _myId => ref.read(supabaseProvider)?.auth.currentUser?.id;
  String get _myName =>
      ref.read(supabaseProvider)?.auth.currentUser?.userMetadata?['name']
          as String? ??
      'Member';

  @override
  void initState() {
    super.initState();
    // Seed previously-drawn strokes after a mid-round reload so the
    // drawer still sees their earlier ink (one-time — local drawing
    // appends on top; realtime echoes of our own strokes stay in
    // provider state and are never re-seeded).
    ref.listenManual(ghostPainterProvider(widget.familyId), (prev, next) {
      if (_allStrokes.isEmpty && next.strokes.isNotEmpty) {
        setState(() {
          _allStrokes.addAll(
            next.strokes
                .map((s) => s.points.map((p) => Offset(p.x, p.y)).toList()),
          );
        });
      }
    }, fireImmediately: true);
    Future.microtask(
      () => ref.read(ghostPainterProvider(widget.familyId).notifier).load(),
    );
  }

  Future<void> _startRound() async {
    GameMotionTokens.tap();
    final myId = _myId;
    if (myId == null) return;
    // Round state flows in via realtime — no local flag needed.
    await ref
        .read(ghostPainterProvider(widget.familyId).notifier)
        .startRound(myId, _myName);
  }

  Future<void> _doneDrawing() async {
    GameMotionTokens.tap();
    await ref
        .read(ghostPainterProvider(widget.familyId).notifier)
        .transitionToGuessing();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ghostPainterProvider(widget.familyId));
    final round = state.activeRound;

    // The studio is drawer-only: while a round is live, anyone who is
    // NOT the drawer gets bounced to the guess gallery — the canvas and
    // the secret word must never render for guessers.
    final myId = _myId;
    if (round != null && round.isActive && myId != null && round.drawerPersonId != myId) {
      if (!_bouncedToGuess) {
        _bouncedToGuess = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.pushReplacement('/family/${widget.familyId}/ghost-painter/guess');
        });
      }
      return const Scaffold(backgroundColor: Color(0xFF12122A));
    }

    return Scaffold(
      backgroundColor: const Color(0xFF12122A),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () async {
            // Only abandon the round if it is still live — a completed
            // round is already archived by the ecosystem trigger.
            final round = ref
                .read(ghostPainterProvider(widget.familyId))
                .activeRound;
            if (round != null && round.isActive) {
              await ref
                  .read(ghostPainterProvider(widget.familyId).notifier)
                  .endRound();
            }
            if (context.mounted) Navigator.of(context).pop();
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
        actions: [
          if (round != null && round.status == 'drawing')
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: TextButton(
                onPressed: _doneDrawing,
                child: Text(
                  'Done',
                  style: TextStyle(
                    color: kGhostAccent,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: round == null
          ? _buildStartScreen()
          : round.status == 'drawing'
          ? _buildDrawCanvas(state, round)
          : round.status == 'guessing'
          ? _buildWaitingForGuesses(state, round)
          : _buildRoundComplete(state, round),
    );
  }

  // ── Start ────────────────────────────────────────────────────────

  Widget _buildStartScreen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GhostMedallion(emoji: '👻', size: 108)
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .moveY(begin: -8, end: 8, duration: 2000.ms)
                .fadeIn(duration: 600.ms),
            const SizedBox(height: 24),
            Text(
              'Start Drawing',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Draw a secret word in glowing ink while your\nfamily races to guess it!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                height: 1.5,
                color: KinrelColors.textDim,
              ),
            ),
            const SizedBox(height: 32),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFEC4899), Color(0xFFB14DB8)],
                ),
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: kGhostAccent.withValues(alpha: 0.45),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: FilledButton.icon(
                onPressed: _startRound,
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(
                  'Start Round',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Live drawing ─────────────────────────────────────────────────

  Widget _buildDrawCanvas(GhostPainterState state, GhostPainterRound round) {
    final remaining = ref
        .read(ghostPainterProvider(widget.familyId).notifier)
        .remainingSeconds;
    final totalDuration = round.endsAt != null
        ? round.endsAt!.difference(round.startedAt).inSeconds
        : 90;
    final progress = totalDuration > 0
        ? (remaining / totalDuration).clamp(0.0, 1.0)
        : 0.0;

    return Column(
      children: [
        // Top bar: glass prompt chip + countdown ring.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: GhostGlassCard(
                  accent: kGhostAccent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.visibility_off_outlined,
                        size: 17,
                        color: kGhostAccent,
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          'Draw: ${round.promptWord}',
                          style: TextStyle(
                            fontFamily: KinrelTypography.displayFont,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.3,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _CountdownRing(remaining: remaining, progress: progress),
            ],
          ),
        ),
        // Neon canvas.
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: GestureDetector(
                onPanStart: (_) {
                  _currentStroke.clear();
                },
                onPanUpdate: (details) {
                  setState(() {
                    _currentStroke.add(details.localPosition);
                  });
                },
                onPanEnd: (_) {
                  if (_currentStroke.isNotEmpty) {
                    _allStrokes.add(List.from(_currentStroke));
                    final points = _currentStroke
                        .map((p) => OffsetPoint(x: p.dx, y: p.dy))
                        .toList();
                    ref
                        .read(ghostPainterProvider(widget.familyId).notifier)
                        .queueStroke(points, _strokeSequence++);
                    GameMotionTokens.tap();
                    _currentStroke.clear();
                  }
                },
                child: GhostPainterCanvas(
                  strokes: _allStrokes,
                  currentStroke: _currentStroke,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Gradient Done CTA.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFEC4899), Color(0xFFB14DB8)],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: kGhostAccent.withValues(alpha: 0.4),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: FilledButton.icon(
                onPressed: _doneDrawing,
                icon: const Icon(Icons.check_rounded),
                label: Text(
                  'I\'m Done Drawing',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
        ),
        // Live guess feed.
        if (state.guesses.isNotEmpty)
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
        const SizedBox(height: 8),
      ],
    );
  }

  // ── Waiting for guesses ──────────────────────────────────────────

  Widget _buildWaitingForGuesses(
    GhostPainterState state,
    GhostPainterRound round,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GhostMedallion(emoji: '🔮', size: 88)
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scale(
                  begin: const Offset(0.94, 0.94),
                  end: const Offset(1.06, 1.06),
                  duration: 1600.ms,
                ),
            const SizedBox(height: 22),
            Text(
              'Waiting for guesses…',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            GhostGlassCard(
              child: Column(
                children: [
                  Text(
                    'YOUR WORD WAS',
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
                      color: Colors.white,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (state.guesses.isEmpty)
              Text(
                'No guesses yet — the ink is still drying…',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13.5,
                  color: KinrelColors.textDim,
                ),
              )
            else ...[
              Text(
                '${state.guesses.length} '
                '${state.guesses.length == 1 ? 'guess' : 'guesses'} so far',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: kGhostAccent,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 6,
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
            ],
          ],
        ),
      ),
    );
  }

  // ── Round complete ───────────────────────────────────────────────

  /// Round finished — the drawer sees the outcome plus the ecosystem
  /// rewards banner (badges / challenges / milestones / personal
  /// bests earned from this round) and can cheer the guessers via the
  /// sportsmanship row.
  Widget _buildRoundComplete(GhostPainterState state, GhostPainterRound round) {
    final correctGuessers = state.guesses.where((g) => g.isCorrect).toList();
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          children: [
            Center(
              child: GhostMedallion(
                emoji: correctGuessers.isNotEmpty ? '🎨' : '🤐',
                size: 84,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Round Complete!',
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
                'GUESSED IT RIGHT',
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
                  'Nobody guessed it — your masterpiece stumped the family! 🤐',
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
            // Drawer: one-tap next round — same studio, fresh prompt.
            // Guessers watch the family's live round channel, so no invites.
            if (round.drawerPersonId == _myId)
              RematchButton(
                familyId: widget.familyId,
                gameType: GameType.ghostPainter,
                previousGameId: round.id,
                participantUserIds: const [],
                label: 'Start Next Round',
                insertInvites: false,
                onCreateNewGame: () async {
                  await _startRound();
                  final newRound = ref
                      .read(ghostPainterProvider(widget.familyId))
                      .activeRound;
                  return (newRound != null && newRound.id != round.id)
                      ? newRound.id
                      : null;
                },
              ),
          ],
        ),
        if (correctGuessers.isNotEmpty)
          const GameConfetti(
            colors: [
              kGhostAccent,
              Color(0xFFB14DB8),
              KinrelColors.success,
              Color(0xFFFDF4FF),
            ],
          ),
      ],
    );
  }
}

/// Glowing circular countdown ring with the number in the center —
/// pulses red in the final ten seconds.
class _CountdownRing extends StatelessWidget {
  const _CountdownRing({required this.remaining, required this.progress});
  final int remaining;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final urgent = remaining <= 10;
    final color = urgent ? const Color(0xFFFF5A5F) : kGhostAccent;
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 14),
        ],
      ),
      child: SizedBox(
        width: 46,
        height: 46,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: progress,
              strokeWidth: 3.5,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation(color),
            ),
            Text(
              '$remaining',
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

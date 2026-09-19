// lib/features/games/sketch_telephone/sketch_telephone_game_screen.dart
//
// Sketch Telephone — main match screen.
//
// Layout (per phase):
//   writing (step 0)     → prompt input (write something for others to draw)
//   drawing (step odd)   → canvas + colors + brush sizes + undo + clear
//   writing (step even)  → describe the drawing shown on screen
//   revealing            → host taps "Reveal next step" to unwrap each chain
//   finished (completed) → full chains + rematch / exit
//
// The drawing canvas reuses the ghost_painter pattern: a single
// CustomPainter renders all finished strokes plus the live in-progress
// stroke with a soft pink glow underlay + bright core. Strokes are
// captured as a list of (points + color + size) and serialized to JSON
// for storage. No image rendering is needed — the stroke data is the
// source of truth.

import 'dart:async';
import 'dart:convert';

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
import '../shared/widgets/reactions_bar.dart';
import 'sketch_telephone_models.dart';
import 'sketch_telephone_provider.dart';

/// Premium pink accent for Sketch Telephone (matches fn__game_meta).
const Color kSketchTelephoneAccent = Color(0xFFEC4899);

class SketchTelephoneGameScreen extends ConsumerStatefulWidget {
  const SketchTelephoneGameScreen({
    super.key,
    required this.familyId,
    required this.gameId,
  });
  final String familyId;
  final String gameId;

  @override
  ConsumerState<SketchTelephoneGameScreen> createState() =>
      _SketchTelephoneGameScreenState();
}

class _SketchTelephoneGameScreenState
    extends ConsumerState<SketchTelephoneGameScreen> {
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(sketchTelephoneProvider(widget.familyId).notifier)
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
    final state = ref.read(sketchTelephoneProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final shouldLeave = await LeaveGameDialog.show(
      context,
      isHost: state.game?.hostUserId == myId &&
          state.game?.isWaiting == true,
      gameName: 'Sketch Telephone',
    );
    if (shouldLeave == true) {
      await ref
          .read(sketchTelephoneProvider(widget.familyId).notifier)
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
    final state = ref.watch(sketchTelephoneProvider(widget.familyId));
    final game = state.game;

    if (state.isLoading && game == null) {
      return DKScaffold(
        backgroundColor: KinrelColors.darkSurface,
        appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back), onPressed: _confirmLeave),
          title: const Text('Sketch Telephone'),
          backgroundColor: KinrelColors.darkCard,
          foregroundColor: KinrelColors.textWhite,
        ),
        body: const Center(
          child: CircularProgressIndicator(color: kSketchTelephoneAccent),
        ),
      );
    }

    if (game == null) {
      return DKScaffold(
        backgroundColor: KinrelColors.darkSurface,
        appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/family/${widget.familyId}')),
          title: const Text('Sketch Telephone'),
          backgroundColor: KinrelColors.darkCard,
          foregroundColor: KinrelColors.textWhite,
        ),
        body: Center(
          child: GamingEmptyCard(
            emoji: '🎨',
            title: 'Game not found',
            message: 'This match may have ended.',
          ),
        ),
      );
    }

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.arrow_back), onPressed: _confirmLeave),
        title: Text(
          game.roomName?.isNotEmpty == true
              ? game.roomName!
              : 'Sketch Telephone',
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
          if (game.isInProgress)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(child: _StepInfo(game: game)),
            ),
          if (game.hostUserId ==
                  ref.read(supabaseProvider)?.auth.currentUser?.id &&
              game.isInProgress)
            IconButton(
              tooltip: 'Leave',
              icon: const Icon(Icons.logout, size: 20),
              onPressed: _confirmLeave,
            ),
        ],
      ),
      body: game.isCompleted
          ? _ResultsView(
              game: game,
              familyId: widget.familyId,
              state: state,
              onRematch: () => ref
                  .read(sketchTelephoneProvider(widget.familyId).notifier)
                  .rematch(),
              onExit: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/family/${widget.familyId}');
                }
              },
            )
          : _ActiveView(
              state: state,
              game: game,
              familyId: widget.familyId,
            ),
    );
  }
}

class _StepInfo extends StatelessWidget {
  const _StepInfo({required this.game});
  final SketchTelephoneGame game;

  @override
  Widget build(BuildContext context) {
    final board = game.boardState;
    final step = (board?.currentStep ?? 0) + 1;
    final total = board?.playerCount ?? 1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: kSketchTelephoneAccent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'Step $step/$total',
        style: TextStyle(
            fontFamily: KinrelTypography.monoFont,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: kSketchTelephoneAccent),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Active view — writing / drawing / describing / revealing
// ─────────────────────────────────────────────────────────────────

class _ActiveView extends ConsumerWidget {
  const _ActiveView({
    required this.state,
    required this.game,
    required this.familyId,
  });

  final SketchTelephoneState state;
  final SketchTelephoneGame game;
  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = game.boardState;
    if (board == null) {
      return const Center(
          child: CircularProgressIndicator(color: kSketchTelephoneAccent));
    }

    if (board.isRevealing) {
      return _RevealView(
        state: state,
        game: game,
        familyId: familyId,
        onAdvance: () => ref
            .read(sketchTelephoneProvider(familyId).notifier)
            .advancePhase(),
      );
    }

    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final playerIdx = game.playerOrder.indexOf(myId ?? '');
    if (playerIdx < 0) {
      // Spectator
      return _SpectatorView(state: state, familyId: familyId);
    }

    return Column(
      children: [
        _TopHud(game: game, board: board),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(KinrelSpacing.md),
            child: _StepBody(
              state: state,
              game: game,
              board: board,
              playerIdx: playerIdx,
              familyId: familyId,
            ),
          ),
        ),
      ],
    );
  }
}

class _TopHud extends StatelessWidget {
  const _TopHud({required this.game, required this.board});
  final SketchTelephoneGame game;
  final SketchBoardState board;

  @override
  Widget build(BuildContext context) {
    final seconds = game.turnSecondsRemaining ?? 0;
    final timerColor =
        seconds <= 5 ? KinrelColors.error : KinrelColors.textWhite;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        border: Border(bottom: BorderSide(color: KinrelColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Step ${board.currentStep + 1}/${board.totalSteps} · ${board.currentStepType.label}',
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: kSketchTelephoneAccent,
              ),
            ),
          ),
          if (game.isInProgress && seconds > 0)
            Row(
              children: [
                Icon(Icons.timer_outlined, size: 14, color: timerColor),
                const SizedBox(width: 4),
                Text('${seconds}s',
                    style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: timerColor)),
              ],
            ),
        ],
      ),
    );
  }
}

class _StepBody extends ConsumerWidget {
  const _StepBody({
    required this.state,
    required this.game,
    required this.board,
    required this.playerIdx,
    required this.familyId,
  });

  final SketchTelephoneState state;
  final SketchTelephoneGame game;
  final SketchBoardState board;
  final int playerIdx;
  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stepType = board.currentStepType;
    final input = state.inputFor(playerIdx);
    final hasSubmitted =
        state.hasUserSubmittedCurrentStep(ref.read(supabaseProvider)?.auth.currentUser?.id);

    if (hasSubmitted) {
      return _SubmittedCard(
        stepType: stepType,
        stepNumber: board.currentStep + 1,
        totalSteps: board.totalSteps,
      );
    }

    switch (stepType) {
      case SketchStepType.prompt:
        return _PromptInputCard(
          isSubmitting: state.isSubmitting,
          onSubmit: (text) async {
            final ok = await ref
                .read(sketchTelephoneProvider(familyId).notifier)
                .submitStep(text);
            if (!ok && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Could not submit prompt'),
                  backgroundColor: KinrelColors.error,
                ),
              );
            }
          },
        );
      case SketchStepType.drawing:
        return _DrawingCard(
          prompt: input?.content ?? '',
          drawingSeconds: board.drawingSeconds,
          isSubmitting: state.isSubmitting,
          onSubmit: (strokes) async {
            final ok = await ref
                .read(sketchTelephoneProvider(familyId).notifier)
                .submitDrawing(strokes);
            if (!ok && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Could not submit drawing'),
                  backgroundColor: KinrelColors.error,
                ),
              );
            }
          },
        );
      case SketchStepType.description:
        return _DescriptionInputCard(
          drawing: input,
          isSubmitting: state.isSubmitting,
          onSubmit: (text) async {
            final ok = await ref
                .read(sketchTelephoneProvider(familyId).notifier)
                .submitStep(text);
            if (!ok && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Could not submit description'),
                  backgroundColor: KinrelColors.error,
                ),
              );
            }
          },
        );
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Prompt input (step 0)
// ─────────────────────────────────────────────────────────────────

class _PromptInputCard extends StatefulWidget {
  const _PromptInputCard({
    required this.isSubmitting,
    required this.onSubmit,
  });
  final bool isSubmitting;
  final Future<void> Function(String text) onSubmit;

  @override
  State<_PromptInputCard> createState() => _PromptInputCardState();
}

class _PromptInputCardState extends State<_PromptInputCard> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            kSketchTelephoneAccent.withValues(alpha: 0.18),
            const Color(0xFF1A1C2E),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: kSketchTelephoneAccent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.edit_note_rounded,
                  size: 22, color: kSketchTelephoneAccent),
              const SizedBox(width: 8),
              Text('Write a prompt',
                  style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: KinrelColors.textWhite)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Your prompt will rotate to the next player, who has to draw it. Be creative — but drawable!',
            style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                height: 1.4,
                color: KinrelColors.textDim),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            maxLength: kSketchTelephoneMaxPromptLength,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 16,
                color: KinrelColors.textWhite),
            decoration: InputDecoration(
              hintText: 'e.g. A cat riding a skateboard on the moon',
              hintStyle: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 16,
                  color: KinrelColors.textDim.withValues(alpha: 0.6)),
              filled: true,
              fillColor: KinrelColors.darkElevated,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(KinrelRadius.md),
                borderSide: BorderSide(color: KinrelColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(KinrelRadius.md),
                borderSide: const BorderSide(
                    color: kSketchTelephoneAccent, width: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 12),
          DKButton(
            label: 'Submit prompt',
            variant: DKButtonVariant.primary,
            fullWidth: true,
            isLoading: widget.isSubmitting,
            onPressed: () {
              final text = _controller.text.trim();
              final err = SketchTelephoneEngine.validateText(text);
              if (err != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(err),
                    backgroundColor: KinrelColors.error,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }
              widget.onSubmit(text);
            },
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Description input (step even > 0)
// ─────────────────────────────────────────────────────────────────

class _DescriptionInputCard extends StatefulWidget {
  const _DescriptionInputCard({
    required this.drawing,
    required this.isSubmitting,
    required this.onSubmit,
  });

  final SketchChainWire? drawing;
  final bool isSubmitting;
  final Future<void> Function(String text) onSubmit;

  @override
  State<_DescriptionInputCard> createState() => _DescriptionInputCardState();
}

class _DescriptionInputCardState extends State<_DescriptionInputCard> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strokes = widget.drawing?.stepType == SketchStepType.drawing
        ? _decodeStrokes(widget.drawing!.content)
        : <SketchStroke>[];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            kSketchTelephoneAccent.withValues(alpha: 0.18),
            const Color(0xFF1A1C2E),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: kSketchTelephoneAccent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.visibility_outlined,
                  size: 22, color: kSketchTelephoneAccent),
              const SizedBox(width: 8),
              Text('Describe this drawing',
                  style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: KinrelColors.textWhite)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Your description will rotate to the next player, who has to draw it from your words alone. Be specific!',
            style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                height: 1.4,
                color: KinrelColors.textDim),
          ),
          const SizedBox(height: 14),
          AspectRatio(
            aspectRatio: 1.0,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SketchTelephoneCanvas(strokes: strokes),
            ),
          ),
          if (widget.drawing != null) ...[
            const SizedBox(height: 8),
            Text(
              'Drawn by ${widget.drawing!.authorUserName}',
              style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 11,
                  color: KinrelColors.textDim),
            ),
          ],
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            maxLength: kSketchTelephoneMaxDescriptionLength,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 16,
                color: KinrelColors.textWhite),
            decoration: InputDecoration(
              hintText: 'e.g. A blob with tentacles and a hat',
              hintStyle: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 16,
                  color: KinrelColors.textDim.withValues(alpha: 0.6)),
              filled: true,
              fillColor: KinrelColors.darkElevated,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(KinrelRadius.md),
                borderSide: BorderSide(color: KinrelColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(KinrelRadius.md),
                borderSide: const BorderSide(
                    color: kSketchTelephoneAccent, width: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 12),
          DKButton(
            label: 'Submit description',
            variant: DKButtonVariant.primary,
            fullWidth: true,
            isLoading: widget.isSubmitting,
            onPressed: () {
              final text = _controller.text.trim();
              final err = SketchTelephoneEngine.validateText(text,
                  isPrompt: false);
              if (err != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(err),
                    backgroundColor: KinrelColors.error,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }
              widget.onSubmit(text);
            },
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Drawing card (step odd) — canvas + colors + brush + undo + clear
// ─────────────────────────────────────────────────────────────────

class _DrawingCard extends StatefulWidget {
  const _DrawingCard({
    required this.prompt,
    required this.drawingSeconds,
    required this.isSubmitting,
    required this.onSubmit,
  });

  final String prompt;
  final int drawingSeconds;
  final bool isSubmitting;
  final Future<void> Function(List<SketchStroke> strokes) onSubmit;

  @override
  State<_DrawingCard> createState() => _DrawingCardState();
}

class _DrawingCardState extends State<_DrawingCard> {
  final List<SketchStroke> _strokes = [];
  final List<SketchStrokePoint> _currentStroke = [];
  int _colorArgb = 0xFFFDF4FF; // bright ivory default
  double _brushSize = 6.0;

  static const List<int> _palette = [
    0xFFFDF4FF, // ivory
    0xFFEC4899, // pink
    0xFFF59E0B, // amber
    0xFF3B82F6, // blue
    0xFF10B981, // green
    0xFFEF4444, // red
    0xFF8B5CF6, // violet
    0xFF111111, // ink
  ];

  static const List<double> _sizes = [3.0, 6.0, 10.0];

  void _onPanStart(DragStartDetails _) {
    _currentStroke.clear();
    setState(() {});
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _currentStroke
          .add(SketchStrokePoint(x: details.localPosition.dx, y: details.localPosition.dy));
    });
  }

  void _onPanEnd(DragEndDetails _) {
    if (_currentStroke.isNotEmpty) {
      setState(() {
        _strokes.add(SketchStroke(
          points: List.from(_currentStroke),
          color: _colorArgb,
          size: _brushSize,
        ));
        _currentStroke.clear();
      });
    }
  }

  void _undo() {
    setState(() {
      if (_strokes.isNotEmpty) _strokes.removeLast();
    });
  }

  void _clear() {
    setState(() {
      _strokes.clear();
      _currentStroke.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            kSketchTelephoneAccent.withValues(alpha: 0.15),
            const Color(0xFF1A1C2E),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: kSketchTelephoneAccent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Prompt / description header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: KinrelColors.darkElevated,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: kSketchTelephoneAccent.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                Icon(Icons.brush_rounded,
                    size: 18, color: kSketchTelephoneAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.prompt.isEmpty
                        ? 'Draw something!'
                        : 'Draw: ${widget.prompt}',
                    style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: KinrelColors.textWhite),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Canvas
          AspectRatio(
            aspectRatio: 1.0,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: GestureDetector(
                onPanStart: _onPanStart,
                onPanUpdate: _onPanUpdate,
                onPanEnd: _onPanEnd,
                child: SketchTelephoneCanvas(
                  strokes: _strokes,
                  currentStroke: _currentStroke,
                  currentColor: _colorArgb,
                  currentSize: _brushSize,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Color palette
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _palette.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final c = _palette[i];
                final selected = c == _colorArgb;
                return GestureDetector(
                  onTap: () => setState(() => _colorArgb = c),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Color(c),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? KinrelColors.textWhite
                            : Colors.transparent,
                        width: 3,
                      ),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: Color(c).withValues(alpha: 0.6),
                                blurRadius: 8,
                              ),
                            ]
                          : null,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          // Brush sizes + undo + clear
          Row(
            children: [
              for (final s in _sizes)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _brushSize = s),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: KinrelColors.darkElevated,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: s == _brushSize
                              ? kSketchTelephoneAccent
                              : KinrelColors.border,
                          width: s == _brushSize ? 2 : 1,
                        ),
                      ),
                      child: Center(
                        child: Container(
                          width: s,
                          height: s,
                          decoration: BoxDecoration(
                            color: KinrelColors.textWhite,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              IconButton(
                tooltip: 'Undo',
                icon: const Icon(Icons.undo_rounded),
                color: KinrelColors.textSilver,
                onPressed: _strokes.isEmpty ? null : _undo,
              ),
              IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.delete_outline),
                color: KinrelColors.error,
                onPressed: _strokes.isEmpty ? null : _clear,
              ),
            ],
          ),
          const SizedBox(height: 12),
          DKButton(
            label: 'Submit drawing',
            variant: DKButtonVariant.primary,
            fullWidth: true,
            isLoading: widget.isSubmitting,
            onPressed: _strokes.isEmpty
                ? null
                : () => widget.onSubmit(List.from(_strokes)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Submitted card
// ─────────────────────────────────────────────────────────────────

class _SubmittedCard extends StatelessWidget {
  const _SubmittedCard({
    required this.stepType,
    required this.stepNumber,
    required this.totalSteps,
  });

  final SketchStepType stepType;
  final int stepNumber;
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: kSketchTelephoneAccent.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          const Icon(Icons.check_circle_rounded,
              color: kSketchTelephoneAccent, size: 36),
          const SizedBox(height: 12),
          Text(
            'Step $stepNumber submitted!',
            style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: KinrelColors.textWhite),
          ),
          const SizedBox(height: 6),
          Text(
            'Waiting for the rest of the family to finish ${stepType.verb}.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: KinrelColors.textDim),
          ),
          const SizedBox(height: 18),
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
                color: kSketchTelephoneAccent, strokeWidth: 2.5),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Spectator view (joined mid-game)
// ─────────────────────────────────────────────────────────────────

class _SpectatorView extends ConsumerWidget {
  const _SpectatorView({required this.state, required this.familyId});
  final SketchTelephoneState state;
  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = state.game?.boardState;
    final step = board == null ? 0 : board.currentStep + 1;
    final total = board == null ? 0 : board.totalSteps;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: KinrelColors.darkCard,
          child: Row(
            children: [
              const Icon(Icons.visibility_outlined,
                  color: kSketchTelephoneAccent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'You\'re spectating — step $step/$total in progress.',
                  style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      color: KinrelColors.textSilver),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('🎨', style: TextStyle(fontSize: 64)),
                  const SizedBox(height: 16),
                  Text(
                    'Sketch Telephone in progress',
                    style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: KinrelColors.textWhite),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You\'ll see all the chains when the game finishes.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 13,
                        color: KinrelColors.textDim),
                  ),
                ],
              ),
            ),
          ),
        ),
        ReactionsBar(
          gameTable: 'sketch_telephone_games',
          gameId: state.game?.id ?? '',
          familyId: familyId,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Reveal view — host unwraps each step across all chains
// ─────────────────────────────────────────────────────────────────

class _RevealView extends ConsumerStatefulWidget {
  const _RevealView({
    required this.state,
    required this.game,
    required this.familyId,
    required this.onAdvance,
  });

  final SketchTelephoneState state;
  final SketchTelephoneGame game;
  final String familyId;
  final VoidCallback onAdvance;

  @override
  ConsumerState<_RevealView> createState() => _RevealViewState();
}

class _RevealViewState extends ConsumerState<_RevealView> {
  /// How many steps to reveal per chain. Starts at 1 (just the prompt).
  int _revealCount = 1;

  @override
  Widget build(BuildContext context) {
    final board = widget.game.boardState!;
    final total = board.totalSteps;
    final isHost = widget.game.hostUserId ==
        ref.read(supabaseProvider)?.auth.currentUser?.id;
    final canRevealMore = _revealCount < total;

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: KinrelColors.darkCard,
            border: Border(bottom: BorderSide(color: KinrelColors.border)),
          ),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome_outlined,
                  size: 18, color: kSketchTelephoneAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Revealing chains · step $_revealCount/$total',
                  style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: kSketchTelephoneAccent),
                ),
              ),
            ],
          ),
        ),
        // Chain list
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(KinrelSpacing.md),
            itemCount: board.chains.length,
            separatorBuilder: (_, __) => const SizedBox(height: 14),
            itemBuilder: (_, i) {
              final chain = board.chains[i];
              final rows = widget.state.chainAt(chain.chainIndex);
              final visibleSteps = rows.take(_revealCount).toList();
              return _ChainRevealCard(
                chain: chain,
                visibleSteps: visibleSteps,
                totalSteps: total,
              );
            },
          ),
        ),
        // Host controls
        if (isHost)
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: KinrelSpacing.md, vertical: 10),
            child: Row(
              children: [
                if (canRevealMore)
                  Expanded(
                    child: DKButton(
                      label: 'Reveal step ${_revealCount + 1}',
                      variant: DKButtonVariant.primary,
                      fullWidth: true,
                      onPressed: () =>
                          setState(() => _revealCount = _revealCount + 1),
                    ),
                  )
                else
                  Expanded(
                    child: DKButton(
                      label: 'Finish & See Results',
                      variant: DKButtonVariant.primary,
                      fullWidth: true,
                      onPressed: widget.onAdvance,
                    ),
                  ),
              ],
            ),
          ),
        if (!isHost)
          Padding(
            padding: const EdgeInsets.all(KinrelSpacing.md),
            child: Text(
              canRevealMore
                  ? 'Waiting for host to reveal the next step…'
                  : 'Waiting for host to finish the reveal…',
              style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  color: KinrelColors.textDim),
            ),
          ),
      ],
    );
  }
}

class _ChainRevealCard extends StatelessWidget {
  const _ChainRevealCard({
    required this.chain,
    required this.visibleSteps,
    required this.totalSteps,
  });

  final SketchChain chain;
  final List<SketchChainWire> visibleSteps;
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: kSketchTelephoneAccent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.link_rounded,
                  size: 16, color: kSketchTelephoneAccent),
              const SizedBox(width: 6),
              Text(
                'Chain ${chain.chainIndex + 1} · started by ${chain.ownerName}',
                style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: KinrelColors.textWhite),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < visibleSteps.length; i++) ...[
            _RevealStepCard(step: visibleSteps[i]),
            if (i < visibleSteps.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Center(
                  child: Icon(Icons.arrow_downward_rounded,
                      size: 16,
                      color: kSketchTelephoneAccent.withValues(alpha: 0.5)),
                ),
              ),
          ],
          if (visibleSteps.length < totalSteps) ...[
            const SizedBox(height: 6),
            Center(
              child: Text(
                '… ${totalSteps - visibleSteps.length} more step(s) to reveal',
                style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: KinrelColors.textDim),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RevealStepCard extends StatelessWidget {
  const _RevealStepCard({required this.step});
  final SketchChainWire step;

  @override
  Widget build(BuildContext context) {
    final label = step.stepType == SketchStepType.prompt
        ? 'Prompt'
        : step.stepType == SketchStepType.drawing
            ? 'Drawing'
            : 'Description';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KinrelColors.darkElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: kSketchTelephoneAccent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: kSketchTelephoneAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(label,
                    style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                        color: kSketchTelephoneAccent)),
              ),
              const SizedBox(width: 8),
              Text(
                'by ${step.authorUserName}',
                style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 11,
                    color: KinrelColors.textDim),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (step.stepType == SketchStepType.drawing)
            AspectRatio(
              aspectRatio: 1.6,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SketchTelephoneCanvas(
                  strokes: _decodeStrokes(step.content),
                ),
              ),
            )
          else
            Text(
              step.content,
              style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textWhite,
                  height: 1.3),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Results view — game over, all chains revealed, rematch / exit
// ─────────────────────────────────────────────────────────────────

class _ResultsView extends StatelessWidget {
  const _ResultsView({
    required this.game,
    required this.familyId,
    required this.state,
    required this.onRematch,
    required this.onExit,
  });

  final SketchTelephoneGame game;
  final String familyId;
  final SketchTelephoneState state;
  final Future<String?> Function() onRematch;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final board = game.boardState;
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.all(KinrelSpacing.lg),
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    kSketchTelephoneAccent.withValues(alpha: 0.18),
                    const Color(0xFF1C1410),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color:
                        kSketchTelephoneAccent.withValues(alpha: 0.45)),
              ),
              child: Column(
                children: [
                  const Text('🎨', style: TextStyle(fontSize: 40)),
                  const SizedBox(height: 8),
                  Text(
                    'Chains Complete!',
                    style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: KinrelColors.textWhite),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Behold the chaos your family hath wrought.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        color: KinrelColors.textSilver),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (board != null)
              for (var i = 0; i < board.chains.length; i++) ...[
                _ChainRevealCard(
                  chain: board.chains[i],
                  visibleSteps: state.chainAt(board.chains[i].chainIndex),
                  totalSteps: board.totalSteps,
                ),
                const SizedBox(height: 14),
              ],
            MatchEcosystemSummary(
              gameTable: 'sketch_telephone_games',
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
                          '/family/$familyId/sketch-telephone/game/$newId',
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
          ],
        ),
        const GameConfetti(
          colors: [
            kSketchTelephoneAccent,
            Color(0xFFB14DB8),
            KinrelColors.success,
            Color(0xFFFDF4FF),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Canvas — CustomPainter that renders strokes with a pink glow
// underlay + bright core. Mirrors ghost_painter_canvas.dart.
// ─────────────────────────────────────────────────────────────────

class SketchTelephoneCanvas extends StatelessWidget {
  const SketchTelephoneCanvas({
    super.key,
    required this.strokes,
    this.currentStroke = const [],
    this.currentColor = 0xFFFDF4FF,
    this.currentSize = 6.0,
  });

  /// Finished strokes.
  final List<SketchStroke> strokes;

  /// The stroke currently being drawn (drawing screen only).
  final List<SketchStrokePoint> currentStroke;

  /// Color + brush size of the in-progress stroke.
  final int currentColor;
  final double currentSize;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SketchCanvasPainter(
        strokes: strokes,
        currentStroke: currentStroke,
        currentColor: currentColor,
        currentSize: currentSize,
      ),
      size: Size.infinite,
    );
  }
}

class _SketchCanvasPainter extends CustomPainter {
  _SketchCanvasPainter({
    required this.strokes,
    required this.currentStroke,
    required this.currentColor,
    required this.currentSize,
  });

  final List<SketchStroke> strokes;
  final List<SketchStrokePoint> currentStroke;
  final int currentColor;
  final double currentSize;

  static const Color _deepA = Color(0xFF1B1B33);
  static const Color _deepB = Color(0xFF0D0D1C);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // ── Midnight studio gradient ───────────────────────────────────
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.2, -0.25),
          radius: 1.6,
          colors: const [_deepA, _deepB],
        ).createShader(rect),
    );

    // ── Faint dotted grid ─────────────────────────────────────────
    final dot = Paint()..color = Colors.white.withValues(alpha: 0.045);
    const step = 26.0;
    for (var x = step; x < size.width; x += step) {
      for (var y = step; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), 1.1, dot);
      }
    }

    // ── Vignette ──────────────────────────────────────────────────
    final vignette = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.0,
        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.38)],
        stops: const [0.62, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, vignette);

    // ── Strokes — glow underlay + bright core ─────────────────────
    for (final s in strokes) {
      _stroke(canvas, s.points, Color(s.color), s.size);
    }
    if (currentStroke.isNotEmpty) {
      _stroke(canvas, currentStroke, Color(currentColor), currentSize);
    }
  }

  void _stroke(
      Canvas canvas, List<SketchStrokePoint> points, Color color, double w) {
    if (points.isEmpty) return;
    // Glow underlay
    final glow = Paint()
      ..color = color.withValues(alpha: 0.30)
      ..strokeWidth = w * 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    final core = Paint()
      ..color = color
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    _drawPath(canvas, points, glow);
    _drawPath(canvas, points, core);
  }

  void _drawPath(
      Canvas canvas, List<SketchStrokePoint> points, Paint paint) {
    if (points.isEmpty) return;
    if (points.length == 1) {
      canvas.drawCircle(
          Offset(points.first.x, points.first.y),
          paint.strokeWidth / 2,
          paint);
      return;
    }
    final path = Path()..moveTo(points.first.x, points.first.y);
    for (var i = 1; i < points.length - 1; i++) {
      final mid = Offset(
        (points[i].x + points[i + 1].x) / 2,
        (points[i].y + points[i + 1].y) / 2,
      );
      path.quadraticBezierTo(points[i].x, points[i].y, mid.dx, mid.dy);
    }
    path.lineTo(points.last.x, points.last.y);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SketchCanvasPainter old) => true;
}

// ─────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────

/// Decode stroke JSON into a list of [SketchStroke]. Defensive —
/// returns an empty list on any error.
List<SketchStroke> _decodeStrokes(String content) {
  if (content.isEmpty) return const [];
  try {
    final decoded = jsonDecode(content);
    if (decoded is! List) return const [];
    return decoded
        .map((s) =>
            SketchStroke.fromJson(Map<String, dynamic>.from(s as Map)))
        .toList();
  } catch (_) {
    return const [];
  }
}

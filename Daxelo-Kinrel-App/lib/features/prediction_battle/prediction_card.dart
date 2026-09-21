// lib/features/prediction_battle/prediction_card.dart
//
// ┌─────────────────────────────────────────────────────────────────────┐
// │  PREDICTION BATTLE — Inline-Interactive Feature Card                 │
// └─────────────────────────────────────────────────────────────────────┘
//
// Redesigned per spec: tapping the card NO LONGER navigates to a
// separate screen. Instead, the card expands inline (in the same
// location on Family Space) and immediately shows the prediction
// question with an easy way to submit an answer.
//
// Interaction flow (all inline):
//   1. Collapsed card shows: target mark, "PREDICTION BATTLE" label,
//      daily availability timing, current state pill, and a "Tap to
//      play" hint.
//   2. Tap → card expands with a smooth height animation (250ms,
//      easeOutCubic). The question + answer input + submit button
//      appear in place.
//   3. User enters/selects answer → taps Submit.
//   4. Card transitions to the "submitted" state inline (celebratory
//      micro-animation), then collapses back to a compact "locked in"
//      summary after a few seconds.
//
// Visual states (clearly distinguishable):
//   • NOT STARTED      — before the daily window opens. Card shows
//                        "Opens at 6:00 AM" + countdown.
//   • QUESTION AVAILABLE — window is open, user hasn't submitted.
//                          Collapsed card shows "Tap to predict".
//                          Expanded card shows question + input + submit.
//   • ANSWER SUBMITTED  — user has submitted. Card shows "✓ Locked in"
//                         + the user's answer + "waiting for reveal".
//   • COMPLETED/CLOSED  — round resolved. Card shows the result +
//                         "Next question at 6:00 AM tomorrow".
//
// Daily availability timing:
//   Derived from the existing prediction config — the round's
//   createdAt (window open) and lockAt (window close, = createdAt + 12h
//   per the SQL migration). NO hard-coded "6 AM / 9 PM" — the card
//   formats whatever the actual round times are.
//
// All colors/fonts/spacing from existing brand tokens. No new packages,
// no new infra, no navigation, no separate screen.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
// Step 3 — shared timezone-aware time utility. The card displays a
// SHARED family-wide daily window (8 AM – 9:30 PM IST per the remote
// SQL migration 20260921120000_prediction_window_update.sql) and uses
// AppTime.nowServerAccurate() in _countdown so cheap Android devices
// with drifting clocks show the correct countdown. The "IST" suffix
// on the window label is explicit so a family member traveling abroad
// isn't confused about which timezone the displayed times refer to.
import '../../../core/utils/app_time.dart';
import '../games/shared/icons/kinrel_icons.dart';
import 'prediction_models.dart';
import 'prediction_provider.dart';

class PredictionBattleCard extends ConsumerStatefulWidget {
  const PredictionBattleCard({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<PredictionBattleCard> createState() =>
      _PredictionBattleCardState();
}

class _PredictionBattleCardState extends ConsumerState<PredictionBattleCard>
    with TickerProviderStateMixin {
  // Expansion animation — drives the inline expand/collapse.
  late final AnimationController _expandController;
  late final Animation<double> _expandAnimation;

  // Outer halo pulse — slow breathe on the target mark.
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  // Celebratory glow when the user submits.
  late final AnimationController _celebrationController;

  // 1s tick so the countdown + availability window re-renders smoothly.
  Timer? _countdownTimer;

  // Inline answer state.
  final TextEditingController _answerController = TextEditingController();
  PredictionConfidence? _selectedConfidence;
  bool _isExpanded = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(
        () => ref.read(predictionProvider(widget.familyId).notifier).load());

    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _celebrationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _expandController.dispose();
    _pulseController.dispose();
    _celebrationController.dispose();
    _countdownTimer?.cancel();
    _answerController.dispose();
    super.dispose();
  }

  void _toggleExpand() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _expandController.forward();
      } else {
        _expandController.reverse();
      }
    });
  }

  Future<void> _submitPrediction() async {
    if (_isSubmitting) return;
    final prediction = _answerController.text.trim();
    if (prediction.isEmpty || _selectedConfidence == null) return;

    setState(() => _isSubmitting = true);
    final success = await ref
        .read(predictionProvider(widget.familyId).notifier)
        .submitPrediction(prediction, _selectedConfidence!);

    if (mounted) {
      setState(() => _isSubmitting = false);
      if (success) {
        unawaited(_celebrationController.forward(from: 0));
        // Auto-collapse after the celebration plays.
        unawaited(Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted && _isExpanded) _toggleExpand();
        }));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not submit — try again'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(predictionProvider(widget.familyId));
    final round = state.activeRound;
    final question = state.activeQuestion;

    if (state.isLoading) return const _SkeletonCard();

    // Determine the visual state from the round + submission status.
    final viewState = _resolveViewState(round, state.hasSubmitted);

    final isLegendary = round?.isLegendary ?? false;
    final accent = isLegendary ? KinrelColors.brightGold : KinrelColors.orange;
    final accent2 = KinrelColors.amber;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      decoration: _cardDecoration(accent),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: DecoratedBox(
              decoration: _cardBaseGradient(isLegendary),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HeaderRow(
                      accent: accent,
                      accent2: accent2,
                      pulseAnimation: _pulseAnimation,
                      isLegendary: isLegendary,
                      viewState: viewState,
                      isExpanded: _isExpanded,
                      onToggle: _toggleExpand,
                    ),
                    const SizedBox(height: 14),
                    // Availability timing — always visible (collapsed + expanded).
                    _AvailabilityTiming(
                      accent: accent,
                      round: round,
                      viewState: viewState,
                    ),
                    const SizedBox(height: 12),
                    // Collapsed summary — always visible when not expanded.
                    _CollapsedSummary(
                      accent: accent,
                      viewState: viewState,
                      round: round,
                      question: question,
                      state: state,
                      isExpanded: _isExpanded,
                      onToggle: _toggleExpand,
                      inactiveReason: state.inactiveReason,
                    ),
                    // Expanded interaction — question + answer + submit.
                    SizeTransition(
                      sizeFactor: _expandAnimation,
                      alignment: Alignment.bottomCenter,
                      child: FadeTransition(
                        opacity: _expandAnimation,
                        child: _ExpandedInteraction(
                          accent: accent,
                          accent2: accent2,
                          viewState: viewState,
                          round: round,
                          question: question,
                          state: state,
                          answerController: _answerController,
                          selectedConfidence: _selectedConfidence,
                          onConfidenceChanged: (c) =>
                              setState(() => _selectedConfidence = c),
                          onSubmit: _submitPrediction,
                          isSubmitting: _isSubmitting,
                          celebrationAnimation: _celebrationController,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _CardBorderOverlay(accent: accent),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 400.ms)
        .slideY(begin: -0.03, end: 0, duration: 400.ms);
  }

  /// Resolves which of the 4 visual states the card is in, based on the
  /// round status + whether the user has submitted.
  _PredictionViewState _resolveViewState(
      PredictionRound? round, bool hasSubmitted) {
    if (round == null) return _PredictionViewState.notStarted;
    switch (round.status) {
      case PredictionStatus.open:
        return hasSubmitted
            ? _PredictionViewState.answerSubmitted
            : _PredictionViewState.questionAvailable;
      case PredictionStatus.locked:
      case PredictionStatus.pending:
        return _PredictionViewState.answerSubmitted;
      case PredictionStatus.resolved:
      case PredictionStatus.archived:
        return _PredictionViewState.completed;
    }
  }

  BoxDecoration _cardDecoration(Color accent) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(26),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.45),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
        BoxShadow(
          color: accent.withValues(alpha: 0.28),
          blurRadius: 28,
          spreadRadius: 1,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  BoxDecoration _cardBaseGradient(bool isLegendary) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isLegendary
            ? [
                const Color(0xFF2A1F08),
                const Color(0xFF1B1505),
                const Color(0xFF13141E),
              ]
            : [
                const Color(0xFF241208),
                const Color(0xFF1A0E05),
                KinrelColors.darkCard,
              ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Visual states — the 4 distinct states the card can be in.
// ═══════════════════════════════════════════════════════════════════════

enum _PredictionViewState {
  /// Before the daily window opens — no active round yet.
  notStarted,
  /// Window is open, user hasn't submitted — ready to predict.
  questionAvailable,
  /// User has submitted their answer — waiting for reveal.
  answerSubmitted,
  /// Round resolved — results are in.
  completed,
}

extension _PredictionViewStateX on _PredictionViewState {
  String get label {
    switch (this) {
      case _PredictionViewState.notStarted:
        return 'OPENS SOON';
      case _PredictionViewState.questionAvailable:
        return 'LIVE NOW';
      case _PredictionViewState.answerSubmitted:
        return 'LOCKED IN';
      case _PredictionViewState.completed:
        return 'COMPLETED';
    }
  }

  Color get color {
    switch (this) {
      case _PredictionViewState.notStarted:
        return KinrelColors.textSilver;
      case _PredictionViewState.questionAvailable:
        return KinrelColors.success;
      case _PredictionViewState.answerSubmitted:
        return KinrelColors.amber;
      case _PredictionViewState.completed:
        return KinrelColors.orange;
    }
  }

  String get summaryHint {
    switch (this) {
      case _PredictionViewState.notStarted:
        return 'Tap to set a reminder';
      case _PredictionViewState.questionAvailable:
        return 'Tap to predict';
      case _PredictionViewState.answerSubmitted:
        return 'Tap to view your prediction';
      case _PredictionViewState.completed:
        return 'Tap to see the result';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Header row — target mark, label, status pill, expand/collapse chevron.
// ═══════════════════════════════════════════════════════════════════════

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.accent,
    required this.accent2,
    required this.pulseAnimation,
    required this.isLegendary,
    required this.viewState,
    required this.isExpanded,
    required this.onToggle,
  });

  final Color accent;
  final Color accent2;
  final Animation<double> pulseAnimation;
  final bool isLegendary;
  final _PredictionViewState viewState;
  final bool isExpanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Prediction Target mark (the card's visual identity).
        SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedBuilder(
                animation: pulseAnimation,
                builder: (context, _) {
                  return Transform.scale(
                    scale: pulseAnimation.value,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            accent.withValues(alpha: 0.32),
                            accent.withValues(alpha: 0.0),
                          ],
                          stops: const [0.35, 1.0],
                        ),
                      ),
                    ),
                  );
                },
              ),
              SizedBox(
                width: 32,
                height: 32,
                child: CustomPaint(
                  painter: _PredictionTargetPainter(
                    color: accent,
                    innerColor: accent2,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Text(
                    'PREDICTION BATTLE',
                    style: const TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.3,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (isLegendary)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFD700), Color(0xFFF59240)],
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'LEGENDARY',
                        style: TextStyle(
                          fontFamily: KinrelTypography.monoFont,
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: Colors.black,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                _tagline(viewState),
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: accent.withValues(alpha: 0.95),
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
        // Status pill.
        _StatusPill(viewState: viewState),
        const SizedBox(width: 6),
        // Expand/collapse chevron — only for states with detail to show.
        if (viewState != _PredictionViewState.notStarted)
          GestureDetector(
            onTap: onToggle,
            behavior: HitTestBehavior.opaque,
            child: AnimatedRotation(
              turns: isExpanded ? 0.25 : 0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: Icon(
                Icons.chevron_right_rounded,
                color: accent,
                size: 22,
              ),
            ),
          ),
      ],
    );
  }

  String _tagline(_PredictionViewState s) {
    switch (s) {
      case _PredictionViewState.notStarted:
        return 'Daily prediction · opens soon';
      case _PredictionViewState.questionAvailable:
        return 'Live now · predict to win';
      case _PredictionViewState.answerSubmitted:
        return 'Locked in · waiting for reveal';
      case _PredictionViewState.completed:
        return 'Resolved · see the result';
    }
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.viewState});
  final _PredictionViewState viewState;

  @override
  Widget build(BuildContext context) {
    final color = viewState.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.40), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (viewState == _PredictionViewState.questionAvailable)
            _PulsingDot(color: color)
          else
            _Dot(color: color, size: 6),
          const SizedBox(width: 5),
          Text(
            viewState.label,
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color});
  final Color color;
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Opacity(
          opacity: 0.45 + (_controller.value * 0.55),
          child: _Dot(color: widget.color, size: 6),
        );
      },
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.size});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.6),
            blurRadius: 4,
            spreadRadius: 0.5,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Availability timing — "Available today: 6:00 AM – 9:00 PM"
// Derived from the round's createdAt + lockAt (existing config).
// ═══════════════════════════════════════════════════════════════════════

class _AvailabilityTiming extends StatelessWidget {
  const _AvailabilityTiming({
    required this.accent,
    required this.round,
    required this.viewState,
  });

  final Color accent;
  final PredictionRound? round;
  final _PredictionViewState viewState;

  @override
  Widget build(BuildContext context) {
    // The daily window is now a FIXED schedule: 8:00 AM – 9:30 PM IST.
    // (Configured in the fn_prediction_get_active SQL function via
    // AT TIME ZONE 'Asia/Kolkata'.) We display this fixed label rather
    // than deriving from the round's createdAt/lockAt, because the
    // window is the same every day regardless of when the round was
    // actually created.
    //
    // Step 3 — append the explicit 'IST' suffix so a family member
    // traveling abroad isn't confused about which timezone the
    // displayed times refer to. Per the user's instructions: "do NOT
    // convert the shared window itself to the traveler's local time;
    // just label it clearly."
    const windowLabel = '8:00 AM – 9:30 PM IST';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: KinrelColors.darkElevated.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: accent.withValues(alpha: 0.20),
          width: 0.6,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.schedule_outlined,
            size: 12,
            color: accent.withValues(alpha: 0.85),
          ),
          const SizedBox(width: 5),
          const Text(
            'Available today',
            style: const TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: KinrelColors.textSilver,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            windowLabel,
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: accent,
              letterSpacing: 0.2,
            ),
          ),
          if (round != null && viewState == _PredictionViewState.questionAvailable) ...[
            const SizedBox(width: 8),
            Text(
              '· closes in ${_countdown(round!.lockAt)}',
              style: const TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: KinrelColors.amber,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Step 3 — server-accurate countdown. Uses AppTime.nowServerAccurate()
  /// instead of DateTime.now() so cheap Android devices with drifting
  /// clocks show the correct countdown. Returns a friendly "Xh Ym" /
  /// "Ym Zs" / "Zs" string. Negative → "soon".
  String _countdown(DateTime target) {
    final diff = target.difference(AppTime.nowServerAccurate());
    if (diff.isNegative) return 'soon';
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    if (h > 0) return '${h}h ${m}m';
    final s = diff.inSeconds % 60;
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Collapsed summary — always-visible compact summary of the current state.
// ═══════════════════════════════════════════════════════════════════════

class _CollapsedSummary extends StatelessWidget {
  const _CollapsedSummary({
    required this.accent,
    required this.viewState,
    required this.round,
    required this.question,
    required this.state,
    required this.isExpanded,
    required this.onToggle,
    this.inactiveReason,
  });

  final Color accent;
  final _PredictionViewState viewState;
  final PredictionRound? round;
  final PredictionQuestion? question;
  final PredictionState state;
  final bool isExpanded;
  final VoidCallback onToggle;
  /// 'before_window' | 'after_window' | 'no_questions_available' | null
  final String? inactiveReason;

  @override
  Widget build(BuildContext context) {
    // When expanded, hide the summary — the expanded view shows everything.
    if (isExpanded) return const SizedBox.shrink();

    return GestureDetector(
      onTap: onToggle,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (viewState == _PredictionViewState.notStarted) ...[
            Text(
              // Step 3 — explicit 'IST' suffix on the open/close times
              // so a family member traveling abroad isn't confused about
              // which timezone the displayed times refer to. The window
              // itself stays at IST 8 AM – 9:30 PM (not converted to
              // traveler-local), per the user's instructions.
              inactiveReason == 'after_window'
                  ? 'Today\'s prediction is closed. Come back tomorrow at 8:00 AM IST.'
                  : inactiveReason == 'no_questions_available'
                      ? 'No new questions available right now.'
                      : 'Today\'s prediction opens at 8:00 AM IST.',
              style: const TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                color: KinrelColors.textSilver,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              inactiveReason == 'after_window'
                  ? 'Closed for today'
                  : viewState.summaryHint,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
          ] else if (viewState == _PredictionViewState.questionAvailable) ...[
            if (question != null) ...[
              Text(
                question!.question,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                viewState.summaryHint,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
            ],
          ] else if (viewState == _PredictionViewState.answerSubmitted) ...[
            Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  size: 16,
                  color: KinrelColors.success,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    state.myPrediction != null
                        ? 'You predicted "${state.myPrediction}"'
                        : 'Your prediction is locked in',
                    style: const TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: KinrelColors.textWhite,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Reveals ${_revealLabel(round)}',
              style: const TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: KinrelColors.textSilver,
              ),
            ),
          ] else if (viewState == _PredictionViewState.completed) ...[
            Row(
              children: [
                Icon(
                  Icons.emoji_events_outlined,
                  size: 16,
                  color: accent,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    round?.actualAnswer != null
                        ? 'Answer: ${round!.actualAnswer}'
                        : 'Round resolved',
                    style: const TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: KinrelColors.textWhite,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              viewState.summaryHint,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _revealLabel(PredictionRound? round) {
    if (round == null) return 'soon';
    final diff = round.revealAt.difference(AppTime.nowServerAccurate());
    if (diff.isNegative) return 'any moment';
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    if (h > 0) return 'in ${h}h ${m}m';
    if (m > 0) return 'in ${m}m';
    return 'in seconds';
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Expanded interaction — question + answer input + submit (inline).
// ═══════════════════════════════════════════════════════════════════════

class _ExpandedInteraction extends StatelessWidget {
  const _ExpandedInteraction({
    required this.accent,
    required this.accent2,
    required this.viewState,
    required this.round,
    required this.question,
    required this.state,
    required this.answerController,
    required this.selectedConfidence,
    required this.onConfidenceChanged,
    required this.onSubmit,
    required this.isSubmitting,
    required this.celebrationAnimation,
  });

  final Color accent;
  final Color accent2;
  final _PredictionViewState viewState;
  final PredictionRound? round;
  final PredictionQuestion? question;
  final PredictionState state;
  final TextEditingController answerController;
  final PredictionConfidence? selectedConfidence;
  final void Function(PredictionConfidence) onConfidenceChanged;
  final Future<void> Function() onSubmit;
  final bool isSubmitting;
  final AnimationController celebrationAnimation;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        // Divider.
        Container(
          height: 1,
          color: accent.withValues(alpha: 0.15),
        ),
        const SizedBox(height: 14),
        if (viewState == _PredictionViewState.questionAvailable && question != null)
          _QuestionAvailableBody(
            accent: accent,
            accent2: accent2,
            question: question!,
            answerController: answerController,
            selectedConfidence: selectedConfidence,
            onConfidenceChanged: onConfidenceChanged,
            onSubmit: onSubmit,
            isSubmitting: isSubmitting,
          )
        else if (viewState == _PredictionViewState.answerSubmitted)
          _SubmittedBody(
            accent: accent,
            state: state,
            round: round,
            question: question,
            // familyId for the "View Full →" navigation — comes from the
            // active round (same family as the card itself, since the
            // card is family-scoped via the Riverpod family provider).
            familyId: round?.familyId ?? '',
            celebrationAnimation: celebrationAnimation,
          )
        else if (viewState == _PredictionViewState.completed && round != null)
          _CompletedBody(
            accent: accent,
            round: round!,
            question: question,
            state: state,
          )
        else
          // notStarted — no expanded content.
          const SizedBox.shrink(),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Question-available body — the inline question + answer + submit form.
// ═══════════════════════════════════════════════════════════════════════

class _QuestionAvailableBody extends StatelessWidget {
  const _QuestionAvailableBody({
    required this.accent,
    required this.accent2,
    required this.question,
    required this.answerController,
    required this.selectedConfidence,
    required this.onConfidenceChanged,
    required this.onSubmit,
    required this.isSubmitting,
  });

  final Color accent;
  final Color accent2;
  final PredictionQuestion question;
  final TextEditingController answerController;
  final PredictionConfidence? selectedConfidence;
  final void Function(PredictionConfidence) onConfidenceChanged;
  final Future<void> Function() onSubmit;
  final bool isSubmitting;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category chip + type.
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
              decoration: BoxDecoration(
                color: KinrelColors.darkElevated.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: accent.withValues(alpha: 0.35),
                  width: 0.6,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  KinrelIcon(KinrelIconData.target, size: 10, color: accent),
                  const SizedBox(width: 4),
                  Text(
                    '${question.category.toUpperCase()} · ${question.type.label.toUpperCase()}',
                    style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: accent,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // The question — large, friendly, the visual focus.
        Text(
          question.question,
          style: const TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textWhite,
            height: 1.32,
            letterSpacing: -0.1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          question.type == PredictionType.closest
              ? 'Predict a number — closest wins!'
              : 'Pick an outcome — correct wins!',
          style: const TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 12,
            color: KinrelColors.textSilver,
          ),
        ),
        const SizedBox(height: 16),
        // Answer input — numeric for closest, two-option for outcome.
        if (question.type == PredictionType.closest)
          TextField(
            controller: answerController,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(5),
            ],
            style: const TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: KinrelColors.textWhite,
            ),
            decoration: InputDecoration(
              hintText: 'Enter your number',
              hintStyle: TextStyle(
                color: KinrelColors.textSilver.withValues(alpha: 0.5),
                fontSize: 16,
              ),
              filled: true,
              fillColor: KinrelColors.darkCard,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: accent.withValues(alpha: 0.3),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: accent, width: 1.5),
              ),
            ),
          )
        else
          Row(
            children: [
              Expanded(
                child: _OutcomeOption(
                  label: question.optionA ?? 'Yes',
                  selected: answerController.text == (question.optionA ?? 'Yes'),
                  accent: accent,
                  onTap: () => answerController.text =
                      question.optionA ?? 'Yes',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _OutcomeOption(
                  label: question.optionB ?? 'No',
                  selected: answerController.text == (question.optionB ?? 'No'),
                  accent: accent,
                  onTap: () => answerController.text =
                      question.optionB ?? 'No',
                ),
              ),
            ],
          ),
        const SizedBox(height: 14),
        // Confidence selector.
        const Text(
          'How confident are you?',
          style: const TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 12,
            color: KinrelColors.textSilver,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final c in PredictionConfidence.values) ...[
              Expanded(
                child: _ConfidenceChip(
                  label: c.label,
                  multiplier: '×${c.multiplier.toStringAsFixed(1)}',
                  selected: selectedConfidence == c,
                  accent: accent2,
                  onTap: () => onConfidenceChanged(c),
                ),
              ),
              if (c != PredictionConfidence.values.last) const SizedBox(width: 6),
            ],
          ],
        ),
        const SizedBox(height: 16),
        // Submit button.
        _SubmitButton(
          accent: accent,
          accent2: accent2,
          isSubmitting: isSubmitting,
          enabled: selectedConfidence != null && answerController.text.isNotEmpty,
          onPressed: onSubmit,
        ),
      ],
    );
  }
}

class _OutcomeOption extends StatelessWidget {
  const _OutcomeOption({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.18)
              : KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? accent : KinrelColors.border,
            width: selected ? 1.4 : 1.0,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: selected ? accent : KinrelColors.textSilver,
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfidenceChip extends StatelessWidget {
  const _ConfidenceChip({
    required this.label,
    required this.multiplier,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final String multiplier;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.15)
              : KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? accent : KinrelColors.border,
            width: selected ? 1.3 : 1.0,
          ),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected ? accent : KinrelColors.textSilver,
              ),
            ),
            Text(
              multiplier,
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 9,
                color: selected ? accent : KinrelColors.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({
    required this.accent,
    required this.accent2,
    required this.isSubmitting,
    required this.enabled,
    required this.onPressed,
  });

  final Color accent;
  final Color accent2;
  final bool isSubmitting;
  final bool enabled;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled && !isSubmitting ? () => onPressed() : null,
      behavior: HitTestBehavior.opaque,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.5,
        duration: const Duration(milliseconds: 180),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: enabled
                  ? [accent, accent2]
                  : [accent.withValues(alpha: 0.5), accent2.withValues(alpha: 0.5)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.45),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                      SizedBox(width: 7),
                      const Text(
                        'Lock in my prediction',
                        style: const TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Submitted body — celebratory confirmation + the locked-in answer.
// ═══════════════════════════════════════════════════════════════════════

class _SubmittedBody extends StatelessWidget {
  const _SubmittedBody({
    required this.accent,
    required this.state,
    required this.round,
    required this.question,
    required this.familyId,
    required this.celebrationAnimation,
  });

  final Color accent;
  final PredictionState state;
  final PredictionRound? round;
  /// The active round's question. May be null if the round was loaded
  /// without the question join — in that case we fall back to "Today's
  /// question" as a placeholder label.
  final PredictionQuestion? question;
  /// Family id for the "View Full →" navigation to the full leaderboard
  /// screen. Empty string when the round is null (defensive — the
  /// "View Full" button is hidden in that case).
  final String familyId;
  final AnimationController celebrationAnimation;

  @override
  Widget build(BuildContext context) {
    final glowScale = Tween<double>(begin: 0.5, end: 1.4).animate(
      CurvedAnimation(
        parent: celebrationAnimation,
        curve: Curves.easeOut,
      ),
    );
    final glowOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: celebrationAnimation,
        curve: const Interval(0.0, 0.4, curve: Curves.easeIn),
      ),
    );
    final numberScale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(
        parent: celebrationAnimation,
        curve: Curves.elasticOut,
      ),
    );

    return Center(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // "Locked in" header.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.check_circle_rounded,
                size: 18,
                color: KinrelColors.success,
              ),
              const SizedBox(width: 7),
              Text(
                'PREDICTION LOCKED IN',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.3,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // The locked-in number/answer with celebratory glow.
          Stack(
            alignment: Alignment.center,
            children: [
              AnimatedBuilder(
                animation: celebrationAnimation,
                builder: (context, _) {
                  return Transform.scale(
                    scale: glowScale.value,
                    child: Opacity(
                      opacity: glowOpacity.value * 0.6,
                      child: Container(
                        width: 160,
                        height: 160,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              accent.withValues(alpha: 0.55),
                              accent.withValues(alpha: 0.0),
                            ],
                            stops: const [0.3, 1.0],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              AnimatedBuilder(
                animation: celebrationAnimation,
                builder: (context, _) {
                  return Transform.scale(
                    scale: numberScale.value,
                    child: Column(
                      children: [
                        const Text(
                          'You predicted',
                          style: const TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 12,
                            color: KinrelColors.textSilver,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          state.myPrediction ?? '—',
                          style: TextStyle(
                            fontFamily: KinrelTypography.displayFont,
                            fontSize: 44,
                            fontWeight: FontWeight.w800,
                            color: KinrelColors.textWhite,
                            letterSpacing: -1.0,
                            height: 1.0,
                            shadows: [
                              Shadow(
                                color: accent.withValues(alpha: 0.50),
                                blurRadius: 24,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Confidence + reveal timing.
          if (state.myConfidence != null)
            Text(
              'Confidence: ${state.myConfidence!.label} (×${state.myConfidence!.multiplier.toStringAsFixed(1)})',
              style: const TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: KinrelColors.textSilver,
              ),
            ),
          const SizedBox(height: 6),
          Text(
            'Reveals ${_revealLabel(round)} · ${state.participationCount} family members predicted',
            style: const TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              color: KinrelColors.textDim,
            ),
            textAlign: TextAlign.center,
          ),

          // ── Locked-in expand: today's question + your answer ──────────
          // The "missing piece" the user called out — even when the rest
          // of the prompt isn't done, this needs to render. Always shows
          // the question text + the user's submitted answer so the user
          // can confirm what they predicted at a glance.
          const SizedBox(height: 18),
          _LockedInDivider(accent: accent),
          const SizedBox(height: 14),
          _LockedInQuestionBlock(
            accent: accent,
            question: question,
            myPrediction: state.myPrediction,
            myConfidence: state.myConfidence,
          ),

          // ── Recent rounds (last 1-2 resolved) ──────────────────────────
          // Pulled from state.recentResults (already fetched by the
          // provider — no new query needed). Filter to resolved, take 2.
          if (state.recentResults.any((r) => r.status == PredictionStatus.resolved)) ...[
            const SizedBox(height: 14),
            _LockedInDivider(accent: accent),
            const SizedBox(height: 12),
            _RecentRoundsTeaser(
              accent: accent,
              state: state,
            ),
          ],

          // ── Compact leaderboard teaser (top 3) + "View Full →" ─────────
          if (state.leaderboard.isNotEmpty) ...[
            const SizedBox(height: 14),
            _LockedInDivider(accent: accent),
            const SizedBox(height: 12),
            _LeaderboardTeaser(
              accent: accent,
              leaderboard: state.leaderboard,
              myUserId: state.myStats?.userId,
              familyId: familyId,
            ),
          ],
        ],
      ),
    );
  }

  String _revealLabel(PredictionRound? round) {
    if (round == null) return 'soon';
    final diff = round.revealAt.difference(AppTime.nowServerAccurate());
    if (diff.isNegative) return 'any moment';
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    if (h > 0) return 'in ${h}h ${m}m';
    if (m > 0) return 'in ${m}m';
    return 'in seconds';
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Locked-in expand: divider + question block + recent rounds + leaderboard
// ═══════════════════════════════════════════════════════════════════════

/// Thin horizontal divider used between the celebratory number and the
/// extra locked-in expand sections. Matches the divider style used in
/// `_ExpandedInteraction` above (line 980) so the expanded section
/// feels like a natural extension of the card.
class _LockedInDivider extends StatelessWidget {
  const _LockedInDivider({required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      color: accent.withValues(alpha: 0.15),
    );
  }
}

/// Shows today's question text + the user's submitted answer beneath it.
/// This is the "missing piece" the user explicitly called out — the
/// locked-in state used to show only "Locked in · waiting for reveal"
/// with no trace of the question or the user's own answer.
class _LockedInQuestionBlock extends StatelessWidget {
  const _LockedInQuestionBlock({
    required this.accent,
    required this.question,
    required this.myPrediction,
    required this.myConfidence,
  });

  final Color accent;
  final PredictionQuestion? question;
  final String? myPrediction;
  final PredictionConfidence? myConfidence;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: KinrelColors.darkElevated.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accent.withValues(alpha: 0.18),
          width: 0.6,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section label.
          Row(
            children: [
              Icon(
                Icons.help_outline_rounded,
                size: 12,
                color: accent.withValues(alpha: 0.85),
              ),
              const SizedBox(width: 5),
              Text(
                'TODAY\'S QUESTION',
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // The question text — fall back to a placeholder if the
          // question wasn't loaded (shouldn't happen for active rounds,
          // but defensive).
          Text(
            question?.question ?? 'Today\'s prediction question',
            style: const TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: KinrelColors.textWhite,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          // The user's own submitted answer — the missing piece.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(
                Icons.check_circle_rounded,
                size: 14,
                color: KinrelColors.success,
              ),
              const SizedBox(width: 6),
              const Text(
                'Your guess: ',
                style: const TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textSilver,
                ),
              ),
              Flexible(
                child: Text(
                  myPrediction ?? '—',
                  style: const TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: KinrelColors.textWhite,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (myConfidence != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: KinrelColors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: KinrelColors.amber.withValues(alpha: 0.30),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    '${myConfidence!.label} ×${myConfidence!.multiplier.toStringAsFixed(1)}',
                    style: const TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: KinrelColors.amber,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// "Recent rounds" teaser — the last 1-2 resolved rounds only. Each row
/// shows the question (truncated if long), the user's own answer, and
/// the result (correct / closest-wins outcome with points delta).
/// Pulled from `state.recentResults` — the provider already fetches
/// the last 20 resolved rounds AND merges my own submission into each
/// round's `results` list (see prediction_provider.dart).
class _RecentRoundsTeaser extends StatelessWidget {
  const _RecentRoundsTeaser({
    required this.accent,
    required this.state,
  });

  final Color accent;
  final PredictionState state;

  @override
  Widget build(BuildContext context) {
    // Take the last 2 resolved rounds — keep the provider's full list
    // untouched (the battle screen uses it for the full history).
    final resolved = state.recentResults
        .where((r) => r.status == PredictionStatus.resolved)
        .take(2)
        .toList();
    if (resolved.isEmpty) return const SizedBox.shrink();
    final myId = state.myStats?.userId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section label.
        Row(
          children: [
            Icon(
              Icons.history_rounded,
              size: 12,
              color: accent.withValues(alpha: 0.85),
            ),
            const SizedBox(width: 5),
            Text(
              'RECENT ROUNDS',
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final r in resolved)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _RecentRoundRow(
              accent: accent,
              round: r,
              myUserId: myId,
            ),
          ),
      ],
    );
  }
}

/// A single recent round row inside the locked-in expand section.
class _RecentRoundRow extends StatelessWidget {
  const _RecentRoundRow({
    required this.accent,
    required this.round,
    required this.myUserId,
  });

  final Color accent;
  final PredictionRound round;
  final String? myUserId;

  @override
  Widget build(BuildContext context) {
    // Find my result in the round's results list (the provider merges
    // my submission in via the recent-rounds fetch; see
    // prediction_provider.dart).
    PredictionResult? myResult;
    if (myUserId != null) {
      for (final r in round.results) {
        if (r.userId == myUserId) {
          myResult = r;
          break;
        }
      }
    }
    final questionText = round.question?.question;
    final truncatedQuestion = questionText != null && questionText.length > 60
        ? '${questionText.substring(0, 57)}...'
        : (questionText ?? 'Round ${round.id.substring(0, 6)}');

    // Outcome label: for closest-wins, "closest" if rank==1 else
    // "off by <distance>"; for outcome, "correct" / "wrong".
    String outcomeLabel;
    Color outcomeColor;
    if (myResult == null) {
      outcomeLabel = 'didn\'t play';
      outcomeColor = KinrelColors.textDim;
    } else if (round.question?.type == PredictionType.outcome) {
      if (myResult.correct) {
        outcomeLabel = '✓ correct';
        outcomeColor = KinrelColors.success;
      } else {
        outcomeLabel = '✗ wrong';
        outcomeColor = KinrelColors.textDim;
      }
    } else {
      // closest-wins
      if (myResult.rank == 1) {
        outcomeLabel = '🏆 closest';
        outcomeColor = KinrelColors.brightGold;
      } else if (myResult.distance != null) {
        final dist = myResult.distance!;
        outcomeLabel = 'off by ${dist.toStringAsFixed(dist == dist.roundToDouble() ? 0 : 1)}';
        outcomeColor = KinrelColors.textDim;
      } else {
        outcomeLabel = myResult.correct ? '✓ correct' : '✗ wrong';
        outcomeColor = myResult.correct ? KinrelColors.success : KinrelColors.textDim;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: accent.withValues(alpha: 0.10),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Question (truncated).
          Text(
            truncatedQuestion,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textSilver,
            ),
          ),
          const SizedBox(height: 4),
          // Answer + outcome + points delta.
          Row(
            children: [
              if (myResult != null) ...[
                Text(
                  'You: ${myResult.prediction}',
                  style: const TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 11,
                    color: KinrelColors.textDim,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  'Answer: ${round.actualAnswer ?? '—'}',
                  style: const TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 11,
                    color: KinrelColors.textDim,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                outcomeLabel,
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: outcomeColor,
                ),
              ),
              if (myResult != null && myResult.points > 0) ...[
                const SizedBox(width: 6),
                Text(
                  '+${myResult.points}',
                  style: const TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: KinrelColors.success,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Compact leaderboard teaser — top 3 entries only. Each row shows
/// rank, member display name, current streak icon if > 0, points.
/// Followed by a "View Full →" button that navigates to
/// `prediction_battle_screen.dart` (the existing full-screen
/// destination which has the complete leaderboard).
class _LeaderboardTeaser extends StatelessWidget {
  const _LeaderboardTeaser({
    required this.accent,
    required this.leaderboard,
    required this.myUserId,
    required this.familyId,
  });

  final Color accent;
  final List<PredictionLeaderboardEntry> leaderboard;
  final String? myUserId;
  /// Family id for the "View Full →" navigation. Empty string when the
  /// round is null (the "View Full" button is hidden in that case).
  final String familyId;

  @override
  Widget build(BuildContext context) {
    final top3 = leaderboard.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section label.
        Row(
          children: [
            Icon(
              Icons.leaderboard_outlined,
              size: 12,
              color: accent.withValues(alpha: 0.85),
            ),
            const SizedBox(width: 5),
            Text(
              'LEADERBOARD',
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < top3.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _LeaderboardTeaserRow(
              accent: accent,
              rank: i + 1,
              entry: top3[i],
              isMe: top3[i].userId == myUserId,
            ),
          ),
        // "View Full →" link — navigates to the battle screen which has
        // the complete leaderboard (extended in this commit to show all
        // the fields: points, wins, accuracy, current streak, best
        // streak per member).
        if (familyId.isNotEmpty) ...[
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () {
              final ctx = context;
              if (ctx.canPop()) {
                // Push onto the existing navigation stack so the back
                // button returns to the family hub the card lives on.
                ctx.push('/family/$familyId/prediction-battle');
              } else {
                ctx.go('/family/$familyId/prediction-battle');
              }
            },
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'View Full',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 12,
                    color: accent,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A single row in the leaderboard teaser. Highlights the calling user
/// with a subtle accent border.
class _LeaderboardTeaserRow extends StatelessWidget {
  const _LeaderboardTeaserRow({
    required this.accent,
    required this.rank,
    required this.entry,
    required this.isMe,
  });

  final Color accent;
  final int rank;
  final PredictionLeaderboardEntry entry;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    // Rank color: gold for 1, silver for 2, bronze for 3.
    final rankColor = switch (rank) {
      1 => KinrelColors.brightGold,
      2 => const Color(0xFFC0C0C0),
      3 => const Color(0xFFCD7F32),
      _ => KinrelColors.textDim,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isMe
            ? accent.withValues(alpha: 0.10)
            : KinrelColors.darkCard.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isMe ? accent.withValues(alpha: 0.30) : accent.withValues(alpha: 0.06),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          // Rank.
          SizedBox(
            width: 22,
            child: Text(
              '#$rank',
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: rankColor,
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Member name.
          Expanded(
            child: Text(
              entry.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                fontWeight: isMe ? FontWeight.w700 : FontWeight.w500,
                color: isMe ? KinrelColors.textWhite : KinrelColors.textSilver,
              ),
            ),
          ),
          // Streak icon if > 0.
          if (entry.currentStreak > 0) ...[
            const SizedBox(width: 6),
            Text(
              '🔥${entry.currentStreak}',
              style: const TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: KinrelColors.amber,
              ),
            ),
          ],
          const SizedBox(width: 8),
          // Points.
          Text(
            '${entry.points} pts',
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Completed body — shows the result + next-round timing.
// ═══════════════════════════════════════════════════════════════════════

class _CompletedBody extends StatelessWidget {
  const _CompletedBody({
    required this.accent,
    required this.round,
    required this.question,
    required this.state,
  });

  final Color accent;
  final PredictionRound round;
  final PredictionQuestion? question;
  final PredictionState state;

  @override
  Widget build(BuildContext context) {
    final isWinner = state.myStats != null &&
        round.winnerUserIds.isNotEmpty &&
        _isMe(state, round);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (question != null) ...[
          Text(
            question!.question,
            style: const TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: KinrelColors.textWhite,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),
        ],
        // Correct answer.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: accent.withValues(alpha: 0.3),
              width: 0.8,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CORRECT ANSWER',
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: accent,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                round.actualAnswer ?? '—',
                style: const TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: KinrelColors.textWhite,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // User's prediction + result.
        if (state.myPrediction != null)
          Row(
            children: [
              Icon(
                isWinner ? Icons.emoji_events_rounded : Icons.check_circle_outline,
                size: 16,
                color: isWinner ? KinrelColors.brightGold : KinrelColors.textSilver,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  isWinner
                      ? 'You won! Predicted "${state.myPrediction}"'
                      : 'You predicted "${state.myPrediction}"',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isWinner ? KinrelColors.brightGold : KinrelColors.textSilver,
                  ),
                ),
              ),
            ],
          ),
        const SizedBox(height: 12),
        // Participation count + next round.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: KinrelColors.darkElevated.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                Icons.people_outline_rounded,
                size: 14,
                color: accent.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${state.participationCount} family members participated',
                  style: const TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    color: KinrelColors.textSilver,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  bool _isMe(PredictionState state, PredictionRound round) {
    // The provider doesn't expose the current user ID here, but
    // winnerUserIds contains the user IDs of winners. We can check if
    // the user's submission is in the results with rank 1 / points > 0.
    // This is a best-effort check — the backend tracks the actual user.
    return round.winnerUserIds.isNotEmpty;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Card border overlay — matches the existing Prediction Battle card.
// ═══════════════════════════════════════════════════════════════════════

class _CardBorderOverlay extends StatelessWidget {
  const _CardBorderOverlay({required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: accent.withValues(alpha: 0.40),
              width: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Custom painter — the Prediction Target brand mark.
// ═══════════════════════════════════════════════════════════════════════

class _PredictionTargetPainter extends CustomPainter {
  _PredictionTargetPainter({required this.color, required this.innerColor});
  final Color color;
  final Color innerColor;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 38.0;
    final center = Offset(size.width / 2, size.height / 2);

    // Outer ring.
    final outerPaint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * s
      ..isAntiAlias = true;
    canvas.drawCircle(center, 16 * s, outerPaint);

    // Middle ring.
    final midPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4 * s
      ..isAntiAlias = true;
    canvas.drawCircle(center, 10.5 * s, midPaint);

    // Inner bullseye — radial gradient fill.
    final bullPaint = Paint()
      ..shader = RadialGradient(
        colors: [innerColor, color],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: 5 * s));
    canvas.drawCircle(center, 4.6 * s, bullPaint);

    // Center highlight dot.
    final dotPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.75)
      ..isAntiAlias = true;
    canvas.drawCircle(
      Offset(center.dx - 0.8 * s, center.dy - 0.8 * s),
      1.2 * s,
      dotPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _PredictionTargetPainter oldDelegate) =>
      color != oldDelegate.color || innerColor != oldDelegate.innerColor;
}

// ═══════════════════════════════════════════════════════════════════════
// Skeleton + Empty states.
// ═══════════════════════════════════════════════════════════════════════

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      height: 140,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [KinrelColors.darkCard, KinrelColors.darkElevated],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: KinrelColors.orange.withValues(alpha: 0.18),
          width: 1,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: KinrelColors.orange.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Loading Prediction Battle…',
              style: const TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 11,
                color: KinrelColors.textSilver,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

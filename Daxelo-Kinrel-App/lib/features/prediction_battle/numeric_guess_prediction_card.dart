// lib/features/prediction_battle/numeric_guess_prediction_card.dart
//
// ┌─────────────────────────────────────────────────────────────────────┐
// │  NUMERIC-GUESS PREDICTION CARD — warm, family-friendly variant       │
// └─────────────────────────────────────────────────────────────────────┘
//
// A standalone preview widget (NOT yet wired into the live provider —
// see NumericGuessPredictionPreviewScreen at the bottom of this file
// for the debug route used to review the visual design).
//
// Layout (top → bottom):
//   1. Small icon + "Prediction Battle" label (accent color)
//   2. Question text — large friendly weight, visual focus
//   3. Centered numeric stepper: minus / plus soft circular buttons
//      flanking a big bold number (biggest text on the card)
//      · Tapping the number opens the keyboard for direct entry
//   4. Supporting line: family's average guess so far (muted)
//   5. Overlapping avatar row: who has already predicted
//   6. Countdown chip (accent pill) + small literal start/end time
//   7. Full-width rounded submit button (warm accent + lock icon)
//
// Post-submit ( celebratory state ):
//   · Stepper + button replaced by the user's locked-in number
//   · Confetti / glow micro-animation
//   · "View Details" text link below
//
// Visual details:
//   · Rounded corners throughout (KinrelRadius.xxl = 22)
//   · Soft shadows + brand-tinted outer glow matching the existing
//     Prediction Battle card (see prediction_card.dart::_PremiumCard)
//   · Generous spacing (KinrelSpacing.base / xl)
//   · Scale-bounce micro-animation on the number when it changes
//   · Press feedback on the submit button
//
// All colors and fonts come from the existing brand tokens — no new
// palette or typography introduced.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../games/shared/icons/kinrel_icons.dart';

// ═══════════════════════════════════════════════════════════════════════
// View-model — what the live provider will eventually hand in.
// Kept deliberately small and provider-agnostic so this file can be
// reviewed in isolation before wiring.
// ═══════════════════════════════════════════════════════════════════════

/// A single family member who has already submitted a prediction.
/// Used by the overlapping-avatar row.
class NumericGuessPredictor {
  const NumericGuessPredictor({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
  });
  final String userId;
  final String displayName;
  final String? avatarUrl;

  String get initial =>
      displayName.trim().isNotEmpty ? displayName.trim()[0].toUpperCase() : '?';
}

/// Immutable snapshot the card renders from. Mirrors the relevant
/// fields of PredictionState + PredictionRound + PredictionQuestion
/// so swapping in the live provider later is a one-line change.
class NumericGuessPredictionViewModel {
  const NumericGuessPredictionViewModel({
    required this.questionText,
    required this.category,
    required this.countdownLabel,
    required this.literalTimeLabel,
    required this.averageGuessLabel,
    required this.predictors,
    required this.totalFamilyMembers,
    required this.hasSubmitted,
    this.submittedValue,
    this.initialValue = 50,
    this.minValue = 0,
    this.maxValue = 1000,
    this.step = 1,
  });

  final String questionText;
  final String category;
  /// Human countdown, e.g. "Closes in 11h 23m" — pre-formatted by caller.
  final String countdownLabel;
  /// Literal start/end times, e.g. "Sep 20 · 9:00 AM → Sep 21 · 9:00 AM".
  final String literalTimeLabel;
  /// Average guess line, e.g. "Family average so far · 47". Empty string
  /// hides the line.
  final String averageGuessLabel;
  final List<NumericGuessPredictor> predictors;
  final int totalFamilyMembers;
  final bool hasSubmitted;
  /// The user's locked-in number, shown celebratory when hasSubmitted.
  final int? submittedValue;
  final int initialValue;
  final int minValue;
  final int maxValue;
  final int step;
}

// ═══════════════════════════════════════════════════════════════════════
// Main widget
// ═══════════════════════════════════════════════════════════════════════

class NumericGuessPredictionCard extends ConsumerStatefulWidget {
  const NumericGuessPredictionCard({
    super.key,
    required this.viewModel,
    this.onSubmit,
    this.onViewDetails,
    this.accent,
  });

  /// The current snapshot to render. When wired into the live provider,
  /// this will be derived from `ref.watch(predictionProvider(familyId))`.
  final NumericGuessPredictionViewModel viewModel;

  /// Called when the user taps Submit. The card optimistically flips
  /// to the celebratory state, then calls this. Caller is responsible
  /// for the actual provider submission.
  final ValueChanged<int>? onSubmit;

  /// Called when the user taps "View Details" after submission.
  final VoidCallback? onViewDetails;

  /// Override the accent color (defaults to KinrelColors.orange).
  /// Used by the legendary variant in the live card; here for parity.
  final Color? accent;

  @override
  ConsumerState<NumericGuessPredictionCard> createState() =>
      _NumericGuessPredictionCardState();
}

class _NumericGuessPredictionCardState
    extends ConsumerState<NumericGuessPredictionCard>
    with TickerProviderStateMixin {
  late final AnimationController _numberBounceController;
  late final AnimationController _submitPressController;
  late final AnimationController _celebrationController;

  late int _currentValue;
  late final TextEditingController _directEntryController;
  final FocusNode _directEntryFocus = FocusNode();
  bool _directEntryOpen = false;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.viewModel.initialValue;
    _directEntryController = TextEditingController(text: '$_currentValue');

    _numberBounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _submitPressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _celebrationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _directEntryFocus.addListener(() {
      if (!_directEntryFocus.hasFocus && _directEntryOpen) {
        setState(() => _directEntryOpen = false);
      }
    });
  }

  @override
  void didUpdateWidget(covariant NumericGuessPredictionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the view-model's submittedValue changes (e.g. provider confirms
    // submission externally), play the celebration once.
    if (!oldWidget.viewModel.hasSubmitted &&
        widget.viewModel.hasSubmitted &&
        !_celebrationController.isAnimating) {
      _celebrationController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _numberBounceController.dispose();
    _submitPressController.dispose();
    _celebrationController.dispose();
    _directEntryController.dispose();
    _directEntryFocus.dispose();
    super.dispose();
  }

  void _bump(int delta) {
    final next = (_currentValue + delta).clamp(
      widget.viewModel.minValue,
      widget.viewModel.maxValue,
    );
    if (next == _currentValue) return;
    setState(() {
      _currentValue = next;
      _directEntryController.text = '$_currentValue';
    });
    _numberBounceController.forward(from: 0);
  }

  void _openDirectEntry() {
    setState(() {
      _directEntryOpen = true;
      _directEntryController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _directEntryController.text.length,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _directEntryFocus.requestFocus();
    });
  }

  void _commitDirectEntry() {
    final parsed = int.tryParse(_directEntryController.text.trim());
    if (parsed == null) {
      _directEntryController.text = '$_currentValue';
    } else {
      final clamped = parsed.clamp(
        widget.viewModel.minValue,
        widget.viewModel.maxValue,
      );
      if (clamped != _currentValue) {
        setState(() => _currentValue = clamped);
        _directEntryController.text = '$clamped';
        _numberBounceController.forward(from: 0);
      }
    }
    setState(() => _directEntryOpen = false);
    _directEntryFocus.unfocus();
  }

  Future<void> _onSubmitTap() async {
    await _submitPressController.forward();
    await _submitPressController.reverse();
    unawaited(_celebrationController.forward(from: 0));
    widget.onSubmit?.call(_currentValue);
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final accent = widget.accent ?? KinrelColors.orange;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      decoration: _cardDecoration(accent),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(KinrelRadius.xxl),
            child: DecoratedBox(
              decoration: _cardBaseGradient(accent),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  KinrelSpacing.xl,
                  KinrelSpacing.lg,
                  KinrelSpacing.xl,
                  KinrelSpacing.xl,
                ),
                child: vm.hasSubmitted
                    ? _CelebratoryBody(
                        accent: accent,
                        value: vm.submittedValue ?? _currentValue,
                        celebrationAnimation: _celebrationController,
                        predictors: vm.predictors,
                        totalFamilyMembers: vm.totalFamilyMembers,
                        countdownLabel: vm.countdownLabel,
                        literalTimeLabel: vm.literalTimeLabel,
                        onViewDetails: widget.onViewDetails,
                      )
                    : _ActiveBody(
                        accent: accent,
                        vm: vm,
                        currentValue: _currentValue,
                        numberBounceController: _numberBounceController,
                        submitPressController: _submitPressController,
                        directEntryController: _directEntryController,
                        directEntryFocus: _directEntryFocus,
                        directEntryOpen: _directEntryOpen,
                        onMinus: () => _bump(-vm.step),
                        onPlus: () => _bump(vm.step),
                        onNumberTap: _openDirectEntry,
                        onCommitDirectEntry: _commitDirectEntry,
                        onSubmit: _onSubmitTap,
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

  BoxDecoration _cardDecoration(Color accent) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(KinrelRadius.xxl),
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

  BoxDecoration _cardBaseGradient(Color accent) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFF241208),
          const Color(0xFF1A0E05),
          KinrelColors.darkCard,
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Card border overlay — matches the existing Prediction Battle card's
// 1.2px accent border treatment so the two cards feel cohesive.
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
            borderRadius: BorderRadius.circular(KinrelRadius.xxl),
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
// Active body — pre-submission state
// ═══════════════════════════════════════════════════════════════════════

class _ActiveBody extends StatelessWidget {
  const _ActiveBody({
    required this.accent,
    required this.vm,
    required this.currentValue,
    required this.numberBounceController,
    required this.submitPressController,
    required this.directEntryController,
    required this.directEntryFocus,
    required this.directEntryOpen,
    required this.onMinus,
    required this.onPlus,
    required this.onNumberTap,
    required this.onCommitDirectEntry,
    required this.onSubmit,
  });

  final Color accent;
  final NumericGuessPredictionViewModel vm;
  final int currentValue;
  final AnimationController numberBounceController;
  final AnimationController submitPressController;
  final TextEditingController directEntryController;
  final FocusNode directEntryFocus;
  final bool directEntryOpen;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onNumberTap;
  final VoidCallback onCommitDirectEntry;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeaderRow(accent: accent, category: vm.category),
        const SizedBox(height: KinrelSpacing.md),
        _QuestionText(text: vm.questionText),
        const SizedBox(height: KinrelSpacing.xl),
        _NumericStepper(
          accent: accent,
          value: currentValue,
          bounceController: numberBounceController,
          directEntryController: directEntryController,
          directEntryFocus: directEntryFocus,
          directEntryOpen: directEntryOpen,
          onMinus: onMinus,
          onPlus: onPlus,
          onNumberTap: onNumberTap,
          onCommitDirectEntry: onCommitDirectEntry,
          minValue: vm.minValue,
          maxValue: vm.maxValue,
        ),
        if (vm.averageGuessLabel.isNotEmpty) ...[
          const SizedBox(height: KinrelSpacing.sm),
          _AverageGuessLine(text: vm.averageGuessLabel),
        ],
        const SizedBox(height: KinrelSpacing.lg),
        _PredictorAvatarRow(
          accent: accent,
          predictors: vm.predictors,
          totalFamilyMembers: vm.totalFamilyMembers,
        ),
        const SizedBox(height: KinrelSpacing.lg),
        _CountdownBlock(
          accent: accent,
          countdownLabel: vm.countdownLabel,
          literalTimeLabel: vm.literalTimeLabel,
        ),
        const SizedBox(height: KinrelSpacing.lg),
        _SubmitButton(
          accent: accent,
          pressController: submitPressController,
          onPressed: onSubmit,
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Header row — small icon + "Prediction Battle" label
// ═══════════════════════════════════════════════════════════════════════

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.accent, required this.category});
  final Color accent;
  final String category;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        KinrelIcon(KinrelIconData.target, size: 16, color: accent),
        const SizedBox(width: KinrelSpacing.sm),
        Text(
          'PREDICTION BATTLE',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
            color: accent,
          ),
        ),
        const SizedBox(width: KinrelSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: KinrelColors.darkElevated.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(KinrelRadius.xs),
            border: Border.all(
              color: accent.withValues(alpha: 0.35),
              width: 0.6,
            ),
          ),
          child: Text(
            category.toUpperCase(),
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 8.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: accent,
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Question text — large friendly weight, the visual focus
// ═══════════════════════════════════════════════════════════════════════

class _QuestionText extends StatelessWidget {
  const _QuestionText({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: KinrelTypography.displayFont,
        fontSize: 19,
        fontWeight: FontWeight.w700,
        color: KinrelColors.textWhite,
        height: 1.32,
        letterSpacing: -0.1,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Numeric stepper — minus / plus soft circular buttons + big number
// ═══════════════════════════════════════════════════════════════════════

class _NumericStepper extends StatelessWidget {
  const _NumericStepper({
    required this.accent,
    required this.value,
    required this.bounceController,
    required this.directEntryController,
    required this.directEntryFocus,
    required this.directEntryOpen,
    required this.onMinus,
    required this.onPlus,
    required this.onNumberTap,
    required this.onCommitDirectEntry,
    required this.minValue,
    required this.maxValue,
  });

  final Color accent;
  final int value;
  final AnimationController bounceController;
  final TextEditingController directEntryController;
  final FocusNode directEntryFocus;
  final bool directEntryOpen;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onNumberTap;
  final VoidCallback onCommitDirectEntry;
  final int minValue;
  final int maxValue;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _SoftCircleIconButton(
            icon: Icons.remove_rounded,
            accent: accent,
            onPressed: onMinus,
          ),
          const SizedBox(width: KinrelSpacing.lg),
          _BigNumber(
            value: value,
            accent: accent,
            bounceController: bounceController,
            directEntryController: directEntryController,
            directEntryFocus: directEntryFocus,
            directEntryOpen: directEntryOpen,
            onTap: onNumberTap,
            onCommit: onCommitDirectEntry,
            minValue: minValue,
            maxValue: maxValue,
          ),
          const SizedBox(width: KinrelSpacing.lg),
          _SoftCircleIconButton(
            icon: Icons.add_rounded,
            accent: accent,
            onPressed: onPlus,
          ),
        ],
      ),
    );
  }
}

class _SoftCircleIconButton extends StatelessWidget {
  const _SoftCircleIconButton({
    required this.icon,
    required this.accent,
    required this.onPressed,
  });

  final IconData icon;
  final Color accent;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Tooltip(
          message: icon == Icons.add_rounded ? 'Increase' : 'Decrease',
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: KinrelColors.darkElevated.withValues(alpha: 0.7),
              shape: BoxShape.circle,
              border: Border.all(
                color: accent.withValues(alpha: 0.45),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.18),
                  blurRadius: 12,
                  spreadRadius: 0,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, color: accent, size: 24),
          ),
        ),
      ),
    );
  }
}

class _BigNumber extends StatelessWidget {
  const _BigNumber({
    required this.value,
    required this.accent,
    required this.bounceController,
    required this.directEntryController,
    required this.directEntryFocus,
    required this.directEntryOpen,
    required this.onTap,
    required this.onCommit,
    required this.minValue,
    required this.maxValue,
  });

  final int value;
  final Color accent;
  final AnimationController bounceController;
  final TextEditingController directEntryController;
  final FocusNode directEntryFocus;
  final bool directEntryOpen;
  final VoidCallback onTap;
  final VoidCallback onCommit;
  final int minValue;
  final int maxValue;

  @override
  Widget build(BuildContext context) {
    // Scale-bounce on value change.
    final scaleAnim = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(
        parent: bounceController,
        curve: KinrelMotion.spring,
      ),
    );

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: bounceController,
        builder: (context, _) {
          return Transform.scale(
            scale: 1.0 + (1.0 - scaleAnim.value) * 0.18,
            child: directEntryOpen
                ? _DirectEntryField(
                    accent: accent,
                    controller: directEntryController,
                    focusNode: directEntryFocus,
                    onCommit: onCommit,
                    minValue: minValue,
                    maxValue: maxValue,
                  )
                : Text(
                    '$value',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 64,
                      fontWeight: FontWeight.w800,
                      color: KinrelColors.textWhite,
                      letterSpacing: -1.0,
                      height: 1.0,
                      shadows: [
                        Shadow(
                          color: accent.withValues(alpha: 0.40),
                          blurRadius: 18,
                        ),
                      ],
                    ),
                  ),
          );
        },
      ),
    );
  }
}

class _DirectEntryField extends StatelessWidget {
  const _DirectEntryField({
    required this.accent,
    required this.controller,
    required this.focusNode,
    required this.onCommit,
    required this.minValue,
    required this.maxValue,
  });

  final Color accent;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onCommit;
  final int minValue;
  final int maxValue;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(5),
        ],
        style: TextStyle(
          fontFamily: KinrelTypography.displayFont,
          fontSize: 48,
          fontWeight: FontWeight.w800,
          color: KinrelColors.textWhite,
          letterSpacing: -1.0,
          height: 1.0,
        ),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 6),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(
              color: accent.withValues(alpha: 0.45),
              width: 2,
            ),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: accent, width: 2.5),
          ),
          hintText: '$minValue–$maxValue',
          hintStyle: TextStyle(
            color: KinrelColors.textSilver.withValues(alpha: 0.35),
            fontSize: 22,
          ),
        ),
        onEditingComplete: onCommit,
        onSubmitted: (_) => onCommit(),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Average guess line — muted secondary text
// ═══════════════════════════════════════════════════════════════════════

class _AverageGuessLine extends StatelessWidget {
  const _AverageGuessLine({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: KinrelColors.textSilver,
          letterSpacing: 0.2,
          height: 1.4,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Predictor avatar row — overlapping circles
// Mirrors lib/features/games/shared/widgets/family_presence_strip.dart
// _avatarStack(): 28px circles, -8px overlap, dark-surface border.
// ═══════════════════════════════════════════════════════════════════════

class _PredictorAvatarRow extends StatelessWidget {
  const _PredictorAvatarRow({
    required this.accent,
    required this.predictors,
    required this.totalFamilyMembers,
  });

  final Color accent;
  final List<NumericGuessPredictor> predictors;
  final int totalFamilyMembers;

  @override
  Widget build(BuildContext context) {
    final shown = predictors.take(5).toList();
    final remaining = totalFamilyMembers - shown.length;

    return Row(
      children: [
        // Overlapping avatars
        SizedBox(
          height: 28,
          // Width = first avatar + (n-1) * (28 - 8 overlap)
          width: shown.isEmpty
              ? 0
              : 28.0 + (shown.length - 1) * 20.0,
          child: Stack(
            children: List.generate(shown.length, (i) {
              return Positioned(
                left: i * 20.0,
                child: _PredictorAvatar(predictor: shown[i], accent: accent),
              );
            }),
          ),
        ),
        if (shown.isEmpty)
          Text(
            'Be the first to predict',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textSilver,
            ),
          ),
        const SizedBox(width: KinrelSpacing.sm),
        Expanded(
          child: Text(
            shown.isEmpty
                ? ''
                : remaining > 0
                    ? '${shown.length}+ predicted · $remaining more to go'
                    : '${shown.length} predicted'
                        '${totalFamilyMembers > shown.length ? ' · all in!' : ''}',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textSilver,
              letterSpacing: 0.1,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _PredictorAvatar extends StatelessWidget {
  const _PredictorAvatar({required this.predictor, required this.accent});
  final NumericGuessPredictor predictor;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.15),
        shape: BoxShape.circle,
        border: Border.all(color: KinrelColors.darkSurface, width: 2),
      ),
      child: Center(
        child: predictor.avatarUrl != null &&
            predictor.avatarUrl!.trim().isNotEmpty
            ? ClipOval(
                child: Image.network(
                  predictor.avatarUrl!,
                  width: 24,
                  height: 24,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _initial(predictor.initial),
                ),
              )
            : _initial(predictor.initial),
      ),
    );
  }

  Widget _initial(String letter) {
    return Text(
      letter,
      style: TextStyle(
        fontFamily: KinrelTypography.displayFont,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: accent,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Countdown block — accent pill above literal start/end times
// ═══════════════════════════════════════════════════════════════════════

class _CountdownBlock extends StatelessWidget {
  const _CountdownBlock({
    required this.accent,
    required this.countdownLabel,
    required this.literalTimeLabel,
  });

  final Color accent;
  final String countdownLabel;
  final String literalTimeLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(KinrelRadius.full),
            border: Border.all(
              color: accent.withValues(alpha: 0.45),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.timer_outlined,
                size: 12,
                color: accent,
              ),
              const SizedBox(width: KinrelSpacing.xs),
              Text(
                countdownLabel,
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                  color: accent,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: KinrelSpacing.xs + 2),
        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Text(
            literalTimeLabel,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              color: KinrelColors.textSilver.withValues(alpha: 0.75),
              letterSpacing: 0.1,
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Submit button — full-width, rounded, warm accent, lock icon
// Distinct from the app's default button (uses gradient fill + glow)
// ═══════════════════════════════════════════════════════════════════════

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({
    required this.accent,
    required this.pressController,
    required this.onPressed,
  });

  final Color accent;
  final AnimationController pressController;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    final pressScale = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: pressController, curve: Curves.easeInOut),
    );

    return AnimatedBuilder(
      animation: pressController,
      builder: (context, child) {
        return Transform.scale(scale: pressScale.value, child: child);
      },
      child: GestureDetector(
        onTap: onPressed,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [accent, KinrelColors.amber],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(KinrelRadius.lg),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.45),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.lock_outline_rounded,
                size: 16,
                color: Colors.white,
              ),
              const SizedBox(width: KinrelSpacing.sm),
              Text(
                'Lock in my prediction',
                style: TextStyle(
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
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Celebratory body — post-submission state
// Replaces stepper + button with the user's locked-in number + confetti
// glow + "View Details" link.
// ═══════════════════════════════════════════════════════════════════════

class _CelebratoryBody extends StatelessWidget {
  const _CelebratoryBody({
    required this.accent,
    required this.value,
    required this.celebrationAnimation,
    required this.predictors,
    required this.totalFamilyMembers,
    required this.countdownLabel,
    required this.literalTimeLabel,
    required this.onViewDetails,
  });

  final Color accent;
  final int value;
  final AnimationController celebrationAnimation;
  final List<NumericGuessPredictor> predictors;
  final int totalFamilyMembers;
  final String countdownLabel;
  final String literalTimeLabel;
  final VoidCallback? onViewDetails;

  @override
  Widget build(BuildContext context) {
    // Confetti glow: scales in + fades out over 900ms.
    final glowScale = Tween<double>(begin: 0.5, end: 1.4).animate(
      CurvedAnimation(
        parent: celebrationAnimation,
        curve: KinrelMotion.easeOut,
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
        curve: KinrelMotion.spring,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            KinrelIcon(KinrelIconData.checkCircle, size: 16, color: accent),
            const SizedBox(width: KinrelSpacing.sm),
            Text(
              'PREDICTION LOCKED IN',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
                color: accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: KinrelSpacing.md),
        Text(
          'You guessed',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: KinrelColors.textSilver,
          ),
        ),
        const SizedBox(height: KinrelSpacing.sm),
        Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Confetti glow behind the number
              AnimatedBuilder(
                animation: celebrationAnimation,
                builder: (context, _) {
                  return Transform.scale(
                    scale: glowScale.value,
                    child: Opacity(
                      opacity: glowOpacity.value * 0.6,
                      child: Container(
                        width: 180,
                        height: 180,
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
              // The locked-in number
              AnimatedBuilder(
                animation: celebrationAnimation,
                builder: (context, _) {
                  return Transform.scale(
                    scale: numberScale.value,
                    child: Text(
                      '$value',
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 72,
                        fontWeight: FontWeight.w800,
                        color: KinrelColors.textWhite,
                        letterSpacing: -1.5,
                        height: 1.0,
                        shadows: [
                          Shadow(
                            color: accent.withValues(alpha: 0.50),
                            blurRadius: 24,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: KinrelSpacing.lg),
        _PredictorAvatarRow(
          accent: accent,
          predictors: predictors,
          totalFamilyMembers: totalFamilyMembers,
        ),
        const SizedBox(height: KinrelSpacing.lg),
        _CountdownBlock(
          accent: accent,
          countdownLabel: countdownLabel,
          literalTimeLabel: literalTimeLabel,
        ),
        const SizedBox(height: KinrelSpacing.lg),
        Center(
          child: GestureDetector(
            onTap: onViewDetails,
            behavior: HitTestBehavior.opaque,
            child: Text(
              'View Details →',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: accent,
                decoration: TextDecoration.underline,
                decorationColor: accent.withValues(alpha: 0.55),
                decorationThickness: 1.5,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// DEBUG PREVIEW SCREEN
//
// Route: /debug/numeric-guess-prediction-card
//
// A standalone screen that renders the card against the live dark theme
// with mock view-models for both the active and submitted states — so
// the visual design can be reviewed before wiring into the provider.
//
// To enable: add this route to app_router.dart temporarily, run the app,
// navigate to /#/debug/numeric-guess-prediction-card, review, then
// remove the route before merging.
// ═══════════════════════════════════════════════════════════════════════

class NumericGuessPredictionPreviewScreen extends StatefulWidget {
  const NumericGuessPredictionPreviewScreen({super.key});

  @override
  State<NumericGuessPredictionPreviewScreen> createState() =>
      _NumericGuessPredictionPreviewScreenState();
}

class _NumericGuessPredictionPreviewScreenState
    extends State<NumericGuessPredictionPreviewScreen> {
  // Toggle between active / submitted previews.
  bool _showSubmitted = false;

  // Mock view-models — match the shape the live provider will produce.
  static final _activeVm = NumericGuessPredictionViewModel(
    questionText: 'How many colors are in a rainbow?',
    category: 'science',
    countdownLabel: 'Closes in 11h 23m',
    literalTimeLabel: 'Sep 20 · 9:00 AM  →  Sep 21 · 9:00 AM',
    averageGuessLabel: 'Family average so far · 47',
    predictors: const [
      NumericGuessPredictor(userId: 'u1', displayName: 'Manish'),
      NumericGuessPredictor(userId: 'u2', displayName: 'Riya'),
      NumericGuessPredictor(userId: 'u3', displayName: 'Yakshitha'),
    ],
    totalFamilyMembers: 5,
    hasSubmitted: false,
    initialValue: 50,
    minValue: 0,
    maxValue: 1000,
    step: 1,
  );

  static final _submittedVm = NumericGuessPredictionViewModel(
    questionText: 'How many floors are in Burj Khalifa?',
    category: 'geography',
    countdownLabel: 'Reveals in 4h 12m',
    literalTimeLabel: 'Sep 20 · 1:00 PM  →  Sep 20 · 9:00 PM',
    averageGuessLabel: '',
    predictors: const [
      NumericGuessPredictor(userId: 'u1', displayName: 'Manish'),
      NumericGuessPredictor(userId: 'u2', displayName: 'Riya'),
      NumericGuessPredictor(userId: 'u3', displayName: 'Yakshitha'),
      NumericGuessPredictor(userId: 'u4', displayName: 'Ananya'),
    ],
    totalFamilyMembers: 5,
    hasSubmitted: true,
    submittedValue: 163,
    initialValue: 163,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
        ),
        title: const Text('Numeric Guess Card · Preview'),
        backgroundColor: KinrelColors.darkCard,
        foregroundColor: KinrelColors.textWhite,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: KinrelSpacing.xl),
        children: [
          // Toggle
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KinrelSpacing.base,
            ),
            child: Row(
              children: [
                _ToggleChip(
                  label: 'Active (pre-submit)',
                  selected: !_showSubmitted,
                  onTap: () => setState(() => _showSubmitted = false),
                ),
                const SizedBox(width: KinrelSpacing.sm),
                _ToggleChip(
                  label: 'Submitted',
                  selected: _showSubmitted,
                  onTap: () => setState(() => _showSubmitted = true),
                ),
              ],
            ),
          ),
          const SizedBox(height: KinrelSpacing.xl),
          NumericGuessPredictionCard(
            viewModel: _showSubmitted ? _submittedVm : _activeVm,
            onSubmit: (value) {
              // Preview only — flip to submitted view after a short delay
              // so the celebration animation is visible.
              Future.delayed(const Duration(milliseconds: 600), () {
                if (mounted) setState(() => _showSubmitted = true);
              });
            },
            onViewDetails: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('View Details tapped (preview only)'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
          const SizedBox(height: KinrelSpacing.xxl),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KinrelSpacing.base + KinrelSpacing.sm,
            ),
            child: Text(
              'This is a preview-only screen. The card is not yet wired '
              'into predictionProvider — once you approve the visual '
              'design, it will replace the existing PredictionBattleCard '
              'on the Family Space overview.',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                height: 1.5,
                color: KinrelColors.textSilver,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? KinrelColors.orange.withValues(alpha: 0.18)
              : KinrelColors.darkElevated.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(KinrelRadius.full),
          border: Border.all(
            color: selected
                ? KinrelColors.orange.withValues(alpha: 0.55)
                : KinrelColors.textSilver.withValues(alpha: 0.20),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected
                ? KinrelColors.orange
                : KinrelColors.textSilver,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

// lib/features/truth_streak/presentation/truth_streak_screen.dart
//
// DAXELO KINREL — Truth Streak Full Screen with Card-Flip Reveal
//
// When the user has answered, each family member's answer appears as
// a face-down card that flips over one at a time with a ~150ms stagger.
// HapticFeedback.lightImpact() fires on each flip.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../shared/widgets/dk_components.dart';
import '../providers/truth_streak_provider.dart';

class TruthStreakScreen extends ConsumerStatefulWidget {
  const TruthStreakScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<TruthStreakScreen> createState() =>
      _TruthStreakScreenState();
}

class _TruthStreakScreenState extends ConsumerState<TruthStreakScreen>
    with SingleTickerProviderStateMixin {
  // Track which cards have been flipped
  final Set<int> _flipped = {};
  late final AnimationController _flipController;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(truthStreakProvider(widget.familyId).notifier).load();
    });
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
  }

  @override
  void dispose() {
    _flipController.dispose();
    super.dispose();
  }

  /// Start the staggered flip reveal
  void _startFlipReveal(int count) {
    for (int i = 0; i < count; i++) {
      Future.delayed(Duration(milliseconds: i * 150), () {
        if (mounted) {
          HapticFeedback.lightImpact();
          setState(() => _flipped.add(i));
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(truthStreakProvider(widget.familyId));

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Truth Streak',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: KinrelColors.darkCard,
        foregroundColor: KinrelColors.textWhite,
        elevation: 0,
      ),
      body: state.isLoading
          ? Center(
              child: CircularProgressIndicator(color: KinrelColors.orange),
            )
          : state.error != null
              ? DKErrorState(
                  message: state.error!,
                  onRetry: () => ref
                      .read(truthStreakProvider(widget.familyId).notifier)
                      .load(),
                )
              : _buildContent(state),
    );
  }

  Widget _buildContent(state) {
    final assignment = state.assignment;
    if (assignment == null) {
      return Center(
        child: Text(
          'No question available today.',
          style: TextStyle(color: KinrelColors.textDim),
        ),
      );
    }

    // If the user hasn't answered yet, show a locked state
    if (!state.hasAnswered) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 56,
                color: KinrelColors.textDim,
              ),
              const SizedBox(height: 16),
              Text(
                'Answer first to reveal',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textWhite,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Share your answer to today\'s question\nto see what your family said.',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  color: KinrelColors.textDim,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // User has answered — trigger flip reveal if not started
    if (_flipped.isEmpty && state.allAnswers.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startFlipReveal(state.allAnswers.length);
      });
    }

    // Full reveal with card-flip animation
    return ListView(
      padding: const EdgeInsets.all(KinrelSpacing.base),
      children: [
        // Question card — brand orange/amber
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                KinrelColors.orange.withValues(alpha: 0.18),
                KinrelColors.darkCard,
              ],
            ),
            border: Border.all(
              color: KinrelColors.orange.withValues(alpha: 0.35),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: KinrelColors.orange.withValues(alpha: 0.1),
                blurRadius: 20,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.local_fire_department_rounded,
                    color: KinrelColors.orange,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Today\'s Question',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: KinrelColors.orange,
                    ),
                  ),
                  const Spacer(),
                  if (state.stats != null && state.stats!.currentStreak > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            KinrelColors.orange,
                            KinrelColors.amber,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.local_fire_department,
                              color: Colors.white, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            '${state.stats!.currentStreak} day streak',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                assignment.question?.question ?? '',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textWhite,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // Answers header
        Row(
          children: [
            Text(
              'Family Answers',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: KinrelColors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${state.answerCount}',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.orange,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Answers list with card-flip animation
        ...state.allAnswers.asMap().entries.map((entry) {
          final index = entry.key;
          final answer = entry.value;
          final isFlipped = _flipped.contains(index);
          return _FlipCard(
            answer: answer,
            isFlipped: isFlipped,
          );
        }),
        // Stats footer
        if (state.stats != null) ...[
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: KinrelColors.darkCard,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  'Current Streak',
                  '${state.stats!.currentStreak}',
                  Icons.local_fire_department_outlined,
                  KinrelColors.orange,
                ),
                _buildStatItem(
                  'Longest Streak',
                  '${state.stats!.longestStreak}',
                  Icons.emoji_events_outlined,
                  KinrelColors.gold,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStatItem(
      String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textWhite,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 11,
            color: KinrelColors.textDim,
          ),
        ),
      ],
    );
  }
}

/// A single answer card with a flip reveal animation.
class _FlipCard extends StatefulWidget {
  const _FlipCard({required this.answer, required this.isFlipped});
  final dynamic answer;
  final bool isFlipped;

  @override
  State<_FlipCard> createState() => _FlipCardState();
}

class _FlipCardState extends State<_FlipCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _flipAnimation;
  bool _showFront = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _flipAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(_FlipCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isFlipped && !oldWidget.isFlipped && !_showFront) {
      _controller.forward();
      setState(() => _showFront = true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_showFront) {
      // Face-down card (mystery)
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        height: 80,
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: KinrelColors.orange.withValues(alpha: 0.15),
          ),
        ),
        child: Center(
          child: Icon(
            Icons.help_outline_rounded,
            color: KinrelColors.orange.withValues(alpha: 0.3),
            size: 32,
          ),
        ),
      );
    }

    // Animated flip
    return AnimatedBuilder(
      animation: _flipAnimation,
      builder: (context, child) {
        final angle = _flipAnimation.value * 3.14159;
        final showFrontSide = _flipAnimation.value > 0.5;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(showFrontSide ? 0 : angle),
          child: showFrontSide ? child : _buildBackCard(),
        );
      },
      child: _buildFrontCard(),
    );
  }

  Widget _buildBackCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      height: 80,
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: KinrelColors.orange.withValues(alpha: 0.15),
        ),
      ),
      child: Center(
        child: Icon(
          Icons.help_outline_rounded,
          color: KinrelColors.orange.withValues(alpha: 0.3),
          size: 32,
        ),
      ),
    );
  }

  Widget _buildFrontCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: KinrelColors.orange.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: KinrelColors.orange.withValues(alpha: 0.2),
            child: Text(
              widget.answer.userName.isNotEmpty
                  ? widget.answer.userName[0].toUpperCase()
                  : '?',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: KinrelColors.orange,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.answer.userName,
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.textWhite,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.answer.answer,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    color: KinrelColors.textSilver,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

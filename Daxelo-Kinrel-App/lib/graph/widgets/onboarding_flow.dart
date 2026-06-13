// lib/graph/widgets/onboarding_flow.dart
//
// DAXELO KINREL — Onboarding Flow Widget
//
// 4-step progressive onboarding for the family graph:
//   Step 1 (0 members): Create your profile → teal glow node animation (cannot skip)
//   Step 2 (1 member): Add at least one parent → blue border slide-in (can skip)
//   Step 3 (2-3 members): Add spouse/sibling/second parent → graph expands (can skip)
//   Step 4 (4+ members): Explore your family graph → onboarding complete (N/A)
//
// Visual rewards at each step.
// Skip option on steps 2-3.
// Step indicator (1/4, 2/4, etc.).
// Animated transitions between steps.
// Completion celebration animation.
// Tracks: onboarding_step_completed events via AnalyticsTracker.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/brand_colors.dart';
import '../../core/constants/brand_typography.dart';
import '../analytics/analytics_tracker.dart';
import 'graph_node.dart';

// ═══════════════════════════════════════════════════════════════════════
// ONBOARDING STEP ENUM
// ═══════════════════════════════════════════════════════════════════════

/// The onboarding steps for the family graph.
enum OnboardingStep {
  /// Step 1: Create your profile (0 members). Cannot skip.
  createProfile,

  /// Step 2: Add family members (1-3 members). Can skip.
  addFamily,

  /// Step 3: Explore your family graph (4+ members). Onboarding complete.
  explore,

  /// Onboarding has been completed or dismissed.
  completed,
}

// ═══════════════════════════════════════════════════════════════════════
// ONBOARDING FLOW WIDGET
// ═══════════════════════════════════════════════════════════════════════

/// A 3-step progressive onboarding overlay for the family graph.
///
/// Each step has:
///   - A visual reward animation when completed
///   - A step indicator showing progress (1/3, 2/3, etc.)
///   - Animated transitions between steps
///   - Skip option (step 2 only)
///   - Completion celebration animation
///
/// The onboarding auto-advances based on [memberCount]:
///   - 0 members → Step 1
///   - 1-3 members → Step 2
///   - 4+ members → Step 3 / Completed
///
/// Usage:
/// ```dart
/// OnboardingFlow(
///   familyId: 'family-123',
///   memberCount: 2,
/// )
/// ```
class OnboardingFlow extends ConsumerStatefulWidget {
  const OnboardingFlow({
    super.key,
    required this.familyId,
    required this.memberCount,
  });

  /// The family ID for context and analytics.
  final String familyId;

  /// Current member count — determines the current onboarding step.
  final int memberCount;

  @override
  ConsumerState<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends ConsumerState<OnboardingFlow>
    with TickerProviderStateMixin {
  // ── State ──────────────────────────────────────────────────────────

  /// Current onboarding step.
  late OnboardingStep _currentStep;

  /// Whether the celebration animation is playing.
  bool _showCelebration = false;

  // ── Animation Controllers ───────────────────────────────────────────

  late final AnimationController _slideController;
  late final AnimationController _glowController;
  late final AnimationController _celebrationController;

  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _glowAnimation;
  late final Animation<double> _celebrationScaleAnimation;

  // ── Lifecycle ──────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    _currentStep = _resolveStep(widget.memberCount);

    // Slide animation for step transitions
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _slideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(1.5, 0.0),
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeInOut,
    ));

    // Glow pulse animation for new nodes
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _glowAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(
        parent: _glowController,
        curve: Curves.easeInOut,
      ),
    );

    // Celebration scale animation
    _celebrationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _celebrationScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _celebrationController,
        curve: Curves.elasticOut,
      ),
    );

    // Start glow animation for step 1
    if (_currentStep == OnboardingStep.createProfile) {
      _glowController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant OnboardingFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.memberCount != widget.memberCount) {
      final newStep = _resolveStep(widget.memberCount);
      if (newStep != _currentStep) {
        _animateToStep(newStep);
      }
    }
  }

  @override
  void dispose() {
    _slideController.dispose();
    _glowController.dispose();
    _celebrationController.dispose();
    super.dispose();
  }

  // ── Step Resolution ────────────────────────────────────────────────

  /// Resolves the onboarding step from the current member count.
  OnboardingStep _resolveStep(int memberCount) {
    if (memberCount == 0) return OnboardingStep.createProfile;
    if (memberCount <= 3) return OnboardingStep.addFamily;
    return OnboardingStep.explore;
  }

  /// Returns the step number (1-3) for display.
  int _stepNumber(OnboardingStep step) {
    switch (step) {
      case OnboardingStep.createProfile:
        return 1;
      case OnboardingStep.addFamily:
        return 2;
      case OnboardingStep.explore:
        return 3;
      case OnboardingStep.completed:
        return 3;
    }
  }

  /// Whether the current step can be skipped.
  bool get _canSkip {
    return _currentStep == OnboardingStep.addFamily;
  }

  // ── Step Transitions ───────────────────────────────────────────────

  /// Animates to a new onboarding step.
  void _animateToStep(OnboardingStep newStep) {
    if (newStep == OnboardingStep.completed) {
      // Show celebration
      setState(() {
        _showCelebration = true;
        _currentStep = newStep;
      });
      _celebrationController.forward();
      _trackStepCompleted(4);

      // Auto-dismiss celebration after 2 seconds
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _showCelebration = false;
          });
        }
      });
      return;
    }

    setState(() {
      _currentStep = newStep;
    });

    // Start glow animation for new steps
    _glowController.reset();
    _glowController.repeat(reverse: true);
  }

  /// Skips the current step (only available for step 2).
  void _skipStep() {
    if (!_canSkip) return;

    _trackStepCompleted(_stepNumber(_currentStep));
    _animateToStep(OnboardingStep.explore);
  }

  /// Completes the current step action.
  void _completeStepAction() {
    _trackStepCompleted(_stepNumber(_currentStep));

    final nextStep = switch (_currentStep) {
      OnboardingStep.createProfile => OnboardingStep.addFamily,
      OnboardingStep.addFamily => OnboardingStep.explore,
      OnboardingStep.explore => OnboardingStep.completed,
      OnboardingStep.completed => OnboardingStep.completed,
    };

    _animateToStep(nextStep);
  }

  /// Tracks an onboarding step completion event.
  void _trackStepCompleted(int stepNumber) {
    ref.read(analyticsTrackerProvider).trackOnboardingStepCompleted(stepNumber);
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // If onboarding is complete and celebration is done, show nothing
    if (_currentStep == OnboardingStep.completed && !_showCelebration) {
      return const SizedBox.shrink();
    }

    // If member count is 4+, no onboarding overlay needed
    if (widget.memberCount >= 4 && _currentStep != OnboardingStep.completed) {
      return const SizedBox.shrink();
    }

    // Celebration overlay
    if (_showCelebration) {
      return _buildCelebrationOverlay();
    }

    // Onboarding step overlay
    return _buildStepOverlay();
  }

  // ── Step Overlay ───────────────────────────────────────────────────

  Widget _buildStepOverlay() {
    return Positioned(
      bottom: 80.0,
      left: 16.0,
      right: 16.0,
      child: AnimatedBuilder(
        animation: _glowAnimation,
        builder: (context, child) {
          return Opacity(
            opacity: 0.7 + (_glowAnimation.value * 0.3),
            child: child,
          );
        },
        child: Container(
          padding: const EdgeInsets.all(20.0),
          decoration: BoxDecoration(
            color: KinrelColors.darkCard.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(20.0),
            border: Border.all(
              color: KinrelColors.orange.withValues(alpha: 0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: KinrelColors.orange.withValues(alpha: 0.1),
                blurRadius: 20.0,
                spreadRadius: 4.0,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Step indicator
              _buildStepIndicator(),

              const SizedBox(height: 16.0),

              // Step title and description
              _buildStepContent(),

              const SizedBox(height: 16.0),

              // Action buttons
              _buildStepActions(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Step Indicator ─────────────────────────────────────────────────

  Widget _buildStepIndicator() {
    final currentNum = _stepNumber(_currentStep);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (index) {
        final stepNum = index + 1;
        final isActive = stepNum == currentNum;
        final isCompleted = stepNum < currentNum;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: isActive ? 24.0 : 8.0,
            height: 8.0,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4.0),
              color: isCompleted
                  ? KinrelColors.success
                  : isActive
                      ? KinrelColors.orange
                      : KinrelColors.border,
            ),
          ),
        );
      }),
    );
  }

  // ── Step Content ───────────────────────────────────────────────────

  Widget _buildStepContent() {
    return switch (_currentStep) {
      OnboardingStep.createProfile => Column(
          children: [
            // Animated teal glow node
            AnimatedBuilder(
              animation: _glowAnimation,
              builder: (context, child) {
                return Container(
                  width: 56.0,
                  height: 56.0,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: KinrelColors.darkCard,
                    border: Border.all(
                      color: RelationshipColors.self,
                      width: 3.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: RelationshipColors.self.withValues(
                          alpha: _glowAnimation.value * 0.4,
                        ),
                        blurRadius: 16.0,
                        spreadRadius: 4.0,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.person,
                      size: 28.0,
                      color: RelationshipColors.self,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12.0),
            Text(
              'Create your profile',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 18.0,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: 4.0),
            Text(
              'Your node will appear at the center of your family graph.',
              style: const TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13.0,
                color: KinrelColors.textSilver,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      OnboardingStep.addFamily => Column(
          children: [
            // Multiple nodes illustration
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildMiniNode(RelationshipColors.parent, Icons.arrow_upward),
                const SizedBox(width: 8.0),
                _buildMiniNode(RelationshipColors.self, Icons.person),
                const SizedBox(width: 8.0),
                _buildMiniNode(RelationshipColors.spouse, Icons.favorite_outline),
              ],
            ),
            const SizedBox(height: 12.0),
            Text(
              'Grow your graph',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 18.0,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: 4.0),
            Text(
              'Add parents, spouse, siblings, or children to build your tree.',
              style: const TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13.0,
                color: KinrelColors.textSilver,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      OnboardingStep.explore => Column(
          children: [
            Icon(
              Icons.explore,
              size: 48.0,
              color: KinrelColors.orange,
            ),
            const SizedBox(height: 12.0),
            Text(
              'Explore your family graph',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 18.0,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: 4.0),
            Text(
              'Pinch to zoom, drag to pan, and tap nodes for details.',
              style: const TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13.0,
                color: KinrelColors.textSilver,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      OnboardingStep.completed => const SizedBox.shrink(),
    };
  }

  /// Builds a small node for the illustration.
  Widget _buildMiniNode(Color color, IconData icon) {
    return Container(
      width: 40.0,
      height: 40.0,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: KinrelColors.darkCard,
        border: Border.all(color: color, width: 2.0),
      ),
      child: Icon(icon, size: 20.0, color: color),
    );
  }

  // ── Step Actions ───────────────────────────────────────────────────

  Widget _buildStepActions() {
    return Row(
      children: [
        // Skip button (steps 2-3 only)
        if (_canSkip)
          TextButton(
            onPressed: _skipStep,
            child: Text(
              'Skip',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14.0,
                color: KinrelColors.textDim,
              ),
            ),
          ),

        const Spacer(),

        // Primary CTA
        ElevatedButton(
          onPressed: _completeStepAction,
          style: ElevatedButton.styleFrom(
            backgroundColor: KinrelColors.orange,
            foregroundColor: KinrelColors.textWhite,
            padding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 12.0,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.0),
            ),
            elevation: 0,
          ),
          child: Text(
            _ctaLabel,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 14.0,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  /// Returns the CTA button label for the current step.
  String get _ctaLabel {
    return switch (_currentStep) {
      OnboardingStep.createProfile => 'Create Profile',
      OnboardingStep.addFamily => 'Add Member',
      OnboardingStep.explore => 'Got it!',
      OnboardingStep.completed => '',
    };
  }

  // ── Celebration Overlay ────────────────────────────────────────────

  Widget _buildCelebrationOverlay() {
    return Center(
      child: AnimatedBuilder(
        animation: _celebrationScaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _celebrationScaleAnimation.value,
            child: child,
          );
        },
        child: Container(
          padding: const EdgeInsets.all(32.0),
          decoration: BoxDecoration(
            color: KinrelColors.darkCard.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(24.0),
            boxShadow: [
              BoxShadow(
                color: KinrelColors.orange.withValues(alpha: 0.3),
                blurRadius: 30.0,
                spreadRadius: 10.0,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.celebration,
                size: 56.0,
                color: KinrelColors.brightGold,
              ),
              const SizedBox(height: 16.0),
              Text(
                'Your family graph is ready!',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 22.0,
                  fontWeight: FontWeight.w800,
                  color: KinrelColors.textWhite,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8.0),
              Text(
                'Explore your connections, expand branches, and discover your family story.',
                style: const TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14.0,
                  color: KinrelColors.textSilver,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

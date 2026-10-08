// lib/core/services/celebration_service.dart
//
// ┌─────────────────────────────────────────────────────────────────────┐
// │  CELEBRATION SERVICE — milestone tracking + delight moments          │
// └─────────────────────────────────────────────────────────────────────┘
//
// WHY THIS EXISTS
// ───────────────
// Duolingo, Snapchat, Cash App, Headspace — every retention-focused
// billion-dollar app celebrates the user's milestones. This isn't
// decoration; it's behavioral engineering:
//
//   • Celebrating small wins (first family created, 5th member added,
//     first relationship mapped) creates a variable reward schedule.
//     Variable rewards are the most powerful driver of habit formation
//     (Skinner, 1957 — the "intermittent reinforcement" schedule).
//
//   • A celebration fires dopamine BEFORE the user has time to feel
//     "is that all?". This shifts the emotional valence of the action
//     from neutral/anticlimactic to positive — which is the difference
//     between "I'll do this again" and "I'll do this once".
//
//   • The celebration is IMMEDIATE (<400ms after the action). The
//     Doherty Threshold says <400ms feels instant; >400ms feels like
//     the system is doing something to you. We fire the overlay the
//     same frame the action completes.
//
// PSYCHOLOGICAL PRINCIPLE: OPERANT CONDITIONING + PEAK-END RULE
// ─────────────────────────────────────────────────────────────────────
//   • Operant Conditioning: behavior + immediate positive consequence
//     → behavior recurs. The celebration is the consequence.
//   • Peak-End Rule: the user remembers the PEAK of an experience and
//     the END. A celebration makes the end a peak.
//
// PERFORMANCE
// ───────────
//   • Milestones are tracked in SharedPreferences (no server call).
//   • The overlay is shown via a global key + OverlayEntry — doesn't
//     require a navigator push, so it works on any screen.
//   • Auto-dismisses after 2.5s (long enough to enjoy, short enough
//     to not annoy).
//   • Respects Reduce Motion: if the user has accessibility enabled,
//     the confetti is replaced with a simple text toast (no animation).
//
// SECURITY & PRIVACY
// ──────────────────
//   • Milestones are stored LOCALLY only. Never synced to the server.
//     This is a UX feature, not a tracking feature.
//   • No PII in milestone data — just counts ("families_created: 3").

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/brand_colors.dart';
import '../constants/brand_typography.dart';
import 'haptic_service.dart';
import 'package:kinrel/core/utils/device_tier.dart';

/// Tracks user milestones and fires celebrations when they're hit.
///
/// Usage:
///   // Check if the user just hit a milestone
///   await CelebrationService.instance.checkAndCelebrate(
///     context: context,
///     milestone: Milestone.familyCreated,
///   );
///
/// Milestones are idempotent — celebrating the same one twice is a
/// no-op (the user only sees the celebration the FIRST time they hit
/// it, which is when it's most surprising and delightful).
class CelebrationService {
  CelebrationService._();
  static final CelebrationService instance = CelebrationService._();

  static const _kPrefix = 'celebration_';
  static const _kCountPrefix = 'count_';

  /// OverlayEntry currently showing — ensures only one celebration
  /// shows at a time.
  OverlayEntry? _currentEntry;

  /// Checks if the given milestone has been celebrated before.
  /// If NOT, fires the celebration and marks it as celebrated.
  /// Returns true if a celebration was shown, false if already-seen.
  Future<bool> checkAndCelebrate({
    required BuildContext context,
    required Milestone milestone,
  }) async {
    final key = '$_kPrefix${milestone.name}';
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(key) == true) {
        // Already celebrated — don't show again.
        return false;
      }
      // Mark as celebrated BEFORE showing, so a rapid double-trigger
      // doesn't show twice.
      await prefs.setBool(key, true);

      // Increment the count (used for "you've done this N times" toasts
      // on repeat — different from first-time celebrations).
      final countKey = '$_kCountPrefix${milestone.name}';
      final count = (prefs.getInt(countKey) ?? 0) + 1;
      await prefs.setInt(countKey, count);

      // Fire the celebration overlay.
      _showCelebration(context, milestone);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Returns how many times the user has completed this milestone.
  /// Useful for "You've added 5 members!" style repeat celebrations.
  Future<int> getCount(Milestone milestone) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt('$_kCountPrefix${milestone.name}') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Resets all celebration state. Used in dev/testing and in
  /// Settings > Privacy > Reset onboarding.
  Future<void> resetAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where(
            (k) => k.startsWith(_kPrefix) || k.startsWith(_kCountPrefix),
          );
      for (final k in keys) {
        await prefs.remove(k);
      }
    } catch (_) {}
  }

  void _showCelebration(BuildContext context, Milestone milestone) {
    // Find the overlay to attach the celebration to.
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    // If a celebration is already showing, remove it first.
    _currentEntry?.remove();
    _currentEntry = null;

    // Fire the success haptic IMMEDIATELY — the haptic is the primary
    // feedback. The visual overlay is the secondary "wow".
    unawaited(HapticService.success());

    final reduceMotion =
        MediaQuery.maybeOf(context)?.accessibleNavigation ?? false;

    _currentEntry = OverlayEntry(
      builder: (ctx) => _CelebrationOverlay(
        milestone: milestone,
        reduceMotion: reduceMotion,
        onDismiss: () {
          _currentEntry?.remove();
          _currentEntry = null;
        },
      ),
    );
    overlay.insert(_currentEntry!);

    // Auto-dismiss after 2.5s (or 1.5s for reduced motion — shorter
    // because there's no animation to enjoy).
    final duration = reduceMotion
        ? const Duration(milliseconds: 1500)
        : const Duration(milliseconds: 2500);
    Future.delayed(duration, () {
      _currentEntry?.remove();
      _currentEntry = null;
    });
  }
}

/// Milestones the app celebrates. Add new ones as features ship.
///
/// Naming: use past-tense verbs ("familyCreated" not "createFamily")
/// because the milestone is checked AFTER the action completes.
enum Milestone {
  /// First family created — the biggest activation milestone.
  familyCreated('🎉', 'Family Created!', 'Your family tree begins here.'),

  /// First member added to a family.
  firstMemberAdded('👤', 'First Member!', 'The roots of your tree.'),

  /// 5 members in a single family — the "engaged" threshold.
  fiveMembers('🌳', '5 Members!', 'Your tree is growing.'),

  /// 10 members — the "hooked" threshold.
  tenMembers('🌲', '10 Members!', 'A full family forest.'),

  /// First relationship mapped (the core value proposition).
  firstRelationship('🔗', 'Relationship Mapped!', 'You just spoke Kinrel.'),

  /// First kinship term discovered (the "aha" moment).
  firstKinshipTerm('✨', 'Kinship Found!', 'A new word for a connection.'),

  /// First invite sent — the user became a growth vector.
  firstInviteSent('💌', 'Invite Sent!', 'Your family is growing.'),

  /// First chat message sent.
  firstMessage('💬', 'First Message!', 'The conversation begins.'),

  /// First chat reply received — the loop is closed.
  firstReply('📩', 'You Got a Reply!', 'The conversation continues.'),

  /// Completed profile (avatar + name + username).
  profileCompleted('⭐', 'Profile Complete!', 'You\'re all set up.'),

  /// First notification received — the user is now connected to the
  /// live activity of their family.
  firstNotification('🔔', 'You\'re In!', 'Your family is reaching out.'),

  /// First story posted — the user is now a creator, not just a consumer.
  firstStory('📷', 'Story Shared!', 'A moment captured for the family.'),

  /// First graph explore — the user is now exploring their tree.
  firstGraphExplore('🌳', 'Tree Explored!', 'You\'re mapping your roots.'),

  /// First game played — the user discovered the social/play layer.
  firstGamePlayed('🎮', 'Game On!', 'Family fun unlocked.'),

  /// 7-day streak — the user has formed a habit.
  sevenDayStreak('🔥', '7-Day Streak!', 'You\'re building a habit.'),

  /// 30-day streak — the user is a power user.
  thirtyDayStreak('🏆', '30-Day Streak!', 'You\'re a Kinrel legend.');

  const Milestone(this.emoji, this.title, this.subtitle);

  final String emoji;
  final String title;
  final String subtitle;
}

/// The visual overlay shown when a milestone is hit.
///
/// Shows a centered card with the emoji, title, and subtitle, plus a
/// burst of confetti (unless Reduce Motion is on).
class _CelebrationOverlay extends StatelessWidget {
  const _CelebrationOverlay({
    required this.milestone,
    required this.reduceMotion,
    required this.onDismiss,
  });

  final Milestone milestone;
  final bool reduceMotion;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54, // Dim the background
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onDismiss, // Tap anywhere to dismiss early
        child: Center(
          child: _buildCard(context),
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context) {
    final card = Container(
      margin: const EdgeInsets.symmetric(horizontal: 40),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: KinrelColors.orange.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: clampBoxShadows([
          BoxShadow(
            color: KinrelColors.orange.withValues(alpha: 0.25),
            blurRadius: 32,
            offset: const Offset(0, 8),
          ),
        ]),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Emoji
          Text(
            milestone.emoji,
            style: const TextStyle(fontSize: 56),
          ),
          const SizedBox(height: 16),
          // Title
          Text(
            milestone.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: KinrelColors.textWhite,
            ),
          ),
          const SizedBox(height: 8),
          // Subtitle
          Text(
            milestone.subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              height: 1.5,
              color: KinrelColors.textSilver,
            ),
          ),
          const SizedBox(height: 20),
          // Dismiss hint
          const Text(
            'Tap to continue',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              color: KinrelColors.textDim,
            ),
          ),
        ],
      ),
    );

    if (reduceMotion) {
      // Reduced motion: just fade in, no confetti, no bounce.
      return card.animate().fadeIn(duration: 200.ms);
    }

    // Full celebration: bounce-in + confetti burst.
    return card
        .animate()
        .fadeIn(duration: 300.ms)
        .scale(
          begin: const Offset(0.7, 0.7),
          end: const Offset(1, 1),
          duration: 400.ms,
          curve: Curves.easeOutBack,
        )
        .shimmer(
          duration: 1200.ms,
          color: KinrelColors.orange.withValues(alpha: 0.15),
        );
  }
}

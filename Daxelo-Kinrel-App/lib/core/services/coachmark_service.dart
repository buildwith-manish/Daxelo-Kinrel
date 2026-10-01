// lib/core/services/coachmark_service.dart
//
// ┌─────────────────────────────────────────────────────────────────────┐
// │  COACHMARK SERVICE — contextual onboarding tooltips                    │
// └─────────────────────────────────────────────────────────────────────┘
//
// WHY THIS EXISTS
// ───────────────
// First-time users see a wall of features and have to figure out what
// to tap first. Most drop off. Billion-dollar apps (Notion, Linear,
// Figma, Slack) show contextual tooltips that appear the FIRST time a
// feature is relevant — "Tap here to add a family member" appears on
// the family screen when the list is empty, not on a startup tutorial.
//
// This is "progressive disclosure" — teach the right thing at the
// right moment, not upfront. Contextual tooltips beat upfront
// documentation 10× (user-research consensus).
//
// HOW IT WORKS
// ────────────
//   1. Wrap any widget in CoachmarkTarget with a unique coachmarkId.
//   2. The first time that widget appears AND the user hasn't seen
//      the coachmark, a tooltip appears pointing to it.
//   3. The user dismisses it (tap-to-dismiss) and the coachmark is
//      marked as seen (SharedPreferences) — it never shows again.
//   4. Use [hasSeen] to gate other coachmarks (e.g., "Advanced Graph
//      Mode" only shows after "Basic Add Member" is seen).
//
// PSYCHOLOGICAL PRINCIPLE: CONTEXTUAL LEARNING + SPACED REPETITION
// ─────────────────────────────────────────────────────────────────────
//   • Contextual Learning: a tooltip that appears when the user is
//     LOOKING at the thing it explains is 10× more memorable than
//     upfront documentation. The brain has a target to attach the
//     explanation to.
//   • Spaced Repetition: by gating advanced coachmarks behind basic
//     ones, we naturally space the teaching over multiple sessions,
//     which is how long-term memory forms.
//
// USAGE
// ─────
//   CoachmarkTarget(
//     id: 'add_family_member_button',
//     title: 'Add a Family Member',
//     body: 'Tap here to add someone to your family tree.',
//     child: MyAddButton(),
//   )
//
// The coachmark auto-shows on first appearance + auto-dismisses on tap.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/brand_colors.dart';
import '../constants/brand_typography.dart';
import '../utils/motion_preference.dart';
import 'haptic_service.dart';

/// Wraps a widget and shows a contextual tooltip the first time the
/// user sees it.
///
/// The tooltip appears as an overlay pointing to the wrapped widget.
/// It auto-dismisses on tap. The "seen" state persists in
/// SharedPreferences so the coachmark never shows twice.
class CoachmarkTarget extends StatefulWidget {
  const CoachmarkTarget({
    super.key,
    required this.id,
    required this.title,
    required this.body,
    required this.child,
    this.gate,
    this.position = CoachmarkPosition.below,
  });

  /// Unique ID for this coachmark. Used to track "has the user seen
  /// this?" in SharedPreferences. Must be unique across the app.
  final String id;

  /// The tooltip title (1-3 words, bold).
  final String title;

  /// The tooltip body (1-2 sentences explaining what to do).
  final String body;

  /// The widget to wrap + point to.
  final Widget child;

  /// Optional gate: another coachmark ID that must be seen BEFORE this
  /// one shows. Use this to enforce progressive disclosure (e.g., show
  /// "Advanced Graph Mode" only after "Basic Add Member" is seen).
  final String? gate;

  /// Where the tooltip appears relative to the target.
  final CoachmarkPosition position;

  @override
  State<CoachmarkTarget> createState() => _CoachmarkTargetState();
}

enum CoachmarkPosition { above, below }

class _CoachmarkTargetState extends State<CoachmarkTarget> {
  final GlobalKey _targetKey = GlobalKey();
  bool _shouldShow = false;
  bool _hasChecked = false;

  @override
  void initState() {
    super.initState();
    _checkShouldShow();
  }

  Future<void> _checkShouldShow() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // If this coachmark was already seen, don't show.
      if (prefs.getBool('coachmark_${widget.id}') == true) {
        if (mounted) setState(() => _hasChecked = true);
        return;
      }

      // If there's a gate, check it.
      if (widget.gate != null &&
          prefs.getBool('coachmark_${widget.gate}') != true) {
        // Gated coachmark — don't show until the gate is seen.
        if (mounted) setState(() => _hasChecked = true);
        return;
      }

      // Show the coachmark after a short delay so the widget tree is
      // fully laid out and we can measure the target's position.
      if (mounted) {
        setState(() => _shouldShow = true);
        // Wait for the next frame so the target key has a render object.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showOverlay();
        });
      }
    } catch (_) {
      if (mounted) setState(() => _hasChecked = true);
    }
  }

  void _showOverlay() {
    if (!mounted || !_shouldShow) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    final renderBox =
        _targetKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final targetRect = renderBox.localToGlobal(Offset.zero) &
        renderBox.size;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _CoachmarkOverlay(
        targetRect: targetRect,
        title: widget.title,
        body: widget.body,
        position: widget.position,
        onDismiss: () {
          entry.remove();
          _markSeen();
        },
      ),
    );
    overlay.insert(entry);

    // Fire a selection haptic to draw attention without being jarring.
    HapticService.selection();
  }

  Future<void> _markSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('coachmark_${widget.id}', true);
    } catch (_) {}
    if (mounted) setState(() => _shouldShow = false);
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: _targetKey,
      child: widget.child,
    );
  }
}

/// The full-screen overlay that dims the background and shows the
/// tooltip pointing to the target.
class _CoachmarkOverlay extends StatelessWidget {
  const _CoachmarkOverlay({
    required this.targetRect,
    required this.title,
    required this.body,
    required this.position,
    required this.onDismiss,
  });

  final Rect targetRect;
  final String title;
  final String body;
  final CoachmarkPosition position;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final isBelow = position == CoachmarkPosition.below;

    // Position the tooltip above or below the target.
    final tooltipTop = isBelow
        ? targetRect.bottom + 12
        : targetRect.top - 12 - _estimateHeight();

    return Stack(
      children: [
        // ── Dimmed background (tap to dismiss) ──────────────────────
        GestureDetector(
          onTap: onDismiss,
          behavior: HitTestBehavior.opaque,
          child: Container(
            color: Colors.black.withValues(alpha: 0.6),
            width: screenSize.width,
            height: screenSize.height,
          ),
        ),
        // ── Highlighted target (cut-out effect) ─────────────────────
        // We draw a transparent container at the target's position
        // with a border so it stands out against the dimmed background.
        // ── Reduce Motion: skip the fade+scale entrance animation. The
        // highlight appears instantly — still functional, just no
        // decorative motion that could trigger vestibular issues.
        Positioned(
          left: targetRect.left - 4,
          top: targetRect.top - 4,
          width: targetRect.width + 8,
          height: targetRect.height + 8,
          child: MotionPreference.isReducedMotion(context)
              ? Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: KinrelColors.orange, width: 2),
                  ),
                )
              : Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: KinrelColors.orange, width: 2),
                  ),
                )
                  .animate()
                  .fadeIn(duration: 200.ms)
                  .scale(
                    begin: const Offset(0.95, 0.95),
                    end: const Offset(1, 1),
                    duration: 200.ms,
                  ),
        ),
        // ── Tooltip ──────────────────────────────────────────────────
        Positioned(
          left: 16,
          right: 16,
          top: tooltipTop.clamp(16.0, screenSize.height - 200),
          child: _Tooltip(
            title: title,
            body: body,
            onDismiss: onDismiss,
            reduceMotion: MotionPreference.isReducedMotion(context),
          ),
        ),
      ],
    );
  }

  double _estimateHeight() {
    // Rough estimate for positioning when position = above.
    return 120;
  }
}

class _Tooltip extends StatelessWidget {
  const _Tooltip({
    required this.title,
    required this.body,
    required this.onDismiss,
    this.reduceMotion = false,
  });

  final String title;
  final String body;
  final VoidCallback onDismiss;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final tooltip = GestureDetector(
      onTap: onDismiss,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: KinrelColors.orange.withValues(alpha: 0.3),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.lightbulb_outline_rounded,
                  color: KinrelColors.orange,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                height: 1.5,
                color: KinrelColors.textSilver,
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Got it',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.orange,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    // ── Reduce Motion: return the tooltip without the fade+slide
    // entrance animation. The tooltip appears instantly — still
    // functional, just no decorative motion.
    if (reduceMotion) return tooltip;
    return tooltip
        .animate()
        .fadeIn(duration: 250.ms, delay: 100.ms)
        .slideY(
          begin: 0.1,
          end: 0,
          duration: 250.ms,
          delay: 100.ms,
          curve: Curves.easeOutCubic,
        );
  }
}

/// Convenience service for checking/resetting coachmark state.
class CoachmarkService {
  CoachmarkService._();

  static Future<bool> hasSeen(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('coachmark_$id') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Resets all coachmarks. Call from Settings > Privacy > Reset
  /// Onboarding to let a user see them again.
  static Future<void> resetAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs
          .getKeys()
          .where((k) => k.startsWith('coachmark_'));
      for (final k in keys) {
        await prefs.remove(k);
      }
    } catch (_) {}
  }
}

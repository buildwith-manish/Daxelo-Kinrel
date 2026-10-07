// lib/features/chat/presentation/widgets/typing_indicator.dart
//
// DAXELO KINREL — Shared typing indicator (group + DM)
//
// v3.5 — MOVED (not rewritten) from chat_screen.dart's
// _buildTypingIndicator so the DM screen renders the SAME indicator
// with the same layout/spacing/typography/colors/animation:
//   - 20x20 ember-tint avatar circle with the typer's initial
//     (displayFont 9 w700 orange)
//   - bodyFont 12 textSilver label ("X is typing")
//   - 3 bouncing 4x4 orange dots (1200ms loop, staggered intervals)
//
// The widget is self-contained: it owns its AnimationController (the
// group screen previously owned it in _ChatScreenState). The
// PERF (Part C3) behavior is preserved — the controller only repeats
// while the widget is visible (the screens render this widget ONLY
// while someone is actually typing; it unmounts when they stop).
//
// Inputs:
//   - name: the typing user's display name (drives the avatar initial)
//   - label: the rendered text (locale-aware; the group prefers its
//     Socket.IO engagement label, both chats fall back to a
//     "<name> is typing" default computed by the caller)
//
// The group chat calls this with the engagement provider's label; the
// DM calls it with the peer's name — identical rendering either way.

import 'package:flutter/material.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/widgets/global_error_widget.dart';

class TypingIndicator extends StatefulWidget {
  const TypingIndicator({
    super.key,
    required this.name,
    required this.label,
  });

  /// Display name of the person typing (drives the avatar initial).
  final String name;

  /// Rendered label text, e.g. "Riya is typing" (locale-aware).
  final String label;

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  // Typing indicator animation — 3 bouncing dots. MOVED verbatim from
  // chat_screen.dart (same 1200ms duration, same staggered Intervals,
  // same -6px translate target).
  late final AnimationController _typingController;
  late final List<Animation<double>> _dotAnimations;

  @override
  void initState() {
    super.initState();
    _typingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _dotAnimations = List.generate(3, (index) {
      return Tween<double>(begin: 0, end: -6).animate(
        CurvedAnimation(
          parent: _typingController,
          curve: Interval(
            index * 0.2,
            0.4 + index * 0.2,
            curve: Curves.easeOut,
          ),
        ),
      );
    });

    // The widget is only built while someone is typing (the screens
    // gate it on chatState.isTyping / engagement.isSomeoneTyping), so
    // the controller starts repeating on mount and stops on unmount —
    // the same effective behavior as the group's _syncTypingController.
    _typingController.repeat();
  }

  @override
  void dispose() {
    _typingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // MOVED verbatim from chat_screen.dart's _buildTypingIndicator.
    final name = widget.name;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          // Small avatar
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: KinrelColors.ember.withValues(alpha: 0.3),
            ),
            child: Center(
              child: Text(
                ((name.isNotEmpty) ? name.substring(0, 1) : '?').toUpperCase(),
                style: const TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.orange,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            widget.label,
            style: const TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              color: KinrelColors.textSilver,
            ),
          ),
          const SizedBox(width: 6),
          // Bouncing dots
          SizedBox(
            width: 24,
            height: 14,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(3, (i) {
                return KinrelAnimatedBuilder(
                  animation: _dotAnimations[i],
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(0, _dotAnimations[i].value),
                      child: child,
                    );
                  },
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: KinrelColors.orange,
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

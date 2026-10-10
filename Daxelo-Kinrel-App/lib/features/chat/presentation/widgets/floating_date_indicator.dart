// lib/features/chat/presentation/widgets/floating_date_indicator.dart
//
// DAXELO KINREL — Floating Date Indicator (WhatsApp/Telegram-style)
//
// Shows a floating date pill at the top of the message list while the
// user is scrolling. The pill displays the date of the messages
// currently visible at the top of the viewport. When scrolling stops,
// the pill fades out after a ~1.5s delay.
//
// Architecture:
//   • Listens to the parent's ScrollController via addListener
//   • On scroll: shows the pill immediately, cancels the hide timer
//   • On scroll stop: starts a 1.5s timer → fade out via AnimationController
//   • Computes the active date by estimating which DateGroup is at the
//     top of the viewport (based on average message height + scroll offset)
//
// The widget is a StatefulWidget that owns its own AnimationController +
// Timer. It's designed to be placed as a Stack overlay on top of the
// ChatMessageList — it does NOT affect the list's layout.
//
// Used by: ChatMessageList (wraps the ListView.builder in a Stack).

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../widgets/chat_meta.dart'; // DateGroup

/// Average message height (post-compact-padding). Used for estimating
/// which date group is at the top of the viewport during scrolling.
/// The estimate doesn't need to be perfect — it just needs to identify
/// the correct DATE (which changes infrequently — at most once per
/// day boundary).
const _kAvgMessageHeight = 80.0;
const _kDateSeparatorHeight = 38.0; // pill + SizedBox(8)
const _kHideDelay = Duration(milliseconds: 1500);
const _kFadeDuration = Duration(milliseconds: 300);

class FloatingDateIndicator extends StatefulWidget {
  const FloatingDateIndicator({
    super.key,
    required this.scrollController,
    required this.grouped,
  });

  /// The parent's ScrollController (shared with the ListView).
  final ScrollController scrollController;

  /// The date-grouped messages (newest-first, matching the reversed
  /// ListView's item order).
  final List<DateGroup> grouped;

  @override
  State<FloatingDateIndicator> createState() => _FloatingDateIndicatorState();
}

class _FloatingDateIndicatorState extends State<FloatingDateIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  Timer? _hideTimer;
  String _currentDateLabel = '';
  bool _isScrolling = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: _kFadeDuration,
    );
    widget.scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    widget.scrollController.removeListener(_onScroll);
    _animController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!mounted) return;

    // Compute the active date label from the scroll position.
    final newLabel = _computeActiveDate();

    // If the date changed, update immediately (no flicker).
    if (newLabel.isNotEmpty && newLabel != _currentDateLabel) {
      setState(() => _currentDateLabel = newLabel);
    }

    // Show the badge immediately on scroll start.
    if (!_isScrolling) {
      _isScrolling = true;
      _hideTimer?.cancel();
      // Animate in (0 → 1).
      if (_animController.value < 1.0) {
        _animController.forward();
      }
    }

    // Cancel any pending hide timer — we're still scrolling.
    _hideTimer?.cancel();

    // Start a new hide timer (resets on every scroll event).
    _hideTimer = Timer(_kHideDelay, () {
      if (!mounted) return;
      _isScrolling = false;
      // Fade out (1 → 0).
      _animController.reverse();
    });
  }

  /// Estimates which DateGroup's date label is at the top of the
  /// viewport based on the scroll offset + average message heights.
  ///
  /// With reverse: true:
  ///   - pixels = 0 → we're at the bottom (newest, index 0)
  ///   - pixels > 0 → we've scrolled up (older messages visible)
  ///   - The TOP of the viewport is at position (pixels + viewportDimension)
  ///     measured from the bottom of the list.
  ///
  /// We iterate from index 0 (newest) upward, accumulating each group's
  /// estimated height. The group whose cumulative range includes the
  /// "top of viewport" position is the active date.
  String _computeActiveDate() {
    if (widget.grouped.isEmpty) return '';

    final position = widget.scrollController.position;
    final pixels = position.pixels;
    final viewportDim = position.viewportDimension;

    // The position of the top of the viewport, measured from the bottom.
    final topPos = pixels + viewportDim;

    double cumulative = 0;
    for (int i = 0; i < widget.grouped.length; i++) {
      final group = widget.grouped[i];
      // Estimate this group's height: date separator + messages.
      final groupHeight = _kDateSeparatorHeight +
          (group.messages.length * _kAvgMessageHeight);

      // If the top of the viewport falls within this group's range,
      // this is the active date.
      if (topPos <= cumulative + groupHeight) {
        return group.dateLabel;
      }
      cumulative += groupHeight;
    }

    // If we've scrolled past all groups (very old messages), return
    // the oldest group's date label.
    return widget.grouped.last.dateLabel;
  }

  @override
  Widget build(BuildContext context) {
    if (_currentDateLabel.isEmpty) return const SizedBox.shrink();

    return Positioned(
      top: 8,
      left: 0,
      right: 0,
      child: Center(
        child: FadeTransition(
          opacity: _animController,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: KinrelColors.darkCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
                width: 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              _currentDateLabel,
              style: const TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textWhite,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

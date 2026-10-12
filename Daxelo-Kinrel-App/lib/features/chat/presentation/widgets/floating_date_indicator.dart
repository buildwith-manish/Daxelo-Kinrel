// lib/features/chat/presentation/widgets/floating_date_indicator.dart
//
// DAXELO KINREL — Floating Date Indicator (v143 redesign)
//
// Shows a floating date pill at the top of the message list while the
// user scrolls. Uses the SAME pill visual as the regular date
// separators (ThreadDateMarker) for visual consistency.
//
// v143 viewport visibility fix:
//   The old code showed the floating indicator whenever the user was
//   scrolling, regardless of whether a regular date pill was already
//   visible in the viewport. This caused duplicate/conflicting date
//   indicators.
//
//   The fix: walk the sliver's live children and check if any visible
//   child's TOP edge is within the viewport (meaning the date
//   separator at the top of that date group is visible). If ANY
//   regular date pill is visible → hide the floating indicator
//   immediately. If NO regular date pill is visible → show the
//   floating indicator with the current date label.
//
// Visibility rules (per spec):
//   1. If ≥1 regular date pill is visible → hide floating indicator.
//   2. If multiple regular pills are visible → keep hidden.
//   3. If no regular pills are visible → floating indicator may appear.
//   4. When a regular pill becomes visible → hide immediately.
//   5. Never show a floating date that conflicts with a visible pill.
//   6. When scrolling stops → fade out after 1.2s, only if no pill visible.
//   7. If scrolling resumes during fade-out → cancel timer + recalculate.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../../core/constants/brand_spacing.dart';

import '../chat_ui_tokens.dart';

const _kHideDelay = Duration(milliseconds: 1200);
const _kThrottleMs = 100;

class FloatingDateIndicator extends StatefulWidget {
  const FloatingDateIndicator({
    super.key,
    required this.scrollController,
    required this.listViewKey,
    required this.dateLabelForIndex,
    required this.itemCount,
  });

  final ScrollController scrollController;
  final GlobalKey listViewKey;
  final String? Function(int index) dateLabelForIndex;
  final int itemCount;

  @override
  State<FloatingDateIndicator> createState() => _FloatingDateIndicatorState();
}

class _FloatingDateIndicatorState extends State<FloatingDateIndicator>
    with SingleTickerProviderStateMixin {
  Timer? _hideTimer;
  Timer? _throttleTimer;
  bool _isScrolling = false;
  String? _currentLabel;

  late final AnimationController _animController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _throttleTimer?.cancel();
    widget.scrollController.removeListener(_onScroll);
    _animController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!mounted) return;
    final position = widget.scrollController.position;

    // At the very bottom (offset 0 on reversed list = newest messages)
    // — don't show the floating date there.
    if (position.pixels <= 0) {
      if (_currentLabel != null) {
        _hideTimer?.cancel();
        _animOut();
      }
      return;
    }

    // Show immediately on scroll start.
    if (!_isScrolling) {
      _isScrolling = true;
      _hideTimer?.cancel();
      _updateLabel();
    }

    // Throttle: at most one update per _kThrottleMs.
    if (_throttleTimer?.isActive ?? false) return;
    _throttleTimer = Timer(const Duration(milliseconds: _kThrottleMs), () {
      _throttleTimer = null;
      _updateLabel();
    });

    // Cancel pending hide — we're still scrolling.
    _hideTimer?.cancel();
    _hideTimer = Timer(_kHideDelay, () {
      if (!mounted) return;
      _isScrolling = false;
      // Only hide if no regular date pill is visible. If a pill IS
      // visible, the floating indicator should already be hidden (or
      // never shown) — but double-check here for safety.
      _updateLabel();
    });
  }

  /// Walks the sliver's live children to:
  /// 1. Find the topmost visible item's date label.
  /// 2. Check if any visible item's TOP edge is within the viewport
  ///    (meaning the date separator pill at the top of that date group
  ///    is visible). If so → hide the floating indicator.
  void _updateLabel() {
    if (!mounted) return;

    final listContext = widget.listViewKey.currentContext;
    if (listContext == null) return;
    final listRenderObj = listContext.findRenderObject();
    if (listRenderObj is! RenderBox || !listRenderObj.attached) return;

    // The list's viewport bounds.
    final viewTop = listRenderObj.localToGlobal(Offset.zero).dy;
    final viewBottom = viewTop + listRenderObj.size.height;

    // Find the RenderSliverMultiBoxAdaptor.
    RenderSliverMultiBoxAdaptor? sliver;
    void findSliver(RenderObject node) {
      if (sliver != null) return;
      if (node is RenderSliverMultiBoxAdaptor) {
        sliver = node;
        return;
      }
      node.visitChildren(findSliver);
    }

    findSliver(listRenderObj);
    final found = sliver;
    if (found == null) return;

    // Walk the sliver's live children.
    String? label;
    var topMostY = double.infinity;
    var regularPillVisible = false;

    var child = found.firstChild;
    while (child != null) {
      final childParentData =
          child.parentData as SliverMultiBoxAdaptorParentData;
      final index = childParentData.index;
      if (index != null && child.attached) {
        final childTop = child.localToGlobal(Offset.zero).dy;
        final childBottom = childTop + child.size.height;
        final visible = childTop < viewBottom && childBottom > viewTop;

        if (visible) {
          // Check if this child's TOP edge is within the viewport.
          // The date separator is at the top of each date group's
          // Column. If the child's top is within the viewport, the
          // date pill IS visible.
          if (childTop >= viewTop) {
            regularPillVisible = true;
          }

          // Track the topmost visible child for the date label.
          if (childTop < topMostY) {
            topMostY = childTop;
            label = widget.dateLabelForIndex(index);
          }
        }
      }
      child = found.childAfter(child);
    }

    // If a regular date pill is visible, hide the floating indicator.
    if (regularPillVisible) {
      if (_currentLabel != null) {
        _currentLabel = null;
        _animOut();
        if (mounted) setState(() {});
      }
      return;
    }

    // No regular date pill is visible — show the floating indicator.
    if (label == null || label.isEmpty) return;

    if (label != _currentLabel) {
      _currentLabel = label;
      _animIn();
      setState(() {});
    } else if (_animController.value < 1.0) {
      _animIn();
    }
  }

  void _animIn() {
    if (_animController.value < 1.0) {
      _animController.forward();
    }
  }

  void _animOut() {
    _animController.reverse().then((_) {
      if (mounted && !_isScrolling && _currentLabel != null) {
        setState(() => _currentLabel = null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_currentLabel == null || _currentLabel!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: 8,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: FadeTransition(
            opacity: _animController,
            // v143: same pill style as ThreadDateMarker for visual
            // consistency — chatCard background, pillText typography,
            // KinrelRadius.full rounded corners.
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: ChatUi.chatCard,
                borderRadius: BorderRadius.circular(KinrelRadius.full),
              ),
              child: Text(_currentLabel!, style: ChatUi.pillText),
            ),
          ),
        ),
      ),
    );
  }
}

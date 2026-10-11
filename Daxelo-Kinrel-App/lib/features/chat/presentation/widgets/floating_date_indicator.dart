// lib/features/chat/presentation/widgets/floating_date_indicator.dart
//
// DAXELO KINREL — Floating Date Indicator (Kin Thread / PR2 Task 2)
//
// Shows a floating date pill at the top of the message list while the
// user scrolls. The pill shows the date of the topmost visible message
// (the label format is identical to the inline date separators:
// Today / Yesterday / weekday within 6 days / "Month D, YYYY").
//
// Behavior:
//   • Disappears ~1.2s after scrolling stops.
//   • Does not appear when the list is at rest or at the very bottom
//     (offset 0 on the reversed list = newest messages).
//   • Does not follow the user once they stop — the chip is a fixed
//     overlay that simply fades out.
//
// Performance:
//   • No setState on every scroll frame — the label only changes when
//     the topmost visible DATE changes (usually once per day-group).
//   • Scroll notifications are throttled to at most one update per
//     100ms.
//   • No Opacity widget — a short fade via FadeTransition on the small
//     chip (explicitly allowed by the flat-mode rules).
//   • No per-item VisibilityDetector — the topmost visible item is
//     found cheaply through the rendered sliver children
//     (RenderSliverMultiBoxAdaptor's live children + their indexes),
//     measured with localToGlobal against the list's own box. Works
//     with the reversed list (topmost = smallest global Y).
//   • No new package.
//
// Used by: ChatMessageList (as a Stack overlay on the ListView).

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/theme/kinrel_fx.dart';

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

  /// Key attached to the ListView by ChatMessageList. Used to locate
  /// the rendered sliver (and its children) cheaply from a Stack
  /// sibling — the indicator is NOT inside the scrollable, so it can't
  /// use Scrollable.of(context).
  final GlobalKey listViewKey;

  /// Returns the date label for the given ListView item index.
  /// Each item in the reversed ListView is a date group, so this
  /// maps the visible item index → its dateLabel.
  final String? Function(int index) dateLabelForIndex;

  /// Total number of items in the ListView (grouped.length).
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

    // Skip if we're at the very bottom (offset 0 on the reversed list =
    // the most recent messages) — don't show the floating date there.
    if (position.pixels <= 0) {
      if (_currentLabel != null) {
        _hideTimer?.cancel();
        _animOut();
      }
      return;
    }

    // Show immediately on scroll start (before the throttle kicks in).
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
      _animOut();
    });
  }

  /// Finds the topmost visible item's date label from the rendered
  /// sliver children. One pass over ~10-20 live children, throttled to
  /// 10 Hz, and only mutates state when the LABEL changes.
  void _updateLabel() {
    if (!mounted) return;

    final listContext = widget.listViewKey.currentContext;
    if (listContext == null) return;
    final listRenderObj = listContext.findRenderObject();
    if (listRenderObj is! RenderBox || !listRenderObj.attached) return;

    // The list's own on-screen bounds (the viewport reference).
    final viewTop = listRenderObj.localToGlobal(Offset.zero).dy;
    final viewBottom = viewTop + listRenderObj.size.height;

    // Find the RenderSliverMultiBoxAdaptor (the list's sliver) by
    // walking down from the ListView's render object.
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

    // Walk the sliver's live children; the topmost visible child has
    // the smallest global Y. localToGlobal handles the reversed
    // growth direction + paint transforms for us.
    String? label;
    var topMostY = double.infinity;
    var child = found.firstChild;
    while (child != null) {
      final childParentData =
          child.parentData as SliverMultiBoxAdaptorParentData;
      final index = childParentData.index;
      if (index != null && child.attached) {
        final childTop = child.localToGlobal(Offset.zero).dy;
        final childBottom = childTop + child.size.height;
        final visible = childTop < viewBottom && childBottom > viewTop;
        if (visible && childTop < topMostY) {
          topMostY = childTop;
          label = widget.dateLabelForIndex(index);
        }
      }
      child = found.childAfter(child);
    }

    if (label == null || label.isEmpty) return;

    // Update only if the label changed (or the fade hasn't completed).
    if (label != _currentLabel) {
      _currentLabel = label;
      _animIn();
      // Rebuild ONLY the small chip (not the whole list): this state
      // lives on the indicator widget, not on ChatMessageList.
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
      top: 6,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: FadeTransition(
            opacity: _animController,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                // Match the inline date separator's styling exactly.
                color: const Color(0xFF13141E).withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 0.5,
                ),
                boxShadow: KinrelFx.shadows([
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]),
              ),
              child: Text(
                _currentLabel!,
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textSilver.withValues(alpha: 0.9),
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

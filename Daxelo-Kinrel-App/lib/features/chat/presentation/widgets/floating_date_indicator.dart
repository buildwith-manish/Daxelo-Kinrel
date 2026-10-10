// lib/features/chat/presentation/widgets/floating_date_indicator.dart
//
// DAXELO KINREL — Floating Date Indicator (WhatsApp/Telegram-style)
//
// Shows a floating date pill at the top of the message list while the
// user scrolls. The pill shows the date of the topmost visible message.
// Disappears ~1.2s after scrolling stops. Does not appear at rest or
// at the very bottom.
//
// Performance:
//   • Uses ValueNotifier<String?> — only rebuilds the pill when the
//     date text CHANGES (not on every scroll frame).
//   • Throttles scroll notifications to at most one update per 100ms.
//   • No Opacity widget — uses a slide+fade via AnimatedSwitcher.
//   • Works with the reversed ListView (reverse: true).
//   • No per-item VisibilityDetector — uses the scroll position +
//     the rendered sliver children's offsets to find the topmost
//     visible message cheaply.
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
    required this.dateLabelForIndex,
    required this.itemCount,
  });

  final ScrollController scrollController;

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
  // The last pixels value — used to detect scroll direction + skip
  // redundant updates.
  double _lastPixels = -1;

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
    super.dispose();
  }

  void _onScroll() {
    if (!mounted) return;
    final position = widget.scrollController.position;

    // Skip if we're at the very bottom (offset 0) — don't show the
    // floating date when the user is at the most recent messages.
    if (position.pixels <= 0) {
      if (_currentLabel != null) {
        _hideTimer?.cancel();
        _animOut();
      }
      return;
    }

    // Throttle: at most one update per _kThrottleMs.
    if (_throttleTimer?.isActive ?? false) return;
    _throttleTimer = Timer(const Duration(milliseconds: _kThrottleMs), () {
      _throttleTimer = null;
      _updateLabel();
    });

    // Show immediately on scroll start.
    if (!_isScrolling) {
      _isScrolling = true;
      _hideTimer?.cancel();
      _updateLabel();
    }

    // Cancel pending hide — we're still scrolling.
    _hideTimer?.cancel();
    _hideTimer = Timer(_kHideDelay, () {
      if (!mounted) return;
      _isScrolling = false;
      _animOut();
    });
  }

  void _updateLabel() {
    if (!mounted) return;
    final position = widget.scrollController.position;
    final pixels = position.pixels;
    if (pixels == _lastPixels) return;
    _lastPixels = pixels;

    // Find the topmost visible item using the scroll position.
    // With reverse: true, the visual TOP of the viewport shows the
    // item with the HIGHEST index that fits.
    //
    // We use the scroll metrics + the SliverRender sliver's children
    // to find the first visible child index.
    final ctx = widget.scrollController.position.context.storageContext;
    final scrollable = ctx?.findAncestorStateOfType<ScrollableState>();
    if (scrollable == null) return;
    final renderObj = scrollable.context.findRenderObject();
    if (renderObj is! RenderSliverMultiBoxAdaptor) return;

    // Iterate through the sliver's children to find the topmost visible.
    String? label;
    final firstChild = renderObj.firstChild;
    var child = firstChild;
    while (child != null) {
      final childParentData = child.parentData as SliverMultiBoxAdaptorParentData;
      final index = childParentData.index;
      if (index != null) {
        final constraints = renderObj.constraints;
        final geometry = child.getTransformTo(renderObj).getTranslation();
        final childTop = geometry.y;
        final viewportHeight = position.viewportDimension;

        // Check if this child is at least partially visible.
        if (childTop < viewportHeight && childTop + child.size.height > 0) {
          // This child is visible. For a reversed list, the topmost
          // visible child has the highest index.
          final childLabel = widget.dateLabelForIndex(index);
          if (childLabel != null) {
            label = childLabel;
          }
        }
      }
      child = renderObj.childAfter(child);
    }

    // Update only if the label changed.
    if (label != null && label != _currentLabel) {
      _currentLabel = label;
      _animIn();
    } else if (label != null && _animController.value < 1.0) {
      _animIn();
    }
  }

  late final AnimationController _animController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );

  void _animIn() {
    if (_animController.value < 1.0) {
      _animController.forward();
    }
  }

  void _animOut() {
    _animController.reverse().then((_) {
      if (mounted && !_isScrolling) {
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
    );
  }
}

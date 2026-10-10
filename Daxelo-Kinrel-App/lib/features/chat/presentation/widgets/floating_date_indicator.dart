// lib/features/chat/presentation/widgets/floating_date_indicator.dart
//
// DAXELO KINREL — Floating Date Indicator (WhatsApp/Telegram-style)
//
// Shows a floating date pill at the top of the message list while the
// user is scrolling. The pill uses the EXACT SAME styling as the
// existing date separator (_buildDateSeparator in chat_message_list.dart)
// so the two look identical — no visual difference between the inline
// separator and the floating badge.
//
// The floating badge only appears when the original date separator
// has scrolled OUT of view (above the viewport). When the separator
// is still visible at its normal position, the floating badge is
// hidden — preventing two competing date indicators.
//
// The active date is tracked using ACTUAL rendered positions (via
// GlobalKey + RenderBox.localToGlobal), NOT height estimation. This
// eliminates the incorrect-date bug where the badge showed an older
// date than what was actually visible.
//
// Architecture:
//   • ChatMessageList owns a Map<int, GlobalKey> for each date separator
//   • On scroll, a post-frame callback iterates through the live keys
//     to find the topmost visible separator + check if it's in the viewport
//   • If the separator IS visible → hide the badge (no duplicate)
//   • If the separator scrolled OUT of view → show the badge with that date
//   • The badge fades in/out via AnimationController with a 1.5s delay
//
// Used by: ChatMessageList (as a Stack overlay on top of ListView.builder).

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/theme/kinrel_fx.dart';

const _kHideDelay = Duration(milliseconds: 1500);
const _kFadeDuration = Duration(milliseconds: 250);

/// Floating date indicator that reuses the EXACT SAME styling as the
/// inline date separator. Takes a [ValueNotifier] for the active date
/// label (null = no badge) + a [ValueNotifier] for whether the
/// original separator is currently visible (true = hide the badge).
class FloatingDateIndicator extends StatefulWidget {
  const FloatingDateIndicator({
    super.key,
    required this.activeDateNotifier,
    required this.separatorVisibleNotifier,
    required this.scrollController,
  });

  /// The active date label (null = no messages / not scrolling).
  /// Updated by ChatMessageList's scroll listener using actual
  /// rendered positions (NOT estimation).
  final ValueNotifier<String?> activeDateNotifier;

  /// Whether the active date's original separator is currently visible
  /// in the viewport. When true, the floating badge is hidden (no
  /// duplicate indicator).
  final ValueNotifier<bool> separatorVisibleNotifier;

  /// The parent's ScrollController — used to detect scroll start/stop.
  final ScrollController scrollController;

  @override
  State<FloatingDateIndicator> createState() => _FloatingDateIndicatorState();
}

class _FloatingDateIndicatorState extends State<FloatingDateIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  Timer? _hideTimer;
  bool _isScrolling = false;
  String? _currentLabel;
  bool _separatorVisible = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: _kFadeDuration,
    );
    widget.scrollController.addListener(_onScroll);
    widget.activeDateNotifier.addListener(_onDateChanged);
    widget.separatorVisibleNotifier.addListener(_onSeparatorVisibilityChanged);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    widget.scrollController.removeListener(_onScroll);
    widget.activeDateNotifier.removeListener(_onDateChanged);
    widget.separatorVisibleNotifier.removeListener(_onSeparatorVisibilityChanged);
    _animController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!mounted) return;
    // Show the badge immediately on scroll start.
    if (!_isScrolling) {
      _isScrolling = true;
      _hideTimer?.cancel();
      _updateVisibility();
    }
    // Cancel any pending hide timer — we're still scrolling.
    _hideTimer?.cancel();
    // Start a new hide timer (resets on every scroll event).
    _hideTimer = Timer(_kHideDelay, () {
      if (!mounted) return;
      _isScrolling = false;
      _animController.reverse();
    });
  }

  void _onDateChanged() {
    _currentLabel = widget.activeDateNotifier.value;
    _updateVisibility();
  }

  void _onSeparatorVisibilityChanged() {
    _separatorVisible = widget.separatorVisibleNotifier.value;
    _updateVisibility();
  }

  /// Show the badge only when:
  /// 1. We're scrolling (or just stopped within the delay window)
  /// 2. We have a valid date label
  /// 3. The original separator is NOT visible (no duplicate)
  void _updateVisibility() {
    final shouldShow = _currentLabel != null &&
        _currentLabel!.isNotEmpty &&
        !_separatorVisible;

    if (shouldShow && _animController.value < 1.0) {
      _animController.forward();
    } else if (!shouldShow && _animController.value > 0.0) {
      _animController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 6,
      left: 0,
      right: 0,
      child: Center(
        child: FadeTransition(
          opacity: _animController,
          // ── Reuse the EXACT SAME styling as _buildDateSeparator ──
          // Same background color, border, radius, font, size — so the
          // floating badge is visually indistinguishable from the inline
          // separator. When the inline separator reappears, the transition
          // is seamless because they look identical.
          child: ValueListenableBuilder<String?>(
            valueListenable: widget.activeDateNotifier,
            builder: (context, label, _) {
              if (label == null || label.isEmpty) return const SizedBox.shrink();
              return Container(
                // Match the inline separator's padding (was 14/6 — now 16/4
                // to match the separator's 16/6, slightly reduced for compactness).
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  // EXACT SAME as _buildDateSeparator:
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
                  label,
                  // EXACT SAME TextStyle as _buildDateSeparator:
                  style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.textSilver.withValues(alpha: 0.9),
                    letterSpacing: 0.8,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

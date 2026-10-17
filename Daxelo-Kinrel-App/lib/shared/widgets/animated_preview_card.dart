// lib/shared/widgets/animated_preview_card.dart
//
// ┌────────────────────────────────────────────────────────────────────┐
// │  ANIMATED PREVIEW CARD — shared shell for empty-state preview cards │
// └────────────────────────────────────────────────────────────────────┘
//
// WHY THIS EXISTS
// ───────────────
// The Memories & Timeline and Oral History empty states both show a
// small, animated preview card that demonstrates what a real card
// looks like — so the user sees the feature in action rather than a
// static icon. The two features animate DIFFERENTLY (Memories
// crossfades between placeholder photo scenes; Oral History pulses a
// waveform), but they share the same card shell:
//
//   • A KinrelColors.darkCard container with KinrelRadius.lg corners
//   • A fixed width (240) so the preview reads as a real card, not a
//     tiny icon chip
//   • Slot-based content layout: [header row] → [animated media area]
//     → [title] → [description]
//   • Reduced-motion passthrough (each feature's media widget reads
//     this flag and suppresses its animation when true)
//   • RepaintBoundary wrapping at the call site (the parent passes
//     the RepaintBoundary — see the call sites in memories_screen.dart
//     and oral_history_screen.dart) so the continuous animation
//     doesn't cause Flutter to repaint the entire empty state on
//     every tick.
//
// This shell keeps the pattern maintainable if a third feature needs
// the same treatment later — implement the slot widgets and pass them
// in, no need to re-implement the card container or reduced-motion
// handling.
//
// USAGE
// ─────
//   AnimatedPreviewCard(
//     reducedMotion: AppMotion.reducedMotion(context),
//     accentColor: KinrelColors.orange,
//     header: _MyHeader(),
//     mediaArea: _MyAnimatedMedia(reducedMotion: ...),
//     title: 'A family celebration',
//     description: 'Birthdays, festivals, and the moments we gather.',
//   )
//
// The [mediaArea] is where the animation happens. Each feature owns
// its own animated media widget — see `_MemoryPhotoCrossfade` in
// memories_screen.dart and `_StoryWaveformPulse` in
// oral_history_screen.dart for the two existing implementations.
//
// REDUCED MOTION
// ──────────────
// The [reducedMotion] flag is passed through to the [mediaArea]
// widget. Each media widget is responsible for suppressing its own
// animation when the flag is true (e.g., show a single static scene
// instead of cycling, or show static waveform bars instead of
// pulsing). The card shell itself has no animation to suppress.
//
// PERFORMANCE
// ───────────
// The parent should wrap the [AnimatedPreviewCard] in a
// [RepaintBoundary] so the continuous animation inside the
// [mediaArea] doesn't cause Flutter to repaint the entire empty
// state on every tick. The call sites in memories_screen.dart and
// oral_history_screen.dart already do this — keep the pattern when
// adding new consumers.

import 'package:flutter/material.dart';

import '../../core/constants/brand_colors.dart';
import '../../core/constants/brand_typography.dart';
import '../../core/constants/brand_spacing.dart';

/// A shared shell for the animated preview cards used in empty states.
///
/// Renders a [KinrelColors.darkCard] container with [KinrelRadius.lg]
/// corners, a fixed 240px width, and a slot-based content layout:
/// [header] → [mediaArea] → [title] → [description]. The [mediaArea]
/// is where the animation happens — each feature provides its own
/// animated media widget that respects the [reducedMotion] flag.
///
/// See the file doc comment for the full rationale and usage example.
class AnimatedPreviewCard extends StatelessWidget {
  const AnimatedPreviewCard({
    super.key,
    required this.mediaArea,
    required this.title,
    required this.description,
    this.reducedMotion = false,
    this.accentColor,
    this.header,
    this.width = 240,
  });

  /// Whether the user has requested reduced motion (via the platform
  /// accessibility setting). Passed through to the [mediaArea] widget
  /// so it can suppress its own animation. The card shell itself has
  /// no animation to suppress.
  final bool reducedMotion;

  /// The accent color used for the card's border and shadow. If null,
  /// a neutral subtle border is used. Each feature passes its own
  /// accent (e.g., Memories passes the current scene's accent; Oral
  /// History passes the cycling category's accent).
  final Color? accentColor;

  /// The header row (typically a type/category badge + date/duration
  /// badge). Rendered at the top of the card, above the [mediaArea].
  /// Pass null to omit (the [mediaArea] becomes the top element).
  final Widget? header;

  /// The animated media area — where the animation happens. Each
  /// feature provides its own widget that reads the [reducedMotion]
  /// flag (via its own constructor parameter) and suppresses its
  /// animation when true.
  final Widget mediaArea;

  /// The card title (one line, ellipsized). Rendered below the
  /// [mediaArea] in [KinrelTypography.headlineSmall] (w700) to match
  /// the real card layout in both Memories and Oral History.
  final String title;

  /// The card description (up to 2 lines, ellipsized). Rendered below
  /// the [title] in [KinrelTypography.bodySmall] (height 1.5) to
  /// match the real card layout.
  final String description;

  /// The fixed width of the preview card. Defaults to 240 — matches
  /// the width that reads as a real timeline/story card rather than
  /// a tiny icon chip.
  final double width;

  @override
  Widget build(BuildContext context) {
    final border = accentColor != null
        ? Border.all(
            color: accentColor!.withValues(alpha: 0.25),
            width: 1,
          )
        : Border.all(color: const Color(0xFF3A3A4A), width: 0.5);
    final shadow = accentColor != null
        ? [
            BoxShadow(
              color: accentColor!.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ]
        : null;

    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(KinrelSpacing.base),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
          border: border,
          boxShadow: shadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (header != null) ...[
              header!,
              const SizedBox(height: 10),
            ],
            // The animated media area. Each feature provides its own
            // widget here — see _MemoryPhotoCrossfade (Memories) and
            // _StoryWaveformPulse (Oral History). The widget is
            // responsible for respecting the reducedMotion flag.
            mediaArea,
            const SizedBox(height: 10),
            Text(
              title,
              style: KinrelTypography.headlineSmall.copyWith(
                color: KinrelColors.textWhite,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: KinrelTypography.bodySmall.copyWith(
                color: KinrelColors.textSilver,
                height: 1.5,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

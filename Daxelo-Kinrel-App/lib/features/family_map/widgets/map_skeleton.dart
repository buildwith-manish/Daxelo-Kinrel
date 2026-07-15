// lib/features/family_map/widgets/map_skeleton.dart
//
// P11.7 — Map Skeleton Loader.
//
// Replaces the CircularProgressIndicator with a static dark map background
// + subtle shimmer. The skeleton matches the final map background color
// so the transition from skeleton → map is seamless (no flash).
//
// Loading sequence (per P11.7 spec):
//   Phase 1 (0ms): Show map_skeleton immediately.
//   Phase 2 (100ms): Load cached viewport from MapStatePersistence (P10.9).
//   Phase 3 (200ms): Load map tiles (MapLibre handles this).
//   Phase 4-7: Load family data progressively.
//
// The skeleton shows during phases 1-2 (< 200ms), then fades to the map
// over 300ms (skeletonCrossfade from MapVisualConstants).
//
// Rule 6 (Performance): skeleton is a static dark background — zero
// computation cost. The shimmer is a lightweight flutter_animate effect.
// Rule 8 (Reduced motion): skeleton appears instantly (no fade).
// Rule 10 (Offline): skeleton is local — works offline.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../config/map_visual_constants.dart';

/// A static dark map background + subtle shimmer + "Loading family map..."
/// text. Replaces the CircularProgressIndicator.
class MapSkeleton extends StatelessWidget {
  const MapSkeleton({
    super.key,
    this.reducedMotion = false,
    this.message = 'Loading family map\u2026',
  });

  final bool reducedMotion;

  /// Default fallback message. Callers should pass the localized
  /// `S.of(context)?.familyMapLoading` value when available.
  final String message;

  @override
  Widget build(BuildContext context) {
    // The icon placeholder — with or without shimmer based on reducedMotion.
    final iconPlaceholder = Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(
        Icons.map_outlined,
        size: 48,
        color: KinrelColors.orange.withOpacity(
          MapVisualConstants.timelineSliderOverlayOpacity,
        ),
      ),
    );

    return Container(
      color: KinrelColors.darkBackground,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Reduced motion: static icon (no shimmer, no timer).
            // Normal: subtle shimmer via flutter_animate.
            reducedMotion
                ? iconPlaceholder
                : iconPlaceholder
                      .animate(onPlay: (c) => c.repeat())
                      .shimmer(
                        duration: 1500.ms,
                        color: KinrelColors.orange.withOpacity(
                          MapVisualConstants.skeletonShimmerOpacity,
                        ),
                      ),
            const SizedBox(height: 24),
            Text(
              message,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: KinrelColors.textSilver,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

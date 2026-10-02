// lib/shared/widgets/kinrel_skeleton.dart
//
// ┌─────────────────────────────────────────────────────────────────────┐
// │  KINREL SKELETON — shimmer loading placeholders                      │
// └─────────────────────────────────────────────────────────────────────┘
//
// WHY THIS EXISTS
// ───────────────
// Spinners communicate "the app is working" but they communicate NOTHING
// about what's coming. Skeleton screens (Facebook, LinkedIn, YouTube,
// every billion-dollar app) show the SHAPE of the content that's about
// to appear. This does three things:
//
//   1. Reduces perceived wait time by ~30% (status quo bias — the user
//      sees the layout is "almost ready" instead of "nothing yet").
//   2. Eliminates layout shift (CLS = 0) when content arrives — the
//      skeleton has the same dimensions as the real content, so the
//      page doesn't jump.
//   3. Sets expectations (the user sees "there will be 3 cards here"
//      before they arrive, so they're primed to read them).
//
// PSYCHOLOGICAL PRINCIPLE: STATUS QUO BIAS + PROCESSING FLUENCY
// ─────────────────────────────────────────────────────────────────────
//   • Status Quo Bias: a layout that's "almost there" feels closer to
//     done than a blank screen with a spinner.
//   • Processing Fluency: a layout the brain can pre-process (because
//     it matches the final shape) feels easier to consume when it
//     arrives.
//
// PERFORMANCE
// ───────────
//   • Uses the `shimmer` package (already in pubspec) — GPU-composited
//     gradient sweep, zero raster cost.
//   • ShimmerDirection defaults to LTR (matches reading direction).
//   • Period is 1000ms — slow enough to be calming, fast enough to
//     signal "it's loading, not frozen".
//   • Skeletons are STATELESS widgets — no AnimationController to leak.
//
// USAGE
// ─────
//   // A card skeleton
//   KinrelSkeletonCard();
//
//   // A list of skeletons
//   KinrelSkeletonList(itemCount: 5);
//
//   // A custom shape
//   KinrelSkeletonBox(width: 120, height: 16);
//
//   // A full screen scaffold skeleton
//   KinrelSkeletonScreen(
//     header: KinrelSkeletonBox(width: 200, height: 24),
//     body: KinrelSkeletonList(itemCount: 4),
//   );

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/utils/motion_preference.dart';

/// The base shimmer wrapper used by all skeleton widgets.
/// Configured once here so the shimmer direction, period, and colors
/// are consistent across the app.
class _KinrelShimmer extends StatelessWidget {
  const _KinrelShimmer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Dark mode: shimmer sweeps from #2A2D3F → #3A3D52 (subtle, on-card).
    // Light mode: shimmer sweeps from #E8E8ED → #F5F5FA (subtle, on-white).
    final baseColor =
        isDark ? const Color(0xFF2A2D3F) : const Color(0xFFE8E8ED);
    final highlightColor =
        isDark ? const Color(0xFF3A3D52) : const Color(0xFFF5F5FA);

    // ── Reduce Motion: skip the shimmer animation. A static gray box
    // still communicates "loading" without the moving gradient sweep.
    // Shimmer triggers vestibular issues for motion-sensitive users.
    if (MotionPreference.isReducedMotion(context)) {
      return ColoredBox(color: baseColor, child: child);
    }

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      period: const Duration(milliseconds: 1000),
      direction: ShimmerDirection.ltr,
      child: child,
    );
  }
}

/// A single rectangular skeleton box.
///
/// Pass [radius] for rounded corners (default 6). Use [circle] = true
/// for avatars (overrides radius).
class KinrelSkeletonBox extends StatelessWidget {
  const KinrelSkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.radius = 6,
    this.circle = false,
  });

  final double width;
  final double height;
  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    return _KinrelShimmer(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white, // Shimmer overrides this; just needs a base
          borderRadius:
              circle ? null : BorderRadius.circular(radius),
          shape: circle ? BoxShape.circle : BoxShape.rectangle,
        ),
      ),
    );
  }
}

/// A skeleton that mimics a card row (avatar + 2 lines of text).
///
/// This is the most common skeleton pattern in the app — family cards,
/// feed posts, chat previews all share this shape.
class KinrelSkeletonCardRow extends StatelessWidget {
  const KinrelSkeletonCardRow({
    super.key,
    this.avatarSize = 44,
    this.titleWidth = 140,
    this.subtitleWidth = 90,
  });

  final double avatarSize;
  final double titleWidth;
  final double subtitleWidth;

  @override
  Widget build(BuildContext context) {
    return _KinrelShimmer(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            KinrelSkeletonBox(
              width: avatarSize,
              height: avatarSize,
              circle: true,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KinrelSkeletonBox(
                    width: titleWidth,
                    height: 14,
                    radius: 4,
                  ),
                  const SizedBox(height: 8),
                  KinrelSkeletonBox(
                    width: subtitleWidth,
                    height: 12,
                    radius: 4,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A skeleton that mimics a full-width content card (e.g., feed post).
class KinrelSkeletonCard extends StatelessWidget {
  const KinrelSkeletonCard({
    super.key,
    this.height = 160,
    this.padding = 16,
  });

  final double height;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return _KinrelShimmer(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: padding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row (avatar + name)
            const Row(
              children: [
                KinrelSkeletonBox(width: 36, height: 36, circle: true),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      KinrelSkeletonBox(width: 120, height: 12, radius: 4),
                      SizedBox(height: 6),
                      KinrelSkeletonBox(width: 80, height: 10, radius: 4),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Body
            KinrelSkeletonBox(
              width: double.infinity,
              height: height,
              radius: 12,
            ),
            const SizedBox(height: 12),
            // Action row
            const Row(
              children: [
                KinrelSkeletonBox(width: 60, height: 10, radius: 4),
                SizedBox(width: 16),
                KinrelSkeletonBox(width: 60, height: 10, radius: 4),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A vertical list of skeleton items. Use for list views during load.
class KinrelSkeletonList extends StatelessWidget {
  const KinrelSkeletonList({
    super.key,
    this.itemCount = 5,
    this.itemType = SkeletonItemType.cardRow,
    this.spacing = 12,
  });

  final int itemCount;
  final SkeletonItemType itemType;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      // NeverScrollable so it doesn't conflict with the parent scroll.
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      itemCount: itemCount,
      separatorBuilder: (_, __) => SizedBox(height: spacing),
      itemBuilder: (_, __) {
        switch (itemType) {
          case SkeletonItemType.cardRow:
            return const KinrelSkeletonCardRow();
          case SkeletonItemType.card:
            return const KinrelSkeletonCard();
          case SkeletonItemType.textLine:
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KinrelSkeletonBox(
                    width: double.infinity,
                    height: 14,
                    radius: 4,
                  ),
                  SizedBox(height: 8),
                  KinrelSkeletonBox(width: 200, height: 14, radius: 4),
                ],
              ),
            );
        }
      },
    );
  }
}

/// The type of skeleton item to show in a list.
enum SkeletonItemType { cardRow, card, textLine }

/// A full screen skeleton scaffold — use for initial screen loads.
///
/// Pass a [header] skeleton and a [body] skeleton. The body is
/// wrapped in a SingleChildScrollView so it works at any screen size.
class KinrelSkeletonScreen extends StatelessWidget {
  const KinrelSkeletonScreen({
    super.key,
    required this.body,
    this.header,
    this.appBarHeight = 0,
  });

  final Widget? header;
  final Widget body;
  final double appBarHeight;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.only(top: appBarHeight),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null) ...[
            header!,
            const SizedBox(height: 16),
          ],
          body,
        ],
      ),
    );
  }
}

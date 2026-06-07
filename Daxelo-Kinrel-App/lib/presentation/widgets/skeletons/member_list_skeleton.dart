// lib/presentation/widgets/skeletons/member_list_skeleton.dart
//
// DAXELO KINREL — Member List Skeleton Screen
//
// Shimmer-based skeleton matching the real _MemberCard layout exactly:
//   • DKCard with 12dp padding
//   • DKAvatar (DKAvatarSize.md = 40dp)
//   • 12dp gap between avatar and text
//   • Name shimmer (140dp wide, 14dp tall)
//   • Gender/subtitle shimmer (80dp wide, 12dp tall)
//   • Chip shimmer (60dp wide, 20dp tall)
//
// On DeviceTier.low: plain grey Container of same size, no animation.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/utils/device_tier.dart';
import '../../../shared/widgets/dk_components.dart';

class MemberListSkeleton extends ConsumerWidget {
  const MemberListSkeleton({super.key, this.itemCount = 6});

  final int itemCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tier = DeviceTierCache.instance.tier;
    final isLight = DKColors.isLight(context);

    // On low-end devices, skip shimmer animation — use plain grey containers
    if (tier == DeviceTier.low) {
      return _buildStaticSkeleton(context, isLight);
    }

    return Shimmer.fromColors(
      baseColor: isLight
          ? const Color(0xFFE0E0E0)
          : DKColors.darkElevated,
      highlightColor: isLight
          ? const Color(0xFFF5F5F5)
          : DKColors.darkSurface,
      period: const Duration(milliseconds: 1500),
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
        itemCount: itemCount,
        itemBuilder: (context, index) => _buildSkeletonItem(context, isLight),
      ),
    );
  }

  Widget _buildStaticSkeleton(BuildContext context, bool isLight) {
    final staticColor = isLight
        ? const Color(0xFFE0E0E0)
        : KinrelColors.darkElevated;

    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      itemCount: itemCount,
      itemBuilder: (context, index) => _buildStaticItem(staticColor),
    );
  }

  /// Animated shimmer item — matches _MemberCard layout exactly
  Widget _buildSkeletonItem(BuildContext context, bool isLight) {
    final containerColor = isLight ? Colors.white : DKColors.darkCard;
    final borderColor = isLight
        ? null
        : KinrelColors.purple.withValues(alpha: 0.15);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: containerColor,
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
          border: borderColor != null
              ? Border.all(color: borderColor, width: 1)
              : null,
        ),
        child: Row(
          children: [
            // Avatar placeholder — 40dp circle (DKAvatarSize.md)
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),

            // Text + chip placeholders
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name shimmer
                  Container(
                    width: 140,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Gender/subtitle shimmer
                  Container(
                    width: 80,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Chip shimmer
                  Container(
                    width: 60,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(KinrelRadius.full),
                    ),
                  ),
                ],
              ),
            ),

            // Gender icon placeholder
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Static item for low-tier devices — same layout, plain grey containers
  Widget _buildStaticItem(Color staticColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
          border: Border.all(
            color: KinrelColors.purple.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Avatar placeholder
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: staticColor,
              ),
            ),
            const SizedBox(width: 12),

            // Text + chip placeholders
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 140,
                    height: 14,
                    decoration: BoxDecoration(
                      color: staticColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 80,
                    height: 12,
                    decoration: BoxDecoration(
                      color: staticColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 60,
                    height: 20,
                    decoration: BoxDecoration(
                      color: staticColor,
                      borderRadius: BorderRadius.circular(KinrelRadius.full),
                    ),
                  ),
                ],
              ),
            ),

            // Gender icon placeholder
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: staticColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

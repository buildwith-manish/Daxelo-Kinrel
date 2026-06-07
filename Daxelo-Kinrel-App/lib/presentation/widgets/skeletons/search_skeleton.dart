// lib/presentation/widgets/skeletons/search_skeleton.dart
//
// DAXELO KINREL — Search Skeleton Screen
//
// Shimmer-based skeleton matching the real search screen layout:
//   • Shimmer search bar at top
//   • 5 shimmer rows matching search result layout
//   • Each row: CircleAvatar (radius 20) + name + subtitle + chevron
//
// On DeviceTier.low: plain grey Container of same size, no animation.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/utils/device_tier.dart';
import '../../../shared/widgets/dk_components.dart';

class SearchSkeleton extends ConsumerWidget {
  const SearchSkeleton({super.key, this.itemCount = 5});

  final int itemCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tier = DeviceTierCache.instance.tier;
    final isLight = DKColors.isLight(context);

    if (tier == DeviceTier.low) {
      return _buildStaticSkeleton(isLight);
    }

    return Shimmer.fromColors(
      baseColor: isLight
          ? const Color(0xFFE0E0E0)
          : DKColors.darkElevated,
      highlightColor: isLight
          ? const Color(0xFFF5F5F5)
          : DKColors.darkSurface,
      period: const Duration(milliseconds: 1500),
      child: Column(
        children: [
          // ── Search bar shimmer ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(KinrelSpacing.base),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: isLight ? Colors.white : DKColors.darkCard,
                borderRadius: BorderRadius.circular(KinrelRadius.xl),
              ),
            ),
          ),

          // ── Filter chips row shimmer ───────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KinrelSpacing.base,
              vertical: KinrelSpacing.xs,
            ),
            child: Row(
              children: [
                _buildChipSkeleton(isLight),
                const SizedBox(width: KinrelSpacing.sm),
                _buildChipSkeleton(isLight),
                const SizedBox(width: KinrelSpacing.sm),
                _buildChipSkeleton(isLight),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── Search result rows ─────────────────────────────────────
          Expanded(
            child: ListView.builder(
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(
                horizontal: KinrelSpacing.base,
                vertical: KinrelSpacing.sm,
              ),
              itemCount: itemCount,
              itemBuilder: (context, index) =>
                  _buildSkeletonResultRow(isLight),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChipSkeleton(bool isLight) {
    return Container(
      width: 60,
      height: 32,
      decoration: BoxDecoration(
        color: isLight ? Colors.white : DKColors.darkCard,
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }

  /// Animated shimmer result row — matches _buildPersonCard layout exactly
  Widget _buildSkeletonResultRow(bool isLight) {
    final containerColor = isLight ? Colors.white : DKColors.darkCard;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: containerColor,
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
          border: isLight
              ? null
              : Border.all(
                  color: const Color(0xFF3A3A4A),
                  width: 1,
                ),
        ),
        child: Row(
          children: [
            // CircleAvatar placeholder (radius 20 = diameter 40)
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),

            // Name + subtitle placeholders
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name shimmer
                  Container(
                    width: 140,
                    height: 15,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Subtitle shimmer (ID + Family)
                  Row(
                    children: [
                      Container(
                        width: 60,
                        height: 11,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 40,
                        height: 11,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Chevron placeholder
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Static skeleton for low-tier devices ──────────────────────────

  Widget _buildStaticSkeleton(bool isLight) {
    final staticColor = isLight
        ? const Color(0xFFE0E0E0)
        : KinrelColors.darkElevated;

    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.all(KinrelSpacing.base),
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: staticColor,
              borderRadius: BorderRadius.circular(KinrelRadius.xl),
            ),
          ),
        ),

        // Filter chips
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: KinrelSpacing.base,
            vertical: KinrelSpacing.xs,
          ),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 32,
                decoration: BoxDecoration(
                  color: staticColor,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              const SizedBox(width: KinrelSpacing.sm),
              Container(
                width: 60,
                height: 32,
                decoration: BoxDecoration(
                  color: staticColor,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              const SizedBox(width: KinrelSpacing.sm),
              Container(
                width: 60,
                height: 32,
                decoration: BoxDecoration(
                  color: staticColor,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Result rows
        Expanded(
          child: ListView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(
              horizontal: KinrelSpacing.base,
              vertical: KinrelSpacing.sm,
            ),
            itemCount: itemCount,
            itemBuilder: (context, index) =>
                _buildStaticResultRow(staticColor, isLight),
          ),
        ),
      ],
    );
  }

  Widget _buildStaticResultRow(Color staticColor, bool isLight) {
    final cardBg = isLight ? Colors.white : KinrelColors.darkCard;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
          border: isLight
              ? null
              : Border.all(
                  color: const Color(0xFF3A3A4A),
                  width: 1,
                ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: staticColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 140,
                    height: 15,
                    decoration: BoxDecoration(
                      color: staticColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 60,
                        height: 11,
                        decoration: BoxDecoration(
                          color: staticColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 40,
                        height: 11,
                        decoration: BoxDecoration(
                          color: staticColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: staticColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

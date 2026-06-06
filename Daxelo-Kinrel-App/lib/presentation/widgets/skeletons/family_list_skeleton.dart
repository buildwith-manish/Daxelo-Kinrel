// lib/presentation/widgets/skeletons/family_list_skeleton.dart
//
// DAXELO KINREL — Family List Skeleton Screen
//
// Shimmer-based skeleton matching the real _FamilyCard layout exactly:
//   • DKAvatar (DKAvatarSize.lg = 56dp)
//   • 14dp gap between avatar and text
//   • Name shimmer + creator badge shimmer
//   • Family code shimmer
//   • Member count stat chip shimmer + language shimmer
//   • Chevron placeholder
//
// On DeviceTier.low: plain grey Container of same size, no animation.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/utils/device_tier.dart';
import '../../../shared/widgets/dk_components.dart';

class FamilyListSkeleton extends ConsumerWidget {
  const FamilyListSkeleton({super.key, this.itemCount = 4});

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
      child: ListView(
        padding: const EdgeInsets.all(KinrelSpacing.base),
        children: [
          const SizedBox(height: 60),

          // Header shimmer
          Row(
            children: [
              Container(
                width: 160,
                height: 28,
                decoration: BoxDecoration(
                  color: isLight ? Colors.white : DKColors.darkCard,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 36,
                height: 24,
                decoration: BoxDecoration(
                  color: isLight ? Colors.white : DKColors.darkCard,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Join family card shimmer
          Container(
            width: double.infinity,
            height: 72,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isLight ? Colors.white : DKColors.darkCard,
              borderRadius: BorderRadius.circular(KinrelRadius.lg),
            ),
          ),
          const SizedBox(height: 12),

          // Family card skeletons
          ...List.generate(
            itemCount,
            (_) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildSkeletonCard(isLight),
            ),
          ),
        ],
      ),
    );
  }

  /// Animated shimmer card — matches _FamilyCard layout exactly
  Widget _buildSkeletonCard(bool isLight) {
    final containerColor = isLight ? Colors.white : DKColors.darkCard;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: isLight
            ? null
            : Border.all(
                color: DKColors.brandPurple.withValues(alpha: 0.2),
                width: 1,
              ),
      ),
      child: Row(
        children: [
          // Avatar placeholder — 56dp circle (DKAvatarSize.lg)
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 14),

          // Text placeholders
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name + creator badge row
                Row(
                  children: [
                    Container(
                      width: 120,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Creator badge placeholder
                    Container(
                      width: 50,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                // Family code shimmer
                Container(
                  width: 100,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                // Member count stat chip + language
                Row(
                  children: [
                    // Stat chip placeholder
                    Container(
                      width: 80,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(KinrelRadius.full),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Language icon placeholder
                    Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Language text placeholder
                    Container(
                      width: 50,
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
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }

  // ── Static skeleton for low-tier devices ──────────────────────────

  Widget _buildStaticSkeleton(bool isLight) {
    final staticColor = isLight
        ? const Color(0xFFE0E0E0)
        : KinrelColors.darkElevated;

    return ListView(
      padding: const EdgeInsets.all(KinrelSpacing.base),
      children: [
        const SizedBox(height: 60),

        // Header
        Row(
          children: [
            Container(
              width: 160,
              height: 28,
              decoration: BoxDecoration(
                color: staticColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 36,
              height: 24,
              decoration: BoxDecoration(
                color: staticColor,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Join family card
        Container(
          width: double.infinity,
          height: 72,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: staticColor,
            borderRadius: BorderRadius.circular(KinrelRadius.lg),
          ),
        ),
        const SizedBox(height: 12),

        // Family card skeletons
        ...List.generate(
          itemCount,
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildStaticCard(staticColor, isLight),
          ),
        ),
      ],
    );
  }

  Widget _buildStaticCard(Color staticColor, bool isLight) {
    final cardBg = isLight ? Colors.white : KinrelColors.darkCard;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: isLight
            ? null
            : Border.all(
                color: DKColors.brandPurple.withValues(alpha: 0.2),
                width: 1,
              ),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: staticColor,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 120,
                      height: 16,
                      decoration: BoxDecoration(
                        color: staticColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 50,
                      height: 16,
                      decoration: BoxDecoration(
                        color: staticColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Container(
                  width: 100,
                  height: 10,
                  decoration: BoxDecoration(
                    color: staticColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      width: 80,
                      height: 20,
                      decoration: BoxDecoration(
                        color: staticColor,
                        borderRadius: BorderRadius.circular(KinrelRadius.full),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        color: staticColor,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      width: 50,
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
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: staticColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }
}

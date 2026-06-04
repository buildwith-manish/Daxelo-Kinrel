// lib/presentation/widgets/skeletons/profile_skeleton.dart
//
// DAXELO KINREL — Profile Skeleton Screen
//
// Shimmer-based skeleton matching the real ProfileScreen layout:
//   • Hero circle (100dp) for avatar
//   • 4 shimmer text lines (name, email, bio, edit button)
//   • Stats row: 3 small shimmer cards
//   • 2-3 section blocks (settings rows)
//
// On DeviceTier.low: plain grey Container of same size, no animation.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/utils/device_tier.dart';
import '../../../shared/widgets/dk_components.dart';

class ProfileSkeleton extends ConsumerWidget {
  const ProfileSkeleton({super.key});

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
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.base,
          vertical: KinrelSpacing.sm,
        ),
        child: _buildSkeletonContent(context, isLight),
      ),
    );
  }

  Widget _buildSkeletonContent(BuildContext context, bool isLight) {
    final containerColor = isLight ? Colors.white : DKColors.darkCard;
    final cardBg = isLight ? const Color(0xFFFFFFFF) : const Color(0xFF191B2C);
    const borderSubtle = Color(0x0FFFFFFF);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),

        // ── Hero Avatar Circle ─────────────────────────────────────
        Center(
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: containerColor,
              border: Border.all(
                color: isLight
                    ? const Color(0xFFE0E0E0)
                    : KinrelColors.orange,
                width: 3,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),

        // ── Name shimmer ───────────────────────────────────────────
        Center(
          child: Container(
            width: 160,
            height: 24,
            decoration: BoxDecoration(
              color: containerColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        const SizedBox(height: 4),

        // ── Email shimmer ──────────────────────────────────────────
        Center(
          child: Container(
            width: 200,
            height: 12,
            decoration: BoxDecoration(
              color: containerColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // ── Bio shimmer ────────────────────────────────────────────
        Center(
          child: Container(
            width: 240,
            height: 13,
            decoration: BoxDecoration(
              color: containerColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ── Edit Profile button shimmer ────────────────────────────
        Center(
          child: Container(
            width: 140,
            height: 38,
            decoration: BoxDecoration(
              color: containerColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isLight
                    ? const Color(0xFFE0E0E0)
                    : KinrelColors.orange,
                width: 1.5,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),

        // ── Stats Row: 3 shimmer cards ─────────────────────────────
        SizedBox(
          height: 90,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _buildStatCardSkeleton(containerColor),
              const SizedBox(width: 10),
              _buildStatCardSkeleton(containerColor),
              const SizedBox(width: 10),
              _buildStatCardSkeleton(containerColor),
            ],
          ),
        ),
        const SizedBox(height: 28),

        // ── Section 1: Account ─────────────────────────────────────
        Container(
          width: 80,
          height: 13,
          decoration: BoxDecoration(
            color: containerColor,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 8),
        _buildSectionCardSkeleton(containerColor, cardBg, borderSubtle, 5),
        const SizedBox(height: 24),

        // ── Section 2: Appearance ──────────────────────────────────
        Container(
          width: 90,
          height: 13,
          decoration: BoxDecoration(
            color: containerColor,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 8),
        _buildSectionCardSkeleton(containerColor, cardBg, borderSubtle, 3),
        const SizedBox(height: 24),

        // ── Section 3: Notifications ───────────────────────────────
        Container(
          width: 100,
          height: 13,
          decoration: BoxDecoration(
            color: containerColor,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 8),
        _buildSectionCardSkeleton(containerColor, cardBg, borderSubtle, 4),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildStatCardSkeleton(Color containerColor) {
    return Container(
      width: 120,
      height: 90,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon placeholder
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 10),
          // Value placeholder
          Container(
            width: 40,
            height: 18,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 4),
          // Label placeholder
          Container(
            width: 80,
            height: 10,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCardSkeleton(
    Color containerColor,
    Color cardBg,
    Color borderSubtle,
    int rowCount,
  ) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderSubtle),
      ),
      child: Column(
        children: List.generate(rowCount, (index) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    // Icon placeholder
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: containerColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 14),
                    // Label placeholder
                    Expanded(
                      child: Container(
                        height: 14,
                        decoration: BoxDecoration(
                          color: containerColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    // Chevron placeholder
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: containerColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
              if (index < rowCount - 1)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Divider(
                    height: 1,
                    thickness: 0.5,
                    color: borderSubtle,
                  ),
                ),
            ],
          );
        }),
      ),
    );
  }

  // ── Static skeleton for low-tier devices ──────────────────────────

  Widget _buildStaticSkeleton(bool isLight) {
    final staticColor = isLight
        ? const Color(0xFFE0E0E0)
        : KinrelColors.darkElevated;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.base,
        vertical: KinrelSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),

          // Hero avatar
          Center(
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: staticColor,
                border: Border.all(
                  color: staticColor,
                  width: 3,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Name
          Center(
            child: Container(
              width: 160,
              height: 24,
              decoration: BoxDecoration(
                color: staticColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 4),

          // Email
          Center(
            child: Container(
              width: 200,
              height: 12,
              decoration: BoxDecoration(
                color: staticColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Bio
          Center(
            child: Container(
              width: 240,
              height: 13,
              decoration: BoxDecoration(
                color: staticColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Edit button
          Center(
            child: Container(
              width: 140,
              height: 38,
              decoration: BoxDecoration(
                color: staticColor,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Stats row
          SizedBox(
            height: 90,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _buildStaticStatCard(staticColor),
                const SizedBox(width: 10),
                _buildStaticStatCard(staticColor),
                const SizedBox(width: 10),
                _buildStaticStatCard(staticColor),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // Section headers + cards
          Container(
            width: 80,
            height: 13,
            decoration: BoxDecoration(
              color: staticColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 8),
          _buildStaticSectionCard(staticColor, 5),
          const SizedBox(height: 24),

          Container(
            width: 90,
            height: 13,
            decoration: BoxDecoration(
              color: staticColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 8),
          _buildStaticSectionCard(staticColor, 3),
          const SizedBox(height: 24),

          Container(
            width: 100,
            height: 13,
            decoration: BoxDecoration(
              color: staticColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 8),
          _buildStaticSectionCard(staticColor, 4),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildStaticStatCard(Color staticColor) {
    return Container(
      width: 120,
      height: 90,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: staticColor,
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  Widget _buildStaticSectionCard(Color staticColor, int rowCount) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: List.generate(rowCount, (index) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: staticColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Container(
                        height: 14,
                        decoration: BoxDecoration(
                          color: staticColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: staticColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
              if (index < rowCount - 1)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Divider(height: 1, thickness: 0.5, color: Color(0x0FFFFFFF)),
                ),
            ],
          );
        }),
      ),
    );
  }
}

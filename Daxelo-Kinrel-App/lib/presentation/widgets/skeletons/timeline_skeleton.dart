// lib/presentation/widgets/skeletons/timeline_skeleton.dart
//
// DAXELO KINREL — Timeline/Events Skeleton Screen
//
// Shimmer-based skeleton matching the real _EventCard layout:
//   • Card with 24dp padding, rounded corners
//   • Type badge placeholder + notification icon
//   • Event name shimmer (18dp font equivalent)
//   • Date/time shimmer row
//   • Description shimmer (2 lines)
//   • Bottom row: countdown chip + RSVP chip
//
// On DeviceTier.low: plain grey Container of same size, no animation.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/utils/device_tier.dart';
import '../../../shared/widgets/dk_components.dart';

class TimelineSkeleton extends ConsumerWidget {
  const TimelineSkeleton({super.key, this.itemCount = 4});

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
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          KinrelSpacing.base,
          0,
          KinrelSpacing.base,
          100,
        ),
        itemCount: itemCount,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) => _buildSkeletonCard(isLight),
      ),
    );
  }

  /// Animated shimmer card — matches _EventCard layout exactly
  Widget _buildSkeletonCard(bool isLight) {
    final containerColor = isLight ? Colors.white : DKColors.darkCard;
    return Container(
      padding: const EdgeInsets.all(KinrelSpacing.xl),
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(
          color: isLight
              ? const Color(0xFFE5E7EB)
              : const Color(0xFF3A3A4A),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top row: type badge + notification icon ────────────────
          Row(
            children: [
              // Type badge placeholder
              Container(
                width: 80,
                height: 22,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(KinrelRadius.full),
                ),
              ),
              const Spacer(),
              // Notification icon placeholder
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(KinrelRadius.sm),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ── Event Name shimmer ─────────────────────────────────────
          Container(
            width: double.infinity,
            height: 18,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: 180,
            height: 18,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),

          const SizedBox(height: 8),

          // ── Date/time shimmer ──────────────────────────────────────
          Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 140,
                height: 13,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // ── Description shimmer (2 lines) ──────────────────────────
          Container(
            width: double.infinity,
            height: 13,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 240,
            height: 13,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),

          const SizedBox(height: 14),

          // ── Bottom row: countdown chip + action chip ───────────────
          Row(
            children: [
              // Countdown chip
              Container(
                width: 80,
                height: 24,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(KinrelRadius.full),
                ),
              ),
              const Spacer(),
              // Action chip (RSVP / Send wishes)
              Container(
                width: 100,
                height: 24,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(KinrelRadius.full),
                ),
              ),
            ],
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

    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        KinrelSpacing.base,
        0,
        KinrelSpacing.base,
        100,
      ),
      itemCount: itemCount,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _buildStaticCard(staticColor, isLight),
    );
  }

  Widget _buildStaticCard(Color staticColor, bool isLight) {
    final cardBg = isLight ? Colors.white : KinrelColors.darkCard;

    return Container(
      padding: const EdgeInsets.all(KinrelSpacing.xl),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(
          color: isLight
              ? const Color(0xFFE5E7EB)
              : const Color(0xFF3A3A4A),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 80,
                height: 22,
                decoration: BoxDecoration(
                  color: staticColor,
                  borderRadius: BorderRadius.circular(KinrelRadius.full),
                ),
              ),
              const Spacer(),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: staticColor,
                  borderRadius: BorderRadius.circular(KinrelRadius.sm),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            height: 18,
            decoration: BoxDecoration(
              color: staticColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: 180,
            height: 18,
            decoration: BoxDecoration(
              color: staticColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: staticColor,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 140,
                height: 13,
                decoration: BoxDecoration(
                  color: staticColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            height: 13,
            decoration: BoxDecoration(
              color: staticColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 240,
            height: 13,
            decoration: BoxDecoration(
              color: staticColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 80,
                height: 24,
                decoration: BoxDecoration(
                  color: staticColor,
                  borderRadius: BorderRadius.circular(KinrelRadius.full),
                ),
              ),
              const Spacer(),
              Container(
                width: 100,
                height: 24,
                decoration: BoxDecoration(
                  color: staticColor,
                  borderRadius: BorderRadius.circular(KinrelRadius.full),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

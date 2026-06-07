// lib/presentation/widgets/sparq_feed_row.dart
//
// DAXELO KINREL — Sparq Feed Row
//
// Horizontal ListView at the top of the HomeScreen:
//   • First item: "Your Sparq" → own avatar + "+" icon
//   • Remaining: other users grouped, unseen first
//   • Loading state: shimmer placeholders
//   • Empty state: hidden

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/constants/brand_colors.dart';
import '../../core/constants/brand_typography.dart';
import '../../features/profile/data/profile_provider.dart';
import '../providers/sparq_provider.dart';
import 'sparq_ring_avatar.dart';

class SparqFeedRow extends ConsumerWidget {
  const SparqFeedRow({
    super.key,
    this.onOwnTap,
    this.onUserTap,
  });

  final VoidCallback? onOwnTap;
  final void Function(String userId)? onUserTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sparqState = ref.watch(sparqProvider);
    final profile = ref.watch(profileProvider.select((s) => s.profile));

    // Loading state → shimmer placeholders
    if (sparqState.isLoading && sparqState.feed.isEmpty) {
      return _buildShimmerRow();
    }

    // Empty state → hidden
    if (sparqState.feed.isEmpty && sparqState.mySparqs.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: sparqState.feed.length + 1, // +1 for "Your Sparq"
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          // First item: "Your Sparq"
          if (index == 0) {
            return _OwnSparqItem(
              avatarUrl: profile?.avatarUrl,
              initials: profile?.name != null && profile!.name!.isNotEmpty
                  ? profile.name![0].toUpperCase()
                  : 'U',
              onTap: onOwnTap,
            );
          }

          // Other users
          final group = sparqState.feed[index - 1];
          return _UserSparqItem(
            userId: group.userId,
            avatarUrl: group.user.avatarUrl,
            initials: group.initials,
            name: group.user.name ?? group.user.username ?? 'User',
            hasUnseen: group.hasUnseen,
            onTap: () => onUserTap?.call(group.userId),
          );
        },
      ),
    );
  }

  Widget _buildShimmerRow() {
    return SizedBox(
      height: 96,
      child: Shimmer.fromColors(
        baseColor: KinrelColors.darkElevated,
        highlightColor: KinrelColors.darkCard,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: 6,
          separatorBuilder: (_, __) => const SizedBox(width: 14),
          itemBuilder: (context, index) => Column(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: KinrelColors.darkElevated,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: 48,
                height: 10,
                decoration: BoxDecoration(
                  color: KinrelColors.darkElevated,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Your Sparq" item with "+" icon overlay.
class _OwnSparqItem extends StatelessWidget {
  const _OwnSparqItem({
    this.avatarUrl,
    this.initials,
    this.onTap,
  });

  final String? avatarUrl;
  final String? initials;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: KinrelColors.orange.withValues(alpha: 0.3),
                    width: 2,
                  ),
                  image: avatarUrl != null
                      ? DecorationImage(
                          image: NetworkImage(avatarUrl!),
                          fit: BoxFit.cover,
                        )
                      : null,
                  color: avatarUrl != null
                      ? null
                      : KinrelColors.orange.withValues(alpha: 0.1),
                ),
                child: avatarUrl != null
                    ? null
                    : Center(
                        child: Text(
                          initials ?? 'U',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: KinrelColors.orange,
                          ),
                        ),
                      ),
              ),
              // "+" icon
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: KinrelGradients.igniteGradient,
                    border: Border.all(
                      color: KinrelColors.darkBackground,
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.add,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 64,
            child: Text(
              'Your Sparq',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: KinrelColors.textSilver,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// User sparq item in the feed row.
class _UserSparqItem extends StatelessWidget {
  const _UserSparqItem({
    required this.userId,
    this.avatarUrl,
    this.initials,
    this.name = 'User',
    this.hasUnseen = false,
    this.onTap,
  });

  final String userId;
  final String? avatarUrl;
  final String? initials;
  final String name;
  final bool hasUnseen;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SparqRingAvatar(
            userId: userId,
            imageUrl: avatarUrl,
            initials: initials,
            size: 64,
            onTap: onTap,
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 64,
            child: Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 10,
                fontWeight: hasUnseen ? FontWeight.w600 : FontWeight.w400,
                color: hasUnseen
                    ? KinrelColors.textWhite
                    : KinrelColors.textSilver,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

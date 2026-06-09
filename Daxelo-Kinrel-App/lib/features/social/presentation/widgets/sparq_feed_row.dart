import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/brand_colors.dart';
import '../../../../core/services/supabase_service.dart';
import '../../data/models/sparq_model.dart';
import '../../data/providers/sparq_provider.dart';
import 'sparq_ring_avatar.dart';

/// SparqFeedRow — horizontal scrollable list of SparqRingAvatars.
///
/// First item is the current user's avatar with a "+" icon for creating Sparqs.
/// Users with unseen Sparqs appear before users with all-seen Sparqs.
/// Mood emoji badges shown on avatars.
class SparqFeedRow extends ConsumerStatefulWidget {
  const SparqFeedRow({super.key});

  @override
  ConsumerState<SparqFeedRow> createState() => _SparqFeedRowState();
}

class _SparqFeedRowState extends ConsumerState<SparqFeedRow> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) {
        ref.read(sparqProvider.notifier).refreshFeed();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final sparqState = ref.watch(sparqProvider);

    if (sparqState.isLoading && sparqState.feed.isEmpty) {
      return _buildShimmerSkeleton();
    }

    // Sort: unseen first, then seen
    final sortedGroups = List<UserSparqGroup>.from(sparqState.feed)
      ..sort((a, b) {
        final aSeen = a.allSeen;
        final bSeen = b.allSeen;
        if (!aSeen && bSeen) return -1;
        if (aSeen && !bSeen) return 1;
        return 0;
      });

    // Get current user ID
    String? currentUserId;
    try {
      final client = ref.read(supabaseProvider);
      currentUserId = client?.auth.currentUser?.id;
    } catch (_) {}

    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: sortedGroups.length + 1, // +1 for "Add" button
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          // First item: current user's create Sparq button
          if (index == 0) {
            return _buildCreateSparqItem(currentUserId);
          }

          final group = sortedGroups[index - 1];
          // Get the most recent sparq for mood/intensity info
          final latestSparq = group.sparqs.isNotEmpty ? group.sparqs.first : null;

          return Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  SparqRingAvatar(
                    userId: group.userId,
                    avatarUrl: group.userAvatarUrl,
                    radius: 26,
                    intensity: latestSparq?.intensity,
                    isTimeCapsule: latestSparq?.isTimeCapsule ?? false,
                    isSeen: group.allSeen,
                    mood: latestSparq?.mood,
                    onTap: () {
                      context.push('/sparq/viewer/${group.userId}');
                    },
                  ),
                  // Mood emoji badge (bottom-right)
                  if (latestSparq != null)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: KinrelColors.darkBackground,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          latestSparq.moodEmoji,
                          style: TextStyle(fontSize: 9),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: 56,
                child: Text(
                  group.userName,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: KinrelColors.textSilver,
                    fontFamily: 'DM Sans',
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCreateSparqItem(String? userId) {
    return Column(
      children: [
        GestureDetector(
          onTap: () => context.push('/sparq/create'),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: KinrelColors.elevation1,
              border: Border.all(
                color: KinrelColors.orange.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
            child: Icon(
              Icons.add,
              color: KinrelColors.orange,
              size: 28,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'You',
          style: TextStyle(
            fontSize: 11,
            color: KinrelColors.textSilver,
            fontFamily: 'DM Sans',
          ),
        ),
      ],
    );
  }

  /// Shimmer skeleton loading state
  Widget _buildShimmerSkeleton() {
    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: 6,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          return Column(
            children: [
              _ShimmerCircle(size: 56),
              const SizedBox(height: 4),
              _ShimmerRect(width: 40, height: 8),
            ],
          );
        },
      ),
    );
  }
}

/// Simple shimmer animation circle
class _ShimmerCircle extends StatefulWidget {
  final double size;
  const _ShimmerCircle({required this.size});

  @override
  State<_ShimmerCircle> createState() => _ShimmerCircleState();
}

class _ShimmerCircleState extends State<_ShimmerCircle>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final opacity = 0.15 + (_controller.value * 0.1);
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: KinrelColors.textSilver.withValues(alpha: opacity),
          ),
        );
      },
    );
  }
}

/// Simple shimmer animation rectangle
class _ShimmerRect extends StatefulWidget {
  final double width;
  final double height;
  const _ShimmerRect({required this.width, required this.height});

  @override
  State<_ShimmerRect> createState() => _ShimmerRectState();
}

class _ShimmerRectState extends State<_ShimmerRect>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final opacity = 0.15 + (_controller.value * 0.1);
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: KinrelColors.textSilver.withValues(alpha: opacity),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      },
    );
  }
}

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
/// Clean, premium design — no emojis in UI chrome.
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

  // ── Mood accent color helper ──────────────────────────────────────

  Color _getMoodAccent(String? mood) {
    switch (mood) {
      case 'happy': return const Color(0xFFFFB300);
      case 'hype': return const Color(0xFFFF5722);
      case 'love': return const Color(0xFFE91E63);
      case 'sad': return const Color(0xFF5C7AEA);
      case 'celebrate': return const Color(0xFFD4AF37);
      case 'angry': return const Color(0xFFFF1744);
      default: return KinrelColors.orange;
    }
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
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: sortedGroups.length + 1, // +1 for "Add" button
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          // First item: current user's create Sparq button
          if (index == 0) {
            return _buildCreateSparqItem(currentUserId);
          }

          final group = sortedGroups[index - 1];
          final latestSparq = group.sparqs.isNotEmpty ? group.sparqs.first : null;
          final moodAccent = _getMoodAccent(latestSparq?.mood);

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
                  // Mood indicator dot (bottom-right) — subtle, no emoji
                  if (latestSparq != null && latestSparq.mood.isNotEmpty)
                    Positioned(
                      right: -1,
                      bottom: -1,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: moodAccent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF080808),
                            width: 2,
                          ),
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
                    color: group.allSeen ? KinrelColors.textDim : KinrelColors.textSilver,
                    fontFamily: 'DM Sans',
                    fontWeight: group.allSeen ? FontWeight.w400 : FontWeight.w500,
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
              color: const Color(0xFF1A1A1A),
              border: Border.all(
                color: KinrelColors.orange.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: Icon(
              Icons.add,
              color: KinrelColors.orange,
              size: 24,
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
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  /// Shimmer skeleton loading state
  Widget _buildShimmerSkeleton() {
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: 6,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
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
        final opacity = 0.08 + (_controller.value * 0.06);
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: opacity),
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
        final opacity = 0.08 + (_controller.value * 0.06);
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: opacity),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      },
    );
  }
}

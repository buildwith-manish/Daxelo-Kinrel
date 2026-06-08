import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/brand_colors.dart';
import '../../../../core/services/supabase_service.dart';
import '../../data/providers/sparq_provider.dart';
import 'sparq_ring_avatar.dart';

/// SparqFeedRow — horizontal scrollable list of SparqRingAvatars.
///
/// First item is the current user's avatar with a "+" icon for creating Sparqs.
/// Users with unseen Sparqs appear before users with all-seen Sparqs.
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
      return _buildLoadingSkeleton();
    }

    // Sort: unseen first, then seen
    final sortedGroups = List<UserSparqGroup>.from(sparqState.feed)
      ..sort((a, b) {
        if (!a.allSeen && b.allSeen) return -1;
        if (a.allSeen && !b.allSeen) return 1;
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
          return Column(
            children: [
              SparqRingAvatar(
                userId: group.userId,
                avatarUrl: group.userAvatarUrl,
                radius: 26,
                onTap: () {
                  context.push('/sparq/viewer/${group.userId}');
                },
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

  Widget _buildLoadingSkeleton() {
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
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: KinrelColors.elevation1,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: 40,
                height: 8,
                decoration: BoxDecoration(
                  color: KinrelColors.elevation1,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

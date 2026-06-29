// lib/features/community/presentation/community_detail_screen.dart
//
// DAXELO KINREL — Community Detail Screen
//
// Shows community info, tabs for Posts and Events, join/leave, RSVP.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../providers/community_provider.dart';
import '../services/community_service.dart';

const _cOrange = KinrelColors.orange;
const _cCard = KinrelColors.darkCard;
const _cElevated = KinrelColors.darkElevated;
const _cTextPrimary = KinrelColors.textWhite;
const _cTextSecondary = KinrelColors.textSilver;
const _cTextDim = KinrelColors.textDim;

class CommunityDetailScreen extends ConsumerStatefulWidget {
  const CommunityDetailScreen({super.key, required this.communityId});
  final String communityId;

  @override
  ConsumerState<CommunityDetailScreen> createState() => _CommunityDetailScreenState();
}

class _CommunityDetailScreenState extends ConsumerState<CommunityDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final communityAsync = ref.watch(communityDetailProvider(widget.communityId));
    final actionState = ref.watch(communityActionProvider);

    return Scaffold(
      backgroundColor: KinrelColors.darkBackground,
      body: communityAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: _cOrange)),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 48, color: _cTextDim),
              const SizedBox(height: 12),
              Text('Failed to load community', style: TextStyle(color: _cTextSecondary)),
            ],
          ),
        ),
        data: (community) {
          return NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              return [
                SliverAppBar(
                  expandedHeight: 200,
                  pinned: true,
                  backgroundColor: _cCard,
                  foregroundColor: _cTextPrimary,
                  flexibleSpace: FlexibleSpaceBar(
                    title: Text(
                      community.name,
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    background: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [_cOrange.withValues(alpha: 0.3), _cCard],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(height: 32),
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: _cElevated,
                                shape: BoxShape.circle,
                                image: community.avatarUrl != null
                                    ? DecorationImage(
                                        image: CachedNetworkImageProvider(community.avatarUrl!),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                              ),
                              child: community.avatarUrl == null
                                  ? Center(
                                      child: Text(
                                        community.name.substring(0, 1).toUpperCase(),
                                        style: TextStyle(
                                          color: _cOrange,
                                          fontSize: 28,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    )
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _TabBarDelegate(
                    TabBar(
                      controller: _tabController,
                      labelColor: _cOrange,
                      unselectedLabelColor: _cTextSecondary,
                      indicatorColor: _cOrange,
                      tabs: [
                        Tab(text: 'Posts'),
                        Tab(text: 'Events'),
                      ],
                    ),
                  ),
                ),
              ];
            },
            body: TabBarView(
              controller: _tabController,
              children: [
                _PostsTab(communityId: widget.communityId),
                _EventsTab(communityId: widget.communityId),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: communityAsync.when(
        loading: () => null,
        error: (_, __) => null,
        data: (community) => _buildBottomBar(community, actionState),
      ),
    );
  }

  Widget? _buildBottomBar(CommunityModel community, CommunityActionState actionState) {
    if (community.isJoined) {
      return Container(
        padding: const EdgeInsets.all(16),
        color: _cCard,
        child: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
            const SizedBox(width: 8),
            Text(
              'Joined as ${community.myRole ?? 'member'}',
              style: TextStyle(color: _cTextSecondary, fontSize: 14),
            ),
            const Spacer(),
            TextButton(
              onPressed: actionState.isLeaving
                  ? null
                  : () => _leaveCommunity(community.id),
              child: actionState.isLeaving
                  ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: KinrelColors.error))
                  : Text('Leave', style: TextStyle(color: KinrelColors.error)),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      color: _cCard,
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: actionState.isJoining ? null : () => _joinCommunity(community.id),
          style: ElevatedButton.styleFrom(
            backgroundColor: _cOrange,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: actionState.isJoining
              ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(
                  community.isPublic ? 'Join Community' : 'Request to Join',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
        ),
      ),
    );
  }

  Future<void> _joinCommunity(String communityId) async {
    final action = ref.read(communityActionProvider.notifier);
    final success = await action.joinCommunity(communityId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Joined successfully!' : 'Failed to join'),
          backgroundColor: success ? Colors.green : KinrelColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _leaveCommunity(String communityId) async {
    final action = ref.read(communityActionProvider.notifier);
    final success = await action.leaveCommunity(communityId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Left community' : 'Failed to leave'),
          backgroundColor: success ? Colors.green : KinrelColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  _TabBarDelegate(this.tabBar);
  final TabBar tabBar;

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(color: _cCard, child: tabBar);
  }

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) => tabBar != oldDelegate.tabBar;
}

// ── Posts Tab ────────────────────────────────────────────────────

class _PostsTab extends ConsumerWidget {
  const _PostsTab({required this.communityId});
  final String communityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postsAsync = ref.watch(communityPostsProvider(communityId));

    return postsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: _cOrange)),
      error: (e, _) => Center(
        child: Text('Failed to load posts', style: TextStyle(color: _cTextSecondary)),
      ),
      data: (posts) {
        if (posts.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.article_outlined, size: 48, color: _cTextDim),
                const SizedBox(height: 12),
                Text('No posts yet', style: TextStyle(color: _cTextSecondary)),
                const SizedBox(height: 8),
                Text('Be the first to start a discussion!', style: TextStyle(color: _cTextDim, fontSize: 13)),
              ],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(KinrelSpacing.base),
          itemCount: posts.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final post = posts[index];
            return _PostCard(post: post);
          },
        );
      },
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({required this.post});
  final CommunityPostModel post;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (post.title != null) ...[
            Text(
              post.title!,
              style: TextStyle(
                color: _cTextPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            post.body,
            style: TextStyle(color: _cTextSecondary, fontSize: 14, height: 1.5),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _cOrange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  post.type.toUpperCase(),
                  style: TextStyle(color: _cOrange, fontSize: 10, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              if (post.isPinned)
                Icon(Icons.push_pin_rounded, size: 14, color: _cOrange),
              const Spacer(),
              if (post.createdAt != null)
                Text(
                  _timeAgo(post.createdAt!),
                  style: TextStyle(color: _cTextDim, fontSize: 12),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }
}

// ── Events Tab ───────────────────────────────────────────────────

class _EventsTab extends ConsumerWidget {
  const _EventsTab({required this.communityId});
  final String communityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(
      communityEventsProvider(CommunityEventsParams(communityId: communityId)),
    );

    return eventsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: _cOrange)),
      error: (e, _) => Center(
        child: Text('Failed to load events', style: TextStyle(color: _cTextSecondary)),
      ),
      data: (events) {
        if (events.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.event_outlined, size: 48, color: _cTextDim),
                const SizedBox(height: 12),
                Text('No events yet', style: TextStyle(color: _cTextSecondary)),
              ],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(KinrelSpacing.base),
          itemCount: events.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final event = events[index];
            return _EventCard(
              event: event,
              communityId: communityId,
            );
          },
        );
      },
    );
  }
}

class _EventCard extends ConsumerWidget {
  const _EventCard({required this.event, required this.communityId});
  final CommunityEventModel event;
  final String communityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            event.title,
            style: TextStyle(
              color: _cTextPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (event.description != null && event.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              event.description!,
              style: TextStyle(color: _cTextSecondary, fontSize: 14),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              if (event.eventDate != null) ...[
                Icon(Icons.calendar_today_rounded, size: 14, color: _cOrange),
                const SizedBox(width: 4),
                Text(
                  _formatDate(event.eventDate!),
                  style: TextStyle(color: _cTextSecondary, fontSize: 13),
                ),
              ],
              if (event.location != null) ...[
                const SizedBox(width: 12),
                Icon(Icons.location_on_rounded, size: 14, color: _cOrange),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    event.location!,
                    style: TextStyle(color: _cTextSecondary, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          // RSVP buttons
          _buildRsvpRow(ref),
        ],
      ),
    );
  }

  Widget _buildRsvpRow(WidgetRef ref) {
    final rsvpOptions = [
      ('attending', 'Going', Icons.check_circle_rounded, Colors.green),
      ('maybe', 'Maybe', Icons.help_outline_rounded, Colors.orange),
      ('declined', 'Can\'t', Icons.cancel_rounded, Colors.red),
    ];

    return Row(
      children: rsvpOptions.map((option) {
        final (status, label, icon, color) = option;
        final isSelected = event.myRsvp == status;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              onTap: () async {
                await ref.read(communityActionProvider.notifier).rsvpEvent(
                  communityId,
                  event.id,
                  status: status,
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? color.withValues(alpha: 0.2) : _cElevated,
                  borderRadius: BorderRadius.circular(10),
                  border: isSelected
                      ? Border.all(color: color, width: 1.5)
                      : Border.all(color: Colors.white10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 14, color: isSelected ? color : _cTextDim),
                    const SizedBox(width: 4),
                    Text(
                      label,
                      style: TextStyle(
                        color: isSelected ? color : _cTextDim,
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  String _formatDate(DateTime date) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

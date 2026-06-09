import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/brand_colors.dart';
import '../../data/providers/follow_provider.dart';
import '../widgets/follow_button.dart';

class FollowersScreen extends ConsumerStatefulWidget {
  const FollowersScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  ConsumerState<FollowersScreen> createState() => _FollowersScreenState();
}

class _FollowersScreenState extends ConsumerState<FollowersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab,
    );
    Future.microtask(() {
      if (mounted) {
        ref.read(followProvider.notifier).loadFollowers();
        ref.read(followProvider.notifier).loadFollowing();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final followState = ref.watch(followProvider);

    return Scaffold(
      backgroundColor: KinrelColors.darkBackground,
      appBar: AppBar(
        backgroundColor: KinrelColors.darkBackground,
        title: Text('Follow', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600)),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Followers'),
            Tab(text: 'Following'),
          ],
          labelColor: KinrelColors.orange,
          unselectedLabelColor: KinrelColors.textSilver,
          indicatorColor: KinrelColors.orange,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildUserList(followState.followers, 'No followers yet', 'When people follow you, they appear here'),
          _buildUserList(followState.following, 'Not following anyone', 'When you follow people, they appear here'),
        ],
      ),
    );
  }

  Widget _buildUserList(List follows, String emptyTitle, String emptySubtitle) {
    if (follows.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 48, color: KinrelColors.textDim),
            SizedBox(height: 12),
            Text(emptyTitle, style: TextStyle(color: KinrelColors.textSilver, fontSize: 16)),
            SizedBox(height: 4),
            Text(emptySubtitle, style: TextStyle(color: KinrelColors.textDim, fontSize: 13)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: KinrelColors.orange,
      onRefresh: () async {
        if (_tabController.index == 0) {
          await ref.read(followProvider.notifier).loadFollowers();
        } else {
          await ref.read(followProvider.notifier).loadFollowing();
        }
      },
      child: ListView.builder(
        padding: EdgeInsets.all(16),
        itemCount: follows.length,
        itemBuilder: (context, index) {
          final follow = follows[index];
          // For followers: the follower is the other user; for following: the following is
          final otherUserId = _tabController.index == 0
              ? follow.followerId
              : follow.followingId;
          return Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: KinrelColors.elevation2,
                  child: Icon(Icons.person, color: KinrelColors.textSilver),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'User',
                    style: TextStyle(color: KinrelColors.textWhite, fontFamily: 'DM Sans'),
                  ),
                ),
                FollowButton(userId: otherUserId),
              ],
            ),
          );
        },
      ),
    );
  }
}

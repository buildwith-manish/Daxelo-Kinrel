// lib/presentation/screens/follow/followers_screen.dart
//
// DAXELO KINREL — Followers / Following Screen
//
// TabBar: Followers ({count}) | Following ({count})
//   • Search bar
//   • Each row: SparqRingAvatar + name + FollowButton
//   • Pull to refresh, pagination

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../data/repositories/follow_repository.dart';
import '../../providers/follow_provider.dart';
import '../../widgets/sparq_ring_avatar.dart';
import '../../widgets/follow_button.dart';

class FollowersScreen extends ConsumerStatefulWidget {
  const FollowersScreen({
    super.key,
    this.initialTab = 0,
    this.userId,
  });

  final int initialTab;
  final String? userId;

  @override
  ConsumerState<FollowersScreen> createState() => _FollowersScreenState();
}

class _FollowersScreenState extends ConsumerState<FollowersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab,
    );
    // Load data
    Future.microtask(() {
      ref.read(followProvider.notifier).loadFollowers();
      ref.read(followProvider.notifier).loadFollowing();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<UserModel> _filterList(List<UserModel> list) {
    if (_searchQuery.isEmpty) return list;
    final q = _searchQuery.toLowerCase();
    return list.where((u) {
      final name = (u.name ?? '').toLowerCase();
      final username = (u.username ?? '').toLowerCase();
      return name.contains(q) || username.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final followState = ref.watch(followProvider);

    return Scaffold(
      backgroundColor: KinrelColors.darkBackground,
      appBar: AppBar(
        backgroundColor: KinrelColors.darkBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: KinrelColors.textWhite),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Connections',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textWhite,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: KinrelColors.orange,
          indicatorWeight: 3,
          labelColor: KinrelColors.orange,
          unselectedLabelColor: KinrelColors.textDim,
          labelStyle: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          tabs: [
            Tab(text: 'Followers (${followState.followers.length})'),
            Tab(text: 'Following (${followState.following.length})'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 15,
                color: KinrelColors.textWhite,
              ),
              decoration: InputDecoration(
                hintText: 'Search...',
                hintStyle: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 15,
                  color: KinrelColors.textDim,
                ),
                prefixIcon: Icon(Icons.search, color: KinrelColors.textDim, size: 20),
                filled: true,
                fillColor: KinrelColors.darkElevated,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(KinrelRadius.xl),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildUserList(
                  _filterList(followState.followers),
                  followState.isLoading,
                ),
                _buildUserList(
                  _filterList(followState.following),
                  followState.isLoading,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserList(List<UserModel> users, bool isLoading) {
    if (isLoading && users.isEmpty) {
      return Center(
        child: CircularProgressIndicator(color: KinrelColors.orange),
      );
    }

    if (users.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 48, color: KinrelColors.textDim),
            const SizedBox(height: 12),
            Text(
              _searchQuery.isNotEmpty ? 'No results found' : 'No connections yet',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _searchQuery.isNotEmpty
                  ? 'Try a different search term'
                  : 'Follow people to see them here',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                color: KinrelColors.textDim,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: KinrelColors.orange,
      backgroundColor: KinrelColors.darkCard,
      onRefresh: () async {
        await Future.wait([
          ref.read(followProvider.notifier).loadFollowers(),
          ref.read(followProvider.notifier).loadFollowing(),
        ]);
      },
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: users.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          thickness: 0.5,
          color: KinrelColors.border,
          indent: 72,
        ),
        itemBuilder: (context, index) {
          final user = users[index];
          return ListTile(
            leading: SparqRingAvatar(
              userId: user.id,
              imageUrl: user.avatarUrl,
              initials: user.initials,
              size: 48,
            ),
            title: Text(
              user.displayName,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: KinrelColors.textWhite,
              ),
            ),
            subtitle: user.username != null
                ? Text(
                    '@${user.username}',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      color: KinrelColors.textDim,
                    ),
                  )
                : null,
            trailing: FollowButton(
              userId: user.id,
              username: user.username,
              compact: true,
            ),
          );
        },
      ),
    );
  }
}

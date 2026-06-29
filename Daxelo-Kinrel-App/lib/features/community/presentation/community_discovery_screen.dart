// lib/features/community/presentation/community_discovery_screen.dart
//
// DAXELO KINREL — Community Discovery Screen
//
// Browse and search communities by type (gotra, village, surname, custom).
// Join public communities, request to join private ones.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../providers/community_provider.dart';
import '../services/community_service.dart';
import 'community_detail_screen.dart';

const _cOrange = KinrelColors.orange;
const _cCard = KinrelColors.darkCard;
const _cElevated = KinrelColors.darkElevated;
const _cTextPrimary = KinrelColors.textWhite;
const _cTextSecondary = KinrelColors.textSilver;
const _cTextDim = KinrelColors.textDim;

class CommunityDiscoveryScreen extends ConsumerStatefulWidget {
  const CommunityDiscoveryScreen({super.key});

  @override
  ConsumerState<CommunityDiscoveryScreen> createState() => _CommunityDiscoveryScreenState();
}

class _CommunityDiscoveryScreenState extends ConsumerState<CommunityDiscoveryScreen> {
  String _selectedType = 'all';
  String _searchQuery = '';
  final _searchController = TextEditingController();

  static const _typeFilters = [
    ('all', 'All'),
    ('gotra', 'Gotra'),
    ('village', 'Village'),
    ('surname', 'Surname'),
    ('custom', 'Custom'),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchParams = CommunitySearchParams(
      type: _selectedType == 'all' ? null : _selectedType,
      search: _searchQuery.isEmpty ? null : _searchQuery,
    );
    final communitiesAsync = ref.watch(communitySearchProvider(searchParams));

    return Scaffold(
      backgroundColor: KinrelColors.darkBackground,
      appBar: AppBar(
        title: Text(
          'Communities',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: _cCard,
        foregroundColor: _cTextPrimary,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(KinrelSpacing.base),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: _cTextPrimary, fontSize: 16),
              decoration: InputDecoration(
                hintText: 'Search communities...',
                hintStyle: TextStyle(color: _cTextDim),
                prefixIcon: Icon(Icons.search_rounded, color: _cTextSecondary),
                filled: true,
                fillColor: _cElevated,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),

          // Type filter chips
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
              itemCount: _typeFilters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final (type, label) = _typeFilters[index];
                final isSelected = _selectedType == type;
                return GestureDetector(
                  onTap: () => setState(() => _selectedType = type),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? _cOrange.withValues(alpha: 0.2) : _cElevated,
                      borderRadius: BorderRadius.circular(20),
                      border: isSelected
                          ? Border.all(color: _cOrange, width: 1.5)
                          : Border.all(color: Colors.white10),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 14,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: isSelected ? _cOrange : _cTextSecondary,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 12),

          // Community list
          Expanded(
            child: communitiesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator(color: _cOrange)),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline_rounded, size: 48, color: _cTextDim),
                    const SizedBox(height: 12),
                    Text('Failed to load communities', style: TextStyle(color: _cTextSecondary)),
                    const SizedBox(height: 8),
                    Text('$e', style: TextStyle(color: _cTextDim, fontSize: 12), textAlign: TextAlign.center),
                  ],
                ),
              ),
              data: (communities) {
                if (communities.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.groups_rounded, size: 48, color: _cTextDim),
                        const SizedBox(height: 12),
                        Text('No communities found', style: TextStyle(color: _cTextSecondary)),
                      ],
                    ),
                  );
                }
                return RefreshIndicator(
                  color: _cOrange,
                  backgroundColor: _cCard,
                  onRefresh: () async {
                    ref.invalidate(communitySearchProvider(searchParams));
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
                    itemCount: communities.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final community = communities[index];
                      return _CommunityCard(
                        community: community,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => CommunityDetailScreen(communityId: community.id),
                            ),
                          );
                        },
                        onJoin: () => _joinCommunity(community.id),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _joinCommunity(String communityId) async {
    final action = ref.read(communityActionProvider.notifier);
    final success = await action.joinCommunity(communityId);
    if (mounted && !success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to join community'),
          backgroundColor: KinrelColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

class _CommunityCard extends StatelessWidget {
  const _CommunityCard({
    required this.community,
    required this.onTap,
    required this.onJoin,
  });

  final CommunityModel community;
  final VoidCallback onTap;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _cCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _cElevated,
                shape: BoxShape.circle,
                image: community.avatarUrl != null
                    ? DecorationImage(image: CachedNetworkImageProvider(community.avatarUrl!), fit: BoxFit.cover)
                    : null,
              ),
              child: community.avatarUrl == null
                  ? Center(
                      child: Text(
                        community.name.substring(0, 1).toUpperCase(),
                        style: TextStyle(
                          color: _cOrange,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 14),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    community.name,
                    style: TextStyle(
                      color: _cTextPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _cOrange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          community.type.toUpperCase(),
                          style: TextStyle(color: _cOrange, fontSize: 10, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.people_outline_rounded, size: 14, color: _cTextDim),
                      const SizedBox(width: 4),
                      Text(
                        '${community.memberCount}',
                        style: TextStyle(color: _cTextDim, fontSize: 12),
                      ),
                      if (!community.isPublic) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.lock_outline_rounded, size: 14, color: _cTextDim),
                      ],
                    ],
                  ),
                  if (community.description != null && community.description!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      community.description!,
                      style: TextStyle(color: _cTextSecondary, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            // Join button
            if (!community.isJoined)
              GestureDetector(
                onTap: onJoin,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: _cOrange,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    community.isPublic ? 'Join' : 'Request',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  community.myRole?.toUpperCase() ?? 'JOINED',
                  style: TextStyle(
                    color: _cTextSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// lib/presentation/screens/follow/follow_requests_screen.dart
//
// DAXELO KINREL — Follow Requests Screen
//
// Each row: Avatar + Name + Accept (orange) + Reject (grey)
// Empty state: "No pending requests"

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../providers/follow_provider.dart';

class FollowRequestsScreen extends ConsumerStatefulWidget {
  const FollowRequestsScreen({super.key});

  @override
  ConsumerState<FollowRequestsScreen> createState() =>
      _FollowRequestsScreenState();
}

class _FollowRequestsScreenState extends ConsumerState<FollowRequestsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(followProvider.notifier).loadRequests();
    });
  }

  @override
  Widget build(BuildContext context) {
    final followState = ref.watch(followProvider);
    final requests = followState.requests;

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
          'Follow Requests',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textWhite,
          ),
        ),
      ),
      body: _buildBody(requests),
    );
  }

  Widget _buildBody(List<dynamic> requests) {
    if (requests.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_add_disabled_outlined,
              size: 48,
              color: KinrelColors.textDim,
            ),
            const SizedBox(height: 12),
            Text(
              'No pending requests',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'When someone requests to follow you,\nit will appear here',
              textAlign: TextAlign.center,
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

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: requests.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        thickness: 0.5,
        color: KinrelColors.border,
        indent: 72,
      ),
      itemBuilder: (context, index) {
        final request = requests[index];
        final user = request.follower;
        final name = user?.name ?? user?.username ?? 'User';
        final username = user?.username;
        final avatarUrl = user?.avatarUrl;
        final initials = name.trim().split(' ').length >= 2
            ? '${name.trim().split(' ')[0][0]}${name.trim().split(' ')[1][0]}'
                .toUpperCase()
            : name.isNotEmpty
                ? name[0].toUpperCase()
                : '?';

        return ListTile(
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: KinrelColors.orange.withValues(alpha: 0.1),
              image: avatarUrl != null
                  ? DecorationImage(
                      image: NetworkImage(avatarUrl),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: avatarUrl != null
                ? null
                : Center(
                    child: Text(
                      initials,
                      style: TextStyle(
                        fontFamily: 'Outfit',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: KinrelColors.orange,
                      ),
                    ),
                  ),
          ),
          title: Text(
            name,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: KinrelColors.textWhite,
            ),
          ),
          subtitle: username != null
              ? Text(
                  '@$username',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    color: KinrelColors.textDim,
                  ),
                )
              : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Accept button (orange)
              ElevatedButton(
                onPressed: () => ref
                    .read(followProvider.notifier)
                    .acceptRequest(request.followerId),
                style: ElevatedButton.styleFrom(
                  backgroundColor: KinrelColors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'Accept',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Reject button (grey)
              OutlinedButton(
                onPressed: () => ref
                    .read(followProvider.notifier)
                    .rejectRequest(request.followerId),
                style: OutlinedButton.styleFrom(
                  foregroundColor: KinrelColors.textSilver,
                  side: BorderSide(
                    color: KinrelColors.textDim.withValues(alpha: 0.5),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  'Reject',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

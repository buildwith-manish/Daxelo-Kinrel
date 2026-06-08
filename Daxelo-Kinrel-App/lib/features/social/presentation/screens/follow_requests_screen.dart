import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/brand_colors.dart';
import '../../data/providers/follow_provider.dart';

class FollowRequestsScreen extends ConsumerStatefulWidget {
  const FollowRequestsScreen({super.key});

  @override
  ConsumerState<FollowRequestsScreen> createState() => _FollowRequestsScreenState();
}

class _FollowRequestsScreenState extends ConsumerState<FollowRequestsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(followProvider.notifier).loadPendingRequests();
    });
  }

  @override
  Widget build(BuildContext context) {
    final followState = ref.watch(followProvider);

    return Scaffold(
      backgroundColor: KinrelColors.darkBackground,
      appBar: AppBar(
        backgroundColor: KinrelColors.darkBackground,
        title: Text('Follow Requests', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600)),
      ),
      body: followState.pendingRequests.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.person_add_disabled, size: 48, color: KinrelColors.textDim),
                  SizedBox(height: 12),
                  Text('No pending requests', style: TextStyle(color: KinrelColors.textSilver, fontSize: 16)),
                  SizedBox(height: 4),
                  Text('Follow requests will appear here', style: TextStyle(color: KinrelColors.textDim, fontSize: 13)),
                ],
              ),
            )
          : ListView.separated(
              padding: EdgeInsets.all(16),
              itemCount: followState.pendingRequests.length,
              separatorBuilder: (_, __) => Divider(color: KinrelColors.elevation1),
              itemBuilder: (context, index) {
                final request = followState.pendingRequests[index];
                return Dismissible(
                  key: Key(request.id),
                  background: Container(
                    color: KinrelColors.success,
                    alignment: Alignment.centerLeft,
                    padding: EdgeInsets.only(left: 16),
                    child: Icon(Icons.check, color: Colors.white),
                  ),
                  secondaryBackground: Container(
                    color: KinrelColors.error,
                    alignment: Alignment.centerRight,
                    padding: EdgeInsets.only(right: 16),
                    child: Icon(Icons.close, color: Colors.white),
                  ),
                  confirmDismiss: (direction) async {
                    if (direction == DismissDirection.startToEnd) {
                      await ref.read(followProvider.notifier)
                          .acceptRequest(request.id, request.followerId);
                    } else {
                      await ref.read(followProvider.notifier)
                          .rejectRequest(request.id, request.followerId);
                    }
                    return true;
                  },
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: KinrelColors.elevation2,
                      child: Icon(Icons.person, color: KinrelColors.textSilver),
                    ),
                    title: Text(
                      'User ${request.followerId.substring(0, 6)}...',
                      style: TextStyle(color: KinrelColors.textWhite, fontFamily: 'DM Sans'),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.check_circle, color: KinrelColors.success),
                          onPressed: () => ref.read(followProvider.notifier)
                              .acceptRequest(request.id, request.followerId),
                        ),
                        IconButton(
                          icon: Icon(Icons.cancel, color: KinrelColors.error),
                          onPressed: () => ref.read(followProvider.notifier)
                              .rejectRequest(request.id, request.followerId),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

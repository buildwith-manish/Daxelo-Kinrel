// lib/presentation/widgets/follow_button.dart
//
// DAXELO KINREL — Follow Button
//
// A ConsumerWidget that displays the follow/unfollow status:
//   'self'      → SizedBox.shrink()
//   'none'      → ElevatedButton, orange fill (KinrelColors.orange), "Follow"
//   'pending'   → OutlinedButton, grey border, "Requested" + long-press → cancel sheet
//   'following' → OutlinedButton, grey border, "Following" + long-press → unfollow sheet
//   loading     → ElevatedButton with CircularProgressIndicator (orange)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/brand_colors.dart';
import '../../core/constants/brand_typography.dart';
import '../../data/repositories/follow_repository.dart';
import '../providers/follow_provider.dart';

class FollowButton extends ConsumerStatefulWidget {
  const FollowButton({
    super.key,
    required this.userId,
    this.username,
    this.isSelf = false,
    this.compact = false,
  });

  final String userId;
  final String? username;
  final bool isSelf;
  final bool compact;

  @override
  ConsumerState<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends ConsumerState<FollowButton> {
  bool _isLoading = false;

  String get _status {
    if (widget.isSelf) return 'self';
    return ref.watch(followProvider).statusCache[widget.userId] ?? 'none';
  }

  Future<void> _onTap() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    final status = _status;
    if (status == 'none') {
      await ref.read(followProvider.notifier).followUser(widget.userId);
    } else if (status == 'pending' || status == 'following') {
      // Show bottom sheet for cancel/unfollow
      _showActionSheet(status);
    }

    if (mounted) setState(() => _isLoading = false);
  }

  void _showActionSheet(String status) {
    final isPending = status == 'pending';
    final username = widget.username ?? 'this user';

    showModalBottomSheet(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: KinrelColors.textDim.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                isPending
                    ? 'Cancel follow request?'
                    : 'Unfollow @$username?',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                isPending
                    ? 'Your request to follow $username will be cancelled.'
                    : 'You will no longer see $username\'s posts in your feed.',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  color: KinrelColors.textSilver,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              // Destructive action
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    setState(() => _isLoading = true);
                    await ref
                        .read(followProvider.notifier)
                        .unfollowUser(widget.userId);
                    if (mounted) setState(() => _isLoading = false);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: KinrelColors.error,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    isPending ? 'Cancel Request' : 'Unfollow',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Cancel
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: KinrelColors.textSilver,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;

    // Self → hide
    if (status == 'self') return const SizedBox.shrink();

    final isCompact = widget.compact;
    final horizontalPadding = isCompact ? 12.0 : 20.0;
    final verticalPadding = isCompact ? 6.0 : 8.0;
    final fontSize = isCompact ? 12.0 : 13.0;

    // Loading state
    if (_isLoading) {
      return ElevatedButton(
        onPressed: null,
        style: ElevatedButton.styleFrom(
          backgroundColor: KinrelColors.orange,
          disabledBackgroundColor: KinrelColors.orange.withValues(alpha: 0.6),
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 0,
        ),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
      );
    }

    // Follow (none) → orange filled
    if (status == 'none') {
      return ElevatedButton(
        onPressed: _onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: KinrelColors.orange,
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 0,
        ),
        child: Text(
          'Follow',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    // Pending → outlined, grey border
    if (status == 'pending') {
      return OutlinedButton(
        onPressed: _onTap,
        onLongPress: _onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: KinrelColors.textSilver,
          side: BorderSide(color: KinrelColors.textDim.withValues(alpha: 0.5)),
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: Text(
          'Requested',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: fontSize,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    // Following → outlined, grey border
    return OutlinedButton(
      onPressed: _onTap,
      onLongPress: _onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: KinrelColors.textSilver,
        side: BorderSide(color: KinrelColors.textDim.withValues(alpha: 0.5)),
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: verticalPadding,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Text(
        'Following',
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

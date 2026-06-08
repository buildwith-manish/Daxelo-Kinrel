import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/constants/brand_colors.dart';
import '../../data/providers/follow_provider.dart';

/// FollowButton — shows different states based on follow status.
///
/// States:
/// - 'none' → Filled orange "Follow" button
/// - 'pending' → Outlined "Requested" button (long-press to cancel)
/// - 'following' → Outlined "Following" button (long-press to unfollow)
/// - 'self' → Renders nothing
class FollowButton extends ConsumerStatefulWidget {
  const FollowButton({
    super.key,
    required this.userId,
    this.onStatusChanged,
  });

  final String userId;
  final VoidCallback? onStatusChanged;

  @override
  ConsumerState<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends ConsumerState<FollowButton> {
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    // Load follow status on init
    Future.microtask(() {
      if (mounted) {
        ref.read(followProvider.notifier).loadFollowStatus(widget.userId);
      }
    });
  }

  String get _status => ref.watch(followStatusProvider(widget.userId));

  Future<void> _handleFollow() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    await ref.read(followProvider.notifier).followUser(widget.userId);
    setState(() => _isProcessing = false);
    widget.onStatusChanged?.call();
  }

  Future<void> _handleUnfollow() async {
    if (_isProcessing) return;
    // Show confirmation dialog
    final confirmed = await _showConfirmDialog(
      title: 'Unfollow',
      message: 'Are you sure you want to unfollow this user?',
    );
    if (confirmed != true) return;
    setState(() => _isProcessing = true);
    await ref.read(followProvider.notifier).unfollowUser(widget.userId);
    setState(() => _isProcessing = false);
    widget.onStatusChanged?.call();
  }

  Future<void> _handleCancelRequest() async {
    if (_isProcessing) return;
    final confirmed = await _showConfirmDialog(
      title: 'Cancel Request',
      message: 'Are you sure you want to cancel this follow request?',
    );
    if (confirmed != true) return;
    setState(() => _isProcessing = true);
    await ref.read(followProvider.notifier).unfollowUser(widget.userId);
    setState(() => _isProcessing = false);
    widget.onStatusChanged?.call();
  }

  Future<bool?> _showConfirmDialog({required String title, required String message}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KinrelColors.elevation2,
        title: Text(title, style: TextStyle(color: KinrelColors.textWhite)),
        content: Text(message, style: TextStyle(color: KinrelColors.textSilver)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: KinrelColors.textSilver)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Confirm', style: TextStyle(color: KinrelColors.error)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;

    if (status == 'self') return const SizedBox.shrink();

    Widget button;

    switch (status) {
      case 'none':
        button = _buildFilledButton('Follow', _handleFollow);
        break;
      case 'pending':
        button = _buildOutlinedButton('Requested', _handleCancelRequest);
        break;
      case 'following':
        button = _buildOutlinedButton('Following', _handleUnfollow);
        break;
      default:
        button = _buildFilledButton('Follow', _handleFollow);
    }

    return button
        .animate(target: status == 'none' ? 0 : 1)
        .fadeIn(duration: 200.ms)
        .scale(begin: Offset(0.95, 0.95), end: Offset(1.0, 1.0), duration: 200.ms);
  }

  Widget _buildFilledButton(String label, VoidCallback onTap) {
    return SizedBox(
      height: 36,
      child: ElevatedButton(
        onPressed: _isProcessing ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: KinrelColors.orange,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 0,
        ),
        child: _isProcessing
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Outfit',
                ),
              ),
      ),
    );
  }

  Widget _buildOutlinedButton(String label, VoidCallback onLongPress) {
    return GestureDetector(
      onLongPress: _isProcessing ? null : onLongPress,
      child: SizedBox(
        height: 36,
        child: OutlinedButton(
          onPressed: () {}, // No-op on tap; long-press for action
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: KinrelColors.textSilver.withValues(alpha: 0.3)),
            foregroundColor: KinrelColors.textSilver,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          child: _isProcessing
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: KinrelColors.textSilver,
                  ),
                )
              : Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Outfit',
                  ),
                ),
        ),
      ),
    );
  }
}

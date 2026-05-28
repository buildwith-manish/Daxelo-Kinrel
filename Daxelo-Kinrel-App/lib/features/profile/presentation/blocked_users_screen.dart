// lib/features/profile/presentation/blocked_users_screen.dart
//
// DAXELO KINREL — Blocked Users Screen
//
// Shows all users the current user has blocked, with the
// ability to unblock them via a confirmation dialog.
// Loads blocked users from profileProvider.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/constants/brand_typography.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/utils/device_tier.dart';
import '../data/profile_provider.dart';

// ── Design Tokens ──────────────────────────────────────────────────
const Color _bg = Color(0xFF131416);
const Color _cardBg = Color(0xFF191B2C);
const Color _orange = Color(0xFFE8612A);
const Color _textPrimary = Color(0xFFF5F0EE);
const Color _textSecondary = Color(0xFFC9B4A8);
const Color _textDim = Color(0xFF8A7A72);
const Color _borderSubtle = Color(0x0FFFFFFF);

class BlockedUsersScreen extends ConsumerStatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  ConsumerState<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends ConsumerState<BlockedUsersScreen> {
  // Track which users are currently being unblocked
  final Set<String> _unblockingIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(profileProvider.notifier).loadBlockedUsers();
    });
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  void _showUnblockConfirmDialog(BlockedUserModel user) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: _borderSubtle),
        ),
        title: const Text(
          'Unblock User?',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
        content: Text(
          'Are you sure you want to unblock ${user.name}? They will be able to see your profile and send you invitations again.',
          style: const TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 14,
            color: _textSecondary,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: _textDim)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _unblockUser(user);
            },
            child: const Text(
              'Unblock',
              style: TextStyle(color: _orange, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _unblockUser(BlockedUserModel user) async {
    setState(() => _unblockingIds.add(user.id));

    final success = await ref
        .read(profileProvider.notifier)
        .unblockUser(user.id);

    if (!mounted) return;

    setState(() => _unblockingIds.remove(user.id));

    if (success) {
      context.showSnackBar('${user.name} has been unblocked');
    } else {
      context.showSnackBar('Failed to unblock user', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileState = ref.watch(profileProvider);
    final blockedUsers = profileState.blockedUsers;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _textPrimary),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Blocked Users',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
      ),
      body: profileState.isLoading
          ? _buildShimmerList()
          : blockedUsers.isEmpty
          ? _buildEmptyState()
          : _buildBlockedList(blockedUsers),
    );
  }

  // ── Blocked Users List ───────────────────────────────────────────

  Widget _buildBlockedList(List<BlockedUserModel> blockedUsers) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: blockedUsers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final user = blockedUsers[index];
        final isUnblocking = _unblockingIds.contains(user.id);
        return _BlockedUserCard(
          user: user,
          initials: _getInitials(user.name),
          isUnblocking: isUnblocking,
          onUnblock: () => _showUnblockConfirmDialog(user),
        );
      },
    );
  }

  // ── Empty State ──────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _orange.withValues(alpha: 0.12),
            ),
            child: const Icon(Icons.block, color: _orange, size: 36),
          ),
          const SizedBox(height: 16),
          const Text(
            "You haven't blocked anyone",
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Blocked users will appear here',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              color: _textDim,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ── Shimmer Loading ──────────────────────────────────────────────

  Widget _buildShimmerList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final _shimmerChild = Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _borderSubtle),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: _bg, shape: BoxShape.circle),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 120,
                      height: 14,
                      decoration: BoxDecoration(
                        color: _bg,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 80,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _bg,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

        if (!DeviceTierCache.instance.shouldShimmer) {
          return _shimmerChild;
        }

        return Shimmer.fromColors(
          baseColor: const Color(0xFF202338),
          highlightColor: const Color(0xFF13141E),
          period: const Duration(milliseconds: 1500),
          child: _shimmerChild,
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Blocked User Card
// ═══════════════════════════════════════════════════════════════════════

class _BlockedUserCard extends StatelessWidget {
  const _BlockedUserCard({
    required this.user,
    required this.initials,
    required this.isUnblocking,
    required this.onUnblock,
  });

  final BlockedUserModel user;
  final String initials;
  final bool isUnblocking;
  final VoidCallback onUnblock;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _borderSubtle),
      ),
      child: Row(
        children: [
          // Avatar initials circle
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _orange.withValues(alpha: 0.15),
              border: Border.all(
                color: _orange.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Center(
              child: Text(
                initials,
                style: const TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _orange,
                  height: 1,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Name + username
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
                  style: const TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (user.username != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '@${user.username}',
                    style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 12,
                      color: _textDim,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Unblock button
          isUnblocking
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(_orange),
                  ),
                )
              : Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onUnblock,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _orange.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _orange.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: const Text(
                        'Unblock',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _orange,
                        ),
                      ),
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

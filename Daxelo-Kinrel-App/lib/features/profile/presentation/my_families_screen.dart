// lib/features/profile/presentation/my_families_screen.dart
//
// DAXELO KINREL — My Families Screen
//
// Shows all families the current user belongs to, with role
// badges, member counts, and actions (Manage for admin,
// Leave for non-admin). Loads families from profileProvider.

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

class MyFamiliesScreen extends ConsumerStatefulWidget {
  const MyFamiliesScreen({super.key});

  @override
  ConsumerState<MyFamiliesScreen> createState() => _MyFamiliesScreenState();
}

class _MyFamiliesScreenState extends ConsumerState<MyFamiliesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(profileProvider.notifier).loadFamilies();
    });
  }

  Color _roleBadgeColor(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return _orange;
      case 'editor':
        return Colors.teal;
      case 'viewer':
        return Colors.grey;
      case 'member':
      default:
        return const Color(0xFF4A90D9);
    }
  }

  IconData _roleIcon(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return Icons.shield;
      case 'editor':
        return Icons.edit;
      case 'viewer':
        return Icons.visibility;
      case 'member':
      default:
        return Icons.person;
    }
  }

  String _roleLabel(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return 'Admin';
      case 'editor':
        return 'Editor';
      case 'viewer':
        return 'Viewer';
      case 'member':
      default:
        return 'Member';
    }
  }

  void _showLeaveConfirmDialog(FamilyTreeNode family) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: _borderSubtle),
        ),
        title: Text(
          'Leave "${family.name}"?',
          style: const TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
        content: Text(
          'You will no longer have access to this family tree. If you are the only admin, the family will need a new admin before you can leave.',
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
              _leaveFamily(family);
            },
            child: const Text(
              'Leave Family',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _leaveFamily(FamilyTreeNode family) async {
    // In a production app, this would call an API method like:
    // await ref.read(profileProvider.notifier).leaveFamily(family.id);
    // For now, refresh the families list after a brief delay
    if (!mounted) return;
    context.showSnackBar('Left "${family.name}"');

    // Refresh the list
    await ref.read(profileProvider.notifier).loadFamilies();
  }

  @override
  Widget build(BuildContext context) {
    final profileState = ref.watch(profileProvider);
    final families = profileState.families;

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
          'My Families',
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
          : families.isEmpty
          ? _buildEmptyState()
          : _buildFamilyList(families),
    );
  }

  // ── Family List ──────────────────────────────────────────────────

  Widget _buildFamilyList(List<FamilyTreeNode> families) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: families.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final family = families[index];
        final isAdmin = family.role.toLowerCase() == 'admin';
        return _FamilyCard(
          family: family,
          roleBadgeColor: _roleBadgeColor(family.role),
          roleIcon: _roleIcon(family.role),
          roleLabel: _roleLabel(family.role),
          isAdmin: isAdmin,
          onManage: () => context.push('/family/${family.id}'),
          onLeave: () => _showLeaveConfirmDialog(family),
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
            child: const Icon(
              Icons.family_restroom_outlined,
              color: _orange,
              size: 36,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            "You're not part of any families yet",
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
            'Create a new family or accept an invitation to get started',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              color: _textDim,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: 200,
            height: 44,
            child: ElevatedButton(
              onPressed: () => context.push('/families/create'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _orange,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Create a Family',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _textPrimary,
                ),
              ),
            ),
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
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final _shimmerChild = Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _borderSubtle),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 140,
                      height: 14,
                      decoration: BoxDecoration(
                        color: _bg,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 90,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _bg,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 60,
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
// Family Card
// ═══════════════════════════════════════════════════════════════════════

class _FamilyCard extends StatelessWidget {
  const _FamilyCard({
    required this.family,
    required this.roleBadgeColor,
    required this.roleIcon,
    required this.roleLabel,
    required this.isAdmin,
    required this.onManage,
    required this.onLeave,
  });

  final FamilyTreeNode family;
  final Color roleBadgeColor;
  final IconData roleIcon;
  final String roleLabel;
  final bool isAdmin;
  final VoidCallback onManage;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isAdmin ? _orange.withValues(alpha: 0.2) : _borderSubtle,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top Row: Family info ────────────────────────────────
          Row(
            children: [
              // Family avatar placeholder
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.family_restroom,
                  color: _orange,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),

              // Family name + username
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      family.name,
                      style: const TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    if (family.username != null)
                      Text(
                        '@${family.username}',
                        style: TextStyle(
                          fontFamily: KinrelTypography.monoFont,
                          fontSize: 12,
                          color: _textDim,
                        ),
                      ),
                  ],
                ),
              ),

              // Role badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: roleBadgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: roleBadgeColor.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(roleIcon, color: roleBadgeColor, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      roleLabel,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: roleBadgeColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ── Bottom Row: Member count + action buttons ───────────
          Row(
            children: [
              // Member count
              Icon(Icons.people_outline, color: _textDim, size: 16),
              const SizedBox(width: 6),
              Text(
                '${family.memberCount} ${family.memberCount == 1 ? 'member' : 'members'}',
                style: const TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  color: _textSecondary,
                ),
              ),

              const Spacer(),

              // Action button
              if (isAdmin)
                _ActionButton(
                  label: 'Manage',
                  color: _orange,
                  isFilled: true,
                  onTap: onManage,
                )
              else
                _ActionButton(
                  label: 'Leave',
                  color: Colors.redAccent,
                  isFilled: false,
                  onTap: onLeave,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Action Button (small inline button)
// ═══════════════════════════════════════════════════════════════════════

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.color,
    required this.isFilled,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool isFilled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isFilled ? color : color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isFilled
                  ? Colors.transparent
                  : color.withValues(alpha: 0.4),
              width: 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isFilled ? _textPrimary : color,
            ),
          ),
        ),
      ),
    );
  }
}

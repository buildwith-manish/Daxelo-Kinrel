// lib/features/family/presentation/family_management_screen.dart
//
// DAXELO KINREL — Family Management Screen
//
// A complete family management system accessible to Creator and Admins.
// Similar to WhatsApp group admin settings but tailored for families.
//
// Sections:
//   1. Permissions (invite, add members, edit info, graph, chat, stories, etc.)
//   2. Safety Controls (member removal, leave family, confirm deletes)
//   3. Join Approval System
//   4. Family Privacy
//   5. Member Management (promote/demote/remove/transfer ownership)
//   6. Family Activity Log
//
// Role badges: 👑 Creator, 🛡️ Admin, 👤 Member

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/services/supabase_service.dart';

class FamilyManagementScreen extends ConsumerStatefulWidget {
  const FamilyManagementScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<FamilyManagementScreen> createState() =>
      _FamilyManagementScreenState();
}

class _FamilyManagementScreenState
    extends ConsumerState<FamilyManagementScreen> {
  Map<String, dynamic>? _settings;
  bool _isLoading = true;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final client = ref.read(supabaseProvider);
    if (client == null) return;

    try {
      final response = await client.rpc(
        'fn_get_family_settings',
        params: {'p_family_id': widget.familyId},
      ).timeout(const Duration(seconds: 8));

      final result = response as Map<String, dynamic>?;
      if (result?['success'] == true) {
        setState(() {
          _settings = result!['settings'] as Map<String, dynamic>?;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('⚠️ Family settings load error: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateSetting(String settingName, String value) async {
    setState(() => _isUpdating = true);
    final client = ref.read(supabaseProvider);
    if (client == null) return;

    try {
      await client.rpc(
        'fn_update_family_setting',
        params: {
          'p_family_id': widget.familyId,
          'p_setting_name': settingName,
          'p_setting_value': value,
        },
      ).timeout(const Duration(seconds: 8));

      // Update local state
      setState(() {
        _settings?[settingName] = value;
        _isUpdating = false;
      });
    } catch (e) {
      setState(() => _isUpdating = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not update setting. Try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _updateBoolSetting(String settingName, bool value) async {
    await _updateSetting(settingName, value.toString());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KinrelColors.darkBackground,
      appBar: AppBar(
        backgroundColor: KinrelColors.darkBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: KinrelColors.textWhite),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Family Management',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textWhite,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: KinrelColors.orange))
          : _settings == null
              ? const Center(child: Text('Could not load settings'))
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Section: Permissions ──
          _buildSectionHeader('Permissions'),
          _buildPermissionTile(
            'Who can invite members',
            'whoCanInvite',
            icon: Icons.person_add_outlined,
          ),
          _buildPermissionTile(
            'Who can add family members to graph',
            'whoCanAddMembers',
            icon: Icons.family_restroom,
          ),
          _buildPermissionTile(
            'Who can edit family information',
            'whoCanEditInfo',
            icon: Icons.edit_outlined,
          ),
          _buildPermissionTile(
            'Who can modify the family graph',
            'whoCanEditGraph',
            icon: Icons.account_tree_outlined,
          ),
          _buildPermissionTile(
            'Who can send chat messages',
            'whoCanChat',
            icon: Icons.chat_bubble_outline,
          ),
          _buildPermissionTile(
            'Who can post stories',
            'whoCanPostStories',
            icon: Icons.auto_stories_outlined,
          ),
          _buildPermissionTile(
            'Who can create Truth Streak questions',
            'whoCanCreateTruthStreak',
            icon: Icons.local_fire_department_outlined,
          ),
          _buildPermissionTile(
            'Who can add calendar events',
            'whoCanAddEvents',
            icon: Icons.calendar_today_outlined,
          ),

          const SizedBox(height: 24),

          // ── Section: Safety Controls ──
          _buildSectionHeader('Safety Controls'),
          _buildSwitchTile(
            'Allow member removal',
            'allowMemberRemoval',
            icon: Icons.person_remove_outlined,
          ),
          _buildSwitchTile(
            'Allow members to leave family',
            'allowMembersToLeave',
            icon: Icons.logout,
          ),
          _buildSwitchTile(
            'Confirm before deleting relationships',
            'confirmBeforeDeleteRelationship',
            icon: Icons.warning_amber_outlined,
          ),

          const SizedBox(height: 24),

          // ── Section: Join Approval ──
          _buildSectionHeader('Join Approval System'),
          _buildSwitchTile(
            'Require approval before joining',
            'requireJoinApproval',
            icon: Icons.approval_outlined,
          ),

          const SizedBox(height: 24),

          // ── Section: Family Privacy ──
          _buildSectionHeader('Family Privacy'),
          _buildPrivacyTile(),

          const SizedBox(height: 24),

          // ── Section: Member Management ──
          _buildSectionHeader('Member Management'),
          _buildActionTile(
            icon: Icons.people_outline,
            title: 'Manage Members',
            subtitle: 'Promote, demote, remove, transfer ownership',
            onTap: () => context.push('/family/${widget.familyId}/members'),
          ),

          const SizedBox(height: 24),

          // ── Section: Activity Log ──
          _buildSectionHeader('Family Activity Log'),
          _buildActionTile(
            icon: Icons.history_outlined,
            title: 'View Activity Log',
            subtitle: 'See all family admin actions',
            onTap: () => _showActivityLog(),
          ),

          const SizedBox(height: 32),

          // ── Role badges info ──
          _buildSectionHeader('Role Badges'),
          _buildRoleBadge('👑', 'Creator', 'The family owner'),
          _buildRoleBadge('🛡️', 'Admin', 'Can manage family settings'),
          _buildRoleBadge('👤', 'Member', 'Standard family member'),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontFamily: KinrelTypography.displayFont,
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: KinrelColors.textWhite,
        ),
      ),
    );
  }

  Widget _buildPermissionTile(
    String title,
    String settingKey, {
    required IconData icon,
  }) {
    final currentValue = _settings?[settingKey] as String? ?? 'everyone';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: KinrelColors.border, width: 1),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        leading: Icon(icon, size: 20, color: KinrelColors.orange),
        title: Text(title,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: KinrelColors.textWhite)),
        subtitle: Text(_permissionLabel(currentValue),
            style: TextStyle(fontSize: 11, color: KinrelColors.textDim)),
        childrenPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        children: [
          _buildPermissionOption(title, settingKey, 'everyone', 'Everyone'),
          _buildPermissionOption(title, settingKey, 'admins', 'Admins only'),
          _buildPermissionOption(title, settingKey, 'creator', 'Creator only'),
        ],
      ),
    );
  }

  Widget _buildPermissionOption(
    String title, String settingKey, String value, String label) {
    final currentValue = _settings?[settingKey] as String? ?? 'everyone';
    return RadioListTile<String>(
      value: value,
      groupValue: currentValue,
      onChanged: _isUpdating ? null : (v) => _updateSetting(settingKey, v!),
      title: Text(label, style: TextStyle(fontSize: 13, color: KinrelColors.textSilver)),
      activeColor: KinrelColors.orange,
      dense: true,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildSwitchTile(
    String title,
    String settingKey, {
    required IconData icon,
  }) {
    final value = _settings?[settingKey] as bool? ?? true;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: KinrelColors.border, width: 1),
      ),
      child: SwitchListTile(
        secondary: Icon(icon, size: 20, color: KinrelColors.orange),
        title: Text(title,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: KinrelColors.textWhite)),
        value: value,
        onChanged: _isUpdating ? null : (v) => _updateBoolSetting(settingKey, v),
        activeColor: KinrelColors.orange,
      ),
    );
  }

  Widget _buildPrivacyTile() {
    final currentValue = _settings?['familyVisibility'] as String? ?? 'invite_only';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: KinrelColors.border, width: 1),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        leading: const Icon(Icons.lock_outline, size: 20, color: KinrelColors.orange),
        title: const Text('Family Visibility',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: KinrelColors.textWhite)),
        subtitle: Text(_visibilityLabel(currentValue),
            style: TextStyle(fontSize: 11, color: KinrelColors.textDim)),
        childrenPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        children: [
          _buildPermissionOption('', 'familyVisibility', 'private', 'Private (hidden)'),
          _buildPermissionOption('', 'familyVisibility', 'invite_only', 'Invite Only'),
          _buildPermissionOption('', 'familyVisibility', 'public', 'Public Discovery'),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: KinrelColors.border, width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(icon, size: 20, color: KinrelColors.orange),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: TextStyle(fontSize: 12, color: KinrelColors.textDim)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 20, color: KinrelColors.textDim),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleBadge(String emoji, String role, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Text(role,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
          const SizedBox(width: 8),
          Text('— $description',
              style: TextStyle(fontSize: 12, color: KinrelColors.textDim)),
        ],
      ),
    );
  }

  String _permissionLabel(String value) {
    switch (value) {
      case 'admins':
        return 'Admins only';
      case 'creator':
        return 'Creator only';
      default:
        return 'Everyone';
    }
  }

  String _visibilityLabel(String value) {
    switch (value) {
      case 'private':
        return 'Private (hidden)';
      case 'public':
        return 'Public Discovery';
      default:
        return 'Invite Only';
    }
  }

  Future<void> _showActivityLog() async {
    // TODO: Navigate to activity log screen
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Activity log coming soon'),
          backgroundColor: KinrelColors.darkCard,
        ),
      );
    }
  }
}

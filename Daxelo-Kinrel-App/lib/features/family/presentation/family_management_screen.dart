// lib/features/family/presentation/family_management_screen.dart
//
// DAXELO KINREL — Family Management Screen (Full Implementation)
//
// A complete family management system with REAL enforcement.
// Every permission setting controls actual app behavior.
// UI uses Kinrel's design language (KinrelColors, KinrelTypography)
// with custom role badges — no emojis.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/services/supabase_service.dart';

// ═══════════════════════════════════════════════════════════════════════
// Models
// ═══════════════════════════════════════════════════════════════════════

class FamilySettings {
  const FamilySettings({
    this.whoCanInvite = 'everyone',
    this.whoCanAddMembers = 'everyone',
    this.whoCanEditInfo = 'creator',
    this.whoCanEditGraph = 'everyone',
    this.whoCanChat = 'everyone',
    this.whoCanPostStories = 'everyone',
    this.whoCanCreateTruthStreak = 'everyone',
    this.whoCanAddEvents = 'everyone',
    this.allowMemberRemoval = true,
    this.allowMembersToLeave = true,
    this.confirmBeforeDeleteRelationship = true,
    this.requireJoinApproval = false,
    this.familyVisibility = 'invite_only',
  });

  factory FamilySettings.fromJson(Map<String, dynamic> json) {
    return FamilySettings(
      whoCanInvite: json['whoCanInvite'] ?? 'everyone',
      whoCanAddMembers: json['whoCanAddMembers'] ?? 'everyone',
      whoCanEditInfo: json['whoCanEditInfo'] ?? 'creator',
      whoCanEditGraph: json['whoCanEditGraph'] ?? 'everyone',
      whoCanChat: json['whoCanChat'] ?? 'everyone',
      whoCanPostStories: json['whoCanPostStories'] ?? 'everyone',
      whoCanCreateTruthStreak: json['whoCanCreateTruthStreak'] ?? 'everyone',
      whoCanAddEvents: json['whoCanAddEvents'] ?? 'everyone',
      allowMemberRemoval: json['allowMemberRemoval'] ?? true,
      allowMembersToLeave: json['allowMembersToLeave'] ?? true,
      confirmBeforeDeleteRelationship:
          json['confirmBeforeDeleteRelationship'] ?? true,
      requireJoinApproval: json['requireJoinApproval'] ?? false,
      familyVisibility: json['familyVisibility'] ?? 'invite_only',
    );
  }

  final String whoCanInvite;
  final String whoCanAddMembers;
  final String whoCanEditInfo;
  final String whoCanEditGraph;
  final String whoCanChat;
  final String whoCanPostStories;
  final String whoCanCreateTruthStreak;
  final String whoCanAddEvents;
  final bool allowMemberRemoval;
  final bool allowMembersToLeave;
  final bool confirmBeforeDeleteRelationship;
  final bool requireJoinApproval;
  final String familyVisibility;
}

class FamilyMemberWithRole {
  const FamilyMemberWithRole({
    required this.userId,
    required this.name,
    this.username,
    this.avatarUrl,
    this.role = 'member',
    this.isCreator = false,
    this.joinedAt,
  });

  factory FamilyMemberWithRole.fromJson(Map<String, dynamic> json) {
    return FamilyMemberWithRole(
      userId: json['user_id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown',
      username: json['username'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      role: json['role'] as String? ?? 'member',
      isCreator: json['is_creator'] as bool? ?? false,
      joinedAt: json['joined_at'] != null
          ? DateTime.tryParse(json['joined_at'].toString())
          : null,
    );
  }

  final String userId;
  final String name;
  final String? username;
  final String? avatarUrl;
  final String role;
  final bool isCreator;
  final DateTime? joinedAt;
}

class ActivityLogEntry {
  const ActivityLogEntry({
    required this.id,
    required this.actorName,
    required this.action,
    required this.description,
    required this.createdAt,
  });

  factory ActivityLogEntry.fromJson(Map<String, dynamic> json) {
    return ActivityLogEntry(
      id: json['id'] as String? ?? '',
      actorName: json['actor_name'] as String? ?? 'Unknown',
      action: json['action'] as String? ?? '',
      description: json['description'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  final String id;
  final String actorName;
  final String action;
  final String description;
  final DateTime createdAt;
}

// ═══════════════════════════════════════════════════════════════════════
// Screen
// ═══════════════════════════════════════════════════════════════════════

class FamilyManagementScreen extends ConsumerStatefulWidget {
  const FamilyManagementScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<FamilyManagementScreen> createState() =>
      _FamilyManagementScreenState();
}

class _FamilyManagementScreenState
    extends ConsumerState<FamilyManagementScreen> {
  FamilySettings? _settings;
  bool _isLoading = true;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final client = ref.read(supabaseProvider);
    if (client == null) {
      setState(() => _isLoading = false);
      return;
    }
    try {
      final response = await client.rpc(
        'fn_get_family_settings',
        params: {'p_family_id': widget.familyId},
      ).timeout(const Duration(seconds: 8));

      final result = response as Map<String, dynamic>?;
      if (result?['success'] == true) {
        setState(() {
          _settings = FamilySettings.fromJson(
            (result!['settings'] as Map<String, dynamic>?) ?? {},
          );
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateSetting(String settingName, String value) async {
    setState(() => _isUpdating = true);
    final client = ref.read(supabaseProvider);
    if (client == null) {
      setState(() => _isUpdating = false);
      return;
    }
    try {
      await client.rpc(
        'fn_update_family_setting',
        params: {
          'p_family_id': widget.familyId,
          'p_setting_name': settingName,
          'p_setting_value': value,
        },
      ).timeout(const Duration(seconds: 8));
      // Reload settings to reflect the change
      await _loadSettings();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not update setting. Try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
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
          ? const Center(
              child: CircularProgressIndicator(color: KinrelColors.orange))
          : _settings == null
              ? const Center(
                  child: Text('Could not load settings',
                      style: TextStyle(color: KinrelColors.textSilver)))
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Permissions ──
              _buildSection('Permissions'),
              _buildPermissionTile('Who can invite members', 'whoCanInvite',
                  Icons.person_add_outlined),
              _buildPermissionTile('Who can add members to graph',
                  'whoCanAddMembers', Icons.family_restroom),
              _buildPermissionTile('Who can edit family info', 'whoCanEditInfo',
                  Icons.edit_outlined),
              _buildPermissionTile('Who can modify the graph', 'whoCanEditGraph',
                  Icons.account_tree_outlined),
              _buildPermissionTile('Who can send chat messages', 'whoCanChat',
                  Icons.chat_bubble_outline),
              _buildPermissionTile('Who can post stories', 'whoCanPostStories',
                  Icons.auto_stories_outlined),
              _buildPermissionTile('Who can create Truth Streaks',
                  'whoCanCreateTruthStreak', Icons.local_fire_department_outlined),
              _buildPermissionTile('Who can add calendar events', 'whoCanAddEvents',
                  Icons.calendar_today_outlined),

              const SizedBox(height: 24),
              _buildSection('Safety Controls'),
              _buildSwitchTile('Allow member removal', 'allowMemberRemoval',
                  Icons.person_remove_outlined),
              _buildSwitchTile('Allow members to leave', 'allowMembersToLeave',
                  Icons.logout),
              _buildSwitchTile('Confirm before deleting relationships',
                  'confirmBeforeDeleteRelationship', Icons.warning_amber_outlined),

              const SizedBox(height: 24),
              _buildSection('Join Approval'),
              _buildSwitchTile('Require approval before joining',
                  'requireJoinApproval', Icons.approval_outlined),

              const SizedBox(height: 24),
              _buildSection('Family Privacy'),
              _buildPrivacyTile(),

              const SizedBox(height: 24),
              _buildSection('Member Management'),
              _buildActionTile(
                icon: Icons.people_outline,
                title: 'Manage Members',
                subtitle:
                    'Promote, demote, remove, transfer ownership',
                onTap: () => _showMemberManagement(),
              ),

              const SizedBox(height: 24),
              _buildSection('Activity Log'),
              _buildActionTile(
                icon: Icons.history_outlined,
                title: 'View Activity Log',
                subtitle: 'See all family admin actions',
                onTap: () => _showActivityLog(),
              ),

              const SizedBox(height: 24),
              _buildSection('Roles'),
              _buildRoleInfo('Creator',
                  'Full control over the family', KinrelColors.orange),
              _buildRoleInfo('Admin',
                  'Can manage settings and members', KinrelColors.amber),
              _buildRoleInfo('Member',
                  'Standard family member', KinrelColors.textSilver),

              const SizedBox(height: 40),
            ],
          ),
        ),
        if (_isUpdating)
          Container(
            color: Colors.black54,
            child: const Center(
              child: CircularProgressIndicator(color: KinrelColors.orange),
            ),
          ),
      ],
    );
  }

  // ── UI Builders ──

  Widget _buildSection(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(title,
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textWhite,
          )),
    );
  }

  Widget _buildPermissionTile(
      String title, String settingKey, IconData icon) {
    final currentValue = _getValue(settingKey);
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
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w500,
                color: KinrelColors.textWhite)),
        subtitle: Text(_permissionLabel(currentValue),
            style: TextStyle(fontSize: 11, color: KinrelColors.textDim)),
        childrenPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        children: [
          _buildRadioOption(settingKey, 'everyone', 'Everyone', currentValue),
          _buildRadioOption(settingKey, 'admins', 'Admins only', currentValue),
          _buildRadioOption(settingKey, 'creator', 'Creator only', currentValue),
        ],
      ),
    );
  }

  Widget _buildRadioOption(
      String key, String value, String label, String current) {
    return RadioListTile<String>(
      value: value,
      groupValue: current,
      onChanged: _isUpdating ? null : (v) => _updateSetting(key, v!),
      title: Text(label,
          style: TextStyle(fontSize: 13, color: KinrelColors.textSilver)),
      activeColor: KinrelColors.orange,
      dense: true,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildSwitchTile(
      String title, String key, IconData icon) {
    final value = _getBoolValue(key);
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
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w500,
                color: KinrelColors.textWhite)),
        value: value,
        onChanged: _isUpdating
            ? null
            : (v) => _updateSetting(key, v.toString()),
        activeColor: KinrelColors.orange,
      ),
    );
  }

  Widget _buildPrivacyTile() {
    final currentValue = _getValue('familyVisibility');
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
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w500,
                color: KinrelColors.textWhite)),
        subtitle: Text(_visibilityLabel(currentValue),
            style: TextStyle(fontSize: 11, color: KinrelColors.textDim)),
        childrenPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        children: [
          _buildRadioOption('familyVisibility', 'private',
              'Private (hidden)', currentValue),
          _buildRadioOption('familyVisibility', 'invite_only',
              'Invite Only', currentValue),
          _buildRadioOption('familyVisibility', 'public',
              'Public Discovery', currentValue),
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
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600,
                              color: KinrelColors.textWhite)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: TextStyle(
                              fontSize: 12, color: KinrelColors.textDim)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 20,
                    color: KinrelColors.textDim),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleInfo(String role, String description, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.15),
              border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
            ),
            child: Icon(
              role == 'Creator'
                  ? Icons.diamond_outlined
                  : role == 'Admin'
                      ? Icons.shield_outlined
                      : Icons.person_outline,
              size: 14,
              color: color,
            ),
          ),
          const SizedBox(width: 10),
          Text(role,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600,
                  color: KinrelColors.textWhite)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(description,
                style: TextStyle(
                    fontSize: 12, color: KinrelColors.textDim)),
          ),
        ],
      ),
    );
  }

  // ── Member Management Bottom Sheet ──

  Future<void> _showMemberManagement() async {
    final client = ref.read(supabaseProvider);
    if (client == null) return;

    try {
      final response = await client.rpc(
        'fn_get_family_members_with_roles',
        params: {'p_family_id': widget.familyId},
      ).timeout(const Duration(seconds: 8));

      final members = (response as List)
          .map((e) => FamilyMemberWithRole.fromJson(e as Map<String, dynamic>))
          .toList();

      if (!mounted) return;

      await showModalBottomSheet(
        context: context,
        backgroundColor: KinrelColors.darkBackground,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        isScrollControlled: true,
        builder: (ctx) => DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (ctx, scrollController) => Column(
            children: [
              // Handle bar
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 16),
                decoration: BoxDecoration(
                  color: KinrelColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text('Manage Members',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 18, fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                  )),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: members.length,
                  itemBuilder: (ctx, index) {
                    final m = members[index];
                    return _buildMemberTile(m);
                  },
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not load members.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildMemberTile(FamilyMemberWithRole m) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: KinrelColors.border, width: 1),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: KinrelColors.orange.withValues(alpha: 0.12),
            ),
            child: m.avatarUrl != null && m.avatarUrl!.isNotEmpty
                ? ClipOval(
                    child: Image.network(m.avatarUrl!, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _buildInitials(m.name)))
                : _buildInitials(m.name),
          ),
          const SizedBox(width: 12),
          // Name + role badge
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.name,
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600,
                        color: KinrelColors.textWhite)),
                const SizedBox(height: 4),
                _buildRoleBadge(m),
              ],
            ),
          ),
          // Actions
          if (!m.isCreator)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: KinrelColors.textDim, size: 20),
              color: KinrelColors.darkCard,
              onSelected: (action) => _handleMemberAction(m, action),
              itemBuilder: (ctx) => [
                if (m.role == 'member')
                  const PopupMenuItem(value: 'promote', child: Text('Promote to Admin')),
                if (m.role == 'admin')
                  const PopupMenuItem(value: 'demote', child: Text('Remove Admin')),
                const PopupMenuItem(value: 'remove', child: Text('Remove Member')),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildRoleBadge(FamilyMemberWithRole m) {
    final isCreator = m.isCreator;
    final isAdmin = m.role == 'admin' || m.role == 'owner';
    final color = isCreator ? KinrelColors.orange : isAdmin ? KinrelColors.amber : KinrelColors.textDim;
    final icon = isCreator ? Icons.diamond : isAdmin ? Icons.shield : Icons.person;
    final label = isCreator ? 'Creator' : isAdmin ? 'Admin' : 'Member';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }

  Widget _buildInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    final initials = parts.isEmpty || parts.first.isEmpty
        ? '?'
        : parts.length == 1
            ? parts.first[0].toUpperCase()
            : (parts.first[0] + parts[1][0]).toUpperCase();
    return Center(
      child: Text(initials,
          style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w700,
              color: KinrelColors.orange)),
    );
  }

  Future<void> _handleMemberAction(FamilyMemberWithRole m, String action) async {
    final client = ref.read(supabaseProvider);
    if (client == null) return;

    String rpcName;
    switch (action) {
      case 'promote':
        rpcName = 'fn_promote_member';
        break;
      case 'demote':
        rpcName = 'fn_demote_member';
        break;
      case 'remove':
        rpcName = 'fn_remove_member';
        break;
      default:
        return;
    }

    // Confirm for destructive actions
    if (action == 'remove') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: KinrelColors.darkCard,
          title: Text('Remove Member',
              style: TextStyle(color: KinrelColors.textWhite)),
          content: Text('Are you sure you want to remove ${m.name} from the family?',
              style: TextStyle(color: KinrelColors.textSilver)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true),
                child: Text('Remove', style: TextStyle(color: Colors.red))),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    try {
      final response = await client.rpc(rpcName, params: {
        'p_family_id': widget.familyId,
        'p_member_user_id': m.userId,
      }).timeout(const Duration(seconds: 8));

      final result = response as Map<String, dynamic>?;
      final success = result?['success'] as bool? ?? false;
      final message = result?['message'] as String? ?? 'Action completed';

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: success ? KinrelColors.orange : Colors.red,
          ),
        );
        if (success) _showMemberManagement(); // Refresh
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Action failed. Try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ── Activity Log Bottom Sheet ──

  Future<void> _showActivityLog() async {
    final client = ref.read(supabaseProvider);
    if (client == null) return;

    try {
      final response = await client.rpc(
        'fn_get_family_activity_log',
        params: {
          'p_family_id': widget.familyId,
          'p_limit': 50,
          'p_offset': 0,
        },
      ).timeout(const Duration(seconds: 8));

      final entries = (response as List)
          .map((e) => ActivityLogEntry.fromJson(e as Map<String, dynamic>))
          .toList();

      if (!mounted) return;

      await showModalBottomSheet(
        context: context,
        backgroundColor: KinrelColors.darkBackground,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        isScrollControlled: true,
        builder: (ctx) => DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (ctx, scrollController) => Column(
            children: [
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 16),
                decoration: BoxDecoration(
                  color: KinrelColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text('Family Activity Log',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 18, fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                  )),
              const SizedBox(height: 16),
              Expanded(
                child: entries.isEmpty
                    ? Center(
                        child: Text('No activity yet',
                            style: TextStyle(color: KinrelColors.textDim)))
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: entries.length,
                        itemBuilder: (ctx, index) {
                          final e = entries[index];
                          return _buildLogEntry(e);
                        },
                      ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not load activity log.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildLogEntry(ActivityLogEntry e) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KinrelColors.border, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: KinrelColors.orange.withValues(alpha: 0.12),
            ),
            child: Icon(Icons.history, size: 14, color: KinrelColors.orange),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.description,
                    style: TextStyle(
                        fontSize: 13, color: KinrelColors.textWhite)),
                const SizedBox(height: 2),
                Text(_formatLogTime(e.createdAt),
                    style: TextStyle(
                        fontSize: 11, color: KinrelColors.textDim)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ──

  String _getValue(String key) {
    switch (key) {
      case 'whoCanInvite': return _settings!.whoCanInvite;
      case 'whoCanAddMembers': return _settings!.whoCanAddMembers;
      case 'whoCanEditInfo': return _settings!.whoCanEditInfo;
      case 'whoCanEditGraph': return _settings!.whoCanEditGraph;
      case 'whoCanChat': return _settings!.whoCanChat;
      case 'whoCanPostStories': return _settings!.whoCanPostStories;
      case 'whoCanCreateTruthStreak': return _settings!.whoCanCreateTruthStreak;
      case 'whoCanAddEvents': return _settings!.whoCanAddEvents;
      case 'familyVisibility': return _settings!.familyVisibility;
      default: return 'everyone';
    }
  }

  bool _getBoolValue(String key) {
    switch (key) {
      case 'allowMemberRemoval': return _settings!.allowMemberRemoval;
      case 'allowMembersToLeave': return _settings!.allowMembersToLeave;
      case 'confirmBeforeDeleteRelationship': return _settings!.confirmBeforeDeleteRelationship;
      case 'requireJoinApproval': return _settings!.requireJoinApproval;
      default: return true;
    }
  }

  String _permissionLabel(String value) {
    switch (value) {
      case 'admins': return 'Admins only';
      case 'creator': return 'Creator only';
      default: return 'Everyone';
    }
  }

  String _visibilityLabel(String value) {
    switch (value) {
      case 'private': return 'Private (hidden)';
      case 'public': return 'Public Discovery';
      default: return 'Invite Only';
    }
  }

  String _formatLogTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

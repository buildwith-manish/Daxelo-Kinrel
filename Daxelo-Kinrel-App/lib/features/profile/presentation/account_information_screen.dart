// lib/features/profile/presentation/account_information_screen.dart
//
// DAXELO KINREL — Account Information Screen
//
// v109: A dedicated screen for private account details that were removed
// from the Edit Profile screen. This screen is accessible from the
// Profile page's Account Settings section and contains:
//   • Email Address (display only — managed via auth)
//   • Phone Number (editable)
//   • Account Security (change password, 2FA, linked accounts, sessions)
//
// The Edit Profile screen now shows ONLY public profile fields (name,
// username, photo, bio, DOB, gender). Email and phone are private
// account details that live here, separated for privacy + clarity.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../shared/widgets/dk_components.dart';
import '../data/profile_provider.dart';

class AccountInformationScreen extends ConsumerStatefulWidget {
  const AccountInformationScreen({super.key});

  @override
  ConsumerState<AccountInformationScreen> createState() =>
      _AccountInformationScreenState();
}

class _AccountInformationScreenState
    extends ConsumerState<AccountInformationScreen> {
  late TextEditingController _phoneController;
  bool _isSaving = false;
  bool _hasChanges = false;
  String _initialPhone = '';

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController();

    final profile = ref.read(profileProvider).profile;
    final phone = profile?.phone ?? '';
    _phoneController.text = phone;
    _initialPhone = phone;
    _phoneController.addListener(_checkForChanges);
  }

  @override
  void dispose() {
    _phoneController.removeListener(_checkForChanges);
    _phoneController.dispose();
    super.dispose();
  }

  void _checkForChanges() {
    final hasChanges = _phoneController.text.trim() != _initialPhone;
    if (hasChanges != _hasChanges) {
      setState(() => _hasChanges = hasChanges);
    }
  }

  Future<void> _savePhone() async {
    if (!_hasChanges) return;
    setState(() => _isSaving = true);

    try {
      final success = await ref.read(profileProvider.notifier).updateProfile({
        'phone': _phoneController.text.trim(),
      });

      if (mounted) {
        setState(() {
          _isSaving = false;
          if (success) {
            _initialPhone = _phoneController.text.trim();
            _hasChanges = false;
          }
        });
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Phone number updated'),
              backgroundColor: KinrelColors.orange,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not update. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not update. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? 'No email';

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
          'Account Information',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textWhite,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.base,
          vertical: KinrelSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),

            // ── Section header ──────────────────────────────────────
            _buildSectionHeader('Private Account Details',
                'These details are private and only visible to you.'),
            const SizedBox(height: 20),

            // ── Email (display only — managed via auth) ─────────────
            _buildFieldLabel('Email Address'),
            const SizedBox(height: 6),
            _buildReadOnlyField(email, Icons.email_outlined),
            const SizedBox(height: 4),
            Text(
              'Your email is linked to your account and cannot be changed here.',
              style: TextStyle(
                fontSize: 11,
                color: KinrelColors.textDim,
              ),
            ),

            const SizedBox(height: 24),

            // ── Phone (editable) ────────────────────────────────────
            _buildFieldLabel('Phone Number'),
            const SizedBox(height: 6),
            _buildPhoneField(),

            const SizedBox(height: 32),

            // ── Save button (only shows when phone changed) ─────────
            if (_hasChanges)
              DKButton(
                label: 'Save Changes',
                variant: DKButtonVariant.primary,
                size: DKButtonSize.lg,
                fullWidth: true,
                isLoading: _isSaving,
                onPressed: _savePhone,
              ),

            const SizedBox(height: 32),

            // ── Account Security section ────────────────────────────
            _buildSectionHeader('Account Security',
                'Manage your account security and authentication settings.'),
            const SizedBox(height: 16),

            _buildSecurityTile(
              icon: Icons.lock_outline,
              title: 'Change Password',
              subtitle: 'Update your account password',
              onTap: () => context.push('/profile/change-password'),
            ),
            _buildSecurityTile(
              icon: Icons.security_outlined,
              title: 'Two-Factor Authentication',
              subtitle: 'Add an extra layer of security',
              onTap: () => context.push('/profile/2fa'),
            ),
            _buildSecurityTile(
              icon: Icons.link_outlined,
              title: 'Linked Accounts',
              subtitle: 'Manage connected accounts (Google, etc.)',
              onTap: () => context.push('/profile/linked-accounts'),
            ),
            _buildSecurityTile(
              icon: Icons.devices_outlined,
              title: 'Active Sessions',
              subtitle: 'View and manage your active sessions',
              onTap: () => context.push('/profile/sessions'),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textWhite,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 12,
            color: KinrelColors.textDim,
          ),
        ),
      ],
    );
  }

  Widget _buildFieldLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        fontFamily: KinrelTypography.bodyFont,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: KinrelColors.textSilver,
      ),
    );
  }

  Widget _buildReadOnlyField(String value, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: KinrelColors.border, width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: KinrelColors.textDim),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: KinrelColors.textWhite,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneField() {
    return Container(
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: KinrelColors.border, width: 1),
      ),
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 14),
            child: Icon(
              Icons.phone_outlined,
              size: 18,
              color: KinrelColors.textDim,
            ),
          ),
          Expanded(
            child: TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: KinrelColors.textWhite,
              ),
              decoration: InputDecoration(
                hintText: 'Phone number',
                hintStyle: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  color: KinrelColors.textDim,
                ),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
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
                      Text(
                        title,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: KinrelColors.textWhite,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 12,
                          color: KinrelColors.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: KinrelColors.textDim,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// lib/presentation/screens/settings/privacy_settings_screen.dart
//
// DAXELO KINREL — Privacy Settings Screen
//
//   • Profile Privacy toggle with confirm dialog
//   • Family Tree Visibility toggle with confirm dialog
//   • Loading state on switches, SnackBar on success/error

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../providers/privacy_provider.dart';

class PrivacySettingsScreen extends ConsumerStatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  ConsumerState<PrivacySettingsScreen> createState() =>
      _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState
    extends ConsumerState<PrivacySettingsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(privacyProvider.notifier).loadPrivacy();
    });
  }

  Future<void> _toggleProfilePrivacy(bool newValue) async {
    // Show confirm dialog for private (restrictive) change
    if (newValue) {
      final confirmed = await _showConfirmDialog(
        title: 'Make Profile Private?',
        message:
            'When your profile is private, only approved followers can see your posts and details. '
            'Existing followers will still have access.',
        confirmLabel: 'Make Private',
      );
      if (confirmed != true) return;
    }

    final success = await ref
        .read(privacyProvider.notifier)
        .updateProfilePrivacy(newValue);

    if (mounted) {
      _showSnackBar(
        success
            ? newValue
                ? 'Profile is now private'
                : 'Profile is now public'
            : 'Failed to update. Please try again.',
        isError: !success,
      );
    }
  }

  Future<void> _toggleFamilyGraphPrivacy(bool newValue) async {
    // Show confirm dialog for private (restrictive) change
    if (!newValue) {
      final confirmed = await _showConfirmDialog(
        title: 'Make Family Tree Private?',
        message:
            'When your family tree is private, only you and your family members can see it. '
            'Others won\'t be able to browse your family connections.',
        confirmLabel: 'Make Private',
      );
      if (confirmed != true) return;
    }

    final success = await ref
        .read(privacyProvider.notifier)
        .updateFamilyGraphPrivacy(newValue);

    if (mounted) {
      _showSnackBar(
        success
            ? newValue
                ? 'Family tree is now visible to everyone'
                : 'Family tree is now private'
            : 'Failed to update. Please try again.',
        isError: !success,
      );
    }
  }

  Future<bool?> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KinrelColors.darkCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.dialog),
          side: const BorderSide(color: KinrelColors.border),
        ),
        title: Row(
          children: [
            Icon(Icons.shield_outlined, color: KinrelColors.orange, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 14,
            color: KinrelColors.textSilver,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(color: KinrelColors.textDim),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: KinrelColors.orange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              confirmLabel,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? KinrelColors.error : KinrelColors.darkCard,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final privacyState = ref.watch(privacyProvider);

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
          'Privacy Settings',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textWhite,
          ),
        ),
      ),
      body: privacyState.isLoading
          ? Center(child: CircularProgressIndicator(color: KinrelColors.orange))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Section header
                Text(
                  'WHO CAN SEE YOUR CONTENT',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textDim,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                // Profile privacy card
                Container(
                  decoration: BoxDecoration(
                    color: KinrelColors.darkCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: KinrelColors.border),
                  ),
                  child: Column(
                    children: [
                      // Profile Privacy
                      SwitchListTile(
                        title: Row(
                          children: [
                            Icon(
                              Icons.lock_outline,
                              color: KinrelColors.orange,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Private Profile',
                                    style: TextStyle(
                                      fontFamily: KinrelTypography.bodyFont,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                      color: KinrelColors.textWhite,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    privacyState.isProfilePrivate
                                        ? 'Only approved followers can see your content'
                                        : 'Anyone can see your posts and details',
                                    style: TextStyle(
                                      fontFamily: KinrelTypography.bodyFont,
                                      fontSize: 12,
                                      color: KinrelColors.textDim,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        value: privacyState.isProfilePrivate,
                        onChanged: privacyState.isSaving ? null : _toggleProfilePrivacy,
                        activeColor: KinrelColors.orange,
                        activeTrackColor: KinrelColors.orange.withValues(alpha: 0.5),
                        secondary: null,
                      ),
                      Divider(
                        height: 1,
                        thickness: 0.5,
                        color: KinrelColors.border,
                        indent: 16,
                      ),
                      // Family Tree Visibility
                      SwitchListTile(
                        title: Row(
                          children: [
                            Icon(
                              Icons.account_tree_outlined,
                              color: KinrelColors.orange,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Public Family Tree',
                                    style: TextStyle(
                                      fontFamily: KinrelTypography.bodyFont,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                      color: KinrelColors.textWhite,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    privacyState.isFamilyGraphPublic
                                        ? 'Anyone can browse your family connections'
                                        : 'Only family members can see your tree',
                                    style: TextStyle(
                                      fontFamily: KinrelTypography.bodyFont,
                                      fontSize: 12,
                                      color: KinrelColors.textDim,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        value: privacyState.isFamilyGraphPublic,
                        onChanged:
                            privacyState.isSaving ? null : _toggleFamilyGraphPrivacy,
                        activeColor: KinrelColors.orange,
                        activeTrackColor: KinrelColors.orange.withValues(alpha: 0.5),
                        secondary: null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Info section
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: KinrelColors.orange.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: KinrelColors.orange.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: KinrelColors.orange,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Changes to your privacy settings take effect immediately. '
                          'Your existing connections and family members are not affected by these changes.',
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 13,
                            color: KinrelColors.textSilver,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/extensions/context_extensions.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Profile',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(KinrelSpacing.xl),
        child: Column(
          children: [
            // Avatar
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                gradient: KinrelColors.igniteGradient,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  (user?.email?.isNotEmpty == true
                      ? user!.email![0].toUpperCase()
                      : '?'),
                  style: const TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 36,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Name display
            Text(
              user?.userMetadata?['name'] as String? ??
                  user?.email?.split('@').first ??
                  'Not signed in',
              style: const TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textWhite,
              ),
            ),

            const SizedBox(height: 4),

            // Email
            Text(
              user?.email ?? '',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: KinrelColors.textSilver,
              ),
            ),

            const SizedBox(height: 4),

            // User ID
            Text(
              user?.id ?? '',
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 11,
                color: KinrelColors.textDim,
              ),
            ),

            const SizedBox(height: 32),

            // Profile info cards
            _ProfileInfoCard(
              icon: Icons.email,
              label: 'Email',
              value: user?.email ?? '-',
            ),
            const SizedBox(height: 8),
            _ProfileInfoCard(
              icon: Icons.calendar_today,
              label: 'Joined',
              value: user?.createdAt != null
                  ? DateTime.parse(user!.createdAt)
                      .toLocal()
                      .toString()
                      .split(' ')
                      .first
                  : '-',
            ),

            const SizedBox(height: 24),

            // Edit Name
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showEditNameDialog(context, ref, user),
                icon: const Icon(Icons.edit, size: 18),
                label: const Text('Edit Name'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: KinrelColors.orange,
                  side: const BorderSide(color: KinrelColors.orange),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(KinrelSpacing.radiusSm),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Change Password
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showChangePasswordDialog(context, ref),
                icon: const Icon(Icons.lock, size: 18),
                label: const Text('Change Password'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: KinrelColors.textSilver,
                  side: BorderSide(color: KinrelColors.darkSurface),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(KinrelSpacing.radiusSm),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Forgot Password
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () => _sendPasswordReset(context, ref),
                icon: const Icon(Icons.email_outlined, size: 18),
                label: const Text('Forgot Password?'),
                style: TextButton.styleFrom(
                  foregroundColor: KinrelColors.textDim,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditNameDialog(
    BuildContext context,
    WidgetRef ref,
    User? user,
  ) {
    final nameController =
        TextEditingController(text: user?.userMetadata?['name'] as String? ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KinrelColors.darkElevated,
        title: Text(
          'Edit Name',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            color: KinrelColors.textWhite,
          ),
        ),
        content: TextField(
          controller: nameController,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            color: KinrelColors.textWhite,
          ),
          decoration: InputDecoration(
            hintText: 'Enter your name',
            hintStyle: TextStyle(color: KinrelColors.textDim),
            filled: true,
            fillColor: KinrelColors.darkCard,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(KinrelSpacing.radiusSm),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: KinrelColors.textSilver),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await ref.read(authServiceProvider).updatePassword('');
                // Update user metadata with name
                final client = ref.read(supabaseProvider);
                await client.auth.updateUser(
                  UserAttributes(
                    data: {'name': nameController.text.trim()},
                  ),
                );
                if (context.mounted) {
                  context.showSnackBar('Name updated successfully');
                }
              } catch (e) {
                if (context.mounted) {
                  context.showSnackBar('Failed to update name', isError: true);
                }
              }
            },
            child: Text(
              'Save',
              style: TextStyle(color: KinrelColors.orange),
            ),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context, WidgetRef ref) {
    final currentController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KinrelColors.darkElevated,
        title: Text(
          'Change Password',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            color: KinrelColors.textWhite,
          ),
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: currentController,
                obscureText: true,
                style: TextStyle(color: KinrelColors.textWhite),
                decoration: InputDecoration(
                  labelText: 'Current Password',
                  labelStyle: TextStyle(color: KinrelColors.textDim),
                  filled: true,
                  fillColor: KinrelColors.darkCard,
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(KinrelSpacing.radiusSm),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: newController,
                obscureText: true,
                style: TextStyle(color: KinrelColors.textWhite),
                decoration: InputDecoration(
                  labelText: 'New Password',
                  labelStyle: TextStyle(color: KinrelColors.textDim),
                  filled: true,
                  fillColor: KinrelColors.darkCard,
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(KinrelSpacing.radiusSm),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (v) =>
                    v == null || v.length < 6 ? 'Min 6 characters' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: confirmController,
                obscureText: true,
                style: TextStyle(color: KinrelColors.textWhite),
                decoration: InputDecoration(
                  labelText: 'Confirm Password',
                  labelStyle: TextStyle(color: KinrelColors.textDim),
                  filled: true,
                  fillColor: KinrelColors.darkCard,
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(KinrelSpacing.radiusSm),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (v) {
                  if (v != newController.text) return 'Passwords don\'t match';
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: KinrelColors.textSilver),
            ),
          ),
          TextButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              Navigator.of(ctx).pop();

              try {
                await ref
                    .read(authServiceProvider)
                    .updatePassword(newController.text);
                if (context.mounted) {
                  context.showSnackBar('Password updated successfully');
                }
              } catch (e) {
                if (context.mounted) {
                  context.showSnackBar(
                    'Failed to update password',
                    isError: true,
                  );
                }
              }
            },
            child: Text(
              'Update',
              style: TextStyle(color: KinrelColors.orange),
            ),
          ),
        ],
      ),
    );
  }

  void _sendPasswordReset(BuildContext context, WidgetRef ref) async {
    final user = ref.read(currentUserProvider);
    if (user?.email == null) {
      context.showSnackBar('No email on file', isError: true);
      return;
    }

    try {
      await ref.read(authServiceProvider).resetPassword(user!.email!);
      if (context.mounted) {
        context.showSnackBar('Password reset email sent to ${user.email}');
      }
    } catch (e) {
      if (context.mounted) {
        context.showSnackBar('Failed to send reset email', isError: true);
      }
    }
  }
}

class _ProfileInfoCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ProfileInfoCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusSm),
        border: Border.all(
            color: KinrelColors.darkSurface.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: KinrelColors.orange),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 11,
                  color: KinrelColors.textDim,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  color: KinrelColors.textWhite,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

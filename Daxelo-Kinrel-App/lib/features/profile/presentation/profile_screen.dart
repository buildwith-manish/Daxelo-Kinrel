import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../shared/widgets/dk_components.dart';

class ProfileScreen extends ConsumerWidget {
  ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;

    return DKScaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(KinrelSpacing.base),
        child: Column(
          children: [
            const SizedBox(height: 8),

            // Profile header with gold-bordered avatar
            DKAvatar(
              initials: (user?.email?.isNotEmpty == true
                  ? user!.email![0].toUpperCase()
                  : '?'),
              size: DKAvatarSize.xl,
              borderColor: DKColors.brandGold,
              backgroundColor: DKColors.brandPurple,
              showGlow: true,
            )
                .animate(onPlay: (c) => c.forward())
                .fadeIn(duration: 500.ms)
                .scale(
                  begin: const Offset(0.8, 0.8),
                  end: const Offset(1.0, 1.0),
                  duration: 400.ms,
                  curve: Curves.easeOutBack,
                ),

            const SizedBox(height: 16),

            // Name
            Text(
              user?.userMetadata?['name'] as String? ??
                  user?.email?.split('@').first ??
                  'Not signed in',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: DKColors.textPrimary(context),
              ),
            ),

            const SizedBox(height: 4),

            // Email
            Text(
              user?.email ?? '',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: DKColors.textSecondary(context),
              ),
            ),

            const SizedBox(height: 32),

            // Menu items as cards
            _MenuCard(
              icon: Icons.family_restroom,
              label: 'My Families',
              subtitle: 'Manage your family trees',
              color: DKColors.brandPurple,
              onTap: () {},
              index: 0,
            ),
            const SizedBox(height: 8),
            _MenuCard(
              icon: Icons.language,
              label: 'Language',
              subtitle: 'App display language',
              color: DKColors.brandPurple,
              onTap: () {},
              index: 1,
            ),
            const SizedBox(height: 8),
            _MenuCard(
              icon: isDark ? Icons.dark_mode : Icons.light_mode,
              label: 'Theme',
              subtitle: isDark ? 'Dark mode' : 'Light mode',
              color: DKColors.brandGold,
              trailing: Switch(
                value: isDark,
                onChanged: (value) {
                  ref.read(themeModeProvider.notifier).state =
                      value ? ThemeMode.dark : ThemeMode.light;
                },
                activeThumbColor: DKColors.brandPurple,
                activeTrackColor: DKColors.brandPurple.withValues(alpha: 0.5),
              ),
              onTap: () {
                ref.read(themeModeProvider.notifier).state =
                    isDark ? ThemeMode.light : ThemeMode.dark;
              },
              index: 2,
            ),
            const SizedBox(height: 8),
            _MenuCard(
              icon: Icons.notifications,
              label: 'Notifications',
              subtitle: 'Alerts & reminders',
              color: DKColors.brandPurple,
              onTap: () {},
              index: 3,
            ),
            const SizedBox(height: 8),
            _MenuCard(
              icon: Icons.privacy_tip,
              label: 'Privacy',
              subtitle: 'Data & privacy settings',
              color: DKColors.brandPurple,
              onTap: () {},
              index: 4,
            ),
            const SizedBox(height: 8),
            _MenuCard(
              icon: Icons.help,
              label: 'Help & Support',
              subtitle: 'FAQ & contact',
              color: DKColors.brandPurple,
              onTap: () {},
              index: 5,
            ),
            const SizedBox(height: 8),
            _MenuCard(
              icon: Icons.info,
              label: 'About',
              subtitle: 'Version 1.0.0',
              color: DKColors.brandPurple,
              onTap: () {},
              index: 6,
            ),

            const SizedBox(height: 32),

            // Sign Out button (gradient: red→purple)
            DKButton(
              label: 'Sign Out',
              variant: DKButtonVariant.gradient,
              gradient: KinrelGradients.signOutGradient,
              icon: Icons.logout,
              fullWidth: true,
              size: DKButtonSize.lg,
              onPressed: () async {
                try {
                  await ref.read(authServiceProvider).signOut();
                  if (context.mounted) context.go('/sign-in');
                } catch (e) {
                  if (context.mounted) {
                    context.showSnackBar('Error signing out', isError: true);
                  }
                }
              },
            )
                .animate(onPlay: (c) => c.forward())
                .fadeIn(duration: 500.ms, delay: 400.ms),

            const SizedBox(height: 16),

            // Footer
            Text(
              'KINREL by Daxelo',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 12,
                color: DKColors.textSecondary(context),
                letterSpacing: 1,
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

}

// ── Menu Card ────────────────────────────────────────────────────

class _MenuCard extends StatelessWidget {
  const _MenuCard({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.color,
    this.trailing,
    required this.onTap,
    required this.index,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final Color color;
  final Widget? trailing;
  final VoidCallback onTap;
  final int index;


  @override
  Widget build(BuildContext context) {
    return DKCard(
      borderColor: DKColors.brandPurple.withValues(alpha: 0.1),
      onTap: onTap,
      padding: 14,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(KinrelRadius.md),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: DKColors.textPrimary(context),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      color: DKColors.textSecondary(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
          trailing ??
              Icon(Icons.chevron_right,
                  color: DKColors.textSecondary(context).withValues(alpha: 0.5),
                  size: 20),
        ],
      ),
    )
        .animate(onPlay: (c) => c.forward())
        .fadeIn(
          duration: 400.ms,
          delay: Duration(milliseconds: 100 + index * 50),
        )
        .slideX(begin: 0.05, end: 0, duration: 400.ms);
  }
}

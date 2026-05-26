import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/supported_languages.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../shared/widgets/dk_components.dart';

/// Provider for the user's selected language
final selectedLanguageProvider = StateProvider<SupportedLanguage>(
  (ref) => SupportedLanguage.english,
);

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fontScale = ref.watch(fontScaleProvider);
    final selectedLanguage = ref.watch(selectedLanguageProvider);
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;

    return DKScaffold(
      body: ListView(
        padding: const EdgeInsets.all(KinrelSpacing.base),
        children: [
          // ── Account Section ──────────────────────────────────────
          const _SectionHeader(title: 'Account', index: 0),
          const SizedBox(height: 8),

          DKCard(
            borderColor: DKColors.brandPurple.withValues(alpha: 0.08),
            padding: 0,
            child: Column(
              children: [
                _SettingsTile(
                  icon: Icons.person_outline,
                  title: 'Edit Profile',
                  color: DKColors.brandPurple,
                  onTap: () => context.go('/profile'),
                ),
                _SettingsDivider(),
                _SettingsTile(
                  icon: Icons.lock_outline,
                  title: 'Change Password',
                  color: DKColors.brandPurple,
                  onTap: () => _showChangePasswordDialog(context, ref),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Preferences Section ──────────────────────────────────
          const _SectionHeader(title: 'Preferences', index: 1),
          const SizedBox(height: 8),

          DKCard(
            borderColor: DKColors.brandPurple.withValues(alpha: 0.08),
            padding: 0,
            child: Column(
              children: [
                _SettingsTile(
                  icon: isDark ? Icons.dark_mode : Icons.light_mode,
                  title: 'Theme',
                  subtitle: isDark ? 'Dark' : 'Light',
                  color: DKColors.brandGold,
                  trailing: Switch(
                    value: isDark,
                    onChanged: (value) {
                      ref.read(themeModeProvider.notifier).state =
                          value ? ThemeMode.dark : ThemeMode.light;
                    },
                    activeThumbColor: DKColors.brandPurple,
                    activeTrackColor:
                        DKColors.brandPurple.withValues(alpha: 0.5),
                  ),
                  onTap: () {
                    ref.read(themeModeProvider.notifier).state =
                        isDark ? ThemeMode.light : ThemeMode.dark;
                  },
                ),
                _SettingsDivider(),
                _SettingsTile(
                  icon: Icons.translate,
                  title: 'Language',
                  subtitle:
                      '${selectedLanguage.nativeName} (${selectedLanguage.name})',
                  color: DKColors.brandPurple,
                  onTap: () =>
                      _showLanguagePicker(context, ref, selectedLanguage),
                ),
                _SettingsDivider(),
                _SettingsTile(
                  icon: Icons.text_fields,
                  title: 'Font Size',
                  subtitle: fontScale <= 0.9
                      ? 'Small'
                      : fontScale <= 1.05
                          ? 'Medium'
                          : fontScale <= 1.2
                              ? 'Large'
                              : 'Extra Large',
                  color: DKColors.brandPurple,
                  trailing: SegmentedButton<double>(
                    segments: const [
                      ButtonSegment(value: 0.85, label: Text('S')),
                      ButtonSegment(value: 1.0, label: Text('M')),
                      ButtonSegment(value: 1.15, label: Text('L')),
                      ButtonSegment(value: 1.3, label: Text('XL')),
                    ],
                    selected: {fontScale},
                    onSelectionChanged: (scales) =>
                        ref.read(fontScaleProvider.notifier).state =
                            scales.first,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Privacy Section ─────────────────────────────────────
          const _SectionHeader(title: 'Privacy', index: 2),
          const SizedBox(height: 8),

          DKCard(
            borderColor: DKColors.brandPurple.withValues(alpha: 0.08),
            padding: 0,
            child: Column(
              children: [
                _SettingsTile(
                  icon: Icons.shield_outlined,
                  title: 'Data & Privacy',
                  color: DKColors.brandPurple,
                  onTap: () {},
                ),
                _SettingsDivider(),
                _SettingsTile(
                  icon: Icons.delete_forever_outlined,
                  title: 'Delete Account',
                  titleColor: DKColors.brandCoral,
                  color: DKColors.brandCoral,
                  onTap: () {
                    // TODO: Account deletion flow
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── About Section ───────────────────────────────────────
          const _SectionHeader(title: 'About', index: 3),
          const SizedBox(height: 8),

          DKCard(
            borderColor: DKColors.brandPurple.withValues(alpha: 0.08),
            padding: 0,
            child: Column(
              children: [
                const _SettingsTile(
                  icon: Icons.info_outline,
                  title: 'App Version',
                  subtitle: '1.0.0',
                  color: DKColors.brandPurple,
                ),
                _SettingsDivider(),
                _SettingsTile(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy Policy',
                  color: DKColors.brandPurple,
                  onTap: () {},
                ),
                _SettingsDivider(),
                _SettingsTile(
                  icon: Icons.description_outlined,
                  title: 'Terms of Service',
                  color: DKColors.brandPurple,
                  onTap: () {},
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Sign Out
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
                await SecureStorageService().clearAuthTokens();
                if (context.mounted) context.go('/sign-in');
              } catch (e) {
                if (context.mounted) {
                  context.showSnackBar('Error signing out', isError: true);
                }
              }
            },
          ),

          const SizedBox(height: 24),

          // Footer
          Center(
            child: Text(
              'KINREL by Daxelo',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 12,
                color: DKColors.textSecondary(context),
                letterSpacing: 1,
              ),
            ),
          ),

          const SizedBox(height: 48),
        ],
      ),
    );
  }

  void _showLanguagePicker(
    BuildContext context,
    WidgetRef ref,
    SupportedLanguage current,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DKColors.cardColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.dialog),
          side: BorderSide(color: DKColors.borderColor(context)),
        ),
        title: Text(
          'Select Language',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            color: DKColors.textPrimary(context),
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: ListView(
            shrinkWrap: true,
            children: SupportedLanguage.values.map((lang) {
              final isSelected = lang == current;
              return ListTile(
                leading: DKAvatar(
                  initials: lang.code.toUpperCase(),
                  size: DKAvatarSize.sm,
                  backgroundColor: isSelected
                      ? DKColors.brandPurple
                      : DKColors.elevatedColor(context),
                ),
                title: Text(
                  lang.nativeName,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    color: isSelected
                        ? DKColors.brandPurple
                        : DKColors.textPrimary(context),
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                subtitle: Text(
                  lang.name,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    color: DKColors.textSecondary(context),
                  ),
                ),
                trailing: isSelected
                    ? const Icon(Icons.check_circle, color: DKColors.brandPurple)
                    : null,
                onTap: () {
                  ref.read(selectedLanguageProvider.notifier).state = lang;
                  Navigator.of(ctx).pop();
                },
              );
            }).toList(),
          ),
        ),
        actions: [
          DKButton(
            label: 'Cancel',
            variant: DKButtonVariant.secondary,
            size: DKButtonSize.sm,
            onPressed: () => Navigator.of(ctx).pop(),
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
        backgroundColor: DKColors.cardColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.dialog),
          side: BorderSide(color: DKColors.borderColor(context)),
        ),
        title: Text(
          'Change Password',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            color: DKColors.textPrimary(context),
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
                style: TextStyle(color: DKColors.textPrimary(context)),
                decoration: InputDecoration(
                  labelText: 'Current Password',
                  labelStyle:
                      TextStyle(color: DKColors.textSecondary(context)),
                  filled: true,
                  fillColor: DKColors.elevatedColor(context),
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(KinrelRadius.input),
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
                style: TextStyle(color: DKColors.textPrimary(context)),
                decoration: InputDecoration(
                  labelText: 'New Password',
                  labelStyle:
                      TextStyle(color: DKColors.textSecondary(context)),
                  filled: true,
                  fillColor: DKColors.elevatedColor(context),
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(KinrelRadius.input),
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
                style: TextStyle(color: DKColors.textPrimary(context)),
                decoration: InputDecoration(
                  labelText: 'Confirm Password',
                  labelStyle:
                      TextStyle(color: DKColors.textSecondary(context)),
                  filled: true,
                  fillColor: DKColors.elevatedColor(context),
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(KinrelRadius.input),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (v) {
                  if (v != newController.text) {
                    return 'Passwords don\'t match';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          DKButton(
            label: 'Cancel',
            variant: DKButtonVariant.secondary,
            size: DKButtonSize.sm,
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          DKButton(
            label: 'Update',
            variant: DKButtonVariant.primary,
            size: DKButtonSize.sm,
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
          ),
        ],
      ),
    );
  }
}

// ── Section Header ────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.index});

  final String title;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: DKColors.brandPurple,
          letterSpacing: 1,
        ),
      ),
    )
        .animate(onPlay: (c) => c.forward())
        .fadeIn(
          duration: 300.ms,
          delay: Duration(milliseconds: index * 60),
        );
  }
}

// ── Settings Tile ─────────────────────────────────────────────────

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.titleColor,
    required this.color,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? titleColor;
  final Color color;
  final Widget? trailing;
  final VoidCallback? onTap;


  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(KinrelRadius.sm),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 15,
          color: titleColor ?? DKColors.textPrimary(context),
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                color: DKColors.textSecondary(context),
              ),
            )
          : null,
      trailing: trailing ??
          (onTap != null
              ? Icon(Icons.chevron_right,
                  color: DKColors.textSecondary(context).withValues(alpha: 0.5),
                  size: 20)
              : null),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.md, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KinrelRadius.sm),
      ),
    );
  }
}

// ── Settings Divider ──────────────────────────────────────────────

class _SettingsDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.md),
      child: Divider(
        height: 1,
        color: DKColors.brandPurple.withValues(alpha: 0.08),
      ),
    );
  }
}

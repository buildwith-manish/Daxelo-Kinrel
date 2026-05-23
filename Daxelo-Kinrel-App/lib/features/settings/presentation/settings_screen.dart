import 'package:flutter/material.dart';
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

/// Provider for the user's selected language
final selectedLanguageProvider = StateProvider<SupportedLanguage>(
  (ref) => SupportedLanguage.english,
);

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final fontScale = ref.watch(fontScaleProvider);
    final selectedLanguage = ref.watch(selectedLanguageProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Settings',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(KinrelSpacing.base),
        children: [
          // ── Appearance ─────────────────────────────────────────
          const _SectionHeader(title: 'Appearance'),

          _SettingsTile(
            icon: Icons.dark_mode,
            title: 'Theme',
            subtitle: themeMode == ThemeMode.dark
                ? 'Dark'
                : themeMode == ThemeMode.light
                    ? 'Light'
                    : 'System',
            trailing: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                    value: ThemeMode.dark, icon: Icon(Icons.dark_mode)),
                ButtonSegment(
                    value: ThemeMode.light, icon: Icon(Icons.light_mode)),
                ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(Icons.brightness_auto)),
              ],
              selected: {themeMode},
              onSelectionChanged: (modes) =>
                  ref.read(themeModeProvider.notifier).state = modes.first,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),

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
            trailing: SegmentedButton<double>(
              segments: const [
                ButtonSegment(value: 0.85, label: Text('S')),
                ButtonSegment(value: 1.0, label: Text('M')),
                ButtonSegment(value: 1.15, label: Text('L')),
                ButtonSegment(value: 1.3, label: Text('XL')),
              ],
              selected: {fontScale},
              onSelectionChanged: (scales) =>
                  ref.read(fontScaleProvider.notifier).state = scales.first,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── Language ───────────────────────────────────────────
          const _SectionHeader(title: 'Language'),

          _SettingsTile(
            icon: Icons.translate,
            title: 'Preferred Language',
            subtitle: '${selectedLanguage.nativeName} (${selectedLanguage.name})',
            onTap: () => _showLanguagePicker(context, ref, selectedLanguage),
          ),

          const SizedBox(height: 24),

          // ── Account ────────────────────────────────────────────
          const _SectionHeader(title: 'Account'),

          _SettingsTile(
            icon: Icons.person,
            title: 'Profile',
            onTap: () => context.go('/profile'),
          ),

          _SettingsTile(
            icon: Icons.lock,
            title: 'Change Password',
            onTap: () => _showChangePasswordDialog(context, ref),
          ),

          _SettingsTile(
            icon: Icons.exit_to_app,
            title: 'Sign Out',
            titleColor: KinrelColors.error,
            onTap: () async {
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

          // ── About ──────────────────────────────────────────────
          const _SectionHeader(title: 'About'),

          const _SettingsTile(
            icon: Icons.info,
            title: 'App Version',
            subtitle: '1.0.0',
          ),

          _SettingsTile(
            icon: Icons.privacy_tip,
            title: 'Privacy Policy',
            onTap: () {
              // TODO: Open privacy policy
            },
          ),

          _SettingsTile(
            icon: Icons.description,
            title: 'Terms of Service',
            onTap: () {
              // TODO: Open terms
            },
          ),

          const SizedBox(height: 48),

          // Footer
          Center(
            child: Text(
              'KINREL by Daxelo',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 12,
                color: KinrelColors.textDim,
                letterSpacing: 1,
              ),
            ),
          ),
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
        backgroundColor: KinrelColors.darkElevated,
        title: Text(
          'Select Language',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            color: KinrelColors.textWhite,
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
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? KinrelColors.orange.withValues(alpha: 0.15)
                        : KinrelColors.darkCard,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      lang.code.toUpperCase(),
                      style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? KinrelColors.orange
                            : KinrelColors.textDim,
                      ),
                    ),
                  ),
                ),
                title: Text(
                  lang.nativeName,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    color: isSelected
                        ? KinrelColors.orange
                        : KinrelColors.textWhite,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                subtitle: Text(
                  lang.name,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    color: KinrelColors.textDim,
                  ),
                ),
                trailing: isSelected
                    ? Icon(Icons.check_circle, color: KinrelColors.orange)
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
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: KinrelColors.textSilver),
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
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: KinrelColors.orange,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? titleColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.titleColor,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: titleColor ?? KinrelColors.textSilver),
      title: Text(
        title,
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 15,
          color: titleColor ?? KinrelColors.textWhite,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                color: KinrelColors.textDim,
              ),
            )
          : null,
      trailing: trailing ??
          (onTap != null
              ? Icon(Icons.chevron_right, color: KinrelColors.textDim)
              : null),
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
    );
  }
}

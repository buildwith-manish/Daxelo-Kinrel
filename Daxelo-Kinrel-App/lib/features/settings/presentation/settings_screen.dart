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

// ── Design Tokens (matching profile_screen) ────────────────────────
const Color _bg = Color(0xFF131416);
const Color _cardBg = Color(0xFF191B2C);
const Color _orange = Color(0xFFE8612A);
const Color _textPrimary = Color(0xFFF5F0EE);
const Color _textSecondary = Color(0xFFC9B4A8);
const Color _textDim = Color(0xFF8A7A72);
const Color _chevronColor = Color(0xFF8A7A72);
const Color _borderSubtle = Color(0x0FFFFFFF); // rgba(255,255,255,0.06)

/// Provider for the user's selected language
final selectedLanguageProvider = StateProvider<SupportedLanguage>(
  (ref) => SupportedLanguage.english,
);

class SettingsScreen extends ConsumerStatefulWidget {
  SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // ── Toggle Providers ───────────────────────────────────────────
  final _twoFactorProvider = StateProvider<bool>((ref) => false);
  final _pushNotifProvider = StateProvider<bool>((ref) => true);
  final _birthdayRemindersProvider = StateProvider<bool>((ref) => true);
  final _anniversaryRemindersProvider = StateProvider<bool>((ref) => false);
  final _familyActivityProvider = StateProvider<bool>((ref) => true);
  final _biometricLockProvider = StateProvider<bool>((ref) => false);

  @override
  Widget build(BuildContext context) {
    final fontScale = ref.watch(fontScaleProvider);
    final selectedLanguage = ref.watch(selectedLanguageProvider);
    final themeMode = ref.watch(themeModeProvider);

    return DKScaffold(
      backgroundColor: _bg,
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.base,
          vertical: KinrelSpacing.sm,
        ),
        children: [
          const SizedBox(height: 8),

          // ── Account ─────────────────────────────────────────────
          _buildSectionHeader('Account'),
          const SizedBox(height: 8),
          _buildSectionCard([
            _SettingsRow(
              icon: Icons.person_outline,
              label: 'Profile details',
              subtitle: 'Name, email, phone, DOB',
              onTap: () => context.go('/profile'),
            ),
            _divider(),
            _SettingsRow(
              icon: Icons.lock_outline,
              label: 'Change password',
              onTap: () => _showChangePasswordDialog(context, ref),
            ),
            _divider(),
            _SettingsRow(
              icon: Icons.link_outlined,
              label: 'Linked accounts',
              subtitle: 'Google, Apple',
              onTap: () {},
            ),
            _divider(),
            _SettingsRow(
              icon: Icons.language_outlined,
              label: 'Preferred language',
              onTap: () {},
            ),
            _divider(),
            _SettingsToggleRow(
              icon: Icons.shield_outlined,
              label: 'Two-factor authentication',
              provider: _twoFactorProvider,
            ),
          ]),
          const SizedBox(height: 24),

          // ── Appearance ──────────────────────────────────────────
          _buildSectionHeader('Appearance'),
          const SizedBox(height: 8),
          _buildSectionCard([
            _SettingsSegmentedRow<ThemeMode>(
              icon: Icons.dark_mode_outlined,
              label: 'Theme',
              segments: {
                ThemeMode.dark: 'Dark',
                ThemeMode.light: 'Light',
                ThemeMode.system: 'System',
              },
              value: themeMode,
              onChanged: (v) =>
                  ref.read(themeModeProvider.notifier).state = v,
            ),
            _divider(),
            _SettingsRow(
              icon: Icons.translate_outlined,
              label: 'App language',
              subtitle:
                  '${selectedLanguage.nativeName} (${selectedLanguage.name})',
              onTap: () =>
                  _showLanguagePicker(context, ref, selectedLanguage),
            ),
            _divider(),
            _SettingsFontScaleRow(
              icon: Icons.text_fields,
              label: 'Font size',
              value: fontScale,
              onChanged: (v) =>
                  ref.read(fontScaleProvider.notifier).state = v,
            ),
          ]),
          const SizedBox(height: 24),

          // ── Notifications ───────────────────────────────────────
          _buildSectionHeader('Notifications'),
          const SizedBox(height: 8),
          _buildSectionCard([
            _SettingsToggleRow(
              icon: Icons.notifications_outlined,
              label: 'Push notifications',
              provider: _pushNotifProvider,
            ),
            _divider(),
            _SettingsToggleRow(
              icon: Icons.cake_outlined,
              label: 'Birthday reminders',
              provider: _birthdayRemindersProvider,
            ),
            _divider(),
            _SettingsToggleRow(
              icon: Icons.favorite_outline,
              label: 'Anniversary reminders',
              provider: _anniversaryRemindersProvider,
            ),
            _divider(),
            _SettingsToggleRow(
              icon: Icons.group_outlined,
              label: 'Family activity',
              provider: _familyActivityProvider,
            ),
            _divider(),
            _SettingsRow(
              icon: Icons.bedtime_outlined,
              label: 'Quiet hours',
              onTap: () {},
            ),
          ]),
          const SizedBox(height: 24),

          // ── Privacy & Security ──────────────────────────────────
          _buildSectionHeader('Privacy & Security'),
          const SizedBox(height: 8),
          _buildSectionCard([
            _SettingsRow(
              icon: Icons.visibility_outlined,
              label: 'Profile visibility',
              subtitle: 'Public / Private',
              onTap: () {},
            ),
            _divider(),
            _SettingsRow(
              icon: Icons.person_add_outlined,
              label: 'Who can invite me',
              onTap: () {},
            ),
            _divider(),
            _SettingsToggleRow(
              icon: Icons.fingerprint,
              label: 'Biometric lock',
              provider: _biometricLockProvider,
            ),
            _divider(),
            _SettingsRow(
              icon: Icons.devices_outlined,
              label: 'Active sessions',
              onTap: () {},
            ),
            _divider(),
            _SettingsRow(
              icon: Icons.download_outlined,
              label: 'Download my data',
              onTap: () {},
            ),
            _divider(),
            _SettingsDeleteRow(
              label: 'Delete my account',
              onTap: () {
                // TODO: Account deletion flow
              },
            ),
          ]),
          const SizedBox(height: 24),

          // ── Family Management ───────────────────────────────────
          _buildSectionHeader('Family Management'),
          const SizedBox(height: 8),
          _buildSectionCard([
            _SettingsRow(
              icon: Icons.account_tree_outlined,
              label: 'My family trees',
              onTap: () {},
            ),
            _divider(),
            _SettingsRow(
              icon: Icons.mail_outline,
              label: 'Pending invitations',
              badge: 3,
              onTap: () {},
            ),
            _divider(),
            _SettingsRow(
              icon: Icons.block_outlined,
              label: 'Blocked members',
              onTap: () {},
            ),
            _divider(),
            _SettingsRow(
              icon: Icons.upload_file_outlined,
              label: 'Export family tree',
              onTap: () {},
            ),
          ]),
          const SizedBox(height: 24),

          // ── Support ─────────────────────────────────────────────
          _buildSectionHeader('Support'),
          const SizedBox(height: 8),
          _buildSectionCard([
            _SettingsRow(
              icon: Icons.help_outline,
              label: 'Help center / FAQ',
              onTap: () {},
            ),
            _divider(),
            _SettingsRow(
              icon: Icons.support_agent,
              label: 'Contact support',
              onTap: () {},
            ),
            _divider(),
            _SettingsRow(
              icon: Icons.bug_report_outlined,
              label: 'Report a bug',
              onTap: () {},
            ),
            _divider(),
            _SettingsRow(
              icon: Icons.star_outline,
              label: 'Rate the app',
              onTap: () {},
            ),
            _divider(),
            _SettingsRow(
              icon: Icons.share_outlined,
              label: 'Share Kinrel with friends',
              iconColor: _orange,
              labelColor: _orange,
              onTap: () {},
            ),
          ]),
          const SizedBox(height: 24),

          // ── About ───────────────────────────────────────────────
          _buildSectionHeader('About'),
          const SizedBox(height: 8),
          _buildSectionCard([
            _SettingsRow(
              icon: Icons.info_outline,
              label: 'App version',
              trailing: Text(
                '1.0.0',
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 13,
                  color: _textDim,
                ),
              ),
            ),
            _divider(),
            _SettingsRow(
              icon: Icons.description_outlined,
              label: 'Terms of service',
              onTap: () {},
            ),
            _divider(),
            _SettingsRow(
              icon: Icons.privacy_tip_outlined,
              label: 'Privacy policy',
              onTap: () {},
            ),
          ]),
          const SizedBox(height: 16),

          // ── Footer ──────────────────────────────────────────────
          Center(
            child: Text(
              'Made with love by Daxelo',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: _textDim,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Sign Out ────────────────────────────────────────────
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

          const SizedBox(height: 48),
        ],
      ),
    );
  }

  // ── Section Header ────────────────────────────────────────────────

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        title,
        style: const TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: _orange,
          letterSpacing: 0.8,
        ),
      ),
    )
        .animate(onPlay: (c) => c.forward())
        .fadeIn(duration: 300.ms);
  }

  // ── Section Card ──────────────────────────────────────────────────

  Widget _buildSectionCard(List<Widget> children) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderSubtle),
      ),
      child: Column(children: children),
    );
  }

  // ── Divider ───────────────────────────────────────────────────────

  Widget _divider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Divider(height: 1, thickness: 0.5, color: _borderSubtle),
    );
  }

  // ── Language Picker ───────────────────────────────────────────────

  void _showLanguagePicker(
    BuildContext context,
    WidgetRef ref,
    SupportedLanguage current,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.dialog),
          side: const BorderSide(color: _borderSubtle),
        ),
        title: const Text(
          'Select Language',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            color: _textPrimary,
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
                        ? _orange
                        : KinrelColors.darkElevated,
                    borderRadius: BorderRadius.circular(KinrelRadius.sm),
                  ),
                  child: Center(
                    child: Text(
                      lang.code.toUpperCase(),
                      style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? Colors.white
                            : _textDim,
                      ),
                    ),
                  ),
                ),
                title: Text(
                  lang.nativeName,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    color: isSelected ? _orange : _textPrimary,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                subtitle: Text(
                  lang.name,
                  style: const TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    color: _textDim,
                  ),
                ),
                trailing: isSelected
                    ? const Icon(Icons.check_circle, color: _orange)
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
            child: const Text(
              'Cancel',
              style: TextStyle(color: _textDim),
            ),
          ),
        ],
      ),
    );
  }

  // ── Change Password Dialog ────────────────────────────────────────

  void _showChangePasswordDialog(BuildContext context, WidgetRef ref) {
    final currentController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.dialog),
          side: const BorderSide(color: _borderSubtle),
        ),
        title: const Text(
          'Change Password',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            color: _textPrimary,
          ),
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogField(currentController, 'Current Password'),
              const SizedBox(height: 12),
              _dialogField(newController, 'New Password', minLength: 6),
              const SizedBox(height: 12),
              _dialogField(
                confirmController,
                'Confirm Password',
                matchController: newController,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: _textDim),
            ),
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

  Widget _dialogField(
    TextEditingController controller,
    String label, {
    int minLength = 1,
    TextEditingController? matchController,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: true,
      style: const TextStyle(color: _textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _textDim),
        filled: true,
        fillColor: KinrelColors.darkElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.input),
          borderSide: BorderSide.none,
        ),
      ),
      validator: (v) {
        if (v == null || v.isEmpty) return 'Required';
        if (v.length < minLength) return 'Min $minLength characters';
        if (matchController != null && v != matchController.text) {
          return "Passwords don't match";
        }
        return null;
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Shared Settings Widgets (same design language as profile_screen)
// ═══════════════════════════════════════════════════════════════════════

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.label,
    this.subtitle,
    this.badge,
    this.iconColor = _textDim,
    this.labelColor = _textPrimary,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final int? badge;
  final Color iconColor;
  final Color labelColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            label,
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: labelColor,
                            ),
                          ),
                        ),
                        if (badge != null && badge! > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _orange,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${badge!}',
                              style: const TextStyle(
                                fontFamily: KinrelTypography.displayFont,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 12,
                          color: _textDim,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              trailing ??
                  const Icon(
                    Icons.chevron_right,
                    color: _chevronColor,
                    size: 20,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsToggleRow extends ConsumerWidget {
  const _SettingsToggleRow({
    required this.icon,
    required this.label,
    required this.provider,
  });

  final IconData icon;
  final String label;
  final StateProvider<bool> provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(provider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: _textDim, size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: _textPrimary,
              ),
            ),
          ),
          SizedBox(
            height: 28,
            child: Switch(
              value: value,
              onChanged: (v) => ref.read(provider.notifier).state = v,
              activeColor: _orange,
              activeTrackColor: _orange.withValues(alpha: 0.5),
              thumbColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return Colors.white;
                return const Color(0xFF9E9E9E);
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSegmentedRow<T> extends StatelessWidget {
  const _SettingsSegmentedRow({
    required this.icon,
    required this.label,
    required this.segments,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final Map<T, String> segments;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: _textDim, size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: KinrelColors.darkElevated,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: segments.entries.map((entry) {
                      final isSelected = entry.key == value;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => onChanged(entry.key),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            decoration: BoxDecoration(
                              color: isSelected ? _orange : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              entry.value,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 12,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color:
                                    isSelected ? Colors.white : _textDim,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
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

class _SettingsFontScaleRow extends StatelessWidget {
  const _SettingsFontScaleRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  static const _sizes = [0.85, 1.0, 1.15];
  static const _labels = ['Small', 'Medium', 'Large'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: _textDim, size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: KinrelColors.darkElevated,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: List.generate(_sizes.length, (i) {
                      final isSelected = (value - _sizes[i]).abs() < 0.05;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => onChanged(_sizes[i]),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            decoration: BoxDecoration(
                              color:
                                  isSelected ? _orange : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _labels[i],
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 12,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color:
                                    isSelected ? Colors.white : _textDim,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
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

class _SettingsDeleteRow extends StatelessWidget {
  const _SettingsDeleteRow({
    required this.label,
    this.onTap,
  });

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              const Icon(Icons.delete_forever_outlined,
                  color: KinrelColors.error, size: 20),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: KinrelColors.error,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: _chevronColor,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

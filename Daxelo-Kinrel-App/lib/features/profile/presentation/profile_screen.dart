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

// ── Design Tokens ──────────────────────────────────────────────────
const Color _bg = Color(0xFF131416);
const Color _cardBg = Color(0xFF191B2C);
const Color _orange = Color(0xFFE8612A);
const Color _textPrimary = Color(0xFFF5F0EE);
const Color _textSecondary = Color(0xFFC9B4A8);
const Color _textDim = Color(0xFF8A7A72);
const Color _chevronColor = Color(0xFF8A7A72);
const Color _borderSubtle = Color(0x0FFFFFFF); // rgba(255,255,255,0.06)

class ProfileScreen extends ConsumerStatefulWidget {
  ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late TextEditingController _bioController;
  bool _isEditingBio = false;

  @override
  void initState() {
    super.initState();
    _bioController = TextEditingController(
      text: 'Building my family tree, one relationship at a time.',
    );
  }

  @override
  void dispose() {
    _bioController.dispose();
    super.dispose();
  }

  // ── Toggle Providers ───────────────────────────────────────────
  final _pushNotifProvider = StateProvider<bool>((ref) => true);
  final _birthdayRemindersProvider = StateProvider<bool>((ref) => true);
  final _anniversaryRemindersProvider = StateProvider<bool>((ref) => false);
  final _familyActivityProvider = StateProvider<bool>((ref) => true);
  final _twoFactorProvider = StateProvider<bool>((ref) => false);
  final _biometricLockProvider = StateProvider<bool>((ref) => false);

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final themeMode = ref.watch(themeModeProvider);
    final fontScale = ref.watch(fontScaleProvider);

    return DKScaffold(
      backgroundColor: _bg,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.base,
          vertical: KinrelSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),

            // ── Header Section ────────────────────────────────────
            _buildHeader(user),
            const SizedBox(height: 24),

            // ── Stats Cards ───────────────────────────────────────
            _buildStatsRow(),
            const SizedBox(height: 28),

            // ── Account ───────────────────────────────────────────
            _buildSectionHeader('Account'),
            const SizedBox(height: 8),
            _buildSectionCard([
              _SettingsRow(
                icon: Icons.person_outline,
                label: 'Profile details',
                subtitle: 'Name, email, phone, DOB',
                onTap: () {},
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

            // ── Appearance ────────────────────────────────────────
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
                onTap: () {},
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

            // ── Notifications ─────────────────────────────────────
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

            // ── Privacy & Security ────────────────────────────────
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

            // ── Family Management ─────────────────────────────────
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

            // ── Support ───────────────────────────────────────────
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

            // ── About ─────────────────────────────────────────────
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

            // ── Footer ────────────────────────────────────────────
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
            const SizedBox(height: 8),

            // ── Sign Out ──────────────────────────────────────────
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

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────

  Widget _buildHeader(user) {
    final displayName = user?.userMetadata?['name'] as String? ??
        user?.email?.split('@').first ??
        'Not signed in';
    final email = user?.email ?? '';
    final phone = user?.phone ?? '';

    return Column(
      children: [
        // Avatar with orange ring + camera overlay
        GestureDetector(
          onTap: () {
            // TODO: Avatar edit
          },
          child: SizedBox(
            width: 100,
            height: 100,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Orange ring
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _orange, width: 3),
                  ),
                  child: ClipOval(
                    child: Container(
                      color: KinrelColors.darkElevated,
                      child: Center(
                        child: Text(
                          displayName.isNotEmpty
                              ? displayName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            fontFamily: KinrelTypography.displayFont,
                            fontSize: 36,
                            fontWeight: FontWeight.w700,
                            color: _textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Camera icon overlay
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: _orange,
                      shape: BoxShape.circle,
                      border: Border.all(color: _bg, width: 2),
                    ),
                    child: const Icon(
                      Icons.camera_alt,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        )
            .animate(onPlay: (c) => c.forward())
            .fadeIn(duration: 500.ms)
            .scale(
              begin: const Offset(0.8, 0.8),
              end: const Offset(1.0, 1.0),
              duration: 400.ms,
              curve: Curves.easeOutBack,
            ),

        const SizedBox(height: 14),

        // Name — Display Small
        Text(
          displayName,
          style: const TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
            letterSpacing: 0.5,
          ),
        ),

        const SizedBox(height: 4),

        // Email / phone — Body Small
        if (email.isNotEmpty)
          Text(
            email,
            style: const TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              color: _textSecondary,
            ),
          ),
        if (phone.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            phone,
            style: const TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              color: _textSecondary,
            ),
          ),
        ],

        const SizedBox(height: 10),

        // Bio — editable, max 200 chars
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _isEditingBio
              ? TextField(
                  controller: _bioController,
                  maxLength: 200,
                  maxLines: 2,
                  autofocus: true,
                  style: const TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    color: _textDim,
                  ),
                  decoration: InputDecoration(
                    counterStyle: const TextStyle(
                      color: _textDim,
                      fontSize: 10,
                    ),
                    filled: true,
                    fillColor: _cardBg,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          const BorderSide(color: _orange, width: 1.5),
                    ),
                  ),
                  onSubmitted: (_) {
                    setState(() => _isEditingBio = false);
                  },
                )
              : GestureDetector(
                  onTap: () => setState(() => _isEditingBio = true),
                  child: Text(
                    _bioController.text.isEmpty
                        ? 'Tap to add a bio...'
                        : _bioController.text,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      color: _bioController.text.isEmpty
                          ? _textDim.withValues(alpha: 0.6)
                          : _textDim,
                    ),
                  ),
                ),
        ),

        const SizedBox(height: 16),

        // "Edit Profile" button — Outlined, orange border, orange text
        SizedBox(
          height: 38,
          child: OutlinedButton(
            onPressed: () {
              // TODO: Navigate to edit profile
            },
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: _orange, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 28),
            ),
            child: const Text(
              'Edit Profile',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _orange,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Stats Row ─────────────────────────────────────────────────────

  Widget _buildStatsRow() {
    return SizedBox(
      height: 90,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _StatCard(
            icon: Icons.park_outlined,
            value: '3',
            label: 'Family Trees',
          ),
          const SizedBox(width: 10),
          _StatCard(
            icon: Icons.person_outline,
            value: '47',
            label: 'Members Added',
          ),
          const SizedBox(width: 10),
          _StatCard(
            icon: Icons.link_outlined,
            value: '62',
            label: 'Relationships Linked',
          ),
          const SizedBox(width: 10),
          _StatCard(
            icon: Icons.public_outlined,
            value: '2',
            label: 'Languages: Hindi, Tamil',
          ),
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
// Stat Card
// ═══════════════════════════════════════════════════════════════════════

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _orange, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 11,
              color: _textDim,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Settings Row (chevron)
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

// ═══════════════════════════════════════════════════════════════════════
// Settings Toggle Row
// ═══════════════════════════════════════════════════════════════════════

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

// ═══════════════════════════════════════════════════════════════════════
// Settings Segmented Row
// ═══════════════════════════════════════════════════════════════════════

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
                            padding: const EdgeInsets.symmetric(
                              vertical: 7,
                            ),
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
                                color: isSelected
                                    ? Colors.white
                                    : _textDim,
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

// ═══════════════════════════════════════════════════════════════════════
// Settings Font Scale Row
// ═══════════════════════════════════════════════════════════════════════

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

// ═══════════════════════════════════════════════════════════════════════
// Settings Delete Row (red text, no icon)
// ═══════════════════════════════════════════════════════════════════════

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

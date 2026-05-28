// lib/features/profile/presentation/profile_screen.dart
//
// DAXELO KINREL — Profile Screen (Full Rewrite)
//
// Complete profile/settings screen with all functional items:
// avatar upload, stats, account settings, appearance, notifications,
// privacy & security, family management, support, and about sections.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:local_auth/local_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:hive/hive.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/theme/theme_provider.dart' show themeModeProvider, fontScaleProvider, localeProvider;
import '../../../core/services/supabase_service.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../shared/widgets/dk_components.dart';
import '../data/profile_provider.dart';
import '../../../core/utils/share_helper.dart';
import '../../core/utils/device_tier.dart';
import '../../../presentation/widgets/skeletons/profile_skeleton.dart';

// ── Design Tokens ──────────────────────────────────────────────────
const Color _bg = Color(0xFF131416);
const Color _cardBg = Color(0xFF191B2C);
const Color _orange = Color(0xFFE8612A);
const Color _textPrimary = Color(0xFFF5F0EE);
const Color _textSecondary = Color(0xFFC9B4A8);
const Color _textDim = Color(0xFF8A7A72);
const Color _chevronColor = Color(0xFF8A7A72);
const Color _borderSubtle = Color(0x0FFFFFFF); // rgba(255,255,255,0.06)

// ── Language Options ───────────────────────────────────────────────
const Map<String, String> _languageOptions = {
  'hi': 'Hindi',
  'bn': 'Bengali',
  'te': 'Telugu',
  'mr': 'Marathi',
  'ta': 'Tamil',
  'gu': 'Gujarati',
  'pa': 'Punjabi',
  'ml': 'Malayalam',
  'kn': 'Kannada',
  'or': 'Odia',
  'as': 'Assamese',
  'sd': 'Sindhi',
  'ur': 'Urdu',
  'en': 'English',
};

class ProfileScreen extends ConsumerStatefulWidget {
  ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen>
    with AutomaticKeepAliveClientMixin {
  bool _isUploadingAvatar = false;
  String? _appVersion;
  String? _buildInfo;
  bool _dataExportRequested = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    // Load profile & stats (fire-and-forget, provider handles state)
    unawaited(ref.read(profileProvider.notifier).loadProfile());
    unawaited(ref.read(profileProvider.notifier).loadStats());
    unawaited(ref.read(profileProvider.notifier).loadInvitations());

    // Load app version
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _appVersion = '${info.version} (${info.buildNumber})';
        _buildInfo =
            'v${info.version} build ${info.buildNumber}\n'
            '${info.appName} — ${info.packageName}';
      });
    }
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
    super.build(context); // Required by AutomaticKeepAliveClientMixin
    final user = ref.watch(currentUserProvider);
    final profile = ref.watch(profileProvider.select((s) => s.profile));
    final themeMode = ref.watch(themeModeProvider);
    final fontScale = ref.watch(fontScaleProvider);

    // Sync 2FA toggle with profile state
    if (profile != null &&
        profile.twoFactorEnabled != ref.read(_twoFactorProvider)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(_twoFactorProvider.notifier).state =
              profile.twoFactorEnabled;
        }
      });
    }

    // Load biometric lock from secure storage
    _loadBiometricState();

    // Show skeleton while profile is loading
    final isProfileLoading = user == null && profile == null;

    return DKScaffold(
      backgroundColor: _bg,
      body: isProfileLoading
          ? const ProfileSkeleton()
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: KinrelSpacing.base,
                vertical: KinrelSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),

                  // ── Header Section ────────────────────────────────────
                  _buildHeader(user, profile),
                  const SizedBox(height: 24),

                  // ── Stats Cards ───────────────────────────────────────
                  _buildStatsRow(ref.watch(profileStatsProvider)),
                  const SizedBox(height: 28),

            // ── Account ───────────────────────────────────────────
            _buildSectionHeader('Account'),
            const SizedBox(height: 8),
            _buildSectionCard([
              _SettingsRow(
                icon: Icons.person_outline,
                label: 'Profile details',
                subtitle: 'Name, email, phone, DOB',
                onTap: () => context.push('/profile/edit'),
              ),
              _divider(),
              _SettingsRow(
                icon: Icons.lock_outline,
                label: 'Change password',
                onTap: () => context.push('/profile/change-password'),
              ),
              _divider(),
              _SettingsRow(
                icon: Icons.link_outlined,
                label: 'Linked accounts',
                subtitle: 'Google',
                onTap: () => context.push('/profile/linked-accounts'),
              ),
              _divider(),
              _SettingsRow(
                icon: Icons.language_outlined,
                label: 'Preferred language',
                subtitle:
                    _languageOptions[profile?.preferredLanguage ?? 'en'] ??
                    'English',
                onTap: () => _showLanguageSheet(
                  context,
                  profile?.preferredLanguage ?? 'en',
                ),
              ),
              _divider(),
              _SettingsRow(
                icon: Icons.shield_outlined,
                label: 'Two-factor authentication',
                subtitle: profile?.twoFactorEnabled == true
                    ? 'Enabled'
                    : 'Disabled',
                onTap: () => context.push('/profile/2fa-setup'),
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
                subtitle:
                    _languageOptions[profile?.preferredLanguage ?? 'en'] ??
                    'English',
                onTap: () => _showLanguageSheet(
                  context,
                  profile?.preferredLanguage ?? 'en',
                ),
              ),
              _divider(),
              _SettingsFontScaleRow(
                icon: Icons.text_fields,
                label: 'Text size',
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
                onChanged: (v) => _persistToggle('push_notifications', v),
              ),
              _divider(),
              _SettingsToggleRow(
                icon: Icons.cake_outlined,
                label: 'Birthday reminders',
                provider: _birthdayRemindersProvider,
                onChanged: (v) => _persistToggle('birthday_reminders', v),
              ),
              _divider(),
              _SettingsToggleRow(
                icon: Icons.favorite_outline,
                label: 'Anniversary reminders',
                provider: _anniversaryRemindersProvider,
                onChanged: (v) => _persistToggle('anniversary_reminders', v),
              ),
              _divider(),
              _SettingsToggleRow(
                icon: Icons.group_outlined,
                label: 'Family activity',
                provider: _familyActivityProvider,
                onChanged: (v) => _persistToggle('family_activity', v),
              ),
              _divider(),
              _SettingsRow(
                icon: Icons.bedtime_outlined,
                label: 'Quiet hours',
                onTap: () => context.push('/profile/quiet-hours'),
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
                subtitle: _capitalize(profile?.profileVisibility ?? 'public'),
                onTap: () => _showVisibilitySheet(
                  context,
                  profile?.profileVisibility ?? 'public',
                ),
              ),
              _divider(),
              _SettingsRow(
                icon: Icons.person_add_outlined,
                label: 'Who can invite me',
                subtitle: _invitePermissionLabel(
                  profile?.invitePermission ?? 'anyone',
                ),
                onTap: () => _showInvitePermissionSheet(
                  context,
                  profile?.invitePermission ?? 'anyone',
                ),
              ),
              _divider(),
              _SettingsToggleRow(
                icon: Icons.fingerprint,
                label: 'Biometric lock',
                provider: _biometricLockProvider,
                onChanged: (value) => _onBiometricToggle(value),
              ),
              _divider(),
              _SettingsRow(
                icon: Icons.devices_outlined,
                label: 'Active sessions',
                onTap: () => context.push('/profile/sessions'),
              ),
              _divider(),
              _SettingsRow(
                icon: Icons.download_outlined,
                label: 'Download my data',
                subtitle: _dataExportRequested ? 'Request pending' : null,
                onTap: () => _showDataExportSheet(context),
              ),
              _divider(),
              _SettingsDeleteRow(
                label: 'Delete my account',
                onTap: () => context.push('/profile/delete-account'),
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
                onTap: () => context.push('/profile/my-families'),
              ),
              _divider(),
              _SettingsRow(
                icon: Icons.mail_outline,
                label: 'Pending invitations',
                badge: ref.watch(pendingInvitationCountProvider),
                onTap: () => context.push('/profile/invitations'),
              ),
              _divider(),
              _SettingsRow(
                icon: Icons.block_outlined,
                label: 'Blocked members',
                onTap: () => context.push('/profile/blocked'),
              ),
              _divider(),
              _SettingsRow(
                icon: Icons.upload_file_outlined,
                label: 'Export family tree',
                onTap: () => _showExportFamilyTreeSheet(context),
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
                onTap: () => context.push('/profile/help'),
              ),
              _divider(),
              _SettingsRow(
                icon: Icons.support_agent,
                label: 'Contact support',
                onTap: () => context.push('/profile/contact-support'),
              ),
              _divider(),
              _SettingsRow(
                icon: Icons.bug_report_outlined,
                label: 'Report a bug',
                onTap: () => context.push('/profile/report-bug'),
              ),
              _divider(),
              _SettingsRow(
                icon: Icons.star_outline,
                label: 'Rate the app',
                onTap: () => _rateApp(),
              ),
              _divider(),
              _SettingsRow(
                icon: Icons.share_outlined,
                label: 'Share Kinrel with friends',
                iconColor: _orange,
                labelColor: _orange,
                onTap: () => _shareApp(),
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
                trailing: Semantics(
                  button: true,
                  label: 'App version ${_appVersion ?? '1.0.0'}',
                  hint: 'Long press for build details',
                  child: GestureDetector(
                  onLongPress: () {
                    if (_buildInfo != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(_buildInfo!),
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 4),
                        ),
                      );
                    }
                  },
                  child: Text(
                    _appVersion ?? '1.0.0',
                    style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 13,
                      color: _textDim,
                    ),
                  ),
                ),
                ),
              ),
              _divider(),
              _SettingsRow(
                icon: Icons.description_outlined,
                label: 'Terms of service',
                onTap: () => context.push('/legal/terms'),
              ),
              _divider(),
              _SettingsRow(
                icon: Icons.privacy_tip_outlined,
                label: 'Privacy policy',
                onTap: () => context.push('/legal/privacy'),
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
                  onPressed: () => _showSignOutDialog(context),
                )
                .maybeAnimate(onPlay: (c) => c.forward())
                .fadeIn(duration: 500.ms, delay: 400.ms),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────

  Widget _buildHeader(user, ProfileModel? profile) {
    final displayName =
        profile?.name ??
        user?.userMetadata?['name'] as String? ??
        user?.email?.split('@').first ??
        'Not signed in';
    final email = profile?.email ?? user?.email ?? '';
    final avatarUrl = profile?.avatarUrl;
    final bio = profile?.bio ?? '';

    return Column(
      children: [
        // Avatar with orange ring + camera overlay
        Semantics(
            button: true,
            label: 'Change profile photo',
            hint: 'Double tap to change your profile photo',
            child: GestureDetector(
              onTap: _showAvatarSourceSheet,
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
                          child: _isUploadingAvatar
                              ? Center(
                                  child: SizedBox(
                                    width: 32,
                                    height: 32,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        _orange,
                                      ),
                                    ),
                                  ),
                                )
                              : (avatarUrl != null && avatarUrl.isNotEmpty)
                              ? CachedNetworkImage(
                                  imageUrl: avatarUrl,
                                  fit: BoxFit.cover,
                                  imageBuilder: (ctx, img) => Image(
                                    image: img,
                                    semanticLabel: '$displayName\'s photo',
                                  ),
                                  placeholder: (_, __) => Center(
                                    child: Text(
                                      displayName.isNotEmpty
                                          ? displayName[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                        fontFamily:
                                            KinrelTypography.displayFont,
                                        fontSize: 36,
                                        fontWeight: FontWeight.w700,
                                        color: _textPrimary,
                                      ),
                                    ),
                                  ),
                                  errorWidget: (_, __, ___) => Center(
                                    child: Text(
                                      displayName.isNotEmpty
                                          ? displayName[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                        fontFamily:
                                            KinrelTypography.displayFont,
                                        fontSize: 36,
                                        fontWeight: FontWeight.w700,
                                        color: _textPrimary,
                                      ),
                                    ),
                                  ),
                                )
                              : Center(
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
            ),
            )
            .maybeAnimate(onPlay: (c) => c.forward())
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

        // Email — display only, not tappable
        if (email.isNotEmpty)
          Text(
            email,
            style: const TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              color: _textSecondary,
            ),
          ),

        const SizedBox(height: 10),

        // Bio — tappable → navigates to /profile/edit with bio focused
        Semantics(
          button: true,
          label: bio.isEmpty ? 'Add a bio' : 'Edit bio',
          hint: 'Double tap to edit your bio',
          child: GestureDetector(
          onTap: () => context.push('/profile/edit?focus=bio'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              bio.isEmpty ? 'Tap to add a bio...' : bio,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                color: bio.isEmpty ? _textDim.withValues(alpha: 0.6) : _textDim,
              ),
            ),
          ),
        ),
        ),

        const SizedBox(height: 16),

        // "Edit Profile" button — Outlined, orange border, orange text
        SizedBox(
          height: 38,
          child: OutlinedButton(
            onPressed: () => context.push('/profile/edit'),
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

  Widget _buildStatsRow(UserStatsModel? stats) {
    final isLoading = stats == null;

    return SizedBox(
      height: 90,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _StatCard(
            icon: Icons.park_outlined,
            value: isLoading ? null : '${stats.familyTrees}',
            label: 'Family Trees',
            onTap: () => context.go('/families'),
          ),
          const SizedBox(width: 10),
          _StatCard(
            icon: Icons.person_outline,
            value: isLoading ? null : '${stats.membersAdded}',
            label: 'Members Added',
            onTap: () => context.push('/profile/members-added'),
          ),
          const SizedBox(width: 10),
          _StatCard(
            icon: Icons.link_outlined,
            value: isLoading ? null : '${stats.relations}',
            label: 'Relations',
            onTap: () => context.push('/profile/relations'),
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
    ).maybeAnimate(onPlay: (c) => c.forward()).fadeIn(duration: 300.ms);
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

  // ══════════════════════════════════════════════════════════════════
  // AVATAR HANDLING
  // ══════════════════════════════════════════════════════════════════

  void _showAvatarSourceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.bottomSheet),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _textDim.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Change Profile Photo',
              style: const TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: _orange),
              title: Text(
                'Take Photo',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 15,
                  color: _textPrimary,
                ),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: _orange),
              title: Text(
                'Choose from Gallery',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 15,
                  color: _textPrimary,
                ),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                _pickImage(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (picked == null) return;

      // Crop to square
      final cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        compressQuality: 85,
        maxWidth: 512,
        maxHeight: 512,
        uiSettings: [
          AndroidUiSettings(
            toolbarColor: _cardBg,
            toolbarWidgetColor: _textPrimary,
            activeControlsWidgetColor: _orange,
            backgroundColor: _bg,
            cropFrameColor: _orange,
            dimmedLayerColor: _bg.withValues(alpha: 0.7),
          ),
          IOSUiSettings(aspectRatioLockEnabled: true),
        ],
      );
      if (cropped == null) return;

      // Upload
      setState(() => _isUploadingAvatar = true);
      final success = await ref
          .read(profileProvider.notifier)
          .uploadAvatar(cropped.path);
      if (mounted) {
        setState(() => _isUploadingAvatar = false);
        if (!success) {
          context.showSnackBar(
            'Failed to upload photo, try again',
            isError: true,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingAvatar = false);
        context.showSnackBar(
          'Failed to upload photo, try again',
          isError: true,
        );
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // LANGUAGE BOTTOM SHEET
  // ══════════════════════════════════════════════════════════════════

  void _showLanguageSheet(BuildContext context, String currentLanguage) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.bottomSheet),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _textDim.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Select Language',
              style: const TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _languageOptions.entries.map((entry) {
                    final isSelected = entry.key == currentLanguage;
                    return ListTile(
                      leading: Icon(
                        isSelected
                            ? Icons.check_circle
                            : Icons.language_outlined,
                        color: isSelected ? _orange : _textDim,
                        size: isSelected ? 22 : 20,
                      ),
                      title: Text(
                        entry.value,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 15,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: isSelected ? _orange : _textPrimary,
                        ),
                      ),
                      trailing: isSelected
                          ? Icon(Icons.check, color: _orange, size: 20)
                          : null,
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _selectLanguage(entry.key);
                      },
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _selectLanguage(String code) async {
    // Save to Hive
    final box = await Hive.openBox('settings');
    await box.put('preferred_language', code);

    // Update locale provider for immediate UI update
    ref.read(localeProvider.notifier).state = Locale(code);

    // Call API (fire-and-forget)
    unawaited(
      ref.read(profileProvider.notifier).updateProfile({
        'preferredLanguage': code,
      }),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // BIOMETRIC LOCK
  // ══════════════════════════════════════════════════════════════════

  Future<void> _loadBiometricState() async {
    try {
      const storage = FlutterSecureStorage();
      final value = await storage.read(key: 'biometric_lock_enabled');
      final enabled = value == 'true';
      if (ref.read(_biometricLockProvider) != enabled) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(_biometricLockProvider.notifier).state = enabled;
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _onBiometricToggle(bool enabling) async {
    final localAuth = LocalAuthentication();

    // Check if device supports biometrics
    bool canAuthenticate = false;
    try {
      canAuthenticate =
          await localAuth.canCheckBiometrics ||
          await localAuth.isDeviceSupported();
    } catch (_) {
      canAuthenticate = false;
    }

    if (!canAuthenticate) {
      ref.read(_biometricLockProvider.notifier).state = false;
      if (mounted) {
        context.showSnackBar(
          'Biometric authentication not available on this device',
          isError: true,
        );
      }
      return;
    }

    if (enabling) {
      // Authenticate with biometric to enable
      try {
        final authenticated = await localAuth.authenticate(
          localizedReason: 'Authenticate to enable biometric lock',
          options: const AuthenticationOptions(
            stickyAuth: true,
            biometricOnly: true,
          ),
        );
        if (authenticated) {
          const storage = FlutterSecureStorage();
          await storage.write(key: 'biometric_lock_enabled', value: 'true');
          ref.read(_biometricLockProvider.notifier).state = true;
        } else {
          ref.read(_biometricLockProvider.notifier).state = false;
        }
      } catch (_) {
        ref.read(_biometricLockProvider.notifier).state = false;
        if (mounted) {
          context.showSnackBar(
            'Biometric authentication failed',
            isError: true,
          );
        }
      }
    } else {
      // Disable biometric lock
      const storage = FlutterSecureStorage();
      await storage.write(key: 'biometric_lock_enabled', value: 'false');
      ref.read(_biometricLockProvider.notifier).state = false;
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // NOTIFICATION TOGGLE PERSISTENCE
  // ══════════════════════════════════════════════════════════════════

  Future<void> _persistToggle(String key, bool value) async {
    try {
      final box = await Hive.openBox('settings');
      await box.put(key, value);
    } catch (_) {}
  }

  // ══════════════════════════════════════════════════════════════════
  // PROFILE VISIBILITY
  // ══════════════════════════════════════════════════════════════════

  void _showVisibilitySheet(BuildContext context, String current) {
    final options = ['public', 'private'];
    showModalBottomSheet(
      context: context,
      backgroundColor: _cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.bottomSheet),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _textDim.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Profile Visibility',
              style: const TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            ...options.map((option) {
              final isSelected = option == current;
              return ListTile(
                leading: Icon(
                  isSelected ? Icons.check_circle : Icons.visibility_outlined,
                  color: isSelected ? _orange : _textDim,
                  size: isSelected ? 22 : 20,
                ),
                title: Text(
                  _capitalize(option),
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 15,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? _orange : _textPrimary,
                  ),
                ),
                trailing: isSelected
                    ? Icon(Icons.check, color: _orange, size: 20)
                    : null,
                onTap: () {
                  Navigator.of(ctx).pop();
                  ref.read(profileProvider.notifier).updateProfile({
                    'profileVisibility': option,
                  });
                },
              );
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // INVITE PERMISSION
  // ══════════════════════════════════════════════════════════════════

  void _showInvitePermissionSheet(BuildContext context, String current) {
    final options = [
      ('anyone', 'Everyone'),
      ('people_i_know', 'Only people I know'),
      ('nobody', 'Nobody'),
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: _cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.bottomSheet),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _textDim.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Who Can Invite Me',
              style: const TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            ...options.map((opt) {
              final isSelected = opt.$1 == current;
              return ListTile(
                leading: Icon(
                  isSelected ? Icons.check_circle : Icons.person_add_outlined,
                  color: isSelected ? _orange : _textDim,
                  size: isSelected ? 22 : 20,
                ),
                title: Text(
                  opt.$2,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 15,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? _orange : _textPrimary,
                  ),
                ),
                trailing: isSelected
                    ? Icon(Icons.check, color: _orange, size: 20)
                    : null,
                onTap: () {
                  Navigator.of(ctx).pop();
                  ref.read(profileProvider.notifier).updateProfile({
                    'invitePermission': opt.$1,
                  });
                },
              );
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // DATA EXPORT
  // ══════════════════════════════════════════════════════════════════

  void _showDataExportSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.bottomSheet),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(KinrelSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _textDim.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Download Your Data',
                style: const TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'We\'ll prepare a file containing your profile information, '
                'family tree data, relationships, and activity history. '
                'You\'ll receive an email when it\'s ready to download.',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  color: _textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              if (_dataExportRequested)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Request pending — you\'ll be notified when ready',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 13,
                        color: _orange,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: DKButton(
                    label: 'Request Download',
                    variant: DKButtonVariant.primary,
                    size: DKButtonSize.lg,
                    onPressed: () async {
                      Navigator.of(ctx).pop();
                      final success = await ref
                          .read(profileProvider.notifier)
                          .requestDataExport();
                      if (!mounted || !context.mounted) return;
                      if (success) {
                        setState(() => _dataExportRequested = true);
                        context.showSnackBar('Data export requested');
                      } else {
                        context.showSnackBar(
                          'Failed to request data export',
                          isError: true,
                        );
                      }
                    },
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // EXPORT FAMILY TREE
  // ══════════════════════════════════════════════════════════════════

  void _showExportFamilyTreeSheet(BuildContext context) {
    String? selectedFamily;
    String selectedFormat = 'pdf';

    final families = ref.read(profileProvider).families;

    showModalBottomSheet(
      context: context,
      backgroundColor: _cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.bottomSheet),
        ),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(KinrelSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: _textDim.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Export Family Tree',
                    style: const TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Family selector
                  Text(
                    'Select family:',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      color: _textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: KinrelColors.darkElevated,
                      borderRadius: BorderRadius.circular(KinrelRadius.input),
                    ),
                    child: DropdownButton<String>(
                      value: selectedFamily,
                      hint: Text(
                        'Choose a family',
                        style: TextStyle(color: _textDim, fontSize: 14),
                      ),
                      isExpanded: true,
                      underline: const SizedBox.shrink(),
                      dropdownColor: KinrelColors.darkElevated,
                      items: families
                          .map(
                            (f) => DropdownMenuItem(
                              value: f.id,
                              child: Text(
                                f.name,
                                style: TextStyle(
                                  fontFamily: KinrelTypography.bodyFont,
                                  fontSize: 14,
                                  color: _textPrimary,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setModalState(() => selectedFamily = v),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Format selector
                  Text(
                    'Export format:',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      color: _textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _formatChip(
                        'PDF',
                        'pdf',
                        selectedFormat,
                        (f) => setModalState(() => selectedFormat = f),
                      ),
                      const SizedBox(width: 8),
                      _formatChip(
                        'JSON',
                        'json',
                        selectedFormat,
                        (f) => setModalState(() => selectedFormat = f),
                      ),
                      const SizedBox(width: 8),
                      _formatChip(
                        'CSV',
                        'csv',
                        selectedFormat,
                        (f) => setModalState(() => selectedFormat = f),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  DKButton(
                    label: 'Export',
                    variant: DKButtonVariant.primary,
                    size: DKButtonSize.lg,
                    fullWidth: true,
                    onPressed: selectedFamily == null
                        ? null
                        : () async {
                            Navigator.of(ctx).pop();
                            final success = await ref
                                .read(profileProvider.notifier)
                                .exportFamilyTree(
                                  selectedFamily!,
                                  selectedFormat,
                                );
                            if (!mounted || !context.mounted) return;
                            if (success) {
                              context.showSnackBar(
                                'Family tree export started',
                              );
                            } else {
                              context.showSnackBar(
                                'Failed to export family tree',
                                isError: true,
                              );
                            }
                          },
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _formatChip(
    String label,
    String value,
    String selected,
    ValueChanged<String> onTap,
  ) {
    final isSelected = value == selected;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? _orange : KinrelColors.darkElevated,
          borderRadius: BorderRadius.circular(KinrelRadius.sm),
          border: isSelected ? null : Border.all(color: _borderSubtle),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? Colors.white : _textDim,
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // RATE APP
  // ══════════════════════════════════════════════════════════════════

  Future<void> _rateApp() async {
    // Mark that user was asked to rate
    final box = await Hive.openBox('settings');
    await box.put('has_rated', true);

    // Try Play Store first, then App Store
    final Uri playStoreUri = Uri.parse(
      'https://play.google.com/store/apps/details?id=com.daxelo.kinrel',
    );
    final Uri appStoreUri = Uri.parse(
      'https://apps.apple.com/app/kinrel/id1234567890',
    );

    if (Platform.isAndroid) {
      if (await canLaunchUrl(playStoreUri)) {
        await launchUrl(playStoreUri, mode: LaunchMode.externalApplication);
      }
    } else if (Platform.isIOS) {
      if (await canLaunchUrl(appStoreUri)) {
        await launchUrl(appStoreUri, mode: LaunchMode.externalApplication);
      }
    } else {
      if (await canLaunchUrl(playStoreUri)) {
        await launchUrl(playStoreUri, mode: LaunchMode.externalApplication);
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // SHARE APP
  // ══════════════════════════════════════════════════════════════════

  void _shareApp() {
    ShareHelper.shareApp();
  }

  // ══════════════════════════════════════════════════════════════════
  // SIGN OUT
  // ══════════════════════════════════════════════════════════════════

  void _showSignOutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.dialog),
          side: const BorderSide(color: _borderSubtle),
        ),
        title: const Text(
          'Sign Out',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            color: _textPrimary,
          ),
        ),
        content: const Text(
          'Sign out of Daxelo Kinrel?',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 14,
            color: _textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: _textDim)),
          ),
          DKButton(
            label: 'Sign Out',
            variant: DKButtonVariant.gradient,
            gradient: KinrelGradients.signOutGradient,
            size: DKButtonSize.sm,
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                // P5-F1: Track logout event
                AnalyticsService.instance.logLogout();
                await ref.read(profileProvider.notifier).logout();
                if (context.mounted) context.go('/sign-in');
              } catch (e) {
                if (context.mounted) {
                  context.showSnackBar('Error signing out', isError: true);
                }
              }
            },
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // HELPERS
  // ══════════════════════════════════════════════════════════════════

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  String _invitePermissionLabel(String key) {
    switch (key) {
      case 'anyone':
        return 'Everyone';
      case 'people_i_know':
        return 'Only people I know';
      case 'nobody':
        return 'Nobody';
      default:
        return _capitalize(key);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Stat Card (with shimmer loading & tap)
// ═══════════════════════════════════════════════════════════════════════

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String? value; // null = loading
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
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
            if (value != null)
              Text(
                value!,
                style: const TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              )
            else
              DKLoadingShimmer(width: 48, height: 22, radius: 4),
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
    this.onChanged,
  });

  final IconData icon;
  final String label;
  final StateProvider<bool> provider;
  final ValueChanged<bool>? onChanged;

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
              onChanged: (v) {
                ref.read(provider.notifier).state = v;
                onChanged?.call(v);
              },
              activeThumbColor: Colors.white,
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
                                color: isSelected ? Colors.white : _textDim,
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
                      final isSelected = (value - _sizes[i]).abs() < 0.01;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => onChanged(_sizes[i]),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            decoration: BoxDecoration(
                              color: isSelected ? _orange : Colors.transparent,
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
                                color: isSelected ? Colors.white : _textDim,
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
// Settings Delete Row
// ═══════════════════════════════════════════════════════════════════════

class _SettingsDeleteRow extends StatelessWidget {
  const _SettingsDeleteRow({required this.label, this.onTap});

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
              const Icon(
                Icons.delete_outline,
                color: KinrelColors.error,
                size: 20,
              ),
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
              const Icon(Icons.chevron_right, color: _chevronColor, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

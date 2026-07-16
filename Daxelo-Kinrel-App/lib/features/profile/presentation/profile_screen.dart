// lib/features/profile/presentation/profile_screen.dart
//
// DAXELO KINREL — Profile Screen (Full Rewrite)
//
// Complete profile/settings screen with all functional items:
// avatar upload, stats, account settings, appearance, notifications,
// privacy & security, family management, support, and about sections.

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
// image_cropper removed — BUG-03: Reply already submitted crash on Android
import 'package:local_auth/local_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
// Hive removed — using shared_preferences for local settings
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/feature_flags.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/theme/theme_provider.dart'
    show themeModeProvider, fontScaleProvider, localeProvider;
import '../../../core/services/supabase_service.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../shared/widgets/dk_components.dart';
import '../data/profile_provider.dart';
import '../../../core/utils/share_helper.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/family/family_id_provider.dart';
import '../../../presentation/widgets/skeletons/profile_skeleton.dart';
import '../../family/providers/family_invite_provider.dart';
import '../../social/data/providers/follow_provider.dart';

import '../../social/presentation/widgets/sparq_ring_avatar.dart';
import '../../../core/services/image_cache_manager.dart';
import '../../trackc/presentation/screens/learning_profile_screen.dart';
import '../../family_map/helpers/location_permission_helper.dart';
import '../../family_map/providers/live_location_provider.dart';
import 'account_switcher_sheet.dart';
// P12.6 — Grandparent Mode accessibility profile
import '../../grandparent_mode/grandparent_mode_profile.dart';
// P12.7 — Kinrel Cameo fallback avatar
import '../../cameo/cameo.dart';

// ── Design Tokens ──────────────────────────────────────────────────
const Color _orange = Color(0xFFE8612A);

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

  // ── Theme-aware color getters (replace hardcoded dark consts) ──────
  Color get _bg => DKColors.background(context);
  Color get _cardBg => DKColors.cardColor(context);
  Color get _textPrimary => DKColors.textPrimary(context);
  Color get _textSecondary => DKColors.textSecondary(context);
  Color get _textDim => DKColors.isLight(context)
      ? const Color(0xFF6B7280)
      : const Color(0xFF8A7A72);
  Color get _borderSubtle => DKColors.borderColor(context);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // ✅ FIX (BUG-05): Defer provider modification until after first frame
    // to avoid "Tried to modify a provider while the widget tree was building"
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadInitialData();
      }
    });
  }

  Future<void> _loadInitialData() async {
    // Load profile & stats (fire-and-forget, provider handles state)
    unawaited(
      ref.read(profileProvider.notifier).loadProfile().catchError((_) {}),
    );
    unawaited(
      ref.read(profileProvider.notifier).loadStats().catchError((_) {}),
    );
    unawaited(
      ref.read(profileProvider.notifier).loadInvitations().catchError((_) {}),
    );

    // Auto-fetch KIN IDs for families that don't have one
    unawaited(_ensureFamilyIds());

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

  /// Auto-fetch KIN IDs for families that don't have one yet.
  /// Families created via Flutter may not have a kinFamilyId until
  /// the backend generates one on first access.
  Future<void> _ensureFamilyIds() async {
    final familiesAsync = ref.read(familyListProvider);
    final families = familiesAsync.valueOrNull ?? [];

    for (final family in families) {
      if (family.kinFamilyId == null || family.kinFamilyId!.isEmpty) {
        try {
          await ref.read(familyIdProvider.notifier).getFamilyId(family.id);
        } catch (e) {
          debugPrint('⚠️ Failed to fetch KIN ID for ${family.name}: $e');
        }
      }
    }
    // Invalidate to refresh with new KIN IDs
    ref.invalidate(familyListProvider);
  }

  // ── Toggle Providers ───────────────────────────────────────────
  final _pushNotifProvider = StateProvider<bool>((ref) => true);
  final _birthdayRemindersProvider = StateProvider<bool>((ref) => true);
  final _anniversaryRemindersProvider = StateProvider<bool>((ref) => false);
  final _familyActivityProvider = StateProvider<bool>((ref) => true);
  final _twoFactorProvider = StateProvider<bool>((ref) => false);
  final _biometricLockProvider = StateProvider<bool>((ref) => false);
  final _locationSharingProvider = StateProvider<bool>((ref) => false);

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
    // KIN-05 FIX: Load the four previously-unpersisted toggles from
    // secure storage, mirroring the _loadBiometricState pattern.
    _loadNotificationToggleStates();

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
                    // Multi-account switcher — prominent entry at the top
                    _SettingsRow(
                      icon: Icons.swap_horiz,
                      label: 'Switch Account',
                      subtitle: 'Add or switch between accounts',
                      iconColor: _orange,
                      labelColor: _orange,
                      onTap: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => const AccountSwitcherSheet(),
                        );
                      },
                    ),
                    _divider(),
                    if (kEnableProfileEditing) ...[
                      _SettingsRow(
                        icon: Icons.person_outline,
                        label: 'Profile details',
                        subtitle: 'Name, email, phone, DOB',
                        onTap: () => context.push('/profile/edit'),
                      ),
                      _divider(),
                    ],
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
                    // KIN-02 FIX: Removed duplicate "Preferred language" row.
                    // Both rows bound the same field (preferredLanguage) and
                    // opened the same sheet (_showLanguageSheet). Keeping only
                    // the Appearance-section "App language" row, relabelled
                    // to just "Language" per the audit recommendation.
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

                  // ── My Cameo (3D Character) — Standalone Section ────
                  _buildCameoSection(context, ref, profile, user),
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
                      label: 'Language',
                      subtitle:
                          _languageOptions[profile?.preferredLanguage ??
                              'en'] ??
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
                      onChanged: (v) =>
                          _persistToggle('anniversary_reminders', v),
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
                    _divider(),
                    ListTile(
                      leading: Icon(
                        Icons.celebration_outlined,
                        color: KinrelColors.orange,
                      ),
                      title: Text(
                        'Occasion Reminders',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          color: KinrelColors.textWhite,
                        ),
                      ),
                      subtitle: Text(
                        'Birthdays & anniversaries',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          color: KinrelColors.textDim,
                          fontSize: 12,
                        ),
                      ),
                      trailing: Icon(
                        Icons.chevron_right,
                        color: KinrelColors.textDim,
                      ),
                      onTap: () => context.push('/occasions'),
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
                      subtitle: _visibilityLabel(
                        profile?.profileVisibility ?? 'public',
                      ),
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
                    // Family Map — live location sharing toggle.
                    // Off by default. When enabled, requests GPS permission,
                    // gets one fix, and starts the broadcast loop on the map
                    // screen. Other family members see your pin move in
                    // near-real-time.
                    _SettingsToggleRow(
                      icon: Icons.location_on_outlined,
                      label: 'Share my location with family',
                      provider: _locationSharingProvider,
                      onChanged: (value) => _onLocationSharingToggle(value),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 50,
                        right: 16,
                        bottom: 8,
                      ),
                      child: Text(
                        'When on, family members see your pin on the Family Map in near-real-time. '
                        'Turn off anytime to stop sharing.',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 11,
                          color: DKColors.isLight(context)
                              ? const Color(0xFF9CA3AF)
                              : const Color(0xFF8A7A72),
                          height: 1.4,
                        ),
                      ),
                    ),
                    _divider(),
                    _SettingsRow(
                      icon: Icons.devices_outlined,
                      label: 'Active sessions',
                      subtitle: () {
                        final count = ref
                            .watch(profileProvider)
                            .sessions
                            .length;
                        return count > 0
                            ? '$count active ${count == 1 ? 'session' : 'sessions'}'
                            : null;
                      }(),
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
                    // Kinrel Learning profile — moved here from the Governance hub.
                    // Invisible infra that powers suggestions; needs a transparency/
                    // reset screen but doesn't belong in governance nav.
                    _SettingsRow(
                      icon: Icons.lightbulb_outline,
                      label: 'Kinrel Learning Profile',
                      subtitle: 'View what Kinrel has learned + reset',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const TrackcLearningProfileScreen(),
                        ),
                      ),
                    ),
                    _divider(),
                    // Silent Alarms — moved here from the Pulse hub.
                    // Passive background nudge system, not something you "go do."
                    _SettingsRow(
                      icon: Icons.notifications_off_outlined,
                      label: 'Silent Alarms',
                      subtitle: 'Private nudges when someone goes quiet',
                      onTap: () => context.push('/pulse/alarms'),
                    ),
                    _divider(),
                    // P12.6 — Pulse Learning Profile (ML engagement transparency)
                    _SettingsRow(
                      icon: Icons.insights_outlined,
                      label: 'Pulse Learning Profile',
                      subtitle:
                          'See what Kinrel has learned about your engagement',
                      onTap: () => context.push('/profile/pulse-learning'),
                    ),
                    _divider(),
                    // P12.6 — Community Discovery
                    _SettingsRow(
                      icon: Icons.groups_outlined,
                      label: 'Communities',
                      subtitle:
                          'Browse gotra, village, and surname communities',
                      onTap: () => context.push('/community'),
                    ),
                    _divider(),
                    // P12.6 — Your Family, Your Data (trust/privacy)
                    _SettingsRow(
                      icon: Icons.shield_outlined,
                      label: 'Your Family, Your Data',
                      subtitle: 'What we store, export, and delete',
                      onTap: () => context.push('/your-data'),
                    ),
                    _divider(),
                    // P12.6 — Grandparent Mode (accessibility profile)
                    Consumer(
                      builder: (context, ref, _) {
                        final gpMode = ref.watch(grandparentModeProvider);
                        return _SettingsRow(
                          icon: Icons.elderly_outlined,
                          label: 'Grandparent Mode',
                          subtitle: gpMode.enabled
                              ? 'On — larger text, simpler navigation'
                              : 'Larger text, simpler navigation, fewer options',
                          onTap: () => ref
                              .read(grandparentModeProvider.notifier)
                              .toggle(),
                        );
                      },
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
                      icon: Icons.qr_code_rounded,
                      label: 'Join Family by ID',
                      subtitle: 'Enter KIN-XXXXXXXX to join',
                      iconColor: _orange,
                      labelColor: _orange,
                      onTap: () => context.push('/join-family'),
                    ),
                    _divider(),
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

                  // ── My Family IDs ─────────────────────────────────────
                  _buildSectionHeader('My Family IDs'),
                  const SizedBox(height: 8),
                  _buildFamilyIdsSection(),
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
                      onTap: () => context.push('/terms'),
                    ),
                    _divider(),
                    _SettingsRow(
                      icon: Icons.privacy_tip_outlined,
                      label: 'Privacy policy',
                      onTap: () => context.push('/privacy'),
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
                      .animate(onPlay: (c) => c.forward())
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
        // Avatar with Sparq ring + camera overlay
        Semantics(
              button: true,
              label: 'View Sparqs or change profile photo',
              hint:
                  'Double tap to view Sparqs. Use camera icon to change photo.',
              child: SparqRingAvatar(
                userId: user?.id ?? profile?.id ?? '',
                avatarUrl: avatarUrl,
                radius: 47,
                onTap: () => context.push('/sparq/create'),
                child: SizedBox(
                  width: 94,
                  height: 94,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Avatar content (ring drawn by SparqRingAvatar)
                      ClipOval(
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
                                  cacheManager:
                                      KinrelImageCacheManager.instance,
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
                                      style: TextStyle(
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
                                      style: TextStyle(
                                        fontFamily:
                                            KinrelTypography.displayFont,
                                        fontSize: 36,
                                        fontWeight: FontWeight.w700,
                                        color: _textPrimary,
                                      ),
                                    ),
                                  ),
                                )
                              : kEnableCameoFallback
                              ? CameoAvatar(
                                  personName: displayName,
                                  ageBand: CameoAgeBand.adult,
                                  skinToneIndex: 5,
                                  surfaceId: 'profile_hero',
                                  isDeceased: false,
                                )
                              : Center(
                                  child: Text(
                                    displayName.isNotEmpty
                                        ? displayName[0].toUpperCase()
                                        : '?',
                                    style: TextStyle(
                                      fontFamily: KinrelTypography.displayFont,
                                      fontSize: 36,
                                      fontWeight: FontWeight.w700,
                                      color: _textPrimary,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                      // Camera icon overlay — separate tap for changing photo
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: GestureDetector(
                          onTap: _showAvatarSourceSheet,
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
                      ),
                    ],
                  ),
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

        const SizedBox(height: 12),

        // ── Follower / Following counts (Phase 7 social) ──────────────
        _buildFollowCountsRow(user?.id ?? profile?.id ?? ''),

        const SizedBox(height: 12),

        // Name — Display Small
        Text(
          displayName,
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
            letterSpacing: 0.5,
          ),
        ),

        // @username — Instagram style
        if (profile?.username != null && profile!.username!.isNotEmpty) ...[
          const SizedBox(height: 2),
          GestureDetector(
            onTap: () {
              // Copy username to clipboard
              final data = ClipboardData(text: '@${profile.username}');
              Clipboard.setData(data);
              context.showSnackBar('Username copied');
            },
            child: Text(
              '@${profile.username}',
              style: const TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: _orange,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ] else ...[
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => context.push('/profile/edit'),
            child: Text(
              'Set username',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                color: _orange.withValues(alpha: 0.7),
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],

        const SizedBox(height: 4),

        // Email — display only, not tappable
        if (email.isNotEmpty)
          Text(
            email,
            style: TextStyle(
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
                  color: bio.isEmpty
                      ? _textDim.withValues(alpha: 0.6)
                      : _textDim,
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

  // ── Follower / Following Counts Row (Phase 7 social) ────────────────

  Widget _buildFollowCountsRow(String userId) {
    if (userId.isEmpty) return const SizedBox.shrink();

    final countsAsync = ref.watch(followCountsProvider(userId));

    return countsAsync.when(
      data: (counts) {
        final followerCount = counts['followers'] ?? 0;
        final followingCount = counts['following'] ?? 0;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Followers
            GestureDetector(
              onTap: () => context.push('/followers/followers'),
              child: Column(
                children: [
                  Text(
                    '$followerCount',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Followers',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      color: _textSecondary,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: KinrelSpacing.xl),
            // Following
            GestureDetector(
              onTap: () => context.push('/followers/following'),
              child: Column(
                children: [
                  Text(
                    '$followingCount',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Following',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      color: _textSecondary,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
      loading: () => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Column(
            children: [
              SizedBox(
                width: 28,
                height: 14,
                child: LinearProgressIndicator(
                  backgroundColor: _borderSubtle,
                  valueColor: AlwaysStoppedAnimation<Color>(_orange),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Followers',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  color: _textSecondary,
                ),
              ),
            ],
          ),
          SizedBox(width: KinrelSpacing.xl),
          Column(
            children: [
              SizedBox(
                width: 28,
                height: 14,
                child: LinearProgressIndicator(
                  backgroundColor: _borderSubtle,
                  valueColor: AlwaysStoppedAnimation<Color>(_orange),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Following',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  color: _textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  // ── Stats Row ─────────────────────────────────────────────────────

  Widget _buildStatsRow(UserStatsModel? stats) {
    final isLoading = stats == null;

    return SizedBox(
      height: 110,
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
    ).animate(onPlay: (c) => c.forward()).fadeIn(duration: 300.ms);
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

  // ── My Cameo Section (Standalone) ─────────────────────────────────

  Widget _buildCameoSection(BuildContext context, WidgetRef ref, ProfileModel? profile, dynamic user) {
    final displayName =
        profile?.name ??
        user?.userMetadata?['name'] as String? ??
        user?.email?.split('@').first ??
        'User';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('My Cameo'),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _orange.withValues(alpha: 0.12),
                _orange.withValues(alpha: 0.04),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _orange.withValues(alpha: 0.3),
            ),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => context.push('/b1-verify'),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    // ── Cameo Avatar Preview ──
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            _orange.withValues(alpha: 0.2),
                            _orange.withValues(alpha: 0.05),
                          ],
                        ),
                        border: Border.all(
                          color: _orange.withValues(alpha: 0.4),
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: kEnableCameoFallback
                            ? SizedBox(
                                width: 56,
                                height: 56,
                                child: CameoAvatar(
                                  personName: displayName,
                                  ageBand: CameoAgeBand.adult,
                                  skinToneIndex: 5,
                                  surfaceId: 'profile_hero',
                                  isDeceased: false,
                                ),
                              )
                            : Icon(
                                Icons.face_retouching_natural,
                                color: _orange,
                                size: 32,
                              ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // ── Text Content ──
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'My Cameo',
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: _textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Your 3D Kinrel character — customize appearance, outfits & expressions',
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 13,
                              color: _textSecondary,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // ── Chevron ──
                    Icon(
                      Icons.chevron_right_rounded,
                      color: _orange,
                      size: 24,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // ── Cameo Diagnostics Row ──
        _buildSectionCard([
          _SettingsRow(
            icon: Icons.science_outlined,
            label: 'Cameo Diagnostics',
            subtitle: 'B1 gate verification + morph target test',
            onTap: () => context.push('/b1-verify'),
          ),
        ]),
      ],
    );
  }

  // ── Family IDs Section ────────────────────────────────────────────

  Widget _buildFamilyIdsSection() {
    final familiesAsync = ref.watch(familyListProvider);

    return familiesAsync.when(
      data: (families) {
        if (families.isEmpty) {
          return _buildSectionCard([
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(
                    Icons.family_restroom_outlined,
                    size: 32,
                    color: _textDim,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No families yet',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      color: _textDim,
                    ),
                  ),
                ],
              ),
            ),
          ]);
        }

        return _buildSectionCard(
          families.map((family) {
            final kinId = family.kinFamilyId;
            return _FamilyIdRow(
              familyName: family.name,
              kinFamilyId: kinId,
              familyId: family.id,
              onCopy: kinId != null
                  ? () {
                      Clipboard.setData(ClipboardData(text: kinId));
                      context.showSnackBar('Family ID copied');
                      ref
                          .read(familyInviteProvider.notifier)
                          .trackInviteSent(
                            familyId: family.id,
                            channel: 'direct',
                          );
                    }
                  : null,
              onQR: (kinId != null && kEnableQrJoin)
                  ? () => context.push(
                      '/family-qr?familyId=${family.id}&familyName=${Uri.encodeComponent(family.name)}&kinFamilyId=$kinId',
                    )
                  : null,
              onShare: kinId != null
                  ? () => ref
                        .read(familyInviteProvider.notifier)
                        .shareInviteLink(kinId, familyName: family.name)
                  : null,
            );
          }).toList(),
        );
      },
      loading: () => _buildSectionCard([
        Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(_orange),
              ),
            ),
          ),
        ),
      ]),
      error: (_, __) => _buildSectionCard([
        Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'Could not load families',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              color: _textDim,
            ),
          ),
        ),
      ]),
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
              style: TextStyle(
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
      // ✅ FIX (BUG-03): Removed image_cropper — uses image_picker with
      // built-in resize instead. image_cropper v8.x crashes on some Android
      // devices with "Reply already submitted" in onActivityResult.
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (picked == null) return;

      // Upload
      setState(() => _isUploadingAvatar = true);
      final success = await ref
          .read(profileProvider.notifier)
          .uploadAvatar(picked.path);
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
              style: TextStyle(
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('preferred_language', code);

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

  // ══════════════════════════════════════════════════════════════════
  // NOTIFICATION TOGGLE PERSISTENCE (KIN-05 FIX)
  // ══════════════════════════════════════════════════════════════════

  static const _kPushNotifKey = 'push_notif_enabled';
  static const _kBirthdayRemindersKey = 'birthday_reminders_enabled';
  static const _kAnniversaryRemindersKey = 'anniversary_reminders_enabled';
  static const _kFamilyActivityKey = 'family_activity_notif_enabled';

  Future<void> _loadNotificationToggleStates() async {
    try {
      const storage = FlutterSecureStorage();
      final results = await Future.wait([
        storage.read(key: _kPushNotifKey),
        storage.read(key: _kBirthdayRemindersKey),
        storage.read(key: _kAnniversaryRemindersKey),
        storage.read(key: _kFamilyActivityKey),
      ]);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(_pushNotifProvider.notifier).state = results[0] != 'false';
        ref.read(_birthdayRemindersProvider.notifier).state =
            results[1] != 'false';
        ref.read(_anniversaryRemindersProvider.notifier).state =
            results[2] == 'true';
        ref.read(_familyActivityProvider.notifier).state =
            results[3] != 'false';
      });
    } catch (_) {}
  }

  Future<void> _saveToggleState(String key, bool value) async {
    try {
      const storage = FlutterSecureStorage();
      await storage.write(key: key, value: value.toString());
    } catch (_) {}
  }

  // ── Location Sharing Toggle ────────────────────────────────────────
  //
  // When enabling: requests GPS permission, gets one fix, calls
  // liveLocationProvider.setSharing(sharing: true). The broadcast loop
  // starts automatically on the map screen when it detects isSharing=true.
  //
  // When disabling: calls setSharing(sharing: false). The broadcast loop
  // stops automatically. The MemberLocation row stays but isSharing=false,
  // so the pin disappears from other family members' maps.
  //
  // Never shows "sharing on" before permission is confirmed.
  Future<void> _onLocationSharingToggle(bool enabling) async {
    if (enabling) {
      // Request permission first — never enable sharing without it.
      final result = await requestLocationPermission();
      if (result != PermissionResult.granted) {
        // Permission denied — revert the toggle immediately.
        ref.read(_locationSharingProvider.notifier).state = false;
        if (result == PermissionResult.deniedForever) {
          // Open app settings so the user can grant manually.
          await openLocationSettings();
        } else if (result == PermissionResult.serviceDisabled) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Please enable location services in your device settings.',
                ),
              ),
            );
          }
        }
        return;
      }

      // Permission granted — get one GPS fix to seed the initial position.
      final pos = await getCurrentPosition();
      if (pos == null) {
        ref.read(_locationSharingProvider.notifier).state = false;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not get your location. Try again.'),
            ),
          );
        }
        return;
      }

      // Get the user's family + person ID for the MemberLocation row.
      final familyId = ref.read(familyListProvider).valueOrNull?.first.id ?? '';
      final members = ref.read(familyMembersProvider(familyId)).valueOrNull;
      final userId = ref.read(supabaseProvider)?.auth.currentUser?.id;
      if (familyId.isEmpty || members == null || userId == null) {
        ref.read(_locationSharingProvider.notifier).state = false;
        return;
      }
      final myPerson = members
          .where((p) => p.linkedUserId == userId)
          .firstOrNull;
      if (myPerson == null) {
        ref.read(_locationSharingProvider.notifier).state = false;
        return;
      }

      // Enable sharing in the provider — the map screen will detect
      // isSharing=true and start the broadcast loop automatically.
      await ref
          .read(liveLocationProvider.notifier)
          .setSharing(
            sharing: true,
            familyId: familyId,
            personId: myPerson.id,
            lat: pos.latitude,
            lng: pos.longitude,
          );
    } else {
      // Disabling sharing — cancel the broadcast + mark isSharing=false.
      final familyId = ref.read(familyListProvider).valueOrNull?.first.id ?? '';
      final members = ref.read(familyMembersProvider(familyId)).valueOrNull;
      final userId = ref.read(supabaseProvider)?.auth.currentUser?.id;
      if (familyId.isNotEmpty && members != null && userId != null) {
        final myPerson = members
            .where((p) => p.linkedUserId == userId)
            .firstOrNull;
        if (myPerson != null) {
          // Use the last known position to set isSharing=false.
          final lastPos = await getCurrentPosition();
          await ref
              .read(liveLocationProvider.notifier)
              .setSharing(
                sharing: false,
                familyId: familyId,
                personId: myPerson.id,
                lat: lastPos?.latitude ?? 0,
                lng: lastPos?.longitude ?? 0,
              );
        }
      }
    }
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
    // KIN-05 FIX: Previously wrote to SharedPreferences with a key
    // that _loadNotificationToggleStates didn't read back. Now writes
    // to FlutterSecureStorage using the same keys the load method
    // reads, mirroring the proven _biometricLockProvider pattern.
    final secureKey = switch (key) {
      'push_notifications' => _kPushNotifKey,
      'birthday_reminders' => _kBirthdayRemindersKey,
      'anniversary_reminders' => _kAnniversaryRemindersKey,
      'family_activity' => _kFamilyActivityKey,
      _ => key,
    };
    await _saveToggleState(secureKey, value);
    // Also keep the SharedPreferences write for backward compat
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {}
  }

  // ══════════════════════════════════════════════════════════════════
  // PROFILE VISIBILITY
  // ══════════════════════════════════════════════════════════════════

  void _showVisibilitySheet(BuildContext context, String current) {
    final options = [
      ('public', 'Public', 'Anyone can see your profile'),
      (
        'connections_only',
        'Connections Only',
        'Only your family connections can see your profile',
      ),
      ('private', 'Private', 'No one can see your profile'),
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
              'Profile Visibility',
              style: TextStyle(
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
                  isSelected ? Icons.check_circle : Icons.visibility_outlined,
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
                subtitle: Text(
                  opt.$3,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    color: _textDim,
                  ),
                ),
                trailing: isSelected
                    ? Icon(Icons.check, color: _orange, size: 20)
                    : null,
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final success = await ref
                      .read(profileProvider.notifier)
                      .updateProfile({'profileVisibility': opt.$1});
                  if (mounted) {
                    if (success) {
                      context.showSnackBar(
                        'Profile visibility updated to ${opt.$2}',
                      );
                    } else {
                      context.showSnackBar(
                        'Failed to update profile visibility',
                        isError: true,
                      );
                    }
                  }
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
      ('anyone', 'Everyone', 'Anyone can send you family invitations'),
      (
        'connections',
        'Connections Only',
        'Only your family connections can invite you',
      ),
      ('nobody', 'Nobody', 'No one can send you invitations'),
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
              style: TextStyle(
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
                subtitle: Text(
                  opt.$3,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    color: _textDim,
                  ),
                ),
                trailing: isSelected
                    ? Icon(Icons.check, color: _orange, size: 20)
                    : null,
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final success = await ref
                      .read(profileProvider.notifier)
                      .updateProfile({'invitePermission': opt.$1});
                  if (mounted) {
                    if (success) {
                      context.showSnackBar(
                        'Invite permission updated to ${opt.$2}',
                      );
                    } else {
                      context.showSnackBar(
                        'Failed to update invite permission',
                        isError: true,
                      );
                    }
                  }
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
                style: TextStyle(
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
                    style: TextStyle(
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_rated', true);

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
          side: BorderSide(color: _orange.withValues(alpha: 0.15)),
        ),
        title: Text(
          'Sign Out',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            color: _textPrimary,
          ),
        ),
        content: Text(
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
            child: Text('Cancel', style: TextStyle(color: _textDim)),
          ),
          DKButton(
            label: 'Sign Out',
            variant: DKButtonVariant.gradient,
            gradient: KinrelGradients.signOutGradient,
            size: DKButtonSize.sm,
            onPressed: () async {
              Navigator.of(ctx).pop();
              // Sign out from Supabase and clear local session state.
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

  String _visibilityLabel(String key) {
    switch (key) {
      case 'public':
        return 'Public';
      case 'connections_only':
        return 'Connections Only';
      case 'private':
        return 'Private';
      default:
        return _capitalize(key);
    }
  }

  String _invitePermissionLabel(String key) {
    switch (key) {
      case 'anyone':
        return 'Everyone';
      case 'connections':
        return 'Connections Only';
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
    final cardBg = DKColors.cardColor(context);
    final borderColor = DKColors.borderColor(context);
    final textPrimary = DKColors.textPrimary(context);
    final textDim = DKColors.isLight(context)
        ? const Color(0xFF6B7280)
        : const Color(0xFF8A7A72);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: _orange, size: 20),
            const SizedBox(height: 8),
            if (value != null)
              Text(
                value!,
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: textPrimary,
                ),
              )
            else
              DKLoadingShimmer(width: 48, height: 22, radius: 4),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 11,
                color: textDim,
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
    this.iconColor,
    this.labelColor,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final int? badge;
  final Color? iconColor;
  final Color? labelColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final effectiveIconColor =
        iconColor ??
        (DKColors.isLight(context)
            ? const Color(0xFF6B7280)
            : const Color(0xFF8A7A72));
    final effectiveLabelColor = labelColor ?? DKColors.textPrimary(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Icon(icon, color: effectiveIconColor, size: 20),
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
                              color: effectiveLabelColor,
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
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 12,
                          color: DKColors.isLight(context)
                              ? const Color(0xFF6B7280)
                              : const Color(0xFF8A7A72),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              trailing ??
                  Icon(
                    Icons.chevron_right,
                    color: DKColors.isLight(context)
                        ? const Color(0xFF9CA3AF)
                        : const Color(0xFF8A7A72),
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
          Icon(
            icon,
            color: DKColors.isLight(context)
                ? const Color(0xFF6B7280)
                : const Color(0xFF8A7A72),
            size: 20,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: DKColors.textPrimary(context),
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
          Icon(
            icon,
            color: DKColors.isLight(context)
                ? const Color(0xFF6B7280)
                : const Color(0xFF8A7A72),
            size: 20,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: DKColors.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: DKColors.elevatedColor(context),
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
                                color: isSelected
                                    ? Colors.white
                                    : (DKColors.isLight(context)
                                          ? const Color(0xFF6B7280)
                                          : const Color(0xFF8A7A72)),
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
          Icon(
            icon,
            color: DKColors.isLight(context)
                ? const Color(0xFF6B7280)
                : const Color(0xFF8A7A72),
            size: 20,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: DKColors.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: DKColors.elevatedColor(context),
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
                                color: isSelected
                                    ? Colors.white
                                    : (DKColors.isLight(context)
                                          ? const Color(0xFF6B7280)
                                          : const Color(0xFF8A7A72)),
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
              Icon(
                Icons.chevron_right,
                color: DKColors.isLight(context)
                    ? const Color(0xFF9CA3AF)
                    : const Color(0xFF8A7A72),
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
// Family ID Row Widget
// ═══════════════════════════════════════════════════════════════════════

class _FamilyIdRow extends StatelessWidget {
  const _FamilyIdRow({
    required this.familyName,
    this.kinFamilyId,
    required this.familyId,
    this.onCopy,
    this.onQR,
    this.onShare,
  });

  final String familyName;
  final String? kinFamilyId;
  final String familyId;
  final VoidCallback? onCopy;
  final VoidCallback? onQR;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final hasKinId = kinFamilyId != null && kinFamilyId!.isNotEmpty;

    return InkWell(
      onTap: hasKinId ? onCopy : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Family icon
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.family_restroom_rounded,
                size: 18,
                color: _orange,
              ),
            ),
            const SizedBox(width: 12),

            // Family name + ID
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    familyName,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: DKColors.textPrimary(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  if (hasKinId)
                    Text(
                      kinFamilyId!,
                      style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: _orange,
                        letterSpacing: 1,
                      ),
                    )
                  else
                    Text(
                      'No Family ID assigned',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        color: DKColors.isLight(context)
                            ? const Color(0xFF6B7280)
                            : const Color(0xFF8A7A72),
                      ),
                    ),
                ],
              ),
            ),

            // Action buttons
            if (hasKinId) ...[
              // QR code button
              SizedBox(
                width: 36,
                height: 36,
                child: IconButton(
                  icon: Icon(
                    Icons.qr_code_rounded,
                    color: DKColors.isLight(context)
                        ? const Color(0xFF6B7280)
                        : const Color(0xFF8A7A72),
                    size: 20,
                  ),
                  onPressed: onQR,
                  padding: EdgeInsets.zero,
                  tooltip: 'Show QR code',
                ),
              ),
              const SizedBox(width: 4),
              // Share button
              SizedBox(
                width: 36,
                height: 36,
                child: IconButton(
                  icon: Icon(
                    Icons.share_outlined,
                    color: DKColors.isLight(context)
                        ? const Color(0xFF6B7280)
                        : const Color(0xFF8A7A72),
                    size: 20,
                  ),
                  onPressed: onShare,
                  padding: EdgeInsets.zero,
                  tooltip: 'Share invite link',
                ),
              ),
            ] else ...[
              Icon(
                Icons.chevron_right,
                color: DKColors.isLight(context)
                    ? const Color(0xFF9CA3AF)
                    : const Color(0xFF8A7A72),
                size: 20,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

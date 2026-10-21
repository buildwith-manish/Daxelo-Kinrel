// lib/features/profile/presentation/settings/settings_category_screen.dart
//
// DAXELO KINREL — Settings category screen (Screen 3 in the redesign
// spec).
//
// Renders the existing rows for a given category. The rows are built
// from the same _SettingsRow / _SettingsToggleRow / _SettingsSegmentedRow
// / _SettingsFontScaleRow / _SettingsDeleteRow widgets that used to
// live inline in profile_screen.dart — they're now public and imported
// from settings_widgets.dart, so look + behavior are identical.
//
// The Privacy category starts with a Privacy checkup card.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/brand_spacing.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/constants/feature_flags.dart';
import '../../../../core/theme/theme_provider.dart'
    show themeModeProvider, fontScaleProvider;
import '../../../../shared/widgets/dk_components.dart';
import '../../../grandparent_mode/grandparent_mode_profile.dart';
import '../../../trackc/presentation/screens/learning_profile_screen.dart';
import '../../data/profile_provider.dart';
import 'settings_actions.dart';
import 'settings_providers.dart';
import 'settings_widgets.dart';

class SettingsCategoryScreen extends ConsumerWidget {
  const SettingsCategoryScreen({super.key, required this.categoryId});
  final String categoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cat = SettingsCategory.fromId(categoryId);
    final bg = DKColors.background(context);
    final textPrimary = DKColors.textPrimary(context);
    final borderSubtle = DKColors.borderColor(context);

    // Trigger the one-shot settings bootstrap when any category screen
    // opens (idempotent — if already loaded, this is a no-op).
    ref.watch(settingsBootstrapProvider);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(
              context,
              title: cat.title,
              textPrimary: textPrimary,
              borderSubtle: borderSubtle,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  KinrelSpacing.base,
                  8,
                  KinrelSpacing.base,
                  32,
                ),
                children: _buildSections(context, ref, cat),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context, {
    required String title,
    required Color textPrimary,
    required Color borderSubtle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderSubtle)),
      ),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Back',
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/profile/settings');
                }
              },
              child: const SizedBox(
                width: 48,
                height: 48,
                child: Icon(Icons.arrow_back, size: 22),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSections(
    BuildContext context,
    WidgetRef ref,
    SettingsCategory cat,
  ) {
    switch (cat) {
      case SettingsCategory.account:
        return _buildAccount(context, ref);
      case SettingsCategory.privacy:
        return _buildPrivacy(context, ref);
      case SettingsCategory.notifications:
        return _buildNotifications(context, ref);
      case SettingsCategory.look:
        return _buildLook(context, ref);
      case SettingsCategory.familyData:
        return _buildFamilyData(context, ref);
      case SettingsCategory.help:
        return _buildHelp(context, ref);
    }
  }

  // ─────────────────────────────────────────────────────────────────
  //  Account & security
  // ─────────────────────────────────────────────────────────────────

  List<Widget> _buildAccount(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).profile;
    final sessions = ref.watch(profileProvider).sessions;
    final sessionCount = sessions.length;
    final sessionSubtitle = sessionCount > 0
        ? '$sessionCount active ${sessionCount == 1 ? 'session' : 'sessions'}'
        : null;

    return [
      SettingsCard(
        children: [
          if (kEnableProfileEditing) ...[
            SettingsRow(
              icon: Icons.person_outline,
              label: 'Profile details',
              subtitle: 'Name, username, DOB, bio, gender',
              onTap: () => context.push('/profile/edit'),
            ),
            const SettingsDivider(),
            SettingsRow(
              icon: Icons.shield_outlined,
              label: 'Account Information',
              subtitle: 'Email, phone, security',
              onTap: () => context.push('/profile/account'),
            ),
            const SettingsDivider(),
          ],
          SettingsRow(
            icon: Icons.lock_outline,
            label: 'Change password',
            onTap: () => context.push('/profile/change-password'),
          ),
          const SettingsDivider(),
          SettingsRow(
            icon: Icons.link_outlined,
            label: 'Linked accounts',
            subtitle: 'Google',
            onTap: () => context.push('/profile/linked-accounts'),
          ),
          const SettingsDivider(),
          SettingsRow(
            icon: Icons.shield_outlined,
            label: 'Two-factor authentication',
            subtitle: profile?.twoFactorEnabled == true ? 'Enabled' : 'Disabled',
            onTap: () => context.push('/profile/2fa-setup'),
          ),
          const SettingsDivider(),
          SettingsRow(
            icon: Icons.devices_outlined,
            label: 'Active sessions',
            subtitle: sessionSubtitle,
            onTap: () => context.push('/profile/sessions'),
          ),
        ],
      ),
      const SizedBox(height: 24),
      // Delete account — own group, danger styling, last in category.
      SettingsCard(
        children: [
          SettingsDeleteRow(
            label: 'Delete my account',
            onTap: () => context.push('/profile/delete-account'),
          ),
        ],
      ),
    ];
  }

  // ─────────────────────────────────────────────────────────────────
  //  Privacy
  // ─────────────────────────────────────────────────────────────────

  List<Widget> _buildPrivacy(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).profile;
    final visibility = profile?.profileVisibility ?? 'public';
    final invitePerm = profile?.invitePermission ?? 'anyone';
    final passed = ref.watch(privacyChecksPassedProvider);
    final cta = ref.watch(privacyCheckupCtaProvider);
    final passedCount = passed.length;

    return [
      _PrivacyCheckupCard(
        passedCount: passedCount,
        cta: cta,
        onTap: () => _runFirstFailingPrivacyCheck(context, ref, passed),
      ),
      const SizedBox(height: 16),
      const SettingsSectionLabel('Who can see me'),
      const SizedBox(height: 8),
      SettingsCard(
        children: [
          SettingsRow(
            icon: Icons.visibility_outlined,
            label: 'Profile visibility',
            subtitle: visibilityLabel(visibility),
            onTap: () => showVisibilitySheet(context, ref, visibility),
          ),
          const SettingsDivider(),
          SettingsRow(
            icon: Icons.person_add_outlined,
            label: 'Who can invite me',
            subtitle: invitePermissionLabel(invitePerm),
            onTap: () => showInvitePermissionSheet(context, ref, invitePerm),
          ),
          const SettingsDivider(),
          SettingsToggleRow(
            icon: Icons.location_on_outlined,
            label: 'Share my location with family',
            provider: locationSharingToggleProvider,
            onChanged: (v) => onLocationSharingToggle(context, ref, v),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 50, right: 16, bottom: 8),
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
        ],
      ),
      const SizedBox(height: 24),
      const SettingsSectionLabel('On this phone'),
      const SizedBox(height: 8),
      SettingsCard(
        children: [
          SettingsToggleRow(
            icon: Icons.fingerprint,
            label: 'Biometric lock',
            provider: biometricLockToggleProvider,
            onChanged: (value) => onBiometricToggle(context, ref, value),
          ),
          const SettingsDivider(),
          SettingsRow(
            icon: Icons.devices_outlined,
            label: 'Active sessions',
            subtitle: () {
              final count = ref.watch(profileProvider).sessions.length;
              return count > 0
                  ? '$count active ${count == 1 ? 'session' : 'sessions'}'
                  : null;
            }(),
            onTap: () => context.push('/profile/sessions'),
          ),
        ],
      ),
      const SizedBox(height: 24),
      const SettingsSectionLabel('Your data'),
      const SizedBox(height: 8),
      SettingsCard(
        children: [
          SettingsRow(
            icon: Icons.shield_outlined,
            label: 'Your Family, Your Data',
            subtitle: 'What we store, export, and delete',
            onTap: () => context.push('/your-data'),
          ),
          const SettingsDivider(),
          SettingsRow(
            icon: Icons.block_outlined,
            label: 'Blocked members',
            onTap: () => context.push('/profile/blocked'),
          ),
        ],
      ),
    ];
  }

  void _runFirstFailingPrivacyCheck(
    BuildContext context,
    WidgetRef ref,
    Set<PrivacyCheck> passed,
  ) {
    if (!passed.contains(PrivacyCheck.biometric)) {
      // Toggle biometric on (runs auth flow + persists)
      onBiometricToggle(context, ref, true);
      return;
    }
    if (!passed.contains(PrivacyCheck.twoFactor)) {
      context.push('/profile/2fa-setup');
      return;
    }
    if (!passed.contains(PrivacyCheck.locationOff)) {
      ref.read(locationSharingToggleProvider.notifier).state = false;
      return;
    }
    if (!passed.contains(PrivacyCheck.visibilityNotPublic)) {
      final profile = ref.read(profileProvider).profile;
      showVisibilitySheet(context, ref, profile?.profileVisibility ?? 'public');
      return;
    }
  }

  // ─────────────────────────────────────────────────────────────────
  //  Notifications
  // ─────────────────────────────────────────────────────────────────

  List<Widget> _buildNotifications(BuildContext context, WidgetRef ref) {
    final quietSummary = ref.watch(quietHoursSummaryProvider).maybeWhen(
          data: (s) => s,
          orElse: () => 'Off',
        );

    return [
      const SettingsSectionLabel('Reminders'),
      const SizedBox(height: 8),
      SettingsCard(
        children: [
          SettingsToggleRow(
            icon: Icons.notifications_outlined,
            label: 'Push notifications',
            provider: pushNotificationsToggleProvider,
            onChanged: (v) => persistToggle(ref, 'push_notifications', v),
          ),
          const SettingsDivider(),
          SettingsToggleRow(
            icon: Icons.cake_outlined,
            label: 'Birthday reminders',
            provider: birthdayRemindersToggleProvider,
            onChanged: (v) => persistToggle(ref, 'birthday_reminders', v),
          ),
          const SettingsDivider(),
          SettingsToggleRow(
            icon: Icons.favorite_outline,
            label: 'Anniversary reminders',
            provider: anniversaryRemindersToggleProvider,
            onChanged: (v) =>
                persistToggle(ref, 'anniversary_reminders', v),
          ),
          const SettingsDivider(),
          SettingsToggleRow(
            icon: Icons.group_outlined,
            label: 'Family activity',
            provider: familyActivityToggleProvider,
            onChanged: (v) => persistToggle(ref, 'family_activity', v),
          ),
        ],
      ),
      const SizedBox(height: 24),
      const SettingsSectionLabel('Schedule & quiet'),
      const SizedBox(height: 8),
      SettingsCard(
        children: [
          SettingsRow(
            icon: Icons.bedtime_outlined,
            label: 'Quiet hours',
            subtitle: quietSummary,
            onTap: () async {
              unawaited(context.push('/profile/quiet-hours'));
              // Refresh the summary when the user returns.
              ref.invalidate(quietHoursSummaryProvider);
            },
          ),
          const SettingsDivider(),
          SettingsRow(
            icon: Icons.celebration_outlined,
            label: 'Manage occasions',
            subtitle: 'Birthdays & anniversaries',
            onTap: () => context.push('/occasions'),
          ),
          const SettingsDivider(),
          SettingsRow(
            icon: Icons.notifications_off_outlined,
            label: 'Silent Alarms',
            subtitle: 'Private nudges when someone goes quiet',
            onTap: () => context.push('/pulse/alarms'),
          ),
        ],
      ),
    ];
  }

  // ─────────────────────────────────────────────────────────────────
  //  Look & language
  // ─────────────────────────────────────────────────────────────────

  List<Widget> _buildLook(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final fontScale = ref.watch(fontScaleProvider);
    final profile = ref.watch(profileProvider).profile;
    final langCode = profile?.preferredLanguage ?? 'en';

    return [
      const SettingsSectionLabel('My Cameo'),
      const SizedBox(height: 8),
      _buildCameoSection(context, profile),
      const SizedBox(height: 24),
      const SettingsSectionLabel('Appearance'),
      const SizedBox(height: 8),
      SettingsCard(
        children: [
          SettingsSegmentedRow<ThemeMode>(
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
          const SettingsDivider(),
          SettingsRow(
            icon: Icons.translate_outlined,
            label: 'Language',
            subtitle: kLanguageEnglishNames[langCode] ?? 'English',
            onTap: () => showLanguageSheet(context, ref, langCode),
          ),
          const SettingsDivider(),
          SettingsFontScaleRow(
            icon: Icons.text_fields,
            label: 'Text size',
            value: fontScale,
            onChanged: (v) =>
                ref.read(fontScaleProvider.notifier).state = v,
          ),
          const SettingsDivider(),
          SettingsRow(
            icon: Icons.wallpaper_rounded,
            label: 'Chat Wallpaper',
            onTap: () => context.push('/settings/wallpaper'),
          ),
        ],
      ),
      const SizedBox(height: 24),
      const SettingsSectionLabel('Accessibility'),
      const SizedBox(height: 8),
      SettingsCard(
        children: [
          Consumer(
            builder: (context, ref, _) {
              final gpMode = ref.watch(grandparentModeProvider);
              return SettingsRow(
                icon: Icons.elderly_outlined,
                label: 'Easy Mode (Grandparent Mode)',
                subtitle: gpMode.enabled
                    ? 'On — larger text, simpler navigation'
                    : 'Larger text, simpler navigation, fewer options',
                onTap: () =>
                    ref.read(grandparentModeProvider.notifier).toggle(),
              );
            },
          ),
        ],
      ),
    ];
  }

  // ── My Cameo block (moved here from old Me screen) ──────────────────

  Widget _buildCameoSection(BuildContext context, ProfileModel? profile) {
    // The full cameo block was implemented in the old profile_screen's
    // _buildCameoSection. Keeping it lazy: most users don't open this
    // category often. Renders a smaller tile here.
    final textSecondary = DKColors.textSecondary(context);
    return SettingsCard(
      children: [
        SettingsRow(
          icon: Icons.face_retouching_natural,
          label: 'My Cameo',
          subtitle: 'View your 3D Kinrel character',
          onTap: () => context.push('/b1-verify'),
        ),
        const SettingsDivider(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.face_retouching_natural,
                  color: kSettingsOrange.withValues(alpha: 0.6), size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Tap to view your 3D Kinrel character',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12.5,
                    color: textSecondary,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────
  //  Family & my data
  // ─────────────────────────────────────────────────────────────────

  List<Widget> _buildFamilyData(BuildContext context, WidgetRef ref) {
    final pendingCount = ref.watch(pendingInvitationCountProvider);
    return [
      const SettingsSectionLabel('Families'),
      const SizedBox(height: 8),
      SettingsCard(
        children: [
          SettingsRow(
            icon: Icons.qr_code_rounded,
            label: 'Join Family by ID',
            subtitle: 'Enter KIN-XXXXXXXX to join',
            iconColor: kSettingsOrange,
            labelColor: kSettingsOrange,
            onTap: () => context.push('/join-family'),
          ),
          const SettingsDivider(),
          SettingsRow(
            icon: Icons.account_tree_outlined,
            label: 'My family trees',
            onTap: () => context.push('/profile/my-families'),
          ),
          const SettingsDivider(),
          SettingsRow(
            icon: Icons.mail_outline,
            label: 'Pending invitations',
            badge: pendingCount,
            onTap: () => context.push('/profile/invitations'),
          ),
          const SettingsDivider(),
          SettingsRow(
            icon: Icons.block_outlined,
            label: 'Blocked members',
            onTap: () => context.push('/profile/blocked'),
          ),
          const SettingsDivider(),
          SettingsRow(
            icon: Icons.upload_file_outlined,
            label: 'Export family tree',
            onTap: () => showExportFamilyTreeSheet(context, ref),
          ),
        ],
      ),
      const SizedBox(height: 24),
      const SettingsSectionLabel('My data'),
      const SizedBox(height: 8),
      SettingsCard(
        children: [
          Consumer(
            builder: (context, ref, _) {
              final requested = ref.watch(dataExportRequestedProvider);
              return SettingsRow(
                icon: Icons.download_outlined,
                label: 'Download my data',
                subtitle: requested ? 'Request pending' : null,
                onTap: () => showDataExportSheet(context, ref),
              );
            },
          ),
          const SettingsDivider(),
          SettingsRow(
            icon: Icons.shield_outlined,
            label: 'Your Family, Your Data',
            subtitle: 'What we store, export, and delete',
            onTap: () => context.push('/your-data'),
          ),
        ],
      ),
      const SizedBox(height: 24),
      const SettingsSectionLabel('What Kinrel has learned'),
      const SizedBox(height: 8),
      SettingsCard(
        children: [
          SettingsRow(
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
          const SettingsDivider(),
          SettingsRow(
            icon: Icons.insights_outlined,
            label: 'Pulse Learning Profile',
            subtitle: 'See what Kinrel has learned about your engagement',
            onTap: () => context.push('/profile/pulse-learning'),
          ),
          const SettingsDivider(),
          // Communities row gated on AppConfig.enableCommunity — when the
          // flag is off, the row (and its divider) disappear from the
          // Family & my data section. The /community route itself also
          // redirects away, so removing this row doesn't strand a deep
          // link: any stale /community URL hits the redirect in
          // app_router.dart and bounces to '/' instead of opening a
          // hidden screen.
          if (AppConfig.enableCommunity) ...[
            const SettingsDivider(),
            SettingsRow(
              icon: Icons.groups_outlined,
              label: 'Communities',
              subtitle: 'Browse gotra, village, and surname communities',
              onTap: () => context.push('/community'),
            ),
          ],
        ],
      ),
    ];
  }

  // ─────────────────────────────────────────────────────────────────
  //  Help & about
  // ─────────────────────────────────────────────────────────────────

  List<Widget> _buildHelp(BuildContext context, WidgetRef ref) {
    return [
      const SettingsSectionLabel('Support'),
      const SizedBox(height: 8),
      SettingsCard(
        children: [
          SettingsRow(
            icon: Icons.help_outline,
            label: 'Help center / FAQ',
            onTap: () => context.push('/profile/help'),
          ),
          const SettingsDivider(),
          SettingsRow(
            icon: Icons.support_agent,
            label: 'Contact support',
            onTap: () => context.push('/profile/contact-support'),
          ),
          const SettingsDivider(),
          SettingsRow(
            icon: Icons.bug_report_outlined,
            label: 'Report a bug',
            onTap: () => context.push('/profile/report-bug'),
          ),
          const SettingsDivider(),
          SettingsRow(
            icon: Icons.star_outline,
            label: 'Rate the app',
            onTap: () => unawaited(rateApp()),
          ),
          const SettingsDivider(),
          SettingsRow(
            icon: Icons.share_outlined,
            label: 'Share Kinrel with friends',
            iconColor: kSettingsOrange,
            labelColor: kSettingsOrange,
            onTap: () => shareApp(),
          ),
        ],
      ),
      const SizedBox(height: 24),
      const SettingsSectionLabel('About'),
      const SizedBox(height: 8),
      SettingsCard(
        children: [
          SettingsRow(
            icon: Icons.info_outline,
            label: 'App version',
            onTap: () async {
              final v = await loadAppVersionInfo();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(v.buildInfo),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 4),
                ),
              );
            },
          ),
          const SettingsDivider(),
          SettingsRow(
            icon: Icons.description_outlined,
            label: 'Terms of service',
            onTap: () => context.push('/terms'),
          ),
          const SettingsDivider(),
          SettingsRow(
            icon: Icons.privacy_tip_outlined,
            label: 'Privacy policy',
            onTap: () => context.push('/privacy'),
          ),
        ],
      ),
    ];
  }
}

// ──────────────────────────────────────────────────────────────────────
//  Privacy checkup card
// ──────────────────────────────────────────────────────────────────────

class _PrivacyCheckupCard extends StatelessWidget {
  const _PrivacyCheckupCard({
    required this.passedCount,
    required this.cta,
    required this.onTap,
  });

  final int passedCount;
  final String cta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final success = const Color(0xFF4CAF7A);
    final allPass = passedCount == 4;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: success.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: success.withValues(alpha: 0.30)),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // 48px badge with n/4 and a ring
            SizedBox(
              width: 48,
              height: 48,
              child: Stack(
                children: [
                  CircularProgressIndicator(
                    value: passedCount / 4,
                    strokeWidth: 4,
                    color: success,
                    backgroundColor:
                        success.withValues(alpha: 0.2),
                  ),
                  Center(
                    child: Text(
                      '$passedCount/4',
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: success,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Privacy checkup',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: success,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    allPass
                        ? 'All set. Your family tree is well protected.'
                        : cta,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12.5,
                      color: DKColors.isLight(context)
                          ? const Color(0xFF4A5568)
                          : const Color(0xFFE5E7EB),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

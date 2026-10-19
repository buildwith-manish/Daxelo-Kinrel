// lib/features/profile/presentation/settings/settings_actions.dart
//
// DAXELO KINREL — Settings actions (extracted from profile_screen.dart).
//
// These handlers + bottom sheets were private methods of
// _ProfileScreenState. They are now top-level functions taking
// (BuildContext, WidgetRef) so the new Settings hub + category screens
// can call them without inheriting from ProfileScreen.
//
// Behavior is identical to the originals:
//   • same Supabase / Dio calls
//   • same SharedPreferences + FlutterSecureStorage keys
//   • same analytics events
//   • same permission flows
//   • same SnackBar / Dialog strings
//
// The "Download my data" sheet's "Request pending" state now reads
// from [dataExportRequestedProvider] (top-level StateProvider) instead
// of the old local _dataExportRequested field, so a Settings screen
// can render the sheet and the state survives a screen rebuild.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:local_auth/local_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_spacing.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/family/family_provider.dart';
import '../../../../core/utils/share_helper.dart';
import '../../../../shared/widgets/dk_components.dart';
import '../../../family_map/helpers/location_permission_helper.dart';
import '../../../family_map/providers/live_location_provider.dart';
import '../../data/profile_provider.dart';
import '../../../../core/theme/theme_provider.dart'
    show localeProvider;
import 'settings_providers.dart';
import 'settings_widgets.dart' show kSettingsOrange;

// ──────────────────────────────────────────────────────────────────────
//  Constants — UI strings gathered at the top so l10n can be added later
// ──────────────────────────────────────────────────────────────────────

const String kSettingsLabelBiometricNotAvailable =
    'Biometric authentication not available on this device';
const String kSettingsLabelBiometricFailed =
    'Biometric authentication failed';
const String kSettingsLabelBiometricReasonEnable =
    'Authenticate to enable biometric lock';
const String kSettingsLabelLocationDisabled =
    'Please enable location services in your device settings.';
const String kSettingsLabelLocationFailed =
    'Could not get your location. Try again.';
const String kSettingsLabelVisibilityUpdated =
    'Profile visibility updated';
const String kSettingsLabelVisibilityFailed =
    'Failed to update profile visibility';
const String kSettingsLabelInviteUpdated =
    'Invite permission updated';
const String kSettingsLabelInviteFailed =
    'Failed to update invite permission';
const String kSettingsLabelDataExportRequested = 'Data export requested';
const String kSettingsLabelDataExportFailed =
    'Failed to request data export';
const String kSettingsLabelTreeExportStarted = 'Family tree export started';
const String kSettingsLabelTreeExportFailed =
    'Failed to export family tree';
const String kSettingsLabelSignOutTitle = 'Sign Out';
const String kSettingsLabelSignOutPrompt = 'Sign out of Daxelo Kinrel?';

// ──────────────────────────────────────────────────────────────────────
//  Toggle persistence
// ──────────────────────────────────────────────────────────────────────

/// Writes a notification-toggle value to FlutterSecureStorage using the
/// same key mapping as the old `_persistToggle` method, plus a mirror
/// write to SharedPreferences for backward compat.
///
/// Callers: SettingsToggleRow.onChanged callbacks in Notifications
/// category. Same behavior — no logic change.
Future<void> persistToggle(WidgetRef ref, String key, bool value) async {
  final secureKey = switch (key) {
    'push_notifications' => kSecureKeyPushNotif,
    'birthday_reminders' => kSecureKeyBirthdayReminders,
    'anniversary_reminders' => kSecureKeyAnniversaryReminders,
    'family_activity' => kSecureKeyFamilyActivity,
    _ => key,
  };
  await saveToggleState(secureKey, value);
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  } catch (_) {}
}

/// Mirrors the old `_saveToggleState` (FlutterSecureStorage write).
Future<void> saveToggleState(String key, bool value) async {
  try {
    const storage = FlutterSecureStorage();
    await storage.write(key: key, value: value.toString());
  } catch (_) {}
}

// ──────────────────────────────────────────────────────────────────────
//  Language sheet
// ──────────────────────────────────────────────────────────────────────

/// Opens the bottom sheet that lets the user pick their preferred
/// language. Mirrors `_showLanguageSheet` exactly — same items, same
/// selected state styling, same `_selectLanguage` write flow.
void showLanguageSheet(BuildContext context, WidgetRef ref, String currentLanguage) {
  final cardBg = DKColors.cardColor(context);
  final textPrimary = DKColors.textPrimary(context);
  final textDim = DKColors.isLight(context)
      ? const Color(0xFF6B7280)
      : const Color(0xFF8A7A72);

  showModalBottomSheet(
    context: context,
    backgroundColor: cardBg,
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
              color: textDim.withValues(alpha: 0.3),
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
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: kLanguageEnglishNames.entries.map((entry) {
                  final isSelected = entry.key == currentLanguage;
                  return ListTile(
                    leading: Icon(
                      isSelected ? Icons.check_circle : Icons.language_outlined,
                      color: isSelected ? kSettingsOrange : textDim,
                      size: isSelected ? 22 : 20,
                    ),
                    title: Text(
                      entry.value,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 15,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w400,
                        color: isSelected ? kSettingsOrange : textPrimary,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check, color: kSettingsOrange, size: 20)
                        : null,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      selectLanguage(ref, entry.key);
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

/// Mirrors `_selectLanguage`: persists to SharedPreferences (key
/// 'preferred_language'), updates the localeProvider immediately, and
/// fire-and-forgets the API update via profileProvider.updateProfile.
Future<void> selectLanguage(WidgetRef ref, String code) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('preferred_language', code);
  ref.read(localeProvider.notifier).state = Locale(code);
  unawaited(
    ref.read(profileProvider.notifier).updateProfile({
      'preferredLanguage': code,
    }),
  );
}

// ──────────────────────────────────────────────────────────────────────
//  Biometric lock toggle
// ──────────────────────────────────────────────────────────────────────

/// Mirrors `_onBiometricToggle`. Same LocalAuthentication flow, same
/// secure-storage write ('biometric_lock_enabled' key), same SnackBar
/// messages. State writes go to the top-level [biometricLockToggleProvider].
Future<void> onBiometricToggle(
  BuildContext context,
  WidgetRef ref,
  bool enabling,
) async {
  final localAuth = LocalAuthentication();
  bool canAuthenticate = false;
  try {
    canAuthenticate = await localAuth.canCheckBiometrics ||
        await localAuth.isDeviceSupported();
  } catch (_) {
    canAuthenticate = false;
  }

  if (!canAuthenticate) {
    ref.read(biometricLockToggleProvider.notifier).state = false;
    if (context.mounted) {
      context.showSnackBar(
        kSettingsLabelBiometricNotAvailable,
        isError: true,
      );
    }
    return;
  }

  if (enabling) {
    try {
      final authenticated = await localAuth.authenticate(
        localizedReason: kSettingsLabelBiometricReasonEnable,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
      if (authenticated) {
        const storage = FlutterSecureStorage();
        await storage.write(key: kSecureKeyBiometricLock, value: 'true');
        ref.read(biometricLockToggleProvider.notifier).state = true;
      } else {
        ref.read(biometricLockToggleProvider.notifier).state = false;
      }
    } catch (_) {
      ref.read(biometricLockToggleProvider.notifier).state = false;
      if (context.mounted) {
        context.showSnackBar(kSettingsLabelBiometricFailed, isError: true);
      }
    }
  } else {
    const storage = FlutterSecureStorage();
    await storage.write(key: kSecureKeyBiometricLock, value: 'false');
    ref.read(biometricLockToggleProvider.notifier).state = false;
  }
}

// ──────────────────────────────────────────────────────────────────────
//  Location sharing toggle
// ──────────────────────────────────────────────────────────────────────

/// Mirrors `_onLocationSharingToggle`. Same permission flow, same GPS
/// fix seeding, same broadcast loop wiring (setSharing). State writes
/// go to the top-level [locationSharingToggleProvider].
Future<void> onLocationSharingToggle(
  BuildContext context,
  WidgetRef ref,
  bool enabling,
) async {
  if (enabling) {
    final result = await requestLocationPermission();
    if (result != PermissionResult.granted) {
      ref.read(locationSharingToggleProvider.notifier).state = false;
      if (result == PermissionResult.deniedForever) {
        await openLocationSettings();
      } else if (result == PermissionResult.serviceDisabled) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(kSettingsLabelLocationDisabled),
            ),
          );
        }
      }
      return;
    }

    final pos = await getCurrentPosition();
    if (pos == null) {
      ref.read(locationSharingToggleProvider.notifier).state = false;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(kSettingsLabelLocationFailed)),
        );
      }
      return;
    }

    final familyId =
        ref.read(familyListProvider).valueOrNull?.first.id ?? '';
    final members = ref.read(familyMembersProvider(familyId)).valueOrNull;
    final userId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    if (familyId.isEmpty || members == null || userId == null) {
      ref.read(locationSharingToggleProvider.notifier).state = false;
      return;
    }
    final myPerson =
        members.where((p) => p.linkedUserId == userId).firstOrNull;
    if (myPerson == null) {
      ref.read(locationSharingToggleProvider.notifier).state = false;
      return;
    }

    await ref.read(liveLocationProvider.notifier).setSharing(
          sharing: true,
          familyId: familyId,
          personId: myPerson.id,
          lat: pos.latitude,
          lng: pos.longitude,
        );
  } else {
    final familyId =
        ref.read(familyListProvider).valueOrNull?.first.id ?? '';
    final members = ref.read(familyMembersProvider(familyId)).valueOrNull;
    final userId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    if (familyId.isNotEmpty && members != null && userId != null) {
      final myPerson =
          members.where((p) => p.linkedUserId == userId).firstOrNull;
      if (myPerson != null) {
        final lastPos = await getCurrentPosition();
        await ref.read(liveLocationProvider.notifier).setSharing(
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

// ──────────────────────────────────────────────────────────────────────
//  Visibility sheet
// ──────────────────────────────────────────────────────────────────────

void showVisibilitySheet(BuildContext context, WidgetRef ref, String current) {
  final cardBg = DKColors.cardColor(context);
  final textPrimary = DKColors.textPrimary(context);
  final textDim = DKColors.isLight(context)
      ? const Color(0xFF6B7280)
      : const Color(0xFF8A7A72);

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
    backgroundColor: cardBg,
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
              color: textDim.withValues(alpha: 0.3),
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
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          ...options.map((opt) {
            final isSelected = opt.$1 == current;
            return ListTile(
              leading: Icon(
                isSelected ? Icons.check_circle : Icons.visibility_outlined,
                color: isSelected ? kSettingsOrange : textDim,
                size: isSelected ? 22 : 20,
              ),
              title: Text(
                opt.$2,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? kSettingsOrange : textPrimary,
                ),
              ),
              subtitle: Text(
                opt.$3,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  color: textDim,
                ),
              ),
              trailing: isSelected
                  ? const Icon(Icons.check, color: kSettingsOrange, size: 20)
                  : null,
              onTap: () async {
                Navigator.of(ctx).pop();
                final success = await ref
                    .read(profileProvider.notifier)
                    .updateProfile({'profileVisibility': opt.$1});
                if (!context.mounted) return;
                if (success) {
                  context.showSnackBar(
                    '$kSettingsLabelVisibilityUpdated to ${opt.$2}',
                  );
                } else {
                  context.showSnackBar(
                    kSettingsLabelVisibilityFailed,
                    isError: true,
                  );
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

// ──────────────────────────────────────────────────────────────────────
//  Invite permission sheet
// ──────────────────────────────────────────────────────────────────────

void showInvitePermissionSheet(
  BuildContext context,
  WidgetRef ref,
  String current,
) {
  final cardBg = DKColors.cardColor(context);
  final textPrimary = DKColors.textPrimary(context);
  final textDim = DKColors.isLight(context)
      ? const Color(0xFF6B7280)
      : const Color(0xFF8A7A72);

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
    backgroundColor: cardBg,
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
              color: textDim.withValues(alpha: 0.3),
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
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          ...options.map((opt) {
            final isSelected = opt.$1 == current;
            return ListTile(
              leading: Icon(
                isSelected ? Icons.check_circle : Icons.person_add_outlined,
                color: isSelected ? kSettingsOrange : textDim,
                size: isSelected ? 22 : 20,
              ),
              title: Text(
                opt.$2,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? kSettingsOrange : textPrimary,
                ),
              ),
              subtitle: Text(
                opt.$3,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  color: textDim,
                ),
              ),
              trailing: isSelected
                  ? const Icon(Icons.check, color: kSettingsOrange, size: 20)
                  : null,
              onTap: () async {
                Navigator.of(ctx).pop();
                final success = await ref
                    .read(profileProvider.notifier)
                    .updateProfile({'invitePermission': opt.$1});
                if (!context.mounted) return;
                if (success) {
                  context.showSnackBar(
                    '$kSettingsLabelInviteUpdated to ${opt.$2}',
                  );
                } else {
                  context.showSnackBar(
                    kSettingsLabelInviteFailed,
                    isError: true,
                  );
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

// ──────────────────────────────────────────────────────────────────────
//  Data export sheet
// ──────────────────────────────────────────────────────────────────────

void showDataExportSheet(BuildContext context, WidgetRef ref) {
  final cardBg = DKColors.cardColor(context);
  final textPrimary = DKColors.textPrimary(context);
  final textSecondary = DKColors.textSecondary(context);

  showModalBottomSheet(
    context: context,
    backgroundColor: cardBg,
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
                  color: (DKColors.isLight(context)
                          ? const Color(0xFF6B7280)
                          : const Color(0xFF8A7A72))
                      .withValues(alpha: 0.3),
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
                color: textPrimary,
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
                color: textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            Consumer(
              builder: (context, ref, _) {
                final requested = ref.watch(dataExportRequestedProvider);
                if (requested) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Request pending — you\'ll be notified when ready',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 13,
                          color: kSettingsOrange,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  );
                }
                return SizedBox(
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
                      if (!context.mounted) return;
                      if (success) {
                        ref
                            .read(dataExportRequestedProvider.notifier)
                            .state = true;
                        context.showSnackBar(kSettingsLabelDataExportRequested);
                      } else {
                        context.showSnackBar(
                          kSettingsLabelDataExportFailed,
                          isError: true,
                        );
                      }
                    },
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}

// ──────────────────────────────────────────────────────────────────────
//  Export family tree sheet
// ──────────────────────────────────────────────────────────────────────

void showExportFamilyTreeSheet(BuildContext context, WidgetRef ref) {
  String? selectedFamily;
  String selectedFormat = 'pdf';

  final families = ref.read(profileProvider).families;
  final cardBg = DKColors.cardColor(context);
  final textPrimary = DKColors.textPrimary(context);
  final textSecondary = DKColors.textSecondary(context);
  final textDim = DKColors.isLight(context)
      ? const Color(0xFF6B7280)
      : const Color(0xFF8A7A72);

  showModalBottomSheet(
    context: context,
    backgroundColor: cardBg,
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
                      color: textDim.withValues(alpha: 0.3),
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
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Select family:',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    color: textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: DKColors.elevatedColor(context),
                    borderRadius: BorderRadius.circular(KinrelRadius.input),
                  ),
                  child: DropdownButton<String>(
                    value: selectedFamily,
                    hint: Text(
                      'Choose a family',
                      style: TextStyle(color: textDim, fontSize: 14),
                    ),
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    dropdownColor: DKColors.elevatedColor(context),
                    items: families
                        .map(
                          (f) => DropdownMenuItem(
                            value: f.id,
                            child: Text(
                              f.name,
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 14,
                                color: textPrimary,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setModalState(() => selectedFamily = v),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Export format:',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    color: textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _FormatChip(
                      label: 'PDF',
                      value: 'pdf',
                      selected: selectedFormat,
                      onTap: (f) => setModalState(() => selectedFormat = f),
                    ),
                    const SizedBox(width: 8),
                    _FormatChip(
                      label: 'JSON',
                      value: 'json',
                      selected: selectedFormat,
                      onTap: (f) => setModalState(() => selectedFormat = f),
                    ),
                    const SizedBox(width: 8),
                    _FormatChip(
                      label: 'CSV',
                      value: 'csv',
                      selected: selectedFormat,
                      onTap: (f) => setModalState(() => selectedFormat = f),
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
                          if (!context.mounted) return;
                          if (success) {
                            context.showSnackBar(kSettingsLabelTreeExportStarted);
                          } else {
                            context.showSnackBar(
                              kSettingsLabelTreeExportFailed,
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

class _FormatChip extends StatelessWidget {
  const _FormatChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final String value;
  final String selected;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final isSelected = value == selected;
    final borderSubtle = DKColors.borderColor(context);
    final textDim = DKColors.isLight(context)
        ? const Color(0xFF6B7280)
        : const Color(0xFF8A7A72);
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? kSettingsOrange : DKColors.elevatedColor(context),
          borderRadius: BorderRadius.circular(KinrelRadius.sm),
          border: isSelected ? null : Border.all(color: borderSubtle),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? Colors.white : textDim,
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
//  Rate app / Share app
// ──────────────────────────────────────────────────────────────────────

Future<void> rateApp() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('has_rated', true);

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

void shareApp() {
  ShareHelper.shareApp();
}

// ──────────────────────────────────────────────────────────────────────
//  Sign out
// ──────────────────────────────────────────────────────────────────────

void showSignOutDialog(BuildContext context, WidgetRef ref) {
  final cardBg = DKColors.cardColor(context);
  final textPrimary = DKColors.textPrimary(context);
  final textSecondary = DKColors.textSecondary(context);
  final textDim = DKColors.isLight(context)
      ? const Color(0xFF6B7280)
      : const Color(0xFF8A7A72);

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KinrelRadius.dialog),
        side: BorderSide(color: kSettingsOrange.withValues(alpha: 0.15)),
      ),
      title: Text(
        kSettingsLabelSignOutTitle,
        style: TextStyle(
          fontFamily: KinrelTypography.displayFont,
          color: textPrimary,
        ),
      ),
      content: Text(
        kSettingsLabelSignOutPrompt,
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 14,
          color: textSecondary,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text('Cancel', style: TextStyle(color: textDim)),
        ),
        DKButton(
          label: 'Sign Out',
          variant: DKButtonVariant.gradient,
          gradient: KinrelGradients.signOutGradient,
          size: DKButtonSize.sm,
          onPressed: () async {
            Navigator.of(ctx).pop();
            try {
              unawaited(AnalyticsService.instance.logLogout());
              await ref.read(profileProvider.notifier).logout();
            } catch (e) {
              debugPrint('Sign out error (non-blocking): $e');
            }
            if (context.mounted) {
              context.go('/sign-in');
            }
          },
        ),
      ],
    ),
  );
}

// ──────────────────────────────────────────────────────────────────────
//  Avatar source sheet + image picker (used by the Me screen)
//  ──────────────────────────────────────────────────────────────────────
//
//  These stay as helper functions because they need to set the
//  "isUploadingAvatar" state on the calling screen. The Me screen
//  passes a `setIsUploading` callback so it owns the local UI state.

void showAvatarSourceSheet(
  BuildContext context, {
  required VoidCallback onPickCamera,
  required VoidCallback onPickGallery,
}) {
  final cardBg = DKColors.cardColor(context);
  final textPrimary = DKColors.textPrimary(context);
  final textDim = DKColors.isLight(context)
      ? const Color(0xFF6B7280)
      : const Color(0xFF8A7A72);

  showModalBottomSheet(
    context: context,
    backgroundColor: cardBg,
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
              color: textDim.withValues(alpha: 0.3),
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
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 20),
          ListTile(
            leading: const Icon(Icons.camera_alt, color: kSettingsOrange),
            title: Text(
              'Take Photo',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 15,
                color: textPrimary,
              ),
            ),
            onTap: () {
              Navigator.of(ctx).pop();
              onPickCamera();
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library, color: kSettingsOrange),
            title: Text(
              'Choose from Gallery',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 15,
                color: textPrimary,
              ),
            ),
            onTap: () {
              Navigator.of(ctx).pop();
              onPickGallery();
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    ),
  );
}

Future<void> pickAndUploadAvatar(
  BuildContext context,
  WidgetRef ref,
  ImageSource source, {
  required void Function(bool uploading) setIsUploading,
}) async {
  try {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked == null) return;

    setIsUploading(true);
    final success =
        await ref.read(profileProvider.notifier).uploadAvatar(picked.path);
    setIsUploading(false);
    if (!context.mounted) return;
    if (!success) {
      context.showSnackBar(
        'Failed to upload photo, try again',
        isError: true,
      );
    }
  } catch (e) {
    setIsUploading(false);
    if (context.mounted) {
      context.showSnackBar(
        'Failed to upload photo, try again',
        isError: true,
      );
    }
  }
}

// ──────────────────────────────────────────────────────────────────────
//  Misc helpers shared with screens
// ──────────────────────────────────────────────────────────────────────

String capitalize(String s) {
  if (s.isEmpty) return s;
  return s[0].toUpperCase() + s.substring(1);
}

/// Mirrors the old `_visibilityLabel`.
String visibilityLabel(String key) {
  switch (key) {
    case 'public':
      return 'Public';
    case 'connections_only':
      return 'Connections Only';
    case 'private':
      return 'Private';
    default:
      return capitalize(key);
  }
}

/// Mirrors the old `_invitePermissionLabel`.
String invitePermissionLabel(String key) {
  switch (key) {
    case 'anyone':
      return 'Everyone';
    case 'connections':
      return 'Connections Only';
    case 'nobody':
      return 'Nobody';
    default:
      return capitalize(key);
  }
}

/// Loads the app version + build info (used by the Me screen header
/// and the Settings hub "Help & about" summary).
Future<({String version, String buildInfo})> loadAppVersionInfo() async {
  final info = await PackageInfo.fromPlatform();
  final version = '${info.version} (${info.buildNumber})';
  final buildInfo =
      'v${info.version} build ${info.buildNumber}\n${info.appName} — ${info.packageName}';
  return (version: version, buildInfo: buildInfo);
}

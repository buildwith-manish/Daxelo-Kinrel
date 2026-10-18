// lib/features/profile/presentation/settings/settings_providers.dart
//
// DAXELO KINREL — Settings providers (extracted from profile_screen.dart).
//
// Why this file exists (KIN-Settings-Refactor):
//   The old ProfileScreen declared its 7 toggle StateProviders as instance
//   fields of _ProfileScreenState and re-loaded their persisted values
//   from FlutterSecureStorage on every call to build() (via
//   _loadBiometricState() + _loadNotificationToggleStates()). That had
//   two problems:
//     1. The values were reloaded on every rebuild — a slow async I/O on
//        a hot path. After the user toggled a switch and the screen
//        rebuilt, the persisted value could overwrite the new in-memory
//        value before the write landed.
//     2. The state was local to ProfileScreen, so the new Settings hub
//        and category screens (which live on different routes) could
//        not read or write the same toggles. The Me "Quick switches"
//        tile would not stay in sync with the Settings "Notifications"
//        toggle.
//
//   This file fixes both: it moves every toggle StateProvider to the
//   top level (so any screen can watch it) and loads the persisted
//   values ONCE via [settingsBootstrapProvider] (a FutureProvider that
//   runs on app start or first read). Toggles are persisted by the
//   existing [SettingsActions.persistToggle] / [SettingsActions.saveToggleState]
//   helpers — the persisted keys are unchanged from the original
//   profile_screen.dart implementation:
//     • push_notifications     -> 'push_notif_enabled'
//     • birthday_reminders    -> 'birthday_reminders_enabled'
//     • anniversary_reminders -> 'anniversary_reminders_enabled'
//     • family_activity       -> 'family_activity_notif_enabled'
//     • biometric lock        -> 'biometric_lock_enabled'
//     • location sharing      -> (no persisted key — runtime state only)
//     • 2FA                   -> synced from profile.twoFactorEnabled
//
//   No behavior changes; the storage keys, defaults, and 2FA sync match
//   the prior implementation exactly. See spec section 4 ("Important fix
//   while moving state").

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/theme/theme_provider.dart'
    show themeModeProvider, fontScaleProvider, localeProvider;
import '../../data/profile_provider.dart';

// ──────────────────────────────────────────────────────────────────────
//  Persistent toggle providers
// ──────────────────────────────────────────────────────────────────────
//
// Defaults mirror the original profile_screen.dart field initializers:
//   push true, birthday true, anniversary false, family activity true,
//   2FA false, biometric false, location false.

final pushNotificationsToggleProvider = StateProvider<bool>((ref) => true);
final birthdayRemindersToggleProvider = StateProvider<bool>((ref) => true);
final anniversaryRemindersToggleProvider = StateProvider<bool>((ref) => false);
final familyActivityToggleProvider = StateProvider<bool>((ref) => true);
final twoFactorToggleProvider = StateProvider<bool>((ref) => false);
final biometricLockToggleProvider = StateProvider<bool>((ref) => false);
final locationSharingToggleProvider = StateProvider<bool>((ref) => false);

// Used by the "Download my data" sheet to show "Request pending" after
// the user taps Request. Local to the runtime session.
final dataExportRequestedProvider = StateProvider<bool>((ref) => false);

/// Loaded by SettingsHubScreen via PackageInfo.fromPlatform(). When
/// the hub loads, it sets this so the Help & about summary can show
/// "FAQ, contact us, version x.y.z" instead of "version —".
final appVersionProvider = StateProvider<String?>((ref) => null);

// ──────────────────────────────────────────────────────────────────────
//  Persisted secure-storage keys
// ──────────────────────────────────────────────────────────────────────

const String kSecureKeyPushNotif = 'push_notif_enabled';
const String kSecureKeyBirthdayReminders = 'birthday_reminders_enabled';
const String kSecureKeyAnniversaryReminders = 'anniversary_reminders_enabled';
const String kSecureKeyFamilyActivity = 'family_activity_notif_enabled';
const String kSecureKeyBiometricLock = 'biometric_lock_enabled';

// ──────────────────────────────────────────────────────────────────────
//  One-shot bootstrap loader
// ──────────────────────────────────────────────────────────────────────

/// Loads the persisted toggle values from FlutterSecureStorage exactly
/// once and writes them into the in-memory StateProviders.
///
/// Runs as a FutureProvider so any screen that needs the persisted
/// values can `ref.watch(settingsBootstrapProvider.future)` to wait
/// for them. The very first watcher triggers the load; later watchers
/// get the cached result.
///
/// This replaces the per-rebuild _loadBiometricState() +
/// _loadNotificationToggleStates() calls in the old ProfileScreen.
/// Those methods scheduled a post-frame write to providers, which:
///   • Re-overwrote a freshly toggled value if the user toggled then
///     the screen rebuilt before the secure-storage read returned.
///   • Ran on every rebuild (slow async I/O on a hot path).
///
/// With this provider, the load runs once. Toggles update the
/// in-memory state synchronously when the user flips them; the
/// SettingsActions.persistToggle helper writes the new value to
/// secure storage asynchronously. The 2FA toggle is synced from
/// profileProvider (same pattern as before).
final settingsBootstrapProvider = FutureProvider<void>((ref) async {
  const storage = FlutterSecureStorage();
  final results = await Future.wait([
    storage.read(key: kSecureKeyPushNotif),
    storage.read(key: kSecureKeyBirthdayReminders),
    storage.read(key: kSecureKeyAnniversaryReminders),
    storage.read(key: kSecureKeyFamilyActivity),
    storage.read(key: kSecureKeyBiometricLock),
  ]);

  // Read defaults that match the StateProvider defaults above.
  // Only update the provider if the persisted value differs —
  // avoids a needless rebuild for users who never touched a toggle.
  final pushVal = results[0] != 'false';
  final birthVal = results[1] != 'false';
  final annivVal = results[2] == 'true';
  final famVal = results[3] != 'false';
  final bioVal = results[4] == 'true';

  if (ref.read(pushNotificationsToggleProvider) != pushVal) {
    ref.read(pushNotificationsToggleProvider.notifier).state = pushVal;
  }
  if (ref.read(birthdayRemindersToggleProvider) != birthVal) {
    ref.read(birthdayRemindersToggleProvider.notifier).state = birthVal;
  }
  if (ref.read(anniversaryRemindersToggleProvider) != annivVal) {
    ref.read(anniversaryRemindersToggleProvider.notifier).state = annivVal;
  }
  if (ref.read(familyActivityToggleProvider) != famVal) {
    ref.read(familyActivityToggleProvider.notifier).state = famVal;
  }
  if (ref.read(biometricLockToggleProvider) != bioVal) {
    ref.read(biometricLockToggleProvider.notifier).state = bioVal;
  }

  // Sync 2FA toggle from profile state. Mirrors the old behavior
  // where the build() method called
  //   if (profile.twoFactorEnabled != ref.read(_twoFactorProvider))
  //     WidgetsBinding.instance.addPostFrameCallback(...)
  final profile = ref.read(profileProvider).profile;
  if (profile != null &&
      ref.read(twoFactorToggleProvider) != profile.twoFactorEnabled) {
    ref.read(twoFactorToggleProvider.notifier).state =
        profile.twoFactorEnabled;
  }
  // Also keep watching profile so a remote 2FA change (e.g. enabled
  // on another device) propagates here.
  ref.listen<ProfileState>(profileProvider, (previous, next) {
    final next2fa = next.profile?.twoFactorEnabled;
    if (next2fa != null &&
        next2fa != ref.read(twoFactorToggleProvider)) {
      ref.read(twoFactorToggleProvider.notifier).state = next2fa;
    }
  });

  return;
});

// ──────────────────────────────────────────────────────────────────────
//  Quiet-hours summary
// ──────────────────────────────────────────────────────────────────────

/// "10pm-6am" or "Off" — read from SharedPreferences using the same
/// keys as QuietHoursScreen. Returns "Off" when quiet hours are
/// disabled or the values aren't set yet.
///
/// Callers should invalidate this provider after returning from
/// /profile/quiet-hours (the QuietHoursScreen itself invalidates it
/// inside _saveToPrefs).
final quietHoursSummaryProvider = FutureProvider<String>((ref) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('enabled') ?? false;
    if (!enabled) return 'Off';
    final sh = prefs.getInt('startHour') ?? 22;
    final sm = prefs.getInt('startMinute') ?? 0;
    final eh = prefs.getInt('endHour') ?? 8;
    final em = prefs.getInt('endMinute') ?? 0;
    return '${_format12(sh, sm)}-${_format12(eh, em)}';
  } catch (_) {
    return 'Off';
  }
});

String _format12(int hour, int minute) {
  final suffix = hour >= 12 ? 'pm' : 'am';
  final h12 = hour % 12 == 0 ? 12 : hour % 12;
  if (minute == 0) return '$h12$suffix';
  final m = minute.toString().padLeft(2, '0');
  return '$h12:$m$suffix';
}

// ──────────────────────────────────────────────────────────────────────
//  Settings summary providers (one per category, used by the hub)
// ──────────────────────────────────────────────────────────────────────

/// Category IDs used by the Settings hub and category screens.
enum SettingsCategory {
  account,
  privacy,
  notifications,
  look,
  familyData,
  help;

  String get id {
    switch (this) {
      case SettingsCategory.account:
        return 'account';
      case SettingsCategory.privacy:
        return 'privacy';
      case SettingsCategory.notifications:
        return 'notifications';
      case SettingsCategory.look:
        return 'look';
      case SettingsCategory.familyData:
        return 'family-data';
      case SettingsCategory.help:
        return 'help';
    }
  }

  String get title {
    switch (this) {
      case SettingsCategory.account:
        return 'Account & security';
      case SettingsCategory.privacy:
        return 'Privacy';
      case SettingsCategory.notifications:
        return 'Notifications';
      case SettingsCategory.look:
        return 'Look & language';
      case SettingsCategory.familyData:
        return 'Family & my data';
      case SettingsCategory.help:
        return 'Help & about';
    }
  }

  static SettingsCategory fromId(String id) {
    return SettingsCategory.values.firstWhere(
      (c) => c.id == id,
      orElse: () => SettingsCategory.account,
    );
  }
}

/// One-line live summary shown under each category row on the Settings
/// hub. Computed from already-loaded providers (no network calls).
///
/// Spec section 2 (Screen 2 — Settings hub) — see the per-category
/// summary lines:
///   1. account:    "Password, 2-step {on|off}, {n} devices"
///   2. privacy:    label of current profile visibility
///   3. notifications: "Birthdays {on|off}, quiet {range|off}"
///   4. look:       "{Theme}, {language native name}, text size {small|medium|large}"
///   5. family-data: "Export tree, download data, blocked"
///   6. help:       "FAQ, contact us, version {x.y.z}"
final settingsSummaryProvider =
    Provider.family<String, SettingsCategory>((ref, cat) {
  switch (cat) {
    case SettingsCategory.account:
      final profile = ref.watch(profileProvider).profile;
      final twoStep = profile?.twoFactorEnabled == true ? 'on' : 'off';
      final n = ref.watch(profileProvider).sessions.length;
      return 'Password, 2-step $twoStep, $n device${n == 1 ? '' : 's'}';

    case SettingsCategory.privacy:
      final visibility =
          ref.watch(profileProvider).profile?.profileVisibility ?? 'public';
      return _visibilityLabel(visibility);

    case SettingsCategory.notifications:
      final birthdays = ref.watch(birthdayRemindersToggleProvider);
      final quiet = ref.watch(quietHoursSummaryProvider).maybeWhen(
            data: (s) => s,
            orElse: () => 'Off',
          );
      return 'Birthdays ${birthdays ? 'on' : 'off'}, quiet $quiet';

    case SettingsCategory.look:
      final themeMode = ref.watch(themeModeProvider);
      final themeName = _themeLabel(themeMode);
      final locale = ref.watch(localeProvider);
      final langName = _languageNativeName(locale?.languageCode ?? 'en');
      final scale = ref.watch(fontScaleProvider);
      final sizeName = _fontScaleLabel(scale);
      return '$themeName, $langName, text size $sizeName';

    case SettingsCategory.familyData:
      return 'Export tree, download data, blocked';

    case SettingsCategory.help:
      final version = ref.watch(appVersionProvider);
      return version != null
          ? 'FAQ, contact us, version $version'
          : 'FAQ, contact us, version —';
  }
});

// ──────────────────────────────────────────────────────────────────────
//  Privacy checkup
// ──────────────────────────────────────────────────────────────────────

/// The four privacy checks the Privacy category's "Privacy checkup"
/// card tallies. Spec section 5 (Privacy category) + Screen 3:
///   1. two-factor enabled
///   2. biometric lock on
///   3. location sharing off
///   4. profile visibility is not public
enum PrivacyCheck { twoFactor, biometric, locationOff, visibilityNotPublic }

/// Returns the set of currently-passing privacy checks.
final privacyChecksPassedProvider = Provider<Set<PrivacyCheck>>((ref) {
  final profile = ref.watch(profileProvider).profile;
  final twoFa = profile?.twoFactorEnabled == true;
  final bio = ref.watch(biometricLockToggleProvider);
  final locOff = !ref.watch(locationSharingToggleProvider);
  final visNotPublic =
      profile != null && profile.profileVisibility != 'public';

  return {
    if (twoFa) PrivacyCheck.twoFactor,
    if (bio) PrivacyCheck.biometric,
    if (locOff) PrivacyCheck.locationOff,
    if (visNotPublic) PrivacyCheck.visibilityNotPublic,
  };
});

/// The most useful next-action sentence for the Privacy checkup card.
/// Empty when all four checks pass.
final privacyCheckupCtaProvider = Provider<String>((ref) {
  final passed = ref.watch(privacyChecksPassedProvider);
  if (!passed.contains(PrivacyCheck.biometric)) {
    return 'Turn on biometric lock to finish. Takes 10 seconds.';
  }
  if (!passed.contains(PrivacyCheck.twoFactor)) {
    return 'Turn on 2-step verification for stronger sign-in.';
  }
  if (!passed.contains(PrivacyCheck.locationOff)) {
    return 'Turn off location sharing to stay private on the map.';
  }
  if (!passed.contains(PrivacyCheck.visibilityNotPublic)) {
    return 'Make your profile visible to family only.';
  }
  return 'All set. Your family tree is well protected.';
});

// ──────────────────────────────────────────────────────────────────────
//  Helpers (mirror _visibilityLabel / _invitePermissionLabel from the
//  old ProfileScreen, exposed so the new Me + Settings screens can call
//  them without re-implementing)
// ──────────────────────────────────────────────────────────────────────

String _visibilityLabel(String key) {
  switch (key) {
    case 'public':
      return 'Public';
    case 'connections_only':
      return 'Connections Only';
    case 'private':
      return 'Private';
    default:
      if (key.isEmpty) return 'Public';
      return key[0].toUpperCase() + key.substring(1);
  }
}

// visibilityLabel and invitePermissionLabel are exported from
// settings_actions.dart for screens to use. This file keeps private
// versions (_visibilityLabel) only for the summary computation.

String _themeLabel(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.dark:
      return 'Dark';
    case ThemeMode.light:
      return 'Light';
    case ThemeMode.system:
      return 'System';
  }
}

String _fontScaleLabel(double scale) {
  if (scale <= 0.9) return 'small';
  if (scale >= 1.1) return 'large';
  return 'medium';
}

// Native-language display names. Defined via \u escapes so the bytes
// are unambiguous (no risk of an editor saving a half-formed combining
// mark). Each value renders as a single human-readable native name.
const Map<String, String> kLanguageOptions = {
  'hi': '\u0939\u093F\u0928\u094D\u0926\u0940', // Hindi (Devanagari)
  'bn': '\u09AC\u09BE\u0982\u09B2\u09BE', // Bengali
  'te': '\u0C24\u0C46\u0C32\u0C41\u0C17\u0C41', // Telugu
  'mr': '\u092E\u0930\u093E\u0920\u0940', // Marathi
  'ta': '\u0BA4\u0BAE\u0BBF\u0BB4\u0BCD', // Tamil
  'gu': '\u0A97\u0AC1\u0A9C\u0AB0\u0ABE\u0AA4\u0AC0', // Gujarati
  'pa': '\u0A2A\u0A70\u0A1C\u0A3E\u0A2C\u0A40', // Punjabi (Gurmukhi)
  'ml': '\u0D2E\u0D32\u0D2F\u0D3E\u0D33\u0D02', // Malayalam
  'kn': '\u0C95\u0CA8\u0CCD\u0CA8\u0CA1', // Kannada
  'or': '\u0B13\u0B21\u0B3C\u0B3F\u0B06', // Odia
  'as': '\u0985\u09B8\u09AE\u09C0\u09AF\u09BC\u09BE', // Assamese
  'sd': '\u0633\u0646\u0681\u064A', // Sindhi
  'ur': '\u0627\u0631\u062F\u0648', // Urdu
  'en': 'English',
};

/// Native-language display name for a language code (e.g. 'hi' → 'हिन्दी').
/// Falls back to 'English' for unknown codes.
String _languageNativeName(String code) {
  return kLanguageOptions[code] ?? 'English';
}

String languageNativeName(String code) => _languageNativeName(code);

/// English-language name for a language code (e.g. 'hi' → 'Hindi').
/// Used by the language sheet.
const Map<String, String> kLanguageEnglishNames = {
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

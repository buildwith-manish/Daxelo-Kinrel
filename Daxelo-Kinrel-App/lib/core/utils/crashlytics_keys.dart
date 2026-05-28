// lib/core/utils/crashlytics_keys.dart
//
// DAXELO KINREL — Crashlytics User Context Helper (P3-F3)
//
// Sets user context on Firebase Crashlytics after login so crash
// reports are associated with the authenticated user. Also clears
// the context on sign-out to prevent stale data.

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../config/app_environment.dart';

class CrashlyticsKeys {
  CrashlyticsKeys._();

  /// Set user context on Crashlytics after a successful sign-in.
  ///
  /// Call this after authentication succeeds so that crash reports
  /// include the user ID, family ID (if available), and current
  /// environment label for easier debugging.
  static Future<void> setUser(String userId, {String? familyId}) async {
    try {
      await FirebaseCrashlytics.instance.setUserIdentifier(userId);
      if (familyId != null) {
        await FirebaseCrashlytics.instance.setCustomKey('familyId', familyId);
      }
      await FirebaseCrashlytics.instance.setCustomKey(
        'environment',
        AppEnvironmentConfig.current.label,
      );
    } catch (_) {
      // Silently ignore — Crashlytics may not be initialized in dev
    }
  }

  /// Clear user context on Crashlytics after sign-out.
  ///
  /// Prevents crash reports from being associated with a user
  /// who is no longer authenticated on this device.
  static Future<void> clearUser() async {
    try {
      await FirebaseCrashlytics.instance.setUserIdentifier('');
    } catch (_) {
      // Silently ignore — Crashlytics may not be initialized in dev
    }
  }
}

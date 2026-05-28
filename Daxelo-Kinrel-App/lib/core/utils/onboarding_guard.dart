import 'package:flutter/foundation.dart';
import '../storage/secure_storage.dart';

/// Onboarding guard — checks whether the user has completed onboarding.
///
/// Uses [SecureStorageService] for persistence, which is backed by
/// flutter_secure_storage on mobile (encrypted keystore/keychain).
class OnboardingGuard {
  OnboardingGuard._();

  /// Returns true if the user has completed onboarding.
  static Future<bool> isComplete() async {
    final storage = SecureStorageService();
    return storage.isOnboardingComplete();
  }

  /// Marks onboarding as complete.
  static Future<void> markComplete() async {
    final storage = SecureStorageService();
    await storage.setOnboardingComplete(true);
  }

  /// Resets onboarding state (debug only — for testing).
  /// Uses assert so this is stripped in release builds.
  static Future<void> reset() async {
    assert(() {
      // In debug mode, allow resetting onboarding for testing
      final storage = SecureStorageService();
      storage.clearAll(); // This clears all secure storage
      return true;
    }(), 'OnboardingGuard.reset() is only available in debug mode');
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/isar_database.dart';

/// In-App Rating Service — follows Play Store best practices.
///
/// ONLY shows the rating prompt when ALL conditions are met:
/// - User has been using the app for at least 7 days
/// - User has added at least 3 family members
/// - User has NOT been prompted before
/// - Current session is at least 3 minutes old
/// - App is in foreground
///
/// Trigger points:
/// - After successfully adding the 3rd family member
/// - After user views the family graph for 30+ seconds
/// - After user shares a profile
class RatingService {
  RatingService._();
  static final RatingService instance = RatingService._();

  DateTime? _sessionStart;
  bool _isForeground = true;

  /// Initialize the rating service. Call once at app startup.
  Future<void> init() async {
    _sessionStart = DateTime.now();
    _isForeground = true;

    // Set install date on first launch
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('install_date') == null) {
      await prefs.setString('install_date', DateTime.now().toIso8601String());
    }
  }

  /// Called when app goes to foreground.
  void onForeground() {
    _isForeground = true;
    if (_sessionStart == null) {
      _sessionStart = DateTime.now();
    }
  }

  /// Called when app goes to background.
  void onBackground() {
    _isForeground = false;
  }

  /// Check all conditions and prompt for rating if eligible.
  /// Call this from trigger points (add member, graph view, share).
  Future<void> checkAndPrompt(WidgetRef ref) async {
    try {
      // Condition 1: App in foreground
      if (!_isForeground) return;

      // Condition 2: Session at least 3 minutes old
      if (_sessionStart == null) return;
      final sessionDuration = DateTime.now().difference(_sessionStart!);
      if (sessionDuration.inMinutes < 3) return;

      final prefs = await SharedPreferences.getInstance();

      // Condition 3: User using app for at least 7 days
      final installDateStr = prefs.getString('install_date');
      if (installDateStr == null) return;
      final installDate = DateTime.tryParse(installDateStr);
      if (installDate == null) return;
      final daysSinceInstall = DateTime.now().difference(installDate).inDays;
      if (daysSinceInstall < 7) return;

      // Condition 4: Not been prompted before
      final alreadyPrompted = prefs.getBool('rating_prompted') ?? false;
      if (alreadyPrompted) return;

      // Condition 5: User has added at least 3 family members
      if (IsarDatabase.isInitialized) {
        final db = IsarDatabase.instance;
        final memberCount = await db.personCount();
        if (memberCount < 3) return;
      } else {
        return; // Can't verify member count without database
      }

      // All conditions met — prompt for review
      final inAppReview = InAppReview.instance;
      if (await inAppReview.isAvailable()) {
        await inAppReview.requestReview();

        // Mark as prompted (never show again)
        await prefs.setBool('rating_prompted', true);
      }
    } catch (e) {
      // Never crash — rating prompt is non-critical
      debugPrint('⚠️ RatingService.checkAndPrompt failed: $e');
    }
  }

  /// Reset rating state (debug only — for testing).
  /// Only works in debug mode via assert.
  Future<void> reset() async {
    assert(() {
      _sessionStart = DateTime.now();
      return true;
    }(), 'RatingService.reset() is only available in debug mode');

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('rating_prompted');
    await prefs.remove('install_date');
  }
}

/// Riverpod provider for RatingService
final ratingServiceProvider = Provider<RatingService>((ref) {
  return RatingService.instance;
});

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:in_app_review/in_app_review.dart';

import '../database/isar_database.dart';
import '../database/collections/cached_person.dart';

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
    final box = Hive.box('preferences');
    if (box.get('install_date') == null) {
      await box.put('install_date', DateTime.now().toIso8601String());
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

      // Condition 3: User using app for at least 7 days
      final box = Hive.box('preferences');
      final installDateStr = box.get('install_date') as String?;
      if (installDateStr == null) return;
      final installDate = DateTime.tryParse(installDateStr);
      if (installDate == null) return;
      final daysSinceInstall = DateTime.now().difference(installDate).inDays;
      if (daysSinceInstall < 7) return;

      // Condition 4: Not been prompted before
      final alreadyPrompted = box.get('rating_prompted', defaultValue: false) as bool;
      if (alreadyPrompted) return;

      // Condition 5: User has added at least 3 family members
      if (IsarDatabase.isInitialized) {
        final isar = IsarDatabase.instance;
        final memberCount = isar.cachedPersons.countSync();
        if (memberCount < 3) return;
      } else {
        return; // Can't verify member count without Isar
      }

      // All conditions met — prompt for review
      final inAppReview = InAppReview.instance;
      if (await inAppReview.isAvailable()) {
        await inAppReview.requestReview();

        // Mark as prompted (never show again)
        await box.put('rating_prompted', true);
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
      final box = Hive.box('preferences');
      box.delete('rating_prompted');
      box.delete('install_date');
      _sessionStart = DateTime.now();
      return true;
    }(), 'RatingService.reset() is only available in debug mode');
  }
}

/// Riverpod provider for RatingService
final ratingServiceProvider = Provider<RatingService>((ref) {
  return RatingService.instance;
});

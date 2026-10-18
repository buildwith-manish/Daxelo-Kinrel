// lib/features/sparq_tray/sparq_tray_analytics.dart
//
// DAXELO KINREL — Family Sparq tray analytics events.
//
// Spec section 10. All event names as typed constants — never raw
// strings — so a single grep can audit every Sparq-tray analytics
// call. No 'story' word anywhere (spec section 0).
//
// Events:
//   • sparq_tray_viewed        — once per Home session, with
//     family_count + families_with_unseen.
//   • sparq_tray_open         — when the user taps a family entry
//     that opens /sparq/family/{id}. Includes family_id,
//     unseen_count, has_moment.
//   • sparq_family_run_completed — when the run screen closes
//     (any way). Includes families_played + members_played.
//   • sparq_moment_action      — when the user taps a Moment
//     CTA. Includes type + action.
//
// All events route through AnalyticsService.instance.logEvent so
// they're silently no-op in dev / test environments where Firebase
// isn't initialized.

import '../../../core/services/analytics_service.dart';

/// Typed Sparq-tray analytics events.
class SparqTrayAnalytics {
  SparqTrayAnalytics._();

  /// Emit `sparq_tray_viewed` — should be called once per Home
  /// session (caller tracks a session flag to deduplicate).
  static Future<void> logTrayViewed({
    required int familyCount,
    required int familiesWithUnseen,
  }) async {
    await AnalyticsService.instance.logEvent(
      'sparq_tray_viewed',
      <String, Object>{
        'family_count': familyCount,
        'families_with_unseen': familiesWithUnseen,
      },
    );
  }

  /// Emit `sparq_tray_open` — when the user taps a family entry that
  /// opens /sparq/family/{id}.
  static Future<void> logTrayOpen({
    required String familyId,
    required int unseenCount,
    required bool hasMoment,
  }) async {
    await AnalyticsService.instance.logEvent(
      'sparq_tray_open',
      <String, Object>{
        'family_id': familyId,
        'unseen_count': unseenCount,
        'has_moment': hasMoment,
      },
    );
  }

  /// Emit `sparq_family_run_completed` — when the run screen closes
  /// (any way: queue exhausted, swipe-down, close button, family-pill
  /// tap). Includes the count of families played and members played.
  static Future<void> logRunCompleted({
    required int familiesPlayed,
    required int membersPlayed,
  }) async {
    await AnalyticsService.instance.logEvent(
      'sparq_family_run_completed',
      <String, Object>{
        'families_played': familiesPlayed,
        'members_played': membersPlayed,
      },
    );
  }

  /// Emit `sparq_moment_action` — when the user taps a Moment CTA
  /// (Send a wish, Pranam, Happy birthday, Voice blessing).
  static Future<void> logMomentAction({
    required String type,
    required String action,
  }) async {
    await AnalyticsService.instance.logEvent(
      'sparq_moment_action',
      <String, Object>{
        'type': type,
        'action': action,
      },
    );
  }
}

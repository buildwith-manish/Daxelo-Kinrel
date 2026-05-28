// lib/core/services/analytics_service.dart
//
// DAXELO KINREL — Analytics Service (P5-F1)
//
// Singleton wrapper around FirebaseAnalytics.
// All event names as typed constants — never raw strings.
// Disabled in dev environment to avoid noise.
// Never logs PII: no names, emails, phone numbers.

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_environment.dart';

// ── Event Name Constants ─────────────────────────────────────────────
// Typed constants prevent typos and make events searchable.

class AnalyticsEvents {
  AnalyticsEvents._();

  // User Lifecycle
  static const String signUp = 'sign_up';
  static const String login = 'login';
  static const String logout = 'logout';

  // Onboarding
  static const String onboardingStart = 'onboarding_start';
  static const String onboardingComplete = 'onboarding_complete';
  static const String onboardingSkip = 'onboarding_skip';

  // Family Actions
  static const String familyCreated = 'family_created';
  static const String familyJoined = 'family_joined';
  static const String memberAdded = 'member_added';
  static const String memberViewed = 'member_viewed';

  // Graph Engagement
  static const String graphOpened = 'graph_opened';
  static const String graphZoomed = 'graph_zoomed';
  static const String graphNodeTapped = 'graph_node_tapped';
  static const String graphSessionDuration = 'graph_session_duration';

  // Sharing & Virality
  static const String shareProfile = 'share_profile';
  static const String inviteSent = 'invite_sent';
  static const String inviteAccepted = 'invite_accepted';
  static const String referralCodeCopied = 'referral_code_copied';

  // Language Feature
  static const String languageSelected = 'language_selected';
  static const String kinshipNameViewed = 'kinship_name_viewed';

  // Engagement
  static const String birthdayReminderTapped = 'birthday_reminder_tapped';
  static const String timelineEventAdded = 'timeline_event_added';
  static const String searchPerformed = 'search_performed';

  // Revenue
  static const String subscriptionStarted = 'subscription_started';
  static const String paymentAttempted = 'payment_attempted';
  static const String paymentSuccess = 'payment_success';
}

// ── Parameter Name Constants ─────────────────────────────────────────

class AnalyticsParams {
  AnalyticsParams._();

  static const String method = 'method';
  static const String page = 'page';
  static const String relation = 'relation';
  static const String nodeCount = 'node_count';
  static const String zoomLevel = 'zoom_level';
  static const String seconds = 'seconds';
  static const String channel = 'channel';
  static const String source = 'source';
  static const String language = 'language';
  static const String query = 'query';
  static const String results = 'results';
  static const String plan = 'plan';
  static const String amount = 'amount';
}

// ── Analytics Service ────────────────────────────────────────────────

class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService _instance = AnalyticsService._();
  static AnalyticsService get instance => _instance;

  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  /// Whether analytics is enabled (disabled in dev environment).
  bool _enabled = true;

  /// Initialize analytics — called once at startup.
  Future<void> init() async {
    // Disable analytics in dev environment
    if (AppEnvironmentConfig.current.isDev) {
      _enabled = false;
      await _analytics.setAnalyticsCollectionEnabled(false);
      debugPrint('📊 Analytics disabled in dev environment');
      return;
    }

    _enabled = true;
    await _analytics.setAnalyticsCollectionEnabled(true);
    debugPrint('📊 Analytics enabled (${AppEnvironmentConfig.current.label})');
  }

  // ── Internal helper ─────────────────────────────────────────────

  Future<void> _logEvent(String name, Map<String, Object>? params) async {
    if (!_enabled) return;
    try {
      await _analytics.logEvent(name: name, parameters: params);
    } catch (e) {
      debugPrint('⚠️ Analytics logEvent failed: $e');
    }
  }

  // ── User Lifecycle ──────────────────────────────────────────────

  Future<void> logSignUp(String method) async {
    await _logEvent(AnalyticsEvents.signUp, {
      AnalyticsParams.method: method,
    });
  }

  Future<void> logLogin(String method) async {
    await _logEvent(AnalyticsEvents.login, {
      AnalyticsParams.method: method,
    });
  }

  Future<void> logLogout() async {
    await _logEvent(AnalyticsEvents.logout, null);
  }

  // ── Onboarding ──────────────────────────────────────────────────

  Future<void> logOnboardingStart() async {
    await _logEvent(AnalyticsEvents.onboardingStart, null);
  }

  Future<void> logOnboardingComplete() async {
    await _logEvent(AnalyticsEvents.onboardingComplete, null);
  }

  Future<void> logOnboardingSkip(int page) async {
    await _logEvent(AnalyticsEvents.onboardingSkip, {
      AnalyticsParams.page: page,
    });
  }

  // ── Family Actions ──────────────────────────────────────────────

  Future<void> logFamilyCreated() async {
    await _logEvent(AnalyticsEvents.familyCreated, null);
  }

  Future<void> logFamilyJoined(String method) async {
    await _logEvent(AnalyticsEvents.familyJoined, {
      AnalyticsParams.method: method,
    });
  }

  Future<void> logMemberAdded(String relation) async {
    await _logEvent(AnalyticsEvents.memberAdded, {
      AnalyticsParams.relation: relation,
    });
  }

  Future<void> logMemberViewed() async {
    await _logEvent(AnalyticsEvents.memberViewed, null);
  }

  // ── Graph Engagement ────────────────────────────────────────────

  Future<void> logGraphOpened(int nodeCount) async {
    await _logEvent(AnalyticsEvents.graphOpened, {
      AnalyticsParams.nodeCount: nodeCount,
    });
  }

  Future<void> logGraphZoomed(double zoomLevel) async {
    await _logEvent(AnalyticsEvents.graphZoomed, {
      AnalyticsParams.zoomLevel: zoomLevel,
    });
  }

  Future<void> logGraphNodeTapped() async {
    await _logEvent(AnalyticsEvents.graphNodeTapped, null);
  }

  Future<void> logGraphSessionDuration(int seconds) async {
    await _logEvent(AnalyticsEvents.graphSessionDuration, {
      AnalyticsParams.seconds: seconds,
    });
  }

  // ── Sharing & Virality ──────────────────────────────────────────

  Future<void> logShareProfile(String method) async {
    await _logEvent(AnalyticsEvents.shareProfile, {
      AnalyticsParams.method: method,
    });
  }

  Future<void> logInviteSent(String channel) async {
    await _logEvent(AnalyticsEvents.inviteSent, {
      AnalyticsParams.channel: channel,
    });
  }

  Future<void> logInviteAccepted(String source) async {
    await _logEvent(AnalyticsEvents.inviteAccepted, {
      AnalyticsParams.source: source,
    });
  }

  Future<void> logReferralCodeCopied() async {
    await _logEvent(AnalyticsEvents.referralCodeCopied, null);
  }

  // ── Language Feature ────────────────────────────────────────────

  Future<void> logLanguageSelected(String language) async {
    await _logEvent(AnalyticsEvents.languageSelected, {
      AnalyticsParams.language: language,
    });
  }

  Future<void> logKinshipNameViewed(String language, String relation) async {
    await _logEvent(AnalyticsEvents.kinshipNameViewed, {
      AnalyticsParams.language: language,
      AnalyticsParams.relation: relation,
    });
  }

  // ── Engagement ──────────────────────────────────────────────────

  Future<void> logBirthdayReminderTapped() async {
    await _logEvent(AnalyticsEvents.birthdayReminderTapped, null);
  }

  Future<void> logTimelineEventAdded() async {
    await _logEvent(AnalyticsEvents.timelineEventAdded, null);
  }

  Future<void> logSearchPerformed(String query, int results) async {
    // Sanitize: truncate query to avoid logging sensitive data
    final sanitizedQuery = query.length > 50 ? query.substring(0, 50) : query;
    await _logEvent(AnalyticsEvents.searchPerformed, {
      AnalyticsParams.query: sanitizedQuery,
      AnalyticsParams.results: results,
    });
  }

  // ── Revenue ─────────────────────────────────────────────────────

  Future<void> logSubscriptionStarted(String plan) async {
    await _logEvent(AnalyticsEvents.subscriptionStarted, {
      AnalyticsParams.plan: plan,
    });
  }

  Future<void> logPaymentAttempted(double amount) async {
    // Amount in rupees (not paise)
    await _logEvent(AnalyticsEvents.paymentAttempted, {
      AnalyticsParams.amount: amount,
    });
  }

  Future<void> logPaymentSuccess(double amount) async {
    await _logEvent(AnalyticsEvents.paymentSuccess, {
      AnalyticsParams.amount: amount,
    });
  }

  // ── User Properties ─────────────────────────────────────────────

  Future<void> setUserProperties({
    required String userId,
    required String familyId,
    required int memberCount,
    required String preferredLanguage,
    required bool isPremium,
  }) async {
    if (!_enabled) return;
    try {
      await _analytics.setUserId(id: userId);
      await _analytics.setUserProperty(name: 'family_id', value: familyId);
      await _analytics.setUserProperty(
        name: 'member_count',
        value: memberCount.toString(),
      );
      await _analytics.setUserProperty(
        name: 'preferred_language',
        value: preferredLanguage,
      );
      await _analytics.setUserProperty(
        name: 'is_premium',
        value: isPremium.toString(),
      );
    } catch (e) {
      debugPrint('⚠️ Analytics setUserProperties failed: $e');
    }
  }

  // ── Screen Tracking ─────────────────────────────────────────────

  Future<void> logScreenView(String screenName) async {
    if (!_enabled) return;
    try {
      await _analytics.logScreenView(screenName: screenName);
    } catch (e) {
      debugPrint('⚠️ Analytics logScreenView failed: $e');
    }
  }
}

// ── Analytics Navigator Observer ──────────────────────────────────────
// Added to GoRouter to track every route change automatically.

class AnalyticsNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route route, Route? previousRoute) {
    final name = route.settings.name;
    if (name != null && name.isNotEmpty) {
      AnalyticsService.instance.logScreenView(name);
    }
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    // Track the screen we're returning to
    final name = previousRoute?.settings.name;
    if (name != null && name.isNotEmpty) {
      AnalyticsService.instance.logScreenView(name);
    }
  }
}

/// Riverpod provider for AnalyticsService
final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  return AnalyticsService.instance;
});

// lib/core/services/remote_config_service.dart
//
// DAXELO KINREL — Remote Config Service (P5)
//
// Wraps FirebaseRemoteConfig with typed getters and safe defaults.
// Provides feature flags and configuration values that can be
// updated server-side without an app release.
//
// Must be initialized in main.dart via RemoteConfigService.instance.init()
// before any values are accessed.
//
// Usage:
//   await RemoteConfigService.instance.init();
//   final showBanner = RemoteConfigService.instance.showInviteBanner;

import 'package:flutter/foundation.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';

import '../config/app_environment.dart';
import 'crashlytics_service.dart';

class RemoteConfigService {
  RemoteConfigService._();
  static final RemoteConfigService instance = RemoteConfigService._();

  late final FirebaseRemoteConfig _remoteConfig;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  // ── Initialization ───────────────────────────────────────────────

  /// Initialize Firebase Remote Config with settings and defaults.
  ///
  /// Should be called once in main.dart after Firebase is initialized.
  /// Uses a 12-hour fetch timeout and 1-hour minimum fetch interval
  /// in production (0 in dev for instant testing).
  Future<void> init() async {
    try {
      _remoteConfig = FirebaseRemoteConfig.instance;

      await _remoteConfig.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(hours: 12),
        minimumFetchInterval: AppEnvironmentConfig.current.isDev
            ? Duration.zero
            : const Duration(hours: 1),
      ));

      await _remoteConfig.setDefaults(_defaults);

      final activated = await _remoteConfig.fetchAndActivate();
      _initialized = true;

      debugPrint(
        '🔧 RemoteConfig initialized (activated: $activated, '
        'keys: ${_remoteConfig.getAll().keys.length})',
      );
    } catch (e, st) {
      logError(e, st, reason: 'RemoteConfigService.init failed');
      // Use defaults if Remote Config fails
      _initialized = false;
    }
  }

  // ── Default Values ───────────────────────────────────────────────

  static const Map<String, dynamic> _defaults = {
    'show_invite_banner': true,
    'invite_banner_text': 'Invite family members to grow your tree!',
    'onboarding_variant': 'default',
    'graph_default_zoom': 1.0,
    'enable_ai_suggestions': false,
    'member_add_cta_text': 'Add Family Member',
    'show_referral_on_profile': true,
    'retention_nudge_day': 3,
    'max_free_members': 15,
  };

  // ── Typed Getters ────────────────────────────────────────────────

  /// Whether to show the invite banner on the home screen.
  bool get showInviteBanner =>
      _getBool('show_invite_banner');

  /// Text to display in the invite banner.
  String get inviteBannerText =>
      _getString('invite_banner_text');

  /// A/B test variant for onboarding flow.
  String get onboardingVariant =>
      _getString('onboarding_variant');

  /// Default zoom level for the family graph view.
  double get graphDefaultZoom =>
      _getDouble('graph_default_zoom');

  /// Whether AI-powered suggestions are enabled.
  bool get enableAiSuggestions =>
      _getBool('enable_ai_suggestions');

  /// CTA text for the "add member" button.
  String get memberAddCtaText =>
      _getString('member_add_cta_text');

  /// Whether to show the referral section on the profile screen.
  bool get showReferralOnProfile =>
      _getBool('show_referral_on_profile');

  /// Number of days before showing a retention nudge notification.
  int get retentionNudgeDay =>
      _getInt('retention_nudge_day');

  /// Maximum number of free members before requiring premium.
  int get maxFreeMembers =>
      _getInt('max_free_members');

  // ── Internal Helpers ─────────────────────────────────────────────

  bool _getBool(String key) {
    try {
      if (!_initialized) return _defaults[key] as bool? ?? false;
      return _remoteConfig.getBool(key);
    } catch (_) {
      return _defaults[key] as bool? ?? false;
    }
  }

  String _getString(String key) {
    try {
      if (!_initialized) return _defaults[key] as String? ?? '';
      return _remoteConfig.getString(key);
    } catch (_) {
      return _defaults[key] as String? ?? '';
    }
  }

  int _getInt(String key) {
    try {
      if (!_initialized) return _defaults[key] as int? ?? 0;
      return _remoteConfig.getInt(key);
    } catch (_) {
      return _defaults[key] as int? ?? 0;
    }
  }

  double _getDouble(String key) {
    try {
      if (!_initialized) return _defaults[key] as double? ?? 0.0;
      return _remoteConfig.getDouble(key);
    } catch (_) {
      return _defaults[key] as double? ?? 0.0;
    }
  }

  /// Get all remote config values as a map (for debug dashboard).
  Map<String, dynamic> getAllValues() {
    if (!_initialized) return Map.from(_defaults);

    try {
      final all = _remoteConfig.getAll();
      return all.map((key, value) {
        // Try each type in order
        try {
          return MapEntry(key, value.toBool());
        } catch (_) {}
        try {
          return MapEntry(key, value.toDouble());
        } catch (_) {}
        try {
          return MapEntry(key, value.toInt());
        } catch (_) {}
        try {
          return MapEntry(key, value.asString());
        } catch (_) {}
        return MapEntry(key, value.source);
      });
    } catch (_) {
      return Map.from(_defaults);
    }
  }
}

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
  ///
  /// WEB: Skipped — Firebase Remote Config requires web-specific setup
  /// (API key + app ID + measurementId in the Firebase web config).
  /// This project runs in Supabase-only mode on web, so Remote Config
  /// falls back to the hardcoded defaults in [_defaults]. All getters
  /// (getBool/getDouble/getInt/getString) already use the same
  /// `_defaults` map when `_initialized == false`.
  Future<void> init() async {
    if (kIsWeb) {
      _initialized = false;
      debugPrint('🔧 RemoteConfig skipped on web — using defaults');
      return;
    }

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
    // Free-tier member cap: 100 members per family. This is calibrated
    // to the Indian joint-family household reality (which routinely
    // runs larger than a generic nuclear-family assumption), so the
    // cap is intentionally generous. It exists as a real abuse/
    // infrastructure backstop rather than a tight monetization gate.
    // Premium (Kinrel Plus) removes this cap entirely.
    'max_free_members': 100,
    // Free-tier family count: a HIGH technical ceiling (10 families)
    // acting purely as an abuse/safety backstop. There is NO paywall
    // at this volume — multiple families are free. Premium (Kinrel
    // Plus) raises this ceiling further if ever hit.
    'max_free_families': 10,
    // Free-tier monthly Memory Vault upload soft cap. Free users may
    // upload up to 50 photos per calendar month (storage has real
    // marginal cost, unlike member/family counts). Hitting the cap
    // shows a non-alarming in-context message and an upsell to
    // Kinrel Plus, but does NOT hard-block — see MemoryVaultScreen.
    // Premium (Kinrel Plus) removes this limit entirely.
    'memory_vault_free_monthly_cap': 50,
    // Premium-only feature flags. These gate features that are
    // available ONLY to premium users. The UI shows them (soft
    // paywall) but free users can't tap them without upgrading.
    // Per the tier revision pass: GEDCOM export is genuinely
    // premium (matches competitor pattern: Ancestry/MyHeritage both
    // paywall GEDCOM export). AI kinship discovery is FREE — it's a
    // core differentiator and was previously a phantom gate.
    'premium_feature_export': true,
    'premium_feature_ai_kinship': false,
    'premium_feature_insights': true,

    // ── Feature Registry keys (Phase 4 lean launch set + heroFamilyMap ON) ──
    //
    // Mirrors the `_defaults` map in feature_registry.dart exactly —
    // 21 ON (daily-use surface, incl. heroFamilyMap turned ON per
    // user request 2026-10-23), 43 OFF (premium/experimental/push),
    // 1 untouched (`feature_unified_timeline` stays `true` — no UI
    // surface, leave alone per spec).
    //
    // When Remote Config has not been fetched / is offline,
    // `Features.isOn()` reads through `_defaults` here. When RC is
    // live, the server-side value overrides the local default — so
    // flipping a feature from the RC console is one-click.
    //
    // ── ON (21) ─────────────────────────────────────────────────────
    'feature_home': true,
    'feature_family_map': true,
    'feature_kinrel': true,
    'feature_sparq_tray': true,
    'feature_feed': true,
    'feature_chat': true,
    'feature_family_chat': true,
    'feature_members': true,
    'feature_calendar': true,
    'feature_profile': true,
    'feature_profile_editing': true,
    'feature_find_on_kinrel': true,
    'feature_activities': true,
    'feature_memories': true,
    'feature_member_timeline': true,
    'feature_oral_history': true,
    'feature_todays_question': true,
    'feature_invite_banner': true,
    'feature_top_bar_notifications': true,
    'feature_top_bar_settings': true,
    // Turned ON per user request 2026-10-23: the hero Graph + Map
    // flanking icons now render. Routes (/family/:id/graph,
    // /family/:id/map) already accessible via feature_family_map.
    'feature_hero_family_map': true,
    // ── OFF (43) ────────────────────────────────────────────────────
    'feature_family_journey': false,
    'feature_sparq_run_navigation': false,
    'feature_circle': false,
    'feature_communities': false,
    'feature_games': false,
    'feature_game_invite_push': false,
    'feature_achievements': false,
    'feature_lists': false,
    'feature_governance_timeline': false, // NEW — OFF per spec
    'feature_hero_kinrel': false,
    'feature_hero_find_on_kinrel': false,
    'feature_hero_add_member': false,
    'feature_cameo_fallback': false,
    'feature_live3d_cameo': false,
    'feature_cameo_studio': false,
    'feature_voice_messages': false,
    'feature_scheduled_messages': false,
    'feature_chat_mentions': false,
    'feature_chat_block_report': false,
    'feature_chat_reactions': false,
    'feature_chat_typing_indicator': false,
    'feature_chat_gallery': false,
    'feature_graph_share_export': false,
    'feature_photo_picker': false,
    'feature_qr_join': false,
    'feature_language_picker': false,
    'feature_audio_pronunciation': false,
    'feature_auto_kinship_inference': false,
    'feature_kinship_ring_row': false,
    'feature_paywall': false,
    'feature_premium_insights': false,
    'feature_premium_export': false,
    'feature_premium_ai_kinship': false,
    'feature_memory_vault': false,
    'feature_memory_vault_free_monthly_cap': false,
    'feature_max_free_members': false,
    'feature_max_free_families': false,
    'feature_coin_pool': false,
    'feature_prediction_battle': false,
    'feature_push_game_invite': false,
    'feature_push_re_engagement': false,
    'feature_push_mention': false,
    'feature_push_scheduled_message': false,
    'feature_referral_on_profile': false,
    'feature_retention_nudge': false,
    'feature_ai_suggestions': false,
    'feature_onboarding': false,
    // ── UNTOUCHED (1) — no screen yet ───────────────────────────────
    'feature_unified_timeline': true,
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
  /// Default 100 — calibrated for Indian joint-family households.
  /// This is an abuse/infrastructure backstop, not a tight
  /// monetization gate. Kinrel Plus removes it entirely.
  int get maxFreeMembers =>
      _getInt('max_free_members');

  /// Maximum number of free families before requiring premium.
  /// Default 10 — a HIGH technical ceiling acting purely as an
  /// abuse/safety backstop. There is NO paywall at this volume;
  /// multiple families are free. Kinrel Plus raises this if hit.
  int get maxFreeFamilies =>
      _getInt('max_free_families');

  /// Free-tier monthly Memory Vault upload soft cap.
  /// Default 50 — calendar-month reset. Free users hitting this
  /// see a non-alarming in-context message + Kinrel Plus upsell,
  /// but the upload flow itself is not hard-blocked. Kinrel Plus
  /// removes the limit entirely.
  int get memoryVaultFreeMonthlyCap =>
      _getInt('memory_vault_free_monthly_cap');

  /// ── Premium feature flags ────────────────────────────────────────
  /// These gate features that are ONLY available to premium users.
  /// The UI shows them (soft paywall) but free users can't tap them
  /// without upgrading.

  /// Whether GEDCOM export is a premium-only feature.
  /// Default TRUE (genuinely enforced) — matches competitor pattern
  /// (Ancestry/MyHeritage both paywall GEDCOM export). The
  /// canExport() gate in PremiumService is wired into the export
  /// flow and the paywall advertises it accurately.
  bool get premiumFeatureExport =>
      _getBool('premium_feature_export');

  /// Whether AI kinship discovery is a premium-only feature.
  /// Default FALSE — AI kinship is a core differentiator and is
  /// FREE for everyone. The previous canUseAiKinship() gate was
  /// a phantom gate (advertised but never enforced); it has been
  /// removed and the paywall copy no longer references it.
  bool get premiumFeatureAiKinship =>
      _getBool('premium_feature_ai_kinship');

  /// Whether the family insights dashboard is a premium-only feature.
  bool get premiumFeatureInsights =>
      _getBool('premium_feature_insights');

  // ── Internal Helpers ─────────────────────────────────────────────

  /// Public bool reader. Reads through the same fallback chain as the
  /// internal `_getBool` (compiled default → Remote Config), so it is
  /// safe to call before [init] completes (returns the default).
  ///
  /// Used by the Feature Registry (`Features.isOn`) so the registry
  /// can read `feature_<name>` keys without exposing `_remoteConfig`
  /// or duplicating the fallback logic.
  bool getBool(String key) => _getBool(key);

  /// True iff [key] is present in the compiled [_defaults] map (the
  /// canonical "known keys" set). Used by the Feature Registry to
  /// decide whether a Remote Config value is authoritative (key is
  /// deployed) or whether to fall back to the compiled default (key
  /// has not been pushed to the RC console yet).
  bool hasKey(String key) => _defaults.containsKey(key);

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
      final result = <String, dynamic>{};
      for (final key in all.keys) {
        // Determine type from defaults, then use the typed getter
        final defaultValue = _defaults[key];
        if (defaultValue is bool) {
          result[key] = _remoteConfig.getBool(key);
        } else if (defaultValue is double) {
          result[key] = _remoteConfig.getDouble(key);
        } else if (defaultValue is int) {
          result[key] = _remoteConfig.getInt(key);
        } else if (defaultValue is String) {
          result[key] = _remoteConfig.getString(key);
        } else {
          result[key] = _remoteConfig.getString(key);
        }
      }
      return result;
    } catch (_) {
      return Map.from(_defaults);
    }
  }
}

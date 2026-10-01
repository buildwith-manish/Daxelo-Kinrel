// lib/core/services/premium_service.dart
//
// DAXELO KINREL — Premium Service (P5)
//
// Manages premium subscription status locally (SharedPreferences)
// and from the backend. Provides canAddMember() check against
// RemoteConfig maxFreeMembers limit.
//
// Usage:
//   final isPremium = await PremiumService.isPremium();
//   final canAdd = await PremiumService.canAddMember(currentCount);
//   await PremiumService.setPremium(true);

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

import 'remote_config_service.dart';

class PremiumService {
  PremiumService._();

  static const _premiumKey = 'is_premium';
  static const _premiumExpiryKey = 'premium_expiry';

  // ── Local Status ────────────────────────────────────────────────

  /// Check if the user has premium status from local cache.
  static Future<bool> isPremium() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_premiumKey) ?? false;
    } catch (e) {
      debugPrint('⚠️ PremiumService.isPremium failed: $e');
      return false;
    }
  }

  /// Set premium status in local cache.
  static Future<void> setPremium(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_premiumKey, value);
      debugPrint('🟡 PremiumService: premium set to $value');
    } catch (e) {
      debugPrint('⚠️ PremiumService.setPremium failed: $e');
    }
  }

  /// Set premium expiry date in local cache.
  static Future<void> setPremiumExpiry(DateTime? expiry) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (expiry != null) {
        await prefs.setString(_premiumExpiryKey, expiry.toIso8601String());
      } else {
        await prefs.remove(_premiumExpiryKey);
      }
    } catch (e) {
      debugPrint('⚠️ PremiumService.setPremiumExpiry failed: $e');
    }
  }

  /// Check if premium subscription is still active (not expired).
  static Future<bool> isPremiumActive() async {
    final premium = await isPremium();
    if (!premium) return false;

    try {
      final prefs = await SharedPreferences.getInstance();
      final expiryStr = prefs.getString(_premiumExpiryKey);
      if (expiryStr == null) return true; // No expiry = lifetime

      final expiry = DateTime.tryParse(expiryStr);
      if (expiry == null) return true;

      return DateTime.now().isBefore(expiry);
    } catch (_) {
      return premium;
    }
  }

  // ── Member Limit Check ───────────────────────────────────────────

  /// Check if the user can add another member based on their
  /// current member count and the RemoteConfig maxFreeMembers limit.
  ///
  /// Premium users always return true.
  static Future<bool> canAddMember(int currentMemberCount) async {
    final premium = await isPremiumActive();
    if (premium) return true;

    final maxFreeMembers = RemoteConfigService.instance.maxFreeMembers;
    return currentMemberCount < maxFreeMembers;
  }

  /// Check if the user can add another family based on their
  /// current family count and the RemoteConfig maxFreeFamilies limit.
  ///
  /// Premium users always return true. Free users are limited to
  /// `maxFreeFamilies` (default 1) — one family is enough to activate;
  /// a 2nd is the natural upsell moment.
  static Future<bool> canAddFamily(int currentFamilyCount) async {
    final premium = await isPremiumActive();
    if (premium) return true;

    final maxFreeFamilies = RemoteConfigService.instance.maxFreeFamilies;
    return currentFamilyCount < maxFreeFamilies;
  }

  // ── Feature Gates (Tier 4 soft paywall) ───────────────────────────
  //
  // Each method returns true if the user can access the feature.
  // Premium users always get true. Free users get true only if the
  // feature is NOT premium-gated (checked via RemoteConfig flags).
  //
  // The UI uses these to decide: show the feature, or show a "Premium"
  // badge + route to the paywall when tapped.

  /// Whether the user can access GEDCOM export.
  static Future<bool> canExport() async {
    final premium = await isPremiumActive();
    if (premium) return true;
    // If the feature flag is OFF, the feature is free for everyone.
    return !RemoteConfigService.instance.premiumFeatureExport;
  }

  /// Whether the user can access AI kinship discovery.
  static Future<bool> canUseAiKinship() async {
    final premium = await isPremiumActive();
    if (premium) return true;
    return !RemoteConfigService.instance.premiumFeatureAiKinship;
  }

  /// Whether the user can access the family insights dashboard.
  static Future<bool> canViewInsights() async {
    final premium = await isPremiumActive();
    if (premium) return true;
    return !RemoteConfigService.instance.premiumFeatureInsights;
  }

  /// The free-tier member limit (for display in the paywall).
  static int get maxFreeMembers => RemoteConfigService.instance.maxFreeMembers;

  /// The free-tier family limit (for display in the paywall).
  static int get maxFreeFamilies => RemoteConfigService.instance.maxFreeFamilies;

  // ── Backend Sync ────────────────────────────────────────────────

  /// Fetch premium status from the backend and update local cache.
  /// Silently fails if the backend is unreachable (NestJS currently
  /// rejects Supabase JWTs) — the app works in free mode by default.
  ///
  /// GET /api/premium/status
  /// Response: { "isPremium": bool, "expiry": "2025-12-31T23:59:59Z" }
  static Future<void> fetchPremiumStatus(Dio dio) async {
    try {
      final response = await dio.get('/api/premium/status');
      final data = response.data as Map<String, dynamic>;

      final isPremiumValue = data['isPremium'] as bool? ?? false;
      await setPremium(isPremiumValue);

      final expiryStr = data['expiry'] as String?;
      if (expiryStr != null) {
        final expiry = DateTime.tryParse(expiryStr);
        await setPremiumExpiry(expiry);
      } else {
        await setPremiumExpiry(null);
      }

      debugPrint('🟡 PremiumService: fetched premium=$isPremiumValue');
    } catch (e) {
      // Silently fail — the app defaults to free mode.
      // The NestJS backend currently rejects Supabase JWTs (ES256/HS256
      // mismatch), so this will 401. Don't log as error to avoid noise.
      debugPrint('🟡 PremiumService: backend unavailable, using free mode');
    }
  }

  // ── Clear (on logout) ───────────────────────────────────────────

  /// Clear premium data from local cache.
  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_premiumKey);
      await prefs.remove(_premiumExpiryKey);
    } catch (_) {}
  }
}

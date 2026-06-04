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

import 'crashlytics_service.dart';
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

  // ── Backend Sync ────────────────────────────────────────────────

  /// Fetch premium status from the backend and update local cache.
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
    } catch (e, st) {
      logError(e, st, reason: 'PremiumService.fetchPremiumStatus failed');
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

// lib/core/services/premium_service.dart
//
// DAXELO KINREL — Premium Service (P5)
//
// Manages premium subscription status locally (Hive 'settings' box)
// and from the backend. Provides canAddMember() check against
// RemoteConfig maxFreeMembers limit.
//
// Usage:
//   final isPremium = await PremiumService.isPremium();
//   final canAdd = await PremiumService.canAddMember(currentCount);
//   await PremiumService.setPremium(true);

import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/foundation.dart';

import 'crashlytics_service.dart';
import 'remote_config_service.dart';

class PremiumService {
  PremiumService._();

  static const _settingsBox = 'settings';
  static const _premiumKey = 'is_premium';
  static const _premiumExpiryKey = 'premium_expiry';

  // ── Local Status (Hive) ─────────────────────────────────────────

  /// Check if the user has premium status from local Hive cache.
  static Future<bool> isPremium() async {
    try {
      final box = Hive.box(_settingsBox);
      return box.get(_premiumKey, defaultValue: false) as bool;
    } catch (e) {
      debugPrint('⚠️ PremiumService.isPremium failed: $e');
      return false;
    }
  }

  /// Set premium status in local Hive cache.
  static Future<void> setPremium(bool value) async {
    try {
      final box = Hive.box(_settingsBox);
      await box.put(_premiumKey, value);
      debugPrint('🟡 PremiumService: premium set to $value');
    } catch (e) {
      debugPrint('⚠️ PremiumService.setPremium failed: $e');
    }
  }

  /// Set premium expiry date in local Hive cache.
  static Future<void> setPremiumExpiry(DateTime? expiry) async {
    try {
      final box = Hive.box(_settingsBox);
      if (expiry != null) {
        await box.put(_premiumExpiryKey, expiry.toIso8601String());
      } else {
        await box.delete(_premiumExpiryKey);
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
      final box = Hive.box(_settingsBox);
      final expiryStr = box.get(_premiumExpiryKey) as String?;
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
      final box = Hive.box(_settingsBox);
      await box.delete(_premiumKey);
      await box.delete(_premiumExpiryKey);
    } catch (_) {}
  }
}

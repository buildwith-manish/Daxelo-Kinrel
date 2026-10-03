// lib/core/services/premium_service.dart
//
// DAXELO KINREL — Premium Service (P5)
//
// Manages premium subscription status locally (SharedPreferences)
// and from the backend. Provides gating logic for the Kinrel tier
// structure:
//
//   FREE TIER
//   • Up to 100 members per family (Indian joint-family calibrated)
//   • Multiple families allowed (high technical ceiling: 10)
//   • Memory Vault: soft cap at 50 uploads / calendar month
//   • Family graph, games, chat, Prediction Battle, coin economy,
//     Graph/Map views — all free and uncapped
//   • Joining an existing family as an invited member is ALWAYS free
//     and uncapped regardless of that family's size relative to the
//     100-member cap. The cap applies to a family's TOTAL size/
//     growth on the INVITING side, NOT to an individual's ability
//     to accept an invite. (canAddMember is checked by the family
//     admin when adding/inviting, never by the invitee when
//     accepting — see join_family_screen.dart.)
//   • AI kinship discovery: FREE (core differentiator)
//
//   KINREL PLUS (paid)
//   • Removes the 100-member cap (unlimited members per family)
//   • Raises the family-count ceiling if ever hit
//   • Unlimited Memory Vault uploads/storage
//   • Family Insights dashboard (soft paywall, blurred preview)
//   • GEDCOM export (genuinely enforced — matches competitor pattern)
//
// IMPORTANT: Razorpay payment capture remains STUBBED per prior
// direction. Tapping "Subscribe" still grants Premium without real
// payment. This tier structure is NOT revenue-generating until
// Razorpay integration is completed separately.
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

  // ── Memory Vault Monthly Upload Tracking ──────────────────────
  //
  // Free-tier Memory Vault uploads are soft-capped at
  // RemoteConfigService.instance.memoryVaultFreeMonthlyCap (default
  // 50) per CALENDAR MONTH. The counter is reset on the first day
  // of each new month (calendar-month basis — simpler to reason
  // about and communicate than rolling). Premium users bypass the
  // counter entirely.
  //
  // Storage: shared preferences, keyed by year-month (e.g.
  // "memory_vault_uploads_2026_10"). A separate "memory_vault_
  // uploads_period" key tracks the current period, so a stale
  // entry from a previous month is detected and replaced.
  static const _mvUploadsCountKey = 'memory_vault_uploads_count';
  static const _mvUploadsPeriodKey = 'memory_vault_uploads_period';

  /// Returns the current calendar-month period key (e.g. "2026_10").
  static String _currentMemoryVaultPeriod() {
    final now = DateTime.now();
    return '${now.year}_${now.month.toString().padLeft(2, '0')}';
  }

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
  //
  // The free-tier member cap (default 100) applies to a family's
  // TOTAL size/growth on the INVITING side. It is checked when a
  // family admin attempts to add or invite a NEW member to a
  // family that is already at the cap.
  //
  // It does NOT apply to accepting an invitation to an EXISTING
  // family — accepting an invite is always free and uncapped on
  // the invitee's side, regardless of the inviting family's tier
  // or current size. See the join flow at join_family_screen.dart
  // (it deliberately does NOT call canAddMember).

  /// Check if the user can add another member based on their
  /// current family's member count and the RemoteConfig
  /// maxFreeMembers limit (default 100, calibrated for Indian
  /// joint-family households).
  ///
  /// Premium (Kinrel Plus) users always return true.
  static Future<bool> canAddMember(int currentMemberCount) async {
    final premium = await isPremiumActive();
    if (premium) return true;

    final maxFreeMembers = RemoteConfigService.instance.maxFreeMembers;
    return currentMemberCount < maxFreeMembers;
  }

  /// Check if the user can create another family based on their
  /// current family count.
  ///
  /// Premium (Kinrel Plus) users always return true. Free users
  /// are limited to `maxFreeFamilies` (default 10) — but this is
  /// a HIGH technical ceiling acting purely as an abuse/safety
  /// backstop, NOT a monetization gate. There is NO paywall at
  /// this volume; multiple families are free. The UI surfaces a
  /// neutral informational message (not an upsell) only if this
  /// ceiling is ever hit, which is vanishingly unlikely in
  /// practice.
  static Future<bool> canAddFamily(int currentFamilyCount) async {
    final premium = await isPremiumActive();
    if (premium) return true;

    final maxFreeFamilies = RemoteConfigService.instance.maxFreeFamilies;
    return currentFamilyCount < maxFreeFamilies;
  }

  // ── Feature Gates ───────────────────────────────────────────────
  //
  // Each method returns true if the user can access the feature.
  // Premium users always get true. Free users get true only if the
  // feature is NOT premium-gated (checked via RemoteConfig flags).
  //
  // The UI uses these to decide: show the feature, or show a
  // "Premium" badge + route to the paywall when tapped.
  //
  // IMPORTANT — NO PHANTOM GATES:
  // Every gate here MUST have a corresponding paywall benefit
  // listed in paywall_sheet.dart, and every advertised paywall
  // benefit MUST have a corresponding real gate here. Dead gates
  // that are never enforced have been removed.

  /// Whether the user can access GEDCOM export.
  ///
  /// GENUINELY PREMIUM — this gate IS enforced in
  /// `gedcom_export_screen.dart` (the export action is blocked
  /// for non-premium users and routes them to the paywall). The
  /// paywall_sheet advertises this accurately. This matches the
  /// competitor pattern (Ancestry/MyHeritage both paywall GEDCOM
  /// export as a defensible premium hook).
  static Future<bool> canExport() async {
    final premium = await isPremiumActive();
    if (premium) return true;
    // If the feature flag is OFF, the feature is free for everyone.
    return !RemoteConfigService.instance.premiumFeatureExport;
  }

  /// Whether the user can access AI kinship discovery.
  ///
  /// FREE FOR EVERYONE — this gate has been REMOVED per the tier
  /// revision pass. AI kinship was identified as a core
  /// differentiator and the previous canUseAiKinship() check was
  /// a phantom gate (advertised in the paywall but never actually
  /// enforced anywhere in the codebase). It has been removed and
  /// the paywall copy no longer references it.
  ///
  /// This method is retained for backward compatibility and always
  /// returns true. It exists so that any future caller that might
  /// want to gate this feature can do so via RemoteConfig if the
  /// product decision ever reverses — but for now it is a no-op.
  static Future<bool> canUseAiKinship() async {
    final premium = await isPremiumActive();
    if (premium) return true;
    // Always returns true for free users — AI kinship is free.
    // (RemoteConfig flag retained for future use only.)
    return true;
  }

  /// Whether the user can access the family insights dashboard.
  ///
  /// Soft paywall — free users see a blurred preview of the
  /// dashboard with a "Premium" badge overlay and a tap-to-upgrade
  /// affordance. See family_insights_dashboard.dart. The dashboard
  /// is positioned AFTER free-value content so it never blocks the
  /// main flow.
  static Future<bool> canViewInsights() async {
    final premium = await isPremiumActive();
    if (premium) return true;
    return !RemoteConfigService.instance.premiumFeatureInsights;
  }

  // ── Memory Vault Monthly Upload Tracking ────────────────────────
  //
  // Free-tier Memory Vault uploads are soft-capped at
  // `memoryVaultFreeMonthlyCap` (default 50) per CALENDAR MONTH.
  // Calendar-month reset is simpler to reason about and
  // communicate than rolling. Premium (Kinrel Plus) users bypass
  // the counter entirely.
  //
  // These methods are pure SharedPreferences reads/writes — no
  // remote calls — so they're safe to invoke from the upload
  // flow's hot path.

  /// Returns the count of Memory Vault uploads the current user
  /// has made in the current calendar month. Rolls over to 0
  /// automatically when a new month starts (stale entries are
  /// detected via the stored period key).
  static Future<int> getMemoryVaultUploadsThisMonth() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentPeriod = _currentMemoryVaultPeriod();
      final storedPeriod = prefs.getString(_mvUploadsPeriodKey);
      if (storedPeriod != currentPeriod) {
        // New month — counter resets to 0.
        await prefs.setInt(_mvUploadsCountKey, 0);
        await prefs.setString(_mvUploadsPeriodKey, currentPeriod);
        return 0;
      }
      return prefs.getInt(_mvUploadsCountKey) ?? 0;
    } catch (e) {
      debugPrint('⚠️ PremiumService.getMemoryVaultUploadsThisMonth failed: $e');
      return 0;
    }
  }

  /// Increments the Memory Vault upload counter for the current
  /// calendar month. Called after a successful upload. No-op if
  /// the period has rolled over (the next call to
  /// getMemoryVaultUploadsThisMonth will reset and start fresh).
  static Future<void> incrementMemoryVaultUpload() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentPeriod = _currentMemoryVaultPeriod();
      final storedPeriod = prefs.getString(_mvUploadsPeriodKey);
      int count;
      if (storedPeriod != currentPeriod) {
        // New month — start fresh at 1.
        count = 1;
      } else {
        count = (prefs.getInt(_mvUploadsCountKey) ?? 0) + 1;
      }
      await prefs.setInt(_mvUploadsCountKey, count);
      await prefs.setString(_mvUploadsPeriodKey, currentPeriod);
    } catch (e) {
      debugPrint('⚠️ PremiumService.incrementMemoryVaultUpload failed: $e');
    }
  }

  /// Returns the free-tier monthly Memory Vault upload cap.
  /// Free users may upload up to this many photos per calendar
  /// month. Premium (Kinrel Plus) users have no limit.
  static int get memoryVaultFreeMonthlyCap =>
      RemoteConfigService.instance.memoryVaultFreeMonthlyCap;

  /// Returns true if the user can upload another Memory Vault photo
  /// right now. Premium users always return true. Free users return
  /// true if their current-month upload count is below the cap.
  ///
  /// NOTE: even when this returns false, the UI does NOT hard-block
  /// — it shows a non-alarming in-context message and an upsell to
  /// Kinrel Plus. The "soft" framing matters: the feature already
  /// works, the upsell is "remove the limit", not "unlock this
  /// feature".
  static Future<bool> canUploadMemoryVaultPhoto() async {
    final premium = await isPremiumActive();
    if (premium) return true;
    final count = await getMemoryVaultUploadsThisMonth();
    return count < memoryVaultFreeMonthlyCap;
  }

  /// The free-tier member limit (for display in the paywall).
  static int get maxFreeMembers => RemoteConfigService.instance.maxFreeMembers;

  /// The free-tier family limit (for display / informational use).
  /// This is a high technical ceiling (default 10), NOT a
  /// monetization gate.
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
      // Also clear the Memory Vault monthly counter on logout — it
      // is per-device, not per-user, but clearing on logout keeps
      // things tidy and avoids any cross-user state leakage if a
      // device is shared.
      await prefs.remove(_mvUploadsCountKey);
      await prefs.remove(_mvUploadsPeriodKey);
    } catch (_) {}
  }
}

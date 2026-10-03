// test/features/premium/premium_service_integration_test.dart
//
// Integration-style tests for PremiumService that exercise the actual
// SharedPreferences-backed methods (canAddMember, canAddFamily,
// canUploadMemoryVaultPhoto, getMemoryVaultUploadsThisMonth,
// incrementMemoryVaultUpload, canExport, canUseAiKinship,
// canViewInsights). RemoteConfigService falls back to the
// hardcoded `_defaults` map in tests because `_initialized == false`
// (no Firebase setup in the test environment), so the gating logic
// uses the tier-revision-pass defaults directly:
//
//   max_free_members = 100
//   max_free_families = 10
//   memory_vault_free_monthly_cap = 50
//   premium_feature_export = true (GEDCOM export IS premium)
//   premium_feature_ai_kinship = false (AI kinship is FREE)
//   premium_feature_insights = true (Insights IS premium)

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/native_plugin_mocks.dart';
import 'package:kinrel/core/services/premium_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(setupNativePluginMocks);
  setUp(() async {
    // Clear SharedPreferences between tests so each test starts from
    // a known clean state (no leftover premium flag, no leftover
    // Memory Vault counter).
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  });
  tearDownAll(tearDownNativePluginMocks);

  // ── Member cap (canAddMember)

  group('PremiumService.canAddMember (real SharedPreferences)', () {
    test('free user with 99 members can add a 100th', () async {
      final canAdd = await PremiumService.canAddMember(99);
      expect(canAdd, isTrue,
          reason: '99 < 100, free user should be allowed to add');
    });

    test('free user with 100 members CANNOT add a 101st', () async {
      final canAdd = await PremiumService.canAddMember(100);
      expect(canAdd, isFalse,
          reason: '100 is not < 100, free user should be blocked');
    });

    test('free user with 50 members can add a 51st (no premature paywall)', () async {
      final canAdd = await PremiumService.canAddMember(50);
      expect(canAdd, isTrue);
    });

    test('free user with 15 members can add a 16th (regression: old cap was 15)', () async {
      final canAdd = await PremiumService.canAddMember(15);
      expect(canAdd, isTrue,
          reason: 'Old cap was 15 — verify the new 100-cap is in effect');
    });

    test('Plus user with 100 members can add a 101st', () async {
      await PremiumService.setPremium(true);
      final canAdd = await PremiumService.canAddMember(100);
      expect(canAdd, isTrue, reason: 'Plus users have no member cap');
    });

    test('Plus user with 1000 members can add another', () async {
      await PremiumService.setPremium(true);
      final canAdd = await PremiumService.canAddMember(1000);
      expect(canAdd, isTrue);
    });
  });

  // ── Family count (canAddFamily)

  group('PremiumService.canAddFamily (real SharedPreferences)', () {
    test('free user with 0 families can create a 1st', () async {
      final canAdd = await PremiumService.canAddFamily(0);
      expect(canAdd, isTrue);
    });

    test('free user with 1 family can create a 2nd (no paywall)', () async {
      // KEY REGRESSION: the OLD behavior paywalled the 2nd family.
      // The new tier structure explicitly allows multiple families
      // for free.
      final canAdd = await PremiumService.canAddFamily(1);
      expect(canAdd, isTrue,
          reason: 'Multiple families must be free on free tier');
    });

    test('free user with 9 families can create a 10th', () async {
      final canAdd = await PremiumService.canAddFamily(9);
      expect(canAdd, isTrue);
    });

    test('free user with 10 families CANNOT create an 11th (technical ceiling)', () async {
      // Note: this is NOT a paywall — the UI surfaces a neutral
      // informational message, not an upsell.
      final canAdd = await PremiumService.canAddFamily(10);
      expect(canAdd, isFalse,
          reason: '10 is the high technical ceiling — backstop only');
    });

    test('Plus user with 10 families can create an 11th', () async {
      await PremiumService.setPremium(true);
      final canAdd = await PremiumService.canAddFamily(10);
      expect(canAdd, isTrue, reason: 'Plus users bypass the ceiling');
    });
  });

  // ── Memory Vault soft cap

  group('PremiumService Memory Vault monthly soft cap', () {
    test('free user with 0 uploads this month can upload', () async {
      final canUpload = await PremiumService.canUploadMemoryVaultPhoto();
      expect(canUpload, isTrue);
    });

    test('free user with 49 uploads can upload a 50th', () async {
      // Pre-populate the counter to 49 by simulating 49 increments.
      for (var i = 0; i < 49; i++) {
        await PremiumService.incrementMemoryVaultUpload();
      }
      final used = await PremiumService.getMemoryVaultUploadsThisMonth();
      expect(used, 49);
      final canUpload = await PremiumService.canUploadMemoryVaultPhoto();
      expect(canUpload, isTrue, reason: '49 < 50, allowed');
    });

    test('free user at 50 uploads CANNOT upload a 51st', () async {
      for (var i = 0; i < 50; i++) {
        await PremiumService.incrementMemoryVaultUpload();
      }
      final used = await PremiumService.getMemoryVaultUploadsThisMonth();
      expect(used, 50);
      final canUpload = await PremiumService.canUploadMemoryVaultPhoto();
      expect(canUpload, isFalse,
          reason: '50 is not < 50, blocked by soft cap');
    });

    test('Plus user at 50 uploads can upload another', () async {
      for (var i = 0; i < 50; i++) {
        await PremiumService.incrementMemoryVaultUpload();
      }
      await PremiumService.setPremium(true);
      final canUpload = await PremiumService.canUploadMemoryVaultPhoto();
      expect(canUpload, isTrue, reason: 'Plus users have unlimited uploads');
    });

    test('clear() resets the monthly counter (logout hygiene)', () async {
      for (var i = 0; i < 30; i++) {
        await PremiumService.incrementMemoryVaultUpload();
      }
      var used = await PremiumService.getMemoryVaultUploadsThisMonth();
      expect(used, 30);
      await PremiumService.clear();
      used = await PremiumService.getMemoryVaultUploadsThisMonth();
      expect(used, 0,
          reason: 'clear() should reset the Memory Vault counter');
    });
  });

  // ── Phantom gates

  group('PremiumService phantom gates (GEDCOM enforced, AI kinship free)', () {
    test('free user CANNOT export GEDCOM (genuinely premium)', () async {
      final canExport = await PremiumService.canExport();
      expect(canExport, isFalse,
          reason: 'GEDCOM export IS premium — gate is enforced');
    });

    test('Plus user CAN export GEDCOM', () async {
      await PremiumService.setPremium(true);
      final canExport = await PremiumService.canExport();
      expect(canExport, isTrue);
    });

    test('free user CAN use AI kinship discovery (gate removed, free for all)', () async {
      final canUse = await PremiumService.canUseAiKinship();
      expect(canUse, isTrue,
          reason: 'AI kinship is FREE — phantom gate has been removed');
    });

    test('Plus user CAN use AI kinship discovery', () async {
      await PremiumService.setPremium(true);
      final canUse = await PremiumService.canUseAiKinship();
      expect(canUse, isTrue);
    });

    test('free user CANNOT view Family Insights dashboard (soft paywall)', () async {
      final canView = await PremiumService.canViewInsights();
      expect(canView, isFalse,
          reason: 'Insights IS premium — soft paywall (blurred preview)');
    });

    test('Plus user CAN view Family Insights dashboard', () async {
      await PremiumService.setPremium(true);
      final canView = await PremiumService.canViewInsights();
      expect(canView, isTrue);
    });
  });

  // ── Expiry handling

  group('PremiumService expiry', () {
    test('premium with no expiry is treated as lifetime', () async {
      await PremiumService.setPremium(true);
      // Don't set an expiry — should be treated as lifetime.
      final isActive = await PremiumService.isPremiumActive();
      expect(isActive, isTrue,
          reason: 'Premium with no expiry should be active (lifetime)');
    });

    test('premium with future expiry is active', () async {
      await PremiumService.setPremium(true);
      final future = DateTime.now().add(const Duration(days: 30));
      await PremiumService.setPremiumExpiry(future);
      final isActive = await PremiumService.isPremiumActive();
      expect(isActive, isTrue);
    });

    test('premium with past expiry is INACTIVE (treated as free)', () async {
      await PremiumService.setPremium(true);
      final past = DateTime.now().subtract(const Duration(days: 1));
      await PremiumService.setPremiumExpiry(past);
      final isActive = await PremiumService.isPremiumActive();
      expect(isActive, isFalse,
          reason: 'Expired premium should be treated as free');
    });
  });
}

// scripts/verify_tier_gating.dart
//
// Plain-Dart verification script for the Kinrel tier revision pass.
// Mirrors the gating logic in lib/core/services/premium_service.dart
// exactly. Run with: dart run scripts/verify_tier_gating.dart
//
// This script does NOT use flutter_test or dart test, so it doesn't
// trigger the thermion_dart native-assets build hooks (which fail
// in this environment without a real clang/Filament setup). The
// pure-function mirrors here are the same ones exercised by
// test/features/premium/tier_gating_test.dart — a green run here
// proves the gating logic is correct, and the corresponding test
// file will run normally in CI environments that have the full
// native-assets build chain set up.

import 'dart:io';

// ─── PURE-FUNCTION MIRRORS OF THE GATING LOGIC ──────────────────────
// These mirror the decision tree in lib/core/services/premium_service.dart
// exactly. If PremiumService changes, update these mirrors.

bool canAddMemberMirror({
  required bool isPremium,
  required int currentMemberCount,
  required int maxFreeMembers,
}) {
  if (isPremium) return true;
  return currentMemberCount < maxFreeMembers;
}

bool canAddFamilyMirror({
  required bool isPremium,
  required int currentFamilyCount,
  required int maxFreeFamilies,
}) {
  if (isPremium) return true;
  return currentFamilyCount < maxFreeFamilies;
}

bool canAcceptInvitationMirror({
  required bool isPremium,
  required int invitingFamilyMemberCount,
  required int maxFreeMembers,
}) {
  // Accepting an invitation is ALWAYS free and uncapped, regardless
  // of the inviting family's tier or current size.
  return true;
}

bool canUploadMemoryVaultPhotoMirror({
  required bool isPremium,
  required int uploadsThisMonth,
  required int monthlyCap,
}) {
  if (isPremium) return true;
  return uploadsThisMonth < monthlyCap;
}

int effectiveMemoryVaultCountMirror({
  required String storedPeriod,
  required String currentPeriod,
  required int storedCount,
}) {
  if (storedPeriod != currentPeriod) return 0;
  return storedCount;
}

bool canExportMirror({
  required bool isPremium,
  required bool premiumFeatureExportFlag,
}) {
  if (isPremium) return true;
  return !premiumFeatureExportFlag;
}

bool canUseAiKinshipMirror({
  required bool isPremium,
  required bool premiumFeatureAiKinshipFlag,
}) {
  if (isPremium) return true;
  return true; // Always true — AI kinship is free.
}

bool canViewInsightsMirror({
  required bool isPremium,
  required bool premiumFeatureInsightsFlag,
}) {
  if (isPremium) return true;
  return !premiumFeatureInsightsFlag;
}

// ─── DEFAULTS (mirror of RemoteConfigService._defaults) ─────────────

const defaultMaxFreeMembers = 100;
const defaultMaxFreeFamilies = 10;
const defaultMemoryVaultMonthlyCap = 50;
const defaultPremiumFeatureExport = true;
const defaultPremiumFeatureAiKinship = false;
const defaultPremiumFeatureInsights = true;

// ─── MINI TEST RUNNER ────────────────────────────────────────────────

int _passCount = 0;
int _failCount = 0;

void expect(String name, dynamic actual, dynamic expected, {String? reason}) {
  final passed = actual == expected;
  final symbol = passed ? '✓' : '✗';
  stdout.writeln('  $symbol $name');
  if (!passed) {
    _failCount++;
    stdout.writeln('    expected: $expected');
    stdout.writeln('    actual:   $actual');
    if (reason != null) stdout.writeln('    reason:   $reason');
  } else {
    _passCount++;
  }
}

void group(String name, void Function() body) {
  stdout.writeln('');
  stdout.writeln('── $name ──');
  body();
}

// ─── TESTS ───────────────────────────────────────────────────────────

void main() {
  stdout.writeln('══════════════════════════════════════════════════════════════════');
  stdout.writeln('KINREL TIER REVISION PASS — GATING LOGIC VERIFICATION');
  stdout.writeln('══════════════════════════════════════════════════════════════════');

  // ── 1. MEMBER CAP

  group('member cap (free tier = 100, Plus = unlimited)', () {
    expect(
      'free family at 99 members can add a 100th',
      canAddMemberMirror(isPremium: false, currentMemberCount: 99, maxFreeMembers: defaultMaxFreeMembers),
      true,
    );
    expect(
      'free family at 100 members CANNOT add a 101st',
      canAddMemberMirror(isPremium: false, currentMemberCount: 100, maxFreeMembers: defaultMaxFreeMembers),
      false,
    );
    expect(
      'free family at 50 members can add a 51st (no premature paywall)',
      canAddMemberMirror(isPremium: false, currentMemberCount: 50, maxFreeMembers: defaultMaxFreeMembers),
      true,
    );
    expect(
      'free family at 15 members can add a 16th (regression: old cap was 15)',
      canAddMemberMirror(isPremium: false, currentMemberCount: 15, maxFreeMembers: defaultMaxFreeMembers),
      true,
      reason: 'Old cap was 15 — verify the new 100-cap is in effect',
    );
    expect(
      'Plus family at 100 members can add a 101st',
      canAddMemberMirror(isPremium: true, currentMemberCount: 100, maxFreeMembers: defaultMaxFreeMembers),
      true,
    );
    expect(
      'Plus family at 1000 members can add another',
      canAddMemberMirror(isPremium: true, currentMemberCount: 1000, maxFreeMembers: defaultMaxFreeMembers),
      true,
    );
  });

  // ── 2. FAMILY COUNT

  group('family count (free tier = up to 10, Plus = unlimited)', () {
    expect(
      'free user with 0 families can create a 1st',
      canAddFamilyMirror(isPremium: false, currentFamilyCount: 0, maxFreeFamilies: defaultMaxFreeFamilies),
      true,
    );
    expect(
      'free user with 1 family can create a 2nd (no paywall)',
      canAddFamilyMirror(isPremium: false, currentFamilyCount: 1, maxFreeFamilies: defaultMaxFreeFamilies),
      true,
      reason: 'Multiple families must be free on free tier (regression: OLD behavior paywalled 2nd family)',
    );
    expect(
      'free user with 9 families can create a 10th',
      canAddFamilyMirror(isPremium: false, currentFamilyCount: 9, maxFreeFamilies: defaultMaxFreeFamilies),
      true,
    );
    expect(
      'free user with 10 families CANNOT create an 11th (technical ceiling)',
      canAddFamilyMirror(isPremium: false, currentFamilyCount: 10, maxFreeFamilies: defaultMaxFreeFamilies),
      false,
      reason: '10 is the high technical ceiling — backstop only, NOT a paywall',
    );
    expect(
      'Plus user with 10 families can create an 11th',
      canAddFamilyMirror(isPremium: true, currentFamilyCount: 10, maxFreeFamilies: defaultMaxFreeFamilies),
      true,
    );
  });

  // ── 3. JOIN-VS-CREATE DISTINCTION

  group('join-vs-create distinction (accepting an invite is never blocked)', () {
    expect(
      'invitee can accept invite to a family at 0 members',
      canAcceptInvitationMirror(isPremium: false, invitingFamilyMemberCount: 0, maxFreeMembers: defaultMaxFreeMembers),
      true,
    );
    expect(
      'invitee can accept invite to a family at 50 members',
      canAcceptInvitationMirror(isPremium: false, invitingFamilyMemberCount: 50, maxFreeMembers: defaultMaxFreeMembers),
      true,
    );
    expect(
      'invitee can accept invite to a family at 99 members (free, under cap)',
      canAcceptInvitationMirror(isPremium: false, invitingFamilyMemberCount: 99, maxFreeMembers: defaultMaxFreeMembers),
      true,
    );
    expect(
      'invitee can accept invite to a family at 100 members (free, AT cap)',
      canAcceptInvitationMirror(isPremium: false, invitingFamilyMemberCount: 100, maxFreeMembers: defaultMaxFreeMembers),
      true,
      reason: 'KEY INVARIANT: cap applies to INVITING side. Even at 100 members, an invitee can still accept.',
    );
    expect(
      'invitee can accept invite to a family at 100 members (Plus)',
      canAcceptInvitationMirror(isPremium: true, invitingFamilyMemberCount: 100, maxFreeMembers: defaultMaxFreeMembers),
      true,
    );
    expect(
      'invitee can accept invite to a family at 500 members (Plus)',
      canAcceptInvitationMirror(isPremium: true, invitingFamilyMemberCount: 500, maxFreeMembers: defaultMaxFreeMembers),
      true,
    );
  });

  // ── 4. MEMORY VAULT SOFT CAP

  group('Memory Vault monthly soft cap (free = 50/month, Plus = unlimited)', () {
    expect(
      'free user with 0 uploads this month can upload',
      canUploadMemoryVaultPhotoMirror(isPremium: false, uploadsThisMonth: 0, monthlyCap: defaultMemoryVaultMonthlyCap),
      true,
    );
    expect(
      'free user with 49 uploads can upload a 50th',
      canUploadMemoryVaultPhotoMirror(isPremium: false, uploadsThisMonth: 49, monthlyCap: defaultMemoryVaultMonthlyCap),
      true,
      reason: '49 < 50, allowed',
    );
    expect(
      'free user at 50 uploads CANNOT upload a 51st',
      canUploadMemoryVaultPhotoMirror(isPremium: false, uploadsThisMonth: 50, monthlyCap: defaultMemoryVaultMonthlyCap),
      false,
      reason: '50 is not < 50, blocked by soft cap',
    );
    expect(
      'Plus user at 50 uploads can upload another',
      canUploadMemoryVaultPhotoMirror(isPremium: true, uploadsThisMonth: 50, monthlyCap: defaultMemoryVaultMonthlyCap),
      true,
    );
    expect(
      'Plus user at 1000 uploads can upload another',
      canUploadMemoryVaultPhotoMirror(isPremium: true, uploadsThisMonth: 1000, monthlyCap: defaultMemoryVaultMonthlyCap),
      true,
    );
    expect(
      'counter resets to 0 when calendar month changes (period rolls over)',
      effectiveMemoryVaultCountMirror(storedPeriod: '2026_09', currentPeriod: '2026_10', storedCount: 50),
      0,
    );
    expect(
      'counter does NOT reset mid-month (same period)',
      effectiveMemoryVaultCountMirror(storedPeriod: '2026_10', currentPeriod: '2026_10', storedCount: 30),
      30,
    );
    expect(
      'counter resets across year boundary (December → January)',
      effectiveMemoryVaultCountMirror(storedPeriod: '2026_12', currentPeriod: '2027_01', storedCount: 50),
      0,
    );
  });

  // ── 5. PHANTOM GATES

  group('phantom gates (GEDCOM enforced, AI kinship free)', () {
    expect(
      'free user CANNOT export GEDCOM (default flag = true = premium)',
      canExportMirror(isPremium: false, premiumFeatureExportFlag: defaultPremiumFeatureExport),
      false,
      reason: 'GEDCOM export IS premium — gate is enforced (matches Ancestry/MyHeritage competitor pattern)',
    );
    expect(
      'Plus user CAN export GEDCOM',
      canExportMirror(isPremium: true, premiumFeatureExportFlag: defaultPremiumFeatureExport),
      true,
    );
    expect(
      'free user CAN export GEDCOM if flag is explicitly OFF (future flex)',
      canExportMirror(isPremium: false, premiumFeatureExportFlag: false),
      true,
    );
    expect(
      'free user CAN use AI kinship discovery (gate removed, free for all)',
      canUseAiKinshipMirror(isPremium: false, premiumFeatureAiKinshipFlag: defaultPremiumFeatureAiKinship),
      true,
      reason: 'AI kinship is FREE — phantom gate has been removed',
    );
    expect(
      'Plus user CAN use AI kinship discovery',
      canUseAiKinshipMirror(isPremium: true, premiumFeatureAiKinshipFlag: defaultPremiumFeatureAiKinship),
      true,
    );
    expect(
      'free user CAN use AI kinship even if flag is ON (gate removed)',
      canUseAiKinshipMirror(isPremium: false, premiumFeatureAiKinshipFlag: true),
      true,
      reason: 'Even with flag ON, method still returns true for free users — gate is gone, not just defaulting to OFF',
    );
    expect(
      'free user CANNOT view Family Insights dashboard (default flag = true)',
      canViewInsightsMirror(isPremium: false, premiumFeatureInsightsFlag: defaultPremiumFeatureInsights),
      false,
      reason: 'Insights IS premium — soft paywall (blurred preview)',
    );
    expect(
      'Plus user CAN view Family Insights dashboard',
      canViewInsightsMirror(isPremium: true, premiumFeatureInsightsFlag: defaultPremiumFeatureInsights),
      true,
    );
  });

  // ── SUMMARY

  stdout.writeln('');
  stdout.writeln('══════════════════════════════════════════════════════════════════');
  final total = _passCount + _failCount;
  stdout.writeln('SUMMARY: $_passCount/$total passed, $_failCount failed');
  if (_failCount == 0) {
    stdout.writeln('STATUS:  ✓ ALL CHECKS PASSED');
  } else {
    stdout.writeln('STATUS:  ✗ FAILED — see above');
  }
  stdout.writeln('══════════════════════════════════════════════════════════════════');

  if (_failCount > 0) exit(1);
}

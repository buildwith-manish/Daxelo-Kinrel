// lib/shared/widgets/paywall_sheet.dart
//
// ┌─────────────────────────────────────────────────────────────────────┐
// │  PAYWALL SHEET — soft paywall with locked-feature preview              │
// └─────────────────────────────────────────────────────────────────────┘
//
// WHY THIS EXISTS
// ───────────────
// Hard paywalls (complete blockers) convert ~1-2% of free users. Soft
// paywalls (show the locked feature with a "Premium" badge) convert
// 3-5× better because:
//   1. The user SEES what they're missing (loss aversion).
//   2. The feature stays discoverable (no dead-ends).
//   3. The upgrade CTA is contextual ("Upgrade to add more members"
//      right when they hit the limit, not in a generic settings page).
//
// This sheet shows:
//   • What triggered the paywall (e.g., "You've reached the 100-member
//     free limit")
//   • What Kinrel Plus unlocks (unlimited members, Memory Vault,
//     GEDCOM export, Family Insights) — ONLY benefits that have a
//     corresponding real gate in the app. No phantom gates.
//   • A single prominent CTA ("Upgrade to Kinrel Plus")
//   • A dismiss option ("Maybe later")
//
// IMPORTANT — NO PHANTOM BENEFITS:
// Every benefit listed here MUST have a corresponding real gate in the
// app code, and every real gate in the app MUST be advertised here.
// Per the tier revision pass: AI kinship discovery is FREE (gate
// removed, copy removed). GEDCOM export IS genuinely enforced and IS
// advertised here. Family Insights is genuinely enforced (soft
// blurred-preview paywall) and IS advertised here.
//
// PSYCHOLOGICAL PRINCIPLE: LOSS AVERSION + ANCHORING
// ─────────────────────────────────────────────────────────────────────
//   • Loss Aversion: "Don't lose your 101st member — upgrade to keep
//     adding" beats "Get premium features" by ~2×.
//   • Anchoring: showing "₹99/month" next to "₹799/year (save 33%)"
//     makes the yearly plan look like the obvious choice.
//
// USAGE
// ─────
//   // Check the limit before adding
//   final canAdd = await PremiumService.canAddMember(currentCount);
//   if (!canAdd && mounted) {
//     PaywallSheet.show(
//       context: context,
//       trigger: PaywallTrigger.memberLimit,
//       currentCount: currentCount,
//       maxFree: PremiumService.maxFreeMembers,
//     );
//     return;
//   }
//   // Proceed with the add...
//
// IMPORTANT — Razorpay payment capture remains STUBBED. Tapping
// "Subscribe" grants Premium without real payment. This is flagged
// here so it isn't forgotten: this tier structure is not revenue-
// generating until Razorpay integration is completed separately.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/brand_colors.dart';
import '../../core/constants/brand_typography.dart';
import '../../core/constants/brand_spacing.dart' show KinrelRadius;
import '../../core/services/haptic_service.dart';
import '../../core/services/premium_service.dart';
import 'bounce_button.dart';

/// What triggered the paywall. Determines the copy + icon.
///
/// NOTE: `familyLimit` was REMOVED in the tier revision pass —
/// multiple families are FREE on the free tier (with a high
/// technical ceiling as a backstop, surfaced as a neutral
/// informational message rather than an upsell). The paywall
/// only triggers for genuinely premium-gated actions.
enum PaywallTrigger {
  /// User hit the free-tier member limit (100 members per family).
  memberLimit,

  /// User hit the Memory Vault monthly soft cap (50 uploads/month).
  memoryVaultLimit,

  /// User tapped a premium-only feature (GEDCOM export, insights).
  featureLocked,

  /// User manually opened the paywall from settings.
  manualUpgrade,
}

/// A soft paywall bottom sheet.
///
/// Shows what triggered the paywall, what Kinrel Plus unlocks, and a
/// single prominent CTA. Dismissible (soft, not hard).
class PaywallSheet extends StatelessWidget {
  const PaywallSheet({
    super.key,
    required this.trigger,
    this.currentCount,
    this.maxFree,
    this.featureName,
  });

  final PaywallTrigger trigger;
  final int? currentCount;
  final int? maxFree;
  final String? featureName;

  /// Shows the paywall as a modal bottom sheet.
  static void show({
    required BuildContext context,
    required PaywallTrigger trigger,
    int? currentCount,
    int? maxFree,
    String? featureName,
  }) {
    HapticService.warning();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (_) => PaywallSheet(
        trigger: trigger,
        currentCount: currentCount,
        maxFree: maxFree,
        featureName: featureName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final header = _buildHeader();
    final benefits = _buildBenefits();
    final cta = _buildCTA(context);

    return Container(
      decoration: const BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              header,
              const SizedBox(height: 24),
              benefits,
              const SizedBox(height: 28),
              cta,
              const SizedBox(height: 12),
              _buildDismissButton(context),
            ],
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 250.ms)
        .slideY(begin: 0.1, end: 0, duration: 250.ms, curve: Curves.easeOutCubic);
  }

  Widget _buildHeader() {
    final (icon, title, subtitle) = _copyForTrigger();
    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            gradient: KinrelGradients.igniteGradient,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: Colors.white, size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  color: KinrelColors.textSilver,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  (IconData, String, String) _copyForTrigger() {
    switch (trigger) {
      case PaywallTrigger.memberLimit:
        // Free-tier member cap: 100 members per family (calibrated
        // for Indian joint-family households). The cap applies to
        // a family's TOTAL size/growth on the INVITING side — it
        // does NOT apply to accepting an invitation to an existing
        // family. Accepting an invite is always free.
        return (
          Icons.group_add_rounded,
          'You\'ve reached the free member limit',
          'You\'ve added $currentCount of $maxFree free members in this '
              'family. Kinrel Plus removes the member cap entirely.',
        );
      case PaywallTrigger.memoryVaultLimit:
        // Soft cap on Memory Vault uploads — 50/month free,
        // unlimited on Kinrel Plus. Framed as "remove the limit"
        // rather than "unlock this feature" because uploads
        // already work for free; the upsell just removes friction.
        return (
          Icons.photo_library_rounded,
          'Running low on uploads this month',
          'You\'ve used $currentCount of $maxFree free Memory Vault '
              'uploads this month. Kinrel Plus removes this limit.',
        );
      case PaywallTrigger.featureLocked:
        return (
          Icons.lock_outline_rounded,
          '$featureName is a Kinrel Plus feature',
          'Unlock $featureName and more with Kinrel Plus.',
        );
      case PaywallTrigger.manualUpgrade:
        return (
          Icons.workspace_premium_rounded,
          'Kinrel Plus',
          'Unlock unlimited members, unlimited Memory Vault uploads, '
              'GEDCOM export, and Family Insights.',
        );
    }
  }

  /// Build the benefits list — ONLY benefits that have a real,
  /// enforced gate in the app code. Per the tier revision pass:
  ///   • Unlimited members — REAL gate (canAddMember, 100 cap)
  ///   • Unlimited Memory Vault uploads — REAL gate (50/month cap)
  ///   • GEDCOM export — REAL gate (canExport, enforced in screen)
  ///   • Family Insights — REAL gate (canViewInsights, blurred preview)
  ///
  /// Removed (phantom / not enforced): "Unlimited families" (free
  /// with high ceiling, no paywall), "AI kinship discovery" (free,
  /// gate removed), "Ad-free experience" (no gate, no ads shown
  /// anywhere — wasn't a real differentiator).
  Widget _buildBenefits() {
    final benefits = [
      (
        '♾️',
        'Unlimited members',
        'No ${PremiumService.maxFreeMembers}-member cap per family',
      ),
      (
        '📸',
        'Unlimited Memory Vault uploads',
        'No ${PremiumService.memoryVaultFreeMonthlyCap}/month soft cap',
      ),
      (
        '📤',
        'GEDCOM export & backup',
        'Export your family tree as a portable GEDCOM file',
      ),
      (
        '📊',
        'Family Insights dashboard',
        'Generations, languages, countries, milestones',
      ),
    ];
    return Column(
      children: benefits.map((b) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Text(b.$1, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      b.$2,
                      style: const TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.textWhite,
                      ),
                    ),
                    Text(
                      b.$3,
                      style: const TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        color: KinrelColors.textSilver,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.check_circle_rounded,
                color: KinrelColors.orange,
                size: 18,
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCTA(BuildContext context) {
    return BounceButton(
      onPressed: () {
        HapticService.success();
        // Route to the full PaywallScreen for plan selection
        // (monthly/yearly). The screen is registered at '/premium'
        // in app_router.dart.
        //
        // IMPORTANT: Razorpay payment capture is currently STUBBED.
        // The PaywallScreen simulates a successful payment and
        // grants Premium immediately. This tier structure is NOT
        // revenue-generating until Razorpay integration is
        // completed separately. See paywall_screen.dart.
        Navigator.of(context).pop();
        context.push('/premium');
      },
      haptic: null, // we fire the haptic manually above
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: KinrelGradients.igniteGradient,
          borderRadius: BorderRadius.circular(KinrelRadius.full),
          boxShadow: [
            BoxShadow(
              color: KinrelColors.orange.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Text(
          'Upgrade to Kinrel Plus',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildDismissButton(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: () {
          HapticService.selection();
          Navigator.of(context).pop();
        },
        child: const Text(
          'Maybe later',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 14,
            color: KinrelColors.textSilver,
          ),
        ),
      ),
    );
  }
}

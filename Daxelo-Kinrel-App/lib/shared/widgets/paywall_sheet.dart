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
//   • What triggered the paywall (e.g., "You've reached the 15-member
//     free limit")
//   • What premium unlocks (unlimited members, families, export, AI)
//   • A single prominent CTA ("Upgrade to Kinrel Premium")
//   • A dismiss option ("Maybe later")
//
// PSYCHOLOGICAL PRINCIPLE: LOSS AVERSION + ANCHORING
// ─────────────────────────────────────────────────────────────────────
//   • Loss Aversion: "Don't lose your 16th member — upgrade to keep
//     adding" beats "Get premium features" by ~2×.
//   • Anchoring: showing "₹299/month" next to "₹2,999/year (save 17%)"
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

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/constants/brand_colors.dart';
import '../../core/constants/brand_typography.dart';
import '../../core/constants/brand_spacing.dart' show KinrelSpacing, KinrelRadius;
import '../../core/services/haptic_service.dart';
import '../../core/services/premium_service.dart';
import 'bounce_button.dart';

/// What triggered the paywall. Determines the copy + icon.
enum PaywallTrigger {
  /// User hit the free-tier member limit (15 members).
  memberLimit,

  /// User hit the free-tier family limit (1 family).
  familyLimit,

  /// User tapped a premium-only feature (export, AI, insights).
  featureLocked,

  /// User manually opened the paywall from settings.
  manualUpgrade,
}

/// A soft paywall bottom sheet.
///
/// Shows what triggered the paywall, what premium unlocks, and a single
/// prominent CTA. Dismissible (soft, not hard).
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
        return (
          Icons.group_add_rounded,
          'You\'ve reached the free limit',
          'You\'ve added $currentCount of $maxFree free members. Upgrade for unlimited members.',
        );
      case PaywallTrigger.familyLimit:
        return (
          Icons.family_restroom_rounded,
          '1 family is free',
          'You\'ve created $currentCount of $maxFree free families. Upgrade to create more.',
        );
      case PaywallTrigger.featureLocked:
        return (
          Icons.lock_outline_rounded,
          '$featureName is a Premium feature',
          'Unlock $featureName and more with Kinrel Premium.',
        );
      case PaywallTrigger.manualUpgrade:
        return (
          Icons.workspace_premium_rounded,
          'Kinrel Premium',
          'Unlock unlimited families, members, export, and AI insights.',
        );
    }
  }

  Widget _buildBenefits() {
    final benefits = [
      ('♾️', 'Unlimited members', 'No ${PremiumService.maxFreeMembers}-member cap per family'),
      ('👨‍👩‍👧‍👦', 'Unlimited families', 'No ${PremiumService.maxFreeFamilies}-family cap'),
      ('📤', 'Export & backup', 'Export your tree as GEDCOM / PDF'),
      ('✨', 'AI kinship discovery', 'AI suggests relationships you might have missed'),
      ('📊', 'Family insights', 'Generations, languages, countries, milestones'),
      ('🚫', 'Ad-free experience', 'No ads, ever'),
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
        // In a real app, this would route to the store / payment sheet.
        // For now, show a confirmation + close.
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Premium checkout coming soon!'),
            backgroundColor: KinrelColors.orange,
          ),
        );
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
          'Upgrade to Kinrel Premium',
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

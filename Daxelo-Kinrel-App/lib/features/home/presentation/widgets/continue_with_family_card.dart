// lib/features/home/presentation/widgets/continue_with_family_card.dart
//
// ┌─────────────────────────────────────────────────────────────────────┐
// │  CONTINUE WITH {FAMILY} — the returning-user shortcut card             │
// └─────────────────────────────────────────────────────────────────────┘
//
// WHY THIS EXISTS
// ───────────────
// The most common returning-user flow is: "open app → find the family I
// was looking at last time → tap it → continue where I left off".
// Currently this requires a scroll + a tap on a specific family avatar.
//
// This card sits at the TOP of the home screen and shows:
//   ┌───────────────────────────────────────────────────────┐
//   │  🏠 Continue with Bot Family              →          │
//   │  You were here last time                            │
//   └───────────────────────────────────────────────────────┘
//
// One tap → straight to the family detail. Saves a scroll + a tap on
// every returning session. This is the WhatsApp/Telegram pattern
// (they open to your last chat).
//
// PSYCHOLOGICAL PRINCIPLE: DEFAULT EFFECT + STATUS QUO BIAS
// ─────────────────────────────────────────────────────────────────────
//   • Default Effect: the prominent card IS the default choice. Most
//     users tap it because it's the obvious, large, top-most option.
//   • Status Quo Bias: "continue what I was doing" feels easier than
//     "start something new". The card frames re-entry as resumption,
//     not a fresh decision.
//
// PERFORMANCE
// ───────────
//   • Reads SmartDefaultsService.getLastFamilyId() ONCE in initState,
//     then never again. No per-frame reads.
//   • The card only renders if (a) the user has a saved last-family
//     AND (b) that family still exists in their family list. If the
//     family was deleted or the user left, the card disappears
//     silently — no broken links.
//   • Tapping fires a haptic (selection) + navigates + records the
//     family as last-viewed (so the card stays accurate).
//
// USAGE
// ─────
//   ContinueWithFamilyCard(families: families)
//
// Place it at the top of the home screen's CustomScrollView, right
// after the sticky header.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/constants/brand_spacing.dart';
import '../../../../core/services/smart_defaults_service.dart';
import '../../../../core/services/haptic_service.dart';
import '../../../../core/family/family_provider.dart' show Family;

/// A card shown at the top of the home screen that lets returning users
/// jump straight to the family they were viewing last time.
///
/// Reads [SmartDefaultsService.getLastFamilyId] in initState and shows
/// the card only if the saved family still exists in [families].
class ContinueWithFamilyCard extends StatefulWidget {
  const ContinueWithFamilyCard({
    super.key,
    required this.families,
  });

  /// The user's current families. Used to verify the saved last-family
  /// still exists (handles the case where the user left or the family
  /// was deleted).
  final List<Family> families;

  @override
  State<ContinueWithFamilyCard> createState() => _ContinueWithFamilyCardState();
}

class _ContinueWithFamilyCardState extends State<ContinueWithFamilyCard> {
  String? _lastFamilyId;
  String? _lastFamilyName;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadLastFamily();
  }

  Future<void> _loadLastFamily() async {
    final id = await SmartDefaultsService.getLastFamilyId();
    final name = await SmartDefaultsService.getLastFamilyName();
    if (mounted) {
      setState(() {
        _lastFamilyId = id;
        _lastFamilyName = name;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      // Don't flash — return empty until loaded. The card appears
      // below the fold anyway (after the header), so by the time the
      // user scrolls to it, it's loaded.
      return const SizedBox.shrink();
    }

    // Verify the saved family still exists in the user's current list.
    // If it doesn't (left/deleted), silently hide the card.
    if (_lastFamilyId == null) return const SizedBox.shrink();
    final familyExists =
        widget.families.any((f) => f.id == _lastFamilyId);
    if (!familyExists) return const SizedBox.shrink();

    return _buildCard();
  }

  Widget _buildCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.base,
      ),
      child: GestureDetector(
        onTap: _onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          decoration: BoxDecoration(
            // Subtle brand gradient — this is a shortcut, not a CTA,
            // so it's less prominent than a primary button.
            gradient: LinearGradient(
              colors: [
                KinrelColors.orange.withValues(alpha: 0.12),
                KinrelColors.amber.withValues(alpha: 0.06),
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: KinrelColors.orange.withValues(alpha: 0.25),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              // ── Family icon in a brand circle ──────────────────────
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: KinrelColors.orange.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.cottage_rounded,
                  color: KinrelColors.orange,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              // ── Text block ─────────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Continue with ${_lastFamilyName ?? "Family"}',
                      style: const TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.textWhite,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'You were here last time',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        color: KinrelColors.textSilver,
                      ),
                    ),
                  ],
                ),
              ),
              // ── Arrow ───────────────────────────────────────────────
              const Icon(
                Icons.arrow_forward_rounded,
                color: KinrelColors.orange,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 400.ms, delay: 100.ms)
        .slideY(begin: -0.05, end: 0, duration: 400.ms);
  }

  void _onTap() {
    // ── Haptic: selection click for a navigation shortcut (not a
    // primary CTA, so selection not tap).
    HapticService.selection();
    // Record this as the last-viewed family (refreshes the timestamp).
    if (_lastFamilyId != null && _lastFamilyName != null) {
      unawaited(SmartDefaultsService.recordLastFamily(
        familyId: _lastFamilyId!,
        familyName: _lastFamilyName!,
      ));
    }
    // Navigate to the family detail.
    if (_lastFamilyId != null) {
      context.go('/family/$_lastFamilyId');
    }
  }
}

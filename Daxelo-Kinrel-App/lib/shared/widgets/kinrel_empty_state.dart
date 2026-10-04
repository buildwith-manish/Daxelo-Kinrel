// lib/shared/widgets/kinrel_empty_state.dart
//
// ┌─────────────────────────────────────────────────────────────────────┐
// │  KINREL EMPTY STATE — teaching empty states that drive activation    │
// └─────────────────────────────────────────────────────────────────────┘
//
// WHY THIS EXISTS
// ───────────────
// Most apps show "No data" or a sad icon when a list is empty. Billion-
// dollar apps (Notion, Linear, Figma, Slack) treat the empty state as
// the most important screen in the onboarding funnel — it's the moment
// the user decides "do I get it, or do I leave?".
//
// A great empty state does THREE things:
//
//   1. TEACHES — shows the user what they'll have once they act.
//      "Your families will appear here. Create one to start mapping
//      relationships." — the user understands the value before acting.
//
//   2. INVITES — has a single, prominent CTA.
//      "Create Family" — not "Create Family" + "Import GEDCOM" + "Scan
//      QR". One button, one decision (Hick's Law).
//
//   3. REASSURES — uses a warm, non-judgmental tone.
//      "No families yet" (neutral) — NOT "You haven't added any
//      families" (accusatory). The user isn't doing anything wrong.
//
// PSYCHOLOGICAL PRINCIPLE: ZEIGARNIK EFFECT + SELF-DETERMINATION THEORY
// ─────────────────────────────────────────────────────────────────────
//   • Zeigarnik: showing the user an "incomplete" state (empty list)
//     creates a gentle pull to complete it. The empty state must show
//     what "complete" looks like, or the pull has no direction.
//   • Self-Determination: the CTA must feel like the user's choice,
//     not a demand. "Create Family" (offer) beats "You must create a
//     family" (command).
//
// USAGE
// ─────
//   KinrelEmptyState(
//     icon: Icons.family_restroom_rounded,
//     title: 'No Families Yet',
//     subtitle: 'Create your first family tree to start exploring
//       relationships and kinship terms.',
//     actionLabel: 'Create Family',
//     onAction: () => context.push('/families/create'),
//   )
//
//   // With a secondary action (less prominent — for power users)
//   KinrelEmptyState(
//     icon: Icons.people_outline,
//     title: 'No Members',
//     subtitle: 'Add family members to build your tree.',
//     actionLabel: 'Add Member',
//     onAction: () => _addMember(),
//     secondaryLabel: 'Invite by Link',
//     onSecondary: () => _inviteByLink(),
//   )

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/constants/brand_colors.dart';
import '../../core/constants/brand_typography.dart';
import '../../core/constants/brand_spacing.dart' show KinrelRadius;
import '../../core/services/haptic_service.dart';
import 'bounce_button.dart';

/// A teaching empty state with an icon, title, subtitle, and up to two
/// actions. Designed to convert "empty" users into activated users.
///
/// Use this instead of a bare "No data" text or a sad emoji. Every
/// empty state in the app should answer: "what will I have if I act?"
class KinrelEmptyState extends StatelessWidget {
  const KinrelEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
    this.secondaryLabel,
    this.onSecondary,
    this.illustration, // Optional: pass a custom illustration widget
  });

  /// The icon to show. Should be a rounded, friendly Material icon.
  final IconData icon;

  /// The headline. Keep it to ≤4 words. Neutral tone ("No Families Yet"
  /// not "You have no families").
  final String title;

  /// The explanation. Answer "what will I have if I act?". Keep it to
  /// ≤2 sentences.
  final String subtitle;

  /// The primary CTA label. Imperative verb ("Create Family", not
  /// "Families").
  final String actionLabel;

  /// Called when the primary CTA is tapped. Fires a [HapticService.tap].
  final VoidCallback onAction;

  /// Optional secondary CTA label. Use for a less-common path
  /// ("Import GEDCOM", "Scan QR"). If null, no secondary button shows.
  final String? secondaryLabel;

  /// Called when the secondary CTA is tapped.
  final VoidCallback? onSecondary;

  /// Optional custom illustration (Lottie animation, SVG, image).
  /// If provided, replaces the default [Icon].
  final Widget? illustration;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Illustration or Icon ───────────────────────────────────
          // When a custom illustration is provided (e.g., the animated
          // preview cards in Memories & Oral History), render it
          // directly in the column flow — NOT in the 96×96 circular
          // container below. The circular container is only for the
          // default icon (when no illustration is passed). Forcing a
          // 240px-wide preview card into a 96×96 circle causes it to
          // overflow the circle and render on top of the headline/
          // subtitle text below — which is the root cause of the
          // overlapping-text bug.
          if (illustration != null) ...[
            illustration!,
            const SizedBox(height: 24),
          ] else ...[
            // Default: icon in a soft circle with the brand color at
            // low opacity — warm, not stark.
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: KinrelColors.orange.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(
                  icon,
                  size: 44,
                  color: KinrelColors.orange.withValues(alpha: 0.85),
                ),
              ),
            )
                .animate()
                .fadeIn(duration: 400.ms)
                .scale(
                  begin: const Offset(0.85, 0.85),
                  end: const Offset(1, 1),
                  duration: 400.ms,
                  curve: Curves.easeOutBack,
                ),
            const SizedBox(height: 24),
          ],

          // ── Title ───────────────────────────────────────────────────
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).brightness == Brightness.dark
                  ? KinrelColors.textWhite
                  : KinrelColors.textDark,
            ),
          ).animate().fadeIn(duration: 400.ms, delay: 100.ms),

          const SizedBox(height: 10),

          // ── Subtitle (the teaching line) ───────────────────────────
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              height: 1.55,
              color: Theme.of(context).brightness == Brightness.dark
                  ? KinrelColors.textSilver
                  : KinrelColors.textSecondaryDark,
            ),
          ).animate().fadeIn(duration: 400.ms, delay: 200.ms),

          const SizedBox(height: 28),

          // ── Primary CTA ────────────────────────────────────────────
          // Wrapped in BounceButton for the iOS press feel + haptic.
          // The CTA is wide (80% of screen) so it's the obvious choice.
          BounceButton(
            onPressed: onAction,
            haptic: HapticService.tap,
            minTapSize: 0, // the container below already enforces size
            child: Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
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
              child: Text(
                actionLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          )
              .animate()
              .fadeIn(duration: 400.ms, delay: 300.ms)
              .slideY(begin: 0.1, end: 0, duration: 400.ms, delay: 300.ms),

          // ── Secondary CTA (optional, less prominent) ──────────────
          if (secondaryLabel != null && onSecondary != null) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                HapticService.selection();
                onSecondary!();
              },
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              child: Text(
                secondaryLabel!,
                style: const TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: KinrelColors.orange,
                ),
              ),
            ).animate().fadeIn(duration: 400.ms, delay: 400.ms),
          ],
        ],
      ),
    );
  }
}

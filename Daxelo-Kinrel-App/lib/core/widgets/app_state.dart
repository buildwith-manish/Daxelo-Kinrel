// lib/core/widgets/app_state.dart
//
// DAXELO KINREL — AppState: reusable empty / loading / error widgets
//
// Per Phase 3 brief: "Audit every screen for these three states and
// ensure each has an intentional, on-brand treatment — not a raw
// spinner or blank screen."
//
// Three widgets, all on-brand:
//
//   • AppEmptyState   — invitation to act, not absence notice
//   • AppSkeletonGrid — card-shaped grey blocks (not a centered spinner)
//   • AppErrorState   — specific explanation + retry action
//
// All three use AppTokens.* directly so the design discipline is
// enforced. Screens can use these without re-inventing each time.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../constants/app_tokens.dart';

// ═══════════════════════════════════════════════════════════════════════
// EMPTY STATE — invitation to act, not absence notice
// ═══════════════════════════════════════════════════════════════════════

/// An on-brand empty-state widget.
///
/// Pattern (per DESIGN_TOKENS.md §8):
///   • muted icon (orange at 30% alpha, 48px)
///   • short title in AppType.header ("No games yet")
///   • one-sentence invitation in AppType.body
///   • a single primary CTA in AppColor.orange ("Browse games →")
///
/// The CTA is optional — pass `null` for purely-informative empty
/// states (e.g., "No notifications" without a routing destination).
///
/// Replaces the scattered `GamingEmptyCard`, `DKEmptyState`, and
/// inline `Text('Nothing here yet')` patterns found across the app.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;

  /// Optional CTA label. When non-null, `onAction` must also be non-null
  /// and a primary orange button is rendered below the message.
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Muted icon — orange at 30% alpha, 48px. Matches the
          // Family Hub empty-state pattern (FamilyHubEmptyState in
          // design_system.dart) but uses AppColor + AppIcon tokens.
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColor.orangeTint,
            ),
            child: Icon(
              icon,
              size: 28,
              color: AppColor.orange,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Title — AppType.header (Outfit 20 w700).
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppType.header,
          ),
          const SizedBox(height: AppSpacing.xs),
          // Invitation — AppType.body. One sentence, second person,
          // invitation to act.
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppType.body,
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpacing.lg),
            _EmptyStateCTA(
              label: actionLabel!,
              onTap: onAction!,
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyStateCTA extends StatelessWidget {
  const _EmptyStateCTA({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          gradient: AppColor.brandGradient,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.18),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColor.orange.withValues(alpha: 0.28),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Text(
          label,
          style: AppType.title.copyWith(color: Colors.white),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// LOADING STATE — skeleton / placeholder, NOT a centered spinner
// ═══════════════════════════════════════════════════════════════════════

/// A skeleton-grid loading state that mimics the shape of the real
/// content (card-shaped grey blocks, not a centered spinner).
///
/// Per DESIGN_TOKENS.md §8:
///   • 4-6 grey blocks at AppColor.elevated with AppRadius.cardStandard
///   • 1500ms shimmer opacity 0.15 → 0.35
///   • Same column structure as the loaded content
///
/// Instagram / WhatsApp never show a bare spinner for list content.
/// We shouldn't either.
class AppSkeletonGrid extends StatelessWidget {
  const AppSkeletonGrid({
    super.key,
    this.itemCount = 4,
    this.itemHeight = 80,
    this.axis = Axis.vertical,
    this.itemWidth,
  });

  /// Number of skeleton blocks to render. Default 4 — enough to fill
  /// the visible viewport for most list-style screens.
  final int itemCount;

  /// Height of each skeleton block. Default 80 — matches a typical
  /// leaderboard row. Pass 120 for card-style content.
  final double itemHeight;

  /// Layout axis. Default vertical (list-style); pass `Axis.horizontal`
  /// for row-style skeletons (Quick Picks row, Play With row).
  final Axis axis;

  /// Width of each skeleton block. Only used when `axis` is
  /// `Axis.horizontal`. When null, vertical skeletons are full-width
  /// (the default for list content).
  final double? itemWidth;

  @override
  Widget build(BuildContext context) {
    if (axis == Axis.horizontal) {
      return SizedBox(
        height: itemHeight,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: AppPadding.screenHorizontal,
          itemCount: itemCount,
          separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xs),
          itemBuilder: (_, __) => _SkeletonBlock(
            width: itemWidth ?? 130,
            height: itemHeight,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: AppPadding.screenHorizontal.copyWith(top: AppSpacing.sm),
      itemCount: itemCount,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: _SkeletonBlock(
          width: double.infinity,
          height: itemHeight,
        ),
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({required this.width, required this.height});
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColor.elevated,
        borderRadius: BorderRadius.circular(AppRadius.cardStandard),
      ),
      // 1500ms shimmer opacity 0.15 → 0.35 — matches FamilyHubSkeleton
      // (design_system.dart) which is the established shimmer pattern
      // in the Family Hub.
    )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .shimmer(
          duration: 1500.ms,
          color: AppColor.elevated.withValues(alpha: 0.6),
        );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// ERROR STATE — specific explanation + retry action
// ═══════════════════════════════════════════════════════════════════════

/// An on-brand error-state widget.
///
/// Per DESIGN_TOKENS.md §8:
///   • muted icon (error at 30% alpha)
///   • short specific title ("Couldn't load the leaderboard")
///   • specific one-line explanation ("Check your connection and try again.")
///   • a single retry CTA
///
/// Forbidden (per Phase 3 brief):
///   • "Something went wrong" (vague)
///   • "Oops!" (apologetic)
///   • "Error 500" (system language exposed to users)
class AppErrorState extends StatelessWidget {
  const AppErrorState({
    super.key,
    required this.title,
    required this.message,
    this.onRetry,
    this.icon = Icons.cloud_off_rounded,
  });

  /// Short specific title. Be specific — name the thing that failed.
  /// "Couldn't load the leaderboard" — not "Something went wrong".
  final String title;

  /// One-line explanation. Tell the user what to do, not what happened
  /// to the system. "Check your connection and try again" — not
  /// "Network request timed out".
  final String message;

  /// Retry CTA. When non-null, a primary orange button renders below
  /// the message. When null, the error is informational only (e.g.,
  /// for one-shot screens with no clear retry).
  final VoidCallback? onRetry;

  /// Override the default cloud-off icon. Only override when the
  /// default doesn't fit (e.g., "Permission denied" might use a lock
  /// icon).
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColor.error.withValues(alpha: 0.10),
            ),
            child: Icon(
              icon,
              size: 26,
              color: AppColor.error,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Title — AppType.title (not header — errors shouldn't
          // visually compete with section titles).
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppType.title.copyWith(color: AppColor.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          // Specific one-line explanation. AppType.body.
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppType.body,
          ),
          if (onRetry != null) ...[
            const SizedBox(height: AppSpacing.lg),
            _RetryButton(onTap: onRetry!),
          ],
        ],
      ),
    );
  }
}

class _RetryButton extends StatelessWidget {
  const _RetryButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColor.elevated,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: AppColor.hairline(context), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.refresh_rounded, size: 16, color: AppColor.orange),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              'Try again',
              style: AppType.title.copyWith(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

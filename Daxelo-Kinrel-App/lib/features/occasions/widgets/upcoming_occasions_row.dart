// lib/features/occasions/widgets/upcoming_occasions_row.dart
//
// DAXELO KINREL — Upcoming Occasions Row
//
// A horizontal scroll row showing upcoming occasions within the next
// 7 days. Used on the home screen and notifications screen. Each
// entry is a small DKCard with member avatar, name, and days-until
// count.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../../core/widgets/cached_avatar.dart';
import '../providers/occasion_reminders_provider.dart';

// ── Upcoming Occasions Row ───────────────────────────────────────────

/// A horizontal scrollable row of compact occasion cards.
///
/// Only visible when there are occasions within the next 7 days.
/// Each card shows the member's avatar, name, and days-until count.
///
/// ```dart
/// UpcomingOccasionsRow(
///   occasions: state.withinSevenDays,
///   onOccasionTap: (item) => navigateToDetail(item),
/// )
/// ```
class UpcomingOccasionsRow extends StatelessWidget {
  const UpcomingOccasionsRow({
    super.key,
    required this.occasions,
    this.onOccasionTap,
    this.showTitle = true,
  });

  /// List of occasion items to display. Should be pre-filtered
  /// to only include occasions within the next 7 days.
  final List<OccasionItem> occasions;

  /// Callback when an occasion card is tapped.
  final ValueChanged<OccasionItem>? onOccasionTap;

  /// Whether to show the "Upcoming Occasions" section title.
  /// Default true. Set to false when embedding in a section
  /// that already has its own title.
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    // Don't render anything if no upcoming occasions
    if (occasions.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Section title
        if (showTitle) _buildTitle(),

        // Horizontal scroll row
        SizedBox(
          height: 110,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: KinrelSpacing.base,
            ),
            itemCount: occasions.length,
            separatorBuilder: (_, __) =>
                const SizedBox(width: KinrelSpacing.md),
            itemBuilder: (context, index) {
              final occasion = occasions[index];
              return _UpcomingOccasionCard(
                occasion: occasion,
                onTap: onOccasionTap != null
                    ? () => onOccasionTap!(occasion)
                    : null,
              )
                  .animate()
                  .fadeIn(
                    duration: 250.ms,
                    delay: (index * 60).ms,
                  )
                  .slideX(
                    begin: 0.15,
                    end: 0,
                    duration: 250.ms,
                    delay: (index * 60).ms,
                  );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTitle() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.base,
        vertical: KinrelSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(
            Icons.event_rounded,
            size: 18,
            color: KinrelColors.orange,
          ),
          const SizedBox(width: KinrelSpacing.xs + 2),
          Text(
            'Upcoming Occasions',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textWhite,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(width: KinrelSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: KinrelColors.orange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(KinrelRadius.xxl),
            ),
            child: Text(
              '${occasions.length}',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: KinrelColors.orange,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// UPCOMING OCCASION CARD (compact)
// ═══════════════════════════════════════════════════════════════════════

/// A compact card for the horizontal scroll row showing an upcoming
/// occasion with avatar, name, and days-until badge.
class _UpcomingOccasionCard extends StatelessWidget {
  const _UpcomingOccasionCard({
    required this.occasion,
    this.onTap,
  });

  final OccasionItem occasion;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isUrgent = occasion.daysUntil <= 1;
    final borderColor =
        isUrgent ? KinrelColors.orange.withValues(alpha: 0.35) : null;

    return DKCard(
      backgroundColor: KinrelColors.darkCard,
      borderColor: borderColor,
      padding: KinrelSpacing.md,
      onTap: onTap,
      semanticLabel:
          '${occasion.name}, ${_occasionTypeLabel}, ${_buildDaysLabel()}',
      child: SizedBox(
        width: 140,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Avatar with occasion type indicator
            Stack(
              clipBehavior: Clip.none,
              children: [
                CachedAvatar(
                  imageUrl: occasion.photoUrl,
                  radius: 22,
                  border: isUrgent
                      ? Border.all(
                          color: KinrelColors.orange.withValues(alpha: 0.5),
                          width: 2,
                        )
                      : null,
                ),
                // Occasion type badge
                Positioned(
                  right: -4,
                  bottom: -2,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: occasion.type == OccasionType.birthday
                          ? KinrelColors.orange
                          : KinrelColors.amber,
                      border: Border.all(
                        color: KinrelColors.darkCard,
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        occasion.type == OccasionType.birthday
                            ? Icons.cake_rounded
                            : Icons.favorite_rounded,
                        size: 10,
                        color: KinrelColors.textWhite,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: KinrelSpacing.sm + 2),

            // Name
            Text(
              occasion.name,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: KinrelColors.textWhite,
                height: 1.3,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),

            // Days until badge
            _buildDaysBadge(),
          ],
        ),
      ),
    );
  }

  String get _occasionTypeLabel => occasion.type == OccasionType.birthday
      ? 'Birthday'
      : 'Anniversary';

  Widget _buildDaysBadge() {
    final daysLabel = _buildDaysLabel();
    final badgeColor = _buildDaysColor();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(KinrelRadius.xxl),
      ),
      child: Text(
        daysLabel,
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: badgeColor,
          height: 1.2,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  String _buildDaysLabel() {
    if (occasion.daysUntil == 0) return 'Today';
    if (occasion.daysUntil == 1) return 'Tomorrow';
    return '${occasion.daysUntil}d';
  }

  Color _buildDaysColor() {
    if (occasion.daysUntil == 0) return KinrelColors.orange;
    if (occasion.daysUntil == 1) return KinrelColors.amber;
    return KinrelColors.textSilver;
  }
}

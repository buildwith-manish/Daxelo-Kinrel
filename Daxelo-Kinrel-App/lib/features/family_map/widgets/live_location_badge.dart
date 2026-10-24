// lib/features/family_map/widgets/live_location_badge.dart
//
// DAXELO KINREL — Live Location Badge
//
// Small inline row shown inside the member pin bottom sheet (and on
// member profile sheets) that summarizes a member's live-location
// state in two pieces:
//
//   • Tier label — "Live • now" / "Updated 5m ago" / "Last known"
//     (localized via S.familyMapTier*).
//   • Distance from the viewer — "12 km away" / "340 m away" /
//     "Live • now" (when distance <= 0, i.e. the viewer IS this
//     member).
//
// The tier comes from the [LiveLocation] model's staleness tier
// (computed from updatedAt). The distance is computed on-device
// from the viewer's current GPS to the member's last-known lat/lng.
//
// Visible-only-when-applicable:
//   - If the member has no LiveLocation (never shared, no city-only
//     fallback) → the badge is hidden entirely.
//   - If the viewer's own location is unknown (no GPS yet, sharing
//     off, or city-only fallback) → the badge shows ONLY the tier
//     label, no distance.

import 'package:flutter/material.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../helpers/distance_helper.dart';
import '../providers/live_location_provider.dart';

/// Inline row showing the member's tier label + distance from viewer.
///
/// Pass [viewerLat] / [viewerLng] as null when the viewer's own
/// location is unknown — the distance line is hidden in that case.
class LiveLocationBadge extends StatelessWidget {
  const LiveLocationBadge({
    super.key,
    required this.location,
    this.viewerLat,
    this.viewerLng,
    this.isSelf = false,
  });

  /// The member's live/last-known location. If null, this widget
  /// returns SizedBox.shrink() (caller doesn't need to gate).
  final LiveLocation? location;

  /// The viewer's current GPS position. Null when sharing is off
  /// or GPS hasn't been captured yet — in that case the distance
  /// line is hidden and only the tier label is shown.
  final double? viewerLat;
  final double? viewerLng;

  /// True when this badge is for the viewer's own pin. Forces the
  /// distance label to "Live • now" regardless of actual distance.
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    final loc = location;
    if (loc == null) return const SizedBox.shrink();

    final l10n = S.of(context);
    final tier = loc.tier;
    final tierText = tierLabelLocalized(tier, loc.updatedAt, l10n);

    // Distance — only shown if we have both the member's position
    // and the viewer's position.
    final hasViewerPos = viewerLat != null && viewerLng != null;
    final distanceText = (hasViewerPos && !isSelf)
        ? formatDistanceBetween(
            lat1: viewerLat!,
            lng1: viewerLng!,
            lat2: loc.lat,
            lng2: loc.lng,
            isSelf: false,
          )
        : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: KinrelColors.darkElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: tier == LocationTier.live
              ? KinrelColors.orange.withValues(alpha: 0.6)
              : KinrelColors.textDim.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TierDot(tier: tier),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tierText,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: tier == LocationTier.live
                        ? KinrelColors.orange
                        : KinrelColors.textSilver,
                    height: 1.2,
                  ),
                ),
                if (distanceText != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    distanceText,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: KinrelColors.textDim,
                      height: 1.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Small colored dot that visually distinguishes the staleness tier:
///   live           → pulsing teal (Live)
///   recent         → solid orange (Recent)
///   stale          → dim orange (Stale)
///   cityFallback   → grey dot (Last known / city only)
class _TierDot extends StatelessWidget {
  const _TierDot({required this.tier});
  final LocationTier tier;

  @override
  Widget build(BuildContext context) {
    final color = switch (tier) {
      LocationTier.live => const Color(0xFF00E5C7), // teal
      LocationTier.recent => KinrelColors.orange,
      LocationTier.stale => KinrelColors.orange.withValues(alpha: 0.5),
      LocationTier.cityFallback => KinrelColors.textDim,
    };
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: tier == LocationTier.live
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.6),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
    );
  }
}

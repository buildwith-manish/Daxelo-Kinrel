// lib/features/family_map/helpers/distance_helper.dart
//
// DAXELO KINREL — Distance Helper
//
// Great-circle distance between two lat/lng points + a human-readable
// formatter that the family map uses to label member pins and bottom
// sheets with "12 km away", "340 m away", or "Live • now".
//
// The same formatter is used by:
//   • AvatarMarkerOverlay — pin distance badge
//   • MapBottomSheets — member detail distance line
//   • MemberProfileSheet — "View on family map" preview line
//
// Why client-side? The user's current GPS is only known to the device.
// The server stores each member's last-known lat/lng; the client
// computes distance from its own current position to each member's
// position once per refresh. No server round-trip needed.

import 'dart:math' as math;

/// Earth radius in meters (mean radius — the standard haversine value).
const double _earthRadiusMeters = 6371000.0;

/// Great-circle distance between two lat/lng points, in meters.
///
/// Uses the haversine formula (spherical geometry). Accurate to
/// ~0.5% for distances up to ~1000 km, which is plenty for a
/// family map (typically <1000 km between family members).
///
/// Returns `0` if both points are identical.
double haversineMeters({
  required double lat1,
  required double lng1,
  required double lat2,
  required double lng2,
}) {
  // Convert degrees to radians.
  final phi1 = lat1 * math.pi / 180.0;
  final phi2 = lat2 * math.pi / 180.0;
  final dPhi = (lat2 - lat1) * math.pi / 180.0;
  final dLambda = (lng2 - lng1) * math.pi / 180.0;

  final a = math.sin(dPhi / 2) * math.sin(dPhi / 2) +
      math.cos(phi1) *
          math.cos(phi2) *
          math.sin(dLambda / 2) *
          math.sin(dLambda / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return _earthRadiusMeters * c;
}

/// Human-readable distance label.
///
/// Examples:
///   -1.0  → "Live • now"      (negative = same user / live self)
///    0    → "Live • now"      (same position)
///   <50   → "< 50 m away"
///   <1000 → "340 m away"
///   <10000 → "3.4 km away"
///   >=10000 → "12 km away"
///
/// Pass [isSelf] = true when the distance is between the user and
/// their own pin (always shows "Live • now").
String formatDistance({
  required double meters,
  bool isSelf = false,
}) {
  if (isSelf) return 'Live • now';
  if (meters <= 0) return 'Live • now';
  if (meters < 50) return '< 50 m away';
  if (meters < 1000) {
    final m = meters.round();
    return '$m m away';
  }
  // 1-999 km → "X.Y km away" with one decimal.
  // >= 1000 km → "X km away" with no decimal.
  final km = meters / 1000.0;
  if (km < 1000) {
    return '${km.toStringAsFixed(1)} km away';
  }
  return '${km.round()} km away';
}

/// Convenience: compute + format in one call.
String formatDistanceBetween({
  required double lat1,
  required double lng1,
  required double lat2,
  required double lng2,
  bool isSelf = false,
}) {
  if (isSelf) return 'Live • now';
  final m = haversineMeters(
    lat1: lat1,
    lng1: lng1,
    lat2: lat2,
    lng2: lng2,
  );
  return formatDistance(meters: m, isSelf: isSelf);
}

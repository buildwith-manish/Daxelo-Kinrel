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

// ═══════════════════════════════════════════════════════════════════════
// MemberStatus — derived from GPS speed (meters per second)
// ═══════════════════════════════════════════════════════════════════════
//
// Used by:
//   • LiveLocationNotifier.viewerStatus — the current user's own status,
//     derived from their GPS capture's `position.speed` field.
//   • The FamilyMapScreen's adaptive broadcast rate — stationary users
//     broadcast every 30s (saves battery), walking every 10s, driving
//     every 3s (high-frequency for live tracking during transit).
//   • The FAB icon overlay — shows a small car icon when driving.
//   • The viewer's own pin badge — adds "Driving" / "Walking" /
//     "Stationary" label next to the tier label.
//
// NOTE: only the VIEWER's status is tracked (not other members').
// To track other members' status, we'd need to extend the broadcast
// payload format to include speedMps — that's a follow-up, not part
// of this one-shot batch.

/// Speed-derived status for the current user (viewer).
enum MemberStatus {
  /// Speed < 1.4 m/s (~5 km/h) — sitting, standing, sleeping.
  stationary,

  /// Speed 1.4–7 m/s (~5–25 km/h) — walking, running, cycling.
  walking,

  /// Speed ≥ 7 m/s (~25 km/h) — driving, train, fast transit.
  driving,
}

/// Speed thresholds in meters per second.
const double _walkingSpeedThreshold = 1.4; // ~5 km/h
const double _drivingSpeedThreshold = 7.0; // ~25 km/h

/// Derive the viewer's [MemberStatus] from their last GPS `position.speed`
/// (in meters per second).
///
/// `speed` is null on platforms that don't expose it (or when GPS hasn't
/// yet computed it). Returns [MemberStatus.stationary] in that case —
/// safe default, prevents battery drain.
MemberStatus statusFromSpeed(double? speedMps) {
  if (speedMps == null || speedMps < 0) return MemberStatus.stationary;
  if (speedMps >= _drivingSpeedThreshold) return MemberStatus.driving;
  if (speedMps >= _walkingSpeedThreshold) return MemberStatus.walking;
  return MemberStatus.stationary;
}

/// Recommended broadcast interval for a given status.
///
///   • stationary → 30s  (saves ~80% battery vs. 5s default)
///   • walking    → 10s
///   • driving    → 3s   (high-frequency for live transit tracking)
Duration broadcastIntervalForStatus(MemberStatus status) {
  switch (status) {
    case MemberStatus.stationary:
      return const Duration(seconds: 30);
    case MemberStatus.walking:
      return const Duration(seconds: 10);
    case MemberStatus.driving:
      return const Duration(seconds: 3);
  }
}

/// Human-readable label for a status.
String statusLabel(MemberStatus status) {
  switch (status) {
    case MemberStatus.stationary:
      return 'Stationary';
    case MemberStatus.walking:
      return 'Walking';
    case MemberStatus.driving:
      return 'Driving';
  }
}

/// True iff `previous` and `current` distances straddle the [threshold]
/// in the "approaching" direction (was far, now close). Used by the
/// proximity-alert logic to fire a local notification when a family
/// member crosses into the user's 500m radius.
///
///   previous=600m, current=400m, threshold=500m → true (just crossed in)
///   previous=400m, current=300m, threshold=500m → false (already inside)
///   previous=400m, current=600m, threshold=500m → false (leaving)
///   previous=null, current=400m, threshold=500m → true (first seen + inside)
bool proximityEnteredThreshold({
  required double? previousMeters,
  required double currentMeters,
  required double threshold,
}) {
  if (currentMeters >= threshold) return false;
  if (previousMeters == null) return true; // first time + inside
  return previousMeters >= threshold;
}

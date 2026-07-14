import 'dart:ui';

/// Computes a deterministic offset for a fallback pin so that multiple
/// members in the same city don't overlap at the exact same point.
///
/// The offset is derived from the personId (not from Random), so it is
/// stable across rebuilds. The offset stays within [maxOffsetDegrees]
/// of the original coordinate.
///
/// [personId] — the person's unique ID (determines the offset direction + magnitude)
/// [maxOffsetDegrees] — maximum offset in degrees (default 0.01 ≈ 1.1 km)
///
/// Returns an (latOffset, lngOffset) tuple.
({double lat, double lng}) deterministicSpreadOffset(
  String personId, {
  double maxOffsetDegrees = 0.01,
}) {
  // Simple deterministic hash: sum of char codes.
  var hash = 0;
  for (final c in personId.codeUnits) {
    hash = (hash * 31 + c) & 0x7FFFFFFF;
  }
  // Use two different "random" values derived from the hash.
  final r1 = (hash % 1000) / 1000.0;        // 0.0..1.0
  final r2 = ((hash ~/ 1000) % 1000) / 1000.0; // 0.0..1.0
  // Map to -1..1 range.
  final magnitude = r2 * maxOffsetDegrees; // 0..maxOffset
  return (
    lat: magnitude * 0.7 * (r1 > 0.5 ? 1 : -1),  // lat spread (smaller)
    lng: magnitude * (r2 > 0.5 ? 1 : -1),         // lng spread
  );
}

/// Applies the deterministic spread to a coordinate.
Offset applyDeterministicSpread(
  String personId,
  double lat,
  double lng, {
  double maxOffsetDegrees = 0.01,
}) {
  final offset = deterministicSpreadOffset(personId, maxOffsetDegrees: maxOffsetDegrees);
  return Offset(lng + offset.lng, lat + offset.lat);
}

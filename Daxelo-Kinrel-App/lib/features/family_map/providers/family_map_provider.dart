// lib/features/family_map/providers/family_map_provider.dart
//
// DAXELO KINREL — Family Map Provider
//
// Watches family members and resolves their cities to (lat, lng)
// coordinates using the bundled kCityCoordinates lookup table.
// Produces a list of MapPin objects for map display, plus a count
// of members whose cities could not be resolved (unpinned).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/family/family_provider.dart';
import '../data/city_coordinates.dart';

// ═══════════════════════════════════════════════════════════════════════
// MAP PIN MODEL
// ═══════════════════════════════════════════════════════════════════════

/// Represents a single family member pinned on the map.
class MapPin {
  const MapPin({
    required this.personId,
    required this.name,
    required this.city,
    required this.photoUrl,
    required this.lat,
    required this.lng,
  });

  /// Unique ID of the person.
  final String personId;

  /// Display name of the person.
  final String name;

  /// City string as stored in the person record.
  final String city;

  /// URL of the person's photo (may be null/empty).
  final String? photoUrl;

  /// Resolved latitude.
  final double lat;

  /// Resolved longitude.
  final double lng;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MapPin &&
          runtimeType == other.runtimeType &&
          personId == other.personId;

  @override
  int get hashCode => personId.hashCode;
}

// ═══════════════════════════════════════════════════════════════════════
// MAP RESULT
// ═══════════════════════════════════════════════════════════════════════

/// Result of resolving family members to map pins.
class FamilyMapResult {
  const FamilyMapResult({
    required this.pins,
    required this.unpinnedMembers,
    required this.unpinnedCount,
  });

  /// Members that were resolved to coordinates.
  final List<MapPin> pins;

  /// Members whose cities could not be resolved.
  final List<UnpinnedMember> unpinnedMembers;

  /// Convenience: count of unpinned members.
  final int unpinnedCount;

  /// Number of distinct cities among pinned members.
  int get distinctCityCount =>
      pins.map((p) => p.city.toLowerCase()).toSet().length;
}

/// A member whose city could not be resolved to coordinates.
class UnpinnedMember {
  const UnpinnedMember({
    required this.personId,
    required this.name,
    required this.city,
    this.photoUrl,
  });

  final String personId;
  final String name;
  final String city;
  final String? photoUrl;
}

// ═══════════════════════════════════════════════════════════════════════
// FAMILY MAP PROVIDER
// ═══════════════════════════════════════════════════════════════════════

/// Watches the first family from [familyListProvider] and resolves
/// all its members to [MapPin] objects using [kCityCoordinates].
///
/// Returns a [FamilyMapResult] containing:
/// - [pins]: Members with resolved coordinates
/// - [unpinnedMembers]: Members without resolvable cities
/// - [unpinnedCount]: Count of unresolved members
final familyMapProvider =
    FutureProvider<FamilyMapResult>((ref) async {
  // Get the first family from the user's family list
  final familiesAsync = ref.watch(familyListProvider);
  final families = familiesAsync.valueOrNull;

  if (families == null || families.isEmpty) {
    return const FamilyMapResult(
      pins: [],
      unpinnedMembers: [],
      unpinnedCount: 0,
    );
  }

  final firstFamily = families.first;
  final familyId = firstFamily.id;

  // Watch the members of that family
  final membersAsync = ref.watch(familyMembersProvider(familyId));
  final members = membersAsync.valueOrNull;

  if (members == null || members.isEmpty) {
    return const FamilyMapResult(
      pins: [],
      unpinnedMembers: [],
      unpinnedCount: 0,
    );
  }

  final pins = <MapPin>[];
  final unpinned = <UnpinnedMember>[];

  for (final person in members) {
    final city = person.city;
    if (city == null || city.trim().isEmpty) {
      unpinned.add(UnpinnedMember(
        personId: person.id,
        name: person.name,
        city: city ?? '',
        photoUrl: person.photoUrl,
      ));
      continue;
    }

    final key = city.trim().toLowerCase();
    final coords = kCityCoordinates[key];

    if (coords != null) {
      final (lat, lng) = coords;
      pins.add(MapPin(
        personId: person.id,
        name: person.name,
        city: city.trim(),
        photoUrl: person.photoUrl,
        lat: lat,
        lng: lng,
      ));
    } else {
      unpinned.add(UnpinnedMember(
        personId: person.id,
        name: person.name,
        city: city.trim(),
        photoUrl: person.photoUrl,
      ));
    }
  }

  return FamilyMapResult(
    pins: pins,
    unpinnedMembers: unpinned,
    unpinnedCount: unpinned.length,
  );
});

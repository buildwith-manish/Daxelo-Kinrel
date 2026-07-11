// lib/features/family_map/providers/family_map_provider.dart
//
// DAXELO KINREL — Family Map Provider
//
// Watches family members and resolves their cities to (lat, lng)
// coordinates using the bundled kCityCoordinates lookup table.
// Produces a list of MapPin objects for map display, plus a count
// of members whose cities could not be resolved (unpinned).
// Also resolves relationship edges between pinned members for
// the graph overlay that draws curved connecting lines.
//
// Three-tier location merge (§4.5 of the map spec):
//   1. Live broadcast position (if received within 2 min) — freshest
//   2. Last-known MemberLocation row (from live_location_provider)
//   3. City-fallback coordinate (kCityCoordinates lookup) — default

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/family/family_provider.dart';
import '../data/city_coordinates.dart';
import 'live_location_provider.dart';

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
    this.isSelf = false,
    this.locationTier = LocationTier.cityFallback,
    this.isSharing = false,
    this.updatedAt,
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

  /// Whether this pin is the current user's claimed Person node.
  final bool isSelf;

  /// How fresh the location data is — drives pin visual treatment.
  final LocationTier locationTier;

  /// Whether this member has location sharing enabled.
  final bool isSharing;

  /// Timestamp of the last location update (UTC), if any.
  final DateTime? updatedAt;

  /// Whether this pin has a live position (within 2 minutes).
  bool get isLive => locationTier == LocationTier.live;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MapPin &&
          runtimeType == other.runtimeType &&
          personId == other.personId;

  @override
  int get hashCode => personId.hashCode;

  MapPin copyWith({
    double? lat,
    double? lng,
    bool? isSelf,
    LocationTier? locationTier,
    bool? isSharing,
    DateTime? updatedAt,
  }) =>
      MapPin(
        personId: personId,
        name: name,
        city: city,
        photoUrl: photoUrl,
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        isSelf: isSelf ?? this.isSelf,
        locationTier: locationTier ?? this.locationTier,
        isSharing: isSharing ?? this.isSharing,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

// ═══════════════════════════════════════════════════════════════════════
// MAP RELATIONSHIP EDGE MODEL
// ═══════════════════════════════════════════════════════════════════════

/// Represents a real relationship edge between two pinned map members.
class MapRelationshipEdge {
  const MapRelationshipEdge({
    required this.pinA,
    required this.pinB,
    required this.relationshipKey,
  });

  /// The first member in this relationship.
  final MapPin pinA;

  /// The second member in this relationship.
  final MapPin pinB;

  /// The raw relationship key (e.g. 'father', 'sister', 'spouse').
  /// Used to resolve the full kinship term via GraphService at tap time.
  final String relationshipKey;
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
    this.edges = const [],
    this.familyId = '',
  });

  /// Members that were resolved to coordinates.
  final List<MapPin> pins;

  /// Members whose cities could not be resolved.
  final List<UnpinnedMember> unpinnedMembers;

  /// Convenience: count of unpinned members.
  final int unpinnedCount;

  /// Relationship edges between pinned members only.
  final List<MapRelationshipEdge> edges;

  /// Family ID needed by GraphService at tap time for path resolution.
  final String familyId;

  /// Number of distinct cities among pinned members.
  int get distinctCityCount =>
      pins.map((p) => p.city.toLowerCase()).toSet().length;

  /// Count of members currently in the live (0-2 min) or recent (2-15 min)
  /// tiers — i.e. genuinely "live" or freshly updated, not stale.
  int get liveCount =>
      pins.where((p) => p.isSharing && p.locationTier != LocationTier.cityFallback).length;
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
/// - [edges]: Relationship edges between pinned members
/// - [familyId]: Family ID for graph resolution at tap time
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
      edges: [],
      familyId: '',
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
      edges: [],
      familyId: '',
    );
  }

  final pins = <MapPin>[];
  final unpinned = <UnpinnedMember>[];

  // ── Three-tier location merge (§4.5) ──────────────────────────────
  // Watch live locations (broadcast + last-known) for this family.
  // Live broadcast position (if fresh) overrides city-fallback.
  final liveState = ref.watch(liveLocationProvider);
  final liveLocations = liveState.locations;

  for (final person in members) {
    final city = person.city;

    // Check for a live or last-known location for this person.
    final live = liveLocations[person.id];
    if (live != null) {
      // Tier 1 or 2: use the live/last-known position.
      pins.add(MapPin(
        personId: person.id,
        name: person.name,
        city: city?.trim() ?? 'Live location',
        photoUrl: person.photoUrl,
        lat: live.lat,
        lng: live.lng,
        isSelf: false, // set below after we check currentUser
        locationTier: computeTier(live.updatedAt),
        isSharing: live.isSharing,
        updatedAt: live.updatedAt,
      ));
      continue;
    }

    // Tier 3: city fallback.
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
        locationTier: LocationTier.cityFallback,
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

  // ── Resolve relationship edges between pinned members ─────────────
  List<MapRelationshipEdge> edges = [];
  try {
    final detail = await ref.read(familyDetailProvider(familyId).future);
    if (detail != null) {
      final pinnedIds = pins.map((p) => p.personId).toSet();
      final pinById = {for (final p in pins) p.personId: p};
      final seenKeys = <String>{};

      for (final rel in detail.relationships) {
        if (!rel.isActive) continue;
        if (!pinnedIds.contains(rel.fromPersonId) ||
            !pinnedIds.contains(rel.toPersonId)) {
          continue;
        }

        // Deduplicate: canonical key is the sorted pair of person IDs
        final pair = [rel.fromPersonId, rel.toPersonId]..sort();
        final canonicalKey = '${pair[0]}-${pair[1]}';
        if (seenKeys.contains(canonicalKey)) continue;
        seenKeys.add(canonicalKey);

        edges.add(MapRelationshipEdge(
          pinA: pinById[rel.fromPersonId]!,
          pinB: pinById[rel.toPersonId]!,
          relationshipKey: rel.relationshipKey,
        ));
      }
    }
  } catch (e) {
    // Never let relationship loading failure break the map pins
    debugPrint('⚠️ familyMapProvider: relationship edge resolution failed: $e');
    edges = [];
  }

  return FamilyMapResult(
    pins: pins,
    unpinnedMembers: unpinned,
    unpinnedCount: unpinned.length,
    edges: edges,
    familyId: familyId,
  );
});

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

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/services/supabase_service.dart' show supabaseProvider;
import '../config/map_visual_constants.dart';
import '../data/city_coordinates.dart';
import '../data/map_data_validator.dart';
import '../data/map_location_resolver.dart';
import '../data/map_location_source.dart';
import '../data/place_models.dart';

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
    this.placeType,
    this.placeId,
    this.locationSource,
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

  /// P10.1 — Optional semantic place type. Null when the pin is a
  /// city-only pin (no linked Place row). When present, drives the
  /// building lighting in P10.2.
  final PlaceType? placeType;

  /// P10.1 — Optional Place row ID this pin is linked to.
  final String? placeId;

  /// Source of this pin's coordinates (live GPS, exact linked place,
  /// saved member location, locality, or city centroid). Null only
  /// when the pin was constructed without going through
  /// [resolvePrimaryMapLocation] (legacy callers).
  ///
  /// Drives household clustering in [computeHouseholds]: city-centroid
  /// pins (and locality pins) must NOT cluster into households — they
  /// render independently with a deterministic spread so visually
  /// overlapping pins don't collapse into a false "household".
  final MapLocationSource? locationSource;

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
    this.places = const [],
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

  /// P10.1 — Family places (homes, birthplaces, memorials, etc.).
  /// Used by P10.2 (family buildings) and P10.7 (timeline filtering).
  /// Empty list when the family has no places or when offline cache
  /// is empty (degrades gracefully — Rule 15).
  final List<FamilyPlace> places;

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
// P10.4 — Household clustering
// ═══════════════════════════════════════════════════════════════════════

/// A household is a group of pins that share roughly the same coordinates
/// (within `MapVisualConstants.householdEpsilon` degrees ≈ 111 meters).
/// Single-member households are returned as well — the screen decides
/// whether to render them as a cluster or a single marker.
@immutable
class Household {
  const Household({
    required this.id,
    required this.members,
    required this.lat,
    required this.lng,
  });

  /// Stable ID — derived from the rounded coordinates.
  final String id;

  /// Pins in this household. Always non-empty.
  final List<MapPin> members;

  /// Representative latitude (first member's lat).
  final double lat;

  /// Representative longitude.
  final double lng;

  /// True when there is more than one member.
  bool get isMulti => members.length > 1;

  /// Number of members.
  int get size => members.length;
}

/// Groups pins into households by shared coordinates.
///
/// Two pins belong to the same household when their lat/lng, divided by
/// [MapVisualConstants.householdEpsilon] and rounded, produce the same
/// integer bucket. This is a fast O(N) grid-based clustering that
/// avoids Haversine distance calculations.
///
/// City-centroid fallback pins (and locality pins) are SKIPPED — only
/// pins with exact coordinates ([MapLocationSource.exactPlace],
/// [MapLocationSource.savedLocation], [MapLocationSource.live]) can
/// form households. City-centroid pins render independently with a
/// deterministic spread so visually overlapping pins don't collapse
/// into a false "household".
///
/// Tunable: change `householdEpsilon` in MapVisualConstants (Rule 14, 16).
List<Household> computeHouseholds(List<MapPin> pins) {
  final epsilon = MapVisualConstants.householdEpsilon;
  final groups = <String, List<MapPin>>{};
  for (final pin in pins) {
    // City-centroid fallback pins must NOT cluster into households.
    // Only pins with exact coordinates (exactPlace, savedLocation, live)
    // can form households — others render independently with a
    // deterministic spread so visually overlapping pins don't collapse
    // into a false "household".
    if (pin.locationSource != null && !pin.locationSource!.canCluster) {
      continue;
    }
    final key =
        '${(pin.lat / epsilon).round()}_${(pin.lng / epsilon).round()}';
    groups.putIfAbsent(key, () => <MapPin>[]).add(pin);
  }
  return groups.entries
      .map((e) => Household(
            id: e.key,
            members: e.value,
            lat: e.value.first.lat,
            lng: e.value.first.lng,
          ))
      .toList(growable: false);
}

// ═══════════════════════════════════════════════════════════════════════
// P10.1 — Family Place fetcher
// ═══════════════════════════════════════════════════════════════════════

/// Fetches family places from Supabase (Place table — P10.1 migration).
///
/// Returns an empty list on any failure so the map continues to render
/// without places (Rule 15 — graceful offline / network-failure handling).
/// Mirrors the existing RLS-scoped family data pattern.
Future<List<FamilyPlace>> _fetchFamilyPlaces(
  SupabaseClient? client,
  String familyId,
) async {
  if (client == null) return const [];
  try {
    final rows = await client
        .from('Place')
        .select()
        .eq('familyId', familyId)
        .order('createdAt', ascending: false);
    if (rows.isEmpty) return const [];
    return rows
        .map<FamilyPlace>(
            (row) => FamilyPlace.fromJson(row as Map<String, dynamic>))
        .toList(growable: false);
  } catch (e) {
    debugPrint('⚠️ familyMapProvider: place fetch failed: $e');
    return const [];
  }
}

// ═══════════════════════════════════════════════════════════════════════
// FAMILY MAP PROVIDER
// ═══════════════════════════════════════════════════════════════════════

/// Resolves all members of the family identified by [familyId] to
/// [MapPin] objects using [kCityCoordinates] and
/// [resolvePrimaryMapLocation].
///
/// Returns a [FamilyMapResult] containing:
/// - [pins]: Members with resolved coordinates
/// - [unpinnedMembers]: Members without resolvable cities
/// - [unpinnedCount]: Count of unresolved members
/// - [edges]: Relationship edges between pinned members
/// - [familyId]: Family ID for graph resolution at tap time
///
/// §7 — PROGRESSIVE DATA DELIVERY NOTE
/// -----------------------------------
/// This provider currently BLOCKS on ALL data before returning: it
/// awaits (a) the family members stream, (b) the family detail
/// stream (for relationship edges), and (c) the family places fetch
/// in parallel, then merges them into a single [FamilyMapResult].
/// The screen therefore cannot show pins before places/relationships
/// complete.
///
/// The screen-side mitigation (in `family_map_screen.dart`) is to
/// render the map SHELL immediately with an empty
/// [FamilyMapResult] while this provider is still loading — pins,
/// edges, and places then appear as overlays when this provider
/// resolves. See the `mapAsync.when(loading: ...)` branch in
/// `FamilyMapScreen.build`.
///
/// A FUTURE improvement would split this into separate providers
/// (e.g. `familyPinsProvider`, `familyEdgesProvider`,
/// `familyPlacesProvider`) so pins can render before edges/places
/// complete, without waiting on the slowest stream. Keeping the
/// merged provider for now — it works, and the screen-side shell
/// rendering already gives the user a non-blocking experience.
final familyMapProvider =
    FutureProvider.family<FamilyMapResult, String>((ref, familyId) async {
  if (familyId.isEmpty) {
    return const FamilyMapResult(
      pins: [],
      unpinnedMembers: [],
      unpinnedCount: 0,
      edges: [],
      familyId: '',
    );
  }

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

  // P10.1 — Fetch family places in parallel with the existing pin / edge
  // resolution below. RLS ensures only this family's places come back.
  // Rule 15: gracefully degrades to an empty list on network failure.
  final supabaseClient = ref.read(supabaseProvider);
  final placesFuture = _fetchFamilyPlaces(supabaseClient, familyId);

  var pins = <MapPin>[];
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

  // Filter out pins with invalid coordinates (NaN, Infinity, out of
  // range). The city centroid table is curated, but defensive
  // validation ensures a corrupt/edited entry can never produce a
  // broken pin that crashes the map renderer.
  pins = pins.where((p) => isValidCoordinate(p.lat, p.lng)).toList();

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

  // P10.1 — Await the parallel place fetch and merge linked PlaceType into
  // the corresponding MapPin so P10.2 can render per-type building lighting
  // without re-reading the Place list.
  final places = await placesFuture;
  final placeByPersonId = <String, FamilyPlace>{
    for (final p in places)
      if (p.personId != null) p.personId!: p,
  };
  final enrichedPins = pins.map((pin) {
    final linked = placeByPersonId[pin.personId];
    final resolved = resolvePrimaryMapLocation(
      cityLat: pin.lat,
      cityLng: pin.lng,
      linkedPlace: linked,
    );
    if (resolved != null) {
      return MapPin(
        personId: pin.personId,
        name: pin.name,
        city: pin.city,
        photoUrl: pin.photoUrl,
        lat: resolved.lat,
        lng: resolved.lng,
        placeType: linked?.placeType,
        placeId: linked?.id,
        locationSource: resolved.source,
      );
    }
    return pin;
  }).toList(growable: false);

  return FamilyMapResult(
    pins: enrichedPins,
    unpinnedMembers: unpinned,
    unpinnedCount: unpinned.length,
    edges: edges,
    familyId: familyId,
    places: places,
  );
});

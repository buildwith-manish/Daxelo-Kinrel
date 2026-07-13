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
import '../data/city_coordinates.dart';
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

  // P10.1 — Fetch family places in parallel with the existing pin / edge
  // resolution below. RLS ensures only this family's places come back.
  // Rule 15: gracefully degrades to an empty list on network failure.
  final supabaseClient = ref.read(supabaseProvider);
  final placesFuture = _fetchFamilyPlaces(supabaseClient, familyId);

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
    if (linked == null) return pin;
    return MapPin(
      personId: pin.personId,
      name: pin.name,
      city: pin.city,
      photoUrl: pin.photoUrl,
      lat: pin.lat,
      lng: pin.lng,
      placeType: linked.placeType,
      placeId: linked.id,
    );
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

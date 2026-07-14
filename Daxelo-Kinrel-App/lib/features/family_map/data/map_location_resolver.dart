import 'map_location_source.dart';
import 'place_models.dart';

/// The result of resolving a member's map location.
class ResolvedMapLocation {
  const ResolvedMapLocation({
    required this.lat,
    required this.lng,
    required this.source,
  });
  final double lat;
  final double lng;
  final MapLocationSource source;
}

/// Determines which PlaceTypes are valid as a current-location anchor
/// for member pin placement.
bool isCurrentLocationAnchor(PlaceType? placeType) {
  switch (placeType) {
    case PlaceType.currentHome:
      return true;
    case PlaceType.familyBusiness:
      return false; // not a residence
    case PlaceType.school:
    case PlaceType.memorial:
    case PlaceType.wedding:
    case PlaceType.birthplace:
    case PlaceType.ancestralHome:
    case PlaceType.childhoodHome:
    case PlaceType.importantPlace:
    case PlaceType.vacationHome:
    case PlaceType.familyTemple:
    case PlaceType.grandparentsHome:
      return false; // historical/ceremonial/secondary — not current residence
    case null:
      return false;
  }
}

/// Resolves the primary map location for a member.
///
/// Priority:
/// 1. Exact linked FamilyPlace coordinate (if placeType is a current-location anchor)
/// 2. City centroid (fallback)
///
/// Returns null if no location can be resolved.
ResolvedMapLocation? resolvePrimaryMapLocation({
  double? cityLat,
  double? cityLng,
  FamilyPlace? linkedPlace,
}) {
  // Priority 1: Exact place coordinate (if it's a current-location anchor)
  if (linkedPlace != null &&
      isCurrentLocationAnchor(linkedPlace.placeType) &&
      linkedPlace.lat != 0.0 &&
      linkedPlace.lng != 0.0 &&
      linkedPlace.lat >= -90.0 && linkedPlace.lat <= 90.0 &&
      linkedPlace.lng >= -180.0 && linkedPlace.lng <= 180.0) {
    return ResolvedMapLocation(
      lat: linkedPlace.lat,
      lng: linkedPlace.lng,
      source: MapLocationSource.exactPlace,
    );
  }

  // Priority 2: City centroid
  if (cityLat != null && cityLng != null &&
      cityLat >= -90.0 && cityLat <= 90.0 &&
      cityLng >= -180.0 && cityLng <= 180.0) {
    return ResolvedMapLocation(
      lat: cityLat,
      lng: cityLng,
      source: MapLocationSource.cityCentroid,
    );
  }

  return null;
}

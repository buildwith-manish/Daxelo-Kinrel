enum MapLocationSource {
  live, // privacy-authorized live GPS
  exactPlace, // exact linked FamilyPlace coordinate
  savedLocation, // existing saved member/location coordinate
  locality, // locality/neighborhood coordinate
  cityCentroid, // city centroid from kCityCoordinates (lowest confidence)
}

extension MapLocationSourceX on MapLocationSource {
  bool get isHighConfidence =>
      this == MapLocationSource.live || this == MapLocationSource.exactPlace;
  bool get isExact =>
      this == MapLocationSource.live ||
      this == MapLocationSource.exactPlace ||
      this == MapLocationSource.savedLocation;
  bool get canCluster =>
      this == MapLocationSource.exactPlace ||
      this == MapLocationSource.savedLocation ||
      this == MapLocationSource.live;
}

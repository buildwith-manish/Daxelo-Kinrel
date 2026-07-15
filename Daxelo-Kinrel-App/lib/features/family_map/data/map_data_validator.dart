/// Validates a latitude value. Returns true if -90 <= lat <= 90 and not NaN/Infinity.
bool isValidLatitude(double lat) {
  return lat.isFinite && lat >= -90.0 && lat <= 90.0;
}

/// Validates a longitude value. Returns true if -180 <= lng <= 180 and not NaN/Infinity.
bool isValidLongitude(double lng) {
  return lng.isFinite && lng >= -180.0 && lng <= 180.0;
}

/// Validates a coordinate pair.
bool isValidCoordinate(double lat, double lng) {
  return isValidLatitude(lat) && isValidLongitude(lng);
}

/// Validates a person ID (non-empty string).
bool isValidPersonId(String? id) {
  return id != null && id.isNotEmpty;
}

/// Removes self-relationship edges (fromId == toId) from a list.
/// Returns a new list; does not modify the input.
List<({String fromId, String toId, String edgeId, String relationshipKey})>
removeSelfEdges(
  List<({String fromId, String toId, String edgeId, String relationshipKey})>
  edges,
) {
  return edges.where((e) => e.fromId != e.toId).toList();
}

/// Removes duplicate relationship edges (same canonical pair).
/// First occurrence wins.
List<({String fromId, String toId, String edgeId, String relationshipKey})>
removeDuplicateEdges(
  List<({String fromId, String toId, String edgeId, String relationshipKey})>
  edges,
) {
  final seen = <String>{};
  return edges.where((e) {
    final key = e.fromId.compareTo(e.toId) <= 0
        ? '${e.fromId}|${e.toId}'
        : '${e.toId}|${e.fromId}';
    if (seen.contains(key)) return false;
    seen.add(key);
    return true;
  }).toList();
}

/// Filters out relationship edges that reference a person ID not in the valid set.
List<({String fromId, String toId, String edgeId, String relationshipKey})>
removeEdgesWithMissingPins(
  List<({String fromId, String toId, String edgeId, String relationshipKey})>
  edges,
  Set<String> validPersonIds,
) {
  return edges
      .where(
        (e) =>
            validPersonIds.contains(e.fromId) &&
            validPersonIds.contains(e.toId),
      )
      .toList();
}

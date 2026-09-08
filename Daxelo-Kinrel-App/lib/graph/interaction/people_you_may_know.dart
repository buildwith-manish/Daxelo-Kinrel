// lib/graph/interaction/people_you_may_know.dart
//
// DAXELO KINREL — v5.175 "People You May Know" Suggestions
//
// Suggests missing connections based on common-neighbor analysis:
// "You and Raj both know Priya — add Raj?"
//
// Uses the standard PYMK pattern: find persons NOT directly connected
// to the viewer who share ≥2 common neighbors, ranked by count.

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A suggested connection.
class SuggestedConnection {
  final String personId;
  final String personName;
  final String? photoUrl;
  final int commonNeighborCount;
  final List<String> commonNeighborNames;

  const SuggestedConnection({
    required this.personId,
    required this.personName,
    this.photoUrl,
    required this.commonNeighborCount,
    required this.commonNeighborNames,
  });
}

/// Computes "People You May Know" suggestions for the viewer in a family.
///
/// Returns a list of suggested connections ranked by common-neighbor count
/// (descending). Only includes persons NOT already directly connected to
/// the viewer, with at least 2 common neighbors.
List<SuggestedConnection> computePeopleYouMayKnow({
  required String viewerPersonId,
  required List<Map<String, dynamic>> persons,
  required List<Map<String, dynamic>> relationships,
  int maxSuggestions = 10,
}) {
  // Build undirected adjacency.
  final adjacency = <String, Set<String>>{};
  for (final r in relationships) {
    final from = (r['fromPersonId'] ?? '').toString();
    final to = (r['toPersonId'] ?? '').toString();
    if (from.isEmpty || to.isEmpty) continue;
    adjacency.putIfAbsent(from, () => <String>{}).add(to);
    adjacency.putIfAbsent(to, () => <String>{}).add(from);
  }

  final viewerNeighbors = adjacency[viewerPersonId] ?? <String>{};
  if (viewerNeighbors.isEmpty) return const [];

  // For each person NOT directly connected to the viewer, count common neighbors.
  final suggestions = <SuggestedConnection>[];
  final personNameMap = <String, String>{};
  final personPhotoMap = <String, String?>{};
  for (final p in persons) {
    final id = (p['id'] ?? '').toString();
    if (id.isEmpty) continue;
    personNameMap[id] = (p['name'] ?? 'Unknown').toString();
    personPhotoMap[id] = p['photoUrl'] as String?;
  }

  for (final personId in adjacency.keys) {
    // Skip the viewer themselves.
    if (personId == viewerPersonId) continue;
    // Skip if already directly connected.
    if (viewerNeighbors.contains(personId)) continue;

    final personNeighbors = adjacency[personId] ?? <String>{};
    final common = viewerNeighbors.intersection(personNeighbors);

    if (common.length >= 2) {
      final commonNames = common
          .map((id) => personNameMap[id] ?? 'Unknown')
          .take(3)
          .toList();
      suggestions.add(SuggestedConnection(
        personId: personId,
        personName: personNameMap[personId] ?? 'Unknown',
        photoUrl: personPhotoMap[personId],
        commonNeighborCount: common.length,
        commonNeighborNames: commonNames,
      ));
    }
  }

  // Sort by common-neighbor count (descending).
  suggestions.sort((a, b) => b.commonNeighborCount.compareTo(a.commonNeighborCount));
  return suggestions.take(maxSuggestions).toList();
}

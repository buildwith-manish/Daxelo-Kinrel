// lib/graph/widgets/engine/event_helpers.dart
// P0.4/P5.2: Extracted from family_graph_engine_view.dart to keep the
// main file under 1500 lines.
//
// Contains the P3.3 (birthday glow), P3.4 (memorial candle), and P3.7
// (on-this-day) helper methods that compute per-person event state
// from the graph RPC data.

part of '../family_graph_engine_view.dart';

/// Mixin containing per-person event helpers for _FamilyGraphEngineViewState.
/// Extracted to keep the main file under 1500 lines (P0.4 decomposition).
extension _EventHelpers on _FamilyGraphEngineViewState {
  /// Returns true if [p] has a birthday within 7 days. Reads
  /// `p['dateOfBirth']` (added to the graph RPC by the P3.3 migration).
  bool isNearBirthdayForPerson(Map<String, dynamic> p) {
    final dobStr = p['dateOfBirth'] as String?;
    if (dobStr == null || dobStr.isEmpty) return false;
    final dob = DateTime.tryParse(dobStr);
    if (dob == null) return false;
    return isNearBirthday(dob);
  }

  /// Returns days until the next birthday for [p], or null if
  /// `dateOfBirth` is missing or invalid.
  int? daysUntilBirthdayForPerson(Map<String, dynamic> p) {
    final dobStr = p['dateOfBirth'] as String?;
    if (dobStr == null || dobStr.isEmpty) return null;
    final dob = DateTime.tryParse(dobStr);
    if (dob == null) return null;
    return daysUntilBirthday(dob);
  }

  /// P3.4: Returns true if the person is deceased AND the death was
  /// within the last 30 days. The memorial candle is brighter (alpha
  /// 0.8-1.0) for the first 30 days, then dims to 0.6-0.9.
  ///
  /// The graph RPC doesn't currently return dateOfDeath, so this
  /// helper returns false (standard candle) until the RPC is extended.
  bool isRecentlyDeceasedForPerson(Map<String, dynamic> p) {
    final isDeceased = (p['isDeceased'] as bool?) ?? false;
    if (!isDeceased) return false;
    final dodStr = p['dateOfDeath'] as String?;
    if (dodStr == null || dodStr.isEmpty) return false;
    final dod = DateTime.tryParse(dodStr);
    if (dod == null) return false;
    final daysSinceDeath = DateTime.now().difference(dod).inDays;
    return daysSinceDeath >= 0 && daysSinceDeath <= 30;
  }

  /// P3.7: Returns an "on this day" event for [p] if today is the person's
  /// birthday OR wedding anniversary. Returns null otherwise.
  ///
  /// Computed from existing person data (dateOfBirth / anniversaryDate)
  /// so no extra API call is needed — the badge appears within 1 render
  /// frame of graph load (per spec P3.7 1-frame requirement).
  OnThisDayEvent? onThisDayEventForPerson(Map<String, dynamic> p) {
    final personId = p['id']?.toString();
    if (personId == null || personId.isEmpty) return null;
    final now = DateTime.now();

    final dobStr = p['dateOfBirth'] as String?;
    if (dobStr != null && dobStr.isNotEmpty) {
      final dob = DateTime.tryParse(dobStr);
      if (dob != null && dob.month == now.month && dob.day == now.day) {
        return OnThisDayEvent(
          personId: personId,
          type: OnThisDayEventType.birthday,
          year: dob.year,
          title: 'Birthday today',
        );
      }
    }

    final annivStr = p['anniversaryDate'] as String?;
    if (annivStr != null && annivStr.isNotEmpty) {
      final anniv = DateTime.tryParse(annivStr);
      if (anniv != null && anniv.month == now.month && anniv.day == now.day) {
        return OnThisDayEvent(
          personId: personId,
          type: OnThisDayEventType.anniversary,
          year: anniv.year,
          title: 'Wedding Anniversary',
        );
      }
    }
    return null;
  }

  /// v5.114: Tap-to-expand — if the tapped person is on the outermost
  /// visible ring, expand their immediate neighborhood into the visible
  /// set.
  ///
  /// This is INCREMENTAL: only the tapped person's direct neighbors are
  /// added to the visible set. The rest of the graph is unchanged.
  ///
  /// "Outermost ring" = the person is visible but has NOT been expanded
  /// yet (their neighbors haven't been revealed).
  void _maybeExpandFromPerson(String personId, FlatGraphResult flat) {
    final proximityState = ref.read(proximityGraphProvider);
    if (!proximityState.isInitialized) return;
    if (!proximityState.visibleIds.contains(personId)) return;
    // Already expanded — no-op.
    if (proximityState.expandedPersonIds.contains(personId)) return;

    // Build adjacency from the flat graph data.
    final allEdges = <({String fromId, String toId, String edgeId, String relationshipKey})>[
      for (final r in flat.relationships)
        (
          fromId: r['fromPersonId'] as String? ?? '',
          toId: r['toPersonId'] as String? ?? '',
          edgeId: r['id'] as String? ?? '',
          relationshipKey: r['relationshipKey'] as String? ?? '',
        ),
    ];
    final adjacency = buildAdjacency(allEdges);
    final allPersonIds = <String>{
      for (final p in flat.persons) p['id'] as String? ?? '',
    };

    ref.read(proximityGraphProvider.notifier).expandFromPerson(
          personId: personId,
          adjacency: adjacency,
          allPersons: allPersonIds,
        );

    // The layout provider watches proximityGraphProvider, so it will
    // automatically recompute with the expanded visible set.
  }
}

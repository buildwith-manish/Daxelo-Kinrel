// lib/features/family_journey/providers/journey_provider.dart
//
// P7.3 — Family Journey Replay provider.
// Filters the graph by year — who was alive, who had valid relationships.
//
// P10.7 — Extended for the Map Timeline. Adds filterMapPins + filterMapPlaces
// (Rule 3 — extend the existing JourneyProvider, do NOT create
// MapJourneyProvider).

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../family_map/data/place_models.dart';
import '../../family_map/providers/family_map_provider.dart';

/// State of the journey replay.
@immutable
class JourneyState {
  const JourneyState({
    this.selectedYear = 2026,
    this.minYear = 1900,
    this.maxYear = 2026,
    this.isPlaying = false,
    this.playbackSpeedYearsPerSecond = 0.5,
    this.alivePersonIds = const {},
    this.memoryMarkers = const {},
  });

  final int selectedYear;
  final int minYear;
  final int maxYear;
  final bool isPlaying;
  final double playbackSpeedYearsPerSecond;
  final Set<String> alivePersonIds;
  final Map<int, String> memoryMarkers;

  JourneyState copyWith({
    int? selectedYear,
    int? minYear,
    int? maxYear,
    bool? isPlaying,
    double? playbackSpeedYearsPerSecond,
    Set<String>? alivePersonIds,
    Map<int, String>? memoryMarkers,
  }) {
    return JourneyState(
      selectedYear: selectedYear ?? this.selectedYear,
      minYear: minYear ?? this.minYear,
      maxYear: maxYear ?? this.maxYear,
      isPlaying: isPlaying ?? this.isPlaying,
      playbackSpeedYearsPerSecond:
          playbackSpeedYearsPerSecond ?? this.playbackSpeedYearsPerSecond,
      alivePersonIds: alivePersonIds ?? this.alivePersonIds,
      memoryMarkers: memoryMarkers ?? this.memoryMarkers,
    );
  }
}

/// Controller for the journey replay.
class JourneyController extends StateNotifier<JourneyState> {
  JourneyController() : super(JourneyState(maxYear: DateTime.now().year, selectedYear: DateTime.now().year));

  /// Sets the selected year.
  void setYear(int year) {
    state = state.copyWith(selectedYear: year.clamp(state.minYear, state.maxYear));
  }

  /// Starts auto-advance playback.
  void play() => state = state.copyWith(isPlaying: true);

  /// Pauses playback.
  void pause() => state = state.copyWith(isPlaying: false);

  /// Sets the year range.
  void setYearRange(int min, int max) {
    state = state.copyWith(minYear: min, maxYear: max);
  }

  /// Sets which persons were alive at the selected year.
  void setAlivePersons(Set<String> ids) {
    state = state.copyWith(alivePersonIds: ids);
  }

  /// Sets memory markers (year → memory description).
  void setMemoryMarkers(Map<int, String> markers) {
    state = state.copyWith(memoryMarkers: markers);
  }

  // ── P10.7 — Map Timeline filters ──────────────────────────────────────
  //
  // Rule 3: extend JourneyProvider, do NOT create MapJourneyProvider.
  // The same provider drives both the graph timeline (P7.3) and the map
  // timeline (P10.7) so the two screens stay in sync.

  /// Filters map pins to those who were alive at the currently selected year.
  ///
  /// Pins whose linked person has no dateOfBirth are always returned
  /// (we can't filter them — see wasAliveAt). Pins whose linked person
  /// was deceased before the selected year are excluded.
  ///
  /// Note: this method takes the pins list as input (rather than reading
  /// a provider) so it's pure and testable. The screen calls it on
  /// every state change with the latest pins from familyMapProvider.
  List<MapPin> filterMapPins(
    List<MapPin> allPins, {
    Map<String, DateTime>? dateOfBirthByPersonId,
    Map<String, DateTime>? dateOfDeathByPersonId,
  }) {
    final year = state.selectedYear;
    return allPins.where((pin) {
      final dob = dateOfBirthByPersonId?[pin.personId];
      final dod = dateOfDeathByPersonId?[pin.personId];
      return wasAliveAt(year: year, dateOfBirth: dob, dateOfDeath: dod);
    }).toList(growable: false);
  }

  /// Filters family places to those valid at the currently selected year.
  /// Uses Place.validFrom / validTo (P10.1) — null bounds mean
  /// "unbounded" on that side.
  List<FamilyPlace> filterMapPlaces(List<FamilyPlace> allPlaces) {
    final viewingDate = DateTime(state.selectedYear, 12, 31, 23, 59, 59);
    return allPlaces
        .where((place) => place.isValidAt(viewingDate))
        .toList(growable: false);
  }
}

final journeyProvider =
    StateNotifierProvider<JourneyController, JourneyState>(
  (ref) => JourneyController(),
);

/// Checks if a person was alive at [year].
/// Returns true if the person was born before or during [year] and
/// (if deceased) died after [year].
bool wasAliveAt({
  required int year,
  DateTime? dateOfBirth,
  DateTime? dateOfDeath,
}) {
  if (dateOfBirth == null) return true; // unknown birth = assume alive
  if (dateOfBirth.year > year) return false; // not born yet
  if (dateOfDeath != null && dateOfDeath.year < year) return false; // already deceased
  return true;
}
